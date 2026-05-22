## ADDED Requirements

### Requirement: idd-diagnose Step 0.5 Clarity Surface PR Gate

The `idd-diagnose` skill SHALL add a new Step 0.5 (between existing Step 0 Bootstrap and Step 1 Read Issue) that refuses to proceed when the target issue body contains unresolved `### Clarity Surface` rows.

#### Scenario: unresolved surfaced rows refuse diagnose

- **WHEN** `idd-diagnose #N` runs against an issue whose body contains a `### Clarity Surface` block with one or more rows having Status=surfaced (default)
- **THEN** the system SHALL emit an actionable refusal message listing all surfaced row indices
- **AND** the system SHALL exit non-zero with structured guidance:
  ```
  Issue #N has X unresolved Clarity Surface rows. Resolve via:
    - /idd-clarify #N --status resolved=<idx>,<reason>
    - /idd-clarify #N --status dismissed=<idx>,<reason>
    - LINE/email domain expert and update issue body manually
  ```
- **AND** the system MUST NOT proceed to Step 1 Read Issue

#### Scenario: all rows resolved or dismissed proceeds normally

- **WHEN** all `### Clarity Surface` rows have Status=resolved or Status=dismissed
- **THEN** the system SHALL proceed to Step 1 (Read Issue) normally

#### Scenario: empty passed marker proceeds normally

- **WHEN** the `### Clarity Surface` block contains only a `(none — no issues detected)` row with Status=passed
- **THEN** the system SHALL proceed to Step 1 normally

#### Scenario: deferred placeholder refuses with retry hint

- **WHEN** the issue body contains `### Clarity Surface (deferred — see retry hint)` placeholder (per idd-issue Step 4.6 failure-handling)
- **THEN** the system SHALL refuse with actionable message: `Run /idd-clarify #N manually to populate Clarity Surface before diagnose`
- **AND** exit non-zero

### Requirement: idd-diagnose Step 0.5 backward compat for legacy issues

The system SHALL silently proceed to Step 1 when the issue body contains no `### Clarity Surface` block (legacy issue filed before v2.71.0 plugin version).

#### Scenario: legacy issue lacking Clarity Surface block

- **WHEN** `idd-diagnose #N` runs against an issue whose body contains no `### Clarity Surface` section
- **THEN** the system SHALL log `[Step 0.5] no Clarity Surface block found (legacy issue — pre-v2.71.0)`
- **AND** SHALL proceed to Step 1 without refusal

### Requirement: idd-diagnose Step 0.5 Bootstrap TaskCreate entry

The system SHALL add a Step 0 Bootstrap TaskCreate entry corresponding to Step 0.5 so the stage TaskList accurately reflects the new gate in completion tracking.

#### Scenario: Step 0 Bootstrap includes Step 0.5 task

- **WHEN** `idd-diagnose` runs its Step 0 Bootstrap stage TaskCreate batch
- **THEN** the batch SHALL include `TaskCreate(name="clarity_gate_check", description="Step 0.5: grep issue body for ### Clarity Surface unresolved rows; refuse if any per IC clarity axis hard-refuse rule")`
- **AND** the task SHALL be ordered immediately after the existing read_issue task (which itself is the first body-touching task)

### Requirement: idd-diagnose Step 0.5 unattended-mode contract deferred to sister

The system SHALL document that Step 0.5 unattended-mode behavior (under `/idd-all` PR mode with UNATTENDED MODE directive) is deferred to sister issue #137 and currently follows fail-fast policy.

#### Scenario: unattended mode hits unresolved Clarity Surface

- **WHEN** `idd-diagnose #N` runs under `/idd-all` UNATTENDED MODE directive against an issue with unresolved Clarity Surface rows
- **THEN** the system SHALL refuse with the same structured message as attended mode
- **AND** `idd-all` orchestrator SHALL abort according to its existing abort flow (per `idd-all-chain` #119 fail-fast precedent)
- **AND** the refusal message SHALL include reference: `(unattended contract deferred to sister #137; current behavior: fail-fast)`
