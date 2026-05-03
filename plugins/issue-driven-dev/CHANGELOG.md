# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.49.0] - 2026-05-03

### Added
- **`references/ic-r011-checkpoint.md` v1.1.0 — Third-Party Skill Alignment section** ([kiki830621/ai_martech_global_scripts#530](https://github.com/kiki830621/ai_martech_global_scripts/issues/530), sub-issue E of [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) systematic plugin alignment, **last sub-issue closing the parent epic**): adds documentation guidance for applying IC_R011 checkpoint to third-party spectra-* skills.

  - `/spectra-discuss` (deliberation moment): SHALL apply manual checkpoint at discussion convergence — review log, AskUserQuestion 3-option, file via `gh issue create`, note in conclusion artifact under `### Tangential Observations (post-discuss)` heading.
  - `/spectra-propose` (deliberation moment): SHALL apply manual checkpoint at proposal drafting completion — re-read drafted artifact, AskUserQuestion 3-option, file via `gh issue create`, note in proposal under `### Tangential Observations (post-propose)` heading.
  - Eligible-skills inventory: explicitly N/A for `/spectra-apply` / `/spectra-archive` / `/spectra-ask` / `/spectra-ingest` / `/spectra-commit` / `/spectra-debug` (all mechanical execution, no deliberation moment).

### Why documentation-only (no SKILL.md modification)
spectra-* skills are published by third-party `kaochenlong/spectra-app` repo. Direct upstream SKILL.md modification would require:
- Cross-plugin coordination governance (different commit cycle)
- Upstream PR review by third-party maintainer

Documentation-side alignment delivers immediate value: agents/users reading this canonical doc when invoking `/spectra-*` know to apply the pattern manually at the equivalent lifecycle moments.

If spectra-app upstream adopts native IC_R011 checkpoint in their SKILL.md files, the new "Third-Party Skill Alignment" section becomes redundant and can be removed. Until then, the canonical doc is the single source of truth that bridges the gap.

### #523 parent epic closing
This is **sub-issue E**, the **last** of 6 sub-issues filed under #523 systematic plugin alignment. With #530 closed, the parent epic [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) is fully resolved across the IDD lifecycle:

| Sub-issue | Skill | Released | Strength |
|---|---|---|---|
| F #525 | canonical reference doc | v2.43.0 | (foundation) |
| A #526 | `/idd-implement` Step 5.7 Sister Bug Sweep | v2.44.0 | SHALL |
| B #527 | `/idd-close` Step 3.5 Closing Summary Scan | v2.45.0 | SHOULD |
| C #528 | `/idd-diagnose` Step 3.6 Sister Concern Surfacing | v2.47.0 | SHALL |
| D #529 | `/idd-issue` Step 4.7 Linked-Context Sister Sweep | v2.48.0 | SHOULD |
| **E #530** | `/spectra-discuss` + `/spectra-propose` (docs-only) | **v2.49.0** | SHALL |

Pre-existing alignment retained:
- `/idd-verify` Step 5b follow-up triage (pre-existing in plugin)
- `/idd-plan` Step 2.5 Tangential Observations Sweep ([#524](https://github.com/kiki830621/ai_martech_global_scripts/issues/524), v2.42.0)
- `/idd-close` Step 0 supersession ([#515](https://github.com/kiki830621/ai_martech_global_scripts/issues/515), v2.41.0 — gate logic, distinct from #527 IC_R011 checkpoint)

### Backward compatibility
Documentation-only addition. No SKILL.md behavioral change. spectra-* invocations continue to work exactly as before; the alignment is opt-in guidance for agents/users who want IC_R011-spirit follow-up filing during spectra deliberation moments.

### Related issues
- Parent: [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) (parent epic — fully resolved with this release)
- Canonical reference doc: [#525](https://github.com/kiki830621/ai_martech_global_scripts/issues/525) (v2.43.0, doc bumped to v1.1.0 in this release)
- Sibling sub-issues (all closed): [#526](https://github.com/kiki830621/ai_martech_global_scripts/issues/526), [#527](https://github.com/kiki830621/ai_martech_global_scripts/issues/527), [#528](https://github.com/kiki830621/ai_martech_global_scripts/issues/528), [#529](https://github.com/kiki830621/ai_martech_global_scripts/issues/529)
- IC_R011 codification: [#516](https://github.com/kiki830621/ai_martech_global_scripts/issues/516)

## [2.48.0] - 2026-05-03

### Added
- **`idd-issue` Step 4.7: Linked-Context Sister Sweep** ([kiki830621/ai_martech_global_scripts#529](https://github.com/kiki830621/ai_martech_global_scripts/issues/529), sub-issue D of [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) systematic plugin alignment): new advisory step between Step 4.5 (auto-milestone) and Step 5 (回報並停止). Scans 3 sources for sibling-concern markers:
  - Issue body draft (`also` / `additionally` / `related` / 「另外」 / 「順便」 / `BTW`)
  - Linked attachments (per IC_R007 attachments policy)
  - Recent session conversation (~20 turns before `/idd-issue` invocation)

  - If any source hits, AskUserQuestion three-option (`file as sibling issues now` / `file selected` / `skip`) per canonical [`references/ic-r011-checkpoint.md`](plugins/issue-driven-dev/references/ic-r011-checkpoint.md).
  - `file as sibling issues now`/`file selected` filing pipeline: `gh issue create` per orphan mention (parallel issues — **NOT** cross-linked into the just-created issue body), each with `confidence:confirmed` + `priority:P3` labels and source link `surfaced during /idd-issue #NEW linked-context sister sweep (Step 4.7)`.
  - PATCHes the just-created issue body via `gh issue edit` to append `### Linked-Context Siblings Filed (v2.48.0+ #529)` audit-trail line per canonical heading conventions.
  - Strength: **SHOULD (advisory, non-blocking)** per canonical eligibility criteria §6 — issue creation is light-touch (user is already in filing-active mode, double-prompt risks friction). Empty list = silent no-op default for clean single-issue invocations.
  - `AI_LOW_BAR_ISSUE_FILING=false` env var (per IC_R011 rollback hatch) silences AskUserQuestion silently with audit-trail line.

### Changed
- **Step 0 Bootstrap Task List**: added `linked_context_sister_sweep` TaskCreate entry between `create_milestone` and `report_and_stop`.

### Why
When user invokes `/idd-issue` from a session with scout history / attached document / linked source material, the session log + attachments often contain references to **sibling concerns** that are tangentially relevant but not the user's primary issue. Without checkpoint, those mentions stay in conversation; the user files one issue + walks away with N orphan mentions still un-tracked.

Sibling issues are **filed in parallel** (not as children of the just-created issue), preserving primary-concern focus. The just-created issue body simply tracks the audit trail of which siblings got filed alongside.

### Backward compatibility
- Empty surface list = silent no-op: existing single-issue invocations unchanged for clean filing without scout context.
- `AI_LOW_BAR_ISSUE_FILING=false` env var (per IC_R011 rollback hatch) skips AskUserQuestion silently.
- Existing issue creation flows without the new section: continue to work; section only appears when Step 4.7 surfaces a hit.

No flag deprecations. No breaking changes for any existing issue creation workflow.

### Related issues
- Parent: [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) (closed as parent tracker)
- Blocking dependency landed: [#525](https://github.com/kiki830621/ai_martech_global_scripts/issues/525) (canonical reference doc v2.43.0)
- Sibling shipped: [#526](https://github.com/kiki830621/ai_martech_global_scripts/issues/526) (idd-implement Step 5.7 v2.44.0), [#527](https://github.com/kiki830621/ai_martech_global_scripts/issues/527) (idd-close Step 3.5 v2.45.0), [#528](https://github.com/kiki830621/ai_martech_global_scripts/issues/528) (idd-diagnose Step 3.6 v2.47.0)
- IC_R011 codification: [#516](https://github.com/kiki830621/ai_martech_global_scripts/issues/516)

## [2.47.0] - 2026-05-03

### Added
- **`idd-diagnose` Step 3.6: Sister Concern Surfacing** ([kiki830621/ai_martech_global_scripts#528](https://github.com/kiki830621/ai_martech_global_scripts/issues/528), sub-issue C of [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) systematic plugin alignment): new mandatory step between Step 3.5 (Complexity Assessment) and Step 3.7 (Agent Routing). Surfaces sister-concern markers in the just-posted Diagnosis content + scout session log.

  - Trigger phrases: 「也有」 / 「same pattern」 / 「related」 / 「另外」 / 「sister」 / 「likewise affects」 — references to other files where the same root cause might apply, plus "this won't solve X" disclaimers in Strategy section.
  - Agent re-reads posted Diagnosis content after `complexity_assessment`, lists candidates per canonical [`references/ic-r011-checkpoint.md`](plugins/issue-driven-dev/references/ic-r011-checkpoint.md) heuristic, then AskUserQuestion three-option (`file all` / `file selected` / `skip`).
  - Files via `gh issue create` with `confidence:confirmed` + `priority:P3` + source link `surfaced during /idd-diagnose #NNN sister concern surfacing (Step 3.6)` for traceability.
  - PATCHes the Step 3 Diagnosis comment to add `### Sister Concerns Filed (mid-diagnose, v2.47.0+ #528)` audit-trail line per canonical heading conventions.
  - Strength: **SHALL** (mandatory step) per canonical eligibility criteria — diagnosis is a deliberation moment where sister concerns naturally surface during Strategy authoring. Empty surface list is a legitimate result.
  - `AI_LOW_BAR_ISSUE_FILING=false` env var (per IC_R011 rollback hatch) silences AskUserQuestion silently with audit-trail line.

### Changed
- **Step 0 Bootstrap Task List**: added `sister_concern_surfacing` TaskCreate entry between `complexity_assessment` and `confirm_and_route`.

### Why
Diagnosis Strategy section is **prime authoring territory** for sister concerns — the AI agent thinks about root cause, identifies the failing pattern, then naturally observes "this same pattern likely affects X / Y / Z elsewhere." Without mechanical checkpoint, those observations live only in conversation + Diagnosis comment text, never tracked as proper follow-up issues.

This is the **earliest** lifecycle moment in the IDD chain where sister concerns surface organically. Catching them here prevents downstream cascading manual reminders during implement / verify / close (the previously-observed `#510 → #518 → #520` cluster pattern).

### Backward compatibility
- Empty surface list = no-op: existing diagnose flow unchanged for issues with no sister concerns.
- `AI_LOW_BAR_ISSUE_FILING=false` env var (per IC_R011 rollback hatch) skips AskUserQuestion silently.
- Existing Diagnosis comments without the new section: continue to work; section only appears when Step 3.6 runs.

No flag deprecations. No breaking changes for any existing diagnose workflow.

### Related issues
- Parent: [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) (closed as parent tracker)
- Blocking dependency landed: [#525](https://github.com/kiki830621/ai_martech_global_scripts/issues/525) (canonical reference doc v2.43.0)
- Sibling shipped: [#526](https://github.com/kiki830621/ai_martech_global_scripts/issues/526) (idd-implement Step 5.7 v2.44.0), [#527](https://github.com/kiki830621/ai_martech_global_scripts/issues/527) (idd-close Step 3.5 v2.45.0)
- IC_R011 codification: [#516](https://github.com/kiki830621/ai_martech_global_scripts/issues/516)
- Reference impl pattern: [#524](https://github.com/kiki830621/ai_martech_global_scripts/issues/524) (idd-plan Step 2.5 v2.42.0)

## [2.46.0] - 2026-05-03

### Added
- **`idd-all` HITL mode** ([PsychQuant/issue-driven-development#1](https://github.com/PsychQuant/issue-driven-development/issues/1)): Phase 0.5 now resolves a `(path, interaction)` tuple from existing `pr_policy` config field + new `--pr` / `--no-pr` flags, replacing the hardcoded `--pr` enforcement.
  - Resolution precedence: `--pr` → `--no-pr` → fork detect → `pr_policy: always|never|ask`. Fork detection always overrides config to PR mode (no push to upstream).
  - **`(PR, unattended)`**: feature branch `idd/<N>-<slug>` from default branch + push + PR + sub-skill args carry `UNATTENDED MODE` directive (suppress `AskUserQuestion`/`EnterPlanMode`). v2.40.0 regression — `/loop` automation observes zero behavioral drift.
  - **`(direct-commit, attended)`**: stays on user's current checkout + no push + no PR + sub-skill args **omit** unattended hint. Native attended-by-default behavior fires: `idd-implement` Plan tier `EnterPlanMode` approval, `spectra-discuss` multi-turn pacing, `spectra-propose` Step 10 Park/Apply, `spectra-apply` Step 4 continue-confirmation. HITL scenario for solo/personal repos where PR is ceremony.
  - Mandatory resolved-tuple notice line printed before any state-mutating action: `→ Path: direct-commit (attended) — pr_policy=never`.
  - Phase 6 next-step copy is mode-aware: PR mode → `Next: review PR <url>, merge, then run /idd-close #N`; direct-commit mode → `Next: review last <N> commits, then run /idd-close #N`. **Verify is the terminal phase regardless of mode** — `idd-all` never auto-invokes `idd-close`.
  - **No silent timeout in attended mode**: documentation explicit that attended mode assumes a user is in session; `idd-all` imposes no timeout on sub-skill prompts.
- **`references/pr-flow.md`**: new `idd-all path resolution` section documenting that `idd-all` consumes `pr_policy` per the same algorithm as `idd-implement` (no behavioral divergence). Captures the "two axes from one source" architectural decision so future maintainers don't reintroduce duplicate config surfaces.

### Migration
Pure additive — no breaking change. Existing callers (`/loop`, `/idd-all #N`, `/idd-all #N --pr`, `/idd-all #N --cwd /path`) all continue to resolve to `(PR, unattended)`. Opt into HITL via `--no-pr` flag or `pr_policy: never` config.

### Spec
New capability `idd-orchestrator-modes` (`openspec/changes/idd-all-hitl-mode/specs/idd-orchestrator-modes/spec.md`) with 7 ADDED Requirements covering mode resolution, PR-path regression guarantee, direct-commit branch behavior, attended-interaction permits sub-skill questions, terminal-verify-regardless-of-mode, no-silent-timeout, and documentation contract.

## [2.45.0] - 2026-05-03

### Added
- **`idd-close` Step 3.5: Closing Summary Follow-up Keyword Scan** ([kiki830621/ai_martech_global_scripts#527](https://github.com/kiki830621/ai_martech_global_scripts/issues/527), sub-issue B of [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) systematic plugin alignment): new advisory step between Step 3 (review with user) and Step 4 (gh issue close). Scans drafted closing summary for trigger phrases (`follow-up` / `follow up` / `deferred` / `future` / `TODO` / `later` / `之後` / `未來` / `待` / `待 follow` / `順便` / `我之前觀察到` / `之後再` / `改天`).

  - Each match checked against existing `#NNN` cross-links via `gh issue view` — orphan mentions (no link or stale link to wrong-scope issue) trigger AskUserQuestion three-option (`file all` / `file selected` / `skip`) per canonical [`references/ic-r011-checkpoint.md`](plugins/issue-driven-dev/references/ic-r011-checkpoint.md).
  - `file all`/`file selected` filing pipeline: `gh issue create` with `confidence:confirmed` + `priority:P3` labels + source link `surfaced during /idd-close #NNN closing summary scan (Step 3.5)`, then **PATCHes the closing summary inline** to replace each filed mention with `(see #NEW)` cross-link.
  - `skip` keeps closing summary as-is, appends `### Closing Follow-ups Filed (v2.45.0+ #527)` audit trail with `Skipped per user choice (kept inline mentions without cross-links: ...)`.
  - Strength: **SHOULD (advisory, non-blocking)** per canonical eligibility criteria §6 — closure is mostly mechanical action with text artifact;hard-blocking on every "future" keyword would create user-friction. Empty-list and skip-with-reason are both legitimate outcomes. The value is making orphan-mention pattern visible at decision moment, not enforcing filing.
  - `AI_LOW_BAR_ISSUE_FILING=false` env var (per IC_R011 rollback hatch) silences AskUserQuestion silently with audit-trail line.

### Changed
- **Step 0.5 Bootstrap Task List**: added `closing_followup_keyword_scan` TaskCreate entry between `review_with_user` and `publish_and_close`.

### Disambiguation
A note added to Step 3.5 explicitly disambiguates this from Step 0 supersession check (#515 v2.41.0):
- **Step 0 supersession** is **gate logic** (recognize Implementation Complete > Checklist as canonical when supersession active) — operates on pre-implementation Strategy/Plan checkboxes
- **Step 3.5 closing summary scan** is the **IC_R011 checkpoint** (orphan mentions in drafted summary)

The two are orthogonal concerns. Step 0 runs at gate time;Step 3.5 runs after summary draft + before final close.

### Why
Closing summaries often contain phrases like "will follow up later" / "之後再做" / "deferred to next sprint" — but if the mention isn't linked to an actual issue, it vanishes into the closing comment never to be tracked. By scan time, the user has just typed the summary, the matched phrase is fresh in context — best moment to prompt for filing.

This step closes a gap in the IDD lifecycle: **closure** is the final discipline checkpoint where audit trail completeness matters most, since after close the issue artifact is frozen and orphan mentions become unrecoverable without manual archaeology.

### Backward compatibility
- Empty match list = no-op: closing flow unchanged for clean summaries (most common case).
- Existing closing summaries unaffected: Step 3.5 only runs on the **draft** before `gh issue close`.
- `AI_LOW_BAR_ISSUE_FILING=false` env var skips AskUserQuestion silently, only writes the skip-reason to closing summary audit trail.

No flag deprecations. No breaking changes for any existing close workflow.

### Related issues
- Parent: [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) (closed as parent tracker)
- Blocking dependency landed: [#525](https://github.com/kiki830621/ai_martech_global_scripts/issues/525) (canonical reference doc v2.43.0)
- Sibling already shipped: [#526](https://github.com/kiki830621/ai_martech_global_scripts/issues/526) (idd-implement Step 5.7 v2.44.0)
- IC_R011 codification: [#516](https://github.com/kiki830621/ai_martech_global_scripts/issues/516)
- Disambiguates from: [#515](https://github.com/kiki830621/ai_martech_global_scripts/issues/515) (idd-close Step 0 supersession v2.41.0 — gate logic, not IC_R011 checkpoint)

## [2.44.0] - 2026-05-03

### Added
- **`idd-implement` Step 5.7: Sister Bug Sweep** ([kiki830621/ai_martech_global_scripts#526](https://github.com/kiki830621/ai_martech_global_scripts/issues/526), sub-issue A of [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) systematic plugin alignment): new mandatory step between Step 5.5 (Open PR, if PR path) and chain to `/idd-verify`. Surfaces sister bugs discovered during TDD reproduction (Step 3 manual reproduction often reveals same-root-cause sibling files in adjacent paths).

  - Agent reviews session log + grep paths + reproduction trace, identifies candidates per canonical [`references/ic-r011-checkpoint.md`](plugins/issue-driven-dev/references/ic-r011-checkpoint.md) heuristic (same root cause manifesting in different file / unrelated quality issue from manual reproduction / TODO-FIXME hits / refactor opportunities adjacent to fix path), surfaces numbered list, then AskUserQuestion three-option (`file all` / `file selected` / `skip`).
  - Files via `gh issue create` with `confidence:confirmed` + `priority:P3` labels and source link `surfaced during /idd-implement #NNN reproduction (Step 5.7)` for traceability.
  - PATCHes the Step 5 Implementation Complete comment to add `### Sister Bugs Filed (mid-impl, v2.44.0+ #526)` audit-trail line per canonical heading conventions table: `Filed: #NNN, #MMM, #PPP` / `none surfaced` / `Skipped per user choice (...)` / `skipped (AI_LOW_BAR_ISSUE_FILING=false)`.
  - Strength: **SHALL** (mandatory step), but empty surface list is a legitimate result. `AI_LOW_BAR_ISSUE_FILING=false` env var (per IC_R011 rollback hatch) silences the AskUserQuestion prompt while preserving audit trail.

### Changed
- **Step 0 Bootstrap Task List**: added `sister_bug_sweep` TaskCreate entry between `open_pr_if_pr_path` and chain-to-verify.

### Why
2026-05-03 cluster `#510 → #518 → #520` proves the inconsistency: 3 separate same-pattern bugs (`gen_product_attribute_*` / `fix_wiser_poisson_tables.R` / `_build.R`) — each manual reminder was needed despite same root-cause pattern. Without mechanical checkpoint at this lifecycle moment, AI spirit-alignment drifts. Implementation is the **prime moment** for sister bugs to surface (manual reproduction is when they're most visible);30-second filing × N items vs. 30+ min reconstructing the cluster pattern weeks later (per IC_R011 cost calibration).

### Backward compatibility
- Empty observation list = no-op: existing implement flow unchanged for focused fixes with no sister observations.
- `AI_LOW_BAR_ISSUE_FILING=false` env var (per IC_R011) skips AskUserQuestion silently, only writes the skip-reason to Implementation Complete audit trail.
- Existing Implementation Complete comments without the new section: continue to work; section only appears when Step 5.7 runs.

No flag deprecations. No breaking changes for any existing implement workflow.

### Related issues
- Parent: [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) (closed 2026-05-03 as parent tracker, decomposed into 6 sub-issues)
- Blocking dependency landed: [#525](https://github.com/kiki830621/ai_martech_global_scripts/issues/525) (sub-issue F, canonical reference doc v2.43.0)
- IC_R011 codification: [#516](https://github.com/kiki830621/ai_martech_global_scripts/issues/516)
- Reference impl pattern: [#524](https://github.com/kiki830621/ai_martech_global_scripts/issues/524) (idd-plan Step 2.5 v2.42.0 — direct sibling at deliberation moment;Step 5.7 is the execution-moment counterpart)

## [2.43.0] - 2026-05-03

### Added
- **NEW canonical reference doc**: [`references/ic-r011-checkpoint.md`](plugins/issue-driven-dev/references/ic-r011-checkpoint.md) ([kiki830621/ai_martech_global_scripts#525](https://github.com/kiki830621/ai_martech_global_scripts/issues/525), sub-issue F of [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) systematic plugin alignment). Standardizes the IC_R011 ([#516](https://github.com/kiki830621/ai_martech_global_scripts/issues/516)) checkpoint pattern across all eligible IDD + Spectra skills:
  - **The 3-option AskUserQuestion structure** — exact labels (`file all` / `file selected` / `skip`), filing command template, sub-prompt structure for cherry-pick
  - **Heuristic triggers** — what counts as "concern worth surfacing" with 7 categories + trigger phrase regex
  - **Default-off exemptions** — narrow list (pure exploration / existing issue / hallucinated / CONSTRAINT / mechanical execution stages)
  - **Audit trail format** — uniform contents + per-skill heading conventions table
  - **Rollback escape hatch** — env var (`AI_LOW_BAR_ISSUE_FILING=false`) + repo CLAUDE.md flag (`# Disable IC_R011`); both layers honored additively
  - **Eligibility criteria** — SHALL (deliberation moments + manual reproduction) / SHOULD (closure + issue creation) / N/A (mechanical execution)
  - **Citation pattern** — exact Markdown for skills to back-reference the canonical doc

### Changed
- **`skills/idd-plan/SKILL.md` Step 2.5** now back-references the canonical doc: link added to `references/ic-r011-checkpoint.md`, and skill-specific sections marked as "this skill's specific application of that pattern". Step 2.5's own normative content unchanged (3-option AskUserQuestion + audit trail format already match canonical).
- **`skills/idd-close/SKILL.md` Step 0 supersession check** now disambiguates itself from IC_R011 checkpoint: a sentinel note marks supersession as "gate logic, NOT IC_R011 checkpoint", and points to [#527](https://github.com/kiki830621/ai_martech_global_scripts/issues/527) as the proper IC_R011 closing summary keyword scan tracker.

### Why
Sub-issues [#526–#530](https://github.com/kiki830621/ai_martech_global_scripts/issues/526) (sibling sub-issues of [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523)) all need the IC_R011 checkpoint pattern in their respective skills. Without a canonical reference, each implementation drifts in option labels, heuristic phrasing, audit format, and rollback semantics. This doc is the **mechanical anchor** that makes cross-skill consistency a verification artifact rather than a code-review aspiration.

Filing this as a separate sub-issue (F) before A-E (per [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) phasing rationale) means:
- A-E start by citing F → no per-skill drift
- Future skill alignments (whatever's added beyond #530's scope) follow the same pattern

### Backward compatibility
- No behavioral change to existing skills. `idd-plan` Step 2.5 + `idd-close` Step 0 supersession both keep their existing logic;only added doc back-references.
- `references/ic-r011-checkpoint.md` is a new file, no existing code references it (yet). Sub-issues #526–#530 will introduce citations as their Plan tier lands.

### Related issues
- Parent: [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) (closed 2026-05-03 as parent tracker, decomposed into 6 sub-issues F + A-E)
- Sibling sub-issues (open): [#526](https://github.com/kiki830621/ai_martech_global_scripts/issues/526) [#527](https://github.com/kiki830621/ai_martech_global_scripts/issues/527) [#528](https://github.com/kiki830621/ai_martech_global_scripts/issues/528) [#529](https://github.com/kiki830621/ai_martech_global_scripts/issues/529) [#530](https://github.com/kiki830621/ai_martech_global_scripts/issues/530) (all blocked on this doc)
- Source principle: [#516](https://github.com/kiki830621/ai_martech_global_scripts/issues/516) (IC_R011 codification)
- Reference impl back-link: [#524](https://github.com/kiki830621/ai_martech_global_scripts/issues/524) (idd-plan Step 2.5 v2.42.0) + [#515](https://github.com/kiki830621/ai_martech_global_scripts/issues/515) (idd-close Step 0 supersession v2.41.0)

## [2.42.0] - 2026-05-03

### Added
- **`idd-plan` Step 2.5: Tangential Observations Sweep** ([kiki830621/ai_martech_global_scripts#524](https://github.com/kiki830621/ai_martech_global_scripts/issues/524)): new mandatory step between Step 2 (Draft Plan) and Step 3 (Confirm post) that surfaces mid-plan tangential discoveries — Phase 1 Explore agents' pass-by sister bugs, Phase 2 grep-discovered drift, Phase 3 user-mentioned sub-concerns — previously falling into the gap between In-scope and Out-of-scope categorization, vanishing into conversation.
  - Agent self-reviews session log from Step 1 to current point, identifies candidates per IC_R011 (#516) default-on heuristic (verifiable behavior gap / sister bug / out-of-scope user-mentioned), surfaces numbered list, then AskUserQuestion three-option (`file all` / `file selected` / `skip`).
  - Files via `gh issue create` with `confidence:confirmed` + `priority:P3` labels and source link `surfaced during /idd-plan #NNN tangential sweep (Step 2.5)` for traceability.
  - PATCHes the Step 2 plan comment to add `### Tangential Observations (filed mid-plan, v2.42.0+ #524)` audit trail line: `filed #NNN, #MMM, #PPP` / `none surfaced` / `skipped per user choice` / `skipped (AI_LOW_BAR_ISSUE_FILING=false)`.
  - Strength: **SHALL** (mandatory step), but empty surface list is a legitimate result. `AI_LOW_BAR_ISSUE_FILING=false` env var (per IC_R011 rollback hatch) silences the AskUserQuestion prompt while preserving audit trail.

### Changed
- **`skills/idd-plan/SKILL.md` Implementation Plan template**: added `### Tangential Observations` section after `### Out-of-scope` (filled by Step 2.5).
- **Step 0 Bootstrap Task List**: added `tangential_sweep` TaskCreate entry between `draft_implementation_plan` and `enter_plan_mode_for_approval`.

### Why
The original `idd-plan` flow had Out-of-scope as the only categorization for non-implemented items, but **Out-of-scope is a categorized exclusion** (diagnosis-mentioned items deliberately deferred). Mid-plan **tangential discoveries** are different — they emerge during scouting/design without a categorization channel, so they vanish into conversation. The plan structure itself didn't have a slot for them, leading to recurring audit-trail loss observed in #524-trigger session.

This step is the plugin-side enforcement of IC_R011 (#516) "when in doubt, file the issue" applied specifically to the mid-plan deliberation window. Finer-grained than #523 broader systematic alignment, which covers Out-of-scope items + manual reproduction sister concerns + verify Step 5b + closing summary mentions but does NOT cover the mid-plan-without-categorization gap.

### Backward compatibility
- Empty observation list = no-op: existing plan flow unchanged for focused-scout cases.
- `AI_LOW_BAR_ISSUE_FILING=false` env var (per IC_R011) skips AskUserQuestion silently, only writes the skip-reason to plan body.
- Existing plan bodies without the new section: continue to work; section only appears when Step 2.5 runs.

No flag deprecations. No breaking changes for any existing plan workflow.

### Related issues
- #516 (IC_R011 Commercial Project Low-Bar Issue Filing — codifies the spirit being mechanically enforced here)
- #523 (broader plugin systematic alignment — sibling, but #524 is finer gap)
- #515 (idd-close skill design gap — sibling, different layer)

## [2.41.0] - 2026-05-03

### Fixed
- **`idd-close` Step 0 false-positive on pre-implementation Strategy/Plan checkboxes** ([kiki830621/ai_martech_global_scripts#515](https://github.com/kiki830621/ai_martech_global_scripts/issues/515)): `idd-close`'s gate scanned `Strategy` + `Implementation Plan` + `Implementation Complete > Checklist` as equal sources, but `idd-implement` Step 5 only writes back to its own `## Implementation Complete > ### Checklist` subsection — never PATCHes the pre-implementation Strategy/Plan comments. Result: complete IDD-lifecycle issues (work done, Implementation Complete fully `- [x]`) still showed 8+ stale `- [ ]` in Strategy/Plan, refusing close until user manually `gh api PATCH`ed both comments. Observed in #455 + #510 close, 2026-05-03.

### Added
- **Pre-implementation supersession check** in `idd-close` Step 0 (`skills/idd-close/SKILL.md`): when `## Implementation Complete > ### Checklist` exists and **all** its items are `- [x]`, that subsection is recognized as the canonical state of truth and `Strategy` / `Implementation Plan` `- [ ]` items are auto-superseded (skipped from gate). Logged as `(superseded by Implementation Complete > Checklist)` for audit trail.

### Why
The original Step 0 spec implicitly assumed `idd-implement` Step 5 syncs all checkbox sources, but the actual implementation only writes the canonical `## Implementation Complete > ### Checklist`. Strategy/Plan are pre-implementation **snapshots** — they record design intent at diagnose/plan time, and shouldn't function as a ship gate after the canonical implementation record exists. Strategy A from #515 diagnosis (header-based supersession) was chosen over B (sync-at-write — adds idd-implement Step 5 complexity, error-prone PATCH fan-out) and C (narrow gate — too aggressive, loses Strategy/Plan defensive coverage when Implementation Complete is missing/partial).

### Backward compatibility
- Legacy issues without `## Implementation Complete` (idd-implement never ran): unchanged, full spec table still scanned.
- Issues with `## Implementation Complete` but containing any `- [ ]`: supersession **not** triggered; falls back to full spec scan (defensive — catches both pre-impl AND post-impl unchecked items).
- Issues already manually `PATCH`ed via the workaround: continue to pass (Strategy/Plan items already `- [x]`; gate succeeds via either the supersession path or the legacy path).

No flag deprecations. No breaking changes for any existing close workflow.

### Spec table update
The `Step 0 > 掃描範圍` table in `skills/idd-close/SKILL.md` now documents the supersession rule explicitly: Strategy and Implementation Plan rows note `**Superseded** when Implementation Complete > Checklist 全 [x]`; Implementation Complete > Checklist row notes that triggering supersession requires all items to be `- [x]`.

## [2.40.0] - 2026-05-03

### Added
- **`--cwd` flag propagated to all cwd-aware sub-skills**: `idd-diagnose`, `idd-implement`, and `idd-verify` now accept `--cwd /path/to/local/clone` with the same semantics as `idd-all` v2.39.0. Each sub-skill's Step 0 parses `--cwd`, derives `$CWD` and `$GITHUB_REPO` from origin remote, and applies a substitution rule to all subsequent `git`/`gh` calls.
- **`references/cross-repo-cwd.md`**: Single source of truth for the `--cwd` convention — resolution algorithm (BSD-sed-compatible), substitution table (`git X` → `git -C "$CWD" X`, `gh issue/pr/repo X` → `gh ... -R "$GITHUB_REPO"`), failure modes, sibling-flag interaction (`--target` for read-only vs `--cwd` for git-writing skills).
- **`idd-all` Phase 1/2/3a/4 forwarding**: When `idd-all` invokes a sub-skill, it now appends `--cwd "$CWD"` (for git-writing skills) or `--target "$GITHUB_REPO"` (for read-only skills like `idd-issue`) to the args string. Without this, sub-skills would inherit Claude Code's session-level cwd and operate on the wrong repo — silently committing to repo A while user expected repo B.

### Changed
- **`idd-diagnose` argument-hint** advertises `--cwd /path/to/clone`.
- **`idd-implement` argument-hint** advertises `--cwd /path/to/clone` alongside `--pr` / `--no-pr`.
- **`idd-verify` argument-hint** advertises `--cwd /path/to/clone` alongside `--pr` / `--commits` / `--branch` / `--since`.
- **`idd-all` Phase 2 / 3a / 4 / Phase 4 follow-up creation**: explicit `--cwd "$CWD"` / `--target "$GITHUB_REPO"` propagation (was: implicit cwd inheritance via Skill tool).

### Why
v2.39.0 introduced `--cwd` only on `idd-all`, but the orchestrator's primary job is to invoke sub-skills via the Skill tool. Skill calls inherit Claude Code's session-level cwd, not anything `idd-all` resolved internally — so sub-skills would still operate on the wrong repo. This release closes that gap by extending the convention to every sub-skill that does local git ops, plus updating `idd-all` to forward the flag explicitly.

### Backward compatibility
Omitting `--cwd` reads from session `pwd` — identical to v2.39.0 behavior. No flag deprecations. Single-repo workflows (the common case) are unchanged.

## [2.39.0] - 2026-05-03

### Added
- **`idd-all --cwd /path/to/clone` flag**: Per-invocation override that decouples the orchestrator from Claude Code's session-level working directory. Previously, running `idd-all` on a repo other than the one your session started in required exiting Claude Code and re-launching with `cd <path>` first — because Skill tool calls inherit session cwd and don't follow mid-session `cd`. New `--cwd` flag breaks that friction; cross-repo orchestration (e.g. thesis work in repo A, want pipeline on dependency repo B) now works without session restart.
- **Step 0.2 "Resolve Working Tree"**: Explicit phase that derives `$CWD` from `--cwd` flag (or falls back to session `pwd`) and `$GITHUB_REPO` from `git -C $CWD remote get-url origin`. All subsequent phases reference these variables instead of relying on cwd defaults.
- **Improved abort messages**: Phase 0.2/0.3 abort guidance now includes `--cwd /path/to/clone` as an explicit alternative to `cd $path && claude`. Failure Modes table grew 3 new rows for `--cwd` validation errors.
- **Cross-repo invocation example** in Examples section: `/idd-all #43 --cwd /Users/che/Developer/macdoc/packages/ooxml-swift`.

### Changed
- All `git` calls in idd-all use `git -C "$CWD" ...` (was: implicit cwd)
- All `gh` calls in idd-all use `gh -R "$GITHUB_REPO" ...` (was: implicit cwd repo detect)
- `argument-hint` updated to advertise the new flag

### Backward compatibility
- Omitting `--cwd` reads from session `pwd` — identical to v2.38.0 behavior. No flag deprecations.

## [2.38.0] - 2026-05-02

### Added
- **`idd-diagnose` Step 3.7**: Calls `~/bin/idd-route recommend` after Complexity Assessment. Injects "Recommended Agent" section into diagnosis comment with confidence + expected metrics + per-candidate stats + reasoning. Powered by data-driven recommendation against `<repo>/.claude/.idd/routing-stats.jsonl` + global mirror at `~/.cache/idd-route/stats.jsonl`. Falls back to static heuristic on cold start.
- **`idd-verify` Step 5d**: Calls `~/bin/idd-route record` after findings post + triage. Captures (issue, agent, complexity, scope_files, scope_loc, signals, round_trips, blocking, medium, low, followups) + initial outcome=in_review. Append-only JSONL.
- **`idd-close` Step 4.5**: Calls `~/bin/idd-route update-outcome` after issue close. Appends a follow-up record with outcome=merged or outcome=abandoned (auto-detected from `gh pr view --json merged`). Original in_review record from idd-verify Step 5d stays for audit. Requires `idd-route-swift` v0.3.0 (P2 of plan); gracefully no-ops on `command not found`.
- **`references/agent-routing.md`**: Canonical contract for IDD ⇄ idd-route boundary. Lifecycle integration (diagnose recommends, verify records, close finalizes), graceful-skip semantics when binary missing, signal extraction conventions, opt-out mechanisms (kill-switch flag / per-project / per-machine config / uninstall).

### Changed
- All three new step blocks gracefully no-op via `command -v idd-route` check — IDD flow is unchanged for users who don't install the companion `idd-route` plugin.
- Marketplace migration: this is the first issue-driven-dev release shipping in `PsychQuant/issue-driven-development` (the new dedicated marketplace). Full 63-commit history preserved via `git filter-repo` from the previous home (`PsychQuant/psychquant-claude-plugins`). `git log -- plugins/issue-driven-dev/` shows complete evolution since v1.0.0.

## [2.37.0] - 2026-05-02
### NEW: External-agent / PR mode for `idd-verify` + use-case routing reference

Closes a structural gap: `idd-verify` previously assumed Claude was always the implementer (operating on `git diff` / `HEAD~1`). When implement is delegated to another agent (Codex via `codex exec`, Copilot Workspace, remote claw on PsychQuantClaw), the change set lives in a PR or remote branch — current verify couldn't reach it.

#### `idd-verify` new input source flags

| Flag | Mode | Diff source |
|------|------|------------|
| `--pr <N>` | PR mode | `gh pr diff <N>` (with `gh pr checkout` so reviewer agents see file context); auto-restore original branch after verify |
| `--commits <N>` | Local mode | `HEAD~N..HEAD` |
| `--since <ref>` | Local mode | `<ref>..HEAD` |
| `--branch <name>` | Branch mode | `git diff origin/<default>...<name>` |
| (no flag) | **Auto-detect** | Count `Refs #N` commits since `origin/<default>` → if N>0 use HEAD~N; else `gh pr list --search "#N in:body" --state open` → AskUserQuestion to pick |

Auto-detect catches the common "I cloned this repo, Codex committed 3 things, I forgot `--commits 3`" scenario without silently switching modes.

#### Issue ↔ PR correspondence gate (PR mode iron rule)

`--pr <N>` runs a hard gate before invoking the 6-AI ensemble:

- `gh pr view --json body` → grep `Refs #N` patterns into **discovered set**
- PR body has zero `Refs #N` → **ABORT** with "violates IDD discipline; add `Refs #N` and retry"
- User passed `#98` but PR doesn't ref #98 → **ABORT** with "correspondence broken"
- PR refs `{#98, #105}` but user only passed `#98` → **AskUserQuestion** to confirm scope

A PR without any issue ref is an untrackable change. IDD's audit value evaporates if the PR-issue link doesn't exist.

#### PR-as-master cross-post

PR mode flips master comment location from issue → PR (external agent owners work in PR view; never see issue comments). Each ref'd issue receives a 1-line pointer comment back:

```markdown
## Verify (via PR #123)
**Result**: PASS — no blocking findings
**Full report**: https://github.com/owner/repo/pull/123#issuecomment-NNN

This issue's findings: see "#98" section in the linked report.
```

Capture-master-URL-then-write-pointer SOP enforced (preventing the recurring bug class where pointer URLs accidentally referenced earlier diagnosis / implementation comments instead of the actual verify report).

#### NEW reference: `references/external-agent-delegation.md`

Single source of truth for IDD ⇄ external agent contract. Covers:

- 4-phase delegation impact matrix (diagnose / implement / verify / close)
- Hands-off principle (no babysitting external agents; strict verify + opt-in fix takeover)
- Three input modes + auto-detect resolution algorithm
- Issue↔PR correspondence gate
- PR-as-master cross-post + working tree handling
- Out-of-scope items deferred to v2 (`--takeover`, `idd-handoff`, force-push detection)

#### NEW reference: `references/usecase-routing.md`

Discoverability gap fix: 24-row table mapping common scenarios → exact skill chain + flags + contract doc. Covers single-issue, batch, cluster-PR, external-agent (PR/commits/branch/auto), Plan tier, Spectra-warranted, bundle close, Spectra-bridge, multi-repo monorepo. Plus a top-of-doc decision tree ("你正要做什麼？") for users who don't know which entry point to start from.

Linked from CLAUDE.md (Claude-facing) and README.md (human-facing) so both audiences find it.

#### Touched files

- `skills/idd-verify/SKILL.md` — argument-hint, description, allowed-tools, Cluster-PR mode section, External-agent / PR mode section (new), 參數 section, Step 0 TaskCreate list (+ resolve_input_source / gate_pr_correspondence / post_master_and_pointers / restore_working_tree), Step 0.5 (new), Step 0.7 (new), Step 1 multi-source, Step 4 master-pointer rules per mode, report format examples
- `references/external-agent-delegation.md` — new
- `references/usecase-routing.md` — new
- `CLAUDE.md` — Use-Case Routing section (new) before Multi-issue Invocation
- `README.md` — Use-Case Routing + External-Agent Verify sections (new) before Multi-issue Invocation

#### Backward compatibility

Single-issue invocation `idd-verify #42` without flags still works exactly as v2.36 in the common case (no Refs commits, no open PRs → falls back to `HEAD~1`). Auto-detect only activates AskUserQuestion when ambiguous; never silently switches modes. Cluster-PR mode (`#34 #36 #38`) unchanged. No flag deprecations.

## [2.35.0] - 2026-04-30
### NEW: `scripts/process-attachments.sh` + `rules/process-attachments.md` — attachment 上下游處理協定

Closes a recurring gap: `gh issue view --json` 抓不到 issue body 含的 user-attachments docx/pdf 內容,IDD skills 過去全程沒處理 → diagnosis 漏關鍵 source-of-truth(歷史案例:kiki830621/collaboration_liu-thesis-analysis#21 摘要 docx 結尾段落「mismatch / SP 作為機制 / construct mapping」三條 narrative bridge 因 idd-diagnose 沒讀附件被遺漏,後續 spectra-propose 重建 design/spec/tasks 全部要回頭補)。

**設計選擇**:把機械工作(detection / curl / sha256 / manifest write / diff check / disk verify)放進 `scripts/process-attachments.sh` helper,**不**依賴 SKILL.md 文檔 link 讓 Claude follow — shell call 一定執行,文檔 link Claude 不一定 follow。SKILL.md 只 call `bash $CLAUDE_PLUGIN_ROOT/scripts/process-attachments.sh {download|check|verify} <NUMBER>`,parse 部分(docx → text)由 Claude 用 MCP tool(che-word-mcp / che-pdf-mcp / Read)處理,因為 parse 本來就需要 LLM 介入。

### Helper script: 3 個 commands

| Command | 用途 | 主要 caller | Exit code 0 / 1 |
|---------|------|-------------|-----------------|
| `download <N>` | 偵測 issue body/comments 的 attachment URL,curl 下載到 `.claude/.idd/attachments/issue-N/`,寫 `_manifest.json` | idd-diagnose Step 1.5 / idd-issue | 0=完成或無 attachment;1=部分下載失敗(error 條目寫進 manifest) |
| `check <N>` | 確認 manifest 涵蓋當下 issue attachment list;偵測 diagnose 後新增 | idd-implement Step 1.2 / idd-verify Step 1.5 / idd-report | 0=up-to-date;1=manifest missing 或有新增(警告但不 auto-repair) |
| `verify <N>` | 確認 manifest 列出的檔案在 disk 上還在 | idd-close Step 1.4 | 0=all present;1=部分被搬走/刪掉(警告但不 abort close) |

Repo 自動從 walk-up config 解析(支援新 `.claude/.idd/local.json` / 舊 `.claude/issue-driven-dev.local.json` / 更舊 `.claude/issue-driven-dev.local.md` YAML frontmatter);可用 `--repo owner/repo` 顯式 override。`IDD_CALLER` 環境變數記錄到 manifest `fetched_by` 欄位作 audit。

### Changed

<!-- (formerly: 上下游責任分工) -->

- **上游下載(`idd-issue`, `idd-diagnose`)** — call `download` 機械抓取 + manifest;Claude 後續用 MCP-first parser 讀內容(`.docx` → che-word-mcp、`.pdf` → che-pdf-mcp、圖片 → Read tool;fallback pandoc / pdftotext)
- **下游檢查(`idd-implement`, `idd-verify`, `idd-close`, `idd-report`)** — call `check` 或 `verify`,缺漏輸出警告引導使用者重跑 idd-diagnose,**不 auto-fetch**(避免 mask 上游 skill bug)
- **不適用** — idd-list / idd-config(不分析 issue 內容)

### Manifest schema(`_manifest.json`)

```json
{
  "issue": 21,
  "fetched_at": "2026-04-30T03:13:02Z",
  "fetched_by": "idd-diagnose",
  "files": [
    {"filename": "1.docx", "url": "https://...", "sha256": "2ae0...", "size_bytes": 16363}
  ]
}
```

下載失敗的條目改為 `{filename, url, error: "download_failed"}`。

### Namespace 重組:`.claude/.idd/`

統一所有 idd 工作流檔案到 `.claude/.idd/`:

```
.claude/.idd/
  ├── local.md         # was .claude/issue-driven-dev.local.md
  ├── local.json       # was .claude/issue-driven-dev.local.json
  ├── state/
  │   └── bridge.json  # was .claude/state/idd-bridge.json
  └── attachments/
      └── issue-NNN/   # 新功能
```

理由:idd config + state + attachments 屬於 issue 工作流,不該散在 `.claude/` root 跟 `.claude/state/` 兩處;統一到 `.claude/.idd/` 子目錄讓 namespace 收斂,協作者一看就知道「這些是 IDD 的東西」。

### Backward compat

Walk-up search 同時找新舊路徑,**新路徑優先**;偵測到 legacy(`.claude/issue-driven-dev.local.json` / `.claude/state/idd-bridge.json`)印一行 migration hint 但 skill 仍正常運作。新 install 一律寫新路徑(config-protocol.md `When skills should write back to config` 段落更新)。

Migration 命令:

```bash
cd <repo-root>
mkdir -p .claude/.idd .claude/.idd/state
[ -f .claude/issue-driven-dev.local.json ] && mv .claude/issue-driven-dev.local.json .claude/.idd/local.json
[ -f .claude/issue-driven-dev.local.md ] && mv .claude/issue-driven-dev.local.md .claude/.idd/local.md
[ -f .claude/state/idd-bridge.json ] && mv .claude/state/idd-bridge.json .claude/.idd/state/bridge.json
```

### Changed
- **NEW** `plugins/issue-driven-dev/scripts/process-attachments.sh`(150 行 bash + python3 inline,3 個 commands;支援 walk-up config 含 .md frontmatter fallback)
- **NEW** `plugins/issue-driven-dev/rules/process-attachments.md`(薄薄的:scope / storage / manifest schema doc / parser strategy / reference convention / .gitignore guidance / 6 條 iron rules;機械邏輯不重複,引用 helper script)
- `skills/idd-diagnose/SKILL.md` — Bootstrap Task List 加 `download_attachments`;Step 1.5 改為 `bash $CLAUDE_PLUGIN_ROOT/scripts/process-attachments.sh download $NUMBER` + Claude 後續 parse
- `skills/idd-implement/SKILL.md` — Bootstrap Task List 加 `check_attachments`;Step 1.2 改為 `bash ... check $NUMBER`,exit 1 警告不 abort
- `skills/idd-verify/SKILL.md` — Bootstrap Task List 加 `check_attachments`;Step 1.5 改為 `bash ... check $NUMBER`,把 attachment path 塞進 reviewer agent prompt 作 source-of-truth
- `skills/idd-close/SKILL.md` — Bootstrap Task List 加 `check_attachments`;Step 1.4 改為 `bash ... verify $NUMBER`,disk integrity check
- `references/config-protocol.md` — Walk-up algorithm 雙路徑;first-run write 寫新路徑;新增 Migration command
- `rules/spectra-bridge.md` — bookmark path 全面換新;Hard rule #6 加 backward compat 條款
- `CLAUDE.md` — 新增「Attachments」「Namespace Migration」段

### Iron rules added

- 下載 = mandatory for upstream(idd-diagnose 偵測到 attachment URL 必須下載,不可跳過)
- Reference by path, never by URL(comment / report 一律用 repo 相對 path)
- Failure must be visible(下載 / parse 失敗一律輸出警告,禁止靜默)
- Downstream never auto-repairs upstream(下游發現 manifest 缺漏 → 警告 + 引導,不偷偷補抓)
- Storage location is fixed(`.claude/.idd/attachments/issue-{NNN}/`,skill 不允許各自選位置)
- Script is source of truth(機械工作由 helper script 處理,SKILL.md 不得 inline 重新實作)

### Out of scope (留下次)

- `idd-issue` 處理「下載別人 issue 的 attachment」(目前只處理「上傳本地素材」,反方向)
- `idd-report` / `idd-all` 的 attachment check
- `idd-config` 的 auto-migrate 命令(目前只在 walk-up 印 hint,沒主動搬)
- `.gitignore` template 自動生成

## [2.33.0] - 2026-04-28
### NEW: `MANIFESTO.md` — methodology thesis

Formalizes the IDD methodology argument as a standalone document, separating "what the plugin does" (README) from "why this is a methodology not a workflow tool" (MANIFESTO).

### Changed

<!-- (formerly: Thesis) -->

> **TDD writes tests. SDD writes specs. IDD solves bugs.**
> 前兩個是手段，IDD 是目的。

### Document structure

- **三 methodology 各自回答的問題** — TDD/SDD/IDD 對應 verification unit；只有 IDD 給出 DONE definition
- **5-axis 解 bug 能力拆解** — diagnosis quality / fix completeness / verification independence / regression prevention / audit traceability。TDD 覆蓋 1.5/5，SDD 覆蓋 0/5，IDD 覆蓋 5/5
- **Verification × Closure 兩個正交軸** — TDD/SDD 在 verification axis 高，但在 closure axis 是 0；IDD 兩軸都正
- **Falsifiability strict superset** — formal proof: IDD ⊋ TDD ∪ SDD via Step 3 RED→GREEN inheritance + spectra-apply conformance inheritance + Step 1.6 semantic gate
- **TDD/SDD ⊂ IDD 的包含關係** — TDD/SDD 是 IDD 的 special case，不是並列方法論
- **Case study: che-word-mcp #56 cluster** — empirical proof. 30 findings via 6-AI verify, 5 sub-stack rounds, v3.13.0-v3.13.5 共 6 個 patch release, zero zombie issues. 對照假想 TDD-only 路徑會 leak 29/30 findings 成為使用者後續半年才陸續報的獨立 bug。
- **5 個 Skill = 5 個 Checkpoint** — 人決定，AI 執行
- **這個 plugin 不是什麼** — disclaimer (不是 issue tracker、不是 GitHub workflow automation、不是 ceremony for ceremony 的 process)
- **一句話總結** — 「TDD 跟 SDD 都驗證『對』，只有 IDD 驗證『完』」

### Changed
- **NEW** `plugins/issue-driven-dev/MANIFESTO.md` (~1100 字)
- **README.md** — opening 加 thesis blockquote + link 到 MANIFESTO.md
- **CLAUDE.md** — 「設計哲學」段加 link 到 MANIFESTO.md，標明本段是濃縮版

### Changed
No code changes. New artifact, opt-in reading. Plugin behavior identical to v2.32.0.

### Why now

`che-word-mcp` 是第一個用 IDD 從 v3.0 一路打到 v3.15 的大專案，#56 cluster 是 IDD 解 bug 能力的 empirical demo。把抽象論述跟具體 case study 一起寫進 MANIFESTO，讓 IDD 從「個人 plugin 的 README 描述」升級為「可被引用的 methodology 論述」。

## [2.32.0] - 2026-04-28
### NEW two protocols closing real-world workflow gaps

Two recurring failure modes observed in real IDD usage now have explicit, mandatory protocols.

#### Feature 1: `rules/tagging-collaborators.md` — collaborator-list-driven `@`-mention

Any IDD skill that posts `@xxx` to GitHub must follow a 5-step protocol:

1. **Detect intent** — `--mention <login>` flag or natural-language ("tag X" / "ping X" / "通知 X")
2. **Fetch real list** — `gh api repos/$REPO/collaborators` (+ org members for org repos); training-data / chat-history / git-log handles are forbidden
3. **Resolve** — fuzzy match against `login` + `name` field; unique match → use, otherwise fallback
4. **AskUserQuestion fallback** — 0 or 2+ matches → menu populated from the real collaborator list, not guessed
5. **Verify pre-post** — grep `@\w+` from body, every token must be in the verified set, otherwise abort

Skills with explicit `--mention <login>[,<login>...]` flag: `idd-issue`, `idd-comment`. Other skills (`idd-diagnose`, `idd-implement`, `idd-verify`, `idd-close`) reference the rule from their Step 0 task list — the protocol applies whenever prose contains `@xxx` regardless of how it got there.

Why now: in PsychQuant/contact-book#96 the AI happened to resolve "Hardy" → `@Hardy1Yang` correctly via `gh api`, but only because of careful prompting — without the protocol formalized, the next call could pick a hallucinated handle, ping the wrong person, and the notification can't be undone. GitHub mentions are an irreversible side effect; the rule is mandatory not advisory.

#### Feature 2: `rules/spectra-bridge.md` — preserve and resume spectra context across IDD detours

When `spectra-discuss` is interrupted mid-flow to invoke an IDD skill (e.g. "let me capture this finding to the issue"), the user previously had to re-explain the topic and assumptions on return. New bridge protocol:

- **Step 0.7 Detect** in IDD skills: trigger `SPECTRA_BRIDGE_ACTIVE=1` if any signal fires — `--resume-spectra="<topic>"` flag, `--source` contains `spectra-discuss`, `spectra list --json` shows in-flight changes, or `.claude/state/idd-bridge.json` already exists
- **Step N-1 Bookmark**: write `.claude/state/idd-bridge.json` with `spectra_topic` (verbatim), `issue_number`, `idd_action`, `idd_action_url`, `open_questions[]`, `next_step_hint`
- **Step N Resume Prompt**: emit a clearly-delimited `↩ Resume spectra-discuss` block with a copy-pasteable `/spectra-discuss <topic>...` prompt the user can paste back

`idd-comment` is the first skill to implement the bridge end-to-end (Step 0.7 detect, Step 7 bookmark + resume prompt). `idd-issue` and `idd-edit` will gain it in subsequent versions; the rule defines the contract for all skills.

Hard rules: never auto-invoke `/spectra-discuss` (user controls pacing); never paraphrase `spectra_topic` (user's wording carries assumptions); resume prompt is the actual recovery — bookmark file is convenience.

### Changed
- **NEW `rules/tagging-collaborators.md`** — 5-step protocol with examples, hard rules, implementation contract for skill authors
- **NEW `rules/spectra-bridge.md`** — detection signals, bookmark schema, resume prompt format, future-compat with spectra-side complement
- **`skills/idd-comment/SKILL.md`** — Step 0 task list expanded (added `detect_spectra_context`, `resolve_mentions`, `verify_mentions`, `spectra_bridge_resume`); new Step 0.7 (Detect Spectra Context), Step 2.5 (Resolve Mentions), Step 3.5 (Verify mentions), Step 7 (Spectra Bridge Resume Prompt); two new flags `--mention <login>[,<login>...]` and `--resume-spectra="<topic>"`; two new examples (`Note with mention`, `Spectra-bridge resume`); two new 鐵律 entries
- **`skills/idd-issue/SKILL.md`** — Step 0 task list adds `resolve_mentions`; Step 2 gathers `Stakeholders` (point 5); new Step 2.6 (Resolve Mentions); rule reference in 鐵律
- **`skills/idd-diagnose/SKILL.md`** — Step 0 footnote: tagging in diagnosis comment must follow `rules/tagging-collaborators.md`
- **`skills/idd-implement/SKILL.md`** — same footnote for Implementation Plan / Complete comments
- **`skills/idd-verify/SKILL.md`** — same footnote for Verify findings comments
- **`skills/idd-close/SKILL.md`** — same footnote for Closing Summary comments
- **`CLAUDE.md`** — new top-level sections "Tagging Collaborators (v2.32.0+)" and "Spectra ↔ IDD Bridge (v2.32.0+)"
- **No breaking changes**. Existing skills work as before; the new flags are opt-in. Skills without `--mention` flag still scan body for `@xxx` tokens and route through the protocol — but only when tokens are present, so empty-mention flows are unaffected.

### Why now

Two failure modes observed in PsychQuant/contact-book#96 (the ContactBook cloud-data-layer architecture decision):

1. The AI was asked to "tag Hardy" — happened to resolve correctly only because the human had reflexes to verify; the protocol formalizes what was previously ad-hoc luck.
2. The conversation pivoted: spectra-discuss → idd-comment (to capture findings + tag Hardy) → user wanted to resume spectra-discuss but the session state was lost. The bridge fixes this for the next person running the same flow.

Both gaps are skill-level (every IDD skill that posts to GitHub needs them), so they live as rules and are referenced from each skill's Step 0 — same pattern as `sdd-integration.md` for the spectra escalation protocol.

## [2.31.0] - 2026-04-27
### NEW `idd-config` skill — independent entry for config lifecycle

Filling a long-standing gap where `.claude/issue-driven-dev.local.json` setup, inspection, and predicate debugging were only available as side effects of `idd-issue` Step 0.5.

### Changed
- **NEW `skills/idd-config/SKILL.md`** with four subcommands:
  - `show` (default, no args) — prints resolved target + cwd-aware predicate trace from current `.claude/issue-driven-dev.local.json`. Walks up filesystem to find config (eslint/tsconfig pattern). Reports candidates / groups / `ask_each_time` if present.
  - `init` — interactive first-time setup. Equivalent to `idd-issue` Step 0.5.E fork-aware detection, but as a standalone command so users can configure before creating any issue. Detects fork via `gh repo view --json isFork,parent`; for forks, presents three-option AskUserQuestion (Upstream / Own fork / Both). Writes `github_repo` + optional `tracking_upstream`; "Both" mode writes an ad-hoc `groups[]` with primary + tracking entries.
  - `validate` — JSON schema check + `gh repo view` existence verification + predicate-key sanity (warns on unknown `when.*` keys). Validates groups (exactly one primary), `github_repo` regex, etc.
  - `which` — dry-run resolution at current cwd. Shows step-by-step trace of Phase 0.5 (path-class predicates) and optionally Phase 2.5 (with `--title <T>` / `--label <L>` to evaluate content predicates). Helps debug "why did `idd-issue` route to repo X instead of Y?"

- **No breaking changes**. `idd-issue` Step 0.5.E fork-detection is retained for users who prefer creating their first issue immediately. A future v3.0 may delegate to `idd-config init`, but v2.31.0 keeps both entry points functional.

### Why now

The IDD plugin's monorepo + multi-repo support has grown sophisticated since v2.25.0 (six-mechanism resolution, candidates with predicates, groups with cross-link tracking), but config management remained tied to `idd-issue`. Real-world use cases:

- Setting up a new project where you want to verify config before filing the first issue
- Debugging "this issue went to the wrong repo" by replaying the resolution at cwd
- Validating a hand-edited config file
- Inspecting which candidate matches at the current cwd

These all required either side-effect-creating `idd-issue` runs or manual JSON editing. `idd-config` is the missing read/inspect/init layer.

## [2.30.0] - 2026-04-26
### Data preservation hard rule in `idd-issue` + extra-requirements channel in `idd-implement`

Two long-standing gaps surfaced during real-world IDD use on the gukai spondylodiscitis project (`kiki830621/collaboration_gukai#4` and `#5`). Both were fixed as additive changes — existing flows are untouched.

### Changed
- **`idd-issue` — 資料保留鐵律 (HARD RULE)**

  - Step 1 renamed `讀取來源（如果是 .docx）` → `讀取來源並保留所有原始資料` with explicit hardline: "all source attachments uploaded to attachments release by default, without asking; only fall back to manual when MCP extraction is technically impossible".
  - New **Source Type Adapter** table covers `.docx` / `.pdf` / Telegram / Apple Mail / Apple Notes / pasted text / mixed.
  - New **Telegram source 專屬流程**: when chat_id / Telegram URL is referenced, enumerate all attachments via MCP `get_chat_history`, attempt download (or fallback to a specific manual-save prompt listing timestamp + sender + caption + suggested filename — never silently skip).
  - Step 4 renamed `附加圖片（如果有）` → `附加所有原始素材（鐵律：預設全保留）` with mandatory **violation checklist** at the end.
  - **Closes a recurring gap**: SNQ issue (`#5`) PDF + 2 timeline images were originally dropped because skill default was "ask first" — should have been "preserve first".

- **`idd-implement` — `--with-skill` + `--extra` flags**

  - `argument-hint` extended: `[--with-skill <skill>] [--extra '<requirement>']` (e.g., `'#42 --with-skill perspective-writer --extra ''500-800 chars'''`).
  - New **Step 1.5: Resolve Extra Requirements** merges three sources: explicit `--with-skill` flag, `--extra "<text>"` free-text constraint, and auto-detected `透過 X` / `via X` patterns from diagnosis Strategy.
  - Step 2 Implementation Plan template gains optional `### Extra Requirements` section listing the resolved with-skill + extra-text.
  - Step 3 GREEN phase: when `with_skill` set, calls `Skill(skill=...)` instead of direct Edit/Write; sub-skill completes the file write, then idd-implement resumes commit + checklist update.
  - Spectra-warranted complexity (SDD path) ignores `--with-skill` — `spectra-apply` already has sub-skill orchestration; no double-layering.
  - **First-class formalization** of the idd-implement × perspective-writer integration pattern that emerged in `#4` — previously hacked via free-form Implementation Plan bullet, now skill-supported.

### Why these changes

| Gap before 2.30.0 | Failure mode | Fix |
|-------------------|--------------|-----|
| Skill default = "ask before attaching" | Easy to skip when AI plays safe — preservation duty silently shifted to user | Default flipped to "preserve all" with explicit violation checklist |
| No documented way to inject "use skill X for execution" | Each prose deliverable hacks Implementation Plan bullets to mention X-skill — no checklist-level verification that X actually ran | First-class flag + Step 1.5 resolution + Step 5 sync verifies sub-skill invocation |

### Backwards compatibility

- All changes additive. Existing flows without Telegram sources / without `--with-skill` flag behave identically to 2.29.0.
- Configs not touched. `pr_policy`, `candidates`, `groups` semantics unchanged.

---

## [2.29.0] - 2026-04-26
### Two-tier checklist gate in `idd-close`

The structural gate (v2.17.0) catches **honest forgetting** — you can't close an issue with unticked `- [ ]` items. But it can't catch **motivated cheating** — ticking `- [x]` without doing the work. v2.29.0 adds a semantic gate to address the second failure mode.

### Changed
- **`idd-close` Step 1.6 — Semantic Checklist Gate** — for each `- [x]` bullet that passed the structural gate, classify against three keyword patterns and verify the underlying artifact exists:

  | Pattern | Check |
  |---------|-------|
  | Contains test/regression/coverage keywords | `git log --grep="#${N}" -- '**/*test*' ...` must return ≥1 commit |
  | References `openspec/changes/<name>/{proposal,design,tasks,spec}.md` | File must exist |
  | Contains backtick-wrapped file path with extension | Path must appear in `git log --grep="#${N}" --name-only` |
  | No recognized pattern | Skip (counted as "unchecked") |

- **Warn-only behavior** — semantic gate doesn't hard-refuse like the structural gate. Keyword extraction has false positives (e.g. test commit landed in earlier PR), so warnings are presented with AskUserQuestion three-way choice: proceed / investigate / edit checklist.

- **`idd-close` Step 0.5 task list** — added `semantic_gate_check` entry.

- **`idd-close` 鐵律 section** — added "打勾沒做要 warn" rule alongside "沒打勾就不關".

- **`CLAUDE.md` Two-Tier Gate section** — new section comparing structural vs semantic gate, and explicit falsifiability claim that IDD is now strict superset of TDD ∪ SDD on the falsifiability surface (outcome verification inherited from inner methodologies + IDD-only audit-level semantic check).

### Why warn-only and not hard-refuse

The structural gate can hard-refuse because false positives are impossible — either a `- [ ]` exists or it doesn't. The semantic gate works on heuristics: a test commit might legitimately live in a prior PR not referencing #NNN, an external file might be modified by tooling, etc. A hard-refuse on heuristic check would block legitimate closes. The warn + AskUserQuestion approach surfaces the suspicious signal, makes the user explicitly acknowledge it, and lets them either proceed (confirming the heuristic was wrong) or investigate (treating the heuristic as right).

### Changed
No breaking changes. Issues that previously closed cleanly under v2.28.0 still close cleanly under v2.29.0 — the semantic gate adds a warning step but doesn't refuse anything. Issues with semantic mismatches now surface them at close time instead of staying hidden.

## [2.28.0] - 2026-04-26
### `idd-all` SDD path is now unattended

`idd-all` is a fire-and-forget orchestrator — it assumes nobody is watching. Previously the SDD path called `spectra-discuss` and `spectra-apply` directly, with two problems:

1. The middle step `spectra-propose` was missing from the chain.
2. Each spectra skill's built-in `AskUserQuestion` checkpoints would stall the pipeline — `spectra-discuss` paces conversation one question at a time; `spectra-propose` Step 10 asks "Park or Apply?" defaulting to Park; `spectra-apply` Step 4 asks for continue-confirmation.

This release makes the SDD path a true unattended chain.

### Changed
- **`idd-all` Phase 3b** — rewrote as four sub-steps: capture issue context, then call `spectra-discuss` / `spectra-propose` / `spectra-apply` in sequence. Each call passes a long `args` string with explicit instructions to suppress `AskUserQuestion` checkpoints and produce a structured marker line (`Conclusion: ...` / `Change: ...`) that the next step parses.
- **`spectra-propose` chaining** — `idd-all` calls `spectra-apply` itself rather than letting `spectra-propose` chain. This respects the architectural `NEVER invoke /spectra-apply` guardrail in spectra-propose (L267) while still achieving end-to-end automation.
- **New core principle: "Unattended assumption"** — added to idd-all's core principles. Sub-skills' attended-by-default behavior is correct for solo use; idd-all is the one promising "unattended", so it's idd-all's responsibility to override via args, not by modifying sub-skill plugins.
- **Failure modes table** — added entries for spectra-discuss / propose / apply specific failure modes (missing marker line, unrecoverable validation, unfinished tasks).
- **Complexity table footnote** — clarifies that users wanting attended SDD discussion should run `/spectra-discuss` etc. manually, not `idd-all`.
- **CLAUDE.md workflow diagram** — annotated to show idd-all's SDD path is unattended chain; manual SDD path remains attended.

### Changed
No breaking changes for users running `idd-all` from scratch — the SDD path now finishes more reliably (no longer stalls on `Park or Apply` prompt). If you were relying on the prior "abort on user input needed" escape hatch, you now need to run the SDD skills manually instead of `idd-all`. The trade-off matches the orchestrator's stated promise: pick `idd-all` for fire-and-forget, pick manual `/spectra-*` for attended alignment.

## [2.27.0] - 2026-04-26
### PR vs Direct-commit path routing

`idd-implement` now explicitly resolves between two execution paths instead of implicitly following whatever branch the user happens to be on:

- **PR path** — feature branch `idd/<N>-<slug>` + push + `gh pr create`
- **Direct-commit path** — current branch, no push, no PR

Resolution priority (highest first):

1. `--pr` / `--no-pr` flag (per-invocation)
2. Fork detection (`gh repo view --json isFork` true → forced PR path)
3. `pr_policy` config field (`always` / `never` / `ask`, default `ask`)

### Changed
- **`idd-implement`** — added Phase 0.5 PR Decision step; added Phase 5.5 PR creation (idempotent — skips if PR for branch already open). New `--pr` / `--no-pr` flags. argument-hint updated.
- **`idd-close`** — added Step 1.5 PR Gate Check. Refuses close when an open PR references the issue, instructing the user to merge first. Mirrors the "no `--force`" philosophy of the checklist gate.
- **`idd-all`** — explicitly enforces `--pr` when calling `idd-implement` (orchestrator path always = PR path, overriding `pr_policy`). Phase 3a doc clarifies this. Phase 5.5 idempotency means orchestrator's Phase 5 PR creation no longer collides with idd-implement's.
- **Config schema** — new optional `pr_policy` field in `.claude/issue-driven-dev.local.json`. Backward compatible (absent = `ask`).
- **`references/pr-flow.md`** — new canonical contract document. Branch naming, PR body template, decision matrix, all in one place. Three SKILLs link here instead of duplicating.
- **`references/config-protocol.md`** — added `pr_policy` documentation to schema and field reference.
- **`CLAUDE.md`** — new "PR vs Direct-commit Path" section describing the routing.

### Changed
No breaking changes. Existing configs without `pr_policy` default to `ask` (prompts on first `idd-implement`). Existing `idd-all` users see no behavior change — it always was PR-only; this release just makes that contract explicit and consistent with the new flag system.

If you want to opt out of the prompt on a solo / personal repo:

```json
{
  "github_repo": "owner/repo",
  "pr_policy": "never"
}
```

If you want to enforce PR for a team repo:

```json
{
  "github_repo": "owner/repo",
  "pr_policy": "always"
}
```

## [2.26.0] - 2026-04-25
(prior history not migrated to CHANGELOG; see git log)
