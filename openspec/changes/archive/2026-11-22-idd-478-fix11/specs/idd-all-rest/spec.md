## MODIFIED Requirements

### Requirement: Start prints the list and resumes an unfinished run

`rest-queue.py start --path P --review yes|no` SHALL print the number of open issues, the issue numbers of every class, and the run order, before any issue is handed out. It SHALL print issue numbers only, no issue titles. The run order it prints SHALL hold only the candidates that have neither a local branch in the repository at `--cwd` (`idd/<N>` or `idd/<N>-…`) nor a directory at the place of their directory. The candidates that have one SHALL be printed on a line of their own, which says that they are recorded as existing work when their turn comes. `start` SHALL also say that a candidate with a pull request or a branch on GitHub is recorded as existing work when its turn comes. Every reason and every time it prints from the run state SHALL be on one line, without control characters and no longer than the helper's limit for a reason, whatever the state file holds. A path it prints from the run state is printed as it is, neither shortened nor with its white space folded; a state that holds a path with a character that cannot be printed as it is, is not a state this helper can use.

`--cwd` SHALL be the top of its repository. `start` SHALL exit with code 3 before it writes anything, the state folder included, when the real path of `--cwd` is not the real path of the top of the repository that holds it, and its reason line SHALL name that top. It SHALL also exit with code 3, writing nothing, when the path of that top has a character that cannot be printed as it is (a control character, or a byte that is not UTF-8): the report names directories by their paths, and a path that cannot be shown exactly cannot be looked at and deleted. `next` SHALL refuse such a `--cwd` in the same way. The state of a run is then always where the directories of its issues show it: `R/.claude/worktrees/rest-<N>` belongs to the run whose state is below `R`.

`P` is the path that `idd-all` resolved for this invocation. Rest mode runs on the PR path only: every issue runs on a branch of its own in a directory of its own, and what it leaves is handed over as a pull request. When `P` is not `PR`, `start` SHALL exit with code 3, write nothing, and print a reason line that says rest mode needs the PR path and names what a person can do: run the same command with `--pr`, in place of `--no-pr` when the command has it, and the other flags kept, install the ralph-loop plugin when its absence is what downgraded the path, or name the issues one at a time. The reason line SHALL NOT hold a complete `/idd-all` command line: a command copied from it would lose the flags of the invocation. A new run SHALL read the default branch of the repository from GitHub and store it in the run state together with the path; `next` makes every directory on that branch. A resumed run keeps the default branch it stored.

When the working tree holds the state of a run of the same repository whose last recorded activity (start, hand-out, record or stop) is less than 24 hours old and that was not ended by `report`, the run is unfinished, and a session may be running it. `start` without `--take-over` SHALL then exit with code 4, change nothing, and say that an unfinished rest run is in this working tree, when it was last active, and that it is taken over with `start --take-over` when no other session runs it (requirement "The commands of one rest run do not overlap"). `start --take-over` SHALL resume it: the recorded attempts and a recorded stop are kept, and the attempts are not handed out again. Otherwise `start` SHALL begin a new run with no attempts, with or without `--take-over`. A state file whose start time cannot be read as a time, with an attempt that has no reason, without a stored default branch, a stored review flag or the stored digest of a token, with a version this helper does not know, or whose stored path is not `PR`, is not a state this helper can use.

Every `start` that begins or resumes a run SHALL choose a new token for the run at random, print it once, on a line of its own that begins with `token: `, and store only its SHA-256 digest in the run state. From then on the token of an earlier `start` no longer counts. No other command prints a token, and no file holds one.

A state file that this helper cannot use and that was written in the last 24 hours SHALL make `start` exit with code 3 and leave the file as it is: the review flag of that run cannot be read, and a new run in its place would drop it. The reason line SHALL name the file and say that it is to be deleted when no rest run is going on in this working tree. A state file of a run that the previous version of this helper wrote (version 5, with a token per issue) is such a file. A state that can be read and belongs to a run for another repository is not such a file. Repository names are compared without regard to letter case, as GitHub compares them. When the last activity of that run is less than 24 hours old, it is unfinished as well: `start` without `--take-over` SHALL exit with code 4, change nothing, and name its repository; `start --take-over` SHALL replace it with a new run for this repository, say whose it was, and first print what it left, as for a run that was never ended with its report. An older one is replaced by a new run in the same way without `--take-over`, and `start` does not say of it that it is older than 24 hours. A state file older than 24 hours is replaced by the new run. When that file can be read and its run was not ended by `report`, `start` SHALL first print what that run left and nobody was told: every path of the closed list of the report (requirement "Report lists what happened and ends the run") that its attempts name and at which something still is, whether or not the directory was finished.

`start` does not look at what the working tree at `--cwd` holds, and a new run begins on whatever branch it is on, with or without changes (requirement "A rest run leaves the working tree it was started in as it was").

Before it reads anything, `start` SHALL ask git whether files in `.claude/.idd/state/` would be ignored in this working tree, for the run state file and for the unattended marker in the same folder. When git would not ignore one of them, or the working tree is not a git working tree, `start` SHALL exit with code 3 and a reason line that names the folder and says how to ignore it, and SHALL write nothing: an untracked state file would show in the working tree the run was started in.

To decide the class `outsider`, the helper asks GitHub who has write access to the repository. GitHub answers that question only to an account that has write access itself. When the account that runs `idd-all` is refused (HTTP 403, other than a rate limit), the command SHALL exit with code 3 and its reason line SHALL say that rest mode needs an account with write access to the repository.

#### Scenario: calling start twice does not reset the run

- **WHEN** `start --take-over` is called during a run, after one issue was recorded
- **THEN** the recorded attempt is still present and `next`, with the token that `start` printed, does not hand that issue out

##### Example: resume within 24 hours

- **GIVEN** a run state whose last activity was 2 hours ago, in which #5 is recorded as stopped, and candidates #5 and #9
- **WHEN** `start --take-over` and then `next` are called
- **THEN** `start` says the run is resumed with 1 attempt, and `next` hands out #9

##### Example: an unfinished run is taken over only with --take-over

- **GIVEN** a run at `T` that `start` began, printing the token `K`, and in which `next` handed out #5
- **WHEN** `start` runs again without `--take-over`, then `start --take-over`, which prints the token `L`, and then `next` with `K` and `next` with `L`
- **THEN** the first `start` exits 4, its reason line says that an unfinished rest run is in this working tree and names `start --take-over`, and the bytes of the run state file are those before it; the second exits 0 and prints `L`, which is not `K`; `next` with `K` exits 4; `next` with `L` prints #5 with `in_flight` true; and no file below `T` holds `K` or `L`

##### Example: a state older than 24 hours starts a new run

- **GIVEN** a run state whose last activity was 25 hours ago, in which #5 is recorded as stopped, and candidates #5 and #9
- **WHEN** `start` and then `next` are called
- **THEN** `next` hands out #5

##### Example: a state that cannot be used

| the state file | written | `start` |
| --- | --- | --- |
| text that is not JSON | now | exits 3, names the file, and the file is unchanged |
| a state of version 5 with review on | 1 hour ago | exits 3, names the file, and the file is unchanged |
| text that is not JSON | 25 hours ago | exits 0 and begins a new run |
| a symbolic link to a usable state | 1 hour ago | exits 3, names the file, and the link is unchanged |
| a symbolic link to a usable state | 25 hours ago | exits 0, begins a new run, and the link is replaced by a file; the file the link pointed at is unchanged |

- **GIVEN** a working tree with the state file of the row, and candidate #5
- **WHEN** `start --path PR --review no` runs
- **THEN** the outcome is that of the row

##### Example: a run that was never reported is not forgotten

| the attempt of #5 in the state, last active 25 hours ago | what is at the place the attempt names | `start` prints before the list |
| --- | --- | --- |
| stopped, its directory made | the directory | the path of the directory |
| in flight, its directory not made | a folder with `partial.txt` | the path of that folder |
| in flight, its directory not made, with a temporary folder recorded | the temporary folder, and nothing at the place of the directory | the path of the temporary folder, and not the path of the directory |

- **GIVEN** a run state of the row and candidate #9
- **WHEN** `start --path PR --review no` runs
- **THEN** it exits 0, begins a new run, and before the list prints what the row says, as it is

