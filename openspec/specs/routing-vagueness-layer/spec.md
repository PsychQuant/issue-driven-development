# routing-vagueness-layer Specification

## Purpose

Defines Layer V (Vagueness Pre-check) — the requirement-clarity gate inside `idd-diagnose` that runs as Step 3.4 between Layer 1 disqualifier evaluation and Step 3.5 Complexity Assessment. Layer V uses Likert 6-point per-axis scoring (V1 vague WHAT, V4 vague ACCEPTANCE) to surface scope-small + intent-vague issues to the user via a Hybrid 3-option AskUserQuestion (`clarify now` / `proceed anyway` / `escalate to Plan`) before the AI commits to a routing tier. Audit trail is PATCHed into the Diagnosis comment regardless of trigger outcome. Effective from v2.50; no retroactive re-evaluation of pre-v2.50 diagnoses.

## Requirements

### Requirement: Vagueness Pre-check executes between Layer 1 and Layer 2

The `idd-diagnose` skill SHALL execute Vagueness Pre-check (Layer V) as Step 3.4, after Layer 1 disqualifier evaluation and before Layer 2 / Layer 3 / Layer P evaluation in Step 3.5 Complexity Assessment. Layer 1 disqualifier hits SHALL force Simple verdict and skip Layer V entirely.

#### Scenario: Layer 1 disqualifier hit forces Simple, Layer V skipped

- **WHEN** an issue's primary deliverable is narrative prose (Layer 1 disqualifier hit)
- **THEN** the skill assigns Simple verdict and skips Layer V evaluation entirely, regardless of vagueness signals in the issue body

#### Scenario: Layer V runs after Layer 1 passes

- **WHEN** an issue passes all Layer 1 disqualifiers (no narrative / ad-hoc / typo / multi-file independent markers)
- **THEN** the skill executes Step 3.4 Vagueness Pre-check before Step 3.5 Complexity Assessment

##### Example: Layer evaluation order

| Layer 1 hit | Layer V hit | Layer 2 hit | Layer 3 hit | Layer P hit | Final Verdict |
| ----------- | ----------- | ----------- | ----------- | ----------- | ------------- |
| yes         | (skipped)   | (skipped)   | (skipped)   | (skipped)   | Simple        |
| no          | yes         | yes         | yes         | (any)       | Spectra       |
| no          | yes         | no          | (any)       | (any)       | Plan via Layer V |
| no          | no          | yes         | yes         | (any)       | Spectra       |
| no          | no          | no          | (any)       | yes         | Plan          |
| no          | no          | no          | (any)       | no          | Simple        |


<!-- @trace
source: add-vagueness-layer-routing
updated: 2026-05-04
code:
  - .spectra.yaml
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - plugins/issue-driven-dev/MANIFESTO.md
  - .agents/skills/spectra-audit/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-debug/SKILL.md
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - .agents/skills/spectra-ask/SKILL.md
  - plugins/issue-driven-dev/rules/sdd-integration.md
  - CLAUDE.md
  - AGENTS.md
-->

---
### Requirement: Vagueness scoring uses Likert 6-point per axis

The Vagueness Pre-check SHALL evaluate two axes independently using a 6-point Likert scale with no neutral midpoint. Axis V1 measures "vague WHAT" (clarity of what should be done). Axis V4 measures "vague ACCEPTANCE" (clarity of completion criteria). Each axis SHALL receive a discrete integer score from 1 (completely clear) to 6 (completely opaque). Keyword matching SHALL NOT be used for scoring.

#### Scenario: Per-axis independent scoring

- **WHEN** Step 3.4 evaluates an issue
- **THEN** the skill produces two independent integer scores in the range 1-6, one for V1 and one for V4

#### Scenario: Likert scoring follows attribute-assessment rule

- **WHEN** the skill assigns a Likert score
- **THEN** the score MUST follow the anchor definitions documented in `.claude/rules/attribute-assessment.md` (or plugin built-in fallback anchors when the project rule file is absent)

##### Example: Score anchors (1-6)

