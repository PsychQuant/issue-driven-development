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

The issue-driven-dev plugin SHALL register a PreToolUse hook for the tools `Read`, `Grep`, `Glob`, `Edit`, `Write`, `NotebookEdit`, `Bash`, `PowerShell` and `Monitor`. The hook SHALL return a deny decision when any of these `tool_input` fields, compared case-insensitively and, for path fields, after POSIX `normpath` normalization (including the join of `path` with Glob's `pattern` or Grep's `glob`), contains `.claude/.idd/archive` as a path segment (followed by `/` or the end): `file_path`, `path`, `notebook_path`, `pattern` (Glob only), `glob` (Grep only), or `command` (Bash, PowerShell and Monitor). The deny reason SHALL state that the directory holds the prior versions of corrected errors, that reading it would reintroduce those errors, and that `/idd-edit` restore is the supported recovery path. When the hook input cannot be parsed, the hook SHALL allow the call. Skill instructions SHALL NOT place the literal archive path in any Bash command they execute; the helper computes the path internally.

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

For Bash, PowerShell and Monitor commands the hook SHALL read the command as flat text — quotes removed and escapes resolved, as the shell joins its words, in two readings (line continuations joined, and read as line breaks; PowerShell backslashes count as path separators and its backtick is the escape) — cut it into path-like pieces, and deny when any piece, after POSIX `normpath`, contains `.claude/.idd/archive` as a path segment (followed by `/` or the end of the piece). The hook SHALL also deny a call with a relative path that goes below `.claude/.idd/archive/` — each piece POSIX-normalized first — joined to the working directory, or written as `archive/…` or `.idd/archive/…` (after any leading `./` and `../`), each piece matched both as written and POSIX-normalized, the working directory read both as given and — once a relative piece mentions `archive` — with symlinks resolved, while the working directory is or is inside a `.claude/.idd` directory, or is a `.claude` directory, or a word of the command names one; it SHALL deny only when the working directory is near the archive (as defined below for permission changes) or a named `.claude` directory holds an archive. The bare word `archive` SHALL NOT count, and a working directory merely under a `.claude` directory (such as `.claude/worktrees/x`) SHALL NOT turn the rule on. The hook SHALL NOT stat the words of a command; it MAY stat a named `.claude` directory after the text has matched. No part of the command is exempt: a commit message, an issue body, a `--reason`, a comment or a heredoc body that only mentions the path is denied too, and the denial SHALL say to pass such text from a file (`-F`, `--body-file`). Verify #351 rounds 3–16 exempted message values, which required a model of shell word splitting; every rewrite of that model opened a new way past the guard, so the guard fails closed (user decision 2026-10-18). A command is a recursive permission change when it holds, anywhere and without attributing words to commands, a permission command (`chmod`, `chown`, `chgrp`, `chflags`, `setfacl`, or GNU-prefixed `gchmod`, `gchown`, `gchgrp`, compared without regard to letter case) and a recursive marker (a short-flag cluster containing a capital `R`, `--recursive` or an abbreviation `--rec…`, a tree walker `find`, `xargs`, `fd`, `gfind`, `gxargs`, `fdfind`, `bfs`; for PowerShell also `-Recurse` in any case or abbreviation down to `-r`, `-Depth`, and `ForEach-Object`, `foreach`, `%`). The hook SHALL deny every recursive permission change when the call's working directory is inside a repository that holds the archive (an archive at or above the working directory), is the folder directly above such a repository, or cannot be listed — checked for the working directory as given and with symlinks resolved, a stat error other than "not found" counting as an archive — whatever the command's target. From any other working directory the hook SHALL NOT check recursive permission changes; this is a documented limit (user decision 2026-10-18), since checking there required resolving targets and denied ordinary scripts in repositories without an archive. This denial SHALL have its own text, naming both words and the unlistable-directory case, and saying to change the intended files without `-R`, to run unrelated parts as separate calls, to write file contents with the Write tool, to pass message text from a file (`-F`, `--body-file`) and to search with the Grep tool. Near the archive, or when a word of the command names a `.claude/.idd` that holds one, the hook SHALL deny a command that holds a permission command together with any change-of-directory word (`cd`, `chdir`, `pushd`, `popd`, `Set-Location`, `sl`, `Push-Location`, `Pop-Location`), in either reading, and SHALL deny any permission command run from a working directory inside `.claude/.idd` near the archive — the working directory checked as given and with symlinks resolved — (user decision 2026-10-19), with its own denial text saying to spell the path from the working directory instead, to leave `.claude/.idd` in a separate call, and to pass message text from a file. Change-of-directory words SHALL match as whole words, and in PowerShell — the PowerShell tool, or `pwsh`/`powershell` named in the command — also as the cmdlet of a module-qualified name (`Microsoft.PowerShell.Management\Set-Location`, a dotted module prefix only, so `tools/cd` does not count). A permission command written with zsh's `=` expansion (`=chmod`), or as a zsh/files builtin (`zf_chmod`, `zf_chown`, `zf_chgrp`), SHALL count as that command. When `pwsh` or `powershell` (including packaged names such as `pwsh-preview`) appears in a Bash command, the hook SHALL also read the command as PowerShell for the literal path check and for both permission rules. Documented limits — the complete list; the docstring, design Risks and CHANGELOG repeat it: (1) paths or flags assembled from variables, globs, brace expansion, `$'…'` escapes, eval, command substitution or tilde prefixes such as `~+`; (2) another program that changes modes (a `python -c` one-liner, for example); (3) recursive permission changes run from a directory that is not near the archive (user decision 2026-10-18); (4) a program option that changes directory before the permission command — `env -C`/`--chdir`, `sudo -D`, `make -C`, `git -C`, `uv --directory`, `pwsh -WorkingDirectory`, … (user decision 2026-10-19); (5) a `.claude` named after an earlier `cd`, or split by a character outside `[\w./~+@%-]`, from a directory not near the archive; (6) a working directory under `.claude/` that is neither `.claude` nor inside `.claude/.idd` (a worktree), followed by a `cd`; (7) other ways to change directory: the zsh two-argument `cd`, an alias of `cd`, zsh `AUTO_CD` and bash `shopt -s autocd`, PowerShell's `SessionState.Path.SetLocation`; (8) a symlink named in the command; (9) a read without a permission change after a `cd` into the archive — it fails on mode 0000, except as root, which ignores the mode, and on Windows, where mode 0000 does not apply; (10) PowerShell reads with backslash paths run from Bash, PowerShell's `.ForEach()` and comma arrays. The hook SHALL be registered with a 10-second timeout and SHALL deny a call whose check has not finished within 5 seconds. An error while checking a well-formed call SHALL deny that call, and its text SHALL NOT tell the agent to turn the guard off. The hook SHALL allow every call while the file `~/.cache/idd/archive-read-guard.disabled` exists.

