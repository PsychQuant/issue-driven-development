## MODIFIED Requirements

### Requirement: Actionability gate evaluates three signals disjunctively

The system SHALL determine whether a diagnosed issue is actionable by evaluating exactly three signals: whether the `### Complexity` value is non-routable for any reason (unparseable prefix, absent section, or deferral vocabulary), whether the `parking-lot` label is present on the issue, and whether the `### Blocking` section of the issue body is non-empty. The issue SHALL be reported as actionable only when none of the three signals holds. When the caller supplies the issue type and that type is `meeting`, the Complexity signal SHALL NOT contribute a reason, because the meeting type deliberately produces no complexity tier (see the meeting-issue-type capability); the `parking-lot` label and `### Blocking` signals SHALL still be evaluated for a meeting issue. When the issue type is not supplied, or is any value other than `meeting`, the gate SHALL produce exactly the verdict and reasons it produced before the issue type input existed. The `- [~]` disposition marker inside a Diagnosis `### Strategy` checklist SHALL NOT be an input to this gate, because that marker is a close-time per-item disposition consumed by `idd-close` rather than a per-issue actionability signal.

#### Scenario: All three signals clear

- **WHEN** an issue has a routable `### Complexity` value, carries no `parking-lot` label, and has an empty `### Blocking` section
- **THEN** the gate reports the issue as actionable

#### Scenario: Parking label alone withholds the issue

- **WHEN** an issue has a `### Complexity` value of `Spectra`, carries the `parking-lot` label, and has an empty `### Blocking` section
- **THEN** the gate reports the issue as not actionable
- **AND** the reported reason includes `parking-lot-label`

#### Scenario: Strategy skip marker does not withhold the issue

- **WHEN** an issue has all three gate signals clear and its Diagnosis `### Strategy` checklist contains a `- [~]` item
- **THEN** the gate reports the issue as actionable

#### Scenario: Meeting issue without a tier is actionable

- **WHEN** the gate is called with issue type `meeting`, a Complexity parse result of unparseable or missing, no `parking-lot` label, and an empty `### Blocking` section
- **THEN** the gate reports the issue as actionable
- **AND** no `complexity-unparseable` or `complexity-missing` reason is reported

#### Scenario: Meeting issue still honours parking and blocking

- **WHEN** the gate is called with issue type `meeting` and the issue carries the `parking-lot` label
- **THEN** the gate reports the issue as not actionable with reason `parking-lot-label`
- **AND** when instead the `### Blocking` section is non-empty, the gate reports reason `blocking-nonempty`

#### Scenario: Omitted issue type preserves the existing verdict

- **WHEN** the gate is called without an issue type on any row of the existing frozen fixtures
- **THEN** every verdict and reason list is identical to the result recorded before this change

## ADDED Requirements

### Requirement: Issue type resolution is part of the shared implementation

The shared implementation SHALL provide the issue type resolution that consumers pass to the gate, so that no consumer parses issue labels or the body `## Type` heading on its own. Resolution SHALL follow the order used by `/idd-diagnose` Step 1: when exactly one IDD type name (`bug`, `feature`, `refactor`, `docs`, `meeting`) is present among the issue labels, that type SHALL be returned; when more than one distinct IDD type label is present, the result SHALL be `unknown`; when no IDD type label is present, the leading word of the first non-empty line under a line-anchored `## Type` heading outside fenced code SHALL be used if it is an IDD type name; otherwise the result SHALL be `unknown`. The value `unknown` SHALL be treated as not meeting. An unrecognised argument, a flag without a value, or an issue type value outside `bug`, `feature`, `refactor`, `docs`, `meeting`, `unknown` SHALL fail loudly with exit status 2 rather than defaulting.

#### Scenario: Label decides when exactly one type label is present

- **WHEN** an issue carries the label `meeting` and its body `## Type` heading reads `bug`
- **THEN** the resolved issue type is `meeting`

#### Scenario: Body heading is used only without a type label

- **WHEN** an issue carries no IDD type label and its body `## Type` heading is followed by the line `meeting（要老師裁決的編排決定）`
- **THEN** the resolved issue type is `meeting`

#### Scenario: Conflicting or absent signals default to not meeting

- **WHEN** an issue carries both the `bug` and `meeting` labels, or carries no type label and no `## Type` heading
- **THEN** the resolved issue type is `unknown`

##### Example: resolution table

| Labels | Body `## Type` first line | Resolved |
| ------ | ------------------------- | -------- |
| `meeting` | (none) | `meeting` |
| `bug`, `planning` | `meeting` | `bug` |
| `planning` | `meeting（審議）` | `meeting` |
| `bug`, `meeting` | `meeting` | `unknown` |
| (none) | (none) | `unknown` |
| (none) | `## Type` only inside a fenced code block | `unknown` |
