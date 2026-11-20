## REMOVED Requirements

### Requirement: Between two issues one helper settles the working tree

**Reason**: Rest mode no longer works in the working tree it was started in. Each issue runs in a directory of its own (requirement "Each issue of a rest run runs in a directory of its own"), so there is nothing to settle between two issues: no commit of what an issue left, no stash, no file moved aside, no line written to the local exclude file, no checkout of the default branch. Eight verify rounds found blocking defects in that step, two of them introduced by the fixes of the round before; the maintainer chose the other approach on 2026-11-20 (issue #478).

**Migration**: `rest-queue.py settle` no longer exists; `idd-all` calls `record` and then `next`. What an issue left is in its directory, which `record` removes or keeps (requirement "The directory of an issue is removed only when nothing exists only there"). A run state written by the earlier version is not a state this version can use; `start` stops on it for 24 hours after its last write, as before.

## ADDED Requirements

### Requirement: Each issue of a rest run runs in a directory of its own

Rest mode SHALL NOT run an issue in the working tree it was started in. For every issue it hands out, `rest-queue.py next` SHALL make a clone of the repository in the directory `.claude/worktrees/rest-<N>` below the top of the repository that holds `--cwd`, and SHALL print that directory as `dir` together with the issue, and `--cwd` itself as `root`. The clone is a repository of its own, not a git linked worktree: the Spectra CLI, run in a linked worktree, writes into the main working tree. It SHALL be made from the `origin` of the repository at `--cwd`, may borrow objects from that repository while it is made, and SHALL NOT depend on it afterwards. It SHALL be on the default branch the run stored, at the commit `origin` has for it.

In the clone `next` SHALL set `user.name` and `user.email` to the values git reports for them in the repository at `--cwd`, when it reports one. This list is closed: no other configuration and no hook of that repository is carried over. It SHALL add to the clone's own exclude file the lines `.claude/.idd/state/`, `.claude/worktrees/` and `.claude/.idd/tree-lock*`, and SHALL write, in the clone's state folder, a pointer file that names `--cwd` and the issue (requirement "A rest run keeps its review flag").

`next` SHALL record the directory in the run state, marked as not yet made, before it makes it, and SHALL mark it as made and print it only after it has checked that the directory is the top of a repository of its own. A directory below the working tree that holds no usable repository is answered for by the repository around it: git, asked in such a directory, finds the working tree the run was started in. `rest-queue.py` SHALL therefore name the git directory and the working tree in every git command it runs for a clone, so that git never looks further up, and SHALL compare paths without dropping white space from their ends.

When `next` finds the issue in flight with a directory recorded as not yet made (an earlier `next` was ended part of the way), it SHALL remove that directory and make it again. It SHALL remove a directory only when the run state names it for that issue as not yet made; it SHALL NOT remove a directory because of its name.

When the directory cannot be made (the clone fails, or the place is taken by something that is not such a directory), `next` SHALL exit with code 3, and the issue stays in flight with its directory recorded as not yet made.

`rest-queue.py here --cwd D --repo O/R --issue N` SHALL exit with code 0 when `D` is the directory that a rest run, found through the pointer file in `D`, has recorded as made for issue `N`, and `N` is in flight in that run. Otherwise it SHALL exit with code 1 and say in its reason line which directory the issue runs in, when it knows one. `idd-all` SHALL run the single-issue pipeline of an issue only after `here` exited with code 0 for the directory it is about to use.

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

##### Example: a directory that was not finished is made again

- **GIVEN** a run at `T` with candidate #5, and a `next` that was ended after it recorded the directory of #5 and before the clone was complete, which left `T/.claude/worktrees/rest-5` holding one file and no repository
- **WHEN** `next` runs again
- **THEN** it prints #5 with `in_flight` true and the same `dir`, the directory is the top of a repository of its own, and the file is gone

##### Example: a directory is not removed because of its name

- **GIVEN** a repository at `T` that holds the directory `T/.claude/worktrees/rest-5` with the file `mine.txt`, no run state, and candidates #5 and #9
- **WHEN** `start` and `next` run
- **THEN** `next` hands out #9, the run state holds #5 as stopped with a reason that begins with `existing work: kept directory`, and `mine.txt` is still there

##### Example: here names the directory an issue runs in

| `here` is asked about | exit | its reason line |
| --- | --- | --- |
| the directory of #5, issue 5 | 0 | — |
| `T`, issue 5 | 1 | names the directory of #5 |
| the directory of #5, issue 9 | 1 | says that the directory is the one of #5 |
| a directory without a pointer file and without a run, issue 5 | 1 | says that no rest run has #5 in flight there |

- **GIVEN** a run at `T` in which #5 is in flight
- **WHEN** `here` runs as the row says
- **THEN** the exit code and the reason line are those of the row

---
### Requirement: The directory of an issue is removed only when nothing exists only there

After `rest-queue.py record` has recorded the outcome of an issue, the same command SHALL decide what becomes of the directory of that issue, and SHALL print the decision: `removed`, `kept` with the reasons, or `none` when the issue had no directory. It SHALL remove the directory only when every item of the following list holds. The list is closed, and an item that cannot be checked does not hold.

1. The directory is the one the run state names for the issue; neither it nor a directory above it, up to the top of the repository at `--cwd`, is a symbolic link; and it is the top of a repository of its own.
2. Git lists no changed file and no untracked file there that it does not ignore, read with every untracked file listed, whatever git is configured to show. Entries below `.claude/.idd/attachments/`, entries below `.claude/.idd/state/` and entries whose path begins with `.claude/.idd/tree-lock` do not count, whether they are untracked files or changes of tracked files: the plugin writes them again. This list of three is closed.
3. There is no stash.
4. The commit of every local branch, and the commit that is checked out, is held by a remote-tracking branch of `origin`. Such a branch exists only through a fetch or a push, so the commit has been on `origin`.
5. Every tag in the directory is on `origin` with the same value, as `origin` answers when it is asked. When `origin` cannot be asked, the item does not hold.
6. The repository has no second working tree.
7. No record is there that exists nowhere else. This list is closed: the folder in which `idd-edit-helper.py` keeps earlier versions of corrected GitHub text, when it holds a file; and a change that the Spectra CLI parked in the git directory.
8. The routing log (`.claude/.idd/routing-stats.jsonl`), when it is an untracked file there, has been carried over as the next paragraph says.

Files that git ignores in the directory, other than those of item 7, are removed with it. The directory was made by the run, so no file of the person from before the run is in it.

When items 1 to 7 hold and the routing log is an untracked file in the directory, `record` SHALL append its content, in one write, to the file of the same path below the top of the repository at `--cwd`, and SHALL NOT rewrite that file: a line another session appends at the same time is kept. When that file already holds the content as one block, `record` SHALL NOT append it again. When that file or a folder above it, up to the top, is a symbolic link, or the write fails, the log is not carried over and the directory is kept. The log of a directory that is kept for another reason stays in it.

`record` SHALL NOT end the run because a directory is kept: it exits with code 0 and the following `next` hands out the next issue. When a directory is kept, `record` SHALL remove the pointer file from it: from then on it is an ordinary clone, in which a person can go on. `record` SHALL store the decision and the reasons in the run state. A `record` that was ended part of the way can be run again and comes to the same end: the outcome is read again, a directory that is gone counts as removed, and a log that was carried over is not carried over twice.

Every reason SHALL say what was found and name it: the paths (at most ten, then the number of the others), the branch, the tag, the folder.

#### Scenario: the directory of a merged issue is removed

- **WHEN** the issue of a directory was merged and closed, its branch was pushed, and nothing but the plugin's own records is left uncommitted there
- **THEN** `record` prints `removed` and the directory no longer exists

##### Example: what becomes of a directory

| what the directory of #5 holds when `record` runs | the directory | a reason names |
| --- | --- | --- |
| a pushed branch `idd/5-x`, nothing uncommitted | removed | — |
| a pushed branch, and a changed tracked `.claude/.idd/attachments/issue-5/_manifest.json` | removed | — |
| a pushed branch, and an untracked `.claude/.idd/attachments/issue-5/spec.docx` | removed | — |
| a pushed branch, and an ignored `build/out.bin` | removed | — |
| nothing but the clone as `next` made it | removed | — |
| a branch `idd/5-x` with one commit that was not pushed | kept | `idd/5-x` |
| a pushed branch, and a changed `a.txt` | kept | `a.txt` |
| a pushed branch, and an untracked `notes.txt` | kept | `notes.txt` |
| a pushed branch, and a stash | kept | a stash |
| a pushed branch, and a tag `idd-5-verified` that is not on `origin` | kept | `idd-5-verified` |
| a pushed branch, and a tag `idd-5-verified` that is on `origin` | removed | — |
| a pushed branch, and a second working tree | kept | a second working tree |
| a pushed branch, and a file in the folder of earlier versions of corrected text | kept | that folder |
| a pushed branch, and a change the Spectra CLI parked | kept | the parked change |
| a commit checked out without a branch that no branch on `origin` holds | kept | the commit that is checked out |

- **GIVEN** a run at `T` in which #5 is in flight, and the directory of #5 brought into the state of the row
- **WHEN** `record --issue 5` runs
- **THEN** it exits 0; the directory is removed or still there as the row says; when it is kept, the decision it prints and the run state hold a reason that names what the row says, and the directory holds no pointer file; and the following `next` hands out the next candidate

##### Example: the routing log is carried over once

- **GIVEN** a run at `T` in which #5 is in flight; `T/.claude/.idd/routing-stats.jsonl` holding the line `{"n":1}`; and the directory of #5 with a pushed branch and an untracked `.claude/.idd/routing-stats.jsonl` holding the lines `{"n":2}` and `{"n":3}`
- **WHEN** `record --issue 5` runs, is ended after it appended the log and before it removed the directory, and runs again
- **THEN** the directory is removed, and the file at `T` holds exactly the three lines `{"n":1}`, `{"n":2}` and `{"n":3}`

##### Example: a routing log that cannot be carried over keeps the directory

| at `T`, `.claude/.idd/routing-stats.jsonl` is | the directory of #5 | what is there afterwards |
| --- | --- | --- |
| a symbolic link to a file outside `T` | kept, and a reason names the routing log | the file outside `T` is unchanged |
| a folder | kept, and a reason names the routing log | the folder, with nothing new in it |

- **GIVEN** a run at `T` in which #5 is in flight, `T` as the row says, and the directory of #5 with a pushed branch and an untracked routing log
- **WHEN** `record --issue 5` runs
- **THEN** the outcome is that of the row

##### Example: a directory that is not a repository of its own is never removed

| `T/.claude/worktrees/rest-5` when `record` runs | `record` |
| --- | --- |
| a folder with the file `x.txt` and no `.git` | keeps it; a reason says that it is not a repository of its own; `x.txt` is still there |
| a symbolic link to a folder outside `T` that holds `x.txt` | keeps it; `x.txt` is still there |
| not there | prints `removed` |

- **GIVEN** a run at `T` in which #5 is in flight with its directory recorded as made, the working tree at `T` holding a stash and an untracked `mine.txt`, and the directory of #5 replaced by what the row says
- **WHEN** `record --issue 5` runs
- **THEN** the outcome is that of the row, and `T` still holds its stash and `mine.txt`

##### Example: record ended part of the way comes to the same end

- **GIVEN** each row of the example "what becomes of a directory", and the example "the routing log is carried over once"
- **WHEN** `record --issue 5` is ended after each of its steps in turn and run again
- **THEN** the directory, the run state's decision and reasons, the routing log at `T` and the working tree at `T` are those of the same case without the interruption

---
### Requirement: A rest run leaves the working tree it was started in as it was

From before `start` to after `report`, a rest run SHALL leave the repository at `--cwd` as it was: the commit and the branch that are checked out, the index, the stash, the local branches and tags, and every file in the working tree, whether git tracks it, does not track it or ignores it. A person or another session MAY work there while the run goes. The skill SHALL say so.

Rest mode writes at these places of that repository, and this list is closed: the state folder of the run (`.claude/.idd/state/` below `--cwd`); the folder of the directories (`.claude/worktrees/` at the top); the routing log at the top, to which `record` appends (requirement "The directory of an issue is removed only when nothing exists only there"); and the local exclude file of the git directory, to which `start` adds the rule for `.claude/worktrees/` when git does not ignore that folder yet. The existing-work check that `next` runs fetches from `origin`: that moves remote-tracking branches and can bring tags that `origin` has, and changes no tag and no local branch that is there.

A helper cannot see an edit that the model makes, with its own tools, to a file of the starting working tree while an issue runs. `next` SHALL therefore record, at the hand-out, the commit and the branch checked out at `--cwd`, what git lists as changed or untracked there, and the stash; `record` SHALL read them again before it writes anything there. When they differ, `record` SHALL store which of the four changed, and the report SHALL say so under the entry of that issue, together with the fact that rest mode does not write there. This does not stop the run: a person may have made the change.

Before it reads anything, `start` SHALL ask git whether `.claude/worktrees/` would be ignored at the top of the repository. When git would not ignore it, `start` SHALL add the rule through the plugin's writer for local runtime paths and ask again; when git still would not ignore it, `start` SHALL exit with code 3 and a reason line that names the folder.

#### Scenario: a run changes nothing in the working tree it was started in

- **WHEN** a rest run handed out two issues, one whose directory was removed and one whose directory was kept, and ended with `report`
- **THEN** the repository at `--cwd` holds the same checked-out commit and branch, index, stash, local branches and files as before `start`, apart from the places of the closed list, and every tag it held, unchanged

##### Example: the starting working tree is the same after every ending

- **GIVEN** a repository at `T` on the branch `wip` with a staged change of `a.txt`, a changed `c.txt`, an untracked `b.txt`, an ignored `local/notes.txt`, one stash and the local branch `side`; candidates #5 and #9; and each row of the example "what becomes of a directory" for #5
- **WHEN** `start`, `next`, the row's state of the directory, `record`, `next`, `record` for #9 and `report` run
- **THEN** a listing of every file below `T` with its content, of the index, of `HEAD`, of the local branches and tags and of the stash is the same as before `start`, apart from `.claude/.idd/state/`, `.claude/worktrees/`, `.claude/.idd/routing-stats.jsonl` and `.git/info/exclude`, and apart from tags of `origin` that the fetch brought

##### Example: a change of the starting working tree is reported

| while #5 is in flight, at `T` | the report says under #5 |
| --- | --- |
| nothing happens | nothing about the working tree at `T` |
| `a.txt` is changed | that the files at `T` changed while #5 ran, and that rest mode does not write there |
| a commit is made | that the checked-out commit at `T` changed while #5 ran |

- **GIVEN** a run at `T` in which `next` handed out #5
- **WHEN** what the row says happens, and then `record --issue 5` and `report` run
- **THEN** the report says what the row says, and `record` exited with code 0

##### Example: the folder of the directories is ignored before a run starts

- **GIVEN** a repository at `T` in which no ignore rule covers `.claude/worktrees/`, and candidate #5
- **WHEN** `start` and `next` run
- **THEN** `start` exits 0, `git status` at `T` lists nothing below `.claude/worktrees/` after `next`, and the rule is in the local exclude file of `T` and in no tracked file

## MODIFIED Requirements

### Requirement: Each issue is attempted at most once per run

`rest-queue.py next` SHALL re-read the open issues and hand out the first issue of the run order that this run has not handed out before, recording it in the run state as in flight at that moment. When no such issue exists it SHALL print `done`. While an issue is in flight and has no recorded outcome, `next` SHALL hand out that same issue again with `in_flight` true and SHALL NOT hand out another one. With it, `next` SHALL print the directory of that issue as `dir`, and as `branch` the branch that is checked out in that directory when it is a branch of that issue (`idd/<N>` or `idd/<N>-…`), or `null` otherwise.

An issue opened after the run started SHALL be handed out by a later `next` when it is a candidate.

`next` does not look at what the working tree at `--cwd` holds: the issue runs in a directory of its own (requirement "Each issue of a rest run runs in a directory of its own").

Rest mode does not take over work that exists. Before it hands out a candidate, `next` SHALL ask three things, in this order, and SHALL hand the issue out only when none of them finds work. This list is closed.

1. A local branch of that issue in the repository at `--cwd` (`idd/<N>` or `idd/<N>-…`): the reason is `existing work: local branch <name>`.
2. A directory at the place of that issue's directory that this run did not record for it: the reason is `existing work: kept directory <path>`.
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
- **THEN** it prints #5 with `in_flight` true, `dir` as `T/.claude/worktrees/rest-5`, `branch` as `null` and `review` as `no`, and the run state still holds exactly one attempt

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

---
### Requirement: A stopped issue does not stop the run and a stopped run hands out nothing

An issue recorded as `stopped` SHALL NOT by itself end the run: the following `next` hands out the next issue. What the issue left is in its directory or on GitHub. `rest-queue.py stop` with a reason SHALL mark the whole run as stopped; every later `next` of that run SHALL print the stop reason and hand out nothing. `stop` SHALL drop a leading `rest-queue: ` from the reason: a reason line copied from this helper's own output then keeps its end, where the number of the paths it did not name stands.

`idd-all` SHALL call `stop` only when a `next` or a `record` of a run that exists exits with code 3: GitHub, `gh` authentication or a helper could not be read, the run state could not be written, or the directory of an issue could not be made. When `stop` itself exits with a code other than 0, `idd-all` SHALL go on to `report`. Exit codes 1 and 2 of `rest-queue.py` mean the call itself was wrong and are corrected, not treated as a stop. An interruption by the user leaves the run state in place.

When the `start` that would begin a run exits with code 3, no run exists and there is nothing to stop or to report; a `start` that refuses the path of the invocation is one of these. `idd-all` SHALL relay the reason line that `start` printed and end, and SHALL NOT call `stop` or `report`. The same holds when that `start` would have resumed an earlier run: the state of the earlier run is left as it is, so that a later `start` resumes it.

When `report` itself exits with a code other than 0, `idd-all` SHALL relay what `report` printed together with its reason line and end. It SHALL NOT call `stop` or `report` again.

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
- **THEN** one line of it names the `report` that exits with code 1 or 3, and that line says to pass on what was printed and to call neither `stop` nor `report` again

##### Example: the skill goes on to the report when stop fails

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the part of the rest section about stopping the whole run is read
- **THEN** one row names `next` and `record` exiting with code 3, and that row says to call `stop` with the reason line and, when `stop` itself fails, to go on to the end of the run

##### Example: a reason copied from the helper keeps its end

- **GIVEN** a run with candidate #5, and a reason line of this helper that is as long as its limit for a reason and ends with `and 2 more)`
- **WHEN** `stop` is given `rest-queue: ` followed by that line, and then `next` and `report` run
- **THEN** the stop reason that `next` prints and the one in the report both end with `and 2 more)`

---
### Requirement: Start prints the list and resumes an unfinished run

`rest-queue.py start --path P --review yes|no` SHALL print the number of open issues, the issue numbers of every class, and the run order, before any issue is handed out. It SHALL print issue numbers only, no issue titles. The run order it prints SHALL hold only the candidates that have neither a local branch in the repository at `--cwd` (`idd/<N>` or `idd/<N>-…`) nor a directory at the place of their directory. The candidates that have one SHALL be printed on a line of their own, which says that they are recorded as existing work when their turn comes. `start` SHALL also say that a candidate with a pull request or a branch on GitHub is recorded as existing work when its turn comes. Every reason and every time it prints from the run state SHALL be on one line, without control characters and no longer than the helper's limit for a reason, whatever the state file holds.

`P` is the path that `idd-all` resolved for this invocation. Rest mode runs on the PR path only: every issue runs on a branch of its own in a directory of its own, and what it leaves is handed over as a pull request. When `P` is not `PR`, `start` SHALL exit with code 3, write nothing, and print a reason line that says rest mode needs the PR path and names what a person can do: run the same command with `--pr`, in place of `--no-pr` when the command has it, and the other flags kept, install the ralph-loop plugin when its absence is what downgraded the path, or name the issues one at a time. The reason line SHALL NOT hold a complete `/idd-all` command line: a command copied from it would lose the flags of the invocation. A new run SHALL read the default branch of the repository from GitHub and store it in the run state together with the path; `next` makes every directory on that branch. A resumed run keeps the default branch it stored.

When the working tree holds the state of a run of the same repository whose last recorded activity (start, hand-out, record or stop) is less than 24 hours old and that was not ended by `report`, `start` SHALL resume it: the recorded attempts and a recorded stop are kept, and the attempts are not handed out again. Otherwise `start` SHALL begin a new run with no attempts. A state file whose start time cannot be read as a time, with an attempt that has no reason, without a stored default branch or a stored review flag, with a version this helper does not know, or whose stored path is not `PR`, is not a state this helper can use.

A state file that this helper cannot use and that was written in the last 24 hours SHALL make `start` exit with code 3 and leave the file as it is: the review flag of that run cannot be read, and a new run in its place would drop it. The reason line SHALL name the file and say that it is to be deleted when no rest run is going on in this working tree. A state file of a run that the previous version of this helper wrote is such a file. A state that can be read and belongs to a run for another repository is not: `start` replaces it and says whose it was, and does not say of it that it is older than 24 hours. A state file older than 24 hours is replaced by the new run. When that file can be read and its run was not ended by `report`, `start` SHALL first print what that run kept and nobody was told: each directory it kept, with the reasons.

`start` does not look at what the working tree at `--cwd` holds, and a new run begins on whatever branch it is on, with or without changes (requirement "A rest run leaves the working tree it was started in as it was").

Before it reads anything, `start` SHALL ask git whether files in `.claude/.idd/state/` would be ignored in this working tree, for the run state file and for the unattended marker in the same folder. When git would not ignore one of them, or the working tree is not a git working tree, `start` SHALL exit with code 3 and a reason line that names the folder and says how to ignore it, and SHALL write nothing: an untracked state file would show in the working tree the run was started in.

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
| a state of version 4 with review on | 1 hour ago | exits 3, names the file, and the file is unchanged |
| text that is not JSON | 25 hours ago | exits 0 and begins a new run |

- **GIVEN** a working tree with the state file of the row, and candidate #5
- **WHEN** `start --path PR --review no` runs
- **THEN** the outcome is that of the row

##### Example: a run that was never reported is not forgotten

- **GIVEN** a run state whose last activity was 25 hours ago, in which #5 is recorded as stopped with a kept directory and the reason `a.txt`; and candidate #9
- **WHEN** `start --path PR --review no` runs
- **THEN** it exits 0, begins a new run, and before the list prints the directory of #5 and that reason

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

---
### Requirement: Report lists what happened and ends the run

`rest-queue.py report` SHALL print one report with: the issues recorded as closed; the issues recorded as stopped, each with its reason; the `needs-person` issues, each with the complete text of every open clarity row, one line per row and not shortened; the issues of every other class that was not run; and the stop reason of the run when there is one. It SHALL then delete the run state. When the open issues cannot be re-read, for whatever reason, it SHALL still print the recorded attempts, say that the list could not be read, and delete the run state.

An issue that this run handed out SHALL appear once: under closed, under stopped or as handed out without a result. It SHALL NOT appear in the list of issues waiting for a person or in the line of a class that was not run. When such an issue is `needs-person` at the time of the report, the report SHALL print its open questions under the entry of that issue, also when the issue was recorded as closed and reopened since. The report prints no text of an issue of any other class.

For the class `verified` the report SHALL say that such an issue continues when it is named (`/idd-all #N`). When at least one issue was recorded with a reason that begins with `existing work:`, the report SHALL say that such an issue is left for a person and that its reason names the pull request, the branch or the directory to look at. Under the entry of an issue recorded as closed, it SHALL print the reason when the issue was recorded with one.

Under the entry of an issue whose directory was kept, whether the issue is recorded as closed or as stopped, the report SHALL name the directory and every reason `record` stored for keeping it. When the report names at least one kept directory, it SHALL say once that nothing in a kept directory was removed, that a later rest run does not take up an issue that has a kept directory, a pull request, a branch or the phase `verified`, and what a person does with such a directory: go on with the work in it, or delete it. Under the entry of an issue that is in flight when `report` runs, the report SHALL name its directory and say that the issue was handed out and has no recorded outcome. When `record` carried lines of the routing log over, the report SHALL say so under that entry and name the file. When `record` found the working tree at `--cwd` changed while the issue ran, the report SHALL say which of the checked-out commit, the branch, the files and the stash changed, and that rest mode does not write there (requirement "A rest run leaves the working tree it was started in as it was").

The report tells a person to take one kind of step, and this list is closed: delete a kept directory. A check of this capability SHALL take that step and see the result: a later run hands the issue out again while it is a candidate without other existing work. Looking at a directory, a branch, a commit or a pull request is not such a step. No line under an issue recorded as stopped SHALL tell the person to name the issue (`/idd-all #N`).

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

##### Example: the report says what to do with a kept directory

- **GIVEN** a run at `T` in which #5 was recorded as stopped and its directory was kept because of a changed `a.txt`, and #9 was recorded as closed and its directory was removed
- **WHEN** `report` runs, then the directory of #5 is deleted as the report says, and a new run is started
- **THEN** the entry of #5 names its directory and `a.txt`; the entry of #9 names no directory; one line says that nothing in a kept directory was removed and that going on in it or deleting it is for a person; no line under a stopped issue holds `/idd-all`; and `next` of the new run hands out #5

##### Example: a closed issue whose run reported a stop

- **GIVEN** a run in which #5 was recorded as closed with the reason `Stopped: /idd-close did not finish`
- **WHEN** `report` runs
- **THEN** #5 is listed under closed, followed by that reason

##### Example: the report names the directory of an issue in flight

- **GIVEN** a run at `T` in which #5 was handed out and no outcome was recorded
- **WHEN** `report` runs
- **THEN** one line names #5 as handed out without a recorded outcome, and names `T/.claude/worktrees/rest-5`

##### Example: the report names the routing log that was carried over

- **GIVEN** a run at `T` in which #5 was recorded as closed, and `record` carried two lines of the routing log of its directory over to `T`
- **WHEN** `report` runs
- **THEN** the entry of #5 says that two lines of the routing log were appended and names `.claude/.idd/routing-stats.jsonl`

---
### Requirement: idd-all runs rest mode as a loop over the single-issue pipeline

In rest mode `idd-all` SHALL first run, once, the steps of the single-issue pipeline that check the repository, the flags and the dependencies, and SHALL resolve the path and the interaction mode, including the step that can downgrade the path. In doing so it SHALL NOT write the unattended marker and SHALL NOT create a branch. When the configuration asks for a question about the path (`pr_policy: ask`), rest mode SHALL ask whether to start the run on the PR path and SHALL offer no other path.

It SHALL then call `rest-queue.py start` with the path it resolved and the review flag of the invocation. When `start` exits with code 3, `idd-all` SHALL relay the reason line and end.

It SHALL then repeat: `next`; change the shell's directory to the `dir` that `next` printed and use that directory as the working directory of the issue; `here` for that directory and that issue; run the single-issue pipeline for the issue, with the path and the interaction mode resolved before `start`, which are neither resolved nor downgraded again for a later issue, and with the review flag that `next` printed, which decides both what is recorded for the close stage and whether the issue fixes in-scope findings and enters the close stage at all; change the shell's directory back to the directory the run was started in; `record` with the stop reason the single-issue report printed, if any. It SHALL leave the loop when `next` prints `done` or a stop reason, and SHALL then call `rest-queue.py report` and relay its output. Every `rest-queue.py` command other than `here` is given the directory the run was started in as `--cwd`; `here` and the single-issue pipeline are given the directory of the issue.

The shell is in the directory of the issue while its pipeline runs, so that every step that goes by the shell's directory (the attachments an issue's diagnosis downloads, the routing log, the Spectra CLI, the check whether a run is unattended) works in that directory. The skill SHALL say that the sub-skills are still given `--cwd`: the reviewers of the verify step do not share the shell. When `here` exits with code 1, `idd-all` SHALL NOT run the pipeline of that issue in that directory.

