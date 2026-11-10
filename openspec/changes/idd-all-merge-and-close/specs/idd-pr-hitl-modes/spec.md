## MODIFIED Requirements

### Requirement: PR path preserves v2.40.0 behavior

When the resolved path is `PR`, `idd-all` SHALL behave identically to v2.40.0 up to and including PR creation: enforce a feature branch off the default branch, pass an unattended hint to every sub-skill invocation, push the branch, and create a PR after verify PASS. After the PR is created, the run SHALL continue under the requirement "Clean verify leads to merge and close"; callers such as `/loop` automation therefore observe the issue closed, not left open at verified, unless the run carries `--review`, stops at a guardrail, or stops because its intent was not confirmed or someone else became involved (requirements "The close stage merges only runs whose intent was confirmed" and "The close stage stops when someone else became involved").

#### Scenario: PR path enforces feature branch

- **GIVEN** resolved path is `PR`
- **AND** the working tree is on the default branch with no uncommitted changes
- **WHEN** Phase 0.5 completes
- **THEN** `idd-all` checks out a new branch named `idd/<N>-<slug>` per `references/pr-flow.md`

#### Scenario: PR path passes unattended hint

- **GIVEN** resolved interaction is `unattended`
- **WHEN** `idd-all` invokes any sub-skill via the `Skill` tool
- **THEN** the args string includes an `UNATTENDED MODE` directive instructing the sub-skill to suppress `AskUserQuestion` calls and converge in one round

#### Scenario: PR path opens PR after verify PASS

- **GIVEN** Phase 4 verify reports zero blocking findings
- **AND** resolved path is `PR`
- **WHEN** Phase 5 executes
- **THEN** `idd-all` runs `git push -u origin <branch>` followed by `gh pr create` with body containing `Refs #<N>` and forbidding any `Closes` / `Fixes` / `Resolves` trailer

### Requirement: Direct-commit path stays on current branch and skips PR

When the resolved path is `direct-commit`, `idd-all` SHALL NOT create a feature branch and SHALL NOT create a PR. Commits land on whichever branch the user currently has checked out. `idd-all` SHALL NOT push during Phases 1 to 4. After a clean verify, `idd-all` SHALL push only when the current branch is the default branch, and only so that the fix exists on the remote default branch before the issue is closed; on any other branch it SHALL stop at verified without pushing. Before the push it SHALL require that every outgoing commit (`origin/<default>..HEAD`) references the issue as `#<N>`, so commits that are not this run's are never pushed, that `HEAD` is the head of the range named by the verify report and is still `HEAD` and on the default branch right before the push, that the push names that verified commit rather than re-resolving `HEAD`, and that no outgoing commit's subject or body carries a `close`, `fix`, or `resolve` keyword before an issue reference (`#<digits>`, `owner/repo#<digits>`, or an issue or pull-request URL, a preceding hyphen or slash included), because GitHub would close the issue from such a commit without `/idd-close`. It SHALL also run the local CI gate (`idd-ci-gate.sh run --commit <verified commit>`, capability `local-ci-gate`) and push only when the gate exits 0 or 10; with exit 10 (remote mode) there is no remote result for commits that were never pushed, so the push proceeds and remote CI runs after it. Any failed condition SHALL stop at verified without pushing.

#### Scenario: direct-commit on default branch

- **GIVEN** resolved path is `direct-commit`
- **AND** user is on the default branch
- **WHEN** `idd-all` runs Phases 1–4
- **THEN** commits land on the default branch, no `idd/<N>-<slug>` branch is created, and nothing is pushed before verify completes

#### Scenario: direct-commit respects pre-existing feature branch

- **GIVEN** resolved path is `direct-commit`
- **AND** user is already on a feature branch named `wip/foo`
- **WHEN** `idd-all` runs
- **THEN** commits land on `wip/foo` without checking out any new branch

#### Scenario: direct-commit skips PR creation

- **GIVEN** resolved path is `direct-commit`
- **WHEN** Phase 5 begins
- **THEN** Phase 5 logs `→ direct-commit path: skipping PR` and does not invoke `gh pr create`

#### Scenario: clean verify on the default branch pushes, then closes

- **GIVEN** resolved path is `direct-commit` on the default branch
- **AND** the verify gate reports `clean`
- **WHEN** the close stage runs
- **THEN** `idd-all` pushes the verified commit itself (`git push origin <sha>:refs/heads/<default>`), confirms on GitHub that the default branch now points at it, and only then invokes `/idd-close #<N>` with the orchestrated directive

The local CI gate can run for as long as its own time limit (`ci.timeout_seconds`, one hour by default). After it ends and before the push, the close stage SHALL read again, in the same process, the verify gate for the commit it is about to push and whether anyone else became involved after the run started, and SHALL NOT push when either check stops.

##### Example: what the direct path reads again after the local CI gate

| While the local CI gate runs | Local CI gate | Result |
| --- | --- | --- |
| nothing changes on the issue | pass | `pushed` |
| a teammate comments on the issue | pass | `stopped`: the comment came after the run started; nothing is pushed |
| a new verify report for the same commit says FAIL | pass | `stopped`: the verify gate; nothing is pushed |

#### Scenario: local CI fails before a direct-commit push

