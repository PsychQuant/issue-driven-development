## ADDED Requirements

### Requirement: North-star tracker roadmap-checklist format

A north-star tracker issue (carrying the `north-star` label) SHALL carry a `## Roadmap` section containing an ordered checklist of stages. An UNFILED stage SHALL be an unchecked item that contains no issue reference (e.g. `- [ ] Stage 2: transfers`). A FILED stage SHALL be a checked item that links its own issue with a trailing reference (e.g. `- [x] Stage 1: core → #7`). The presence of the `#<number>` reference on a roadmap item is the canonical signal that the stage has emerged into a filed issue; its absence means the stage is roadmap-only and not yet filed.

#### Scenario: roadmap with one stage filed and two pending

- **WHEN** a north-star tracker's `## Roadmap` lists Stage 1 as a checked item linking an issue and Stages 2 and 3 as unchecked items with no issue reference
- **THEN** Stage 1 is treated as filed (emerged) and Stages 2 and 3 are treated as roadmap-only (not yet emerged)

##### Example: counting filed vs roadmap-only stages

- **GIVEN** a `## Roadmap` containing `- [x] Stage 1: core → #7`, `- [ ] Stage 2: transfers`, and `- [ ] Stage 3: realtime`
- **WHEN** the roadmap is parsed
- **THEN** the filed count is 1 (Stage 1 → #7) and the total is 3, yielding progress `1/3 stages`

### Requirement: Progressive file-on-start emergence

A north-star stage SHALL be filed as its own GitHub issue — running the full IDD lifecycle — only when work on that stage begins, NOT at tracker-creation time. When a stage is filed, the tracker's corresponding roadmap item SHALL be updated to a checked item linking the new issue. This progressive emergence is the defining difference from `idd-issue --bundle-mode`, which files all children upfront at epic-creation time; a north-star roadmap MUST be able to grow stage by stage without listing every child in advance.

#### Scenario: a pending stage is started and filed

- **WHEN** Stage 2 of a north-star tracker begins and is filed as issue #42
- **THEN** the tracker's `## Roadmap` item for Stage 2 is updated from an unchecked, unreferenced bullet to `- [x] Stage 2: <description> → #42`, and no stage beyond Stage 2 is required to have been filed in advance

### Requirement: idd-list tracker-phase display

When `idd-list` encounters an open issue carrying a tracker label (`north-star` or `epic`), it SHALL display a `tracking` phase instead of `(no phase)` and SHALL NOT suggest running `/idd-update` on that issue. When the issue body contains a parseable `## Roadmap` checklist, `idd-list` SHALL additionally show roadmap progress as `<filed>/<total> stages`, where `<filed>` is the number of checked items carrying an `#<number>` reference and `<total>` is the number of roadmap items. This same display rule SHALL apply to milestone-tracked epic trackers surfaced by the milestone-first SOP (issue-driven-development#83), so the tracker-phase fix is shared rather than north-star-specific.

#### Scenario: north-star tracker is listed without no-phase noise

- **WHEN** `idd-list` lists an open issue labeled `north-star` whose body has a `## Roadmap` with one filed and two pending stages
- **THEN** the issue is shown with a `tracking` phase and roadmap progress `1/3 stages`, and the output does NOT show `(no phase)` or a `/idd-update` suggestion for that issue

##### Example: tracker display string

- **GIVEN** open issue #7 labeled `north-star` with a `## Roadmap` of `- [x] Stage 1 → #10`, `- [ ] Stage 2`, `- [ ] Stage 3`
- **WHEN** `idd-list` derives its phase line
- **THEN** #7 is displayed as `[tracking] 1/3 stages` rather than `(no phase)` with an idd-update hint
