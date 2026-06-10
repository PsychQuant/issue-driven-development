## 1. Lock helper (TDD)

- [x] 1.1 Write `plugins/issue-driven-dev/scripts/tests/idd-tree-lock/test.sh` (RED) sourcing the #156 `assert-helpers.sh`: fixtures for two-concurrent-acquires-one-winner, dead-PID-reclaim, live-PID-held (use the test's own `$$`), and release-then-reacquire. Done when the suite exists and fails (no helper yet). (Requirement: Shared-working-tree lock)
- [x] 1.2 Write `plugins/issue-driven-dev/scripts/idd-tree-lock.sh` (GREEN): subcommands `acquire` (atomic `mkdir`-based; writes holder/pid/heartbeat) / `release` / `holder` / `reclaim-stale`. Acquire on an existing lock reclaims iff the recorded PID is dead (`kill -0`), with a heartbeat-TTL backup only when the PID is unverifiable; never reclaims on idle. Exit 0 acquired/released, 3 held-by-live-other, 2 usage. Done when `scripts/tests/idd-tree-lock/test.sh` is all green. (Requirement: Stale-lock reclaim by holder liveness)

## 2. idd-implement Step 0.5 wiring

- [x] 2.1 In `plugins/issue-driven-dev/skills/idd-implement/SKILL.md` Step 0.5, call `idd-tree-lock.sh acquire` before working-tree resolution: exit 0 (solo/first-come) → stay on main, direct-commit, no worktree, print a one-line "tree lock acquired" note; exit 3 (held by live other) → invoke `scripts/idd-worktree.sh create <N>` and run in the isolated worktree+branch, without waiting for the holder. Done when the SKILL describes the acquire→solo/escalate decision and the no-wait rule. (Requirement: Asymmetric escalation at idd-implement Step 0.5)
- [x] 2.2 Fail-open: if the lock dir is unwritable, the Step 0.5 logic stays on the main tree with a visible warning and never aborts. Done when the SKILL documents the fail-open path. (Requirement: Lock release at close and fail-open on lock-infra failure)

## 3. idd-close release

- [x] 3.1 In `plugins/issue-driven-dev/skills/idd-close/SKILL.md`, release the tree lock at close (alongside the existing Step 6.7 worktree GC) so a subsequent `acquire` returns 0; add a `release_tree_lock` entry to the Step 0.5 Bootstrap TaskList. Done when the SKILL releases the lock and the bootstrap list covers it. (Requirement: Lock release at close and fail-open on lock-infra failure)

## 4. Normative docs

- [x] 4.1 [P] Update `plugins/issue-driven-dev/references/worktree-isolation.md` + `plugins/issue-driven-dev/references/pr-flow.md`: promote the concurrent-session guidance from advisory ("prefer a worktree") to the lock-driven normative behavior (the lock is the mechanism), and cross-reference the #184 companion gate. Done when both docs state the normative acquire/escalate contract.

## 5. Release plumbing

- [x] 5.1 Bump the plugin version (minor) in `plugins/issue-driven-dev/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`; add a CHANGELOG entry. Done when all three agree on the new version (2.85.0).

## 6. Verification

- [x] 6.1 Run `/idd-verify` on the change scope against the 5 spec requirements + their scenarios/examples; confirm the acquire-race, dead-PID-reclaim, live-PID-held, release, escalation, and fail-open behaviors each hold. Done when verify reports the spec scenarios satisfied.
