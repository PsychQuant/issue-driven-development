## ADDED Requirements

### Requirement: Privacy-scrubbing gate SHALL run before any GitHub issue egress

Every IDD skill that dispatches to GitHub via `gh issue create`, `gh issue comment`, or `gh issue edit` SHALL pass the drafted body through a repo-aware privacy-scrubbing gate BEFORE dispatch. The gate SHALL prevent local / private identifiers (absolute home paths, `~/.claude.json` project basenames, non-public collaborator real names, unpublished context) from leaking into public or third-party repos.

#### Scenario: draft with a home path in a third-party clone is gated

- **WHEN** an IDD skill is about to dispatch an issue body containing `/Users/alice/projects/foo` in a repo classified as third-party
- **THEN** the gate SHALL run before dispatch and classify the draft as containing a private identifier
- **AND** dispatch SHALL NOT proceed until the gate's outcome is resolved (see block-with-diff requirement)

#### Scenario: gate runs on all three egress verbs

- **WHEN** a skill invokes create, comment, or edit egress
- **THEN** the gate SHALL run for each of the three verbs
- **AND** no egress verb SHALL bypass the gate

### Requirement: Detection SHALL be LLM semantic self-review, not a fixed pattern set

The gate's detection mechanism SHALL be an LLM semantic self-review performed at egress time. The system SHALL NOT rely on a maintained regex denylist, keyword list, or NLP name-detector as the detection mechanism. Personal-name detection SHALL be handled by LLM semantic judgment (understanding from context who is private), NOT by fixed lists or name-detection libraries.

#### Scenario: detection uses semantic judgment over a drafted body

- **WHEN** the gate evaluates a drafted body
- **THEN** it SHALL instruct the AI to semantically inspect the body for private identifiers
- **AND** the classification of a token as private-or-not SHALL come from LLM judgment, not from matching against a maintained pattern set

#### Scenario: no maintained private-identifier pattern set is introduced

- **WHEN** the change is implemented
- **THEN** the codebase SHALL NOT contain a maintained denylist / regex catalogue / name-detector used as the primary detection mechanism for private identifiers
- **AND** personal-name detection SHALL be documented as LLM-semantic in `rules/privacy-scrubbing.md`

### Requirement: A single deterministic choke-point wrapper SHALL enforce that the gate ran

All GitHub issue egress SHALL route through a single choke-point wrapper `scripts/gh-egress.sh` instead of calling `gh issue create/comment/edit` directly. The wrapper SHALL deterministically enforce that the privacy self-review step was performed before dispatch (via a required attestation), and SHALL refuse to dispatch when that attestation is absent. The wrapper SHALL NOT perform semantic pattern matching.

#### Scenario: egress without self-check attestation is refused

- **WHEN** the wrapper is invoked to dispatch an egress action but the self-review attestation is absent
- **THEN** the wrapper SHALL refuse to dispatch
- **AND** SHALL surface that the privacy self-review step must run first

#### Scenario: wrapper is the single egress call site

- **WHEN** an IDD skill needs to create/comment/edit a GitHub issue
- **THEN** it SHALL call `bash scripts/gh-egress.sh <verb> …` rather than raw `gh issue <verb> …`
- **AND** the egress logic SHALL live in the wrapper alone (call sites are pure substitutions)

#### Scenario: wrapper does not do semantic detection

