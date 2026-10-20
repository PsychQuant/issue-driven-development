# in-place-correction Specification

## Purpose

Defines how `/idd-edit --correct` replaces content in an issue comment or issue body that the user has confirmed to be wrong, so that downstream readers (humans and AI sessions) stop inheriting the error. It also fixes which regions can never be corrected and requires every other IDD skill to propose corrections rather than apply them.

## Requirements

### Requirement: /idd-edit --correct SHALL replace a bounded region after explicit confirmation

The `/idd-edit` skill SHALL accept a `--correct` mode whose target is either a comment (`comment:<id>`) or an issue body (`issue:<N>`). For a comment target the invocation SHALL carry exactly one of `--scope whole-comment` or `--section <heading>`. For an issue-body target the invocation SHALL carry `--section <heading>`; `--scope whole-comment` and any whole-body scope SHALL be refused with exit code 3. In every `/idd-edit` mode a `--section` value SHALL be a markdown heading line (one to six `#`, whitespace, then the title); any other value SHALL be refused with exit code 2. A `--correct` invocation without replacement text (`--body` or a non-empty `--body-file`) SHALL be refused with exit code 2. The flow SHALL run in the helper, not in skill shell code: `correct-prepare` reads the target, applies the author gate, the protected-region checks and `gh-egress.sh check` on the composed body (attesting only the logins the target already mentions), and writes the preview into a working directory private to the user; `correct-apply` runs after confirmation; `correct-discard` runs when the user declines. Before the preview `correct-prepare` SHALL check that the archive can be written (the same location checks the archive itself applies) and refuse the target as `archive` when it cannot, so a confirmed correction is not refused for a reason known in advance. `correct-prepare` SHALL require `--scrub-attested` (the skill resolves the tier per the privacy-scrubbing rule; the helper SHALL NOT default it) and SHALL print the SHA-256 of its state file as `STATE=`. Because the preview, the confirmation and the apply are separate tool calls, the run's `prepare` SHALL print `WORK=`, `PREVIEW=`, `DIFF=` and `STATE=`, and the skill SHALL pass the printed `STATE` to `apply --state` in a later call (see the requirement on runs). `apply` SHALL treat a `--state` that does not match the state file as a usage error (exit 2) without recording an outcome — it cannot tell a mistyped value from a state file changed after the preview, so a value copied again that still does not match means the preview is no longer trustworthy and the target SHALL be discarded, the run finished, and the target prepared again in a new run (a run prepares a target once) — and SHALL refuse as `differs-from-preview` when a field of the state file is malformed. `correct-apply` SHALL read the state file once, hashing and parsing the same bytes, and SHALL run the author gate and the protected-region checks again before it fetches the target the second time, refusing with the same reasons as `correct-prepare`. A replacement that is empty once a leading copy of the target heading is removed SHALL be refused with exit 2 (by `run-start` in a run); one that holds only a copy of the comment's top marker SHALL be refused as `empty`. Text outside the replaced region SHALL be written back byte for byte (line endings and the presence of a final newline included), and for `--scope whole-comment` the IDD markers at the top of the original SHALL stay at the top, a copy of them in the replacement being dropped. A body the egress gates would reject SHALL be refused as `egress` before the preview, so it is never confirmed or archived. The skill SHALL show the diff from the current text to the previewed body (its lines end at `\r\n`, `\r` or `\n`, as GitHub reads them; a lone `\r` is shown as a line end) and the full previewed body — the composed body with a placeholder in place of the backup id — then ask for confirmation with NO as the default; `correct-apply` SHALL refuse as `differs-from-preview` when any file of the working directory changed or when composing again with the placeholder no longer gives the preview, and only then composes the body with the real backup id. The working directory SHALL be removed at the end of `correct-apply` and by `correct-discard`, and `correct-apply` SHALL accept only a directory `correct-prepare` created (a direct child of the user's temporary directory with its prefix, owned by the user, closed to others; a run's `apply` accepts the working directory its own ledger names under any temporary directory, since sandboxed and unsandboxed calls see different ones). When the replacement text begins with the target heading line, that line SHALL NOT appear twice. The run's exit code SHALL be the exit code of `finish`, first match wins: 4 when a target was refused or its write failed, 7 when a write could not be read back as sent, 9 when the user declined at least one preview, and 0 otherwise; argument errors keep parse-args' codes (2, 3, 5) from `run-start`, which also exits 1 when the comments of an `#N --last` target cannot be read. Working directories SHALL be created by the helper under the user's temporary directory, and the helper's `--body-file`/`--from-file` path gate SHALL accept files strictly below the user's own temporary directory even where it lives under `/var` (macOS), while still refusing the system and credential paths; credential directories SHALL be matched without regard to letter case (macOS's default file system opens `~/.SSH` as `~/.ssh`), under both `HOME` and the account's home directory, by the path as given and as resolved (a link inside a credential directory is refused), system paths without regard to case on the resolved path, and gh's token store SHALL be refused wherever gh may keep it (`GH_CONFIG_DIR`, `$XDG_CONFIG_HOME/gh`, `~/.config/gh`), the escape hatch included. The skill SHALL write the archive and PATCH the target only after the user confirms; a declined confirmation SHALL leave both the target and the archive directory unchanged.

