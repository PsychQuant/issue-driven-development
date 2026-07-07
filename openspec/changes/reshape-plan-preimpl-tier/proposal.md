## Why

IDD's Plan / pre-implementation tier has three ratified gaps (user decisions 2026-07-07, issues #129 / #57 / #111). (1) Complexity routing's Layer P is purely advisory disjunctive any-match — large multi-file / shared-abstraction changes can silently route Simple and be under-planned (empirically #44 / #47: one conceptual change scattered across three artifacts, missed by a single Plan pass, needing two closes to fully cover). (2) Meeting / deliberation issues are forced through a code-centric pipeline (Strategy = Files & Changes, closing = TDD verify) that does not fit user-driven decision work. (3) Pre-implementation staging (brainstorm → written plan) has no home in IDD, and #209 already made superpowers a hard dependency — so the correct move is delegation, not a self-built equivalent.

## What Changes

- **#129 — complexity hard gate**: Layer P keeps its current disjunctive any-match "may trigger" behavior; on top of it, a **MUST-trigger hard gate** forces Plan tier when a change touches ≥ N files or modifies a shared abstraction (a data structure / helper interface / constants set used by multiple callers). The Simple default is preserved for everything else — the gate escalates, it does NOT invert the default to Default-Plan.
- **#57 — explicit meeting issue type**: add `meeting` to the issue-type taxonomy alongside bug / feature / refactor / docs. `/idd-diagnose` emits a Phase A/B/C Strategy template (deliberation deliverables, not code Files & Changes) for `type=meeting`; `/idd-plan` detects `type=meeting`, uses a meeting-adapted Plan body, and skips the Step 6 chain to `/idd-implement`; closing semantics become a decision→action mapping with no `/idd-verify` TDD pass.
- **#111 — delegate pre-implementation staging to superpowers**: add an IDD ↔ superpowers stage-mapping table to the plugin README (marking the verify ensemble and close audit trail as IDD-unique), and a hand-off hint in `/idd-issue` Step 5 and `/idd-diagnose` pointing design-heavy issues at superpowers:brainstorming. No new idd-brainstorm / idd-write-plan skill is created — self-building would be a forbidden vendored fork under the deep-integration-over-hardcode rule.

Coupling: #129's hard gate and #57's meeting branch both alter `/idd-diagnose` Step 3.5 routing, so they are designed together in this one change to avoid a double or conflicting verdict path.

## Capabilities

### New Capabilities

- `complexity-hard-gate`: MUST-trigger escalation layered above Layer P that forces Plan tier on ≥ N-file or shared-abstraction changes, while preserving the Simple default elsewhere.
- `meeting-issue-type`: first-class `meeting` issue type with a deliberation-shaped diagnose Strategy template, a meeting-adapted plan body that skips the implement chain, and decision→action closing semantics.

### Modified Capabilities

- `superpowers-integration`: add a pre-implementation staging hand-off requirement — README stage-mapping table plus diagnose / issue hand-off pointers to superpowers:brainstorming, with no self-built staging skill.

## Impact

- Affected specs: `complexity-hard-gate` (new), `meeting-issue-type` (new), `superpowers-integration` (modified)
- Affected code:
  - Modified:
    - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md (Step 3.5 routing — #129 hard gate + #57 meeting Strategy template branch)
    - plugins/issue-driven-dev/skills/idd-plan/SKILL.md (#57 meeting-adapted Plan body + skip Step 6 chain to implement)
    - plugins/issue-driven-dev/skills/idd-issue/SKILL.md (#57 add meeting to the type taxonomy; #111 hand-off hint at Step 5)
    - plugins/issue-driven-dev/skills/idd-close/SKILL.md (#57 meeting decision→action closing semantics — no /idd-verify TDD pass)
    - plugins/issue-driven-dev/rules/sdd-integration.md (#129 Layer P hard-gate definition)
    - plugins/issue-driven-dev/README.md (#111 IDD ↔ superpowers stage-mapping table)
  - New:
    - openspec/specs/complexity-hard-gate/spec.md (on archive)
    - openspec/specs/meeting-issue-type/spec.md (on archive)
  - Removed: (none)
