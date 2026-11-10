# local-ci-gate Specification

## Purpose

Defines how IDD decides whether a commit passes CI using a command configured on the local machine, and how that result relates to remote CI and releases.

## Requirements

### Requirement: Local mode is the default

The gate SHALL treat a missing `ci` object or missing `ci.mode` as `local` in every repository. A `ci.mode` of `remote` SHALL exit 10 without running any command. Any other mode value SHALL exit 4.

#### Scenario: No ci configuration and no command

- **WHEN** the gate runs in a clone whose config has no `ci` object
- **THEN** it exits 3 with `RESULT=not-configured` and runs nothing

#### Scenario: Remote mode selected

- **WHEN** `ci.mode` is `remote`
- **THEN** it exits 10 with `RESULT=remote` and runs nothing


<!-- @trace
source: idd-local-ci-gate
updated: 2026-11-02
code:
  - CLAUDE.md
-->

---
### Requirement: The command comes only from untracked local configuration

The gate SHALL read the command only from `ci.command` in `.claude/.idd/local.json` at the repository root, or at the main worktree root for a linked worktree, and SHALL NOT search parent directories. It SHALL NOT execute or infer a command from any other repository file. The gate SHALL exit 4 without running anything when that file is tracked by git under any case variant of its name, when asking git fails, when the file or a directory on its path is a symbolic link, belongs to another user, or is writable by group or others. The tracked check SHALL run from the root, not from the config's directory. The gate SHALL also exit 4 when `.claude` or `.claude/.idd` is a submodule or holds a `.git` entry, when the root is not an ordinary work tree whose `.git` is what git reports, and when the config changes during the run. A linked worktree SHALL read only the main worktree's config. The gate SHALL exit 4 when the clone's own git config defines a filter or an include. It SHALL ignore relative `PATH` entries and `BASH_ENV`. Its Python SHALL NOT import from the current directory, and it SHALL NOT prune other worktrees' records. A symlinked `.git`, a submodule checkout, `--separate-git-dir` and worktrees of a bare repository SHALL exit 4 with a message naming them, and git older than 2.31 SHALL exit 4. Its checkout SHALL skip LFS downloads. The gate's git calls SHALL ignore repository hooks, bare-repository discovery and repository-local `GIT_*` variables.

#### Scenario: Repository ships a CI script but no config

- **WHEN** the repository contains `scripts/ci.sh` and `ci.command` is unset
- **THEN** the gate exits 3 and `scripts/ci.sh` is not executed

#### Scenario: A bare repository beside a tracked config

- **WHEN** a tracked config's directory also holds `HEAD`, `objects` and `refs`
- **THEN** the gate exits 4 and the command is not executed

#### Scenario: Submodule at .claude

- **WHEN** `.claude` is a populated submodule holding the config
- **THEN** the gate exits 4 and the command is not executed

#### Scenario: Planted git directory in a subdirectory

- **WHEN** the gate runs from a tracked subdirectory holding `HEAD`, `objects`, `refs`, `config` and a config file
- **THEN** the gate does not exit 0 and the command is not executed

#### Scenario: Config above the repository

- **WHEN** only a parent directory of the repository has the config
- **THEN** the gate exits 3 and the command is not executed

#### Scenario: Config file is tracked

- **WHEN** `.claude/.idd/local.json` is tracked by git and sets `ci.command`
- **THEN** the gate exits 4 and the command is not executed


<!-- @trace
source: idd-local-ci-gate
updated: 2026-11-02
code:
  - CLAUDE.md
-->

---
### Requirement: The command runs from a clean checkout of the named commit

The gate SHALL run the command in a detached worktree of the given commit and SHALL remove that worktree on every exit path. A commit that does not exist locally SHALL exit 4.

#### Scenario: Uncommitted files stay out

- **WHEN** the clone has an uncommitted file and the gate runs on HEAD
- **THEN** that file is absent from the directory the command runs in

#### Scenario: Worktree is removed after failure

