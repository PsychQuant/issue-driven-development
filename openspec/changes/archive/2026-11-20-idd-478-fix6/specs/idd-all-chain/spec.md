## MODIFIED Requirements

### Requirement: idd-all-chain skill SHALL drive root issue plus auto-emergent spawn through one cluster branch and one PR

The `idd-all-chain` skill SHALL accept one or more root issue arguments (`/idd-all-chain #N` or `/idd-all-chain #N #M #P [--bfs] [--cwd <path>]`) and run a chain-solve workflow that:

1. Creates a single cluster branch from the default branch. When N=1 the branch is named `idd/chain-<N>-<slug>` (backward compatible). When N>1 the branch is named `idd/chain-multi-<hash8>-<root1-slug>`, where `hash8` is the first 8 hex characters of `sha256` over the sorted-ascending root numbers joined by `-`, and `root1-slug` is the slug of the lowest root issue's title. On branch-name collision the chain shell SHALL retry with `hash16` (first 16 hex characters); on double collision the shell SHALL abort with a manual cleanup hint.
2. Recursively invokes `/idd-all #M --in-chain` for each root issue and each chain-eligible spawned issue, using either DFS or BFS traversal as specified below.
3. Stops processing the chain queue when the queue is empty, the per-root depth limit (`chain_max_depth=3`) is reached for the current subtree, or the total issues cap (`chain_max_issues=10`) is reached for the whole chain.
4. Opens exactly one pull request after the chain completes, covering all chained issues across all root subtrees.
5. Stops at verified state and SHALL NOT auto-close any issue (user retains close authority per IDD discipline).

The skill MUST NOT alter the existing `/idd-all` skill's single-issue lifecycle behavior. `/idd-all` invocations that name an issue and carry no `--in-chain` flag MUST behave identically to v2.46.0+ baseline. An invocation without an issue is rest mode, which capability `idd-all-rest` defines.

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
