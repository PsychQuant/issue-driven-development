# idd-clarify Specification

## Purpose

Define the `/idd-clarify` skill — the composable primitive that scans an existing GitHub issue body for terminology / ambiguity / missing-context gaps and emits a `### Clarity Surface` annotation block. The skill is the third IDD quality axis (terminology / semantic accuracy alongside IC_R007 verbatim source preservation and IC_R010 confidence-tagged routing). Standalone primitive — also delegated by `/idd-issue` Step 4.6 (mandatory auto-invoke on issue creation) and gated by `/idd-diagnose` Step 0.5 (hard refuse + reason-pattern accept for unattended-auto-deferred rows per #137 v2.74.0+).

Two invocation modes: **scan mode** (no `--status` flag — emits annotation block) and **update mode** (`--status resolved|dismissed=<idx>,<reason>` — mutates a single row's status enum). v2.74.0+ adds Step 4.8.A unattended detection (Path D from #137): under `[ ! -t 0 ] || [ -n "$IDD_ALL_UNATTENDED" ]`, scan mode emits `deferred` rows with reason literal cited from `rules/append-vs-modify.md` § Reason pattern registry (`unattended-auto-Step-4.6-deferred`) instead of `surfaced`, enabling unattended chain to proceed-with-warn instead of silent break at downstream Step 0.5 gate.

Sourced from #135 (initial composable primitive) + #137 (unattended-mode contract codification + spec creation).

## Requirements

### Requirement: /idd-clarify SHALL operate in two dispatch modes (scan / update)

The `/idd-clarify` skill SHALL dispatch on presence of `--status` flag at invocation time. Without `--status` → scan mode: parse issue body for terminology / ambiguity / missing-context candidates against the terminology library; emit `### Clarity Surface` annotation block at issue body tail. With `--status action=row[,reason]` → update mode: locate the named row in the existing block and mutate only its status enum field, preserving all other row content.

#### Scenario: Scan mode without status flag

- **WHEN** `/idd-clarify #42` is invoked with no `--status` flag
- **THEN** the skill SHALL execute scan mode and emit a `### Clarity Surface` block to the issue body

#### Scenario: Update mode with status flag

- **WHEN** `/idd-clarify #42 --status resolved=2,user-confirmed-canonical-term` is invoked
- **THEN** the skill SHALL execute update mode, locate row 2 in the existing `### Clarity Surface` block, and change its status from previous value to `resolved` with the reason field set

### Requirement: Scan mode SHALL detect three classes (terminology / ambiguity / missing-context)

Scan mode SHALL examine the issue body for three distinct gap categories: (1) terminology — domain terms matching the canonical library's source-term + context pattern; (2) ambiguity — phrases with multiple plausible interpretations or critical under-specified variables; (3) missing-context — analysis or implementation requirements naming inputs whose source is not declared. Each detected candidate becomes a row in the emitted `### Clarity Surface` table with status field set to `surfaced` (attended) or `deferred` (unattended, per Step 4.8.A).

#### Scenario: Terminology candidate detected

- **WHEN** scan mode finds a body excerpt matching a library entry (e.g. body says "particularly important variables" and library lists this as source-term in context "MLM analysis", suggested canonical "feature importance")
- **THEN** the emitted row SHALL contain `terminology | "<quoted excerpt>" | feature importance | surfaced` (attended) or `terminology | "<quoted excerpt>" | feature importance | deferred | unattended-auto-Step-4.6-deferred` (unattended per Step 4.8.A)

#### Scenario: Empty surface case

- **WHEN** scan mode finds no candidates in any of the three classes
- **THEN** the skill SHALL still emit a `### Clarity Surface` block containing a single row `(none) | — | no issues detected | passed`, ensuring downstream `/idd-diagnose` Step 0.5 gate can distinguish "never ran clarify" from "ran and passed"

### Requirement: Step 4.8.A SHALL detect unattended mode and write deferred rows with registry-cited reason

In scan mode, Step 4.8.A SHALL execute before Step 5a and detect unattended invocation context via the union of (a) no controlling TTY on stdin (`[ ! -t 0 ]`) and (b) `IDD_ALL_UNATTENDED` environment variable being set. When detected as unattended, Step 5a SHALL write each detected row with `status=deferred` and `reason` field set to the literal `unattended-auto-Step-4.6-deferred` cited from `plugins/issue-driven-dev/rules/append-vs-modify.md` § Reason pattern registry, instead of writing `surfaced`. The unattended variant SHALL use the 5-column table schema (Type / Source / Suggested canonical / Status / Reason).

#### Scenario: Unattended detection via env var

- **WHEN** `IDD_ALL_UNATTENDED=1 /idd-clarify #42 < /dev/null` is invoked
- **THEN** Step 4.8.A SHALL set `IS_UNATTENDED=true` and Step 5a SHALL emit detected rows with `status=deferred` + `reason=unattended-auto-Step-4.6-deferred`

#### Scenario: Unattended detection via no-TTY

- **WHEN** `/idd-clarify #42 < /dev/null` is invoked with no TTY on stdin and no `IDD_ALL_UNATTENDED` env var
- **THEN** Step 4.8.A SHALL set `IS_UNATTENDED=true` (no-TTY branch) and behave the same as the env var case

#### Scenario: Attended mode preserves surfaced

- **WHEN** `/idd-clarify #42` is invoked with TTY on stdin and `IDD_ALL_UNATTENDED` unset
- **THEN** Step 4.8.A SHALL set `IS_UNATTENDED=false` and Step 5a SHALL emit rows with `status=surfaced` using the 4-column schema (no Reason column)

### Requirement: Reason literal SHALL cite the central registry

The unattended-mode reason literal SHALL be cited from `plugins/issue-driven-dev/rules/append-vs-modify.md` § Reason pattern registry. The literal SHALL appear in that registry exactly once as the single source of truth. SKILL.md implementations SHALL reference the literal by cite (with cross-link to the registry section), not by inline duplication that would risk typo drift between sites.

#### Scenario: Registry contains exactly one literal definition

- **WHEN** `grep -c "unattended-auto-Step-4.6-deferred" plugins/issue-driven-dev/rules/append-vs-modify.md` is run
- **THEN** the result SHALL equal `1`

#### Scenario: Implementing skills cite the registry

- **WHEN** `/idd-clarify` SKILL.md Step 4.8.A is read
- **THEN** the SKILL.md SHALL contain a cite reference to `rules/append-vs-modify.md` § Reason pattern registry rather than embedding the literal as a standalone constant detached from the registry

### Requirement: Update mode SHALL preserve IC_R007 verbatim discipline

Update mode SHALL modify only the status enum field of the named row. The skill SHALL NOT alter the Source quoted excerpt (IC_R007 verbatim preservation), Type field, Suggested canonical field, or any other row content. Update mode SHALL NOT alter any other row in the `### Clarity Surface` block beyond the named row. Update mode SHALL NOT alter any issue body content outside the `### Clarity Surface` block.

#### Scenario: Update mode preserves Source field

- **WHEN** `/idd-clarify #42 --status resolved=2,reason text` is invoked and row 2 has Source `"particularly important variables in MLM"`
- **THEN** after invocation, row 2 Source SHALL still be `"particularly important variables in MLM"` verbatim — only the Status field SHALL change to `resolved`

#### Scenario: Update mode does not affect other rows

- **WHEN** update mode targets row 2, and rows 1 and 3 exist in the block
- **THEN** rows 1 and 3 SHALL remain unchanged in all fields after the update completes

### Requirement: Step 4.6 mandatory auto-delegation from /idd-issue

`/idd-issue` Step 4.6 SHALL auto-delegate to `/idd-clarify $NEW_ISSUE_NUMBER` after the issue is created and before Step 4.7 Sister Sweep, unless `--multi-finding` mode is active. This delegation SHALL be mandatory (not advisory) per #135 v4 design D2. Failure of `/idd-clarify` SHALL NOT silently bypass — `/idd-issue` SHALL emit a deferred placeholder row into the issue body so downstream `/idd-diagnose` Step 0.5 gate catches the gap.

#### Scenario: Auto-delegation succeeds

- **WHEN** `/idd-issue` creates issue #50 with a text-based source
- **THEN** `/idd-issue` Step 4.6 SHALL invoke `/idd-clarify #50` automatically, and the resulting `### Clarity Surface` block SHALL appear in the issue body

#### Scenario: Auto-delegation skipped in multi-finding mode

- **WHEN** `/idd-issue source.docx` triggers multi-finding mode (≥2 findings detected)
- **THEN** Step 4.6 SHALL NOT auto-delegate (per #135 v4 design D3 — cost prevention to avoid N × prompt multiplication)

### Requirement: Source preservation guard SHALL apply across all modes

`/idd-clarify` SHALL NOT modify source blockquotes (lines beginning with `>`) per IC_R007 verbatim preservation, and SHALL NOT modify any existing `### ` heading content beyond emitting its own `### Clarity Surface` block at the body tail. Scan mode appends; update mode modifies only the targeted row's status field within its own emitted block.

#### Scenario: Source blockquote untouched

- **WHEN** scan mode runs on an issue whose body contains `> verbatim user statement`
- **THEN** the blockquote SHALL appear unchanged in the body after scan mode emits its `### Clarity Surface` block

#### Scenario: Pre-existing heading untouched

- **WHEN** scan mode runs on an issue whose body contains `## Problem` and `## Expected` sections
- **THEN** both sections SHALL appear unchanged in the body after scan mode emits its `### Clarity Surface` block at the body tail
