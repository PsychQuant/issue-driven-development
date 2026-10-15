## Purpose

Defines how `/idd-edit --correct` replaces content in an issue comment or issue body that the user has confirmed to be wrong, so that downstream readers (humans and AI sessions) stop inheriting the error. It also fixes which regions can never be corrected and requires every other IDD skill to propose corrections rather than apply them.

## ADDED Requirements

### Requirement: /idd-edit --correct SHALL replace a bounded region after explicit confirmation

The `/idd-edit` skill SHALL accept a `--correct` mode whose target is either a comment (`comment:<id>`) or an issue body (`issue:<N>`). For a comment target the invocation SHALL carry exactly one of `--scope whole-comment` or `--section <heading>`. For an issue-body target the invocation SHALL carry `--section <heading>`; `--scope whole-comment` and any whole-body scope SHALL be refused with exit code 3. A `--section` value SHALL be a markdown heading line (one to six `#`, whitespace, then the title); any other value SHALL be refused with exit code 2. The skill SHALL show the full body that would be written — composed by the helper's `compose-correction` with a placeholder in place of the backup id — then ask for confirmation with NO as the default; after confirmation the same subcommand composes the written body with the real backup id. When the replacement text begins with the target heading line, that line SHALL NOT appear twice. The skill SHALL write the archive and PATCH the target only after the user confirms; a declined confirmation SHALL leave both the target and the archive directory unchanged.

#### Scenario: Section flag that is not a heading

- **WHEN** a user invokes `/idd-edit comment:1 --correct --section "Expected" --body-file fixed.md`
- **THEN** the parser SHALL exit 2 and nothing SHALL be fetched or written

#### Scenario: Comment section corrected after confirmation

- **WHEN** a user invokes `/idd-edit comment:5805214375 --correct --section "### Strategy" --body-file new.md --reason "backup path was wrong"` and confirms the preview
- **THEN** the skill SHALL archive the comment's prior full text, replace only the `### Strategy` section with the content of `new.md`, and exit 0

#### Scenario: Issue body whole-scope refused

- **WHEN** a user invokes `/idd-edit issue:351 --correct --scope whole-comment --body "..."`
- **THEN** the helper SHALL exit 3 with a message stating that issue-body corrections require `--section <heading>`, and no archive file SHALL be created

#### Scenario: Confirmation declined

- **WHEN** a user invokes a valid `--correct` command and answers NO at the preview
- **THEN** the target SHALL be unchanged, no file SHALL be created under the archive directory, and the skill SHALL report that nothing was changed

### Requirement: Protected regions SHALL NOT be corrected

The helper SHALL refuse a correction with exit code 6 when either of the following holds: (1) the target section — or, for `--scope whole-comment`, the whole comment — is or contains `## Current Status`, a heading beginning with `### Clarity Surface`, or any heading nested inside `## Current Status`, or the replacement introduces such a heading (a line inside a code block of the original is not a heading; a matching line anywhere in the replacement, fenced or not, is refused, because `idd-update` and `idd-clarify` find their heading by exact line match); (2) the verbatim blocks of the original region and of the replacement are not identical as multisets. A verbatim block is a maximal run of consecutive lines starting with `>` in which some line contains `Original text` or the decision-template label `**Original**` (closed list of two labels). The refusal message SHALL name the protected region and the skill that owns it (`idd-update` for Current Status, `idd-clarify` for Clarity Surface) or state that the verbatim block must be preserved.

#### Scenario: Whole-comment correction that drops a managed region

- **WHEN** a comment contains a `### Clarity Surface` block and `/idd-edit comment:<id> --correct --scope whole-comment` supplies a replacement without it
- **THEN** the helper SHALL exit 6 naming `idd-clarify`

#### Scenario: Managed section refused

- **WHEN** a user invokes `/idd-edit issue:351 --correct --section "## Current Status" --body "..."`
- **THEN** the helper SHALL exit 6 and the message SHALL name `idd-update` as the owner of that section

#### Scenario: Managed heading nested below the target ends it

- **WHEN** `## Related` is followed by a nested `### Clarity Surface` table and a user invokes `/idd-edit issue:351 --correct --section "## Related" --body "..."`
- **THEN** only the lines between `## Related` and `### Clarity Surface` SHALL be replaced, and the `### Clarity Surface` block SHALL be unchanged

#### Scenario: Verbatim block preserved in replacement

- **WHEN** the original `## Problem` section contains an `Original text` blockquote and the replacement contains that blockquote byte-identical with a changed interpretation paragraph
- **THEN** the helper SHALL accept the replacement

##### Example: verbatim check outcomes

