## ADDED Requirements

### Requirement: Claude Code is the canonical IDD runtime

IDD skills SHALL treat Claude Code as the canonical runtime for workflow semantics. Other agent runtimes that load the same skill source tree through compatibility shells MUST preserve the Claude-defined workflow semantics or explicitly mark any degraded fallback.

#### Scenario: non-Claude runtime cannot provide an equivalent primitive

- **WHEN** a non-Claude runtime encounters a Claude-native primitive that it cannot faithfully emulate
- **THEN** it documents the behavior as degraded rather than silently weakening the workflow gate
- **AND** it does not redefine the canonical skill semantics

##### Example: structured user choice is unavailable

- **GIVEN** Claude Code exposes `AskUserQuestion` with structured choices
- **AND** Codex support only has a plain-text user prompt available for that workflow
- **WHEN** a skill requires the user to choose between `diagnose`, `implement`, and `verify`
- **THEN** the Codex mapping documents the fallback as degraded
- **AND** the skill still treats the Claude Code behavior as canonical

### Requirement: Shared skills tree remains canonical

The repository SHALL keep `plugins/issue-driven-dev/skills/` as the canonical source tree for IDD skill behavior. Platform-specific support MUST prefer compatibility references, adapters, or plugin shell metadata before introducing a forked skill tree.

#### Scenario: Codex support needs tool interpretation

- **WHEN** Codex support needs to interpret a Claude-native tool contract
- **THEN** the mapping is documented in a reference file or adapter layer
- **AND** `skills-codex/` is not introduced unless a specific incompatibility is documented

### Requirement: Runtime tool mappings are explicit

The plugin documentation SHALL provide runtime tool mapping references for Claude Code and Codex. The Codex mapping MUST name unsupported or degraded behavior explicitly.

#### Scenario: maintainer reviews runtime compatibility

- **WHEN** a maintainer needs to assess whether a skill can run under Codex
- **THEN** they can compare `references/claude-code-tools.md` and `references/codex-tools.md`
- **AND** both references use the same tool-contract vocabulary
- **AND** Codex-specific limitations are visible in the mapping

### Requirement: Documentation avoids full-parity claims

The plugin documentation SHALL distinguish between loading the shared skill tree and achieving full runtime parity. Documentation MUST NOT imply that a compatibility shell makes every Claude-native skill contract fully equivalent in another runtime.

#### Scenario: user reads runtime support docs

- **WHEN** a user reads the plugin README
- **THEN** they see that Claude Code is the canonical runtime
- **AND** they see that other runtimes are compatibility consumers of the same skills
- **AND** they see references for runtime tool mappings

##### Example: README points to compatibility references

- **GIVEN** a user opens `plugins/issue-driven-dev/README.md`
- **WHEN** they read the runtime support section
- **THEN** they see that `skills/` is shared across supported shells
- **AND** they see links to `references/claude-code-tools.md` and `references/codex-tools.md`