- **GIVEN** resolved path is `direct-commit` on the default branch and the verify gate reports `clean`
- **AND** the local CI gate exits 1 for the verified commit
- **WHEN** the close stage runs
- **THEN** `idd-all` does not push and does not close, and the run report contains `Stopped:` naming the CI guardrail

#### Scenario: clean verify on a feature branch stops at verified

- **GIVEN** resolved path is `direct-commit` on `wip/foo`
- **AND** the verify gate reports `clean`
- **WHEN** the close stage runs
- **THEN** `idd-all` does not push and does not close, and the run report contains `Stopped:` stating that the fix is not on the default branch

### Requirement: Attended interaction permits sub-skill questions

When the resolved interaction is `attended`, `idd-all` SHALL NOT inject any `UNATTENDED MODE` directive into sub-skill invocation args. Each sub-skill's own attended-by-default behavior — `/idd-plan`'s `EnterPlanMode` approval, `spectra-discuss` multi-turn pacing, `spectra-propose` Step 10 Park/Apply prompt, `idd-implement` `AskUserQuestion` checkpoints — MUST take effect natively. The one exception is `/idd-close` invoked by the close stage: it carries the `ORCHESTRATED BY /idd-all` directive in both interactions, so its stop points take the defaults that requirement "idd-close honors the orchestrated directive from idd-all" lists instead of asking; only its distribution-sync question is still asked when the interaction is attended.

> The Plan-tier gate lives in `/idd-plan`, not in `idd-implement` (`#292`). Which phase invokes which skill is stated once, in `skills/idd-all/SKILL.md`'s dispatch table; this spec constrains the *directive injection* and defers to that table for routing.

#### Scenario: attended mode allows EnterPlanMode

- **GIVEN** resolved interaction is `attended`
- **AND** Phase 2 diagnose returns Complexity = `Plan`
- **WHEN** Phase 3p invokes `/idd-plan` (per the dispatch table in `skills/idd-all/SKILL.md`)
- **THEN** the args string contains no `UNATTENDED MODE` directive
- **AND** `/idd-plan` triggers `EnterPlanMode` for user approval, then chains to `idd-implement`

#### Scenario: attended mode allows spectra-discuss multi-turn

- **GIVEN** resolved interaction is `attended`
- **AND** Phase 2 diagnose returns Complexity = `Spectra`
- **WHEN** Phase 3b invokes `spectra-discuss`
- **THEN** the args string contains no `UNATTENDED MODE` directive
- **AND** `spectra-discuss` paces the discussion across multiple turns using `AskUserQuestion` per its native default

#### Scenario: attended close stage applies idd-close's defaults

- **GIVEN** resolved interaction is `attended` and the verify gate reports `clean`
- **WHEN** the close stage invokes `/idd-close`
- **THEN** the args carry the `ORCHESTRATED BY /idd-all` directive and no `UNATTENDED MODE` directive
- **AND** `/idd-close` does not ask at Step 1.55, 1.6, 3.5, 3.6 or 6.3, and asks at Step 6.5 when it detects a distribution

## REMOVED Requirements

### Requirement: Verify is the terminal phase regardless of mode

**Reason**: #392 moves the terminal state from verified to closed. Merging a PR and closing an issue are both recoverable (revert, reopen), so under the Foresay traceable branch they run without a prior confirmation, provided the run reports what it did. The guarantee "`idd-all` MUST NOT auto-invoke `idd-close`" is replaced by the requirement "Clean verify leads to merge and close".

**Migration**: Callers that need the previous stop-at-verified behaviour pass `--review`, which keeps `idd-all` at verified with the "awaiting human acceptance" wording. `/idd-all-chain` (`--in-chain`) and `type=meeting` runs are unaffected.

## ADDED Requirements

### Requirement: Clean verify leads to merge and close

After verify, `idd-all` SHALL ask the verify gate whether the latest verify round is clean. When the gate reports `clean`, the path is `PR`, and every merge guardrail passes, `idd-all` SHALL squash-merge the PR, fetch the remote default branch, and invoke `/idd-close #<N>` with the orchestrated directive, without asking the user first. When the path is `direct-commit`, the push-then-close behaviour of the requirement "Direct-commit path stays on current branch and skips PR" applies. `idd-all` SHALL NOT merge or close when the run carries `--review`, when it runs with `--in-chain`, or when the issue type is `meeting`. Every check that guards the merge or the push SHALL run in the same process as the merge or the push, and the run's flags SHALL be read from a run-state record written when the mode is resolved, not from shell state or the model's memory. Every value in that record SHALL be given explicitly when it is written (a lost value is an error, never a default that allows merging); a missing, foreign or more than 24-hour-old record SHALL stop the close stage. The close stage SHALL also stop when the run was downgraded from the PR path (a missing ralph-loop), when the issue's author or the last editor of its body lacks write access to the repository, when the fetch or push URL of the clone's `origin` is not `github.com/<repo>`, and when a workflow publishes on a push to the default branch. Publishing detection is a named limit (maintainer decision after verify round 7): it reads the workflow files for a list of known publishing steps and treats a trigger it cannot read as publishing, so a release path that is not on the list (a `make` target, `rsync`, a remote action, a script at the repository root) is not detected and the merge publishes. A repository whose merges publish in such a way SHALL be run with `--review`.

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

