## REMOVED Requirements

### Requirement: /idd-edit --correct SHALL replace a bounded region after explicit confirmation

**Reason**: #424 D1 removes the confirmation for corrections to the invoking user's own content; the requirement's name and its confirmation clauses no longer hold.

**Migration**: Replaced by "/idd-edit --correct SHALL replace a bounded region after reporting the preview", which keeps every other clause (author gate, protected regions, egress check, archive, re-read before apply, exit codes) and replaces the confirmation with reporting the diff and preview, discarding on a privacy hit at `enforce` or a declined #272 question.

### Requirement: Skills that detect errors SHALL propose corrections, not apply them

**Reason**: #424 D4 makes skills that detect a published error apply the correction and report it, in attended and unattended mode alike.

**Migration**: Replaced by "Skills that detect errors SHALL apply corrections and report them"; the report block `### Proposed Corrections` becomes `### Applied Corrections`.

## ADDED Requirements

### Requirement: /idd-edit --correct SHALL replace a bounded region after reporting the preview

The `/idd-edit` skill SHALL accept a `--correct` mode whose target is either a comment (`comment:<id>`) or an issue body (`issue:<N>`). For a comment target the invocation SHALL carry exactly one of `--scope whole-comment` or `--section <heading>`. For an issue-body target the invocation SHALL carry `--section <heading>`; `--scope whole-comment` and any whole-body scope SHALL be refused with exit code 3. In every `/idd-edit` mode a `--section` value SHALL be a markdown heading line (one to six `#`, whitespace, then the title); any other value SHALL be refused with exit code 2. A `--correct` invocation without replacement text (`--body` or a non-empty `--body-file`) SHALL be refused with exit code 2. The flow SHALL run in the helper, not in skill shell code: `correct-prepare` reads the target, applies the author gate, the protected-region checks and `gh-egress.sh check` on the composed body (attesting only the logins the target already mentions), and writes the preview into a working directory private to the user; `correct-apply` runs after the preview has been reported; `correct-discard` runs when the user declines. Before the preview `correct-prepare` SHALL check that the archive can be written (the same location checks the archive itself applies) and refuse the target as `archive` when it cannot, so an applied correction is not refused for a reason known in advance. `correct-prepare` SHALL require `--scrub-attested` (the skill resolves the tier per the privacy-scrubbing rule; the helper SHALL NOT default it) and SHALL print the SHA-256 of its state file as `STATE=`. Because the preview and the apply are separate tool calls, the run's `prepare` SHALL print `WORK=`, `PREVIEW=`, `DIFF=` and `STATE=`, and the skill SHALL pass the printed `STATE` to `apply --state` in a later call (see the requirement on runs). `apply` SHALL treat a `--state` that does not match the state file as a usage error (exit 2) without recording an outcome — it cannot tell a mistyped value from a state file changed after the preview, so a value copied again that still does not match means the preview is no longer trustworthy and the target SHALL be discarded, the run finished, and the target prepared again in a new run (a run prepares a target once) — and SHALL refuse as `differs-from-preview` when a field of the state file is malformed. `correct-apply` SHALL read the state file once, hashing and parsing the same bytes, and SHALL run the author gate and the protected-region checks again before it fetches the target the second time, refusing with the same reasons as `correct-prepare`. A replacement that is empty once a leading copy of the target heading is removed SHALL be refused with exit 2 (by `run-start` in a run); one that holds only a copy of the comment's top marker SHALL be refused as `empty`. Text outside the replaced region SHALL be written back byte for byte (line endings and the presence of a final newline included), and for `--scope whole-comment` the IDD markers at the top of the original SHALL stay at the top, a copy of them in the replacement being dropped. A body the egress gates would reject SHALL be refused as `egress` before the preview, so it is never confirmed or archived. The skill SHALL show the diff from the current text to the previewed body (its lines end at `\r\n`, `\r` or `\n`, as GitHub reads them; a lone `\r` is shown as a line end) and the full previewed body — the composed body with a placeholder in place of the backup id — in the conversation and then apply without asking for confirmation (#424 D1); it SHALL discard the target instead when its privacy review finds a hit at `enforce`, or when the reply-tier question of #272 is asked and the user declines it; `correct-apply` SHALL refuse as `differs-from-preview` when any file of the working directory changed or when composing again with the placeholder no longer gives the preview, and only then composes the body with the real backup id. The working directory SHALL be removed at the end of `correct-apply` and by `correct-discard`, and `correct-apply` SHALL accept only a directory `correct-prepare` created (a direct child of the user's temporary directory with its prefix, owned by the user, closed to others; a run's `apply` accepts the working directory its own ledger names under any temporary directory, since sandboxed and unsandboxed calls see different ones). When the replacement text begins with the target heading line, that line SHALL NOT appear twice. The run's exit code SHALL be the exit code of `finish`, first match wins: 4 when a target was refused or its write failed, 7 when a write could not be read back as sent, 9 when at least one target was discarded after its preview, and 0 otherwise; argument errors keep parse-args' codes (2, 3, 5) from `run-start`, which also exits 1 when the comments of an `#N --last` target cannot be read. Working directories SHALL be created by the helper under the user's temporary directory, and the helper's `--body-file`/`--from-file` path gate SHALL accept files strictly below the user's own temporary directory even where it lives under `/var` (macOS), while still refusing the system and credential paths; credential directories SHALL be matched without regard to letter case (macOS's default file system opens `~/.SSH` as `~/.ssh`), under both `HOME` and the account's home directory, by the path as given and as resolved (a link inside a credential directory is refused), system paths without regard to case on the resolved path, and gh's token store SHALL be refused in every location gh uses for it (`GH_CONFIG_DIR`, `$XDG_CONFIG_HOME/gh`, `~/.config/gh`), the escape hatch included. The skill SHALL write the archive and PATCH the target only after the preview has been reported and the privacy review has passed; a discarded target SHALL leave both the target and the archive directory unchanged.

#### Scenario: Section flag that is not a heading

- **WHEN** a user invokes `/idd-edit comment:1 --correct --section "Expected" --body-file fixed.md`
- **THEN** the parser SHALL exit 2 and nothing SHALL be fetched or written

#### Scenario: Comment section corrected after the preview is reported

- **WHEN** a user invokes `/idd-edit comment:5805214375 --correct --section "### Strategy" --body-file new.md` on a comment the user wrote
- **THEN** the skill SHALL show the diff and the preview, SHALL NOT ask for confirmation, SHALL archive the comment's prior full text, replace only the `### Strategy` section with the content of `new.md`, and exit 0

#### Scenario: Issue body whole-scope refused

- **WHEN** a user invokes `/idd-edit issue:351 --correct --scope whole-comment --body "..."`
- **THEN** the helper SHALL exit 3 with a message stating that issue-body corrections require `--section <heading>`, and no archive file SHALL be created

#### Scenario: Privacy review discards the target

- **WHEN** a user invokes a valid `--correct` command whose preview contains a local home path, in a repository whose privacy level is `enforce`
- **THEN** the target SHALL be unchanged, no file SHALL be created under the archive directory, the skill SHALL report that nothing was changed and why, and `finish` SHALL exit 9

### Requirement: Skills that detect errors SHALL apply corrections and report them

`idd-verify`, `idd-diagnose`, and `idd-reorganize` SHALL, when their analysis shows that a statement already published in the issue body or an issue comment is wrong, apply the correction and add a `### Applied Corrections` block to their own report. When the target is the invoking user's own content, as decided by the helper's strict author check (`validate-target <id> <repo> false --correct` exits 0), the skill SHALL invoke `/idd-edit ... --correct`; when the target is not the invoking user's own content, or the wrong text is in an issue body and belongs to no heading, the skill SHALL post `/idd-comment --type errata --target-comment <id>` for a comment or `/idd-comment --type correction` for an issue body (untitled text in the user's own comment is reachable with `--scope whole-comment`). This SHALL hold in attended and unattended mode alike, and the skill SHALL NOT ask the user before applying (#424). Each entry of `### Applied Corrections` SHALL name the target (`comment:<id>` or `issue:<N>`), the section heading, a one-line statement of what was wrong, and the outcome: the backup id of a correction, the URL of an errata or correction comment, or the reason `/idd-edit` refused or the write failed. These skills SHALL NOT write to the archive or PATCH the target themselves. A skill that runs `/idd-edit` SHALL build the arguments from its own values (the target id all digits, the section an ATX heading line) and SHALL NOT paste text read from GitHub into the command.

#### Scenario: Unattended verify applies the correction

- **WHEN** `/idd-verify` runs under the unattended contract and finds that the diagnosis comment, written by the invoking user, names the wrong root-cause file
- **THEN** the skill SHALL invoke `/idd-edit comment:<id> --correct --section "### Root Cause / Analysis"`, the diagnosis comment SHALL be corrected, and the verify report's `### Applied Corrections` SHALL list the target with the backup id

#### Scenario: Attended diagnose applies without asking

- **WHEN** `/idd-diagnose` in attended mode finds that a section of the issue body the user opened is wrong
- **THEN** the skill SHALL invoke `/idd-edit issue:<N> --correct --section <heading>` without asking first and SHALL list the correction under `### Applied Corrections`

#### Scenario: Collaborator comment answered with errata

- **WHEN** `/idd-verify` finds that a comment written by a collaborator is wrong
- **THEN** the skill SHALL post `/idd-comment --type errata --target-comment <id>`, the collaborator's comment SHALL be unchanged, and `### Applied Corrections` SHALL list the errata comment's URL

#### Scenario: Refused correction reported

- **WHEN** `/idd-edit` refuses a correction because the section is a protected region
- **THEN** the target SHALL be unchanged and `### Applied Corrections` SHALL list the refusal reason for that entry