The two steps of the single-issue pipeline that resolve the path and that can downgrade it SHALL each say, where they stand in the skill, that a rest run does not run them again for an issue and which values it uses instead. Wherever the skill says that a later `/idd-all` resumes an unfinished run, it SHALL say that the command is to carry the same flags. The text of the pull request an issue of a rest run opens SHALL follow the review flag `next` printed for that issue, not a value recorded earlier.

The step of the single-issue pipeline that creates the issue's branch SHALL check out in the way that does not overwrite a file git ignores (`git checkout --no-overwrite-ignore`), whether it creates the branch from `origin/<default>` or takes up a branch on the remote: `origin` can track a path that git ignores in this working tree, and a plain checkout writes over that file without a word. When a file is in the way, that step stops the issue and says so. This holds for every `/idd-all` run on the PR path, not only for rest mode.

The skill SHALL say that a rest run does not work in the working tree it was started in, and that a person or another session may go on working there while the run goes.

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
- **THEN** the step that runs the single-issue pipeline holds a line that changes the shell's directory to the directory `next` printed and sets `CWD` to it, before the `here` invocation; the line of the `here` invocation holds `--cwd "$CWD"`; the step that records holds a line that changes the shell's directory to `"$REST_ROOT"` before the `record` invocation; the lines of the `start`, `next`, `record`, `stop` and `report` invocations hold `--cwd "$REST_ROOT"`; and the step says that the sub-skills are given `--cwd`

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

