## MODIFIED Requirements

### Requirement: Each issue is attempted at most once per run

`rest-queue.py next` SHALL re-read the open issues and hand out the first issue of the run order that this run has not handed out before, recording it in the run state as in flight at that moment. When no such issue exists it SHALL print `done`. While an issue is in flight and has no recorded outcome, `next` SHALL hand out that same issue again with `in_flight` true and SHALL NOT hand out another one. With it, `next` SHALL print the name of a local branch of that issue as `branch`, or `null` when the working tree has none: an issue without a branch had not reached the step that creates it.

An issue opened after the run started SHALL be handed out by a later `next` when it is a candidate.

`next` SHALL hand out a new issue only when the working tree is on the default branch and `git status --porcelain` prints nothing there. Otherwise it SHALL exit with code 3 and hand out nothing; its reason line says where the working tree is and what a person does, in the words `start` uses for a new run. With the hand-out, `next` SHALL record in the run state every path in the working tree that matches an ignore rule at that moment; `settle` reads that record. A folder that a rule ignores is one path. A folder that merely holds nothing but ignored files is not recorded as a whole, only its ignored files are: what is written into such a folder later is not ignored. An issue in flight is handed out again without this check, and what was recorded for it stays as it is.

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
- **THEN** it prints `{"next": 5, "in_flight": true, "branch": null, "review": "no"}` and the run state still holds exactly one attempt

##### Example: an issue with a local branch is recorded, not handed out

- **GIVEN** a run whose candidates are #5 and #9, in a working tree that has the local branch `idd/5-old`
- **WHEN** `next` is called
- **THEN** it hands out #9, and the run state holds #5 as stopped with the reason `existing work: local branch idd/5-old`

##### Example: the in-flight issue names its branch

- **GIVEN** a run in which `next` handed out #5, no outcome was recorded, and the working tree has the local branch `idd/5-x`
- **WHEN** `next` is called again
- **THEN** it prints `{"next": 5, "in_flight": true, "branch": "idd/5-x", "review": "no"}`

##### Example: a new issue is handed out only on a clean default branch

| the working tree | `next` |
| --- | --- |
| on `main`, clean, with the ignored folder `local/` | hands out #5; the run state holds `local/` among the paths recorded for #5, and does not hold `.claude/`, which holds nothing but the ignored folder of the run state |
| on `wip` | exits 3; its reason line names `wip`; the run state holds no attempt |
| on `main`, with an untracked `b.txt` | exits 3; its reason line names `b.txt`; the run state holds no attempt |

- **GIVEN** a run that was started on a clean `main`, candidate #5, and the working tree then brought into the state of the row
- **WHEN** `next` runs
- **THEN** the outcome is that of the row

#### Scenario: an issue in flight is handed out again wherever the working tree is

- **WHEN** #5 is in flight, the working tree is on `idd/5-x` with a changed file, and `next` runs
- **THEN** it hands out #5 again with `in_flight` true, and the paths recorded for #5 are those of its first hand-out

---
### Requirement: Start prints the list and resumes an unfinished run

`rest-queue.py start --path P --review yes|no` SHALL print the number of open issues, the issue numbers of every class, and the run order, before any issue is handed out. It SHALL print issue numbers only, no issue titles. The run order it prints SHALL hold only the candidates that have no local branch in the working tree. The candidates that have one (`idd/<N>` or `idd/<N>-…`) SHALL be printed on a line of their own, which says that they are recorded as existing work when their turn comes. `start` SHALL also say that a candidate with a pull request or a branch on GitHub is recorded as existing work when its turn comes. Every reason and every time it prints from the run state SHALL be on one line, without control characters and no longer than the helper's limit for a reason, whatever the state file holds.

`P` is the path that `idd-all` resolved for this invocation. Rest mode runs on the PR path only: between two issues, what an issue left is kept on that issue's own branch, and only the PR path gives every issue a branch. When `P` is not `PR`, `start` SHALL exit with code 3, write nothing, and print a reason line that says rest mode needs the PR path and names what a person can do: run the same command with `--pr`, in place of `--no-pr` when the command has it, and the other flags kept, install the ralph-loop plugin when its absence is what downgraded the path, or name the issues one at a time. The reason line SHALL NOT hold a complete `/idd-all` command line: a command copied from it would lose the flags of the invocation. A new run SHALL read the default branch of the repository from GitHub and store it in the run state together with the path; `settle` takes the default branch from there. A resumed run keeps the default branch it stored.

When the working tree holds the state of a run of the same repository whose last recorded activity (start, hand-out, record or stop) is less than 24 hours old and that was not ended by `report`, `start` SHALL resume it: the recorded attempts and a recorded stop are kept, and the attempts are not handed out again. Otherwise `start` SHALL begin a new run with no attempts. A state file whose start time cannot be read as a time, with an attempt that has no reason, without a stored default branch or a stored review flag, with a version this helper does not know, or whose stored path is not `PR`, is not a state this helper can use.

A state file that this helper cannot use and that was written in the last 24 hours SHALL make `start` exit with code 3 and leave the file as it is: the review flag of that run cannot be read, and a new run in its place would drop it. The reason line SHALL name the file and say that it is to be deleted when no rest run is going on in this working tree. A state file of a run that the previous version of this helper wrote is such a file. A state that can be read and belongs to a run for another repository is not: `start` replaces it and says whose it was. A state file older than 24 hours is replaced by the new run. When that file can be read and its run was not ended by `report`, `start` SHALL first print what that run kept and nobody was told: each kept branch with its commit and whether a commit was made without the repository's hooks, each stash with its commit, and each path that run added to the local exclude file.

A new run SHALL begin only when the working tree is on the default branch and `git status --porcelain` prints nothing there, which is what every issue on the PR path requires when it starts. Otherwise `start` SHALL exit with code 3, write nothing, and say in its reason line where the working tree is, that an earlier run may have left it so, and what a person does: on another branch, commit or remove what is left there and run `git checkout --no-overwrite-ignore <default>` (a plain checkout overwrites, without a word, a file git ignores); on the default branch with changes, commit them elsewhere or move them away. Taken as written, those steps leave a working tree in which the run starts. A resumed run is not checked this way: its issue in flight may be on its own branch.

Before it reads anything, `start` SHALL ask git whether files in `.claude/.idd/state/` would be ignored in this working tree, for the run state file and for the unattended marker in the same folder. When git would not ignore one of them, or the working tree is not a git working tree, `start` SHALL exit with code 3 and a reason line that names the folder and says how to ignore it, and SHALL write nothing: an untracked state file makes every later issue stop at its clean-tree check.

To decide the class `outsider`, the helper asks GitHub who has write access to the repository. GitHub answers that question only to an account that has write access itself. When the account that runs `idd-all` is refused (HTTP 403, other than a rate limit), the command SHALL exit with code 3 and its reason line SHALL say that rest mode needs an account with write access to the repository.

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

##### Example: a state that cannot be used

| the state file | written | `start` |
| --- | --- | --- |
| text that is not JSON | now | exits 3, names the file, and the file is unchanged |
| a state of version 3 with review on | 1 hour ago | exits 3, names the file, and the file is unchanged |
| text that is not JSON | 25 hours ago | exits 0 and begins a new run |

- **GIVEN** a working tree with the state file of the row, and candidate #5
- **WHEN** `start --path PR --review no` runs
- **THEN** the outcome is that of the row

##### Example: a run that was never reported is not forgotten

- **GIVEN** a run state whose last activity was 25 hours ago, in which #5 is recorded as stopped and settled with the kept branch `idd/5-x`, a commit made without the repository's hooks, and a stash; and candidate #9
- **WHEN** `start --path PR --review no` runs
- **THEN** it exits 0, begins a new run, and before the list prints `idd/5-x` with that commit and that it was made without the hooks, and the commit of that stash

##### Example: a reason with a line break is printed on one line

- **GIVEN** a run state less than 24 hours old whose stop reason is two lines of text, `first line` and `SECOND-LINE`, and in which #5 is recorded as stopped with a reason of two lines
- **WHEN** `start` runs, and then `report`
- **THEN** no line of either output begins with `SECOND-LINE`, and both outputs hold the two parts of the stop reason on the same line

##### Example: a run state that git would track

- **GIVEN** a git working tree in which no ignore rule covers `.claude/.idd/state/`
- **WHEN** `start` runs
- **THEN** it exits 3, its reason line names `.claude/.idd/state/`, and no run state file exists

##### Example: a run that is not on the PR path is refused

- **GIVEN** a working tree without a run state
- **WHEN** `start --path direct-commit --review no` runs
- **THEN** it exits 3, its reason line names `--pr`, says that it takes the place of `--no-pr`, and holds no `/idd-all` followed by a flag, and no run state file exists

##### Example: start stores the default branch

- **GIVEN** a repository whose default branch on GitHub is `trunk`, and a working tree on `trunk` without a run state
- **WHEN** `start --path PR --review no` runs
- **THEN** it exits 0 and the run state holds the path `PR` and the default branch `trunk`

##### Example: candidates with a local branch are listed apart

- **GIVEN** candidates #5 and #9, in a working tree that has the local branch `idd/5-old`
- **WHEN** `start --path PR --review no` runs
- **THEN** the line of the run order names #9 and not #5, and another line names #5 as a candidate with a local branch

##### Example: an account without write access cannot start a run

