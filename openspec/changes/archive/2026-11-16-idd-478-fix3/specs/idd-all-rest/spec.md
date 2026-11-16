## MODIFIED Requirements

### Requirement: The open issues are read completely or not at all

`rest-queue.py` SHALL read all open issues with one paginated GraphQL query. For an issue that has more comments than the query returned, it SHALL read all comments of that issue before choosing its latest trusted Diagnosis. When any page fails, a response lacks an expected field, a permission read fails for a reason other than the account not being found, or an `actionability.sh` function reports misuse, the command SHALL exit with code 3, print one reason line on stderr, and SHALL NOT print a list on stdout.

An issue whose body has text for which GitHub returns no rendering this helper can read is not a failed read, and neither is an issue whose rendering this helper fails to read for any other reason. The command SHALL give that issue the class `unreadable`, or `outsider` when the issue holds text from an account without write access, and SHALL classify and order every other issue as usual.

#### Scenario: a failed page fails the whole command

- **WHEN** the second page of the query fails
- **THEN** the command exits non-zero and prints no list

#### Scenario: one issue without a rendering does not hide the others

- **WHEN** one open issue has a body that GitHub renders as nothing
- **THEN** the command exits 0 and the run order holds the other candidates

##### Example: second page fails

- **GIVEN** a repository whose open issues span two pages, and the request for the second page exits 1
- **WHEN** `rest-queue.py list --repo o/r --json` runs
- **THEN** the exit code is not 0 and stdout is empty

##### Example: Diagnosis older than the last 100 comments

- **GIVEN** issue #7 with 130 comments, where the only trusted `## Diagnosis` comment is the 5th comment and its Complexity is `Simple`
- **WHEN** the list is produced
- **THEN** issue #7 has gate group `actionable`, not `undiagnosed`

##### Example: a body GitHub renders as nothing

- **GIVEN** open issues #5 (a plain candidate), #6 whose body is one HTML comment and whose rendering is the empty string, opened by an account with write access, and #7 with the same body, opened by an account without write access
- **WHEN** `rest-queue.py list --repo o/r --json` runs
- **THEN** the exit code is 0, #6 has the class `unreadable`, #7 has the class `outsider`, and the run order is 5

---
### Requirement: Each issue is attempted at most once per run

`rest-queue.py next` SHALL re-read the open issues and hand out the first issue of the run order that this run has not handed out before, recording it in the run state as in flight at that moment. When no such issue exists it SHALL print `done`. While an issue is in flight and has no recorded outcome, `next` SHALL hand out that same issue again with `in_flight` true and SHALL NOT hand out another one.

An issue opened after the run started SHALL be handed out by a later `next` when it is a candidate.

Before it hands out a candidate, `next` SHALL look for a local branch of that issue in the working tree (`idd/<N>` or `idd/<N>-…`). When one exists, `next` SHALL NOT hand the issue out: it SHALL record the issue as stopped with the reason `existing work: local branch <name>` and go on to the following candidate. Such a branch is work that an earlier run or a person started; rest mode does not take it over. When git cannot be asked, `next` SHALL exit with code 3.

#### Scenario: an issue that stopped is not handed out again

- **WHEN** an issue was handed out and recorded as stopped, and it is still an open candidate
- **THEN** no later `next` of the same run hands it out

##### Example: a spawned issue is picked up

- **GIVEN** a run whose candidates are #5 and #9
- **WHEN** #5 is handed out and recorded as stopped, then #9 is handed out and recorded as closed, and a new candidate #12 exists by then
- **THEN** the three `next` results after the first are 9, 12 and `done`

##### Example: the in-flight issue is repeated

- **GIVEN** a run in which `next` handed out #5 and no outcome was recorded
- **WHEN** `next` is called again
- **THEN** it prints `{"next": 5, "in_flight": true}` and the run state still holds exactly one attempt

##### Example: an issue with a local branch is recorded, not handed out

