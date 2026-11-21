# idd-all-rest Specification

## Purpose

`/idd-all` invoked without an issue runs every open issue of the repository that is ready (a candidate) through the single-issue pipeline, one at a time, on the PR path. This capability defines which invocations select that mode, how open issues are classified and ordered, how a run records what it tried, when a run stops as a whole, and what it reports.

## Requirements

### Requirement: Rest mode is selected by a closed list of argument forms

`scripts/rest-queue.py args -- <argv>` SHALL classify an `/idd-all` invocation as `rest`, `other` or `refuse` and print one JSON line with the key `mode` (and `reason` for `refuse`). It SHALL exit 0 for `rest` and `other`, and 1 for `refuse`.

Flags are `--pr`, `--no-pr`, `--review`, `--in-chain`, `--cwd <path>` and `--cwd=<path>`. Every other argument that does not begin with `--` is a positional argument. The classification is this closed list, first match wins:

1. An argument that begins with `--` and is not a flag, `--cwd` without a value, or a positional argument that is empty or holds only white space → `refuse`.
2. Two or more positional arguments of which at least one is exactly `rest` → `refuse`.
3. No positional argument, or exactly one positional argument that is exactly `rest`: `refuse` when `--in-chain` is present, otherwise `rest`.
4. Exactly one positional argument that is exactly `last` → `refuse`, with a reason that names `rest`. `last` is the word the request for this mode first used; it is not a mode and SHALL NOT be read as the description of a new issue.
5. Anything else → `other`.

`idd-all` SHALL run this classification before any other step. On `rest` it SHALL NOT ask which issue to run. On `refuse` it SHALL print the reason and the usage and do nothing else. On `other` its behaviour is unchanged.

#### Scenario: no positional argument starts rest mode

- **WHEN** `/idd-all` is invoked with no argument, or with flags only
- **THEN** the classification is `rest` and no question about which issue to run is asked

#### Scenario: a mistyped flag does not start a run

- **WHEN** `/idd-all` is invoked with an argument that begins with `--` and is not one of the flags
- **THEN** the classification is `refuse` and nothing runs

#### Scenario: the word last does not open an issue

- **WHEN** `/idd-all` is invoked with the single argument `last`
- **THEN** the classification is `refuse` and the reason tells the user to use `rest` or no argument

##### Example: argument forms

| argv | mode | Notes |
| ---- | ---- | ----- |
| (empty) | rest | no positional argument |
| `rest` | rest | the reserved word alone |
| `--pr` | rest | flags only |
| `--review --cwd /tmp/x` | rest | flags only, `--cwd` consumes its value |
| `rest --no-pr` | rest | reserved word with a flag |
| `rest #12` | refuse | `rest` with another positional argument |
| `#12 rest` | refuse | order does not matter |
| `--in-chain` | refuse | chain-internal flag without an issue |
| `rest --in-chain` | refuse | chain-internal flag without an issue |
| `--reveiw` | refuse | unknown flag |
| `--cwd` | refuse | flag without its value |
| an empty argument | refuse | nothing to classify |
| an argument of two spaces | refuse | white space only |
| `last` | refuse | not a mode; the reason names `rest` |
| `last --pr` | refuse | the same with a flag |
| `#12` | other | one issue |
| `#12 #13` | other | explicit batch |
| `Rest` | other | the reserved word is case-sensitive |
| `rest in peace` given as one argument | other | not exactly `rest` |
| `last call for papers` given as one argument | other | not exactly `last` |
| `#12 --in-chain` | other | chain call with an issue |

---
### Requirement: Every open issue falls into exactly one class

`rest-queue.py` SHALL put every open issue of the repository into exactly one of nine classes by this ordered table, first match wins:

