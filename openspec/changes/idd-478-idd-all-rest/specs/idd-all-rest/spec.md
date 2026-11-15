## Purpose

`/idd-all` invoked without an issue runs every remaining open issue of the repository through the single-issue pipeline. This capability defines which invocations select that mode, how open issues are classified and ordered, how a run records what it tried, when a run stops as a whole, and what it reports.

## ADDED Requirements

### Requirement: Rest mode is selected by a closed list of argument forms

`scripts/rest-queue.py args -- <argv>` SHALL classify an `/idd-all` invocation as `rest`, `other` or `refuse` and print one JSON line with the key `mode` (and `reason` for `refuse`). It SHALL exit 0 for `rest` and `other`, and 1 for `refuse`.

Flags are `--pr`, `--no-pr`, `--review`, `--in-chain`, `--cwd <path>` and `--cwd=<path>`. Every other argument that does not begin with `--` is a positional argument. The classification is this closed list, first match wins:

1. An argument that begins with `--` and is not a flag, or `--cwd` without a value → `refuse`.
2. Two or more positional arguments of which at least one is exactly `rest` → `refuse`.
3. No positional argument, or exactly one positional argument that is exactly `rest`: `refuse` when `--in-chain` is present, otherwise `rest`.
4. Anything else → `other`.

`idd-all` SHALL run this classification before any other step. On `rest` it SHALL NOT ask which issue to run. On `refuse` it SHALL print the reason and the usage and do nothing else. On `other` its behaviour is unchanged.

#### Scenario: no positional argument starts rest mode

- **WHEN** `/idd-all` is invoked with no argument, or with flags only
- **THEN** the classification is `rest` and no question about which issue to run is asked

#### Scenario: a mistyped flag does not start a run

- **WHEN** `/idd-all` is invoked with an argument that begins with `--` and is not one of the flags
- **THEN** the classification is `refuse` and nothing runs

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
| `#12` | other | one issue |
| `#12 #13` | other | explicit batch |
| `Rest` | other | the reserved word is case-sensitive |
| `rest in peace` given as one argument | other | not exactly `rest` |
| `#12 --in-chain` | other | chain call with an issue |

### Requirement: Every open issue falls into exactly one class

`rest-queue.py` SHALL put every open issue of the repository into exactly one of eight classes by this ordered table, first match wins:

1. `outsider` — the account that opened the issue, the last editor of its body, or the author of any of its comments has no write access to the repository, or one of these accounts cannot be read. A comment by a bot account does not count, as in the close stage.
2. `tracker` — the issue carries the label `north-star` or `epic`.
3. `needs-person` — the issue body shows at least one open clarity row.
4. `parked` — the actionability gate puts the issue in its `parked` group.
5. `blocked` — the actionability gate puts the issue in its `blocked` group.
6. `meeting` — the latest trusted Diagnosis records the type `meeting`.
7. `verified` — the first `Phase` line that GitHub's rendering of the body shows outside code blocks has the value `verified`.
8. `candidate` — every other issue.

Only `candidate` issues are run. The table SHALL be held as ordered data, and the classification SHALL be a pure function of these inputs: author has write access, last editor has write access, every commenter has write access, tracker label present, open clarity row present, gate group (`actionable`, `parked`, `blocked`, `undiagnosed`), Diagnosis type is `meeting`, phase is `verified`.

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

##### Example: class precedence

| author writes | editor writes | commenters write | tracker | open clarity row | gate group | meeting | verified | class |
| ------------- | ------------- | ---------------- | ------- | ---------------- | ---------- | ------- | -------- | ----- |
| no | yes | yes | no | no | actionable | no | no | outsider |
| yes | no | yes | no | no | actionable | no | no | outsider |
| yes | yes | no | no | no | actionable | no | no | outsider |
| no | yes | yes | yes | yes | parked | no | yes | outsider |
| yes | yes | yes | yes | yes | blocked | no | no | tracker |
| yes | yes | yes | no | yes | blocked | no | yes | needs-person |
| yes | yes | yes | no | no | parked | yes | yes | parked |
| yes | yes | yes | no | no | blocked | no | yes | blocked |
| yes | yes | yes | no | no | actionable | yes | yes | meeting |
| yes | yes | yes | no | no | actionable | no | yes | verified |
| yes | yes | yes | no | no | actionable | no | no | candidate |
| yes | yes | yes | no | no | undiagnosed | no | no | candidate |

