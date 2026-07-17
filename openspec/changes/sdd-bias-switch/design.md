## Context

The quantum was the only open question and the user decided it: config switch (option c). This design records the mechanics so the switch composes cleanly with the existing 7-step meeting-first routing.

## Goals / Non-Goals

**Goals**: opt-in per-repo Spectra escalation at the hard-gate exit; zero default change; verdict transparency. **Non-Goals**: Layer 2 widening; default flip; retroactive re-evaluation (see proposal).

## Decisions

### D1 — The switch acts at exactly one point: the hard-gate exit

The 7-step order is untouched: (1) meeting → (2) Layer 1 → (3) Layer V → (4) Spectra L2+L3 → (5) hard gate → (6) Layer P → (7) Simple. `sdd_bias: high` only rewrites step 5's exit (`Plan` → `Spectra via hard-gate (sdd_bias)`). Rationale: the hard gate already mechanically identifies "large interdependent change worth deliberation"; the bias question is only *which* deliberation tier. Layer-2-qualified issues reach Spectra at step 4 regardless; Layer-1 disqualified stay Simple regardless.

### D2 — Verdict format reuses the ` via X` suffix convention

`Spectra via hard-gate (sdd_bias)` — downstream parsers (idd-implement Step 2.5, idd-all Phase 2, idd-list) already `split(' via ')[0]`, so no parser changes (v2.50 precedent). The suffix keeps the audit trail honest about WHY the issue routed to Spectra.

### D3 — Config read is walk-up, absent-safe

`sdd_bias` read from the walked-up IDD config (new path first, legacy fallback — mechanism 4). Absent / any value other than `high` → `default`. Invalid values do not error (routing must never abort on config noise); the audit line notes the resolved value only when it changed the outcome.

### D4 — The anti-pattern section is qualified, not deleted

The "internal cross-file refactor → should be Plan not Spectra" over-trigger guidance stays true for `sdd_bias: default` repos; the section gains one sentence scoping it and pointing at the switch. This resolves the documented conflict with the user's position without weakening the default guidance.

## Risks / Trade-offs

- **Process weight on high-bias repos**: hard-gate hits become hours-scale spectra chains — deliberate, per the user's value call; the switch is opt-in per repo.
- **Verdict drift in drift-guards**: complexity-hard-gate suite asserts exit tokens; assertions extended to cover both exits (default Plan / high Spectra) rather than replaced.

## Migration Plan

Additive config field; no migration. Repos without the field behave byte-identically.

## Open Questions

(none — quantum decided by user 2026-07-17)
