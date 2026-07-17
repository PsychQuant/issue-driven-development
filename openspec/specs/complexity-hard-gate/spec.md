# complexity-hard-gate Specification

## Purpose

TBD - created by archiving change 'reshape-plan-preimpl-tier'. Update Purpose after archive.

## Requirements

### Requirement: MUST-trigger complexity hard gate layered above Layer P

`/idd-diagnose` Step 3.5 SHALL evaluate a MUST-trigger hard gate that forces escalation out of the `Simple` default when the diagnosed change is estimated to touch at least N files (default N = 5) **that belong to one interdependent concept**, OR to modify a shared abstraction. A shared abstraction is a data structure, helper interface, or constants set estimated to be referenced by at least 2 distinct files other than the one under change. The file-count trigger is scoped to *one interdependent concept scattered across files*, NOT raw file count: genuinely-independent multi-file changes (parallel doc updates, independent script tweaks) SHALL NOT trigger the hard gate — they remain `Simple` via the Layer 1 "Multi-file but each file independent" disqualifier. The hard gate SHALL only escalate: when it does not trigger, routing SHALL fall through to the existing Layer P disjunctive any-match evaluation with the `Simple` default preserved. The hard gate SHALL NOT invert the default tier to `Plan`.

The **escalation destination is config-sensitive** (#252): when the gate fires, the verdict SHALL be `Plan` when the walked-up IDD config's `sdd_bias` field is absent or `default`, and SHALL be `Spectra via hard-gate (sdd_bias)` when `sdd_bias` is `high` (downstream parsers extract the canonical tier by stripping the existing ` via ` suffix). Values of `sdd_bias` other than `high` or `default` SHALL be treated as `default` without error or warning. The `sdd_bias` field SHALL act only at the hard-gate exit: it SHALL NOT widen Layer 2's Spectra qualification, SHALL NOT alter Layer P signals or the `Simple` default, and SHALL have no effect when the gate does not fire. The gate's trigger criteria, its escalate-only nature, its audit line, and its position in the 7-step routing order SHALL remain unchanged by the field.

#### Scenario: Multi-file change of one interdependent concept forces Plan

- **WHEN** `/idd-diagnose` estimates a change will touch 5 or more files that belong to one interdependent concept
- **THEN** the Complexity verdict is `Plan`, set by the hard gate before Layer P is consulted

#### Scenario: Shared-abstraction change forces Plan

- **WHEN** `/idd-diagnose` estimates the change modifies a helper interface referenced by 2 or more other files
- **THEN** the Complexity verdict is `Plan`, set by the hard gate

##### Example: gate decisions by estimated scope

| Estimated scope | Shared abstraction touched | Hard gate | Complexity verdict |
| --------------- | -------------------------- | --------- | ------------------ |
| 1 file (impl only) | no | not triggered | Simple (default) |
| 3 files (impl + test + doc) | no | not triggered | Simple (default), unless Layer P any-match fires |
| 5 files of one interdependent concept | no | triggered | Plan |
| 5 genuinely-independent files (parallel doc / script edits) | no | not triggered | Simple (Layer 1 disqualifier) |
| 2 files | yes (constants set used by 4 callers) | triggered | Plan |

#### Scenario: Small isolated change preserves the Simple default

- **WHEN** `/idd-diagnose` estimates a change touches 1 file and no shared abstraction, and no Layer P signal fires
- **THEN** the hard gate does not trigger and the Complexity verdict is `Simple`

#### Scenario: default repo keeps the Plan exit

- **GIVEN** a repo whose IDD config has no `sdd_bias` field
- **WHEN** a diagnosis estimates a single concept spread across 6 interdependent files
- **THEN** the Complexity verdict is `Plan` with the hard-gate audit line, exactly as before

#### Scenario: high-bias repo escalates to Spectra

- **GIVEN** a repo whose IDD config sets `"sdd_bias": "high"`
- **WHEN** the same 6-file interdependent change is diagnosed
- **THEN** the Complexity verdict is `Spectra via hard-gate (sdd_bias)` and downstream parsers extract the canonical tier `Spectra` via the existing ` via ` suffix strip

#### Scenario: invalid value degrades to default silently

- **GIVEN** a repo whose config sets `"sdd_bias": "maximum"`
- **WHEN** a hard-gate hit occurs
- **THEN** the verdict is `Plan` (default) and routing does not abort or warn beyond the normal audit line


<!-- @trace
source: sdd-bias-switch
updated: 2026-07-17
code:
  - plugins/issue-driven-dev/scripts/.impeccable/hook.cache.json
  - plugins/issue-driven-dev/skills/idd-verify/.impeccable/hook.cache.json
  - .wiki-last-sync
-->

---
### Requirement: Hard-gate estimate is disclosed in the audit trail

The hard-gate evaluation SHALL be an AI scope estimate, because `/idd-diagnose` runs before implementation and no diff exists yet. The evaluation SHALL be disclosed as a single audit line of the form `Hard-gate: <triggered|not triggered> — <reason with concrete anchors>` in the Diagnosis comment, placed alongside the Layer V audit line. The reason SHALL cite concrete anchors (estimated file names or symbol names), not style words. When the issue provides insufficient signal to estimate file count or caller count, the hard gate SHALL NOT trigger and the audit line SHALL state `insufficient signal`.

#### Scenario: Triggered gate discloses reason and anchors

- **WHEN** the hard gate triggers because the issue names four scale-family modules plus a shared scoring helper
- **THEN** the Diagnosis comment contains a line `Hard-gate: triggered — <names the modules and the shared helper>`

#### Scenario: Insufficient signal fails open to Layer P

- **WHEN** the issue body is too sparse to estimate file count or caller count
- **THEN** the hard gate does not trigger, the audit line reads `Hard-gate: not triggered — insufficient signal`, and routing falls through to Layer P with the `Simple` default


<!-- @trace
source: reshape-plan-preimpl-tier
updated: 2026-07-08
code:
  - plugins/issue-driven-dev/skills/.impeccable/hook.cache.json
-->

---
### Requirement: Shared-abstraction trigger forces family-wide Plan scope

When the hard gate triggers because of a shared-abstraction estimate, the resulting Plan SHALL enumerate all known call sites and family members of that abstraction as in-scope, not only the triggering file.

#### Scenario: Plan enumerates family members

- **WHEN** the hard gate triggers on a change to a scoring helper shared by three sibling scale modules
- **THEN** the Plan lists all three sibling modules as in-scope, not just the one module named in the issue title

<!-- @trace
source: reshape-plan-preimpl-tier
updated: 2026-07-08
code:
  - plugins/issue-driven-dev/skills/.impeccable/hook.cache.json
-->