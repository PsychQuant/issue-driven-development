# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
