# idd-ic-r011-checkpoint Specification

## Purpose

Defines the **IC_R011 follow-up filing checkpoint** — the cross-skill discipline for how IDD skills handle sister concerns and tangential follow-ups surfaced mid-work. Specifies that SHALL-tier sites (`idd-diagnose` Step 3.6, `idd-plan` Step 2.5, `idd-implement` Step 5.7, `idd-issue` Step 4.7, `idd-verify` Step 5b) **file surfaced candidates by default** rather than asking; the 3-category skip taxonomy required to opt out; the rule that the canonical reference holds the normative procedure body while individual SKILL.md files cite (not duplicate) it; escape-hatch semantics that preserve names but shift to the new file-by-default behavior; the unattended-mode fall-back to implicit skip with an audit trail; and the issue-body `Source` footer that identifies the surfacing skill and step.

## Requirements

### Requirement: SHALL-tier sites SHALL default to filing surfaced candidates, not asking

When an IC_R011 follow-up filing checkpoint fires on a SHALL-tier site (`idd-diagnose` Step 3.6, `idd-plan` Step 2.5, `idd-implement` Step 5.7, `idd-issue` Step 4.7, or `idd-verify` Step 5b), the skill SHALL file each surfaced candidate via `gh issue create` by default, without first asking the user via `AskUserQuestion` whether to file. The skill SHALL produce an audit trail PATCH on the originating comment listing the filed issue numbers (`Filed: #NNN, #MMM, ...`) or the literal string `(none surfaced)` when the candidate list is empty.

#### Scenario: idd-diagnose surfaces 3 sister concerns

- **WHEN** `/idd-diagnose` Step 3.6 surfaces 3 candidate sister concerns from the just-posted Diagnosis content
- **THEN** the skill MUST call `gh issue create` 3 times in sequence, each producing a separate issue with the canonical body footer `**Source**: surfaced during /idd-diagnose #N sister concern surfacing (Step 3.6)`, and MUST PATCH the Diagnosis comment with an audit-trail block `### Sister Concerns Filed (mid-diagnose, v2.47.0+ #528)` listing the 3 filed issue numbers

##### Example: filed audit trail entry

- **GIVEN** 3 surfaced candidates with proposed titles `[bug] X`, `[refactor] Y`, `[docs] Z`
- **WHEN** the skill executes the default file path
- **THEN** the audit trail block contains exactly the text `Filed: #NNN, #MMM, #PPP` (with the 3 newly created issue numbers in creation order)

#### Scenario: empty candidate list

- **WHEN** an IC_R011 checkpoint fires on a SHALL-tier site and the candidate list is empty
- **THEN** the skill MUST skip the `gh issue create` loop entirely and PATCH the audit-trail block with the literal string `(none surfaced)`


<!-- @trace
source: idd-ic-r011-default-file
updated: 2026-05-25
code:
  - .agents/skills/spectra-archive/SKILL.md
-->

---
### Requirement: Skip path SHALL require explicit 3-category taxonomy disambiguation

When the user requests to skip filing one or more candidates (via explicit user prompt, env var bypass, or `# Disable IC_R011` flag), the skill SHALL present a second-level `AskUserQuestion` for each skip-candidate forcing selection among three categories: `(a) unactionable observation`, `(b) infeasible but understood`, or `(c) blocked on external state`. Selecting `(a)` SHALL skip filing and record `Skipped: (a) unactionable observation` in the audit trail. Selecting `(b)` or `(c)` SHALL still file the candidate via `gh issue create` with an added repository label of `blocker:infeasible` or `blocker:waiting` respectively, and SHALL record `Skipped: (b) infeasible — filed as #NNN with blocker:infeasible label` (or the `(c)` equivalent).

#### Scenario: user skips one of three candidates with category (a)

- **WHEN** the user invokes skip for 1 out of 3 surfaced candidates and selects `(a) unactionable observation` from the second-level picker
- **THEN** the skill MUST file the other 2 candidates via `gh issue create` AND MUST NOT file the skipped candidate AND MUST record the skip reason in the audit trail with the literal string `Skipped: (a) unactionable observation`