---
### Requirement: A rest run keeps its review flag

A rest run started with `--review` stops every issue at verified; a run that loses the flag merges and closes instead. The flag SHALL therefore live in the run state and reach the close stage without passing through anything a context compaction can lose.

`start` SHALL store the review flag of a new run. When it resumes a run, review is on when the stored run has it or this `start` gives it: the flag can be added to a run and cannot be dropped from it, and `start` SHALL say so when the two differ. Ending the run with `report` is the way to drop it. When `start` adds the flag to a run that has an issue in flight, it SHALL say that a close stage already running for that issue is not stopped by it: the close stage reads the flag once, when it starts. A state file that cannot be used does not lose the flag by being replaced: `start` does not replace such a file within 24 hours of its last write (requirement "Start prints the list and resumes an unfinished run").

`next` SHALL print the review flag of the run (`"review": "yes"` or `"no"`) with every issue it hands out, in flight or not. `idd-all` SHALL take the review flag of each issue from there.

The state of a rest run is below the directory the run was started in; the close stage of an issue runs in the directory of that issue. `next` SHALL write a pointer file into the state folder of that directory, which names the directory the run was started in and the issue (requirement "Each issue of a rest run runs in a directory of its own"). `close-stage.py` SHALL find the state of the rest run through that pointer.

