## ADDED Requirements

### Requirement: Complexity tier extraction tolerates trailing rationale

The system SHALL extract the routing tier from the `### Complexity` field by (1) stripping leading and trailing markdown decoration, (2) requiring the stripped value to **begin with** one of `Simple`, `Plan`, `Spectra`, or `SDD-warranted` (longest match first, so `SDD-warranted` is not read as a non-tier), and (3) taking that leading tier as the extracted value. Any further text on the value line — same-line rationale, parenthetical explanation, or a ` via <source>` provenance suffix — SHALL NOT prevent tier extraction. Trailing rationale is the producer's normal writing style: in a corpus of 159 real diagnoses in this repository, 71.7% of values are not a bare tier (23.3% decorated, 41.5% carry same-line rationale, 0.6% a provenance suffix) and only 5.7% express deferral; a closed domain would have wrongly refused 41.5% of them (66 of 159).

#### Scenario: Bare tier is extracted

- **WHEN** the value is `Spectra`
- **THEN** the extracted tier is `Spectra`

#### Scenario: Same-line rationale does not block extraction

- **WHEN** the value is `Spectra（opt-out → 直接 propose）`
- **THEN** the extracted tier is `Spectra`
- **AND** the value is treated as routable

#### Scenario: Markdown decoration is stripped

- **WHEN** the value is `**Plan**`
- **THEN** the extracted tier is `Plan`

#### Scenario: Provenance suffix is stripped

- **WHEN** the value is `Plan via Layer V`
- **THEN** the extracted tier is `Plan`

#### Scenario: Non-tier prefix is not routable

- **WHEN** the value is `移入 discussion list`
- **THEN** no tier is extracted
- **AND** the reason reported is `complexity-unparseable`

### Requirement: Actionability gate evaluates three signals disjunctively

The system SHALL determine whether a diagnosed issue is actionable by evaluating exactly three signals: whether the `### Complexity` value is non-routable for any reason (unparseable prefix, absent section, or deferral vocabulary), whether the `parking-lot` label is present on the issue, and whether the `### Blocking` section of the issue body is non-empty. The issue SHALL be reported as actionable only when none of the three signals holds. The `- [~]` disposition marker inside a Diagnosis `### Strategy` checklist SHALL NOT be an input to this gate, because that marker is a close-time per-item disposition consumed by `idd-close` rather than a per-issue actionability signal.

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

### Requirement: Deferral vocabulary withholds routing under its own reason

The system SHALL scan the **entire** `### Complexity` value — not only the text following the tier — for deferral vocabulary, and SHALL withhold the issue from routing when any is found, even though the tier prefix is valid. This condition SHALL carry the distinct reason `complexity-deferral-marker`, separate from `complexity-unparseable` and `complexity-missing`, because the three call for different human responses: an unparseable value is a data defect to correct, a missing section is a diagnosis that never ran, and a deferral marker is a legitimate state requiring no repair. The deferral vocabulary SHALL NOT be treated as a closed enumeration — it is a high-precision heuristic, and the `parking-lot` label remains the primary parked signal.

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

### Requirement: Conservative verdict and mandatory surfacing on non-routable Complexity

When a `### Complexity` value cannot be routed for any reason, the system SHALL report the issue as not actionable and SHALL surface the original unmodified value to the operator. A missing `### Complexity` section SHALL report reason `complexity-missing`. The system SHALL NOT silently truncate a non-routable value to a tier prefix, SHALL NOT downgrade it to any tier, and SHALL NOT abort the enclosing listing operation.

#### Scenario: Missing section is distinguished from a non-routable value

- **WHEN** a Diagnosis comment contains no `### Complexity` section
- **THEN** the issue is reported as not actionable with reason `complexity-missing`

#### Scenario: One bad value does not suppress other issues

- **WHEN** a listing contains one issue with a non-routable `### Complexity` value and other issues with routable values
- **THEN** the listing reports every issue
- **AND** the listing operation does not abort

#### Scenario: No downgrade to a routable tier

- **WHEN** a value is reported as not actionable for any complexity reason
- **THEN** no tier is emitted for routing
- **AND** the issue is not dispatched to any lifecycle command

### Requirement: Single shared implementation of parsing and verdict

Complexity parsing and actionability verdict logic SHALL exist as one shared implementation. Every consumer that routes on `### Complexity` — `idd-list`, `idd-all`, `idd-implement`, and `idd-plan` — SHALL invoke that shared implementation rather than embedding its own parsing. The verdict reason vocabulary SHALL be the closed set `complexity-unparseable`, `complexity-missing`, `complexity-deferral-marker`, `parking-lot-label`, `blocking-nonempty`. When the shared implementation is unavailable, a consumer SHALL fail loudly and name the missing path rather than degrade to a private parsing path.

#### Scenario: All routing consumers agree on the same input

- **WHEN** the same Diagnosis comment containing `Simple when triggered` is evaluated by each routing consumer
- **THEN** every consumer reports the value as non-routable under reason `complexity-deferral-marker`
- **AND** no consumer dispatches the issue to a lifecycle command, even though the tier prefix `Simple` is itself well-formed

#### Scenario: Missing helper fails loudly

- **WHEN** a consumer invokes the shared implementation and the implementation file is absent
- **THEN** the consumer reports an error naming the missing path
- **AND** the consumer does not fall back to a private parsing path

### Requirement: Blocked-state output is preserved as a distinct display group

