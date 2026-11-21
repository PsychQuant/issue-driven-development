## MODIFIED Requirements

### Requirement: idd-all runs rest mode as a loop over the single-issue pipeline

In rest mode `idd-all` SHALL first run, once, the steps of the single-issue pipeline that check the repository, the flags and the dependencies, and SHALL resolve the path and the interaction mode, including the step that can downgrade the path. In doing so it SHALL NOT write the unattended marker and SHALL NOT create a branch. When the configuration asks for a question about the path (`pr_policy: ask`), rest mode SHALL ask whether to start the run on the PR path and SHALL offer no other path.

It SHALL then call `rest-queue.py start` with the path it resolved and the review flag of the invocation. When `start` exits with code 3, `idd-all` SHALL relay the reason line and end.

It SHALL then repeat: `next`; keep the `token` it printed with the issue where it survives a context compaction (the task list of the issue); change the shell's directory to the `dir` that `next` printed in a command of its own, and use that directory as the working directory of the issue; `here` for that directory, that issue and that token, in a separate command;  run the single-issue pipeline for the issue, with the path and the interaction mode resolved before `start`, which are neither resolved nor downgraded again for a later issue, and with the review flag that `next` printed, which decides both what is recorded for the close stage and whether the issue fixes in-scope findings and enters the close stage at all; change the shell's directory back to the directory the run was started in; `record` with the stop reason the single-issue report printed, if any. It SHALL leave the loop when `next` prints `done` or a stop reason, and SHALL then call `rest-queue.py report` and relay its output. Every `rest-queue.py` command other than `here` is given the directory the run was started in as `--cwd`; `here` and the single-issue pipeline are given the directory of the issue.

The shell is in the directory of the issue while its pipeline runs, so that every step that goes by the shell's directory (the attachments an issue's diagnosis downloads, the routing log, the Spectra CLI, the check whether a run is unattended) works in that directory. The skill SHALL say that the sub-skills are still given `--cwd`: the reviewers of the verify step do not share the shell. When `here` exits with code 1, `idd-all` SHALL NOT run the pipeline of that issue in that directory; when its reason is the current directory, `idd-all` SHALL stop the whole run (requirement "Each issue of a rest run runs in a directory of its own"). When `here` or `record` exits with code 4 (the token is not the one of the issue: another session has taken the run over), `idd-all` SHALL end the invocation as it does for a lock it cannot get (requirement "The commands of one rest run do not overlap"): it SHALL NOT call `record`, `stop`, `report` or `next` again, and SHALL NOT call `next --take-over`. A run hands out one issue at a time, so a `next` of the session that was displaced would print the same issue again. `idd-all` SHALL call `next --take-over` only when the token of the issue in flight is lost and no other session runs the run; the skill SHALL say that a token `here` or `record` refused is not a lost token.

The two steps of the single-issue pipeline that resolve the path and that can downgrade it SHALL each say, where they stand in the skill, that a rest run does not run them again for an issue and which values it uses instead. Wherever the skill says that a later `/idd-all` resumes an unfinished run, it SHALL say that the command is to carry the same flags. The text of the pull request an issue of a rest run opens SHALL follow the review flag `next` printed for that issue, not a value recorded earlier.

The step of the single-issue pipeline that creates the issue's branch SHALL check out in the way that does not overwrite a file git ignores (`git checkout --no-overwrite-ignore`), whether it creates the branch from `origin/<default>` or takes up a branch on the remote: `origin` can track a path that git ignores in this working tree, and a plain checkout writes over that file without a word. When a file is in the way, that step stops the issue and says so. This holds for every `/idd-all` run on the PR path, not only for rest mode.

The skill SHALL say that a rest run does not work in the working tree it was started in, and that a person or another session may go on working there while the run goes. No text of the plugin SHALL describe a step between two issues in the working tree a run was started in: no commit, stash, exclude line, checkout or branch deletion there.