`close-stage.py init` records the run of one issue, and `close-stage.py run` merges when that record says review is off. `init` SHALL refuse to record review as off for an issue that a rest run with review on has in flight: it SHALL exit with a usage error and write no run state, so that `run` finds none and stops at verified. Its message SHALL name both ways out: give `--review yes`, or, when the issue was named by a person while that rest run is unfinished, end the rest run first. `run` SHALL stop without merging for an issue that such a run with review on has in flight, whatever the record of that issue says: the flag can be added to the run after `init` recorded the issue. `run` reads that state once, when it starts.

`close-stage.py rest-review --cwd C --repo O/R --issue N` SHALL print the reading as one word. This list is closed.

- `on`: `C` holds a pointer for issue `N`, and the run it names has review on and `N` in flight.
- `off`: `C` holds no pointer and no run state below `C` has `N` in flight; or the pointer names a run that has no state file, whose state is older than 24 hours, that has review off, or that does not have `N` in flight.
- `elsewhere`: `C` holds no pointer, and a rest run whose state is below `C` has `N` in flight in a directory of its own. The pipeline of the issue is then running in the wrong place.
- `unreadable`: the pointer cannot be read or names another issue; or the state file it leads to, or the one below `C`, was changed in the last 24 hours and is not a usable state.

`init` SHALL exit with a usage error and write no run state when the reading is `elsewhere`, whatever the review value, and its message SHALL name the directory the issue runs in. `unreadable` does not change what `init` does. `run` SHALL stop without merging for `elsewhere` and for `unreadable`, and its reason SHALL say which. Phase 5 of `idd-all` SHALL take the review of a rest run from that command and from nowhere else, and SHALL treat every word other than `off` as review: the close stage stops at verified for it, so the body of the pull request does not promise a merge.

