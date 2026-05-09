# idd-orchestrator-modes Specification

## Purpose

TBD - created by archiving change 'idd-all-hitl-mode'. Update Purpose after archive.

## Requirements

### Requirement: Mode resolution from pr_policy and flags

`idd-all` SHALL resolve a `(path, interaction)` tuple at Phase 0.5 from the existing `pr_policy` config field, `--pr` / `--no-pr` per-invocation flags, and the new `--in-chain` per-invocation flag introduced in v2.55.0+. The two axes MUST derive from a single source of truth — either `pr_policy` or `--in-chain` — to prevent duplicate config surfaces.

Resolution precedence (first match wins):

1. `--in-chain` flag → `(direct-commit, unattended)` — chain context tuple introduced for `/idd-all-chain` recursive invocations
2. `--pr` flag → `(PR, unattended)`
3. `--no-pr` flag → `(direct-commit, attended)`
4. Fork detected (`gh repo view --json isFork` returns true) → `(PR, unattended)` regardless of config
5. `pr_policy: always` → `(PR, unattended)`
6. `pr_policy: never` → `(direct-commit, attended)`
7. `pr_policy: ask` (explicitly set) → `AskUserQuestion`; first answer locks the tuple for the invocation
8. `pr_policy` absent (no config file, or field missing) → `(PR, unattended)` — v2.40.0 backward-compat default; protects existing `/loop` automation callers from interactive hang

The resolved tuple MUST be printed as a one-line notice before any state-mutating action, e.g. `→ Path: direct-commit (attended) — pr_policy=never` or `→ Path: direct-commit (unattended) — flag=--in-chain`.

The `--in-chain` flag MUST NOT be combined with `--pr` or `--no-pr` in the same invocation. Combining them MUST cause `idd-all` to abort with a conflict error before Phase 0.3 universal pre-flight gates run.

When tuple is `(direct-commit, unattended)` resolved from `--in-chain`, `idd-all` Phase 0.5 MUST skip PR-mode branch creation (no `git checkout -b idd/<N>-<slug>`) and remain on the current branch (assumed to be a cluster branch managed by the calling `/idd-all-chain` shell). Phase 5.5 PR creation MUST be skipped entirely (the cluster PR is opened by `/idd-all-chain` Phase 3 after the chain queue completes).

#### Scenario: explicit --no-pr flag

- **WHEN** user invokes `idd-all #42 --no-pr`
- **THEN** `idd-all` resolves `(path, interaction) = (direct-commit, attended)`
- **AND** prints `→ Path: direct-commit (attended) — flag=--no-pr` before Phase 1

#### Scenario: pr_policy=never config

- **GIVEN** `.claude/issue-driven-dev.local.json` contains `"pr_policy": "never"`
- **WHEN** user invokes `idd-all #42` with no `--pr` / `--no-pr` flag
- **THEN** `idd-all` resolves `(path, interaction) = (direct-commit, attended)`

#### Scenario: fork forces PR path

- **GIVEN** the target repo is a fork (`gh repo view --json isFork` returns true)
- **AND** config sets `pr_policy: never`
- **WHEN** user invokes `idd-all #42`
- **THEN** `idd-all` resolves `(path, interaction) = (PR, unattended)` and prints a one-line override notice citing fork detection

#### Scenario: backward-compatible default (explicit --pr)

- **GIVEN** no `pr_policy` config exists and the repo is not a fork
- **WHEN** user invokes `idd-all #42 --pr`
- **THEN** `idd-all` resolves `(path, interaction) = (PR, unattended)` — identical to v2.40.0 behavior

#### Scenario: backward-compatible default (no flag, no config)

- **GIVEN** no `pr_policy` config exists and the repo is not a fork
- **AND** user invokes `idd-all #42` with no `--pr` / `--no-pr` flag (the typical `/loop` automation shape)
- **WHEN** Phase 0.5 mode resolution runs
- **THEN** `idd-all` resolves `(path, interaction) = (PR, unattended)` and prints `→ Path: PR (unattended) — pr_policy absent (v2.40.0 default)` before Phase 1
- **AND** does NOT invoke `AskUserQuestion`; absent-config callers never hang waiting for interactive input

#### Scenario: explicit ask requires user choice

