## ADDED Requirements

### Requirement: Closed value domain for the Complexity field

The `### Complexity` field emitted by `idd-diagnose` SHALL carry exactly one of four tier values: `Simple`, `Plan`, `Spectra`, or `SDD-warranted`. A tier value SHALL also be accepted when followed by the existing ` via <source>` provenance suffix, in which case the canonical tier SHALL be the text preceding the first ` via ` separator. Qualifiers that express deferral state, such as `when triggered` or `(parking lot)`, SHALL NOT be written into this field; deferral state belongs to the `parking-lot` label instead. Consumers SHALL treat any other value as outside the domain.

#### Scenario: Bare tier is accepted

- **WHEN** a Diagnosis comment contains a `### Complexity` section whose value is `Spectra`
- **THEN** the canonical tier resolves to `Spectra`
- **AND** the value is inside the closed domain

#### Scenario: Provenance suffix is accepted and stripped

- **WHEN** a Diagnosis comment contains a `### Complexity` section whose value is `Plan via Layer V`
- **THEN** the canonical tier resolves to `Plan`
- **AND** the value is inside the closed domain

#### Scenario: Deferral qualifier is outside the domain

- **WHEN** a Diagnosis comment contains a `### Complexity` section whose value is `Simple when triggered`
- **THEN** the value is reported as outside the closed domain
- **AND** the canonical tier is not resolved to `Simple`

### Requirement: Actionability gate evaluates three signals disjunctively

The system SHALL determine whether a diagnosed issue is actionable by evaluating exactly three signals: whether the `### Complexity` value is outside the closed domain or absent, whether the `parking-lot` label is present on the issue, and whether the `### Blocking` section of the issue body is non-empty. The issue SHALL be reported as actionable only when none of the three signals holds. The `- [~]` disposition marker inside a Diagnosis `### Strategy` checklist SHALL NOT be an input to this gate, because that marker is a close-time per-item disposition consumed by `idd-close` rather than a per-issue actionability signal.

#### Scenario: All three signals clear

- **WHEN** an issue has a `### Complexity` value inside the closed domain, carries no `parking-lot` label, and has an empty `### Blocking` section
- **THEN** the gate reports the issue as actionable

#### Scenario: Parking label alone withholds the issue

- **WHEN** an issue has a `### Complexity` value of `Spectra`, carries the `parking-lot` label, and has an empty `### Blocking` section
- **THEN** the gate reports the issue as not actionable
- **AND** the reported reason includes `parking-lot-label`

#### Scenario: Strategy skip marker does not withhold the issue

- **WHEN** an issue has all three gate signals clear and its Diagnosis `### Strategy` checklist contains a `- [~]` item
- **THEN** the gate reports the issue as actionable

### Requirement: Conservative verdict and mandatory surfacing on non-domain Complexity

When the `### Complexity` value is outside the closed domain, the system SHALL report the issue as not actionable and SHALL surface the original unmodified value to the operator. When the `### Complexity` section is absent entirely, the system SHALL report the issue as not actionable with a distinct reason. The system SHALL NOT silently truncate a non-domain value to a tier prefix, SHALL NOT downgrade it to any tier, and SHALL NOT abort the enclosing listing operation.

#### Scenario: Non-domain value surfaces verbatim

- **WHEN** the gate evaluates an issue whose `### Complexity` value is `Spectra when triggered (parking lot)`
- **THEN** the issue is reported as not actionable with reason `complexity-unparseable`
- **AND** the string `Spectra when triggered (parking lot)` appears in the operator-facing output

#### Scenario: Missing section is distinguished from non-domain value

- **WHEN** the gate evaluates a Diagnosis comment that contains no `### Complexity` section
- **THEN** the issue is reported as not actionable with reason `complexity-missing`

#### Scenario: One bad value does not suppress other issues

- **WHEN** a listing contains one issue with a non-domain `### Complexity` value and other issues with valid values
- **THEN** the listing reports every issue
- **AND** the listing operation does not abort

### Requirement: Single shared implementation of parsing and verdict

Complexity parsing and actionability verdict logic SHALL exist as one shared implementation. Every consumer that routes on `### Complexity` — `idd-list`, `idd-all`, `idd-implement`, and `idd-plan` — SHALL invoke that shared implementation rather than embedding its own parsing. The verdict reason vocabulary SHALL be the closed set `complexity-unparseable`, `complexity-missing`, `parking-lot-label`, `blocking-nonempty`. When the shared implementation is unavailable, a consumer SHALL fail loudly and name the missing path rather than degrade to a private parsing path.

#### Scenario: All routing consumers agree on the same input

- **WHEN** the same Diagnosis comment containing `Simple when triggered` is evaluated by each routing consumer
- **THEN** every consumer reports the value as outside the closed domain
- **AND** no consumer resolves a canonical tier from it

#### Scenario: Missing helper fails loudly

- **WHEN** a consumer invokes the shared implementation and the implementation file is absent
- **THEN** the consumer reports an error naming the missing path
- **AND** the consumer does not fall back to a private parsing path

### Requirement: Blocked-state output is preserved as a distinct display group

The gate SHALL produce a verdict together with its reason list, and the display layer SHALL group not-actionable issues by reason. Issues whose only reason is `blocking-nonempty` SHALL continue to appear under the existing blocked-state grouping, with its group heading, its all-blocked banner text, and its footer counts unchanged from the behavior established for blocked-state awareness. Issues whose reasons include `parking-lot-label`, `complexity-unparseable`, or `complexity-missing` SHALL appear under a separate parked grouping.

#### Scenario: Blocking-only issue keeps existing grouping

- **WHEN** an issue is not actionable with reason `blocking-nonempty` alone
- **THEN** the issue appears under the existing blocked-state group
- **AND** the group heading, banner text, and footer counts match the pre-change behavior

#### Scenario: Parked issue appears in the parked group

- **WHEN** an issue is not actionable with reason `parking-lot-label`
- **THEN** the issue appears under the parked group rather than the blocked-state group

### Requirement: Parked label is authored by a human and never derived by the producer

`idd-diagnose` SHALL NOT apply, remove, or derive the `parking-lot` label. The label SHALL remain a human-authored decision that is settable and removable after the diagnosis was written.

#### Scenario: Diagnosis run leaves labels untouched

- **WHEN** `idd-diagnose` completes and emits a Diagnosis comment
- **THEN** the issue's `parking-lot` label state is unchanged by that run

#### Scenario: Human parks an issue whose tier is inside the domain

- **WHEN** an issue carries a `### Complexity` value of `Spectra` and a human applies the `parking-lot` label afterwards
- **THEN** the gate reports the issue as not actionable with reason `parking-lot-label`

### Requirement: Legacy Diagnosis values are handled without rewriting history

Existing Diagnosis comments that carry deferral qualifiers in `### Complexity` SHALL NOT be rewritten to satisfy the closed value domain. The closed value domain SHALL constrain newly emitted diagnoses, and legacy values SHALL be carried by the non-domain path, which yields a not-actionable verdict with the original value surfaced. Migration SHALL be limited to applying the `parking-lot` label where it is absent.

#### Scenario: Legacy value yields the correct verdict without edit

- **WHEN** the gate evaluates an issue whose Diagnosis comment still reads `Simple when triggered` and which carries no `parking-lot` label
- **THEN** the issue is reported as not actionable
- **AND** the Diagnosis comment content is unchanged
