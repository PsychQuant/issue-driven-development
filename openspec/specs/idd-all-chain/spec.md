# idd-all-chain Specification

## Purpose

TBD - created by archiving change 'add-idd-all-chain-skill'. Update Purpose after archive.

## Requirements

### Requirement: idd-all-chain skill SHALL drive root issue plus auto-emergent spawn through one cluster branch and one PR

The `idd-all-chain` skill SHALL accept one or more root issue arguments (`/idd-all-chain #N` or `/idd-all-chain #N #M #P [--bfs] [--cwd <path>]`) and run a chain-solve workflow that:

1. Creates a single cluster branch from the default branch. When N=1 the branch is named `idd/chain-<N>-<slug>` (backward compatible). When N>1 the branch is named `idd/chain-multi-<hash8>-<root1-slug>`, where `hash8` is the first 8 hex characters of `sha256` over the sorted-ascending root numbers joined by `-`, and `root1-slug` is the slug of the lowest root issue's title. On branch-name collision the chain shell SHALL retry with `hash16` (first 16 hex characters); on double collision the shell SHALL abort with a manual cleanup hint.
2. Recursively invokes `/idd-all #M --in-chain` for each root issue and each chain-eligible spawned issue, using either DFS or BFS traversal as specified below.
3. Stops processing the chain queue when the queue is empty, the per-root depth limit (`chain_max_depth=3`) is reached for the current subtree, or the total issues cap (`chain_max_issues=10`) is reached for the whole chain.
4. Opens exactly one pull request after the chain completes, covering all chained issues across all root subtrees.
5. Stops at verified state and SHALL NOT auto-close any issue (user retains close authority per IDD discipline).

The skill MUST NOT alter the existing `/idd-all` skill's single-issue lifecycle behavior. `/idd-all` invocations without `--in-chain` flag MUST behave identically to v2.46.0+ baseline.

The skill SHALL accept an optional `--bfs` flag that selects BFS traversal mode (level-by-level across all root subtrees). When `--bfs` is absent the skill SHALL use DFS traversal mode (process one root subtree fully before advancing to the next root). In DFS mode the chain queue SHALL push newly spawned issues to the **front** of the queue. In BFS mode the chain queue SHALL push newly spawned issues to the **back** of the queue. The default mode is DFS.

Each root issue SHALL have its own independent depth counter starting at zero. Spawn entries SHALL inherit `depth = parent_depth + 1` within their root subtree. The `chain_max_depth` cap applies per-root subtree. The `chain_max_issues` cap applies to the union of all root subtrees combined.

#### Scenario: single-root invocation is backward compatible

- **GIVEN** issue #28 is OPEN
- **WHEN** user invokes `/idd-all-chain #28`
- **THEN** the chain shell creates branch `idd/chain-28-<slug>` (single-root naming)
- **AND** initializes manifest with `root_issues=[28]` and `traversal="dfs"`
- **AND** processes the chain in identical observable behavior to v2.55.0 single-root chain runs

#### Scenario: multi-root invocation uses hash branch naming and DFS by default

- **GIVEN** issues #44, #45, #50 are all OPEN
- **WHEN** user invokes `/idd-all-chain #44 #45 #50`
- **THEN** the chain shell creates branch `idd/chain-multi-<hash8>-<root-44-slug>` where `hash8` is computed from `sha256` of `44-45-50`
- **AND** initializes manifest with `root_issues=[44,45,50]` and `traversal="dfs"`
- **AND** processes root #44's full subtree (including any DFS-eligible spawns) before advancing to root #45
- **AND** advances to root #50 only after #45's subtree completes

#### Scenario: multi-root with explicit BFS flag

- **GIVEN** issues #44, #45, #50 are all OPEN
- **WHEN** user invokes `/idd-all-chain #44 #45 #50 --bfs`
- **THEN** the manifest records `traversal="bfs"`
- **AND** the chain queue uses push-back semantics
- **AND** roots #44, #45, #50 are processed in input order at the top level before any spawns are processed

##### Example: DFS vs BFS queue order with a single spawn

| Mode | Initial queue | Pop #44 | Spawn #X (from #44) added | Next pop |
| ---- | ------------- | ------- | ------------------------- | -------- |
| DFS  | [44, 45, 50]  | [45, 50] (current=44) | push-front: [X, 45, 50]   | X |
| BFS  | [44, 45, 50]  | [45, 50] (current=44) | push-back: [45, 50, X]    | 45 |

#### Scenario: per-root depth cap enforced

- **GIVEN** chain max-depth cap is 3
- **AND** root #44 has a chain of spawns: #44 → #X (depth 1 in #44 subtree) → #Y (depth 2) → #Z (depth 3) → #W would be depth 4
- **WHEN** the chain shell processes #Z
- **THEN** #W is filed as a follow-up issue with manifest entry (audit preserved)
- **AND** #W is NOT added to the chain queue (per-root depth limit enforced)
- **AND** the chain continues processing root #45's subtree independently

