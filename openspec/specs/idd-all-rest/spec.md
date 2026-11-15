# idd-all-rest Specification

## Purpose

`/idd-all` invoked without an issue runs every remaining open issue of the repository through the single-issue pipeline. This capability defines which invocations select that mode, how open issues are classified and ordered, how a run records what it tried, when a run stops as a whole, and what it reports.

## Requirements

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

---
### Requirement: Every open issue falls into exactly one class

`rest-queue.py` SHALL put every open issue of the repository into exactly one of eight classes by this ordered table, first match wins:

1. `outsider` — the account that opened the issue, the last editor of its body, or the author of any of its comments has no write access to the repository, or one of these accounts cannot be read. A comment by a bot account does not count, as in the close stage.
2. `tracker` — the issue carries the label `north-star` or `epic`.
3. `unreadable` — the body of the issue has text and GitHub returns no rendering of it that this helper can read.
4. `needs-person` — the issue body shows at least one open clarity row; or a comment of the issue records a skipped confirmation that no later Decision comment answered; or a comment that has to be read for such a record has text for which GitHub returns no rendering.
5. `parked` — the actionability gate puts the issue in its `parked` group.
6. `blocked` — the actionability gate puts the issue in its `blocked` group.
7. `meeting` — the latest trusted Diagnosis records the type `meeting`.
8. `candidate` — every other issue.

Only `candidate` issues are run. The table SHALL be held as ordered data, and the classification SHALL be a pure function of these inputs: author has write access, last editor has write access, every commenter has write access, tracker label present, body rendering readable, open question present (an open clarity row or an unanswered skipped confirmation), gate group (`actionable`, `parked`, `blocked`, `undiagnosed`), Diagnosis type is `meeting`.

The input "last editor has write access" SHALL be true when the body was never edited (GitHub reports neither a last editor nor a time of a last edit), true when GitHub names the last editor and that account has write access, and false in every other case: a body that was edited by an account GitHub does not return is treated as edited by an account without write access.

The three inputs about accounts SHALL be decided without reading the rendering of the body, so that an issue that holds text from an account without write access is `outsider` whatever its body renders to. For an issue whose body rendering is not readable, the input "open question present" SHALL be false.

An issue that an earlier run left at the phase `verified`, or that already has a pull request or a branch, is not a class of its own: it is a `candidate` unless one of the rules above holds, so that a run takes it up again. An issue whose earlier run stopped because a confirmation was skipped stays `needs-person` until a Decision comment answers it, so that the run does not repeat the work only to stop at the same place.

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

#### Scenario: an issue an earlier run verified is taken up again

- **WHEN** the body of an open issue by a maintainer shows the phase `verified`, and none of the rules above holds
- **THEN** its class is `candidate` and it is in the run order

#### Scenario: an issue edited by an account that cannot be read is never run

- **WHEN** the body of an open issue by a maintainer was edited and GitHub does not return the account that edited it
- **THEN** its class is `outsider` and it is not in the run order

##### Example: class precedence

| author writes | editor writes | commenters write | tracker | readable | open question | gate group | meeting | class |
| ------------- | ------------- | ---------------- | ------- | -------- | ------------- | ---------- | ------- | ----- |
| no | yes | yes | no | yes | no | actionable | no | outsider |
| yes | no | yes | no | yes | no | actionable | no | outsider |
| yes | yes | no | no | yes | no | actionable | no | outsider |
| no | yes | yes | yes | yes | yes | parked | no | outsider |
| no | yes | yes | no | no | no | actionable | no | outsider |
| yes | yes | yes | yes | yes | yes | blocked | no | tracker |
| yes | yes | yes | yes | no | no | actionable | no | tracker |
| yes | yes | yes | no | no | no | actionable | no | unreadable |
| yes | yes | yes | no | no | no | blocked | yes | unreadable |
| yes | yes | yes | no | yes | yes | blocked | no | needs-person |
| yes | yes | yes | no | yes | no | parked | yes | parked |
| yes | yes | yes | no | yes | no | blocked | yes | blocked |
| yes | yes | yes | no | yes | no | actionable | yes | meeting |
| yes | yes | yes | no | yes | no | actionable | no | candidate |
| yes | yes | yes | no | yes | no | undiagnosed | no | candidate |

##### Example: edited by an account that cannot be read

- **GIVEN** three open issues opened by an account with write access: #5 was never edited, #6 was edited by an account with write access, and #7 was edited and GitHub returns no account for the editor
- **WHEN** the list is produced
- **THEN** #5 and #6 are candidates and #7 has the class `outsider`

##### Example: an unanswered default keeps an issue waiting

- **GIVEN** three open issues by an account with write access, each with a trusted Diagnosis comment: on #5 that comment shows a `Reason` line with the literal `unattended-auto-Step-4-choice-default` and no Decision comment follows; on #6 the same comment is followed by a Decision comment; on #7 the literal stands only inside a code block of the comment
- **WHEN** the list is produced
- **THEN** #5 has the class `needs-person` and its questions name the unanswered confirmation, and #6 and #7 are candidates

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

