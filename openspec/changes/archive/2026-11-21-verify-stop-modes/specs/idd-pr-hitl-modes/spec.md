## ADDED Requirements

### Requirement: A configured stop mode decides when the fix loop stops and whether the run merges

A run has a stop mode when the `--stop <mode>` flag of `idd-all`, or else the `verify_stop.mode` field of the resolved IDD config, names one of `early`, `exhaustive-blocking` or `exhaustive-all`. The flag takes precedence over the config. A flag with any other value SHALL stop `idd-all` before Phase 1 with a message naming the three values. A config value outside the three SHALL be treated as no stop mode, and `idd-all` SHALL print one line saying so. The resolved mode, or its absence, SHALL be written into the run-state record when the mode is resolved and SHALL be read from there afterwards.

Each time `close-stage.py gate` reads a verify report that has not been read in this run, it SHALL append one round to the round record of the run-state record: the round number, the reviewed commit, and the counts `blocking`, `in_scope` and `low_in_scope`. Reading the same report again SHALL NOT add a round. The to-fix count of a round is `blocking + in_scope - low_in_scope`; for a run that carries `--review` or `--in-chain` it is `blocking`.

After each round of a run with a stop mode, `idd-all` SHALL ask `close-stage.py next` whether to fix and verify again, and SHALL follow its answer; the model SHALL NOT decide this itself. `next` SHALL answer from the mode and the round record only:

| Mode | Stops when | Merges on that stop |
|---|---|---|
| `early` | the to-fix count is 0, or, from round 2 on, it is not lower than the previous round's | when `blocking` is 0 |
| `exhaustive-blocking` | `blocking` is 0, or `blocking` was not lower than the previous round's in each of the last two rounds | when `blocking` is 0 |
| `exhaustive-all` | `blocking` is 0 and `in_scope` is 0, LOW findings included | always |

In every mode `next` SHALL answer stop without merging when the latest gate result is `unparseable` or holds a Rejected finding, and `exhaustive-all` has no round limit. When a finding to be fixed is a security vulnerability, `idd-all` SHALL stop without merging instead of fixing it, as for a run without a stop mode. When the run stops with a merge and findings remain, `idd-all` SHALL NOT change the branch for them: the commit that merges is the commit the last round reviewed, and the remaining findings SHALL be filed together as one follow-up issue. A merge allowed by this table passes the same guardrails as a clean merge, including a complete coverage line and a complete reviewers line, which the verify gate SHALL read for every verdict; a run with `--review` or `--in-chain`, or of type `meeting`, never merges.

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

## MODIFIED Requirements

### Requirement: Clean verify leads to merge and close

After verify, `idd-all` SHALL ask the verify gate whether the latest verify round is clean. When the gate reports `clean` (for a run with a stop mode: when requirement "A configured stop mode decides when the fix loop stops and whether the run merges" allows the merge), the path is `PR`, and every merge guardrail passes, `idd-all` SHALL squash-merge the PR, fetch the remote default branch, and invoke `/idd-close #<N>` with the orchestrated directive, without asking the user first. When the path is `direct-commit`, the push-then-close behaviour of the requirement "Direct-commit path stays on current branch and skips PR" applies. `idd-all` SHALL NOT merge or close when the run carries `--review`, when it runs with `--in-chain`, or when the issue type is `meeting`. Every check that guards the merge or the push SHALL run in the same process as the merge or the push, and the run's flags SHALL be read from a run-state record written when the mode is resolved, not from shell state or the model's memory. Every value in that record SHALL be given explicitly when it is written (a lost value is an error, never a default that allows merging); a missing or foreign record, or one more than 24 hours old, SHALL stop the close stage. The age is measured from the record's creation; for a run with a stop mode it is measured from the last verify round the record holds, so that a long run is not stopped by its own length. The close stage SHALL also stop when the run was downgraded from the PR path (a missing ralph-loop), when the issue's author or the last editor of its body lacks write access to the repository, when the fetch or push URL of the clone's `origin` is not `github.com/<repo>`, and when a workflow publishes on a push to the default branch. Publishing detection is a named limit (maintainer decision after verify round 7): it reads the workflow files for a list of known publishing steps and treats a trigger it cannot read as publishing, so a release path that is not on the list (a `make` target, `rsync`, a remote action, a script at the repository root) is not detected and the merge publishes. A repository whose merges publish in such a way SHALL be run with `--review`.

#### Scenario: Clean verify on the PR path

- **GIVEN** resolved path is `PR`
- **AND** the verify gate reports `clean` and all merge guardrails pass
- **WHEN** the close stage runs
- **THEN** `idd-all` runs `gh pr merge <P> --squash` with a subject and body it composed, runs `git fetch`, invokes `/idd-close #<N>` with the orchestrated directive, and the run report starts with `Done:`

#### Scenario: Only follow-up findings remain

- **GIVEN** the latest verify round says PASS and has 0 Blocking, 0 In-scope fix, and 2 Follow-up findings
- **WHEN** the verify gate runs
- **THEN** it reports `clean`, the two follow-up issues are filed as before, and the run proceeds to merge and close

#### Scenario: Review flag keeps the run at verified

- **GIVEN** the run carries `--review`
- **AND** the verify gate reports `clean`
- **WHEN** Phase 6 runs
- **THEN** `idd-all` neither merges nor closes, and the report uses the "awaiting human acceptance" wording

#### Scenario: Chain context never merges or closes

- **GIVEN** the run carries `--in-chain`
- **WHEN** verify completes clean
- **THEN** `idd-all` neither merges nor closes, leaving the cluster PR to `/idd-all-chain`

#### Scenario: A stop-mode run is not stopped by its own length

- **GIVEN** a run with stop mode `exhaustive-all` whose run-state record was created 30 hours ago
- **AND** the record's last verify round was written 2 hours ago and the gate reports `clean`
- **WHEN** the close stage reads the record
- **THEN** the record's age is 2 hours and the close stage does not stop for age

### Requirement: Unattended fix loop covers in-scope findings with a two-round limit

This requirement applies to a run without a stop mode; a run with one follows requirement "A configured stop mode decides when the fix loop stops and whether the run merges". When the resolved interaction is `unattended` and the verify gate reports `not_clean`, `idd-all` SHALL fix every Blocking finding, and every In-scope fix finding unless the run carries `--review` or `--in-chain` (those runs never merge and keep the Blocking-only scope), in the same branch and run verify again, for at most 2 verify rounds in total (one fix pass between them). The number of rounds already run SHALL be read from the run-state record, not from the model's memory; every new commit the verify gate judged, and every new report on the same commit, counts as one round, also when its report was missing or could not be read or the fix pass made no commit. The close stage SHALL stop, without merging, an unattended run without a stop mode whose record holds more than 2 rounds, or whose newest verify report is not in the record. If the gate still reports `not_clean` after the second verify round, `idd-all` SHALL stop at verified without merging or closing. When the resolved interaction is `attended`, `idd-all` SHALL NOT fix findings automatically; it SHALL hand the findings back to the user, and merge and close only follow a later round that the gate reports `clean`. When the gate reports `clean` with `low_in_scope` above zero, `idd-all` SHALL NOT change the branch for those findings (the commit that merges is the commit the round reviewed); it SHALL file them together as one follow-up issue before the close stage.

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