### Requirement: Candidates run diagnosed first and then by issue number

The run order SHALL contain exactly the `candidate` issues. Candidates whose gate group is `actionable` SHALL come before candidates whose gate group is `undiagnosed`, and within each of the two groups the order SHALL be ascending issue number. The `### Conflict Class` of a Diagnosis SHALL NOT influence the order.

#### Scenario: diagnosed issues are run before undiagnosed ones

- **WHEN** the candidates are a mix of diagnosed and undiagnosed issues
- **THEN** every diagnosed candidate precedes every undiagnosed candidate

##### Example: four candidates in run order

- **GIVEN** candidates #9 (undiagnosed), #12 (actionable), #3 (undiagnosed) and #20 (actionable)
- **WHEN** the list is produced
- **THEN** the run order is 12, 20, 3, 9

### Requirement: The open issues are read completely or not at all

`rest-queue.py` SHALL read all open issues with one paginated GraphQL query. For an issue that has more comments than the query returned, it SHALL read all comments of that issue before choosing its latest trusted Diagnosis. When any page fails, a response lacks an expected field, a permission read fails for a reason other than the account not being found, or an `actionability.sh` function reports misuse, the command SHALL exit with code 3, print one reason line on stderr, and SHALL NOT print a list on stdout.

#### Scenario: a failed page fails the whole command

- **WHEN** the second page of the query fails
- **THEN** the command exits non-zero and prints no list

##### Example: second page fails

- **GIVEN** a repository whose open issues span two pages, and the request for the second page exits 1
- **WHEN** `rest-queue.py list --repo o/r --json` runs
- **THEN** the exit code is not 0 and stdout is empty

##### Example: Diagnosis older than the last 100 comments

- **GIVEN** issue #7 with 130 comments, where the only trusted `## Diagnosis` comment is the 5th comment and its Complexity is `Simple`
- **WHEN** the list is produced
- **THEN** issue #7 has gate group `actionable`, not `undiagnosed`

### Requirement: Each issue is attempted at most once per run

`rest-queue.py next` SHALL re-read the open issues and hand out the first issue of the run order that this run has not handed out before, recording it in the run state as in flight at that moment. When no such issue exists it SHALL print `done`. While an issue is in flight and has no recorded outcome, `next` SHALL hand out that same issue again with `in_flight` true and SHALL NOT hand out another one.

An issue opened after the run started SHALL be handed out by a later `next` when it is a candidate.

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

### Requirement: A stopped issue does not stop the run and a stopped run hands out nothing

An issue recorded as `stopped` SHALL NOT end the run: the following `next` hands out the next issue. `rest-queue.py stop --reason TEXT` SHALL mark the whole run as stopped; every later `next` of that run SHALL print the stop reason and hand out nothing.

`idd-all` SHALL call `stop` only in these three cases: the default branch cannot be checked out or fast-forwarded between two issues in PR mode; a `rest-queue.py` command exits with code 3 (GitHub or a helper could not be read); `gh` authentication is lost. Exit codes 1 and 2 of `rest-queue.py` mean the call itself was wrong and are corrected, not treated as a stop. An interruption by the user leaves the run state in place without a stop record.

#### Scenario: one failing issue does not end the run

- **WHEN** the first issue of a run is recorded as stopped
- **THEN** the next `next` hands out the second issue

##### Example: stop ends the run

- **GIVEN** a run with candidates #5 and #9, where #5 was recorded as stopped
- **WHEN** `stop --reason "default branch could not be fast-forwarded"` is called and then `next`
- **THEN** `next` prints `{"next": null, "stopped": "default branch could not be fast-forwarded"}` and #9 is not handed out

### Requirement: Start prints the list and resumes an unfinished run

