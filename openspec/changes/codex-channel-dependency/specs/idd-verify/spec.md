## ADDED Requirements

### Requirement: Codex channel is fully dependency-resolved

`idd-verify`'s codex channel SHALL contain no vendored executable and no model pin: the `codex-call` executable SHALL resolve from the installed `parallel-ai-agents` plugin cache (semver `sort -V`, gated `MIN_PAI` ≥ 2.19.0 — the `codexModel`/`codexEffort` contract floor), and model / effort / max-time governance SHALL resolve per `codex-pro`'s profile contract (gated `MIN_CODEX_PRO` ≥ 0.7.0): `references/defaults.json` as the base layer overlaid by the global then project `profile.yaml`. Resolved values SHALL be passed explicitly — as `codexModel` / `codexEffort` Workflow args on the canonical tier and as explicit `--model` / `--effort` flags on manual-fan-out invocations. A missing or too-old `codex-pro` installation, or an unreadable `defaults.json`, SHALL fail fast with a one-step install instruction and SHALL NOT silently fall back to any hardcoded model.

#### Scenario: no vendored executable in the tree

- **WHEN** the plugin tree is inspected
- **THEN** `plugins/issue-driven-dev/bin/codex-call` does not exist, and the SKILL resolves the executable from the pai plugin cache

#### Scenario: governance flows from codex-pro to the canonical tier

- **GIVEN** codex-pro 0.7.0+ installed with `defaults.json` model `gpt-5.6-sol` and no profile.yaml overrides
- **WHEN** the pai-ensemble canonical tier dispatches
- **THEN** the Workflow args include `codexModel: "gpt-5.6-sol"` and the codex leg runs that model

#### Scenario: project profile overrides the default

- **GIVEN** `./.codex-pro/profile.yaml` sets `effort: high`
- **WHEN** governance resolves
- **THEN** effort is `high` (project layer) while model still comes from `defaults.json`

#### Scenario: absent codex-pro fails fast

- **WHEN** codex-pro is not installed (or < 0.7.0)
- **THEN** idd-verify aborts before dispatch with the instruction `claude plugin install codex-pro@codex-pro`, and no ensemble runs on a guessed model