### Requirement: The close stage merges only runs whose intent was confirmed

The close stage SHALL merge, push or close only when the run's intent was confirmed. It SHALL read the issue and its comments as GitHub renders them (`body_html`), and SHALL stop at verified, with the PR left open, when any of these holds (a closed list): a comment on the issue was posted by an account without write access to the repository, bots excepted; the issue body shows an open clarity question, read wherever GitHub shows it and whatever heading stands above it (in a table with a `Status` header, a row whose Status cell starts with `surfaced` or `deferred`; in a table without one, a row with a cell that is exactly `surfaced` or `deferred`; outside any table, a line with pipes whose cell starts with one of the two words); the Diagnosis that idd-all Phase 2 routes on (the newest trusted comment with a `## Diagnosis` line) has no readable Complexity tier; or any comment shows a record line `- **Reason**: <literal>` whose literal is `unattended-auto-Step-3.4-layerV-deferred` or `unattended-auto-Step-4-choice-default` and no Decision comment was posted after it. A Decision comment records what a person decided; it answers every record posted before it. The tier of the Diagnosis SHALL NOT stop the close stage: an unattended run that implemented a Plan, Spectra or SDD-warranted issue merges and closes like any other when every check passes (decision of 2026-11-10, comment 6761899504, which replaces that item of decision 6566557673). Proposed Corrections that an unattended run listed and nobody answered SHALL NOT stop the close stage either; the close stage SHALL count the comments that show a Proposed Corrections section with content after the latest Decision comment, put that count in its result as `proposed_corrections`, and the run report SHALL say how many there are and that they were not applied (decision of 2026-11-10, comment 6761657951). Foresay's traceable branch requires the intent to be clear and the action reversible; unattended runs skip intent confirmations on purpose and record that they did, and comments and attachments steer diagnose and implement. The Stage 1 strategy confirmation an unattended diagnose performs itself is attention, not a skipped confirmation, and is not on the list (decision of 2026-11-02, comment 6568180861). The threat model is an orchestrator that can be wrong, not one that deceives: these checks stop honest mistakes, and they cannot stop an orchestrator that deliberately mislabels a finding, omits a record or posts a Decision on its own.

#### Scenario: A comment by someone without write access

- **GIVEN** the verify gate reports `clean`
- **AND** one comment on the issue was posted by an account with read access only
- **WHEN** the close stage runs
- **THEN** `idd-all` neither merges nor closes, and the run report names the comment's author under `Stopped:`

#### Scenario: The tier does not decide the merge

- **GIVEN** the latest Diagnosis records a tier and every other check passes
- **WHEN** the close stage runs
- **THEN** the result is the one in the table below

##### Example: result by tier and interaction

| Tier in the latest Diagnosis | Interaction | Result |
| --- | --- | --- |
| `Simple` | unattended | merged |
| `Plan` | unattended | merged |
| `Spectra` | unattended | merged |
| `SDD-warranted` | unattended | merged |
| `Plan` | attended | merged |
| no readable tier | either | stopped |

#### Scenario: Proposed Corrections nobody answered

- **GIVEN** an unattended run whose Diagnosis lists a Proposed Corrections table with one row, and no later Decision comment
- **WHEN** the close stage runs with every other check passing
- **THEN** `idd-all` merges and closes, the result carries `proposed_corrections` of 1, and the run report says one comment lists corrections that were not applied

##### Example: the count in the result

| Comments with Proposed Corrections | Decision comment after them | `proposed_corrections` | Result |
| --- | --- | --- | --- |
| none | — | 0 | merged |
| the Diagnosis | none | 1 | merged |
| the Diagnosis and a verify report | none | 2 | merged |
| the Diagnosis | one, posted later | 0 | merged |

#### Scenario: A record posted as its own comment

- **GIVEN** an unattended diagnose posted the Diagnosis, then took a choice-first default and posted its record as a separate comment
- **WHEN** the close stage runs
- **THEN** `idd-all` neither merges nor closes, because the record has no later Decision comment

#### Scenario: A Decision answers a record

- **GIVEN** a Layer V deferral record on the issue, and a later Decision comment recording the maintainer's ruling
- **WHEN** the close stage runs with every other check passing
- **THEN** the record does not stop the run

#### Scenario: A resolved Clarity row keeps its reason

- **GIVEN** a Clarity Surface row reads `| ambiguity | x | y? | resolved | unattended-auto-Step-4.6-deferred |`
- **WHEN** the close stage runs
- **THEN** the row does not stop the run, because its status is no longer `deferred`

#### Scenario: An open clarity question wherever GitHub shows it

- **GIVEN** the issue body holds a clarity row
- **WHEN** the close stage reads the body as GitHub renders it
- **THEN** the row stops the run or not as in the table below

##### Example: where the row stands and what its status says

