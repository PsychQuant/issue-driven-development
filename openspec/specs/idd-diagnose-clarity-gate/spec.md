# idd-diagnose-clarity-gate Specification

## Purpose

Define the `/idd-diagnose` Step 0.5 Clarity Surface PR Gate — the hard-refuse gate that enforces the third IDD quality axis (terminology / semantic accuracy) before diagnosis proceeds to Layer V vagueness scoring + complexity routing. The gate scans the target issue body for a `### Clarity Surface` annotation block (per `/idd-clarify` skill output schema) and REFUSES diagnosis when unresolved rows exist, mirroring the PR Gate Check precedent in `/idd-close` Step 1.5 and fail-fast discipline in `/idd-all-chain` #119.

v2.74.0+ #137 extends the gate with **reason-pattern accept**: `deferred` rows whose `reason` field matches the registry-cited literal `unattended-auto-Step-4.6-deferred` (from `plugins/issue-driven-dev/rules/append-vs-modify.md` § Reason pattern registry) are treated as PROCEED-with-warn instead of REFUSE, enabling unattended chains (`/loop`, `/idd-all` PR mode, `/idd-all-chain`) to continue without silent break. Non-matched `deferred` rows (legacy clarify-failed cases, manual defer with no reason or different reason) preserve the original REFUSE behavior for backward compatibility.

Sourced from #135 (initial hard-refuse baseline) + #137 (reason-pattern accept + legacy backward-compat preservation).

## Requirements

### Requirement: Gate SHALL refuse when surfaced rows exist

The Step 0.5 gate SHALL refuse diagnosis (exit non-zero) when the target issue body contains a `### Clarity Surface` block with one or more rows whose `Status` field equals `surfaced`. The refuse message SHALL identify the surfaced row count and provide actionable next steps (resolve via `/idd-clarify --status resolved=...`, dismiss via `--status dismissed=...`, or domain-expert consultation).

#### Scenario: Single surfaced row triggers refuse

- **WHEN** `/idd-diagnose #42` is invoked and #42 body contains 1 `surfaced` row
- **THEN** the gate SHALL exit non-zero with refuse message listing 1 surfaced row + actionable next steps

#### Scenario: Mixed surfaced and resolved triggers refuse

- **WHEN** body contains 1 `surfaced` row, 1 `resolved` row, 1 `dismissed` row
- **THEN** the gate SHALL refuse (surfaced count > 0); resolved + dismissed do not cancel the surfaced row

### Requirement: Gate SHALL refuse legacy deferred rows (no registry-cited reason)

The Step 0.5 gate SHALL refuse diagnosis when the target issue body contains a `### Clarity Surface` block with one or more `deferred` rows whose `Reason` field is absent, empty, or set to a literal NOT registered in `plugins/issue-driven-dev/rules/append-vs-modify.md` § Reason pattern registry. These represent legacy clarify-failed deferrals or manual defer actions that require human resolution before diagnosis proceeds.

#### Scenario: Deferred row with no Reason field (legacy schema)

- **WHEN** body contains 1 `deferred` row using the legacy 4-column schema (no Reason column)
- **THEN** the gate SHALL refuse with retry hint message

#### Scenario: Deferred row with non-registry reason

- **WHEN** body contains 1 `deferred` row with `Reason=clarify-failed-network` (not registered in the canonical registry)
- **THEN** the gate SHALL refuse, treating the row as legacy / manual defer

### Requirement: Gate SHALL proceed-with-warn for registry-cited unattended-auto deferred rows

The Step 0.5 gate SHALL accept (proceed with warn audit line) when the target issue body's `### Clarity Surface` block contains `deferred` rows whose `Reason` field matches the registry-cited literal `unattended-auto-Step-4.6-deferred` (per `plugins/issue-driven-dev/rules/append-vs-modify.md` § Reason pattern registry). The gate SHALL emit a warn audit line to stderr identifying the count of auto-deferred rows and noting that `/idd-all` Phase 4 final report will surface them for human review. The gate SHALL NOT refuse on these rows alone.

#### Scenario: Single auto-deferred row proceeds

- **WHEN** body contains 1 `deferred` row with `Reason=unattended-auto-Step-4.6-deferred` and no other unresolved rows
- **THEN** the gate SHALL proceed to Step 1 and SHALL emit a warn audit line such as `[Step 0.5] 1 row(s) auto-deferred under unattended mode (reason: unattended-auto-Step-4.6-deferred) — proceeding with warn`

