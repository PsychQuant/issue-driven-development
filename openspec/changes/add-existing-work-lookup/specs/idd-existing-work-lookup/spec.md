## Purpose

Define how the IDD skills find out whether a pull request or a branch already addresses an issue before they start work on it: one helper that holds the matching rule, a closed list of evidence kinds, the verdicts it returns, and what each calling skill does with them. It exists so that `/idd-all #N` does not diagnose and implement an issue a second time.

## ADDED Requirements

### Requirement: One helper SHALL answer whether work already exists for an issue

A script `scripts/check-existing-work.sh <owner/repo> <issue-number>...` SHALL return, for every issue number given, a verdict and the list of evidence it found, as JSON on stdout. It SHALL fetch the open PRs, the merged PRs and the remote branches once for the whole call and match every issue on the client side. It SHALL be the only implementation of this matching: no calling skill SHALL carry its own matcher for "which PR addresses issue N". The exit status SHALL be 0 whenever a result was produced, including a result whose verdict is `unknown`, 1 when no result could be produced at all, and 2 for a usage error.

#### Scenario: Several issues in one call

- **WHEN** the helper is called with three issue numbers
- **THEN** the PR lists and the branch list SHALL be fetched once, not once per issue
- **AND** the JSON SHALL contain one entry per issue number

#### Scenario: A caller needs the matching rule

- **WHEN** a skill other than the helper needs to know which PR addresses an issue
- **THEN** it SHALL call the helper and SHALL NOT embed its own pattern

### Requirement: Evidence kinds SHALL be a closed list and SHALL NOT include content similarity

The helper SHALL report only these kinds of evidence, and no other. A PR or branch SHALL NOT be reported because its content resembles the issue; it SHALL be reported only when it references the issue in one of the ways below.

- **E1**: an open PR whose body has a line, outside a fenced code block, that starts with `Refs`, `Closes`, `Fixes` or `Resolves` (any letter case, optionally followed by a colon) and contains `#N`, where the PR was created no earlier than the issue.
- **E2**: an open PR whose body contains `#N`, which is not E1, and which was created no earlier than the issue.
- **E3**: a merged PR that satisfies E1 for an issue that is still OPEN.
- **E4**: a remote branch named `idd/N` or `idd/N-*` that is not a stale merged leftover.
- **E6**: a commit that is not on the default branch and whose message contains `Refs #N`, on a branch that is not a stale merged leftover.

`#N` SHALL match only when the character before `#` is not one of `A-Za-z0-9_/-` and the character after the digits is not a digit, so that `codex-pro#7`, `owner/repo#7` and `#70` do not match `#7`.

#### Scenario: A PR that only mentions the issue

- **GIVEN** an open PR whose body lists `#265` under "Recorded, not changed" and has no line starting with `Refs`, `Closes`, `Fixes` or `Resolves` that contains `#265`
- **WHEN** the helper is called for 265
- **THEN** the PR SHALL be reported as E2
- **AND** the verdict SHALL NOT be `blocked` because of it

#### Scenario: A PR that declares the issue

- **GIVEN** an open PR created after issue 258 whose body has the line `Refs #258`
- **WHEN** the helper is called for 258
- **THEN** the PR SHALL be reported as E1

#### Scenario: A declaration inside a fenced code block

- **GIVEN** an open PR whose only `Closes #42` appears inside a fenced code block
- **WHEN** the helper is called for 42
- **THEN** it SHALL NOT be reported as E1

#### Scenario: A cross-repository reference

- **GIVEN** an open PR whose body has the line `Refs codex-pro#7`
- **WHEN** the helper is called for 7
- **THEN** the PR SHALL NOT be reported

#### Scenario: A PR older than the issue

- **GIVEN** a PR whose body has `Refs #50` but whose creation time is earlier than issue 50's
- **WHEN** the helper is called for 50
- **THEN** the PR SHALL NOT be reported as E1 or as E2

#### Scenario: A branch with another prefix

- **GIVEN** a remote branch `codex/119-124-install-contract` whose commits carry no `Refs #124`
- **WHEN** the helper is called for 124
- **THEN** the branch SHALL NOT be reported

### Requirement: A merged leftover branch SHALL NOT count as work in progress

A remote branch whose tip equals the head commit of a merged PR SHALL be classified `stale-merged` and SHALL NOT be reported as E4 or E6. The helper SHALL decide this from the merged PR's head commit and not from the branch name.

#### Scenario: A branch that survived a squash merge

- **GIVEN** issue 255 is closed, its PR was squash-merged, and `origin/idd/255-js-fewer-roundtrips` still exists with a tip that is not an ancestor of the default branch
- **WHEN** the helper is called for 255
- **THEN** that branch SHALL be classified `stale-merged` and SHALL NOT be reported as E4

#### Scenario: A branch with commits no merged PR contains

- **GIVEN** a branch `idd/300-x` whose tip is not the head commit of any merged PR
- **WHEN** the helper is called for 300
- **THEN** it SHALL be reported as E4

### Requirement: An issue SHALL get exactly one verdict

The helper SHALL assign each issue one of `blocked`, `resume`, `unknown` or `clear`, and SHALL list all evidence regardless of the verdict.

- `blocked`: at least one E1 whose head branch is not `idd/N` or `idd/N-*`, or at least one E3 that is not excused by a reopen.
- `resume`: no blocking evidence, and an E1 whose head branch is `idd/N` or `idd/N-*`, or an E4.
- `unknown`: no blocking evidence, and a lookup failed or a list was truncated.
- `clear`: none of the above.

