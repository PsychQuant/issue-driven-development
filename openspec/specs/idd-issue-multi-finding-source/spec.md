# idd-issue-multi-finding-source Specification

## Purpose

Define a `multi-finding source mode` for the `idd-issue` skill that fans out a single source document (transcript / docx / pdf / pasted text) into multiple coordinated dispatch actions (create new issue / comment to existing / edit existing body / skip / merge), with user-driven routing decisions and structured audit trail. This capability is orthogonal to existing single-issue creation, the `idd-issue-bundle` capability (parent / blocked-by / bundle-mode), and the cross-repo `groups` mechanism: multi-finding mode handles "one source → mixed routing across new and existing issues in a single repo". Sourced from change `add-multi-finding-source-mode-to-idd-issue` (archived 2026-05-10).

## Requirements

### Requirement: idd-issue SHALL auto-detect multi-finding source and trigger multi-finding mode

The `idd-issue` skill SHALL detect during Step 1 (Read source) whether the source contains two or more independently-actionable findings. When two or more findings are detected, the skill SHALL enter multi-finding source mode and run Stages 1-4 in place of single-issue creation.

A "finding" is a paragraph-level chunk of source content that maps to a single dispatch decision (one issue creation, one comment, one body edit, one merge, or one skip).

When fewer than two findings are detected, the skill SHALL fall through to existing single-issue creation behavior unchanged (backward compatibility).

#### Scenario: Source with multiple findings auto-triggers multi-finding mode

- **WHEN** `idd-issue path/to/transcript.srt` is invoked and Stage 1 extracts 5 paragraph-level findings
- **THEN** the skill enters multi-finding mode
- **AND** Stage 2 (per-finding picker) is invoked for each of the 5 findings

#### Scenario: Source with one finding falls back to single-issue mode

- **WHEN** `idd-issue path/to/short.docx` is invoked and Stage 1 extracts only 1 finding
- **THEN** the skill SHALL NOT enter multi-finding mode
- **AND** the skill SHALL proceed with existing single-issue creation flow (current `idd-issue` behavior)

#### Scenario: Pasted text with multiple findings triggers mode

- **WHEN** `idd-issue` is invoked with pasted multi-paragraph text containing 3 distinct topics
- **THEN** Stage 1 extracts 3 findings
- **AND** multi-finding mode is triggered


<!-- @trace
source: add-multi-finding-source-mode-to-idd-issue
updated: 2026-05-10
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-comment/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - README.md
-->

---
### Requirement: idd-issue SHALL accept --multi-finding and --no-multi-finding override flags

The `idd-issue` skill SHALL accept a `--multi-finding` flag that forces multi-finding mode regardless of detected finding count, and a `--no-multi-finding` flag that disables auto-trigger and forces single-issue mode regardless of detected finding count.

The two flags SHALL be mutually exclusive: providing both SHALL cause the skill to refuse with an error message.

#### Scenario: --multi-finding forces mode for source with single detected finding

- **WHEN** `idd-issue --multi-finding source.docx` is invoked and Stage 1 detects only 1 finding
- **THEN** the skill enters multi-finding mode anyway
- **AND** Stage 2 picker is invoked for the single finding (allowing user to test extraction or use uniform pipeline)

#### Scenario: --no-multi-finding forces single-issue for multi-finding source

- **WHEN** `idd-issue --no-multi-finding source.docx` is invoked and Stage 1 extracts 5 findings
- **THEN** the skill SHALL NOT enter multi-finding mode
- **AND** the skill SHALL treat the entire source as a single issue body (existing docx-based idd-issue behavior)

#### Scenario: Both flags refuse

- **WHEN** `idd-issue --multi-finding --no-multi-finding source.docx` is invoked
- **THEN** the skill SHALL refuse with an error message stating the flags are mutually exclusive


<!-- @trace
source: add-multi-finding-source-mode-to-idd-issue
updated: 2026-05-10
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-comment/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - README.md
-->

---
### Requirement: Stage 1 Extract SHALL produce paragraph-level findings with original quotes

In multi-finding mode, Stage 1 (Extract) SHALL parse the source content and produce a list of findings. Each finding SHALL include:

1. A 1-indexed `finding_id`
2. The original text quote (verbatim, no AI rewording)
3. A 1-3 sentence AI summary describing what the finding is about

The granularity SHALL be paragraph-level by default. AI MAY merge clearly continuous content across paragraphs if it forms a single thought, and MAY split a single paragraph if it contains 2+ distinct topics.

#### Scenario: Verbatim quote preserved

- **WHEN** Stage 1 extracts a finding from a transcript paragraph containing colloquial expressions
- **THEN** the `finding_quote` field SHALL contain the exact original text
- **AND** the AI summary SHALL be separate from the quote (not a paraphrase replacing it)