- **GIVEN** `.claude/issue-driven-dev.local.json` contains `"pr_policy": "ask"` (explicitly set, not omitted)
- **AND** user invokes `idd-all #42` with no `--pr` / `--no-pr` flag
- **AND** the repo is not a fork
- **WHEN** Phase 0.5 mode resolution runs
- **THEN** `idd-all` invokes the `AskUserQuestion` Claude tool with two options (PR vs direct-commit)
- **AND** the first answer locks the tuple for the invocation

#### Scenario: in-chain flag resolves to chain-context tuple

- **GIVEN** user has a cluster branch `idd/chain-28-foo` checked out (e.g. from `/idd-all-chain` Phase 0)
- **WHEN** the chain shell invokes `idd-all #34 --in-chain`
- **THEN** `idd-all` resolves `(path, interaction) = (direct-commit, unattended)`
- **AND** prints `→ Path: direct-commit (unattended) — flag=--in-chain` before Phase 1
- **AND** Phase 0.5 PR-mode branch creation is skipped; the invocation remains on `idd/chain-28-foo`
- **AND** sub-skills receive an `UNATTENDED MODE` directive suppressing `AskUserQuestion`
- **AND** Phase 5.5 PR creation is skipped (the cluster PR is opened later by `/idd-all-chain`)

#### Scenario: in-chain flag conflicts with --pr or --no-pr

- **GIVEN** any combination such as `idd-all #34 --in-chain --pr` or `idd-all #34 --in-chain --no-pr`
- **WHEN** Phase 0.2 argument parsing runs
- **THEN** `idd-all` aborts with a conflict error message naming both flags and instructing the user to pick exactly one
- **AND** does NOT proceed to Phase 0.3 universal pre-flight gates


<!-- @trace
source: add-idd-all-chain-skill
updated: 2026-05-10
code:
  - .spectra.yaml
  - .agents/skills/spectra-ingest/SKILL.md
  - plugins/issue-driven-dev/scripts/manifest-append.sh
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/CLAUDE.md
  - .agents/skills/spectra-archive/SKILL.md
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/spectra-apply/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/references/spawn-manifest.md
  - .agents/skills/spectra-commit/SKILL.md
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .claude-plugin/marketplace.json
  - .agents/skills/spectra-drift/SKILL.md
  - plugins/issue-driven-dev/skills/idd-all-chain/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - plugins/issue-driven-dev/skills/idd-verify/SKILL.md
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - docs/design-patterns/default-dilemma.md
  - plugins/issue-driven-dev/references/chain-flow.md
  - .agents/skills/spectra-debug/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - AGENTS.md
-->

---
### Requirement: PR path preserves v2.40.0 behavior

When the resolved path is `PR`, `idd-all` SHALL behave identically to v2.40.0: enforce a feature branch off the default branch, pass an unattended hint to every sub-skill invocation, push the branch, and create a PR after verify PASS. No existing caller (including `/loop` automation) MUST observe behavioral drift.

#### Scenario: PR path enforces feature branch

- **GIVEN** resolved path is `PR`
- **AND** the working tree is on the default branch with no uncommitted changes
- **WHEN** Phase 0.5 completes
- **THEN** `idd-all` checks out a new branch named `idd/<N>-<slug>` per `references/pr-flow.md`

#### Scenario: PR path passes unattended hint

- **GIVEN** resolved interaction is `unattended`
- **WHEN** `idd-all` invokes any sub-skill via the `Skill` tool
- **THEN** the args string includes an `UNATTENDED MODE` directive instructing the sub-skill to suppress `AskUserQuestion` calls and converge in one round

#### Scenario: PR path opens PR after verify PASS

- **GIVEN** Phase 4 verify reports zero blocking findings
- **AND** resolved path is `PR`
- **WHEN** Phase 5 executes
- **THEN** `idd-all` runs `git push -u origin <branch>` followed by `gh pr create` with body containing `Refs #<N>` and forbidding any `Closes` / `Fixes` / `Resolves` trailer


