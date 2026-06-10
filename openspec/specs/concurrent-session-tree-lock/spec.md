# concurrent-session-tree-lock Specification

## Purpose

Defines the **shared-working-tree lock + asymmetric escalation** (`scripts/idd-tree-lock.sh`) that prevents FM-1 — concurrent IDD sessions in **separate terminals / `claude` instances** trampling one shared working tree (branch parking, same-file WIP mixing, `git status` races; ai_martech 2026-06-03 incident). The first session holds the tree for free (direct-commit, zero worktree tax); a later session that finds the lock held by a **live** holder self-escalates into an isolated worktree via `idd-worktree.sh`. Liveness is judged by the holder's persistent session PID (`$PPID`, `kill -0`) — never by "is the holder done" (idle ≠ done). Governs: the atomic lock-file contract, the `idd-implement` Step 0.4 acquire-or-escalate decision, `idd-close` Step 6.8 release, stale-lock reclaim, and fail-open on lock-infra failure (the #184 merge-completeness gate is the correctness backstop). Same-instance sub-agent concurrency is the deferred Case A in `idd-worktree-isolation`.

## Requirements

### Requirement: Shared-working-tree lock

The system SHALL provide a lock over a repository's shared working tree at `.claude/.idd/tree-lock`, acquired and released by a helper (`scripts/idd-tree-lock.sh`). Acquisition SHALL be atomic so that two simultaneous starts cannot both win. The lock SHALL record the holder's session id, PID, and a heartbeat timestamp. The lock SHALL live under the gitignored `.claude/.idd/` namespace (tooling state), not under version control.

#### Scenario: two concurrent acquires yield exactly one winner

- **WHEN** two sessions call `acquire` on the same repository at the same time
- **THEN** exactly one acquire succeeds (the lock is held by that session) and the other reports the lock is held by a live other session

##### Example: acquire / held / release lifecycle

- **GIVEN** a repository with no tree lock
- **WHEN** session A calls `acquire`, then session B (a live process) calls `acquire`, then session A calls `release`, then session B calls `acquire`
- **THEN** A's first acquire returns 0 (acquired), B's first acquire returns 3 (held by live other), and after A releases, B's second acquire returns 0

---
### Requirement: Asymmetric escalation at idd-implement Step 0.5

`idd-implement` Step 0.5 SHALL try to acquire the tree lock before resolving the working tree. If the lock is acquired (first-come or solo), the session SHALL stay on the main working tree and direct-commit as today, with no worktree created (zero tax, convention preserved). If the lock is held by another live session, the session SHALL self-escalate by invoking `scripts/idd-worktree.sh create <N>` and run the issue in that isolated worktree and branch, merging back at close. The escalating session SHALL NOT wait for the lock holder to finish; it isolates immediately.

#### Scenario: solo session stays on main

- **WHEN** `idd-implement #N` starts and no live session holds the tree lock
- **THEN** the session acquires the lock and works on the main tree (direct-commit), creating no worktree

#### Scenario: concurrent session escalates itself

- **WHEN** `idd-implement #N` starts while another live session holds the tree lock
- **THEN** the session invokes `idd-worktree.sh create <N>` and runs in `.claude/worktrees/idd-<N>/` on its own branch, without waiting for the holder

---
### Requirement: Stale-lock reclaim by holder liveness

A session attempting to acquire a lock that is already present SHALL decide whether to reclaim it by judging whether the **holder is still alive** (PID liveness via `kill -0`), never by judging whether the holder is **done**. If the recorded PID is dead, the lock SHALL be reclaimed atomically and acquisition SHALL succeed. If the PID is alive, acquisition SHALL report held-by-live-other. A heartbeat-TTL check MAY serve only as a backup when the PID cannot be verified; a lock SHALL NOT be reclaimed merely because the holder appears idle.

The recorded PID SHALL be a **persistent process that represents the holder's live session** (the harness shell, `$PPID`) — NOT the ephemeral pid of the short-lived lock helper subprocess (`$$`), which dies the instant `acquire` returns and would make every subsequent acquire reclaim the lock unconditionally (defeating isolation entirely). Acceptance fixtures SHALL exercise alive/dead holders using a **separate process whose lifetime the test controls**, not the always-alive test-runner pid, so the fixtures fail if the recorded pid is the ephemeral helper pid.

#### Scenario: dead holder's lock is reclaimed

- **WHEN** a session calls `acquire` and the existing lock's recorded PID is not a running process
- **THEN** the lock is reclaimed and the call returns 0 (acquired)

#### Scenario: live holder's lock is not reclaimed

- **WHEN** a session calls `acquire` and the existing lock's recorded PID is a running process
- **THEN** the call returns 3 (held by live other) and the lock is not reclaimed

#### Scenario: the recorded PID outlives the lock helper subprocess

- **WHEN** a session calls `acquire` without an explicit pid (taking the default)
- **THEN** the recorded PID is the invoking harness shell (`$PPID`), which is still alive after the lock helper subprocess has exited — never the helper's own ephemeral pid

---
### Requirement: Lock release at close and fail-open on lock-infra failure

`idd-close` SHALL release the tree lock held for the issue (in addition to the existing worktree garbage collection). If the lock directory cannot be created or written (lock-infra failure), the system SHALL fail open — proceed on the main working tree with a visible warning — and SHALL NOT hard-block work, because the lock is a convenience and the correctness backstop is the #184 merge-completeness gate.

#### Scenario: close releases the lock

- **WHEN** `idd-close #N` runs for a session that held the tree lock
- **THEN** the lock is released so a subsequent `acquire` on that repository returns 0

#### Scenario: lock-infra failure does not block work

- **WHEN** the lock directory cannot be written
- **THEN** the session proceeds on the main tree with a visible warning rather than aborting
