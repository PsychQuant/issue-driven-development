## Why

IDD runs diagnose → implement → verify sequentially, and multi-issue modes loop **one issue at a time**. A backlog of independent issues leaves potential parallelism on the table; running them blindly in parallel corrupts shared physical resources (a single-writer DB lock, a serial upload endpoint, a shared submodule). Surfaced from real dogfooding (issue-driven-development#182, ai_martech L4 session 2026-06-01): the missing piece is not "open a worktree per issue" — worktrees solve parallel *file* edits but not shared *physical* resources. A conflict-class taxonomy is what makes parallelization **safe** rather than merely fast.

This change ships the taxonomy as a **discipline layered onto existing `idd-diagnose` + `idd-all`** (per #182's own Non-Goal — not a new top-level skill), and is **honest about scope**: the read-only parallel-diagnose fan-out runs concurrently today; concurrent *stateful* lanes are deferred because no within-window concurrent-lane primitive exists.

## What Changes

- Define the **A–E conflict-class taxonomy** in `plugins/issue-driven-dev/references/parallel-orchestration.md` and express it as a `### Conflict Class` field that `idd-diagnose` emits and `idd-all` consumes.
- Add an **`idd-all` multi-issue batch mode** (`idd-all #a #b #c`): a conflict-class-**ordered sequential** backlog drain — orders by the discipline (E/D first, same-resource B/C adjacent, same-file grouped, A unconstrained), runs each through the normal pipeline one at a time, optionally worktree-isolating A for later **manual** parallelism. Sequential by design; stops at verified.
- Add an **opt-in parallel-diagnose fan-out** to `idd-diagnose` (the one half that genuinely runs concurrently today, via the Workflow tool): for a root cause spanning N independent subsystems, fan out one read-only investigator per subsystem + a synthesis agent citing file refs from ≥2 legs.
- Document the **honest scope split**: concurrent stateful lanes are deferred (within-window agent teams is `## Deferred: Case A` in `worktree-isolation.md`; `TeamCreate` was abandoned by `idd-verify`). The taxonomy is a forward-looking safety contract for manual/future parallelism, **not** a live auto-concurrency engine.

## Non-Goals

(Recorded in design.md — Goals/Non-Goals section.)

## Capabilities

### New Capabilities

- `parallel-orchestration`: the conflict-class discipline — the A–E taxonomy, the `### Conflict Class` Diagnosis field contract (`idd-diagnose` emits, `idd-all` consumes), the opt-in parallel-diagnose fan-out, the `idd-all` sequential conflict-class-ordered batch mode, and the explicit deferral of concurrent stateful execution.

### Modified Capabilities

(none)

## Impact

- Affected specs: new `parallel-orchestration`
- Affected code:
  - New:
    - plugins/issue-driven-dev/references/parallel-orchestration.md
  - Modified:
    - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
    - plugins/issue-driven-dev/skills/idd-all/SKILL.md
    - plugins/issue-driven-dev/CLAUDE.md
    - plugins/issue-driven-dev/references/usecase-routing.md
    - plugins/issue-driven-dev/CHANGELOG.md
    - plugins/issue-driven-dev/.claude-plugin/plugin.json
    - .claude-plugin/marketplace.json
  - Removed: (none)