| Original section | Replacement | Result |
| --- | --- | --- |
| blockquote with `Original text` + paragraph A | same blockquote + paragraph B | accepted |
| blockquote with `Original text` + paragraph A | blockquote with one character changed + paragraph A | exit 6 |
| blockquote with `Original text` + paragraph A | paragraph B only | exit 6 |
| blockquote without `Original text` + paragraph A | paragraph B only | accepted |

### Requirement: Correction marker SHALL carry only the backup id and sit at the end of the replaced region

After a correction the replaced region SHALL end with exactly one new marker of the form `<!-- idd:edit mode="correct" backup-id="<backup-id>" date="<YYYY-MM-DD>" -->`. The marker SHALL NOT contain a filesystem path; `emit-audit-marker` SHALL refuse with exit 2 a `backup-id` value that does not match the backup id pattern. For `--scope whole-comment` the marker SHALL be the last line of the comment; for `--section` the marker SHALL be the last line of the replaced section, before the next heading of the same or higher level. Correction markers already present in the replaced region SHALL be kept, in their order, immediately before the new marker, so every earlier backup id stays reachable.

#### Scenario: Second correction of the same section

- **WHEN** a section that already ends with a correction marker for backup id A is corrected again and archived as backup id B
- **THEN** the section SHALL end with the marker for A followed by the marker for B, and B's marker SHALL be the last line of the section

#### Scenario: Section marker survives a later idd-update

- **WHEN** a body section `## Expected` is corrected and `/idd-update` later rewrites `## Current Status`
- **THEN** the correction marker SHALL still be present, because it sits inside `## Expected` and not in the managed zone

#### Scenario: Marker contains no path

- **WHEN** any correction completes
- **THEN** the new marker SHALL match `backup-id="(comment|issue)-[0-9]+(-body)?-[0-9]{8}T[0-9]{6}Z(-[0-9]+)?"` and SHALL NOT contain the character `/`

### Requirement: Skills that detect errors SHALL propose corrections, not apply them

`idd-verify`, `idd-diagnose`, and `idd-reorganize` SHALL, when their analysis shows that a statement already published in the issue body or an issue comment is wrong, add a `### Proposed Corrections` block to their own report. Each entry SHALL name the target (`comment:<id>` or `issue:<N>`), the section heading, a one-line statement of what is wrong, and the exact `/idd-edit ... --correct` command. In attended mode the skill SHALL ask the user, per entry, whether to run the command now; in unattended mode the skill SHALL only list the entries and SHALL NOT invoke `/idd-edit`. These skills SHALL NOT write to the archive or PATCH the target themselves.

#### Scenario: Unattended verify lists but does not apply

- **WHEN** `/idd-verify` runs under the unattended contract and finds that the diagnosis comment names the wrong root-cause file
- **THEN** the verify report SHALL contain a `### Proposed Corrections` entry with the `/idd-edit comment:<id> --correct --section "### Root Cause / Analysis"` command, and the diagnosis comment SHALL be unchanged

#### Scenario: Attended diagnose applies after the user agrees

- **WHEN** `/idd-diagnose` in attended mode proposes one correction and the user selects "run now"
- **THEN** the skill SHALL invoke `/idd-edit` with that command, and `/idd-edit` SHALL still show its own preview and confirmation

### Requirement: idd-comment errata SHALL route by comment author

`/idd-comment --type errata --target-comment <id>` SHALL resolve the target comment's author. When the author is the repository OWNER or the authenticated `gh` user, the skill SHALL delegate to `/idd-edit comment:<id> --correct` with the supplied scope or section and SHALL NOT post a separate errata comment. When the author is anyone else, a bot included, the skill SHALL post the errata comment only and SHALL NOT attempt to modify the target comment.

#### Scenario: Own comment corrected in place

- **WHEN** a user runs `/idd-comment #351 --type errata --target-comment 5805214375 --section "### Strategy" --body-file fixed.md` and comment 5805214375 is OWNER-authored
- **THEN** no new comment SHALL be posted and `/idd-edit comment:5805214375 --correct --section "### Strategy"` SHALL run with its preview and confirmation

#### Scenario: Collaborator comment left untouched

- **WHEN** the errata target comment was authored by a collaborator who is neither OWNER nor the authenticated `gh` user, or by a bot
- **THEN** the skill SHALL post the errata comment, SHALL NOT call `/idd-edit`, and the target comment SHALL be unchanged

### Requirement: Correction targets SHALL be resolved one per iteration

