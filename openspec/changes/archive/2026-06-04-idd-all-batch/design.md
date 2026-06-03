## Context

IDD has two orchestrators today: `idd-all` (one issue, sequential) and `idd-all-chain` (one root + auto-emergent ripple, sequential traversal, one cluster PR). Neither parallelizes a backlog of N pre-known independent issues. Worktree isolation (`idd-worktree-isolation`, scripts/idd-worktree.sh) already isolates concurrent file edits, and `idd-pr-hitl-modes` already resolves the `(path, interaction)` run-shape. The gap surfaced in issue-driven-development#182 from real dogfooding: parallel batch needs a way to keep shared **physical** resources (single-writer DB lock, serial upload endpoint, shared submodule) from being corrupted — worktrees do not cover that.

issue-driven-development#182's own Non-Goal #2 said "not a new top-level skill."

## Rescope (R1 verify-driven, 2026-06-04) — supersedes the skill design below

The first cut of this change proposed a standalone parallel orchestrator skill `/idd-all-batch` (a sibling to `idd-all-chain`) whose spec `SHALL`-ed stateful parallel lanes "via agent-teams". The 6-AI verify ensemble (Devil's Advocate, #182 R1) caught that **the `agent-teams` concurrency mechanism does not exist as a primitive**: within-window agent teams is `## Deferred: Case A` in `worktree-isolation.md` (#167), `TeamCreate` was abandoned by `idd-verify` after #47/#52, and a Workflow `agent()` is a single subagent turn that cannot host `idd-all`'s skill orchestration or nest the verify ensemble. Freezing a `SHALL` on a non-existent engine is an honest-reduction violation.

**Resolution (chosen by the user):** demote to a **discipline layered onto existing `idd-diagnose` + `idd-all`** (which is exactly what #182's Non-Goal #2 argued for). No standalone skill. The capability lives as:
- the conflict-class taxonomy + `### Conflict Class` Diagnosis field (real),
- the opt-in parallel-diagnose fan-out (real today — read-only, Workflow tool),
- an `idd-all` **multi-issue batch mode** that is **sequential**, conflict-class-ordered (concurrency deferred),
- an explicit deferral of concurrent stateful execution (taxonomy = forward-looking safety contract).

The Goals/Decisions/Implementation-Contract sections below were written for the superseded skill design; the binding contract is now the rescoped `parallel-orchestration` spec. Decisions D1 (conflict-class field), D4 (same-file group), D5 (reference brain) survive; D2 (unattended PR-per-lane), D3 (dual-mechanism stateful lanes) are dropped — there are no concurrent stateful lanes.

## Goals / Non-Goals

**Goals:**

- A conflict-class **discipline** that tells you which issues in a backlog are safe to parallelize and which must serialize — captured in one reference doc.
- A cross-skill contract: `idd-diagnose` emits a `### Conflict Class` field; `idd-all`'s multi-issue mode consumes it.
- An honest `idd-all` multi-issue batch mode (sequential, conflict-class-ordered) + the one genuinely-concurrent piece (read-only diagnose fan-out via the Workflow tool).
- Reuse existing primitives (`idd-worktree.sh` for optional class-A isolation) rather than reinventing.

**Non-Goals:**

- **Not a new top-level skill** (matches #182 Non-Goal #2; the R1 verify confirmed the standalone-skill design overclaimed). The capability is layered onto `idd-diagnose` + `idd-all`.
- **Not auto-parallelizing stateful lanes** — no within-window concurrent-lane primitive exists (deferred Case A in `worktree-isolation.md`; `TeamCreate` abandoned). The batch mode is sequential; parallelism is manual/future.
- Not making everything parallel by default. Trivial single-issue diagnose stays single-agent.
- Not auto-merging or auto-closing — stop at verified.

## Decisions

**D1 — Conflict-class is a `### Conflict Class` field emitted by `idd-diagnose`, not a label and not batch-time inference.** (survives)
The A–E class keys off affected-files + shared-resource analysis, which the Diagnosis Strategy already produces. It belongs where RCA lives. Rejected: a `conflict:db-serialize` GitHub label (separate classifier pass + drifts); inferring at dispatch (loses the audit trail).

**D4 — Same-file issues form one serialized group; `B`/`C` serialize per named resource.** (survives)
Two issues editing the same file are not independent; group them, consistent with `batch-and-cluster.md` same-file → bundle. Serialization granularity is per *named* resource — two `B` issues on different DBs do not contend.

**D5 — Discipline doc + light consumers (IDD house style).** (survives, reframed)
The A–E taxonomy + the fan-out-vs-sequential judgment live in `references/parallel-orchestration.md`; `idd-diagnose` and `idd-all` cite it rather than duplicating. The doc is the brain; the skills are thin consumers — but there is **no new orchestrator skill**.

**D-rescope (R1 verify-driven, supersedes the original D2/D3) — sequential batch, concurrency deferred, no skill.**
The original design had D2 (class-A fans out, Plan/Spectra excluded from a parallel set) and D3 (agent-teams run stateful lanes). R1 verify proved the stateful-concurrency engine does not exist, so both are dropped. The honest design: `idd-all #a #b #c` processes the backlog **sequentially**, ordered by the discipline; the taxonomy is the forward-looking safety contract for manual/future parallelism. There is no parallel set, so the HIGH-1 "Plan-exclusion vs same-file-merge ordering" defect dissolves (sequential is always safe regardless of order). Only the read-only diagnose fan-out is concurrent today.

## Implementation Contract

- **Behavior**: `/idd-all #a #b #c` reads each issue's `### Conflict Class`, orders the sequence by the discipline (`E`/`D` first, same-resource `B`/`C` adjacent, same-file grouped, `A` unconstrained), and runs each through the normal `idd-all` pipeline **one at a time**. `A` issues MAY get an `idd-worktree.sh` worktree for later manual parallelism. Stops at verified; never auto-merges/auto-closes.
- **Interface**:
  - `idd-diagnose` emits a `### Conflict Class` section (one of the five keys; `B`/`C` name the resource); orthogonal to `### Complexity`.
  - A consumer reading an absent/unparseable field defaults to `D_diagnose_first` and surfaces it (never silent, never a parallel default).
  - The opt-in parallel-diagnose fan-out runs N read-only investigators (Workflow tool) + synthesis citing ≥2 legs.
- **Failure modes**: absent/unparseable `### Conflict Class` → `D_diagnose_first`, surfaced. Sequential processing has no concurrent-corruption failure mode (that is the point of deferring concurrency).
- **Acceptance criteria**:
  - Given issues classified A(parser)/A(formatter)/A(parser, same-file)/B/E, `idd-all` groups the two parser issues, orders E early, and drains all five sequentially (spec scenario + example).
  - `idd-diagnose` fan-out produces a Diagnosis whose synthesis cites file refs from ≥2 legs.
  - No skill, spec, or doc `SHALL`-s a within-window concurrent-stateful-lane mechanism.
- **Scope boundaries**: in scope = the discipline doc, the `### Conflict Class` field, the diagnose fan-out, the `idd-all` sequential batch mode, CLAUDE.md/usecase-routing wiring. Out of scope = building the deferred concurrent-lane primitive, a standalone orchestrator skill, auto-detection of "N subsystems".

## Risks / Trade-offs

- **Conflict-class misclassification** → only matters when a human *manually* parallelizes (sequential batch is always safe). Mitigation: default-to-`D`; same-file grouping; `B`/`C` require a named resource; the human applying parallelism is the last check (the discipline does not claim a dispatcher falsifies the label).
- **Sequential batch is thin** → ordering does not buy safety, only review ergonomics + pre-isolation. Accepted: the lasting value is the taxonomy as a parallel-safety contract, not the sequential outer loop; shipping the honest version beats shipping an unimplementable concurrent one.
- **Deferred concurrency** → the feature people might *want* (true concurrent drain) isn't here. Mitigation: explicitly tracked against `worktree-isolation.md` Deferred Case A; revisit when a real primitive lands.