#### Scenario: Section flag that is not a heading

- **WHEN** a user invokes `/idd-edit comment:1 --correct --section "Expected" --body-file fixed.md`
- **THEN** the parser SHALL exit 2 and nothing SHALL be fetched or written

#### Scenario: Comment section corrected after confirmation

- **WHEN** a user invokes `/idd-edit comment:5805214375 --correct --section "### Strategy" --body-file new.md` and confirms the preview
- **THEN** the skill SHALL archive the comment's prior full text, replace only the `### Strategy` section with the content of `new.md`, and exit 0

#### Scenario: Issue body whole-scope refused

- **WHEN** a user invokes `/idd-edit issue:351 --correct --scope whole-comment --body "..."`
- **THEN** the helper SHALL exit 3 with a message stating that issue-body corrections require `--section <heading>`, and no archive file SHALL be created

#### Scenario: Confirmation declined

- **WHEN** a user invokes a valid `--correct` command and answers NO at the preview
- **THEN** the target SHALL be unchanged, no file SHALL be created under the archive directory, and the skill SHALL report that nothing was changed


<!-- @trace
source: idd-edit-in-place-correction
updated: 2026-10-20
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/README.md
-->

---
### Requirement: Protected regions SHALL NOT be corrected

The helper SHALL refuse a correction with exit code 6 when any of the following holds (closed list): (1) the target section — or, for `--scope whole-comment`, the whole comment — is or contains `## Current Status` (which owns the rest of the body), a heading beginning with `### Clarity Surface` or a heading nested under it, or the replacement introduces a line beginning with either (both the original and the replacement are read line by line, fenced or not, because `idd-update` and `idd-clarify` find their heading by exact line match); (2) the verbatim blocks of the original region and of the replacement are not identical as multisets; (3) for `--scope whole-comment`, the comment's opening line — its first non-blank line that is not an IDD marker, such as `## Diagnosis` — is an ATX heading the replacement does not keep as its opening line; (4) a non-blank line follows a verbatim block in the replacement directly, joining the quotation as a lazy continuation, where the original had no such line; (5) for `--section`, the replacement contains a top-level heading of the target's level or higher, or a top-level thematic break, which would split the section; (6) the replacement places a verbatim block inside a code block or an HTML block where the original did not. A verbatim block is a maximal run of consecutive lines starting with `>` in which some line contains `Original text`, the decision-template label `**Original**`, or the reply-template label `**Point ` (closed list of three labels; the third is a reviewer's words quoted verbatim, verify #351 round 7). The refusal message SHALL name the protected region and the skill that owns it (`idd-update` for Current Status, `idd-clarify` for Clarity Surface) or state what the replacement must keep. A verbatim block of the replaced region that the replacement keeps SHALL be written with the original's bytes, its line endings included, except that one whose lines end in a lone carriage return SHALL be written with LF, so the blank line after it is not joined to it.

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

#### Scenario: Quotation keeps its own line endings

- **WHEN** the original section holds an `Original text` blockquote with CRLF line endings and the replacement holds the same blockquote with LF line endings
- **THEN** the check SHALL accept the replacement (quotations are compared with line endings normalised) and the composed body SHALL contain the blockquote with the original's CRLF bytes


<!-- @trace
source: idd-edit-in-place-correction
updated: 2026-10-20
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/README.md
-->

---
### Requirement: Correction marker SHALL carry only the backup id and sit at the end of the replaced region

After a correction the replaced region SHALL end with exactly one new marker of the form `<!-- idd:edit mode="correct" backup-id="<backup-id>" date="<YYYY-MM-DD>" -->`, where the date is the local date, as in the other modes' markers (the backup id keeps its UTC time with `Z`); `emit-audit-marker` SHALL use the same local date. The marker SHALL NOT contain a filesystem path; `emit-audit-marker` SHALL refuse with exit 2 a `backup-id` value that does not match the backup id pattern. For `--scope whole-comment` the marker SHALL be the last line of the comment; for `--section` the marker SHALL be the last line of the replaced section, before the next heading of the same or higher level. Every whole-line IDD marker (`<!-- idd:… -->`, correction markers included) present in the replaced region outside a fenced or indented code block SHALL be kept once, in order, immediately before the new marker — except that for `--scope whole-comment` the markers before the comment's first text line (a dashboard comment's line 1) SHALL stay at the top — so every earlier backup id and every marker other skills look for stays; a marker the replacement already contains as its own HTML block outside a code block SHALL NOT be repeated (a copy inside another HTML block, such as a `<script>` or `<div>` block, is not counted, so the live marker is carried), and a marker inside a fenced example is text, neither carried nor counted. `compose-correction` SHALL refuse with exit 6 when the composed body would parse differently outside the replaced region, or when a marker it carries, adds or counts as kept would not start its own HTML block or would sit in a code block in the composed body — the result of a replacement that leaves a fence or an HTML comment open.

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


<!-- @trace
source: idd-edit-in-place-correction
updated: 2026-10-20
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/README.md
-->

---
### Requirement: Skills that detect errors SHALL propose corrections, not apply them

`idd-verify`, `idd-diagnose`, and `idd-reorganize` SHALL, when their analysis shows that a statement already published in the issue body or an issue comment is wrong, add a `### Proposed Corrections` block to their own report. Each entry SHALL name the target (`comment:<id>` or `issue:<N>`), the section heading, a one-line statement of what is wrong, and the exact `/idd-edit ... --correct` command; when the target is not the invoking user's own content, or the wrong text is in an issue body and belongs to no heading, the entry SHALL instead give `/idd-comment --type errata --target-comment <id>` for a comment or `/idd-comment --type correction` for an issue body (untitled text in the user's own comment is reachable with `--scope whole-comment`). In attended mode the skill SHALL ask the user, per entry, whether to run the command now; in unattended mode the skill SHALL only list the entries and SHALL NOT invoke `/idd-edit`. These skills SHALL NOT write to the archive or PATCH the target themselves. The posted command is a proposal collaborators can edit: a skill that runs it SHALL rebuild the arguments from its own values (the target id all digits, the section an ATX heading line) and SHALL NOT paste the published cell.

#### Scenario: Unattended verify lists but does not apply

- **WHEN** `/idd-verify` runs under the unattended contract and finds that the diagnosis comment names the wrong root-cause file
- **THEN** the verify report SHALL contain a `### Proposed Corrections` entry with the `/idd-edit comment:<id> --correct --section "### Root Cause / Analysis"` command, and the diagnosis comment SHALL be unchanged

#### Scenario: Attended diagnose applies after the user agrees

- **WHEN** `/idd-diagnose` in attended mode proposes one correction and the user selects "run now"
- **THEN** the skill SHALL invoke `/idd-edit` with that command, and `/idd-edit` SHALL still show its own preview and confirmation


<!-- @trace
source: idd-edit-in-place-correction
updated: 2026-10-20
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/README.md
-->

---
### Requirement: idd-comment errata SHALL route by comment author

`/idd-comment --type errata --target-comment <id>` SHALL resolve the target comment's author. When the author is the authenticated `gh` user, the skill SHALL delegate to `/idd-edit comment:<id> --correct --repo <the repository it checked the author in>` with the supplied scope or section and SHALL NOT post a separate errata comment. When the author is anyone else, the repository OWNER and a bot included, the skill SHALL post the errata comment only and SHALL NOT attempt to modify the target comment. When `/idd-edit` refuses the correction or its write fails (exit 4), the skill SHALL post the errata comment instead and state that the in-place correction did not succeed — summarising the correction file, except when the refusal was `egress`, where it SHALL state only that the correction was refused by the egress gates and SHALL NOT restate its content; when its arguments are rejected (exit 2, 3 or 5, which includes a correction file the path gate refused) the skill SHALL post nothing, SHALL NOT read the correction file by other means, and SHALL report the argument error; when `/idd-edit` exits 7 (written but not confirmed) it SHALL report that and post nothing; when it exits 9 (declined) it SHALL post nothing. When the author cannot be determined, the skill SHALL post the errata comment and SHALL NOT modify the target. After posting an errata comment because the in-place correction of the user's own comment did not succeed (exit 4), the skill SHALL propose `/idd-edit comment:<id> --prepend-note` pointing to the errata comment, under that skill's own preview and confirmation, unless the comment's first non-blank line is an ATX heading or an IDD marker; anyone else's comment, the OWNER's and a bot's included, SHALL receive no note (user decision 2026-10-17).

#### Scenario: Own comment corrected in place

- **WHEN** a user runs `/idd-comment #351 --type errata --target-comment 5805214375 --section "### Strategy" --correction-file fixed.md` and comment 5805214375 was written by the authenticated `gh` user
- **THEN** no new comment SHALL be posted and `/idd-edit comment:5805214375 --correct --section "### Strategy"` SHALL run with its preview and confirmation

#### Scenario: Own comment, correction refused

- **WHEN** the errata target is the user's own plain comment and `/idd-edit --correct` exits 4 with a reason other than `egress`
- **THEN** the skill SHALL post an errata comment summarising the correction and stating that the in-place correction did not succeed, then propose `/idd-edit --prepend-note` pointing to it

#### Scenario: Own comment, correction declined or unverified

- **WHEN** `/idd-edit --correct` exits 9 (declined) or 7 (written but not confirmed)
- **THEN** the skill SHALL post nothing and report the outcome

#### Scenario: Collaborator comment left untouched

- **WHEN** the errata target comment was authored by anyone other than the authenticated `gh` user — a collaborator, the repository OWNER, or a bot
- **THEN** the skill SHALL post the errata comment, SHALL NOT call `/idd-edit`, and the target comment SHALL be unchanged


<!-- @trace
source: idd-edit-in-place-correction
updated: 2026-10-20
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/README.md
-->

---
### Requirement: Correction targets SHALL be resolved one per iteration

`parse-args` SHALL refuse with exit 2 an invocation that combines an `issue:<N>` target with any other target, or that names more than one `issue:<N>` target, and SHALL refuse with exit 3 a `--correct` invocation carrying both `--scope` and `--section`. Each target SHALL be processed as its own iteration whose archive kind, PATCH endpoint and verification are derived from that target, never from state set by another target.

#### Scenario: Mixed targets refused

- **WHEN** a user invokes `/idd-edit issue:351 comment:5 --correct --section "## Expected" --body x`
- **THEN** the helper SHALL exit 2 and nothing SHALL be archived or PATCHed

#### Scenario: Issue-only correction runs

- **WHEN** a user invokes `/idd-edit issue:351 --correct --section "## Expected" --body-file fixed.md` and confirms
- **THEN** exactly one iteration SHALL run, archive kind `issue`, PATCH through the issue-edit path, and the report SHALL show `edited: 1`


<!-- @trace
source: idd-edit-in-place-correction
updated: 2026-10-20
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/README.md
-->

---
### Requirement: Only the invoking user's own content SHALL be correctable

A target SHALL be correctable only when its author has the same login as the authenticated `gh` user. The repository OWNER's content SHALL be refused when someone else runs the correction, and a bot's comment SHALL always be refused: both are a third party's words to the person running it, answered with `/idd-comment --type errata` (user decision 2026-10-17; before it, any OWNER content passed, so a collaborator with write access could rewrite the owner's words and keep the only archive on their own machine). For an issue-body target the author is the issue author — an approximation the user accepted on 2026-10-17 (text written later into someone else's issue body is not correctable in place; it is answered with `/idd-comment --type correction`). The refusal SHALL say that content written under another GitHub account of the user's is corrected by switching to that account (`gh auth switch`). Any other author SHALL be refused with exit 4, and the refusal SHALL NOT suggest `--override-user-content`, which `--correct` does not accept and which SHALL NOT change the result. Under `--correct`, when the author is not a bot and the authenticated `gh` user cannot be determined, `validate-target` SHALL exit 1 instead of guessing, and `correct-prepare` SHALL report the target as `REASON=author-unknown`. `correct-prepare` SHALL fetch the target before applying the author gate, so a target that cannot be read is reported as `fetch-failed`, not as `author-unknown`.

#### Scenario: Maintainer's own comment in an organization repository

- **WHEN** the target comment's author is `kiki830621` with `author_association` `MEMBER` and the authenticated `gh` user is `kiki830621`
- **THEN** the author gate SHALL pass

#### Scenario: The owner's comment, corrected by a collaborator

- **WHEN** the target comment's author is the repository OWNER `repo-owner` and the authenticated `gh` user is a collaborator `kiki830621`
- **THEN** the helper SHALL exit 4 and the refusal SHALL point to `/idd-comment --type errata`

#### Scenario: Review bot comment

- **WHEN** the target comment was written by `coderabbitai[bot]`
- **THEN** the helper SHALL exit 4 and the refusal SHALL point to `/idd-comment --type errata`

#### Scenario: Issue opened by an outside reporter

- **WHEN** a user invokes `/idd-edit issue:42 --correct --section "## Actual" ...` and issue 42 was opened by someone other than the authenticated user
- **THEN** the helper SHALL exit 4 and the issue body SHALL be unchanged


<!-- @trace
source: idd-edit-in-place-correction
updated: 2026-10-20
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/README.md
-->

---
### Requirement: The target SHALL be re-read after confirmation

After the user confirms and before archiving, `correct-apply` SHALL fetch the target again and compare it byte-for-byte with the previewed text. When they differ, it SHALL refuse that target as changed since preview, write no archive and PATCH nothing. When either fetch — the one before the preview or the one after confirmation — fails, the target SHALL be refused as `fetch-failed` and nothing written; an empty working copy SHALL never be compared, archived or written. Working copies SHALL live in a directory private to the run. After the PATCH `correct-apply` SHALL read the target back; when the read fails or differs from what was sent, the target SHALL be reported as unverified and SHALL NOT count as edited. Every fetch SHALL take the `body` field of the API's JSON response exactly as returned, with no newline added or removed; a response without a `body` field, or a comment whose `body` is null, SHALL be a failed fetch (an issue body may be null, which reads as empty). The read-back SHALL equal the sent body byte for byte; any other content, extra newlines included, SHALL be reported as unverified. An error after the archive is written SHALL be reported as unverified with the backup id, never as nothing changed. When gh fails the PATCH itself, `correct-apply` SHALL read the target again: when it still equals the archived text the target SHALL be reported as a failed write (not a refusal), making the run exit 4; when it differs, or cannot be read, the target SHALL be reported as unverified (exit 7), because the write may have landed.

#### Scenario: Both fetches fail

- **WHEN** `gh api` fails while fetching the target before the preview
- **THEN** the target SHALL be reported as `fetch-failed`, no archive SHALL be written, and the target SHALL be unchanged

#### Scenario: The write lands before gh reports an error

- **WHEN** gh exits non-zero for the write but the target already holds the new body
- **THEN** the target SHALL be reported as unverified (exit 7) with its backup id, not as a failed write

#### Scenario: Concurrent edit during preview

- **WHEN** `idd-update` rewrites the issue body while the user is reading the preview, and the user then confirms
- **THEN** the correction SHALL be refused as changed since preview and the body SHALL keep `idd-update`'s version


<!-- @trace
source: idd-edit-in-place-correction
updated: 2026-10-20
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/README.md
-->

---
### Requirement: Corrected sections SHALL stop at a thematic break or a managed heading

Section boundaries SHALL come from the pinned CommonMark parser (`markdown-it-py` 4.0.0, `scripts/requirements-egress.txt`) with the GFM table rule enabled, as in the gh-egress scanner, not from the leading characters of a line. For `--correct`, a section SHALL end at the first of: the next top-level ATX heading of the same or a higher level, the next top-level thematic break, or the next `## Current Status` or `### Clarity Surface` line outside a code or HTML block — so that separators, the audit blocks below them, and regions owned by other skills are never replaced. A line inside a fenced or indented code block or an HTML block SHALL NOT end a section. A setext heading inside the section being corrected, or one the replacement adds, SHALL be refused with exit 6 and reported as `REASON=setext`, not `protected`: a paragraph line over `---` is a heading to the parser and a separator to a reader, so the two disagree about where the section ends. `--replace` keeps its existing reach and replaces through a setext heading. When the `--section` heading occurs more than once outside code and HTML blocks, `section-replace`, `check-correction` and `compose-correction` SHALL exit 9 (`section-ambiguous`) and change nothing, instead of picking the first. When the parser is missing or a different version, `section-replace`, `check-correction` and `compose-correction` SHALL exit 8 and change nothing. Known limitation (user decision 2026-10-17), for issue bodies only: text that belongs to no heading — below the last thematic break of an issue body (such as the IC_R011 `**Source**` footnote), or before its first heading — cannot be reached by `--section`, and an issue body has no whole-body scope (in a comment such text is reachable with `--scope whole-comment`); a skill that finds an error there SHALL propose `/idd-comment --type correction` (an issue body has no comment id for `--type errata`) instead of `/idd-edit --correct`.

#### Scenario: A heading inside an HTML comment

- **WHEN** the section being corrected contains a multi-line `<!--` comment with a `## hidden` line, followed by more prose
- **THEN** the section SHALL run past the comment to the next real heading, and no `-->` SHALL be left behind

#### Scenario: A comment line inside a fence

- **WHEN** the section being corrected contains a fenced code block with the lines `# a shell comment` and `---`, followed by more prose before the next heading
- **THEN** the whole section, the fence and the prose after it included, SHALL be replaced, and the next heading SHALL remain

#### Scenario: Heading that occurs twice

- **WHEN** the comment has two `### Strategy` sections and `--section "### Strategy"` is corrected
- **THEN** the target SHALL be refused as `section-ambiguous` and nothing archived or written

#### Scenario: Setext heading inside the section

- **WHEN** the section being corrected contains a paragraph line followed by `---`
- **THEN** the helper SHALL exit 6, `correct-prepare` SHALL report `REASON=setext`, and the target SHALL be unchanged

#### Scenario: CRLF outside the corrected section

- **WHEN** a comment written with CRLF line endings and no final newline has its `## Notes` section corrected
- **THEN** the next section SHALL keep its CRLF endings and the body SHALL still end without a newline

#### Scenario: Last section before the separator

- **WHEN** `## Related` is followed by `---`, `### Linked-Context Siblings` and `---`, and `## Related` is corrected
- **THEN** both `---` lines and the `### Linked-Context Siblings` block SHALL remain in the result


<!-- @trace
source: idd-edit-in-place-correction
updated: 2026-10-20
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/README.md
-->

---
### Requirement: idd-update SHALL rebuild Key Decisions from current comments

`idd-update` SHALL derive `### Key Decisions` from the comments as they currently read on every run, instead of keeping every earlier entry, so that a decision corrected at its source disappears from the summary on the next run.

#### Scenario: Corrected decision leaves the summary

- **WHEN** a Diagnosis comment that stated a decision is corrected with `/idd-edit --correct` and `/idd-update` runs afterwards
- **THEN** `### Key Decisions` SHALL NOT contain the corrected statement


<!-- @trace
source: idd-edit-in-place-correction
updated: 2026-10-20
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/README.md
-->

---
### Requirement: One /idd-edit run SHALL keep its state in the helper

Every mode of `/idd-edit` SHALL run as five helper commands, each one tool call: `run-start` (parse the arguments with the parse-args gates, resolve the targets and the privacy tier, print `RUN=`, `REPO=`, `SCRUB=` and one `TARGET=` or `PICK=` line per target), `prepare` per target, `apply` after the user confirms or `discard` after the user declines, and `finish`. The run's state — the parsed arguments, each target's progress and outcome — SHALL live in a private run directory created by `run-start`, never in shell variables, arrays or loops of the skill: each skill block SHALL be a single command that reads no shell variable other than `CLAUDE_PLUGIN_ROOT` and takes only values an earlier block printed. `apply` SHALL require `--scrub-attested`, given after the privacy self-review of the preview, at least as strict as the run's tier, and SHALL write at the attested tier in every mode. A body carrying both `type=reply` and `points-from=user-pasted` (idd-comment's reply marker) falls under #272 at every tier, as idd-comment applies it: `prepare` SHALL print `FLOOR=272` whenever the new body or the current one carries both markers (a replacement that drops the marker is still asked), check it at no less than `warn`, and print no `SCRUB=` line the skill could copy into `apply`; the skill SHALL ask the user the #272 question (may this third-party text be posted; about the text this edit adds — the quoted points already on GitHub stay as they are, and declining cancels only this edit; a redact option in every mode, for the body file's text) before applying, and SHALL attest `warn` instead of a run tier of `light`; `apply` SHALL refuse an attested `light` for such a body with exit 2, without recording an outcome, and SHALL never raise the tier on the caller's behalf (verify #351 rounds 11–12). In every mode `apply` SHALL run the author gate again and fetch the target again before writing, and SHALL refuse as `changed-since-preview` when the target no longer equals the text it was prepared from, so that an edit made after the preview is never overwritten. `finish` SHALL print the outcome report, remove the run directory and any working copy a prepared but unapplied correction left, and exit with the run's exit code; a target `run-start` listed but nobody prepared (`not-prepared`) and a `PICK` nobody resolved (`not-picked`) SHALL count as refusals; a prepared target that was neither applied nor discarded (`not-applied`) SHALL count with the declines (exit 9), since nothing was written (the user may have confirmed and `apply` returned exit 2), so a caller does not act on an edit that never landed. `apply` SHALL accept an attested tier at least as strict as the run's (`enforce` ≥ `warn` ≥ `light`) and SHALL treat a `--state` that does not match the prepared state as a usage error (exit 2) without recording an outcome, so the correctly copied value can be retried. An explicit empty value (`--state ""`) SHALL be accepted. `run-start` SHALL list a target named twice once. The run directory SHALL be found by its own path and ownership, not by the temporary directory of the call that uses it, because sandboxed and unsandboxed tool calls see different temporary directories. A `--replace` marker SHALL name its backup by its directory name and file name (`idd-edit-backup/<file>`, or the fallback directory's name), never by a local absolute path. A backup directory this user owns with group or other permissions (left by 3.4.0) SHALL be made private rather than refused; when the name belongs to someone else, `idd-edit-backup-<uid>` and then a fresh private `idd-edit-backup-*` directory SHALL be used, and `prepare` prints the path as `BACKUP=`. `prepare` SHALL accept only a target `run-start` listed, or a comment chosen for an open `PICK` (`--pick N`), which SHALL be a comment of issue N; each PICK SHALL be settled by its own record, never by counting extra targets. A chosen comment whose body or author cannot be read (`fetch-failed`, `author-unknown`) SHALL be reported and not recorded, so the PICK stays open; a pick that names a target the run already has SHALL print `RESULT=merged`. PICK numbers SHALL be one to eighteen ASCII digits compared as numbers (`#007` is `#7`); anything else is a usage error (exit 2). The stale-run cleanup SHALL never remove the run being served or the working copies its ledger names, and recording an outcome SHALL refresh the run directory's modification time. A run directory's `run.json` SHALL pass the same gates as the arguments (mode, repository shape, tier, the override's reason, scope, section, targets) and its `body.md` SHALL be a regular file, or the directory is not a run (exit 2); the ledger and working copies `prepare` adds are the run's own. `run-start` SHALL refuse with exit 3 a `--scope` other than `whole-comment` in every mode, so it never starts a run its later steps refuse. A `--correct` run SHALL hand the run's own text to `correct-prepare` rather than its path, so it works from a call whose temporary directory differs from the one that started the run. Backups of `--append`, `--replace` and `--prepend-note` SHALL be kept after the run under the user's temporary directory in `idd-edit-backup/`.