- **GIVEN** a run whose candidates are #5 and #9, in a working tree that has the local branch `idd/5-old`
- **WHEN** `next` is called
- **THEN** it hands out #9, and the run state holds #5 as stopped with the reason `existing work: local branch idd/5-old`

---
### Requirement: A stopped issue does not stop the run and a stopped run hands out nothing

An issue recorded as `stopped` SHALL NOT by itself end the run: once `settle` has succeeded for it, the following `next` hands out the next issue. In direct-commit mode an issue that stopped after leaving commits or files on the default branch ends the run through `settle`, which exits with code 3: the close stage of any later issue would push them with its own. A PR-mode run goes on past such an issue, because the leftovers stay on the issue's own branch. `rest-queue.py stop --reason TEXT` SHALL mark the whole run as stopped; every later `next` of that run SHALL print the stop reason and hand out nothing.

`idd-all` SHALL call `stop` only when a `next`, a `record` or a `settle` of a run that exists exits with code 3: GitHub, `gh` authentication or a helper could not be read, the run state could not be written, or the working tree could not be settled between two issues. When `stop` itself exits with a code other than 0, `idd-all` SHALL go on to `report`. Exit codes 1 and 2 of `rest-queue.py` mean the call itself was wrong and are corrected, not treated as a stop. An interruption by the user leaves the run state in place without a stop record.

When the `start` that would begin a run exits with code 3, no run exists and there is nothing to stop or to report. `idd-all` SHALL relay the reason line that `start` printed and end, and SHALL NOT call `stop` or `report`. The same holds when that `start` would have resumed an earlier run: the state of the earlier run is left as it is, so that a later `start` resumes it.

When `report` itself exits with a code other than 0, `idd-all` SHALL relay what `report` printed together with its reason line, clear the unattended marker, and end. It SHALL NOT call `stop` or `report` again.

#### Scenario: one failing issue does not end the run

- **WHEN** the first issue of a run is recorded as stopped
- **THEN** the next `next` hands out the second issue

#### Scenario: a failed start leaves no run behind

- **WHEN** `start` cannot read the open issues and no run state existed before
- **THEN** `start` exits 3, no run state file exists, and `stop` exits 1

#### Scenario: a failed start leaves an earlier run as it was

- **WHEN** `start` cannot read the open issues and the working tree holds the state of an unfinished run
- **THEN** `start` exits 3, the state file is unchanged, and a later `start` resumes that run

##### Example: stop ends the run

- **GIVEN** a run with candidates #5 and #9, where #5 was recorded as stopped
- **WHEN** `stop --reason "default branch could not be fast-forwarded"` is called and then `next`
- **THEN** `next` prints `{"next": null, "stopped": "default branch could not be fast-forwarded"}` and #9 is not handed out

##### Example: the skill reports a failed start directly

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the part of the rest section about stopping the whole run is read
- **THEN** one line of it names the `start` that exits with code 3 before a run exists, and that line says to tell the user the reason and to call neither `stop` nor `report`

##### Example: the skill ends when the report itself fails

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the part of the rest section about stopping the whole run is read
- **THEN** one line of it names the `report` that exits with code 1 or 3, and that line says to pass on what was printed, to clear the unattended marker, and to call neither `stop` nor `report` again

##### Example: the skill goes on to the report when stop fails

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the part of the rest section about stopping the whole run is read
- **THEN** one row names `next`, `record` and `settle` exiting with code 3, and that row says to call `stop` with the reason line and, when `stop` itself fails, to go on to the end of the run

##### Example: the skill says where a direct-commit run ends

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the rest section is read
- **THEN** it says that in direct-commit an issue that stopped after leaving commits or files on the default branch ends the run, and that a PR-mode run goes on

---
### Requirement: Start prints the list and resumes an unfinished run

