# idd-all-rest Specification

## Purpose

`/idd-all` invoked without an issue runs every remaining open issue of the repository through the single-issue pipeline. This capability defines which invocations select that mode, how open issues are classified and ordered, how a run records what it tried, when a run stops as a whole, and what it reports.

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

`rest-queue.py next` SHALL re-read the open issues and hand out the first issue of the run order that this run has not handed out before, recording it in the run state as in flight at that moment. When no such issue exists it SHALL print `done`. While an issue is in flight and has no recorded outcome, `next` SHALL hand out that same issue again with `in_flight` true and SHALL NOT hand out another one. With it, `next` SHALL print the name of a local branch of that issue as `branch`, or `null` when the working tree has none: an issue without a branch had not reached the step that creates it.

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
- **THEN** it prints `{"next": 5, "in_flight": true, "branch": null}` and the run state still holds exactly one attempt

##### Example: an issue with a local branch is recorded, not handed out

- **GIVEN** a run whose candidates are #5 and #9, in a working tree that has the local branch `idd/5-old`
- **WHEN** `next` is called
- **THEN** it hands out #9, and the run state holds #5 as stopped with the reason `existing work: local branch idd/5-old`

##### Example: the in-flight issue names its branch

- **GIVEN** a run in which `next` handed out #5, no outcome was recorded, and the working tree has the local branch `idd/5-x`
- **WHEN** `next` is called again
- **THEN** it prints `{"next": 5, "in_flight": true, "branch": "idd/5-x"}`

---
### Requirement: The outcome of an issue is read from GitHub

`rest-queue.py record --issue N` SHALL read the state of issue N from GitHub. It SHALL record the outcome `closed` when the issue is closed, and `stopped` with the text of `--reason` otherwise. It SHALL accept only the issue that is in flight: for any other issue number it SHALL exit 1 and leave the run state unchanged.

#### Scenario: a claimed close is not trusted

- **WHEN** `record` is called for the in-flight issue and GitHub reports the issue as open
- **THEN** the recorded outcome is `stopped`, whatever the caller believes

##### Example: outcomes by issue state

| issue state on GitHub | --reason | recorded outcome | recorded reason |
| --------------------- | -------- | ---------------- | --------------- |
| CLOSED | (none) | closed | (empty) |
| OPEN | `verify gate: not_clean` | stopped | `verify gate: not_clean` |
| OPEN | (none) | stopped | `no reason given` |

---
### Requirement: A stopped issue does not stop the run and a stopped run hands out nothing

An issue recorded as `stopped` SHALL NOT by itself end the run: once `settle` has succeeded for it, the following `next` hands out the next issue. What the issue left stays on its own branch. `rest-queue.py stop --reason TEXT` SHALL mark the whole run as stopped; every later `next` of that run SHALL print the stop reason and hand out nothing.

`idd-all` SHALL call `stop` only when a `next`, a `record` or a `settle` of a run that exists exits with code 3: GitHub, `gh` authentication or a helper could not be read, the run state could not be written, or the working tree could not be settled between two issues. When `stop` itself exits with a code other than 0, `idd-all` SHALL go on to `report`. Exit codes 1 and 2 of `rest-queue.py` mean the call itself was wrong and are corrected, not treated as a stop. An interruption by the user leaves the run state in place without a stop record.

When the `start` that would begin a run exits with code 3, no run exists and there is nothing to stop or to report; a `start` that refuses the path of the invocation is one of these. `idd-all` SHALL relay the reason line that `start` printed and end, and SHALL NOT call `stop` or `report`. The same holds when that `start` would have resumed an earlier run: the state of the earlier run is left as it is, so that a later `start` resumes it.

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

---
### Requirement: Start prints the list and resumes an unfinished run

`rest-queue.py start --path P` SHALL print the number of open issues, the issue numbers of every class, and the run order, before any issue is handed out. It SHALL print issue numbers only, no issue titles. The run order it prints SHALL hold only the candidates that have no local branch in the working tree. The candidates that have one (`idd/<N>` or `idd/<N>-…`) SHALL be printed on a line of their own, which says that they are recorded as existing work when their turn comes. `start` SHALL also say that a candidate with a pull request or a branch on GitHub is recorded as existing work when its turn comes. Every reason and every time it prints from the run state SHALL be on one line, without control characters and no longer than the helper's limit for a reason, whatever the state file holds.