1. `outsider` — the account that opened the issue, the last editor of its body, or the author of any of its comments has no write access to the repository, or one of these accounts cannot be read. A comment by a bot account does not count, as in the close stage.
2. `tracker` — the issue carries the label `north-star` or `epic`.
3. `unreadable` — the body of the issue has text and GitHub returns no rendering of it that this helper can read.
4. `needs-person` — the issue body shows at least one open clarity row.
5. `parked` — the actionability gate puts the issue in its `parked` group.
6. `blocked` — the actionability gate puts the issue in its `blocked` group.
7. `meeting` — the latest trusted Diagnosis records the type `meeting`.
8. `verified` — the first `Phase` line that GitHub's rendering of the body shows outside code blocks has the value `verified`.
9. `candidate` — every other issue.

Only `candidate` issues are run. The table SHALL be held as ordered data, and the classification SHALL be a pure function of these inputs: author has write access, last editor has write access, every commenter has write access, tracker label present, body rendering readable, open clarity row present, gate group (`actionable`, `parked`, `blocked`, `undiagnosed`), Diagnosis type is `meeting`, phase is `verified`.

The input "last editor has write access" SHALL be true when the body was never edited (GitHub reports neither a last editor nor a time of a last edit), true when GitHub names the last editor and that account has write access, and false in every other case: a body that was edited by an account GitHub does not return is treated as edited by an account without write access.

The three inputs about accounts SHALL be decided without reading the rendering of the body, so that an issue that holds text from an account without write access is `outsider` whatever its body renders to. For an issue whose body rendering is not readable, the inputs "open clarity row present" and "phase is `verified`" SHALL be false.

An issue that an earlier run left at the phase `verified` is listed and not run: it stopped at the last point where a person decides, and it continues when a person names it. Running such issues again is not part of this capability.

The judgements SHALL come from the existing implementations: open clarity rows from `scripts/lib/intent.py`, the gate group and the Diagnosis type from `scripts/lib/actionability.sh`, write access from `scripts/lib/ghread.py`, and the latest trusted Diagnosis from `scripts/lib/ghread.py`. `rest-queue.py` SHALL NOT contain a second implementation of any of them.

#### Scenario: an issue opened by an account without write access is never run

- **WHEN** an open issue was opened by an account without write access and would otherwise be a candidate
- **THEN** its class is `outsider` and it is not in the run order

#### Scenario: a comment by an account without write access keeps an issue out of the run

- **WHEN** an open issue by a maintainer carries a comment by an account without write access, and would otherwise be a candidate
- **THEN** its class is `outsider`, also when that comment is older than the comments the first read returned

#### Scenario: an issue with an unanswered clarity question waits for a person

- **WHEN** an open issue by a maintainer shows a clarity row whose status is `surfaced`
- **THEN** its class is `needs-person` and it is not in the run order

#### Scenario: an issue edited by an account that cannot be read is never run

- **WHEN** the body of an open issue by a maintainer was edited and GitHub does not return the account that edited it
- **THEN** its class is `outsider` and it is not in the run order

#### Scenario: an issue an earlier run verified is listed, not run

- **WHEN** the body of an open issue by a maintainer shows the phase `verified`, and none of the rules above it holds
- **THEN** its class is `verified` and it is not in the run order

##### Example: class precedence

| author writes | editor writes | commenters write | tracker | readable | open clarity row | gate group | meeting | verified | class |
| ------------- | ------------- | ---------------- | ------- | -------- | ---------------- | ---------- | ------- | -------- | ----- |
| no | yes | yes | no | yes | no | actionable | no | no | outsider |
| yes | no | yes | no | yes | no | actionable | no | no | outsider |
| yes | yes | no | no | yes | no | actionable | no | no | outsider |
| no | yes | yes | yes | yes | yes | parked | no | yes | outsider |
| no | yes | yes | no | no | no | actionable | no | no | outsider |
| yes | yes | yes | yes | yes | yes | blocked | no | no | tracker |
| yes | yes | yes | yes | no | no | actionable | no | no | tracker |
| yes | yes | yes | no | no | no | actionable | no | no | unreadable |
| yes | yes | yes | no | no | no | blocked | yes | no | unreadable |
| yes | yes | yes | no | yes | yes | blocked | no | yes | needs-person |
| yes | yes | yes | no | yes | no | parked | yes | yes | parked |
| yes | yes | yes | no | yes | no | blocked | no | yes | blocked |
| yes | yes | yes | no | yes | no | actionable | yes | yes | meeting |
| yes | yes | yes | no | yes | no | actionable | no | yes | verified |
| yes | yes | yes | no | yes | no | actionable | no | no | candidate |
| yes | yes | yes | no | yes | no | undiagnosed | no | no | candidate |

