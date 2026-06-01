## Purpose

Defines the `/idd-verify` capability: an ensemble of independent agents (distinct-lens reviewers + an adversarial devil's-advocate + a cross-model blind verifier) that cross-check an implementation and merge their findings before reporting. Specifies the ensemble-execution contract — fan-out, cross-check, merge — and its graceful degradation across execution backends (the dynamic-workflow primitive when available, manual fan-out otherwise) with an identical findings contract either way.

## ADDED Requirements

### Requirement: Independent-agent cross-verification ensemble

The `/idd-verify` capability SHALL verify an implementation through an ensemble of independent agents: distinct-lens reviewers (requirements, logic, security, regression), an adversarial devil's-advocate that attempts to refute the other lenses' pass judgments, and a cross-model blind verifier. The reported result SHALL be the merged, deduplicated union of all sources, with each finding's severity taken as the highest reported.

#### Scenario: ensemble composition and merge

- **WHEN** `/idd-verify` runs on a change
- **THEN** findings are produced from each distinct lens, the devil's-advocate has attempted to refute the other lenses' pass judgments, and the cross-model verifier has run independently
- **AND** the reported findings are the merged + deduplicated union, severity taken highest

### Requirement: Deterministic core runs on the dynamic-workflow primitive when available

When the dynamic-workflow primitive is available, the deterministic core — fan-out of reviewers, adversarial verification, and merge — SHALL run as a workflow whose intermediate findings live in the workflow rather than the conversation. The skill SHALL await the workflow's validated findings before any GitHub posting.

#### Scenario: workflow backend selected

- **WHEN** the dynamic-workflow primitive is available and `/idd-verify` runs
- **THEN** the fan-out, adversarial verify, and merge execute as a background workflow
- **AND** the skill awaits the workflow's validated findings array before posting any comment

### Requirement: Graceful degradation to manual fan-out with an identical findings contract

When the dynamic-workflow primitive is unavailable, `/idd-verify` SHALL fall back to a manual fan-out that produces findings of an identical contract — the same lenses, the same finding shape, and the same merge semantics — and SHALL emit a one-line notice naming the selected backend. Every step downstream of the core (posting, triage, verify-fix) SHALL be backend-agnostic.

#### Scenario: fallback when primitive unavailable

- **WHEN** the dynamic-workflow primitive is unavailable and `/idd-verify` runs
- **THEN** the manual fan-out runs and a one-line notice names the selected backend
- **AND** the findings shape, posting, and triage are identical to the workflow path

### Requirement: Cross-model verifier runs with a bounded lifetime

The cross-model verifier SHALL run with a bounded lifetime so that a hung run cannot block the ensemble — bounded by the workflow runtime when it runs as a workflow agent, or by a skill-level timeout otherwise. A run exceeding its bound SHALL be terminated and recorded in the master report as an incomplete cross-model pass, and SHALL NOT be silently dropped.

#### Scenario: cross-model run hangs

- **WHEN** the cross-model verifier exceeds its lifetime bound
- **THEN** it is terminated and the master report records the cross-model pass as incomplete (a process gap)
- **AND** the remaining ensemble findings are still merged and reported

### Requirement: Deterministic core executes under unattended interaction semantics

The deterministic core SHALL execute under unattended interaction semantics — no user input mid-core — consistent with the interaction axis defined in `idd-pr-hitl-modes`. All user-facing decisions (gates, follow-up triage, the verify-fix loop) SHALL occur in the skill before the core starts or after it returns, never inside it.

#### Scenario: no user input during the core

- **WHEN** the deterministic core is executing
- **THEN** no user prompt occurs during it
- **AND** any scope or triage decision is resolved by the skill before the core starts or after it returns its findings