The 24 hours count from the last time the rest run wrote its state, which it does at every hand-out and record; a run that has written nothing for that long is over as far as this check goes, as it is for `start`. Whether a file at the place of a state or of a pointer can be read is decided in one place, for `rest-queue.py` and `close-stage.py` alike (`scripts/lib/reststate.py`): neither reads a state file, a pointer file or a state folder that is a symbolic link, and a file that `start` stops on is a file whose review flag the close stage does not take either, however its `review` entry reads.

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

| the rest run at `T` | `init --issue 5` runs in | `--review` | exit | a run state for #5 exists there |
| --- | --- | --- | --- | --- |
| review on, #5 in flight | the directory of #5 | `no` | 64 | no |
| review on, #5 in flight | the directory of #5 | `yes` | 0 | yes |
| review off, #5 in flight | the directory of #5 | `no` | 0 | yes |
| review off, #5 in flight | `T` | `no` | 64 | no |
| review on, #5 in flight | `T` | `yes` | 64 | no |
| review on, #9 in flight | `T` | `no` | 0 | yes |
| none | `T` | `no` | 0 | yes |

- **GIVEN** a repository at `T` with the rest run of the first column
- **WHEN** `close-stage.py init` runs for issue 5 with `--cwd` as the second column says, the review value of the third column and otherwise valid arguments
- **THEN** the exit code and the run state of #5 are those of the row; in the two rows for `T` with #5 in flight the message names the directory of #5

