## ADDED Requirements

### Requirement: idd-issue Step 4.6 auto-delegate to idd-clarify

The `idd-issue` skill SHALL add a new Step 4.6 (between existing Step 4.5 Milestone and Step 4.7 Linked-Context Sister Sweep) that auto-delegates to `/idd-clarify` after issue creation, except when in `--multi-finding` mode.

#### Scenario: doc source triggers Step 4.6 auto-delegate

- **WHEN** `idd-issue` files a new issue from a `.docx` / `.pdf` source
- **THEN** after Step 4.5 (Milestone) and before Step 4.7 (Sister Sweep), the system SHALL invoke `Skill(skill="idd-clarify", args="#$NEW_ISSUE_NUMBER")`
- **AND** the resulting `### Clarity Surface` annotation block MUST appear in the issue body before Step 4.7 reads body for sister-concern scanning

#### Scenario: pasted-text source triggers Step 4.6 auto-delegate

- **WHEN** `idd-issue` files a new issue from pasted text (no document source file)
- **THEN** Step 4.6 SHALL invoke `/idd-clarify` with the same behavior as doc source

#### Scenario: multi-finding mode skips Step 4.6

- **WHEN** `idd-issue` runs in `--multi-finding` mode (single source produces N findings = N issues)
- **THEN** Step 4.6 SHALL be skipped entirely for the multi-finding session
- **AND** the audit trail MUST record `Step 4.6 skipped: --multi-finding mode`

#### Scenario: Step 4.6 placement preserves Step 4.7 ordering

- **WHEN** `idd-issue` runs against a doc source
- **THEN** the execution order MUST be: Step 4.5 (Milestone) → Step 4.6 (Clarity Surface) → Step 4.7 (Sister Sweep) → Step 4.8 (Split Umbrella SOP)
- **AND** Step 4.7 Sister Sweep MUST read the issue body AFTER Step 4.6 has appended the Clarity Surface annotation block

### Requirement: idd-issue Step 4.6 failure handling

The system SHALL gracefully handle `/idd-clarify` invocation failures during Step 4.6 without aborting the entire `idd-issue` workflow.

#### Scenario: idd-clarify delegation fails (network / gh API error)

- **WHEN** the delegated `/idd-clarify` invocation fails for non-fatal reasons (gh API rate limit, network timeout, transient library file read error)
- **THEN** `idd-issue` SHALL emit a warning to stderr referencing the failure cause
- **AND** `idd-issue` SHALL continue to Step 4.7 (Sister Sweep) without aborting
- **AND** the issue MUST be marked with a `### Clarity Surface (deferred — see retry hint)` placeholder block so downstream `idd-diagnose` Step 0.5 gate does not silently bypass

#### Scenario: idd-clarify delegation returns empty surface

- **WHEN** the delegated `/idd-clarify` invocation completes successfully with no issues detected
- **THEN** the issue body MUST contain `### Clarity Surface` block with `(none — no issues detected)` row Status=passed
- **AND** Step 4.7 SHALL proceed normally

### Requirement: idd-issue Step 4.6 Bootstrap TaskCreate entry

The system SHALL add a Step 0 Bootstrap TaskCreate entry corresponding to Step 4.6 so the stage TaskList accurately reflects the new step in completion tracking.

#### Scenario: Step 0 Bootstrap includes Step 4.6 task

- **WHEN** `idd-issue` runs its Step 0 Bootstrap stage TaskCreate batch
- **THEN** the batch SHALL include `TaskCreate(name="clarity_surface", description="Step 4.6: delegate to /idd-clarify $NEW_ISSUE_NUMBER per IC clarity axis")`
- **AND** the task SHALL be ordered between the existing milestone task and sister-sweep task
