## Context

`/idd-verify` runs a 6-AI cross-verification ensemble (5 distinct-lens reviewers — requirements / logic / security / regression / devil's-advocate — plus a cross-model blind Codex verifier). Today this is hand-orchestrated in skill prose: the skill spawns 5 parallel `Agent` calls that each write findings to `/tmp`, the devil's-advocate polls for the other four files, a background Codex subprocess runs separately, and the skill merges all six. The Codex subprocess has hung twice in one session (exit 144; #147). There is no `idd-verify` spec.

Claude Code's dynamic-workflow primitive (research preview) is a JavaScript script the runtime executes in the background; intermediate results live in script variables, not the conversation; it is resumable within a session and can fan out and cross-check agents. Its documented canonical pattern is precisely "independent agents adversarially review each other's findings before they're reported." Two hard constraints shape any adoption: a workflow takes **no mid-run user input** (only agent permission prompts pause it), and the workflow script itself has **no direct filesystem/shell access** (its agents do the I/O).

This design adopts that primitive for the ensemble's deterministic core while keeping the skill's stateful and human-in-the-loop responsibilities, and creates the inaugural `idd-verify` spec.

## Goals / Non-Goals

**Goals:**

- A first-class `idd-verify` capability spec: fan-out → cross-check → merge, with graceful degradation across two execution backends and an identical findings contract either way.
- Move the deterministic core (fan-out + adversarial verify + merge) onto the dynamic-workflow primitive, eliminating the `/tmp` file-IPC and hand-rolled polling.
- Bound Codex deterministically (address the #147 hangs) without losing its cross-model value.
- Never break users without the primitive (older Claude Code / free tier): a manual-fan-out fallback with the same findings contract.

**Non-Goals:**

- idd-all-chain workflow adoption (Phase 2, separate change, MODIFIES the existing `idd-all-chain` spec).
- Re-speccing idd-verify's gates / PR-mode / auto-close detection / triage (stay skill prose; may be codified later into the same spec).
- Changing reviewer lenses or the merged-findings shape.
- Implementing now — this change is parked; implementation is under `/spectra-apply`.

## Decisions

### D1: Hybrid split — workflow owns the deterministic core; skill keeps gates + side-effects + human-in-loop

The workflow owns: fan-out of the 5 reviewers → each reviewer's findings adversarially verified by the devil's-advocate as soon as it completes (a pipeline, not a barrier) → Codex cross-model pass → merge + dedup → return a validated findings array. The skill keeps: input-source resolution, PR↔issue correspondence + auto-close detection gates, GitHub master/pointer posting, follow-up triage, and the verify-fix loop.

Rationale: the seam is forced by the two workflow constraints. Gates and triage call `AskUserQuestion` (mid-run user input — forbidden in a workflow); posting and git checkout are stateful side-effects (the workflow script has no shell/FS). The skill **awaits** the workflow's returned findings before posting, so the user-facing flow ("run verify → get findings") is unchanged.

Alternatives: (a) full-workflow — rejected, hits both constraints. (b) status quo manual fan-out — rejected, the file-IPC + polling + unbounded Codex are workarounds the primitive removes.

**Seam depth check** (from the #164 discuss): one adapter on the path (skill → one workflow); the workflow hides real behavior (parallel fan-out, the adversarial verify pipeline, merge/dedup), not a pass-through; deleting it drops back to manual fan-out — a meaningful loss. The seam earns its keep.

### D2: Workflow script — ship as a plain file in the plugin, passed to the Workflow tool inline (RESOLVED 2026-06-01, task 2.3)

**Investigation (task 2.3)**: the official Claude Code plugin structure has no `workflows/` component. A plugin can ship `skills/`, `commands/`, `agents/`, `hooks/`, `.mcp.json`, `.lsp.json`, `monitors/`, `bin/`, and `settings.json` — but **not** a registrable saved workflow. Saved workflows live only in `.claude/workflows/` (project) or `~/.claude/workflows/` (user). So the "bundled, invoked by name" path is **not available** to a plugin skill.

**Decision**: ship the ensemble workflow as a plain, version-controlled `.js` file inside the idd-verify skill directory; at call time the skill reads that file and passes its contents to the Workflow tool's `script` parameter (inline execution). This keeps the script maintainable, version-controlled, and reusable (other skills can read the same file) without depending on plugin→workflow registration, which Claude Code does not support.

Alternatives: (a) author the script directly in skill prose — workable but buries a large script in markdown and forgoes file-level reuse; (b) have the skill write the script into `~/.claude/workflows/` on first run then invoke by name — rejected, it mutates the user's workflow registry as a side effect.

### D3: Codex inside the workflow, gated by a Phase 0 spike

Run Codex as a workflow agent that shells out to the Codex CLI, so the runtime's abort/stop can deterministically kill a hung run. This is gated by **Phase 0**: a spike that confirms stopping a workflow agent cleanly terminates a hung `codex exec` child process. If the spike fails, Codex stays an external background process with a skill-level timeout (the fallback), and the rest of the design is unaffected.

**Phase 0 result (2026-06-01): PASS.** Stopping the supervising background task — via the harness `TaskStop`, the same Bash-tool termination a workflow agent uses to run a shell command — cleanly killed the entire process tree down to the codex `node` wrapper and the rust binary, with zero orphan. Corroborated by a direct probe in which a `timeout` SIGTERM also reaped a hung `sleep 300 | codex exec` pipeline with no leftover. Caveat: this exercised the harness background-task stop, not the literal dynamic-workflow runtime's agent-stop (the agent-interpretation layer made a faithful in-workflow scripted run unreliable); both reduce to the same Bash-tool kill path, so the result is expected to carry over. **Decision: Codex runs inside the workflow**, with the skill-level timeout retained as belt-and-suspenders.

Rationale: directly targets the #147 hang class; keeps Codex's cross-model blind-verify value (a workflow agent runs the session model, not gpt-5.5, so Codex must remain a shell-out either way — the only question is who bounds its lifetime).

### D4: Capability detection + manual fallback

The skill detects whether the dynamic-workflow primitive is available (version / feature gate). Available → run the workflow path. Unavailable → run the existing manual fan-out, emitting a one-line notice. Both paths produce the same findings contract, so every downstream step (posting, triage, verify-fix) is backend-agnostic.

### D5: Interaction-axis alignment with `idd-pr-hitl-modes`

A background workflow is inherently unattended for its duration (the no-mid-run-input constraint). The `idd-verify` spec references `idd-pr-hitl-modes` so the verify run's interaction semantics are stated in the same vocabulary the orchestrator-mode spec already established, rather than inventing a parallel notion.

## Implementation Contract

- **Behavior**: `/idd-verify #N` (and the `--pr` / `--commits` / `--branch` / `--since` modes) produces the same merged, deduped findings and the same master + per-issue pointer comments as today. When the workflow primitive is available, the deterministic fan-out → adversarial verify → merge runs as a background workflow (observable via the workflow progress view); when it is not, the current manual fan-out runs. The user does not choose the backend; the skill selects it and prints a one-line notice.
- **Interface / data shape**: the workflow returns a validated array of findings; each finding carries at least a severity, a file/location, a title, and a body, plus its source lens. The skill consumes this array for merge-presentation, posting, and triage. The reviewer lenses and the merged-findings shape are unchanged from today.
- **Failure modes**: primitive unavailable → manual-fan-out fallback (notice, not silent). A reviewer agent erroring → that lens's findings are absent and the master report records a process gap (same posture as today's recovery protocol). Codex hang → workflow abort when Phase 0 passed, else skill-level timeout. Workflow opt-in is satisfied by the skill invoking it (an allowed opt-in path); the skill states this.
- **Acceptance criteria**: (1) the Phase 0 spike result is recorded (pass → Codex-in-workflow; fail → external + timeout). (2) A verify run on a real PR yields findings of the same shape via both backends. (3) Disabling the workflow primitive exercises the manual fallback and yields the same posting/triage behavior. (4) The `idd-verify` spec validates and carries a real (non-stub) Purpose.
- **Scope boundaries**: IN — the verify ensemble deterministic core, the `idd-verify` spec, capability detection + manual fallback, Codex-in-workflow gated by the Phase 0 spike. OUT — idd-all-chain (Phase 2), the other idd-verify aspects (gates/PR-mode/auto-close/triage stay prose), any change to reviewer lenses or findings shape, the broader Codex robustness work (#147).

## Risks / Trade-offs

- Research-preview dependency → capability gate + manual fallback; never hard-depend on the primitive.
- Codex clean-kill unverified → Phase 0 spike gates it; external + skill-timeout fallback if it fails.
- Async-execution UX shift → the skill awaits the workflow result before posting, so the user-facing flow is unchanged; only the progress surface differs.
- Workflow resume is same-session only → acceptable; verify is normally a single-session step.
- Plugin-to-workflow registration may be unsupported → inline-script branch (D2) is the fallback.
- Spec scope narrower than the skill → the `idd-verify` Purpose states it covers the ensemble-execution contract today and grows by later changes; the name is not over-promised because nothing else claims the `idd-verify` capability yet.
- **Untrusted input (the diff + issue bodies come from a possibly-untrusted PR author)** → three hardening rules in the workflow script, each verified by background security review: (a) **command injection** — the diff is never interpolated into a shell command; the Codex lens passes it as prompt data, the agent writes it to a temp file with its file-write tool, and codex reads from the file (only a controlled path reaches the shell). (b) **fail-closed verdict** — a core lens or the devil's-advocate that errors synthesizes a HIGH integrity finding so the verdict cannot be PASS with a core lens missing (a missing Codex lens is a non-blocking INFO process gap, matching manual-fan-out parity); this restores the manual fan-out's Step 2.5 recovery-protocol discipline that a naive `parallel().filter(Boolean)` would drop. (c) **prompt injection** — untrusted content is wrapped in non-forgeable sentinel markers (a ``` fence can be closed by ``` in the diff; sentinels can't, and a forged END marker is neutralized) behind a guard instructing the reviewer to treat it as DATA and to report embedded instructions as a finding. The manual fan-out shares property (c) and could be hardened the same way in a follow-up.

## Migration Plan

Phased. Phase 0: the Codex-kill spike (gates D3). Phase 1: implement the workflow path behind the capability gate, keeping the manual fan-out as the live fallback — so users without the primitive see zero change (zero-regression rollout). Phase 2 (separate change): idd-all-chain. Rollback: turn the capability gate off (or disable workflows) → the skill runs the manual fan-out, i.e. today's behavior.

## Open Questions

- ~~Can a plugin bundle and register a saved workflow for a consuming session, or must the skill inline the script at call time?~~ **RESOLVED (task 2.3, 2026-06-01): No registration** — plugins have no `workflows/` component; the skill ships the script as a plain `.js` file and passes it to the Workflow tool's `script` parameter inline (see D2).
- ~~Does stopping a workflow agent cleanly terminate a hung `codex exec` child?~~ **RESOLVED (Phase 0 spike, 2026-06-01): PASS** — harness `TaskStop` clean-killed the codex process tree with zero orphan (see D3). In-workflow Codex confirmed viable; skill-level timeout kept as fallback.
- The exact JSON schema for the workflow's structured findings output (refined during apply; must preserve the current merged shape).
