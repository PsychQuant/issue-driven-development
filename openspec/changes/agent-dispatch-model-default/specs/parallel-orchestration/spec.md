## MODIFIED Requirements

### Requirement: Opt-in parallel-diagnose fan-out

`idd-diagnose` SHALL support an opt-in path that, for an issue whose root cause spans N independent subsystems or hypotheses, fans out one read-only investigator per subsystem in parallel (via the Workflow tool) and then runs a synthesis agent that merges their findings into a single Diagnosis Report. This path SHALL remain opt-in; the single-agent diagnose path SHALL stay the default for simple issues. The synthesis output SHALL cite concrete file references drawn from at least two independent investigator legs. Every agent dispatched under this fan-out (investigators, the synthesis agent, and adversarial-variant skeptics) SHALL carry an explicit dispatch model resolved per the idd-verify dispatch-model rule — `IDD_AGENT_MODEL` when set and valid, `opus` otherwise, with invalid values failing loudly — never inheriting the session's main-loop model implicitly.

#### Scenario: multi-subsystem RCA fans out and synthesizes

- **WHEN** the parallel-diagnose fan-out is opted into for an issue whose root cause spans three independent subsystems
- **THEN** three read-only investigators run in parallel and a synthesis agent produces one Diagnosis Report citing file references from at least two of the legs
- **AND** every dispatched agent carries an explicit model designation (default `opus`)

#### Scenario: fan-out dispatch never inherits the session model

- **GIVEN** a session running on a tier above opus and `IDD_AGENT_MODEL` unset
- **WHEN** the parallel-diagnose fan-out dispatches its investigators and synthesis agent
- **THEN** each agent is dispatched with an explicit `opus` designation rather than the session's main-loop model
