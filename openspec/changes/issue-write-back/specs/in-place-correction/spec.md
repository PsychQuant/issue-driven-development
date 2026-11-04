## REMOVED Requirements

### Requirement: /idd-edit --correct SHALL replace a bounded region after explicit confirmation

**Reason**: #424 D1 removes the confirmation for corrections to the invoking user's own content; the requirement's name and its confirmation clauses no longer hold.

**Migration**: Replaced by "/idd-edit --correct SHALL replace a bounded region after reporting the preview", which keeps every other clause (author gate, protected regions, egress check, archive, re-read before apply, exit codes) and replaces the confirmation with reporting the diff and preview, holding back on a privacy hit or an unconfirmed #272 question.

### Requirement: The target SHALL be re-read after confirmation

**Reason**: #424 removes the confirmation from `--correct`; the re-read now follows the preview.

**Migration**: Replaced by "The target SHALL be re-read before the write", with the same checks.

## ADDED Requirements

### Requirement: /idd-edit --correct SHALL replace a bounded region after reporting the preview

The `/idd-edit` skill SHALL accept a `--correct` mode whose target is either a comment (`comment:<id>`) or an issue body (`issue:<N>`). For a comment target the invocation SHALL carry exactly one of `--scope whole-comment` or `--section <heading>`. For an issue-body target the invocation SHALL carry `--section <heading>`; `--scope whole-comment` and any whole-body scope SHALL be refused with exit code 3. In every `/idd-edit` mode a `--section` value SHALL be a markdown heading line (one to six `#`, whitespace, then the title); any other value SHALL be refused with exit code 2. A `--correct` invocation without replacement text (`--body` or a non-empty `--body-file`) SHALL be refused with exit code 2. The flow SHALL run in the helper, not in skill shell code: `correct-prepare` reads the target, applies the author gate, the protected-region checks and `gh-egress.sh check` on the composed body (attesting only the logins the target already mentions), and writes the preview into a working directory private to the user; `correct-apply` runs after the preview has been reported; `correct-discard` runs when the user declines. Before the preview `correct-prepare` SHALL check that the archive can be written (the same location checks the archive itself applies) and refuse the target as `archive` when it cannot, so an applied correction is not refused for a reason known in advance. `correct-prepare` SHALL require `--scrub-attested` (the skill resolves the tier per the privacy-scrubbing rule; the helper SHALL NOT default it) and SHALL print the SHA-256 of its state file as `STATE=`. Because the preview and the apply are separate tool calls, the run's `prepare` SHALL print `WORK=`, `PREVIEW=`, `DIFF=` and `STATE=`, and the skill SHALL pass the printed `STATE` to `apply --state` in a later call (see the requirement on runs). `apply` SHALL treat a `--state` that does not match the state file as a usage error (exit 2) without recording an outcome — it cannot tell a mistyped value from a state file changed after the preview, so a value copied again that still does not match means the preview is no longer trustworthy and the target SHALL be discarded, the run finished, and the target prepared again in a new run (a run prepares a target once) — and SHALL refuse as `differs-from-preview` when a field of the state file is malformed. `correct-apply` SHALL read the state file once, hashing and parsing the same bytes, and SHALL run the author gate and the protected-region checks again before it fetches the target the second time, refusing with the same reasons as `correct-prepare`. A replacement that is empty once a leading copy of the target heading, the visible lines of earlier corrections and whole-line IDD markers are removed, or that carries an earlier visible line or correction marker before its trailing group, SHALL be refused with exit 2 (by `run-start` in a run); outside a run, one that holds only a copy of the comment's top marker SHALL be refused as `empty`. Text outside the replaced region SHALL be written back byte for byte (line endings and the presence of a final newline included), and for `--scope whole-comment` the IDD markers at the top of the original SHALL stay at the top, a copy of them in the replacement being dropped. A body the egress gates would reject SHALL be refused as `egress` before the preview, so it is never applied or archived. The skill SHALL show the diff from the current text to the previewed body (its lines end at `\r\n`, `\r` or `\n`, as GitHub reads them; a lone `\r` is shown as a line end) and the full previewed body — the composed body with a placeholder in place of the backup id — in the conversation and then apply without asking for confirmation (#424 D1), except that it SHALL ask with NO as the default when the run's privacy level is `enforce` (no write permission, or it cannot be read); it SHALL hold the target back instead when its privacy review of the added text finds a hit at `enforce` or `warn`, newly added third-party verbatim text at `light`, or a credential at any level, and the user does not approve it, or when the reply-tier question of #272 is not confirmed; `correct-apply` SHALL refuse as `differs-from-preview` when any file of the working directory changed or when composing again with the placeholder no longer gives the preview, and only then composes the body with the real backup id. The working directory SHALL be removed at the end of `correct-apply` and by `correct-discard`, and `correct-apply` SHALL accept only a directory `correct-prepare` created (a direct child of the user's temporary directory with its prefix, owned by the user, closed to others; a run's `apply` accepts the working directory its own ledger names under any temporary directory, since sandboxed and unsandboxed calls see different ones). When the replacement text begins with the target heading line, that line SHALL NOT appear twice. The run's exit code SHALL be the exit code of `finish`, first match wins: 4 when a target was refused or its write failed, 7 when a write could not be read back as sent, 9 when at least one target was discarded after its preview, and 0 otherwise; argument errors keep parse-args' codes (2, 3, 5) from `run-start`, which also exits 1 when the comments of an `#N --last` target cannot be read. Working directories SHALL be created by the helper under the user's temporary directory, and the helper's `--body-file`/`--from-file` path gate SHALL accept files strictly below the user's own temporary directory even where it lives under `/var` (macOS), while still refusing the system and credential paths; credential directories SHALL be matched without regard to letter case (macOS's default file system opens `~/.SSH` as `~/.ssh`), under both `HOME` and the account's home directory, by the path as given and as resolved (a link inside a credential directory is refused), system paths without regard to case on the resolved path, and gh's token store SHALL be refused in every location gh uses for it (`GH_CONFIG_DIR`, `$XDG_CONFIG_HOME/gh`, `~/.config/gh`), the escape hatch included. The skill SHALL write the archive and PATCH the target only after the preview has been reported and the privacy review has passed; a discarded target SHALL leave both the target and the archive directory unchanged.

#### Scenario: Section flag that is not a heading

- **WHEN** a user invokes `/idd-edit comment:1 --correct --section "Expected" --body-file fixed.md`
- **THEN** the parser SHALL exit 2 and nothing SHALL be fetched or written

#### Scenario: Comment section corrected after the preview is reported

- **WHEN** a user invokes `/idd-edit comment:5805214375 --correct --section "### Strategy" --body-file new.md` on a comment the user wrote
- **THEN** the skill SHALL show the diff and the preview, SHALL NOT ask for confirmation, SHALL archive the comment's prior full text, replace only the `### Strategy` section with the content of `new.md`, and exit 0

#### Scenario: Issue body whole-scope refused

- **WHEN** a user invokes `/idd-edit issue:351 --correct --scope whole-comment --body "..."`
- **THEN** the helper SHALL exit 3 with a message stating that issue-body corrections require `--section <heading>`, and no archive file SHALL be created

#### Scenario: Privacy review holds the target back

- **WHEN** a valid `--correct` command's replacement adds an unpublished result, the run's privacy level is `warn` or `enforce`, and the user does not approve it
- **THEN** the target SHALL be unchanged, no file SHALL be created under the archive directory, the skill SHALL NOT restate the text, and `finish` SHALL exit 9

#### Scenario: Repository the user cannot write to

- **WHEN** the run's privacy level is `enforce` because the user has no write permission or the permission cannot be read
- **THEN** the skill SHALL ask for confirmation with NO as the default

### Requirement: The target SHALL be re-read before the write

After the preview and before archiving, `correct-apply` SHALL fetch the target again and compare it byte-for-byte with the previewed text. When they differ, it SHALL refuse that target as changed since preview, write no archive and PATCH nothing. When either fetch — the one before the preview or the one after the preview — fails, the target SHALL be refused as `fetch-failed` and nothing written; an empty working copy SHALL never be compared, archived or written. Working copies SHALL live in a directory private to the run. After the PATCH `correct-apply` SHALL read the target back; when the read fails or differs from what was sent, the target SHALL be reported as unverified and SHALL NOT count as edited. Every fetch SHALL take the `body` field of the API's JSON response exactly as returned, with no newline added or removed; a response without a `body` field, or a comment whose `body` is null, SHALL be a failed fetch (an issue body may be null, which reads as empty). The read-back SHALL equal the sent body byte for byte; any other content, extra newlines included, SHALL be reported as unverified. An error after the archive is written SHALL be reported as unverified with the backup id, never as nothing changed. When gh fails the PATCH itself, `correct-apply` SHALL read the target again: when it still equals the archived text the target SHALL be reported as a failed write (not a refusal), making the run exit 4; when it differs, or cannot be read, the target SHALL be reported as unverified (exit 7), because the write may have landed.

#### Scenario: Both fetches fail

- **WHEN** `gh api` fails while fetching the target before the preview
- **THEN** the target SHALL be reported as `fetch-failed`, no archive SHALL be written, and the target SHALL be unchanged

#### Scenario: The write lands before gh reports an error

- **WHEN** gh exits non-zero for the write but the target already holds the new body
- **THEN** the target SHALL be reported as unverified (exit 7) with its backup id, not as a failed write

#### Scenario: Concurrent edit during preview

- **WHEN** `idd-update` rewrites the issue body after the preview and before `correct-apply`
- **THEN** the correction SHALL be refused as changed since preview and the body SHALL keep `idd-update`'s version

## MODIFIED Requirements

### Requirement: idd-comment errata SHALL route by comment author

`/idd-comment --type errata --target-comment <id>` SHALL resolve the target comment's author. When the author is the authenticated `gh` user, the skill SHALL delegate to `/idd-edit comment:<id> --correct --repo <the repository it checked the author in>` with the supplied scope or section and a `--note`, and SHALL NOT post a separate errata comment. When the author is anyone else, the repository OWNER and a bot included, the skill SHALL post the errata comment only and SHALL NOT attempt to modify the target comment. When `/idd-edit` refuses the correction or its write fails (exit 4), the skill SHALL post the errata comment instead and state that the in-place correction did not succeed — summarising the correction file, except when the refusal was `egress`, where it SHALL state only that the correction was refused by the egress gates and SHALL NOT restate its content; when its arguments are rejected (exit 2, 3 or 5, which includes a correction file the path gate refused) the skill SHALL post nothing, SHALL NOT read the correction file by other means, and SHALL report the argument error; when `/idd-edit` exits 7 (written but not confirmed) it SHALL report that and post nothing; when it exits 9 (declined) it SHALL post nothing and report it. When the author cannot be determined, the skill SHALL post the errata comment and SHALL NOT modify the target. After posting an errata comment because the in-place correction of the user's own comment did not succeed (exit 4), the skill SHALL propose `/idd-edit comment:<id> --prepend-note` pointing to the errata comment, under that skill's own preview and confirmation, unless the comment's first non-blank line is an ATX heading or an IDD marker; anyone else's comment, the OWNER's and a bot's included, SHALL receive no note (user decision 2026-10-17).

#### Scenario: Own comment corrected in place

- **WHEN** a user runs `/idd-comment #351 --type errata --target-comment 5805214375 --section "### Strategy" --correction-file fixed.md` and comment 5805214375 was written by the authenticated `gh` user
- **THEN** no new comment SHALL be posted and `/idd-edit comment:5805214375 --correct --section "### Strategy"` SHALL run, showing its preview and writing without asking

#### Scenario: Own comment, correction refused

- **WHEN** the errata target is the user's own plain comment and `/idd-edit --correct` exits 4 with a reason other than `egress`
- **THEN** the skill SHALL post an errata comment summarising the correction and stating that the in-place correction did not succeed, then propose `/idd-edit --prepend-note` pointing to it

#### Scenario: Own comment, correction declined or unverified

- **WHEN** `/idd-edit --correct` exits 9 (declined) or 7 (written but not confirmed)
- **THEN** the skill SHALL post nothing and report the outcome

#### Scenario: Collaborator comment left untouched

- **WHEN** the errata target comment was authored by anyone other than the authenticated `gh` user — a collaborator, the repository OWNER, or a bot
- **THEN** the skill SHALL post the errata comment, SHALL NOT call `/idd-edit`, and the target comment SHALL be unchanged

### Requirement: Correction targets SHALL be resolved one per iteration

`parse-args` SHALL refuse with exit 2 an invocation that combines an `issue:<N>` target with any other target, or that names more than one `issue:<N>` target, and SHALL refuse with exit 3 a `--correct` invocation carrying both `--scope` and `--section`. Each target SHALL be processed as its own iteration whose archive kind, PATCH endpoint and verification are derived from that target, never from state set by another target.

#### Scenario: Mixed targets refused

- **WHEN** a user invokes `/idd-edit issue:351 comment:5 --correct --section "## Expected" --body x`
- **THEN** the helper SHALL exit 2 and nothing SHALL be archived or PATCHed

#### Scenario: Issue-only correction runs

- **WHEN** a user invokes `/idd-edit issue:351 --correct --section "## Expected" --body-file fixed.md`
- **THEN** exactly one iteration SHALL run, archive kind `issue`, PATCH through the issue-edit path, and the report SHALL show `edited: 1`

### Requirement: One /idd-edit run SHALL keep its state in the helper

Every mode of `/idd-edit` SHALL run as five helper commands, each one tool call: `run-start` (parse the arguments with the parse-args gates, resolve the targets and the privacy tier, print `RUN=`, `REPO=`, `SCRUB=` and one `TARGET=` or `PICK=` line per target), `prepare` per target, `apply` when the target may be written, or `discard` when the user declines, and `finish`. The run's state — the parsed arguments, each target's progress and outcome — SHALL live in a private run directory created by `run-start`, never in shell variables, arrays or loops of the skill: each skill block SHALL be a single command that reads no shell variable other than `CLAUDE_PLUGIN_ROOT` and takes only values an earlier block printed. `apply` SHALL require `--scrub-attested`, given after the privacy self-review of the preview, at least as strict as the run's tier, and SHALL write at the attested tier in every mode. A body carrying both `type=reply` and `points-from=user-pasted` (idd-comment's reply marker) falls under #272 at every tier, as idd-comment applies it: `prepare` SHALL print `FLOOR=272` whenever the new body or the current one carries both markers (a replacement that drops the marker is still asked), check it at no less than `warn`, and print no `SCRUB=` line the skill could copy into `apply`; the skill SHALL ask the user the #272 question (may this third-party text be posted; about the text this edit adds — the quoted points already on GitHub stay as they are, and declining cancels only this edit; a redact option in every mode, for the body file's text) before applying, and SHALL attest `warn` instead of a run tier of `light`; `apply` SHALL refuse an attested `light` for such a body with exit 2, without recording an outcome, and SHALL never raise the tier on the caller's behalf (verify #351 rounds 11–12). In every mode `apply` SHALL run the author gate again and fetch the target again before writing, and SHALL refuse as `changed-since-preview` when the target no longer equals the text it was prepared from, so that an edit made after the preview is never overwritten. `finish` SHALL print the outcome report, remove the run directory and any working copy a prepared but unapplied correction left, and exit with the run's exit code; a target `run-start` listed but nobody prepared (`not-prepared`) and a `PICK` nobody resolved (`not-picked`) SHALL count as refusals; a prepared target that was neither applied nor discarded (`not-applied`) SHALL count with the declines (exit 9), since nothing was written (the user may have confirmed and `apply` returned exit 2), so a caller does not act on an edit that never landed. `apply` SHALL accept an attested tier at least as strict as the run's (`enforce` ≥ `warn` ≥ `light`) and SHALL treat a `--state` that does not match the prepared state as a usage error (exit 2) without recording an outcome, so the correctly copied value can be retried. An explicit empty value (`--state ""`) SHALL be accepted. `run-start` SHALL list a target named twice once. The run directory SHALL be found by its own path and ownership, not by the temporary directory of the call that uses it, because sandboxed and unsandboxed tool calls see different temporary directories. A `--replace` marker SHALL name its backup by its directory name and file name (`idd-edit-backup/<file>`, or the fallback directory's name), never by a local absolute path. A backup directory this user owns with group or other permissions (left by 3.4.0) SHALL be made private rather than refused; when the name belongs to someone else, `idd-edit-backup-<uid>` and then a fresh private `idd-edit-backup-*` directory SHALL be used, and `prepare` prints the path as `BACKUP=`. `prepare` SHALL accept only a target `run-start` listed, or a comment chosen for an open `PICK` (`--pick N`), which SHALL be a comment of issue N; each PICK SHALL be settled by its own record, never by counting extra targets. A chosen comment whose body or author cannot be read (`fetch-failed`, `author-unknown`) SHALL be reported and not recorded, so the PICK stays open; a pick that names a target the run already has SHALL print `RESULT=merged`. PICK numbers SHALL be one to eighteen ASCII digits compared as numbers (`#007` is `#7`); anything else is a usage error (exit 2). The stale-run cleanup SHALL never remove the run being served or the working copies its ledger names, and recording an outcome SHALL refresh the run directory's modification time. A run directory's `run.json` SHALL pass the same gates as the arguments (mode, repository shape, tier, the override's reason, scope, section, targets) and its `body.md` SHALL be a regular file, or the directory is not a run (exit 2); the ledger and working copies `prepare` adds are the run's own. `run-start` SHALL refuse with exit 3 a `--scope` other than `whole-comment` in every mode, so it never starts a run its later steps refuse. A `--correct` run SHALL hand the run's own text to `correct-prepare` rather than its path, so it works from a call whose temporary directory differs from the one that started the run. Backups of `--append`, `--replace` and `--prepend-note` SHALL be kept after the run under the user's temporary directory in `idd-edit-backup/`.

