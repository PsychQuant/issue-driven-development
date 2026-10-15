## MODIFIED Requirements

### Requirement: Actionability gate evaluates three signals disjunctively

The system SHALL determine whether a diagnosed issue is actionable by evaluating exactly three signals: whether the `### Complexity` value is non-routable for any reason (unparseable prefix, absent section, or deferral vocabulary), whether the `parking-lot` label is present on the issue, and whether the `### Blocking` section of the issue body is non-empty. The issue SHALL be reported as actionable only when none of the three signals holds. A **diagnosed `meeting` issue** is an issue whose latest trusted Diagnosis comment — authored by an OWNER, MEMBER or COLLABORATOR, the same comment the Complexity signal is read from — records `meeting` under its `### Type` heading. When the caller supplies that Diagnosis type and it is `meeting`, the Complexity signal SHALL NOT contribute a reason, because the meeting type deliberately produces no complexity tier (see the meeting-issue-type capability); the `parking-lot` label and `### Blocking` signals SHALL still be evaluated for a meeting issue. The type SHALL NOT be taken from issue labels or from the issue body for this purpose, because the issue body is editable by the issue author; an issue with no trusted Diagnosis has the Diagnosis type `none` and its Complexity signal is evaluated as for any other type. When the Diagnosis type is not supplied, or is any value other than `meeting`, the gate SHALL produce exactly the verdict and reasons it produced before the Diagnosis type input existed. The `- [~]` disposition marker inside a Diagnosis `### Strategy` checklist SHALL NOT be an input to this gate, because that marker is a close-time per-item disposition consumed by `idd-close` rather than a per-issue actionability signal.

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

- **WHEN** the gate is called with Diagnosis type `meeting`, a Complexity parse result of unparseable or missing, no `parking-lot` label, and an empty `### Blocking` section
- **THEN** the gate reports the issue as actionable
- **AND** no `complexity-unparseable` or `complexity-missing` reason is reported

#### Scenario: Undiagnosed issue stays undiagnosed whatever its body says

- **WHEN** an issue has no trusted Diagnosis comment, so the gate is called with Diagnosis type `none`, and its body declares `## Type` `meeting`
- **THEN** the gate reports the issue as not actionable with reason `complexity-missing`
- **AND** the display group is undiagnosed, which retains the diagnose lifecycle command

#### Scenario: The issue body cannot release the gate

- **WHEN** an issue's latest trusted Diagnosis records type `bug` with the Complexity value `Simple when triggered`, and the issue author has since changed the body to declare `## Type` `meeting`
- **THEN** the gate is called with Diagnosis type `bug` and reports the issue as not actionable with reason `complexity-deferral-marker`

#### Scenario: Out-of-domain Diagnosis type is misuse

- **WHEN** the gate is called with a Diagnosis type that is empty or not one of `bug`, `feature`, `refactor`, `docs`, `meeting`, `unknown`, `none`
- **THEN** the gate exits with status 2 and reports no verdict

#### Scenario: Meeting issue still honours parking and blocking

- **WHEN** the gate is called with Diagnosis type `meeting` and the issue carries the `parking-lot` label
- **THEN** the gate reports the issue as not actionable with reason `parking-lot-label`
- **AND** when instead the `### Blocking` section is non-empty, the gate reports reason `blocking-nonempty`

#### Scenario: Omitted or non-meeting Diagnosis type preserves the existing verdict

- **WHEN** the gate is called without a Diagnosis type, or with any value other than `meeting`, on any row of the existing frozen fixtures
- **THEN** every verdict and reason list is identical to the result recorded before this change

### Requirement: Complexity tier extraction tolerates trailing rationale

The system SHALL extract the routing tier from the `### Complexity` field by (1) stripping leading and trailing markdown decoration, (2) requiring the stripped value to **begin with** one of `Simple`, `Plan`, `Spectra`, or `SDD-warranted` (longest match first, so `SDD-warranted` is not read as a non-tier), and (3) taking that leading tier as the extracted value. Any further text on the value line — same-line rationale, parenthetical explanation, or a ` via <source>` provenance suffix — SHALL NOT prevent tier extraction. Trailing rationale is the producer's normal writing style: in a corpus of 159 real diagnoses in this repository, 71.7% of values are not a bare tier (23.3% decorated, 41.5% carry same-line rationale, 0.6% a provenance suffix) and only 5.7% express deferral; a closed domain would have wrongly refused 41.5% of them (66 of 159). Extraction does not depend on the issue type; whether a non-routable value contributes a reason to the verdict is decided by the gate, which does not evaluate the Complexity signal of a diagnosed `meeting` issue (see "Actionability gate evaluates three signals disjunctively").

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

