## Context

IDD skills mutate git/filesystem state assuming a single serial executor. Running multiple IDD pipelines concurrently collides on the shared working tree, branch HEAD, and `.claude/.idd/` staging directory. PsychQuant/issue-driven-development#167 diagnosed this and `/spectra-discuss` converged on the scope below.

Two enabling facts already exist:

1. **`--cwd` plumbing** (`references/cross-repo-cwd.md`): every cwd-aware IDD skill rewrites `git X` to `git -C "$CWD" X` and `gh ... X` to `gh ... -R "$GITHUB_REPO"`. The target path only needs `.git` + an `origin` remote — a git worktree satisfies both.
2. **Worktree isolates staging for free**: because a git worktree has its own working directory and `.claude/.idd/` is a repo-relative path, each worktree gets its own `.claude/.idd/`. One isolation primitive covers working-tree, branch, and staging collisions simultaneously.

So the work is a convention + a thin helper, not new isolation machinery.

## Goals / Non-Goals

**Goals:**

- Let N independent Claude Code windows (Case B) each run a full IDD pipeline against the same repo without working-tree / branch / staging collision.
- Encode worktree naming, gitignore management, and safe teardown in one helper so users do not hand-run `git worktree` commands and forget cleanup.
- Freeze the worktree-isolation contract as a reference doc so the deferred Case A change builds on a stable foundation.

**Non-Goals:**

- Case A (single window calling agent teams) merge-back orchestration — N parallel worktree branches collected into one cluster PR. Deferred to a future change.
- New file-locking layer for shared global state.
- A new `/idd-worktree` skill (v1 ships a bash helper).
- Deciding *when* to parallelize — the human/orchestrator opens windows and invokes the helper.

## Decisions

### D1: Convergence = N branches → N PRs (no merge-back)

Each parallel IDD produces its own feature branch and its own PR (one per issue). v1 does NOT merge N worktree branches into one cluster PR.

Rationale: single-clustered-PR and parallelism are opposite convergence models. IDD already owns the sequential single-PR side (`/idd-all-chain` Phase 2 is a pop-invoke-enqueue loop on ONE cluster branch). Chasing parallel-into-one-PR would duplicate that machinery and add a worktree-branch merge-back step with conflict resolution. Taking the N-PRs branch deletes that entire problem. Users who want one clustered PR use the existing sequential `/idd-all-chain`.

### D2: Case A deferred out of v1

v1 ships Case B (multi-window) only. Case A (within-window agent teams sharing one process, where parallel sub-agents work on one coherent feature that must land as one PR) needs the merge-back protocol from D1's non-goal and a new orchestration entry point. It is recorded as the known next boundary in the reference doc, not built now.

Rationale: zero current IDD code invokes skills as parallel sub-agents (Case A is net-new orchestration); Case B reuses `--cwd`. The diagnose flagged Case A may be premature if real usage is mostly Case B. The user confirmed Case B is the primary target.

### D3: Helper is a bash script, not a skill

`plugins/issue-driven-dev/scripts/idd-worktree.sh` with `create` / `cleanup` / `list` subcommands.

Rationale: matches the existing extracted-helper precedent (`manifest-append.sh`, `check-diagnosis-readiness.sh`) — lower cognitive cost than a 15th skill for ~30% unique surface. The script is invokable both by a human (Case B setup) and by `idd-close` (auto-GC).

### D4: Worktree layout and branch ownership

- Worktree path: `.claude/worktrees/idd-<N>/` under the repo root (matches the harness `EnterWorktree` location).
- Branch: the helper creates the feature branch `idd/<N>-<slug>` at worktree-creation time (`git worktree add -b idd/<N>-<slug> <path> <default-branch>`). `slug` comes from `--slug`, else the gh issue title slugified (lowercase, non-alphanumeric → `-`, capped 40 chars), else bare `idd/<N>` when gh/title is unavailable.
- `.claude/worktrees/` is added to the target repo's `.gitignore` idempotently (marker-guarded append) so the worktree directory does not show as untracked in the main tree.

### D5: idd-implement composes via a Phase 0.5 worktree-branch acceptance clause

git refuses to check out the default branch in two worktrees, so a helper-created worktree is necessarily already on a feature branch. `idd-implement` Phase 0.5 currently aborts unless started from the default branch. The clause: when `git branch --show-current` matches `idd/<N>-*` (the issue number being implemented), accept it as the feature branch and skip branch creation — the same outcome as its existing "already on the expected feature branch" path, but slug-agnostic. This is the seam that lets a helper-created worktree drive `idd-implement #N --cwd <worktree>` end-to-end.

### D6: Auto-GC trigger = idd-close

After `idd-close` closes issue #N, it invokes `idd-worktree.sh cleanup <N>`. The worktree is removed; the branch is left intact (a PR may still be open / merged separately). Cleanup refuses if the worktree has uncommitted changes unless `--force`.

