## MODIFIED Requirements

### Requirement: PR path preserves v2.40.0 behavior

When the resolved path is `PR`, `idd-all` SHALL behave identically to v2.40.0 up to and including PR creation: enforce a feature branch off the default branch, pass an unattended hint to every sub-skill invocation, push the branch, and create a PR after verify PASS. After the PR is created, the run SHALL continue under the requirement "Clean verify leads to merge and close"; callers such as `/loop` automation therefore observe the issue closed, not left open at verified, unless the run stops at a guardrail or carries `--review`.

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

When the resolved path is `direct-commit`, `idd-all` SHALL NOT create a feature branch and SHALL NOT create a PR. Commits land on whichever branch the user currently has checked out. `idd-all` SHALL NOT push during Phases 1 to 4. After a clean verify, `idd-all` SHALL push only when the current branch is the default branch, and only so that the fix exists on the remote default branch before the issue is closed; on any other branch it SHALL stop at verified without pushing. Before the push it SHALL require that every outgoing commit (`origin/<default>..HEAD`) references the issue as `#<N>`, so commits that are not this run's are never pushed, that `HEAD` is the head of the range named by the verify report and is still `HEAD` and on the default branch right before the push, that the push names that verified commit rather than re-resolving `HEAD`, and that no outgoing commit's subject or body carries a `close`, `fix`, or `resolve` keyword before an issue reference (`#<digits>`, `owner/repo#<digits>`, or an issue or pull-request URL, a preceding hyphen or slash included), because GitHub would close the issue from such a commit without `/idd-close`. Any failed condition SHALL stop at verified without pushing.

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
- **THEN** `idd-all` runs `git push origin HEAD`, and only after the push succeeds invokes `/idd-close #<N>` with the orchestrated directive

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

After verify, `idd-all` SHALL ask the verify gate whether the latest verify round is clean. When the gate reports `clean`, the path is `PR`, and every merge guardrail passes, `idd-all` SHALL squash-merge the PR, fetch the remote default branch, and invoke `/idd-close #<N>` with the orchestrated directive, without asking the user first. When the path is `direct-commit`, the push-then-close behaviour of the requirement "Direct-commit path stays on current branch and skips PR" applies. `idd-all` SHALL NOT merge or close when the run carries `--review`, when it runs with `--in-chain`, or when the issue type is `meeting`. Every check that guards the merge or the push SHALL run in the same process as the merge or the push, and the run's flags SHALL be read from a run-state record written when the mode is resolved, not from shell state or the model's memory. Every value in that record SHALL be given explicitly when it is written (a lost value is an error, never a default that allows merging); a missing, foreign or more than 24-hour-old record SHALL stop the close stage. The close stage SHALL also stop when the run was downgraded from the PR path (a missing ralph-loop), when the issue's author or the last editor of its body lacks write access to the repository, when the clone's `origin` is not the repository, and when a workflow publishes on a push to the default branch.

#### Scenario: Clean verify on the PR path

- **GIVEN** resolved path is `PR`
- **AND** the verify gate reports `clean` and all merge guardrails pass
- **WHEN** the close stage runs
- **THEN** `idd-all` runs `gh pr merge <P> --squash` with a subject and body it composed, runs `git fetch`, invokes `/idd-close #<N>` with the orchestrated directive, and the run report starts with `Done:`

#### Scenario: Only follow-up findings remain

- **GIVEN** the latest verify round has 0 Blocking, 0 In-scope fix, and 2 Follow-up findings
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

### Requirement: Unattended fix loop covers in-scope findings with a two-round limit

When the resolved interaction is `unattended` and the verify gate reports `not_clean`, `idd-all` SHALL fix every Blocking finding, and every In-scope fix finding unless the run carries `--review` or `--in-chain` (those runs never merge and keep the Blocking-only scope), in the same branch and run verify again, for at most 2 verify rounds in total (one fix pass between them). If the gate still reports `not_clean` after the second verify round, `idd-all` SHALL stop at verified without merging or closing. When the resolved interaction is `attended`, `idd-all` SHALL NOT fix findings automatically; it SHALL hand the findings back to the user, and merge and close only follow a later round that the gate reports `clean`.

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

#### Scenario: Attended run with findings

- **GIVEN** resolved interaction is `attended`
- **AND** verify reports 1 Blocking finding
- **WHEN** Phase 4 evaluates the result
- **THEN** `idd-all` reports the finding to the user and makes no automatic fix commit

### Requirement: Merge guardrails gate every automatic merge