`P` is the path that `idd-all` resolved for this invocation. Rest mode runs on the PR path only: between two issues, what an issue left is kept on that issue's own branch, and only the PR path gives every issue a branch. When `P` is not `PR`, `start` SHALL exit with code 3, write nothing, and print a reason line that says rest mode needs the PR path and names what a person can do: pass `--pr`, install the ralph-loop plugin when its absence is what downgraded the path, or name the issues one at a time. A new run SHALL read the default branch of the repository from GitHub and store it in the run state together with the path; `settle` takes the default branch from there. A resumed run keeps the default branch it stored.

When the working tree holds the state of a run of the same repository whose last recorded activity (start, hand-out, record or stop) is less than 24 hours old and that was not ended by `report`, `start` SHALL resume it: the recorded attempts and a recorded stop are kept, and the attempts are not handed out again. Otherwise `start` SHALL begin a new run with no attempts. A state file whose start time cannot be read as a time, with an attempt that has no reason, without a stored default branch, or whose stored path is not `PR`, is not a state this helper can use.

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
- **WHEN** `start --path direct-commit` runs
- **THEN** it exits 3, its reason line names `--pr`, and no run state file exists

##### Example: start stores the default branch

- **GIVEN** a repository whose default branch on GitHub is `trunk`, and a working tree without a run state
- **WHEN** `start --path PR` runs
- **THEN** it exits 0 and the run state holds the path `PR` and the default branch `trunk`

##### Example: candidates with a local branch are listed apart

- **GIVEN** candidates #5 and #9, in a working tree that has the local branch `idd/5-old`
- **WHEN** `start --path PR` runs
- **THEN** the line of the run order names #9 and not #5, and another line names #5 as a candidate with a local branch

##### Example: an account without write access cannot start a run

- **GIVEN** an open issue #5 opened by `alice`, and a GitHub that answers HTTP 403 to the question whether `alice` has write access
- **WHEN** `start --path PR` runs
- **THEN** it exits 3, its reason line says that rest mode needs an account with write access, and no run state file exists

---
### Requirement: Report lists what happened and ends the run

`rest-queue.py report` SHALL print one report with: the issues recorded as closed; the issues recorded as stopped, each with its reason; the `needs-person` issues, each with the complete text of every open clarity row, one line per row and not shortened; the issues of every other class that was not run; and the stop reason of the run when there is one. It SHALL then delete the run state. When the open issues cannot be re-read, for whatever reason, it SHALL still print the recorded attempts, say that the list could not be read, and delete the run state.

An issue that this run handed out SHALL appear once: under closed, under stopped or as handed out without a result. It SHALL NOT appear in the list of issues waiting for a person or in the line of a class that was not run. When such an issue is `needs-person` at the time of the report, the report SHALL print its open questions under the entry of that issue, also when the issue was recorded as closed and reopened since. The report prints no text of an issue of any other class.

For the class `verified` the report SHALL say that such an issue continues when it is named (`/idd-all #N`). When at least one issue was recorded with a reason that begins with `existing work:`, the report SHALL say that such an issue is left for a person and that its reason names the pull request or branch to look at. Under the entry of an issue recorded as stopped, the report SHALL name each branch of that issue that `settle` kept and, when `settle` made a commit on it, that commit and the paths it holds (at most ten, then the number of the others). Under the entry of an issue recorded as closed, it SHALL name the branch, the commit and the paths only when `settle` made a commit. When one of those paths is a log shared by all issues (`.claude/.idd/routing-stats.jsonl`, or a file under `.claude/.idd/issue-runs/`), the report SHALL say so on that entry: the new lines of that log are on that branch and not on the default branch. When the report names a kept branch, it SHALL say once what a person can do: a later rest run records an issue with a kept branch as existing work; to have the issue started over, delete the branch; to keep its work, look at the branch first. It SHALL NOT tell the person to name the issue (`/idd-all #N`) as the way to continue a kept branch.

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

