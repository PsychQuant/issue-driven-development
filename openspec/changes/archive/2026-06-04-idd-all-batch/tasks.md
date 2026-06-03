## 1. Conflict-class discipline (reference brain)

- [x] 1.1 Create `plugins/issue-driven-dev/references/parallel-orchestration.md` with the A–E taxonomy, same-file-group rule, per-named-resource serialization, and the audit lenses. (Requirement: Conflict-class taxonomy)
- [x] 1.2 In the same doc, document the **honest scope split** — read-only diagnose fan-out is real today; concurrent stateful lanes are deferred (worktree-isolation Case A, TeamCreate abandoned) — and frame the taxonomy as a forward-looking safety contract, not an auto-concurrency engine. (Requirement: Concurrent stateful execution is deferred)

## 2. idd-diagnose — emit the field + opt-in fan-out

- [x] 2.1 Add a `### Conflict Class` section to the `idd-diagnose` Diagnosis Report (one of five keys; `B`/`C` name the resource), and document the absent/unparseable → `D_diagnose_first` surfaced default + the orthogonality with `### Complexity`. (Requirement: Conflict-class Diagnosis field contract)
- [x] 2.2 Add the opt-in parallel-diagnose fan-out path (N read-only investigators via the Workflow tool + synthesis citing ≥2 legs; single-agent stays default). (Requirement: Opt-in parallel-diagnose fan-out)

## 3. idd-all — multi-issue batch mode (sequential, conflict-class-ordered)

- [x] 3.1 Add a `## Multi-issue batch mode` section to `plugins/issue-driven-dev/skills/idd-all/SKILL.md` + an args-table row: `idd-all #a #b #c` reads each `### Conflict Class` (default-on-absence surfaced), orders by the discipline, runs each through the normal pipeline sequentially, optionally worktree-isolates `A`, stops at verified. Includes the explicit "sequential, concurrency deferred" honesty boundary. (Requirement: idd-all multi-issue batch mode (conflict-class-ordered, sequential))

## 4. Wiring + docs

- [x] 4.1 Fold a multi-issue-batch-mode note into the `idd-all` row of the CLAUDE.md orchestrator table (no separate skill row); preserve the file's line endings.
- [x] 4.2 Reframe `references/usecase-routing.md` row 27 + the decision-tree Note to route to `idd-all #a #b #c` (retire the "no built-in bulk-solve" claim).

## 5. Release plumbing

- [x] 5.1 Bump the plugin version (minor) in `plugins/issue-driven-dev/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`, add a CHANGELOG entry summarizing the discipline + the design honesty trail. All three agree on 2.83.0.

## 6. Verification

- [x] 6.1 Run `/idd-verify` (6-AI ensemble) on the change scope; R1 FAILed (DA-1: spec froze a SHALL on a non-existent concurrency engine) → rescoped to this discipline form; re-verify confirms the overclaim is gone and the spec scenarios hold.