#### Scenario: total max-issues cap caps the whole chain

- **GIVEN** chain max-issues cap is 10
- **AND** roots #44 and #45 between them produce 10 processed issues in their combined subtrees
- **WHEN** an 11th spawn is filed
- **THEN** the 11th spawn is recorded in the manifest with its `root_id` set
- **AND** the 11th spawn is NOT added to the chain queue (total cap enforced)
- **AND** Phase 4 report lists the 11th spawn under "filed only, not chained (max-issues cap)"


<!-- @trace
source: multi-root-traversal-idd-all-chain
updated: 2026-05-18
code:
  - plugins/issue-driven-dev/skills/idd-verify/SKILL.md
  - plugins/issue-driven-dev/README.md
  - plugins/issue-driven-dev/references/chain-flow.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/CLAUDE.md
  - plugins/issue-driven-dev/references/spawn-manifest.md
  - plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-all-chain/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - plugins/issue-driven-dev/scripts/manifest-append.sh
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
-->

---
### Requirement: idd-all-chain SHALL halt the chain on verify failure and preserve partial commits

When any chained `/idd-all #M --in-chain` invocation completes with verify FAIL state, the chain shell MUST scope the halt to the failing root's subtree only (not the entire queue), preserve all commits already made on the cluster branch, and continue processing the chain queue for other root subtrees whose work is independent. Specifically the shell MUST:

1. Identify the `root_id` of the failing issue (from the manifest entry, or from `root_issues[0]` if the failing issue is a root itself)
2. Add that `root_id` to the `FAIL_ROOTS[]` set
3. Remove from the chain queue all pending issues whose `root_id` matches the failing root's `root_id` (the failing subtree is halted)
4. Continue processing the chain queue for other root subtrees (their work is not affected)
5. Preserve all commits already made on the cluster branch (the shell MUST NOT rebase, revert, or modify existing commits)

The shell MUST emit a final report in Phase 4 listing per-root PASS / FAIL / SKIPPED status.

When verify FAIL occurs on the only root subtree of the chain (single-root invocation or all other root subtrees already completed), behavior is equivalent to halting the entire queue.

#### Scenario: verify FAIL in one root subtree halts only that subtree

- **GIVEN** the chain queue contains pending issues from root #44 subtree and root #45 subtree
- **AND** root #44's spawn #X reaches verify FAIL
- **WHEN** the chain shell observes the FAIL
- **THEN** `FAIL_ROOTS` contains 44
- **AND** all pending issues with `root_id=44` are removed from the queue
- **AND** the queue continues processing issues with `root_id=45`
- **AND** the cluster branch retains all commits from both #44's partial work and #45's complete work
- **AND** Phase 4 report shows root #44 as `FAIL (verify FAIL at #X)` and root #45 as `PASS`

#### Scenario: single-root verify FAIL still halts the whole queue

- **GIVEN** `/idd-all-chain #28` is invoked (single root)
- **AND** `/idd-all #28 --in-chain` reaches Phase 4 verify and reports blocking findings
- **WHEN** the chain shell observes the FAIL
- **THEN** the chain queue is fully halted (no other root subtrees exist)
- **AND** the cluster branch retains partial commits made so far
- **AND** Phase 4 report shows root #28 as `FAIL (verify FAIL at #28)`


<!-- @trace
source: multi-root-traversal-idd-all-chain
updated: 2026-05-18
code:
  - plugins/issue-driven-dev/skills/idd-verify/SKILL.md
  - plugins/issue-driven-dev/README.md
  - plugins/issue-driven-dev/references/chain-flow.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/CLAUDE.md
  - plugins/issue-driven-dev/references/spawn-manifest.md
  - plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-all-chain/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - plugins/issue-driven-dev/scripts/manifest-append.sh
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
-->

---
### Requirement: idd-all-chain SHALL produce a cluster PR with collapsed per-issue sections

After the chain queue is processed (full success, per-root partial failure, or any combination), `idd-all-chain` Phase 3 SHALL open exactly one pull request whose body contains:

1. PR title:
   - When N=1: `chain: <root title>` (backward compatible)
   - When N>1: `chain (multi-root): N issues — <root#1 title>` where `<root#1 title>` is the title of the lowest-numbered root issue
2. `Refs #<root_1> #<root_2> ... #<chained_1> #<chained_2> ...` listing all chained issue numbers (all roots first, then their spawns)
3. A `## Cluster overview` section with a table summarizing each issue (issue number, `root_id` it belongs to, spawn source, phase, head commit)
4. A `## Per-issue details` section using collapsed `<details>` HTML elements per issue
5. A `## Pending review` checklist where the final box reads `Pending: human review of cluster PR + /idd-close <issue list> after merge`

The PR body SHALL NOT contain `Closes #N` / `Fixes #N` / `Resolves #N` trailers (per existing IDD discipline against auto-close).

#### Scenario: single-root cluster PR uses chain prefix