- **WHEN** the value is `移入 discussion list` on an issue that is not a diagnosed `meeting` issue
- **THEN** no tier is extracted
- **AND** the reason reported is `complexity-unparseable`

#### Scenario: Non-tier prefix on a diagnosed meeting issue contributes no reason

- **WHEN** the value is `（不適用）type=meeting 在 complexity 評估前分流` on a diagnosed `meeting` issue
- **THEN** no tier is extracted
- **AND** the gate reports no `complexity-unparseable` reason for it

### Requirement: Deferral vocabulary withholds routing under its own reason

The system SHALL scan the **entire** `### Complexity` value — not only the text following the tier — for deferral vocabulary, and SHALL withhold the issue from routing when any is found, even though the tier prefix is valid. This condition SHALL carry the distinct reason `complexity-deferral-marker`, separate from `complexity-unparseable` and `complexity-missing`, because the three call for different human responses: an unparseable value is a data defect to correct, a missing section is a diagnosis that never ran, and a deferral marker is a legitimate state requiring no repair. The deferral vocabulary SHALL NOT be treated as a closed enumeration — it is a high-precision heuristic, and the `parking-lot` label remains the primary parked signal. For a diagnosed `meeting` issue the Complexity signal is not evaluated (see "Actionability gate evaluates three signals disjunctively"), so deferral vocabulary in its `### Complexity` value SHALL NOT withhold it; parking a meeting issue is the `parking-lot` label's job.

#### Scenario: Deferral vocabulary withholds a valid tier

- **WHEN** the value is `Simple when triggered` on an issue that is not a diagnosed `meeting` issue
- **THEN** the issue is reported as not actionable with reason `complexity-deferral-marker`
- **AND** the string `Simple when triggered` appears in the operator-facing output

#### Scenario: Deferral vocabulary inside a parenthetical is still detected

- **WHEN** the value is `**Spectra**(Layer 2 + Layer 3 if/when triggered)` on an issue that is not a diagnosed `meeting` issue
- **THEN** the issue is reported as not actionable with reason `complexity-deferral-marker`

#### Scenario: Deferral reason is distinct from unparseable

- **WHEN** one issue that is not a diagnosed `meeting` issue has the value `Plan when triggered` and another such issue has the value `移入 discussion list`
- **THEN** the first reports reason `complexity-deferral-marker`
- **AND** the second reports reason `complexity-unparseable`

#### Scenario: Deferral vocabulary does not park a diagnosed meeting issue

- **WHEN** a diagnosed `meeting` issue has the `### Complexity` value `Plan when triggered`, no `parking-lot` label, and an empty `### Blocking` section
- **THEN** the issue is reported as actionable

### Requirement: Conservative verdict and mandatory surfacing on non-routable Complexity

When a `### Complexity` value cannot be routed for any reason, the system SHALL report the issue as not actionable and SHALL surface the original unmodified value to the operator. A missing `### Complexity` section SHALL report reason `complexity-missing`. The system SHALL NOT silently truncate a non-routable value to a tier prefix, SHALL NOT downgrade it to any tier, and SHALL NOT abort the enclosing listing operation. The single exception is a diagnosed `meeting` issue, whose Complexity signal is not evaluated (see "Actionability gate evaluates three signals disjunctively"); an issue with no trusted Diagnosis comment is not excepted and SHALL report `complexity-missing`.

#### Scenario: Missing section is distinguished from a non-routable value

- **WHEN** a Diagnosis comment of an issue that is not a diagnosed `meeting` issue contains no `### Complexity` section
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

- **WHEN** a diagnosed `meeting` issue has a `### Complexity` value that is a sentence
- **THEN** no complexity reason is reported for it
- **AND** an issue with no trusted Diagnosis comment is reported with reason `complexity-missing`, whatever its body declares

### Requirement: Single shared implementation of parsing and verdict

Complexity parsing and actionability verdict logic SHALL exist as one shared implementation. Every consumer that routes on `### Complexity` — `idd-list`, `idd-all`, `idd-implement`, and `idd-plan` — SHALL invoke that shared implementation rather than embedding its own parsing. The verdict reason vocabulary SHALL be the closed set `complexity-unparseable`, `complexity-missing`, `complexity-deferral-marker`, `parking-lot-label`, `blocking-nonempty`. When the shared implementation is unavailable, a consumer SHALL fail loudly and name the missing path rather than degrade to a private parsing path. Consumers SHALL agree on every input, including a diagnosed `meeting` issue, whose Complexity signal the shared implementation does not evaluate (see "Actionability gate evaluates three signals disjunctively").