`parse-args` SHALL refuse with exit 2 an invocation that combines an `issue:<N>` target with any other target, or that names more than one `issue:<N>` target, and SHALL refuse with exit 3 a `--correct` invocation carrying both `--scope` and `--section`. Each target SHALL be processed as its own iteration whose archive kind, PATCH endpoint and verification are derived from that target, never from state set by another target.

#### Scenario: Mixed targets refused

- **WHEN** a user invokes `/idd-edit issue:351 comment:5 --correct --section "## Expected" --body x`
- **THEN** the helper SHALL exit 2 and nothing SHALL be archived or PATCHed

#### Scenario: Issue-only correction runs

- **WHEN** a user invokes `/idd-edit issue:351 --correct --section "## Expected" --body-file fixed.md` and confirms
- **THEN** exactly one iteration SHALL run, archive kind `issue`, PATCH through the issue-edit path, and the report SHALL show `edited: 1`

### Requirement: Only the invoking user's own content SHALL be correctable

A target SHALL be correctable only when its author has `author_association` `OWNER` or has the same login as the authenticated `gh` user. A bot's comment SHALL be refused: a review bot's words are a third party's, answered with `/idd-comment --type errata`. For an issue-body target the author is the issue author. Any other author SHALL be refused with exit 4, and the refusal SHALL NOT suggest `--override-user-content`, which `--correct` does not accept.

#### Scenario: Maintainer's own comment in an organization repository

- **WHEN** the target comment's author is `kiki830621` with `author_association` `MEMBER` and the authenticated `gh` user is `kiki830621`
- **THEN** the author gate SHALL pass

#### Scenario: Review bot comment

- **WHEN** the target comment was written by `coderabbitai[bot]`
- **THEN** the helper SHALL exit 4 and the refusal SHALL point to `/idd-comment --type errata`

#### Scenario: Issue opened by an outside reporter

- **WHEN** a user invokes `/idd-edit issue:42 --correct --section "## Actual" ...` and issue 42 was opened by a non-bot user who is neither OWNER nor the authenticated user
- **THEN** the helper SHALL exit 4 and the issue body SHALL be unchanged

### Requirement: The target SHALL be re-read after confirmation

After the user confirms and before archiving, the skill SHALL fetch the target again and compare it byte-for-byte with the previewed text. When they differ, the skill SHALL refuse that target as changed since preview, write no archive and PATCH nothing. When either fetch — the one before the preview or the one after confirmation — fails, the skill SHALL refuse that target as `fetch-failed` and write nothing; an empty working copy SHALL never be compared, archived or written.

#### Scenario: Both fetches fail

- **WHEN** `gh api` fails while fetching the target before the preview
- **THEN** the target SHALL be reported as `fetch-failed`, no archive SHALL be written, and the target SHALL be unchanged

#### Scenario: Concurrent edit during preview

- **WHEN** `idd-update` rewrites the issue body while the user is reading the preview, and the user then confirms
- **THEN** the correction SHALL be refused as changed since preview and the body SHALL keep `idd-update`'s version

### Requirement: Corrected sections SHALL stop at a thematic break or a managed heading

For `--correct`, a section SHALL end at the first of: the next heading of the same or a higher level, the next line consisting of `---`, or the next `## Current Status` or `### Clarity Surface` heading — so that separators, the audit blocks below them, and regions owned by other skills are never replaced. A line inside a fenced or indented code block SHALL NOT end a section; code block ranges SHALL come from the pinned CommonMark parser (`markdown-it-py` 4.0.0, `scripts/requirements-egress.txt`), and when that parser is missing or a different version the helper SHALL refuse with exit 1 and change nothing.

#### Scenario: A comment line inside a fence

- **WHEN** the section being corrected contains a fenced code block with the lines `# a shell comment` and `---`, followed by more prose before the next heading
- **THEN** the whole section, the fence and the prose after it included, SHALL be replaced, and the next heading SHALL remain

#### Scenario: Last section before the separator

- **WHEN** `## Related` is followed by `---`, `### Linked-Context Siblings` and `---`, and `## Related` is corrected
- **THEN** both `---` lines and the `### Linked-Context Siblings` block SHALL remain in the result

### Requirement: idd-update SHALL rebuild Key Decisions from current comments

`idd-update` SHALL derive `### Key Decisions` from the comments as they currently read on every run, instead of keeping every earlier entry, so that a decision corrected at its source disappears from the summary on the next run.

#### Scenario: Corrected decision leaves the summary

- **WHEN** a Diagnosis comment that stated a decision is corrected with `/idd-edit --correct` and `/idd-update` runs afterwards
- **THEN** `### Key Decisions` SHALL NOT contain the corrected statement