#### Scenario: Mixed auto-deferred and surfaced refuses

- **WHEN** body contains 1 `deferred` row with `Reason=unattended-auto-Step-4.6-deferred` AND 1 `surfaced` row
- **THEN** the gate SHALL refuse (surfaced row blocks regardless of auto-deferred status); the refuse message SHALL distinguish surfaced vs auto-deferred vs legacy-deferred counts

#### Scenario: Mixed auto-deferred and legacy-deferred refuses

- **WHEN** body contains 1 `deferred` row with `Reason=unattended-auto-Step-4.6-deferred` AND 1 `deferred` row with no Reason field
- **THEN** the gate SHALL refuse (legacy-deferred row blocks); the refuse message SHALL distinguish auto-deferred count (proceed-eligible) from legacy-deferred count (blocking)

### Requirement: Reason regex SHALL be dot-escaped and anchored

The Step 0.5 gate SHALL match the registry-cited reason literal using a strict regex anchored at both ends with dot characters escaped: `^unattended-auto-Step-4\.6-deferred$`. Case-sensitive match. Sub-string matches or unanchored regex SHALL NOT trigger the proceed-with-warn behavior.

#### Scenario: Anchored regex rejects suffix variant

- **WHEN** body contains 1 `deferred` row with `Reason=unattended-auto-Step-4.6-deferred-extra` (extra suffix)
- **THEN** the gate SHALL NOT accept this as registry-cited (regex is anchored), and the row SHALL be classified as legacy-deferred → REFUSE

#### Scenario: Case-sensitive match

- **WHEN** body contains 1 `deferred` row with `Reason=Unattended-Auto-Step-4.6-Deferred` (capitalized variant)
- **THEN** the gate SHALL NOT accept (case-sensitive regex), and the row SHALL be classified as legacy-deferred → REFUSE

### Requirement: Gate SHALL proceed silently when block is absent (legacy backward-compat)

The Step 0.5 gate SHALL proceed to Step 1 when the target issue body contains no `### Clarity Surface` block (legacy issues filed before v2.71.0). The gate SHALL emit a single log line acknowledging the legacy pattern. The gate SHALL NOT refuse on missing block.

#### Scenario: Legacy issue with no block

- **WHEN** `/idd-diagnose #42` is invoked and #42 body has no `### Clarity Surface` block (filed before v2.71.0)
- **THEN** the gate SHALL log `[Step 0.5] no Clarity Surface block found (legacy issue — pre-v2.71.0). Proceeding to Step 1.` and proceed

### Requirement: Gate SHALL proceed when all rows are resolved / dismissed / passed

The Step 0.5 gate SHALL proceed to Step 1 when the target issue body contains a `### Clarity Surface` block whose rows are all in the `resolved`, `dismissed`, or `passed` status (no `surfaced` and no `deferred` rows of any kind). The gate SHALL proceed silently in this case (no warn line).

#### Scenario: All rows resolved

- **WHEN** body contains 3 rows all with `Status=resolved`
- **THEN** the gate SHALL proceed to Step 1 silently

#### Scenario: All rows passed (empty surface marker)

- **WHEN** body contains 1 row `(none) | — | no issues detected | passed`
- **THEN** the gate SHALL proceed to Step 1 silently (passed marker is explicit "scan ran, no issues found")

### Requirement: Unattended-auto contract SHALL align with /idd-clarify and /idd-all

The reason literal recognized by this gate SHALL match exactly the literal written by `/idd-clarify` Step 4.8.A (unattended-mode auto-defer) and the literal scanned by `/idd-all` Phase 6 final report's Action items surface. The literal SHALL be defined in `plugins/issue-driven-dev/rules/append-vs-modify.md` § Reason pattern registry as the single source of truth. Drift between the three citing sites (gate / writer / surface) constitutes a contract violation detectable by grep audit.

#### Scenario: Cross-site literal alignment grep check

- **WHEN** `grep -rc "unattended-auto-Step-4.6-deferred" plugins/issue-driven-dev/skills/` is executed and the registry contains the literal
- **THEN** at least three SKILL.md files (`idd-clarify`, `idd-diagnose`, `idd-all`) SHALL each contain at least one occurrence of the literal (citing the registry), and `plugins/issue-driven-dev/rules/append-vs-modify.md` SHALL contain exactly one occurrence (the registry source)