- **WHEN** the command exits non-zero
- **THEN** the gate exits 1 and `git worktree list` no longer shows the temporary worktree


<!-- @trace
source: idd-local-ci-gate
updated: 2026-11-02
code:
  - CLAUDE.md
-->

---
### Requirement: Exit codes report the result

The gate SHALL exit 0 only when the command exits 0. It SHALL exit 1 when the command exits non-zero, and 2 when the command exceeds `ci.timeout_seconds` (default 3600), after terminating its process group. Invalid configuration SHALL exit 4 and SHALL NOT count as passing.

##### Example: results

| Command | timeout_seconds | Exit | RESULT |
| ------- | --------------- | ---- | ------- |
| `true` | unset | 0 | pass |
| `false` | unset | 1 | fail |
| `sleep 5` | 1 | 2 | timeout |
| `true` | `abc` | 4 | error |

#### Scenario: Timed-out command leaves no children

- **WHEN** the command starts a background child and exceeds the timeout
- **THEN** the gate exits 2 and the child is no longer running


<!-- @trace
source: idd-local-ci-gate
updated: 2026-11-02
code:
  - CLAUDE.md
-->

---
### Requirement: Each run produces a record

The gate SHALL write a record containing the commit, a hash of the command, start and end times with offset, and exit code. The record SHALL NOT contain the command or its output, except that with `ci.post_output_tail: true` a fail or timeout record SHALL contain the last 40 output lines with the home directory replaced by `~`, the checkout path replaced by `<checkout>`, control characters removed, and a code fence longer than any backtick run in them. A non-boolean value SHALL exit 4. The full output SHALL stay in a local log.

#### Scenario: Output stays out by default

- **WHEN** the command prints a token and exits 1, without `ci.post_output_tail`
- **THEN** the record does not contain the token or the command, and the local log contains the token

#### Scenario: Failure output is normalized

- **WHEN** `ci.post_output_tail` is true and the command prints a path under the home directory and exits 1
- **THEN** the record shows that path starting with `~` and does not contain the home directory


<!-- @trace
source: idd-local-ci-gate
updated: 2026-11-02
code:
  - CLAUDE.md
-->

---
### Requirement: idd-all stops at the gate unless it passes

`idd-all` SHALL run the gate after verify and before opening a PR or finishing, and SHALL post the record to the PR or issue through `gh-egress.sh`. It SHALL continue only on exit 0, or on exit 10 by following remote CI. On exit 3, an attended run SHALL ask for the command, may list candidates found in the repository without running them, and SHALL write the config only after confirmation; an unattended run SHALL stop and report. On exit 1, 2 or 4 it SHALL stop and report.

#### Scenario: Unattended run without a command

- **WHEN** an unattended `idd-all` receives exit 3
- **THEN** it stops, reports how to set `ci.command`, and writes no config


<!-- @trace
source: idd-local-ci-gate
updated: 2026-11-02
code:
  - CLAUDE.md
-->

---
### Requirement: Remote CI reports but does not block merging in local mode

In local mode a failing remote check SHALL be reported to the user and SHALL NOT block the merge decision.

#### Scenario: Local pass with remote failure

- **WHEN** the gate exits 0 and a remote check on the same commit failed
- **THEN** the report names the failing check and the merge decision is not blocked by it


<!-- @trace
source: idd-local-ci-gate
updated: 2026-11-02
code:
  - CLAUDE.md
-->

---
### Requirement: Releases still require green remote CI

The `idd-close` distribution sync SHALL NOT proceed to a release while the check runs or commit statuses of the default branch's commit are failing, pending or unreadable, regardless of `ci.mode`. With no checks at all it SHALL proceed only after the user confirms the repository has no remote CI.

#### Scenario: Release with pending remote check

- **WHEN** distribution sync reaches a release and a remote check is still running
- **THEN** it stops and reports that check

<!-- @trace
source: idd-local-ci-gate
updated: 2026-11-02
code:
  - CLAUDE.md
-->