- **GIVEN** an open issue #5 opened by `alice`, and a GitHub that answers HTTP 403 to the question whether `alice` has write access
- **WHEN** `start --path PR --review no` runs
- **THEN** it exits 3, its reason line says that rest mode needs an account with write access, and no run state file exists

##### Example: a new run does not start in a working tree an earlier run left

| the working tree | exit | the reason line names |
| --- | --- | --- |
| on `main`, clean | 0 | — |
| on `idd/7-y`, clean | 3 | `idd/7-y` |
| on `main`, with an untracked `b.txt` | 3 | `b.txt` |

- **GIVEN** a working tree as in the row, without a run state, and candidate #5
- **WHEN** `start --path PR --review no` runs
- **THEN** the exit code is that of the row; on exit 3 the reason line names what the row says and the steps to take, and no run state file exists; in the second row the reason line gives `git checkout --no-overwrite-ignore main`, and after that command the same `start` exits 0

---
### Requirement: Report lists what happened and ends the run

`rest-queue.py report` SHALL print one report with: the issues recorded as closed; the issues recorded as stopped, each with its reason; the `needs-person` issues, each with the complete text of every open clarity row, one line per row and not shortened; the issues of every other class that was not run; and the stop reason of the run when there is one. It SHALL then delete the run state. When the open issues cannot be re-read, for whatever reason, it SHALL still print the recorded attempts, say that the list could not be read, and delete the run state.

An issue that this run handed out SHALL appear once: under closed, under stopped or as handed out without a result. It SHALL NOT appear in the list of issues waiting for a person or in the line of a class that was not run. When such an issue is `needs-person` at the time of the report, the report SHALL print its open questions under the entry of that issue, also when the issue was recorded as closed and reopened since. The report prints no text of an issue of any other class.

For the class `verified` the report SHALL say that such an issue continues when it is named (`/idd-all #N`), and that a branch of it kept in this working tree is to be looked at first. When at least one issue was recorded with a reason that begins with `existing work:`, the report SHALL say that such an issue is left for a person and that its reason names the pull request or branch to look at. Under the entry of an issue recorded as stopped, the report SHALL name each branch of that issue that `settle` kept and, when `settle` made a commit on it, that commit and the paths it holds (at most ten, then the number of the others). Under the entry of an issue recorded as closed, it SHALL name the branch, the commit and the paths only when `settle` made a commit, and SHALL print the reason when the issue was recorded with one. When `settle` made a commit without the repository's commit hooks, the report SHALL say so on that entry, that the commit failed while the repository has a commit hook (which is all `settle` knows about why), and that the commit is to be looked at before the branch is pushed. When `settle` stashed files, the report SHALL name, for each stash, the commit of the stash entry and the paths on that entry, and say that `git stash apply <commit>` on that branch brings them back. When `settle` added paths to the local exclude file, the report SHALL name them on that entry and say that they were in the working tree before the run, that the default branch no longer ignores them, and that their lines in `.git/info/exclude` can be removed once the files are dealt with. When `settle` put files back after the checkout, or found paths from before the run missing, the report SHALL name them on that entry and say which of the two happened. When a folder of files set aside is still below the state folder, the report SHALL name it. When one of those paths is a log shared by all issues (`.claude/.idd/routing-stats.jsonl`, or a file under `.claude/.idd/issue-runs/`), the report SHALL say so on that entry: the new lines of that log are on that branch and not on the default branch. When the report names a kept branch of an issue recorded as stopped, it SHALL say once that a later rest run does not take up an issue that has a kept branch, a pull request or the phase `verified`, and that going on with such work is for a person. Under a kept branch that is recorded as having no upstream it SHALL add that deleting the branch lets a later rest run start the issue over while the issue is a candidate. It SHALL NOT say that under a branch that has an upstream, nor under one whose record does not say (a `settle` that stopped part of the way), and no line under an issue recorded as stopped SHALL tell the person to name the issue (`/idd-all #N`). When the branch a stash names was not kept, the report SHALL say that the branch is deleted that the stash brings the files back as files git does not track there, and that they are to be moved out of the working tree again before the next run; it SHALL NOT say `on that branch`. When `settle` committed twice on a branch, the report SHALL name both commits.

The report tells a person to take three kinds of steps, and this list is closed: delete a branch that has no upstream (a kept one, or, after a `settle` that stopped, a branch of that issue without a commit of its own); apply a stash; and, when the attempt recorded last was not settled or an issue is in flight, commit or remove what is left on the branch of that issue and run `git checkout --no-overwrite-ignore <default>`. A check of this capability SHALL take each of them and see the result: the issue is handed out again; the files are back; a new run starts. Looking at a branch, a commit or a pull request is not such a step.

When the attempt recorded last was not settled, or an issue is in flight, when `report` runs, the report SHALL say that the working tree may still be on a branch of that issue and name the default branch to check out.

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

##### Example: the report says what to do with a kept branch

- **GIVEN** a run in which #5 was recorded as stopped and `settle` kept `idd/5-x`, which has one commit and no upstream, and #9 was recorded as stopped and `settle` kept `idd/9-y`, which has one commit and an upstream
- **WHEN** `report` runs, then `idd/5-x` is deleted as the report says, and a new run is started
- **THEN** the line of `idd/5-x` says that deleting the branch lets a later rest run start the issue over, the line of `idd/9-y` does not, one line says that going on with kept work is for a person, no line under a stopped issue holds `/idd-all`, and `next` of the new run hands out #5

##### Example: a closed issue whose run reported a stop

- **GIVEN** a run in which #5 was recorded as closed with the reason `Stopped: /idd-close did not finish`
- **WHEN** `report` runs
- **THEN** #5 is listed under closed, followed by that reason

##### Example: the report says where the working tree may be

- **GIVEN** a run in which #5 was handed out and no outcome was recorded
- **WHEN** `report` runs
- **THEN** one line says that the working tree may still be on a branch of #5 and names `main`

##### Example: the step for a working tree that was not settled

- **GIVEN** a run in which #5 was handed out and no outcome was recorded, and the working tree on `idd/5-x` with a changed `a.txt`
- **WHEN** `report` runs, and a person then commits `a.txt` on `idd/5-x`, runs the checkout the report gives and starts a new run
- **THEN** the report says to commit or remove what is left there and gives `git checkout --no-overwrite-ignore main`, and after that commit and that command the new run starts

---
### Requirement: idd-all runs rest mode as a loop over the single-issue pipeline

In rest mode `idd-all` SHALL first run, once, the steps of the single-issue pipeline that check the working tree, the flags and the dependencies, and SHALL resolve the path and the interaction mode, including the step that can downgrade the path. In doing so it SHALL NOT write the unattended marker and SHALL NOT create a branch. When the configuration asks for a question about the path (`pr_policy: ask`), rest mode SHALL ask whether to start the run on the PR path and SHALL offer no other path.

It SHALL then call `rest-queue.py start` with the path it resolved and the review flag of the invocation. When `start` exits with code 3, `idd-all` SHALL relay the reason line, clear the unattended marker and end.

It SHALL then repeat: `next`; run the single-issue pipeline for the issue handed out, with the path and the interaction mode resolved before `start`, which are neither resolved nor downgraded again for a later issue, and with the review flag that `next` printed, which decides both what is recorded for the close stage and whether the issue fixes in-scope findings and enters the close stage at all; `record` with the stop reason the single-issue report printed, if any; `rest-queue.py settle` for that issue, with the issue number and no path or branch. It SHALL leave the loop when `next` prints `done` or a stop reason, and SHALL then call `rest-queue.py report` and relay its output.

The two steps of the single-issue pipeline that resolve the path and that can downgrade it SHALL each say, where they stand in the skill, that a rest run does not run them again for an issue and which values it uses instead. Wherever the skill says that a later `/idd-all` resumes an unfinished run, it SHALL say that the command is to carry the same flags. The text of the pull request an issue of a rest run opens SHALL follow the review flag `next` printed for that issue, not a value recorded earlier.

The step of the single-issue pipeline that creates the issue's branch SHALL check out in the way that does not overwrite a file git ignores (`git checkout --no-overwrite-ignore`), whether it creates the branch from `origin/<default>` or takes up a branch on the remote: `origin` can track a path that git ignores in this working tree, and a plain checkout writes over that file without a word. When a file is in the way, that step stops the issue and says so. This holds for every `/idd-all` run on the PR path, not only for rest mode.

Between two issues `settle` commits, stashes and checks out in the working tree. The skill SHALL say that nothing else, neither a person nor another session, is to work in that working tree while a rest run goes: `settle` cannot tell such changes from what the issue left.

