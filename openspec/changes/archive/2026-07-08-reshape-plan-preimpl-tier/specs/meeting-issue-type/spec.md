## ADDED Requirements

### Requirement: meeting is a first-class issue type

The IDD issue-type taxonomy SHALL include `meeting` alongside `bug`, `feature`, `refactor`, and `docs`. `/idd-issue` SHALL accept `meeting` as a valid type value when creating an issue.

#### Scenario: idd-issue accepts the meeting type

- **WHEN** a user creates an issue and selects type `meeting`
- **THEN** `/idd-issue` records the type as `meeting` without falling back to `feature` or rejecting the value

### Requirement: Diagnose emits a deliberation Strategy for meeting issues

For an issue with `type=meeting`, `/idd-diagnose` SHALL emit a Phase A/B/C deliberation Strategy template (Phase A agenda, Phase B decision points, Phase C action items) instead of the code-centric Files & Changes Strategy. The `meeting` branch SHALL be evaluated FIRST in routing — before the Layer 1 disqualifier, before the Layer V vagueness pre-check (which SHALL short-circuit at Step 3.4 for `type=meeting`), before the Spectra (Layer 2+3) evaluation, before the complexity hard gate, and before Layer P — so a `meeting` issue SHALL NOT be assigned a `Simple`, `Plan`, or `Spectra` complexity verdict by any of them. Evaluating meeting first is required because a meeting's deliberation content would otherwise match the Layer 1 narrative disqualifier and be forced to `Simple`.

#### Scenario: meeting issue gets a Phase A/B/C Strategy

- **WHEN** `/idd-diagnose` runs on an issue with `type=meeting`
- **THEN** the emitted Strategy contains Phase A / Phase B / Phase C deliberation sections and contains no Files & Changes section

#### Scenario: meeting issue bypasses the complexity hard gate

- **WHEN** `/idd-diagnose` reaches Step 3.5 routing for an issue with `type=meeting`
- **THEN** the meeting branch is taken before complexity scoring, so none of Spectra (Layer 2+3), the hard gate, or Layer P assigns a `Simple` / `Plan` / `Spectra` verdict to the issue

#### Scenario: meeting issue skips the Layer V vagueness gate

- **WHEN** `/idd-diagnose` reaches Step 3.4 (Layer V) for an issue with `type=meeting` whose body would otherwise score V1/V4 ≥ 4
- **THEN** Step 3.4 short-circuits without scoring V1/V4 or raising the vagueness AskUserQuestion, and routing proceeds directly to the Step 3.5 meeting branch

### Requirement: Plan for meeting issues skips the implement chain

For an issue with `type=meeting`, `/idd-plan` SHALL produce a meeting-adapted Plan body and SHALL NOT chain to `/idd-implement`.

#### Scenario: meeting plan does not chain to implement

- **WHEN** `/idd-plan` completes for an issue with `type=meeting`
- **THEN** the Plan body uses the meeting-adapted schema and the skill does not invoke or prompt to invoke `/idd-implement`

### Requirement: Meeting closing maps decisions to actions without a TDD verify pass

Closing an issue with `type=meeting` SHALL use a decision-to-action mapping as the closing summary and SHALL NOT require an `/idd-verify` TDD verification pass. `/idd-close` SHALL gate a `type=meeting` issue with a **meeting-specific gate** — NOT the generic code-issue checklist gate / `authoritative_source` resolution. The meeting gate SHALL scan the authoritative meeting deliverable — the approved Meeting Plan's Phase C action items, falling back to the diagnose Strategy deliberation's Phase C when no plan stage ran (when both exist, only the Meeting Plan Phase C is scanned) — and each action item SHALL carry a disposition marker (`[x]` done / `[~]` tracked in a follow-up / `[-]` dropped). A bare undispositioned `- [ ]` action item SHALL block close.

#### Scenario: meeting close needs no TDD verify

- **WHEN** an issue with `type=meeting` is closed
- **THEN** the closing summary records each decision mapped to its follow-up action, and no `/idd-verify` TDD pass is required as a precondition of closing

#### Scenario: meeting gate blocks on an undispositioned Phase C action item

- **WHEN** a `type=meeting` issue with an approved Meeting Plan whose Phase C contains a bare `- [ ]` action item (no owner / no disposition) is closed
- **THEN** the meeting-specific gate blocks close until that item is marked `[x]`, `[~] — tracked in #NNN`, or `[-] — <reason>` (mirroring the generic checklist markers), and the generic `authoritative_source` resolution is not consulted for the meeting issue
