# Chain Flow Contract

> Canonical contract for `/idd-all-chain` — the shell algorithm that drives a root issue plus its auto-emergent spawned issues through ONE cluster branch and ONE review PR.

**Source**: `add-idd-all-chain-skill` Spectra change (capability `idd-all-chain`).

This document defines the **algorithmic contract** the chain shell honors. Implementation lives in `plugins/issue-driven-dev/skills/idd-all-chain/SKILL.md`; this file is the spec the implementation must match.

## Phases

| Phase | Action | Side effects |
|-------|--------|--------------|
| 0 | Pre-flight (5 gates: git repo / gh auth / issue OPEN / **diagnosis-readiness** / clean tree) + cluster branch setup + manifest init | May PATCH issue body (audit trail) when diagnosis bypassed; creates `idd/chain-<root>-<slug>` branch; writes `.claude/.idd/state/chain-spawned-issues.json` schema_version=1 |
| 1 | Initialize chain state (queue, depth_map, processed set) | In-memory only |
| 2 | Main chain loop — pop, invoke `/idd-all #N --in-chain`, read manifest delta, enqueue eligible spawns | Commits on cluster branch (via sub-`/idd-all`); manifest grows append-only |
| 3 | Open cluster PR with collapsed per-issue sections | `git push` cluster branch; `gh pr create` |
| 4 | Final report; STOP at verified | Print summary; no auto-close, no auto-merge |

A chain run is fully determined by `(root_issue, working_tree_state, manifest_writes_during_run, user_choice_at_diagnosis_gate)`. No external state.

## Diagnosis-readiness gate (Phase 0 Step 0.4, v2.55+ #47)

Phase 0 includes a diagnosis-readiness gate **before** any branch / manifest creation. Detects whether the root issue has a `## Diagnosis` comment via `comments[*].body` filter (precise — does NOT inspect issue body, which may discuss "diagnosis" conceptually).

When detection finds no diagnosis comment, the chain shell fires `AskUserQuestion` with three options reflecting different mental models:

- **`run /idd-diagnose first`** — diagnosis-first discipline (default safest). Halts cleanly with zero side effects (no branch / manifest yet); user runs `/idd-diagnose #N` then re-invokes `/idd-all-chain`.
- **`proceed anyway`** — escape hatch for fresh-issue / quick-iter scenarios. PATCHes issue body with `### Chain pre-flight: diagnosis bypassed` audit section so future readers know this chain ran without prior diagnose.
- **`cancel`** — clean recovery. Same as `run /idd-diagnose first` mechanically (zero side effect, just exits) but communicates "user changed mind" rather than "user will diagnose later". Print explicit `(no cleanup needed — Phase 0.4 ran before any branch/manifest creation)` to remove confusion.

**No unattended fallback by design**: `/idd-all-chain` is a user-invoked deliberation moment. There is no automated caller path (`/loop`, cron, etc.) that should reach Step 0.4. If the call is made non-interactively for some reason, the AskUserQuestion will block — that is the correct behavior, not a bug. (Earlier draft included an `IN_CHAIN_CONTEXT` env detection for unattended fallback, but `/idd-verify #47` proved it was dead code with no producer in the repo, so the fallback was removed.)

**Why placement before branch/manifest creation matters**: cancel-path side-effect minimization. If user picks `cancel`, no work is undone — there is no work yet. Diagnosis-readiness gate placed AFTER branch creation would leave dangling cluster branches user must manually delete, breaking IDD's halt+preserve discipline (preserve assumes there's something worth preserving).

