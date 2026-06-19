# choice-first-decision-rendering Specification

## Purpose
TBD - created by archiving change add-choice-first-decision-doctrine. Update Purpose after archive.
## Requirements
### Requirement: IDD skills SHALL render enumerable decisions as candidate choices

At any decision or clarification point where an `idd-*` skill needs human input AND the option space is enumerable (the AI can produce 2+ plausible candidate answers), the skill SHALL present the options via `AskUserQuestion` — a concrete candidate list with a recommended option first — rather than asking the human to articulate the answer in free-text.

Free-text prompting is a **named-exception fallback**, permitted ONLY when the option space is genuinely open (the AI cannot enumerate plausible candidates). When falling back to free-text, the skill SHALL state the reason the space is not enumerable.

This doctrine is the normative generalization of the NSQL Confirmation Protocol's "Read-Only for Humans" principle (the human selects; the AI writes). It is cross-skill: it applies wherever an `idd-*` skill surfaces a decision to a human, not only within a single skill's vagueness check.

**Scope boundary**: this requirement governs **decision / clarification points** only. It does NOT govern pure informational notices, progress reports, or status output (those are not decisions and need no choices).

#### Scenario: Enumerable decision renders choices

- **WHEN** an `idd-*` skill reaches a decision point that needs human input AND the AI can enumerate 2+ plausible candidate answers
- **THEN** the skill SHALL invoke `AskUserQuestion` with those candidates, recommended option first
- **AND** the skill SHALL NOT instead ask the human to articulate the answer in free-text

#### Scenario: Genuinely-open decision falls back to free-text with a named reason

- **WHEN** a decision point's option space is genuinely open (the AI cannot produce plausible candidates to enumerate)
- **THEN** the skill MAY ask the human in free-text
- **AND** the skill SHALL state the reason the space could not be enumerated (named exception, not a silent default)

#### Scenario: Pure informational output is out of scope

- **WHEN** a skill emits a notice, progress line, or status report that requires no human decision
- **THEN** this requirement does NOT apply (no choices are rendered)

#### Scenario: Unattended mode auto-proceeds without blocking

- **WHEN** a skill runs under unattended mode (no human present, e.g. `/idd-all --pr`, `/loop`; signalled to sub-skills via the `UNATTENDED MODE` directive)
- **THEN** the skill SHALL NOT block on `AskUserQuestion`
- **AND** the skill SHALL apply a safe non-blocking default per its existing unattended convention — the conservative proceed-style option that does not itself require a human, which is NOT necessarily the human-facing recommended option — and record the auto-decision in the audit trail, mirroring idd-diagnose Layer V's `proceed anyway` default

#### Scenario: idd-diagnose Layer V D.1 is an instance of this doctrine

- **WHEN** `idd-diagnose` Step 3.4 Layer V `clarify now` renders candidate interpretations for an unclear point
- **THEN** that behavior SHALL be defined as an application of this doctrine to the vagueness-clarification context
- **AND** the doctrine SHALL be the single source of truth (Layer V D.1 references it rather than re-specifying the choice-vs-free-text rule)

#### Scenario: idd-diagnose stakeholder-decision surfacing renders choices

- **WHEN** `idd-diagnose` Step 4 (confirm + routing) surfaces stakeholder decisions to the human (e.g. an aggregate report listing decisions that need a human to pick a direction) AND those decisions are enumerable
- **THEN** the skill SHALL render them via `AskUserQuestion` rather than listing them in prose for the human to articulate a response to