- **GIVEN** chain solved root #28 with spawn #34
- **WHEN** Phase 3 opens the cluster PR
- **THEN** the PR title is `chain: <#28 title>`
- **AND** the body contains `Refs #28 #34`

#### Scenario: multi-root cluster PR uses chain (multi-root) prefix

- **GIVEN** chain solved roots #44, #45, #50 with one additional spawn #X from root #44
- **WHEN** Phase 3 opens the cluster PR
- **THEN** the PR title is `chain (multi-root): 4 issues — <#44 title>`
- **AND** the body contains `Refs #44 #45 #50 #X`
- **AND** the cluster overview table includes a `root_id` column showing #X belongs to root_id=44


<!-- @trace
source: multi-root-traversal-idd-all-chain
updated: 2026-05-18
code:
  - plugins/issue-driven-dev/skills/idd-verify/SKILL.md
  - plugins/issue-driven-dev/README.md
  - plugins/issue-driven-dev/references/chain-flow.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/CLAUDE.md
  - plugins/issue-driven-dev/references/spawn-manifest.md
  - plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-all-chain/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - plugins/issue-driven-dev/scripts/manifest-append.sh
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
-->

---
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

<!-- @trace
source: add-idd-all-chain-skill
updated: 2026-05-10
code:
  - .spectra.yaml
  - .agents/skills/spectra-ingest/SKILL.md
  - plugins/issue-driven-dev/scripts/manifest-append.sh
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/CLAUDE.md
  - .agents/skills/spectra-archive/SKILL.md
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/spectra-apply/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/references/spawn-manifest.md
  - .agents/skills/spectra-commit/SKILL.md
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .claude-plugin/marketplace.json
  - .agents/skills/spectra-drift/SKILL.md
  - plugins/issue-driven-dev/skills/idd-all-chain/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - plugins/issue-driven-dev/skills/idd-verify/SKILL.md
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - docs/design-patterns/default-dilemma.md
  - plugins/issue-driven-dev/references/chain-flow.md
  - .agents/skills/spectra-debug/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - AGENTS.md
-->

---
### Requirement: idd-all-chain SHALL emit a Phase 4 final report with forest-tree visualization for multi-root chains

When the chain shell completes the queue (success or per-root failure), Phase 4 SHALL emit a final report containing:

1. A traversal mode line indicating the chosen mode (`Forest summary (traversal: dfs)` or `Forest summary (traversal: bfs)`).
2. A forest visualization: one tree per root issue. Each node shall display the issue number, depth within its root subtree, spawn source (sub-skill + spawn kind) for non-root nodes, and a status icon (`✓` for PASS, `✗` for FAIL, `⊘` for filed-but-not-chained).
3. A per-root summary listing each root's final status: `PASS (N spawn processed)` / `FAIL (verify FAIL at #X — subtree halted)` / `SKIPPED (max-issues cap)` / `SKIPPED (root not OPEN)`.
4. A flat list of filed-only-not-chained issues (those that hit a cap or eligibility filter).

For single-root chains (N=1), the forest visualization SHALL contain exactly one tree, and the per-root summary SHALL contain exactly one entry.

#### Scenario: multi-root forest report shows per-root status

- **GIVEN** roots #44 (PASS, 2 spawn processed), #45 (FAIL at #48), #50 (filed but unprocessed due to max-issues cap)
- **WHEN** Phase 4 emits the report
- **THEN** the report contains a `Forest summary (traversal: dfs)` header
- **AND** lists a `✓` node for root #44 with its two `✓` descendant nodes
- **AND** lists a `✗` node for root #45 with the failing spawn #48 shown as `✗`
- **AND** lists a `⊘` node for root #50 with annotation `(max-issues cap)`
- **AND** the per-root summary lists `#44: PASS (2 spawn processed)`, `#45: FAIL (verify FAIL at #48 — subtree halted)`, `#50: SKIPPED (max-issues cap)`

##### Example: forest tree output for the scenario above

```
Forest summary (traversal: dfs):

  ✓ root #44 (depth 0)
    ✓ #34 (depth 1, idd-implement Step 5.7 sister-bug)
      ✓ #41 (depth 2, idd-verify Phase 4 follow-up-finding)
  ✗ root #45 (depth 0) — FAIL at #48
    ✗ #48 (depth 1, idd-plan Step 2.5 tangential)
  ⊘ root #50 (depth 0) — filed but unprocessed (max-issues cap)

Per-root PASS/FAIL:
  #44: PASS (2 spawn processed)
  #45: FAIL (verify FAIL at #48 — subtree halted)
  #50: SKIPPED (max-issues cap)
```

<!-- @trace
source: multi-root-traversal-idd-all-chain
updated: 2026-05-18
code:
  - plugins/issue-driven-dev/skills/idd-verify/SKILL.md
  - plugins/issue-driven-dev/README.md
  - plugins/issue-driven-dev/references/chain-flow.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/CLAUDE.md
  - plugins/issue-driven-dev/references/spawn-manifest.md
  - plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-all-chain/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - plugins/issue-driven-dev/scripts/manifest-append.sh
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
-->