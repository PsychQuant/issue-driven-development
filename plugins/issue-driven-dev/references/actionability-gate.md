# Actionability Gate

> The contract that answers **「這個 issue 現在可不可以動？」** — the closed value domain of the `### Complexity` Diagnosis field, where deferral state lives, and the three-signal gate that `idd-list` / `idd-all` / `idd-implement` / `idd-plan` all consume. This file is the single source of truth; the four skills cite it and MUST NOT restate the rules in their own words.
>
> **Source**: `add-actionability-gate` Spectra change (capability `actionability-gate`). Origin: issue-driven-development#298, surfaced from real dogfooding (2026-08-10 backlog routing).

## The incident this exists to prevent

On 2026-08-10 a real 22-issue backlog was routed by `/idd-list`. Of the 11 diagnosed issues, **8 parked/deferred/blocked ones were reported as "Actionable now"**. Two of them (#131, #200) carried a defer ruling the user had personally made on 2026-07-07 — following the routing would have re-opened work the user had decided to park.

The failure was **silent**. The table was syntactically correct, well-formatted, and carried no warning.

## Root cause — mutable state in an immutable artifact

`### Complexity` lives in a Diagnosis comment, and Diagnosis comments are **append-only** (see [`rules/append-vs-modify.md`](../rules/append-vs-modify.md)). But "is this issue parked?" is **mutable** — a trigger firing should un-park it. Writing deferral qualifiers (`Simple when triggered`, `Spectra when triggered (parking lot)`) into a frozen field created a value that could never be corrected in place.

Two consequences followed:

1. **The field carried two kinds of information** (tier + deferral) while every consumer's parser assumed one. Three consumers each invented an incompatible narrowing, and they disagreed:

   | Consumer | private narrowing | result on `Simple when triggered` |
   |---|---|---|
   | `idd-list` | `([A-Za-z-]+)` | silently truncated to `Simple` → routed a parked issue to `/idd-implement` |
   | `idd-all` | `(.+?)` + via-split | non-tier string; matched no dispatch row **and** was not `UNKNOWN` |
   | `idd-implement` | same | same |

   `idd-all`'s `UNKNOWN → abort` safety net structurally could not catch this: it fires only when the regex fails entirely, never when it matches an out-of-domain value.

2. **The frozen state drifted elsewhere.** #136's Diagnosis comment read bare `Spectra` while its body read `Spectra when triggered (parking lot)` — state that cannot be corrected in place migrates to wherever it can be edited.

IDD already knew the right shape: `### Blocking` is mutable, so it lives in the issue **body** and is maintained by `idd-update`. This contract applies the same reasoning to deferral.

## Closed value domain — `### Complexity`

**The legal values are exactly these four. This is a CLOSED enumeration — do NOT extend it by analogy, and do NOT infer a fifth value from resemblance to an existing one:**

1. `Simple`
2. `Plan`
3. `Spectra`
4. `SDD-warranted` — legacy alias of `Spectra`, retained for backward compatibility

A value MAY carry the provenance suffix ` via <source>` (established v2.50). The canonical tier is the text preceding the **first** ` via ` separator. Both existing producers of suffixed values remain legal: `Plan via Layer V` (Layer V escalation) and `Spectra via hard-gate (sdd_bias)` (hard-gate exit).

**Deferral qualifiers SHALL NOT be written into this field.** `when triggered`, `(parking lot)`, and any prose describing why the issue is on hold belong to the `parking-lot` label, not here. A tier field that carries deferral state is the defect this contract closes.

### Where deferral state lives instead

| State | Home | Mutable? | Maintained by |
|---|---|---|---|
| Complexity tier | `### Complexity` in the Diagnosis comment | no (append-only) | `idd-diagnose` |
| Deferral / parked | `parking-lot` label | **yes** | **a human** — see below |
| External blocker | `### Blocking` in the issue body | yes | `idd-update` |

**`idd-diagnose` SHALL NOT apply, remove, or derive the `parking-lot` label.** The label is a human ruling, and it is settable *after* the diagnosis was written. Empirically the two signals disagree: of 11 diagnosed issues sampled on 2026-08-10, only 5 had the qualifier and the label in agreement. #37 was bare `Spectra` with the label applied later by a human; #131 and #200 had the qualifier with no label. They are not two spellings of one fact — they are two facts, and deriving one from the other would delete the human's ability to park an issue whose tier is perfectly clear.

## The three-signal gate

An issue is **actionable** only when all three signals are clear. Any one of them withholds it.

```
  ### Complexity outside the closed domain, or absent  ─┐
  parking-lot label present                            ─┼─→  not actionable
  ### Blocking section non-empty                       ─┘

  actionable  ⟺  none of the three holds
```

### Reason vocabulary — also a CLOSED enumeration

**Exactly four values. Do NOT add a fifth by analogy:**

| Reason | Fires when |
|---|---|
| `complexity-unparseable` | `### Complexity` section present, value outside the closed domain |
| `complexity-missing` | no `### Complexity` section at all |
| `parking-lot-label` | the issue carries the `parking-lot` label |
| `blocking-nonempty` | the `### Blocking` section of the body is non-empty |

### What is deliberately NOT a signal

**The `- [~]` disposition marker inside a Diagnosis `### Strategy` checklist is NOT an input to this gate.** It has an existing consumer — `idd-close`'s checklist gate, where it means "this checklist item was deliberately skipped at close time". That is a *per-item, close-time* disposition. This gate asks a *per-issue, routing-time* question. Feeding one into the other answers a different question than the one being asked, and would collide with `idd-close`'s established semantics.

> ⚠ Anyone editing `- [~]` handling must check `idd-close` first. Treating it as unused because routing ignores it will break the close gate.

## Default on absent or unparseable — conservative, and always surfaced

A consumer parsing a `### Complexity` value outside the closed domain SHALL report the issue as **not actionable** and SHALL **surface the original unmodified value** to the operator. A missing section gets the same verdict under a distinct reason.

Three things are forbidden:

- **SHALL NOT** silently truncate a non-domain value to its tier prefix. That truncation is the 2026-08-10 incident.
- **SHALL NOT** downgrade a non-domain value to any tier, including `Plan`. `Plan` is still actionable; downgrading routes a parked issue into `/idd-plan`.
- **SHALL NOT** abort the enclosing listing operation. One bad value must not suppress the other issues — a surfacing tool that dies on one malformed row is worse than one that flags it.

This mirrors the `### Conflict Class` contract in [`parallel-orchestration.md`](parallel-orchestration.md), which defaults an absent or unparseable value to `D_diagnose_first` and requires the fallback be printed. The two fields are orthogonal (one classifies physical resources touched, the other routing tier) but share one discipline: **conservative default plus mandatory surfacing, never silent.**

## Display grouping — the gate is unified, the display is not

The gate emits a verdict together with its reason list. The display layer groups by reason:

| Reasons | Group |
|---|---|
| `blocking-nonempty` **alone** | the existing blocked-state group (#84) — heading, all-blocked banner text, and footer counts unchanged |
| anything else, including any mix | the parked group |

Unifying the *judgment* does not mean unifying the *presentation*. #84's blocked-state surface is user-facing behavior people rely on; merging it into one undifferentiated bucket would be a regression dressed as a simplification.

## Consumer contract

The four routing consumers SHALL invoke the shared implementation at `scripts/lib/actionability.sh` and MUST NOT embed a private parse:

```bash
. "$CLAUDE_PLUGIN_ROOT/scripts/lib/actionability.sh"

tier=$(idd_parse_complexity "$diagnosis_body"); cexit=$?
verdict=$(idd_actionability_verdict \
            --complexity-exit "$cexit" \
            --parking-label "$has_parking_lot_label" \
            --blocking-section "$blocking_section_nonempty")
```

| Function | stdout | exit |
|---|---|---|
| `idd_parse_complexity <body>` | canonical tier | `0` in domain · `3` out of domain (stderr: `unparseable-complexity: <raw>`) · `4` no section (stderr: `missing-complexity`) |
| `idd_actionability_verdict …` | `actionable` / `not-actionable: <reason>[; …]` | `0` actionable · `1` not actionable · `2` bad usage |
| `idd_actionability_group <reasons>` | `blocked` / `parked` | `0` |

**Malformed invocation fails loud (exit 2), never defaults to actionable.** An unanswered signal treated as "clear" would re-open the exact hole this contract closes.

**When the shared implementation is missing, a consumer SHALL fail loudly and name the path** — never fall back to a private parse. A silent fallback would restore the three-way divergence this file exists to prevent.

## Adversary discipline (audit lenses)

Per [`.claude/rules/attribute-assessment.md`](../../../.claude/rules/attribute-assessment.md), evaluate this interface through three lenses:

| Lens | Risk | Mitigation |
|---|---|---|
| **Scoundrel** | Write `Simple via when triggered` so the via-split yields a legal tier and the issue passes the gate | The provenance suffix only affects the *tier* channel. Deferral is asserted through the label, which the gate reads independently — a scoundrel who wants the issue withheld cannot express that through Complexity anyway, and one who wants it actionable has simply declared it actionable, which is a claim the audit trail records under their name |
| **Lazy Developer** | Skip a signal argument and let the gate assume "clear" | Every argument is required and validated; missing or non-boolean input returns exit 2 with a named cause. The cheap path is not the unsafe path |
| **Confused Developer** | Answer "does this issue block others?" when asked "is this issue blocked?" | The flag is named `--blocking-section`, pointing at the artifact section being read rather than at a relationship. The axis is **what the `### Blocking` section contains**, never who blocks whom |

## Out of scope

- **Evaluating whether a trigger condition has fired.** Trigger conditions are prose propositions about future world state (「等 ≥3 instances」「首次 trace-stale 實害事故」). Deciding whether one has come true requires a human observing the world; it is not derivable from the repo. This gate knows only that *someone declared the issue parked*, never whether the parking is still warranted. That is an epistemic boundary, not a missing feature.
- **Bringing parked issues back into view.** Nothing here re-surfaces an issue whose trigger has fired — tracked separately as **#310**. This contract makes parked issues *more* thoroughly hidden, which makes that gap more urgent, not less.
- **`- [~]` handling** — belongs to `idd-close`, see above.

## See also

- [`parallel-orchestration.md`](parallel-orchestration.md) — the `### Conflict Class` contract this one mirrors; orthogonal field, same discipline
- [`rules/append-vs-modify.md`](../rules/append-vs-modify.md) — why a Diagnosis comment cannot hold mutable state
- **Why both enumerations above are written as closed lists with explicit no-analogy clauses** rather than as summarizing criteria: a criterion plus illustrative examples is two specifications that will not be updated together, and the criterion's literal reach eventually exceeds the set of cases its author had in mind. The divergence is silent — the prose still reads fine, it just answers a boundary question nobody agreed to. Naming the members and forbidding extension-by-resemblance is what makes a boundary auditable. (This mirrors a maintainer-side writing discipline that is not part of the plugin distribution, so no link is given here.)
