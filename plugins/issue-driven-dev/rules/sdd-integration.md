---
name: sdd-integration
description: When to route IDD to Plan-mode or Spectra (formerly SDD), with backward-compat alias
---

# Complexity Routing Rule (Simple / Plan / Spectra)

> **v2.36.0+ rename**: the Complexity verdict was previously a binary `Simple` / `SDD-warranted`. It is now a 3-tier `Simple` / `Plan` / `Spectra`. `SDD-warranted` is treated as an alias for `Spectra` for backward compat (existing diagnosis comments parse without rewrite).
>
> **v2.50.0+ Layer V**: a 5th evaluation layer (Vagueness Pre-check) sits between Layer 1 and Layer 2. See "Layer V" section below. Existing diagnoses written before v2.50 are not retroactively re-evaluated.

`idd-diagnose` is the single decision point. After diagnosis, evaluate in order (5 layers as of v2.50):

1. **Disqualifiers (Layer 1)** — any one yes → force `Simple`, ignore everything below
2. **Vagueness Pre-check (Layer V, v2.50+)** — `max(V1, V4) ≥ 4` triggers a 3-option AskUserQuestion gate; user choice determines whether routing continues, body is clarified first, or verdict is force-set to `Plan via Layer V`
3. **Spectra-warranting condition (Layer 2 + Layer 3)** — both must be yes → `Spectra`
4. **Plan signals (Layer P)** — at least one yes → `Plan`
5. Otherwise → `Simple` (default)

This 5-layer evaluation replaces the v2.36 4-layer order by inserting Layer V right after Layer 1 disqualifier. Plan exists for "I want to think before I leap, but no spec contract is needed" — the most common case where Simple is too thin (multi-step / multi-file / decision-heavy) but Spectra is overkill (no published API contract for future callers). Layer V exists for the orthogonal case: **the change shape is small, but the request itself is unclear** — Simple's direct TDD loop would pattern-match a wrong direction.

## Layer 1: Simple-required disqualifiers (any one = force Simple)

If any of these match, the work is `Simple` regardless of other signals. Plan / Spectra add dead weight to fluid deliverables.

- **Primary deliverable is narrative / prose** — abstract revision, paper section, report, closing summary, blog post, internal memo, wording polish, translation
- **Primary deliverable is ad-hoc analysis script** — one-shot data analysis (R/Python/Julia notebook style) where the script is not a reusable abstraction; it produces tables/figures/reports for human consumption
- **Primary deliverable is updating existing prose without changing behavior** — typo fixes, wording cleanup, restructuring documents
- **Multi-file but each file is independent** — parallel doc updates, parallel script tweaks; multi-file count without interdependent contract is not a routing signal

**Rationale**: Plan's value is the approval checkpoint; Spectra's value is the spec contract. Narrative is fluid by design (evolves with reviewer feedback). Ad-hoc analysis is similar — once the question is answered, the script is archived. IDD's checklist + closing summary already provide sufficient audit trail.

## Layer V: Vagueness Pre-check (v2.50.0+)

`Layer V` evaluates **request clarity** — orthogonal to the change-shape signals that Layer 1 / 2 / 3 / P measure. The 4-shape layers ask "what kind of work is this?". Layer V asks "is the work request itself clear enough to act on?".

### Why Layer V exists

`spectra-discuss` already handles vagueness inside the Spectra path ("AI consistently over-estimates how complete its diagnosis is"). But Simple path has **no equivalent alignment gate**. The most common failure mode is **scope-small + request-vague** ("the menu feels off, fix it") — current routing forces `Simple`, AI pattern-matches a direction, code lands wrong. Layer V plugs that hole **before** the routing tier is decided, regardless of which downstream tier (Simple / Plan / Spectra) eventually applies.

### Heuristic: 6-point Likert per axis (no keywords)

Layer V uses Likert scoring per the project rule [`.claude/rules/attribute-assessment.md`](../../../.claude/rules/attribute-assessment.md). Two axes:

- **V1 (vague WHAT)** — clarity of what should be done
- **V4 (vague ACCEPTANCE)** — clarity of completion criteria

Both axes scored independently 1–6. Trigger threshold is `max(V1, V4) ≥ 4` (per-axis OR semantics). Anchors and concrete examples for each score live in the project rule file. **Keyword matching is explicitly forbidden** — see the rule's "Core principle" section for rationale.

`V2` (vague HOW) is **not** evaluated here: it is already covered by Layer P's "Decision-heavy with multiple valid approaches" signal. `V3` (vague SCOPE) is **not** evaluated here either: it overlaps with the IC_R011 sister sweep mechanism (`idd-diagnose` Step 3.6).

### When Layer V fires

When `max(V1, V4) ≥ 4`, `idd-diagnose` Step 3.4 fires a Hybrid 3-option `AskUserQuestion`:

| Score (max) | Default option        | Rationale                                                |
|-------------|-----------------------|----------------------------------------------------------|
| 4           | `proceed anyway`      | Mild vagueness — user often has unstated mental model    |
| 5           | `clarify now`         | Medium vagueness — clarification is recommended          |
| 6           | `escalate to Plan`    | Severe vagueness — alignment via Plan tier is recommended|

User can choose any of the three options regardless of default:

- **`clarify now`** → Claude asks 1–3 focused questions, appends user answers to the issue body via `gh issue edit` under `Clarification (added during diagnose)`, then re-runs Layer V + Step 3.5 with the clarified body
- **`proceed anyway`** → Layer V is skipped (audit trail records the trigger event), routing continues to Layer 2/3/P normally
- **`escalate to Plan`** → verdict force-set to `Plan via Layer V`; Layer 2/3/P evaluation is skipped entirely; routing chains to `idd-plan` (EnterPlanMode approval gate)

### Audit trail (always recorded)

Whether Layer V triggers or not, Step 3.4 PATCHes the just-posted Diagnosis comment with a `### Vagueness Pre-check` section recording: V1 score + reasoning, V4 score + reasoning, trigger status, user choice (if triggered), and routing effect. This is non-negotiable — Layer V's audit trail is the calibration mechanism for anchor drift.

### `idd-all` unattended mode

When `idd-diagnose` runs under `idd-all` UNATTENDED MODE directive, Layer V still scores but does not present `AskUserQuestion`. It auto-applies `proceed anyway` and records `[Layer V: V1=N V4=M, clarify-default skipped under unattended mode, defaulting to proceed]` in the audit trail. Same pattern as Plan tier under unattended mode (`/idd-plan` EnterPlanMode is also skipped).

### Layer evaluation order (5-layer)

| Layer 1 hit | Layer V hit | Layer 2 hit | Layer 3 hit | Layer P hit | Verdict             |
|-------------|-------------|-------------|-------------|-------------|---------------------|
| yes         | (skipped)   | (skipped)   | (skipped)   | (skipped)   | Simple              |
| no          | yes (escalate) | (skipped) | (skipped)  | (skipped)   | `Plan via Layer V`  |
| no          | yes (proceed/clarify) | yes | yes      | (any)       | Spectra             |
| no          | yes (proceed/clarify) | no  | (any)    | yes         | Plan                |
| no          | yes (proceed/clarify) | no  | (any)    | no          | Simple              |
| no          | no (≤3)     | yes         | yes         | (any)       | Spectra             |
| no          | no (≤3)     | no          | (any)       | yes         | Plan                |
| no          | no (≤3)     | no          | (any)       | no          | Simple              |

### Backward compatibility

Diagnoses written before v2.50.0 (without Layer V evaluation) are **not** retroactively re-evaluated or flagged. Existing `Simple` / `Plan` / `Spectra` / `SDD-warranted` verdicts remain valid. Layer V applies only to diagnoses created on or after v2.50.0.

There is **no `--ignore-vagueness` flag**: the 3-option `proceed anyway` choice already covers the "user knows what they want, just didn't write it down" case. Adding a flag would invite habitual bypass.

### Retrospective dry-run