##### Example: edited by an account that cannot be read

- **GIVEN** three open issues opened by an account with write access: #5 was never edited, #6 was edited by an account with write access, and #7 was edited and GitHub returns no account for the editor
- **WHEN** the list is produced
- **THEN** #5 and #6 are candidates and #7 has the class `outsider`

---
### Requirement: Candidates run diagnosed first and then by issue number

The run order SHALL contain exactly the `candidate` issues. Candidates whose gate group is `actionable` SHALL come before candidates whose gate group is `undiagnosed`, and within each of the two groups the order SHALL be ascending issue number. The `### Conflict Class` of a Diagnosis SHALL NOT influence the order.

#### Scenario: diagnosed issues are run before undiagnosed ones

- **WHEN** the candidates are a mix of diagnosed and undiagnosed issues
- **THEN** every diagnosed candidate precedes every undiagnosed candidate

##### Example: four candidates in run order

- **GIVEN** candidates #9 (undiagnosed), #12 (actionable), #3 (undiagnosed) and #20 (actionable)
- **WHEN** the list is produced
- **THEN** the run order is 12, 20, 3, 9

---
### Requirement: The open issues are read completely or not at all

`rest-queue.py` SHALL read all open issues with one paginated GraphQL query. For an issue that has more comments than the query returned, it SHALL read all comments of that issue before choosing its latest trusted Diagnosis; when that second read returns fewer comments than the query said the issue has, the read has failed. When any page fails, a response lacks an expected field, a permission read fails for a reason other than the account not being found, or an `actionability.sh` function reports misuse, the command SHALL exit with code 3, print one reason line on stderr, and SHALL NOT print a list on stdout.

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

##### Example: fewer comments than the issue has

- **GIVEN** one open issue #5 for which the query reports 130 comments and returns the newest 100, and a second read of its comments that returns one comment
- **WHEN** `rest-queue.py list --json` runs
- **THEN** it does not exit 0, prints no list on stdout, and its reason line says that the comments of #5 could not be read completely

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

---
### Requirement: The outcome of an issue is read from GitHub

`rest-queue.py record --issue N` SHALL read the state of issue N from GitHub. It SHALL record the outcome `closed` when the issue is closed, and `stopped` otherwise. In both cases it SHALL keep the reason it was given: an issue that someone closed while its run reported a stop is closed, and the report still says what its run reported. An issue recorded as `stopped` without a reason gets the reason `no reason given`. The reason is given as `--reason TEXT` or, with `--reason-stdin`, on standard input; `stop` takes the same two forms. Giving both forms is a usage error. It SHALL accept only the issue that is in flight: for any other issue number it SHALL exit 1 and leave the run state unchanged.

#### Scenario: a claimed close is not trusted

- **WHEN** `record` is called for the in-flight issue and GitHub reports the issue as open
- **THEN** the recorded outcome is `stopped`, whatever the caller believes

##### Example: outcomes by issue state

| issue state on GitHub | --reason | recorded outcome | recorded reason |
| --------------------- | -------- | ---------------- | --------------- |
| CLOSED | (none) | closed | (empty) |
| CLOSED | `Stopped: /idd-close did not finish` | closed | `Stopped: /idd-close did not finish` |
| OPEN | `verify gate: not_clean` | stopped | `verify gate: not_clean` |
| OPEN | (none) | stopped | `no reason given` |