`rest-queue.py start` SHALL print the number of open issues, the issue numbers of every class, and the run order, before any issue is handed out. It SHALL print issue numbers only, no issue titles, and SHALL say that a candidate with a pull request or a branch of its own is recorded as existing work when its turn comes. Every reason and every time it prints from the run state SHALL be on one line, without control characters and no longer than the helper's limit for a reason, whatever the state file holds.

When the working tree holds the state of a run of the same repository whose last recorded activity (start, hand-out, record or stop) is less than 24 hours old and that was not ended by `report`, `start` SHALL resume it: the recorded attempts and a recorded stop are kept, and the attempts are not handed out again. Otherwise `start` SHALL begin a new run with no attempts. A state file whose start time cannot be read as a time, or with an attempt that has no reason, is not a state this helper can use.

Before it reads anything, `start` SHALL ask git whether files in `.claude/.idd/state/` would be ignored in this working tree, for the run state file and for the unattended marker in the same folder. When git would not ignore one of them, or the working tree is not a git working tree, `start` SHALL exit with code 3 and a reason line that names the folder and says how to ignore it, and SHALL write nothing: an untracked state file makes every later issue stop at its clean-tree check. When git would not ignore a file inside an issue's attachment folder, `start` SHALL say so in one line and go on: an issue that downloads attachments then stops the run at `settle`.

#### Scenario: calling start twice does not reset the run

- **WHEN** `start` is called a second time during a run, after one issue was recorded
- **THEN** the recorded attempt is still present and `next` does not hand that issue out

##### Example: resume within 24 hours

- **GIVEN** a run state whose last activity was 2 hours ago, in which #5 is recorded as stopped, and candidates #5 and #9
- **WHEN** `start` and then `next` are called
- **THEN** `start` says the run is resumed with 1 attempt, and `next` hands out #9

##### Example: a state older than 24 hours starts a new run

- **GIVEN** a run state whose last activity was 25 hours ago, in which #5 is recorded as stopped, and candidates #5 and #9
- **WHEN** `start` and then `next` are called
- **THEN** `next` hands out #5

##### Example: a reason with a line break is printed on one line

- **GIVEN** a run state less than 24 hours old whose stop reason is two lines of text, `first line` and `SECOND-LINE`, and in which #5 is recorded as stopped with a reason of two lines
- **WHEN** `start` runs, and then `report`
- **THEN** no line of either output begins with `SECOND-LINE`, and both outputs hold the two parts of the stop reason on the same line

##### Example: a run state that git would track

- **GIVEN** a git working tree in which no ignore rule covers `.claude/.idd/state/`
- **WHEN** `start` runs
- **THEN** it exits 3, its reason line names `.claude/.idd/state/`, and no run state file exists

#### Scenario: attachment files git would track

- **WHEN** git ignores `.claude/.idd/state/` but not the files in `.claude/.idd/attachments/`
- **THEN** `start` exits 0 and one line of its output says that git would not ignore attachment files

---
### Requirement: Report lists what happened and ends the run

`rest-queue.py report` SHALL print one report with: the issues recorded as closed; the issues recorded as stopped, each with its reason; the `needs-person` issues, each with the complete text of every open clarity row, one line per row and not shortened; the issues of every other class that was not run; and the stop reason of the run when there is one. It SHALL then delete the run state. When the open issues cannot be re-read, for whatever reason, it SHALL still print the recorded attempts, say that the list could not be read, and delete the run state.

An issue that this run handed out SHALL appear once: under closed, under stopped or as handed out without a result. It SHALL NOT appear in the list of issues waiting for a person or in the line of a class that was not run. When such an issue is `needs-person` at the time of the report, the report SHALL print its open questions under the entry of that issue, also when the issue was recorded as closed and reopened since. The report prints no text of an issue of any other class.

