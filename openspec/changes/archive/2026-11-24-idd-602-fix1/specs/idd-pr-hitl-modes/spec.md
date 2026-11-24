## MODIFIED Requirements

### Requirement: A configured stop mode decides when the fix loop stops and whether the run merges

A run has a stop mode when the `--stop <mode>` flag of `idd-all`, or else the `verify_stop.mode` field of the resolved IDD config, names one of `early`, `exhaustive-blocking` or `exhaustive-all`. The flag takes precedence over the config. A flag with any other value SHALL stop `idd-all` before Phase 1 with a message naming the three values; so SHALL a `--stop` given more than once, and a bare `--stop` followed by another flag, which is never taken as its value. A config value outside the three SHALL be treated as no stop mode, and `idd-all` SHALL print one line saying so. The resolved mode, or its absence, SHALL be written into the run-state record when the mode is resolved and SHALL be read from there afterwards.

Each time `close-stage.py gate` reads a verify report that has not been read in this run, it SHALL append one round to the round record of the run-state record: the round number, the reviewed commit, and the counts `blocking`, `in_scope` and `low_in_scope`. Reading the same report again SHALL NOT add a round. The to-fix count of a round is `blocking + in_scope - low_in_scope`; for a run that carries `--review` or `--in-chain` it is `blocking`.

After each round of a run with a stop mode, `idd-all` SHALL ask `close-stage.py next` whether to fix and verify again, and SHALL follow its answer; the model SHALL NOT decide this itself. `next` SHALL answer from the mode and the round record only:

| Mode | Stops when | Merges on that stop |
|---|---|---|
| `early` | the to-fix count is 0, or, from round 2 on, it is not lower than the previous round's | when `blocking` is 0 |
| `exhaustive-blocking` | `blocking` is 0, or `blocking` was not lower than the previous round's in each of the last two rounds | when `blocking` is 0 |
| `exhaustive-all` | `blocking` is 0 and `in_scope` is 0, LOW findings included; for a run that carries `--review` or `--in-chain`, `blocking` is 0 | always |