##### Example: a run for another repository is not replaced without --take-over

| the state in `T`, last active 1 hour ago | `start --repo o/r` | `start --repo o/r --take-over` |
| --- | --- | --- |
| a run for `O/R` | exits 4 | resumes that run |
| a run for `o/other` with #5 handed out and its directory made | exits 4, and its reason line names `o/other` | begins a new run, says whose the state was, and before the list prints the directory of #5 |

- **GIVEN** a working tree `T` with the state of the row, and candidate #5
- **WHEN** `start` runs as the columns say, the first without `--take-over` and then with it
- **THEN** the outcomes are those of the row; the first `start` leaves the bytes of the state file as they were; and in the second row a `next` with the token of the run for `o/other` exits 4 afterwards

##### Example: start runs only at the top of a repository

| `--cwd` | `start` | afterwards |
| --- | --- | --- |
| `T/sub`, a folder below the top `T` | exits 3, and its reason line names `T` | no `.claude` folder below `T/sub` and no run state below `T` |
| a repository whose path holds a line feed | exits 3 | no run state below it |
| `T` | exits 0 | a run state below `T` |

- **GIVEN** a repository at `T` with the folder `T/sub`, and candidate #5
- **WHEN** `start --path PR --review no` runs with the `--cwd` of the row
- **THEN** the outcome is that of the row; and `next` with that `--cwd` exits 3 in the first two rows

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

### Requirement: Report lists what happened and ends the run

`rest-queue.py report --token K` SHALL be given the token of the run (requirement "The commands of one rest run do not overlap"). It SHALL print one report with: the issues recorded as closed; the issues recorded as stopped, each with its reason; the `needs-person` issues, each with the complete text of every open clarity row, one line per row and not shortened; the issues of every other class that was not run; and the stop reason of the run when there is one. It SHALL then delete the run state. When the open issues cannot be re-read, for whatever reason, it SHALL still print the recorded attempts, say that the list could not be read, and delete the run state.

An issue that this run handed out SHALL appear once: under closed, under stopped or as handed out without a result. It SHALL NOT appear in the list of issues waiting for a person or in the line of a class that was not run. When such an issue is `needs-person` at the time of the report, the report SHALL print its open questions under the entry of that issue, also when the issue was recorded as closed and reopened since. The report prints no text of an issue of any other class.

For the class `verified` the report SHALL say that such an issue continues when it is named (`/idd-all #N`). When at least one issue was recorded with a reason that begins with `existing work:`, the report SHALL say that such an issue is left for a person and that its reason names the pull request, the branch or the directory to look at. Under the entry of an issue recorded as closed, it SHALL print the reason when the issue was recorded with one.

The report names paths of one closed list, and no other: the directory of an issue; what was at the place of the directory of an issue when `next` found that place taken (requirement "Each issue of a rest run runs in a directory of its own"); and a temporary folder that a `next` made for the clone of an issue and that is still there. Under the entry of every issue, whether it is recorded as closed, as stopped or as in flight, the report SHALL name each such path of that issue, on a line of its own and as it is: neither shortened nor with its white space folded. When it names at least one, it SHALL say once that rest mode removes no directory; that a directory may hold work that exists nowhere else (commits that were not pushed, changes that were not committed, a stash, a tag, records of the plugin); that a person looks at it and deletes it; and that a later rest run does not take up an issue whose directory is still there. Under the entry of an issue that is in flight when `report` runs, the report SHALL name its directory and say that the issue was handed out and has no recorded outcome. When `record` found the working tree at `--cwd` changed while the issue ran, the report SHALL say which of the checked-out commit, the branch, the files and the stash changed, and that rest mode does not write there (requirement "A rest run leaves the working tree it was started in as it was").

The report tells a person to take one kind of step, and this list is closed: delete a path the report names after looking at it. A check of this capability SHALL take that step and see the result: a later run hands the issue out again while it is a candidate without other existing work. Looking at a directory, a branch, a commit or a pull request is not such a step. No line under an issue recorded as stopped SHALL tell the person to name the issue (`/idd-all #N`).

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

##### Example: the report names the directory of every issue

- **GIVEN** a run at `T` in which #5 was recorded as stopped while its directory held a changed `a.txt`, and #9 was recorded as closed
- **WHEN** `report` runs, then the directory of #5 is deleted as the report says, and a new run is started
- **THEN** the entries of #5 and #9 each name their directory; one line says that rest mode removes no directory and that a person looks at a directory and deletes it; the directory of #5 still holds the changed `a.txt` when `report` has run; no line under a stopped issue holds `/idd-all`; and `next` of the new run hands out #5

##### Example: a closed issue whose run reported a stop

- **GIVEN** a run in which #5 was recorded as closed with the reason `Stopped: /idd-close did not finish`
- **WHEN** `report` runs
- **THEN** #5 is listed under closed, followed by that reason

##### Example: the report names the directory of an issue in flight

- **GIVEN** a run at `T` in which #5 was handed out and no outcome was recorded
- **WHEN** `report` runs
- **THEN** one line names #5 as handed out without a recorded outcome, and a line under its entry names `T/.claude/worktrees/rest-5`

##### Example: the report prints a path as it is

- **GIVEN** a run at `T`, where the path of `T` holds two spaces in a row and is longer than 300 characters, in which #5 was recorded as stopped
- **WHEN** `report` runs
- **THEN** a line of the report is four spaces, a label, and `T/.claude/worktrees/rest-5` exactly

##### Example: the report names a temporary folder that is left

- **GIVEN** a run at `T` with candidates #5 and #9, a `next` that was ended after it recorded the temporary folder of the clone of #5 and before it moved the clone to its place, and then a `next` that handed out #5 again in a new temporary folder and finished
- **WHEN** `record --issue 5` and `report` run
- **THEN** the report names, under #5, its directory and the first temporary folder, and the first temporary folder is still there

### Requirement: idd-all runs rest mode as a loop over the single-issue pipeline

In rest mode `idd-all` SHALL first run, once, the steps of the single-issue pipeline that check the repository, the flags and the dependencies, and SHALL resolve the path and the interaction mode, including the step that can downgrade the path. In doing so it SHALL NOT write the unattended marker and SHALL NOT create a branch. When the configuration asks for a question about the path (`pr_policy: ask`), rest mode SHALL ask whether to start the run on the PR path and SHALL offer no other path.

It SHALL then call `rest-queue.py start` with the path it resolved and the review flag of the invocation, and with the top of the repository that holds the directory it resolved as `--cwd` (the directory the run is started in). It SHALL keep the token that `start` printed where it survives a context compaction (the task list of the run). When `start` exits with code 3, `idd-all` SHALL relay the reason line and end. When `start` exits with code 4, an unfinished run is in the working tree and a session may be running it: `idd-all` SHALL tell the user what `start` printed and end. It SHALL call `start --take-over` only when the user asks, in this conversation, for that run to be taken over: the helper cannot tell whether another session still runs it, and neither can the model. A token that is lost (not in the task list and not remembered) is told to the user, and the invocation ends.

It SHALL then repeat: `next`; change the shell's directory, in a command of its own, to the directory that `rest-queue.py where` prints, taking it from the output of `where` and not writing the path into the command, and use that directory as the working directory of the issue; `here` for that directory, that issue and the token of the run, in a separate command;  run the single-issue pipeline for the issue, with the path and the interaction mode resolved before `start`, which are neither resolved nor downgraded again for a later issue, and with the review flag that `next` printed, which decides both what is recorded for the close stage and whether the issue fixes in-scope findings and enters the close stage at all; change the shell's directory back to the directory the run was started in; `record` with the stop reason the single-issue report printed, if any. It SHALL leave the loop when `next` prints `done` or a stop reason, and SHALL then call `rest-queue.py report` and relay its output. Every `rest-queue.py` command other than `here` is given the directory the run was started in as `--cwd`; `here` and the single-issue pipeline are given the directory of the issue. Every command of the run other than `start` is given the token of the run, and so are `close-stage.py init` and `close-stage.py run` for an issue of the run (requirement "A rest run keeps its review flag"). When the skill has the model write a path into a command (the directory the run was started in, after the shell lost it), it SHALL put the path in single quotes and write a single quote in it as `'\''`.