<!-- @trace
source: idd-all-hitl-mode
updated: 2026-05-04
code:
  - plugins/issue-driven-dev/references/usecase-routing.md
  - .agents/skills/spectra-debug/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - .claude-plugin/marketplace.json
  - plugins/issue-driven-dev/CLAUDE.md
  - plugins/issue-driven-dev/references/ic-r011-checkpoint.md
  - .agents/skills/spectra-ask/SKILL.md
  - AGENTS.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - CLAUDE.md
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - plugins/issue-driven-dev/references/pr-flow.md
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - .spectra.yaml
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
-->

---
### Requirement: Direct-commit path stays on current branch and skips PR

When the resolved path is `direct-commit`, `idd-all` SHALL NOT create a feature branch, SHALL NOT push, and SHALL NOT create a PR. Commits land on whichever branch the user currently has checked out. Phase 5 PR creation steps MUST be skipped, advancing directly to Phase 6 report.

#### Scenario: direct-commit on default branch

- **GIVEN** resolved path is `direct-commit`
- **AND** user is on the default branch
- **WHEN** `idd-all` runs Phases 1–4
- **THEN** commits land on the default branch and no `idd/<N>-<slug>` branch is created

#### Scenario: direct-commit respects pre-existing feature branch

- **GIVEN** resolved path is `direct-commit`
- **AND** user is already on a feature branch named `wip/foo`
- **WHEN** `idd-all` runs
- **THEN** commits land on `wip/foo` without checking out any new branch

#### Scenario: direct-commit skips PR creation

- **GIVEN** resolved path is `direct-commit`
- **WHEN** Phase 5 begins
- **THEN** Phase 5 logs `→ direct-commit path: skipping push + PR` and advances to Phase 6 without invoking `git push` or `gh pr create`


<!-- @trace
source: idd-all-hitl-mode
updated: 2026-05-04
code:
  - plugins/issue-driven-dev/references/usecase-routing.md
  - .agents/skills/spectra-debug/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - .claude-plugin/marketplace.json
  - plugins/issue-driven-dev/CLAUDE.md
  - plugins/issue-driven-dev/references/ic-r011-checkpoint.md
  - .agents/skills/spectra-ask/SKILL.md
  - AGENTS.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - CLAUDE.md
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - plugins/issue-driven-dev/references/pr-flow.md
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - .spectra.yaml
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
-->

---
### Requirement: Attended interaction permits sub-skill questions

When the resolved interaction is `attended`, `idd-all` SHALL NOT inject any `UNATTENDED MODE` directive into sub-skill invocation args. Each sub-skill's own attended-by-default behavior — `idd-implement` plan-tier `EnterPlanMode` approval, `spectra-discuss` multi-turn pacing, `spectra-propose` Step 10 Park/Apply prompt, `idd-implement` `AskUserQuestion` checkpoints — MUST take effect natively.

#### Scenario: attended mode allows EnterPlanMode

- **GIVEN** resolved interaction is `attended`
- **AND** Phase 2 diagnose returns Complexity = `Plan`
- **WHEN** Phase 3a invokes `idd-implement`
- **THEN** the args string contains no `UNATTENDED MODE` directive
- **AND** `idd-implement` enters Plan tier and triggers `EnterPlanMode` for user approval

#### Scenario: attended mode allows spectra-discuss multi-turn

- **GIVEN** resolved interaction is `attended`
- **AND** Phase 2 diagnose returns Complexity = `Spectra`
- **WHEN** Phase 3b invokes `spectra-discuss`
- **THEN** the args string contains no `UNATTENDED MODE` directive
- **AND** `spectra-discuss` paces the discussion across multiple turns using `AskUserQuestion` per its native default


<!-- @trace
source: idd-all-hitl-mode
updated: 2026-05-04
code:
  - plugins/issue-driven-dev/references/usecase-routing.md
  - .agents/skills/spectra-debug/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - .claude-plugin/marketplace.json
  - plugins/issue-driven-dev/CLAUDE.md
  - plugins/issue-driven-dev/references/ic-r011-checkpoint.md
  - .agents/skills/spectra-ask/SKILL.md
  - AGENTS.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - CLAUDE.md
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - plugins/issue-driven-dev/references/pr-flow.md
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - .spectra.yaml
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
-->

---
### Requirement: Verify is the terminal phase regardless of mode

