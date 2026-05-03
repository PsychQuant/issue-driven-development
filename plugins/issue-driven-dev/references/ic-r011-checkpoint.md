# IC_R011 Checkpoint Pattern — Canonical Reference

**Status**: canonical (cited by `idd-*` + `spectra-*` skills since v2.43.0)
**Source principle**: [IC_R011](https://github.com/kiki830621/ai_martech_global_scripts/issues/516) — Commercial Project Low-Bar Issue Filing
**Filing trigger**: [kiki830621/ai_martech_global_scripts#525](https://github.com/kiki830621/ai_martech_global_scripts/issues/525) (sub-issue of #523 systematic plugin alignment)

---

## Purpose

Every IDD lifecycle moment that involves **deliberation** or **manual reproduction** SHALL surface tangential discoveries (sister bugs, observed friction, deferred work, out-of-scope user mentions) via a standardized AskUserQuestion 3-option checkpoint, preventing audit-trail loss into conversation.

This document is the **canonical mechanical anchor** that every alignment-eligible skill cites. Without it, each skill's implementation drifts in:

- AskUserQuestion option labels (`file all` vs `file everything`)
- Heuristic trigger phrasing (different `grep` patterns for "sister bug")
- Audit-trail format (Markdown section vs comment vs body PATCH)
- Skip rollback semantics (env var name / scope)

**Single source of truth → cross-skill consistency mechanically guaranteed.**

---

## 1. The 3-Option AskUserQuestion Structure (Canonical)

When a skill surfaces tangential discoveries, present them via **AskUserQuestion** with these EXACT three options:

```
question: "Found N tangential observation(s). File as follow-up issues?"
options:
  - label: "file all"
    description: "Create one follow-up issue per item with default labels (confidence:confirmed, priority:P3) + source link to this {issue|plan|PR}"
  - label: "file selected"
    description: "Show numbered checklist for cherry-pick"
  - label: "skip"
    description: "Don't file. Audit-trail line documenting reason will be added to {plan|close summary|diagnosis}"
```

### Rationale for these specific labels

- **`file all`** — default for happy-path (everything verifiable, user just confirms)
- **`file selected`** — user wants triage but not all (e.g. some are duplicates of existing issues)
- **`skip`** — explicit out, with audit trail (NOT silent skip)

**Do NOT add a 4th option** like `defer` — that's `skip with reason "deferred"`, captured in audit trail.

### "file selected" sub-prompt structure

When user picks `file selected`, follow with a numbered AskUserQuestion checklist:

```
question: "Which observations to file?"
options:
  - label: "1, 2, 3"  (each item presented separately or as multi-select)
  - label: "1 only"
  - label: "1 and 3"
  ...
```

Or use OS-native multi-select if available.

### Filing command (`file all` or `file selected`)

```bash
gh issue create \
  --repo "$GITHUB_REPO" \
  --title "[$type] $description (mid-{stage} tangential from #$NNN)" \
  --body "$BODY_WITH_SOURCE_LINK" \
  --label "$type,confidence:confirmed,priority:P3"
```

Body MUST contain `**Source**: surfaced during /{skill_name} #$NNN tangential sweep ({Step or stage})` for traceability.

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

When scanning Markdown comments / closing summaries / Diagnosis bodies for orphan mentions:

```
也有 | sister | 同樣的 | 另外 | also | additionally | related |
follow-up | follow up | deferred | future | TODO | later |
之後 | 未來 | 待 | 順便 | 我之前觀察到
```

If any matched paragraph is NOT linking to existing issue (`#NNN` cross-link absent or stale per `gh issue view`) → trigger AskUserQuestion checkpoint.

---

## 3. Default-Off Exemptions (Narrow)

Do NOT surface (would create noise vs. signal):

| Exemption | Reason |
|---|---|
| **Pure exploration / academic theory** | Route via [IC_R010](https://github.com/kiki830621/ai_martech_global_scripts/issues/509) `confidence:exploratory` separately, NOT as IC_R011 follow-up |
| **Existing issue covers** | grep-verified duplicate; reference rather than file again |
| **AI hallucinated without codebase evidence** | per MP029 verify-before-act; surface only if grep-confirmed |
| **CONSTRAINT not TODO** | deliberate non-action ("we don't support X" is a design choice, not a follow-up) |
| **Mechanical execution stages** | apply / archive / commit / ingest / debug — no deliberation phase, no checkpoint applies |

When uncertain whether an observation is pure exploration vs. verifiable concern → **default to file** (per IC_R011 cost calibration: 30s file vs. 30+ min reconstruct).

---

## 4. Audit Trail Format (Per-Skill Section)

Each skill PATCHes its own primary comment to add an audit-trail section after the checkpoint runs. Section heading varies per skill (purpose-specific) but contents are uniform.

### Per-skill heading conventions

| Skill | Audit section heading | Where it lives |
|---|---|---|
| `/idd-plan` | `### Tangential Observations (filed mid-plan, v2.42.0+ #524)` | Implementation Plan comment |
| `/idd-implement` | `### Sister Bugs Filed (mid-impl, v?.?.?+ #526)` | Implementation Complete comment |
| `/idd-close` | `### Closing Follow-ups Filed (v?.?.?+ #527)` | Closing summary comment |
| `/idd-diagnose` | `### Sister Concerns Filed (mid-diagnose, v?.?.?+ #528)` | Diagnosis comment |
| `/idd-issue` | `### Linked-Context Siblings Filed (v?.?.?+ #529)` | New issue body |
| `/spectra-discuss` | `### Tangential Observations (post-discuss, v?.?.?+ #530)` | Discussion artifact |
| `/spectra-propose` | `### Tangential Observations (post-propose, v?.?.?+ #530)` | Proposal artifact |

### Uniform contents

For each result of the AskUserQuestion checkpoint, write ONE of these lines:

| User choice | Audit line format |
|---|---|
| `file all` (N items, all filed) | `Filed: #NNN, #MMM, #PPP` |
| `file selected` (subset) | `Filed: #NNN, #MMM` <br> `Skipped (user choice): {brief description of N3, N4, N5}` |
| `skip` | `Skipped per user choice (N items: brief list of descriptions)` |
| empty surface list | `none surfaced` |
| env var skipped | `skipped (AI_LOW_BAR_ISSUE_FILING=false, per IC_R011 rollback)` |

---

## 5. Rollback Escape Hatch

Per [IC_R011 Decision 3](https://github.com/kiki830621/ai_martech_global_scripts/issues/516), the user can disable IC_R011 prompts:

### Temporary (env var)

```bash
AI_LOW_BAR_ISSUE_FILING=false /idd-plan #NNN
```

When set:
- Skill skips the AskUserQuestion checkpoint silently
- Audit trail STILL written, marked `skipped (AI_LOW_BAR_ISSUE_FILING=false, per IC_R011 rollback)`
- No filing happens

### Permanent (repo CLAUDE.md flag)

In a repo's `CLAUDE.md`, add:

```markdown
# Disable IC_R011
```

When this directive is detected (skill reads CLAUDE.md content from repo root):
- Skill silently skips checkpoint
- Repo opted out from IC_R011 default-on commercial filing
- Effectively makes the repo `personal-repo` even if heuristic A/B/C (per #522 if implemented) would classify it commercial

### Both layers active

If both env var and CLAUDE.md directive present → both honored (additive opt-out;harmless redundancy).

---

## 6. Eligibility Criteria — Which Skills Mandate This Checkpoint?

| Skill type | Strength | Reason |
|---|---|---|
| **Deliberation moments** (`/idd-plan`, `/idd-diagnose`, `/spectra-discuss`, `/spectra-propose`) | **SHALL** | These are the prime moments where tangential discoveries surface. Empty list is legitimate but step is mandatory. |
| **Manual reproduction / verify** (`/idd-implement`, `/idd-verify`) | **SHALL** | Reproduction reveals same-root-cause sister files (proven by #510 → #518 → #520 cluster). Verify already aligned via Step 5b. |
| **Closure** (`/idd-close`) | **SHOULD** (advisory) | Closing summary keyword scan; non-blocking. Closing is mostly mechanical action with text artifact — checkpoint is a soft gate. |
| **Issue creation** (`/idd-issue`) | **SHOULD** (advisory) | Light-touch: filing an issue while prompting about siblings = double prompt. Only surface if linked-context grep hits. |
| **Mechanical execution** (`/spectra-apply`, `/spectra-archive`, `/spectra-ask`, `/spectra-ingest`, `/spectra-commit`, `/spectra-debug`) | **N/A** (not applicable) | No deliberation phase. These execute pre-decided actions. |

### When in doubt about a new skill

If a future skill's category is unclear, fall back to the question:

> "Does this skill have a phase where the AI agent makes design / scope decisions vs. mechanically executing pre-decided actions?"

- Yes → SHALL or SHOULD checkpoint
- No → N/A

Add new skills to the table above (with `cross-repo:idd-plugin` tracker issue) when this question gets non-obvious.

---

## Third-Party Skill Alignment (v1.1.0+, #530)

For skills outside this plugin (e.g. `/spectra-*` skills published by `kaochenlong/spectra-app`), **direct SKILL.md modification is not available**. Instead, agents and users invoking these skills with IC_R011 alignment SHALL apply this pattern manually at the equivalent lifecycle moments:

### `/spectra-discuss` — Manual Step at end of discussion

When discussion converges to a conclusion, **before** producing the conclusion artifact:

1. AI agent reviews the discussion log for tangential observations per heuristic §2 above
2. If hits, applies AskUserQuestion 3-option per §1 above
3. Files via `gh issue create` per §1 filing command template
4. Notes filed issues in conclusion artifact under `### Tangential Observations (post-discuss)` heading per §4 conventions

**Strength**: SHALL — discussion convergence is a deliberation moment per §6 eligibility criteria.

### `/spectra-propose` — Manual Step at end of proposal drafting

When proposal artifact (spec / proposal / tasks) is drafted, **before** finalizing:

1. AI agent re-reads the drafted artifact for sister-concern markers per heuristic §2 above
2. If hits, applies AskUserQuestion 3-option per §1 above
3. Files via `gh issue create` per §1 filing command template
4. Notes filed issues in proposal under `### Tangential Observations (post-propose)` heading per §4 conventions

**Strength**: SHALL — proposal drafting is a deliberation moment per §6 eligibility criteria.

### Why manual-only for third-party skills

Direct upstream contribution would be the proper fix (file upstream PR to add the steps natively), but:
- Out-of-scope for this plugin's commit cycle (cross-plugin coordination has different governance)
- Documentation-side alignment is the immediate-value path: agents reading this doc when invoking `/spectra-*` will know to apply the pattern manually
- If spectra-* upstream adopts native IC_R011 checkpoint, this section becomes redundant + can be removed

### Eligible spectra-* skills only

Per §6 eligibility criteria, only **deliberation-moment** spectra skills need IC_R011 alignment:

- ✅ `/spectra-discuss` (deliberation)
- ✅ `/spectra-propose` (deliberation)
- ❌ `/spectra-apply` (mechanical execution — N/A)
- ❌ `/spectra-archive` (mechanical move — N/A)
- ❌ `/spectra-ask` (read-only query — N/A)
- ❌ `/spectra-ingest` (mechanical state import — N/A)
- ❌ `/spectra-commit` (mechanical commit — N/A)
- ❌ `/spectra-debug` (already a debugging workflow with own surfacing — N/A)

When invoking the N/A skills, no checkpoint applies.

---

## Citation Pattern (For Skill SKILL.md Files)

Skills citing this reference doc SHALL use this exact pattern at the top of the relevant Step section:

```markdown
### Step X.Y: {Stage-Specific Name}

**Compliance**: this step implements [IC_R011](#516) commercial low-bar filing per the canonical [`references/ic-r011-checkpoint.md`](../../references/ic-r011-checkpoint.md) pattern (3-option AskUserQuestion + audit trail + rollback hatch).

{Stage-specific procedure follows...}
```

This makes the dependency relationship explicit and lets future maintainers find the canonical doc immediately.

---

## Version History

| Version | Date | Change |
|---|---|---|
| **1.0.0** | 2026-05-03 | Initial canonical reference (sub-issue F of #523, plugin v2.43.0) |
| **1.1.0** | 2026-05-03 | Added "Third-Party Skill Alignment" section for `/spectra-discuss` + `/spectra-propose` manual application (sub-issue E of #523, [#530](https://github.com/kiki830621/ai_martech_global_scripts/issues/530), plugin v2.49.0) |

Future amendments to this doc require:
- Cross-co IC_P002 verify (5 companies + community consumers)
- Plugin version bump (minor for additions, major for breaking changes)
- Cite-back update across all consuming skills (per Citation Pattern above)
- Refresh `### Per-skill heading conventions` table when new skill aligns

---

## Related Principles

- [IC_R011](https://github.com/kiki830621/ai_martech_global_scripts/issues/516) — Commercial Project Low-Bar Issue Filing (the principle this doc mechanizes)
- [IC_R010](https://github.com/kiki830621/ai_martech_global_scripts/issues/509) — Issue Source Confidence Triage (sibling: routing of opened issues)
- [IC_R009](https://github.com/kiki830621/ai_martech_global_scripts/blob/main/00_principles/docs/en/part1_principles/CH06_integration_collaboration/rules/IC_R009_bidirectional_traceability.qmd) — Bidirectional Commit-Issue Traceability (sister: closure discipline)
- [MP029](https://github.com/kiki830621/ai_martech_global_scripts/blob/main/00_principles/docs/en/part1_principles/CH00_meta/MP029_no_fake_information.qmd) — verify before file (do not surface AI-hallucinated concerns)
- [MP155](https://github.com/kiki830621/ai_martech_global_scripts) — Minimize Human Input (orthogonal: MP155 minimizes user input;IC_R011 maximizes audit trail completeness)

## Reference Implementations

- [`skills/idd-plan/SKILL.md`](../skills/idd-plan/SKILL.md) — Step 2.5 Tangential Observations Sweep (v2.42.0, #524)
- [`skills/idd-close/SKILL.md`](../skills/idd-close/SKILL.md) — Step 0 supersession check (v2.41.0, #515)

Future implementations will be added here as sub-issues (#526–#530) land.
