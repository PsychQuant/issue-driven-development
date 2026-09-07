# Actionability Gate

> The contract that answers **「這個 issue 現在可不可以動？」** — how the routing tier is extracted from the `### Complexity` Diagnosis field, how deferral is detected, where parked state lives, and the three-signal gate that `idd-list` / `idd-all` / `idd-implement` / `idd-plan` all consume. This file is the single source of truth; the four skills cite it and MUST NOT restate the rules in their own words.
>
> **Source**: `add-actionability-gate` Spectra change (capability `actionability-gate`). Origin: issue-driven-development#298 → #316, surfaced from real dogfooding (2026-08-10 backlog routing). **Round 2** (2026-08-15): `/idd-verify --pr 318` falsified round 1's closed value domain against the real diagnosis corpus; the extraction rule below is the corrected one, validated on all 159 diagnoses in this repository. **Round 3** (2026-09-07): the round-2 verify found the same failure shape on the third signal — the `### Blocking` reader had been written against an unvalidated producer assumption — and found that filing not-yet-diagnosed issues under *Parked* misdescribed 11 of 14 open issues. Both are corrected below, each with its own frozen corpus or live-backlog measurement.

## The incident this exists to prevent

On 2026-08-10 a real 22-issue backlog was routed by `/idd-list`. Of the 11 diagnosed issues, **8 parked/deferred/blocked ones were reported as "Actionable now"**. Two of them (#131, #200) carried a defer ruling the user had personally made on 2026-07-07 — following the routing would have re-opened work the user had decided to park.

The failure was **silent**. The table was syntactically correct, well-formatted, and carried no warning.

## Root cause, in two layers

### 1. Mutable state in an immutable artifact

`### Complexity` lives in a Diagnosis comment, and Diagnosis comments are **append-only** (see [`rules/append-vs-modify.md`](../rules/append-vs-modify.md)). But "is this issue parked?" is **mutable** — a trigger firing should un-park it. Writing deferral qualifiers (`Simple when triggered`, `**Spectra when triggered**(Layer 2: …)`) into a frozen field created a value that could never be corrected in place, and every consumer's parser assumed the field carried one kind of information. Three consumers each invented an incompatible narrowing:

| Consumer | private narrowing | result on `Simple when triggered` |
|---|---|---|
| `idd-list` | `([A-Za-z-]+)` | silently truncated to `Simple` → routed a parked issue to `/idd-implement` |
| `idd-all` | `(.+?)` + via-split | non-tier string; matched no dispatch row **and** was not `UNKNOWN` |
| `idd-implement` | same | same |

`idd-all`'s `UNKNOWN → abort` safety net structurally could not catch this: it fires only when the regex fails entirely, never when it matches an out-of-domain value.

IDD already knew the right shape: `### Blocking` is mutable, so it lives in the issue **body** and is maintained by `idd-update`. This contract applies the same reasoning to deferral.

> **Correction to the round-1 narrative.** Round 1 claimed #136's Diagnosis comment read bare `Spectra` while its body read `Spectra when triggered (parking lot)`. The "bare `Spectra`" was the truncating regex talking: the comment actually reads `**Spectra**(Layer 2 + Layer 3 if/when triggered):…` — the deferral was hiding inside the parenthetical, exactly where a suffix-only scan would miss it. The two-signals-drift argument still stands (#37, #131, #200), but #136 is evidence for scanning the *whole* value, not for state drift.

### 2. The round-1 fix over-corrected

Round 1 declared a **closed value domain**: the value had to be exactly one of the four tiers, optionally followed by ` via <source>`. That rejected the producer's normal writing style. On the real corpus of **159 diagnoses** in this repository:

| Shape (mutually exclusive, first line of the value) | Count | Share |
|---|---|---|
| bare tier (`Plan`) | 45 | 28.3 % |
| decorated bare tier (`**Plan**`) | 37 | 23.3 % |
| decorated tier + same-line rationale (`**Spectra** — Layer 2（…）`) | 41 | 25.8 % |
| plain tier + same-line rationale (`Spectra（opt-out → 直接 propose）`) | 25 | 15.7 % |
| tier + ` via <source>` (`Plan via hard-gate`) | 1 | 0.6 % |
| deferral vocabulary present | 9 | 5.7 % |
| no `### Complexity` section | 1 | 0.6 % |

71.7 % of values are not a bare tier. Round 1 stripped decoration before matching, so it would still have refused every rationale-bearing value: **66 of 159 (41.5 %)** wrongly withheld — worse than the 29 % misroute rate of the truncating regex it replaced (37 decorated values unmatched + 9 deferral values passed). Both figures are reproducible from the frozen fixture. That was verify finding CRITICAL-2 on PR #318, and it is why round 2 exists. The counts above are reproducible from the frozen fixture, not from memory.

## The extraction rule — prefix tier, whole-line deferral scan

`idd_parse_complexity` applies these steps, in this order:

1. **Take the first non-blank line** under the `### Complexity` heading. The heading is anchored at line start; a ``` or ~~~ fence is not a section; the section ends at the next heading of the same or higher level; a deeper `####` line is skipped.
2. **Strip leading and trailing markdown decoration** (`**`, `` ` ``, `_`). Decoration is presentation, not value.
3. **The stripped value must begin with one of `Simple`, `Plan`, `Spectra`, `SDD-warranted`** as a whole word — longest match first, so `SDD-warranted` is tried before anything that could be its prefix, and a word boundary keeps `Simpler` from reading as `Simple`. That leading word **is the tier**. Everything after it — same-line rationale, a parenthetical, an em-dash note, a ` via <source>` provenance suffix (`Plan via Layer V`, `Spectra via hard-gate (sdd_bias)`) — is **legal and ignored** for tier extraction.
4. **Scan the entire first line** — not only the text after the tier — for deferral vocabulary: `when triggered`, `parking lot`, `deferred`, `暫緩` (case-insensitive; space, hyphen and underscore tolerant, so `Parking-Lot` and `if/when triggered` both count). A hit withholds the issue under its own reason, **even though the tier prefix is valid**.

| Outcome | exit | stdout | stderr |
|---|---|---|---|
| routable | `0` | the leading tier | — |
| value does not begin with a tier (`移入 discussion list`) | `3` | — | `unparseable-complexity: <raw line>` |
| no `### Complexity` section | `4` | — | `missing-complexity` |
| tier valid, deferral vocabulary present (`Plan when triggered`) | `5` | — | `deferral-marker: <raw line>` |

Two ordering consequences are deliberate:

- **Tier check precedes the deferral scan.** `移入 discussion list（暫緩）` is exit 3, not 5 — a value with no tier is a data defect first, whatever else it says.
- **Only the first line is scanned.** Scanning the whole section would add two false positives on the corpus (#154 "remove *deferred* caveat", #137 "reuse existing `deferred` enum") and catch nothing new. The producer's deferral intent, when written into this field at all, sits on the value line.

On every non-zero path **nothing is written to stdout**. A consumer that captured a tier there could route on it — which is the incident.

### Corpus validation — the regression that keeps this honest

The rule was derived from and validated against every diagnosed issue in this repository (snapshot 2026-08-15, 225 issues fetched, 159 with a `## Diagnosis` comment), and that validation is a **frozen regression test**, not a one-off check: `scripts/tests/actionability-gate/fixtures/corpus-complexity.json`, asserted by `scripts/tests/actionability-gate/test.sh`.

| exit | count | issues |
|---|---|---|
| `0` routable | 149 | Plan 69 · Simple 41 · Spectra 39 |
| `5` deferral | 9 | #131 #136 #140 #143 #144 #145 #146 #157 #200 |
| `4` missing | 1 | #273 |
| `3` unparseable | 0 | — |

| — no `## Diagnosis` comment at all | 66 of 225 | every one is exit 4 (`complexity-missing`) — see the *undiagnosed* group below |

Every one of the 159 routes as hand-reviewed; **0 false positives**. No Diagnosis comment was rewritten and no label was backfilled to get there — **zero migration** is a claim about this corpus, and the test is what makes it falsifiable. Read it for what it says: *no existing diagnosis needs rewriting*. It does **not** say the backlog's actionability distribution is unchanged — on the 2026-09-07 open backlog only 2 of 14 issues were routable, because 11 had never been diagnosed. That is why the display distinguishes *undiagnosed* from *parked*.

**Signal 3 has its own frozen corpus — read it for what it proves.** `scripts/tests/actionability-gate/fixtures/corpus-blocking.json` holds every `### Blocking` section in the bodies of all 238 issues (55 sections, first section per issue; hand review: 48 empty, 7 real blockers), each row with its **original body** so the shared extractor is exercised, not bypassed. The reader agrees with the hand review on **54 of the 55**; row #1 is an accepted false positive (an informational second bullet). **54 of the 55 issues are CLOSED**, which the gate never evaluates — on the 2026-09-07 open backlog signal 3 decided one issue (#316 itself). So the corpus is a legitimate sample of producer style and a regression baseline; it is *not* proof of gate correctness on the live backlog, and #336's acceptance bar is the semantic truth (48 / 7), not the fixture's expectations. Round 2 shipped `idd_blocking_section` without any of this and withheld 31 of the 48 — including #316's own `- (none — 可動)`. Two rival rules were measured on the same rows and rejected; their text and FP/FN counts are recorded in the helper. The rule is locale-independent (multibyte separators as alternations, never inside a bracket expression — under `LC_ALL=C` the round-3 rule flipped both directions) and the test runs it under `LC_ALL=C`.

## Risk posture — the label is primary, the vocabulary is a net

Deferral vocabulary is a **high-precision, low-recall heuristic**. It is NOT a closed enumeration and MUST NOT be "completed" by analogy — but it must not grow casually either. The two failure directions are asymmetric:

| Failure | Consequence | Posture |
|---|---|---|
| **miss** (deferral written in words the scan does not know) | the issue looks actionable — the pre-#298 behaviour, no worse | acceptable; the `parking-lot` label is the human backstop |
| **false positive** (routable issue withheld) | a hard stop on real work, with a reason that reads as authoritative | unacceptable; keep the vocabulary conservative |

So the rule for adding a term: **corpus evidence of zero false positives**, recorded in the regression fixture. Resemblance to an existing term is not evidence.

**Signal 3 (`### Blocking`) has a different posture, and the difference matters.** It is a **list** field written by `idd-update`'s template `- {blocker 1, or "(none)"}`, model-filled, with 35+ spellings for "no blocker" in the wild. The reader therefore (a) judges **each bullet** — any non-placeholder bullet makes the section non-empty, so `- (none)` followed by `- 等 …` is a blocker — and (b) recognises a placeholder by its **leading token** (`none` · `n/a` · `無`, optionally bulleted, decorated or parenthesised, followed by end of line, a closing paren or a separator), so `- (none — 可動)` is empty while `- none of the reviewers replied yet` is not. Its failure directions are **not** symmetric with signal 1's: a miss here is not "pre-#298 behaviour", it is a regression of #84's blocked-state surfacing; a false positive is the hard stop the table above calls unacceptable. **The rule for misses, stated as a rule** (both directions accepted, documented, pinned by test): *the leading token decides the bullet, and only `-` / `*` bullets or the section's first line are judged*. Fail-open: a placeholder token followed by a clause (`- (none) but actually blocked by #86`) reads as empty, and a real blocker written after a placeholder as an ordered-list item, `+` bullet, blockquote, table row, `####` line or bare paragraph is a continuation and is not read. Fail-closed: a lead-in sentence before the first bullet is judged as the first line and reads as a blocker. The corpus has none of these shapes; widening the bullet class was measured and rejected (it enlarges the fail-closed side). Only the **first** `### Blocking` section of a body is read. Whether this field should be regex-read at all — producer contract or model judgement, first-vs-last section, and IC_R011 (c) semantics — is **#336**; do not extend the rule by analogy before that is decided. An unbalanced (unclosed) fence in a body disables fence tracking for that body so a section below it is still found (live instance #290).

**Mentions are not declarations — and the scan cannot tell them apart.** `Plan（把 parking lot 的文件敘述收斂）` and `Simple, no longer deferred` both trip the deferral scan. The corpus has zero such values, and negation logic would open a new miss surface, so the vocabulary is left as is; the operator sees the raw line and the remedy for this class is to keep meta-discussion out of the value line.

**A documented miss, kept honest.** #128's Diagnosis reads `Plan（觸發表）+ 未決 UX 軸 → **移入 discussion list**`; its deferral ("blocked-by #86") lives only in Strategy prose. Under this rule it routes as `Plan`. That is the designed outcome — the gate does not parse prose — and the fixture pins #128 as *actionable* rather than pretending a marker exists. If it should be withheld, a human applies the label.

## Where deferral state lives

| State | Home | Mutable? | Maintained by |
|---|---|---|---|
| Complexity tier | `### Complexity` in the Diagnosis comment | no (append-only) | `idd-diagnose` |
| Deferral / parked | `parking-lot` label | **yes** | **a human** — see below |
| External blocker | `### Blocking` in the issue body | yes | `idd-update` |

**`idd-diagnose` SHALL NOT apply, remove, or derive the `parking-lot` label on the issue it is diagnosing.** The label is a human ruling, and it is settable *after* the diagnosis was written. (Scope: the IC_R011 checkpoint that idd-diagnose runs in Step 3.6 may attach `parking-lot` to a *newly filed sister issue* when the user classifies it (b) infeasible / (c) blocked-on-external — that is a human classification landing on a different issue, and since 3.1.0 it means the new issue is born parked. `blocker:infeasible` / `blocker:waiting` were never created in any repo and are retired everywhere IC_R011 is stated.) Empirically the two signals disagree: of 11 diagnosed issues sampled on 2026-08-10, only 5 had the qualifier and the label in agreement. #37 was `**Spectra**` with the label applied later by a human; #131 and #200 had the qualifier with no label. They are not two spellings of one fact — they are two facts, and deriving one from the other would delete the human's ability to park an issue whose tier is perfectly clear.

**The producer's rule is therefore simple**: write the tier clearly, rationale welcome; if the issue is on hold, say so with the label, not in this field. The vocabulary scan exists for the 159-issue past, not as an invitation.

## The three-signal gate

An issue is **actionable** only when all three signals are clear. Any one of them withholds it.

```
  ### Complexity non-routable (exit 3 / 4 / 5)  ─┐
  parking-lot label present                     ─┼─→  not actionable
  ### Blocking section non-empty                ─┘

  actionable  ⟺  none of the three holds
```

### Reason vocabulary — a CLOSED enumeration

**Exactly five values. Do NOT add a sixth by analogy:**

| Reason | Fires when | What it asks of a human |
|---|---|---|
| `complexity-unparseable` | section present, value does not begin with a tier | fix the Diagnosis — this is a data defect |
| `complexity-missing` | no `### Complexity` section | run `/idd-diagnose` — the diagnosis never judged complexity |
| `complexity-deferral-marker` | tier valid, deferral vocabulary present | nothing to repair — this is a legitimate parked state; apply the label if it is not already there |
| `parking-lot-label` | the issue carries the `parking-lot` label | nothing — a human parked it |
| `blocking-nonempty` | the `### Blocking` section of the body is non-empty | wait, or clear the blocker via `idd-update` |

The three complexity reasons are kept distinct **because the human response differs**. Collapsing them into one would tell the operator to "fix" a value that is not broken.

### What is deliberately NOT a signal

**The `- [~]` disposition marker inside a Diagnosis `### Strategy` checklist is NOT an input to this gate.** It has an existing consumer — `idd-close`'s checklist gate, where it means "this checklist item was deliberately skipped at close time". That is a *per-item, close-time* disposition. This gate asks a *per-issue, routing-time* question. Feeding one into the other answers a different question than the one being asked, and would collide with `idd-close`'s established semantics.

> ⚠ Anyone editing `- [~]` handling must check `idd-close` first. Treating it as unused because routing ignores it will break the close gate.

## Default on non-routable Complexity — conservative, and always surfaced

A consumer whose `### Complexity` value is non-routable **for any reason** SHALL report the issue as **not actionable** and SHALL **surface the original unmodified line** to the operator.

Three things are forbidden:

- **SHALL NOT** silently truncate a non-routable value to its tier prefix. That truncation is the 2026-08-10 incident — and on exit 5 the prefix is *right there*, well-formed, which is exactly why the helper refuses to print it.
- **SHALL NOT** downgrade a non-routable value to any tier, including `Plan`. `Plan` is still actionable; downgrading routes a parked issue into `/idd-plan`.
- **SHALL NOT** abort the enclosing listing operation. One bad value must not suppress the other issues — a surfacing tool that dies on one malformed row is worse than one that flags it. (The `set -e` call shape below is what makes this hold in practice.)

This mirrors the `### Conflict Class` contract in [`parallel-orchestration.md`](parallel-orchestration.md), which defaults an absent or unparseable value to `D_diagnose_first` and requires the fallback be printed. The two fields are orthogonal (one classifies physical resources touched, the other routing tier) but share one discipline: **conservative default plus mandatory surfacing, never silent.**

## Display grouping — the gate is unified, the display is not

The gate emits a verdict together with its reason list. The display layer groups by reason:

| Reasons | Group |
|---|---|
| any of `parking-lot-label` · `complexity-deferral-marker` · `complexity-unparseable` | **parked** — a human parked it, the diagnosis said so, or the value is a defect to repair; each row shows the raw `### Complexity` line (from the helper's stderr) or the label, so the operator sees *why*. (`idd-list --parked` is a *revisit* list with its own definition — parked ∪ blocked, minus data defects — not this group.) |
| otherwise `blocking-nonempty` | the existing **blocked**-state group (#84) — heading, all-blocked banner text, and footer counts unchanged |
| otherwise (`complexity-missing` alone) | **undiagnosed** — the issue has not been diagnosed yet. That is every issue's birth state and, on a live backlog, the dominant one (11 of 14 open issues on 2026-09-07); round 2 filed it under *Parked*, which hid `→ /idd-diagnose #N` and made the footer disagree with `--parked` by an order of magnitude. The display keeps the diagnose command |

`idd_actionability_group` returns exactly these three strings (an empty or unknown reason list is exit 2 — API misuse, never a quiet *parked*). The raw values the helper surfaces are third-party text: **the helper strips C0 control characters and DEL from its own outputs** (TAB and LF kept) so a `\r` or an ANSI sequence in an issue body cannot repaint the terminal or the executing model's context — **data, never instructions**. Issue bodies carry no author filter (anyone can open an issue on a public repo); that is why the strip lives in the helper and not in each consumer.

Unifying the *judgment* does not mean unifying the *presentation*. #84's blocked-state surface is user-facing behavior people rely on; merging it into one undifferentiated bucket would be a regression dressed as a simplification.

## Consumer contract

The four routing consumers SHALL invoke the shared implementation at `scripts/lib/actionability.sh` and MUST NOT embed a private parse — of `### Complexity` **or** of `### Blocking`. **The gate SHALL run before any egress or branch creation** (a comment, a `git checkout -b`, a tree-lock): a human-parked issue must not receive an Implementation Plan comment before being told it is parked — round 2's `idd-implement` did exactly that at Step 2.5, and the test now pins the order. **The gate SHALL print its verdict** — skills are executed by a model whose only observation channel is the Bash output; a block that merely assigns `$VEXIT` shows a parked issue as a clean, silent exit 0. **Shell variables do not survive across Bash calls**: a consumer that reads the gate's variables in a later block MUST check `${VEXIT:-}` and re-run the same block with the same helper when they are absent (never a private regex). **Cluster path**: the consumers currently gate the *first* issue of `/idd-implement #a #b #c` only — issue-set parsing happens after the gate; tracked in #340. Diagnosis comments are trusted only from `OWNER` / `MEMBER` / `COLLABORATOR` (org-repo maintainers are `MEMBER`); a former collaborator's comments are re-classified `CONTRIBUTOR` by GitHub and would then read as `complexity-missing`. Prerequisites: `gh`, `jq`, `python3` (pre-approve them in `allowed-tools` so unattended runs do not stall on a permission prompt). The canonical call shape, in full, is:

```bash
# 0. Missing helper → fail loud, name the path. Never fall back to a private regex.
. "$CLAUDE_PLUGIN_ROOT/scripts/lib/actionability.sh" || {
    echo "FATAL: missing $CLAUDE_PLUGIN_ROOT/scripts/lib/actionability.sh — 不得改用私有 regex" >&2
    exit 1
}

# 0. Issue numbers enter a REST path: digits only, or refuse. (A `?per_page=1`
#    smuggled in would silently truncate the fetch.)
case "$N" in ''|*[!0-9]*) echo "FATAL: non-numeric issue number: $N" >&2; exit 1 ;; esac

# 1. Latest Diagnosis comment — PAGINATE, and TRUST ONLY repo-affiliated authors.
#    `gh issue view --json comments` returns only the OLDEST 100 comments, so on
#    a long issue the latest diagnosis is exactly the one that gets dropped
#    (`--paginate --jq` emits one array per page; `jq -s add` folds them). On a
#    public repo any account can append a `## Diagnosis`; without the author
#    filter that comment would become signal 1.
LATEST_DIAGNOSIS=$(gh api "repos/$GITHUB_REPO/issues/$N/comments" --paginate \
    --jq '[.[] | select(.author_association == "OWNER" or .author_association == "MEMBER" or .author_association == "COLLABORATOR") | {body}]' \
    | jq -s 'add // []' \
    | python3 -c '
import json, sys, re
cs = json.load(sys.stdin)
ds = [c for c in cs if re.search(r"(?m)^## Diagnosis", c["body"])]   # line-anchored: quoted/inline mentions do not count
print(ds[-1]["body"] if ds else "")')

# 2. The other two signals — labels, and the body's ### Blocking section (via the helper).
ISSUE_JSON=$(gh issue view "$N" --repo "$GITHUB_REPO" --json labels,body)
HAS_PARKING=$(jq -r 'if any(.labels[]; .name == "parking-lot") then "yes" else "no" end' <<<"$ISSUE_JSON")
BLOCK_LINE=$(idd_blocking_section "$(jq -r '.body // ""' <<<"$ISSUE_JSON")")
if [ -n "$BLOCK_LINE" ]; then BLOCKING=yes; else BLOCKING=no; fi

# 3. Conditional capture — the only shape that survives `set -euo pipefail`.
#    A bare TIER=$(idd_parse_complexity …) aborts the caller on exit 3/4/5 and
#    takes the whole listing down with it.
if TIER=$(idd_parse_complexity "$LATEST_DIAGNOSIS" 2>/dev/null); then CEXIT=0; else CEXIT=$?; fi
COMPLEXITY_ERR=$(idd_parse_complexity "$LATEST_DIAGNOSIS" 2>&1 >/dev/null) || true   # raw line on 3/5, `missing-complexity` on 4

# 4. The gate — actually call it. Exit 2 is API misuse (a bug in THIS consumer),
#    never "not actionable"; do not fold it into the withheld branch.
if VERDICT=$(idd_actionability_verdict --complexity-exit "$CEXIT" --parking-label "$HAS_PARKING" --blocking-section "$BLOCKING" 2>&1); then VEXIT=0; else VEXIT=$?; fi
case "$VEXIT" in
    0) REASONS="" ;;                                       # actionable → dispatch on "$TIER" (reset: a cluster loop must not carry the previous issue's reasons)
    1) REASONS="${VERDICT#not-actionable: }" ;;            # withheld  → surface "$REASONS" + "$COMPLEXITY_ERR" / "$BLOCK_LINE"; no lifecycle command
    *) echo "FATAL: idd_actionability_verdict misuse — $VERDICT" >&2; exit 1 ;;   # a LISTING consumer prints this and marks the row `(gate error)` instead of exiting
esac
# 5. Print the verdict. The executing model sees only this output; an unprinted
#    withheld verdict is indistinguishable from an actionable issue.
printf 'gate #%s: VEXIT=%s TIER=%s REASONS=%s | %s%s\n' "$N" "$VEXIT" "${TIER:-}" "${REASONS:-}" "${COMPLEXITY_ERR:-}" "${BLOCK_LINE:-}"
```

`idd-list` deviates in three documented ways: it takes labels/body/comments from its bulk fetch and paginates only when the comment array is ≥ 100 (its own anti-N+1 rule), it skips the gate for non-open issues, and every fetch failure marks the row rather than exiting — "one bad value does not suppress the other issues" applies to API errors too.

| Function | stdout | exit |
|---|---|---|
| `idd_parse_complexity <body>` | the leading tier (exit 0 only) | `0` routable · `3` no tier prefix (stderr `unparseable-complexity: <raw>`) · `4` no section (stderr `missing-complexity`) · `5` deferral vocabulary (stderr `deferral-marker: <raw>`) |
| `idd_blocking_section <issue-body>` | the first **bullet** of `### Blocking` that is not a none-placeholder (leading-token rule); empty when the section is absent or every bullet is a placeholder | `0` |
| `idd_actionability_verdict --complexity-exit 0|3|4|5 --parking-label yes|no --blocking-section yes|no` | `actionable` / `not-actionable: <reason>[; …]` | `0` actionable · `1` not actionable · `2` bad usage (missing value, non-boolean, unknown flag) |
| `idd_actionability_group <reasons>` | `parked` / `blocked` / `undiagnosed` | `0` |

**Only replacing the parser is not a fix.** Round 1 shipped a complete gate, 66 green assertions, and zero consumers calling `idd_actionability_verdict` (verify CRITICAL-1 on PR #318). A consumer that reads `$TIER` and never asks the gate has re-created the incident with a nicer parser.

**Malformed invocation fails loud (exit 2), never defaults to actionable.** An unanswered signal treated as "clear" would re-open the exact hole this contract closes. A flag with no value is a named exit-2 error, not an infinite loop (verify H1).

**When the shared implementation is missing, a consumer SHALL fail loudly and name the path** — never fall back to a private parse. A silent fallback would restore the three-way divergence this file exists to prevent.

## Adversary discipline (audit lenses)

Per [`.claude/rules/attribute-assessment.md`](../../../.claude/rules/attribute-assessment.md), evaluate this interface through three lenses:

| Lens | Risk | Mitigation |
|---|---|---|
| **Scoundrel** | Smuggle deferral vocabulary after the ` via ` separator (`Simple via when triggered`) so a suffix-stripping parser yields a legal tier | The scan covers the whole line; the suffix is not an escape hatch (fixture row 906). And in the other direction — a scoundrel who wants an issue *actionable* has simply declared it so under their own name in the audit trail; the label, which the gate reads independently, is the human's veto |
| **Lazy Developer** | Skip a signal argument and let the gate assume "clear"; or read `$TIER` and skip the verdict | Every argument is required and validated; missing or non-boolean input returns exit 2 with a named cause. The consumer contract above makes the verdict call part of the canonical shape, and the #318 verify history is the reminder of what happens without it |
| **Confused Developer** | Answer "does this issue block others?" when asked "is this issue blocked?"; or treat exit 5 as a value to correct | The flag is named `--blocking-section`, pointing at the artifact section being read rather than at a relationship. The three complexity reasons are distinct precisely so that `complexity-deferral-marker` reads as "parked", not "broken" |

## Out of scope

- **Evaluating whether a trigger condition has fired.** Trigger conditions are prose propositions about future world state (「等 ≥3 instances」「首次 trace-stale 實害事故」). Deciding whether one has come true requires a human observing the world; it is not derivable from the repo. This gate knows only that *someone declared the issue parked*, never whether the parking is still warranted. That is an epistemic boundary, not a missing feature.
- **Bringing parked issues back into view.** Nothing here re-surfaces an issue whose trigger has fired — tracked separately as **#310** (`idd-list --parked` is the manual review path). This contract makes parked issues *more* thoroughly hidden, which makes that gap more urgent, not less.
- **Deferral expressed only in prose** (Strategy bullets, Blocking rationale, comments) — see #128 above. The label is the mechanism for that.
- **`- [~]` handling** — belongs to `idd-close`, see above.

## See also

- [`parallel-orchestration.md`](parallel-orchestration.md) — the `### Conflict Class` contract this one mirrors; orthogonal field, same discipline
- [`rules/append-vs-modify.md`](../rules/append-vs-modify.md) — why a Diagnosis comment cannot hold mutable state
- `scripts/tests/actionability-gate/` — the incident fixture (`parked-routing.json`, verbatim 2026-08-10 rows plus corpus-sampled shapes), the frozen Complexity corpus (`corpus-complexity.json`, 159 rows) and the frozen Blocking corpus (`corpus-blocking.json`, 55 rows)
- **#336** — whether `### Blocking` should be regex-read at all (producer contract vs model judgement); **#337** — #84's `blocked`-label / wait-class display signals, retired from the gate path in 3.1.0
- **On enumerations.** The *reason* vocabulary is written as a closed list with an explicit no-analogy clause because it is one: a summarizing criterion plus examples is two specifications that drift apart silently. The *deferral* vocabulary is deliberately **not** presented that way — it is a heuristic with a stated add-criterion (corpus evidence, zero false positives) — because round 1 showed what happens when a heuristic is dressed up as a domain: it rejects the data it was meant to describe.
