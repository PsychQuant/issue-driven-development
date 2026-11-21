## 1. Tests first

- [ ] 1.1 Tests for the new and changed Examples, failing on the code at `8aaa948`. Verified by running the suite `rest-queue` before the change.

## 2. The implementation

- [ ] 2.1 `record` leaves the directory alone; remove the judgement, the fetch, the removal and the carrying of the routing log. Verified by the example "record leaves every directory as it was".
- [ ] 2.2 No pointer file; `here` and the close stage find the run by the place of the directory; `init --rest-root`. Verified by the examples "here names the directory an issue runs in", "the close stage cannot be told that review is off", "the review flag of a rest run has one reader", "a run that is gone stops the close stage of a rest issue".
- [ ] 2.3 The token of an issue and `next --take-over`. Verified by the example "a token belongs to one session".
- [ ] 2.4 A directory that was not finished is not removed. Verified by the example "a directory that was not finished".
- [ ] 2.5 Exit code 4 for a busy run; state files opened without blocking. Verified by the examples "two sessions at the same run" and "the review flag of a rest run has one reader".
- [ ] 2.6 The skill (separate `cd` and `here`, the token, exit 4) and the documents. Verified by the examples "the skill runs each issue in its directory", "the skill handles a busy run" and "no text describes the removed step between two issues".

## 3. Checks

- [ ] 3.1 The sweep: `next` and `record` ended at each step and run again. Verified by the suite `rest-queue-sweep`.
- [ ] 3.2 `scripts/run-all-tests.sh` and the mutation checks on the new code.
