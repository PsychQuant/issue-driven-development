## Purpose

Defines where the prior version of a corrected comment or issue body is kept, how it is guaranteed never to enter git history or review diffs, how it is restored, and how Claude's own tools are prevented from reading it. The archive exists so that corrected errors remain recoverable by humans without being re-read by AI sessions.

## ADDED Requirements

### Requirement: Archive entries SHALL be written once under a fixed local path

The `idd-edit-helper.py archive <comment|issue> <id> --from-file <path>` subcommand SHALL write the full prior text of the target (the whole comment, or the whole issue body for a section correction) — for `--correct`, the copy `correct-prepare` fetched and `correct-apply` confirmed unchanged by fetching it again, written by `correct-apply` in-process — byte-for-byte to `<main-worktree>/.claude/.idd/archive/edits/<backup-id>.md`, where the main worktree is the parent of `git rev-parse --git-common-dir` (so an archive written from a linked worktree survives `git worktree remove`), together with a sidecar `<backup-id>.repo` holding the `owner/repo` the target belongs to. `--from-file` SHALL pass the same sensitive-path gate as `--body-file`. The backup id SHALL be `comment-<comment-id>-<UTC timestamp>` or `issue-<N>-body-<UTC timestamp>`, with the timestamp in `YYYYMMDDTHHMMSSZ` form. The file SHALL be created exclusively; when the name already exists the helper SHALL append `-2`, `-3`, and so on, and SHALL NOT overwrite or modify any existing archive file. The subcommand SHALL print only the backup id on stdout and SHALL NOT print archived content on stdout or stderr.

#### Scenario: Comment archived with a unique id

- **WHEN** the helper archives comment 5805214375 at 2026-10-09T10:00:00Z
- **THEN** it SHALL create `.claude/.idd/archive/edits/comment-5805214375-20261009T100000Z.md` and print `comment-5805214375-20261009T100000Z`

#### Scenario: Same-second collision

- **WHEN** an archive file with that id already exists and the helper archives the same comment within the same second
- **THEN** the helper SHALL create `comment-5805214375-20261009T100000Z-2.md` and the existing file SHALL be byte-identical to before

### Requirement: Archive entries SHALL never be tracked by git

Before writing, the helper SHALL ensure `.claude/.idd/archive/` is listed in the repository's `.git/info/exclude` by calling `scripts/git-ignore-block.sh` (idempotent), and SHALL then verify with `git check-ignore` that the exact archive path to be written — including any collision suffix — is ignored. When the current directory is not inside a git work tree, or the path is not ignored after this step, the helper SHALL exit 7, SHALL NOT write the archive, and the calling skill SHALL NOT PATCH the target.

#### Scenario: Re-include rule detected

- **WHEN** the repository's `.gitignore` contains `!.claude/.idd/archive/` so the archive path is not ignored after the exclude block is written
- **THEN** the `archive` subcommand SHALL exit 7 with a message naming the path, and `correct-prepare` SHALL refuse the target as `archive` before the preview, leaving the target unchanged

#### Scenario: Not a git work tree

- **WHEN** `/idd-edit --correct` runs from a directory that is not inside a git work tree
- **THEN** `correct-prepare` SHALL refuse the target as `archive` before the preview (the run exits 4), and the target SHALL be unchanged

### Requirement: Archive files SHALL be unreadable at rest

After writing an archive file the helper SHALL set its permission bits to `0000`. Only the `restore` subcommand SHALL temporarily grant owner read permission, and it SHALL reset the bits to `0000` before exiting, including when the restore fails.

#### Scenario: Recursive grep does not surface archived content

- **WHEN** a command such as `grep -r "<a phrase from the archived text>" .` runs from the repository root after an archive was written
- **THEN** the archived file's content SHALL NOT appear in the output

### Requirement: Restore SHALL return a target to its archived version without displaying the content

