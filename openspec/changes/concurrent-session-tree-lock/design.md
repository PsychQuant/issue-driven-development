## Context

`idd-worktree-isolation` (#167) ships a managed worktree lifecycle (`scripts/idd-worktree.sh`: create / cleanup / list under `.claude/worktrees/idd-<N>/`, with `idd-implement` worktree-branch acceptance and `idd-close` GC), but its concurrent-session guidance is **advisory** — nothing makes a session isolate when another is live in the shared tree. The real failure mode (FM-1): N sessions on the direct-commit-on-main path share one tree → branch parking, same-file WIP mixing, `git status` races. FM-2 (orphan commit) is orthogonal and already fixed by #184's merge-completeness gate; escalated sessions branch+merge, so that gate is a required companion, not optional.

## Goals / Non-Goals

**Goals:**
- A solo session pays **zero** tax: it holds the tree and direct-commits to main exactly as today.
- A concurrent session **isolates itself** (worktree) automatically, with no prediction and no retroactive tree move.
- "Is someone else live in this tree?" is answered by **holder liveness**, never by "are they done?" (idle ≠ done).
- Reuse the existing `idd-worktree.sh` primitive for the isolated worktree.

**Non-Goals:**
- Not a multi-session **orchestration / scheduling** model (who runs what when) — only working-tree isolation. The broader "concurrent IDD orchestration" horizon is #183's recorded residue, deferred.
- Not changing the PR-vs-direct-commit (`idd-pr-hitl-modes`) semantics — the lock decides *where the tree is*, not *whether a PR opens*.
- Not cross-machine locking — a working tree is local; concurrency is same-machine, so PID liveness is sufficient.
- Not FM-2 (orphan gate) — shipped separately in #184.
- Not unconditional worktree-default (rejected Option A: taxes solo sessions + amplifies FM-2); not a pure warn-guard (rejected Option C: surfaces but does not structurally prevent FM-1).

## Decisions

**D1 — Lock file at `.claude/.idd/tree-lock`, holder-identified, atomic acquire.**
Content: holder session id + PID + ISO timestamp (heartbeat). Acquire is atomic via `mkdir` (or `O_EXCL`/`noclobber`) so two simultaneous starts cannot both win. Lives under the existing `.claude/.idd/` namespace (gitignored), not `.git/`, so it is tooling state, not repo state.

**D2 — Asymmetric escalation at `idd-implement` Step 0.5.**
Try-acquire the lock. Won → record holder, stay on the main tree (current behavior, zero tax). Lost to a *live* holder → call `scripts/idd-worktree.sh create <N>` and run the issue in that worktree+branch (merge back at close: solo fast-forward looks like direct-commit; genuine divergence → real merge, with #184 catching any orphan). The later session never waits.

**D3 — Stale-lock reclaim by liveness, not doneness (the open question, resolved).**
Primary signal: **PID liveness** — `kill -0 <pid>` on the same machine cheaply answers "holder still running?" If the PID is dead, the lock is stale → reclaim atomically. Backup: a **heartbeat / mtime TTL** — if the lock is older than a bounded window (e.g. 30 min) AND the PID is unverifiable, treat as stale. PID-first because it is exact; TTL only as a safety net for the rare case the PID is unusable. Never reclaim on "holder looks idle" — the ai_martech watcher proved process-quiet ≠ session-done.

**Which PID (resolved at verify, #183 B1/rescope) — `$PPID`, scope = cross-terminal.** The recorded pid MUST be a *persistent* process that lives as long as the holder's session. The lock helper runs as a short-lived subprocess, so its own `$$` is dead the instant `acquire` returns — recording it makes every later acquire reclaim unconditionally, i.e. the lock provides **zero** isolation (the no-op the first cut shipped; verify caught it). The correct anchor is **`$PPID`** — the harness shell, stable across a `claude` instance's Bash calls and dead once that instance exits. This gives real isolation between sessions in **separate terminals / instances** (the actual incident: ~3 parallel sessions in separate terminals), which is the in-scope concurrency. The one case `$PPID` cannot distinguish — sub-agents *within one instance* sharing a `$PPID` — is exactly **"Case A within-window agent teams", already deferred** in `worktree-isolation.md`, so it is out of scope by prior decision, not a new gap. idd-implement Step 0.4 passes `--pid "$PPID"`; the helper also defaults to `$PPID`. Acceptance fixtures use a real, killable background process as the holder (never the always-alive test-runner pid) so they fail if the recorded pid is ephemeral.

**Atomicity (resolved at verify, B2/B3).** The lock is a FILE created with `set -C` (noclobber) so create-with-content is one indivisible step (no mkdir-then-write window where a competitor sees an empty lock). Stale reclaim moves the file aside with `mv` (one racer wins) before re-creating, so a late reclaimer cannot wipe a fresh lock another session just took. A fresh lock with no readable pid (the brief create window) is treated as held, not stolen.

**D4 — Lock released at `idd-close` / session end; escalation requires #184.**
`idd-close` releases the lock (in addition to the existing worktree GC). Because escalated sessions branch+merge, the #184 merge-completeness gate is a hard companion — it is already shipped, so this change depends on it but adds no new gate.

**D5 — Promote concurrent-session guidance to normative.**
`references/worktree-isolation.md` + `references/pr-flow.md` change the "prefer a worktree" advisory into the lock-driven normative behavior, with the lock as the mechanism.

## Implementation Contract

- **Behavior**: starting `idd-implement #N` in a repo where no live session holds the tree → works on main, direct-commit (unchanged, zero new output beyond a one-line "tree lock acquired" note). Starting it while another live session holds the tree → prints an escalation notice and runs in `.claude/worktrees/idd-<N>/`. On `idd-close`, the lock is released; a crashed holder's stale lock is reclaimed by the next starter.
- **Interface**:
  - `scripts/idd-tree-lock.sh acquire|release|holder|reclaim-stale [--repo <root>] [--id <session>]` — exit 0 acquired / 3 held-by-live-other / 0 released / etc.
  - Lock file `.claude/.idd/tree-lock` with fields: `holder`, `pid`, `heartbeat` (ISO).
  - `idd-implement` Step 0.5 calls `acquire`; on exit-3 calls `idd-worktree.sh create <N>`.
  - `idd-close` calls `release`.
- **Failure modes**: acquire race → exactly one winner (atomic mkdir); the loser escalates, never blocks. Stale lock (dead PID) → reclaimed, surfaced with a one-line note. Lock dir unwritable → fail-open to current behavior (stay on main) + a visible warning, never hard-block (a lock-infra failure must not stop work).
- **Acceptance criteria**:
  - Two concurrent `acquire` calls on one repo → one returns 0 (acquired), the other returns 3 (held-by-live-other). Falsifiable in `scripts/tests/idd-tree-lock/test.sh`.
  - `acquire` against a lock whose recorded PID is dead → reclaims and returns 0.
  - `acquire` against a lock held by a live PID (this test's own `$$`) → returns 3.
  - `release` removes the lock; a subsequent `acquire` returns 0.
- **Scope boundaries**: in scope = the lock helper + tests, the Step 0.5 acquire/escalate wiring, the idd-close release, the docs promotion. Out of scope = cross-machine locking, an orchestration/scheduling model, FM-2 (#184), and any change to PR-vs-direct-commit resolution.

## Risks / Trade-offs

- **Lock infra failure stops work** → mitigation: fail-open (stay on main + warn), never hard-block; the lock is a convenience, correctness backstop is #184.
- **PID reuse** → a dead holder's PID reused by an unrelated process could look "live" → mitigation: the heartbeat TTL backup + the holder id (session id mismatch is a corroborating signal).
- **Escalation adds branch+merge for the later session** → amplifies the orphan risk the lock cannot see → mitigation: #184 is a required companion (already shipped).
- **Behavior change to a documented contract** (`worktree-isolation.md` / `pr-flow.md` go normative) → mitigation: solo behavior is byte-identical (zero tax); only the concurrent case changes, and it changes from "silently collide" to "isolate."