| Score | Meaning              | V1 example                                                                  | V4 example                                                                |
| ----- | -------------------- | --------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| 1     | Completely clear     | "Change line 42 of foo.rs from `x = 1` to `x = 2`"                          | "Acceptance: function returns 200 status when input is valid email"       |
| 2     | Clear                | "Add a button to the login page that opens the help modal"                  | "Done when all unit tests pass and PR review approved"                    |
| 3     | Mostly clear         | "The export feature seems slow when handling 10k+ rows, optimize it"        | "Done when latency feels noticeably better"                               |
| 4     | Somewhat vague       | "Improve the menu navigation, it feels off"                                 | "Make the API response cleaner"                                           |
| 5     | Vague                | "The reports look weird, fix them"                                          | "Done when it's good enough"                                              |
| 6     | Completely opaque    | "Make this work better"                                                     | "Done when done"                                                          |


<!-- @trace
source: add-vagueness-layer-routing
updated: 2026-05-04
code:
  - .spectra.yaml
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - plugins/issue-driven-dev/MANIFESTO.md
  - .agents/skills/spectra-audit/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-debug/SKILL.md
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - .agents/skills/spectra-ask/SKILL.md
  - plugins/issue-driven-dev/rules/sdd-integration.md
  - CLAUDE.md
  - AGENTS.md
-->

---
### Requirement: Trigger threshold is per-axis ≥ 4

Layer V SHALL be considered triggered when V1 ≥ 4 OR V4 ≥ 4 (per-axis OR semantics). Both axes scoring ≤ 3 SHALL NOT trigger Layer V, and the skill proceeds directly to Layer 2 / 3 / P evaluation.

#### Scenario: V1 alone triggers Layer V

- **WHEN** V1 = 5 and V4 = 2
- **THEN** Layer V is triggered and 3-option AskUserQuestion fires

#### Scenario: Neither axis above threshold

- **WHEN** V1 = 2 and V4 = 3
- **THEN** Layer V is not triggered and Step 3.5 proceeds without user prompt

##### Example: Trigger matrix

| V1 score | V4 score | Triggered |
| -------- | -------- | --------- |
| 1        | 1        | no        |
| 3        | 3        | no        |
| 4        | 1        | yes       |
| 1        | 4        | yes       |
| 5        | 5        | yes       |
| 6        | 6        | yes       |


<!-- @trace
source: add-vagueness-layer-routing
updated: 2026-05-04
code:
  - .spectra.yaml
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - plugins/issue-driven-dev/MANIFESTO.md
  - .agents/skills/spectra-audit/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-debug/SKILL.md
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - .agents/skills/spectra-ask/SKILL.md
  - plugins/issue-driven-dev/rules/sdd-integration.md
  - CLAUDE.md
  - AGENTS.md
-->

---
### Requirement: Triggered Layer V presents Hybrid 3-option AskUserQuestion

When Layer V is triggered, the skill SHALL present an AskUserQuestion with exactly three options labelled `clarify now`, `proceed anyway`, and `escalate to Plan`. The default option (presented first) SHALL be selected based on the higher score of V1 and V4 according to the table below. The user SHALL be able to choose any of the three options regardless of the default.

| max(V1, V4) | Default option       |
| ----------- | -------------------- |
| 4           | proceed anyway       |
| 5           | clarify now          |
| 6           | escalate to Plan     |

#### Scenario: V=4 default is proceed anyway

- **WHEN** Layer V triggers with V1 = 4 and V4 = 2
- **THEN** the AskUserQuestion lists `proceed anyway` as the first option

#### Scenario: V=6 default is escalate to Plan

- **WHEN** Layer V triggers with V1 = 6 and V4 = 6
- **THEN** the AskUserQuestion lists `escalate to Plan` as the first option, but the user remains able to choose `proceed anyway` or `clarify now`

#### Scenario: Mixed scores use the maximum

- **WHEN** Layer V triggers with V1 = 4 and V4 = 6
- **THEN** the default is determined by max(V1, V4) = 6, presenting `escalate to Plan` as the first option


