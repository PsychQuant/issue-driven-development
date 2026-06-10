## Why

Multiple IDD agent sessions running `idd-implement`'s **direct-commit-on-main** path against the **same repo** share one working tree and trample each other (real incident, ai_martech 2026-06-03, ~3 concurrent sessions): (1) one session parks the shared `main` tree on its feature branch, so another session's `git status` changes between checks; (2) two sessions edit the same file, and `git add <file>` stages the other's unfinished hunk; (3) an orphan commit leaks a live crash to `main` (the FM-2 half, already fixed by #184). `idd-worktree-isolation` (#167) gives a worktree primitive, but its use is **advisory** ("prefer worktree") — there is no mechanism that makes a session actually isolate when (and only when) another session is live in the tree.

Direct-commit-on-main is fundamentally incompatible with concurrency: two sessions cannot both commit to `main` in one working tree. A fix must either serialize (lock) or branch (worktree). The converged design (spectra-discuss 2026-06-03) is **Option D — lock-based asymmetric escalation**: the first-comer holds the tree for free (zero tax, convention preserved); later-comers detect the lock and isolate *themselves* into a worktree. No session predicts the future or retroactively moves its tree.

## What Changes

- Add a **shared-working-tree lock** (`.claude/.idd/tree-lock`) carrying holder id + PID + heartbeat timestamp, with an atomic acquire and a release.
- `idd-implement` **Step 0.5** tries to acquire the lock: **acquired (first-come / solo)** → stay on the main tree, direct-commit-on-main, zero worktree tax; **held by another LIVE session** → self-escalate via the existing `scripts/idd-worktree.sh create <N>`, work in an isolated worktree+branch, merge back at close.
- `idd-close` **releases** the lock (and GCs the worktree, already wired by #167).
- **Stale-lock reclaim**: a crashed holder leaves a stale lock; a newcomer reclaims it by judging "is the holder still alive?" (PID liveness) — never "is the holder done?" (the idle≠done lesson — a later session never waits for the holder to finish, it isolates immediately).
- Promote the `pr-flow.md` / `worktree-isolation.md` concurrent-session guidance from **advisory** to **normative** (the lock is the mechanism).

## Non-Goals

(Recorded in design.md — Goals/Non-Goals.)

## Capabilities

### New Capabilities

- `concurrent-session-tree-lock`: the shared-working-tree lock + asymmetric escalation — lock file format + atomic acquire/release, the `idd-implement` Step 0.5 acquire-or-escalate decision, lock release at `idd-close`, and stale-lock reclaim by holder-liveness (never holder-doneness).

### Modified Capabilities

(none)

## Impact

- Affected specs: new `concurrent-session-tree-lock` (builds on existing `idd-worktree-isolation`)
- Affected code:
  - New:
    - plugins/issue-driven-dev/scripts/idd-tree-lock.sh
    - plugins/issue-driven-dev/scripts/tests/idd-tree-lock/test.sh
  - Modified:
    - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
    - plugins/issue-driven-dev/skills/idd-close/SKILL.md
    - plugins/issue-driven-dev/references/worktree-isolation.md
    - plugins/issue-driven-dev/references/pr-flow.md
    - plugins/issue-driven-dev/CHANGELOG.md
    - plugins/issue-driven-dev/.claude-plugin/plugin.json
    - .claude-plugin/marketplace.json
  - Removed: (none)
