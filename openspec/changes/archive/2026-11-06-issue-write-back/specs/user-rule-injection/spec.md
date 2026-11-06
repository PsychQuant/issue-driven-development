## MODIFIED Requirements

### Requirement: SessionStart rule injection is minimal and canonical-aligned

The plugin SHALL ship a SessionStart hook (`hooks/hooks.json` + `hooks/session-start-commit-rule.sh`) whose output is at most 5 lines, containing the commit issue-reference iron rules, a pointer to the canonical rule file, and one line on issue write-back with the installed path of `rules/issue-write-back.md`. The hook content SHALL be statically defined except that installed path, and token-aligned with the canonical rule files.

#### Scenario: Hook artifact is wired for SessionStart

- **WHEN** the drift-guard test inspects the shipped hook artifacts
- **THEN** `hooks/hooks.json` wires exactly one SessionStart command entry to the executable hook script, whose direct execution prints at most 5 lines containing the issue-reference discipline and the canonical rule file path (artifact-level coverage; runtime hook discovery is Claude Code's contract — `hooks/hooks.json` is the documented auto-discovery location)

#### Scenario: Drift guard enforces alignment

- **WHEN** the drift-guard test runs
- **THEN** it asserts the hook output is ≤ 5 lines AND the key tokens (`(#N)`, `Refs #N`, close-keyword adjacency warning, `/idd-close`, canonical path) appear in both the hook output and `plugins/issue-driven-dev/rules/commit-issue-reference.md`