##### Example: a reason on standard input is taken as it is

- **GIVEN** a run in which #5 is in flight and open on GitHub
- **WHEN** `record --issue 5 --reason-stdin` runs with the standard input ``it's `whoami` and $(touch made-by-the-reason)``
- **THEN** the recorded reason is that text, and no file `made-by-the-reason` exists

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

A state file that this helper cannot use and that was written in the last 24 hours SHALL make `start` exit with code 3 and leave the file as it is: the review flag of that run cannot be read, and a new run in its place would drop it. The reason line SHALL name the file and say that it is to be deleted when no rest run is going on in this working tree. A state file of a run that the previous version of this helper wrote is such a file. A state that can be read and belongs to a run for another repository is not: `start` replaces it and says whose it was, and does not say of it that it is older than 24 hours. A state file older than 24 hours is replaced by the new run. When that file can be read and its run was not ended by `report`, `start` SHALL first print what that run left and nobody was told: the directory of each of its issues.

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
| a symbolic link to a usable state | 1 hour ago | exits 3, names the file, and the link is unchanged |
| a symbolic link to a usable state | 25 hours ago | exits 0, begins a new run, and the link is replaced by a file; the file the link pointed at is unchanged |

- **GIVEN** a working tree with the state file of the row, and candidate #5
- **WHEN** `start --path PR --review no` runs
- **THEN** the outcome is that of the row

##### Example: a run that was never reported is not forgotten

- **GIVEN** a run state whose last activity was 25 hours ago, in which #5 is recorded as stopped with its directory; and candidate #9
- **WHEN** `start --path PR --review no` runs
- **THEN** it exits 0, begins a new run, and before the list prints the directory of #5

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

Under the entry of every issue that has a directory, whether it is recorded as closed or as stopped, the report SHALL name the directory. When it names at least one, it SHALL say once that rest mode removes no directory; that a directory may hold work that exists nowhere else (commits that were not pushed, changes that were not committed, a stash, a tag, records of the plugin); that a person looks at it and deletes it; and that a later rest run does not take up an issue whose directory is still there. Under the entry of an issue that is in flight when `report` runs, the report SHALL name its directory and say that the issue was handed out and has no recorded outcome. When `record` found the working tree at `--cwd` changed while the issue ran, the report SHALL say which of the checked-out commit, the branch, the files and the stash changed, and that rest mode does not write there (requirement "A rest run leaves the working tree it was started in as it was").

The report tells a person to take one kind of step, and this list is closed: delete the directory of an issue after looking at it. A check of this capability SHALL take that step and see the result: a later run hands the issue out again while it is a candidate without other existing work. Looking at a directory, a branch, a commit or a pull request is not such a step. No line under an issue recorded as stopped SHALL tell the person to name the issue (`/idd-all #N`).

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
- **THEN** one line names #5 as handed out without a recorded outcome, and names `T/.claude/worktrees/rest-5`

---
### Requirement: All open clarity rows are available from one implementation

`scripts/lib/intent.py` SHALL provide `open_clarity_rows(issue)`, which returns the text of every open clarity row the issue body shows: the rows of rendered tables in document order, followed by the rows GitHub did not render as a table. `open_clarity_row(issue)` SHALL return the first element of that list, or `None` when the list is empty, so that the close stage keeps its behaviour.

#### Scenario: the close stage sees the same first row as before

- **WHEN** an issue body shows several open clarity rows
- **THEN** `open_clarity_row` returns the first of the rows that `open_clarity_rows` returns

##### Example: two open rows and one resolved row

- **GIVEN** a body whose clarity table has three rows with the statuses `surfaced`, `resolved @ 2026-11-10T05:36:57Z (reason: answered)` and `deferred`
- **WHEN** `open_clarity_rows` is called
- **THEN** it returns two texts, the first for the `surfaced` row and the second for the `deferred` row, and `open_clarity_row` returns the first

