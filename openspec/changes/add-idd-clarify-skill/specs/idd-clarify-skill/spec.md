## ADDED Requirements

### Requirement: idd-clarify standalone primitive surfacing

The system SHALL provide a `/idd-clarify <#N>` skill that scans the body of an existing GitHub issue for terminology mismatches, ambiguity, and missing-context gaps, then annotates the issue body with a `### Clarity Surface` section. The skill SHALL be surfacing-only and MUST NOT resolve, fix, or rewrite the source content.

#### Scenario: terminology mismatch detection from canonical library

- **WHEN** the user invokes `/idd-clarify #N` and the issue body contains terms listed in `references/terminology-canonical.md` heuristic rules
- **THEN** the system SHALL emit a `### Clarity Surface` annotation block appended to the issue body via `gh issue edit`
- **AND** each detected mismatch SHALL produce one row with columns: Type=terminology, Source=quoted-excerpt, Suggested-canonical=heuristic-lookup, Status=surfaced
- **AND** the system MUST NOT modify any IC_R007 verbatim blockquotes in the source body

#### Scenario: ambiguity marker detection

- **WHEN** the issue body contains terms with multiple plausible interpretations (per skill heuristic — under-specified critical variables, conflicting modifiers, undefined acronyms)
- **THEN** the system SHALL emit a row with Type=ambiguity, Source=quoted-excerpt, Suggested-canonical=detected-interpretations-list, Status=surfaced

#### Scenario: missing-context marker detection

- **WHEN** the issue body describes an analysis or implementation that requires input X but the source of X is not specified
- **THEN** the system SHALL emit a row with Type=missing-context, Source=quoted-excerpt, Suggested-canonical=gap-description, Status=surfaced

#### Scenario: empty surface produces explicit passed marker

- **WHEN** no terminology / ambiguity / missing-context issues are detected
- **THEN** the system SHALL still emit the `### Clarity Surface` block with a single row `(none — no issues detected)` and Status=passed
- **AND** the body MUST NOT be missing the annotation block (avoids ambiguity between "not yet run" and "ran, passed")

### Requirement: idd-clarify status resolution interface

The system SHALL provide `--status <action>=<row_idx>[,<reason>]` flag for marking individual Clarity Surface rows as dismissed or resolved. The system MUST NOT delete rows from the annotation block to preserve audit trail.

#### Scenario: resolved status with reason

- **WHEN** the user invokes `/idd-clarify #N --status resolved=2,domain expert confirmed canonical term`
- **THEN** the system SHALL update row index 2 Status column to `resolved (reason: domain expert confirmed canonical term)`
- **AND** the original row content (Type, Source, Suggested-canonical) MUST remain unchanged

#### Scenario: dismissed status with reason

- **WHEN** the user invokes `/idd-clarify #N --status dismissed=3,false positive — source term is correct`
- **THEN** the system SHALL update row index 3 Status column to `dismissed (reason: false positive — source term is correct)`

#### Scenario: invalid row index

- **WHEN** the user supplies a row index that does not exist in the Clarity Surface block
- **THEN** the system SHALL emit an actionable error message listing valid row indices and exit non-zero

#### Scenario: dismissed-to-resolved transition preserves history

- **WHEN** a row currently has Status=dismissed and user invokes `--status resolved=<idx>,<reason>`
- **THEN** the system SHALL update the row to `resolved (was: dismissed @ <previous timestamp>; reason: <new reason>)`
- **AND** the original dismissal timestamp MUST be preserved in the transition note

### Requirement: idd-clarify operates on existing issues only

The system SHALL be invokable only against an existing GitHub issue (state OPEN or CLOSED). It SHALL NOT create new issues.

#### Scenario: target issue does not exist

- **WHEN** the user invokes `/idd-clarify #99999` against a non-existent issue
- **THEN** the system SHALL emit an actionable error referencing `gh issue view` and exit non-zero

### Requirement: idd-clarify terminology library reload per invocation

The system SHALL freshly read `references/terminology-canonical.md` on every invocation. The system MUST NOT cache library contents across invocations.

#### Scenario: library updated between invocations

- **WHEN** the user updates `references/terminology-canonical.md` with a new misuse pattern, then invokes `/idd-clarify #N`
- **THEN** the system SHALL detect the new pattern without requiring a plugin reload
