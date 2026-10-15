## Purpose

Defines how `/idd-edit --correct` replaces content in an issue comment or issue body that the user has confirmed to be wrong, so that downstream readers (humans and AI sessions) stop inheriting the error. It also fixes which regions can never be corrected and requires every other IDD skill to propose corrections rather than apply them.

## ADDED Requirements

### Requirement: /idd-edit --correct SHALL replace a bounded region after explicit confirmation

The `/idd-edit` skill SHALL accept a `--correct` mode whose target is either a comment (`comment:<id>`) or an issue body (`issue:<N>`). For a comment target the invocation SHALL carry exactly one of `--scope whole-comment` or `--section <heading>`. For an issue-body target the invocation SHALL carry `--section <heading>`; `--scope whole-comment` and any whole-body scope SHALL be refused with exit code 3. In every `/idd-edit` mode a `--section` value SHALL be a markdown heading line (one to six `#`, whitespace, then the title); any other value SHALL be refused with exit code 2. A `--correct` invocation without replacement text (`--body` or a non-empty `--body-file`) SHALL be refused with exit code 2. Before the preview the skill SHALL run `gh-egress.sh check` on the composed body, attesting only the logins the target already mentions (`existing-mentions`), and SHALL refuse the target as `egress` when the check fails, so a body the egress gates would reject is never confirmed or archived. The skill SHALL show the full body that would be written — composed by the helper's `compose-correction` with a placeholder in place of the backup id — then ask for confirmation with NO as the default; after confirmation, and before archiving, the same subcommand composes the body again with the placeholder and the skill SHALL refuse the target as `differs-from-preview` when the result differs from the preview; only then is the body composed with the real backup id. When the replacement text begins with the target heading line, that line SHALL NOT appear twice. The run's exit code SHALL be, first match wins: 4 when a target was refused or its write failed, 7 when a write could not be read back as sent, 9 when the user declined at least one preview, and 0 otherwise; argument errors keep parse-args' codes (2, 3, 5). The working directory SHALL be created with `mktemp -d` under `${TMPDIR:-/tmp}`, and the helper's `--body-file`/`--from-file` path gate SHALL accept files strictly below the user's own temporary directory even where it lives under `/var` (macOS), while still refusing the system and credential paths. The skill SHALL write the archive and PATCH the target only after the user confirms; a declined confirmation SHALL leave both the target and the archive directory unchanged.

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

The helper SHALL refuse a correction with exit code 6 when any of the following holds (closed list): (1) the target section — or, for `--scope whole-comment`, the whole comment — is or contains `## Current Status` (which owns the rest of the body), a heading beginning with `### Clarity Surface` or a heading nested under it, or the replacement introduces a line beginning with either (both the original and the replacement are read line by line, fenced or not, because `idd-update` and `idd-clarify` find their heading by exact line match); (2) the verbatim blocks of the original region and of the replacement are not identical as multisets; (3) for `--scope whole-comment`, the comment's opening line — its first non-blank line that is not an IDD marker, such as `## Diagnosis` — is an ATX heading the replacement does not keep as its opening line; (4) a non-blank line follows a verbatim block in the replacement directly, joining the quotation as a lazy continuation, where the original had no such line; (5) for `--section`, the replacement contains a top-level heading of the target's level or higher, or a top-level thematic break, which would split the section; (6) the replacement places a verbatim block inside a code block or an HTML block where the original did not. A verbatim block is a maximal run of consecutive lines starting with `>` in which some line contains `Original text` or the decision-template label `**Original**` (closed list of two labels). The refusal message SHALL name the protected region and the skill that owns it (`idd-update` for Current Status, `idd-clarify` for Clarity Surface) or state what the replacement must keep.

#### Scenario: Correction that would swallow a section after an unclosed fence

- **WHEN** the target section contains a fence that is never closed and `## Current Status` follows it
- **THEN** `check-correction` SHALL exit 6, because the section then runs to the end and contains `## Current Status`

#### Scenario: Whole-comment correction that drops the opening heading

- **WHEN** a comment opens with `## Diagnosis` and the whole-comment replacement does not start with that line
- **THEN** the helper SHALL exit 6

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

After a correction the replaced region SHALL end with exactly one new marker of the form `<!-- idd:edit mode="correct" backup-id="<backup-id>" date="<YYYY-MM-DD>" -->`. The marker SHALL NOT contain a filesystem path; `emit-audit-marker` SHALL refuse with exit 2 a `backup-id` value that does not match the backup id pattern. For `--scope whole-comment` the marker SHALL be the last line of the comment; for `--section` the marker SHALL be the last line of the replaced section, before the next heading of the same or higher level. Every whole-line IDD marker (`<!-- idd:… -->`, correction markers included) present in the replaced region outside a fenced or indented code block SHALL be kept once, in order, immediately before the new marker — except that for `--scope whole-comment` the markers before the comment's first text line (a dashboard comment's line 1) SHALL stay at the top — so every earlier backup id and every marker other skills look for stays; a marker the replacement already contains outside a code block SHALL NOT be repeated, and a marker inside a fenced example is text, neither carried nor counted. `compose-correction` SHALL refuse with exit 6 when the composed body would parse differently outside the replaced region, or when a marker would not start its own HTML block or would sit in a code block — the result of a replacement that leaves a fence or an HTML comment open.