For the class `verified` the report SHALL say that such an issue continues when it is named (`/idd-all #N`). When at least one issue was recorded with a reason that begins with `existing work:`, the report SHALL say that such an issue is left for a person and that its reason names the pull request or branch to look at. Under the entry of an issue recorded as stopped, the report SHALL name each branch of that issue that `settle` kept, with the commit `settle` made when it made one, and SHALL say once that a later rest run records an issue with a kept branch as existing work. Under the entry of an issue recorded as closed, it SHALL name the branch and the commit only when `settle` made a commit.

#### Scenario: the report ends the run

- **WHEN** `report` has run
- **THEN** the run state file no longer exists and a later `next` exits 1

#### Scenario: an issue the run stopped on is not reported as not run

- **WHEN** an issue was handed out and stopped, and by the time of the report it falls into a class that is not run
- **THEN** the report lists it under stopped and not in the line of that class

##### Example: report with one closed, one stopped and one waiting issue

- **GIVEN** a run in which #5 was recorded as closed and #9 as stopped with the reason `verify gate: not_clean`, and an open issue #14 whose body shows two open clarity rows
- **WHEN** `report` runs
- **THEN** the output names #5 under closed, #9 with `verify gate: not_clean` under stopped, #14 with both row texts under waiting for a person, and the state file is gone

##### Example: an attempted issue is not listed as not run

- **GIVEN** a run in which #5 was recorded as stopped with the reason `verify gate: not_clean`, and by the time of the report the body of #5 shows the phase `verified`; the open issue #8 also shows the phase `verified` and was never handed out
- **WHEN** `report` runs
- **THEN** the line of the `verified` class names #8 and does not name #5, #5 is listed under stopped, and the report says that a verified issue continues when it is named

##### Example: a stopped issue carries its open questions

- **GIVEN** a run in which #5 was recorded as stopped with the reason `verify gate: not_clean`, and by the time of the report the body of #5 shows two open clarity rows; the open issue #14 also shows two open clarity rows and was never handed out
- **WHEN** `report` runs
- **THEN** #5 is named once, under stopped, followed by its two row texts; the list of issues waiting for a person names #14 and does not name #5

##### Example: a closed issue that was reopened carries its open questions

- **GIVEN** a run in which #5 was recorded as closed, and by the time of the report #5 is open again and its body shows two open clarity rows
- **WHEN** `report` runs
- **THEN** the closed part of the report names #5 with a note that it is open again, followed by its two row texts, and the list of issues waiting for a person does not name #5

##### Example: a long clarity row is printed in full

- **GIVEN** an open issue #14 whose body shows one open clarity row that is longer than 300 characters and whose question ends with the words `END-OF-QUESTION`
- **WHEN** `report` runs
- **THEN** the line of that row in the output contains `END-OF-QUESTION`

---
### Requirement: idd-all runs rest mode as a loop over the single-issue pipeline

In rest mode `idd-all` SHALL call `rest-queue.py start`, then repeat: `next`; run the single-issue pipeline for the issue handed out, with the flags of this invocation; `record` with the stop reason the single-issue report printed, if any; `rest-queue.py settle` for that issue. It SHALL run the steps of the single-issue pipeline that check the working tree, the flags and the dependencies once, and SHALL resolve the path and the interaction mode once, for the first issue, and reuse them for every later issue. It SHALL leave the loop when `next` prints `done` or a stop reason, and SHALL then call `rest-queue.py report` and relay its output.

In rest mode `idd-all` SHALL NOT take over work that already exists: when the existing-work check of the single-issue pipeline returns `resume` or `blocked` for the issue handed out, it SHALL create no branch, leave the pull request untouched, ask no question, and record the issue with a reason that begins with `existing work: ` and holds the outcome the check printed and the next step for a person.

When `next` prints `in_flight` true, `idd-all` SHALL continue that issue where it stopped: when the issue already has its Phase 6 result, it goes straight to `record`; otherwise it continues the interrupted phase. It SHALL NOT run the existing-work check of that issue again: the branch and the pull request the check would find are this run's own.

