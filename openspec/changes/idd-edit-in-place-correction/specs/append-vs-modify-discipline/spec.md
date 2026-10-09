## MODIFIED Requirements

### Requirement: Every modify-action SHALL declare a scope category

Every IDD plugin action that modifies existing artifacts (issue bodies, comments, files, state fields) SHALL declare exactly one scope category from the canonical 8-category enumeration. The category declaration SHALL appear in the action's SKILL.md normative description as an inline note of the form `(category: <name>)` or `(category: <name>, scope: <identifier>)`. Actions without a declared category SHALL be treated as `(undeclared)` and SHALL be refused per the default-refuse requirement.

#### Scenario: Action declares scope in SKILL.md

- **WHEN** a plugin author writes a new skill that modifies an issue body's `## Current Status` section
- **THEN** the SKILL.md modify-action description SHALL include an inline note `(category: bounded-section-replace, scope: "## Current Status")`

#### Scenario: Action without declared scope

- **WHEN** a skill executes a modify-action whose SKILL.md description has no `(category: ...)` inline note
- **THEN** the action SHALL be refused at runtime with error message citing the missing declaration and pointing to `plugins/issue-driven-dev/rules/append-vs-modify.md`

### Requirement: Undeclared modify-actions SHALL be refused (default-refuse)

