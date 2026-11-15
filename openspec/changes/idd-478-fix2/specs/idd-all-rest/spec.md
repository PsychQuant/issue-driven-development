## MODIFIED Requirements

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
### Requirement: The open issues are read completely or not at all

`rest-queue.py` SHALL read all open issues with one paginated GraphQL query. For an issue that has more comments than the query returned, it SHALL read all comments of that issue before choosing its latest trusted Diagnosis. When any page fails, a response lacks an expected field, a permission read fails for a reason other than the account not being found, or an `actionability.sh` function reports misuse, the command SHALL exit with code 3, print one reason line on stderr, and SHALL NOT print a list on stdout.

An issue whose body has text for which GitHub returns no rendering this helper can read is not a failed read. The command SHALL give that issue the class `unreadable`, or `outsider` when the issue holds text from an account without write access, and SHALL classify and order every other issue as usual.

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
### Requirement: A stopped issue does not stop the run and a stopped run hands out nothing

An issue recorded as `stopped` SHALL NOT end the run: the following `next` hands out the next issue. `rest-queue.py stop --reason TEXT` SHALL mark the whole run as stopped; every later `next` of that run SHALL print the stop reason and hand out nothing.

`idd-all` SHALL call `stop` only in these three cases: between two issues in PR mode the default branch cannot be checked out or fast-forwarded, or the working tree is not clean afterwards; a `next` or a `record` exits with code 3 (GitHub or a helper could not be read, or the run state could not be written); `gh` authentication is lost. Exit codes 1 and 2 of `rest-queue.py` mean the call itself was wrong and are corrected, not treated as a stop. An interruption by the user leaves the run state in place without a stop record.

When the `start` that would begin a run exits with code 3, no run exists and there is nothing to stop or to report. `idd-all` SHALL relay the reason line that `start` printed and end, and SHALL NOT call `stop` or `report`. The same holds when that `start` would have resumed an earlier run: the state of the earlier run is left as it is, so that a later `start` resumes it.

When `report` itself exits with code 3, `idd-all` SHALL relay what `report` printed together with its reason line and end. It SHALL NOT call `stop` or `report` again.

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
- **THEN** one line of it names the `report` that exits with code 3, and that line says to pass on what was printed and to call neither `stop` nor `report` again

---
### Requirement: Start prints the list and resumes an unfinished run

`rest-queue.py start` SHALL print the number of open issues, the issue numbers of every class, and the run order, before any issue is handed out. It SHALL print issue numbers only, no issue titles. Every reason it prints from the run state SHALL be on one line, without control characters and no longer than the helper's limit for a reason, whatever the state file holds.

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

##### Example: a reason with a line break is printed on one line

- **GIVEN** a run state less than 24 hours old whose stop reason is two lines of text, `first line` and `SECOND-LINE`, and in which #5 is recorded as stopped with a reason of two lines
- **WHEN** `start` runs, and then `report`
- **THEN** no line of either output begins with `SECOND-LINE`, and both outputs hold the two parts of the stop reason on the same line

---
### Requirement: Report lists what happened and ends the run

`rest-queue.py report` SHALL print one report with: the issues recorded as closed; the issues recorded as stopped, each with its reason; the `needs-person` issues, each with the complete text of every open clarity row, one line per row and not shortened; the issues of every other class that was not run; and the stop reason of the run when there is one. It SHALL then delete the run state. When the open issues cannot be re-read, for whatever reason, it SHALL still print the recorded attempts, say that the list could not be read, and delete the run state.

An issue that this run handed out SHALL appear once: under closed, under stopped or as handed out without a result. It SHALL NOT appear in the list of issues waiting for a person or in the line of a class that was not run. When such an issue is `needs-person` at the time of the report, the report SHALL print its open questions under the entry of that issue, also when the issue was recorded as closed and reopened since. The report prints no text of an issue of any other class.

For the class `verified`, and when at least one issue was recorded with a reason that begins with `existing work:`, the report SHALL say that such an issue continues when it is named (`/idd-all #N`).

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

In rest mode `idd-all` SHALL call `rest-queue.py start`, then repeat: `next`; run the single-issue pipeline for the issue handed out, with the flags of this invocation; `record` with the stop reason the single-issue report printed, if any; in PR mode check out the default branch and fast-forward it as the batch mode of capability `parallel-orchestration` requires, and confirm that the working tree is clean. It SHALL resolve the path and the interaction mode once, for the first issue, and reuse them for every later issue. It SHALL leave the loop when `next` prints `done` or a stop reason, and SHALL then call `rest-queue.py report` and relay its output.

In rest mode `idd-all` SHALL NOT take over work that already exists: when the existing-work check of the single-issue pipeline returns `resume` or `blocked` for the issue handed out, it SHALL create no branch, leave the pull request untouched, and record the issue with a reason that names the pull request or branch.

The unattended marker SHALL NOT outlive the run. Before `idd-all` records an issue that it did not take over, it SHALL clear the marker that the mode step of that issue wrote, because that issue does not reach the clean-up of the single-issue pipeline. After `report`, it SHALL clear the marker once more.

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

##### Example: the skill clears the unattended marker

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the rest section is read
- **THEN** the step for an issue that is not taken over holds `clear_unattended "$CWD"` before the issue is recorded, and the part about the end of the run holds `clear_unattended "$CWD"` after the `report` invocation

## REMOVED Requirements

### Requirement: Unanswered skipped confirmations are available from one implementation

**Reason**: The requirement served the takeover of issues an earlier run left at `verified` or with their own branch or pull request. The maintainer decided on 2026-11-15 that this version does not take such issues over; the takeover, and with it this reading of skipped confirmations, moved to issue #566.

**Migration**: `scripts/lib/intent.py` no longer provides `unanswered_confirmations`. The close stage's intent check reads skipped confirmations itself, as it did before; nothing else called the function.
