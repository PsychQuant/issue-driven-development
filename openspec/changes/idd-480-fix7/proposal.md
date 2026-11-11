## Problem

Verify round 7 of #480 found that a revision asked for in plan mode cannot be made in the change's files: after "No, keep planning" the session stays in plan mode, where file edits stay blocked until the plan is approved (Claude Code permission-modes documentation). Rounds 4 to 7 each found a HIGH in the same place, the attended Plan tier where `idd-plan` approves the Spectra proposal in plan mode, a path that was only contract-tested.

## Root Cause

Approving the proposal in plan mode needs the approved files to be the applied files, which needs edits outside plan mode and a binding between the two; each round added a piece of that and the next round broke on the new piece.

## Proposed Solution

Per the maintainer's decision of 2026-11-11 (comment 6785887652), the attended Plan tier approves the Implementation Plan in plan mode as before #480 and does not propose. Which phase of `idd-all` invokes which skill stays in the dispatch table of `skills/idd-all/SKILL.md`; this change only constrains what `idd-plan` and `idd-implement` do once invoked. Before plan mode `idd-plan` writes `**Spec plan**: proposed (change idd-<N>-<slug>)`, on approval `change <name>`, and hands the name to `idd-implement`, which proposes in the light form and applies, as in the Simple tier. Step 3.5, the `rejected` form and the fix4 to fix6 text about presenting the change's files are removed; the Revised and Aborted rows of `idd-plan` go back to their wording before #480. Approving the proposal itself in plan mode moves to #497.

## Non-Goals

Approving the proposal in plan mode with a content binding (#497). The plan-mode limits of the Revised and Aborted rows that existed before #480 are recorded in #497.

## Success Criteria

`idd-plan` has no call to `spectra-propose` and no Step 3.5; `spec-change.py plan` reads a `rejected` line as `invalid`; contract step 3 has no `rejected` branch; `idd-implement` proposes with the name from the approved plan when it comes from `idd-plan`. The new checks fail before the change and pass after it.

## Impact

- Affected code:
  - Modified: plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - Modified: plugins/issue-driven-dev/references/spec-wrapper.md
  - Modified: plugins/issue-driven-dev/rules/sdd-integration.md
  - Modified: plugins/issue-driven-dev/scripts/spec-change.py
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-change/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-wrapper-contract/test.sh
