## Why

IDD's stateful operations (branch checkout, working-tree edits, commits, `.claude/.idd/` staging) all assume a single serial executor. Running multiple IDD pipelines in parallel — the motivation in PsychQuant/issue-driven-development#167 — makes them collide on the shared git working tree.

The `/idd-diagnose` of #167 reached a key insight: a git worktree isolates the working tree **and** the repo-relative `.claude/.idd/` staging dir simultaneously, because a worktree has its own working directory. The harness already ships the isolation primitives (`Agent(isolation:"worktree")`, `EnterWorktree`) and IDD already ships `--cwd` (every skill's git/gh ops can target an arbitrary path per `references/cross-repo-cwd.md`). So the missing piece is not isolation machinery — it is a **convention** that ties these together and a small helper to manage worktree lifecycle.

The `/spectra-discuss` of #167 converged on a YAGNI scope: ship the **multi-window** case (Case B — N independent Claude Code windows, each running one IDD) first, using N independent branches → N PRs (no merge-back). Clustering into a single PR remains the job of the existing **sequential** `/idd-all-chain`. The harder **within-window agent-teams** case (Case A — parallel sub-agents on one coherent feature needing merge-back) is explicitly deferred.

## What Changes

- A new **worktree-isolation convention**: each parallel IDD runs in a git worktree at `.claude/worktrees/idd-<N>/` on branch `idd/<N>-<slug>`, invoked via the existing `--cwd` flag. The convention is documented as a frozen contract so the deferred Case A change can build on it.
- A thin helper script `plugins/issue-driven-dev/scripts/idd-worktree.sh` with `create` / `cleanup` / `list` subcommands that encode worktree naming, `.claude/worktrees/` gitignore management in the target repo, and safe teardown.
- `/idd-implement` Phase 0.5 gains a worktree-aware clause: when invoked with `--cwd` into a worktree already checked out on a branch matching `idd/<N>-*`, it accepts that branch as the feature branch instead of requiring the default branch (git forbids two worktrees sharing the default branch, so the worktree must already be on a feature branch). This is what lets the helper-created worktree compose with `idd-implement` end-to-end.
- `/idd-close` gains a terminal worktree-GC step: after closing issue #N, it detects a worktree at `.claude/worktrees/idd-<N>/` and cleans it up (refusing on uncommitted changes).
- `references/cross-repo-cwd.md` cross-references the parallel worktree pattern so users discover it from the `--cwd` docs.

## Non-Goals

- **Case A (within-window agent teams) merge-back orchestration** — deferred to a future change. v1 does not add a protocol for collecting N parallel worktree branches into one cluster PR. Users who want a single clustered PR use the existing sequential `/idd-all-chain`.
- **New file locking for shared global state** — issue-N-scoped attachment naming (`issue_<N>_*`) and the #76-hardened `.claude/.idd/issue-runs/<run_id>.jsonl` are sufficient; v1 adds no mutex/flock layer.
- **A full `/idd-worktree` skill** — v1 ships a bash helper (matching the `manifest-append.sh` / `check-diagnosis-readiness.sh` precedent), not a new skill, to keep cognitive cost low.
- **Auto-parallelization** — IDD does not decide *when* to parallelize; the human/orchestrator opens windows and invokes the helper. v1 only removes the collision hazard.

## Capabilities

### New Capabilities

- `idd-worktree-isolation`: git-worktree-based isolation convention + lifecycle helper enabling multiple IDD pipelines to run concurrently (multi-window Case B) without working-tree/branch/staging collision, converging as N independent branches → N PRs.

### Modified Capabilities

(none)

## Impact

- Affected specs: new capability `idd-worktree-isolation`
- Affected code:
  - New: plugins/issue-driven-dev/scripts/idd-worktree.sh
  - New: plugins/issue-driven-dev/references/worktree-isolation.md
  - New: plugins/issue-driven-dev/scripts/tests/idd-worktree/test.sh
  - Modified: plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - Modified: plugins/issue-driven-dev/references/cross-repo-cwd.md
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
  - Modified: plugins/issue-driven-dev/.claude-plugin/plugin.json
  - Removed: (none)