| Where the row stands | Status cell | Result |
| --- | --- | --- |
| under `### Clarity Surface` | `surfaced` | stopped |
| under `#### Clarity Surface` | `surfaced` | stopped |
| inside a `<details>` block | `deferred` | stopped |
| inside a quote | `surfaced` | stopped |
| under a heading with another name | `surfaced` | stopped |
| a line with pipes GitHub did not draw as a table | `surfaced` | stopped |
| under `### Clarity Surface` | `deferred (see retry hint)` | stopped |
| under `### Clarity Surface` | `resolved @ … (reason: deferred to the next issue)` | not stopped |
| under `### Clarity Surface`, another cell quotes the word deferred | `resolved` | not stopped |
| inside a code fence | `surfaced` | not stopped |

### Requirement: The close stage stops when someone else became involved

The close stage SHALL stop at verified when any of these holds (a closed list). After the run began (the creation time of its run state): an account other than the one running the session, and not a bot, posted or edited a comment on the issue, edited the issue body, added or removed a label, changed the title, or closed or reopened the issue; a comment on the issue by any account other than the one running the session was deleted. At the close stage: the issue is not OPEN; the PR was not opened by the account running the session; the PR is a draft or its review decision is `CHANGES_REQUESTED`; the PR has a comment or a review from an account that is not a bot, or a label, title or state change by another account that is not a bot, or a description edit by another account; or any of these histories holds more entries than one read returns, so that entries after the run began could be missed. For a history read with a type filter (the issue's and the PR's timeline events), the count compared with the entries read SHALL be the number of entries that match the filter (GraphQL `filteredCount`), not the number of all entries of that history (`totalCount`, which also counts commits and comments), and an answer without that count SHALL stop the close stage. The PR checks SHALL run after the CI wait, right before the merge. The run read the issue when it started; anything that arrives later is intent it never read, and a comment deleted after diagnose read it may have steered the work.

#### Scenario: A teammate comments during the run

- **GIVEN** the verify gate reports `clean`
- **AND** an account with write access commented on the issue after the run began
- **WHEN** the close stage runs
- **THEN** `idd-all` neither merges nor closes, and the report names that account under `Stopped:`

#### Scenario: An outsider deletes a comment after diagnose

- **GIVEN** an account without write access commented, diagnose read the comment, and the account deleted it before the close stage
- **WHEN** the close stage runs
- **THEN** `idd-all` neither merges nor closes, because a comment was deleted after the run began

#### Scenario: The issue is closed during the run

- **GIVEN** a maintainer closed the issue as not planned while the close stage waited for CI
- **WHEN** the close stage checks right before merging
- **THEN** `idd-all` does not merge

#### Scenario: Changes requested on the PR during the CI wait

- **GIVEN** a reviewer requested changes on the PR while the close stage waited for CI
- **WHEN** the close stage checks the PR right before merging
- **THEN** `idd-all` does not merge

#### Scenario: A PR whose only timeline entries are its commits

- **GIVEN** a PR with one commit and no label, title or state event, so that GitHub answers the filtered timeline read with `totalCount` 1, `filteredCount` 0 and no nodes (the answer recorded from a sandbox PR on 2026-11-10)
- **WHEN** the close stage checks the PR
- **THEN** the timeline does not stop the run

##### Example: timeline answers and the result

| Read | `totalCount` | `filteredCount` | Nodes read | Oldest node read | Result |
| --- | --- | --- | --- | --- | --- |
| PR timeline, one commit only | 1 | 0 | 0 | — | not stopped |
| PR timeline, 16 entries, one of them a close event | 16 | 1 | 1 | — | judged by that node |
| PR timeline, more matching events than read | 150 | 150 | 100 | — | stopped |
| issue timeline, more matching events than read | 150 | 150 | 100 | after the run began | stopped |
| issue timeline, more matching events than read | 150 | 150 | 100 | before the run began | judged by the nodes read |
| either timeline, no `filteredCount` in the answer | 1 | absent | 0 | — | stopped |

### Requirement: Unattended fix loop covers in-scope findings with a two-round limit

When the resolved interaction is `unattended` and the verify gate reports `not_clean`, `idd-all` SHALL fix every Blocking finding, and every In-scope fix finding unless the run carries `--review` or `--in-chain` (those runs never merge and keep the Blocking-only scope), in the same branch and run verify again, for at most 2 verify rounds in total (one fix pass between them). If the gate still reports `not_clean` after the second verify round, `idd-all` SHALL stop at verified without merging or closing. When the resolved interaction is `attended`, `idd-all` SHALL NOT fix findings automatically; it SHALL hand the findings back to the user, and merge and close only follow a later round that the gate reports `clean`. When the gate reports `clean` with `low_in_scope` above zero, `idd-all` SHALL NOT change the branch for those findings (the commit that merges is the commit the round reviewed); it SHALL file them together as one follow-up issue before the close stage.

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

### Requirement: Merge guardrails gate every automatic merge