#### Scenario: Replacement that leaves a fence open

- **WHEN** the replacement text ends inside an open fenced code block
- **THEN** `compose-correction` SHALL exit 6 and nothing SHALL be previewed or written

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

`/idd-comment --type errata --target-comment <id>` SHALL resolve the target comment's author. When the author is the repository OWNER or the authenticated `gh` user, the skill SHALL delegate to `/idd-edit comment:<id> --correct` with the supplied scope or section and SHALL NOT post a separate errata comment. When the author is anyone else, a bot included, the skill SHALL post the errata comment only and SHALL NOT attempt to modify the target comment. When `/idd-edit` refuses the correction, its write fails, or its arguments are rejected, the skill SHALL post the errata comment instead and state that the in-place correction did not succeed; when `/idd-edit` exits 7 (written but not confirmed) it SHALL report that and post nothing; when it exits 9 (declined) it SHALL post nothing. When the author cannot be determined, the skill SHALL post the errata comment and SHALL NOT modify the target.

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

### Requirement: Only content by the OWNER or the invoking user SHALL be correctable

A target SHALL be correctable only when its author has `author_association` `OWNER` or has the same login as the authenticated `gh` user. A bot's comment SHALL be refused: a review bot's words are a third party's, answered with `/idd-comment --type errata`. For an issue-body target the author is the issue author. Any other author SHALL be refused with exit 4, and the refusal SHALL NOT suggest `--override-user-content`, which `--correct` does not accept and which SHALL NOT change the result. When the author is neither OWNER nor a bot and the authenticated `gh` user cannot be determined, the helper SHALL exit 1 instead of guessing.

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

After the user confirms and before archiving, the skill SHALL fetch the target again and compare it byte-for-byte with the previewed text. When they differ, the skill SHALL refuse that target as changed since preview, write no archive and PATCH nothing. When either fetch — the one before the preview or the one after confirmation — fails, the skill SHALL refuse that target as `fetch-failed` and write nothing; an empty working copy SHALL never be compared, archived or written. Working copies SHALL live in a directory private to the run. After the PATCH the skill SHALL read the target back; when the read fails or differs from what was sent, the target SHALL be reported as unverified and SHALL NOT count as edited. When gh fails the PATCH itself, the target SHALL be reported as a failed write (not a refusal) and SHALL make the run exit 4.

#### Scenario: Both fetches fail

- **WHEN** `gh api` fails while fetching the target before the preview
- **THEN** the target SHALL be reported as `fetch-failed`, no archive SHALL be written, and the target SHALL be unchanged

#### Scenario: Concurrent edit during preview

- **WHEN** `idd-update` rewrites the issue body while the user is reading the preview, and the user then confirms
- **THEN** the correction SHALL be refused as changed since preview and the body SHALL keep `idd-update`'s version

### Requirement: Corrected sections SHALL stop at a thematic break or a managed heading

Section boundaries SHALL come from the pinned CommonMark parser (`markdown-it-py` 4.0.0, `scripts/requirements-egress.txt`) with the GFM table rule enabled, as in the gh-egress scanner, not from the leading characters of a line. For `--correct`, a section SHALL end at the first of: the next top-level heading of the same or a higher level (ATX or setext), the next top-level thematic break, or the next `## Current Status` or `### Clarity Surface` line outside a code or HTML block — so that separators, the audit blocks below them, and regions owned by other skills are never replaced. A line inside a fenced or indented code block or an HTML block SHALL NOT end a section. When the parser is missing or a different version, `section-replace`, `check-correction` and `compose-correction` SHALL exit 8 and change nothing.

#### Scenario: A heading inside an HTML comment

- **WHEN** the section being corrected contains a multi-line `<!--` comment with a `## hidden` line, followed by more prose
- **THEN** the section SHALL run past the comment to the next real heading, and no `-->` SHALL be left behind

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

### Requirement: Parsed arguments SHALL evaluate to exactly the given values

`parse-args` output is evaluated by the skill under bash or zsh. Every emitted value SHALL evaluate to exactly the value given: a value containing a newline, any other control character or any non-ASCII character SHALL be emitted in ANSI-C quoting, with every non-ASCII character written as its UTF-8 byte escapes so the result does not depend on the shell's locale, and every `=` SHALL be escaped (zsh expands `=cmd` at the start of a word and after `:`). A `--body-file` containing a NUL byte SHALL be refused with exit code 5. An invocation without a target, or a `--correct` whose text is empty or only whitespace, SHALL be refused with exit code 2. The skill SHALL stop when the evaluation fails.

#### Scenario: NUL byte in a body file

- **WHEN** `--body-file` names a file whose content is `x`, a NUL byte, then `;touch PWNED`
- **THEN** `parse-args` SHALL exit 5 and no command from the file SHALL run

#### Scenario: Equals sign after a colon under zsh

- **WHEN** `--body 'a:=ls'` is parsed and the output is evaluated by zsh
- **THEN** `BODY_INPUT` SHALL equal `a:=ls`
