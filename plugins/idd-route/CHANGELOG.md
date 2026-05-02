# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-05-02

### Changed
- Pinned binary version `binaries.idd-route.version`: 0.2.0 → 0.3.0. Wrapper auto-downloads new binary on next invocation (atomic swap; `~/bin/.idd-route.version` sidecar tracks installed version).

### Added
- `/idd-route:backfill` skill is now functional (was placeholder in v0.1.0 — the underlying `idd-route backfill` command shipped in idd-route-swift v0.3.0).
- Companion: idd-close Step 4.5 in issue-driven-dev v2.38.0+ now successfully calls `idd-route update-outcome` instead of gracefully no-op'ing on command-not-found.

## [0.1.0] - 2026-05-02

### Added
- Plugin shell for `PsychQuant/idd-route-swift` Swift binary (v0.2.0).
- `bin/idd-route-wrapper.sh` — version-aware auto-download (mirrors `che-word-mcp` pattern). Reads `binaries.idd-route.version` from `plugin.json`, compares against `~/bin/.idd-route.version` sidecar, atomic-downloads from GH release if stale. Uses `gh api` if available (auth'd, high rate limit), falls back to `curl` (60/hr unauth limit).
- `/idd-route:recommend` skill — ad-hoc agent recommendation lookup. Reads per-repo `routing-stats.jsonl` + optional `~/.cache/idd-route/stats.jsonl` global mirror; falls back to static heuristic when < 5 data points (exit code 3).
- `/idd-route:stats` skill — markdown summary of routing-stats by agent + by `(agent × complexity × scope_class)` bucket.
- `/idd-route:backfill` skill — placeholder for binary v0.3.0's backfill command (one-shot seed from GH verify comment history). Skill ships now; binary support lands in P2 of the rollout plan.
- `references/signal-vocabulary.md` — controlled vocabulary for `--signals` flag (12 named signals: explicit_acceptance, single_handler, design_negotiation, sibling_sweep_needed, etc) with detection heuristics + per-signal scoring weights.
- `references/static-heuristic.md` — full static fallback rubric documentation, calibration notes, update procedure when data shows the rubric needs adjustment.
- `CLAUDE.md` — plugin design philosophy, three-tier config injection, stats data flow, why-separate-plugin rationale.

### Changed
- Plugin is intentionally thin — the 3 skills are mostly argv-passthrough to `~/bin/idd-route`. Interesting logic lives in the Swift binary (`PsychQuant/idd-route-swift`).
- `issue-driven-dev` plugin (sibling in this marketplace) doesn't need this plugin to be installed for its core workflow, but if installed, `idd-diagnose` / `idd-verify` / `idd-close` call `~/bin/idd-route` directly to record + recommend.