#### Scenario: user skips with category (b)

- **WHEN** the user selects `(b) infeasible but understood` for a candidate
- **THEN** the skill MUST still call `gh issue create` for that candidate AND MUST attach the label `blocker:infeasible` via the `--label` flag AND MUST record `Skipped: (b) infeasible — filed as #<newly-created-number> with blocker:infeasible label` in the audit trail

##### Example: skip-and-file audit trail entries

- **GIVEN** 3 candidates [X, Y, Z], user skips Z with category (c)
- **WHEN** the skill executes
- **THEN** the audit trail contains both `Filed: #X-num, #Y-num` and `Skipped: (c) blocked-on-external — filed as #Z-num with blocker:waiting label`


<!-- @trace
source: idd-ic-r011-default-file
updated: 2026-05-25
code:
  - .agents/skills/spectra-archive/SKILL.md
-->

---
### Requirement: idd-close Step 3.5 SHALL preserve 3-option ask behavior unchanged

The `idd-close` Step 3.5 closing-summary follow-up keyword scan SHALL retain its existing SHOULD-tier behavior using the legacy 3-option `AskUserQuestion` (`[file all]` / `[file selected]` / `[skip]`) without translating to the new file-by-default semantics. Audit trail wording MAY be normalized for consistency with other sites, but the structural choice surface MUST remain the 3-option ask.

#### Scenario: idd-close skips file-by-default translation

- **WHEN** `/idd-close` Step 3.5 surfaces follow-up keyword matches in a closing summary
- **THEN** the skill MUST present the legacy 3-option `AskUserQuestion` ([file all] / [file selected] / [skip]) AND MUST NOT enter the file-by-default path used by SHALL-tier sites


<!-- @trace
source: idd-ic-r011-default-file
updated: 2026-05-25
code:
  - .agents/skills/spectra-archive/SKILL.md
-->

---
### Requirement: Canonical reference SHALL hold the normative procedure body; skill SKILL.md files SHALL cite, not duplicate

The canonical reference at `plugins/issue-driven-dev/references/ic-r011-checkpoint.md` SHALL contain the full normative IC_R011 procedure body (default behavior, 3-category skip taxonomy, escape hatch semantics, audit trail format, failure modes). Each of the 6 implementing skill SKILL.md files (`idd-diagnose` 3.6, `idd-plan` 2.5, `idd-implement` 5.7, `idd-issue` 4.7, `idd-verify` 5b, `idd-close` 3.5) SHALL cite the canonical reference via the literal text fragment `per IC_R011` and a markdown link to the reference, followed only by per-step deviation text. Inline duplication of the procedure body in SKILL.md files SHALL NOT be permitted.

#### Scenario: skill SKILL.md files lose inline procedure duplication

- **WHEN** a maintainer greps `grep -L 'per IC_R011' plugins/issue-driven-dev/skills/idd-{diagnose,plan,implement,issue,verify,close}/SKILL.md`
- **THEN** the command MUST return an empty result (all 6 skill files contain the cite phrase)

#### Scenario: procedure-body changes propagate from canonical reference

- **WHEN** a maintainer edits only the canonical reference at `plugins/issue-driven-dev/references/ic-r011-checkpoint.md` to clarify a procedure step
- **THEN** the change MUST take effect across all 6 implementing skill sites without requiring edits to the 6 SKILL.md files


<!-- @trace
source: idd-ic-r011-default-file
updated: 2026-05-25
code:
  - .agents/skills/spectra-archive/SKILL.md
-->

---
### Requirement: Existing escape hatches SHALL preserve names but shift to new semantics

