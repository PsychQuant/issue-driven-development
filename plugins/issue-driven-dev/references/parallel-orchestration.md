# Parallel Orchestration Discipline

> The **conflict-class discipline** for safely draining a backlog of independent issues — consumed by `idd-all`'s multi-issue batch mode (conflict-class-ordered) and by `idd-diagnose` (the `### Conflict Class` field + the opt-in parallel-diagnose fan-out). This file is the single source of truth both sides cite.

**Source**: `idd-all-batch` Spectra change (capability `parallel-orchestration`). Origin: issue-driven-development#182, surfaced from real dogfooding (ai_martech L4 session, 2026-06-01).

## Honest scope — what is real today vs deferred (CRITICAL)

This discipline has **two halves with very different maturity**, and conflating them is the trap this doc exists to prevent:

| Half | Status | Mechanism |
|------|--------|-----------|
| **Read-only diagnose fan-out** | ✅ **real today** | the Workflow tool (deterministic parallel agents + synthesis, exactly like `idd-verify`'s canonical pai-ensemble engine（#219 後 vendored fork 已刪，引擎 = parallel-ai-agents plugin）) |
| **Concurrent *stateful* lanes** (run N full `idd-all` pipelines at once) | ⛔ **deferred** | no primitive exists — within-window agent teams is `## Deferred: Case A` in [`worktree-isolation.md`](worktree-isolation.md) (#167); `TeamCreate` was abandoned by `idd-verify` after #47/#52; a Workflow `agent()` is a single subagent turn that cannot host `idd-all`'s skill orchestration or nest the verify ensemble |

So **`idd-all #a #b #c` batch mode is sequential, not concurrent.** The conflict-class taxonomy below is a **forward-looking safety contract**: it tells you what is safe to parallelize *when you do so manually* (separate Claude sessions / worktrees) or *when a real concurrent-lane primitive eventually lands*. It does NOT assert that any skill auto-parallelizes stateful work today. Do not write a spec or skill that `SHALL`s a concurrency engine that does not exist.

**Dispatch model（#205）**：本契約下派發的每個 agent（workflow `agent()` 或 manual `Agent()`）SHALL 帶顯式 `model`——依 idd-verify 的 dispatch-model 規則解析（`IDD_AGENT_MODEL` else `opus`，非法值 fail-loud）——永不隱式繼承 session 的 main-loop model。

## Why the taxonomy exists — the hard part is physical-resource serialization

Worktree isolation (`scripts/idd-worktree.sh`, [`worktree-isolation.md`](worktree-isolation.md)) cleanly solves *parallel file edits*: one `git worktree` per agent, no shared index. It does **not** solve shared **physical** resources — a single-writer DB lock, a serial cloud-upload endpoint, one external queue, or a shared submodule that multiple checkouts symlink to. The conflict-class taxonomy is the missing piece that tells you which issues are safe to parallelize and which must serialize — the part "just open a worktree per issue" never covers.

## Conflict-class taxonomy

Classify each issue by the physical resources its *implementation* touches (not by how its issue body is written — see Adversary discipline below).

| Class | Meaning | If you parallelize |
|-------|---------|--------------------|
| `A_parallel_safe` | independent file edits, no shared mutable resource | safe to run concurrently (one worktree each) |
| `B_resource_serialize` | touches a single-writer resource (DB lock, serial cloud upload, one external queue) | MUST serialize within the resource |
| `C_shared_module_coord` | edits a shared submodule / vendored dep consumed by others | serialize + cross-verify the consumers |
| `D_diagnose_first` | scope unclear; MUST be read before it can be bucketed | read-only diagnose first, then re-bucket |
| `E_verified_close` | already done; needs verification + close only | cheap, run anytime |

**Same-file rule**: two issues that edit the same source file are **not** independent `A_parallel_safe` issues — treat them as one serialized group, consistent with [`batch-and-cluster.md`](batch-and-cluster.md) cluster eligibility (same-file → bundle). Same-file is the most common false-`A`.

**Resource granularity for `B`/`C`**: serialization is **per named resource**, not per class — two `B` issues writing *different* DBs do not contend, so they are independent of each other (each still serializes against anything touching *its* DB). This is why the justification MUST name the resource.

## The `### Conflict Class` Diagnosis field contract

`idd-diagnose` SHALL emit a `### Conflict Class` section in its Diagnosis Report:

```markdown
### Conflict Class

`B_resource_serialize` — writes to the shared SQLite `runs.db` (single-writer lock); cannot run concurrently with #204 which migrates the same DB.
```

Rules:

- Value is **exactly one** of the five taxonomy keys.
- A one-line justification follows. For `B_resource_serialize` and `C_shared_module_coord` the justification MUST **name the shared resource** (the DB / endpoint / submodule). Naming the resource is what makes a serialize-class auditable rather than asserted.
- **Default-on-absence**: a consumer parsing a Diagnosis whose `### Conflict Class` is absent or unparseable SHALL default the issue to `D_diagnose_first` and **surface** that fallback (print it) — never fail silently, never default to a parallel class. (Conflict class and `### Complexity` are orthogonal fields — see the consumption note below.)

### Adversary discipline (audit lenses)

The `### Conflict Class` field is an interface; evaluate it through the three lenses from `.claude/rules/attribute-assessment.md`:

| Lens | Risk | Mitigation |
|------|------|------------|
| **Scoundrel** | Mislabel a resource-touching issue `A_parallel_safe` to force fast parallelization | The class describes the *substance* (what the implementation touches), not issue-body style. `B`/`C` require a **named** resource. The label is *advisory* — a false `A` is only dangerous if a human then actually parallelizes it; the same-file group rule catches the common case, but a false `A` on *different files sharing one runtime resource* is NOT auto-detected — the human applying parallelism is the last check (this discipline does not claim a dispatcher falsifies the label). |
| **Lazy Developer** | Default everything to `A_parallel_safe` to skip analysis | The conservative default is `D_diagnose_first`, **not** `A`. Absent/unclear → read first. |
| **Confused Developer** | Score "how hard is the issue" instead of "what does it touch" | The axis is **physical resources touched at implement time**, not difficulty, priority, or size. |

## How `idd-all` multi-issue mode consumes it (sequential, today)

`/idd-all #a #b #c` reads each issue's `### Conflict Class` and processes the backlog **sequentially**, ordered by this discipline:

1. Default any absent/unparseable class to `D_diagnose_first` (surfaced).
2. Re-bucket `D_diagnose_first` issues via a read-only diagnose pass before ordering.
3. Order: `E` / `D`-resolved cheap items first; `B`/`C` touching the same named resource adjacent (so a reviewer sees them together); same-file issues grouped; `A` order unconstrained.
4. Run each through the normal `idd-all` pipeline one at a time. `A_parallel_safe` issues MAY acquire an `idd-worktree.sh` worktree so the resulting branches can be **manually** advanced in parallel later.
5. Stop at verified.

Ordering does not buy *safety* (sequential is always safe); it buys review ergonomics + pre-isolation for later manual parallelism. The taxonomy's real payoff is as the parallel-safety contract, not this sequential outer loop.

## Opt-in parallel-diagnose fan-out (`idd-diagnose`) — real today

For an issue whose root cause spans **N independent subsystems / hypotheses**, `idd-diagnose` supports an opt-in path that fans out one read-only investigator per subsystem (Workflow tool) + a synthesis agent merging findings into one Diagnosis Report. This is the half that genuinely runs concurrently today (read-only, no shared state).

- The single-agent path stays the **default** for simple issues.
- Synthesis MUST cite concrete file references from **≥2** independent investigator legs (the value of fan-out is cross-leg recontextualization — one leg's reads correct another's framing).
- **Adversarial-verify variant**: for high-stakes findings, fan out N skeptics to refute each hypothesis before it enters the report.
- Opt-in only: auto-detecting "N subsystems" is fuzzy, and fan-out multiplies token spend.

## When parallel beats sequential (for manual parallelization)

| Worth parallelizing (manually, across sessions/worktrees) | Keep sequential / single-agent |
|------------------------------------------------------------|-------------------------------|
| Backlog with a real mix of independent (`A`) + resource-bound (`B`/`C`) work | ≤3 issues, or all touching one resource |
| RCA genuinely spans independent subsystems read in parallel | single-subsystem RCA |
| The independent legs dominate wall-clock | coordination cost > the parallelism win |

Default is sequential. Parallelism is an **explicit, opt-in, currently-manual** act — never automatic.

## See also

- `plugins/issue-driven-dev/skills/idd-all/SKILL.md` — `## Multi-issue batch mode` (the sequential consumer)
- `plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md` — `### Conflict Class` emitter + the fan-out opt-in
- [`worktree-isolation.md`](worktree-isolation.md) — `idd-worktree.sh` + the **Deferred: Case A** (within-window agent teams) that gates true concurrent lanes (#167)
- [`chain-flow.md`](chain-flow.md) — `idd-all-chain` (contrast: sequential auto-emergent ripple, one cluster PR)
- [`batch-and-cluster.md`](batch-and-cluster.md) — pre-known cluster-PR + the existing sequential "batch mode"
- `.claude/rules/attribute-assessment.md` — the Likert/adversary discipline the conflict-class field follows
