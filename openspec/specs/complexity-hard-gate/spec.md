# complexity-hard-gate Specification

## Purpose

TBD - created by archiving change 'reshape-plan-preimpl-tier'. Update Purpose after archive.

## Requirements

### Requirement: MUST-trigger complexity hard gate layered above Layer P

`/idd-diagnose` Step 3.5 SHALL evaluate a MUST-trigger hard gate that forces the `Plan` complexity tier when the diagnosed change is estimated to touch at least N files (default N = 5) **that belong to one interdependent concept**, OR to modify a shared abstraction. A shared abstraction is a data structure, helper interface, or constants set estimated to be referenced by at least 2 distinct files other than the one under change. The file-count trigger is scoped to *one interdependent concept scattered across files*, NOT raw file count: genuinely-independent multi-file changes (parallel doc updates, independent script tweaks) SHALL NOT trigger the hard gate — they remain `Simple` via the Layer 1 "Multi-file but each file independent" disqualifier. The hard gate SHALL only escalate: when it does not trigger, routing SHALL fall through to the existing Layer P disjunctive any-match evaluation with the `Simple` default preserved. The hard gate SHALL NOT invert the default tier to `Plan`.

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


<!-- @trace
source: reshape-plan-preimpl-tier
updated: 2026-07-08
code:
  - plugins/issue-driven-dev/skills/.impeccable/hook.cache.json
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