In every mode `next` SHALL answer stop without merging when the latest gate result is `unparseable` or holds a Rejected finding, and `exhaustive-all` has no round limit. A gate result read for a run whose run-state record was replaced while the gate was reading SHALL NOT be recorded: `init` writes a random `run_id`, every write and the deletion of the run state (by `init`, by the gate, by `next`'s fix answer and by `reset`) holds one per-issue lock, and the gate compares the `created_at` and `run_id` it read at its start with the record inside that lock. A gate result refused because the run state was replaced SHALL carry `replaced: true`, and so SHALL a `next` answer whose fix answer was refused for that reason; Phase 4 SHALL stop the run on either, with or without a stop mode, and SHALL NOT count, fix or push another round. A run-state record without a `verify_stop` field, or with a value that is not `null` or one of the three modes, SHALL be refused by `next` and by the close stage, never read as no stop mode. Reading the gate and `next` to write the PR body or the run report SHALL use their read-only form, which SHALL NOT change the round record or the fix answers: a report that appears after Phase 4 stopped is not a round, and the close stage does not merge on it. A gate result that `next` has already answered with fix (the same report on the same commit, or no report on the same commit) SHALL be answered stop without merging, in every run with or without a stop mode: a new round brings a new commit or a new report, and a round whose result was not recorded does not reuse the previous answer. When a finding to be fixed is a security vulnerability, `idd-all` SHALL stop without merging instead of fixing it, as for a run without a stop mode. When the run stops with a merge and findings remain, `idd-all` SHALL NOT change the branch for them: the commit that merges is the commit the last round reviewed, and the remaining findings SHALL be filed together as one follow-up issue. A merge allowed by this table SHALL require the Blocking, In-scope fix and LOW counts of the report the close stage re-reads to equal those of the last recorded round, and passes the same guardrails as a clean merge, including a complete coverage line and a complete reviewers line, which the verify gate SHALL read for every verdict, and it SHALL NOT leave an In-scope fix finding of severity CRITICAL, HIGH, P0 or P1 unfixed: the verify gate SHALL report their number, and the close stage itself SHALL refuse such a merge; a run with `--review` or `--in-chain`, or of type `meeting`, never merges.

With a stop mode, an attended run SHALL fix findings and verify again as an unattended run does, and SHALL ask the user only where a sub-skill asks in attended interaction; without a stop mode it hands the findings back as before. The run report SHALL state the stop mode, the number of rounds, the to-fix count of each round, and the reason `next` gave for stopping.

#### Scenario: early stops when the count stops falling and merges with no Blocking

- **GIVEN** a run with stop mode `early`
- **AND** rounds 1, 2 and 3 have to-fix counts 6, 4 and 4, and round 3 has 0 Blocking
- **WHEN** `close-stage.py next` runs after round 3
- **THEN** it answers stop with merge, giving the reason that the to-fix count did not fall (4 → 4)
- **AND** `idd-all` merges the commit round 3 reviewed and files one follow-up issue listing the 4 findings

#### Scenario: early stops with Blocking and does not merge

- **GIVEN** a run with stop mode `early`
- **AND** rounds 1 and 2 have to-fix counts 3 and 3, and round 2 has 1 Blocking
- **WHEN** `close-stage.py next` runs after round 2
- **THEN** it answers stop without merge, and the run stops at verified

#### Scenario: exhaustive-blocking reaches zero Blocking

- **GIVEN** a run with stop mode `exhaustive-blocking`
- **AND** rounds 1, 2 and 3 have `blocking` 2, 1 and 0, and round 3 has 3 In-scope fix findings
- **WHEN** `close-stage.py next` runs after round 3
- **THEN** it answers stop with merge, and the 3 findings are filed as one follow-up issue

#### Scenario: exhaustive-blocking stops when Blocking does not fall twice

- **GIVEN** a run with stop mode `exhaustive-blocking`
- **AND** rounds 1, 2 and 3 have `blocking` 2, 2 and 2
- **WHEN** `close-stage.py next` runs after round 3
- **THEN** it answers stop without merge; after round 2 it had answered fix

#### Scenario: exhaustive-all keeps going until nothing is left

- **GIVEN** a run with stop mode `exhaustive-all`
- **AND** round 6 has 0 Blocking and 1 In-scope fix finding that is LOW
- **WHEN** `close-stage.py next` runs after round 6
- **THEN** it answers fix
- **AND** when round 7 has 0 Blocking and 0 In-scope fix, it answers stop with merge

#### Scenario: A stop-mode merge needs a complete coverage line

- **GIVEN** a run with stop mode `early` whose rounds 1 and 2 each report 0 Blocking and 2 MEDIUM In-scope fix findings
- **AND** round 2's report says `3 / 5 requirements addressed`
- **WHEN** the close stage runs
- **THEN** it stops without merging, and the reason names the coverage line

#### Scenario: The same report read twice is one round

- **GIVEN** a run whose round record holds 2 rounds
- **WHEN** `close-stage.py gate` reads round 2's report again
- **THEN** the round record still holds 2 rounds

#### Scenario: Flag over config, and values outside the three

- **GIVEN** the config sets `verify_stop.mode` to `early`
- **WHEN** `idd-all` runs with `--stop exhaustive-all`, with `--stop fast`, and, in another repository whose config sets the mode to `fast`, with no flag
- **THEN** the first run has stop mode `exhaustive-all`; the second stops before Phase 1 and names `early`, `exhaustive-blocking` and `exhaustive-all`; the third prints one line and runs without a stop mode

#### Scenario: An attended run with a stop mode fixes on its own

- **GIVEN** resolved interaction is `attended` and stop mode `early`
- **AND** verify round 1 reports 1 Blocking finding that is not a security vulnerability
- **WHEN** Phase 4 evaluates the result
- **THEN** `idd-all` fixes the finding, runs verify round 2, and asks `close-stage.py next` again

<!-- @trace
source: verify-stop-modes
updated: 2026-11-21
code:
  - plugins/issue-driven-dev/scripts/close-stage.py
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - plugins/issue-driven-dev/scripts/verify-gate.py
  - plugins/issue-driven-dev/references/config-protocol.md
  - plugins/issue-driven-dev/scripts/lib/stopmode.py
tests:
  - plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh
-->

#### Scenario: A result already answered with fix stops the loop

- **GIVEN** a run with stop mode `early` whose round 1 has to-fix count 3, and `next` answered fix for it
- **WHEN** the next verify round posts no report and makes no commit, and the gate reads round 1's report again
- **THEN** `next` answers stop without merging, and the reason says that no new report or commit followed the fix answer

#### Scenario: A serious In-scope finding left unfixed is not merged

- **GIVEN** a run with stop mode `early` whose rounds 1 and 2 each report 0 Blocking and 2 In-scope fix findings, one of them HIGH
- **WHEN** the close stage runs after round 2
- **THEN** it stops without merging, and the reason names the HIGH In-scope fix finding

#### Scenario: exhaustive-all with --review counts Blocking only

- **GIVEN** a run with stop mode `exhaustive-all` that carries `--review`
- **AND** its round 1 has 0 Blocking and 2 In-scope fix findings
- **WHEN** `close-stage.py next` runs
- **THEN** it answers stop without merging, and the reason says the round has no Blocking finding

<!-- @trace
source: idd-595-fix1
updated: 2026-11-22
code:
  - plugins/issue-driven-dev/scripts/lib/stopmode.py
  - plugins/issue-driven-dev/scripts/verify-gate.py
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - plugins/issue-driven-dev/scripts/close-stage.py
tests:
  - plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh
-->

#### Scenario: The PR body reads the gate without recording a round

- **GIVEN** a run with stop mode `early` that stopped without a merge after round 2
- **AND** a new verify report appears on the same commit before Phase 5
- **WHEN** Phase 5 reads the gate and `next` in their read-only form to write the PR body
- **THEN** the round record still holds 2 rounds and `next` still answers stop
- **AND** the close stage stops without merging, because the newest report is not the round the stop mode judged

<!-- @trace
source: idd-595-fix4
updated: 2026-11-22
code:
  - plugins/issue-driven-dev/scripts/close-stage.py
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
tests:
  - plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh
-->

#### Scenario: A replaced run is not recorded, even within the same second

- **GIVEN** a gate that started reading for a run, and another `init` that replaced the run state with the same `created_at` before the gate recorded its round
- **WHEN** the gate records its result
- **THEN** nothing is written, and the gate answers `unparseable`

##### Example: the run state is identified and locked

| Situation | Result |
| --- | --- |
| the record has the gate's `created_at` and `run_id` | the round is recorded |
| same `created_at`, another `run_id` | refused: the run state was replaced |
| another process holds the run-state lock | the writer waits for it; a second exclusive lock cannot be taken |
| the record has no `verify_stop` field | `next` answers stop, undecided; the close stage stops |

#### Scenario: A replaced run stops

- **GIVEN** a run whose state another `/idd-all` replaced while its gate or its `next` was running
- **WHEN** Phase 4 reads the answers
- **THEN** the gate's or next's answer carries `replaced: true`, and Phase 4 stops without fixing

##### Example: replaced is marked and stops the run

| Situation | Answer | Phase 4 |
| --- | --- | --- |
| the gate read for a run whose `run_id` is no longer on disk | gate unparseable, `replaced: true` | stops |
| `next` re-reads a record with another `run_id` before writing its fix answer | stop, undecided, `replaced: true` | stops |
| `reset` while another process holds the run-state lock | waits for the lock, then deletes | — |

### Requirement: Unattended fix loop covers in-scope findings with a two-round limit

This requirement applies to a run without a stop mode; a run with one follows requirement "A configured stop mode decides when the fix loop stops and whether the run merges". When the resolved interaction is `unattended` and the verify gate reports `not_clean`, `idd-all` SHALL fix every Blocking finding, and every In-scope fix finding unless the run carries `--review` or `--in-chain` (those runs never merge and keep the Blocking-only scope), in the same branch and run verify again, for at most 2 verify rounds in total (one fix pass between them). The number of rounds already run SHALL be read from the run-state record, not from the model's memory; every new commit the verify gate judged, and every new report on the same commit, counts as one round, also when its report was missing or could not be read or the fix pass made no commit. The close stage SHALL stop, without merging, an unattended run without a stop mode whose record holds more than 2 rounds, or whose newest verify report is not in the record, an empty record included, or whose record holds fewer attempts than rounds. When the run-state record cannot be read, or `next` answers undecided (its printed answer carries `decided: false`, for example before any gate result was recorded), a run without a stop mode SHALL count its rounds itself, as before the record existed, and from that round on SHALL keep counting itself for the rest of the run, not taking `next`'s count again (next counts only the rounds it recorded); the run stops at its own limit. A run that took this count does not merge before its own count reaches its stop, and never after more verify rounds than the limit. If the gate still reports `not_clean` after the second verify round, `idd-all` SHALL stop at verified without merging or closing. When the resolved interaction is `attended`, `idd-all` SHALL NOT fix findings automatically; it SHALL hand the findings back to the user, and merge and close only follow a later round that the gate reports `clean`. When the gate reports `clean` with `low_in_scope` above zero, `idd-all` SHALL NOT change the branch for those findings (the commit that merges is the commit the round reviewed); it SHALL file them together as one follow-up issue before the close stage.

#### Scenario: Second round comes back clean

- **GIVEN** resolved interaction is `unattended`
- **AND** verify round 1 reports 0 Blocking and 2 In-scope fix findings
- **WHEN** `idd-all` fixes both findings and runs verify round 2, which reports 0 Blocking and 0 In-scope fix
- **THEN** the gate reports `clean` and the run proceeds to merge and close

#### Scenario: Second round still has an in-scope finding

- **GIVEN** resolved interaction is `unattended`
- **AND** verify round 2 reports 0 Blocking and 1 In-scope fix finding
- **WHEN** the fix loop checks its round count
- **THEN** `idd-all` stops at verified, does not merge, and the run report lists the remaining finding under `Stopped:`

#### Scenario: A clean round with LOW in-scope findings

- **GIVEN** verify round 1 says PASS with 0 Blocking and 2 In-scope fix findings, both LOW
- **WHEN** Phase 4 reads the gate
- **THEN** the gate reports `clean` with `low_in_scope` 2, `idd-all` makes no fix commit, files one follow-up issue listing both findings, and proceeds to the close stage with the reviewed commit

#### Scenario: Attended run with findings

- **GIVEN** resolved interaction is `attended`
- **AND** verify reports 1 Blocking finding
- **WHEN** Phase 4 evaluates the result
- **THEN** `idd-all` reports the finding to the user and makes no automatic fix commit

#### Scenario: A third round is caught by the close stage

- **GIVEN** an unattended run without a stop mode whose round record holds 3 verify rounds
- **AND** the third round's gate result is `clean`
- **WHEN** the close stage runs
- **THEN** it stops without merging, and the reason names the two-round limit


<!-- @trace
source: verify-stop-modes
updated: 2026-11-21
code:
  - plugins/issue-driven-dev/scripts/close-stage.py
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - plugins/issue-driven-dev/scripts/verify-gate.py
  - plugins/issue-driven-dev/references/config-protocol.md
  - plugins/issue-driven-dev/scripts/lib/stopmode.py
tests:
  - plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh
-->

#### Scenario: An empty round record does not merge

- **GIVEN** a run without a stop mode whose round record is empty
- **AND** the newest verify report on the issue is clean
- **WHEN** the close stage runs
- **THEN** it stops without merging, and the reason says that Phase 4 never judged the report


<!-- @trace
source: idd-595-fix1
updated: 2026-11-22
code:
  - plugins/issue-driven-dev/scripts/lib/stopmode.py
  - plugins/issue-driven-dev/scripts/verify-gate.py
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - plugins/issue-driven-dev/scripts/close-stage.py
tests:
  - plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh
-->


<!-- @trace
source: idd-595-fix4
updated: 2026-11-22
code:
  - plugins/issue-driven-dev/scripts/close-stage.py
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
tests:
  - plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh
-->

#### Scenario: An undecided next keeps the fix round of a run without a stop mode

- **GIVEN** a run without a stop mode whose first gate could not write the round record
- **WHEN** `next` answers stop with `decided: false`
- **THEN** Phase 4 counts this as round 1 of 2 and fixes, and the close stage does not merge the run

##### Example: next says whether it decided

| Run state | `decision` | `decided` |
| --- | --- | --- |
| no gate result recorded yet (no stop mode) | stop | false |
| one not_clean round recorded (no stop mode, unattended) | fix | true |

#### Scenario: After an undecided round Phase 4 keeps its own count

- **GIVEN** a run without a stop mode, unattended, whose first gate could not write the round record
- **WHEN** later rounds are recorded, or the write keeps failing
- **THEN** the loop ends at round 2 by Phase 4's own count, and a stop that merges comes at round 2 at the latest

##### Example: rounds after an undecided next

| next's answers | Phase 4 |
| --- | --- |
| undecided every round | fix at 1, stop at 2, no merge |
| undecided, then fix (round 1 of 2) | fix at 1, stop at 2, no merge |
| undecided, then stop with merge (round 1) | fix at 1, stop with merge at 2 |
| fix (round 1), then stop with merge (round 2), all recorded | next's answers as they are |
