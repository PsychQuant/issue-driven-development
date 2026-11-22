## ADDED Requirements

### Requirement: A run with a stop mode leaves a record of how its verify loop ended

When `/idd-all` runs with a stop mode and `close-stage.py next` answers anything other than `fix`, the Phase 4 block that runs `next` SHALL append one JSON line to the stop-mode record through `scripts/stop-mode-log.py append`. The line SHALL carry the repository, the issue, the run's `created_at`, the mode, the decision, whether it merges, `decided`, the reason, and every recorded round with its status, Blocking count, In-scope count and report id. The record file SHALL be `~/.claude/.idd/stop-mode-runs.jsonl` unless `IDD_STOP_LOG` names another path, outside every repository. A run without a stop mode, a `fix` answer, or a run with no readable run state SHALL write nothing. A failed append SHALL print a warning and SHALL NOT change the run. `stop-mode-log.py summary` SHALL group the records by mode, taking the last line written for each (repository, issue, `created_at`).

#### Scenario: A stop answer of a run with a stop mode is recorded once per run

- **GIVEN** a run with stop mode `exhaustive-blocking` and one recorded round
- **WHEN** `next` answers stop, and is asked again with the same answer
- **THEN** the record has two lines for the run and `summary` counts the run once

##### Example: what append writes

| Run | `next` answer | Lines appended |
| --- | --- | --- |
| stop mode `early`, one round | stop, merge true | 1 |
| stop mode `exhaustive-blocking`, two rounds | stop, merge false | 1 |
| stop mode `exhaustive-blocking` | fix | 0 |
| no stop mode | stop | 0 |
| no run state | stop, undecided | 0 |

#### Scenario: A failed append does not change the run

- **GIVEN** a record path that cannot be written
- **WHEN** the Phase 4 `next` block runs
- **THEN** it prints a warning, `NEXT_JSON` and `NEXT_RC` are the answer of `next`, and the block's own result is unchanged