##### Example: review added while an issue is in flight

| the run is resumed with | `close-stage.py run` for #5 in its directory |
| --- | --- |
| `--review yes` | exits 3, and its reason says that the rest run has `--review` |
| `--review no` | does not give that reason |

- **GIVEN** a rest run started with `--review no` in which #5 is in flight, and a `close-stage.py init` for #5 with `--review no` that succeeded in the directory of #5
- **WHEN** `start` runs again with the flag of the first column, and then `close-stage.py run` for #5
- **THEN** the close stage does what the row says

#### Scenario: a rest run state that cannot be read stops the close stage

- **WHEN** #5 is in flight in a rest run, `close-stage.py init` for #5 succeeded in its directory, the rest run state is then overwritten with text that is not JSON, and `close-stage.py run` for #5 runs
- **THEN** it exits 3 and its reason says that the review flag of that run is unknown

##### Example: the review flag of a rest run has one reader

| the state file of the rest run at `T` | the directory of #5 | `close-stage.py rest-review --issue 5` there |
| --- | --- | --- |
| none | without a pointer | `off` |
| written by `start --review yes` and `next`, #5 in flight | as `next` made it | `on` |
| written by `start --review no` and `next`, #5 in flight | as `next` made it | `off` |
| a usable state with review on and #5 in flight, last written 25 hours ago | as `next` made it | `off` |
| written an hour ago, review `false`, #5 in flight, without its `version` | as `next` made it | `unreadable` |
| the same without its `path` | as `next` made it | `unreadable` |
| the same without its `default` | as `next` made it | `unreadable` |
| written just now, not JSON | as `next` made it | `unreadable` |
| a symbolic link to a usable state with review off and #5 in flight | as `next` made it | `unreadable` |
| written by `start --review no` and `next`, #5 in flight | its pointer is not JSON | `unreadable` |
| written by `start --review no` and `next`, #5 in flight | its pointer names issue 9 | `unreadable` |
| written by `start --review no` and `next`, #5 in flight | its pointer is a symbolic link to a pointer that names `T` and issue 5 | `unreadable` |

- **GIVEN** the state file and the directory of the row, and for the three rows without an entry a run state of #5 that `close-stage.py init --review no` wrote in the directory of #5
- **WHEN** `rest-review` runs in the directory of #5; and, for those three rows, `rest-queue.py start` at `T` and `close-stage.py run --issue 5` in the directory
- **THEN** `rest-review` prints the word of the row; for those three rows `start` exits 3 and `run` stays at verified and says that the review flag is unknown; `rest-review` at `T` prints `elsewhere` in the second and the third row; the line of `skills/idd-all/SKILL.md` that sets `REST_REVIEW` calls `close-stage.py rest-review`, and no line of the skill reads the state file of the rest run with `jq`; and that line together with the one after it, run as they are written with the review of the issue set to no, leave it at no for `off` and for no file, and make it yes for `on`, for `elsewhere` and for `unreadable`