An issue whose body has text for which GitHub returns no rendering this helper can read is not a failed read. The command SHALL give that issue the class `unreadable`, or `outsider` when the issue holds text from an account without write access, and SHALL classify and order every other issue as usual.

The comments of an issue are read with GitHub's rendering only when one of them holds the text of a skipped-confirmation literal. When such a comment has text and no rendering, that is not a failed read either: the issue is `needs-person`, with a question that says a comment could not be read.

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

##### Example: a comment GitHub does not render keeps the issue waiting

- **GIVEN** the open issue #7 by an account with write access, whose one comment holds the text `unattended-auto-Step-4-choice-default` and for which GitHub returns the empty string as its rendering, and the plain candidate #8
- **WHEN** `rest-queue.py list --repo o/r --json` runs
- **THEN** the exit code is 0, #7 has the class `needs-person` with one question that says a comment could not be read, and the run order is 8

##### Example: a body GitHub renders as nothing

- **GIVEN** open issues #5 (a plain candidate), #6 whose body is one HTML comment and whose rendering is the empty string, opened by an account with write access, and #7 with the same body, opened by an account without write access
- **WHEN** `rest-queue.py list --repo o/r --json` runs
- **THEN** the exit code is 0, #6 has the class `unreadable`, #7 has the class `outsider`, and the run order is 5

---
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

An issue recorded as `stopped` SHALL NOT end the run: the following `next` hands out the next issue. `rest-queue.py stop --reason TEXT` SHALL mark the whole run as stopped; every later `next` of that run SHALL print the stop reason and hand out nothing.

`idd-all` SHALL call `stop` only in these three cases: between two issues in PR mode the default branch cannot be checked out or fast-forwarded, or the working tree is not clean afterwards; a `rest-queue.py` command of a run that exists exits with code 3 (GitHub or a helper could not be read); `gh` authentication is lost. Exit codes 1 and 2 of `rest-queue.py` mean the call itself was wrong and are corrected, not treated as a stop. An interruption by the user leaves the run state in place without a stop record.

When the `start` that would begin a run exits with code 3, no run exists and there is nothing to stop or to report. `idd-all` SHALL relay the reason line that `start` printed and end, and SHALL NOT call `stop` or `report`. The same holds when that `start` would have resumed an earlier run: the state of the earlier run is left as it is, so that a later `start` resumes it.

#### Scenario: one failing issue does not end the run

- **WHEN** the first issue of a run is recorded as stopped
- **THEN** the next `next` hands out the second issue

#### Scenario: a failed start leaves no run behind

- **WHEN** `start` cannot read the open issues and no run state existed before
- **THEN** `start` exits 3, no run state file exists, and `stop` exits 1

##### Example: stop ends the run

- **GIVEN** a run with candidates #5 and #9, where #5 was recorded as stopped
- **WHEN** `stop --reason "default branch could not be fast-forwarded"` is called and then `next`
- **THEN** `next` prints `{"next": null, "stopped": "default branch could not be fast-forwarded"}` and #9 is not handed out

##### Example: the skill reports a failed start directly

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the part of the rest section about stopping the whole run is read
- **THEN** one line of it names the `start` that exits with code 3 before a run exists, and that line says to tell the user the reason and to call neither `stop` nor `report`

---
### Requirement: Start prints the list and resumes an unfinished run

`rest-queue.py start` SHALL print the number of open issues, the issue numbers of every class, and the run order, before any issue is handed out. It SHALL print issue numbers only, no issue titles. Among the issues of the run order it SHALL name those whose body shows the phase `verified`: an earlier run stopped there and this run takes them up again.

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

##### Example: a verified issue is taken up again

- **GIVEN** the open issues #5 (a plain candidate without a Diagnosis) and #8, whose body shows the phase `verified` and which has a trusted Diagnosis with the Complexity `Simple`
- **WHEN** `start` runs
- **THEN** the run order is 8, 5, and the output names #8 as taken up again from an earlier run and does not name #5 there

---
### Requirement: Report lists what happened and ends the run

`rest-queue.py report` SHALL print one report with: the issues recorded as closed; the issues recorded as stopped, each with its reason; the `needs-person` issues, each with the complete text of every open clarity row, one line per row and not shortened; the issues of every other class that was not run; and the stop reason of the run when there is one. It SHALL then delete the run state. When the open issues cannot be re-read, it SHALL still print the recorded attempts, say that the list could not be read, and delete the run state.

An issue that this run handed out SHALL appear once: under closed, under stopped or as handed out without a result. It SHALL NOT appear in the list of issues waiting for a person or in the line of a class that was not run. When such an issue is `needs-person` at the time of the report, the report SHALL print its open questions under the entry of that issue. The report prints no text of an issue of any other class.

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

