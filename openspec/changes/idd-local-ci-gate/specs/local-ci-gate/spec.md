## Purpose

Defines how IDD decides whether a commit passes CI using a command configured on the local machine, and how that result relates to remote CI and releases.

## ADDED Requirements

### Requirement: Local mode is the default

The gate SHALL treat a missing `ci` object or missing `ci.mode` as `local` in every repository. A `ci.mode` of `remote` SHALL exit 10 without running any command. Any other mode value SHALL exit 4.

#### Scenario: No ci configuration and no command

- **WHEN** the gate runs in a clone whose config has no `ci` object
- **THEN** it exits 3 with `RESULT=not-configured` and runs nothing

#### Scenario: Remote mode selected

- **WHEN** `ci.mode` is `remote`
- **THEN** it exits 10 with `RESULT=remote` and runs nothing

### Requirement: The command comes only from untracked local configuration

The gate SHALL read the command only from `ci.command` in the walked-up `.claude/.idd/local.json`. It SHALL NOT execute or infer a command from any other repository file. If that config file is tracked by git, the gate SHALL exit 4 without running anything.

#### Scenario: Repository ships a CI script but no config

- **WHEN** the repository contains `scripts/ci.sh` and `ci.command` is unset
- **THEN** the gate exits 3 and `scripts/ci.sh` is not executed

#### Scenario: Config file is tracked

- **WHEN** `.claude/.idd/local.json` is tracked by git and sets `ci.command`
- **THEN** the gate exits 4 and the command is not executed

### Requirement: The command runs from a clean checkout of the named commit

The gate SHALL run the command in a detached worktree of the given commit and SHALL remove that worktree on every exit path. A commit that does not exist locally SHALL exit 4.

#### Scenario: Uncommitted files stay out

- **WHEN** the clone has an uncommitted file and the gate runs on HEAD
- **THEN** that file is absent from the directory the command runs in

#### Scenario: Worktree is removed after failure

- **WHEN** the command exits non-zero
- **THEN** the gate exits 1 and `git worktree list` no longer shows the temporary worktree

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

### Requirement: Each run produces a record

The gate SHALL write a record containing the commit, command, start and end times with offset, and exit code. On fail or timeout the record SHALL also contain the last 40 output lines with the home directory replaced by `~` and the checkout path replaced by `<checkout>`. On pass it SHALL NOT contain command output.

#### Scenario: Failure output is normalized

- **WHEN** the command prints a path under the home directory and exits 1
- **THEN** the record shows that path starting with `~` and does not contain the home directory

### Requirement: idd-all stops at the gate unless it passes

`idd-all` SHALL run the gate after verify and before opening a PR or finishing, and SHALL post the record to the PR or issue through `gh-egress.sh`. It SHALL continue only on exit 0, or on exit 10 by following remote CI. On exit 3, an attended run SHALL ask for the command, may list candidates found in the repository without running them, and SHALL write the config only after confirmation; an unattended run SHALL stop and report. On exit 1, 2 or 4 it SHALL stop and report.

#### Scenario: Unattended run without a command

- **WHEN** an unattended `idd-all` receives exit 3
- **THEN** it stops, reports how to set `ci.command`, and writes no config

### Requirement: Remote CI reports but does not block merging in local mode

In local mode a failing remote check SHALL be reported to the user and SHALL NOT block the merge decision.

#### Scenario: Local pass with remote failure

- **WHEN** the gate exits 0 and a remote check on the same commit failed
- **THEN** the report names the failing check and the merge decision is not blocked by it

### Requirement: Releases still require green remote CI

The `idd-close` distribution sync SHALL NOT proceed to a release while the remote checks of the commit are failing, pending or unreadable, regardless of `ci.mode`.

#### Scenario: Release with pending remote check

- **WHEN** distribution sync reaches a release and a remote check is still running
- **THEN** it stops and reports that check