---
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
### Requirement: A rest run keeps its review flag

A rest run started with `--review` stops every issue at verified; a run that loses the flag merges and closes instead. The flag SHALL therefore live in the run state and reach the close stage without passing through anything a context compaction can lose.

`start` SHALL store the review flag of a new run. When it resumes a run, review is on when the stored run has it or this `start` gives it: the flag can be added to a run and cannot be dropped from it, and `start` SHALL say so when the two differ. Ending the run with `report` is the way to drop it. When `start` adds the flag to a run that has an issue in flight, it SHALL say that a close stage already running for that issue is not stopped by it: the close stage reads the flag once, when it starts. A state file that cannot be used does not lose the flag by being replaced: `start` does not replace such a file within 24 hours of its last write (requirement "Start prints the list and resumes an unfinished run").

`next` SHALL print the review flag of the run (`"review": "yes"` or `"no"`) with every issue it hands out, in flight or not. `idd-all` SHALL take the review flag of each issue from there.

The state of a rest run is below the directory the run was started in; the close stage of an issue runs in the directory of that issue. `close-stage.py init` SHALL take `--rest-root R`, the directory the rest run was started in, for an issue of a rest run, and `--rest-root none` for any other run; the option is required, so that a value lost on the way is a usage error and not a run without its rest. `init` SHALL refuse, with a usage error and no run state written, when `R` is given and the run at `R` does not have the issue in flight in a directory that is exactly `--cwd`, and when `none` is given and `--cwd` is `X/.claude/worktrees/rest-<N>` for a working tree `X` whose run has the issue `N` in flight there. `init` SHALL record `R` in the run of the issue. `run` SHALL stop without merging when that record names `R` and the run at `R` cannot be read, has ended, or does not have the issue in flight in that directory: the review flag of the issue's rest run can no longer be read.

`close-stage.py init` records the run of one issue, and `close-stage.py run` merges when that record says review is off. `init` SHALL refuse to record review as off for an issue that a rest run with review on has in flight: it SHALL exit with a usage error and write no run state, so that `run` finds none and stops at verified. Its message SHALL name both ways out: give `--review yes`, or, when the issue was named by a person while that rest run is unfinished, end the rest run first. `run` SHALL stop without merging for an issue that such a run with review on has in flight, whatever the record of that issue says: the flag can be added to the run after `init` recorded the issue. `run` reads that state once, when it starts.

`close-stage.py rest-review --cwd C --repo O/R --issue N` SHALL print the reading as one word. This list is closed.

- `on`: the run of the issue at `C` names a rest root `R`, and the run at `R` has review on and `N` in flight in `C`.
- `off`: the run of the issue at `C` names a rest root whose run has review off and `N` in flight in `C`; or it names none, or there is no run of the issue at `C`, and no rest run has `N` in flight in `C` or at `C`.
- `elsewhere`: the run of the issue at `C` names no rest root, or there is none, and a rest run has `N` in flight in a directory of its own: either `C` is the working tree of that run, or `C` is at the place of that run's directory for `N`. The pipeline of the issue then runs in the wrong place, or without its rest root.
- `unreadable`: the run of the issue names a rest root whose run cannot be read, has ended, or does not have `N` in flight in `C`; or a state file of a rest run that was changed in the last 24 hours is not a usable state.

`init` with `--rest-root none` SHALL exit with a usage error and write no run state when the reading is `elsewhere`, whatever the review value, and its message SHALL name the directory the issue runs in. `unreadable` does not change what `init` does. `run` SHALL stop without merging for `elsewhere` and for `unreadable`, and its reason SHALL say which. Phase 5 of `idd-all` SHALL take the review of a rest run from that command and from nowhere else, and SHALL treat every word other than `off` as review: the close stage stops at verified for it, so the body of the pull request does not promise a merge.

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
- **WHEN** `close-stage.py init` runs for issue 5 with `--cwd` as the second column says and the `--rest-root` and the review value of the next two columns, and otherwise valid arguments
- **THEN** the exit code and the run state of #5 are those of the row; in the rows that give `none` with #5 in flight the message names the directory of #5