`idd-edit-helper.py restore <backup-id> --repo <owner/repo>` SHALL validate the backup id against the pattern `^(comment-[0-9]+|issue-[0-9]+-body)-[0-9]{8}T[0-9]{6}Z(-[0-9]+)?$`, refuse any other value with exit 2, derive the target from the id, and PATCH the target with the archived text passed on stdin. On success it SHALL print only the target URL and the number of bytes restored. The restore SHALL replace the whole target, and the skill SHALL ask for confirmation stating that changes made after the correction will be lost. `restore --target comment:<id>|issue:<N> --repo <owner/repo>` SHALL only look up: it SHALL list the archive entries this clone holds for that target whose sidecar names that repository, oldest first, in the order they were written (time, then the `-N` a same-second write got), print each id as a `BACKUP_ID=` line, say on stderr whether the target still carries that correction's marker, and write nothing; it SHALL refuse with exit 2, as `restore <backup-id>` does, when the archive path has a symlinked component or the repository tracks archive entries, and SHALL skip an entry whose file or sidecar is not a regular file; the archive is the source, because a `--replace` or a restore removes a marker from GitHub while the archived text stays restorable (exit 0; exit 2 when none remains, 1 when the target cannot be read, 7 outside the git work tree). The skill SHALL show those ids to the user and pass the one the user confirms to `restore <backup-id>`, even when only one remains, because which markers remain is GitHub text others can edit. The skill SHALL never copy a value from a marker into a command; it passes only the target, the repository and an id the helper printed after checking it.

#### Scenario: Path traversal refused

- **WHEN** the helper is called as `restore ../../etc/passwd --repo owner/repo`
- **THEN** it SHALL exit 2 without reading any file

#### Scenario: Successful restore output

- **WHEN** a valid backup id is restored
- **THEN** stdout SHALL contain the target URL and a byte count, and SHALL NOT contain any line of the archived text

#### Scenario: Restore by target looks up only

- **WHEN** a comment corrected once is given as `restore --target comment:5 --repo owner/repo`
- **THEN** the helper SHALL print that correction's id as a `BACKUP_ID=` line, exit 0 and leave the comment unchanged, and the comment SHALL be restored only by a later `restore <that id> --repo owner/repo`

### Requirement: A PreToolUse hook SHALL deny Claude tool access to the archive

The issue-driven-dev plugin SHALL register a PreToolUse hook for the tools `Read`, `Grep`, `Glob`, `Edit`, `Write`, `NotebookEdit`, `Bash`, and `PowerShell`. The hook SHALL return a deny decision when any of these `tool_input` fields, compared case-insensitively and, for path fields, after `os.path.normpath` normalization (including the join of `path` with Glob's `pattern` or Grep's `glob`), contains `.claude/.idd/archive` as a path segment (followed by `/` or the end): `file_path`, `path`, `notebook_path`, `pattern` (Glob only), `glob` (Grep only), or `command` (Bash and PowerShell). The deny reason SHALL state that the directory holds the prior versions of corrected errors, that reading it would reintroduce those errors, and that `/idd-edit` restore is the supported recovery path. When the hook input cannot be parsed, the hook SHALL allow the call. Skill instructions SHALL NOT place the literal archive path in any Bash command they execute; the helper computes the path internally.

#### Scenario: Read denied

- **WHEN** Claude calls `Read` with `file_path` ending in `.claude/.idd/archive/edits/comment-5805214375-20261009T100000Z.md`
- **THEN** the hook SHALL return `permissionDecision: "deny"` with the reason described above

#### Scenario: Helper invocation allowed

- **WHEN** Claude runs `python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" archive comment 5805214375 --from-file "$BACKUP_FILE"`
- **THEN** the hook SHALL allow the call, because the command string does not contain the archive path

#### Scenario: Glob pattern into the archive denied

- **WHEN** Claude calls `Glob` with `pattern` set to `.claude/.idd/archive/**/*.md`
- **THEN** the hook SHALL return `permissionDecision: "deny"`

#### Scenario: Case and dot-segment variants denied

- **WHEN** Claude calls `Read` with `file_path` `.Claude/./.IDD/Archive/edits/x.md`
- **THEN** the hook SHALL return `permissionDecision: "deny"`

#### Scenario: Unrelated tool call allowed

- **WHEN** Claude calls `Read` on `plugins/issue-driven-dev/skills/idd-edit/SKILL.md`
- **THEN** the hook SHALL allow the call

### Requirement: Restore SHALL refuse entries it did not write

