## 1. Tests first (RED)

- [x] 1.1 (Req: MUST-trigger complexity hard gate layered above Layer P — escalation destination is config-sensitive) Extend plugins/issue-driven-dev/scripts/tests/complexity-hard-gate/test.sh with sdd_bias assertions: sdd-integration.md documents the `sdd_bias` switch + both exits (`Plan` default / `Spectra via hard-gate (sdd_bias)` high) + invalid-degrades-to-default; idd-diagnose Step 3.5 mirrors it; config-protocol documents the field. Run: RED (prose absent).

## 2. Prose (GREEN — per Design D1–D4)

- [x] 2.1 (Design D3 — config read is walk-up, absent-safe) references/config-protocol.md — new `### sdd_bias field` (values, default, absent/invalid semantics, walk-up, trade-off note: hours-scale chain weight for spec records). Verify: suite config assertions GREEN.
- [x] 2.2 (Design D1 — the switch acts at exactly one point: the hard-gate exit; D2 — verdict format reuses the ` via X` suffix convention; D4 — the anti-pattern section is qualified, not deleted) rules/sdd-integration.md — hard-gate section: exit becomes config-sensitive (both verdict strings verbatim); anti-pattern section gains the D4 scoping sentence. Verify: suite sdd-integration assertions GREEN.
- [x] 2.3 (Design D1 — the switch acts at exactly one point: the hard-gate exit; D2 — verdict format reuses the ` via X` suffix convention) skills/idd-diagnose/SKILL.md Step 3.5 — step-5 exit text mirrors the switch (read config walk-up, absent-safe); verdict format documented. Verify: suite Step 3.5 assertions GREEN; full plugin sweep 0 fail; spectra validate clean.
