## 1. One token per run

- [x] 1.1 Tests: `start` prints the token once and stores its digest; `start` without `--take-over` exits 4 on an unfinished run; every command that takes a token refuses another one with exit code 4, read from the helpers' own command tables; `close-stage.py init` with a rest root and `run` refuse a token that is not the run's; `run` checks the token again right before the merge, holding the lock
- [x] 1.2 `lib/reststate.py`: the token digest in the state (version 6), one function that compares a token, the lock of the run
- [x] 1.3 `rest-queue.py`: `start --take-over`, `--token` on `next`, `where`, `here`, `record`, `stop` and `report`; no `next --take-over`
- [x] 1.4 `close-stage.py`: `--rest-token` on `init` and `run`; the check before the merge

## 2. The issue and its directory

- [x] 2.1 Tests: `start` and `next` refuse a folder below the top and a top that cannot be printed; the mark and `origin` bind a directory to its issue in `here`, `init` and the close stage's reading; the clone is made in a temporary folder and moved into a place that `next` took; `init --rest-root none` decides by the place
- [x] 2.2 `rest-queue.py`: the top check, the temporary folder, the mark, `where`, adopting a directory an earlier `next` finished
- [x] 2.3 `close-stage.py`: the place and the binding in `init` and `rest_reading`; `init none` by the place alone

## 3. The rest of round 11

- [x] 3.1 The report prints paths as they are, names temporary folders, and a run that was never reported lists every path that is still there
- [x] 3.2 Tests: the check that `record` leaves a directory lists the whole directory; the Phase 5 test of `on` reads `on`; a further change of a file already listed is not reported
- [x] 3.3 `skills/idd-all/SKILL.md`: the token of the run, `start --take-over`, `where`, `here` before Phase 5, the stale text about deleting a directory; `references/working-tree-writers.md`, `CHANGELOG.md`
- [ ] 3.4 Run the rest-queue, close-stage and sweep suites, then every suite
