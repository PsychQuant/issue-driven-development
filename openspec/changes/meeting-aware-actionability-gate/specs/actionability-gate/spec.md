## MODIFIED Requirements

### Requirement: Actionability gate evaluates three signals disjunctively

The system SHALL determine whether a diagnosed issue is actionable by evaluating exactly three signals: whether the `### Complexity` value is non-routable for any reason (unparseable prefix, absent section, or deferral vocabulary), whether the `parking-lot` label is present on the issue, and whether the `### Blocking` section of the issue body is non-empty. The issue SHALL be reported as actionable only when none of the three signals holds. When the caller supplies the issue type `meeting` and states that a trusted Diagnosis comment exists, the Complexity signal SHALL NOT contribute a reason, because the meeting type deliberately produces no complexity tier (see the meeting-issue-type capability); the `parking-lot` label and `### Blocking` signals SHALL still be evaluated for a meeting issue. When the caller states that no trusted Diagnosis comment exists, the Complexity signal SHALL be evaluated for a meeting issue exactly as for any other type, so that a meeting issue that was never diagnosed reports `complexity-missing`. A caller that supplies the issue type `meeting` without stating whether a Diagnosis exists SHALL receive exit status 2, because both defaults are unsafe. When the issue type is not supplied, or is any value other than `meeting`, the gate SHALL produce exactly the verdict and reasons it produced before the issue type input existed. The `- [~]` disposition marker inside a Diagnosis `### Strategy` checklist SHALL NOT be an input to this gate, because that marker is a close-time per-item disposition consumed by `idd-close` rather than a per-issue actionability signal.

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

- **WHEN** the gate is called with issue type `meeting`, a trusted Diagnosis present, a Complexity parse result of unparseable or missing, no `parking-lot` label, and an empty `### Blocking` section
- **THEN** the gate reports the issue as actionable
- **AND** no `complexity-unparseable` or `complexity-missing` reason is reported

#### Scenario: Undiagnosed meeting issue stays undiagnosed

- **WHEN** the gate is called with issue type `meeting`, no trusted Diagnosis comment, no `parking-lot` label, and an empty `### Blocking` section
- **THEN** the gate reports the issue as not actionable with reason `complexity-missing`
- **AND** the display group is undiagnosed, which retains the diagnose lifecycle command

#### Scenario: Meeting type without the diagnosis signal is misuse

- **WHEN** the gate is called with issue type `meeting` and no statement of whether a Diagnosis exists
- **THEN** the gate exits with status 2 and reports no verdict

#### Scenario: Meeting issue still honours parking and blocking

- **WHEN** the gate is called with issue type `meeting` and the issue carries the `parking-lot` label
- **THEN** the gate reports the issue as not actionable with reason `parking-lot-label`
- **AND** when instead the `### Blocking` section is non-empty, the gate reports reason `blocking-nonempty`

#### Scenario: Omitted issue type preserves the existing verdict

- **WHEN** the gate is called without an issue type on any row of the existing frozen fixtures
- **THEN** every verdict and reason list is identical to the result recorded before this change

### Requirement: Deferral vocabulary withholds routing under its own reason

The system SHALL scan the **entire** `### Complexity` value — not only the text following the tier — for deferral vocabulary, and SHALL withhold the issue from routing when any is found, even though the tier prefix is valid. This condition SHALL carry the distinct reason `complexity-deferral-marker`, separate from `complexity-unparseable` and `complexity-missing`, because the three call for different human responses: an unparseable value is a data defect to correct, a missing section is a diagnosis that never ran, and a deferral marker is a legitimate state requiring no repair. The deferral vocabulary SHALL NOT be treated as a closed enumeration — it is a high-precision heuristic, and the `parking-lot` label remains the primary parked signal. For a diagnosed `meeting` issue the Complexity signal is not evaluated (see "Actionability gate evaluates three signals disjunctively"), so deferral vocabulary in its `### Complexity` value SHALL NOT withhold it; parking a meeting issue is the `parking-lot` label's job.

#### Scenario: Deferral vocabulary withholds a valid tier

- **WHEN** the value is `Simple when triggered`
- **THEN** the issue is reported as not actionable with reason `complexity-deferral-marker`
- **AND** the string `Simple when triggered` appears in the operator-facing output