`restore` SHALL refuse with exit 2 when the archive entry is a symbolic link or not a regular file, when any directory between the work tree and the entry (`.claude`, `.claude/.idd`, `.claude/.idd/archive`, `.claude/.idd/archive/edits`) is a symbolic link or holds a nested git repository, when it is tracked by git, when the repository tracks any path under the archive directory in any letter case, or when its sidecar `owner/repo` differs from `--repo`. `archive` SHALL refuse with exit 7, writing nothing, when any of those directories is a symbolic link or holds a nested git repository, or when the repository tracks any path under the archive directory in any letter case. `archive` SHALL create both the entry and its `.repo` sidecar exclusively, moving to the next suffix when either name exists, so an existing or symlinked sidecar is never written through.

#### Scenario: Orphan sidecar

- **WHEN** a `.repo` sidecar for the base id already exists without its `.md` entry
- **THEN** `archive` SHALL write the entry under the `-2` suffix and SHALL leave the existing sidecar unchanged

#### Scenario: Symlinked archive directory

- **WHEN** a cloned repository ships `.claude/.idd/archive/edits` as a symbolic link to a directory holding an entry and a sidecar that names the repository
- **THEN** `restore` SHALL exit 2 without reading the entry or calling `gh`

#### Scenario: Tracked symlink in a cloned repository

- **WHEN** a repository tracks `.claude/.idd/archive/edits/comment-1-20261009T100000Z.md` as a symlink and the user runs `restore comment-1-20261009T100000Z --repo o/r`
- **THEN** the helper SHALL exit 2, read nothing, and change no file mode

#### Scenario: Wrong repository

- **WHEN** the sidecar records `a/b` and the user runs `restore <id> --repo c/d`
- **THEN** the helper SHALL exit 2 without calling `gh`

### Requirement: The read guard SHALL match path tokens and honour an unlock flag

For Bash, PowerShell and Monitor commands the hook SHALL read the command as flat text — quotes removed and escapes resolved, as the shell joins its words, in two readings (line continuations joined, and read as line breaks; PowerShell backslashes count as path separators and its backtick is the escape) — cut it into path-like pieces, and deny when any piece, after `os.path.normpath`, contains `.claude/.idd/archive` as a path segment (followed by `/` or the end of the piece). No part of the command is exempt: a commit message, an issue body, a `--reason`, a comment or a heredoc body that only mentions the path is denied too, and the denial SHALL say to pass such text from a file (`-F`, `--body-file`). Verify #351 rounds 3–16 exempted message values, which required a model of shell word splitting; every rewrite of that model opened a new way past the guard, so the guard fails closed (user decision 2026-10-18). The hook SHALL also deny a command that holds a permission command (`chmod`, `chown`, `chgrp`, `chflags` or `setfacl`) followed by a recursive marker (`-R`, a short-flag cluster containing `R`, `--recursive` or an abbreviation `--rec…`) and by any word that, resolved against the call's working directory and compared without regard to letter case, is the archive or a directory above it — including directories above the repository root that contains the working directory; with a tree walker (`find`, `xargs`, `fd`) anywhere in the command, every word counts. A quoted or escaped target with a space SHALL be read as one word, and a target the guard cannot resolve (one containing `$` or a backtick) SHALL be denied. This denial SHALL have its own text, naming the recursive permission change. The hook SHALL allow every call while the file `~/.cache/idd/archive-read-guard.disabled` exists.

#### Scenario: Commit message that mentions the path

- **WHEN** Claude runs `git commit -m "keep .claude/.idd/archive/ out of git"`
- **THEN** the hook SHALL deny the call, and the denial SHALL say to pass the message from a file (`git commit -F <file>`)

#### Scenario: A reason that mentions the path

- **WHEN** Claude runs the idd-edit helper with `--reason 'the backups live in .claude/.idd/archive/edits, not in git'`
- **THEN** the hook SHALL deny the call, as it denies `--reason "$(cat .claude/.idd/archive/edits/a.md)"`

#### Scenario: A comment line hides nothing

- **WHEN** Claude runs a multi-line command whose second line is `# Let's fix perms` and whose third line is `chmod -R u+r .claude`, from a repository that holds the archive
- **THEN** the hook SHALL deny the call

#### Scenario: Read through sh -c

- **WHEN** Claude runs `sh -c "cat .claude/.idd/archive/edits/a.md"`
- **THEN** the hook SHALL deny the call

#### Scenario: Dot-dot variant

- **WHEN** Claude runs `cat .claude/x/../.idd/archive/edits/a.md`
- **THEN** the hook SHALL deny the call