#### Scenario: Apply block run in a fresh shell

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

### Requirement: Skills that detect errors SHALL propose corrections, not apply them

`idd-verify`, `idd-diagnose`, and `idd-reorganize` SHALL, when their analysis shows that a statement already published in the issue body or an issue comment is wrong, add a `### Proposed Corrections` block to their own report. Each entry SHALL name the target (`comment:<id>` or `issue:<N>`), the section heading, a one-line statement of what is wrong, and the exact `/idd-edit ... --correct` command; when the target is not the invoking user's own content, or the wrong text is in an issue body and belongs to no heading, the entry SHALL instead give `/idd-comment --type errata --target-comment <id>` for a comment or `/idd-comment --type correction` for an issue body (untitled text in the user's own comment is reachable with `--scope whole-comment`). In attended mode the skill SHALL ask the user, per entry, whether to run the command now; in unattended mode the skill SHALL only list the entries and SHALL NOT invoke `/idd-edit`. These skills SHALL NOT write to the archive or PATCH the target themselves. The posted command is a proposal collaborators can edit: a skill that runs it SHALL rebuild the arguments from its own values (the target id all digits, the section an ATX heading line) and SHALL NOT paste the published cell. In attended mode the user's choice to run the command is the confirmation: the question SHALL show the full replacement text, the replacement SHALL be written to a new directory made for that run, the command SHALL carry `--repo` and `--note`, and `/idd-edit --correct` SHALL then write after its preview without asking a second time unless a privacy hit, the #272 question or the `enforce` level makes it ask.

#### Scenario: Unattended verify lists but does not apply

- **WHEN** `/idd-verify` runs under the unattended contract and finds that the diagnosis comment names the wrong root-cause file
- **THEN** the verify report SHALL contain a `### Proposed Corrections` entry with the `/idd-edit comment:<id> --correct --section "### Root Cause / Analysis"` command, and the diagnosis comment SHALL be unchanged

#### Scenario: Attended diagnose applies after the user agrees

- **WHEN** `/idd-diagnose` in attended mode proposes one correction and the user selects "run now"
- **THEN** the skill SHALL invoke `/idd-edit` with that command, and the question SHALL show the full replacement text, the command SHALL carry `--repo` with the skill's repository and a `--note`, and `/idd-edit --correct` SHALL show its preview and write without asking a second time unless a privacy hit, the #272 question or the `enforce` level makes it ask; the user's choice of "run now" is the confirmation
