# superpowers-integration Specification

## Purpose

TBD - created by archiving change 'idd-depend-on-superpowers'. Update Purpose after archive.

## Requirements

### Requirement: Superpowers install-time dependency declaration

The IDD plugin manifest SHALL declare `superpowers` as a plugin dependency resolved from the `claude-plugins-official` marketplace (unversioned), and the IDD root marketplace manifest SHALL list `claude-plugins-official` in `allowCrossMarketplaceDependenciesOn`.

#### Scenario: Fresh install auto-installs superpowers

- **WHEN** a user installs `issue-driven-dev` and `superpowers` is not yet installed
- **THEN** Claude Code resolves and installs `superpowers` automatically and lists it as an added dependency in the install output

#### Scenario: Cross-marketplace resolution is allowlisted

- **WHEN** dependency resolution evaluates the `superpowers` entry from the IDD marketplace
- **THEN** resolution proceeds without a `cross-marketplace` error because the root marketplace allowlist contains `claude-plugins-official`

---
### Requirement: Dual pre-flight at delegation sites

Each delegation site SHALL verify, before delegating: (1) the `superpowers` plugin is present in the local plugin cache, and (2) the target skill exists by name within it. On either failure the invoking skill SHALL abort with an error message containing the one-step install command `claude plugin install superpowers@claude-plugins-official`. The invoking skill SHALL NOT fall back to built-in equivalent process descriptions and SHALL NOT silently degrade. The sole documented exception is the audited operator override `IDD_SKIP_PLUGIN_CHECK=1`, which prints a stderr warning and exits 0 — an explicit, logged operator action, not a silent degrade (R2 verify reconciliation).

#### Scenario: Plugin absent triggers fail-fast

- **WHEN** `idd-implement` reaches the TDD delegation site and the `superpowers` plugin is absent from the plugin cache
- **THEN** the skill aborts and the error message contains the literal install command

#### Scenario: Plugin present but target skill renamed upstream

- **WHEN** the `superpowers` plugin is present but a target skill name is not found
- **THEN** the skill aborts and the error message names the missing skill; no built-in fallback executes

---
### Requirement: Process-discipline delegation

`idd-implement` SHALL delegate its TDD execution loop to `superpowers:test-driven-development` and its pre-completion check to `superpowers:verification-before-completion`. `idd-diagnose` SHALL delegate the bug-type root-cause-analysis execution framework to `superpowers:systematic-debugging`. IDD-specific wrapper discipline — issue-anchored commits referencing `#N`, scope control, and report/comment formats — SHALL remain owned by IDD and SHALL NOT be delegated.

#### Scenario: TDD loop delegates while commit discipline stays

- **WHEN** `idd-implement` executes implementation for an issue
- **THEN** the RED-GREEN-REFACTOR execution follows `superpowers:test-driven-development`, and each commit still references the issue number per IDD discipline

#### Scenario: Bug RCA delegates while report format stays

- **WHEN** `idd-diagnose` runs the diagnosis step for a bug-type issue
- **THEN** the investigation framework follows `superpowers:systematic-debugging`, and the Diagnosis Report structure posted to the issue remains the IDD template

---
### Requirement: Kept disciplines are excluded from delegation

`idd-verify` ensemble backend resolution, worktree isolation, and planning disciplines (idd-plan / Spectra — explicitly including the `brainstorming` and `writing-plans` counterparts) SHALL NOT delegate to `superpowers`. A non-binding hand-off pointer surfaced by `idd-issue` or `idd-diagnose` that names `superpowers:brainstorming` as an optional pre-implementation staging destination for the user is NOT delegation — IDD's own planning flow does not invoke it, and the user chooses whether to follow the pointer — and it is permitted; that pointer is governed by the "Pre-implementation staging hand-off to superpowers" requirement.

#### Scenario: Verify backend unaffected

- **WHEN** `idd-verify` resolves its ensemble backend
- **THEN** resolution follows the existing `idd-verify` spec chain (pai canonical → vendored fallback → manual fan-out) with no `superpowers` involvement

#### Scenario: Planning disciplines remain superpowers-free

- **WHEN** `idd-plan` or the Spectra planning skills execute
- **THEN** their skill definitions contain no `superpowers:` invocation (mechanical check: `grep -rn 'superpowers:' plugins/issue-driven-dev/skills/idd-plan/` returns zero hits)


<!-- @trace
source: reshape-plan-preimpl-tier
updated: 2026-07-08
code:
  - plugins/issue-driven-dev/skills/.impeccable/hook.cache.json
-->

---
### Requirement: Pre-implementation staging hand-off to superpowers

The IDD plugin README SHALL contain an IDD-to-superpowers stage-mapping table that maps each IDD pipeline stage to its superpowers counterpart and marks the `idd-verify` ensemble and the `idd-close` audit trail as IDD-unique (no superpowers counterpart). For a design-heavy issue, `idd-issue` (at its issue-creation summary step) and `idd-diagnose` SHALL surface a non-binding hand-off pointer naming `superpowers:brainstorming` as the pre-implementation staging destination. IDD SHALL NOT add a self-built brainstorming or plan-writing skill; no skill named `idd-brainstorm` or `idd-write-plan` SHALL exist.

#### Scenario: README documents the stage mapping

- **WHEN** a reader opens the IDD plugin README
- **THEN** a stage-mapping table maps IDD pipeline stages to superpowers counterparts and explicitly marks the verify ensemble and close audit trail as having no superpowers counterpart

#### Scenario: Design-heavy issue surfaces the brainstorming pointer

- **WHEN** `idd-diagnose` classifies an issue as design-heavy (Plan tier or Spectra tier)
- **THEN** the emitted output contains a non-binding pointer naming `superpowers:brainstorming` as the pre-implementation staging destination, and the pointer does not cause IDD to invoke that skill itself

#### Scenario: No self-built staging skill is added

- **WHEN** the IDD plugin skill set is enumerated
- **THEN** no skill named `idd-brainstorm` or `idd-write-plan` exists (mechanical check: the `plugins/issue-driven-dev/skills/` directory contains neither)

<!-- @trace
source: reshape-plan-preimpl-tier
updated: 2026-07-08
code:
  - plugins/issue-driven-dev/skills/.impeccable/hook.cache.json
-->