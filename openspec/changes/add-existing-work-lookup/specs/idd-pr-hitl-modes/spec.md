## ADDED Requirements

### Requirement: PR mode SHALL check for existing work before it creates a feature branch

In PR mode, `idd-all` SHALL run the existing-work check for each issue before Phase 0.5 creates the `idd/<N>-<slug>` feature branch. A blocked verdict SHALL leave the working tree and the branch list unchanged. Direct-commit mode SHALL run the same check at the same point in its flow, before it changes anything.

#### Scenario: Blocked issue in PR mode

- **GIVEN** `idd-all` runs in PR mode on an issue whose verdict is `blocked`
- **WHEN** the check completes
- **THEN** no feature branch SHALL have been created
- **AND** the working tree SHALL be as it was before the run

#### Scenario: Clear issue in PR mode

- **GIVEN** an issue whose verdict is `clear`
- **WHEN** the check completes
- **THEN** Phase 0.5 SHALL proceed as before
