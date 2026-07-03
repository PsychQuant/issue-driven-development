# user-rule-injection Specification

## Purpose

TBD - created by archiving change 'rules-layering-user-injection'. Update Purpose after archive.

## Requirements

### Requirement: SessionStart rule injection is minimal and canonical-aligned

The plugin SHALL ship a SessionStart hook (`hooks/hooks.json` + `hooks/session-start-commit-rule.sh`) whose output is at most 5 lines, containing the commit issue-reference iron rules and a pointer to the canonical rule file. The hook content SHALL be statically defined and token-aligned with the canonical rule file.

#### Scenario: Hook artifact is wired for SessionStart

- **WHEN** the drift-guard test inspects the shipped hook artifacts
- **THEN** `hooks/hooks.json` wires exactly one SessionStart command entry to the executable hook script, whose direct execution prints at most 5 lines containing the issue-reference discipline and the canonical rule file path (artifact-level coverage; runtime hook discovery is Claude Code's contract — `hooks/hooks.json` is the documented auto-discovery location)

#### Scenario: Drift guard enforces alignment

- **WHEN** the drift-guard test runs
- **THEN** it asserts the hook output is ≤ 5 lines AND the key tokens (`(#N)`, `Refs #N`, close-keyword adjacency warning, `/idd-close`, canonical path) appear in both the hook output and `plugins/issue-driven-dev/rules/commit-issue-reference.md`

---
### Requirement: Canonical user-facing rule location

The canonical user-facing commit issue-reference rule SHALL live at `plugins/issue-driven-dev/rules/commit-issue-reference.md` and ship with the plugin. The dev-layer copy SHALL be a distilled pointer (≤ 10 lines) back to the canonical file, not a parallel full text.

#### Scenario: Single canonical source

- **WHEN** the rule content needs an update
- **THEN** only the plugin rules file requires the normative edit; the dev-layer file and plugin CLAUDE.md section reference it by path

---
### Requirement: Skill-scope reference at commit-authoring sites

`idd-implement` and `idd-all` SHALL reference the canonical rule file in their commit-conventions sections, so skill-driven commits get the discipline in-scope even without the hook.

#### Scenario: Skill references present

- **WHEN** grepping the two SKILL.md files for the canonical rule path
- **THEN** each contains at least one reference to `rules/commit-issue-reference.md`
