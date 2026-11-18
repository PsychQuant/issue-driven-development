## MODIFIED Requirements

### Requirement: Starting skills SHALL act on a blocked verdict

`idd-all`, `idd-all-chain` and `idd-implement` SHALL call the helper before they start work on an issue. On `blocked`, an attended run SHALL ask the user to choose between continuing on that PR, verifying that PR with `idd-verify #N --pr P`, and ignoring it, and SHALL record an ignore as one line in the issue body. An unattended run SHALL NOT start work on that issue, SHALL continue with the rest of the batch, and SHALL add one line for the issue to the Phase 6 section `## Action items (require human review)`, with the outcome `existing PR #P` or, for E3, `already merged in PR #P -> /idd-close #N`. On `resume` the run SHALL continue on that PR or branch. `idd-implement` SHALL skip its own call when its caller passes `--existing-work-checked`.

In rest mode (capability `idd-all-rest`, an `/idd-all` without an issue) `idd-all` still calls the helper before it starts work on an issue. What differs is what it does with `resume` and with `blocked`: it starts no work on the issue, asks no question and writes no Action item. It records the issue as existing work, with the outcome and the next step for a person, and the report of the rest run lists it.

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

#### Scenario: rest mode meets a blocked verdict

- **WHEN** `/idd-all` without an issue hands out an issue whose verdict is `blocked`
- **THEN** no question is asked, no branch is created, and the issue is recorded as stopped with a reason that begins with `existing work: `

##### Example: rest mode records existing work instead of acting on it

- **GIVEN** the text of `skills/idd-all/SKILL.md`
- **WHEN** the rest section and Step 0.5.1 are read
- **THEN** the rest section states that `verdict=resume` and `verdict=blocked` are recorded with the reason `existing work: ` without a question, and Step 0.5.1 points a rest run to the rest section