The environment variable `AI_LOW_BAR_ISSUE_FILING=false` and the repository `CLAUDE.md` flag `# Disable IC_R011` SHALL retain their existing names but SHALL shift semantically from "silently skip checkpoint" to "revert to pre-default-flip 3-option ask behavior". A user setting either escape hatch SHALL receive the legacy 3-option `AskUserQuestion` interface at SHALL-tier sites in place of the new file-by-default flow. No new environment variable or flag SHALL be introduced for this change.

#### Scenario: env var bypass reverts to legacy ask

- **WHEN** `AI_LOW_BAR_ISSUE_FILING=false` is set AND an IC_R011 checkpoint fires on a SHALL-tier site with 2 candidates surfaced
- **THEN** the skill MUST present the legacy 3-option `AskUserQuestion` ([file all] / [file selected] / [skip]) AND MUST NOT auto-file via the new default

#### Scenario: repo flag bypass reverts to legacy ask

- **WHEN** the repository `CLAUDE.md` contains the literal flag string `# Disable IC_R011` AND an IC_R011 checkpoint fires on a SHALL-tier site
- **THEN** the skill MUST behave identically to the env var bypass case above


<!-- @trace
source: idd-ic-r011-default-file
updated: 2026-05-25
code:
  - .agents/skills/spectra-archive/SKILL.md
-->

---
### Requirement: Unattended mode SHALL fall back to implicit (a) skip with audit trail

When the skill detects unattended mode (no TTY via `[ ! -t 0 ]` or env var `IDD_ALL_UNATTENDED=1`) AND the user has also set `AI_LOW_BAR_ISSUE_FILING=false` (which would normally revert to the legacy ask path), the skill SHALL NOT block on `AskUserQuestion`. Instead it SHALL apply implicit `(a) unactionable observation` skip semantics to all candidates and record the bypass reason in the audit trail using the literal string `Skipped (unattended mode + AI_LOW_BAR_ISSUE_FILING=false → implicit (a) skip)`.

#### Scenario: unattended CI run with env var bypass

- **WHEN** `IDD_ALL_UNATTENDED=1` and `AI_LOW_BAR_ISSUE_FILING=false` are both set AND an IC_R011 checkpoint fires with 3 candidates
- **THEN** the skill MUST NOT call `AskUserQuestion` AND MUST NOT call `gh issue create` AND MUST PATCH the audit trail with the literal string `Skipped (unattended mode + AI_LOW_BAR_ISSUE_FILING=false → implicit (a) skip)`

#### Scenario: unattended without env var bypass uses default file path

- **WHEN** `IDD_ALL_UNATTENDED=1` is set but `AI_LOW_BAR_ISSUE_FILING` is unset (or set to anything other than `false`)
- **THEN** the skill MUST execute the new file-by-default path (auto-file all candidates) since the new default is itself non-blocking


<!-- @trace
source: idd-ic-r011-default-file
updated: 2026-05-25
code:
  - .agents/skills/spectra-archive/SKILL.md
-->

---
### Requirement: Issue body `Source` footer SHALL identify the surfacing skill and step

Each candidate issue created via the IC_R011 file-by-default path or the (b)/(c) auto-file path SHALL include in its body a footer line containing the literal text `**Source**: surfaced during /<skill-name> #<source-issue-or-pr> <description> (Step <N.M>)`. This footer SHALL be present on issues created from any of the 6 IC_R011 checkpoint sites.

#### Scenario: footer text on a diagnose-surfaced issue

- **WHEN** `/idd-diagnose` Step 3.6 files a sister concern from issue #100
- **THEN** the newly created issue body MUST contain a line matching the literal text `**Source**: surfaced during /idd-diagnose #100 sister concern surfacing (Step 3.6)`

#### Scenario: footer text on an implement-surfaced issue

- **WHEN** `/idd-implement` Step 5.7 files a sister bug from issue #100
- **THEN** the newly created issue body MUST contain a line matching the literal text `**Source**: surfaced during /idd-implement #100 reproduction (Step 5.7)`

<!-- @trace
source: idd-ic-r011-default-file
updated: 2026-05-25
code:
  - .agents/skills/spectra-archive/SKILL.md
-->