#### Scenario: All routing consumers agree on the same input

- **WHEN** the same Diagnosis comment containing `Simple when triggered` is evaluated by each routing consumer for an issue that is not a diagnosed `meeting` issue
- **THEN** every consumer reports the value as non-routable under reason `complexity-deferral-marker`
- **AND** no consumer dispatches the issue to a lifecycle command, even though the tier prefix `Simple` is itself well-formed

#### Scenario: All routing consumers agree on a diagnosed meeting issue

- **WHEN** the same Diagnosis comment containing `Plan when triggered` is evaluated by each routing consumer for a diagnosed `meeting` issue with no `parking-lot` label and an empty `### Blocking` section
- **THEN** every consumer reports the issue as actionable with no complexity reason
- **AND** every consumer routes it on the meeting type rather than on any tier

#### Scenario: Missing helper fails loudly

- **WHEN** a consumer invokes the shared implementation and the implementation file is absent
- **THEN** the consumer reports an error naming the missing path
- **AND** the consumer does not fall back to a private parsing path

### Requirement: Existing diagnoses require no migration

Existing Diagnosis comments SHALL NOT be rewritten, and no label SHALL be backfilled, in order for the gate to produce correct verdicts on them. The extraction and deferral rules SHALL be validated against the repository's full diagnosis corpus, and that validation SHALL be a regression test rather than a one-off check. The corpus is evaluated without a Diagnosis type, and therefore under the rules for an issue that is not a diagnosed `meeting` issue; supplying any non-meeting Diagnosis type SHALL NOT change a corpus verdict.

#### Scenario: Full corpus produces correct verdicts unmodified

- **WHEN** the gate evaluates every existing Diagnosis comment in the repository without a Diagnosis type, or with any Diagnosis type other than `meeting`
- **THEN** every value carrying a valid tier without deferral vocabulary yields that tier
- **AND** every value carrying deferral vocabulary is withheld with reason `complexity-deferral-marker`
- **AND** no Diagnosis comment content is modified

#### Scenario: Fixture reflects real shapes rather than a hypothesis-confirming sample

- **WHEN** the regression fixture is reviewed
- **THEN** it contains at least three real-corpus cases each of bare tier, tier with same-line rationale, decorated tier, and deferral vocabulary

## ADDED Requirements

### Requirement: The meeting type is read from the latest trusted Diagnosis

The shared implementation SHALL provide the Diagnosis type that consumers pass to the gate, so that no consumer parses it on its own and no consumer takes it from issue labels or the issue body. Given the latest trusted Diagnosis comment, the result SHALL be read from the first non-empty line under its `### Type` heading, found with the same section reader as `### Complexity`, by these five steps and no others: (1) remove leading spaces and tabs, then any leading run of `*`, `_` and backtick characters; (2) take the leading run of ASCII letters as the word; (3) remove any run of `*`, `_` and backtick characters directly after the word; (4) the character that then follows, if there is one, SHALL NOT be an ASCII letter, an ASCII digit, `_` or `-`; (5) the word in ASCII lower case SHALL be one of `bug`, `feature`, `refactor`, `docs`, `meeting`. A line that fails any step, or no `### Type` heading, SHALL yield `unknown`; an empty input (no trusted Diagnosis) SHALL yield `none`. Only `meeting` relaxes the gate. A call with other than exactly one argument SHALL fail loudly with exit status 2.

#### Scenario: A meeting Diagnosis is read as meeting

- **WHEN** the latest trusted Diagnosis has `### Type` followed by the line `meeting（本文 ## Type；label 不是 IDD 類型）`
- **THEN** the Diagnosis type is `meeting`

#### Scenario: No trusted Diagnosis is none

- **WHEN** the issue has no trusted Diagnosis comment
- **THEN** the Diagnosis type is `none`

##### Example: Diagnosis type table

| Latest trusted Diagnosis | Diagnosis type |
| ------------------------ | -------------- |
| `### Type` / `meeting` | `meeting` |
| `### Type` / `**meeting**` | `meeting` |
| `### Type` / `bug` | `bug` |
| `### Type` / `meeting-notes` | `unknown` |
| `### Type` / `meeting（本文 ## Type）` | `meeting` |
| `### Type` / `meeting_` | `meeting` |
| `### Type` / `- meeting` | `unknown` |
| `### Type` / `type=meeting` | `unknown` |
| no `### Type` heading | `unknown` |
| (no trusted Diagnosis) | `none` |