When introducing or recalibrating Layer V anchors, run a retrospective dry-run on 5–10 closed issues to validate that anchors are not inflated (false positives) or deflated (false negatives). Record sample results in the table below.

| Issue                     | V1 | V4 | Triggered | Actual verdict was | Layer V would have routed | Match? |
|---------------------------|----|----|-----------|--------------------|---------------------------|--------|
| #10 (合併重複段落)        | 2  | 3  | no        | (Simple — closed)  | Simple (no change)        | ✓      |
| #9 (sanitize title)       | 2  | 3  | no        | (Simple — closed)  | Simple (no change)        | ✓      |
| #8 (shape assertion)      | 1  | 3  | no        | (Simple — closed)  | Simple (no change)        | ✓      |
| #7 (quoted heredoc)       | 2  | 3  | no        | (Simple — closed)  | Simple (no change)        | ✓      |
| #11 (umbrella split SOP)  | 2  | 3  | no        | (Plan — open)      | Plan (no change)          | ✓      |

**Dry-run finding (v2.50.0 release)**: 5 sample issues 全 V≤3,Layer V 都不 trigger。原因:這些 issue 多從 verify findings 派生,inherently 高清晰度(verify 階段已 framed problem)。Layer V 的設計目標是擋「user 直接開的、scope 小但需求模糊的 issue」(quadrant A),這類 issue 在 IDD-self-improvement repo 較少見。Anchors 不需 fine-tune,但需在後續其他 repo dogfood 時驗證。

## Spectra (Layer 2 + Layer 3)

`Spectra` is reserved for changes that produce a **frozen contract for future callers**.

### Layer 2: Necessary condition (must be yes)

- **Published API/protocol/skill/tool surface for future callers** — a function, MCP tool, plugin skill, agent, public Swift API, REST endpoint, OOXML element handler, or any other named interface that future callers (other modules, other plugins, other repos, other engineers) will depend on, AND the abstraction's behavior contract should be documented for those callers

If the necessary condition is not yes, do NOT route to Spectra. Drop down to Layer P (Plan signals).

### Layer 3: Spectra confirmation signals (at least one in addition to Layer 2)

- **Modifies normative behavior of an existing published spec** — MUST/SHALL clause changes that affect downstream maintainers
- **Affects 2+ existing specs that need consistency-checking** — cross-spec impact requires coordinated update
- **Architectural decision with long-term maintenance implications** — not just method-level choice, but a structural decision that future engineers will inherit

### The "Plan-Spectra line"

The single discriminator is **"published API/protocol for future callers"**:

| Pattern | Tier | Why |
|---------|------|-----|
| Internal refactor across 5 files (no exposed API change) | `Plan` | No new contract; just careful execution |
| Add a new MCP tool to a published server | `Spectra` | Tool name + JSON schema = published contract |
| Rename internal helper used by 4 modules | `Plan` | No external caller; internal coupling |
| Add new plugin skill / agent / hook | `Spectra` | Plugin skills are public surface |
| Modify spec MUST/SHALL clause | `Spectra` | By definition: spec contract |
| Tighten input validation that callers already conform to | `Plan` | No published behavior change for compliant callers |
| Loosen input validation that callers will start exploiting | `Spectra` | Contract widening is contract change |

When in doubt, ask: **"Will a future engineer / future caller check the spec to know how to use this?"** Yes → Spectra. No → Plan.

## Layer P: Plan signals (at least one = `Plan`)

If Layer 1 didn't fire AND Layer 2 didn't qualify for Spectra, evaluate Plan signals:

- **2+ files with sequence dependency** — file A's changes affect what file B's changes must do; can't parallelize the edits
- **Strategy has 5+ ordered steps** — sequential complexity benefits from explicit checkpoint before execution
- **Decision-heavy with multiple valid approaches** — the diagnosis identifies 2+ implementation strategies and the pick affects code shape (e.g., regex splice vs DOM walker, optimistic-locking vs pessimistic, batch vs streaming)
- **Touches risk-sensitive boundary** — concurrency, migrations, backward-compat shims, security-critical paths, save-durability, ordering semantics, atomic operations
- **Cross-file refactor without external contract change** — pulling shared logic into a helper, splitting a god-function, renaming internal API used by ≥3 callers