#### Scenario: Confirm block run in a fresh shell

- **WHEN** an agent runs the SKILL's `apply` block in a new zsh process with an empty environment, filling in only the RUN, TARGET, SCRUB and STATE values earlier blocks printed
- **THEN** the correction SHALL be written and `finish` SHALL exit 0

#### Scenario: A refusal is not reported as success

- **WHEN** `prepare` refuses the only target and the agent runs `finish` in a new shell
- **THEN** `finish` SHALL exit 4, so that idd-comment's errata path posts the errata

#### Scenario: Reply quoting user-pasted points in a private repository

- **WHEN** the run's tier is `light` and the target comment carries `<!-- idd:comment type=reply … points-from=user-pasted … -->`, and the user runs `--append` or `--correct` on it
- **THEN** `prepare` SHALL check the composed body at `warn`, print `FLOOR=272` and no `SCRUB=` line, `apply --scrub-attested light` SHALL exit 2 and write nothing, and after the user answers the #272 question `apply --scrub-attested warn` SHALL write it

#### Scenario: Reply quoting user-pasted points in a public repository

- **WHEN** the run's tier is `warn` and the target comment carries the same marker
- **THEN** `prepare` SHALL still print `FLOOR=272`, and the skill SHALL ask the #272 question before applying

#### Scenario: A run idle for a day

