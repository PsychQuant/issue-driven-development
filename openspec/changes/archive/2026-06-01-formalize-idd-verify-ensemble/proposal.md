## Why

`/idd-verify` is a major published IDD skill with **no spec at all** — its 6-AI cross-verification ensemble (5 distinct-lens reviewers + an adversarial devil's-advocate + a cross-model blind Codex verifier) is hand-rolled prose: manual `Agent` fan-out, file-based output to `/tmp`, devil's-advocate polling for the other findings files, and a Codex subprocess that hangs (observed twice in one session, exit 144; tracked in #147).

Claude Code's **dynamic-workflow primitive** (research preview) is the first-class tool this manual fan-out was approximating. Its documented canonical pattern literally is the verify ensemble: a workflow "can have independent agents adversarially review each other's findings before they're reported." The current manual fan-out (introduced in #52 when idd-verify migrated off the experimental Agent Teams / `TeamCreate` model) is a workaround from before the primitive existed.

This change creates the **inaugural `idd-verify` spec** (the ensemble-execution contract) and adopts the dynamic-workflow primitive for the deterministic core, **capability-gated with a manual fallback** so users on older Claude Code or free tier (where the research-preview primitive is unavailable) keep a working verify.

Surfaced + converged via #164 (`/idd-diagnose` + `/spectra-discuss`, 2026-06-01).

## What Changes

- **New `idd-verify` spec** — the ensemble-execution contract: fan-out → cross-check → merge, plus **graceful degradation** across execution backends (dynamic-workflow primitive when available, manual fan-out otherwise) with an **identical findings contract** either way. The spec references `idd-pr-hitl-modes` for the interaction axis (a background workflow is inherently unattended).
- **Hybrid split of the skill** — the deterministic core (5 reviewers fan-out → adversarial verify → merge) moves into a dynamic-workflow script; the skill **keeps** the gates (input-source resolution, PR↔issue correspondence, auto-close detection), the GitHub posting (master + pointer comments), the follow-up triage, and the verify-fix loop. The seam is forced by two workflow constraints: no mid-run user input, and no direct filesystem/shell access from the workflow itself.
- **Codex wrapped inside the workflow** as a bounded-timeout agent that shells out to the Codex CLI, so the workflow runtime can deterministically abort a hung run (directly addressing the #147 hangs). This is **gated by a Phase 0 spike** that confirms a workflow agent can cleanly kill a hung Codex child; if the spike fails, Codex stays external with a skill-level timeout.
- **Capability detection + fallback** — the skill detects whether the workflow primitive is available and falls back to the existing manual fan-out when it is not, emitting a one-line notice.

## Non-Goals

- **idd-all-chain workflow adoption** — this is the converged Phase 2 from #164 ("think together, ship verify-first"); it is a separate future change that will MODIFY the existing `idd-all-chain` spec. Out of scope here.
- **Re-speccing the rest of `/idd-verify`** — the new `idd-verify` spec starts with the ensemble-execution contract only. The gates, PR-mode, auto-close detection, and triage remain skill prose and may be codified into the same spec by later changes; this change does not freeze them.
- **Changing the findings contract or reviewer composition** — the lenses (requirements / logic / security / regression / devil's-advocate + cross-model Codex) and the merged-findings shape are unchanged. Only the execution backend changes.
- **A full Codex subprocess robustness migration** (#147) — this change only bounds Codex via the workflow timeout; the broader subprocess work stays in #147.
- **Implementation in this change** — `/spectra-propose` parks the change; implementation happens under `/spectra-apply` when picked up (P3 parking-lot pacing).

## Capabilities

### New Capabilities

- `idd-verify`: the cross-verification ensemble capability — fan-out of independent agents that cross-check an implementation and merge findings before reporting, with graceful degradation across the dynamic-workflow and manual-fan-out execution backends.

### Modified Capabilities

(none)

## Impact

- **Affected specs**: new `idd-verify` (references `idd-pr-hitl-modes`).
- **Affected code**:
  - New: openspec/specs/idd-verify/spec.md (materialized on archive from this change's delta)
  - New: a dynamic-workflow script implementing the deterministic fan-out → adversarial verify → merge core, shipped with the idd-verify skill (concrete registration path + the inline-vs-bundled decision resolved in design.md)
  - Modified: plugins/issue-driven-dev/skills/idd-verify/SKILL.md (hybrid split — invoke the workflow for the deterministic core, keep gates / posting / triage / verify-fix; add capability detection + manual fallback + Phase 0 Codex-kill spike gate)
  - Modified: plugins/issue-driven-dev/.claude-plugin/plugin.json (version bump)
  - Modified: .claude-plugin/marketplace.json (version bump)
  - Modified: plugins/issue-driven-dev/CHANGELOG.md (entry)