If at least one signal hits, route to `Plan`. The Plan path inserts an `EnterPlanMode` approval gate between diagnosis and TDD execution — user reviews the proposed plan, approves or revises, then implementation proceeds with same TDD discipline as Simple.

## Simple (default for everything else)

Route to `Simple` when none of the above apply:

- Bug fix with clear root cause and self-contained fix
- Single-file change
- Following an existing pattern (e.g., adding the Nth instance of a known visitor)
- Cross-file research analysis (R/Python script + outputs + docs + abstract)
- Narrative revision (abstract update, paper section rewrite)
- Ad-hoc one-shot analysis where the script is the deliverable
- Multi-step workflow where every step is bespoke for this issue with no shared abstraction

## Flow

```
Simple:    diagnose → idd-implement → verify → close
Plan:      diagnose → idd-plan (EnterPlanMode → user approves Implementation Plan → ExitPlanMode) → idd-implement → verify → close
Spectra:   diagnose → spectra-discuss → spectra-propose(#NNN) → spectra-apply → verify → close + archive
```

`Spectra (opt-out)`: `diagnose → spectra-propose(#NNN) → spectra-apply → verify → close + archive` (skip discuss only when ALL Step 4 opt-out conditions hold; see idd-diagnose).

## Why Plan exists (mid-tier between Simple and Spectra)

Pre-v2.36 the Complexity verdict was binary: `Simple` or `SDD-warranted`. Real-world routing patterns showed two failure modes:

1. **Spectra over-trigger**: cross-file refactor with 5+ steps and decision-heavy execution but no new caller contract was getting bumped to Spectra (because Layer 3 supplementary signals matched), producing proposal/design/spec artifacts for changes that nobody would ever check the spec for. Diagnosed in `kiki830621/collaboration_liu-thesis-analysis#21` retrospective and confirmed by user across 5+ subsequent issues.

2. **Simple under-served**: PsychQuant/che-word-mcp#104 was diagnosed as Simple ("FieldParser canonical 5-run form gap"), implemented, then 6-AI verify surfaced a P1 sub-bug because the diagnosis missed the rawXML-shadowing case. Re-routing through approval gate would have caught the gap before commit. The work didn't warrant a spec, but it did warrant deliberation.

Plan tier sits between: heavier than Simple's direct TDD, lighter than Spectra's spec/design/tasks artifacts. Mechanic is Claude Plan Mode (`EnterPlanMode` / `ExitPlanMode`) — the user reviews the Implementation Plan markdown in plan-mode UI and approves before any tool that modifies state runs.

## Why spectra-discuss is the default for Spectra

AI agents consistently over-estimate how complete their diagnosis is. A diagnosis may describe the strategy in detail but still leave critical decisions unresolved: naming, scope boundaries, which option to pick among equally valid ones, where to place new artifacts. Going directly to `spectra-propose` at that point produces proposals built on implicit assumptions that the user never confirmed.

`spectra-discuss` is the alignment safety net — it forces assumptions to be stated and corrected before any formal proposal is written. Skipping it should be the exception, not the default.

## When to opt-out of spectra-discuss (skip directly to spectra-propose)

Only skip `spectra-discuss` when ALL of the following are true:

- The user has already chosen a specific direction in the issue body or diagnosis discussion
- There are no open questions about naming, scope, or trade-offs
- The change follows an existing pattern without new abstractions
- The diagnosis Strategy section has zero unresolved decisions

If even one of these fails, keep `spectra-discuss` in the flow.

## Backward compat: `SDD-warranted` alias

For diagnosis comments written before v2.36.0:

- `### Complexity\nSDD-warranted` → parse as `Spectra`
- `### Complexity\nSimple` → parse as `Simple`
- `### Complexity\nPlan` → only appears in v2.36.0+ comments