Before an automatic merge, `idd-all` SHALL check, in order: the PR's branch is not behind the default branch and does not change `.github/workflows` or `.github/actions`; the newest verify comment this account posted on the issue since the run began is a `## Verify: #<N>` report that was not edited after it was posted and is not hidden, the gate reports `clean` for it with no `Rejected` finding, no Follow-up finding of severity CRITICAL, HIGH, P0 or P1, and no sign of a degraded verify (`process_gaps`), and its reviewed range runs from the merge base of the default branch and the PR head to the PR head; every commit in that range references the issue as `#<N>`; after the CI wait and right before the merge, the default branch SHALL be fetched again and the branch, publishing, CI-edit, merge-queue and verify-gate checks SHALL run again; the local CI gate (`idd-ci-gate.sh run --commit <verified head>`, capability `local-ci-gate`) exits 0, or it exits 10 (remote mode) and every check reported by `gh pr checks` has succeeded, waiting at most 15 minutes for pending checks, accepting a result only after the set of checks has stayed unchanged for a 90-second grace period, requiring at least one `pull_request` check when a workflow runs on every pull request, and treating a PR with no checks as passing only when no such workflow exists; any other exit code of the gate (1 fail, 2 timeout, 3 not configured, 4 error, or a code outside the list) SHALL stop the close stage; when the gate exits 0, the close stage SHALL read the PR's remote checks once without waiting, SHALL put the names of failed or cancelled ones in its result as `remote_ci_failed` and of pending ones as `remote_ci_pending` (`remote_ci_failed` reads `not readable` when the checks could not be read), and SHALL NOT stop on any of them; the PR body has no closing reference and no commit subject or body (read from local git over the reviewed range, not from a capped list) carries a `close`, `fix`, or `resolve` keyword before an issue reference (`#<digits>`, `owner/repo#<digits>`, or an issue or pull-request URL, a preceding hyphen or slash included); and the squash subject and body that `idd-all` composes reference the issue only as `Refs #<N>` and pass the same scan. The PR SHALL come from this repository (not a fork) and the default branch SHALL have no merge queue. The merge SHALL be pinned to the verified head commit (`--match-head-commit`), and `idd-all` SHALL confirm that the PR is `MERGED` with a merge commit before invoking `/idd-close`; a PR still open after the merge call SHALL have auto-merge disabled and the run SHALL stop, and a merge it cannot confirm SHALL be reported as possibly merged. If any check fails, `idd-all` SHALL NOT merge, SHALL stop at verified, and SHALL name the failed guardrail in the run report.

#### Scenario: A CI check fails in remote mode

- **GIVEN** the verify gate reports `clean` and the local CI gate exits 10 (`ci.mode` is `remote`)
- **AND** `gh pr checks` reports one failed check named `test`
- **WHEN** the guardrails run
- **THEN** `idd-all` does not merge and the run report contains `Stopped:` naming the CI guardrail and the check `test`

#### Scenario: Local CI decides the CI guardrail

- **GIVEN** the verify gate reports `clean`
- **WHEN** the close stage runs the local CI gate on the verified head
- **THEN** the CI guardrail gives the result in the table below

##### Example: gate exit code, remote checks and the result

| Gate exit | Remote checks on the PR | CI guardrail | `remote_ci_failed` |
| --- | --- | --- | --- |
| 0 (pass) | all passed | passes | empty |
| 0 (pass) | `test` failed | passes | `test` |
| 0 (pass) | could not be read | passes | `not readable` |
| 0 (pass) | `test` still pending | passes, without waiting | empty (`remote_ci_pending` holds `test`) |
| 10 (remote) | all passed | passes | not reported |
| 10 (remote) | `test` failed | stops | not reported |
| 1 (fail) | any | stops | not reported |
| 2 (timeout) | any | stops | not reported |
| 3 (not configured) | any | stops | not reported |
| 4 (error) | any | stops | not reported |
| any other code | any | stops | not reported |

#### Scenario: The PR head moved after verify

- **GIVEN** the verify report names commit `abc…` as reviewed
- **AND** a new commit was pushed to the PR branch afterwards
- **WHEN** the guardrails run
- **THEN** guardrail 1 reports that the reviewed commit is not the PR head and `idd-all` does not merge

#### Scenario: A report posted by another account

