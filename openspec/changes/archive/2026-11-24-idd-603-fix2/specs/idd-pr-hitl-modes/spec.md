## MODIFIED Requirements

### Requirement: A run with a stop mode leaves a record of how its verify loop ended

When `/idd-all` runs with a stop mode and `close-stage.py next` answers anything other than `fix`, the Phase 4 block that runs `next` SHALL append one JSON line to the stop-mode record through `scripts/stop-mode-log.py append`. The line SHALL carry the repository, the issue, the run's `created_at`, the mode, the decision, whether `next` answered merge (`next_merge`; not whether the run merged, because the close stage can still stop it), `decided`, the reason, and every recorded round with its status, Blocking count, In-scope count and report id. The record file SHALL be `~/.claude/.idd/stop-mode-runs.jsonl` unless `IDD_STOP_LOG` names another path, outside every repository. A run without a stop mode, a `fix` answer, a run with no readable run state, or a run another `/idd-all` replaced (`replaced` in `next`'s answer or in the gate's answer, which the Phase 4 block passes to `append` with `--gate`) SHALL write nothing, because a replaced run no longer owns the run state on disk. An empty `--gate` means the gate's answer was lost between the two Bash calls; `append` SHALL then write nothing and say so on stderr, and the Phase 4 block SHALL tell the model to restore `GATE_JSON` from the gate block's output first. A run replaced earlier, before its gate read the run state, cannot be told apart this way; telling it apart needs the run's identity from its own init (#618). The record file SHALL be created with mode 0600, and a symbolic link at its path SHALL NOT be followed (the append fails and only warns). A failed append SHALL print a warning and SHALL NOT change the run. `stop-mode-log.py summary` SHALL group the records by mode, taking the last line written for each (repository, issue, `created_at`), and SHALL count merge answers as such, not as merged runs. A line that parses as JSON but is not shaped like a line `append` writes (no string `mode`, `rounds` not a list of objects, a `reason` that is not text, or a key that cannot be compared), and a line that is not UTF-8, SHALL be counted as unreadable, not stop `summary`; the text output SHALL print the mode, each to-fix sequence and each reason with their control characters (C0 and C1) escaped.

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
| stop mode `early`, `next` answered `replaced` | stop, undecided | 0 |
| stop mode `early`, the gate answered `replaced`, `next` answered without the flag | stop, undecided | 0 |
| stop mode `early`, the gate's answer lost (`--gate ''`) | stop, undecided | 0 |

#### Scenario: A failed append does not change the run

- **GIVEN** a record path that cannot be written
- **WHEN** the Phase 4 `next` block runs
- **THEN** it prints a warning, `NEXT_JSON` and `NEXT_RC` are the answer of `next`, and the block's own result is unchanged

#### Scenario: The summary does not claim a merge

- **GIVEN** a record whose `next` answered stop with merge true
- **WHEN** `summary` is run
- **THEN** it counts one merge answer for the mode, says `next answered merge`, and has no `merged` count

