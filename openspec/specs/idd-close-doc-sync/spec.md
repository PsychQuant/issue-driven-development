# idd-close-doc-sync Specification

## Purpose

Defines when `/idd-close` runs its doc-sync sweep, the check of README and CLAUDE.md files for content the closed issue made stale: after the issue is closed and its closing summary is posted. It exists so that the places in `skills/idd-close/SKILL.md` that state this position cannot drift apart again.

## Requirements

### Requirement: The doc-sync sweep runs after the issue is closed

`/idd-close` SHALL run the doc-sync sweep (Step 6.3) only when the issue is closed and its closing summary is posted: after the step that posts the summary and closes the issue (Step 4), after the body sync (Step 6), and before the distribution sync (Step 6.5). `skills/idd-close/SKILL.md` states where the sweep sits in three places: the order of its step sections, the order of the stage task list of Step 0.5, and the sentence of Step 6.3 that states the position. The step sections and the task list SHALL both place the sweep after the close and the body sync and before the distribution sync. The sentence SHALL say that the issue is already closed and SHALL NOT say that the sweep comes before the issue is closed.

No executable check: the steps are carried out by a model that follows SKILL.md, so the order in which a run actually takes them is not checked. The Example checks the text the model follows.

#### Scenario: A close reaches the doc-sync sweep

- **GIVEN** `/idd-close` has posted the closing summary and closed the issue
- **WHEN** it reaches Step 6.3
- **THEN** the issue is already closed and its closing summary is already posted, so nothing the sweep finds holds the close back

##### Example: where the doc-sync sweep sits in idd-close

| `skills/idd-close/SKILL.md` | The check |
| --- | --- |
| as shipped | passes |
| the position sentence of Step 6.3 says the sweep comes before `gh issue close` | fails on the sentence |
| the position sentence of Step 6.3 does not say that the issue is closed | fails on the sentence |
| Step 6.3 has no position sentence | fails on the sentence |
| the Step 6.3 section is placed before Step 4 | fails on the step order |
| the Step 6.3 section is placed after Step 6.5 | fails on the step order |
| the task list names `doc_sync_sweep` before `publish_and_close` | fails on the task order |
| the task list names `doc_sync_sweep` after `distribution_sync_chain_detection` | fails on the task order |
