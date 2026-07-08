## MODIFIED Requirements

### Requirement: Kept disciplines are excluded from delegation

`idd-verify` ensemble backend resolution, worktree isolation, and planning disciplines (idd-plan / Spectra — explicitly including the `brainstorming` and `writing-plans` counterparts) SHALL NOT delegate to `superpowers`. A non-binding hand-off pointer surfaced by `idd-issue` or `idd-diagnose` that names `superpowers:brainstorming` as an optional pre-implementation staging destination for the user is NOT delegation — IDD's own planning flow does not invoke it, and the user chooses whether to follow the pointer — and it is permitted; that pointer is governed by the "Pre-implementation staging hand-off to superpowers" requirement.

#### Scenario: Verify backend unaffected

- **WHEN** `idd-verify` resolves its ensemble backend
- **THEN** resolution follows the existing `idd-verify` spec chain (pai canonical → vendored fallback → manual fan-out) with no `superpowers` involvement

#### Scenario: Planning disciplines remain superpowers-free

- **WHEN** `idd-plan` or the Spectra planning skills execute
- **THEN** their skill definitions contain no `superpowers:` invocation (mechanical check: `grep -rn 'superpowers:' plugins/issue-driven-dev/skills/idd-plan/` returns zero hits)

## ADDED Requirements

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