The shell is in the directory of the issue while its pipeline runs, so that every step that goes by the shell's directory (the attachments an issue's diagnosis downloads, the routing log, the Spectra CLI, the check whether a run is unattended) works in that directory. The skill SHALL say that the sub-skills are still given `--cwd`: the reviewers of the verify step do not share the shell. When `here` exits with code 1, `idd-all` SHALL NOT run the pipeline of that issue in that directory; when its reason is the current directory, `idd-all` SHALL stop the whole run (requirement "Each issue of a rest run runs in a directory of its own"). When a command of `rest-queue.py`, `close-stage.py init` or `close-stage.py reset` exits with code 4 (the token is not the one of the run: another session has taken the run over; the lock of the run is held; or `start` found an unfinished run), or `close-stage.py run` stops because its token is not the run's or it was given none, `idd-all` SHALL end the invocation (requirement "The commands of one rest run do not overlap"): it SHALL NOT call `record`, `stop`, `report` or `next` again, SHALL NOT do the clean-up of the issue (its run state, its result, its unattended marker), and SHALL NOT call `start --take-over`. Every `close-stage.py reset` of an issue of the run SHALL be given the token of the run. A run hands out one issue at a time, so a `next` of the session that was displaced would print the same issue again. The skill SHALL say that a token a command refused is not a lost token. `idd-all` SHALL run `here` the same way before the step that pushes the branch and opens the pull request and before the step that reports and cleans up, as before the steps that diagnose, implement and verify the issue, and once more in the directory of the issue at the start of the step that records it.

The two steps of the single-issue pipeline that resolve the path and that can downgrade it SHALL each say, where they stand in the skill, that a rest run does not run them again for an issue and which values it uses instead. Wherever the skill says that a later `/idd-all` resumes an unfinished run, it SHALL say that the command is to carry the same flags. The text of the pull request an issue of a rest run opens SHALL follow the review flag `next` printed for that issue, not a value recorded earlier.

The step of the single-issue pipeline that creates the issue's branch SHALL check out in the way that does not overwrite a file git ignores (`git checkout --no-overwrite-ignore`), whether it creates the branch from `origin/<default>` or takes up a branch on the remote: `origin` can track a path that git ignores in this working tree, and a plain checkout writes over that file without a word. When a file is in the way, that step stops the issue and says so. This holds for every `/idd-all` run on the PR path, not only for rest mode.

The skill SHALL say that a rest run does not work in the working tree it was started in, and that a person or another session may go on working there while the run goes. No text of the plugin SHALL describe a step between two issues in the working tree a run was started in: no commit, stash, exclude line, checkout or branch deletion there.