Skills that read `### Complexity` (idd-all Phase 3, idd-implement Step 2.5) MUST treat `SDD-warranted` and `Spectra` as identical for routing.

New diagnosis comments (v2.36.0+) MUST emit `Spectra` — `SDD-warranted` is read-only legacy.

## Rules

1. **Issue is always the entry and exit** — Simple, Plan, and Spectra all start from and close with an issue
2. **One source of progress** — Simple/Plan use IDD checklist + TaskList; Spectra uses tasks.md, issue gets a link (`→ see spectra change: <name>`)
3. **Verify through IDD** — `idd-verify #NNN` regardless of which path was taken
4. **Close triggers archive (Spectra only)** — `idd-close` should also `spectra-archive` for Spectra changes
5. **Discuss-first for Spectra** — `idd-diagnose` must route Spectra issues to `spectra-discuss` by default; only bypass when the user explicitly opts out during the Step 4 routing prompt
6. **Plan-mode approval gate** — `idd-plan` MUST use `EnterPlanMode` + present full Implementation Plan + `ExitPlanMode` for user approval BEFORE any tool that modifies state. No silent fallthrough to TDD.
7. **Disqualifiers are evaluated first** — narrative / ad-hoc / no-caller deliverables route to `Simple` even if Plan signals or Spectra signals technically match. The disqualifier protects against pattern-matching scope hints into the heavier tiers.

## Retrospective check (motivating examples)

The 3-tier logic was designed to fix the over-triggering observed in `kiki830621/collaboration_liu-thesis-analysis#21` AND the under-deliberation observed in `PsychQuant/che-word-mcp#104` P1 sub-bug. Reviewers extending the logic should ensure these cases still classify correctly:

| Case | Pre-v2.36 verdict | Real outcome | v2.36+ verdict | Why |
|---|---|---|---|---|
| Issue #21 (research analysis: SP-stratified contrasts + abstract rewrite) | SDD-warranted | Three rounds of framing revision via spectra-ingest before settling; surgical follow-up went through Simple and converged faster | `Simple` | Layer 1 disqualifier hit: primary deliverable is abstract revision (narrative) and ad-hoc analysis script |
| Adding a new MCP tool to a published server | SDD-warranted | Spec/design/tasks artifacts useful for maintainers | `Spectra` | Layer 2 (new published API) + Layer 3 (architectural decision) both yes |
| che-word-mcp#104 FieldParser canonical fix | Simple | 6-AI verify surfaced P1 rawXML-shadowing — would have been caught by approval gate review of the Implementation Plan | `Plan` | Layer P: 2+ files with sequence dependency + risk-sensitive (XML emit roundtrip) + decision-heavy (regex splice vs DOM walker) |
| Fixing a typo in a function name across 5 callers | (would have triggered cross-file → SDD) | Trivial, doesn't need Plan or Spectra | `Simple` | Layer 1 disqualifier (multi-file but each independent) hit; no contract change |
| Refactoring a shared utility to add a new internal parameter, used by 4 modules | Borderline SDD | If parameter is part of documented contract → Spectra; if internal-only → was forced Simple, often under-deliberated | Internal-only → `Plan`; documented contract → `Spectra` | "Documented contract" is the discriminator |
| Adding `[~]` checklist marker semantics to idd-close | SDD-warranted | Real spec change with downstream callers (other idd-* skills) | `Spectra` | Layer 2 (modifies normative spec behavior of idd skills protocol) + Layer 3 (affects 2+ skills) yes |
| Internal refactor: extract BodyChildVisitor protocol to dedupe 5+ walkers | SDD-warranted (Layer 3 architectural) | Actually doesn't change any external behavior | `Plan` | Layer 2 fails (no new published API; existing walker callers unchanged); Layer P hits (5+ files with sequence dep + decision-heavy: visitor design) |
| Bug fix: 1 file, clear root cause, regression test added | Simple | Trivial | `Simple` | Default — no Layer 1, no Layer P, no Layer 2 |

When extending or modifying these rules, run a similar dry-run against current open issues. If the new logic would have routed differently from what the issue actually needed, reconsider the change.