`idd-all` SHALL stop after Phase 6 report in both `(PR, unattended)` and `(direct-commit, attended)` modes. Closing the underlying GitHub issue MUST remain a separate user-initiated action via `idd-close`. `idd-all` MUST NOT auto-invoke `idd-close` under any mode.

#### Scenario: PR path stops at verify

- **GIVEN** resolved path is `PR` and verify PASSes
- **WHEN** Phase 6 completes
- **THEN** `idd-all` prints `Next: review PR <url>, merge, then run /idd-close #<N>` and exits

#### Scenario: direct-commit path stops at verify

- **GIVEN** resolved path is `direct-commit` and verify PASSes
- **WHEN** Phase 6 completes
- **THEN** `idd-all` prints `Next: review last <N> commits, then run /idd-close #<N>` and exits


<!-- @trace
source: idd-all-hitl-mode
updated: 2026-05-04
code:
  - plugins/issue-driven-dev/references/usecase-routing.md
  - .agents/skills/spectra-debug/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - .claude-plugin/marketplace.json
  - plugins/issue-driven-dev/CLAUDE.md
  - plugins/issue-driven-dev/references/ic-r011-checkpoint.md
  - .agents/skills/spectra-ask/SKILL.md
  - AGENTS.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - CLAUDE.md
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - plugins/issue-driven-dev/references/pr-flow.md
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - .spectra.yaml
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
-->

---
### Requirement: No silent timeout on sub-skill questions

`idd-all` SHALL NOT impose any silent timeout on sub-skill `AskUserQuestion` or `EnterPlanMode` prompts when running in attended interaction mode. The skill documentation MUST state explicitly that attended mode assumes a user is in session.

#### Scenario: attended mode honors indefinite wait

- **GIVEN** resolved interaction is `attended`
- **AND** a sub-skill issues an `AskUserQuestion`
- **WHEN** the user does not respond for 30 minutes
- **THEN** `idd-all` does not abort, kill, or auto-answer the prompt; the sub-skill remains paused awaiting user input


<!-- @trace
source: idd-all-hitl-mode
updated: 2026-05-04
code:
  - plugins/issue-driven-dev/references/usecase-routing.md
  - .agents/skills/spectra-debug/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - .claude-plugin/marketplace.json
  - plugins/issue-driven-dev/CLAUDE.md
  - plugins/issue-driven-dev/references/ic-r011-checkpoint.md
  - .agents/skills/spectra-ask/SKILL.md
  - AGENTS.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - CLAUDE.md
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - plugins/issue-driven-dev/references/pr-flow.md
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - .spectra.yaml
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
-->

---
### Requirement: Documentation reflects two-mode contract

The `idd-all` SKILL.md frontmatter `argument-hint` and `description` SHALL document the new mode matrix. `references/pr-flow.md` SHALL include an additive section stating that `idd-all` consumes `pr_policy` identically to `idd-implement`. The skill body SHALL include at least one usage trace per resolved tuple — a `(PR, unattended)` example and a `(direct-commit, attended)` example.

#### Scenario: argument-hint mentions --no-pr

- **WHEN** a user reads the `idd-all` SKILL.md frontmatter
- **THEN** the `argument-hint` field includes `--no-pr` and a one-line description of the HITL direct-commit mode it triggers

#### Scenario: pr-flow.md cross-references idd-all

- **WHEN** a maintainer reads `references/pr-flow.md`
- **THEN** the document contains a section titled `idd-all path resolution` (or equivalent) explicitly stating that `idd-all` resolves `pr_policy` per the same algorithm as `idd-implement`

<!-- @trace
source: idd-all-hitl-mode
updated: 2026-05-04
code:
  - plugins/issue-driven-dev/references/usecase-routing.md
  - .agents/skills/spectra-debug/SKILL.md
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - .claude-plugin/marketplace.json
  - plugins/issue-driven-dev/CLAUDE.md
  - plugins/issue-driven-dev/references/ic-r011-checkpoint.md
  - .agents/skills/spectra-ask/SKILL.md
  - AGENTS.md
  - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - .agents/skills/spectra-commit/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - .agents/skills/spectra-archive/SKILL.md
  - CLAUDE.md
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - plugins/issue-driven-dev/references/pr-flow.md
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/spectra-apply/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - .spectra.yaml
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - .agents/skills/spectra-ingest/SKILL.md
-->