The unattended marker SHALL NOT outlive the run. Before `idd-all` records an issue that it did not take over, it SHALL clear the marker that the mode step of that issue wrote, because that issue does not reach the clean-up of the single-issue pipeline. After `report`, it SHALL clear the marker once more.

#### Scenario: the loop ends with the report

- **WHEN** `next` prints `done`
- **THEN** `idd-all` calls `report` and starts no further issue

#### Scenario: an issue that already has a pull request is listed, not resumed

- **WHEN** the issue handed out has an open pull request on its own `idd/<N>-…` branch
- **THEN** `idd-all` records it as stopped with a reason that begins with `existing work: ` and names PR #<P>, and asks `next` for the following issue

##### Example: the skill names the loop commands in order

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the rest section is read
- **THEN** it contains the invocations `rest-queue.py" start`, `rest-queue.py" next`, `rest-queue.py" record`, `rest-queue.py" settle`, `rest-queue.py" stop` and `rest-queue.py" report`, with `start` before `next`, `next` before `record`, `record` before `settle`, and `report` last; Step 0.1 contains the invocation `rest-queue.py" args`; the rest section states that `resume` and `blocked` are recorded with the reason `existing work: `; and Phase 6 sends a rest run back to the rest section

##### Example: the skill clears the unattended marker

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the rest section is read
- **THEN** the step for an issue that is not taken over holds `clear_unattended "$CWD"` before the issue is recorded, and the part about the end of the run holds `clear_unattended "$CWD"` after the `report` invocation

##### Example: the skill runs the preflight steps once

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the rest section is read
- **THEN** one sentence names Step 0.2, Step 0.3 and Step 0.35 and says they run once, and the path passed to `settle` is the one resolved after Step 0.6

##### Example: the skill continues an issue in flight

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the row of the rest section for `in_flight` true is read
- **THEN** it says to go to `record` when the issue has its Phase 6 result, to continue the interrupted phase otherwise, and not to run Step 0.5.1 again

## ADDED Requirements

### Requirement: Between two issues one helper settles the working tree

After an issue is recorded and before the next one is handed out, `idd-all` SHALL call `rest-queue.py settle --issue N --default D --path P`, where `P` is the path the run resolved after Step 0.6 (`PR` or `direct-commit`). `settle` SHALL accept only the issue this run recorded last, and SHALL exit 1 for any other issue and while an issue is in flight. A second `settle` for an issue it has already settled SHALL change nothing and print what the first one recorded. Until `settle` has succeeded for the issue recorded last, `next` SHALL exit 1 and name that issue. An issue that `next` itself recorded as existing work needs no `settle`: no work was started on it.

`settle` SHALL exit 3 and change nothing when git reports an unfinished merge, cherry-pick, revert or rebase. Otherwise it SHALL act on what it observes in the working tree, by this closed table, first match wins:

1. Path `PR`, the working tree is on the issue's own branch (`idd/<N>` or `idd/<N>-…`): every changed or untracked path that git does not ignore is a leftover of that issue. When a leftover lies in a place IDD keeps out of git, `settle` SHALL exit 3 and commit nothing. These places are a closed list: `.claude/.idd/archive/`, `.claude/.idd/state/`, a name that begins with `.claude/.idd/tree-lock`, `.claude/worktrees/`, and every file under `.claude/.idd/attachments/` other than a `_manifest.json` directly inside an issue's folder. Otherwise `settle` SHALL commit the leftovers on that branch, without pushing, record the commit in the run state, and check out the default branch.
2. Path `PR`, the working tree is on the default branch: any leftover SHALL make `settle` exit 3 and commit nothing, because a later issue would carry it into its own pull request.
3. Path `PR`, the working tree is on any other branch, or on no branch: `settle` SHALL exit 3.
4. Path `direct-commit`: the working tree SHALL be on the default branch and clean; otherwise `settle` SHALL exit 3, because a later issue would commit the leftovers with its own.