Rationale: `idd-close` is IDD's terminal step — the natural lifecycle end for an issue's worktree. PR-merge-detection was considered but rejected: it needs polling/event infrastructure IDD does not have, and a closed issue is the durable "this work is done" signal.

### D7: No new locking for shared global state

Attachment uploads are named `issue_<N>_*` (issue-scoped — different issues never collide; same-issue parallel processing is a rare re-run). `.claude/.idd/issue-runs/<run_id>.jsonl` is already collision-hardened (#76: ms-precision run_id + nonce + noclobber). The `~/.cache/idd-route/stats.jsonl` append is line-oriented and tolerant of rare interleave. v1 adds no mutex.

## Implementation Contract

**Behavior (observable):**

- `bash plugins/issue-driven-dev/scripts/idd-worktree.sh create <N> [--slug <s>] [--repo-root <path>]` creates `.claude/worktrees/idd-<N>/` on branch `idd/<N>-<slug>`, ensures `.claude/worktrees/` is gitignored, and prints the absolute worktree path on stdout (the value to pass to `--cwd`). Re-running for an existing `<N>` prints the existing path and exits 0 (idempotent).
- `idd-worktree.sh cleanup <N> [--force] [--repo-root <path>]` removes the worktree. Missing worktree → exit 0 (idempotent no-op). Uncommitted changes without `--force` → refuse.
- `idd-worktree.sh list [--repo-root <path>]` prints one line per IDD worktree: `<N>  <branch>  <path>`.
- `idd-implement #N --cwd .claude/worktrees/idd-N` runs the full pipeline on the worktree's `idd/<N>-*` branch without aborting on the default-branch precondition.
- After `idd-close #N`, the worktree `.claude/worktrees/idd-<N>/` no longer exists (clean tree) or a refusal is surfaced (dirty tree).

**Interface / data shape:**

- Subcommands: `create`, `cleanup`, `list`. Flags: `--slug`, `--repo-root`, `--force`.
- Exit codes: `0` success, `1` generic error, `2` usage error, `3` not a git repository, `4` branch-name conflict (a branch `idd/<N>-*` already exists on a DIFFERENT worktree/path), `5` refuse-dirty (cleanup blocked by uncommitted changes without `--force`).
- stdout of `create` is exactly the worktree absolute path (parseable by callers / `--cwd`).

**Failure modes:**

- Target path is not a git repo → exit 3, message naming `--repo-root`.
- `create` when the branch exists on another worktree → exit 4, message naming the conflicting path.
- `cleanup` dirty without `--force` → exit 5, message listing the dirty worktree; the worktree is left intact.
- `idd-close` GC: if `idd-worktree.sh` is absent (older plugin) or cleanup refuses, `idd-close` surfaces a one-line warning and still completes the close (GC is best-effort, never blocks close).

**Acceptance criteria:**

- `plugins/issue-driven-dev/scripts/tests/idd-worktree/test.sh` passes: fixtures cover create (fresh / idempotent re-run / gitignore-append idempotency), cleanup (clean / dirty-refuse / dirty-force / missing-no-op), list, and the exit codes above, using a throwaway git repo per fixture.
- Manual: in a scratch repo, `create 1` then `create 2` yields two worktrees on distinct branches; `idd-implement` semantics (branch acceptance) confirmed by the Phase 0.5 clause text + a unit assertion that a branch matching `idd/<N>-*` is accepted.

**Scope boundaries:**

- In scope: the helper, the reference doc, the `idd-implement` Phase 0.5 clause, the `idd-close` GC step, the `cross-repo-cwd.md` cross-reference, CHANGELOG.
- Out of scope: Case A merge-back, any change to `idd-diagnose` / `idd-verify` (they already compose via `--cwd` unchanged), any locking layer, any auto-parallelization logic.

## Risks / Trade-offs

- **Shared `.git` ref contention**: worktrees have independent indexes but share refs/packed-refs. Concurrent commits updating different branch refs are normally safe, but heavy concurrency could rarely contend on `index.lock` at the `.git` level. Mitigation: documented as a known boundary; v1 targets human-paced multi-window use (low concurrency), not high-fanout automation.
- **Worktree leak**: if `idd-close` never runs (issue abandoned), the worktree persists. Mitigation: `idd-worktree.sh list` surfaces orphans for manual `cleanup`.
- **Slug divergence**: helper-created branch slug vs what a human expects. Mitigation: D5's acceptance clause is slug-agnostic (matches `idd/<N>-*`), so exact slug agreement is not required.
- **N-PRs review cost**: parallel work produces N PRs instead of one clustered PR. Trade-off accepted per D1 — users wanting one PR use sequential `/idd-all-chain`.