<!-- @trace
source: add-multi-finding-source-mode-to-idd-issue
updated: 2026-05-10
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-comment/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - README.md
-->

---
### Requirement: Stage 2 Per-finding picker SHALL surface AI top-3 candidates and require user confirmation

For each finding, the skill SHALL:

1. Compute keyword overlap score between the finding and existing open issues in the target repo, retrieved via `gh issue list --state open --search "<noun phrases from finding>" --limit 30`
2. Score each candidate issue using: `(title overlap × 2) + (body[:300] overlap × 1)`, normalized to [0, 1]
3. Surface the top-3 highest-scoring candidates in a 4-option AskUserQuestion picker:
   - Options 1-3: top-3 candidate issues with score visible
   - Option 4 ("Other"): expands to second-level picker for [New issue / Skip / Merge with another finding / Pick free-text #N]
4. When user picks one of the top-3 (or pick free-text #N), prompt a sub-question to disambiguate routing intent:
   - `comment` (append new comment to issue)
   - `edit body` (modify issue body)
   - `update status` (call idd-update on the issue's Current Status block)
   - `skip — change my mind` (back to picker)

The skill SHALL NOT auto-dispatch based on score; routing decisions require explicit user selection.

#### Scenario: Top-3 picker shows scores

- **WHEN** Stage 2 invokes picker for a finding about "green product purchase intent"
- **AND** repo has open issues #14 (score 0.85), #17 (score 0.72), #6 (score 0.41), and others
- **THEN** AskUserQuestion shows 4 options: `[#14 (0.85)] [#17 (0.72)] [#6 (0.41)] [Other]`

#### Scenario: User picks existing issue triggers intent disambiguation

- **WHEN** user picks `#14 (0.85)`
- **THEN** a sub-AskUserQuestion appears: `Finding goes to #14. What action? [comment] [edit body] [update status] [skip — change my mind]`
- **AND** only after intent is confirmed does the routing decision get recorded

#### Scenario: Other expands to free-pick options

- **WHEN** user picks `[Other]`
- **THEN** a sub-AskUserQuestion appears: `[New issue] [Skip] [Merge with another finding] [Pick free-text #N]`


<!-- @trace
source: add-multi-finding-source-mode-to-idd-issue
updated: 2026-05-10
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-comment/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - README.md
-->

---
### Requirement: Stage 2 SHALL support merge with combined routing target

When user picks `[Merge with another finding]` in the picker, the skill SHALL:

1. AskUserQuestion to pick a partner finding from remaining unprocessed findings in the current run (4-option, with overflow to `[Other]` if more than 3 remain)
2. AskUserQuestion to determine the combined routing target (`#X` / `#Y` / `[New issue]` / `[Skip]`)
3. Record the merge in the JSONL audit trail with `merged_from: [partner_finding_id]`
4. Perform a single dispatch action containing both findings' content (as a combined comment / issue body)

Merge SHALL be limited to two-way (one merge target plus one partner) in this version. Three-way or higher merges SHALL be a future enhancement and SHALL NOT be supported.

#### Scenario: Two-way merge combines content into single dispatch

- **WHEN** user selects merge for finding #5
- **AND** picks finding #3 as partner
- **AND** picks `#14` as combined target with intent `comment`
- **THEN** Stage 4 dispatches a single comment to #14 containing both findings' quotes
- **AND** JSONL records: `{"finding_id": 3, "action": "comment", "issue_number": 14, "merged_from": [5], ...}`
- **AND** finding #5 has its own JSONL entry with no separate dispatch: `{"finding_id": 5, "action": "merged-into", "merged_into": 3, ...}`


<!-- @trace
source: add-multi-finding-source-mode-to-idd-issue
updated: 2026-05-10
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-comment/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - README.md
-->

---
### Requirement: Stage 3 Batch preview SHALL display full plan before any dispatch

After all per-finding decisions are made in Stage 2, the skill SHALL invoke a single AskUserQuestion presenting:

1. A table listing all N findings with their resolved actions (NEW / COMMENT / EDIT / UPDATE / SKIP / MERGED)
2. For dispatched actions, the target issue number and a short summary
3. Three primary options: `[Execute all]` / `[Edit row N]` / `[Cancel]`

When user selects `[Edit row N]`, the skill SHALL re-invoke Stage 2 picker for that specific finding only. After re-pick, return to Stage 3 preview.

When user selects `[Cancel]`, the skill SHALL exit without dispatching any action and SHALL NOT write the JSONL log.

When user selects `[Execute all]`, the skill SHALL proceed to Stage 4.

#### Scenario: Preview table shows all decisions

- **WHEN** Stage 3 is invoked for a 10-finding plan
- **THEN** the preview displays a numbered table with action types, targets, and summaries for all 10 rows

#### Scenario: Edit row re-invokes picker for that finding only

- **WHEN** user picks `[Edit row 4]` in preview
- **THEN** Stage 2 picker is re-invoked for finding #4 only
- **AND** other findings retain their existing routing decisions
- **AND** after re-pick, Stage 3 preview is shown again

#### Scenario: Cancel produces no side effects

- **WHEN** user picks `[Cancel]` in preview
- **THEN** the skill exits
- **AND** no GitHub API calls are made
- **AND** no JSONL file is written


<!-- @trace
source: add-multi-finding-source-mode-to-idd-issue
updated: 2026-05-10
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-comment/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - README.md
-->

---
### Requirement: Stage 4 SHALL dispatch with warn-continue and write JSONL audit trail

In Stage 4, the skill SHALL execute each routing decision sequentially via the appropriate `gh` command (`gh issue create` / `gh issue comment` / `gh issue edit` / no-op for skip). For each action:

1. On success, the skill SHALL append the action to the JSONL log with success metadata (issue_url, comment_url, duration_ms)
2. On failure, the skill SHALL NOT abort. The skill SHALL log the error in the JSONL `actions[i].error` field with a `retry_hint` field suggesting manual recovery, then continue to the next action.
3. After all actions complete (success or failure), the skill SHALL print a summary: `N succeeded, M failed (see jsonl), K skipped`

The skill SHALL NOT attempt rollback of successful actions when subsequent actions fail.

#### Scenario: Successful dispatch writes complete JSONL

- **WHEN** Stage 4 dispatches 5 actions and all succeed
- **THEN** JSONL file at `.claude/.idd/issue-runs/<run_id>.jsonl` contains 5 action entries
- **AND** summary prints `5 succeeded, 0 failed, 0 skipped`

#### Scenario: Mid-stream failure does not abort

- **WHEN** Stage 4 dispatches 5 actions, the 3rd fails (e.g., GitHub API rate limit)
- **THEN** actions 1, 2 are dispatched and recorded as success
- **AND** action 3 is recorded with `error: "<api error message>"` and `retry_hint`
- **AND** actions 4, 5 are still attempted and recorded
- **AND** summary prints with the failure count

##### Example: JSONL schema entry

```json
{
  "run_id": "2026-05-10T17:00:00",
  "source": "communications/recordings/0509-research.srt",
  "source_type": "pasted-text",
  "total_findings": 10,
  "actions": [
    {"finding_id": 1, "finding_quote": "Schultz scale 12 items", "action": "create", "issue_number": 50, "issue_url": "...", "duration_ms": 1234},
    {"finding_id": 3, "finding_quote": "...", "action": "comment", "issue_number": 14, "comment_url": "...", "merged_from": [5], "duration_ms": 890},
    {"finding_id": 5, "finding_quote": "...", "action": "merged-into", "merged_into": 3},
    {"finding_id": 6, "finding_quote": "...", "action": "create", "error": "GraphQL: rate limit exceeded", "retry_hint": "rerun gh issue create with same title manually"}
  ],
  "started_at": "2026-05-10T17:00:00",
  "completed_at": "2026-05-10T17:03:42",
  "succeeded": 8,
  "failed": 1,
  "skipped": 1
}
```


<!-- @trace
source: add-multi-finding-source-mode-to-idd-issue
updated: 2026-05-10
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-comment/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - README.md
-->

---
### Requirement: Each dispatched action body SHALL contain audit trail footer

Every issue body created and every comment posted via multi-finding mode SHALL contain a footer block at the end:

```markdown

<!-- @trace
source: add-multi-finding-source-mode-to-idd-issue
updated: 2026-05-10
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-comment/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - README.md
-->

---
> **Surfaced via**: /idd-issue multi-finding mode <run_id> from `<source>`
> **Run log**: `.claude/.idd/issue-runs/<run_id>.jsonl`
```

The `<source>` value SHALL be the source file path when the source is a file, or `pasted-text:<first-30-chars>` when the source is pasted text.

For body edits via `idd-edit`, the footer SHALL be appended (not replacing existing footer if any from prior multi-finding runs).

#### Scenario: Footer in created issue

- **WHEN** Stage 4 creates issue #50 from finding #1 in run `2026-05-10T17:00:00`
- **THEN** issue #50 body ends with a footer block referencing the run_id and source path
- **AND** the footer is separated from issue body content by a `---` horizontal rule

#### Scenario: Footer in comment

- **WHEN** Stage 4 posts a comment on issue #14 from finding #3
- **THEN** the comment body ends with the audit footer

---
### Requirement: idd-issue SHALL refuse multi-finding mode when --bundle-mode is also set

When the skill detects multi-finding mode would trigger AND `--bundle-mode` is set, the skill SHALL refuse the invocation with an error message stating the modes are mutually exclusive and explaining the difference (bundle = explicit ordered/unordered creation; multi-finding = source-driven mixed routing including amend existing).

#### Scenario: Bundle mode with multi-finding source refuses

- **WHEN** `idd-issue --bundle-mode ordered source.docx` is invoked and source contains 5 findings
- **THEN** the skill SHALL refuse to proceed
- **AND** SHALL emit an error message naming both modes and instructing user to pick one


<!-- @trace
source: add-multi-finding-source-mode-to-idd-issue
updated: 2026-05-10
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-comment/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - README.md
-->

---
### Requirement: idd-issue SHALL preserve all source-type adapters in multi-finding mode

The Step 1 source-type adapters (docx via che-word-mcp, pdf via che-pdf-mcp, Telegram, Apple Mail, Apple Notes, pasted text, markdown) SHALL all be supported as input sources for multi-finding mode. The mode SHALL apply uniformly regardless of source type.

For sources containing attachments (e.g., docx with images, Telegram with photos), the existing attachment-preservation rule SHALL still apply: attachments SHALL be uploaded to the attachments release per existing idd-issue Step 4 behavior, attached to the most-relevant dispatched issue (typically the one containing the finding that references the attachment in its quote).

#### Scenario: Docx source with images dispatches attachments to relevant issue

- **WHEN** Stage 1 extracts 3 findings from a docx, one of which references an embedded image
- **AND** Stage 2 routes that finding to a NEW issue
- **THEN** Stage 4 creates the new issue
- **AND** uploads the image to the attachments release
- **AND** embeds the image link in the new issue body


<!-- @trace
source: add-multi-finding-source-mode-to-idd-issue
updated: 2026-05-10
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-comment/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - README.md
-->

---
### Requirement: JSONL run log SHALL be committed to git by default

The `.claude/.idd/issue-runs/<run_id>.jsonl` files SHALL be tracked in git by default. The change SHALL update repo `.gitignore` patterns to ensure these files are not silently excluded.

This decision is intentional for cross-machine continuity: a user moving between machines (e.g., laptop ↔ remote workstation) SHALL be able to replay or audit a multi-finding run from git history alone.

#### Scenario: New jsonl file is staged in git

- **WHEN** Stage 4 completes and writes `.claude/.idd/issue-runs/2026-05-10T17:00:00.jsonl`
- **THEN** `git status` shows the new file as untracked or staged (not gitignored)


<!-- @trace
source: add-multi-finding-source-mode-to-idd-issue
updated: 2026-05-10
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-comment/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - README.md
-->

---
### Requirement: Cross-reference updates SHALL be made to atomic skills

The SKILL.md files for `idd-comment`, `idd-edit`, and `idd-update` SHALL be updated to add a "When NOT to use this skill" or "When to use idd-issue multi-finding mode instead" section, redirecting users from manually invoking these skills N times to using multi-finding mode for source-driven batch operations.

#### Scenario: idd-comment SKILL.md mentions multi-finding mode

- **WHEN** `idd-comment` SKILL.md is opened
- **THEN** it contains a cross-reference: "For batch commenting from a source document with multiple findings, use `idd-issue` multi-finding mode (auto-triggers when source contains ≥2 findings)"

#### Scenario: idd-edit and idd-update similarly cross-referenced

- **WHEN** `idd-edit` and `idd-update` SKILL.md files are opened
- **THEN** each contains an analogous cross-reference to multi-finding mode


<!-- @trace
source: add-multi-finding-source-mode-to-idd-issue
updated: 2026-05-10
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-comment/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - README.md
-->

---
### Requirement: Multi-finding mode SHALL preserve backward compatibility

Existing `idd-issue` invocations that do not trigger multi-finding mode SHALL behave identically to pre-change behavior. This includes:

- Single-text invocation (`idd-issue "text"`)
- Single-finding source file invocation
- `--bundle-mode ordered/unordered` invocations
- `--target` cross-repo / group invocations
- `--mention` invocations
- `--parent` / `--blocked-by` invocations

No existing flag, config, or behavior SHALL be deprecated, removed, or have its semantics changed by this change.

#### Scenario: Pre-change invocation produces identical output

- **WHEN** `idd-issue "test issue title"` is invoked (single text, no multi-finding trigger)
- **THEN** behavior is unchanged from pre-change: 1 issue created, no Stage 2/3/4 invocation, no JSONL log written

<!-- @trace
source: add-multi-finding-source-mode-to-idd-issue
updated: 2026-05-10
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-comment/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - README.md
-->