- **GIVEN** a run in which #5 was recorded as stopped and `settle` kept the branch `idd/5-x`
- **WHEN** `report` runs
- **THEN** one line of it says that deleting the branch lets a later rest run start the issue over, and that line does not hold `/idd-all`

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

In rest mode `idd-all` SHALL first run, once, the steps of the single-issue pipeline that check the working tree, the flags and the dependencies, and SHALL resolve the path and the interaction mode, including the step that can downgrade the path. In doing so it SHALL NOT write the unattended marker and SHALL NOT create a branch. When the configuration asks for a question about the path (`pr_policy: ask`), rest mode SHALL ask whether to start the run on the PR path and SHALL offer no other path.

It SHALL then call `rest-queue.py start` with the path it resolved. When `start` exits with code 3, `idd-all` SHALL relay the reason line, clear the unattended marker and end.

It SHALL then repeat: `next`; run the single-issue pipeline for the issue handed out, with the flags of this invocation and with the path and the interaction mode resolved before `start`, which are neither resolved nor downgraded again for a later issue; `record` with the stop reason the single-issue report printed, if any; `rest-queue.py settle` for that issue, with the issue number and no path or branch. It SHALL leave the loop when `next` prints `done` or a stop reason, and SHALL then call `rest-queue.py report` and relay its output.

In rest mode `idd-all` SHALL NOT take over work that already exists: when the existing-work check of the single-issue pipeline returns `resume` or `blocked` for the issue handed out, it SHALL create no branch, leave the pull request untouched, ask no question, and record the issue with a reason that begins with `existing work: ` and holds the outcome the check printed and the next step for a person.

When `next` prints `in_flight` true, `idd-all` SHALL continue that issue. When the issue already has its Phase 6 result, it goes straight to `record`. When `next` reports no local branch for the issue (`branch` is `null`), the issue had not reached its own branch: `idd-all` SHALL start it again from the step that resolves the issue, the existing-work check included. Otherwise it SHALL continue the interrupted phase and SHALL NOT run the existing-work check of that issue again: the branch and the pull request the check would find are this run's own.

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
- **THEN** the numbered step before the `start` invocation names Step 0.2, Step 0.3, Step 0.35, Step 0.5 and Step 0.6 and says they run once; the line of the `start` invocation holds `--path "$PATH_AXIS"`; and the line of the `settle` invocation holds neither `--default` nor `--path`

##### Example: the skill continues an issue in flight

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the row of the rest section for `in_flight` true is read
- **THEN** it says to go to `record` when the issue has its Phase 6 result, to start again from Step 0.4 when `branch` is `null`, and otherwise to continue the interrupted phase without running Step 0.5.1 again

##### Example: the skill ends a refused run without a marker

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the row of the stop table for a `start` that exits with code 3 is read
- **THEN** it names a path that is not `PR` among the causes and holds `clear_unattended "$CWD"`

---
### Requirement: Between two issues one helper settles the working tree

After an issue is recorded and before the next one is handed out, `idd-all` SHALL call `rest-queue.py settle --issue N`. `settle` takes the default branch from the run state, where `start` stored it. `settle` SHALL accept only the issue this run recorded last, and SHALL exit 1 for any other issue and while an issue is in flight. A second `settle` for an issue it has already settled SHALL change nothing and print what the first one recorded. Until `settle` has succeeded for the issue recorded last, `next` SHALL exit 1 and name that issue. An issue that `next` itself recorded as existing work needs no `settle`: no work was started on it.

The paths in this requirement are relative to the directory `idd-all` runs in (`--cwd`), which need not be the top of the repository.

`settle` SHALL exit 3 and change nothing when git reports an unfinished merge, cherry-pick, revert or rebase. Otherwise it SHALL act on what it observes in the working tree, by this closed table, first match wins:

1. The working tree is on the issue's own branch (`idd/<N>` or `idd/<N>-…`). Every changed or untracked path that git does not ignore is a leftover, and `settle` SHALL handle the leftovers in three steps, in this order:
   1. **Regenerated records.** The folder `.claude/.idd/attachments/issue-<N>/` holds what `idd-diagnose` downloads for the issue, and `idd-diagnose` runs again, and writes that folder again, every time the issue is run. When `_manifest.json` is the only leftover in that folder, `settle` SHALL discard it. When the branch has no commit that `origin/<default>` lacks and no upstream, and every leftover lies in that folder and is either the manifest or a file that the manifest lists with the SHA-256 the file has, `settle` SHALL discard all of them. To discard is to delete an untracked file and to restore a tracked one to its committed content. `settle` SHALL discard nothing else.
   2. **Places that are never committed.** When a leftover that remains lies in a place whose writer keeps it out of git, `settle` SHALL exit 3 without having discarded or committed anything. These places are a closed list: `.claude/.idd/state/`, `.claude/.idd/archive/`, a name that begins with `.claude/.idd/tree-lock`, and `.claude/worktrees/`.
   3. **Everything else stays with the issue.** `settle` SHALL commit the leftovers that remain on that branch, without pushing, and SHALL record the branch, the commit and the committed paths in the run state before it does anything else.

   It SHALL then check out the default branch.
2. The working tree is on the default branch: any leftover SHALL make `settle` exit 3 and commit nothing, because no branch of the issue holds it and the next issue starts from a clean working tree.
3. The working tree is on any other branch, or on no branch: `settle` SHALL exit 3.

After the table, `settle` SHALL fetch the default branch from `origin` and exit 3 when it cannot. When the local default branch is behind `origin/<default>` it SHALL fast-forward it. When the local default branch has commits that `origin/<default>` lacks, `settle` SHALL leave it as it is: an issue on the PR path starts its branch from `origin/<default>`, not from the local default branch. It SHALL then confirm that `git status --porcelain` prints nothing in the working tree, which is the check every issue on the PR path starts with, and exit 3 otherwise.

`settle` SHALL then look at every local branch of the issue. A branch with no commits that `origin/<default>` lacks and no upstream holds no work, and `settle` SHALL delete it, since every commit of such a branch is on `origin/<default>`; it SHALL record every other one as kept. Every local branch of the issue was created by this run, because `next` does not hand out an issue that already has one. A `settle` that runs again after an earlier call stopped part of the way SHALL keep the commit and the paths that the earlier call recorded.

On exit 3, whichever step stopped, the reason line SHALL have one shape: the issue and the branch the working tree is on at that moment, what is wrong, what a person does next, and only then the detail, which is git's own words or at most three paths and the number of the others. The paths are shortened to fit and the number is never cut off. The whole line SHALL be no longer than the helper's limit for a reason.

#### Scenario: an issue branch with work and nothing left over

- **WHEN** the run of #5 ended on `idd/5-x`, which has one commit and nothing changed
- **THEN** `settle` makes no commit, checks out the default branch, fast-forwards it, and records `idd/5-x` as kept

#### Scenario: the working tree is on a branch of another issue

- **WHEN** `settle` is called for #5 and the working tree is on `idd/7-y`
- **THEN** it exits 3 and changes nothing

#### Scenario: a branch with an upstream is kept

- **WHEN** the run of #5 ended on `idd/5-x`, which has no commit that `origin/main` lacks and has an upstream
- **THEN** `settle` exits 0 and records `idd/5-x` as kept

#### Scenario: two branches of one issue

- **WHEN** the run of #5 ended on `idd/5-x`, which has one commit, and the branch `idd/5-y` exists with no commit of its own and no upstream
- **THEN** `settle` deletes `idd/5-y` and records `idd/5-x` as kept

##### Example: endings of the single-issue pipeline

Every way the single-issue pipeline ends on the PR path, what it leaves, and what `settle` makes of it. "handed out" in the last column means that `next` of a later rest run hands the issue out while it is a candidate; "existing work" means that `next` records it as existing work.

- **GIVEN** a run in which #5 was handed out, ended in the way the row names, and was recorded
- **WHEN** `settle --issue 5` runs, and then a new run is started
- **THEN** the exit code, the branches of #5 and the next run are those of the row; and on exit 0 the working tree is on the default branch and `git status --porcelain` prints nothing

