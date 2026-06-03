## Why

IDD has no first-class convention for an **ordered, progressively-emerging multi-stage roadmap** (a "north-star" epic). Two existing multi-issue mechanisms each miss it: `--bundle-mode` (idd-issue) requires ALL children to be filed upfront, but later stages are not designed until earlier stages ship; milestone-first (#83) is a flat, unordered grouping of issues that all already exist. The motivating real case is PsychQuant/che-transport-mcp#7, where a routing-engine north-star naturally split into Stage 1 / 2 / 3 — Stage 1 shipped, but Stages 2/3 could only be prose notes because IDD had no structured way to track "a roadmap whose stage-issues are filed over time". Tracked as PsychQuant/issue-driven-development#179; design converged in a spectra-discuss conclusion on that issue.

## What Changes

- A documented **North-star tracker SOP**: a persistent tracker issue carrying a roadmap checklist where an UNFILED stage is a plain bullet and a FILED stage is a checked bullet linking to its issue. The presence or absence of the issue link is the "emerged vs not-yet" state, so a roadmap can grow stage by stage without the upfront-all-children constraint that `--bundle-mode` imposes.
- A **shared idd-list tracker-phase display rule**: an issue recognized as a tracker (by a tracker label such as north-star or epic) is shown with a tracking-oriented status (and roadmap progress when derivable) instead of the misleading no-phase state plus a false suggestion to run idd-update. This same rule also serves the milestone-tracked epics of #83.

## Non-Goals (optional)

- No new flag or skill now. An idd-issue stage-of flag that auto-edits the tracker is explicitly deferred until the rule-of-three (3 independent real cases) fires; today there is only one real case.
- Not merging or superseding #83 (flat milestone grouping) or #81 (bundle-to-chain, upfront children). North-star is the distinct ordered + progressive cell of the multi-issue-structure design space; the three are complementary.
- No change to the bundle-creation flags themselves; only a cross-reference is added so authors can find the progressive alternative.

## Capabilities

### New Capabilities

- `north-star-tracker`: the roadmap-checklist tracker convention plus the idd-list tracker-phase display rule for ordered, progressively-emerging multi-stage epics.

### Modified Capabilities

(none)

## Impact

- Affected specs: new capability north-star-tracker
- Affected code:
  - New: plugins/issue-driven-dev/references/north-star-tracker.md
  - Modified: plugins/issue-driven-dev/skills/idd-list/SKILL.md
  - Modified: plugins/issue-driven-dev/references/bundle-flags.md