##### Example: review added while an issue is in flight

| the run is resumed with | `close-stage.py run` for #5 in its directory |
| --- | --- |
| `--review yes` | exits 3, and its reason says that the rest run has `--review` |
| `--review no` | does not give that reason |

- **GIVEN** a rest run started with `--review no` in which #5 is in flight, and a `close-stage.py init --rest-root T` for #5 with `--review no` that succeeded in the directory of #5
- **WHEN** `start` runs again with the flag of the first column, and then `close-stage.py run` for #5
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
- **WHEN** what the row says happens, and then `close-stage.py run` for #5 runs there
- **THEN** the close stage does what the row says

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
### Requirement: A rest run leaves the working tree it was started in as it was

From before `start` to after `report`, a rest run SHALL leave the repository at `--cwd` as it was: the commit and the branch that are checked out, the index, the stash, the local branches and tags, and every file in the working tree, whether git tracks it, does not track it or ignores it. A person or another session MAY work there while the run goes. The skill SHALL say so.

Rest mode writes at these places of that repository, and this list is closed: the state folder of the run (`.claude/.idd/state/` below `--cwd`); the folder of the directories (`.claude/worktrees/` at the top); and the local exclude file of the git directory, to which `start` adds the rule for `.claude/worktrees/` when git does not ignore that folder yet. The existing-work check that `next` runs fetches from `origin`: that moves remote-tracking branches and can bring tags that `origin` has, and changes no tag and no local branch that is there.

Reading a repository can write it: `git status` refreshes the index and writes it back when it can take the lock. Every git command of `rest-queue.py` and of the existing-work check it runs SHALL therefore run without optional locks (`--no-optional-locks`, or `GIT_OPTIONAL_LOCKS=0` for a program it starts), so that no read writes the index.

A helper cannot see an edit that the model makes, with its own tools, to a file of the starting working tree while an issue runs. `next` SHALL therefore record, at the hand-out, the commit and the branch checked out at `--cwd`, what git lists as changed or untracked there, and the stash; `record` SHALL read them again before it writes anything there. When they differ, `record` SHALL store which of the four changed, and the report SHALL say so under the entry of that issue, together with the fact that rest mode does not write there. This does not stop the run: a person may have made the change.

Before it reads anything, `start` SHALL ask git whether `.claude/worktrees/` would be ignored at the top of the repository. When git would not ignore it, `start` SHALL add the rule through the plugin's writer for local runtime paths and ask again; when git still would not ignore it, `start` SHALL exit with code 3 and a reason line that names the folder.

#### Scenario: a run changes nothing in the working tree it was started in

- **WHEN** a rest run handed out two issues, one whose directory was removed and one whose directory was kept, and ended with `report`
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

- **GIVEN** a run at `T` in which `next` handed out #5
- **WHEN** what the row says happens, and then `record --issue 5` and `report` run
- **THEN** the report says what the row says, and `record` exited with code 0

##### Example: the folder of the directories is ignored before a run starts

- **GIVEN** a repository at `T` in which no ignore rule covers `.claude/worktrees/`, and candidate #5
- **WHEN** `start` and `next` run
- **THEN** `start` exits 0, `git status` at `T` lists nothing below `.claude/worktrees/` after `next`, and the rule is in the local exclude file of `T` and in no tracked file

##### Example: reading the starting working tree does not write its index

- **GIVEN** a repository at `T` whose tracked `d.txt` was given an older modification time after the index was written, and candidate #5
- **WHEN** `start`, `next` and `record --issue 5` run
- **THEN** the bytes of the index file of `T` are those before `start`

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