A reason that `idd-all` passes to `record` or to `stop` is text from outside (a line of a report, a line this helper printed, with file names and git's words in it). `idd-all` SHALL pass it on standard input, not as a shell argument. The commands in the skill that do so SHALL work when they are run exactly as they are written there, indentation included.

In rest mode `idd-all` SHALL NOT take over work that already exists: when the existing-work check of the single-issue pipeline returns `resume` or `blocked` for the issue handed out, it SHALL create no branch, leave the pull request untouched, ask no question, and record the issue with a reason that begins with `existing work: ` and holds the outcome the check printed and the next step for a person.

When `next` prints `in_flight` true, `idd-all` SHALL continue that issue. When the issue already has its Phase 6 result, it goes straight to `record`. When `next` reports no local branch for the issue (`branch` is `null`), the issue had not reached its own branch: `idd-all` SHALL start it again from the step that resolves the issue, the existing-work check included. Otherwise it SHALL continue the interrupted phase and SHALL NOT run the existing-work check of that issue again: the branch and the pull request the check would find are this run's own.

A run that was interrupted is resumed by the same command. Where the skill tells a person that giving the command again resumes the run, it SHALL say that the flags are to be the same.

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
- **THEN** the numbered step before the `start` invocation names Step 0.2, Step 0.3, Step 0.35, Step 0.5 and Step 0.6 and says they run once; the line of the `start` invocation holds `--path "$PATH_AXIS"` and `--review "$REVIEW_YN"`; and the line of the `settle` invocation holds neither `--default` nor `--path`

##### Example: the skill continues an issue in flight

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the row of the rest section for `in_flight` true is read
- **THEN** it says to go to `record` when the issue has its Phase 6 result, to start again from Step 0.4 when `branch` is `null`, and otherwise to continue the interrupted phase without running Step 0.5.1 again

##### Example: the skill ends a refused run without a marker

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the row of the stop table for a `start` that exits with code 3 is read
- **THEN** it names a path that is not `PR` among the causes and holds `clear_unattended "$CWD"`

##### Example: the skill takes the review flag from next

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the step of the rest section that runs the single-issue pipeline is read
- **THEN** it says that `REVIEW_YN` of the issue is the `review` value `next` printed, and not a value remembered from the invocation

##### Example: the skill takes both review values from next

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the step of the rest section that runs the single-issue pipeline, and the paragraph of Step 0.7 about running its block again in a new shell, are read
- **THEN** the step says that `REVIEW_FLAG` follows the value `next` printed, and the paragraph says that a rest run does not go back to the original arguments for `REVIEW_YN`; and the block that prepares the text of the pull request reads the review flag of the rest run state for the issue in flight

##### Example: the skill's record command works as written

- **GIVEN** a run in which #5 is in flight, and the two fenced blocks of the rest section of `skills/idd-all/SKILL.md` that hold `--reason-stdin`, copied as they are
- **WHEN** the first block is run by a shell with ``Stopped: the price is $5 and `date` is not run`` in the place of its placeholder, `settle` runs, and the second block is run with `the helper stopped` in the place of its placeholder
- **THEN** the recorded reason of #5 is exactly ``Stopped: the price is $5 and `date` is not run``, and the stop reason of the run is exactly `the helper stopped`

##### Example: the skill passes reasons on standard input

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the rest section is read
- **THEN** the lines of the `record` and the `stop` invocation each hold `--reason-stdin`, and no invocation in the section holds `--reason '`

##### Example: Step 0.5 and Step 0.6 point at the rest rule

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the first paragraph under the heading of Step 0.5 and the first paragraph under the heading of Step 0.6 are read
- **THEN** each names `## Rest mode` and says that a rest run does not resolve the path again

##### Example: the skill says the flags are to be the same

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the two rows of the stop table that say a later command resumes the run are read
- **THEN** each says that the command is to carry the same flags; and every other line of the skill that says a later `/idd-all` within 24 hours resumes the run says so as well

##### Example: the step that creates the branch does not overwrite a file git ignores

- **GIVEN** a working tree in which `.git/info/exclude` ignores `.vscode/` and `.vscode/settings.json` holds `MINE`, and an `origin/main` whose newest commit tracks `.vscode/settings.json` with the content `TEAM`
- **WHEN** the line of Step 0.5 in `skills/idd-all/SKILL.md` that creates the branch from `origin/$DEFAULT` is run as it is written
- **THEN** that line holds `--no-overwrite-ignore`, as does the line that takes up a branch on the remote; the command fails and git names `.vscode/settings.json`; and the file still holds `MINE`

##### Example: the skill says to leave the working tree alone

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the rest section is read
- **THEN** it says that nothing else is to work in the same working tree while a rest run goes

---
### Requirement: Between two issues one helper settles the working tree

After an issue is recorded and before the next one is handed out, `idd-all` SHALL call `rest-queue.py settle --issue N`. `settle` takes the default branch from the run state, where `start` stored it. `settle` SHALL accept only the issue this run recorded last, and SHALL exit 1 for any other issue and while an issue is in flight. A second `settle` for an issue it has already settled SHALL change nothing and print what the first one recorded: the kept branches, the records it discarded, the stashes it made, and the paths it added to the local exclude file, put back, or found missing. Until `settle` has succeeded for the issue recorded last, `next` SHALL exit 1 and name that issue. An issue that `next` itself recorded as existing work needs no `settle`: no work was started on it.

The paths in this requirement are relative to the directory `idd-all` runs in (`--cwd`), which need not be the top of the repository. Two of the places that are never committed, the worktree folder and the folder of edit backups, are written at the top of the repository whatever `--cwd` is, so `settle` SHALL match all four places both below `--cwd` and at the top.

What the single-issue pipeline writes into the repository, and which of the classes below each location falls into, is listed in `references/working-tree-writers.md`. The lists in this requirement come from that inventory. A check SHALL fail when a skill or a script of the plugin names a location under `.claude/` that the inventory does not name. The inventory covers the plugin's own writers; what other programs write (the Spectra CLI, `idd-route`, the hooks of the target repository) is outside what that check can see.

What was in the working tree before an issue was handed out is not that issue's work. `next` hands out a new issue only when the working tree is clean on the default branch, so at that moment every file git does not track is a file it ignores, and `next` records those paths with the issue. `settle` SHALL account for every file that was in the working tree at that moment. A file git did not track then SHALL be, when `settle` returns with exit code 0 or 3, where it was and as it was when `settle` began: `settle` SHALL NOT commit it, stash it or delete it, and SHALL NOT leave it anywhere else. A file git tracked then holds, after exit code 0, what the default branch has for it.

Three cases have a step of their own:

- **The issue's branch tracks a path recorded at hand-out, and the default branch does not** (the issue committed a file git used to ignore). A checkout of the default branch takes such a file out of the working tree. Before the checkout `settle` SHALL move each such file into a folder of its own below the state folder, and after the checkout, whether it succeeded or failed, SHALL move each back to where it was; it records the paths it moved back on the default branch as returned. The list of what is moved SHALL be written before anything is moved, and a later `settle` for the issue SHALL first move back what an earlier one left there. A place that is taken again by something else is left as it is and so is the file set aside: `settle` SHALL exit 3 and name the folder. While that folder exists, `start` SHALL NOT start a new run (exit code 3, naming the folder), and the report SHALL name it.
- **A commit hook of the repository staged a path recorded at hand-out** into the commit of step 3 (a hook that runs `git add -A`), whether the hook then let the commit through or failed. `settle` SHALL undo that commit, take those paths out of the index, and make the commit without the repository's hooks; the body of the commit message SHALL say that a hook staged files from before the run. When nothing else was staged, `settle` makes no commit.
- **A path recorded at hand-out is gone when `settle` begins**: the issue's run removed it. `settle` cannot bring it back. It SHALL record the path as missing, and the report names it.

A file that a person or another session adds to the working tree while an issue is in flight is, to `settle`, something that issue left: it is not recorded at hand-out, and `settle` has no way to tell it apart. A change the issue's run itself made to a file from before the run is not `settle`'s to undo either.

A check of this capability SHALL establish that from the file system and not from `git status`, which is the view `settle` itself works from: it records the content of every file outside the git folder before `settle` runs, and afterwards finds each of them unchanged, in a commit `settle` made, in a stash `settle` recorded, among the regenerated records `settle` discarded, or written by the checkout with the content of the default branch. Every fixture of that check holds files that were there before the issue was handed out and that git ignored, and the run state of the fixture is written by `start` and `next` themselves.

`settle` SHALL exit 3 and change nothing when git reports an unfinished merge, cherry-pick, revert or rebase. Otherwise it SHALL act on what it observes in the working tree, by this closed table, first match wins:

1. The working tree is on the issue's own branch (`idd/<N>` or `idd/<N>-…`). A path recorded at hand-out can show up as untracked here, because the issue's branch no longer ignores it: the issue deleted or rewrote an ignore rule, or the local default branch has an ignore rule of its own that `origin/<default>` lacks. `settle` SHALL leave such a path where it is. Every other changed or untracked path that git does not ignore is a leftover, and `settle` SHALL handle the leftovers in three steps, in this order:
   1. **Regenerated records.** The folder `.claude/.idd/attachments/issue-<N>/` holds what `idd-diagnose` downloads for the issue, and `idd-diagnose` runs again, and writes that folder again, every time the issue is run. A file directly in that folder is vouched for when the manifest lists it with the SHA-256 the file has, or lists it as a download that failed. When `_manifest.json` is the only leftover in that folder, `settle` SHALL discard it. When the branch has no commit that `origin/<default>` lacks and no upstream, and every leftover lies in that folder and is either the manifest or a file the manifest vouches for, `settle` SHALL discard all of them, the manifest last. To discard is to delete an untracked file and to restore a tracked one to its committed content. `settle` SHALL discard nothing else.
   2. **Places that are never committed.** When a leftover that remains lies in a place whose writer keeps it out of git, `settle` SHALL exit 3 without having discarded or committed anything. These places are a closed list: `.claude/.idd/state/`, `.claude/.idd/archive/`, a name that begins with `.claude/.idd/tree-lock`, and `.claude/worktrees/`.
   3. **Everything else stays with the issue.** `settle` SHALL commit the leftovers that remain on that branch, and nothing else: it stages those paths by name. It commits without pushing, with the subject `chore: keep what the run of #<N> left (#<N>)`, and SHALL record the branch, the commit, the committed paths and whether the branch has an upstream in the run state before it does anything else. The paths it records are the ones git reports for that commit. A file the run wrote that the default branch ignores and the issue's branch does not is a leftover like any other: it was not there at hand-out, and it is committed. The commit runs the repository's commit hooks. When the commit fails and the repository has a hook that git runs before a commit (`pre-commit`, `prepare-commit-msg` or `commit-msg`; a hook file, or a hook from git's configuration where git has those, whatever its name), `settle` SHALL read the leftovers again, because a hook may have written files, apply the first two steps and the rule about paths recorded at hand-out to them once more, stage what remains by name, and make the same commit without running the repository's hooks, of either kind. It SHALL say in the body of that commit message that the commit failed with the repository's commit hooks and that the hooks were skipped, and SHALL record that in the run state. `settle` cannot tell whether a hook or something else made the commit fail; that such a hook is there is what it goes by. When the commit fails and the repository has no such hook, `settle` SHALL exit 3 and SHALL NOT make the commit a second time.

   `settle` SHALL then fetch the default branch from `origin`. When the fetch succeeded and the local default branch is behind `origin/<default>` and has no commit of its own, `settle` SHALL move the local default branch forward to `origin/<default>` while it is not checked out; git allows only a fast-forward there, and when git refuses, the branch is left as it is. A fetch that failed does not stop `settle` here: it goes on with what it has and stops further down, with the working tree on the default branch.

   A plain checkout overwrites, without a word, a file the issue's branch ignores and the default branch tracks. An issue that stops tracking a file (`git rm --cached` and an ignore rule) leaves exactly such a file in the working tree. `settle` SHALL put every such file that is not a path recorded at hand-out into one stash entry with the message `idd rest: files of #<N> that <branch> ignores and the default branch tracks`, before the checkout, deleting none of them, and SHALL record the commit of that stash entry and the paths in the run state before it does anything else. Because the local default branch was moved forward first, an issue that is already merged has no such file.

   It SHALL then check out the default branch, in the way that does not overwrite a file git ignores (`git checkout --no-overwrite-ignore`). A file still in the way makes that checkout fail; `settle` SHALL then exit 3 with the working tree still on the issue's branch and the file as it was. When git reports the checkout as failed and the working tree is on the default branch all the same (a hook that runs after the checkout failed), the checkout counts as done.
2. The working tree is on the default branch: any leftover SHALL make `settle` exit 3 and commit nothing, because no branch of the issue holds it and the next issue starts from a clean working tree.
3. The working tree is on any other branch, or on no branch: `settle` SHALL exit 3.

After the table the working tree is on the default branch. When the local default branch is still behind `origin/<default>` and has no commit of its own (the working tree was on it, or git refused to move it), `settle` SHALL fast-forward it, again in the way that does not overwrite a file git ignores (`git merge --ff-only --no-overwrite-ignore`): such a file in the way makes `settle` exit 3 with the file as it was. When the local default branch has commits that `origin/<default>` lacks, `settle` SHALL leave it as it is: an issue on the PR path starts its branch from `origin/<default>`, not from the local default branch.

Untracked paths can remain at this point. `settle` SHALL handle them by this closed list, first match wins:

1. A path recorded at hand-out. The default branch no longer ignores it, because the issue that removed the ignore rule is merged. `settle` SHALL add it to the repository's local exclude file (`.git/info/exclude`, which is never committed and never leaves this machine), as a pattern that matches this path and no other, under a comment line that names the issue, SHALL leave the file as it is, and SHALL record the path in the run state. This is the maintainer's Decision of 2026-11-20: the file stays, and the run goes on.
2. A path that git ignored while the working tree was on the issue's branch. The issue's branch carries an ignore rule that the default branch lacks. `settle` SHALL put all such paths into one stash entry with the message `idd rest: files of #<N> that only <branch> ignores`, deleting none of them, and SHALL record the commit of that stash entry and the paths in the run state before it does anything else.
3. Any other path is not handled.

It SHALL then confirm that `git status --porcelain` prints nothing in the working tree, which is the check every issue on the PR path starts with, and exit 3 otherwise. When the fetch had failed, `settle` SHALL exit 3 at this point, with the working tree clean on the default branch.

`settle` SHALL then look at every local branch of the issue. A branch with no commits that `origin/<default>` lacks and no upstream holds no work, and `settle` SHALL delete it, since every commit of such a branch is on `origin/<default>`; it SHALL record every other one as kept, with whether it has an upstream. Every local branch of the issue was created by this run, because `next` does not hand out an issue that already has one. For each stash it made, `settle` SHALL record whether the branch the stash names was kept.

A `settle` that runs again after an earlier call stopped part of the way SHALL keep what the earlier call recorded: the records it discarded, its commit and paths, its stashes, and the paths it added to the local exclude file. When it makes a second commit on a branch that the earlier call committed on, the record of that branch SHALL name the newest commit, the earlier commit, and the paths of both, also when the record of the earlier commit was lost and the commit is found again by its subject. When the earlier call stopped after the commit or a stash and before the run state was written, `settle` SHALL find them again: a kept branch whose newest commit has the subject above and is not on `origin/<default>` is that commit, and a stash entry with one of the two messages above is that stash; the paths it records for a stash it found again are the files that stash holds.

On exit 3, whichever step stopped, the reason line SHALL have one shape: the issue and the branch the working tree is on at that moment, what is wrong, what a person does next, and only then the detail, which is git's own words or at most three paths and the number of the others. The branch the working tree is on is named once, at the start of the line; what is wrong and what a person does next name the default branch only when the working tree is on another branch, or inside a git command the person is to run. A command in the line names the default branch only when that name is at most 40 characters long and holds nothing but letters, digits, `.`, `_`, `/` and `-`. Any other name is replaced there by `<the default branch>`: a person may copy the command into a shell, and git allows `;`, `$` and backticks in a branch name. A name is never shortened inside a command. The name of the branch the working tree is on is shortened to 60 characters, and further, though never below 20, when what a person does next would not fit otherwise. When the line would be too long, what is wrong is shortened first and the detail after it; what a person does next and the number of the other paths are never cut off. The whole line SHALL be no longer than the helper's limit for a reason.

After `settle` stops, `idd-all` ends the run with its report, so the next `/idd-all` begins a new run, and a new run needs the working tree clean on the default branch. For the stops of the table below, what the reason tells a person to do SHALL therefore be complete: taken as written, the steps leave a working tree in which a new run starts, and they overwrite no file. A plain `git checkout` overwrites, without a word, a file git ignores; wherever a reason or the report tells a person to check out the default branch, it SHALL give the command that does not (`git checkout --no-overwrite-ignore <default>`), which names in full every file in its way. Each row ends with running the same `/idd-all` command again with the same flags.

| `settle` stops because | The working tree is on | What the reason tells the person to do |
| --- | --- | --- |
| git reports an unfinished merge, cherry-pick, revert or rebase | a branch of the issue | finish or abort it, commit or remove what is left, then that checkout |
| git reports an unfinished merge, cherry-pick, revert or rebase | the default branch | finish or abort it, commit what is left elsewhere or move it away |
| git reports unmerged paths and no unfinished operation | a branch of the issue | resolve them, commit or remove what is left, then that checkout |
| a place that is never committed holds a file git does not ignore | a branch of the issue | have git ignore them, commit or remove what else is left, then that checkout |
| the checkout would overwrite a file git ignores (a path recorded at hand-out that the default branch has come to track) | a branch of the issue | run that checkout and move away each file it names until it succeeds, then move away what `git status` shows as untracked |
| something is left on the default branch | the default branch | commit them elsewhere or move them away |
| the working tree is on another branch | that branch | commit or remove what is left there, then that checkout |
| `origin` cannot be reached | the default branch | check that origin can be reached |
| the fast-forward would overwrite a file git ignores | the default branch | run `git merge --ff-only --no-overwrite-ignore origin/<default>` and move away each file it names until it succeeds |
| the working tree is not clean after the checkout | the default branch | commit what is there elsewhere or move it away |
| the run state holds no usable default branch | a branch of the issue | commit or remove what is left, check out the default branch of the repository |

This table is closed. `settle` stops in these other ways too, and this list is closed as well: a git command it needs fails (reading the status, what git ignores, a branch, an upstream or a commit; staging; the commit when the repository has no commit hook; the commit made without the hooks; discarding a regenerated record; making or finding a stash; comparing the default branch with `origin`), the local exclude file or the run state cannot be written, a path that would go into the local exclude file holds a line break, or `settle` fails in a way it does not know. For these the reason carries git's own words or the error, and names looking at that and running the same command again as the next step. This requirement does not promise that this step is enough.

When the attempt recorded last was not settled (a `settle` that stopped), the report SHALL name every local branch of that issue that has no commit of its own and no upstream, and say that deleting it lets a later rest run start the issue over: `settle` deletes such a branch only at its end.

#### Scenario: an issue branch with work and nothing left over

- **WHEN** the run of #5 ended on `idd/5-x`, which has one commit and nothing changed
- **THEN** `settle` makes no commit, checks out the default branch, fast-forwards it, and records `idd/5-x` as kept

#### Scenario: the working tree is on a branch of another issue

- **WHEN** `settle` is called for #5 and the working tree is on `idd/7-y`
- **THEN** it exits 3 and changes nothing

#### Scenario: a branch with an upstream is kept

- **WHEN** the run of #5 ended on `idd/5-x`, which has no commit that `origin/main` lacks and has an upstream
- **THEN** `settle` exits 0 and records `idd/5-x` as kept, with an upstream

#### Scenario: two branches of one issue

- **WHEN** the run of #5 ended on `idd/5-x`, which has one commit, and the branch `idd/5-y` exists with no commit of its own and no upstream
- **THEN** `settle` deletes `idd/5-y` and records `idd/5-x` as kept

#### Scenario: commit hooks that accept the leftovers run

- **WHEN** the run of #5 ended on `idd/5-x` with a changed `a.txt`, and the repository has a pre-commit hook that succeeds
- **THEN** the hook has run, and neither the commit message nor the run state says that hooks were skipped

#### Scenario: a hook that fails after the checkout

- **WHEN** the run of #5 ended on `idd/5-x`, which has one commit, and the repository has a post-checkout hook that fails
- **THEN** `settle` exits 0 with the working tree on the default branch

##### Example: endings of the single-issue pipeline

The endings of the single-issue pipeline on the PR path that the inventory of its writers gives, and the mechanisms of the target repository that bear on them (commit hooks that reject what was left; ignore rules that the issue's branch and the default branch do not share). In every row the repository holds, before the run, a tracked `a.txt`, a tracked `tools/run.sh`, a tracked `tools/.gitignore` with the rule `.env`, a top `.gitignore` with the rule `local/`, and two files git ignores: `tools/.env` and `local/settings.json`. For each: what it leaves, what `settle` makes of it, and what a later rest run does with #5 given the state the ending leaves on GitHub. In the last column, `handed out` means #5 is a candidate without a local branch and `next` hands it out; `existing work` means it is a candidate with a kept branch and `next` records it as existing work; `not run: <class>` means it is no longer a candidate and `start` lists it under that class.

- **GIVEN** a run in which #5 was handed out, ended in the way the row names, and was recorded
- **WHEN** `settle --issue 5` runs, and then a new run is started
- **THEN** the exit code, the branches of #5 and the later run are those of the row; on exit 0 the working tree is on the default branch and `git status --porcelain` prints nothing; and with either exit code `tools/.env`, `local/settings.json` and every other file that git ignored when #5 was handed out are where they were, with the same content, and every other file that was in the working tree before `settle` is unchanged, in the commit `settle` made, in a stash it recorded, among the records it discarded, or holds the content of the default branch

| Ending | The working tree is on | What the ending leaves | Exit | Branches of #5 afterwards | A later rest run |
| --- | --- | --- | --- | --- | --- |
| `closed-before-start`: the issue was closed before any step ran | `main` | nothing | 0 | none | #5 is closed |
| `existing-work`: the existing-work check answered `resume` or `blocked` | `main` | nothing | 0 | none | handed out |
| `stop-before-download`: diagnose stopped before it downloaded anything | `idd/5-x`, no commit | nothing | 0 | none | handed out |
| `stop-after-diagnose`: the issue stopped after diagnose and before its first commit; it has no attachments | `idd/5-x`, no commit | the untracked manifest, written by `process-attachments.sh download` | 0 | none | handed out |
| `stop-after-diagnose-attachments`: the same, and the issue has one attachment that git does not ignore | `idd/5-x`, no commit | the untracked manifest and the downloaded file, both written by `process-attachments.sh download` | 0 | none | handed out |
| `stop-after-diagnose-ignored-attachments`: the same, and git ignores the downloaded files but not the manifest | `idd/5-x`, no commit | the untracked manifest, which lists one file | 0 | none | handed out |
| `stop-after-diagnose-tracked-manifest`: as `stop-after-diagnose`, and the manifest was already committed on the default branch by an earlier run | `idd/5-x`, no commit | the tracked manifest, changed by `process-attachments.sh download` | 0 | none | handed out |
| `stop-after-diagnose-failed-download`: as `stop-after-diagnose-attachments`, and the download broke off part of the way | `idd/5-x`, no commit | the untracked manifest, which lists the file as a failed download, and the part of the file that arrived | 0 | none | handed out |
| `stop-after-diagnose-foreign-file`: as `stop-after-diagnose`, and the folder also holds `notes.txt`, which the manifest does not list | `idd/5-x`, no commit | the untracked manifest and `notes.txt` | 0 | `idd/5-x`, with a commit that holds both paths | existing work |
| `meeting`: the meeting unwind committed the attachment folder on the branch and checked out the default branch; the newest Diagnosis says meeting | `main` | nothing; `idd/5-x` has one commit | 0 | `idd/5-x` | not run: meeting |
| `stop-in-implement`: implement or the spec steps stopped part of the way | `idd/5-x`, one commit | a changed `a.txt`, a new `openspec/changes/idd-5-x/proposal.md`, and the untracked manifest | 0 | `idd/5-x`, with a commit that holds `a.txt` and the proposal and not the manifest | existing work |
| `stop-in-implement-attachments`: implement stopped part of the way, and the issue has one attachment that git does not ignore | `idd/5-x`, one commit | a changed `a.txt`, the untracked manifest and the downloaded file | 0 | `idd/5-x`, with a commit that holds `a.txt`, the manifest and the file | existing work |
| `stop-in-implement-hooks-reject`: implement stopped part of the way, and a pre-commit hook of the repository rejects what it left | `idd/5-x`, one commit | a changed `a.txt` | 0 | `idd/5-x`, with a commit that holds `a.txt` and was made without the hooks | existing work |
| `stop-in-implement-ignored-files`: a commit of the issue added the ignore rule `coverage/`, and its run wrote `coverage/report.txt` | `idd/5-x`, one commit | nothing git shows on that branch; `coverage/report.txt`, ignored there | 0 | `idd/5-x`; a stash entry holds `coverage/` | existing work |
| `stop-before-commit-ignored-files`: the issue stopped before its first commit; `origin/main` has the ignore rule `coverage/`, the local `main` lacks it and has a commit of its own, and the run wrote `coverage/report.txt` | `idd/5-x`, no commit | nothing git shows on that branch; `coverage/report.txt`, ignored there | 0 | none; a stash entry holds `coverage/` | handed out |
| `stop-rule-deleted`: a commit of the issue deleted `tools/` with its `.gitignore`, and the issue stopped | `idd/5-x`, one commit | nothing of the run; `tools/.env`, which that branch no longer ignores | 0 | `idd/5-x` | existing work |
| `merged-rule-deleted`: the same commit, squash-merged, and the issue closed | `idd/5-x`, one commit, with an upstream; `origin/main` has the squash commit | nothing of the run; `tools/.env`, which neither branch ignores any more | 0 | `idd/5-x`; `tools/.env` is in the local exclude file | #5 is closed |
| `stop-rule-rewritten`: a commit of the issue rewrote the top `.gitignore` without the rule `local/`, and the issue stopped | `idd/5-x`, one commit | nothing of the run; `local/settings.json`, which that branch no longer ignores | 0 | `idd/5-x` | existing work |
| `local-default-rule`: the local `main` has a commit of its own with the ignore rule `settings.local.json`, the file was there before the run, and the issue stopped before its first commit | `idd/5-x`, no commit | nothing of the run; `settings.local.json`, which that branch does not ignore | 0 | none | handed out |
| `stop-tracks-file-from-before`: a commit of the issue dropped the rule `local/` and added `local/settings.json`, and the issue stopped | `idd/5-x`, one commit | nothing of the run; `local/settings.json`, which that branch tracks | 0 | `idd/5-x` | existing work |
| `stop-hook-stages-everything`: implement stopped part of the way after a commit that deleted `tools/`, and a pre-commit hook of the repository stages every file | `idd/5-x`, one commit | a changed `a.txt`; `tools/.env`, which that branch no longer ignores | 0 | `idd/5-x`, with a commit that holds `a.txt` and was made without the hooks | existing work |
| `stop-after-verify-failed`: verify ended with findings that block, and the issue body lists them under `### Blocking` | `idd/5-x`, one commit | the untracked manifest and one new line in the tracked `.claude/.idd/routing-stats.jsonl` | 0 | `idd/5-x`, with a commit that holds the log and not the manifest | not run: blocked |
| `stop-at-close-stage`: verify was clean, the issue was pushed and stopped before the merge; its phase is `verified` | `idd/5-x`, one commit, with an upstream | the same as `stop-after-verify-failed` | 0 | `idd/5-x`, with a commit that holds the log | not run: verified |
| `merged-and-closed`: the pull request was squash-merged and the issue closed | `idd/5-x`, one commit, with an upstream; `origin/main` has the squash commit | a changed tracked manifest and one new line in the tracked `.claude/.idd/routing-stats.jsonl` | 0 | `idd/5-x`, with a commit that holds the log and not the manifest | #5 is closed |
| `on-another-branch`: the pipeline ended on a branch that is neither the default branch nor a branch of #5 | `wip` | nothing | 3 | unchanged | — |
| `leftover-on-default`: something was left on the default branch | `main` | an untracked `b.txt` | 3 | unchanged | — |
| `never-committed-place`: a file whose writer keeps it out of git is not ignored | `idd/5-x`, one commit | an untracked `.claude/.idd/tree-lock` and a changed `a.txt` | 3 | unchanged, no new commit | — |
| `file-the-default-branch-tracks`: a commit of the issue stopped tracking `a.txt` and added an ignore rule for it, and its run wrote `a.txt` | `idd/5-x`, one commit | nothing git shows on that branch; `a.txt`, ignored there and tracked on `main` | 0 | `idd/5-x`; a stash entry holds `a.txt` | existing work |
| `merged-file-untracked`: the same commit with `a.txt` left as it was, squash-merged, and the issue closed | `idd/5-x`, one commit, with an upstream; `origin/main` has the squash commit | nothing git shows on that branch; `a.txt`, ignored there | 0 | `idd/5-x` | #5 is closed |

##### Example: leftovers on the issue's own branch are kept there

- **GIVEN** #5 recorded as stopped, the working tree on `idd/5-x` with a changed tracked file `a.txt` and the untracked `.claude/.idd/attachments/issue-5/_manifest.json`, and the remote default branch `main` one commit ahead of the local one
- **WHEN** `settle --issue 5` runs, and then `report`
- **THEN** `settle` exits 0, `idd/5-x` has one new commit that holds `a.txt` and does not hold the manifest, the manifest no longer exists, the working tree is on `main`, clean, at the commit of `origin/main`, and the report names `idd/5-x`, that commit and `a.txt` under the entry of #5

##### Example: a leftover on the default branch stops the run

- **GIVEN** #5 recorded as stopped, the working tree on `main` with an untracked file `b.txt`
- **WHEN** `settle --issue 5` runs
- **THEN** it exits 3, its reason line names `b.txt`, and no commit was made

##### Example: a file IDD keeps out of git is never committed

- **GIVEN** #5 recorded as stopped, the working tree on `idd/5-x` with an untracked file `.claude/.idd/tree-lock` that no ignore rule covers, and a changed tracked file `a.txt`
- **WHEN** `settle --issue 5` runs
- **THEN** it exits 3, its reason line names `.claude/.idd/tree-lock`, and `idd/5-x` has no new commit

##### Example: a local default branch with commits of its own does not stop the run

- **GIVEN** #5 recorded as stopped, the working tree on `idd/5-x`, which has one commit and nothing changed, and the local `main` one commit ahead of `origin/main`
- **WHEN** `settle --issue 5` runs
- **THEN** it exits 0, the working tree is on `main`, and `main` still has its own commit

##### Example: an empty issue branch is deleted

- **GIVEN** #5 recorded as stopped, the working tree on `idd/5-x`, which has no commit of its own, no upstream, and nothing changed
- **WHEN** `settle --issue 5` runs, and then `report`
- **THEN** `settle` exits 0, the branch `idd/5-x` no longer exists, the working tree is on `main`, and the report names no branch under the entry of #5

##### Example: next waits for settle

- **GIVEN** a run with candidates #5 and #9, in which #5 was handed out and recorded as stopped and `settle` was not called
- **WHEN** `next` is called, then `settle` for #5, then `next` again
- **THEN** the first `next` exits 1 and its reason line names #5, and the second `next` hands out #9

##### Example: a shared log is committed and named as such

- **GIVEN** #5 recorded as closed, the working tree on `idd/5-x`, which has one commit and an upstream, with one new line in the tracked file `.claude/.idd/routing-stats.jsonl`
- **WHEN** `settle --issue 5` runs, and then `report`
- **THEN** `settle` exits 0, `idd/5-x` has one new commit that holds `.claude/.idd/routing-stats.jsonl`, and the report names that branch, that commit and that path under the entry of #5 and says that the path is a log shared by all issues

##### Example: an interrupted settle keeps its commit

- **GIVEN** #5 recorded as stopped, the working tree on `idd/5-x` with a changed tracked file `a.txt`, and an `origin` that cannot be reached
- **WHEN** `settle --issue 5` runs, `origin` becomes reachable again, and `settle --issue 5` runs a second time
- **THEN** the first call exits 3 after it committed `a.txt` on `idd/5-x`, the second call exits 0, and the run state holds `idd/5-x` as kept with the commit of the first call and the path `a.txt`

##### Example: a commit the run state missed is found again

- **GIVEN** the state of the Example above after its first call, from which the record of the kept commit was then removed
- **WHEN** `settle --issue 5` runs again with `origin` reachable
- **THEN** it exits 0 and the run state holds `idd/5-x` as kept with the commit of the first call and the path `a.txt`

##### Example: commit hooks that reject the leftovers are skipped for that commit

- **GIVEN** #5 recorded as stopped, the working tree on `idd/5-x` with a changed tracked file `a.txt`, in a repository whose hook rejects the commit

  | the hook | what it does |
  | --- | --- |
  | `pre-commit` | exits 1 |
  | `prepare-commit-msg` | exits 1 |
  | `pre-commit` | writes `formatted` into `a.txt`, then exits 1 |
  | `pre-commit`, from git's configuration (`hook.lint.event`) | exits 1 |
  | `prepare-commit-msg`, from git's configuration | exits 1 |
  | `pre-commit`, from git's configuration, and a `pre-commit` file | both exit 1 |
  | `pre-commit`, from git's configuration, under the name `my lint` | exits 1 |
  | `prepare-commit-msg`, from git's configuration, under the name `my lint` | exits 1 |

- **WHEN** `settle --issue 5` runs, and then `report`
- **THEN** in each row `settle` exits 0, `idd/5-x` has one new commit that holds `a.txt` (in the third row with the content `formatted`; the last five rows apply on a git that has hooks from its configuration), the body of its message says that the commit hooks were skipped, the working tree is on `main` and clean, and the report says under the entry of #5 that the commit was made without the repository's commit hooks

##### Example: files that only the issue's branch ignores are stashed

- **GIVEN** #5 recorded as stopped, the working tree on `idd/5-x`, whose one commit adds the ignore rule `coverage/`, and the files `coverage/report.txt` and `coverage/html/index.html`
- **WHEN** `settle --issue 5` runs, then `report`, and then the stash commit the report names is applied on `idd/5-x`
- **THEN** `settle` exits 0, the working tree is on `main` and `git status --porcelain` prints nothing, one stash entry has the message `idd rest: files of #5 that only idd/5-x ignores`, the report names that stash commit and `coverage/` under the entry of #5, and after the stash is applied `coverage/report.txt` is there again with its content

##### Example: a file the default branch tracks is not overwritten

- **GIVEN** `local/settings.json` with the content `mine`, which git ignores, in the working tree before the run; #5 recorded as stopped, the working tree on `idd/5-x`, which has one commit; and `origin/main` with a new commit, made elsewhere, that tracks `local/settings.json`
- **WHEN** `settle --issue 5` runs, `idd-all` ends the run, and a person then runs the checkout the reason gives, moves away the file it names, runs it again and starts a new run
- **THEN** `settle` exits 3 with the working tree on `idd/5-x` and `local/settings.json` still holding `mine`, no stash was made, its reason line gives `git checkout --no-overwrite-ignore main`, that checkout fails and names `local/settings.json` while the file is in the way, and the new run starts. With four such files under `local/` whose names are too long for the reason line, that checkout names all four in full, and after `local/` is moved away each of the four still holds `mine`

##### Example: a file the issue stopped tracking does not stop the run

- **GIVEN** #5 recorded with the outcome of the row, the working tree on `idd/5-x`, whose one commit stops tracking `a.txt` and adds the ignore rule `a.txt`

  | the issue | `a.txt` in the working tree | `settle` | afterwards |
  | --- | --- | --- | --- |
  | stopped | `the run wrote this` | exits 0; one stash entry has the message `idd rest: files of #5 that idd/5-x ignores and the default branch tracks` and holds `a.txt` | `a.txt` on `main` holds what `main` has; the report names the stash commit, and applied on `idd/5-x` it gives `the run wrote this` back |
  | squash-merged and closed | as the issue left it | exits 0; no stash entry | `main` is at `origin/main` and does not track `a.txt`; `a.txt` is there with the content it had |

- **WHEN** `settle --issue 5` runs, and then `next`
- **THEN** the outcome is that of the row, and `next` hands out #9

##### Example: a file that was there before the run is left where it is

- **GIVEN** a repository whose `tools/.gitignore` has the rule `.env`, with the file `tools/.env` holding `TOKEN=ghp_secret` before the run, and a pre-commit hook that rejects a staged change holding `ghp_`; #5 handed out by `next`; `idd/5-x` with one commit that deletes `tools/`, a changed tracked file `a.txt`, and #5 recorded as stopped
- **WHEN** `settle --issue 5` runs, and then `report`
- **THEN** `settle` exits 0, `idd/5-x` has one new commit that holds `a.txt` and does not hold `tools/.env`, the hook has run and accepted that commit, `tools/.env` is in the working tree with `TOKEN=ghp_secret`, the working tree is on `main` and `git status --porcelain` prints nothing, and the report does not name `tools/.env`

##### Example: a file from before that the issue starts to track is put back

- **GIVEN** a repository whose `.gitignore` has the rule `package-lock.json`, with the file `package-lock.json` holding `{"lock": "MINE"}` before the run; #5 handed out by `next`; `idd/5-x` with one commit that empties `.gitignore` and adds `package-lock.json`; and #5 recorded as stopped

  | `package-lock.json` in the working tree when `settle` begins | afterwards |
  | --- | --- |
  | as the issue committed it | `{"lock": "MINE"}` |
  | changed to `{"lock": "MINE, edited"}` and not committed | `{"lock": "MINE, edited"}` |

- **WHEN** `settle --issue 5` runs, then `report`, and then `idd/5-x` is deleted
- **THEN** in each row `settle` exits 0, makes no commit and prints `package-lock.json` as returned, the working tree is on `main` and `git status --porcelain` prints nothing, no folder is left below the state folder, `package-lock.json` is in the working tree with the content of the row, the report says that `settle` put it back, and it is still there after the branch is deleted

##### Example: a file set aside is put back when the checkout fails

- **GIVEN** a repository whose `.gitignore` has the rule `local/`, with `local/settings.json` holding `mine` and `local/notes.txt` before the run; #5 handed out by `next`; `idd/5-x` with one commit that adds `local/notes.txt`; `local/notes.txt` then changed to `notes, edited` and not committed; a newer commit on `origin/main` that tracks `local/settings.json`; and #5 recorded as stopped
- **WHEN** `settle --issue 5` runs
- **THEN** it exits 3 because the checkout would write over `local/settings.json`, the working tree is on `idd/5-x` with `git status --porcelain` printing ` M local/notes.txt` as before, `local/notes.txt` holds `notes, edited`, `local/settings.json` holds `mine`, and no folder is left below the state folder

##### Example: a file put back that the default branch does not ignore goes into the local exclude file

- **GIVEN** the repository of the first Example of this group; #5 handed out by `next`; `idd/5-x` with one commit that adds `package-lock.json` and leaves `.gitignore` alone; a newer commit on `origin/main` that empties `.gitignore`; and #5 recorded as stopped
- **WHEN** `settle --issue 5` runs
- **THEN** it exits 0, `package-lock.json` is in the working tree with `{"lock": "MINE"}`, the run state records the path both as returned and as added to the local exclude file, `.git/info/exclude` has the line `/package-lock.json`, and the working tree is on `main` with nothing for `git status --porcelain` to print

##### Example: a changed file from before that the merged issue tracks stays as it is

- **GIVEN** the repository and the branch of the first Example of this group; `idd/5-x` pushed, squash-merged on `origin/main`, and #5 closed and recorded so; and `package-lock.json` then changed in the working tree to `{"lock": "MINE, edited"}`
- **WHEN** `settle --issue 5` runs
- **THEN** it exits 3 with the working tree on `main`, where `git status --porcelain` prints ` M package-lock.json`: the default branch tracks the file by now, so it is not set aside; it holds `{"lock": "MINE, edited"}`, and no folder is left below the state folder

##### Example: a settle that was killed with a file set aside

- **GIVEN** the repository and the branch of the first Example of this group, #5 recorded as stopped, and what a `settle` leaves that was killed after it had set the file aside: the folder `rest-held-5` below the state folder with its list and the file, and no `package-lock.json` in the working tree

  | what happens next | outcome |
  | --- | --- |
  | `settle --issue 5` runs, with the working tree still on `idd/5-x` | exit 0; the file is back with `{"lock": "MINE"}`, recorded as returned; the folder is gone; the working tree is clean on `main` |
  | the working tree is switched to `main`, then `settle --issue 5` runs | the same |
  | `report` ends the run, the working tree is switched to `main`, and `start` runs | the report names the folder; `start` exits 3 and names the folder; the file is still in the folder; with the file moved back and the folder removed, `start` exits 0 |
  | the working tree is switched to `main`, a `package-lock.json` with the same content is written there, and `settle --issue 5` runs | exit 0; the folder is gone |
  | the same with a `package-lock.json` that holds `OTHER` | exit 3; the reason names the folder; the file in the working tree holds `OTHER` and the file in the folder holds `{"lock": "MINE"}` |
  | the list in the folder names `../escaped.txt` as the place of the file, the working tree is switched to `main`, and `settle --issue 5` runs | exit 3; no file is written outside the working tree, and the file is still in the folder |

- **WHEN** the steps of the row happen
- **THEN** the outcome is that of the row

##### Example: a hook that stages everything does not put a file from before into the commit

- **GIVEN** a repository whose `tools/.gitignore` has the rule `.env`, with the file `tools/.env` holding `TOKEN=ghp_secret` before the run; #5 handed out by `next`; `idd/5-x` with one commit that deletes `tools/`, a changed tracked file `a.txt`, and #5 recorded as stopped

  | the pre-commit hook of the repository |
  | --- |
  | runs `git add -A` and succeeds |
  | runs `git add -A` and fails |

- **WHEN** `settle --issue 5` runs
- **THEN** in each row it exits 0, `idd/5-x` has one new commit that holds `a.txt` and does not hold `tools/.env`, no commit of `idd/5-x` holds `tools/.env`, the body of the new commit's message says that a hook staged files that were in the working tree before the run, the run state says the hooks were skipped, `tools/.env` is in the working tree with `TOKEN=ghp_secret`, and the working tree is on `main` with nothing for `git status --porcelain` to print

##### Example: a file from before that the run removed is named in the report

- **GIVEN** the repository of the Example above without a hook; #5 handed out by `next`; the working tree on `idd/5-x`, where the run deleted the folder `tools/` from the disk; and #5 recorded as stopped
- **WHEN** `settle --issue 5` runs, and then `report`
- **THEN** `settle` prints `tools/.env` as missing, and the report says under the entry of #5 that `tools/.env` was in the working tree when the issue was handed out and was gone when its run ended

##### Example: a path the default branch no longer ignores goes into the local exclude file

- **GIVEN** the repository of the Example above without the hook, candidates #5 and #9, #5 handed out by `next`; `idd/5-x` with one commit that deletes `tools/`, pushed; `origin/main` with the squash commit of that change; and #5 closed and recorded
- **WHEN** `settle --issue 5` runs, then `next`, and at the end of the run `report`
- **THEN** `settle` exits 0 and prints `tools/.env` as excluded, `.git/info/exclude` holds the line `/tools/.env` under a comment line that names #5, `tools/.env` still holds `TOKEN=ghp_secret`, `git status --porcelain` prints nothing, `next` hands out #9, and the report says under the entry of #5 that `tools/.env` was there before the run, is no longer ignored by the default branch and was added to `.git/info/exclude`

##### Example: what a rejecting hook wrote is looked at again

- **GIVEN** #5 recorded as stopped, the working tree on `idd/5-x` with a changed tracked file `a.txt`, and a pre-commit hook that writes the file of the row and exits 1

  | the hook writes | `settle` |
  | --- | --- |
  | `lint.log` | exits 0; the commit made without the hooks holds `a.txt` and `lint.log`, and the run state names both |
  | `.claude/.idd/tree-lock`, which no ignore rule covers | exits 3; its reason line names `.claude/.idd/tree-lock`; `idd/5-x` has no new commit |

- **WHEN** `settle --issue 5` runs
- **THEN** the outcome is that of the row

##### Example: a settle that stopped gives no delete step for a pushed branch

- **GIVEN** #5 recorded as stopped, the working tree on `idd/5-x`, which has one commit and an upstream, with a changed tracked file `a.txt`, an untracked `stray.txt` written by a post-checkout hook of the repository, and a second local branch `idd/5-y` with no commit of its own and no upstream
- **WHEN** `settle --issue 5` runs, and then `stop` and `report`
- **THEN** `settle` exits 3 after it committed `a.txt` on `idd/5-x`; the line of `idd/5-x` in the report does not say that deleting it lets a later rest run start the issue over; and the report names `idd/5-y` as a branch of #5 without a commit of its own whose deletion lets a later rest run start the issue over

##### Example: the steps a stop names lead to a run that starts

- **GIVEN** #5 recorded as stopped, and the working tree as the row says

  | the stop | the working tree | the steps the reason names, as a person takes them |
  | --- | --- | --- |
  | a place that is never committed | on `idd/5-x`, with an untracked `.claude/.idd/tree-lock` that no ignore rule covers and a changed `a.txt` | add the lock to `.git/info/exclude`, commit `a.txt` on `idd/5-x`, `git checkout --no-overwrite-ignore main` |
  | another branch | on `wip`, with a changed `a.txt` | commit `a.txt` on `wip`, that checkout |
  | a leftover on the default branch | on `main`, with an untracked `b.txt` | move `b.txt` away |
  | an unfinished merge | on `idd/5-x`, in a merge that stopped on a conflict in `a.txt` | abort the merge, that checkout |
  | an unfinished merge on the default branch | on `main`, which has a commit of its own, in a merge that stopped on a conflict in `a.txt` | abort the merge |
  | unmerged paths | on `idd/5-x`, after a stash was applied and conflicted in `a.txt` | `git add a.txt`, commit, that checkout |
  | not clean after the checkout | on `idd/5-x`, which has one commit, in a repository whose post-checkout hook writes `stray.txt` | move `stray.txt` away |
  | no usable default branch in the run state | on `idd/5-x`, with a changed `a.txt`, and the default branch in the run state replaced by text that is no branch name | commit `a.txt`, that checkout |
  | `origin` cannot be reached | on `idd/5-x`, with a changed `a.txt`, and the URL of `origin` points nowhere | set the URL of `origin` back |
  | the fast-forward | on `main`, where the issue ended; `origin/main` has a new commit that tracks `build.log`, and the working tree holds, from before the run, a `build.log` with the content `local, ignored` that `.git/info/exclude` ignores | run `git merge --ff-only --no-overwrite-ignore origin/main`, move away the `build.log` it names, run it again |

- **WHEN** `settle --issue 5` runs, `idd-all` ends the run with `stop` and `report`, the person takes the steps of the row, and a new run is started
- **THEN** in each row `settle` exits 3 with a reason line that names those steps, and the new run starts; in the last row `build.log` still holds `local, ignored` when `settle` has stopped, and the command the reason gives fails and names `build.log` while the file is in the way; in the rows `a leftover on the default branch` and `origin cannot be reached`, the reason line names `main` once

##### Example: a commit that fails without a commit hook is not made again

- **GIVEN** #5 recorded as stopped, the working tree on `idd/5-x` with a changed tracked file `a.txt`, and a git whose first commit fails for a reason that is no hook's

  | the repository has | `settle` |
  | --- | --- |
  | no commit hook | exits 3; its reason line says that what the run left could not be committed; `idd/5-x` has no new commit |
  | a `pre-commit` hook that succeeds | exits 0; the body of the commit message says that the commit hooks were skipped |

- **WHEN** `settle --issue 5` runs
- **THEN** the outcome is that of the row

##### Example: a second keep commit keeps the first

- **GIVEN** #5 recorded as stopped, the working tree on `idd/5-x` with a changed tracked file `a.txt`, and a first `settle --issue 5` that committed `a.txt` and then stopped before the checkout
- **WHEN** an untracked file `b.txt` appears, `settle --issue 5` runs again, and then `report`
- **THEN** the second call exits 0, the run state holds `idd/5-x` as kept with the commit of the second call, the commit of the first call as the earlier one, and the paths `a.txt` and `b.txt`, and the report names both commits on the line of `idd/5-x`. The run state holds the same earlier commit and paths when the record of the first commit was removed from it before the second call

##### Example: a stash whose branch was deleted

- **GIVEN** `origin/main` with the ignore rule `coverage/`, a local `main` that lacks that rule and has one commit of its own, #5 recorded as stopped, the working tree on `idd/5-x`, which was created from `origin/main` and has no commit of its own, and the file `coverage/report.txt`
- **WHEN** `settle --issue 5` runs, then `report`, and then the stash commit the report names is applied in the working tree
- **THEN** `settle` exits 0, the branch `idd/5-x` no longer exists, `settle` prints one stash, with `kept` false, the report says on the line of that stash that the branch is deleted and that the files are to be moved out of the working tree again before the next run, and does not say `on that branch`; after the stash is applied `coverage/report.txt` is there again, and with `coverage/` moved out a new run starts

##### Example: a stash the run state missed is found again

- **GIVEN** the state of the Example "files that only the issue's branch ignores are stashed" after `settle`, from which the record of the stash was then removed and the attempt marked as not settled
- **WHEN** `settle --issue 5` runs again, and then once more
- **THEN** the first of the two exits 0 and prints one stash with the commit of the first stash, the path `coverage/html/index.html` among the files it holds, and `kept` true, and the second prints the same stash commit

##### Example: a long branch name does not cut off the next step

- **GIVEN** #5 recorded as stopped, the working tree on `idd/5-` followed by a 40-character slug, with an untracked `.claude/.idd/tree-lock` that no ignore rule covers and five untracked files with long names in `.claude/worktrees/`
- **WHEN** `settle --issue 5` runs
- **THEN** it exits 3, its reason line is no longer than the helper's limit for a reason, contains the branch name once, contains `(same flags)`, and ends with the number of the paths it did not name. With a default branch whose name is 40 characters long and a branch of #5 whose name is 60 characters long, the reason line of the same stop is no longer than the limit and holds `git checkout --no-overwrite-ignore` with the whole name of the default branch, followed by the instruction to run the same command again. With a default branch named `ma;in`, `a$(touch${IFS}made-by-the-name)` or a name of 41 characters, the command in the reason line holds `<the default branch>` and the line does not hold that name

##### Example: the working tree below the top of the repository

- **GIVEN** a repository whose folder `sub/` is the directory `idd-all` runs in, #5 recorded as stopped, the working tree on `idd/5-x` with no commit of its own, and the untracked `sub/.claude/.idd/attachments/issue-5/_manifest.json` as the only leftover
- **WHEN** `settle --cwd <repository>/sub --issue 5` runs
- **THEN** it exits 0, that manifest no longer exists, and the branch `idd/5-x` no longer exists

##### Example: a worktree folder at the top is never committed from below

- **GIVEN** the repository of the Example above, #5 recorded as stopped, the working tree on `idd/5-x`, and an untracked file `.claude/worktrees/w/a` at the top of the repository that no ignore rule covers
- **WHEN** `settle --cwd <repository>/sub --issue 5` runs
- **THEN** it exits 3 and its reason line names `.claude/worktrees/w/a`

##### Example: every location the plugin names is in the inventory

- **GIVEN** the skills and the scripts of the plugin, and `references/working-tree-writers.md`
- **WHEN** every path that begins with `.claude/` in them is reduced to its location (`.claude/<name>`, or `.claude/.idd/<name>`)
- **THEN** the inventory names each of these locations

---
### Requirement: A rest run keeps its review flag

A rest run started with `--review` stops every issue at verified; a run that loses the flag merges and closes instead. The flag SHALL therefore live in the run state and reach the close stage without passing through anything a context compaction can lose.

`start` SHALL store the review flag of a new run. When it resumes a run, review is on when the stored run has it or this `start` gives it: the flag can be added to a run and cannot be dropped from it, and `start` SHALL say so when the two differ. Ending the run with `report` is the way to drop it. When `start` adds the flag to a run that has an issue in flight, it SHALL say that a close stage already running for that issue is not stopped by it: the close stage reads the flag once, when it starts. A state file that cannot be used does not lose the flag by being replaced: `start` does not replace such a file within 24 hours of its last write (requirement "Start prints the list and resumes an unfinished run").

`next` SHALL print the review flag of the run (`"review": "yes"` or `"no"`) with every issue it hands out, in flight or not. `idd-all` SHALL take the review flag of each issue from there.

`close-stage.py init` records the run of one issue, and `close-stage.py run` merges when that record says review is off. Both SHALL read the state of the rest run at their own `--cwd`. `init` SHALL refuse to record review as off for an issue that such a run with review on has in flight: it SHALL exit with a usage error and write no run state, so that `run` finds none and stops at verified. Its message SHALL name both ways out: give `--review yes`, or, when the issue was named by a person while that rest run is unfinished, end the rest run first. `run` SHALL stop without merging for an issue that such a run with review on has in flight, whatever the record of that issue says: the flag can be added to the run after `init` recorded the issue. `run` reads that state once, when it starts.

A rest run state that is older than 24 hours, or that has another issue in flight, changes neither of the two. The 24 hours count from the last time the rest run wrote its state, which it does at every hand-out, record and settle; a run that has written nothing for that long is over as far as this check goes, as it is for `start`. A rest run state that cannot be read does not change what `init` does; `run` SHALL stop without merging when such a file was changed in the last 24 hours, because the review flag of that run is then unknown, and its reason SHALL say so.

Both helpers keep their state below `--cwd`. A rest run at another `--cwd` of the same repository is not seen by `close-stage.py`; `idd-all` gives both helpers the same `--cwd`.

#### Scenario: the flag is printed for an issue in flight

- **WHEN** a run started with `--review yes` handed out #5 and `next` is called again before an outcome is recorded
- **THEN** `next` prints #5 with `in_flight` true and `"review": "yes"`

##### Example: the review flag across a resumed run

| the unfinished run was started with | this start gives | review of the run afterwards | start says the flag differs |
| --- | --- | --- | --- |
| `--review yes` | `--review yes` | yes | no |
| `--review yes` | `--review no` | yes | yes |
| `--review no` | `--review yes` | yes | yes |
| `--review no` | `--review no` | no | no |

- **GIVEN** a run state less than 24 hours old that was started as the first column says, and candidate #5
- **WHEN** `start --path PR` runs with the flag of the second column, and then `next`
- **THEN** `next` prints the review of the third column, and `start` printed a line about the flag exactly when the fourth column says yes

##### Example: the close stage cannot be told that review is off

| the rest run in the working tree | `init --issue 5 --review` | exit | a run state for #5 exists |
| --- | --- | --- | --- |
| review on, #5 in flight | `no` | 64 | no |
| review on, #5 in flight | `yes` | 0 | yes |
| review off, #5 in flight | `no` | 0 | yes |
| review on, #9 in flight | `no` | 0 | yes |
| none | `no` | 0 | yes |

- **GIVEN** a working tree with the rest run state of the first column
- **WHEN** `close-stage.py init` runs for issue 5 with the review value of the second column and otherwise valid arguments
- **THEN** the exit code and the run state of #5 are those of the row

##### Example: review added while an issue is in flight

| the run is resumed with | `close-stage.py run` for #5 |
| --- | --- |
| `--review yes` | exits 3, and its reason says that the rest run at this `--cwd` has `--review` |
| `--review no` | does not give that reason |

- **GIVEN** a rest run started with `--review no` in which #5 is in flight, and a `close-stage.py init` for #5 with `--review no` that succeeded
- **WHEN** `start` runs again with the flag of the first column, and then `close-stage.py run` for #5
- **THEN** the close stage does what the row says

#### Scenario: a rest run state that cannot be read stops the close stage

- **WHEN** #5 is in flight in a rest run, `close-stage.py init` for #5 succeeded, the rest run state is then overwritten with text that is not JSON, and `close-stage.py run` for #5 runs
- **THEN** it exits 3 and its reason says that the review flag of that run is unknown
