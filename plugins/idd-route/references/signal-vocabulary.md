# Signal Vocabulary

Controlled vocabulary for `scope_signals` (the field that drives recommendation bucketing + static heuristic scoring). Extensible — unknown signals are informational only and have no scoring impact.

When `idd-diagnose` runs, it should detect which of these signals apply to the new issue and pass them to `idd-route recommend --signals s1,s2,...`.

## Codex-favoring signals

| Signal | Detection heuristic | Static heuristic score |
|--------|---------------------|------------------------|
| `explicit_acceptance` | Issue body has structured "Suggested fix" or "Acceptance criteria" section, or numbered "Expected behavior" list | +2 Codex |
| `single_handler` | Diagnosis identifies one function/handler/file as the sole change site | +1 Codex |
| `test_extension` | Existing test file/class can be extended (no new fixture infrastructure) | +1 Codex |
| `mechanical_fix` | Repetitive structural change (rename, dep bump, format conversion) | +1 Codex |

Codex's strength: literal implementation of well-specified narrow tasks. Weakness: rarely extends scope to fix sibling instances.

## Claude-favoring signals

| Signal | Detection heuristic | Static heuristic score |
|--------|---------------------|------------------------|
| `hot_context` | Issue was just diagnosed inside a longer Claude conversation about the same area (context already loaded) | +1 Claude |
| `design_negotiation` | Issue body uses "I think we need", "consider", "explore", "rethink" | +2 Claude |
| `redesign` | Body uses "refactor", "rethink", "redesign", "rewrite" | +2 Claude |
| `sibling_sweep_needed` | Diagnosis notes the same pattern in N other locations that should be fixed together | +1 Claude |
| `cross_repo` | Touches submodule or sibling repo (multi-repo coordination) | +2 Claude |
| `requires_changelog` | BREAKING change or notable feature warranting CHANGELOG.md / migration notes | +1 Claude |
| `breaking_change` | Caller-visible contract change (label or body explicit) | +1 Claude |
| `public_api` | Change touches an exported MCP tool surface or public Swift API | +1 Claude |

Claude's strength: scope-aware sweeps + design negotiation + deployment coordination. Weakness: tends to over-implement when scope is already tight.

## Informational-only signals (no scoring)

These are recorded for analysis but don't affect static heuristic. Useful for future analysis or new heuristic rules:

- `multi_file` — scope spans 3+ files (broader scope, but doesn't directly favor either agent)
- `new_test_infrastructure` — needs new test fixture or harness from scratch
- (add more as patterns emerge — they'll show up in `idd-route stats` per-bucket aggregates)

## How signals affect recommendations

1. `idd-diagnose` extracts signals from the issue body + Claude's analysis
2. Signals get serialized into `--signals s1,s2,s3` when calling `idd-route recommend`
3. The recommendation engine uses signals **only for static heuristic fallback** (when fewer than 5 data points exist for a bucket). Once warm, the data-driven scoring (merge_rate / round_trips / blocking) takes over and signals are recorded for analysis but don't directly affect scoring.

This design keeps the warm-state recommendation purely empirical (what the data says) while the cold-start fallback uses the rubric distilled from the IDD vs Codex retrospective.

## Adding new signals

To propose a new signal:

1. Detect a recurring pattern in `idd-route stats` per-bucket aggregates (e.g., "issues with `requires_translation` signal seem to favor X")
2. Add the signal to this vocabulary doc with detection heuristic
3. Update `references/static-heuristic.md` if the signal should affect scoring
4. Update `Sources/IDDRoute/Logic/StaticHeuristic.swift` in `PsychQuant/idd-route-swift` if static rubric needs the new term
5. Bump `idd-route-swift` minor version (vocabulary extensions are forward-compatible)