<!-- @trace
source: add-vagueness-layer-routing
updated: 2026-05-04
code:
  - .spectra.yaml
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - plugins/issue-driven-dev/MANIFESTO.md
  - .agents/skills/spectra-audit/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-debug/SKILL.md
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - .agents/skills/spectra-ask/SKILL.md
  - plugins/issue-driven-dev/rules/sdd-integration.md
  - CLAUDE.md
  - AGENTS.md
-->

---
### Requirement: 3-option choices have defined effects on routing

Each user choice in the Hybrid 3-option AskUserQuestion SHALL produce a defined effect on subsequent diagnose flow:

- `clarify now` SHALL cause the skill to ask 1-3 focused clarification questions, append the user's responses to the issue body under a "Clarification (added during diagnose)" subsection via `gh issue edit`, and then re-evaluate Layer V plus Step 3.5 Complexity Assessment with the updated body
- `proceed anyway` SHALL cause the skill to skip clarification, proceed to Step 3.5 Complexity Assessment using the original issue body, and record the trigger event in the audit trail
- `escalate to Plan` SHALL cause the skill to assign verdict = `Plan` (with audit trail marker `Plan via Layer V`) and skip Step 3.5 Layer 2 / 3 / P evaluation entirely

#### Scenario: Clarify now triggers re-evaluation

- **WHEN** user selects `clarify now`
- **THEN** the skill prompts for 1-3 clarification questions, appends responses to the issue body, and re-runs Layer V + Step 3.5 with the updated body

#### Scenario: Proceed anyway records audit trail

- **WHEN** user selects `proceed anyway`
- **THEN** Step 3.5 evaluates Layer 2 / 3 / P normally, and the Diagnosis comment audit trail records `Layer V triggered (V1=N V4=M), user opted to proceed`

#### Scenario: Escalate skips Layer 2 / 3 / P

- **WHEN** user selects `escalate to Plan`
- **THEN** verdict is `Plan via Layer V`, Step 3.5 Layer 2 / 3 / P evaluation is skipped, and routing proceeds to `idd-plan` with EnterPlanMode approval gate


<!-- @trace
source: add-vagueness-layer-routing
updated: 2026-05-04
code:
  - .spectra.yaml
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - plugins/issue-driven-dev/MANIFESTO.md
  - .agents/skills/spectra-audit/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-debug/SKILL.md
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - .agents/skills/spectra-ask/SKILL.md
  - plugins/issue-driven-dev/rules/sdd-integration.md
  - CLAUDE.md
  - AGENTS.md
-->

---
### Requirement: Audit trail SHALL be appended to Diagnosis comment

The skill SHALL PATCH the just-posted Diagnosis comment to append a `### Vagueness Pre-check` section regardless of whether Layer V triggered, recording: (a) V1 and V4 scores with one-sentence reasoning each, (b) whether Layer V triggered, (c) the user's choice and resulting routing effect. When Layer V did not trigger (both axes ≤ 3), the section SHALL still be present and SHALL show the scores plus the explicit note `not triggered`.

#### Scenario: Triggered case includes user choice

- **WHEN** Layer V triggers with V1 = 5, V4 = 4 and user selects `clarify now`
- **THEN** the Diagnosis comment is PATCHed to include a `### Vagueness Pre-check` section with V1 = 5 reasoning, V4 = 4 reasoning, `triggered: yes`, `user choice: clarify now`, and `clarification appended to issue body`

#### Scenario: Untriggered case still records scores

- **WHEN** V1 = 2 and V4 = 3 (neither above threshold)
- **THEN** the Diagnosis comment is PATCHed to include a `### Vagueness Pre-check` section with both scores, reasoning, and `triggered: no — both axes ≤ 3`


<!-- @trace
source: add-vagueness-layer-routing
updated: 2026-05-04
code:
  - .spectra.yaml
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - plugins/issue-driven-dev/MANIFESTO.md
  - .agents/skills/spectra-audit/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-debug/SKILL.md
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - .agents/skills/spectra-ask/SKILL.md
  - plugins/issue-driven-dev/rules/sdd-integration.md
  - CLAUDE.md
  - AGENTS.md
-->

