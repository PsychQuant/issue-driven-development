## Problem

Verify round 6 of #480 found that a Plan-tier approval does not cover the change that is applied. `spectra-propose` parks the change, and a parked change's files are not in the changes directory, so `idd-plan` had nothing to read when it was told to attach the change's files to the plan (with Spectra 3.0.0, `spectra show` prints the proposal and the tasks but only the paths of the spec delta). A revision in plan mode changed only the Implementation Plan comment, so `idd-implement` applied the tasks the maintainer had asked to change.

## Root Cause

`idd-plan` presented the plan comment and assumed the change's files were readable in place; nothing tied a revision to the change's own files.

## Proposed Solution

Before plan mode, `idd-plan` runs one bash block: it takes the change out of the parked state if it is parked, reads the change directory from `spectra instructions apply --json`, and stops when the proposal, the tasks or a spec delta is missing; plan mode shows those files verbatim after the plan. A revision is made in the change's files and checked with `spectra validate` before the plan is rebuilt from them and shown again. An abort parks the change again. Two small items in the same area: `idd-implement`'s note that still asks the Plan question a second time, and the step-3 stop message that names the wrong change when the plan names another one.

## Non-Goals

The other in-scope MEDIUM and LOW findings of round 6 (items 2, 4, 5, 6, 8, 9, 10) go to a follow-up issue, per the maintainer's decision of 2026-11-11 for rounds from 6 on.

## Success Criteria

The step-3.5 block, run with a stand-in `spectra`, prints the change directory and its files for a parked and for an active change, unparks only a parked one, and stops when unpark or `spectra instructions` fails or a file is missing. The new text checks fail before the change and pass after it.

## Impact

- Affected code:
  - Modified: plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - Modified: plugins/issue-driven-dev/references/spec-wrapper.md
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-wrapper-contract/test.sh