`rest-queue.py start` SHALL print the number of open issues, the issue numbers of every class, and the run order, before any issue is handed out. It SHALL print issue numbers only, no issue titles.

When the working tree holds the state of a run of the same repository whose last recorded activity (start, hand-out, record or stop) is less than 24 hours old and that was not ended by `report`, `start` SHALL resume it: the recorded attempts and a recorded stop are kept, and the attempts are not handed out again. Otherwise `start` SHALL begin a new run with no attempts.

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

### Requirement: Report lists what happened and ends the run

`rest-queue.py report` SHALL print one report with: the issues recorded as closed; the issues recorded as stopped, each with its reason; the `needs-person` issues, each with the text of every open clarity row; the issues of every other class that was not run; and the stop reason of the run when there is one. It SHALL then delete the run state. When the open issues cannot be re-read, it SHALL still print the recorded attempts, say that the list could not be read, and delete the run state.

#### Scenario: the report ends the run

- **WHEN** `report` has run
- **THEN** the run state file no longer exists and a later `next` exits 1

##### Example: report with one closed, one stopped and one waiting issue

- **GIVEN** a run in which #5 was recorded as closed and #9 as stopped with the reason `verify gate: not_clean`, and an open issue #14 whose body shows two open clarity rows
- **WHEN** `report` runs
- **THEN** the output names #5 under closed, #9 with `verify gate: not_clean` under stopped, #14 with both row texts under waiting for a person, and the state file is gone

### Requirement: All open clarity rows are available from one implementation

`scripts/lib/intent.py` SHALL provide `open_clarity_rows(issue)`, which returns the text of every open clarity row the issue body shows: the rows of rendered tables in document order, followed by the rows GitHub did not render as a table. `open_clarity_row(issue)` SHALL return the first element of that list, or `None` when the list is empty, so that the close stage keeps its behaviour.

#### Scenario: the close stage sees the same first row as before

- **WHEN** an issue body shows several open clarity rows
- **THEN** `open_clarity_row` returns the first of the rows that `open_clarity_rows` returns

##### Example: two open rows and one resolved row

- **GIVEN** a body whose clarity table has three rows with the statuses `surfaced`, `resolved @ 2026-11-10T05:36:57Z (reason: answered)` and `deferred`
- **WHEN** `open_clarity_rows` is called
- **THEN** it returns two texts, the first for the `surfaced` row and the second for the `deferred` row, and `open_clarity_row` returns the first

### Requirement: idd-all runs rest mode as a loop over the single-issue pipeline

In rest mode `idd-all` SHALL call `rest-queue.py start`, then repeat: `next`; run the single-issue pipeline for the issue handed out, with the flags of this invocation; `record` with the stop reason the single-issue report printed, if any; in PR mode check out the default branch and fast-forward it as the batch mode of capability `parallel-orchestration` requires. It SHALL leave the loop when `next` prints `done` or a stop reason, and SHALL then call `rest-queue.py report` and relay its output.

In rest mode `idd-all` SHALL NOT take over work that already exists: when the existing-work check of the single-issue pipeline returns `resume` or `blocked` for the issue handed out, it SHALL create no branch, leave the pull request untouched, and record the issue with a reason that names the pull request or branch.

#### Scenario: the loop ends with the report

- **WHEN** `next` prints `done`
- **THEN** `idd-all` calls `report` and starts no further issue

#### Scenario: an issue that already has a pull request is listed, not resumed

- **WHEN** the issue handed out has an open pull request on its own `idd/<N>-…` branch
- **THEN** `idd-all` records it as stopped with the reason `existing work: PR #<P>` and asks `next` for the following issue

##### Example: the skill names the loop commands in order

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the rest section is read
- **THEN** it contains the invocations `rest-queue.py" start`, `rest-queue.py" next`, `rest-queue.py" record`, `rest-queue.py" stop` and `rest-queue.py" report`, with `start` before `next`, `next` before `record`, and `report` last; Step 0.1 contains the invocation `rest-queue.py" args`; the rest section states that `resume` and `blocked` are recorded with the reason `existing work: `; and Phase 6 sends a rest run back to the rest section
