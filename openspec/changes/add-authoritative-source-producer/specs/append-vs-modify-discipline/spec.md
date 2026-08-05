## MODIFIED Requirements

### Requirement: Gate logic SHALL resolve authoritative source

Gate sites that check checklist completeness SHALL resolve an `authoritative_source` by the following priority order: (1) `## Implementation Complete > ### Checklist`, (2) `## Current Status > ### Tasks`, (3) `## Todo` / `## Tasks` / `## Checklist` top-level headings. When an authoritative source resolves, the gate SHALL only evaluate items in that source and SHALL treat earlier sources (Strategy, Implementation Plan) as superseded snapshots not subject to gate evaluation.

A candidate SHALL resolve only when its heading is present **and** it contains at least one parsable checklist item. A heading with zero items SHALL be treated as absent, and resolution SHALL continue to the next candidate. This definition SHALL apply identically at every consumer; a consumer SHALL NOT define its own emptiness rule.

The participants in this resolution SHALL be described by role rather than as a uniform set of gate sites. Exactly one participant produces the first candidate (`idd-implement` Step 5a, Checklist Sync); three participants consume the resolution (`idd-close` Step 0, `idd-verify` checklist scan, `idd-update` body sync). A producer does not evaluate the resolution and SHALL NOT be counted among the consumers.

Every candidate in the priority order SHALL have a named producer. A candidate that no tool produces cannot resolve in practice, which silently collapses the priority order to its remaining layers.

#### Scenario: Implementation Complete checklist supersedes Strategy

- **WHEN** an issue body contains both `## Strategy` (with unchecked items) and `## Implementation Complete > ### Checklist` (with all items checked)
- **THEN** the gate SHALL evaluate only the `## Implementation Complete > ### Checklist` and SHALL pass (Strategy is superseded snapshot)

#### Scenario: Multiple authoritative source candidates with different priorities

- **WHEN** an issue body contains both `## Current Status > ### Tasks` and `## Implementation Complete > ### Checklist`
- **THEN** the gate SHALL choose `## Implementation Complete > ### Checklist` per priority order, ignoring `## Current Status > ### Tasks`

#### Scenario: A candidate heading exists but carries no items

- **WHEN** an issue body contains a `## Current Status > ### Tasks` heading with no checklist items beneath it, and no higher-priority candidate
- **THEN** that candidate SHALL NOT resolve
- **AND** resolution SHALL continue to the next candidate, falling back to scanning all checklist-bearing sections if none resolves

##### Example: Emptiness is decided by item count, not heading presence

| Candidate state | Resolves? |
| --- | --- |
| heading absent | no |
| heading present, 0 items | no |
| heading present, 1 unchecked item | yes |
| heading present, 3 checked items | yes |

## ADDED Requirements

### Requirement: A checklist file outside the current work tree SHALL be refused as a task source

A tool that accepts an external checklist file as the source for `## Current Status > ### Tasks` SHALL resolve the given path to an absolute path and SHALL refuse it when it does not lie within the top level of the current work tree.

Refusal SHALL report both the given path and the resolved top level. Reporting only the refusal leaves the operator unable to tell a misconfiguration from a genuine boundary violation.

Refusal SHALL NOT abort the surrounding operation; the tool SHALL continue without emitting the section, which restores the behaviour that applied before any external source was offered.

The hazard this guards against is not hypothetical. A checklist path obtained by querying an external tool has been observed to point into a sibling work tree of the same repository, because that tool's registry is not scoped to the working directory. Consuming such a path makes a gate report the completion state of unrelated work.

The failure direction is what makes this mandatory rather than defensive: a gate reading a foreign checklist that happens to be complete admits work that is not finished. An over-strict gate is noticed and complained about; an over-permissive one is not.

#### Scenario: The checklist path points into a sibling work tree

- **WHEN** a checklist path resolves outside the top level of the current work tree
- **THEN** the source SHALL be refused
- **AND** the message SHALL name both the given path and the current top level
- **AND** no `### Tasks` section SHALL be emitted
- **AND** the surrounding operation SHALL continue

#### Scenario: The checklist path lies within the current work tree

- **WHEN** a checklist path resolves within the top level of the current work tree and contains at least one checklist item
- **THEN** the source SHALL be accepted
- **AND** a `### Tasks` section SHALL be emitted carrying that file's checklist items

#### Scenario: No checklist file is offered

- **WHEN** no external checklist file is given
- **THEN** no `### Tasks` section SHALL be emitted
- **AND** all other behaviour SHALL be unchanged

#### Scenario: The offered file carries no items

- **WHEN** an accepted checklist file contains zero parsable checklist items
- **THEN** no `### Tasks` section SHALL be emitted, because a section that cannot resolve is noise rather than information

### Requirement: The layout of an external checklist source SHALL NOT be hardcoded

A tool that consumes an external checklist SHALL receive a path. It SHALL NOT construct that path from a change identifier plus a directory convention, and SHALL NOT contain the external tool's directory names.

The path SHALL be obtained by querying the external tool for it. Constructing the path relocates knowledge of the external layout rather than removing it, and a layout change would then fail silently.

Knowledge of which external tool to query MAY reside in an orchestrator that already invokes that tool by name. It SHALL NOT reside in a general-purpose component used on paths that do not involve the external tool at all.

#### Scenario: A layout change in the external tool

- **WHEN** the external tool changes where it stores its checklist files
- **THEN** the consuming tool SHALL be unaffected, because it received a path rather than derived one

#### Scenario: Selecting among several candidate sources

- **WHEN** the external tool reports several in-progress units of work
- **THEN** the path SHALL NOT be inferred by assuming exactly one is active

##### Example: Why inference by uniqueness was rejected

- **GIVEN** a repository whose external tool reports six units of work in progress at once
- **WHEN** a rule of "take the only active one" is applied
- **THEN** it selects arbitrarily among six, and the resulting checklist describes unrelated work
