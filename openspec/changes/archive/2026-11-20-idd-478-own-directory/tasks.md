## 1. The state and its readers

- [x] 1.1 `scripts/lib/reststate.py`: state version 5 (an attempt holds its directory, whether it was made, what was read at the starting working tree, and the decision about the directory); one function that reads a state file or a pointer file and refuses a symbolic link at the file or at the state folder; `usable` for version 5. Verified by the suite `rest-queue` (example "a state that cannot be used") and `close-stage` (example "the review flag of a rest run has one reader").
- [x] 1.2 `scripts/close-stage.py`: `rest_review` finds the run through the pointer and prints `on`, `off`, `elsewhere` or `unreadable`; `init` refuses `elsewhere`; `run` stops for `elsewhere` and `unreadable`. Verified by the suite `close-stage` (examples "the close stage cannot be told that review is off", "review added while an issue is in flight").

## 2. The directory of an issue

- [x] 2.1 `scripts/rest-queue.py next`: the three questions about existing work in their order (local branch, a directory at the place, `check-existing-work.sh` with only `clear` handed out); the directory recorded before it is made, made as a clone of its own, checked and marked as made; a directory recorded as not yet made is removed and made again. Verified by the examples "the directory is a repository of its own", "a directory that was not finished is made again", "a directory is not removed because of its name", "existing work on GitHub is found by next".
- [x] 2.2 `scripts/rest-queue.py here`. Verified by the example "here names the directory an issue runs in".
- [x] 2.3 `scripts/rest-queue.py record`: the decision about the directory by the closed list of eight items, the routing log appended once, the pointer removed from a kept directory, the comparison of the starting working tree. Verified by the examples "what becomes of a directory", "the routing log is carried over once", "a routing log that cannot be carried over keeps the directory", "a directory that is not a repository of its own is never removed", "a change of the starting working tree is reported".
- [x] 2.4 `start` no longer needs a clean working tree and makes git ignore `.claude/worktrees/`; `report` names kept directories, the directory of an issue in flight, carried routing lines and a changed starting working tree. Verified by the examples "the working tree the run was started in is not needed clean", "the folder of the directories is ignored before a run starts", "the report says what to do with a kept directory", "the report names the directory of an issue in flight", "the report names the routing log that was carried over".
- [x] 2.5 Remove `settle` and everything only it used from `scripts/rest-queue.py`, and the suites and fixtures that tested it (`settle_matrix.py`, `endings.py`, the kill sweep of `settle`). Verified by `scripts/run-all-tests.sh`.

## 3. Properties

- [x] 3.1 `scripts/tests/rest-queue/treecheck.py` and a table of endings: the starting working tree is the same after every ending. Verified by the example "the starting working tree is the same after every ending".
- [x] 3.2 `scripts/tests/rest-queue-sweep/`: `next` and `record` ended after each of their steps and run again. Verified by the example "record ended part of the way comes to the same end".

## 4. The skill and the documents

- [x] 4.1 `skills/idd-all/SKILL.md`: the rest section (the loop with `here`, the shell in the directory of the issue, `REST_ROOT`, the marker, the stop table, what the section does not do), the task description of `rest_run`, the example near the end. Verified by the examples of the requirement "idd-all runs rest mode as a loop over the single-issue pipeline".
- [x] 4.2 `references/working-tree-writers.md`, `README.md`, `CHANGELOG.md`. Verified by the check of the suite `rest-queue` that every location under `.claude/` a skill or script names is in the reference.
- [x] 4.3 Run `scripts/run-all-tests.sh` and the mutation checks on the new code.
