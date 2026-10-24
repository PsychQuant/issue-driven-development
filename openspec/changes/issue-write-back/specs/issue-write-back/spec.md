## Purpose

Defines how IDD keeps an issue current while it is being discussed: each change is written back to the place that owns it (the issue body for the problem, the Diagnosis comment for the diagnosis, a new comment for new information or decisions), decided by the AI, without asking for confirmation, rewriting only the invoking user's own content.

## ADDED Requirements

### Requirement: Discussion changes SHALL be written back by kind

When a discussion of an issue changes something about it, the AI SHALL classify the change into exactly one of three kinds (closed list; no fourth kind SHALL be inferred from similarity) and write it back to that kind's place: (1) the problem itself — the question the issue asks, its scope, its `## Expected` — SHALL be written to the issue body section that holds it with `/idd-edit issue:<N> --correct --section <heading>`; (2) the diagnosis — root cause, strategy, routing — SHALL be written to the Diagnosis comment section that holds it with `/idd-edit comment:<id> --correct --section <heading>`; (3) new information, a decision, or the course of the discussion SHALL be posted as a new comment with `/idd-comment` of the matching type (`decision`, `note`, `question`, `link`). A change that belongs to both (1) and (2) SHALL be written to both places. The `Original text` quotation of the issue body SHALL NOT be changed. The write-back SHALL happen during the discussion, not after it ends.

#### Scenario: Scope widened in a session

- **WHEN** the user says in a session that issue #N must also cover case Y, and the issue body was opened by the user
- **THEN** the AI SHALL run `/idd-edit issue:N --correct --section "## Expected"` with the widened text and SHALL NOT post a new comment for it

##### Example: Routing by kind

| Change raised in the discussion | Kind | Written with |
| ------------------------------- | ---- | ------------ |
| "the scope must also include Y" | problem | `/idd-edit issue:N --correct --section "## Expected"` |
| "the root cause is in b.py, not a.py" | diagnosis | `/idd-edit comment:<Diagnosis id> --correct --section "### Root Cause / Analysis"` |
| "this has to ship before Nov 1" | new information | `/idd-comment #N --type note` |
| "we chose option B" (does not change the diagnosis) | decision | `/idd-comment #N --type decision` |

### Requirement: Write-back SHALL be triggered by session discussion and by issue comments

Write-back SHALL be triggered by exactly two sources (closed list): (1) the user discussing the issue in a session, and (2) a comment on the issue by anyone, observed the next time an IDD skill reads the issue's comments or the issue comes up in a session. No real-time trigger (GitHub Action, webhook, polling) SHALL be required.

#### Scenario: Collaborator comment observed by the next skill run

- **WHEN** a collaborator comments on #N that the root cause is in `b.py`, and `/idd-plan #N` later reads the comments
- **THEN** the AI SHALL classify the comment as a diagnosis change and write it back to the Diagnosis comment, and the collaborator's comment SHALL be unchanged

### Requirement: Only the invoking user's own content SHALL be rewritten

A write-back SHALL rewrite only content the invoking user wrote, as decided by the helper's strict author check (`validate-target <id> <repo> false --correct`, exit 0). When the place a change belongs to was written by someone else, the AI SHALL instead post `/idd-comment --type errata --target-comment <id>` for a comment or `/idd-comment --type correction` for an issue body; the same applies to text in an issue body that belongs to no heading.

#### Scenario: Problem change on an issue opened by an outside reporter

- **WHEN** the problem of issue #N changes during a discussion and #N was opened by someone other than the invoking user
- **THEN** the AI SHALL post `/idd-comment #N --type correction` stating the change, and the issue body SHALL be unchanged

### Requirement: Write-back SHALL NOT ask for confirmation and SHALL be reported

The AI SHALL decide the kind and perform the write-back without asking the user for confirmation. Each write-back SHALL be reported in the conversation with its kind, its target (`issue:<N>` and section, or `comment:<id>` and section), its link, and for a `--correct` its backup id. Before every write-back the privacy review of the privacy-scrubbing rule SHALL run on the text to be written; at `enforce` a hit SHALL stop that write-back until the text is redacted, and at `warn` a hit SHALL be reported in one line.

#### Scenario: Private detail in the discussed text

- **WHEN** a diagnosis change discussed in a session contains a local home path, in a repository whose privacy level is `enforce`
- **THEN** the write-back SHALL NOT be sent until the path is removed, and the AI SHALL report that it was held back and why

### Requirement: A corrected diagnosis SHALL update the records that depend on it

When a write-back corrects the Diagnosis, the AI SHALL also correct the affected sections of the issue's Implementation Plan comment with `/idd-edit comment:<id> --correct --section <heading>`, and SHALL prepend one line to each existing verify report of the issue with `/idd-edit comment:<id> --prepend-note`, stating the date the diagnosis was corrected and linking the corrected Diagnosis comment. The findings of a verify report SHALL NOT be rewritten, because a report records the result for the head it verified.

#### Scenario: Root cause corrected after a verify round

- **WHEN** the Diagnosis root cause of #N is corrected on 2026-10-25 and #N has one Implementation Plan comment and two verify report comments, all written by the invoking user
- **THEN** the affected Implementation Plan sections SHALL be corrected, each verify report SHALL begin with one added line linking the corrected Diagnosis, and the findings of both reports SHALL be unchanged

### Requirement: /idd-edit --prepend-note SHALL skip confirmation only for the invoking user's own content

`/idd-edit --prepend-note` SHALL proceed without asking for confirmation when its target passes the helper's strict author check (`validate-target <id> <repo> false --correct` exits 0), reporting the diff and the preview instead; for any other target it SHALL ask for confirmation as before. `/idd-edit --append` and `--replace` SHALL keep asking for confirmation.

#### Scenario: Note on a collaborator's comment

- **WHEN** `/idd-edit comment:7 --prepend-note` targets a comment written by a collaborator, and the invoking user is a repository admin
- **THEN** the strict author check SHALL fail and the skill SHALL ask for confirmation with NO as the default

### Requirement: idd-diagnose SHALL correct its own Diagnosis instead of appending a correction

When the user asks `/idd-diagnose` to adjust a Diagnosis it posted, the skill SHALL rewrite the affected section of that Diagnosis comment with `/idd-edit comment:<id> --correct --section <heading>` and SHALL NOT post a separate correction comment.

#### Scenario: Strategy adjusted at Stage 1

- **WHEN** the user answers the Stage 1 question of `/idd-diagnose #N` by asking for a different strategy
- **THEN** the `### Strategy` section of the Diagnosis comment SHALL be rewritten in place and no new comment SHALL be posted for the adjustment

### Requirement: IDD SessionStart output SHALL carry the write-back reminder within five lines

The IDD SessionStart hook output SHALL include one line stating the write-back rule and naming `rules/issue-write-back.md`, and the whole IDD SessionStart output SHALL stay at five lines or fewer.

#### Scenario: Session starts

- **WHEN** a Claude Code session starts with the plugin enabled
- **THEN** the hook output SHALL contain the write-back line and SHALL have at most five lines