- **WHEN** a `--correct` run prepared and discarded one target, its directory was last modified two days ago, and `prepare` is called for its second target
- **THEN** the run directory SHALL survive the stale-run cleanup and `finish` SHALL still report both targets


<!-- @trace
source: idd-edit-in-place-correction
updated: 2026-10-20
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/README.md
-->

---
### Requirement: Parsed arguments SHALL evaluate to exactly the given values

The skill passes the user's arguments to `run-start` as single-quoted words, and `run-start` parses them in-process; the `parse-args` subcommand is kept for compatibility (no IDD skill evaluates its output any more), and its output SHALL still evaluate exactly under bash or zsh. A leading `~`, `$HOME` or `${HOME}` in a `--body-file` value SHALL be read as the user's home directory, since single quotes keep the shell from expanding it. Every value `parse-args` emits SHALL evaluate to exactly the value given: a value containing a newline, any other control character or any non-ASCII character SHALL be emitted in ANSI-C quoting, with every non-ASCII character written as its UTF-8 byte escapes so the result does not depend on the shell's locale, and every `=` SHALL be escaped (zsh expands `=cmd` at the start of a word and after `:`). A `--body-file` containing a NUL byte SHALL be refused with exit code 5. An invocation without a target, or a `--correct` whose text is empty or only whitespace, SHALL be refused with exit code 2, and a `--scope` other than `whole-comment` in any mode with exit code 3; `run-start` SHALL also refuse with exit code 2 an invocation without a mode, and a `--correct` whose text is only the target heading. A caller that evaluates `parse-args` output SHALL stop when the evaluation fails.

#### Scenario: NUL byte in a body file

- **WHEN** `--body-file` names a file whose content is `x`, a NUL byte, then `;touch PWNED`
- **THEN** `parse-args` SHALL exit 5 and no command from the file SHALL run

#### Scenario: Equals sign after a colon under zsh

- **WHEN** `--body 'a:=ls'` is parsed and the output is evaluated by zsh
- **THEN** `BODY_INPUT` SHALL equal `a:=ls`

<!-- @trace
source: idd-edit-in-place-correction
updated: 2026-10-20
code:
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/README.md
-->