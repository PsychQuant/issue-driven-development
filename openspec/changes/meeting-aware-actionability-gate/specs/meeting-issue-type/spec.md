## ADDED Requirements

### Requirement: Routing consumers honour the meeting type

For an issue with `type=meeting`, the routing consumers `idd-all`, `idd-plan`, `idd-implement`, and `idd-list` SHALL pass the resolved issue type to the actionability gate (see the actionability-gate capability) and SHALL route on the type before any complexity tier. `/idd-all` SHALL dispatch an actionable meeting issue to the meeting-adapted `/idd-plan` when its interaction mode is attended, and SHALL stop at the diagnosed state and record an action item stating that the meeting issue needs an attended `/idd-plan` when its interaction mode is unattended; in neither mode SHALL `/idd-all` invoke `/idd-implement` or `/idd-verify`, push a branch, or open a pull request for a meeting issue. `/idd-implement` SHALL refuse a meeting issue with a message that names the meeting type and points to `/idd-plan` or `/idd-close`, and SHALL NOT instruct the user to correct the Diagnosis. `/idd-list` SHALL suggest `/idd-plan` as the next action for an actionable meeting issue in the `diagnosed` phase and `/idd-close` for one that already has a Meeting Plan.

#### Scenario: attended orchestration plans a meeting issue

- **WHEN** `/idd-all` runs in attended mode on an actionable `type=meeting` issue whose Diagnosis has no complexity tier
- **THEN** it dispatches to the meeting-adapted `/idd-plan`
- **AND** it does not invoke `/idd-implement` or `/idd-verify` and does not open a pull request

#### Scenario: unattended orchestration stops at diagnosed

- **WHEN** `/idd-all` runs in unattended mode on an actionable `type=meeting` issue
- **THEN** it does not run `/idd-plan`, `/idd-implement`, or `/idd-verify`
- **AND** its final report lists an action item saying the meeting issue needs an attended `/idd-plan`

#### Scenario: implement refuses a meeting issue without blaming the Diagnosis

- **WHEN** `/idd-implement` is invoked on a `type=meeting` issue
- **THEN** it stops before creating a branch or committing
- **AND** its message names the meeting type and points to `/idd-plan` or `/idd-close` rather than asking for the Diagnosis to be corrected

#### Scenario: list suggests the meeting next action

- **WHEN** `/idd-list` shows an actionable `type=meeting` issue in the `diagnosed` phase
- **THEN** the suggested next action is `/idd-plan`
- **AND** when the issue already has a `## Meeting Plan` comment the suggested next action is `/idd-close`

### Requirement: Meeting Plan advances the phase to planning

`/idd-update` SHALL infer the phase `planning` when the latest phase-bearing comment is a Meeting Plan, identified by a heading that begins with `## Meeting Plan`, using the same tolerant heading match it applies to the other phase headings.

#### Scenario: meeting plan comment moves the phase

- **WHEN** an open `type=meeting` issue has a `## Diagnosis` comment followed by a `## Meeting Plan: Issue #42` comment
- **THEN** `/idd-update` sets the phase to `planning`