A reason that `idd-all` passes to `record` or to `stop` is text from outside (a line of a report, a line this helper printed, with file names and git's words in it). `idd-all` SHALL pass it on standard input, not as a shell argument. The commands in the skill that do so SHALL work when they are run exactly as they are written there, indentation included.

In rest mode `idd-all` SHALL NOT take over work that already exists. `next` asks the existing-work check before it hands an issue out (requirement "Each issue is attempted at most once per run"). The check of the single-issue pipeline runs once more in the directory of the issue; when it returns anything but `clear` there, `idd-all` SHALL create no branch, leave the pull request untouched, ask no question, and record the issue with a reason that begins with `existing work: ` and holds the outcome the check printed and the next step for a person.

When `next` prints `in_flight` true, `idd-all` SHALL continue that issue in the `dir` it printed. When the issue already has its Phase 6 result, it goes straight to `record`. When `next` prints `branch` as `null`, the issue had not reached its own branch: `idd-all` SHALL start it again from the step that resolves the issue, the existing-work check included. Otherwise it SHALL continue the interrupted phase and SHALL NOT run the existing-work check of that issue again: the branch and the pull request the check would find are this run's own.

A run that was interrupted is resumed by the same command. Where the skill tells a person that giving the command again resumes the run, it SHALL say that the flags are to be the same.

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
- **THEN** it contains the invocations `rest-queue.py" start`, `rest-queue.py" next`, `rest-queue.py" here`, `rest-queue.py" record`, `rest-queue.py" stop` and `rest-queue.py" report`, with `start` before `next`, `next` before `here`, `here` before `record`, and `report` last; no line of the skill holds `rest-queue.py" settle`; Step 0.1 contains the invocation `rest-queue.py" args`; the rest section states that an existing-work verdict other than `clear` is recorded with the reason `existing work: `; and Phase 6 sends a rest run back to the rest section

##### Example: the skill runs each issue in its directory

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the rest section is read
- **THEN** the step that runs the single-issue pipeline holds a fenced block that sets `CWD` to the directory `next` printed and holds `cd "$CWD" ||`, and a later fenced block of its own that holds the `here` invocation with `--token "$TOKEN"` and no `cd`; the step says to run that block again before Phase 2, before Phase 3 and before Phase 4, and that a `here` that fails on the current directory stops the whole run; the line of the `here` invocation holds `--cwd "$CWD"`; the step that records holds a line that changes the shell's directory to `"$REST_ROOT"` before the `record` invocation; the lines of the `start`, `next`, `record`, `stop` and `report` invocations hold `--cwd "$REST_ROOT"`; and the step says that the sub-skills are given `--cwd`

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
- **THEN** each says that the command is to carry the same flags; every other line of the skill that says a later `/idd-all` within 24 hours resumes the run says so as well; and so does every line of the rest section that speaks of resuming a run within 24 hours, whatever its wording

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
- **THEN** one row names a command of `rest-queue.py` that exits with code 4, names both causes (a lock that is held, and a token that is not the issue's), and says to end this invocation, to call neither `stop` nor `report`, and neither to call `next` again nor to take the issue back with `next --take-over`; the step that runs `here` says that exit code 4 ends the invocation; and no sentence of the rest section sends a session whose token was refused back to `next`

---
### Requirement: Each issue of a rest run runs in a directory of its own

Rest mode SHALL NOT run an issue in the working tree it was started in. For every issue it hands out, `rest-queue.py next` SHALL make a clone of the repository in the directory `.claude/worktrees/rest-<N>` below the top of the repository that holds `--cwd`, and SHALL print that directory as `dir` together with the issue, and `--cwd` itself as `root`. The clone is a repository of its own, not a git linked worktree: the Spectra CLI, run in a linked worktree, writes into the main working tree. It SHALL be made from the `origin` of the repository at `--cwd`, may borrow objects from that repository while it is made, and SHALL NOT depend on it afterwards. It SHALL be on the default branch the run stored, at the commit `origin` has for it.

In the clone `next` SHALL set `user.name` and `user.email` to the values git reports for them in the repository at `--cwd`, when it reports one. This list is closed: no other configuration and no hook of that repository is carried over. It SHALL add to the clone's own exclude file the lines `.claude/.idd/state/`, `.claude/worktrees/` and `.claude/.idd/tree-lock*`, It SHALL write those lines only when no symbolic link is on the way to the exclude file from the directory; otherwise it SHALL exit with code 3 and write nothing there. It SHALL write no other file into the clone. A directory belongs to the run of the working tree it is below: the directory `R/.claude/worktrees/rest-<N>` is the one of issue `N` of the run whose working tree is `R`, and the helpers find that run by this place, not by a file in the clone.

`next` SHALL record the directory in the run state, marked as not yet made, before it makes it, and SHALL mark it as made and print it only after it has checked that the directory is the top of a repository of its own. A directory below the working tree that holds no usable repository is answered for by the repository around it: git, asked in such a directory, finds the working tree the run was started in. `rest-queue.py` SHALL therefore name the git directory and the working tree in every git command it runs for a clone, so that git never looks further up, and SHALL compare paths without dropping white space from their ends.

When `next` finds the issue in flight with a directory recorded as not yet made (an earlier `next` was ended part of the way), it SHALL make the directory again when nothing is at its place. When something is there, `next` SHALL NOT remove it: it SHALL record the issue as stopped, with a reason that names the place and says that a person is to look at it and delete it, and go on to the following candidate. Rest mode removes no directory (requirement "The directory of an issue is left for a person").

With an issue it hands out for the first time, `next` SHALL print `token`: a value it chose at random and stored with the issue in the run state. It SHALL NOT print the token of an issue in flight again. `next --take-over` SHALL store a new token for the issue in flight and print it; the earlier token is then invalid. A token tells the session that was handed an issue from any other: `here` and `record` exit with code 4 for a token that is not the one stored, so that a second session that took over makes the first one end its invocation at its next `here` or `record`, instead of both working on the issue. Code 4 is the code of a run another session has (requirement "The commands of one rest run do not overlap"); the session that gets it calls no further command of the run. The helper cannot tell the first session after it lost its token from another session; the skill keeps the token where it survives a context compaction.

When the directory cannot be made (the clone fails, or the place is taken by something that is not such a directory), `next` SHALL exit with code 3, and the issue stays in flight with its directory recorded as not yet made.

`rest-queue.py here --cwd D --repo O/R --issue N --token K` SHALL exit with code 0 only when all of these hold (closed list): `D`, made absolute and not resolved, is `R/.claude/worktrees/rest-N` for a working tree `R` whose run has `N` in flight, recorded as made at `D`, with the token `K`; no symbolic link is on the way to `D` from `R`, `D` included; `D` is the top of a repository of its own; and the current directory of the process, which is the shell's directory when the skill runs it, is `D`. When only the token does not hold, it SHALL exit with code 4 and say that another session has taken the issue over. Otherwise it SHALL exit with code 1 and say in its reason line what does not hold, and which directory the issue runs in when it knows one.

`idd-all` SHALL change the shell's directory to `D` in a command of its own, and SHALL then run `here` in a separate command that does not change the directory. A `cd` that fails SHALL end its command. When that `here` fails because the current directory is not `D`, the shell does not keep its directory from one command to the next, and `idd-all` SHALL stop the whole run: the single-issue pipeline runs programs that write by the shell's directory. `idd-all` SHALL run `here` the same way, in a command of its own that does not change the directory, before the step that diagnoses the issue, before the step that implements it and before the step that verifies it, and SHALL run the pipeline of the issue only after each of them exited with code 0.

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

- **GIVEN** a run at `T` with candidates #5 and #9, and a `next` that was ended after it recorded the directory of #5 and before the clone was complete, and the place of that directory as the row says
- **WHEN** `next` runs again
- **THEN** it does what the row says

##### Example: a token belongs to one session

- **GIVEN** a run at `T` in which `next` handed out #5 and printed the token `K`
- **WHEN** `next` runs again, then `next --take-over`, which prints the token `L`, and then `here` and `record --issue 5` with `K`, a `next` without `--take-over`, and `here` with `L`
- **THEN** the second `next` printed no token; `here` and `record` with `K` exit 4 and their reason lines say that the token is not the one of #5 and that the invocation is to end; the outcome of #5 is not recorded; the `next` after them prints #5 with `in_flight` true and no token, and the token stored for #5 is still `L`; and `here` with `L` exits 0

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
| the directory of #5, issue 5, another token | 4 | says that the token is not the one of #5 |
| a directory that is not below a working tree with a run, issue 5 | 1 | says that no rest run has #5 in flight there |
| the directory of #5, issue 5, with the process in `T` | 1 | says that the current directory is not the directory of #5 |
| the directory of #5 after it was moved to `U` outside `T` and a symbolic link to `U` was put at its place, given as `U`, with the process in `U` | 1 | says that no rest run has #5 in flight there |
| the same, given as the place of the link, with the process there | 1 | says that a symbolic link is on the way |

- **GIVEN** a run at `T` in which #5 is in flight
- **WHEN** `here` runs as the row says, with the process in the directory it is asked about unless the row says otherwise, and with the token `next` printed for #5 unless the row says otherwise
- **THEN** the exit code and the reason line are those of the row

---
### Requirement: The commands of one rest run do not overlap

`rest-queue.py` `start`, `next`, `record`, `stop` and `report` SHALL each hold an exclusive lock on the file `idd-all-rest.lock` in the state folder of the run, from before they read the run state until after their last write. Without it, two sessions that call the helper for the same run at the same time each act on a state the other is about to replace: a `next` can take the directory of an issue that the other `next` just handed out for one it did not finish and remove it, and a `record` that read the state before a `start --review yes` can write review off again. The lock file SHALL be opened without following a symbolic link. A command that finds the lock held SHALL wait for it, at most 30 seconds, and SHALL then exit with code 4 and a reason line that says another rest command for this run is going on and that two sessions are not to run the same rest run. Code 4 means that another session has this run; `here` and `record` also exit with it for a token that is not the issue's (requirement "Each issue of a rest run runs in a directory of its own"). It is not a failure of the run: `idd-all` SHALL end the invocation and SHALL NOT call `stop` or `report`, which would end the run of the other session, and SHALL NOT call `next` again. `here` and `list` read and do not take the lock.

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

---
### Requirement: The directory of an issue is left for a person

`rest-queue.py record` SHALL record the outcome of the issue and SHALL NOT read, change or remove anything in the directory of the issue. Rest mode removes no directory: the report names every one (requirement "Report lists what happened and ends the run"), and a person deletes it. A later rest run does not take up an issue whose directory is still there (requirement "Each issue is attempted at most once per run").

`record --issue N --token K` SHALL exit with code 4, and record nothing, when `K` is not the token stored for the issue. Called again for the issue recorded last while no issue has been handed out since, with its token, it SHALL print what it recorded and exit with code 0.

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
- **THEN** it exits 0; a listing of every file of the directory with its content, its index, its branches, its tags and its stash is the same as before `record`; and `T/.claude/.idd/routing-stats.jsonl` does not exist

---
### Requirement: Each issue is attempted at most once per run

`rest-queue.py next` SHALL re-read the open issues and hand out the first issue of the run order that this run has not handed out before, recording it in the run state as in flight at that moment. When no such issue exists it SHALL print `done`. While an issue is in flight and has no recorded outcome, `next` SHALL hand out that same issue again with `in_flight` true and SHALL NOT hand out another one. With it, `next` SHALL print the directory of that issue as `dir`, and as `branch` the branch that is checked out in that directory when it is a branch of that issue (`idd/<N>` or `idd/<N>-…`), or `null` otherwise.

An issue opened after the run started SHALL be handed out by a later `next` when it is a candidate.

`next` does not look at what the working tree at `--cwd` holds: the issue runs in a directory of its own (requirement "Each issue of a rest run runs in a directory of its own").

Rest mode does not take over work that exists. Before it hands out a candidate, `next` SHALL ask three things, in this order, and SHALL hand the issue out only when none of them finds work. This list is closed.

1. A local branch of that issue in the repository at `--cwd` (`idd/<N>` or `idd/<N>-…`): the reason is `existing work: local branch <name>`.
2. A directory at the place of that issue's directory that this run did not record for it: the reason is `existing work: directory <path>`, followed by the statement that rest mode removes no directory and that a person is to look at it and delete it.
3. The existing-work check of the single-issue pipeline (`scripts/check-existing-work.sh`), the only implementation of that question. `next` SHALL hand the issue out only when the verdict is `clear`. For `resume` and `blocked` the reason is `existing work: ` followed by the reason the check gave. For every other answer (the verdict `unknown`, a check that failed, an answer that cannot be read) the reason is `existing work: could not be determined` followed by what the check said: a lookup that was not completed does not show that there is no work.

In each of these cases `next` SHALL record the issue as stopped with that reason and go on to the following candidate. When git cannot be asked, `next` SHALL exit with code 3.

#### Scenario: an issue that stopped is not handed out again

- **WHEN** an issue was handed out and recorded as stopped, and it is still an open candidate
- **THEN** no later `next` of the same run hands it out

##### Example: a spawned issue is picked up

- **GIVEN** a run whose candidates are #5 and #9
- **WHEN** #5 is handed out and recorded as stopped, then #9 is handed out and recorded as closed, and a new candidate #12 exists by then
- **THEN** the three `next` results after the first are 9, 12 and `done`

##### Example: the in-flight issue is repeated

- **GIVEN** a run at `T` in which `next` handed out #5 and no outcome was recorded
- **WHEN** `next` is called again
- **THEN** it prints #5 with `in_flight` true, `dir` as `T/.claude/worktrees/rest-5`, `branch` as `null`, `review` as `no` and no `token`, and the run state still holds exactly one attempt

##### Example: an issue with a local branch is recorded, not handed out

- **GIVEN** a run whose candidates are #5 and #9, in a repository that has the local branch `idd/5-old`
- **WHEN** `next` is called
- **THEN** it hands out #9, the run state holds #5 as stopped with the reason `existing work: local branch idd/5-old`, and no directory was made for #5

##### Example: the in-flight issue names its branch

- **GIVEN** a run in which `next` handed out #5, no outcome was recorded, and the directory of #5 is on the branch `idd/5-x`
- **WHEN** `next` is called again
- **THEN** it prints #5 with `in_flight` true and `branch` as `idd/5-x`

##### Example: existing work on GitHub is found by next

| GitHub and `origin` hold for #5 | `next` | the reason recorded for #5 |
| --- | --- | --- |
| nothing | hands out #5 | — |
| an open pull request #12 whose body has the line `Refs #5` | hands out #9 | begins with `existing work: ` and names pull request #12 |
| a branch `idd/5-x` on `origin` with one commit of its own | hands out #9 | begins with `existing work: ` and names `idd/5-x` |
| nothing, and the list of open pull requests cannot be read | hands out neither #5 nor #9 | begins with `existing work: could not be determined`, for #9 as well |

- **GIVEN** a run whose candidates are #5 and #9, and GitHub and `origin` as the row says
- **WHEN** `next` is called
- **THEN** it does what the row says; when #5 is not handed out, no directory was made for it and the run state holds it as stopped with the reason of the row