---
### Requirement: Unattended mode skips clarify default and proceeds

When `idd-diagnose` runs under `idd-all` unattended mode (UNATTENDED MODE directive injected), Layer V SHALL still evaluate scores and PATCH the audit trail, but SHALL NOT present AskUserQuestion. Instead, the skill SHALL automatically apply the `proceed anyway` choice and append `[Layer V: V1=N V4=M, clarify-default skipped under unattended mode, defaulting to proceed]` to the audit trail. The user SHALL be able to inspect the audit trail post-run and re-route manually if needed.

#### Scenario: Unattended mode auto-proceeds

- **WHEN** Layer V triggers with V1 = 6 under `idd-all` unattended mode
- **THEN** the skill skips AskUserQuestion, applies `proceed anyway`, and records `[Layer V: V1=6 V4=N, clarify-default skipped under unattended mode, defaulting to proceed]` in the audit trail

#### Scenario: Attended mode preserves AskUserQuestion

- **WHEN** Layer V triggers with V1 = 6 under attended mode (no UNATTENDED MODE directive)
- **THEN** the skill presents AskUserQuestion with `escalate to Plan` as the default option


<!-- @trace
source: add-vagueness-layer-routing
updated: 2026-05-04
code:
  - .spectra.yaml
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - plugins/issue-driven-dev/MANIFESTO.md
  - .agents/skills/spectra-audit/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-debug/SKILL.md
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - .agents/skills/spectra-ask/SKILL.md
  - plugins/issue-driven-dev/rules/sdd-integration.md
  - CLAUDE.md
  - AGENTS.md
-->

---
### Requirement: Routing parsers SHALL recognize Plan via Layer V verdict

Routing parsers in `idd-implement` (Step 2.5) and `idd-all` (Phase 3) SHALL recognize verdict text `Plan` regardless of trailing markers like `via Layer V`. Verdict matching SHALL extract the canonical tier (Simple / Plan / Spectra) by treating any trailing parenthetical or "via X" suffix as informational metadata, not a separate verdict value.

#### Scenario: Parser strips Layer V suffix

- **WHEN** the Diagnosis comment contains `### Complexity\nPlan via Layer V`
- **THEN** the routing parser in `idd-implement` and `idd-all` returns canonical tier = `Plan` and routes to `idd-plan` accordingly

#### Scenario: Backward compat with bare verdicts preserved

- **WHEN** the Diagnosis comment contains `### Complexity\nPlan` (without suffix)
- **THEN** parsers behave identically to existing v2.36+ behavior


<!-- @trace
source: add-vagueness-layer-routing
updated: 2026-05-04
code:
  - .spectra.yaml
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - plugins/issue-driven-dev/MANIFESTO.md
  - .agents/skills/spectra-audit/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-debug/SKILL.md
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - .agents/skills/spectra-ask/SKILL.md
  - plugins/issue-driven-dev/rules/sdd-integration.md
  - CLAUDE.md
  - AGENTS.md
-->

---
### Requirement: Backward compatibility with pre-Layer V diagnoses

Diagnoses written before v2.50 (without Layer V evaluation) SHALL NOT be retroactively re-evaluated or flagged. Existing `Simple` / `Plan` / `Spectra` / `SDD-warranted` verdicts SHALL remain valid. Layer V evaluation SHALL apply only to diagnoses created on or after v2.50.

#### Scenario: Pre-v2.50 Simple verdict unchanged

- **WHEN** an issue closed before v2.50 has Diagnosis comment with `### Complexity\nSimple`
- **THEN** the verdict remains valid and no retroactive Layer V evaluation is performed

<!-- @trace
source: add-vagueness-layer-routing
updated: 2026-05-04
code:
  - .spectra.yaml
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - plugins/issue-driven-dev/MANIFESTO.md
  - .agents/skills/spectra-audit/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
  - .agents/skills/spectra-debug/SKILL.md
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - .agents/skills/spectra-ask/SKILL.md
  - plugins/issue-driven-dev/rules/sdd-integration.md
  - CLAUDE.md
  - AGENTS.md
-->