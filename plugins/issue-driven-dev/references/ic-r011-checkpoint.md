# IC_R011 Checkpoint Pattern — Canonical Reference

**Status**: canonical (cited by `idd-*` + `spectra-*` skills since v2.43.0;default-flip + 3-category skip taxonomy since v2.72.0)
**Source principle**: [IC_R011](https://github.com/kiki830621/ai_martech_global_scripts/issues/516) — Commercial Project Low-Bar Issue Filing
**Filing trigger**: [kiki830621/ai_martech_global_scripts#525](https://github.com/kiki830621/ai_martech_global_scripts/issues/525) (sub-issue of #523 systematic plugin alignment)
**Default-flip trigger**: [PsychQuant/issue-driven-development#148](https://github.com/PsychQuant/issue-driven-development/issues/148) (post-3/3 file-all session pattern,2026-05-23)

---

## Purpose

Every IDD lifecycle moment that involves **deliberation** or **manual reproduction** SHALL surface tangential discoveries (sister bugs, observed friction, deferred work, out-of-scope user mentions) via a standardized checkpoint, preventing audit-trail loss into conversation.

This document is the **canonical mechanical anchor** that every alignment-eligible skill cites. Skill SKILL.md files SHALL NOT duplicate the procedure body inline — they SHALL cite this document and add only per-step deviation. Without centralization, each skill's implementation drifts in:

- Default behavior (file vs ask)
- Skip path semantics (silent skip vs categorized rationale)
- Audit-trail format (Markdown section vs comment vs body PATCH)
- Skip rollback semantics (env var name / scope)

**Single source of truth → cross-skill consistency mechanically guaranteed.**

---

## 1. Default Behavior — File by Default (Filing Checkpoint Sites)

When a SHALL-tier filing checkpoint site surfaces tangential discoveries, the skill SHALL file each candidate by default — without first asking the user. This default applies to **filing checkpoints**(see Section 6 eligibility), NOT to all IC_R011-shaped 3-option patterns (e.g. `idd-all-chain` Phase 0.4 diagnosis-readiness gate is structurally similar but is not a filing checkpoint).

### 1.1 Default file path (procedure)

```
1. Surface candidate list (with proposed title + type + labels per Section 2 heuristic)
2. Print: "Filing N candidates as P3 follow-ups (per IC_R011 default-flip, v2.72.0+):"
   - List each candidate with its proposed title + 1-line description
3. Loop `gh issue create` per candidate (sequential, NOT batched — each issue gets its own audit line)
4. PATCH originating comment with audit-trail block (Section 4 format)
```

### 1.2 Filing command (literal `gh` invocation)

```bash
gh issue create \
  --repo "$GITHUB_REPO" \
  --title "[$type] $description (mid-{stage} tangential from #$NNN)" \
  --body "$BODY_WITH_SOURCE_LINK" \
  --label "$type,confidence:confirmed,priority:P3"
```

Issue body MUST include the canonical **Source footer** (see Section 7) for traceability.

### 1.3 When the default path is NOT taken

The default file path is bypassed under exactly four conditions:

| Trigger | Path taken |
|---------|-----------|
| User explicitly requests skip mid-checkpoint (e.g. 「等等」 / 「先別 file」) | Skip path (Section 1.4 — 3-category taxonomy) |
| `AI_LOW_BAR_ISSUE_FILING=false` env var set | Legacy ask path (Section 1.6 — reverts to pre-flip 3-option) |
| `# Disable IC_R011` flag in repo CLAUDE.md | Legacy ask path (Section 1.6) |
| Unattended mode (no TTY) + env var bypass | Implicit (a) skip + audit trail (Section 5 fallback chain) |

If none of the above apply → default file path proceeds without AskUserQuestion.

### 1.4 Skip path — 3-category taxonomy (when user requests skip)

When the user requests to skip one or more candidates, the skill SHALL present a **per-skip-candidate AskUserQuestion** forcing selection among three categories:

| Category | Meaning | Action |
|----------|---------|--------|
| **(a) unactionable observation** | Pure observation with no actionable form (e.g. "AI hallucinates is a statistical fact") | Real skip — NO `gh issue create`. Audit: `Skipped: (a) unactionable observation` |
| **(b) infeasible but understood** | Technically infeasible at this point but understood (e.g. "Need 100x budget to reproduce") | **Still files** as P3 with `blocker:infeasible` label. Audit: `Skipped: (b) infeasible — filed as #NNN with blocker:infeasible label` |
| **(c) blocked on external state** | Waiting on external state that will likely change (e.g. "Wait for GitHub Actions API to add X") | **Still files** as P3 with `blocker:waiting` label. Audit: `Skipped: (c) blocked-on-external — filed as #NNN with blocker:waiting label` |

**Net effect**: only (a) avoids filing. (b) and (c) preserve the parking lot — periodic backlog grooming can grep `blocker:infeasible` or `blocker:waiting` to revisit when conditions change.

### 1.5 Skip taxonomy AskUserQuestion structure (per-candidate)

When user explicitly requests skip, for EACH skip-candidate, present:

```
question: "Skip candidate #N: '{candidate title}'. Which category?"
options:
  - label: "(a) unactionable observation"
    description: "Real skip — no issue created. Pure observation with no actionable form."
  - label: "(b) infeasible but understood"
    description: "Still files as P3 with blocker:infeasible label. Parking lot — revisit when feasibility changes."
  - label: "(c) blocked on external state"
    description: "Still files as P3 with blocker:waiting label. Parking lot — revisit when external state changes."
```

### 1.6 Legacy 3-option ask (close-tier only + bypass paths)

The legacy 3-option `AskUserQuestion` (`file all` / `file selected` / `skip`) is preserved for:

1. **SHOULD-tier sites** (`/idd-close` Step 3.5) — closing is mostly mechanical wrap-up;翻 default 增加 friction without proportional value
2. **Bypass paths** — `AI_LOW_BAR_ISSUE_FILING=false` env var or `# Disable IC_R011` CLAUDE.md flag reverts SHALL-tier sites to this legacy path

```
question: "Found N tangential observation(s). File as follow-up issues?"
options:
  - label: "file all"
    description: "Create one follow-up issue per item with default labels (confidence:confirmed, priority:P3) + source link"
  - label: "file selected"
    description: "Show numbered checklist for cherry-pick"
  - label: "skip"
    description: "Don't file. Audit trail line documenting reason will be added."
```

`file selected` sub-prompt: numbered checklist (per-item AskUserQuestion or OS-native multi-select).

---

## 2. Heuristic — What Counts as "Concern Worth Surfacing"

Per [IC_R011 default-on triggers](https://github.com/kiki830621/ai_martech_global_scripts/issues/516), surface ANY of:

| Trigger category | Examples |
|---|---|
| **Verifiable behavior gap** | even a 1-line fix; observable wrong/missing behavior |
| **Sister bug from reproduction** | same root cause manifesting in different file (proven by `#510 → #518 → #520` cluster pattern) |
| **Observed friction** | "this won't solve X" disclaimers; UX papercuts surfaced incidentally |
| **Deferred work** | mention of "later" / 「之後」 / 「順便」 in conversation or comment |
| **Out-of-scope user mentions** | items user said but plan/diagnose categorized OOS without a follow-up issue |
| **Drift / tangential code quality** | TODO/FIXME comments encountered during scout; sibling helper with similar pattern |
| **Skill plugin design ambiguity** | gaps observed during skill execution itself (meta-tangential, file with `cross-repo:idd-plugin` if applicable) |

### Trigger phrases (for skills that scan their own outputs)

| Language | Phrase patterns (case-insensitive substring) |
|---|---|
| English | `also`, `additionally`, `another (bug\|issue)`, `BTW`, `follow.?up`, `deferred`, `future`, `TODO`, `later`, `worth (filing\|tracking)` |
| 繁體中文 | 「另外」、「順便」、「之後」、「未來」、「待」、「後續」、「需要 follow up」、「我之前觀察到」、「改天」、「再看看」 |

Empty surface list is legitimate — Section 4 audit `(none surfaced)` covers it.

---

## 3. Default-Off Exemptions (Narrow)

Even with file-by-default, the following do NOT surface as candidates:

- **Pure exploration / academic theory brainstorm** — already routed via `confidence:exploratory` (per IC_R010, separate file)
- **Existing issue already covers** — grep `gh issue list --search "<keywords>"` confirms duplicate;reference existing issue # in conversation instead
- **AI hallucinated without codebase evidence** — per MP029 verify first;don't file what doesn't actually exist
- **CONSTRAINT not TODO** — deliberate non-action (e.g. "this skill intentionally doesn't support Windows") is a design choice, not a tangential to track

When exemption applies, do NOT surface the candidate at all (don't even mention in audit unless borderline).

---

## 4. Audit Trail Format (Per-Skill Section)

Each skill PATCHes its own primary comment to add an audit-trail section after the checkpoint runs. Section heading varies per skill (purpose-specific) but contents follow a uniform format.

### 4.1 Per-skill heading conventions

| Skill | Audit section heading | Where it lives |
|---|---|---|
| `/idd-plan` | `### Tangential Observations (filed mid-plan, v2.42.0+ #524)` | Implementation Plan comment |
| `/idd-implement` | `### Sister Bugs Filed (mid-impl, v2.44.0+ #526)` | Implementation Complete comment |
| `/idd-close` | `### Closing Follow-ups Filed (v2.45.0+ #527)` | Closing summary comment |
| `/idd-diagnose` | `### Sister Concerns Filed (mid-diagnose, v2.47.0+ #528)` | Diagnosis comment |
| `/idd-issue` | `### Linked-Context Siblings Filed (v2.48.0+ #529)` | New issue body |
| `/idd-verify` | `### Follow-up Findings Filed (v2.72.0+ #148)` | Verify report (master comment) |
| `/spectra-discuss` | `### Tangential Observations (post-discuss, v1.1.0+ #530)` | Discussion artifact |
| `/spectra-propose` | `### Tangential Observations (post-propose, v1.1.0+ #530)` | Proposal artifact |

### 4.2 Uniform contents — 6 literal audit string formats

For each result of the checkpoint, write ONE of these lines (literal text matters — downstream telemetry / log analysis matches these strings):

| Outcome | Literal audit string format |
|---------|---------------------------|
| Default file path — N items filed | `Filed: #NNN, #MMM, #PPP` |
| Skip (a) — unactionable | `Skipped: (a) unactionable observation` |
| Skip (b) — infeasible | `Skipped: (b) infeasible — filed as #NNN with blocker:infeasible label` |
| Skip (c) — blocked-on-external | `Skipped: (c) blocked-on-external — filed as #NNN with blocker:waiting label` |
| Empty surface | `(none surfaced)` |
| Env var bypass — user chose skip in reverted ask | `Skipped (AI_LOW_BAR_ISSUE_FILING=false — reverted to 3-option ask, user chose skip)` |
| Unattended mode bypass | `Skipped (unattended mode + AI_LOW_BAR_ISSUE_FILING=false → implicit (a) skip)` |
| Legacy ask (close-tier) — file all | `Filed: #NNN, #MMM` (with `(via legacy 3-option ask)` suffix when SHOULD-tier site) |
| Legacy ask (close-tier) — file selected | `Filed: #NNN, #MMM` + `Skipped (user choice): {brief description of N3, N4, N5}` |
| Legacy ask (close-tier) — skip | `Skipped per user choice (N items: brief list of descriptions)` |

### 4.3 Combined outcomes (file + skip mix)

When a default-file invocation surfaces 5 candidates and user skips 2 with mixed categories:

```
Filed: #N1, #N2, #N3
Skipped: (a) unactionable observation (candidate #4: "AI race condition is statistical")
Skipped: (c) blocked-on-external — filed as #N5 with blocker:waiting label (candidate #5: "wait for new GitHub API")
```

Each filed / skipped item gets its own audit line. Multi-line audit block is preferred over compressed single-line for readability.

### 4.4 Telemetry / log analysis migration hint

Pre-v2.72.0 audit trail used `Skipped per user choice (...)` as the canonical skip marker. Post-v2.72.0 skip lines are categorized `Skipped: (a)|(b)|(c) ...`. Downstream tools matching the legacy string need to extend the regex:

```bash
# pre-v2.72.0 (still works for legacy close-tier skips)
grep "Skipped per user choice"

# v2.72.0+ (covers both legacy close-tier + new categorized skips)
grep -E "Skipped(:| per user choice)"
```

---

## 5. Backward-Compat Escape Hatches — Semantic Shift (v2.72.0+)

Per [#148 Decision 5](https://github.com/PsychQuant/issue-driven-development/issues/148), the existing escape hatches retain their names but shift semantics. **No new env var or flag is introduced**.

### 5.1 Semantic shift table

| Setting | Pre-v2.72.0 behavior | Post-v2.72.0 behavior |
|---------|---------------------|----------------------|
| (default) | 3-option ask `[file all] / [file selected] / [skip]` | **file by default + 3-category skip taxonomy** |
| `AI_LOW_BAR_ISSUE_FILING=false` (env var) | Silent skip + audit trail | **Revert to pre-default-flip 3-option ask** |
| `# Disable IC_R011` (repo CLAUDE.md flag) | Silent skip + audit trail | **Revert to pre-default-flip 3-option ask** |
| Unattended (no TTY) + `=false` set | Silent skip + audit trail | **Implicit (a) skip + audit trail** (no AskUserQuestion possible) |
| Unattended (no TTY) + default | (didn't apply pre-flip) | Default file path proceeds (non-blocking by design) |

### 5.2 Temporary opt-out (env var)

```bash
AI_LOW_BAR_ISSUE_FILING=false /idd-plan #NNN
```

When set on a SHALL-tier site invocation, the skill semantics revert to pre-default-flip 3-option ask:
- Default file path is **NOT** taken
- Skill **reverts to pre-default-flip 3-option ask** `[file all] / [file selected] / [skip]`
- User's choice determines outcome (file all / file selected / skip)
- Audit trail string when user chose skip:`Skipped (AI_LOW_BAR_ISSUE_FILING=false — reverted to 3-option ask, user chose skip)`

### 5.3 Permanent opt-out (repo CLAUDE.md flag)

In a repo's `CLAUDE.md`, add the literal directive line:

```markdown
# Disable IC_R011
```

When detected, the skill reverts to the legacy 3-option ask path identically to the env var bypass. Behavior is repo-wide for all IDD checkpoints in that repo.

### 5.4 Unattended mode fallback (no TTY + bypass set)

When the skill detects unattended mode（per `references/unattended-contract.md`：state file 或 `IDD_ALL_UNATTENDED=1`；TTY check 已廢除 #222）AND `AI_LOW_BAR_ISSUE_FILING=false`:
- Skill cannot call AskUserQuestion (no TTY)
- Skill SHALL apply **implicit (a) skip semantics** to all candidates
- Audit trail: `Skipped (unattended mode + AI_LOW_BAR_ISSUE_FILING=false → implicit (a) skip)`

When skill detects unattended mode WITHOUT env var bypass（unattended-contract 訊號本身）:
- Default file path proceeds (it's non-blocking by design — no AskUserQuestion in default file path)

### 5.5 Both layers active

If both env var and CLAUDE.md directive present → both honored (additive opt-out;harmless redundancy). Behavior equivalent to either active.

---

## 6. Eligibility Criteria — Which Skills Mandate This Checkpoint?

| Skill type | Strength | Default behavior (v2.72.0+) | Reason |
|---|---|---|---|
| **Deliberation moments** (`/idd-plan`, `/idd-diagnose`, `/spectra-discuss`, `/spectra-propose`) | **SHALL** | File by default + 3-category skip | These are the prime moments where tangential discoveries surface. Empty list is legitimate but step is mandatory. |
| **Manual reproduction / verify** (`/idd-implement`, `/idd-verify`) | **SHALL** | File by default + 3-category skip | Reproduction reveals same-root-cause sister files (proven by #510 → #518 → #520 cluster). |
| **Closure** (`/idd-close`) | **SHOULD** (advisory) | **Legacy 3-option ask preserved** | Closing summary keyword scan is mostly mechanical wrap-up action;翻 default 增加 friction without proportional value. |
| **Issue creation** (`/idd-issue`) | **SHALL** | File by default + 3-category skip | Light-touch grep on linked context;surface only when heuristic clearly hits. Default file applies to the surface-list outcome. |
| **Mechanical execution** (`/spectra-apply`, `/spectra-archive`, `/spectra-ask`, `/spectra-ingest`, `/spectra-commit`, `/spectra-debug`) | **N/A** (not applicable) | (no checkpoint) | No deliberation phase. These execute pre-decided actions. |

### Per-site treatment summary

- **5 sites get default-flip**:`/idd-diagnose` Step 3.6, `/idd-plan` Step 2.5, `/idd-implement` Step 5.7, `/idd-issue` Step 4.7, `/idd-verify` Step 5b
- **1 site preserves legacy**:`/idd-close` Step 3.5 (SHOULD-tier)
- **2 third-party sites get default-flip**:`/spectra-discuss`, `/spectra-propose` (deliberation moments)

### When in doubt about a new skill

Apply this decision tree:

1. Does the skill have a **deliberation moment** (designing, reviewing, exploring)? → SHALL with default file
2. Does the skill perform **manual reproduction** (running, testing, scouting)? → SHALL with default file
3. Is the skill a **closure** / **wrap-up** action? → SHOULD with legacy 3-option ask
4. Is the skill **purely mechanical** (apply, archive, commit)? → N/A — do not implement checkpoint

---

## 7. Source Footer — Normative Format (All Filed Issues)

Every issue created via IC_R011 (default file path OR (b)/(c) auto-file OR legacy file-all path) SHALL include in its body a footer line identifying the surfacing skill and step. The footer is the audit anchor — three months later, looking at an unrelated issue created by a skill, the reader can trace back to which checkpoint surfaced it.

### 7.1 Literal footer format

```
**Source**: surfaced during /<skill-name> #<source-issue-or-pr> <description> (Step <N.M>)
```

### 7.2 Examples per skill

| Skill | Literal footer text |
|-------|---------------------|
| `/idd-diagnose` | `**Source**: surfaced during /idd-diagnose #N sister concern surfacing (Step 3.6)` |
| `/idd-plan` | `**Source**: surfaced during /idd-plan #N tangential sweep (Step 2.5)` |
| `/idd-implement` | `**Source**: surfaced during /idd-implement #N reproduction (Step 5.7)` |
| `/idd-issue` | `**Source**: surfaced during /idd-issue #N linked-context sister sweep (Step 4.7)` |
| `/idd-verify` | `**Source**: surfaced during /idd-verify #N follow-up triage (Step 5b)` (or via PR `--pr <N>`) |
| `/idd-close` | `**Source**: surfaced during /idd-close #N closing summary scan (Step 3.5)` |

### 7.3 Footer placement

The footer SHALL appear in the issue **body** (NOT a separate comment), typically at the END of the body markdown, after the Problem / Expected / Actual sections. Placement at the end ensures it survives body edits that target earlier sections.

---

## 8. Skill Citation Template

Skill SKILL.md files SHALL cite this canonical reference rather than duplicate the procedure body. The standard template:

```markdown
### Step X.Y: {Stage-Specific Name}

**Per IC_R011 follow-up filing checkpoint** (see [`references/ic-r011-checkpoint.md`](../../references/ic-r011-checkpoint.md))。

**Trigger condition**: <skill-specific — when does this step fire?>

**Per-step deviation** (if any):
- <e.g. idd-verify 5b also filters follow-up-classified findings>
- <e.g. idd-issue 4.7 scans linked attachments + recent conversation>

**Audit trail target**: {section heading per Section 4.1 of canonical}
```

Skills SHALL include the literal substring `per IC_R011` so that maintainer grep `grep -L 'per IC_R011' plugins/issue-driven-dev/skills/idd-*/SKILL.md` returns empty (all sites covered).

---

## Third-Party Skill Alignment (v1.1.0+, #530)

Spectra workflow skills (`/spectra-discuss`, `/spectra-propose`) participate as third-party adopters. Each manually invokes the checkpoint at the end of its primary phase.

### `/spectra-discuss` — Manual Step at end of discussion

After convergence (per `spectra-discuss` Convergence section), but before the user is told the discussion is complete, the skill SHALL run the IC_R011 checkpoint per Section 1.1 default file path.

### `/spectra-propose` — Manual Step at end of proposal drafting

After all artifacts (proposal / design / specs / tasks) are written, the skill SHALL run the IC_R011 checkpoint over the just-drafted artifacts + session log per Section 1.1 default file path.

### Why manual-only for third-party skills

Spectra skills are not part of the IDD plugin and don't share the same automatic invocation infrastructure. The manual step is the alignment mechanism — Spectra documents the IC_R011 step in its skill instructions, but the skill itself doesn't auto-trigger anything (the agent following the skill does the triggering).

### Eligible spectra-* skills only

- ✅ `/spectra-discuss` — deliberation moment
- ✅ `/spectra-propose` — design moment
- ❌ `/spectra-apply` — mechanical execution (no checkpoint)
- ❌ `/spectra-archive` — mechanical execution
- ❌ `/spectra-ask` — informational query
- ❌ `/spectra-ingest` — mechanical artifact update
- ❌ `/spectra-commit` — mechanical git operation
- ❌ `/spectra-debug` — interactive analysis (debug session, not deliberation)

---

## Version History

| Version | Date | Change |
|---------|------|--------|
| 2.43.0 | 2026-05-08 | IC_R011 canonical reference created;6 SHALL/SHOULD sites adopt 3-option ask + audit trail |
| 2.45.0 | 2026-05-10 | `/idd-close` SHOULD-tier #527 added with closing keyword scan |
| 2.46.0–2.48.0 | 2026-05-11–13 | `/idd-diagnose` #528, `/idd-issue` #529 added |
| 2.61.0 | 2026-05-15 | Source 2 commit-body trap scan added to `/idd-verify` Step 0.8 |
| 2.72.0 | 2026-05-25 | **#148 default-flip**:5 SHALL sites + `/idd-issue` + 2 spectra sites flip to file-by-default + 3-category skip taxonomy + `Source` footer normative + Section 8 citation template added。`/idd-close` (SHOULD-tier) preserves legacy 3-option ask。Existing escape hatches preserve names but shift semantics (=false now means "revert to ask"). `Skipped per user choice` audit string superseded by categorized `Skipped: (a)|(b)|(c)` lines for new SHALL sites;`/idd-close` keeps legacy string. |

---

## Related Principles

- [IC_R010](https://github.com/kiki830621/ai_martech_global_scripts/issues/515) — `confidence:exploratory` routing for academic / brainstorm material
- [MP029](https://github.com/kiki830621/ai_martech_global_scripts/issues/) — Verify first before claiming
- [#148 design.md](../../openspec/changes/idd-ic-r011-default-file/design.md) — Default-flip 5 decisions + per-site treatment matrix + escape hatch semantic shift rationale

---

## Reference Implementations

- `/idd-diagnose` Step 3.6 — canonical pattern for sister concern surfacing
- `/idd-plan` Step 2.5 — canonical pattern for tangential observation sweep
- `/idd-implement` Step 5.7 — canonical pattern for sister bug sweep
- `/idd-issue` Step 4.7 — canonical pattern for linked-context sister sweep
- `/idd-verify` Step 5b — canonical pattern for follow-up findings triage (v2.72.0+ adds Rule (SHALL) framing per #149)
- `/idd-close` Step 3.5 — canonical pattern for SHOULD-tier closing keyword scan with legacy 3-option ask

All implementations cite this document via the literal substring `per IC_R011` per Section 8.
