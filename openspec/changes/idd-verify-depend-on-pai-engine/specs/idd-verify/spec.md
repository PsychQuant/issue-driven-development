## MODIFIED Requirements

### Requirement: Independent-agent cross-verification ensemble

The `/idd-verify` capability SHALL verify an implementation through an ensemble of independent agents: distinct-lens reviewers (requirements, logic, security, regression), an adversarial devil's-advocate that attempts to refute the other lenses' pass judgments, and a cross-model blind verifier. The reported result SHALL be the merged, deduplicated union of all sources, with each finding's severity taken as the highest reported. Ensemble agents (both workflow-backend and manual fan-out) SHALL be dispatched on an explicitly configured Claude model — defaulting to `opus` and overridable via the `IDD_AGENT_MODEL` environment variable — rather than inheriting the session's main-loop model; an invalid override value SHALL fail loudly at dispatch time. The cross-model verifier's non-Claude engine is exempt (it runs on a different model family by design), but the agent that drives it is dispatched like any other ensemble agent. The master report SHALL disclose the dispatch model. The workflow backend SHALL be resolved through a three-tier chain: (1) the installed parallel-ai-agents canonical ensemble engine when its version meets the minimum contract version (2.18.0, the start of the `agentModel` + stable external-consumer contract), configured via that contract's custom-profile surface so the four IDD lenses, devil's-advocate focus, untrusted-content guard, and dispatch model are preserved; (2) the frozen vendored fallback engine when the canonical engine is absent or predates the contract; (3) manual fan-out when no workflow primitive is available. The resolved backend and, for the canonical tier, its version SHALL be disclosed in a notice line and in the master report's engine line.

#### Scenario: ensemble composition and merge

- **WHEN** `/idd-verify` runs on a change
- **THEN** findings are produced from each distinct lens, the devil's-advocate has attempted to refute the other lenses' pass judgments, and the cross-model verifier has run independently
- **AND** the reported findings are the merged + deduplicated union, severity taken highest

#### Scenario: dispatch model defaults to opus

- **GIVEN** `IDD_AGENT_MODEL` is unset
- **WHEN** the ensemble dispatches its agents
- **THEN** every reviewer, the devil's-advocate, and the cross-model runner agent carry an explicit `opus` model designation
- **AND** the master report's engine line discloses the dispatch model

#### Scenario: explicit override is honored and validated

- **GIVEN** `IDD_AGENT_MODEL=sonnet`
- **WHEN** the ensemble dispatches
- **THEN** agents run on sonnet
- **AND** an invalid value (e.g. `gpt-4`) aborts dispatch with a usage error naming the accepted values

#### Scenario: canonical engine preferred when contract version is met

- **GIVEN** the parallel-ai-agents plugin is installed at version 2.18.0 or newer
- **WHEN** `/idd-verify` resolves its workflow backend
- **THEN** the installed canonical engine runs the ensemble via the custom-profile contract (four IDD lenses, DA focus, guarded untrusted context, `agentModel` threaded)
- **AND** the notice and engine lines disclose `pai-ensemble <version>`

#### Scenario: graceful degrade below the contract version

- **GIVEN** the installed parallel-ai-agents version predates 2.18.0, or the plugin is absent
- **WHEN** `/idd-verify` resolves its workflow backend
- **THEN** the frozen vendored fallback engine runs instead (never the pre-contract canonical engine, which would silently drop `agentModel`)
- **AND** the degrade reason is disclosed in the notice line