The gate SHALL produce a verdict together with its reason list, and the display layer SHALL group not-actionable issues by reason into exactly three groups. Issues whose reasons include any of `parking-lot-label`, `complexity-deferral-marker`, or `complexity-unparseable` SHALL appear under a parked grouping. Otherwise, issues whose reasons include `blocking-nonempty` SHALL appear under the existing blocked-state grouping, with its group heading, its all-blocked banner text, and its footer counts unchanged from the behavior established for blocked-state awareness. Otherwise — reason `complexity-missing` alone — the issue SHALL appear under an undiagnosed grouping that retains the diagnose lifecycle command, because an issue that has never been diagnosed is in its birth state, not a parked state; on the 2026-09-07 open backlog that state held 11 of 14 issues, and filing it as parked hid the only correct next action and made the footer disagree with the parked-review flag by an order of magnitude.

#### Scenario: Blocking-only issue keeps existing grouping

- **WHEN** an issue is not actionable with reason `blocking-nonempty` alone
- **THEN** the issue appears under the existing blocked-state group
- **AND** the group heading, banner text, and footer counts match the pre-change behavior

#### Scenario: Parked issue appears in the parked group

- **WHEN** an issue is not actionable with reason `parking-lot-label`
- **THEN** the issue appears under the parked group rather than the blocked-state group

#### Scenario: Undiagnosed issue keeps its diagnose command

- **WHEN** an issue is not actionable with reason `complexity-missing` alone
- **THEN** the issue appears under the undiagnosed group, not the parked group
- **AND** its row still offers the diagnose lifecycle command

#### Scenario: Missing diagnosis with a real blocker is blocked

- **WHEN** an issue is not actionable with reasons `complexity-missing` and `blocking-nonempty`
- **THEN** the issue appears under the blocked-state group

### Requirement: Parked label is authored by a human and never derived by the producer

`idd-diagnose` SHALL NOT apply, remove, or derive the `parking-lot` label on the issue it is diagnosing. The label SHALL remain a human-authored decision that is settable and removable after the diagnosis was written. This prohibition is scoped to the issue under diagnosis: the IC_R011 checkpoint that runs inside `idd-diagnose` MAY attach `parking-lot` to a newly filed sister issue when the user classifies that candidate as infeasible or blocked-on-external, because that is a human classification landing on a different issue.

#### Scenario: Diagnosis run leaves labels untouched

- **WHEN** `idd-diagnose` completes and emits a Diagnosis comment
- **THEN** the issue's `parking-lot` label state is unchanged by that run

#### Scenario: Human parks an issue whose tier is inside the domain

- **WHEN** an issue carries a `### Complexity` value of `Spectra` and a human applies the `parking-lot` label afterwards
- **THEN** the gate reports the issue as not actionable with reason `parking-lot-label`

### Requirement: Existing diagnoses require no migration

Existing Diagnosis comments SHALL NOT be rewritten, and no label SHALL be backfilled, in order for the gate to produce correct verdicts on them. The extraction and deferral rules SHALL be validated against the repository's full diagnosis corpus, and that validation SHALL be a regression test rather than a one-off check.

#### Scenario: Full corpus produces correct verdicts unmodified

- **WHEN** the gate evaluates every existing Diagnosis comment in the repository
- **THEN** every value carrying a valid tier without deferral vocabulary yields that tier
- **AND** every value carrying deferral vocabulary is withheld with reason `complexity-deferral-marker`
- **AND** no Diagnosis comment content is modified

#### Scenario: Fixture reflects real shapes rather than a hypothesis-confirming sample

- **WHEN** the regression fixture is reviewed
- **THEN** it contains at least three real-corpus cases each of bare tier, tier with same-line rationale, decorated tier, and deferral vocabulary

### Requirement: The blocking signal is read per bullet against a frozen corpus

The `### Blocking` section SHALL be read as a list: the section is non-empty when any bullet is not a none-placeholder, and a placeholder SHALL be recognised by its leading token (`none`, `n/a`, `無`, optionally bulleted, decorated, or parenthesised, followed by end of line, a closing paren, or a separator) so that an annotated placeholder such as `- (none — 可動)` is empty while a bullet whose first word merely happens to be `none` is not. Lines that do not begin a `-` or `*` bullet SHALL be treated as continuations of the bullet above, and the accepted consequences SHALL be stated as a rule in both failure directions rather than as examples. A trailing carriage return SHALL be stripped before either section reader judges a line, the rule SHALL NOT depend on the process locale, an unbalanced code fence SHALL NOT hide a section below it, and control characters SHALL be removed from every value the helper surfaces. The rule SHALL be validated against every `### Blocking` section in the repository's issue bodies as a frozen regression fixture, because the first implementation was written against an assumed producer shape and withheld 31 of the 47 empty sections in that corpus, including the tracking issue of this change.

#### Scenario: Annotated placeholder is empty

- **WHEN** the section reads `- (none — 可動)`
- **THEN** the blocking signal is clear

#### Scenario: Placeholder followed by a real bullet is non-empty

- **WHEN** the section reads `- (none)` on one bullet and `- 等 upstream #310 merge` on the next
- **THEN** the blocking signal reports the second bullet

#### Scenario: A blocker that starts with the token is kept

- **WHEN** the section reads `- none of the reviewers replied yet`
- **THEN** the blocking signal reports that line

#### Scenario: Locale does not change the verdict

- **WHEN** the reader runs under `LC_ALL=C`
- **THEN** `- none ぁ x` is still reported as a blocker
- **AND** `（無）` is still empty

#### Scenario: An unclosed fence does not hide the section

- **WHEN** a body contains an unclosed code fence above `### Blocking`
- **THEN** the section is still read

#### Scenario: CRLF does not change either reader's verdict

- **WHEN** an issue body or Diagnosis comment uses CRLF line endings
- **THEN** `### Complexity` and `### Blocking` are judged exactly as their LF equivalents