**Implementation** (v2.57.0+, #51): extracted from inline bash to standalone helper at `plugins/issue-driven-dev/scripts/check-diagnosis-readiness.sh`. Variadic positional signature: `check-diagnosis-readiness.sh <github-repo> <issue-number> [<issue-number>...]` emits `{"ready":[N,...],"not_ready":[N,...]}` JSON to stdout. Exit codes 0 (success) / 1 (gh-jq failure) / 2 (usage error) per `manifest-append.sh` precedent. v1 single-root invocation; ready for #46 multi-root chain to call with multiple issue numbers without API change.

## Cluster branch naming

Branch naming dispatches on N (number of roots passed to `/idd-all-chain`):

**N=1 (backward compatible)**:

```
idd/chain-<root_issue_number>-<slug>
```

**N>1 (multi-root, v2.60+, #46)**:

```
idd/chain-multi-<hash8>-<root1-slug>
```

- `hash8` = first 8 hex chars of `sha256(roots_joined)` where `roots_joined` is the sorted-ascending root issue numbers joined by `-` (e.g. `44-45-50` for roots #44, #45, #50). Same root set → same hash, deterministic.
- `root1-slug` = lowercased title slug of the **lowest** root issue (also deterministic given the sorted root set).
- Hash collision on `hash8` → fallback to `hash16` (first 16 hex chars); double collision → Phase 0.5 abort with manual cleanup hint.

**Common rules** (both N=1 and N>1):

- `slug` / `root1-slug` = lowercased title, non-alphanumeric → `-`, capped at 40 chars, leading/trailing `-` trimmed
- The chain shell MUST refuse to start if a branch with the dispatched name already exists (N=1 single-root naming) — manual cleanup required
- Sub-`/idd-all #M --in-chain` Step 0.5 sanity check MUST verify the current branch matches `^idd/chain-` prefix (covers both `idd/chain-<N>-` and `idd/chain-multi-` forms); otherwise abort

## Chain state

```
QUEUE          : ordered list of pending issues (seeded with all roots in sorted order)
DEPTH_MAP      : issue → integer depth WITHIN its owning root's subtree (each root=0)
ROOT_ID_MAP    : issue → owning root id (which subtree it belongs to)
PROCESSED      : issue → "verified" | "failed"
CHAINED_ORDER  : ordered list of verified issues (used to build PR body)
FAIL_ROOTS     : set of root ids whose subtree FAILed (verify FAIL)
FAILED_AT      : ordered list of failing issues (used in Phase 4 forest report)
TRAVERSAL      : "dfs" (default) | "bfs" (when --bfs flag present)
```

Caps (hard-coded constants, not config-driven):

```
chain_max_depth   = 3     # applies PER ROOT SUBTREE (each root starts at depth 0)
chain_max_issues  = 10    # global cap across ALL root subtrees combined
```

Both caps apply independently — whichever is triggered first wins. Bumped from v2.55.0's `(2, 5)` to `(3, 10)` to accommodate multi-root scenarios where `(N=3 roots × ~2 spawns/each = 6)` already exceeds the v1 max-issues=5 cap. See `add-idd-all-chain-skill` design.md Decision 7 for the v1 cap rationale and `multi-root-traversal-idd-all-chain` design.md Decision D3 for the v2 bump rationale.

## Traversal mode (DFS vs BFS)

```
DFS (default, --bfs flag absent):
    New spawns are pushed to QUEUE FRONT:
        QUEUE = ($SPAWN_NUM "${QUEUE[@]}")
    Effect: a root's entire subtree is fully explored before moving to the next root.
    Use when: reviewer cognitive load matters — process one root + its descendants
              fully before switching context.

BFS (--bfs flag present):
    New spawns are pushed to QUEUE BACK:
        QUEUE += ("$SPAWN_NUM")
    Effect: all roots are processed level-by-level (all root depth=0 first, then
            all depth=1 spawns from any root, etc.).
    Use when: fairness across roots matters — guarantee each root subtree gets at
              least depth-0 processing before any other root's deeper spawns.
```

Single-root invocations (N=1) have no observable DFS/BFS difference since the only "branching" comes from spawns of a single subtree. The `traversal` field is still recorded in the manifest.

### DFS vs BFS queue order example

| Mode | Initial queue | Pop #44 | Spawn #X from #44 added | Next pop |
| ---- | ------------- | ------- | ------------------------ | -------- |
| DFS  | [44, 45, 50]  | [45, 50] (current=44) | push-front: [X, 45, 50] | X |
| BFS  | [44, 45, 50]  | [45, 50] (current=44) | push-back: [45, 50, X]  | 45 |

## Eligibility heuristic

For each spawn manifest entry observed after a sub-`/idd-all` invocation, the shell evaluates:

```
chain_eligible(spawned, root) =
    spawned.same_file_as_root == true
    OR spawned.same_skill_as_root == true
    OR spawned.spawn_kind == "sister-bug"
```

The fields are sourced from `chain-spawned-issues.json` (per `references/spawn-manifest.md`).

**Ineligible spawns are NOT skipped at the audit-trail layer** — sub-skills still file the GitHub issue (existing `Filed sibling issues` / `Sister Bugs Filed` behavior unchanged). Eligibility only gates **enqueueing into the chain**. Same applies to depth-cap and max-issues-cap rejections.

## Loop algorithm

```
WHILE queue is non-empty:
    IF |processed| >= chain_max_issues:
        log "max-issues cap reached, remaining queue filed-only"
        BREAK

    current ← queue.pop_front()
    current_root ← root_id_map[current]

    # Skip if current's owning root subtree has already FAILed (defensive — purge
    # below normally clears this, but covers concurrent FAIL during long /idd-all
    # invocation)
    IF current_root IN fail_roots:
        log "#current skipped (root #current_root subtree already FAILed)"
        CONTINUE

    pre_len ← len(manifest.spawned)

    export IDD_CHAIN_CURRENT_ROOT_ID = current_root
    invoke /idd-all #current --in-chain --cwd <CWD>
    unset IDD_CHAIN_CURRENT_ROOT_ID

    phase ← read latest Phase from issue body Current Status

    IF phase == "verified":
        processed[current] ← "verified"
        chained_order.append(current)
    ELSE:
        # Per-root halt (D4 Option C, v2.60+): scope the halt to current_root's subtree only
        processed[current] ← "failed"
        fail_roots.add(current_root)
        failed_at.append(current)
        # Purge from queue all pending issues whose owning root == current_root
        queue ← [q for q in queue if root_id_map[q] != current_root]
        log "halted root #current_root subtree; other roots continue"
        CONTINUE   # NOT exit 1 — other root subtrees still process

    post_len ← len(manifest.spawned)
    FOR idx in [pre_len, post_len):
        spawn ← manifest.spawned[idx]
        next_depth ← depth_map[current] + 1   # per-root depth: current's depth within ITS subtree

        IF chain_eligible(spawn, root) AND
           next_depth <= chain_max_depth AND                    # per-root cap
           |processed| + |queue| + 1 <= chain_max_issues:        # global cap
            # Push semantics dispatch on traversal mode
            IF traversal == "dfs":
                queue.push_front(spawn.issue_number)              # rich subtree first
            ELSE:
                queue.append(spawn.issue_number)                  # level-by-level
            depth_map[spawn.issue_number] ← next_depth
            root_id_map[spawn.issue_number] ← current_root        # inherit owning root
        ELSE:
            log spawn filed-only (reason: ineligible | depth-cap | issues-cap)
```

**Determinism notes**:

- Manifest delta is computed by length, not by contents. Sub-skills append-only; the shell only reads entries in `[pre_len, post_len)` after each sub-invocation.
- Order of enqueueing within a single delta is the order sub-skills wrote entries. Sub-skills MUST NOT re-order or rewrite earlier entries.
- The shell is single-threaded — no concurrent sub-`/idd-all` invocations within one chain run.
- `root_id_map` is populated at Phase 1 init for each root (root_id=self) and inherited by spawns from `current_root` (the issue being processed when the spawn was filed).
- Sub-skills propagate `root_id` to the manifest via the 9th positional arg to `manifest-append.sh`, reading `IDD_CHAIN_CURRENT_ROOT_ID` env var with fallback to the current issue number.

## Failure mode

| Trigger | Action |
|---------|--------|
| Sub-`/idd-all #N --in-chain` returns verify-FAIL phase (single root subtree) | Halt that root's subtree only; purge same-root pending from queue; other root subtrees CONTINUE; preserve all commits on cluster branch; Phase 4 report shows per-root FAIL/PASS |
| Sub-`/idd-all #N --in-chain` returns verify-FAIL phase (the only root subtree) | Equivalent to halting whole queue; preserve commits; Phase 4 shows single root FAIL |
| `git`/`gh` command failure during Phase 0 | Abort before mutations |
| Branch hash8 collision (N>1) | Fallback to hash16; double collision → Phase 0.5 abort |
| Manifest schema mismatch (v1 on disk under v2 helper) | Helper exits 1 (fail-fast, no silent migrate) |
| Sub-skill invokes `manifest-append.sh` with 8 args (missing root_id) | Helper exits 2 (usage error) |
| `gh pr create` fails in Phase 3 | Branch is already pushed; print recovery hint (`gh pr create` manually) |

**No rebase, no revert, no auto-cleanup**. The cluster branch is the audit trail of the run; preserving partial commits is a feature, not a bug. For multi-root chains, partial work from completed root subtrees coexists with halted FAIL root's partial commits on the same branch — user reviews the cluster PR and decides whether to revert FAIL root's commits or merge all and follow up. Recovery options the Phase 4 report MUST surface (per-root FAIL):

1. `/idd-verify --pr <future-PR>` to inspect FAIL details (the cluster PR opens at Phase 3 regardless)
2. `/idd-implement #failing --branch-override <cluster-branch>` to retry the failing issue on cluster branch
3. `/idd-all-chain #failing` from clean main (creates new branch, leaves this cluster for cleanup)
4. Discard cluster: `gh pr close` + `git checkout <default>` + `git branch -D <cluster-branch>`

## PR title schema (Phase 3)

```
N=1: chain: <root title>
N>1: chain (multi-root): <N> issues — <lowest-root title>
```

## PR body schema (Phase 3)

```markdown
Refs #<root_1> #<root_2> ... #<chained_1> #<chained_2> ...    (roots first, then spawns)

## Summary

(N=1) Cluster of <N> issues solved as one chain (root + auto-emergent spawn) via `/idd-all-chain` (v2.55+).
(N>1) Multi-root chain (N=<N> roots: <comma-separated-roots>) solved as one cluster via `/idd-all-chain` (v2.60+, traversal=<mode>). Total <K> processed issues across all root subtrees.

## Cluster overview

| # | root_id | Spawn source | Phase | PR commit |
|---|---------|--------------|-------|-----------|
| #<root>     | <root>      | root | verified | <abbrev sha> |
| #<chained>  | <root_id>   | <sub-skill> <step> | verified | <abbrev sha> |
| ...

## Per-issue details

<details>
<summary>#<issue> (root_id=<root_id>) — <title></summary>

(diagnose / verify / commit links)

</details>

...

## Review status

- [x] Diagnose ✓ for all <N> issues
- [x] Implement ✓
- [x] Verify ✓ (per-issue 6-AI ensemble)
- [x] **Verify-gated**: per-issue verify PASS — cluster ready to merge → /idd-close #<root> #<chained_1> ... per issue after merge
```

PR title MUST begin with `chain:` (distinguishes from `cluster:` prefix used by pre-known cluster-PR mode in `idd-implement`/`idd-verify`/`idd-close`).

PR body MUST NOT contain `Closes #N` / `Fixes #N` / `Resolves #N` (per `plugins/issue-driven-dev/CLAUDE.md` Commit Conventions — IDD owns the close pathway via `/idd-close`).

## Stop conditions

The chain run terminates in one of these states:

| Termination | Phase reached | Next user action |
|-------------|---------------|------------------|
| Queue empty, all verified | 4 (final report) | Review PR → merge → `/idd-close #<root> #<chained...>` |
| Verify FAIL on a chained issue | 2 (halt) | Inspect verify findings → recovery path from abort report |
| `gh pr create` failure | 3 (partial) | Manual `gh pr create` against cluster branch |
| Phase 0 pre-flight failure | 0 (no mutations) | Fix prerequisite (auth / clean tree / branch name collision) |

The chain shell **never** auto-closes issues and **never** auto-merges PRs. Both are human checkpoints.

## See also

- `references/spawn-manifest.md` — manifest schema + sub-skill write contract (data layer)
- `references/pr-flow.md` — `/idd-all` PR mode 4-tuple resolution (the `--in-chain` flag derives the 4th tuple)
- `references/batch-and-cluster.md` — pre-known cluster-PR mode (contrast: chain is auto-emergent)
- `docs/design-patterns/default-dilemma.md` — why chain is a separate skill, not an `--chain` flag
- `plugins/issue-driven-dev/skills/idd-all-chain/SKILL.md` — implementation
