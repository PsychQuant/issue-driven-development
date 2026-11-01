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

When the resolved path is `direct-commit`, `idd-all` SHALL NOT create a feature branch and SHALL NOT create a PR. Commits land on whichever branch the user currently has checked out. `idd-all` SHALL NOT push during Phases 1 to 4. After a clean verify, `idd-all` SHALL push only when the current branch is the default branch, and only so that the fix exists on the remote default branch before the issue is closed; on any other branch it SHALL stop at verified without pushing.

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

## REMOVED Requirements

### Requirement: Verify is the terminal phase regardless of mode

**Reason**: #392 moves the terminal state from verified to closed. Merging a PR and closing an issue are both recoverable (revert, reopen), so under the Foresay traceable branch they run without a prior confirmation, provided the run reports what it did. The guarantee "`idd-all` MUST NOT auto-invoke `idd-close`" is replaced by the requirement "Clean verify leads to merge and close".

**Migration**: Callers that need the previous stop-at-verified behaviour pass `--review`, which keeps `idd-all` at verified with the "awaiting human acceptance" wording. `/idd-all-chain` (`--in-chain`) and `type=meeting` runs are unaffected.

## ADDED Requirements

### Requirement: Clean verify leads to merge and close

After verify, `idd-all` SHALL ask the verify gate whether the latest verify round is clean. When the gate reports `clean`, the path is `PR`, and every merge guardrail passes, `idd-all` SHALL squash-merge the PR, fetch the remote default branch, and invoke `/idd-close #<N>` with the orchestrated directive, without asking the user first. When the path is `direct-commit`, the push-then-close behaviour of the requirement "Direct-commit path stays on current branch and skips PR" applies. `idd-all` SHALL NOT merge or close when the run carries `--review`, when it runs with `--in-chain`, or when the issue type is `meeting`.

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

When the resolved interaction is `unattended` and the verify gate reports `not_clean`, `idd-all` SHALL fix every Blocking and every In-scope fix finding in the same branch and run verify again, for at most 2 fix rounds in total. If the gate still reports `not_clean` after the second round, `idd-all` SHALL stop at verified without merging or closing. When the resolved interaction is `attended`, `idd-all` SHALL NOT fix findings automatically; it SHALL hand the findings back to the user, and merge and close only follow a later round that the gate reports `clean`.

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

Before an automatic merge, `idd-all` SHALL check, in order: the verify gate reports `clean`; every check reported by `gh pr checks` has succeeded, waiting at most 15 minutes for pending checks and treating a PR with no checks as passing; the Step 0.8 auto-close trap scan of the PR body and every commit body is clean; and the squash subject and body that `idd-all` composes reference the issue only as `Refs #<N>` and contain no `close`, `fix`, or `resolve` keyword adjacent to a `#<digits>` reference. If any check fails, `idd-all` SHALL NOT merge, SHALL stop at verified, and SHALL name the failed guardrail in the run report.

#### Scenario: A CI check fails

- **GIVEN** the verify gate reports `clean`
- **AND** `gh pr checks` reports one failed check named `test`
- **WHEN** the guardrails run
- **THEN** `idd-all` does not merge and the run report contains `Stopped:` naming the CI guardrail and the check `test`

#### Scenario: A commit body would auto-close the issue

- **GIVEN** the verify gate reports `clean`
- **AND** one commit body on the branch contains a close keyword adjacent to the issue reference
- **WHEN** the guardrails run
- **THEN** `idd-all` does not merge and the run report names the auto-close trap guardrail and the commit

### Requirement: Verify gate parsing fails closed

The verify gate SHALL read the latest verify master comment and report exactly one of `clean`, `not_clean`, or `unparseable`. It SHALL report `unparseable` when the verdict line or the classification table cannot be found, when a classification value is not one of Blocking, In-scope fix, or Follow-up, or when the verdict is PASS while the table contains a Blocking finding. `idd-all` SHALL treat `unparseable` exactly like a failed guardrail: no merge, no close, and the reason in the run report.

#### Scenario: Classification table is missing

- **WHEN** the gate reads a verify comment whose verdict line says PASS but which has no classification table
- **THEN** the gate reports `unparseable` with the reason that the table was not found, and `idd-all` stops at verified

#### Scenario: Verdict contradicts the table

- **WHEN** the gate reads a verify comment whose verdict line says PASS and whose table has one Blocking row
- **THEN** the gate reports `unparseable` with the reason that the verdict contradicts the table

### Requirement: idd-close honors the orchestrated directive from idd-all

When `/idd-close` is invoked with the `ORCHESTRATED BY /idd-all` directive, it SHALL apply these defaults instead of asking the user: when Step 1.55 reports commits not on the default branch, or Step 1.6 reports a checked item without a matching commit, it SHALL stop without closing and report why; follow-up mentions found by Step 3.5 SHALL be filed as issues per the IC_R011 default; a non-empty Residue read by Step 3.6 SHALL be recorded as residue without filing an issue; the Step 6.5 distribution sync SHALL ask the user when the interaction is attended and SHALL be skipped, with the command to run listed in the report, when the interaction is unattended. Without the directive, `/idd-close` SHALL behave exactly as before.

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