- **GIVEN** the newest `## Verify: #<N>` comment that says PASS was posted by an account other than the one running the session, after the run began
- **WHEN** the guardrails run
- **THEN** that comment is not read as the verify report, and `idd-all` does not merge (another account's comment after the run began stops the run on its own)

#### Scenario: A PR-mode verify report posted during the CI wait

- **GIVEN** the account running the session posted `## Verify (via PR #<P>)` on the issue after the run's own `## Verify: #<N>` report
- **WHEN** the guardrails run
- **THEN** the gate reports `unparseable` (the newest verify comment is not a `## Verify: #<N>` report) and `idd-all` does not merge

#### Scenario: The default branch moves during the CI wait

- **GIVEN** another PR landed on the default branch while the close stage waited for CI
- **WHEN** the close stage checks again right before merging
- **THEN** the branch is behind the default branch and `idd-all` does not merge

#### Scenario: A serious finding filed as out of scope

- **GIVEN** the verify report says PASS and lists a HIGH finding with Action `Follow-up`
- **WHEN** the guardrails run
- **THEN** `idd-all` does not merge and the run report says a person agrees before a serious finding is left for later

#### Scenario: A verify report edited after it was posted

- **GIVEN** the newest verify report said FAIL when it was posted and was later edited to say PASS
- **WHEN** the guardrails run
- **THEN** the gate reports `unparseable` and `idd-all` does not merge

#### Scenario: A finding the orchestrator rejected

- **GIVEN** the verify report says PASS and marks one finding `Rejected`
- **WHEN** the guardrails run
- **THEN** `idd-all` does not merge and the run report says a person decides whether the rejected finding stands

#### Scenario: A commit body would auto-close the issue

- **GIVEN** the verify gate reports `clean`
- **AND** one commit body on the branch contains a close keyword adjacent to the issue reference
- **WHEN** the guardrails run
- **THEN** `idd-all` does not merge and the run report names the auto-close trap guardrail and the commit

### Requirement: Verify gate parsing fails closed

The verify gate SHALL read the verify master comment as GitHub renders it (the comment's `body_html`), so that every table a person sees on GitHub is a table the gate reads and nothing GitHub hides is read, and SHALL report exactly one of `clean`, `not_clean`, or `unparseable`, together with the counts of Blocking, In-scope fix, Follow-up and Rejected findings, the count of Follow-up findings of severity CRITICAL, HIGH, P0 or P1, and whether the verify ran degraded (`process_gaps`: the words `process gaps` or `cross-model pass incomplete` anywhere in the visible text, in any case, or a reviewers line that says fewer reviewers completed than were dispatched). Every line of visible text counts — in a paragraph, a list item, a heading, a summary or raw text in a details block — except code blocks. It SHALL report `unparseable` when the verdict line or the classification table cannot be found, when there is more than one verdict-like line outside table cells or the verdict line is inside a quote, list or details block (verdict-like: a line that opens with a bold upper-case word, also after an emoji or inside italics; a line that starts with PASS, PASSED, FAIL, FAILED or CONDITIONAL in upper case; a line that starts with a `Verdict:` label; a heading that holds one of those words), when a line, a heading or a bold label outside the tables starts with a class name (Blocking, In-scope fix, Follow-up, Rejected, plural forms and any case included, also after an emoji), when a table has a `Severity` column and no `Action` column, when a PASS report does not carry exactly one line `X / Y reviewers completed` with Y above zero and X not above Y, when a classification value is not one of Blocking, In-scope fix, Follow-up or Rejected, when the verdict is PASS while the table contains a Blocking finding, when the verdict is FAIL while the table has neither a Blocking nor an In-scope fix finding, when a cell naming one of the four classes stands in a table without an `Action` column or a line of text with pipes names one outside any table, when a table header ends in a decorated `Action`, when the verdict line does not state its blocking count, states counts that differ from the tables (findings tables inside a details block count), or omits the rejected count while the tables have a Rejected finding, when a table has an `Action` column that is not its last column, when a PASS report has no coverage line, more than one, or one that says fewer requirements were addressed than exist, and, when the commit to be merged is given, when the report does not carry exactly one top-level `**Reviewed**` line whose head is that full commit and, when a base is given, whose range starts at that base. It SHALL report `clean` only when the verdict is PASS, the tables hold no Blocking finding and every In-scope fix finding has severity LOW, INFO or P3; it SHALL report `not_clean` when the verdict is FAIL or an In-scope fix finding of any other severity remains (decision of 2026-11-10, comment 6761657951: a merge is held by Blocking findings and by In-scope fix findings above LOW, not by LOW ones). The severity of a row is the most severe severity word in its Severity cell, in the order CRITICAL, P0, HIGH, P1, MEDIUM, P2, LOW, P3, INFO; an In-scope fix or Follow-up row whose Severity cell has no such word is `unparseable`. The count of In-scope fix findings that did not hold the merge SHALL be reported as `low_in_scope`. The same verdict words and class names in the middle of a sentence are not read (a named limit: the gate reads where a line starts, not what a sentence means). A Rejected finding, a serious Follow-up finding and a degraded verify do not change the status; the close stage stops on them. `idd-all` SHALL treat `unparseable` exactly like a failed guardrail: no merge, no close, and the reason in the run report.

#### Scenario: Classification table is missing

- **WHEN** the gate reads a verify comment whose verdict line says PASS but which has no classification table
- **THEN** the gate reports `unparseable` with the reason that the table was not found, and `idd-all` stops at verified

#### Scenario: Verdict contradicts the table

- **WHEN** the gate reads a verify comment whose verdict line says PASS and whose table has one Blocking row
- **THEN** the gate reports `unparseable` with the reason that the verdict contradicts the table

#### Scenario: A second verdict or a finding outside the table

- **GIVEN** a report whose verdict line says PASS with 0 blocking, an empty findings table, complete coverage and `6 / 6 reviewers completed`
- **WHEN** one more block is added to it
- **THEN** the gate reports the status in the table below

##### Example: the added block and the status

| Added block | status |
| --- | --- |
| nothing | clean |
| `❌ **FAIL** — 2 blocking` | unparseable |
| `***FAIL***` | unparseable |
| `Verdict: FAIL` | unparseable |
| `FAIL — the cross-check did not hold` | unparseable |
| the heading `## Verify: #42 — round 2 → FAIL` in place of `## Verify: #42` | unparseable |
| `### Blocking findings (2)` and a list | unparseable |
| `### ❌ Blocking` and a list | unparseable |
| `- Blocking: the merge is wrong` | unparseable |
| `**Blocking finding**: the merge is wrong` | unparseable |
| `### Follow-ups` and a list | unparseable |
| a table `# / Severity / Finding` with a CRITICAL row | unparseable |
| a sentence: 第 1 輪判定 FAIL，那一輪的 2 項 Blocking 都已修 | clean |

#### Scenario: A degraded verify is reported

- **GIVEN** a report that is otherwise clean
- **WHEN** the gate reads its reviewers line and looks for the degraded markers
- **THEN** it reports the values in the table below

##### Example: reviewers line, markers and the result

| Reviewers line | Marker in the report | status | `process_gaps` |
| --- | --- | --- | --- |
| `6 / 6 reviewers completed` | none | clean | false |
| `5 / 6 reviewers completed` | none | clean | true |
| `6 / 6 reviewers completed` | `### Process gaps` | clean | true |
| `6 / 6 reviewers completed` | `### ⚠ Process Gaps` | clean | true |
| `6 / 6 reviewers completed` | `**Process Gaps**: …` | clean | true |
| none | none | unparseable | — |
| `0 / 0 reviewers completed` | none | unparseable | — |
| `7 / 6 reviewers completed` | none | unparseable | — |
| two reviewers lines | none | unparseable | — |

#### Scenario: Low in-scope findings do not hold a merge

- **GIVEN** a report whose verdict line says PASS, with 0 Blocking findings and complete coverage
- **WHEN** the gate reads the Severity cells of its In-scope fix rows
- **THEN** it reports the status in the table below

##### Example: status by the In-scope fix rows

| Severity cells of the In-scope fix rows | status | `low_in_scope` |
| --- | --- | --- |
| no In-scope fix row | clean | 0 |
| `LOW` | clean | 1 |
| `INFO`, `LOW`, `P3` | clean | 3 |
| `MEDIUM` | not_clean | 0 |
| `LOW`, `HIGH` | not_clean | 1 |
| `LOW (one reviewer says HIGH)` | not_clean | 0 |
| `P2` | not_clean | 0 |
| `soon` | unparseable | — |

### Requirement: idd-close honors the orchestrated directive from idd-all

When `/idd-close` is invoked with the `ORCHESTRATED BY /idd-all` directive, it SHALL apply these defaults instead of asking the user: when Step 1.55 reports commits not on the default branch, or Step 1.6 reports a checked item without a matching commit, it SHALL stop without closing and report why; follow-up mentions found by Step 3.5 SHALL be filed as issues per the IC_R011 default; a non-empty Residue read by Step 3.6 SHALL be recorded as residue without filing an issue; a document that the Step 6.3 doc-sync sweep finds stale SHALL NOT be committed and SHALL instead be listed in the closing summary under `### Doc-sync 檢查`; the Step 6.5 distribution sync SHALL ask the user when the interaction is attended and SHALL be skipped, with the command to run listed in the report, when the interaction is unattended. Without the directive, `/idd-close` SHALL behave exactly as before.

#### Scenario: Semantic check warns during an orchestrated close

- **GIVEN** `/idd-close` runs with the orchestrated directive
- **AND** Step 1.6 finds a checked Strategy item with no matching commit
- **WHEN** the close would proceed
- **THEN** `/idd-close` does not close the issue, and `idd-all` reports that the PR was merged but the issue was left open, with the Step 1.6 warning and the command `/idd-close #<N>`

#### Scenario: Unattended distribution sync is skipped

- **GIVEN** `/idd-close` runs with the orchestrated directive in an unattended run
- **AND** Step 6.5 detects a plugin distribution
- **WHEN** Step 6.5 runs
- **THEN** no distribution command is executed, and the run report lists the command that would have run

#### Scenario: Manual close is unchanged

- **WHEN** a user runs `/idd-close #<N>` without the orchestrated directive
- **THEN** every existing question in `/idd-close` is asked exactly as before

### Requirement: Run report states what was done and how to undo it

When `idd-all` merges, pushes, or closes, its Phase 6 report SHALL start with `Done:` and list the actual merge commit or pushed commits, the closed issue with a link to its closing summary, the number of changed files with added and deleted lines, the follow-up issues filed, the recorded residue, the outcome of distribution sync, and which verify reviewers ran and which were missing. It SHALL also state, each only when it is not zero or empty: the number of LOW In-scope fix findings the merge did not wait for (`low_in_scope`) with the follow-up issue that lists them, the number of comments whose Proposed Corrections were not applied (`proposed_corrections`), and the remote checks that failed, are still running or could not be read while local CI passed (`remote_ci_failed`, `remote_ci_pending`). It SHALL end with an `Undo:` section containing `gh issue reopen <N>` and `git revert <sha>`. When the run stops before closing, the report SHALL list only the steps actually done and add a `Stopped:` line naming the guardrail or close stop point and its verbatim reason.

#### Scenario: Successful run report

- **WHEN** a PR-mode run merges PR 412 as commit `abc1234` and closes issue 405
- **THEN** the report contains `merged PR #412`, `abc1234`, `closed #405`, the closing summary link, and the lines `gh issue reopen 405` and `git revert abc1234`

#### Scenario: A merge that left LOW findings and a failed remote check

- **WHEN** a run merges with `low_in_scope` 2, `proposed_corrections` 0 and `remote_ci_failed` naming `lint`
- **THEN** the report says two LOW in-scope findings were not fixed and names the follow-up issue that lists them, says the remote check `lint` failed while local CI passed, and has no line about Proposed Corrections

#### Scenario: Run stopped at a guardrail

- **WHEN** a run stops because the verify gate reported `unparseable`
- **THEN** the report contains no `merged` or `closed` line and contains `Stopped:` with the gate's reason

### Requirement: idd-all states which outward actions it runs without asking

`skills/idd-all/SKILL.md` SHALL carry a section headed `## 權限` that lists, as two closed tables, the outward actions `idd-all` itself starts: the actions it runs and then reports with an `Undo:` line, and the actions it asks a person about first. The basis SHALL be Foresay's `reversible` property: the state can be restored, no cost is unrecoverable, and nothing has been observed by another party. An outward action of `idd-all` that is on neither table SHALL be asked about first; no action SHALL be added to the first table because it resembles one that is there. An action a sub-skill starts follows that sub-skill. Where the rules of the person running `idd-all` are stricter than the section, those rules apply.

`idd-all` SHALL open the pull request of its run, and SHALL refresh the body of a pull request the same run opened earlier, without asking only when `close-stage.py pr-check` prints `"status": "open"`. The check reads the title and the body the run is about to send and the default branch as the local clone has it, and SHALL answer `ask` with a reason when any of these holds: the title is empty; the title or the body mentions an account (an `@` followed by a letter or digit and not preceded by a letter or digit, or an `@` written as a character reference; this is wider than what GitHub notifies on, and the extra cases only ask); the title or the body has a close keyword next to an issue reference; a `CODEOWNERS` file exists on the default branch at `.github/CODEOWNERS`, `CODEOWNERS` or `docs/CODEOWNERS` (opening the pull request would request a review from a person); or the default branch cannot be fetched or read. The check fetches the default branch before it looks for `CODEOWNERS`, so a file added during the run counts. The pull request is opened in the repository the run pushed its branch to, from the run's branch to the default branch, with no reviewer and no assignee. The privacy self-review of the title and the body stays with the model and is not part of this check. When the check answers `ask`, an attended run SHALL ask the person and an unattended run SHALL NOT open the pull request and SHALL NOT change one that is already open: the branch stays pushed and the run report names the reason. A push of the run's branch that fails SHALL stop the phase before any pull request is opened.

#### Scenario: A repository with a CODEOWNERS file

- **GIVEN** an unattended PR-mode run whose verify is clean
- **AND** the default branch has `.github/CODEOWNERS`
- **WHEN** the run reaches the step that opens the pull request
- **THEN** `pr-check` prints `"status": "ask"` naming the file, no pull request is opened, the branch stays pushed, and the run report names the reason

##### Example: pr-check by title, body and default branch

| Title and body | Default branch | `status` | Exit |
| --- | --- | --- | --- |
| `Refs #7`, no mention | no `CODEOWNERS` at any of the three paths | `open` | 0 |
| `Refs #7`, no mention | `.github/CODEOWNERS` exists | `ask` | 3 |
| `Refs #7`, no mention | `docs/CODEOWNERS` exists | `ask` | 3 |
| body has `thanks @someone` | no `CODEOWNERS` | `ask` | 3 |
| body has `mail t@example.test` and `` `pkg@1.2` `` | no `CODEOWNERS` | `open` | 0 |
| title has `fix #7` | no `CODEOWNERS` | `ask` | 3 |
| `Refs #7`, no mention | the default branch cannot be fetched | `ask` | 3 |
| `Refs #7`, no mention | `.github/CODEOWNERS` was pushed to the remote after the clone last fetched | `ask` | 3 |
| body has `_@someone_`, `-@someone`, `.@someone` or `(@someone)` | no `CODEOWNERS` | `ask` | 3 |
| body has `&#64;someone`, `&#x40;someone` or `&commat;someone` | no `CODEOWNERS` | `ask` | 3 |
| an empty title | no `CODEOWNERS` | `ask` | 3 |
| a title file that does not exist | any | usage error | 64 |

##### Example: which actions idd-all runs and reports, and which it asks about

| Action started by `idd-all` | Table | Undo, or why it cannot be undone |
| --- | --- | --- |
| create an issue, comment, edit its own issue body, set a label, push the baseline tag | runs and reports | edit or delete the record |
| push the run's branch (not the default branch, no `--force`) | runs and reports | delete the remote branch |
| open the run's pull request, or refresh the body of the one it opened, when `pr-check` prints `open` | runs and reports | `gh pr close <N>`; GitHub keeps the earlier body in the edit history |
| squash-merge, push on the default branch, `/idd-close`, when `close-stage.py run` passes every guardrail | runs and reports | `git revert`, `gh issue reopen` |
| open or change a pull request for which `pr-check` prints `ask` | asks first | a notification cannot be recalled |
| open a pull request in a repository other than the one `origin` names | asks first; `idd-all` has no step that does it | the other party has already seen it |
| any egress whose text did not pass the privacy self-review | asks first | published text cannot be recalled |
| delete a branch, or push with `--force` | asks first | the overwritten commits are gone |
| publish: `gh release`, a marketplace sync, a tag other than the baseline tag | asks first | it has reached users |
| merge and close in a run that carries `--review` | a person does it | the flag means a person looks first |

