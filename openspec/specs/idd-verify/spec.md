# idd-verify Specification

## Purpose

Defines the `/idd-verify` capability: an ensemble of independent agents (distinct-lens reviewers + an adversarial devil's-advocate + a cross-model blind verifier) that cross-check an implementation and merge their findings before reporting. Specifies the ensemble-execution contract — fan-out, cross-check, merge — and its graceful degradation across execution backends (the dynamic-workflow primitive when available, manual fan-out otherwise) with an identical findings contract either way.

## Requirements

### Requirement: Independent-agent cross-verification ensemble

The `/idd-verify` capability SHALL verify an implementation through an ensemble of independent agents: distinct-lens reviewers (requirements, logic, security, regression), an adversarial devil's-advocate that attempts to refute the other lenses' pass judgments, and a cross-model blind verifier. The reported result SHALL be the merged, deduplicated union of all sources, with each finding's severity taken as the highest reported.

#### Scenario: ensemble composition and merge

- **WHEN** `/idd-verify` runs on a change
- **THEN** findings are produced from each distinct lens, the devil's-advocate has attempted to refute the other lenses' pass judgments, and the cross-model verifier has run independently
- **AND** the reported findings are the merged + deduplicated union, severity taken highest

---
### Requirement: Deterministic core runs on the dynamic-workflow primitive when available

When the dynamic-workflow primitive is available, the deterministic core — fan-out of reviewers, adversarial verification, and merge — SHALL run as a workflow whose intermediate findings live in the workflow rather than the conversation. The skill SHALL await the workflow's validated findings before any GitHub posting.

#### Scenario: workflow backend selected

- **WHEN** the dynamic-workflow primitive is available and `/idd-verify` runs
- **THEN** the fan-out, adversarial verify, and merge execute as a background workflow
- **AND** the skill awaits the workflow's validated findings array before posting any comment

---
### Requirement: Graceful degradation to manual fan-out with an identical findings contract

When the dynamic-workflow primitive is unavailable, `/idd-verify` SHALL fall back to a manual fan-out that produces findings of an identical contract — the same lenses, the same finding shape, and the same merge semantics — and SHALL emit a one-line notice naming the selected backend. Every step downstream of the core (posting, triage, verify-fix) SHALL be backend-agnostic.

#### Scenario: fallback when primitive unavailable

- **WHEN** the dynamic-workflow primitive is unavailable and `/idd-verify` runs
- **THEN** the manual fan-out runs and a one-line notice names the selected backend
- **AND** the findings shape, posting, and triage are identical to the workflow path

---
### Requirement: Cross-model verifier runs with a bounded lifetime

The cross-model verifier SHALL run with a bounded lifetime so that a hung run cannot block the ensemble — bounded by the workflow runtime when it runs as a workflow agent, or by a skill-level timeout otherwise. A run exceeding its bound SHALL be terminated and recorded in the master report as an incomplete cross-model pass, and SHALL NOT be silently dropped.

#### Scenario: cross-model run hangs

- **WHEN** the cross-model verifier exceeds its lifetime bound
- **THEN** it is terminated and the master report records the cross-model pass as incomplete (a process gap)
- **AND** the remaining ensemble findings are still merged and reported

---
### Requirement: Deterministic core executes under unattended interaction semantics

The deterministic core SHALL execute under unattended interaction semantics — no user input mid-core — consistent with the interaction axis defined in `idd-pr-hitl-modes`. All user-facing decisions (gates, follow-up triage, the verify-fix loop) SHALL occur in the skill before the core starts or after it returns, never inside it.

#### Scenario: no user input during the core

- **WHEN** the deterministic core is executing
- **THEN** no user prompt occurs during it
- **AND** any scope or triage decision is resolved by the skill before the core starts or after it returns its findings

---
### Requirement: Composable verification profiles selectable at the skill layer

`idd-verify` SHALL accept a `--profile <name>` flag selecting a verification profile — a four-tuple of lens set, devil's-advocate focus, default input source, and freshness mechanism — with built-in profiles `code` (default), `prose`, and `academic` defined in `references/verify-profiles.md` as the single source of truth. When `--profile` is absent or `code`, behavior SHALL be byte-identical to the pre-profile skill (lens texts, input auto-detection, and the git diff-freshness gate unchanged). An unknown profile name (neither built-in nor config-defined) SHALL abort with the list of available profiles rather than silently falling back. Repo-local custom profiles MAY be registered under the `verify_profiles` config field; a custom profile whose name collides with a built-in SHALL be ignored with a warning (built-in wins).

#### Scenario: default invocation is unchanged

- **WHEN** `idd-verify #42` runs with no `--profile` flag
- **THEN** the ensemble uses the existing requirements/logic/security/regression lenses and git input auto-detection, byte-identical to pre-profile behavior

#### Scenario: prose profile verifies a document without a git worktree

- **WHEN** `idd-verify #42 --profile prose --file report.md` runs in a non-git directory
- **THEN** the ensemble runs the prose lens set (factual-accuracy-vs-source, format compliance, PII/PHI leak, citation support) against the file content, and the master comment posts to the config-resolved repo's issue

#### Scenario: unknown profile fails loud

- **WHEN** `idd-verify #42 --profile porse` runs and no such profile exists
- **THEN** the skill aborts listing available profiles; no ensemble is dispatched

#### Scenario: custom profile cannot shadow a built-in

- **GIVEN** config `verify_profiles` defines a profile named `code`
- **WHEN** `idd-verify #42` resolves profiles
- **THEN** the built-in `code` profile wins and a warning names the ignored config entry


<!-- @trace
source: verify-profiles
updated: 2026-07-17
code:
  - plugins/issue-driven-dev/skills/idd-verify/.impeccable/hook.cache.json
  - .wiki-last-sync
  - plugins/issue-driven-dev/scripts/.impeccable/hook.cache.json
-->

---
### Requirement: Non-git input sources join input-source resolution

`idd-verify` SHALL accept `--file <path>` and `--dir <path>` as input sources parallel to `--pr` / `--commits` / `--branch` / `--since`, mutually exclusive with them (combining SHALL abort with usage). Profiles whose default input source is `file` SHALL require `--file` or `--dir` and SHALL NOT fall back to git detection. File-mode runs SHALL NOT perform git checkout or branch restore.

#### Scenario: mixed input sources are rejected

- **WHEN** `idd-verify #42 --file report.md --pr 123` is invoked
- **THEN** the skill aborts with a usage error naming the mutual exclusion

#### Scenario: prose profile without an input source aborts

- **WHEN** `idd-verify #42 --profile prose` is invoked with no `--file` / `--dir`
- **THEN** the skill aborts asking for an input source instead of falling back to git diff


<!-- @trace
source: verify-profiles
updated: 2026-07-17
code:
  - plugins/issue-driven-dev/skills/idd-verify/.impeccable/hook.cache.json
  - .wiki-last-sync
  - plugins/issue-driven-dev/scripts/.impeccable/hook.cache.json
-->

---
### Requirement: File-input freshness gate equivalent to the diff-freshness gate

For `--file` / `--dir` input, `idd-verify` SHALL snapshot the SHA-256 of every input file before dispatching the ensemble and SHALL re-hash before posting the aggregate verdict; any mismatch — including added or removed files under `--dir` — SHALL refuse the verdict with a stale-snapshot message and a re-run instruction. The gate SHALL NOT be silently exempted for non-git inputs.

#### Scenario: input mutated mid-verify refuses the verdict

- **GIVEN** an ensemble dispatched over `--file report.md`
- **WHEN** `report.md` changes before the aggregate verdict posts
- **THEN** the skill refuses to post, reports the hash mismatch, and instructs a re-run

<!-- @trace
source: verify-profiles
updated: 2026-07-17
code:
  - plugins/issue-driven-dev/skills/idd-verify/.impeccable/hook.cache.json
  - .wiki-last-sync
  - plugins/issue-driven-dev/scripts/.impeccable/hook.cache.json
-->