- **GIVEN** a run in which #5 was recorded as stopped with the reason `verify gate: not_clean`, and by the time of the report the body of #5 has a non-empty `### Blocking` section; the open issue #8 also has one and was never handed out
- **WHEN** `report` runs
- **THEN** the line of the `blocked` class names #8 and does not name #5, and #5 is listed under stopped

##### Example: a stopped issue carries its open questions

- **GIVEN** a run in which #5 was recorded as stopped with the reason `verify gate: not_clean`, and by the time of the report the body of #5 shows two open clarity rows; the open issue #14 also shows two open clarity rows and was never handed out
- **WHEN** `report` runs
- **THEN** #5 is named once, under stopped, followed by its two row texts; the list of issues waiting for a person names #14 and does not name #5

##### Example: a long clarity row is printed in full

- **GIVEN** an open issue #14 whose body shows one open clarity row that is longer than 300 characters and whose question ends with the words `END-OF-QUESTION`
- **WHEN** `report` runs
- **THEN** the line of that row in the output contains `END-OF-QUESTION`

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

In rest mode `idd-all` SHALL call `rest-queue.py start`, then repeat: `next`; run the single-issue pipeline for the issue handed out, with the flags of this invocation; `record` with the stop reason the single-issue report printed, if any; in PR mode check out the default branch and fast-forward it as the batch mode of capability `parallel-orchestration` requires, and confirm that the working tree is clean. It SHALL resolve the path and the interaction mode once, for the first issue, and reuse them for every later issue. It SHALL leave the loop when `next` prints `done` or a stop reason, and SHALL then call `rest-queue.py report` and relay its output.

In rest mode `idd-all` SHALL treat an issue that already has a pull request or a branch as the single-issue pipeline treats it when that issue is named, with one difference: when the branch of the issue already exists in the working tree, left there by an earlier run, rest mode SHALL NOT ask what to do with it. It SHALL check that branch out, fast-forward it to the remote branch of the same name when there is one, and continue on it; when the fast-forward is not possible it SHALL stop that issue, without deleting the branch and without a forced push. When the existing-work check returns `resume`, it SHALL continue on the issue's own branch and reuse its pull request. When the check returns `blocked` and the interaction is unattended, it SHALL NOT start the issue, as the single-issue pipeline requires for a pull request that is not on the issue's own branch or that is already merged, and SHALL record the issue with the outcome the check printed.

#### Scenario: the loop ends with the report

- **WHEN** `next` prints `done`
- **THEN** `idd-all` calls `report` and starts no further issue

#### Scenario: an issue that already has its own pull request is continued

- **WHEN** the issue handed out has an open pull request on its own `idd/<N>-…` branch
- **THEN** `idd-all` checks out that branch, continues the pipeline on it and reuses the pull request

#### Scenario: the branch an earlier run left in the working tree is continued without a question

- **WHEN** the issue handed out has a local branch of its own in the working tree from an earlier run
- **THEN** `idd-all` checks that branch out, fast-forwards it to the remote branch of the same name when there is one, and asks no question

#### Scenario: a pull request that is not the issue's own is left alone

- **WHEN** the issue handed out is declared by an open pull request on another branch and the run is unattended
- **THEN** `idd-all` starts nothing for that issue, records it as stopped with the outcome of the existing-work check, and asks `next` for the following issue

##### Example: the skill names the loop commands in order

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the rest section is read
- **THEN** it contains the invocations `rest-queue.py" start`, `rest-queue.py" next`, `rest-queue.py" record`, `rest-queue.py" stop` and `rest-queue.py" report`, with `start` before `next`, `next` before `record`, and `report` last; Step 0.1 contains the invocation `rest-queue.py" args`; the rest section states that `verdict=resume` is continued on the issue's own branch and that `verdict=blocked` is handled as the single-issue pipeline handles it; it holds the commands that check out the issue's own local branch and fast-forward it with `merge -q --ff-only`, and says that no question is asked there; and Phase 6 sends a rest run back to the rest section

---
### Requirement: Unanswered skipped confirmations are available from one implementation

`scripts/lib/intent.py` SHALL provide `unanswered_confirmations(comments)`, which returns the skipped-confirmation literals that the comments posted after the latest Decision comment show, in the order of those comments. A literal counts where GitHub's rendering of the comment shows it on a line labelled `Reason`; a comment by a bot account does not count. The close stage SHALL use this function for its own check, so that the close stage and rest mode read an issue the same way.

#### Scenario: the close stage stops on the same record

- **WHEN** `unanswered_confirmations` returns at least one literal for the comments of an issue
- **THEN** the intent check of the close stage stops for that issue and names the first of them

##### Example: a record before and after a Decision

- **GIVEN** three comments in this order: a Diagnosis whose `Reason` line shows `unattended-auto-Step-4-choice-default`, a Decision comment, and a second Diagnosis whose `Reason` line shows `unattended-auto-Step-3.4-layerV-deferred`
- **WHEN** `unanswered_confirmations` is called with the three comments, and again with only the first two
- **THEN** the first call returns the one literal `unattended-auto-Step-3.4-layerV-deferred`, and the second call returns an empty list