#### Scenario: Deferral vocabulary inside a parenthetical is still detected

- **WHEN** the value is `**Spectra**(Layer 2 + Layer 3 if/when triggered)`
- **THEN** the issue is reported as not actionable with reason `complexity-deferral-marker`

#### Scenario: Deferral reason is distinct from unparseable

- **WHEN** one issue has the value `Plan when triggered` and another has the value `移入 discussion list`
- **THEN** the first reports reason `complexity-deferral-marker`
- **AND** the second reports reason `complexity-unparseable`

#### Scenario: Deferral vocabulary does not park a diagnosed meeting issue

- **WHEN** a diagnosed `meeting` issue has the `### Complexity` value `Plan when triggered`, no `parking-lot` label, and an empty `### Blocking` section
- **THEN** the issue is reported as actionable

### Requirement: Conservative verdict and mandatory surfacing on non-routable Complexity

When a `### Complexity` value cannot be routed for any reason, the system SHALL report the issue as not actionable and SHALL surface the original unmodified value to the operator. A missing `### Complexity` section SHALL report reason `complexity-missing`. The system SHALL NOT silently truncate a non-routable value to a tier prefix, SHALL NOT downgrade it to any tier, and SHALL NOT abort the enclosing listing operation. The single exception is a `meeting` issue with a trusted Diagnosis comment, whose Complexity signal is not evaluated (see "Actionability gate evaluates three signals disjunctively"); a `meeting` issue with no trusted Diagnosis comment is not excepted and SHALL report `complexity-missing`.

#### Scenario: Missing section is distinguished from a non-routable value

- **WHEN** a Diagnosis comment of a non-meeting issue contains no `### Complexity` section
- **THEN** the issue is reported as not actionable with reason `complexity-missing`

#### Scenario: One bad value does not suppress other issues

- **WHEN** a listing contains one issue with a non-routable `### Complexity` value and other issues with routable values
- **THEN** the listing reports every issue
- **AND** the listing operation does not abort

#### Scenario: No downgrade to a routable tier

- **WHEN** a value is reported as not actionable for any complexity reason
- **THEN** no tier is emitted for routing
- **AND** the issue is not dispatched to any lifecycle command

#### Scenario: A diagnosed meeting issue is the only exception

- **WHEN** a `meeting` issue has a trusted Diagnosis comment whose `### Complexity` value is a sentence
- **THEN** no complexity reason is reported for it
- **AND** a `meeting` issue with no trusted Diagnosis comment is reported with reason `complexity-missing`

## ADDED Requirements

### Requirement: Issue type resolution is part of the shared implementation

The shared implementation SHALL provide the issue type resolution that consumers pass to the gate, so that no consumer parses issue labels or the body `## Type` heading on its own. Resolution SHALL follow the order used by `/idd-diagnose` Step 1: when exactly one IDD type name (`bug`, `feature`, `refactor`, `docs`, `meeting`) is present among the issue labels, compared after ASCII case folding and trimming of ASCII space and tab only, that type SHALL be returned; when more than one distinct IDD type label is present, the result SHALL be `unknown`; when no IDD type label is present, the leading word of the first non-empty line under a line-anchored `## Type` heading outside fenced code and outside HTML comment blocks SHALL be used if it is an IDD type name, where a fence closes only on a line of the opener's character at no less than the opener's length with nothing after it; otherwise the result SHALL be `unknown`. The value `unknown` SHALL be treated as not meeting. An unrecognised argument, a flag without a value, or an issue type value outside `bug`, `feature`, `refactor`, `docs`, `meeting`, `unknown` SHALL fail loudly with exit status 2 rather than defaulting.

#### Scenario: Label decides when exactly one type label is present

- **WHEN** an issue carries the label `meeting` and its body `## Type` heading reads `bug`
- **THEN** the resolved issue type is `meeting`

#### Scenario: Body heading is used only without a type label

- **WHEN** an issue carries no IDD type label and its body `## Type` heading is followed by the line `meeting（需要裁決的編排決定）`
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
| (none) | `## Type` inside a four-backtick fence that contains a three-backtick line | `unknown` |
| (none) | `## Type` / `meeting` inside an HTML comment, then a visible `## Type` / `bug` | `bug` |
| `Meeting` | (none) | `meeting` |
