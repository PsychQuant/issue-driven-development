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

For unattended caller (e.g. `/loop --in-chain` misuse — chain shell is not designed to be called by `/loop` directly, but sanity check), defaults to `proceed` + audit trail (same fallback pattern as Layer V unattended in idd-diagnose Step 3.4).

**Why placement before branch/manifest creation matters**: cancel-path side-effect minimization. If user picks `cancel`, no work is undone — there is no work yet. Diagnosis-readiness gate placed AFTER branch creation would leave dangling cluster branches user must manually delete, breaking IDD's halt+preserve discipline (preserve assumes there's something worth preserving).

**Future #46 multi-root extension**: helper function design preserves N-arg shape (`check_diagnosis_readiness(issue_numbers...) → [ready_list, not_ready_list]`) so #46 can reuse for per-root readiness aggregation. v1 ships single-root only.

## Cluster branch naming

```
idd/chain-<root_issue_number>-<slug>
```

- `slug` = lowercased title of root issue, non-alphanumeric → `-`, capped at 40 chars, leading/trailing `-` trimmed
- The chain shell MUST refuse to start if a branch with this name already exists (manual cleanup required)
- Sub-`/idd-all #M --in-chain` Step 0.5 sanity check MUST verify the current branch matches `^idd/chain-` prefix; otherwise abort

## Chain state

```
QUEUE          : ordered list of pending issues (FIFO; root pushed first)
DEPTH_MAP      : issue → integer depth (root=0, immediate spawns=1, ...)
PROCESSED      : issue → "verified" | "failed"
CHAINED_ORDER  : ordered list of verified issues (used to build PR body)
```

Caps (hard-coded constants, not config-driven):

```
chain_max_depth   = 2
chain_max_issues  = 5    # includes root
```

Hard cap rationale: real-world chains rarely exceed depth 2 (per `add-idd-all-chain-skill` design.md Decision 7). Conservative v1 limit; future evidence may justify config-driven override, but v1 ships with no such surface to avoid default ambiguity.

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
    pre_len ← len(manifest.spawned)

    invoke /idd-all #current --in-chain --cwd <CWD>

    phase ← read latest Phase from issue body Current Status

    IF phase == "verified":
        processed[current] ← "verified"
        chained_order.append(current)
    ELSE:
        processed[current] ← "failed"
        emit abort_report(current, phase)
        EXIT 1                    # halt + preserve

    post_len ← len(manifest.spawned)
    FOR idx in [pre_len, post_len):
        spawn ← manifest.spawned[idx]
        next_depth ← depth_map[current] + 1

        IF chain_eligible(spawn, root) AND
           next_depth <= chain_max_depth AND
           |processed| + |queue| + 1 <= chain_max_issues:
            queue.append(spawn.issue_number)
            depth_map[spawn.issue_number] ← next_depth
        ELSE:
            log spawn filed-only (reason: ineligible | depth-cap | issues-cap)
```

**Determinism notes**:

- Manifest delta is computed by length, not by contents. Sub-skills append-only; the shell only reads entries in `[pre_len, post_len)` after each sub-invocation.
- Order of enqueueing within a single delta is the order sub-skills wrote entries. Sub-skills MUST NOT re-order or rewrite earlier entries.
- The shell is single-threaded — no concurrent sub-`/idd-all` invocations within one chain run.

## Failure mode

| Trigger | Action |
|---------|--------|
| Sub-`/idd-all #N --in-chain` returns verify-FAIL phase | Halt queue; preserve all commits on cluster branch; emit abort report |
| `git`/`gh` command failure during Phase 0 | Abort before mutations |
| `gh pr create` fails in Phase 3 | Branch is already pushed; print recovery hint (`gh pr create` manually) |

**No rebase, no revert, no auto-cleanup**. The cluster branch is the audit trail of the run; preserving partial commits is a feature, not a bug. Recovery options the abort report MUST surface:

1. `/idd-verify --pr <future-PR>` to inspect FAIL details
2. `/idd-implement #failing --branch-override <cluster-branch>` to retry on cluster branch
3. `/idd-all-chain #failing` from clean main (creates new branch, leaves this one for cleanup)
4. Discard cluster: `gh pr close` + `git checkout <default>` + `git branch -D <cluster-branch>`

## PR body schema (Phase 3)

```markdown
Refs #<root> #<chained_1> #<chained_2> ...

## Summary

Cluster of <N> issues solved as one chain (root + auto-emergent spawn) via `/idd-all-chain`.

## Cluster overview

| # | Spawn source | Phase | PR commit |
|---|--------------|-------|-----------|
| #<root> (root) | — | verified | <abbrev sha> |
| #<chained_1>   | <sub-skill> <step> | verified | <abbrev sha> |
| ...

## Per-issue details

<details>
<summary>#<issue> — <title></summary>

(diagnose / verify / commit links)

</details>

...

## Pending review

- [x] Diagnose ✓ for all <N> issues
- [x] Implement ✓
- [x] Verify ✓ (per-issue 6-AI ensemble)
- [ ] **Pending: human review of cluster PR + /idd-close #<root> #<chained_1> ... after merge**
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
