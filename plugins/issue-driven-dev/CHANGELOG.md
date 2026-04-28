# Changelog

## 2.33.0 — 2026-04-28

### NEW: `MANIFESTO.md` — methodology thesis

Formalizes the IDD methodology argument as a standalone document, separating "what the plugin does" (README) from "why this is a methodology not a workflow tool" (MANIFESTO).

### Thesis

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

### Changes

- **NEW** `plugins/issue-driven-dev/MANIFESTO.md` (~1100 字)
- **README.md** — opening 加 thesis blockquote + link 到 MANIFESTO.md
- **CLAUDE.md** — 「設計哲學」段加 link 到 MANIFESTO.md，標明本段是濃縮版

### Migration

No code changes. New artifact, opt-in reading. Plugin behavior identical to v2.32.0.

### Why now

`che-word-mcp` 是第一個用 IDD 從 v3.0 一路打到 v3.15 的大專案，#56 cluster 是 IDD 解 bug 能力的 empirical demo。把抽象論述跟具體 case study 一起寫進 MANIFESTO，讓 IDD 從「個人 plugin 的 README 描述」升級為「可被引用的 methodology 論述」。

## 2.32.0 — 2026-04-28

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

### Changes

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

## 2.31.0 — 2026-04-27

### NEW `idd-config` skill — independent entry for config lifecycle

Filling a long-standing gap where `.claude/issue-driven-dev.local.json` setup, inspection, and predicate debugging were only available as side effects of `idd-issue` Step 0.5.

### Changes

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

## 2.30.0 — 2026-04-26

### Data preservation hard rule in `idd-issue` + extra-requirements channel in `idd-implement`

Two long-standing gaps surfaced during real-world IDD use on the gukai spondylodiscitis project (`kiki830621/collaboration_gukai#4` and `#5`). Both were fixed as additive changes — existing flows are untouched.

### Changes

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

## 2.29.0 — 2026-04-26

### Two-tier checklist gate in `idd-close`

The structural gate (v2.17.0) catches **honest forgetting** — you can't close an issue with unticked `- [ ]` items. But it can't catch **motivated cheating** — ticking `- [x]` without doing the work. v2.29.0 adds a semantic gate to address the second failure mode.

### Changes

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

### Migration

No breaking changes. Issues that previously closed cleanly under v2.28.0 still close cleanly under v2.29.0 — the semantic gate adds a warning step but doesn't refuse anything. Issues with semantic mismatches now surface them at close time instead of staying hidden.

## 2.28.0 — 2026-04-26

### `idd-all` SDD path is now unattended

`idd-all` is a fire-and-forget orchestrator — it assumes nobody is watching. Previously the SDD path called `spectra-discuss` and `spectra-apply` directly, with two problems:

1. The middle step `spectra-propose` was missing from the chain.
2. Each spectra skill's built-in `AskUserQuestion` checkpoints would stall the pipeline — `spectra-discuss` paces conversation one question at a time; `spectra-propose` Step 10 asks "Park or Apply?" defaulting to Park; `spectra-apply` Step 4 asks for continue-confirmation.

This release makes the SDD path a true unattended chain.

### Changes

- **`idd-all` Phase 3b** — rewrote as four sub-steps: capture issue context, then call `spectra-discuss` / `spectra-propose` / `spectra-apply` in sequence. Each call passes a long `args` string with explicit instructions to suppress `AskUserQuestion` checkpoints and produce a structured marker line (`Conclusion: ...` / `Change: ...`) that the next step parses.
- **`spectra-propose` chaining** — `idd-all` calls `spectra-apply` itself rather than letting `spectra-propose` chain. This respects the architectural `NEVER invoke /spectra-apply` guardrail in spectra-propose (L267) while still achieving end-to-end automation.
- **New core principle: "Unattended assumption"** — added to idd-all's core principles. Sub-skills' attended-by-default behavior is correct for solo use; idd-all is the one promising "unattended", so it's idd-all's responsibility to override via args, not by modifying sub-skill plugins.
- **Failure modes table** — added entries for spectra-discuss / propose / apply specific failure modes (missing marker line, unrecoverable validation, unfinished tasks).
- **Complexity table footnote** — clarifies that users wanting attended SDD discussion should run `/spectra-discuss` etc. manually, not `idd-all`.
- **CLAUDE.md workflow diagram** — annotated to show idd-all's SDD path is unattended chain; manual SDD path remains attended.

### Migration

No breaking changes for users running `idd-all` from scratch — the SDD path now finishes more reliably (no longer stalls on `Park or Apply` prompt). If you were relying on the prior "abort on user input needed" escape hatch, you now need to run the SDD skills manually instead of `idd-all`. The trade-off matches the orchestrator's stated promise: pick `idd-all` for fire-and-forget, pick manual `/spectra-*` for attended alignment.

## 2.27.0 — 2026-04-26

### PR vs Direct-commit path routing

`idd-implement` now explicitly resolves between two execution paths instead of implicitly following whatever branch the user happens to be on:

- **PR path** — feature branch `idd/<N>-<slug>` + push + `gh pr create`
- **Direct-commit path** — current branch, no push, no PR

Resolution priority (highest first):

1. `--pr` / `--no-pr` flag (per-invocation)
2. Fork detection (`gh repo view --json isFork` true → forced PR path)
3. `pr_policy` config field (`always` / `never` / `ask`, default `ask`)

### Changes

- **`idd-implement`** — added Phase 0.5 PR Decision step; added Phase 5.5 PR creation (idempotent — skips if PR for branch already open). New `--pr` / `--no-pr` flags. argument-hint updated.
- **`idd-close`** — added Step 1.5 PR Gate Check. Refuses close when an open PR references the issue, instructing the user to merge first. Mirrors the "no `--force`" philosophy of the checklist gate.
- **`idd-all`** — explicitly enforces `--pr` when calling `idd-implement` (orchestrator path always = PR path, overriding `pr_policy`). Phase 3a doc clarifies this. Phase 5.5 idempotency means orchestrator's Phase 5 PR creation no longer collides with idd-implement's.
- **Config schema** — new optional `pr_policy` field in `.claude/issue-driven-dev.local.json`. Backward compatible (absent = `ask`).
- **`references/pr-flow.md`** — new canonical contract document. Branch naming, PR body template, decision matrix, all in one place. Three SKILLs link here instead of duplicating.
- **`references/config-protocol.md`** — added `pr_policy` documentation to schema and field reference.
- **`CLAUDE.md`** — new "PR vs Direct-commit Path" section describing the routing.

### Migration

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

## 2.26.0 — 2026-04-25

(prior history not migrated to CHANGELOG; see git log)
