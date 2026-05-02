# idd-route — CLAUDE.md

## Purpose

Data-driven agent routing for IDD methodology. Wraps the [`PsychQuant/idd-route-swift`](https://github.com/PsychQuant/idd-route-swift) Swift binary, distributed via plugin auto-download (`bin/idd-route-wrapper.sh`).

Recommends the best agent (Codex GPT-5.5 xhigh / Claude Opus 4.7 / Sonnet 4.6 / Haiku 4.5) for each new IDD issue based on observed track record per `(complexity, scope_class)` bucket with exponential decay. Falls back to a static heuristic rubric on cold start (< 5 data points in bucket).

## Skills

| Skill | Purpose |
|-------|---------|
| `/idd-route:recommend` | Ad-hoc lookup: "given this issue's features, which agent should implement?" |
| `/idd-route:stats` | Human-readable markdown summary of routing-stats.jsonl |
| `/idd-route:backfill` | One-shot seed from past GH verify comments (cold start救星)。**Requires binary v0.3.0** (P2 of plan)。 |

## Hooks

(none — `idd-route` doesn't fire on tool events; the `issue-driven-dev` plugin's `idd-verify` / `idd-close` skills call the binary directly via `~/bin/idd-route`)

## Binary

Source: [`PsychQuant/idd-route-swift`](https://github.com/PsychQuant/idd-route-swift) — universal arm64+x86_64 macOS Swift binary.

Distribution: `bin/idd-route-wrapper.sh` reads `binaries.idd-route.version` from `plugin.json`, compares against `~/bin/.idd-route.version` sidecar, atomic-downloads from GH release if stale. Mirrors `che-word-mcp-wrapper.sh` pattern. Uses `gh api` if available (auth'd, high rate limit), falls back to plain `curl` (60/hr unauth limit).

Current pinned version: **v0.2.0** (record / recommend / stats / summarize commands; v0.3.0 will add update-outcome + backfill).

## Stats data flow

```
idd-verify (in issue-driven-dev) ─→ ~/bin/idd-route record ... --outcome in_review
                                            └─→ <repo>/.claude/.idd/routing-stats.jsonl
                                            └─→ ~/.cache/idd-route/stats.jsonl (mirror)

idd-close  (in issue-driven-dev) ─→ ~/bin/idd-route update-outcome ... --outcome merged|abandoned
                                            └─→ append a new record (jsonl is append-only)

idd-diagnose (in issue-driven-dev) ─→ ~/bin/idd-route recommend ...
                                            └─→ stdout JSON {recommended, confidence, ...}
```

The `issue-driven-dev` skills invoke the binary at `~/bin/idd-route` directly (NOT via `${CLAUDE_PLUGIN_ROOT}/../idd-route/bin/...`) — decouples plugin path layout from skill code; idd-route binary can also be installed via `cli-tools:cli-install` for non-IDD users.

## Three-tier config injection

```
1. <repo>/.claude/idd-route.json     ← per-project (highest priority)
2. ~/.cache/idd-route/config.json    ← per-machine
3. Built-in defaults                 ← in PsychQuant/idd-route-swift
```

Plus kill-switch:

```bash
touch ~/.cache/idd-route/disabled    # `idd-verify` skips record call entirely
```

Schema (all optional):

```json
{
  "enabled": true,
  "global_mirror": true,
  "decay_half_life_days": 30,
  "min_data_points": 5,
  "candidates": ["codex-gpt-5.5-xhigh", "claude-opus-4.7"]
}
```

## Format spec

`routing-stats.jsonl` schema documented in [`PsychQuant/idd-route-swift README.md`](https://github.com/PsychQuant/idd-route-swift#schema). Append-only; forward-compatible; reader tolerates new optional fields.

## References

- [`signal-vocabulary.md`](references/signal-vocabulary.md) — controlled signal terms used by `--signals` flag
- [`static-heuristic.md`](references/static-heuristic.md) — cold-start fallback rubric
- [`PsychQuant/idd-route-swift`](https://github.com/PsychQuant/idd-route-swift) — binary source repo
- [`PsychQuant/issue-driven-development/plugins/issue-driven-dev`](../issue-driven-dev) — IDD core plugin (consumes idd-route via direct binary calls)

## Why a separate plugin

Could be inlined into `issue-driven-dev`, but as a separate plugin:

- Binary lifecycle is independent (idd-route-swift releases on its own cadence)
- Other tools / CI / standalone scripts can depend on idd-route without bringing in IDD core
- Skills are discoverable via `/idd-route:*` namespace
- User can disable just routing (uninstall idd-route) while keeping IDD core