- **WHEN** a body contains a semantically-private identifier that is not one of the mechanical zero-tolerance items (e.g., an unpublished project name)
- **THEN** the wrapper itself SHALL NOT flag it (semantic breadth is the LLM self-review's job)
- **AND** the wrapper's only content inspection SHALL be the mechanical last-resort net

### Requirement: Wrapper mechanical net SHALL catch only 2-3 zero-tolerance literal items

As a last-resort safety net, the wrapper SHALL mechanically catch a small fixed set of zero-tolerance items only: literal absolute home paths of the form `/Users/<name>` and verbatim `~/.claude.json` file content. This net SHALL be a belt-and-suspenders backstop, NOT the detection mechanism, and SHALL NOT be expanded into a general semantic pattern set within this change.

#### Scenario: literal home path caught even if LLM misses it

- **WHEN** a drafted body contains the literal string `/Users/alice` and the LLM self-review did not flag it
- **THEN** the wrapper's mechanical net SHALL catch it before dispatch

#### Scenario: verbatim ~/.claude.json content caught

- **WHEN** a drafted body contains verbatim content copied from `~/.claude.json`
- **THEN** the wrapper's mechanical net SHALL catch it before dispatch

#### Scenario: net does not grow into semantic matching

- **WHEN** the mechanical net is implemented
- **THEN** it SHALL be limited to the literal home-path and `~/.claude.json` cases
- **AND** adding further semantic patterns SHALL require a separate change (not folded into this net)

### Requirement: Repo-visibility classification SHALL drive gate strictness across three levels

The gate SHALL classify the target repo's visibility and select strictness accordingly. Classification SHALL reuse the existing third-party detection (viewerPermission-based own-vs-third-party) and SHALL add a repo-visibility (`isPrivate`) query to the existing `gh repo view` call. The three levels SHALL be: third-party → ENFORCE, own-public → WARN, private → LIGHT.

#### Scenario: third-party repo triggers ENFORCE

- **WHEN** the target repo's `viewerPermission` is not one of WRITE / MAINTAIN / ADMIN (third-party, per #192 detection)
- **THEN** the gate SHALL operate at ENFORCE strictness (block-with-diff + require confirm)

#### Scenario: own public repo triggers WARN

- **WHEN** the user has write access AND `isPrivate` is `false`
- **THEN** the gate SHALL operate at WARN strictness (flag concerns, default proceed without blocking)

#### Scenario: private repo triggers LIGHT

- **WHEN** the target repo's `isPrivate` is `true`
- **THEN** the gate SHALL operate at LIGHT strictness (do not block ordinary identifiers)
- **AND** SHALL still honor the CLAUDE.md rule that raw third-party verbatim content does not go to remote

#### Scenario: isPrivate query folded into existing repo view

- **WHEN** the classification runs
- **THEN** `isPrivate` SHALL be requested within the existing `gh repo view --json` call that already fetches `isFork` and `viewerPermission`
- **AND** no additional GitHub API round-trip SHALL be introduced solely for visibility

### Requirement: ENFORCE SHALL block with a redaction diff, never silent auto-redact

At ENFORCE strictness, when the gate detects a private identifier it SHALL show a redaction diff (original vs suggested redaction) and refuse dispatch until the user confirms. The gate SHALL NOT silently modify (auto-redact) the body. This mirrors the existing `sanitize_source_label` (#75) refuse-not-strip philosophy.

#### Scenario: ENFORCE shows diff and blocks

- **WHEN** the gate at ENFORCE detects a private identifier
- **THEN** it SHALL display a redaction diff and refuse dispatch
- **AND** SHALL wait for explicit user confirmation before any dispatch

#### Scenario: no silent auto-redaction

- **WHEN** the gate detects a private identifier at any strictness level
- **THEN** it SHALL NOT silently rewrite the body and dispatch
- **AND** any redaction SHALL be surfaced to the user (diff at ENFORCE, flag at WARN) rather than applied invisibly

#### Scenario: user confirmation allows dispatch

- **WHEN** the user reviews the ENFORCE redaction diff and confirms
- **THEN** dispatch SHALL proceed with the confirmed body

### Requirement: Privacy-scrubbing contract SHALL live in a shared home separate from sanitize_source_label

The privacy-scrubbing policy SHALL be lifted out of skill-local text into a shared `rules/privacy-scrubbing.md` (sibling to `rules/tagging-collaborators.md`) plus the `scripts/gh-egress.sh` wrapper. The existing `sanitize_source_label` machinery SHALL remain unchanged and continue to handle its control-character / `@`-mention responsibilities; privacy scrubbing is a new semantic layer on top of it, not a replacement.

#### Scenario: policy rule exists as a sibling rule

- **WHEN** the change is implemented
- **THEN** `rules/privacy-scrubbing.md` SHALL exist alongside `rules/tagging-collaborators.md`
- **AND** SHALL define the three-level strictness, LLM self-review contract, and block-with-diff behavior

#### Scenario: sanitize_source_label is untouched

- **WHEN** the privacy-scrubbing gate is added
- **THEN** the `sanitize_source_label` function's behavior SHALL be byte-for-byte unchanged
- **AND** it SHALL continue to run its control-character strip and `@`-mention refuse for source labels

### Requirement: All egress sites SHALL be retrofitted to the wrapper, idd-issue first

The change SHALL retrofit all IDD egress sites (idd-issue, idd-comment, idd-edit, idd-diagnose, idd-implement, idd-plan, idd-update, idd-clarify, idd-close, idd-verify, idd-all-chain, and the multi-finding Stage 4 dispatch) to call `scripts/gh-egress.sh` instead of raw `gh issue …`. Implementation SHALL land `idd-issue` first (Phase 1); the remaining sites SHALL follow in Phase 2.

#### Scenario: idd-issue routes through the wrapper in Phase 1

- **WHEN** Phase 1 is implemented
- **THEN** every `gh issue create/comment/edit` call site inside `idd-issue` SHALL route through `bash scripts/gh-egress.sh …`
- **AND** idd-issue SHALL reference `rules/privacy-scrubbing.md` in its Step 0 task list

#### Scenario: remaining sites are covered by spec, retrofitted in Phase 2

- **WHEN** Phase 1 has landed
- **THEN** the remaining egress sites SHALL be retrofitted to the wrapper as Phase 2 follow-up
- **AND** each retrofit SHALL be a call-site substitution because the egress logic already lives in the wrapper