After the table, `settle` SHALL fetch the default branch from `origin`. When the local default branch has commits that `origin/<default>` lacks, it SHALL exit 3: in direct-commit they are the commits of an issue that stopped, and the close stage of a later issue would push them; in PR mode a later pull request would carry them. It SHALL then fast-forward the local default branch to `origin/<default>` and confirm that the working tree is clean, and exit 3 when either fails.

In PR mode, `settle` SHALL then look at every local branch of the issue. A branch with no commits that `origin/<default>` lacks and no upstream holds no work, and `settle` SHALL delete it with a safe delete; it SHALL record every other one as kept. Every local branch of the issue was created by this run, because `next` does not hand out an issue that already has one.

On exit 3, the reason line SHALL name the issue, the branch the working tree is on, and up to five of the paths or the number of commits that could not be settled, and SHALL say what a person does next.

#### Scenario: an issue branch with work and nothing left over

- **WHEN** the run of #5 ended on `idd/5-x`, which has one commit and nothing changed
- **THEN** `settle` makes no commit, checks out the default branch, fast-forwards it, and records `idd/5-x` as kept

#### Scenario: the working tree is on a branch of another issue

- **WHEN** `settle` is called for #5 and the working tree is on `idd/7-y`
- **THEN** it exits 3 and changes nothing

##### Example: leftovers on the issue's own branch are kept there

- **GIVEN** path `PR`, #5 recorded as stopped, the working tree on `idd/5-x` with a changed tracked file `a.txt` and an untracked file `.claude/.idd/attachments/issue-5/_manifest.json` in an untracked `.claude/` folder, and the remote default branch `main` one commit ahead of the local one
- **WHEN** `settle --issue 5 --default main --path PR` runs, and then `report`
- **THEN** `settle` exits 0, `idd/5-x` has one new commit that holds both paths, the working tree is on `main`, clean, at the commit of `origin/main`, and the report names `idd/5-x` and that commit under the entry of #5

##### Example: a leftover on the default branch stops the run

- **GIVEN** path `PR`, #5 recorded as stopped, the working tree on `main` with an untracked file `b.txt`
- **WHEN** `settle --issue 5 --default main --path PR` runs
- **THEN** it exits 3, its reason line names `b.txt`, and no commit was made

##### Example: a file IDD keeps out of git is never committed

- **GIVEN** path `PR`, #5 recorded as stopped, the working tree on `idd/5-x` with an untracked file `.claude/.idd/attachments/issue-5/screenshot.png` that no ignore rule covers, and a changed tracked file `a.txt`
- **WHEN** `settle --issue 5 --default main --path PR` runs
- **THEN** it exits 3, its reason line names `.claude/.idd/attachments/issue-5/screenshot.png`, and `idd/5-x` has no new commit

##### Example: unpushed commits on the default branch stop a direct-commit run

- **GIVEN** path `direct-commit`, #5 recorded as stopped, the working tree on `main`, clean, with one commit that `origin/main` lacks
- **WHEN** `settle --issue 5 --default main --path direct-commit` runs
- **THEN** it exits 3, and its reason line names #5 and the number of unpushed commits

##### Example: an empty issue branch is deleted

- **GIVEN** path `PR`, #5 recorded as stopped, the working tree on `idd/5-x`, which has no commit of its own, no upstream, and nothing changed
- **WHEN** `settle --issue 5 --default main --path PR` runs, and then `report`
- **THEN** `settle` exits 0, the branch `idd/5-x` no longer exists, the working tree is on `main`, and the report names no branch under the entry of #5

##### Example: next waits for settle

- **GIVEN** a run with candidates #5 and #9, in which #5 was handed out and recorded as stopped and `settle` was not called
- **WHEN** `next` is called, then `settle` for #5, then `next` again
- **THEN** the first `next` exits 1 and its reason line names #5, and the second `next` hands out #9
