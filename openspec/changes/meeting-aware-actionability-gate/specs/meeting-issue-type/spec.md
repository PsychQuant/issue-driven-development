## ADDED Requirements

### Requirement: Routing consumers honour the meeting type

For a diagnosed meeting issue — one whose latest trusted Diagnosis comment records `meeting` under `### Type` (see the actionability-gate capability) — the routing consumers `idd-all`, `idd-plan`, `idd-implement`, and `idd-list` SHALL pass that Diagnosis type to the actionability gate and SHALL route on it before any complexity tier. They SHALL NOT take the type from issue labels or the issue body, which the issue author can edit; every later step of `/idd-all` that needs the type (the branch unwind, verify, push, the final report) SHALL read it from the trusted Diagnosis again rather than from the issue body. `/idd-all` SHALL dispatch an actionable meeting issue to the meeting-adapted `/idd-plan` when its interaction mode is attended, and SHALL stop at the diagnosed state and record an action item stating that it stopped there and that the next step is an attended `/idd-plan` or `/idd-close` when its interaction mode is unattended; a Meeting Plan is optional, because the meeting close gate falls back to the Diagnosis Phase C when no plan stage ran. In neither mode SHALL `/idd-all` invoke `/idd-implement` or `/idd-verify`, push a branch, or open a pull request for a meeting issue; in pull-request mode it SHALL return to the default branch, first committing the attachment manifest that diagnosis wrote onto the feature branch it created before the type was known and keeping that branch unpushed (deleting it only when it carries no commit and has no upstream), and SHALL name the kept branch and what to do with it in its output and final report; its final report SHALL NOT claim a verification, implementation commits or a pull request. When a later step of a run that `/idd-all` routed as code work reads a meeting Diagnosis — which can only have appeared after that routing — the run SHALL stop without verifying or pushing rather than switch to the meeting route (a step that cannot read the type continues on the route the run took, except that no push happens without a readable type), and the final report SHALL follow the route the run actually took and warn that the type changed. `/idd-implement` SHALL refuse an actionable meeting issue with a message that names the meeting type and points to `/idd-plan` or `/idd-close`, and SHALL NOT instruct the user to correct the Diagnosis; a meeting issue the gate withholds is handled by the parked or blocked rules. `/idd-list` SHALL suggest `/idd-plan` as the next action for an actionable meeting issue in the `diagnosed` phase and `/idd-close` for one in the `planning` phase, which `/idd-update` sets when it reads a Meeting Plan.

#### Scenario: attended orchestration plans a meeting issue

- **WHEN** `/idd-all` runs in attended mode on an actionable diagnosed meeting issue whose Diagnosis has no complexity tier
- **THEN** it dispatches to the meeting-adapted `/idd-plan`
- **AND** it does not invoke `/idd-implement` or `/idd-verify` and does not open a pull request

#### Scenario: unattended orchestration stops at diagnosed

- **WHEN** `/idd-all` runs in unattended mode on an actionable diagnosed meeting issue
- **THEN** it does not run `/idd-plan`, `/idd-implement`, or `/idd-verify`
- **AND** its final report lists an action item saying it stopped at diagnosed and naming an attended `/idd-plan` or `/idd-close` as the next step
- **AND** its final report claims no verification, no implementation commits and no pull request

#### Scenario: pull-request mode leaves a clean default branch and keeps the manifest

- **WHEN** `/idd-all` runs in pull-request mode on a diagnosed meeting issue and diagnosis wrote the attachment manifest
- **THEN** the manifest is committed on the feature branch, which is kept and not pushed
- **AND** the working tree is on the default branch and clean, so the next pull-request-mode run can start
- **AND** the output names the kept branch and how to push or delete it

#### Scenario: an edited issue body does not change the route

- **WHEN** an issue was diagnosed as `bug`, implemented by `/idd-all`, and the issue author then changes the body to declare `meeting`
- **THEN** `/idd-all` still runs verify and the push for it, because later steps read the type from the trusted Diagnosis, not from the body

#### Scenario: a meeting Diagnosis that appears mid-run stops a code run

- **WHEN** `/idd-all` routed an issue as code work and, before verify, the latest trusted Diagnosis comes to record `meeting` and the run can read it
- **THEN** the run stops before `/idd-verify` and before any push
- **AND** its message says that commits this run made stay where they are

