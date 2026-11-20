## Why

Rest mode ran every issue in the working tree it was started in, and between two issues `rest-queue.py settle` tidied that tree: it committed what an issue left, stashed, moved files aside, wrote exclude lines and checked out the default branch, all around files of the person that were there before the run. Eight verify rounds found blocking defects in that step each time, and in round 8 two of them had been introduced by the fixes of round 7. The maintainer set a stop condition for round 8, it was met, and the maintainer chose to change the approach (2026-11-20, issue #478): each issue of a rest run runs in a directory of its own.

A git linked worktree cannot be that directory: the Spectra CLI, run in a linked worktree, writes into the main working tree (measured on spectra 3.0.0), and `spec-change.py preflight` stops there. The directory is therefore a clone of its own, placed below the working tree the run was started in.

## What Changes

- `rest-queue.py next` makes a clone for the issue it hands out (`<top>/.claude/worktrees/rest-<N>`) and prints it as `dir`. `idd-all` runs the single-issue pipeline with the shell in that directory.
- `rest-queue.py here` tells whether a directory is the one the run made for an issue; the pipeline of an issue starts only there.
- `rest-queue.py record` decides, after it recorded the outcome, whether the directory is removed: only when nothing exists only there, by a closed list. Otherwise it is kept and the report names it with the reasons. A kept directory does not stop the run.
- **BREAKING**: `rest-queue.py settle` is removed, with the commits, stashes, exclude lines and moved files it made. `start` and `next` no longer need a clean working tree on the default branch.
- `next` asks the existing-work check itself and hands out an issue only when the check says `clear`; a lookup that could not be completed no longer lets the issue start.
- The close stage finds the review flag of the run from the issue's directory through a pointer file, and refuses an issue that a rest run has in flight in another directory. Whether a file is a readable state, symbolic links included, is decided in one place.
- The state of a run has version 5.

## Non-Goals

- Taking over a kept directory in a later run (#566).
- Bringing files that git ignores in the starting working tree (`node_modules`, `.env`) into the directory of an issue.
- Carrying the local git hooks and the local git configuration of the starting repository into the directory, other than `user.name` and `user.email`.
- A harness whose shell does not stay in a directory after `cd`.
- Direct-commit and attended rest runs (#583).

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `idd-all-rest`: the requirement about settling the working tree between two issues is removed; three requirements about the directory of an issue, its removal and the starting working tree are added; the requirements about attempts, stops, the start, the report, the loop and the review flag change accordingly.

## Impact

- Affected specs: `idd-all-rest`
- Affected code: `plugins/issue-driven-dev/scripts/rest-queue.py`, `plugins/issue-driven-dev/scripts/close-stage.py`, `plugins/issue-driven-dev/scripts/lib/reststate.py`, `plugins/issue-driven-dev/skills/idd-all/SKILL.md`, `plugins/issue-driven-dev/references/working-tree-writers.md`, `plugins/issue-driven-dev/README.md`, `plugins/issue-driven-dev/CHANGELOG.md`, `plugins/issue-driven-dev/scripts/tests/rest-queue/`, `plugins/issue-driven-dev/scripts/tests/rest-queue-sweep/`, `plugins/issue-driven-dev/scripts/tests/close-stage/`