| Ending | The working tree is on | What the ending leaves | Exit | Branches of #5 afterwards | A later rest run |
| --- | --- | --- | --- | --- | --- |
| `closed-before-start`: the issue was closed before any step ran | `main` | nothing | 0 | none | #5 is closed |
| `existing-work`: the existing-work check answered `resume` or `blocked` | `main` | nothing | 0 | none | handed out |
| `stop-before-download`: diagnose stopped before it downloaded anything | `idd/5-x`, no commit | nothing | 0 | none | handed out |
| `stop-after-diagnose`: the issue stopped after diagnose and before its first commit; it has no attachments | `idd/5-x`, no commit | the untracked manifest, written by `process-attachments.sh download` | 0 | none | handed out |
| `stop-after-diagnose-attachments`: the same, and the issue has one attachment that git does not ignore | `idd/5-x`, no commit | the untracked manifest and the downloaded file, both written by `process-attachments.sh download` | 0 | none | handed out |
| `stop-after-diagnose-ignored-attachments`: the same, and git ignores the downloaded files but not the manifest | `idd/5-x`, no commit | the untracked manifest, which lists one file | 0 | none | handed out |
| `stop-after-diagnose-tracked-manifest`: as `stop-after-diagnose`, and the manifest was already committed on the default branch by an earlier run | `idd/5-x`, no commit | the tracked manifest, changed by `process-attachments.sh download` | 0 | none | handed out |
| `stop-after-diagnose-foreign-file`: as `stop-after-diagnose`, and the folder also holds `notes.txt`, which the manifest does not list | `idd/5-x`, no commit | the untracked manifest and `notes.txt` | 0 | `idd/5-x`, with a commit that holds both paths | existing work |
| `meeting`: the meeting unwind committed the attachment folder on the branch and checked out the default branch | `main` | nothing; `idd/5-x` has one commit | 0 | `idd/5-x` | existing work |
| `stop-in-implement`: implement or the spec steps stopped part of the way | `idd/5-x`, one commit | a changed `a.txt`, a new `openspec/changes/idd-5-x/proposal.md`, and the untracked manifest | 0 | `idd/5-x`, with a commit that holds `a.txt` and the proposal and not the manifest | existing work |
| `stop-in-implement-attachments`: implement stopped part of the way, and the issue has one attachment that git does not ignore | `idd/5-x`, one commit | a changed `a.txt`, the untracked manifest and the downloaded file | 0 | `idd/5-x`, with a commit that holds `a.txt`, the manifest and the file | existing work |
| `stop-after-verify`: verify, the CI gate, the push or the pull request stopped the issue | `idd/5-x`, one commit | the untracked manifest and one new line in the tracked `.claude/.idd/routing-stats.jsonl` | 0 | `idd/5-x`, with a commit that holds the log and not the manifest | existing work |
| `stop-at-close-stage`: the issue was pushed and stopped at verified | `idd/5-x`, one commit, with an upstream | the same as `stop-after-verify` | 0 | `idd/5-x`, with a commit that holds the log | existing work |
| `merged-and-closed`: the pull request was squash-merged and the issue closed | `idd/5-x`, one commit, with an upstream; `origin/main` has the squash commit | a changed tracked manifest and one new line in the tracked `.claude/.idd/routing-stats.jsonl` | 0 | `idd/5-x`, with a commit that holds the log and not the manifest | #5 is closed |
| `on-another-branch`: the pipeline ended on a branch that is neither the default branch nor a branch of #5 | `wip` | nothing | 3 | unchanged | — |
| `leftover-on-default`: something was left on the default branch | `main` | an untracked `b.txt` | 3 | unchanged | — |
| `never-committed-place`: a file whose writer keeps it out of git is not ignored | `idd/5-x`, one commit | an untracked `.claude/.idd/tree-lock` and a changed `a.txt` | 3 | unchanged, no new commit | — |

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

##### Example: the working tree below the top of the repository

- **GIVEN** a repository whose folder `sub/` is the directory `idd-all` runs in, #5 recorded as stopped, the working tree on `idd/5-x` with no commit of its own, and the untracked `sub/.claude/.idd/attachments/issue-5/_manifest.json` as the only leftover
- **WHEN** `settle --cwd <repository>/sub --issue 5` runs
- **THEN** it exits 0, that manifest no longer exists, and the branch `idd/5-x` no longer exists
