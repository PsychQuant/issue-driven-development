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

> **Every modify-action SHALL declare exactly one scope category from the canonical 8-category enumeration.** Actions without a declared category SHALL be treated as `(undeclared)` and SHALL be refused at runtime (by skill spec gate) or at review time (by analyzer, future tooling).

Scope declaration takes the form of an inline note in the action's SKILL.md description:

```
(category: <name>)
(category: <name>, scope: "<identifier>")
```

The `scope` qualifier names the targeted section / field / artifact when relevant (e.g. `scope: "## Current Status"`).

## Canonical 8-Category Enumeration

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

**Definition**: Absolute immutability. Once written, never modified by any action (AI or user), including `in-place-correction`. This is the IC_R007 zone.

**Scope boundary**: Exactly two kinds of content (closed list, #351 — do not extend by analogy):
1. **Original-source quotations** — a maximal run of consecutive lines starting with `>` in which some line contains one of exactly two labels: `Original text`, or the decision-template label `**Original**`. The quotation records what was actually said; it stays true as a record even when the judgment it led to turns out wrong.
2. **Third-party content** — comments, and issue bodies, whose author is neither the OWNER, a bot, nor the invoking user (the authenticated `gh` user). They are someone else's words; IDD proposes corrections to them but does not correct them in place. A bot's comment is outside this list (`--append` / `--replace` / `--prepend-note` may touch it), but it is still a third party's words, so `--correct` refuses it too (verify #351 round 2).

`--override-user-content --reason="..."` still exists for `--append` / `--replace` / `--prepend-note` as an explicit, audited exception for third-party comments; it is never accepted with `--correct`.

Issue-body prose in an issue opened by the OWNER or the invoking user — interpretation paragraphs, Expected, Actual, Impact, including text an IDD skill wrote there — is **not** in this zone: it is correctable through `in-place-correction`. An issue body opened by anyone else is third-party content (item 2). Before #351 the whole body above the `---` separator was listed here, which made every wrong interpretation permanent and pushed corrections into appended errata that downstream readers kept missing.

**Examples**:
- The `> **Original text**: …` blockquote under `## Problem` (per IC_R007)
- A collaborator's review comment on the issue (`/idd-edit` R5 refuses it; `--correct` has no override)

### 6. `append-only`

**Definition**: Only add new entries; never modify or remove existing entries.

**Scope boundary**: Whole artifact is append-target. Existing entries immutable; new entries inserted at top or bottom per artifact convention.

**Examples**:
- GitHub comments after publish (the GitHub mechanism enforces this; PATCH is reserved for `audit-block-append` and `in-place-correction`)
- `CHANGELOG.md` — new version entries prepended on top, old entries never modified
- `tasks.md` history rows (the rows themselves are append-only; the checkbox state field is `state-field-update`)
- Spectra archive snapshot directories (`openspec/changes/archive/<date>-<name>/`)
- `openspec/specs/<name>/spec.md` — changed only by archiving a change's delta, never edited directly

### 7. `free-rewrite`

**Definition**: Documentation / source code artifacts — the artifact IS the work product, not audit history. Free rewriting allowed (git provides history).

**Scope boundary**: Whole artifact. No internal structural protection.

**Examples**:
- SKILL.md files
- Canonical reference docs (`plugins/issue-driven-dev/references/*.md`)
- Source code files (`.rs` / `.py` / `.swift` / `.ts` / etc.)
- Plugin manifesto, README, contributor guides

### 8. `in-place-correction`

**Definition**: Replace content that the user has confirmed to be wrong, in place, so that later readers — humans and AI sessions that re-read the issue as memory — stop inheriting the error (#351). Applies only to the invoking user's own content — issue bodies and comments whose author is the OWNER or the invoking user's own `gh` login (org maintainers show as `MEMBER`, so the login check is what admits them) — including published comments that are otherwise `append-only`. A bot's comment is not included: it is a third party's words, answered with an errata comment (verify #351 round 2).

**Scope boundary**: One bounded region — a whole comment (`--scope whole-comment`) or one named section (`--section <heading>`; the only form allowed for an issue body). The action SHALL (a) show the original and the replacement and get explicit confirmation, (b) archive the prior full text under `.claude/.idd/archive/edits/` of the main worktree (not a linked worktree, so the archive outlives worktree cleanup) before writing — the archive is never tracked by git and Claude's tools are denied access to it — (c) end the replaced region with a marker that carries the backup id and no path, and (d) refuse `verbatim-preserve` content and the regions owned by other skills (`## Current Status` → `idd-update`, `### Clarity Surface` → `idd-clarify`). `/idd-edit --correct` is the only action declared in this category; other skills reach it by proposing the command.

**Examples**:
- `/idd-edit comment:<id> --correct --section "### Strategy"` replaces a Diagnosis strategy that named the wrong backup location
- `/idd-edit issue:<N> --correct --section "## Expected"` replaces an Expected paragraph that misread the request, keeping the `Original text` quotation above it untouched
- `/idd-comment --type errata --target-comment <id>` on a comment by the OWNER or the invoking user delegates to `/idd-edit --correct` instead of appending an errata comment

## Decision tree for classifying new modify-actions

When introducing a new IDD action that modifies an existing artifact, walk this tree to assign a category:

```
Does the action publish to a permanent place (GitHub comment, archived spec)?
├─ Yes → Does it happen in draft phase (before publish call)?
│   ├─ Yes  → category: inline-replace-before-publish
│   └─ No   → Continue ↓
│
Is the target verbatim-preserve content (an Original-text / **Original** quotation,
or a comment or issue body authored by someone other than the OWNER, a bot, or the invoking user)?
├─ Yes → REFUSE the action entirely (this zone is verbatim-preserve)
│
Is the action replacing content the user has confirmed to be wrong?
├─ Yes → category: in-place-correction (only via /idd-edit --correct; the OWNER's or your own content only —
│          a bot's comment gets an errata comment instead)
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
| **IC_R007** (verbatim source preservation) | "Don't modify original-source quotations (`Original text` / `**Original**`) or third-party content" | IC_R007 zones map to `verbatim-preserve` category in this rule. IC_R007 remains the authoritative source for *what counts as* verbatim; this rule says *how* the discipline is structurally enforced (refuse modification via category gate). |
| **IC_R010** (confidence-tagged routing) | "Tag confidence on automated decisions; defer low-confidence to review" | Orthogonal axis. IC_R010 governs *whether* an action should proceed; this rule governs *what scope* it operates on once proceeding. An IC_R010-confident action still SHALL declare its scope. |
| **IC_R011** (follow-up filing checkpoint) | "Surface tangential concerns at deliberation moments; file by default" | IC_R011 audit blocks (`### Sister Concerns Filed` / `### Closing Follow-ups Filed` / `### Linked-Context Siblings Filed` / `### Distribution Sync` / `### Residue Acknowledgement`) are all instances of `audit-block-append` category under this rule. IC_R011 governs *when* and *why* to surface; this rule governs *how* the surface is structurally written (named-section append, not free modification). |

When an IC principle and this rule both apply to an action, both SHALL be satisfied. They do not conflict in observed cases — IC principles operate on different axes (content selection, surfacing eligibility) while this rule operates on the modify-action axis (scope discipline).

## Gate logic: `authoritative_source` resolution (Path C generalization)

`#515` introduced supersession bridge logic in `idd-close` Step 0: when `## Implementation Complete > ### Checklist` exists with all items `[x]`, the gate ignores pre-impl Strategy/Plan checkboxes (they are superseded snapshots).

This rule generalizes that pattern。參與者要**按角色**描述而非當成一組同質的 gate site
（#290 修正——原本寫「4 個 gate site」，把 producer 誤列為 gate）。**角色不是互斥的**：
`idd-update` 兩者皆是。

| 誰 | Producer | Consumer |
|---|---|---|
| `idd-implement` Step 5a Checklist Sync | ✅ 寫 priority 1（`## Implementation Complete > ### Checklist`）| — |
| `idd-update` | ✅ 寫 priority 2（`## Current Status > ### Tasks`，經 `--tasks-file`，#290）| ✅ body sync 的 phase 推斷 fallback |
| `idd-close` Step 0 | — | ✅ 硬 gate：未完成則拒絕 close |
| `idd-verify` checklist scan | — | ✅ 讀為 verify context |

**以 producer 身分執行時不評估 resolution**；`idd-update` 在同一次執行中兩件事都做，但那是
兩個分開的動作（先寫、後讀），不是一個角色。

每個 consumer SHALL resolve an `authoritative_source` via the following priority order:

```
authoritative_source = first_exists([
  "## Implementation Complete > ### Checklist",   # producer: idd-implement Step 5a
  "## Current Status > ### Tasks",                # producer: idd-update --tasks-file
  "## Todo" | "## Tasks" | "## Checklist"         # producer: 無（僅人手寫）
])
```

When a source resolves, the gate evaluates only items in that source. Earlier sources (Strategy, Implementation Plan) are treated as superseded snapshots — not subject to gate evaluation, retained for historical reference.

### `exists` 的判準（normative，#290）

一個候選**只有在** heading 存在**且**其下含**至少一個可解析的 checklist 項目**時才 resolve。
heading 在而項目數為 0 **視同不存在**，resolution 繼續往下一個候選。

此定義**三個 consumer 一致適用**；consumer **SHALL NOT** 自訂 emptiness 規則。在 #290 之前
只有 `idd-close` Step 0 寫出這個條件（`len(items) > 0`），且只對 priority 1，另兩個無條件——
本節把它升為 canonical。

| 候選狀態 | resolve？ |
|---|---|
| heading 缺席 | 否 |
| heading 在，0 項 | **否** |
| heading 在，1 項未勾 | 是 |
| heading 在，3 項已勾 | 是 |

### 不變式：每一層都必須**具名其 producer 或明示無自動 producer**（normative，#290）

優先序的每一層 **MUST** 在上表指名它的 producer，**或**明示「無自動 producer（僅人手寫）」。
兩者皆可，但**不得留白**——留白會讓一層在實務上永遠不 resolve，使優先序**靜默塌縮**成剩下
的層，而塌縮不報錯，只會讓某些路徑莫名其妙地 fallback。

> 措辭注意：本不變式要求的是**具名**，不是「必須有自動 producer」。priority 3 明示為人工
> 逃生口即滿足；若寫成「每層都必須有 producer」，會與 priority 3 的既定設計直接矛盾。

這正是 #290 的成因：priority 2 被 consumer 讀，卻沒有任何 skill 寫它，而**那個事實沒有被
記在任何地方**——於是 chain 退化成「只有 priority 1」，而 priority 1 只有 `idd-implement`
產生，**任何繞過它的路徑都沒有 authoritative source**。

**priority 3 明示為「無自動 producer（僅人手寫）」**——它是給人工維護的 issue 用的逃生口。
若日後有工具開始依賴它，本不變式要求先為它指名 producer。

**本不變式無法被測試強制**——它約束的是「未來新增的層」，而未來的層尚不存在。只能寫在此處
靠 review 維持。

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
- **CLI parser + bash enforcement** (out of scope): native `--section` / `--scope` flag handling for `/idd-edit` at CLI parser layer + verbatim-preserve guard. Three R1/R2/R3 attempts at bash-level enforcement in SKILL.md introduced new bugs each iteration (infinite loop, flag-eat, multi-line awk-v BREAK). Deferred to follow-up issue [#154](https://github.com/PsychQuant/issue-driven-development/issues/154) for proper standalone proposal with multi-line body handling + parser pattern guards + errata flow integration designed upfront. Phase 1 (this change) is **spec-discipline-only**: the normative `--scope` / `--section` requirements + verbatim-preserve guard live in `openspec/specs/append-vs-modify-discipline/spec.md` Requirements 4-5 + this rule's "Spec discipline" section below + CHANGELOG `[2.73.0]`. `idd-edit/SKILL.md` was reverted to pre-#150 baseline as part of the R4 / Path (c) decision — SKILL.md surface (argument-hint, mode table, usage examples) does NOT currently describe the discipline. AI / user invocation reads spec + rule + CHANGELOG + applies discipline manually until #154 ships both the runtime gate AND the SKILL.md surface updates. (#154 shipped in v2.81.0 — see the Enforcement status paragraph under "Spec discipline" below.)

## Migration period for existing actions

≥ 8 existing IDD actions are retroactively labeled by the change that introduced this rule (`add-action-scoped-modify-discipline`). New actions added after this rule ships SHALL declare category at SKILL.md authoring time. The `(undeclared) → REFUSE` rule applies to both new and retroactively-introduced actions; legacy actions without inline notes are caught at next maintainer review.

## Spec discipline: `/idd-edit` SHALL declare scope

`/idd-edit` is the IDD plugin's existing comment-edit primitive. Per this rule's action-scoped discipline, the skill's invocation surface SHALL declare scope:

- `--append` / `--prepend-note` modes: `audit-block-append` category (scope inherent in mode semantics — trailing block / leading errata marker). No additional flag required.
- `--replace` mode: `bounded-section-replace` category. Invocations SHALL include `--scope whole-comment` (full-comment overwrite acknowledgment) OR `--section <heading-within-comment>` (named subsection scope).
- `--correct` mode: `in-place-correction` category (#351). Same scope flags as `--replace`; an issue-body target (`issue:<N>`) accepts `--section` only. No `--override-user-content`.

This rule additionally declares a verbatim-preserve guard at the comment layer: comments where `author_association ≠ OWNER` (and the author is neither in the known-bot allowlist nor the invoking user's own `gh` login) SHALL NOT be modified without explicit `--override-user-content --reason="..."` invocation discipline. `--correct` is narrower still: it admits only the OWNER and the invoking user, never a bot, and has no override.

**Enforcement status**: enforced at runtime by `scripts/idd-edit-helper.py` since v2.81.0 ([#154](https://github.com/PsychQuant/issue-driven-development/issues/154) → [#155](https://github.com/PsychQuant/issue-driven-development/issues/155) Python layer): `parse-args` refuses `--replace` / `--correct` without scope (exit 3), `validate-target` refuses authors other than the OWNER, a bot, or the invoking `gh` user (exit 4; with `--correct` a bot is refused as well), and `check-correction` refuses protected regions (exit 6, #351). The bash-in-SKILL.md attempts on PR #153 that this paragraph used to describe were replaced by that helper.

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