Before an automatic merge, `idd-all` SHALL check, in order: the verify gate reports `clean` for a report posted by the account running the session whose reviewed range runs from the merge base of the default branch and the PR head to the PR head (judged again after the CI wait, right before the merge); every check reported by `gh pr checks` has succeeded, waiting at most 15 minutes for pending checks, accepting a result only after a 90-second grace period, requiring at least one `pull_request` check when a workflow runs on every pull request, and treating a PR with no checks as passing only when no such workflow exists; the PR body has no closing reference and no commit subject or body carries a `close`, `fix`, or `resolve` keyword before an issue reference (`#<digits>`, `owner/repo#<digits>`, or an issue or pull-request URL, a preceding hyphen or slash included); and the squash subject and body that `idd-all` composes reference the issue only as `Refs #<N>` and pass the same scan. The PR SHALL come from this repository (not a fork) and the default branch SHALL have no merge queue. The merge SHALL be pinned to the verified head commit (`--match-head-commit`), and `idd-all` SHALL confirm that the PR is `MERGED` with a merge commit before invoking `/idd-close`; a PR still open after the merge call SHALL have auto-merge disabled and the run SHALL stop, and a merge it cannot confirm SHALL be reported as possibly merged. If any check fails, `idd-all` SHALL NOT merge, SHALL stop at verified, and SHALL name the failed guardrail in the run report.

#### Scenario: A CI check fails

- **GIVEN** the verify gate reports `clean`
- **AND** `gh pr checks` reports one failed check named `test`
- **WHEN** the guardrails run
- **THEN** `idd-all` does not merge and the run report contains `Stopped:` naming the CI guardrail and the check `test`

#### Scenario: The PR head moved after verify

- **GIVEN** the verify report names commit `abc…` as reviewed
- **AND** a new commit was pushed to the PR branch afterwards
- **WHEN** the guardrails run
- **THEN** guardrail 1 reports that the reviewed commit is not the PR head and `idd-all` does not merge

#### Scenario: A report posted by another account

- **GIVEN** the newest `## Verify: #<N>` comment that says PASS was posted by an account other than the one running the session
- **WHEN** the guardrails run
- **THEN** that comment is not read as the verify report, and `idd-all` does not merge on the strength of it

#### Scenario: A commit body would auto-close the issue

- **GIVEN** the verify gate reports `clean`
- **AND** one commit body on the branch contains a close keyword adjacent to the issue reference
- **WHEN** the guardrails run
- **THEN** `idd-all` does not merge and the run report names the auto-close trap guardrail and the commit

### Requirement: Verify gate parsing fails closed

The verify gate SHALL read the latest verify master comment and report exactly one of `clean`, `not_clean`, or `unparseable`. It SHALL report `unparseable` when the verdict line or the classification table cannot be found, when a classification value is not one of Blocking, In-scope fix, or Follow-up, when the verdict is PASS while the table contains a Blocking finding, when the verdict is FAIL while the table has neither a Blocking nor an In-scope fix finding, when a fenced code block is never closed (fences pair by character and length), when a row naming one of the three classes stands outside any findings table, when a table header ends in a decorated `Action`, when the verdict line does not state its blocking count or states counts that differ from the table, when a table has an `Action` column that is not its last column, when a row naming one of the three classes stands outside a findings table, and, when the commit to be merged is given, when the report does not carry exactly one `**Reviewed**` line whose head is that full commit and, when a base is given, whose range starts at that base. `idd-all` SHALL treat `unparseable` exactly like a failed guardrail: no merge, no close, and the reason in the run report.

#### Scenario: Classification table is missing

- **WHEN** the gate reads a verify comment whose verdict line says PASS but which has no classification table
- **THEN** the gate reports `unparseable` with the reason that the table was not found, and `idd-all` stops at verified

#### Scenario: Verdict contradicts the table

- **WHEN** the gate reads a verify comment whose verdict line says PASS and whose table has one Blocking row
- **THEN** the gate reports `unparseable` with the reason that the verdict contradicts the table

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

When `idd-all` merges, pushes, or closes, its Phase 6 report SHALL start with `Done:` and list the actual merge commit or pushed commits, the closed issue with a link to its closing summary, the number of changed files with added and deleted lines, the follow-up issues filed, the recorded residue, the outcome of distribution sync, and which verify reviewers ran and which were missing. It SHALL end with an `Undo:` section containing `gh issue reopen <N>` and `git revert <sha>`. When the run stops before closing, the report SHALL list only the steps actually done and add a `Stopped:` line naming the guardrail or close stop point and its verbatim reason.

#### Scenario: Successful run report

- **WHEN** a PR-mode run merges PR 412 as commit `abc1234` and closes issue 405
- **THEN** the report contains `merged PR #412`, `abc1234`, `closed #405`, the closing summary link, and the lines `gh issue reopen 405` and `git revert abc1234`

#### Scenario: Run stopped at a guardrail

- **WHEN** a run stops because the verify gate reported `unparseable`
- **THEN** the report contains no `merged` or `closed` line and contains `Stopped:` with the gate's reason
