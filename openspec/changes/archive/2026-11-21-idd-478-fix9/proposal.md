## Why

Verify round 9 of issue #478, the first round of the changed approach (each issue of a rest run in a directory of its own), ended FAIL with 11 HIGH findings (comment 7057508640). The maintainer chose to fix them and verify again with Codex (2026-11-21). The findings fall into five properties that the spec did not state: two sessions can act on one run at once; the directory of an issue can be reached or written through a symbolic link, and the shell's directory is never checked; the removal of a directory goes by views of git that are not the facts they stand for (a stale remote-tracking branch, a status that hides flagged files, a folder that could not be listed); reading the starting working tree writes its index; and the close stage falls back to review off when the pointer of a rest issue is gone. The permission section of the skill and three documents still describe the removed step between two issues.

## What Changes

- The commands of a run that write its state hold an exclusive lock for their whole run; a second command waits up to 30 seconds and then stops.
- `next` writes the pointer and the exclude lines of a directory only when no symbolic link is on the way. `here` compares the given path as it is, refuses a symbolic link on the way, and checks the shell's directory; the skill runs `cd "$CWD" && here` again before implementing and before verifying.
- `record` fetches with pruning in the directory before it judges, keeps a directory with a file flagged `assume-unchanged` or `skip-worktree`, keeps one whose records cannot be listed, carries the routing log over whether or not git ignores it, marks the removal before it starts and finishes it after an interruption, and reads the outcome again when it was ended before it decided.
- Every git command of the helper runs without optional locks; the check of the starting working tree compares the bytes of the index file.
- `close-stage.py init` records whether the issue runs in a rest directory; `run` stops when that record says it does and the pointer is gone. One function reads a state or pointer file, without following a symbolic link.
- The permission section of the skill, the plugin's `CLAUDE.md`, `references/parallel-orchestration.md` and `docs/commands.md` describe the directory of each issue.

## Non-Goals

- Taking over a kept directory (#566).
- Running two rest runs of one repository at the same time: the second waits for the lock or stops.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `idd-all-rest`: one requirement added (the commands of one run do not overlap); seven requirements changed.

## Impact

- Affected specs: `idd-all-rest`
- Affected code: `plugins/issue-driven-dev/scripts/rest-queue.py`, `plugins/issue-driven-dev/scripts/close-stage.py`, `plugins/issue-driven-dev/scripts/lib/reststate.py`, `plugins/issue-driven-dev/skills/idd-all/SKILL.md`, `plugins/issue-driven-dev/CLAUDE.md`, `plugins/issue-driven-dev/references/parallel-orchestration.md`, `plugins/issue-driven-dev/references/working-tree-writers.md`, `plugins/issue-driven-dev/CHANGELOG.md`, `docs/commands.md`, `plugins/issue-driven-dev/scripts/tests/rest-queue/`, `plugins/issue-driven-dev/scripts/tests/rest-queue-sweep/`