An E3 SHALL NOT be blocking when the issue has a `reopened` event later than that PR's merge time; it SHALL still be listed. When both an own `idd/N-*` PR and another PR that declares the issue exist, the verdict SHALL be `blocked`.

#### Scenario: Merged PR, issue still open

- **GIVEN** a merged PR with the line `Closes #12` and issue 12 is OPEN with no later reopen
- **WHEN** the helper is called for 12
- **THEN** the verdict SHALL be `blocked`
- **AND** the evidence SHALL name the PR as E3

#### Scenario: Merged PR, issue reopened afterwards

- **GIVEN** the same PR and a `reopened` event on issue 12 dated after the PR's merge time
- **WHEN** the helper is called for 12
- **THEN** the verdict SHALL NOT be `blocked` because of that PR
- **AND** the PR SHALL still be listed

#### Scenario: The run's own PR

- **GIVEN** an open PR whose head is `idd/258-isolated-bootstrap-test-timeout` and whose body has `Refs #258`
- **WHEN** the helper is called for 258
- **THEN** the verdict SHALL be `resume`

#### Scenario: Own PR and a foreign declaring PR

- **GIVEN** the own PR of the previous scenario and another open PR from `codex/258-x` that has `Refs #258`
- **WHEN** the helper is called for 258
- **THEN** the verdict SHALL be `blocked`

### Requirement: A failed lookup or a truncated list SHALL be reported as unknown, never as clear

When `gh` or `git ls-remote` fails, or when a PR list reaches its limit, the helper SHALL say so and SHALL NOT return `clear` for an issue it could not check completely. Calling skills SHALL print the `unknown` verdict and continue; they SHALL NOT stop on it.

#### Scenario: gh fails

- **GIVEN** the PR listing command exits non-zero
- **WHEN** the helper is called for issue 9
- **THEN** the verdict for 9 SHALL be `unknown`
- **AND** the JSON SHALL carry the reason

#### Scenario: The open PR list reaches its limit

- **GIVEN** the open PR listing returns exactly its limit
- **WHEN** the helper is called
- **THEN** the result SHALL carry `truncated: true`
- **AND** an issue with no evidence SHALL get `unknown`, not `clear`

### Requirement: Starting skills SHALL act on a blocked verdict

`idd-all`, `idd-all-chain` and `idd-implement` SHALL call the helper before they start work on an issue. On `blocked`, an attended run SHALL ask the user to choose between continuing on that PR, verifying that PR with `idd-verify #N --pr P`, and ignoring it, and SHALL record an ignore as one line in the issue body. An unattended run SHALL NOT start work on that issue, SHALL continue with the rest of the batch, and SHALL add one line for the issue to the Phase 6 section `## Action items (require human review)`, with the outcome `existing PR #P` or, for E3, `already merged in PR #P -> /idd-close #N`. On `resume` the run SHALL continue on that PR or branch. `idd-implement` SHALL skip its own call when its caller passes `--existing-work-checked`.

#### Scenario: Unattended batch with one blocked issue

- **GIVEN** `/idd-all #1 #2 #3` runs unattended and issue 2 has an E1 from a foreign branch
- **WHEN** the run reaches issue 2
- **THEN** no branch SHALL be created for issue 2
- **AND** issues 1 and 3 SHALL still run
- **AND** the Phase 6 Action items SHALL contain one line for issue 2 naming the PR

#### Scenario: Attended run

- **GIVEN** an attended `/idd-all #5` and a blocked verdict
- **WHEN** the helper returns
- **THEN** the run SHALL ask the user to choose between the three options before any branch is created

#### Scenario: idd-all calls idd-implement

- **WHEN** `idd-all` has already called the helper and invokes `idd-implement`
- **THEN** it SHALL pass `--existing-work-checked`
- **AND** `idd-implement` SHALL NOT call the helper again

### Requirement: idd-diagnose SHALL report existing work and SHALL NOT stop on it

`idd-diagnose` SHALL call the helper and write the evidence into the Diagnosis under a heading `### Existing work`, including the `unknown` case and the `(none)` case. It SHALL NOT refuse or stop because of any verdict.

#### Scenario: Diagnose on an issue with a declaring PR

- **GIVEN** an issue with an E1
- **WHEN** `/idd-diagnose #N` runs
- **THEN** the Diagnosis SHALL contain `### Existing work` naming the PR
- **AND** the diagnosis SHALL still be posted

### Requirement: idd-close SHALL use the same evidence for its open-PR gate

`idd-close` Step 1.5 SHALL obtain the open PRs that reference the issue from the helper and not from a pattern of its own. The gate SHALL stay as it is: it SHALL refuse to close while any open PR references the issue, whether the evidence is E1 or E2 and whether the PR is the run's own or another's. It SHALL refuse to close, and say why, when the open PR list could not be fetched or reached its limit, because closing is irreversible and an unknown SHALL NOT be read as none. Step 1.55 SHALL keep its own matching.

#### Scenario: Close with an open PR that only mentions the issue

- **GIVEN** an open PR that mentions `#N` without declaring it
- **WHEN** `/idd-close #N` runs
- **THEN** it SHALL refuse to close, as it does today

#### Scenario: Close with the run's own unmerged PR

- **GIVEN** an open PR from `idd/N-x` that declares `#N`
- **WHEN** `/idd-close #N` runs
- **THEN** it SHALL refuse to close

#### Scenario: The open PR list cannot be fetched

- **GIVEN** the helper reports that `gh pr list --state open` failed
- **WHEN** `/idd-close #N` runs
- **THEN** it SHALL refuse to close and print the reason
