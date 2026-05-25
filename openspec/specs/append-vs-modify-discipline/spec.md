# append-vs-modify-discipline Specification

## Purpose

Defines the action-scoped modify discipline that governs every IDD plugin action that modifies existing artifacts (issue bodies, comments, files, state fields). Every modify-action SHALL declare exactly one scope category from a canonical 7-category enumeration (`state-field-update`, `bounded-section-replace`, `audit-block-append`, `inline-replace-before-publish`, `verbatim-preserve`, `append-only`, `free-rewrite`). Undeclared modify-actions SHALL be refused at runtime regardless of actor identity (default-refuse), and `/idd-edit --replace` SHALL require an explicit `--scope` or `--section` flag. The discipline also defines authoritative-source resolution for checklist gates (Implementation Complete > Current Status > top-level Todo/Tasks/Checklist) with a legacy-scan fallback for pre-discipline issues, plus retroactive category labeling of existing IDD skills. Sourced from change `add-action-scoped-modify-discipline`.

**Implementation status (v2.75.0)**: discipline declared at spec level + runtime enforcement landed for ALL categories. Runtime gates for `bounded-section-replace` (`/idd-update` REPLACE + `/idd-edit --replace --scope`/`--section` per R4), `state-field-update` (`/idd-clarify` status mutation, `spectra task done`), `audit-block-append` (5 IC_R011 PATCH sites), `inline-replace-before-publish` (`/idd-close` Step 3.5), `verbatim-preserve` (`/idd-edit` R5 author-check + override pathway), Path C authoritative-source gate logic across 4 gate sites. **`/idd-edit` Requirements 4 + 5 runtime gates landed via [#154](https://github.com/PsychQuant/issue-driven-development/issues/154)** through extracted helper `.claude/scripts/idd-edit-helper.sh` (parse-args / validate-target / section-replace subcommands) with 13 unit-test fixtures at `.claude/scripts/tests/idd-edit/` — closes R1/R2/R3 bash-inline parser bug class observed on PR #153.

## Requirements

### Requirement: Every modify-action SHALL declare a scope category

Every IDD plugin action that modifies existing artifacts (issue bodies, comments, files, state fields) SHALL declare exactly one scope category from the canonical 7-category enumeration. The category declaration SHALL appear in the action's SKILL.md normative description as an inline note of the form `(category: <name>)` or `(category: <name>, scope: <identifier>)`. Actions without a declared category SHALL be treated as `(undeclared)` and SHALL be refused per the default-refuse requirement.

#### Scenario: Action declares scope in SKILL.md

- **WHEN** a plugin author writes a new skill that modifies an issue body's `## Current Status` section
- **THEN** the SKILL.md modify-action description SHALL include an inline note `(category: bounded-section-replace, scope: "## Current Status")`

#### Scenario: Action without declared scope

- **WHEN** a skill executes a modify-action whose SKILL.md description has no `(category: ...)` inline note
- **THEN** the action SHALL be refused at runtime with error message citing the missing declaration and pointing to `plugins/issue-driven-dev/rules/append-vs-modify.md`


<!-- @trace
source: add-action-scoped-modify-discipline
updated: 2026-05-25
code:
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - plugins/issue-driven-dev/MANIFESTO.md
  - .agents/skills/spectra-archive/SKILL.md
  - plugins/issue-driven-dev/rules/append-vs-modify.md
  - plugins/issue-driven-dev/skills/idd-clarify/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - plugins/issue-driven-dev/skills/idd-verify/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
-->

---
### Requirement: Undeclared modify-actions SHALL be refused (default-refuse)

Modify-actions not classified into one of the 7 canonical categories SHALL be refused by both (a) the skill spec gate (skill author's responsibility) and (b) future tooling-layer enforcement (out of scope for this change but reserved as enforcement surface). The default-refuse SHALL apply regardless of which actor (AI or human user) invokes the action.

#### Scenario: Raw bash sed substitution with no scope declaration

- **WHEN** a skill executes `sed -i 's|X|Y|' issue-body.md` followed by `gh issue edit --body ...` without declaring scope category
- **THEN** the action SHALL be refused at skill review time (analyzer / dogfood) with the rationale that the substitution has no bounded scope

#### Scenario: Actor identity does not exempt scope requirement

- **WHEN** a user explicitly invokes a skill that performs a modify-action without declared scope
- **THEN** the action SHALL be refused with the same error as AI invocation; actor identity SHALL NOT serve as exemption


<!-- @trace
source: add-action-scoped-modify-discipline
updated: 2026-05-25
code:
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - plugins/issue-driven-dev/MANIFESTO.md
  - .agents/skills/spectra-archive/SKILL.md
  - plugins/issue-driven-dev/rules/append-vs-modify.md
  - plugins/issue-driven-dev/skills/idd-clarify/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - plugins/issue-driven-dev/skills/idd-verify/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
-->

---
### Requirement: Canonical 7-category enumeration SHALL be normative

The 7 categories SHALL be: `state-field-update`, `bounded-section-replace`, `audit-block-append`, `inline-replace-before-publish`, `verbatim-preserve`, `append-only`, `free-rewrite`. The rule file `plugins/issue-driven-dev/rules/append-vs-modify.md` SHALL contain definitions, scope boundaries, and at least two example actions per category. New categories SHALL only be added via follow-up changes that update the rule file and amend this specification.

#### Scenario: Category definitions exist in rule file

- **WHEN** a plugin contributor reads `plugins/issue-driven-dev/rules/append-vs-modify.md`
- **THEN** the file SHALL contain each of the 7 categories with definition + scope boundary + at least 2 worked example actions from existing IDD skills

##### Example: state-field-update definition shape

- **GIVEN** the category `state-field-update`
- **WHEN** a plugin contributor reads the category section
- **THEN** the section SHALL contain: (a) definition text "changes machine-readable state field (phase / timestamp / status enum / checkbox boolean), does not modify prose", (b) example actions list including `/idd-update` Current Status phase change and `/idd-clarify` status field update


<!-- @trace
source: add-action-scoped-modify-discipline
updated: 2026-05-25
code:
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - plugins/issue-driven-dev/MANIFESTO.md
  - .agents/skills/spectra-archive/SKILL.md
  - plugins/issue-driven-dev/rules/append-vs-modify.md
  - plugins/issue-driven-dev/skills/idd-clarify/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - plugins/issue-driven-dev/skills/idd-verify/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
-->

---
### Requirement: /idd-edit --replace SHALL require scope flag

**Implementation status (v2.75.0)**: landed via [#154](https://github.com/PsychQuant/issue-driven-development/issues/154). `/idd-edit` Step 1 invokes `.claude/scripts/idd-edit-helper.sh parse-args` which enforces R4 gate (exit code 3 with actionable error message). Tested by fixture `10-replace-no-scope`. SKILL.md `## Runtime gates` section documents the gate matrix.

The `/idd-edit` skill SHALL require explicit scope when invoked with `--replace` mode. The skill SHALL accept either `--scope whole-comment` (explicit acknowledgment of full-comment overwrite) OR `--section <heading-within-comment>` (limit replacement to a named subsection within the comment). Invocations of `--replace` without either flag SHALL be refused. The `--append` and `--prepend-note` modes SHALL NOT require scope flags because their scope is inherently bounded (trailing block / leading errata marker respectively).

#### Scenario: idd-edit --replace without scope flag

- **WHEN** a user invokes `/idd-edit comment:NNN --replace --body "..."` with no `--scope` and no `--section` flag
- **THEN** the skill SHALL exit with non-zero status and error message "Refuse: --replace requires --scope whole-comment OR --section <heading> (action-scoped discipline per plugins/issue-driven-dev/rules/append-vs-modify.md)"

#### Scenario: idd-edit --replace --scope whole-comment

- **WHEN** a user invokes `/idd-edit comment:NNN --replace --scope whole-comment --body "..."`
- **THEN** the skill SHALL proceed to replace the entire comment body as a `bounded-section-replace` action with explicit whole-comment scope acknowledgment

#### Scenario: idd-edit --replace --section <heading>

- **WHEN** a user invokes `/idd-edit comment:NNN --replace --section "### Sister Concerns Filed" --body "..."`
- **THEN** the skill SHALL proceed to replace only the named subsection within the comment as a `bounded-section-replace` action scoped to that subsection

#### Scenario: idd-edit --append without scope flag

- **WHEN** a user invokes `/idd-edit comment:NNN --append --body "..."`
- **THEN** the skill SHALL proceed normally; `--append` is `audit-block-append` category with inherent trailing-block scope and does not require explicit scope flag


<!-- @trace
source: add-action-scoped-modify-discipline
updated: 2026-05-25
code:
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - plugins/issue-driven-dev/MANIFESTO.md
  - .agents/skills/spectra-archive/SKILL.md
  - plugins/issue-driven-dev/rules/append-vs-modify.md
  - plugins/issue-driven-dev/skills/idd-clarify/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - plugins/issue-driven-dev/skills/idd-verify/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
-->

---
### Requirement: /idd-edit SHALL refuse modifications to user-authored comments

**Implementation status (v2.75.0)**: landed via [#154](https://github.com/PsychQuant/issue-driven-development/issues/154). `/idd-edit` Step 1.5 invokes `.claude/scripts/idd-edit-helper.sh validate-target` which enforces R5 gate (exit code 4 with actionable error message + bot allowlist via `*[bot]` glob + OWNER passthrough + override pathway). `/idd-comment` errata Template auto-call handles exit 4 with helpful manual-invocation hint (D2 decision: refuse-with-message > auto-override, aligns with IC_R007 user-authored-intent spirit). Tested by fixtures `11-non-owner-no-override` (default OVERRIDE=false) + `12-non-owner-with-override` (override-pair guard) + `13-errata-refuse-message` (override+reason succeeds).

The `/idd-edit` skill SHALL refuse modifications targeting comments authored by users whose `author_association` is not `OWNER` and who are not in the known-bot allowlist (`github-actions[bot]`, `dependabot[bot]`, and other repo-configured bots). This protection SHALL apply to all three modes (`--append`, `--prepend-note`, `--replace`). Invocations targeting user-authored comments SHALL be refused unless the caller provides `--override-user-content` flag together with `--reason="<rationale>"` documenting the explicit decision to modify user content. This requirement is the comment-level instance of the `verbatim-preserve` category, aligned with IC_R007 (verbatim source preservation).

#### Scenario: idd-edit targets user-authored comment

- **WHEN** a user invokes `/idd-edit comment:NNN --replace --scope whole-comment --body "..."` and comment NNN was authored by a non-OWNER user (e.g. an external collaborator)
- **THEN** the skill SHALL exit with non-zero status and error message "Refuse: comment NNN was authored by <user> (non-OWNER, non-bot) and is verbatim-preserve per IC_R007; pass --override-user-content --reason='...' to explicitly modify user content"

#### Scenario: idd-edit targets bot-authored comment

- **WHEN** a user invokes `/idd-edit comment:NNN --append --body "..."` and comment NNN was authored by `github-actions[bot]`
- **THEN** the skill SHALL proceed; bot-authored comments are not subject to the verbatim-preserve refusal

#### Scenario: idd-edit override of user-authored comment

- **WHEN** a user invokes `/idd-edit comment:NNN --replace --scope whole-comment --body "..." --override-user-content --reason="Reformatted at original author's email request 2026-05-25"`
- **THEN** the skill SHALL proceed with the override and SHALL append an audit marker to the comment recording the override + reason + timestamp


<!-- @trace
source: add-action-scoped-modify-discipline
updated: 2026-05-25
code:
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - plugins/issue-driven-dev/MANIFESTO.md
  - .agents/skills/spectra-archive/SKILL.md
  - plugins/issue-driven-dev/rules/append-vs-modify.md
  - plugins/issue-driven-dev/skills/idd-clarify/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - plugins/issue-driven-dev/skills/idd-verify/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
-->

---
### Requirement: Gate logic SHALL resolve authoritative source

Gate sites that check checklist completeness (`idd-close` Step 0, `idd-verify` checklist scan, `idd-update` body sync gate, `idd-implement` Step 5 Checklist Sync) SHALL resolve an `authoritative_source` by the following priority order: (1) `## Implementation Complete > ### Checklist`, (2) `## Current Status > ### Tasks`, (3) `## Todo` / `## Tasks` / `## Checklist` top-level headings. When an authoritative source exists, the gate SHALL only evaluate items in that source and SHALL treat earlier sources (Strategy, Implementation Plan) as superseded snapshots not subject to gate evaluation.

#### Scenario: Implementation Complete checklist supersedes Strategy

- **WHEN** an issue body contains both `## Strategy` (with unchecked items) and `## Implementation Complete > ### Checklist` (with all items checked)
- **THEN** the gate SHALL evaluate only the `## Implementation Complete > ### Checklist` and SHALL pass (Strategy is superseded snapshot)

#### Scenario: Multiple authoritative source candidates with different priorities

- **WHEN** an issue body contains both `## Current Status > ### Tasks` and `## Implementation Complete > ### Checklist`
- **THEN** the gate SHALL choose `## Implementation Complete > ### Checklist` per priority order, ignoring `## Current Status > ### Tasks`


<!-- @trace
source: add-action-scoped-modify-discipline
updated: 2026-05-25
code:
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - plugins/issue-driven-dev/MANIFESTO.md
  - .agents/skills/spectra-archive/SKILL.md
  - plugins/issue-driven-dev/rules/append-vs-modify.md
  - plugins/issue-driven-dev/skills/idd-clarify/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - plugins/issue-driven-dev/skills/idd-verify/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
-->

---
### Requirement: Gate SHALL fall back to legacy scan when no authoritative source exists

When no authoritative source can be resolved (e.g., legacy issues created before this discipline shipped), the gate SHALL fall back to scanning all checklist-bearing sections (Strategy, Implementation Plan, Implementation Complete, Todo, Tasks, Checklist, Current Status > Tasks) as the pre-discipline behavior. This fallback SHALL preserve backward compatibility for issues that predate the rule.

#### Scenario: Legacy issue without Implementation Complete

- **WHEN** an issue body contains only `## Strategy` (with mixed checked/unchecked items) and no Implementation Complete section
- **THEN** the gate SHALL fall back to scanning Strategy + other legacy sections per pre-discipline behavior


<!-- @trace
source: add-action-scoped-modify-discipline
updated: 2026-05-25
code:
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - plugins/issue-driven-dev/MANIFESTO.md
  - .agents/skills/spectra-archive/SKILL.md
  - plugins/issue-driven-dev/rules/append-vs-modify.md
  - plugins/issue-driven-dev/skills/idd-clarify/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - plugins/issue-driven-dev/skills/idd-verify/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
-->

---
### Requirement: Action category labels SHALL be retroactively applied to existing skills

Existing IDD skills with modify-actions SHALL have their actions retroactively labeled with the appropriate category in SKILL.md inline notes. The retroactive labeling SHALL cover at minimum: `/idd-update` (`bounded-section-replace`), `/idd-clarify` (`state-field-update`), `/idd-close` Step 3.5 inline replace (`inline-replace-before-publish`), IC_R011 audit PATCH in each skill (`audit-block-append`), `spectra task done` checkbox flip (`state-field-update`).

#### Scenario: /idd-update SKILL.md retroactively labeled

- **WHEN** a plugin contributor reads the `/idd-update` SKILL.md after this change ships

- **THEN** the modify-action description for `## Current Status` replacement SHALL contain inline note `(category: bounded-section-replace, scope: "## Current Status")`

#### Scenario: IC_R011 audit PATCH retroactively labeled in each skill

- **WHEN** a plugin contributor reads `/idd-diagnose` SKILL.md Step 3.6 (sister concern surfacing)
- **THEN** the PATCH-to-diagnosis-comment action SHALL contain inline note `(category: audit-block-append, scope: "### Sister Concerns Filed")`

<!-- @trace
source: add-action-scoped-modify-discipline
updated: 2026-05-25
code:
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-update/SKILL.md
  - plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - plugins/issue-driven-dev/MANIFESTO.md
  - .agents/skills/spectra-archive/SKILL.md
  - plugins/issue-driven-dev/rules/append-vs-modify.md
  - plugins/issue-driven-dev/skills/idd-clarify/SKILL.md
  - plugins/issue-driven-dev/skills/idd-edit/SKILL.md
  - plugins/issue-driven-dev/skills/idd-verify/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
-->