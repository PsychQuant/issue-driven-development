---
name: sdd-integration
description: When to route IDD to Plan-mode or Spectra (formerly SDD), with backward-compat alias
---

# Complexity Routing Rule (Simple / Plan / Spectra)

> **v2.36.0+ rename**: the Complexity verdict was previously a binary `Simple` / `SDD-warranted`. It is now a 3-tier `Simple` / `Plan` / `Spectra`. `SDD-warranted` is treated as an alias for `Spectra` for backward compat (existing diagnosis comments parse without rewrite).

`idd-diagnose` is the single decision point. After diagnosis, evaluate in order:

1. **Disqualifiers (Layer 1)** — any one yes → force `Simple`, ignore everything below
2. **Spectra-warranting condition (Layer 2 + Layer 3)** — both must be yes → `Spectra`
3. **Plan signals (Layer P)** — at least one yes → `Plan`
4. Otherwise → `Simple` (default)

This three-tier evaluation replaces the previous binary "Simple vs SDD-warranted". Plan exists for "I want to think before I leap, but no spec contract is needed" — the most common case where Simple is too thin (multi-step / multi-file / decision-heavy) but Spectra is overkill (no published API contract for future callers).

## Layer 1: Simple-required disqualifiers (any one = force Simple)

If any of these match, the work is `Simple` regardless of other signals. Plan / Spectra add dead weight to fluid deliverables.

- **Primary deliverable is narrative / prose** — abstract revision, paper section, report, closing summary, blog post, internal memo, wording polish, translation
- **Primary deliverable is ad-hoc analysis script** — one-shot data analysis (R/Python/Julia notebook style) where the script is not a reusable abstraction; it produces tables/figures/reports for human consumption
- **Primary deliverable is updating existing prose without changing behavior** — typo fixes, wording cleanup, restructuring documents
- **Multi-file but each file is independent** — parallel doc updates, parallel script tweaks; multi-file count without interdependent contract is not a routing signal

**Rationale**: Plan's value is the approval checkpoint; Spectra's value is the spec contract. Narrative is fluid by design (evolves with reviewer feedback). Ad-hoc analysis is similar — once the question is answered, the script is archived. IDD's checklist + closing summary already provide sufficient audit trail.

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
