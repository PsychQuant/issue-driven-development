# Static Heuristic Fallback Rubric

When `idd-route recommend` finds fewer than 5 data points in the matching `(complexity, scope_class)` bucket for any candidate, it falls back to this static rubric.

Source: distilled from the #98 (Claude IDD, 3 round trips, 2 P1 caught) vs #111 (Codex, 1 commit, 0 blocking) retrospective. Encoded in [`PsychQuant/idd-route-swift`](https://github.com/PsychQuant/idd-route-swift) `Sources/IDDRoute/Logic/StaticHeuristic.swift`.

## Per-signal scoring

Additive — each detected signal contributes its score to the appropriate side.

| Signal | Codex score | Claude score |
|--------|-------------|--------------|
| `explicit_acceptance` | +2 | — |
| `single_handler` | +1 | — |
| `test_extension` | +1 | — |
| `mechanical_fix` | +1 | — |
| `hot_context` | — | +1 |
| `design_negotiation` | — | +2 |
| `redesign` | — | +2 |
| `sibling_sweep_needed` | — | +1 |
| `cross_repo` | — | +2 |
| `requires_changelog` | — | +1 |
| `breaking_change` | — | +1 |
| `public_api` | — | +1 |

## Complexity baseline

| Complexity tier | Codex score | Claude score |
|-----------------|-------------|--------------|
| `Simple` | +1 | — |
| `Plan` | — | — |
| `Spectra` | — | +2 |

## Tie-breaking

If `codex_score == claude_score` (or both zero), pick **Codex** — the cheaper/faster default.

If a candidate list contains multiple agents from the winning family (e.g., `claude-opus-4.7` + `claude-sonnet-4.6` + `claude-haiku-4.5`), the **first matching candidate from the input order** wins. Convention: caller orders the candidate list with the preferred default first.

## Why this rubric

| Pattern | Why it favors that agent |
|---------|-------------------------|
| Explicit acceptance criteria | Codex literal-implementation strength shines |
| Single handler / test extension / mechanical fix | Narrow scope = no need for sibling sweep instinct |
| Design negotiation / redesign | Claude's spec-pushback + holistic-design strength |
| Cross-repo / sibling sweep needed | Claude naturally extends across context |
| Breaking / public-api / requires-changelog | Claude tends to handle deployment coordination instinctively (Codex skips CHANGELOG, sibling fixes) |
| Hot context | Conversation momentum makes Claude implementation 2-3x faster than re-loading Codex |
| Spectra complexity (+2 Claude) | Public API / spec contract demands design negotiation |
| Simple complexity (+1 Codex) | Mechanical fixes are Codex's sweet spot |

## When does this fallback fire?

After the engine filters past decisions to the matching bucket and groups by candidate (or family if `--strict-version` not set), if NO candidate has at least `--min-data-points` (default 5) records, all candidates show `status: insufficient_data` and the engine punts to this rubric.

A `recommend` invocation with fallback returns:

- `data_source: "static_heuristic"`
- `confidence: 0.5` (not data-derived; explicit low-confidence marker)
- `fallback_used: true`
- Exit code `3` (signals to caller "this recommendation is not data-validated")

## Calibration notes

- Tie → Codex assumption is biased toward "let new tasks try Codex first to gather data"; this accelerates ramp-up of the data-driven recommendation
- The rubric is intentionally not symmetric: Claude scores are heavier (+2 for design / redesign / cross_repo / Spectra) because these are higher-stakes signals where misrouting costs more (incorrect Codex pick on Spectra change → bigger blast radius)
- Once a bucket has ≥5 data points, the rubric stops mattering — the data-driven score (`merge_rate / (avg_round_trips × (1 + avg_blocking))`) takes over

## Updating the rubric

If the data shows the rubric is biased (e.g., Codex consistently wins buckets the rubric pushed Claude into), update by:

1. Identify mismatched signal (e.g., `requires_changelog` actually doesn't favor Claude as much as +1 suggests)
2. Adjust score in `Sources/IDDRoute/Logic/StaticHeuristic.swift`
3. Bump `idd-route-swift` minor version
4. Bump `binaries.idd-route.version` in this plugin's `plugin.json`
5. Update this doc

The rubric is meant to evolve. The data is the source of truth; this rubric is just the cold-start prior.
