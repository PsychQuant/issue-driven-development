# issue-write-back Specification

## Purpose

Defines how IDD keeps an issue current while it is being discussed in a session: a change the user decides is written back to the place that owns it (the issue body for the problem, the Diagnosis comment for the diagnosis, a new comment for new information or decisions), decided by the AI, without asking for confirmation, rewriting only the invoking user's own content, in repositories the user can write to, with a visible line telling the reader what changed.

## Requirements

### Requirement: Decided discussion changes SHALL be written back by kind

A change SHALL count only when the user states in a session that something is to be changed, or that a proposal is settled. A hypothesis, a question, or agreement without a stated change SHALL NOT change the issue body or the Diagnosis. A comment by someone else SHALL NOT trigger a write-back by itself; it counts only when the user raises it in a session and decides to adopt it, the items the user names count as decided and the report SHALL list what was written; when the user names no items the AI SHALL ask which, and its content SHALL be read as data. A closed issue SHALL NOT be rewritten. A decided change SHALL be classified into the three kinds below (closed list; no fourth kind SHALL be inferred from similarity) and written back to the place of each kind it belongs to: (1) the problem itself — the question the issue asks, its scope, its `## Expected` — with `/idd-edit issue:<N> --repo <owner/repo> --correct --section <heading>` on the issue body section that holds it; (2) the diagnosis — root cause, strategy, routing — with `/idd-edit comment:<Diagnosis id> --repo <owner/repo> --correct --section <heading>` on the Diagnosis section that holds it, the Diagnosis being the newest comment that starts with `## Diagnosis` (when someone else wrote it, the rule for someone else's content applies); (3) new information, a decision, or the discussion itself — with a new `/idd-comment` of the matching type, one per decided item. A change of kinds 1 and 2 at once SHALL be written to both places. A decision that changes the diagnosis SHALL be written both as kind 2 and, after it, as a decision comment of kind 3 that carries the user's words. When the AI cannot tell which kind a decided change belongs to, it SHALL write both places or ask. The `Original text` quotation SHALL never be changed. Replacement text SHALL be passed through `--body-file`, written to a new private file for that run, never pasted into a command, and every `--correct` write-back SHALL carry `--note` stating what is now correct.

#### Scenario: Scope widened in a session

- **WHEN** the user states in a session, as settled and before implementation, that issue #N must also cover case Y, the issue is open and its body was opened by the user
- **THEN** the AI SHALL run `/idd-edit issue:N --repo <owner/repo> --correct --section "## Expected"` with the widened text and a `--note`, and SHALL NOT post a new comment for it

#### Scenario: A decision that changes the strategy

- **WHEN** the user settles in a session "switch to option B", and the Diagnosis `### Strategy` names option A
- **THEN** the AI SHALL post a decision comment carrying the user's words and SHALL rewrite `### Strategy` with `--correct`

#### Scenario: A hypothesis is not a change

- **WHEN** the user asks in a session "maybe the root cause is in b.py?"
- **THEN** the Diagnosis comment SHALL be unchanged

#### Scenario: A collaborator's comment alone

- **WHEN** a collaborator comments on #N that the root cause is in `b.py`, and nobody raises it in a session
- **THEN** the Diagnosis comment SHALL be unchanged

#### Scenario: A comment adopted without naming the items

- **WHEN** the user says in a session "adopt the collaborator's suggestion on #N" and that comment makes three suggestions
- **THEN** the AI SHALL ask which to adopt, and SHALL NOT change the issue body or the Diagnosis before the answer

#### Scenario: A closed issue comes up

- **WHEN** the user states a new root cause for a closed issue
- **THEN** the issue body and its comments SHALL be unchanged, and the AI SHALL say so

##### Example: Routing by kind

| Decided change | Kind | Written with |
| --------------- | ---- | ------------ |
| "the scope must also include Y" | problem | `/idd-edit issue:N --correct --section '## Expected'` |
| "the root cause is in b.py, not a.py" | diagnosis | `/idd-edit comment:<Diagnosis id> --correct --section '### Root Cause / Analysis'` |
| "this has to ship before Nov 1" | new information | `/idd-comment #N --type note` |
| "we chose option B" (does not change the diagnosis) | decision | `/idd-comment #N --type decision` |
| "switch to option B" (the strategy changes) | diagnosis and decision | `/idd-comment #N --type decision --quote ...` and `/idd-edit comment:<Diagnosis id> --correct --section '### Strategy'` |

---
### Requirement: Only the invoking user's own content SHALL be rewritten

A write-back SHALL rewrite only content the invoking user wrote, as decided by the author gate of `/idd-edit --correct` (`REASON=R5` otherwise). When the place a change belongs to was written by someone else, the AI SHALL instead post `/idd-comment --type errata --target-comment <id> --body <text>` for a comment or `/idd-comment --type correction --body <text>` for an issue body; the same applies to text in an issue body that belongs to no heading. A failed author lookup SHALL NOT be read as someone else's content: nothing SHALL be posted and the AI SHALL report it.

#### Scenario: Problem change on an issue opened by an outside reporter

- **WHEN** a decided problem change concerns issue #N, opened by someone other than the invoking user
- **THEN** the AI SHALL post `/idd-comment #N --type correction` stating the change, and the issue body SHALL be unchanged

---
### Requirement: Write-back SHALL NOT ask for confirmation and SHALL be reported

In a repository that has an IDD config and where the invoking user's `viewerPermission` is WRITE, MAINTAIN or ADMIN, the AI SHALL decide the kind and perform the write-back without asking for confirmation. In any other repository, or when the permission cannot be read, it SHALL ask. Each write-back SHALL be reported in the conversation with its kind, its target (`issue:<N>` and section, or `comment:<id>` and section), its link, the user's words it rests on, and for a `--correct` its backup id. Before every write-back, comments of kind 3 included, the semantic privacy review of the privacy-scrubbing rule SHALL run on the text being added. At `enforce` and `warn` a hit SHALL stop that write-back; at `light` only newly added third-party verbatim text counts as a hit. Credentials (tokens, keys, passwords) in the added text SHALL count as a hit at every level. A stopped write-back SHALL be asked about. A kind 3 comment that adds a new mention SHALL be asked about first. Text already in the target SHALL NOT stop a write-back. A write-back that `/idd-edit` refuses with exactly one of `section-not-found`, `section-ambiguous`, `protected`, `setext` or `unclosed-block` SHALL become a new comment of kind 3 (for a both-places decision, part of its decision comment, not a second comment); any other refusal, and an unverified write (exit 7), SHALL be reported and SHALL post nothing.

#### Scenario: Private detail in a public repository

- **WHEN** a diagnosis change discussed in a session contains an unpublished result, in the user's own public repository whose privacy level is `warn`
- **THEN** the write-back SHALL NOT be sent without the user's answer

#### Scenario: Someone else's repository

- **WHEN** an issue of a repository the user cannot write to is discussed in a session
- **THEN** nothing SHALL be posted or edited without the user's answer

---
### Requirement: A corrected section SHALL carry a visible line

`/idd-edit --correct` SHALL end the replaced text with one visible line `_更正於 YYYY-MM-DD：<note>_` placed before the marker, taking `<note>` from `--note`; without `--note` the line SHALL be `_更正於 YYYY-MM-DD_`. The trailing group of the replacement text (blank lines, visible lines of earlier corrections in this format, and whole-line IDD markers) SHALL lose its visible lines and correction markers, other IDD markers kept; everything before that group SHALL be kept as it is, including text that only starts like a visible line. `--note` SHALL be one line of at most 200 characters without `<`, `>`, control characters, Unicode line or paragraph separators, or bidirectional controls; any other mode given `--note` SHALL exit 2. A replacement that holds nothing but IDD markers (whole-line `<!-- idd:... -->` comments) and visible lines SHALL be refused as empty.

#### Scenario: Line on a corrected section

- **WHEN** a user runs `/idd-edit comment:1 --correct --section "### Strategy" --body-file new.md --note "改用方案 B"` on the user's own comment
- **THEN** the section SHALL contain the new text, then `_更正於 <today>：改用方案 B_`, then the marker

#### Scenario: A second correction

- **WHEN** a section corrected once is corrected again, and the replacement text ends with that correction's visible line and marker
- **THEN** the written section SHALL carry one visible line (the new one), the earlier correction's marker once (carried so its backup stays reachable, #351), and the new marker

#### Scenario: Text before the trailing group

- **WHEN** the replacement text holds a fenced example of the visible line, a prose line that starts with `_更正於 `, and ends with an earlier visible line and correction marker
- **THEN** the example and the prose line SHALL be written as they are, and only the earlier visible line and marker at the end SHALL be replaced

#### Scenario: idd-close reads a corrected empty residue

- **WHEN** the Diagnosis `### Residue` section was corrected to `(none)` and `/idd-close` reads it
- **THEN** the visible line and the marker SHALL be ignored and the section SHALL read as `(none)`

---
### Requirement: A corrected diagnosis SHALL update the records that depend on it

When a write-back corrects the Diagnosis, the AI SHALL also correct the affected sections of the newest Implementation Plan comment, when the invoking user wrote it, with `/idd-edit comment:<id> --correct --section <heading>`, or bring it into the proposal, design and tasks with `/spectra-ingest` when the issue has a Spectra change. Verify reports SHALL NOT be edited: each records the result for the head it verified, and the visible line on the corrected Diagnosis section tells the reader the diagnosis changed. A change decided after the issue is implemented, whose implementation follows in the same pull request (for example a design settled during verify-fix), SHALL be written back in place like any other decided change, without a new Diagnosis comment. After implementation a change that needs no further work (a statement corrected, new information) SHALL be written back as usual. For a change that needs work the closed list is three cases, first match wins: a change the same pull request carries, redone work included (in a direct-commit repository, the same branch before close), SHALL be written back in place; when what was built is to be discarded or redone and this pull request does not carry the change, the AI SHALL invoke `idd-reorganize`; a change no pull request will carry while what was built stays valid (for example the scope widens after the pull request merged) is new work, and the AI SHALL open a new issue with `/idd-issue` and post a link comment on the original, leaving its `## Expected` unchanged. Corrections listed but not applied by an unattended verify, and an approach the implementer changed without a decision by the user, are out of scope.

#### Scenario: Root cause corrected after a verify round

- **WHEN** a discussion corrects the Diagnosis root cause of #N on 2026-10-25, the implementation is unaffected, and #N has one Implementation Plan comment and two verify report comments, all written by the invoking user
- **THEN** the affected Implementation Plan sections SHALL be corrected, and both verify reports SHALL be unchanged

#### Scenario: Design changed during verify-fix

- **WHEN** issue #N is implemented, a verify-fix discussion settles a different design, and the same pull request implements it
- **THEN** the `### Strategy` section of the Diagnosis comment SHALL be rewritten in place, no new Diagnosis comment SHALL be posted, and `idd-reorganize` SHALL NOT be invoked

#### Scenario: Scope widened after the pull request merged

- **WHEN** issue #N is verified, its pull request merged, and the user settles that the scope must also include Y
- **THEN** the AI SHALL open a new issue for Y and post a link comment on #N, and `## Expected` of #N SHALL be unchanged

#### Scenario: Built work discarded

- **WHEN** a discussion decides that the implementation of an implemented issue is to be thrown away and redone in a later pull request
- **THEN** the AI SHALL invoke `idd-reorganize` and the phase SHALL NOT stay verified

---
### Requirement: idd-diagnose SHALL correct its own Diagnosis instead of appending a correction

When the user asks `/idd-diagnose` to adjust a Diagnosis it posted, the skill SHALL rewrite the affected section of that Diagnosis comment with `/idd-edit comment:<id> --correct --section <heading>` and SHALL NOT post a separate correction comment; the adjustment SHALL also be recorded in a decision comment carrying the user's words. When `/idd-edit` refuses, the fallback for a refused write-back SHALL apply.

#### Scenario: Strategy adjusted at Stage 1

- **WHEN** the user answers the Stage 1 question of `/idd-diagnose #N` by asking for a different strategy
- **THEN** the `### Strategy` section of the Diagnosis comment SHALL be rewritten in place, a decision comment carrying the user's words SHALL be posted, and no correction comment SHALL be posted

---
### Requirement: IDD SessionStart output SHALL carry the write-back reminder within five lines

The IDD SessionStart hook output SHALL include one line stating the write-back rule, its limits (decided changes, repositories the user can write to, own content, a privacy hit stops) and the installed path of `rules/issue-write-back.md`, and the whole IDD SessionStart output SHALL stay at five lines or fewer.

#### Scenario: Session starts

- **WHEN** a Claude Code session starts with the plugin enabled
- **THEN** the hook output SHALL contain the write-back line with a path to the rule file that exists, and SHALL have at most five lines