#### Scenario: Commit message that mentions the path

- **WHEN** Claude runs `git commit -m "keep .claude/.idd/archive/ out of git"`
- **THEN** the hook SHALL deny the call, and the denial SHALL say to pass the message from a file (`git commit -F <file>`)

#### Scenario: A reason that mentions the path

- **WHEN** Claude runs the idd-edit helper with `--reason 'the backups live in .claude/.idd/archive/edits, not in git'`
- **THEN** the hook SHALL deny the call, as it denies `--reason "$(cat .claude/.idd/archive/edits/a.md)"`

#### Scenario: A comment line hides nothing

- **WHEN** Claude runs a multi-line command whose second line is `# Let's fix perms` and whose third line is `chmod -R u+r .claude`, from a repository that holds the archive
- **THEN** the hook SHALL deny the call

#### Scenario: Any recursive permission change inside the repository

- **WHEN** Claude runs `cd .claude && chmod -R u+rw .idd`, or `grep -R chmod .`, with a working directory inside a repository that holds the archive
- **THEN** the hook SHALL deny the call with the permission denial text, while `chmod u+x scripts/run.sh` and `ls -lrt` stay allowed

#### Scenario: Recursive permission changes near and away from the archive

- **WHEN** the working directory is the folder that directly holds a repository with the archive, and Claude runs `chmod -R u+r .`
- **THEN** the hook SHALL deny the call
- **WHEN** the working directory is a sibling repository without an archive, and Claude runs `chmod -R u+r ..`, `chmod -R u+x scripts`, or a heredoc that writes a script containing `chmod -R u+x "$DIR"`
- **THEN** the hook SHALL allow each call (the first is the documented limit)

#### Scenario: A relative path from inside .claude/.idd

- **WHEN** the working directory is `.claude/.idd` of a repository that holds the archive, and Claude runs `cat archive/edits/a.md`; or the working directory is the repository root and Claude runs `cd .claude/.idd && head archive/edits/a.md`, `cd "<repository path with a space>/.claude/.idd" && cat archive/edits/a.md` or `cd "$(git rev-parse --show-toplevel)/.claude/.idd" && cat archive/edits/a.md`
- **THEN** the hook SHALL deny the call, and so it SHALL for `archive//edits/a.md`, `.claude//.idd`, `attachments/../archive/…`, `cd archive/. && chmod u+r edits/a.md`, `cd -P archive && chmod u+r edits/a.md`, `cd scripts && chmod +x run.sh` in a repository that holds the archive, and `cd ../repo/.claude/.idd && cat archive/edits/a.md` from a sibling directory, while `cat archive/notes/a.md` from `.claude/worktrees/wt`, `cd .claude/.idd && ls attachments`, `ls .claude/.idd && spectra archive my-change` and `git log --oneline | grep archive` stay allowed, and so does `ls -la .claude/.idd/ && sed -n 1p archive/README.md` in a repository that has `.claude/.idd` but no archive

#### Scenario: A permission command near the archive after a change of directory

- **WHEN** the working directory is the repository root of a repository that holds the archive and Claude runs `cd .claude/.idd && cd -P archive && chmod u+r edits/a.md`, or the working directory is `.claude/.idd/attachments` (or a symlink into `.claude/.idd/archive`) and Claude runs `chmod u+r edits/a.md`, or the working directory is a sibling directory and Claude runs `cd ../repo/.claude/.idd && cd -P archive && chmod u+r edits/a.md`
- **THEN** the hook SHALL deny each call with the relocated-permission text, while `chmod +x tools/cd` and `cd scripts && ls -la` from the repository root stay allowed

#### Scenario: Read through sh -c

- **WHEN** Claude runs `sh -c "cat .claude/.idd/archive/edits/a.md"`
- **THEN** the hook SHALL deny the call

#### Scenario: Dot-dot variant

- **WHEN** Claude runs `cat .claude/x/../.idd/archive/edits/a.md`
- **THEN** the hook SHALL deny the call
