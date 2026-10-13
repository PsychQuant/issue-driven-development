## ADDED Requirements

### Requirement: Routing consumers honour the meeting type

For an issue with `type=meeting`, the routing consumers `idd-all`, `idd-plan`, `idd-implement`, and `idd-list` SHALL pass the resolved issue type, and whether a trusted Diagnosis comment exists, to the actionability gate (see the actionability-gate capability) and SHALL route on the type before any complexity tier. `/idd-all` SHALL dispatch an actionable meeting issue to the meeting-adapted `/idd-plan` when its interaction mode is attended, and SHALL stop at the diagnosed state and record an action item stating that it stopped there and that the next step is an attended `/idd-plan` or `/idd-close` when its interaction mode is unattended; a Meeting Plan is optional, because the meeting close gate falls back to the Diagnosis Phase C when no plan stage ran. In neither mode SHALL `/idd-all` invoke `/idd-implement` or `/idd-verify`, push a branch, or open a pull request for a meeting issue; in pull-request mode it SHALL return to the default branch, first committing the attachment manifest that diagnosis wrote onto the feature branch it created before the type was known and keeping that branch unpushed (deleting it only when it carries no commit and has no upstream), and SHALL name the kept branch and what to do with it in its output and final report; its final report SHALL NOT claim a verification, implementation commits or a pull request. `/idd-implement` SHALL refuse an actionable meeting issue with a message that names the meeting type and points to `/idd-plan` or `/idd-close`, and SHALL NOT instruct the user to correct the Diagnosis; a meeting issue the gate withholds is handled by the parked or blocked rules. `/idd-list` SHALL suggest `/idd-plan` as the next action for an actionable meeting issue in the `diagnosed` phase and `/idd-close` for one in the `planning` phase, which `/idd-update` sets when it reads a Meeting Plan.

#### Scenario: attended orchestration plans a meeting issue

- **WHEN** `/idd-all` runs in attended mode on an actionable `type=meeting` issue whose Diagnosis has no complexity tier
- **THEN** it dispatches to the meeting-adapted `/idd-plan`
- **AND** it does not invoke `/idd-implement` or `/idd-verify` and does not open a pull request

#### Scenario: unattended orchestration stops at diagnosed

- **WHEN** `/idd-all` runs in unattended mode on an actionable `type=meeting` issue
- **THEN** it does not run `/idd-plan`, `/idd-implement`, or `/idd-verify`
- **AND** its final report lists an action item saying it stopped at diagnosed and naming an attended `/idd-plan` or `/idd-close` as the next step
- **AND** its final report claims no verification, no implementation commits and no pull request

#### Scenario: pull-request mode leaves a clean default branch and keeps the manifest

- **WHEN** `/idd-all` runs in pull-request mode on a `type=meeting` issue and diagnosis wrote the attachment manifest
- **THEN** the manifest is committed on the feature branch, which is kept and not pushed
- **AND** the working tree is on the default branch and clean, so the next pull-request-mode run can start
- **AND** the output names the kept branch and how to push or delete it

#### Scenario: implement refuses a meeting issue without blaming the Diagnosis

- **WHEN** `/idd-implement` is invoked on an actionable `type=meeting` issue
- **THEN** it stops before creating a branch or committing
- **AND** its message names the meeting type and points to `/idd-plan` or `/idd-close` rather than asking for the Diagnosis to be corrected

#### Scenario: list suggests the meeting next action

- **WHEN** `/idd-list` shows an actionable `type=meeting` issue in the `diagnosed` phase
- **THEN** the suggested next action is `/idd-plan`
- **AND** when the issue is in the `planning` phase because a `## Meeting Plan` comment was recorded, the suggested next action is `/idd-close`

#### Scenario: an undiagnosed meeting issue still needs diagnosis

- **WHEN** `/idd-list` shows a `type=meeting` issue that has no trusted Diagnosis comment
- **THEN** it appears in the undiagnosed group with `/idd-diagnose` as the next action

### Requirement: Meeting Plan advances the phase to planning

`/idd-update` SHALL infer the phase `planning` when the latest phase-bearing comment is a Meeting Plan, identified by a heading that begins with `## Meeting Plan`, using the same tolerant heading match it applies to the other phase headings.

#### Scenario: meeting plan comment moves the phase

- **WHEN** an open `type=meeting` issue has a `## Diagnosis` comment followed by a `## Meeting Plan: Issue #42` comment
- **THEN** `/idd-update` sets the phase to `planning`
