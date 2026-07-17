---
name: append-vs-modify
description: Action-scoped discipline for IDD modify-actions — every modify SHALL declare scope category, undeclared SHALL refuse
---

# Append-vs-Modify Discipline Rule

**Every modify-action SHALL declare an explicit scope category. Undeclared modify-actions SHALL be refused.**

This rule supersedes IDD's previously implicit hybrid append+modify discipline. It applies uniformly to AI invocations and human user invocations — actor identity is NOT a discipline boundary.

## Why this rule exists

IDD plugin v2.72.0 development hit ≥ 6 supersession workaround instances in a single session — each new feature ran into "AI-authored stale state" and re-invented its own bridge:

- `#515` supersession bridge (`idd-close` Step 0 gate fork for Strategy/Plan pre-impl checkbox staleness)
- `#148` retroactive `## Implementation Complete` post (configured to trigger #515)
- `#149` retroactive `## Closing Summary` post (after commit-body auto-close trap)
- IC_R011 audit blocks (`### Sister Concerns Filed` / `### Closing Follow-ups Filed` / `### Distribution Sync` / `### Residue Acknowledgement`) appending to one comment without convergence
- Canonical reference docs growing freely (`ic-r011-checkpoint.md` 301→397 lines)
- `#150` body wiped by bad `sed` substitution + silent `gh issue edit` accept

Pattern: no first-class principle governs "how a modify-action should exist". Each new IDD feature ran into the same shape of pain and shipped its own ad-hoc workaround. This rule codifies the discipline so future contributors classify their modify-actions on day one instead of inventing a 7th supersession workaround.

User pivot during `/spectra-discuss` (2026-05-25): actor-based exemption ("AI restricted / user free") was structurally weak — `/idd-edit` blanket user-modify entry was a black hole, structurally same shape as raw `bash sed` (both lack scope declaration). Discipline shifted to action-scoped: every action declares what it modifies, regardless of who invokes.

## The Rule

> **Every modify-action SHALL declare exactly one scope category from the canonical 7-category enumeration.** Actions without a declared category SHALL be treated as `(undeclared)` and SHALL be refused at runtime (by skill spec gate) or at review time (by analyzer, future tooling).

Scope declaration takes the form of an inline note in the action's SKILL.md description:

```
(category: <name>)
(category: <name>, scope: "<identifier>")
```

The `scope` qualifier names the targeted section / field / artifact when relevant (e.g. `scope: "## Current Status"`).

## Canonical 7-Category Enumeration

### 1. `state-field-update`

**Definition**: Changes a machine-readable state field — `phase`, `timestamp`, `status` enum value, checkbox boolean. Does NOT modify prose.

**Scope boundary**: Only the named field. Surrounding text immutable.

**Examples**:
- `/idd-update` Current Status `**Phase**:` field change (`created` → `diagnosed`)
- `/idd-clarify --status resolved=N,<reason>` flips Clarity Surface row status enum
- `spectra task done` flips `- [ ]` to `- [x]`
- Step 0.5 dismiss row sets `deferred` → `dismissed` with reason

### 2. `bounded-section-replace`

**Definition**: Whole *named section* REPLACE — section boundary explicitly declared (section identifier is part of invocation contract). Does NOT overflow.

**Scope boundary**: The named section's heading-to-next-heading range only.

**Examples**:
- `/idd-update` REPLACE `## Current Status` entire section below `---` separator
- `/idd-edit --section "## Foo"` REPLACE the named section's content (heading preserved)

### 3. `audit-block-append`

**Definition**: APPEND a new audit block to a *named comment* under a *named section heading*. Does NOT modify existing content within or outside the target.

**Scope boundary**: The target section's end position (insert before next heading or EOF). Existing text immutable.

**Examples**:
- IC_R011 sister sweep PATCHes `### Sister Concerns Filed` block into a Diagnosis comment
- `/idd-diagnose` Step 3.4 Layer V Vagueness Pre-check PATCHes `### Vagueness Pre-check` block
- `/idd-issue` Step 4.6 emits `### Clarity Surface` block into a new issue body

### 4. `inline-replace-before-publish`

**Definition**: Modify occurs in the *draft phase before publish*. Once published (committed to GitHub or written to disk as final artifact), the content falls under `append-only` discipline.

**Scope boundary**: Time-bounded — only during draft assembly. Post-publish the same content is immutable.

**Examples**:
- `/idd-close` Step 3.5 inline replace `「follow up later」` → `「(see #NEW)」` in closing summary body assembly *before* `gh issue comment` publishes the comment

### 5. `verbatim-preserve`

**Definition**: Absolute immutability. Once written, never modified by any action (AI or user). This is the IC_R007 zone.

**Scope boundary**: User-authored prose, verbatim quotes, frozen spec contracts. Identified by structural markers (issue body above `---` separator) or content type (blockquote citing original text).

**Examples**:
- Issue body above the `---` separator (Problem / Type / Expected / Actual / Impact sections — user's original framing)
- Blockquote-wrapped verbatim quotes from external sources (per IC_R007)
- Spec files in `openspec/specs/<name>/spec.md` once a change is archived

### 6. `append-only`

**Definition**: Only add new entries; never modify or remove existing entries.

**Scope boundary**: Whole artifact is append-target. Existing entries immutable; new entries inserted at top or bottom per artifact convention.

**Examples**:
- GitHub comments after publish (the GitHub mechanism enforces this; PATCH is reserved for `audit-block-append` discipline)
- `CHANGELOG.md` — new version entries prepended on top, old entries never modified
- `tasks.md` history rows (the rows themselves are append-only; the checkbox state field is `state-field-update`)
- Spectra archive snapshot directories (`openspec/changes/archive/<date>-<name>/`)

### 7. `free-rewrite`

**Definition**: Documentation / source code artifacts — the artifact IS the work product, not audit history. Free rewriting allowed (git provides history).

**Scope boundary**: Whole artifact. No internal structural protection.

**Examples**:
- SKILL.md files
- Canonical reference docs (`plugins/issue-driven-dev/references/*.md`)
- Source code files (`.rs` / `.py` / `.swift` / `.ts` / etc.)
- Plugin manifesto, README, contributor guides

## Decision tree for classifying new modify-actions

When introducing a new IDD action that modifies an existing artifact, walk this tree to assign a category:

```
Does the action publish to a permanent place (GitHub comment, archived spec)?
├─ Yes → Does it happen in draft phase (before publish call)?
│   ├─ Yes  → category: inline-replace-before-publish
│   └─ No   → Continue ↓
│
Is the target a user-authored / IC_R007-verbatim zone?
├─ Yes → REFUSE the action entirely (this zone is verbatim-preserve)
│
Is the target a machine-readable state field (phase, timestamp, status enum, checkbox boolean)?
├─ Yes → category: state-field-update
│
Is the target a whole named section (with explicit identifier in the invocation)?
├─ Yes → category: bounded-section-replace
│
Does the action APPEND to a named section without modifying existing content?
├─ Yes → category: audit-block-append
│
Is the target a doc / source code file (artifact IS the work product)?
├─ Yes → category: free-rewrite
│
Is the action purely additive (new entries only, existing entries immutable)?
├─ Yes → category: append-only
│
None of the above → REFUSE; the action lacks a defined scope and SHALL NOT proceed
```

## Boundary with IC sister principles

This rule does NOT replace existing IDD principles — it codifies the modify-action *axis* that the IC principles each touch from their own angle.

| IC principle | Concern | Boundary with this rule |
|---|---|---|
| **IC_R007** (verbatim source preservation) | "Don't modify user-authored prose or external verbatim quotes" | IC_R007 zones map to `verbatim-preserve` category in this rule. IC_R007 remains the authoritative source for *what counts as* verbatim; this rule says *how* the discipline is structurally enforced (refuse modification via category gate). |
| **IC_R010** (confidence-tagged routing) | "Tag confidence on automated decisions; defer low-confidence to review" | Orthogonal axis. IC_R010 governs *whether* an action should proceed; this rule governs *what scope* it operates on once proceeding. An IC_R010-confident action still SHALL declare its scope. |
| **IC_R011** (follow-up filing checkpoint) | "Surface tangential concerns at deliberation moments; file by default" | IC_R011 audit blocks (`### Sister Concerns Filed` / `### Closing Follow-ups Filed` / `### Linked-Context Siblings Filed` / `### Distribution Sync` / `### Residue Acknowledgement`) are all instances of `audit-block-append` category under this rule. IC_R011 governs *when* and *why* to surface; this rule governs *how* the surface is structurally written (named-section append, not free modification). |

When an IC principle and this rule both apply to an action, both SHALL be satisfied. They do not conflict in observed cases — IC principles operate on different axes (content selection, surfacing eligibility) while this rule operates on the modify-action axis (scope discipline).

## Gate logic: `authoritative_source` resolution (Path C generalization)

`#515` introduced supersession bridge logic in `idd-close` Step 0: when `## Implementation Complete > ### Checklist` exists with all items `[x]`, the gate ignores pre-impl Strategy/Plan checkboxes (they are superseded snapshots).

This rule generalizes that pattern across all 4 gate sites (`idd-close` Step 0 / `idd-verify` checklist scan / `idd-update` body sync gate / `idd-implement` Step 5 Checklist Sync). Each gate SHALL resolve an `authoritative_source` via the following priority order:

```
authoritative_source = first_exists([
  "## Implementation Complete > ### Checklist",
  "## Current Status > ### Tasks",
  "## Todo" | "## Tasks" | "## Checklist"    # top-level headings
])
```

When a source resolves, the gate evaluates only items in that source. Earlier sources (Strategy, Implementation Plan) are treated as superseded snapshots — not subject to gate evaluation, retained for historical reference.

## Backward-compat fallback

When no `authoritative_source` resolves (legacy issues created before this rule shipped, or pre-Implementation issues that genuinely have only Strategy), the gate SHALL fall back to scanning all checklist-bearing sections (Strategy, Implementation Plan, Implementation Complete, Todo, Tasks, Checklist, Current Status > Tasks) — the pre-discipline behavior.

This fallback preserves backward compatibility:
- Existing closed issues remain inspectable / verifiable under the same behavior they were closed under
- Legacy in-flight issues (still using Strategy-only pattern) continue to gate correctly
- The supersession bridge for `#515` remains a no-op (the new generalized logic subsumes it)

Fallback is non-permanent: once an issue acquires an `authoritative_source` via normal `/idd-implement` flow, the gate transitions to authoritative-source-only evaluation for that issue.

## Tooling enforcement (future scope)

This rule defines the discipline; tooling-level enforcement is reserved for follow-up work:

- **Skill spec gate** (in scope of this rule): each modify-action's SKILL.md description SHALL contain `(category: <name>)` inline note. Skill author's responsibility; reviewable manually.
- **Future analyzer** (out of scope): static analyzer that scans SKILL.md for modify-action descriptions missing `(category: ...)` notes and flags as Critical. Follow-up issue when needed.
- **CLI parser + bash enforcement** (out of scope): native `--section` / `--scope` flag handling for `/idd-edit` at CLI parser layer + verbatim-preserve guard. Three R1/R2/R3 attempts at bash-level enforcement in SKILL.md introduced new bugs each iteration (infinite loop, flag-eat, multi-line awk-v BREAK). Deferred to follow-up issue [#154](https://github.com/PsychQuant/issue-driven-development/issues/154) for proper standalone proposal with multi-line body handling + parser pattern guards + errata flow integration designed upfront. Phase 1 (this change) is **spec-discipline-only**: the normative `--scope` / `--section` requirements + verbatim-preserve guard live in `openspec/specs/append-vs-modify-discipline/spec.md` Requirements 4-5 + this rule's "Spec discipline" section below + CHANGELOG `[2.73.0]`. `idd-edit/SKILL.md` was reverted to pre-#150 baseline as part of the R4 / Path (c) decision — SKILL.md surface (argument-hint, mode table, usage examples) does NOT currently describe the discipline. AI / user invocation reads spec + rule + CHANGELOG + applies discipline manually until #154 ships both the runtime gate AND the SKILL.md surface updates.

## Migration period for existing actions

≥ 8 existing IDD actions are retroactively labeled by the change that introduced this rule (`add-action-scoped-modify-discipline`). New actions added after this rule ships SHALL declare category at SKILL.md authoring time. The `(undeclared) → REFUSE` rule applies to both new and retroactively-introduced actions; legacy actions without inline notes are caught at next maintainer review.

## Spec discipline: `/idd-edit` SHALL declare scope (runtime enforcement deferred)

`/idd-edit` is the IDD plugin's existing comment-edit primitive. Per this rule's action-scoped discipline, the skill's invocation surface SHALL declare scope:

- `--append` / `--prepend-note` modes: `audit-block-append` category (scope inherent in mode semantics — trailing block / leading errata marker). No additional flag required.
- `--replace` mode: `bounded-section-replace` category. Invocations SHALL include `--scope whole-comment` (full-comment overwrite acknowledgment) OR `--section <heading-within-comment>` (named subsection scope).

This rule additionally declares a verbatim-preserve guard at the comment layer: comments where `author_association ≠ OWNER` (and author is not in known-bot allowlist) SHALL NOT be modified without explicit `--override-user-content --reason="..."` invocation discipline.

**Enforcement status**: spec-discipline + AI / user invocation guideline. Three implementation attempts (verify R1/R2/R3 on PR #153) showed bash-level enforcement in SKILL.md introduces new bugs incrementally. Runtime enforcement deferred to follow-up issue [#154](https://github.com/PsychQuant/issue-driven-development/issues/154) requiring proper standalone proposal with multi-line body handling + parser pattern guards + `/idd-comment` errata flow integration designed upfront.

Recommended invocation patterns (per discipline):
- `/idd-edit comment:NNN --replace --scope whole-comment --body "..."`
- `/idd-edit comment:NNN --replace --section "### Sister Concerns Filed" --body "..."`
- `/idd-edit comment:<external-user-id> --append --body "..." --override-user-content --reason="..."`

CHANGELOG.md `[2.73.0]` declares the spec discipline + cites this rule + tracks runtime-enforcement deferral via [#154](https://github.com/PsychQuant/issue-driven-development/issues/154).

## Reason pattern registry

Some `state-field-update` operations carry a `reason` field that downstream gates must regex-match for behavior dispatch (e.g. `/idd-diagnose` Step 0.5 gate proceeds-with-warn only on specific reasons). To prevent typo drift across multiple SKILL.md sites that cite the same literal, **all gate-recognized reason literals SHALL be registered here as the single source of truth**. SKILL.md sites SHALL cite by reference (with cross-link to this section), not by inline duplication.

| Reason literal | Originating action | Recognized by | Behavior |
|---|---|---|---|
| `unattended-auto-Step-4.6-deferred` | `/idd-clarify` Step 4.8.A — auto-defer in unattended mode (#137, v2.74.0+) | `/idd-diagnose` Step 0.5 gate | Proceed-with-warn (instead of REFUSE the `deferred` row) |
| `unattended-auto-Step-3.4-layerV-deferred` | `/idd-diagnose` Step 3.4 F — Layer V trigger auto-proceeds in unattended mode, leaving a structured deferred record in the Diagnosis comment (#120) | `/idd-all` Phase 6 Action items scan | Aggregate into「## Action items (require human review)」with the catch-up command `/idd-clarify #N` — not a gate bypass: the auto-proceed already happened, the record makes it recoverable |

**Adding a new reason literal**:
1. Choose strict literal (no abbreviation, no version suffix, no underscore variants — kebab-case with clear semantic anchor)
2. Add row to this table — name the originating action, recognizing gate(s), behavior
3. Update the originating SKILL.md to write the literal; update the recognizing gate SKILL.md to match
4. Both SKILL.md sites cite this registry rather than embed the literal inline
5. Add corresponding scenario to `openspec/specs/append-vs-modify-discipline/spec.md` if discipline-level recognition is required

**Why centralized**: 3+ SKILL.md sites citing the same literal is a typo-drift HIGH risk surface. One source eliminates drift; sites that drift their citation are caught by `spectra analyze` or manual grep (`grep -c "<literal>" plugins/issue-driven-dev/rules/append-vs-modify.md` = 1 SHALL hold).

**Regex matching convention**: when gates match these literals via regex, dot characters in the literal MUST be escaped (`Step-4\.6-deferred`, not `Step-4.6-deferred`) to prevent over-broad match. Case-sensitive, anchored (`^...$`) match preferred.

## See also

- `openspec/specs/append-vs-modify-discipline/spec.md` — normative spec
- `plugins/issue-driven-dev/references/ic-r011-checkpoint.md` — audit-block-append category authority
- `#515` — Path C precedent (supersession bridge)
- `#150` — the META issue codifying this rule
- `#137` — first reason literal registered (see Reason pattern registry section)
