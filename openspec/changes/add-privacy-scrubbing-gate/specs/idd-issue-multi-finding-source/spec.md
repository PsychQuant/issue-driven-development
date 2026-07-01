## MODIFIED Requirements

### Requirement: Stage 4 SHALL dispatch with warn-continue and write JSONL audit trail

In Stage 4, the skill SHALL execute each routing decision sequentially. Each dispatch action (`create` / `comment` / `edit`; no-op for skip) SHALL be issued through the `scripts/gh-egress.sh` privacy-scrubbing choke-point wrapper (`bash scripts/gh-egress.sh create|comment|edit …`), NOT via raw `gh issue create/comment/edit`. Each drafted action body SHALL therefore pass the repo-aware privacy-scrubbing gate before dispatch. For each action:

1. On success, the skill SHALL append the action to the JSONL log with success metadata (issue_url, comment_url, duration_ms)
2. On failure, the skill SHALL NOT abort. The skill SHALL log the error in the JSONL `actions[i].error` field with a `retry_hint` field suggesting manual recovery, then continue to the next action.
3. After all actions complete (success or failure), the skill SHALL print a summary: `N succeeded, M failed (see jsonl), K skipped`

A dispatch action that the privacy-scrubbing gate blocks at ENFORCE strictness (unconfirmed redaction) SHALL be treated as a non-dispatched action for that finding (recorded with a gate-block reason), and SHALL NOT abort the remaining actions — consistent with the warn-continue contract.

The skill SHALL NOT attempt rollback of successful actions when subsequent actions fail.

#### Scenario: Successful dispatch writes complete JSONL

- **WHEN** Stage 4 dispatches 5 actions and all succeed
- **THEN** JSONL file at `.claude/.idd/issue-runs/<run_id>.jsonl` contains 5 action entries
- **AND** summary prints `5 succeeded, 0 failed, 0 skipped`

#### Scenario: Mid-stream failure does not abort

- **WHEN** Stage 4 dispatches 5 actions, the 3rd fails (e.g., GitHub API rate limit)
- **THEN** actions 1, 2 are dispatched and recorded as success
- **AND** action 3 is recorded with `error: "<api error message>"` and `retry_hint`
- **AND** actions 4, 5 are still attempted and recorded
- **AND** summary prints with the failure count

#### Scenario: Each dispatch action routes through the egress gate

- **WHEN** Stage 4 dispatches any `create` / `comment` / `edit` action
- **THEN** it SHALL invoke `bash scripts/gh-egress.sh <verb> …` rather than raw `gh issue <verb> …`
- **AND** the drafted body SHALL pass the privacy-scrubbing self-review before dispatch
- **AND** a body blocked at ENFORCE without confirmation SHALL be recorded as non-dispatched for that finding without aborting the remaining actions
