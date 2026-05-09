## ADDED Requirements

### Requirement: idd-all-chain skill SHALL drive root issue plus auto-emergent spawn through one cluster branch and one PR

The `idd-all-chain` skill SHALL accept a single root issue argument (`/idd-all-chain #N`) and run a chain-solve workflow that:

1. Creates a single cluster branch named `idd/chain-<N>-<slug>` from the default branch
2. Recursively invokes `/idd-all #M --in-chain` for the root issue and each chain-eligible spawned issue
3. Stops the chain when the spawn queue is empty, depth limit is reached, or max-issues cap is reached
4. Opens exactly one pull request after the chain completes, covering all chained issues
5. Stops at verified state and SHALL NOT auto-close any issue (user retains close authority per IDD discipline)

The skill MUST NOT alter the existing `/idd-all` skill's single-issue lifecycle behavior. `/idd-all` invocations without `--in-chain` flag MUST behave identically to v2.46.0+ baseline.

#### Scenario: root issue with one chain-eligible spawn

- **GIVEN** issue #28 is OPEN and assigned no PR
- **WHEN** user invokes `/idd-all-chain #28`
- **AND** during the implement phase of #28, idd-implement Step 5.7 spawns issue #34 (sister-bug, same skill as #28)
- **THEN** `idd-all-chain` creates branch `idd/chain-28-<slug>` from main
- **AND** runs `/idd-all #28 --in-chain` to verified state on cluster branch
- **AND** detects #34 in the spawn manifest and runs `/idd-all #34 --in-chain` on the same branch
- **AND** opens one PR titled `chain: <#28 title>` referencing #28 and #34
- **AND** stops at verified state without closing either issue

#### Scenario: chain depth limit prevents runaway

- **GIVEN** chain depth limit is 2
- **AND** issue #28 spawns #34 at depth 1
- **AND** #34 spawn another issue #99 at depth 2
- **AND** #99 would spawn issue #100 at depth 3
- **WHEN** the chain shell processes #99
- **THEN** #100 is filed as a follow-up issue (existing audit trail behavior)
- **AND** #100 is NOT added to the chain queue (depth limit enforced)
- **AND** the cluster PR covers #28, #34, #99 only

#### Scenario: max-issues cap prevents PR bloat

- **GIVEN** chain max-issues cap is 5
- **WHEN** the chain queue reaches 5 chained issues (root + 4 chained)
- **AND** another spawn occurs
- **THEN** the new spawn is filed as a follow-up issue but NOT added to the chain queue
- **AND** the cluster PR covers exactly 5 issues

#### Scenario: chain-ineligible spawn is filed but not chained

- **GIVEN** issue #28 spawns issue #29 with `same_file_as_root=false` AND `same_skill_as_root=false` AND `spawn_kind != "sister-bug"`
- **WHEN** the chain shell processes the spawn manifest after #28 verify
- **THEN** #29 is filed as a follow-up issue (already done by sub-skill)
- **AND** #29 is NOT added to the chain queue
- **AND** the chain shell continues with other eligible spawns or terminates

### Requirement: idd-all-chain SHALL halt the chain on verify failure and preserve partial commits

When any chained `/idd-all #M --in-chain` invocation completes with verify FAIL state, the chain shell MUST halt the queue (no further chain processing) and preserve all commits already made on the cluster branch. The shell MUST NOT rebase, revert, or modify existing commits.

The shell MUST emit an abort report listing:
- All chained issues that completed successfully (issue number + verify URL + commit list)
- The failing issue number, the phase where verification failed, and a link to the verify findings comment
- All issues that remained in the queue and were skipped

#### Scenario: chain halts on verify FAIL

- **GIVEN** chain queue is `[#28, #34, #41]` and #28 completes successfully with 2 commits
- **WHEN** `/idd-all #34 --in-chain` reaches Phase 4 verify and reports blocking findings
- **THEN** the chain shell halts the queue
- **AND** does NOT process #41 (skipped, listed in abort report)
- **AND** does NOT rebase or revert #28 commits (cluster branch retains 2 verified commits + partial #34 commits)
- **AND** prints abort report citing #34 as failing issue with verify-findings URL

### Requirement: idd-all-chain SHALL produce a cluster PR with collapsed per-issue sections

After the chain queue is processed (success or partial failure), `idd-all-chain` Phase 3 SHALL open exactly one pull request whose body contains:

1. PR title prefix `chain:` followed by the root issue title
2. `Refs #<root> #<chained_1> #<chained_2> ...` listing all chained issue numbers
3. A `## Cluster overview` section with a table summarizing each issue (number, spawn source, phase, head commit)
4. A `## Per-issue details` section using collapsed `<details>` HTML elements per issue
5. A `## Pending review` checklist where the final box reads `Pending: human review of cluster PR + /idd-close <issue list> after merge`

The PR body SHALL NOT contain `Closes #N` / `Fixes #N` / `Resolves #N` trailers (per existing IDD discipline against auto-close).

#### Scenario: cluster PR body contains all required sections

- **GIVEN** chain solved #28 + #34 successfully
- **WHEN** `idd-all-chain` Phase 3 opens the cluster PR
- **THEN** the PR body contains a `## Cluster overview` table with rows for #28 and #34
- **AND** contains a `<details>` block per issue listing diagnose / verify / commit URLs
- **AND** contains `Refs #28 #34` (no `Closes`)
- **AND** the title begins with `chain:`

### Requirement: idd-all-chain SHALL provide chain-eligible heuristic based on spawn manifest fields

For each spawned issue, the chain shell MUST evaluate eligibility using the spawn manifest's `same_file_as_root`, `same_skill_as_root`, and `spawn_kind` fields. The eligibility rule:

```
chain_eligible(spawned, root) =
    spawned.same_file_as_root == true
    OR spawned.same_skill_as_root == true
    OR spawned.spawn_kind == "sister-bug"
```

Spawned issues that fail eligibility MUST still be filed as follow-up issues (existing sub-skill audit trail behavior preserved) but MUST NOT be added to the chain queue.

#### Scenario: same-file spawn is eligible

- **GIVEN** spawn manifest entry for #34 reports `same_file_as_root=true`
- **WHEN** the chain shell evaluates eligibility
- **THEN** #34 is added to the chain queue

#### Scenario: cross-cutting tracking spawn is ineligible

- **GIVEN** spawn manifest entry for #29 reports `same_file_as_root=false`, `same_skill_as_root=false`, `spawn_kind="upstream-tracking"`
- **WHEN** the chain shell evaluates eligibility
- **THEN** #29 is NOT added to the chain queue
- **AND** #29 remains a filed follow-up issue (sub-skill behavior preserved)
