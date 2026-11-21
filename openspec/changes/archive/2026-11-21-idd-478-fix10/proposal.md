## Why

Verify round 10 of issue #478 ended FAIL with 11 HIGH findings (comment 7059012246). Six of them were in one judgement: whether the clone of an issue holds anything that exists nowhere else, so that `record` may remove it; two rounds in a row found new gaps in it. The maintainer decided on 2026-11-21 that rest mode does not remove the directory of an issue, and that the other findings are fixed (comment 7060421980). The remaining findings: the close stage inferred from a pointer file whether an issue belongs to a rest run, and compared resolved paths; two sessions could both run one issue; the check of the shell's directory was not tied to the commands that write; a pointer file could overwrite a tracked file; a state file that is a FIFO blocked a read.

## What Changes

- **BREAKING** (within this unreleased branch): `record` no longer removes or reads the directory of an issue; the report names every directory, and a person deletes it. The routing log stays in the directory.
- No pointer file is written into a clone. A directory belongs to the run of the working tree it is below (`R/.claude/worktrees/rest-<N>`).
- `close-stage.py init` takes a required `--rest-root R|none`; `run` stops when the rest run it names can no longer be found.
- `next` prints a token with a new hand-out; `here` and `record` require it; `next --take-over` replaces it.
- A command that waits for the lock in vain exits 4, and `idd-all` ends the invocation without `stop` or `report`.
- `idd-all` changes the shell's directory and runs `here` in separate commands, before diagnosing, implementing and verifying; a `here` that fails on the current directory stops the run.
- State files are opened without blocking and only as regular files.

## Non-Goals

- A command that removes the directories of merged issues (a follow-up issue).
- Telling a session that lost its token from another session.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `idd-all-rest`: one requirement removed (the directory of an issue is removed only when nothing exists only there), one added (the directory of an issue is left for a person), eight changed.

## Impact

- Affected specs: `idd-all-rest`
- Affected code: `plugins/issue-driven-dev/scripts/rest-queue.py`, `plugins/issue-driven-dev/scripts/close-stage.py`, `plugins/issue-driven-dev/scripts/lib/reststate.py`, `plugins/issue-driven-dev/skills/idd-all/SKILL.md`, `plugins/issue-driven-dev/references/working-tree-writers.md`, `plugins/issue-driven-dev/CHANGELOG.md`, `plugins/issue-driven-dev/CLAUDE.md`, `plugins/issue-driven-dev/references/parallel-orchestration.md`, `docs/commands.md`, `plugins/issue-driven-dev/scripts/tests/rest-queue/`, `plugins/issue-driven-dev/scripts/tests/rest-queue-sweep/`