#### Scenario: implement refuses a meeting issue without blaming the Diagnosis

- **WHEN** `/idd-implement` is invoked on an actionable diagnosed meeting issue
- **THEN** it stops before creating a branch or committing
- **AND** its message names the meeting type and points to `/idd-plan` or `/idd-close` rather than asking for the Diagnosis to be corrected

#### Scenario: list suggests the meeting next action

- **WHEN** `/idd-list` shows an actionable diagnosed meeting issue in the `diagnosed` phase
- **THEN** the suggested next action is `/idd-plan`
- **AND** when the issue is in the `planning` phase because a `## Meeting Plan` comment was recorded, the suggested next action is `/idd-close`

#### Scenario: an undiagnosed meeting issue still needs diagnosis

- **WHEN** `/idd-list` shows an issue whose body declares `meeting` but that has no trusted Diagnosis comment, no `parking-lot` label and an empty `### Blocking` section
- **THEN** it appears in the undiagnosed group with `/idd-diagnose` as the next action

### Requirement: Diagnose records meeting only from a trusted source

`/idd-diagnose` SHALL record `meeting` under the Diagnosis `### Type` only in two cases: the issue's only IDD type label is `meeting`; or the issue carries no IDD type label, its body's `## Type` declares `meeting`, and the issue's author association is `OWNER`, `MEMBER` or `COLLABORATOR` (the set whose Diagnosis comments the gate trusts). It SHALL NOT infer `meeting` from the issue's content. When the body declares `meeting` but the author association is outside that set or cannot be read, `/idd-diagnose` SHALL resolve the type as if the body declared no type, and the Diagnosis SHALL say that a maintainer can add the `meeting` label. Two or more IDD type labels SHALL count as no type label. The `### Type` line SHALL begin with the adopted value; a declaration that was not adopted SHALL NOT appear at its start, because the gate reads only the leading word. This rule is carried out by the model that runs `/idd-diagnose`; it governs Diagnoses written under it. Because `/idd-all` runs `/idd-diagnose` on every run, this rule is what keeps an issue author outside that set from switching off the Complexity signal by editing the body.

#### Scenario: an outside author's body declaration is not adopted

- **WHEN** an issue with no type label, opened by an author whose association is `NONE` or `CONTRIBUTOR`, declares `meeting` in its body's `## Type`
- **THEN** `/idd-diagnose` does not record `meeting` under `### Type`
- **AND** a later `/idd-all` run on the issue, which diagnoses it again, still evaluates its Complexity signal

#### Scenario: a maintainer's body declaration is adopted

- **WHEN** an issue with no type label, opened by an author whose association is `OWNER`, declares `meeting` in its body's `## Type`
- **THEN** `/idd-diagnose` records `meeting` under `### Type`

#### Scenario: the meeting label is adopted whoever opened the issue

- **WHEN** an issue opened by an author whose association is `NONE` carries the `meeting` type label
- **THEN** `/idd-diagnose` records `meeting` under `### Type`

#### Scenario: two type labels do not make a meeting

- **WHEN** an issue opened by an author whose association is `NONE` carries both the `bug` and the `meeting` type labels, and its body does not declare a type
- **THEN** `/idd-diagnose` does not record `meeting` under `### Type`
- **AND** the Diagnosis names the conflicting labels

#### Scenario: a rejected declaration does not lead the Type line

- **WHEN** `/idd-diagnose` does not adopt a body's `meeting` declaration
- **THEN** the line under `### Type` does not begin with `meeting`

#### Scenario: an unreadable author association is not trusted

- **WHEN** the body of an issue with no type label declares `meeting` and the author association lookup fails
- **THEN** `/idd-diagnose` does not record `meeting` under `### Type`

### Requirement: Meeting Plan advances the phase to planning

`/idd-update` SHALL infer the phase `planning` when the latest phase-bearing comment is a Meeting Plan, identified by a heading that begins with `## Meeting Plan`, using the same tolerant heading match it applies to the other phase headings.

#### Scenario: meeting plan comment moves the phase

- **WHEN** an open `type=meeting` issue has a `## Diagnosis` comment followed by a `## Meeting Plan: Issue #42` comment
- **THEN** `/idd-update` sets the phase to `planning`
