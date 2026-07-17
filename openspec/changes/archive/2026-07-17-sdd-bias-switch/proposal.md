## Summary

Add an opt-in repo-level `sdd_bias` config switch: when set to `high`, a #129 hard-gate hit (≥5-file interdependent concept OR shared abstraction) escalates to **Spectra** instead of Plan — so repos that value durable spec records get them for large internal changes, without changing any default. (#252)

## Motivation

The user's standing position (2026-07-10, recorded verbatim in #252): routing should lean more toward SDD because the spectra chain produces durable spec records (`openspec/specs/`), while Plan-tier Implementation Plans are one-shot comments lost in issue timelines. Current Layer 2 makes Spectra a narrow gate (published API contract only) and the SKILL's anti-pattern section explicitly calls internal-refactor-to-Spectra an over-trigger — in direct conflict with that position. Real-world evidence: an AI4o batch judged 8/10 issues SDD-warranted; under current criteria that is over-trigger, but the user ruled it desired behavior. The decided quantum (user, 2026-07-17): **option (c), a config switch** — the most conservative shape; different repos weigh spec-record value vs process weight differently, and defaults stay untouched (no grandfathering needed).

## Proposed Solution

- New optional config field `sdd_bias: "high" | "default"` (absent = `default`) in the IDD local config, documented in the config protocol reference.
- Routing change (idd-diagnose Step 3.5 + rules/sdd-integration.md): when `sdd_bias: high` AND the #129 hard gate fires, the verdict becomes `Spectra via hard-gate (sdd_bias)` instead of `Plan`. Layer 2/3 evaluation is unchanged; Layer 1 disqualifiers still win; meeting-first ordering untouched.
- The anti-pattern section gains a note that the over-trigger framing applies to `sdd_bias: default` repos; `high` repos deliberately accept the process weight for the spec record.
- Verdict format extends the existing ` via X` suffix convention (parsers already strip it — v2.50 precedent).

## Non-Goals

- No default flip (default behavior byte-identical; repos without the field see zero change).
- No Layer 2 definition widening (rejected direction (a) — the published-API line stays).
- No unconditional hard-gate-to-Spectra (rejected direction (b) as a global rule; it lives only behind the switch).
- No retroactive re-evaluation of existing verdicts.

## Impact

- Affected specs: `complexity-hard-gate` (modified — gate exit destination becomes config-sensitive)
- Affected code:
  - Modified: plugins/issue-driven-dev/rules/sdd-integration.md, plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md, plugins/issue-driven-dev/references/config-protocol.md, plugins/issue-driven-dev/scripts/tests/complexity-hard-gate/test.sh
  - New: (none — assertions join the existing hard-gate suite)
  - Removed: (none)