Modify-actions not classified into one of the 8 canonical categories SHALL be refused by both (a) the skill spec gate (skill author's responsibility) and (b) future tooling-layer enforcement (out of scope for this change but reserved as enforcement surface). The default-refuse SHALL apply regardless of which actor (AI or human user) invokes the action.

#### Scenario: Raw bash sed substitution with no scope declaration

- **WHEN** a skill executes `sed -i 's|X|Y|' issue-body.md` followed by `gh issue edit --body ...` without declaring scope category
- **THEN** the action SHALL be refused at skill review time (analyzer / dogfood) with the rationale that the substitution has no bounded scope

#### Scenario: Actor identity does not exempt scope requirement

- **WHEN** a user explicitly invokes a skill that performs a modify-action without declared scope
- **THEN** the action SHALL be refused with the same error as AI invocation; actor identity SHALL NOT serve as exemption

### Requirement: /idd-edit SHALL refuse modifications to user-authored comments

The `/idd-edit` skill SHALL refuse modifications targeting comments authored by users whose `author_association` is not `OWNER` and who are not in the known-bot allowlist (`github-actions[bot]`, `dependabot[bot]`, and other repo-configured bots). This protection SHALL apply to all modes (`--append`, `--prepend-note`, `--replace`, `--correct`). For `--append`, `--prepend-note`, and `--replace`, invocations targeting user-authored comments SHALL be refused unless the caller provides `--override-user-content` flag together with `--reason="<rationale>"` documenting the explicit decision to modify user content. For `--correct`, no override SHALL exist: the parser SHALL refuse the combination of `--correct` and `--override-user-content` with exit code 2, and a `--correct` invocation targeting a user-authored comment SHALL be refused with exit code 4. This requirement is the comment-level instance of the `verbatim-preserve` category, aligned with IC_R007 (verbatim source preservation).

#### Scenario: idd-edit targets user-authored comment

- **WHEN** a user invokes `/idd-edit comment:NNN --replace --scope whole-comment --body "..."` and comment NNN was authored by a non-OWNER user (e.g. an external collaborator)
- **THEN** the skill SHALL exit with non-zero status and error message "Refuse: comment NNN was authored by <user> (non-OWNER, non-bot) and is verbatim-preserve per IC_R007; pass --override-user-content --reason='...' to explicitly modify user content"

#### Scenario: idd-edit targets bot-authored comment

- **WHEN** a user invokes `/idd-edit comment:NNN --append --body "..."` and comment NNN was authored by `github-actions[bot]`
- **THEN** the skill SHALL proceed; bot-authored comments are not subject to the verbatim-preserve refusal

#### Scenario: idd-edit override of user-authored comment

- **WHEN** a user invokes `/idd-edit comment:NNN --replace --scope whole-comment --body "..." --override-user-content --reason="Reformatted at original author's email request 2026-05-25"`
- **THEN** the skill SHALL proceed with the override and SHALL append an audit marker to the comment recording the override + reason + timestamp

#### Scenario: Correction of a collaborator comment has no override

- **WHEN** a user invokes `/idd-edit comment:NNN --correct --scope whole-comment --body "..." --override-user-content --reason="..."`
- **THEN** the parser SHALL exit 2 stating that `--correct` cannot override user-authored content, and comment NNN SHALL be unchanged

## ADDED Requirements

### Requirement: Canonical category enumeration SHALL be normative

The 8 categories SHALL be: `state-field-update`, `bounded-section-replace`, `audit-block-append`, `inline-replace-before-publish`, `verbatim-preserve`, `append-only`, `free-rewrite`, `in-place-correction`. The rule file `plugins/issue-driven-dev/rules/append-vs-modify.md` SHALL contain definitions, scope boundaries, and at least two example actions per category. New categories SHALL only be added via follow-up changes that update the rule file and amend this specification.

#### Scenario: Category definitions exist in rule file

- **WHEN** a plugin contributor reads `plugins/issue-driven-dev/rules/append-vs-modify.md`
- **THEN** the file SHALL contain each of the 8 categories with definition + scope boundary + at least 2 worked example actions from existing IDD skills

##### Example: state-field-update definition shape

- **GIVEN** the category `state-field-update`
- **WHEN** a plugin contributor reads the category section
- **THEN** the section SHALL contain: (a) definition text "changes machine-readable state field (phase / timestamp / status enum / checkbox boolean), does not modify prose", (b) example actions list including `/idd-update` Current Status phase change and `/idd-clarify` status field update

### Requirement: in-place-correction SHALL replace confirmed errors only after archiving the prior version

The `in-place-correction` category SHALL cover replacing content that the user has confirmed to be wrong, in an issue body or an OWNER- or bot-authored comment, including content that would otherwise fall under `append-only` (published comments) or the issue body above the `---` separator. An action in this category SHALL (a) archive the prior full text of the target before writing, (b) obtain explicit user confirmation, (c) leave a marker that identifies the archive entry without a filesystem path, and (d) refuse the regions that remain `verbatim-preserve`. `/idd-edit --correct` SHALL be the only action declared in this category; other skills SHALL reach it by invoking `/idd-edit`.

#### Scenario: Correction declared in idd-edit

- **WHEN** a plugin contributor reads `plugins/issue-driven-dev/skills/idd-edit/SKILL.md`
- **THEN** the `--correct` mode description SHALL contain the inline note `(category: in-place-correction)`

#### Scenario: Another skill attempts a direct correction

- **WHEN** a skill other than `idd-edit` replaces published comment text to fix an error without invoking `/idd-edit --correct`
- **THEN** the action SHALL be refused at skill review time as an undeclared or misdeclared modify-action

### Requirement: verbatim-preserve SHALL cover only original-source quotations and third-party content

The `verbatim-preserve` category SHALL cover exactly two kinds of content: (1) blockquote runs that quote original source text, identified by a line containing `Original text` within the run, and (2) comments authored by non-OWNER, non-bot users. Issue-body prose written by the issue author or by an IDD skill (interpretation paragraphs, Expected, Actual, Impact) SHALL NOT be `verbatim-preserve`; it SHALL be correctable through `in-place-correction`.

#### Scenario: Interpretation paragraph is correctable

- **WHEN** the plain-language interpretation under `## Problem` is confirmed wrong and the `Original text` blockquote above it is unchanged in the replacement
- **THEN** `/idd-edit issue:<N> --correct --section "## Problem"` SHALL be accepted

#### Scenario: Original quotation is not correctable

- **WHEN** a replacement for `## Problem` alters the `Original text` blockquote
- **THEN** the correction SHALL be refused as `verbatim-preserve`

## REMOVED Requirements

### Requirement: Canonical 7-category enumeration SHALL be normative

**Reason**: The enumeration grows to 8 categories with `in-place-correction`; a requirement name that states the count would be false after this change.
**Migration**: Replaced by the ADDED requirement `Canonical category enumeration SHALL be normative`, which lists all 8 categories and keeps the same rule-file obligations.