A reason that `idd-all` passes to `record` or to `stop` is text from outside (a line of a report, a line this helper printed, with file names and git's words in it). `idd-all` SHALL pass it on standard input, not as a shell argument. The commands in the skill that do so SHALL work when they are run exactly as they are written there, indentation included.

In rest mode `idd-all` SHALL NOT take over work that already exists. `next` asks the existing-work check before it hands an issue out (requirement "Each issue is attempted at most once per run"). The check of the single-issue pipeline runs once more in the directory of the issue; when it returns anything but `clear` there, `idd-all` SHALL create no branch, leave the pull request untouched, ask no question, and record the issue with a reason that begins with `existing work: ` and holds the outcome the check printed and the next step for a person.

When `next` prints `in_flight` true, `idd-all` SHALL continue that issue in the `dir` it printed. When the issue already has its Phase 6 result, it goes straight to `record`. When `next` prints `branch` as `null`, the issue had not reached its own branch: `idd-all` SHALL start it again from the step that resolves the issue, the existing-work check included. Otherwise it SHALL continue the interrupted phase and SHALL NOT run the existing-work check of that issue again: the branch and the pull request the check would find are this run's own.

A run that was interrupted is resumed by taking it over: `start --take-over` with the flags of the run. Where the skill tells a person how a run is resumed, it SHALL say that the flags are to be the same and that a `start` without `--take-over` refuses while the run is unfinished.

The unattended marker of an issue is in the directory of that issue. Before `idd-all` leaves that directory to record the issue, it SHALL clear the marker there, whether or not the pipeline of the issue reached its own clean-up. It SHALL NOT clear a marker in the directory the run was started in: another session may work there.

#### Scenario: the loop ends with the report

- **WHEN** `next` prints `done`
- **THEN** `idd-all` calls `report` and starts no further issue

#### Scenario: an issue that already has a pull request is listed, not resumed

- **WHEN** the next candidate has an open pull request on its own `idd/<N>-…` branch
- **THEN** it is recorded as stopped with a reason that begins with `existing work: ` and names PR #<P>, no directory is made for it, and the following issue is handed out

##### Example: the skill names the loop commands in order

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the rest section is read
- **THEN** it contains the invocations `rest-queue.py" start`, `rest-queue.py" next`, `rest-queue.py" where`, `rest-queue.py" here`, `rest-queue.py" record`, `rest-queue.py" stop` and `rest-queue.py" report`, with `start` before `next`, `next` before `where`, `where` before `here`, `here` before `record`, and `report` last; no line of the skill holds `rest-queue.py" settle`; Step 0.1 contains the invocation `rest-queue.py" args`; the rest section states that an existing-work verdict other than `clear` is recorded with the reason `existing work: `; and Phase 6 sends a rest run back to the rest section

##### Example: the skill runs each issue in its directory

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the rest section is read
- **THEN** the step that runs the single-issue pipeline holds a fenced block that sets `CWD` from the output of the `where` invocation and holds `cd "$CWD" ||`, and a later fenced block of its own that holds the `here` invocation and no `cd`; no line of the rest section sets `CWD` to a value written between angle brackets; the step says to run the `here` block again before Phase 2, before Phase 3, before Phase 4, before Phase 5 and before Phase 6, and that a `here` that fails on the current directory stops the whole run; the step that records says to run `here` first and to end the invocation when it exits 4; the line of the `here` invocation holds `--cwd "$CWD"`; the step that records holds a line that changes the shell's directory to `"$REST_ROOT"` before the `record` invocation; the lines of the `start`, `next`, `where`, `record`, `stop` and `report` invocations hold `--cwd "$REST_ROOT"`; the lines of the `next`, `where`, `here`, `record`, `stop` and `report` invocations hold `--token "$TOKEN"`; and the step says that the sub-skills are given `--cwd`

##### Example: the skill takes the directory from where

- **GIVEN** a run at `T` in which #5 is in flight, and the fenced block of the rest section of `skills/idd-all/SKILL.md` that sets `CWD`, copied as it is
- **WHEN** a shell with `REST_ROOT`, `GITHUB_REPO`, `N` and `TOKEN` set runs it, and the path of `T` holds `$(touch made-by-the-path)`
- **THEN** the shell is in the directory of #5 afterwards and no file `made-by-the-path` exists

##### Example: the skill keeps the token of the run

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the rest section is read
- **THEN** the step that calls `start` sets `REST_ROOT` from `rev-parse --show-toplevel` and says to keep the value of the `token: ` line in the task list of the run; no line of the skill holds `next --take-over`; `start --take-over` is named only for a user who asks for the run to be taken over, and the paragraph about a lost token says to tell the user; a `start` that exits with code 4 ends the invocation; Step 0.7 ends the invocation when `init` exits 4 and does not reset then; and every `close-stage.py reset` of the skill is given the token of a rest run in rest mode

##### Example: the skill clears the unattended marker

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the rest section is read
- **THEN** the step that records holds `clear_unattended "$CWD"` before the line that changes the shell's directory back, and no line of the rest section holds `clear_unattended "$REST_ROOT"`

##### Example: the skill runs the preflight steps once

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the rest section is read
- **THEN** the numbered step before the `start` invocation names Step 0.2, Step 0.3, Step 0.35, Step 0.5 and Step 0.6 and says they run once; and the line of the `start` invocation holds `--path "$PATH_AXIS"` and `--review "$REVIEW_YN"`

##### Example: the skill continues an issue in flight

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the row of the rest section for `in_flight` true is read
- **THEN** it says to continue in the `dir` that was printed, to go to `record` when the issue has its Phase 6 result, to start again from Step 0.4 when `branch` is `null`, and otherwise to continue the interrupted phase without running Step 0.5.1 again

##### Example: the skill ends a refused run

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the row of the stop table for a `start` that exits with code 3 is read
- **THEN** it names a path that is not `PR` among the causes, and does not name a working tree that is not clean

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
- **WHEN** the first block is run by a shell with ``Stopped: the price is $5 and `date` is not run`` in the place of its placeholder, and the second block is run with `the helper stopped` in the place of its placeholder
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
- **THEN** each says that the command is to carry the same flags; every other line of the skill that says a run is resumed within 24 hours says so as well and names `--take-over`; and so does every line of the rest section that speaks of resuming a run within 24 hours, whatever its wording

##### Example: the step that creates the branch does not overwrite a file git ignores

- **GIVEN** a working tree in which `.git/info/exclude` ignores `.vscode/` and `.vscode/settings.json` holds `MINE`, and an `origin/main` whose newest commit tracks `.vscode/settings.json` with the content `TEAM`
- **WHEN** the line of Step 0.5 in `skills/idd-all/SKILL.md` that creates the branch from `origin/$DEFAULT` is run as it is written
- **THEN** that line holds `--no-overwrite-ignore`, as does the line that takes up a branch on the remote; the command fails and git names `.vscode/settings.json`; and the file still holds `MINE`

##### Example: the skill says that the starting working tree is not used

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the rest section is read
- **THEN** it says that a rest run does not work in the working tree it was started in and that a person may go on working there while the run goes

##### Example: no text describes the removed step between two issues

- **GIVEN** the texts of `skills/idd-all/SKILL.md`, `CLAUDE.md`, `references/parallel-orchestration.md` and `references/working-tree-writers.md` of the plugin, and `docs/commands.md` of the repository
- **WHEN** they are read
- **THEN** none holds `rest-queue.py settle` or `` `settle` ``, none holds the words `between two issues` in a sentence about rest mode, and `docs/commands.md` does not say that a rest run needs a clean working tree or that nothing else may work in it

##### Example: the skill handles a busy run

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the part of the rest section about stopping the whole run is read
- **THEN** one row names a command of `rest-queue.py` or `close-stage.py init` that exits with code 4, names its causes (a lock that is held, a token that is not the run's, and an unfinished run that `start` without `--take-over` finds), and says to end this invocation, to call neither `stop` nor `report`, and neither to call `next` again nor to take the run back with `start --take-over`; the step that runs `here` says that exit code 4 ends the invocation; and no sentence of the rest section sends a session whose token was refused back to `next`

### Requirement: A rest run keeps its review flag

A rest run started with `--review` stops every issue at verified; a run that loses the flag merges and closes instead. The flag SHALL therefore live in the run state and reach the close stage without passing through anything a context compaction can lose.

`start` SHALL store the review flag of a new run. When it resumes a run, review is on when the stored run has it or this `start` gives it: the flag can be added to a run and cannot be dropped from it, and `start` SHALL say so when the two differ. Ending the run with `report` is the way to drop it. When `start` adds the flag to a run that has an issue in flight, it SHALL say that a close stage already running for that issue is not stopped by it: the close stage reads the flag once, when it starts. A state file that cannot be used does not lose the flag by being replaced: `start` does not replace such a file within 24 hours of its last write (requirement "Start prints the list and resumes an unfinished run").

`next` SHALL print the review flag of the run (`"review": "yes"` or `"no"`) with every issue it hands out, in flight or not. `idd-all` SHALL take the review flag of each issue from there.

The state of a rest run is below the directory the run was started in; the close stage of an issue runs in the directory of that issue. `close-stage.py init` SHALL take `--rest-root R` and `--rest-token K`, the directory the rest run was started in and the token of that run, for an issue of a rest run, and `--rest-root none --rest-token none` for any other run; both options are required, so that a value lost on the way is a usage error and not a run without its rest. With `R`, `init` SHALL refuse with a usage error, and write no run state, unless all of these hold (closed list): `--cwd`, as given and as its real path, is the place `R/.claude/worktrees/rest-<N>` of the issue `N`; the run at `R` can be read and has `N` in flight, recorded as made in that directory; and the directory is bound to the issue: its mark and its `origin` are those recorded with the issue (requirement "Each issue of a rest run runs in a directory of its own"). When all of them hold and `K` is not the token of the run, `init` SHALL exit with code 4 and write no run state. With `R`, `init` SHALL also refuse with a usage error when the path it is given is not `PR`: an issue of a rest run runs on the PR path only. With `none`, `init` SHALL decide by the place of `--cwd` alone and SHALL NOT read the run of the issue that an earlier `init` recorded at `--cwd`, which it is about to replace: it SHALL refuse with a usage error, and write no run state, when `--cwd` is in the working tree of a rest run that has `N` in flight in a directory of its own, or in the directory of an issue of such a run. `--cwd` is in the working tree of the run at `R` when it is `R` or the top of the repository that holds it, as git names it, is `R`; and in the directory of an issue of that run when that top is `R/.claude/worktrees/rest-<M>`, whatever `M` is: a folder below either is in it too, and so is a path written with other letter case on a file system that does not tell letter case apart. `init` SHALL record `R` in the run of the issue, and no token. `run` SHALL stop without merging when that record names `R` and the run at `R` cannot be read, has ended, or does not have the issue in flight in that directory, bound to it: the review flag of the issue's rest run can no longer be read.

`run` SHALL take `--rest-token K`. When the record names `R`, `run` SHALL stop without merging when `--rest-token` is not given or `K` is not the token of the run at `R`: another session has taken the run over, and the issue is that session's. Right before it asks GitHub to merge, `run` SHALL take the lock of the run at `R` (requirement "The commands of one rest run do not overlap") and read the run again, and SHALL stop without merging when it cannot get the lock within the wait, when `K` is no longer the token of the run, or when the run no longer has the issue in flight in that directory, bound to it. It SHALL hold the lock until the merge call has returned: a `start --take-over` that comes meanwhile waits for it.

A session that was taken over writes nothing for the issue. `run` SHALL write nothing and remove nothing at `--cwd`, and exit with code 3 and say why, when it was given no token or a token that is not the token of the rest run that the record names or that has the issue in flight at `--cwd`. `close-stage.py reset --cwd D --issue N` SHALL take `--rest-token K`, and SHALL exit with code 4 and remove nothing when `D` is the directory of issue `N` that a rest run has in flight there and `K` is not the token of that run.

`close-stage.py init` records the run of one issue, and `close-stage.py run` merges when that record says review is off. `init` SHALL refuse to record review as off for an issue that a rest run with review on has in flight: it SHALL exit with a usage error and write no run state, so that `run` finds none and stops at verified. Its message SHALL name both ways out: give `--review yes`, or, when the issue was named by a person while that rest run is unfinished, end the rest run first. `run` SHALL stop without merging for an issue that such a run with review on has in flight, whatever the record of that issue says: the flag can be added to the run after `init` recorded the issue. `run` reads that state once, when it starts.

`close-stage.py rest-review --cwd C --repo O/R --issue N` SHALL print the reading as one word. This list is closed.

- `on`: the run of the issue at `C` names a rest root `R`, `C` is the place of `N` below `R`, and the run at `R` has review on and `N` in flight in `C`, bound to it.
- `off`: the run of the issue at `C` names a rest root whose run has review off and `N` in flight in `C`, bound to it; or it names none, or there is no run of the issue at `C`, and no rest run has `N` in flight in `C` or at `C`.
- `elsewhere`: the run of the issue at `C` names no rest root, or there is none, and a rest run has `N` in flight in a directory of its own, and `C` is in the working tree of that run or in the directory of one of its issues (as for `init` above). The pipeline of the issue then runs in the wrong place, or without its rest root.
- `unreadable`: the run of the issue names a rest root whose run cannot be read, has ended, or does not have `N` in flight in `C`, bound to it, or `C` is not the place of `N` below it; or a state file of a rest run that was changed in the last 24 hours is not a usable state.

`rest-review` reads and takes no token. `init` with `--rest-root none` SHALL refuse as said above whatever the review value, and its message SHALL name the directory the issue runs in. `unreadable` does not change what `init` does. `run` SHALL stop without merging for `elsewhere` and for `unreadable`, and its reason SHALL say which. Phase 5 of `idd-all` SHALL take the review of a rest run from that command and from nowhere else, and SHALL treat every word other than `off` as review: the close stage stops at verified for it, so the body of the pull request does not promise a merge.

The 24 hours count from the last time the rest run wrote its state, which it does at every hand-out and record; a run that has written nothing for that long is over as far as this check goes, as it is for `start`. Whether a file at the place of a state can be read is decided in one place, for `rest-queue.py` and `close-stage.py` alike (`scripts/lib/reststate.py`): both open a state file through one function that does not follow a symbolic link, does not wait on a file that is not a regular file (a FIFO), accepts only a regular file and takes the age from the file itself; neither reads a state file or a state folder that is a symbolic link; and a file that `start` stops on is a file whose review flag the close stage does not take either, however its `review` entry reads. A state file that is a symbolic link counts as a file that cannot be used: one changed in the last 24 hours makes `start` stop and the close stage stay at verified, and an older one is replaced by a new run.

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

| the rest run at `T` | `init --issue 5` runs in | `--rest-root` | `--review` | exit | a run state for #5 exists there |
| --- | --- | --- | --- | --- | --- |
| review on, #5 in flight | the directory of #5 | `T` | `no` | 64 | no |
| review on, #5 in flight | the directory of #5 | `T` | `yes` | 0 | yes |
| review off, #5 in flight | the directory of #5 | `T` | `no` | 0 | yes |
| review off, #5 in flight | the directory of #5 | `none` | `no` | 64 | no |
| review off, #5 in flight | `T` | `none` | `no` | 64 | no |
| review on, #5 in flight | `T` | `none` | `yes` | 64 | no |
| review on, #9 in flight | `T` | `none` | `no` | 0 | yes |
| none | `T` | `none` | `no` | 0 | yes |
| none | `T` | `T` | `no` | 64 | no |

- **GIVEN** a repository at `T` with the rest run of the first column
- **WHEN** `close-stage.py init` runs for issue 5 with `--cwd` as the second column says and the `--rest-root` and the review value of the next two columns, `--rest-token` the token of the run where `--rest-root` is `T` and `none` where it is `none`, and otherwise valid arguments
- **THEN** the exit code and the run state of #5 are those of the row; in the rows that give `none` with #5 in flight the message names the directory of #5

##### Example: init binds the issue to its directory

| after `next` handed out #5 at `T` | `init --issue 5` in the directory of #5 with | exit | the run of #5 there afterwards |
| --- | --- | --- | --- |
| nothing | `--rest-root T` and the token of the run | 0 | names `T` |
| nothing | `--rest-root T` and another token | 4 | none |
| the directory of #5 was moved away and another clone of the same `origin` was put at its place | `--rest-root T` and the token of the run | 64 | none |
| `origin` of the directory of #5 was set to another URL | `--rest-root T` and the token of the run | 64 | none |
| a folder `U` outside `T` is given as `--rest-root` | `--rest-root U` and the token of the run | 64 | none |
| an `init --rest-root T` succeeded | `--rest-root none` | 64 | names `T` |

- **GIVEN** a run at `T` with candidate #5, and what the first column says
- **WHEN** `close-stage.py init` runs for issue 5 in the directory of #5 with the options of the second column and `--review no`
- **THEN** the exit code and the run of #5 in that directory are those of the row

##### Example: the close stage sees a rest run from anywhere in its working tree

| `--cwd` of `init --issue 5 --rest-root none` and of `rest-review --issue 5` |
| --- |
| `T/sub`, a folder below the top `T` |
| `T/.claude/worktrees/rest-5/sub`, a folder below the directory of #5 |
| `T/.claude/worktrees/rest-9`, the directory of #9, which the run recorded before it handed out #5 |
| `T` written with other letter case, on a file system that does not tell letter case apart |

- **GIVEN** a rest run at `T` with review on in which #5 is in flight, and the folder of the row
- **WHEN** `close-stage.py init` with `--rest-root none --rest-token none --review no` and `close-stage.py rest-review` run for issue 5 with that folder as `--cwd`
- **THEN** `init` exits 64 and writes no run state there, and `rest-review` prints `elsewhere`

##### Example: a session that was taken over writes nothing for its issue

- **GIVEN** a rest run at `T` in which #5 is in flight, an `init --rest-root T` for #5 that succeeded in its directory, a result file of an earlier close stage of #5 there, and then a `start --take-over`
- **WHEN** `close-stage.py reset` and `close-stage.py run` for #5 run in the directory of #5 with the token of the start before the take-over, and `reset` once without a token
- **THEN** `reset` exits 4 both times; `run` exits 3 and says that another session has taken the rest run over; and the run state and the result file of #5 there are as they were

##### Example: an issue of a rest run runs on the PR path only

- **GIVEN** a rest run at `T` in which #5 is in flight
- **WHEN** `close-stage.py init --rest-root T` with the token of the run runs for #5 in its directory with `--path direct-commit`
- **THEN** it exits 64 and writes no run state

##### Example: the close stage of a session that was taken over

| `close-stage.py run --issue 5` in the directory of #5 | it |
| --- | --- |
| with the token of the run | does not give the reason of the other rows |
| without `--rest-token` | exits 3, and its reason says that no token of the rest run was given |
| with the token of a `start` before a `start --take-over` | exits 3, and its reason says that another session has taken the rest run over |
| with the token of the run, while a `start --take-over` runs as the close stage waits for CI | exits 3 without asking GitHub to merge, and its reason says that another session has taken the rest run over |
| with the token of the run, while another command holds the lock of the run for longer than the wait | exits 3 without asking GitHub to merge, and its reason says that the lock of the rest run is held |

- **GIVEN** a rest run at `T` with review off in which #5 is in flight, an `init --rest-root T` for #5 that succeeded in its directory, and a pull request of #5 with a clean verify report and checks that pass
- **WHEN** `close-stage.py run` runs as the row says
- **THEN** it does what the row says

##### Example: review added while an issue is in flight

| the run is resumed with | `close-stage.py run` for #5 in its directory |
| --- | --- |
| `--review yes` | exits 3, and its reason says that the rest run has `--review` |
| `--review no` | does not give that reason |

- **GIVEN** a rest run started with `--review no` in which #5 is in flight, and a `close-stage.py init --rest-root T` for #5 with `--review no` that succeeded in the directory of #5
- **WHEN** `start --take-over` runs with the flag of the first column, and then `close-stage.py run` for #5 with the token that `start` printed
- **THEN** the close stage does what the row says

#### Scenario: a rest run state that cannot be read stops the close stage

- **WHEN** #5 is in flight in a rest run, `close-stage.py init --rest-root T` for #5 succeeded in its directory, the rest run state is then overwritten with text that is not JSON, and `close-stage.py run` for #5 runs
- **THEN** it exits 3 and its reason says that the review flag of that run is unknown

##### Example: the review flag of a rest run has one reader

| the state file of the rest run at `T` | the run of #5 in its directory | `close-stage.py rest-review --issue 5` there |
| --- | --- | --- |
| none | none | `off` |
| written by `start --review yes` and `next`, #5 in flight | recorded with `--rest-root T` | `on` |
| written by `start --review no` and `next`, #5 in flight | recorded with `--rest-root T` | `off` |
| written by `start --review no` and `next`, #5 in flight | none | `elsewhere` |
| a usable state with review on and #5 in flight, last written 25 hours ago | recorded with `--rest-root T` | `unreadable` |
| written an hour ago, review `false`, #5 in flight, without its `version` | recorded with `--rest-root T` | `unreadable` |
| the same without its `path` | recorded with `--rest-root T` | `unreadable` |
| the same without its `default` | recorded with `--rest-root T` | `unreadable` |
| written just now, not JSON | recorded with `--rest-root T` | `unreadable` |
| a symbolic link to a usable state with review off and #5 in flight | recorded with `--rest-root T` | `unreadable` |
| deleted by `report` after the run of #5 was recorded | recorded with `--rest-root T` | `unreadable` |
| written by `start --review no` and `next`, #5 in flight; the directory of #5 then moved to `U` with a symbolic link to `U` at its place | recorded with `--rest-root T`, asked in `U` | `unreadable` |
| a FIFO | none | returns `unreadable` without waiting |

- **GIVEN** the state file and the run of #5 of the row, the run of #5 written by `close-stage.py init --review no` before the state file was brought into the state of the row
- **WHEN** `rest-review` runs in the directory of #5 (or where the row says); and, for the rows with `version`, `path` and `default` missing, `rest-queue.py start` at `T` and `close-stage.py run --issue 5` in the directory
- **THEN** `rest-review` prints the word of the row; for those three rows `start` exits 3 and `run` stays at verified and says that the review flag is unknown; `rest-review` at `T` prints `elsewhere` in the second and the third row; the line of `skills/idd-all/SKILL.md` that sets `REST_REVIEW` calls `close-stage.py rest-review`, and no line of the skill reads the state file of the rest run with `jq`; and that line together with the one after it, run as they are written with the review of the issue set to no, leave it at no for `off` and for no file, and make it yes for `on`, for `elsewhere` and for `unreadable`

##### Example: a run that is gone stops the close stage of a rest issue

| after `init --rest-root T` for #5 succeeded in its directory | `close-stage.py run` for #5 |
| --- | --- |
| nothing happens | does not give the reason of the other rows |
| the run is resumed with `--review yes` and ended with `report` | exits 3, and its reason says that the rest run of the issue cannot be found |
| the run is ended with `report`, and a new run hands out #9 | exits 3, and its reason says that the rest run of the issue cannot be found |

- **GIVEN** a rest run at `T` started with `--review no` in which #5 is in flight, and a `close-stage.py init --rest-root T` for #5 with `--review no` that succeeded in the directory of #5
- **WHEN** what the row says happens (a resumed run is taken over with `start --take-over`), and then `close-stage.py run` for #5 runs there with the token of the last `start`
- **THEN** the close stage does what the row says

### Requirement: Each issue of a rest run runs in a directory of its own

Rest mode SHALL NOT run an issue in the working tree it was started in. For every issue it hands out, `rest-queue.py next` SHALL make a clone of the repository in the directory `.claude/worktrees/rest-<N>` below `--cwd`, which is the top of its repository (requirement "Start prints the list and resumes an unfinished run"), and SHALL print that directory as `dir` together with the issue, and `--cwd` itself as `root`. The clone is a repository of its own, not a git linked worktree: the Spectra CLI, run in a linked worktree, writes into the main working tree. It SHALL be made from the `origin` of the repository at `--cwd`, may borrow objects from that repository while it is made, and SHALL NOT depend on it afterwards. It SHALL be on the default branch the run stored, at the commit `origin` has for it.

In the clone `next` SHALL set `user.name` and `user.email` to the values git reports for them in the repository at `--cwd`, when it reports one. This list is closed: no other configuration and no hook of that repository is carried over. It SHALL add to the clone's own exclude file the lines `.claude/.idd/state/`, `.claude/worktrees/` and `.claude/.idd/tree-lock*`, It SHALL write those lines only when no symbolic link is on the way to the exclude file from the directory; otherwise it SHALL exit with code 3 and write nothing there. It SHALL write one more file into the clone's git directory, `idd-rest-mark`, which holds a value `next` chose at random for the issue and stored with it in the run state; and it SHALL store with the issue the URL it cloned from. These two files are a closed list: `next` writes no other file into the clone. A directory belongs to the run of the working tree it is below: the directory `R/.claude/worktrees/rest-<N>` is the one of issue `N` of the run whose working tree is `R`, and the helpers find that run by this place. A directory is bound to its issue when its mark file, read without following a symbolic link and only when it is a regular file, holds the value stored with the issue, and the `origin` of the clone, as its own configuration file says, is the URL stored with the issue. A clone put at the same place in its stead is not bound to the issue; a copy of the directory made with its git directory is.

`next` SHALL make the clone in a temporary folder of its own next to the place of the directory, with a name that it chose at random and that is not the name of a directory (`.rest-<N>-…`). It SHALL record that folder with the issue before it starts the clone, and SHALL write the configuration, the exclude lines and the mark there. Only then SHALL it take the place of the directory, by making there an empty folder that did not exist before, and move the clone into that folder. A clone that fails, and git's clean-up of it, touch only the temporary folder. When the place cannot be taken, or the move fails, something was put there while the clone was made: `next` SHALL record the issue as stopped with a reason that names the place, leave the place and the temporary folder as they are, and go on to the following candidate. Rest mode removes no directory, and no temporary folder either (requirement "The directory of an issue is left for a person").

`next` SHALL record the directory in the run state, marked as not yet made, before it makes it, and SHALL mark it as made and print it only after it has checked that the directory is the top of a repository of its own and bound to the issue. A directory below the working tree that holds no usable repository is answered for by the repository around it: git, asked in such a directory, finds the working tree the run was started in. `rest-queue.py` SHALL therefore name the git directory and the working tree in every git command it runs for a clone, so that git never looks further up, and SHALL compare paths without dropping white space from their ends.

When `next` finds the issue in flight with a directory recorded as not yet made (an earlier `next` was ended part of the way), it SHALL make the directory again, in a new temporary folder, when nothing is at its place. When a repository of its own is there and bound to the issue, it is the directory that the earlier `next` moved there before it was ended: `next` SHALL mark it as made. When anything else is there, `next` SHALL NOT remove it: it SHALL record the issue as stopped, with a reason that names the place and says that a person is to look at it and delete it, and go on to the following candidate. Rest mode removes no directory (requirement "The directory of an issue is left for a person").

The token of the run is issued by `start` (requirement "Start prints the list and resumes an unfinished run"). `next`, `where` and `here` SHALL be given it and SHALL exit with code 4 for any other value (requirement "The commands of one rest run do not overlap"); `next` prints no token. The helper cannot tell a session that lost the token from another session; the skill keeps the token where it survives a context compaction.

`rest-queue.py where --cwd R --repo O/R --token K` SHALL print the directory of the issue in flight, when it was recorded as made, and nothing else, and exit 0. It SHALL exit with code 1 when no issue is in flight with a directory that was made, and with code 4 when `K` is not the token of the run. It reads the run state and takes no lock.

When the clone cannot be made (git fails, the temporary folder cannot be made, or the clone is not a repository of its own on the default branch), `next` SHALL exit with code 3, and the issue stays in flight with its directory recorded as not yet made.

`rest-queue.py here --cwd D --repo O/R --issue N --token K` SHALL exit with code 0 only when all of these hold (closed list): `D`, made absolute and not resolved, is `R/.claude/worktrees/rest-N` for a working tree `R` whose run has `N` in flight, recorded as made at `D`; `K` is the token of that run; no symbolic link is on the way to `D` from `R`, `D` included; `D` is the top of a repository of its own; `D` is bound to the issue; and the current directory of the process, which is the shell's directory when the skill runs it, is `D`. When the token does not hold, it SHALL exit with code 4 and say that another session has taken the run over; it SHALL compare the token before it looks at the issue in flight, so that a token that is not the run's gets code 4 also after the run has handed out another issue. Otherwise it SHALL exit with code 1 and say in its reason line what does not hold, and which directory the issue runs in when it knows one.

`idd-all` SHALL change the shell's directory to `D` in a command of its own, and SHALL then run `here` in a separate command that does not change the directory. A `cd` that fails SHALL end its command. When that `here` fails because the current directory is not `D`, the shell does not keep its directory from one command to the next, and `idd-all` SHALL stop the whole run: the single-issue pipeline runs programs that write by the shell's directory. `idd-all` SHALL run `here` the same way, in a command of its own that does not change the directory, before the step that diagnoses the issue, before the step that implements it, before the step that verifies it and before the step that pushes its branch and opens its pull request, and SHALL run the pipeline of the issue only after each of them exited with code 0.

#### Scenario: an issue is handed out with its directory

- **WHEN** `next` hands out #5 in a run started at `T`
- **THEN** it prints `dir` as `T/.claude/worktrees/rest-5` and `root` as `T`, that directory is the top of a repository of its own on the default branch, and `here` exits 0 for it and issue 5

##### Example: the directory is a repository of its own

- **GIVEN** a repository at `T` whose `origin/main` is one commit ahead of the local `main`, whose local configuration sets `user.name` to `Local Name`, and which has a local `pre-commit` hook; and candidate #5
- **WHEN** `start` and `next` run at `T`
- **THEN** `T/.claude/worktrees/rest-5/.git` is a directory; the clone is on `main` at the commit of `origin/main`; `git worktree list` at `T` has one line; the clone's `origin` is the URL of `origin` at `T`; `user.name` in the clone is `Local Name`; the clone has no `pre-commit` hook; and the clone has no `objects/info/alternates` file

##### Example: the working tree the run was started in is not needed clean

| the working tree at `T` | `start` | `next` |
| --- | --- | --- |
| on `main`, clean | exits 0 | hands out #5 |
| on `wip`, with a changed `a.txt` and an untracked `b.txt` | exits 0 | hands out #5 |

- **GIVEN** a repository at `T` in the state of the row, and candidate #5
- **WHEN** `start --path PR --review no` and `next` run
- **THEN** they do what the row says; afterwards `T` is on the same branch with the same changed and untracked files, and the directory of #5 is on `main`

##### Example: a directory that was not finished

| at the place of the directory of #5 | the next `next` |
| --- | --- |
| nothing | prints #5 with `in_flight` true and the same `dir`, which is now the top of a repository of its own |
| a folder with the file `partial.txt` | records #5 as stopped with a reason that names the place; hands out #9; `partial.txt` is still there |
| the clone that the earlier `next` moved there | prints #5 with `in_flight` true and the same `dir`, and the clone is the one that was there |
| another clone of the same `origin`, without the mark | records #5 as stopped with a reason that names the place; hands out #9; that clone is as it was |

- **GIVEN** a run at `T` with candidates #5 and #9, and a `next` that was ended after it recorded the directory of #5 and before it marked it as made, and the place of that directory as the row says
- **WHEN** `next` runs again
- **THEN** it does what the row says

##### Example: the token belongs to the run

- **GIVEN** a run at `T` that `start` began, printing the token `K`, and in which `next` handed out #5
- **WHEN** `start --take-over` runs, which prints the token `L`, and then `here`, `where` and `record --issue 5` with `K`, `next` with `L`, and `here` and `where` with `L`
- **THEN** `here`, `where` and `record` with `K` exit 4 and their reason lines say that the token is not the one of this rest run and that the invocation is to end; the outcome of #5 is not recorded; `next` with `L` prints #5 with `in_flight` true and no token; `here` with `L` exits 0; and `where` with `L` prints the directory of #5

##### Example: here refuses an earlier token first

- **GIVEN** a run at `T` that `start` began, printing the token `K`, in which `next` handed out #5; then a `start --take-over`, a `record --issue 5` and a `next` that handed out #9, with the new token
- **WHEN** `here` runs in the directory of #5 for issue 5 with `K`
- **THEN** it exits 4 and its reason line says that the token is not the one of this rest run

##### Example: a clone that fails touches only its temporary folder

| `origin` of `T` | while `next` waits before the clone, the place of the directory of #5 gets | `next` | afterwards |
| --- | --- | --- | --- |
| a path where no repository is | a folder with `mine.txt` | exits 3 | `mine.txt` is there with its content |
| the usual one | a folder with `mine.txt` | records #5 as stopped with a reason that names the place, and hands out #9 | `mine.txt` is there with its content, and the temporary folder of #5 holds the clone |
| the usual one | an empty folder | records #5 as stopped with a reason that names the place, and hands out #9 | the folder is there and empty, and the temporary folder of #5 holds the clone |

- **GIVEN** a run at `T` with candidates #5 and #9, and `origin` of `T` as the row says
- **WHEN** `next` runs, made to wait before the clone (test hook `IDD_REST_SLEEP_BEFORE_CLONE`), and the place of the directory of #5 gets what the row says while it waits
- **THEN** the outcome is that of the row

##### Example: a directory is not removed because of its name

- **GIVEN** a repository at `T` that holds the directory `T/.claude/worktrees/rest-5` with the file `mine.txt`, no run state, and candidates #5 and #9
- **WHEN** `start` and `next` run
- **THEN** `next` hands out #9, the run state holds #5 as stopped with a reason that begins with `existing work: directory` and names that directory, and `mine.txt` is still there

##### Example: here names the directory an issue runs in

| `here` is asked about | exit | its reason line |
| --- | --- | --- |
| the directory of #5, issue 5, its token | 0 | — |
| `T`, issue 5 | 1 | says that `T` is not the directory of #5 |
| the directory of #5, issue 9 | 1 | says that it is not the directory of #9 |
| the directory of #5, issue 5, another token | 4 | says that the token is not the one of this rest run |
| the directory of #5 after it was moved away and another clone of the same `origin` was put at its place | 1 | says that the directory is not bound to #5 |
| the directory of #5 after its `origin` was set to another URL | 1 | says that the directory is not bound to #5 |
| a directory that is not below a working tree with a run, issue 5 | 1 | says that no rest run has #5 in flight there |
| the directory of #5, issue 5, with the process in `T` | 1 | says that the current directory is not the directory of #5 |
| the directory of #5 after it was moved to `U` outside `T` and a symbolic link to `U` was put at its place, given as `U`, with the process in `U` | 1 | says that no rest run has #5 in flight there |
| the same, given as the place of the link, with the process there | 1 | says that a symbolic link is on the way |

- **GIVEN** a run at `T` in which #5 is in flight
- **WHEN** `here` runs as the row says, with the process in the directory it is asked about unless the row says otherwise, and with the token of the run unless the row says otherwise
- **THEN** the exit code and the reason line are those of the row

### Requirement: A rest run leaves the working tree it was started in as it was

From before `start` to after `report`, a rest run SHALL leave the repository at `--cwd` as it was: the commit and the branch that are checked out, the index, the stash, the local branches and tags, and every file in the working tree, whether git tracks it, does not track it or ignores it. A person or another session MAY work there while the run goes. The skill SHALL say so.

Rest mode writes at these places of that repository, and this list is closed: the state folder of the run (`.claude/.idd/state/` below `--cwd`); the folder of the directories (`.claude/worktrees/` at the top); and the local exclude file of the git directory, to which `start` adds the rule for `.claude/worktrees/` when git does not ignore that folder yet. The existing-work check that `next` runs fetches from `origin` with `--prune`: that moves remote-tracking branches, removes the remote-tracking branches whose branch `origin` no longer has, and can bring tags that `origin` has. It changes no tag and no local branch that is there, whatever the configuration of that repository says about pruning tags: `next` runs the check with `fetch.pruneTags` and `remote.origin.pruneTags` set to false.

Reading a repository can write it: `git status` refreshes the index and writes it back when it can take the lock. Every git command of `rest-queue.py` and of the existing-work check it runs SHALL therefore run without optional locks (`--no-optional-locks`, or `GIT_OPTIONAL_LOCKS=0` for a program it starts), so that no read writes the index.

A helper cannot see an edit that the model makes, with its own tools, to a file of the starting working tree while an issue runs. `next` SHALL therefore record, at the hand-out, the commit and the branch checked out at `--cwd`, what git lists as changed or untracked there, and the stash; `record` SHALL read them again before it writes anything there. When they differ, `record` SHALL store which of the four changed, and the report SHALL say so under the entry of that issue, together with the fact that rest mode does not write there. This does not stop the run: a person may have made the change. What is compared is what git lists: the checked-out commit, the branch, the paths that `git status` shows together with their two status letters, and the stashes. A further change of a file that git already lists as changed, a change of a file that git ignores, and a change that was made and undone while the issue ran leave that list as it was and are not noticed; the skill and the report SHALL NOT say that every change is.

Before it reads anything, `start` SHALL ask git whether `.claude/worktrees/` would be ignored at the top of the repository. When git would not ignore it, `start` SHALL add the rule through the plugin's writer for local runtime paths and ask again; when git still would not ignore it, `start` SHALL exit with code 3 and a reason line that names the folder.

#### Scenario: a run changes nothing in the working tree it was started in

- **WHEN** a rest run handed out two issues, recorded one as closed and one as stopped, and ended with `report`
- **THEN** the repository at `--cwd` holds the same checked-out commit and branch, index, stash, local branches and files as before `start`, apart from the places of the closed list, and every tag it held, unchanged

##### Example: the starting working tree is the same after every ending

- **GIVEN** a repository at `T` on the branch `wip` with a staged change of `a.txt`, a changed `c.txt`, an untracked `b.txt`, an ignored `local/notes.txt`, one stash and the local branch `side`; candidates #5 and #9; and each of the states the directory of #5 can be in that the tests of this capability make (pushed or not, changed, with a stash, a tag, a second working tree, records of corrected text, a parked change, a routing log)
- **WHEN** `start`, `next`, the state of the directory, `record`, `next`, `record` for #9 and `report` run
- **THEN** a listing of every file below `T` with its content, of the bytes of the index file, of `HEAD`, of the local branches and tags and of the stash is the same as before `start`, apart from `.claude/.idd/state/`, `.claude/worktrees/` and `.git/info/exclude`, and apart from tags of `origin` that the fetch brought

##### Example: a change of the starting working tree is reported

| while #5 is in flight, at `T` | the report says under #5 |
| --- | --- |
| nothing happens | nothing about the working tree at `T` |
| `a.txt` is changed | that the files at `T` changed while #5 ran, and that rest mode does not write there |
| a commit is made | that the checked-out commit at `T` changed while #5 ran |
| `a.txt`, already changed when #5 was handed out, is changed once more | nothing about the working tree at `T` |

- **GIVEN** a run at `T` in which `next` handed out #5
- **WHEN** what the row says happens, and then `record --issue 5` and `report` run
- **THEN** the report says what the row says, and `record` exited with code 0

##### Example: the existing-work check removes no tag

- **GIVEN** a repository at `T` whose local configuration sets `fetch.pruneTags` and `remote.origin.pruneTags` to true, with a local tag `mytag` that `origin` does not have, and candidate #5
- **WHEN** `start` and `next` run
- **THEN** `next` hands out #5 and `mytag` is still there at the same commit

##### Example: the folder of the directories is ignored before a run starts

- **GIVEN** a repository at `T` in which no ignore rule covers `.claude/worktrees/`, and candidate #5
- **WHEN** `start` and `next` run
- **THEN** `start` exits 0, `git status` at `T` lists nothing below `.claude/worktrees/` after `next`, and the rule is in the local exclude file of `T` and in no tracked file

##### Example: reading the starting working tree does not write its index

- **GIVEN** a repository at `T` whose tracked `d.txt` was given an older modification time after the index was written, and candidate #5
- **WHEN** `start`, `next` and `record --issue 5` run
- **THEN** the bytes of the index file of `T` are those before `start`

### Requirement: The commands of one rest run do not overlap

`rest-queue.py` `start`, `next`, `record`, `stop` and `report` SHALL each hold an exclusive lock on the file `idd-all-rest.lock` in the state folder of the run, from before they read the run state until after their last write. Without it, two sessions that call the helper for the same run at the same time each act on a state the other is about to replace: a `next` can hand out an issue whose directory the other `next` is making, and a `record` that read the state before a `start --review yes` can write review off again. The lock file SHALL be opened without following a symbolic link. A command that finds the lock held SHALL wait for it, at most 30 seconds, and SHALL then exit with code 4 and a reason line that says another rest command for this run is going on and that two sessions are not to run the same rest run. Code 4 means that another session has this run, or may have it: the lock is held, a token is not the run's, or `start` without `--take-over` found an unfinished run. It is not a failure of the run: `idd-all` SHALL end the invocation and SHALL NOT call `stop` or `report`, which would end the run of the other session, and SHALL NOT call `next` again. `here`, `where`, `list` and `close-stage.py rest-review` read and do not take the lock; the close stage takes it right before the merge (requirement "A rest run keeps its review flag"). Both helpers take the lock through one function.

A run is run by one session: the one that holds its token (requirement "Start prints the list and resumes an unfinished run"). Every command of `rest-queue.py` other than `args`, `list` and `start` — `next`, `where`, `here`, `record`, `stop` and `report` — SHALL be given the token as `--token`, and SHALL exit with code 4 and change nothing when it is not the token of the run. So SHALL `close-stage.py init` with a rest root, and `close-stage.py reset` in the directory of an issue that a rest run has in flight there; and `close-stage.py run` for such an issue, or for an issue whose record names a rest root, SHALL stop without merging and write nothing. These are the commands that change a rest run or what the close stage holds or does for an issue of one. `close-stage.py rest-review` only reads the state of a rest run and prints a word, and `init` and `run` read it to refuse: they take no token for that. A command that only refuses or reports does not need the token; every command of either helper is in one of these lists, which are closed, and a check of this capability SHALL find a command that is in none. Both helpers SHALL compare a token in one function. `start --take-over` is the only way to take a run over; the session that had it ends its invocation at its next command.

#### Scenario: a second command waits for the first

- **WHEN** a `next` holds the lock and another `next` for the same run starts
- **THEN** the second waits, and when the first has handed out #5 the second prints #5 with `in_flight` true and removes nothing

##### Example: two sessions at the same run

| while the first command holds the lock | the second command | afterwards |
| --- | --- | --- |
| `next`, which hands out #5 and then writes `notes.txt` into its directory | `next` | the second prints #5 with `in_flight` true; `notes.txt` is still there |
| `record --issue 5`, held for a second after it read the run state | `start --review yes` | the run state has review on |
| a lock held for longer than the wait | `next` | the second exits 4; its reason line says another rest command for this run is going on; the run state is unchanged |

- **GIVEN** a run at `T` with candidates #5 and #9, run with a wait of a few seconds for the lock (test hook `IDD_REST_LOCK_WAIT`)
- **WHEN** the two commands of the row run at the same time
- **THEN** the outcome is that of the row

##### Example: every command of a run takes its token

- **GIVEN** a run at `T` in which #5 is in flight, and the commands that `rest-queue.py` and `close-stage.py` dispatch, read from the helpers themselves
- **WHEN** every command of `rest-queue.py` other than `args`, `list` and `start` runs with a token that is not the run's, and once without a token; and `close-stage.py init --rest-root T` for #5 in its directory runs with a token that is not the run's
- **THEN** each exits 4 with a token that is not the run's, and with a usage error without one; the bytes of the run state are those before; every command of `rest-queue.py` is `args`, `list`, `start` or one of the commands that take a token; and every command of `close-stage.py` is `init`, `run`, `reset` or one of the commands that do not change what the close stage holds for an issue of a rest run (`rest-review`, `gate`, `pr-check`, `confirm-close`)

### Requirement: The directory of an issue is left for a person

`rest-queue.py record` SHALL record the outcome of the issue and SHALL NOT read, change or remove anything in the directory of the issue. Rest mode removes no directory, and no temporary folder that `next` made: the report names every one (requirement "Report lists what happened and ends the run"), and a person deletes it. A later rest run does not take up an issue whose directory is still there (requirement "Each issue is attempted at most once per run").

`record --issue N --token K` SHALL exit with code 4, and record nothing, when `K` is not the token of the run. Called again for the issue recorded last while no issue has been handed out since, with the token of the run, it SHALL print what it recorded and exit with code 0.

#### Scenario: a merged issue keeps its directory

- **WHEN** the issue of a directory was merged and closed, and `record` runs for it
- **THEN** the directory is there afterwards, with the same files, index, branches, tags and stash as before `record`

##### Example: record leaves every directory as it was

| the directory of #5 when `record` runs |
| --- |
| a pushed branch `idd/5-x`, nothing uncommitted |
| a branch with one commit that was not pushed |
| a changed `a.txt` and an untracked `notes.txt` |
| a stash and a tag that is not on `origin` |
| a routing log `.claude/.idd/routing-stats.jsonl` |

- **GIVEN** a run at `T` in which #5 is in flight, and the directory of #5 in the state of the row
- **WHEN** `record --issue 5` runs with the token of #5
- **THEN** it exits 0; a listing of every file below the directory, its git directory and its routing log included, with its content, is the same as before `record`, and so are its branches, its tags and its stash; and `T/.claude/.idd/routing-stats.jsonl` does not exist

