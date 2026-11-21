## Why

Verify round 11 of issue #478 (comment 7066735866) found two classes of defect, each for the third round in a row. Two sessions could run one rest run: the token of fix round 10 was checked by `here` and `record` only, so a session that had been taken over could still merge and close in the close stage, and the `report` of one session could end a run another session was working on. And an issue was bound to its directory by things that can stop matching: the path (another clone put at the same place was accepted), the rest root recorded by an earlier `close-stage.py init` (an `init --rest-root none` read it and then overwrote it), and the directory the run was started in (a run started in a folder below the top of the repository kept its state where no `here` looked for it).

The maintainer decided on 2026-11-22 (comment 7069013462) to fix both classes structurally, to keep the shell that is reset between two tool calls as a known limitation, and to fix the remaining findings.

## What Changes

- One token per run. `start` issues it and prints it once; the run state keeps only its digest. Every command of `rest-queue.py` that reads or writes the run (`next`, `where`, `here`, `record`, `stop`, `report`) and the close stage of an issue of a rest run (`close-stage.py init` with a rest root, and `run` for a record that names one) require it, and refuse every other value with exit code 4. Taking a run over is `start --take-over` and nothing else: a `start` without it exits 4 while an unfinished run is there. `next --take-over` and the per-issue token are gone.
- The close stage checks the token once more right before the merge, holding the lock of the rest run, so that a session taken over while it waited for CI does not merge.
- `start` and `next` refuse a `--cwd` that is not the top of its repository, and a top whose path has a character that cannot be printed as it is. The skill gives `start` the top of the repository.
- Each directory gets a mark: `next` writes a file into the clone's git directory with a value it chose at random and stores with the issue, together with the URL it cloned from. `here`, `close-stage.py init` and the close stage's reading of a rest run accept the directory only when its mark and its `origin` are those of the issue.
- `next` clones into a temporary folder of its own name, writes the configuration, the exclude lines and the mark there, then takes the place of the directory with `mkdir` and moves the clone into it. A failed clone and git's clean-up of it touch only the temporary folder. A temporary folder that is left is recorded and the report names it. A directory at the place whose mark is the issue's is the directory an earlier `next` finished.
- `close-stage.py init --rest-root none` decides whether the directory is one of a rest run by its place alone; it does not read the record it is about to replace. With a rest root, the rest root must be the one the place shows.
- `where` prints the directory of the issue in flight, so that the skill takes the directory from the program and does not paste it into a command.
- The report prints every path as it is (no white space folded, nothing cut), lists the directories of a run that was never reported whether or not they were finished, and names temporary folders.
- Wording: the report notices a change of the starting working tree only when it changes what git lists; the stale text that still described deleting a directory is corrected; the sweep says what its interruption points are.
- Tests: the check that `record` leaves a directory as it was lists the whole directory, `.git` and the routing log included; the Phase 5 test of the word `on` reads `on`.

## Non-Goals

- A shell that is reset between two tool calls of one phase: the steps that write by the shell's directory then write into the working tree the run was started in. The maintainer accepted this as a known limitation (comment 7069013462).
- Telling the session that lost its token from another session.
- A copy of a directory made with its git directory (`cp -R`) has the same mark and is accepted.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `idd-all-rest`: the start of a run, the report, the loop of the skill, the review flag and the close stage, the directory of an issue, the starting working tree, the lock and the token, and the directory left for a person.

## Impact

- `plugins/issue-driven-dev/scripts/rest-queue.py`
- `plugins/issue-driven-dev/scripts/close-stage.py`
- `plugins/issue-driven-dev/scripts/lib/reststate.py`
- `plugins/issue-driven-dev/skills/idd-all/SKILL.md`
- `plugins/issue-driven-dev/references/working-tree-writers.md`, `plugins/issue-driven-dev/CHANGELOG.md`
- `plugins/issue-driven-dev/scripts/tests/rest-queue/`, `plugins/issue-driven-dev/scripts/tests/rest-queue-sweep/`, `plugins/issue-driven-dev/scripts/tests/close-stage/`
