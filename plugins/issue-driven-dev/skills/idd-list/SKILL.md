---
name: idd-list
description: |
  列出 GitHub issues（預設 open），顯示每個 issue 的 IDD phase 和建議 next action。
  按 config-protocol 解析 target repo(walk-up cascading + --target flag),支援 --state / --label / --limit filter。
  Use when: 開工前 triage、想知道有哪些還沒處理完的 issue、回到專案看進度。
  防止的失敗：不知道有什麼要做、重複 diagnose 已處理的 issue、漏掉卡在 verify 的 issue。
argument-hint: "[--state open|closed|all] [--label <name>] [--limit N] [--target owner/repo]"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
  - Read
---

# /idd-list — 列出 Issues

快速看 repo 有哪些 issue 在 IDD workflow 的哪個階段，並顯示每個 issue 的下一步。

## 核心原則

> 開工前先看 open issues — 避免重複 diagnose、漏掉卡 verify 的、或不知從哪開始。

## Configuration

按 [config-protocol](../../references/config-protocol.md) 解析 target repo。priority(由高到低):

1. `--repo owner/repo` flag (per-invocation override)
2. Walk-up `.claude/issue-driven-dev.local.json`(從 cwd 往上找,first-match wins)
3. Path predicates (`when.path_contains` / `path_matches` / `git_remote_matches` 等)在 candidates / groups 上自動匹配
4. `ask_each_time: true` → AskUserQuestion menu
5. Fallback: `gh repo view --json nameWithOwner -q .nameWithOwner` 偵測 git remote
6. 偵測不到 → 要求明確 `--repo`

**注意**:`idd-list` 不會評估內容類 predicate(`title_matches` / `label_in` 等),因為這個 skill 不蒐集 issue title/labels。只 path / git 類 predicate 會生效。

**Group 行為**:若解析結果是 group,預設只列 primary repo 的 issues;加 `--all-tracked` 可同時列所有 tracking repos。

## Execution

### Step 0: Bootstrap Stage Task List（強制)

**在動任何事之前**先用 `TaskCreate` 為這個 stage 建 todo list,確保每個 sub-step 都被追蹤:

```
TaskCreate(name="parse_args", description="Parse --state / --label / --limit / --repo flags 並 fallback 到 .claude/issue-driven-dev.local.json")
TaskCreate(name="fetch_issues", description="gh issue list 取 number/title/state/labels/updatedAt/body/comments")
TaskCreate(name="extract_phase", description="從每個 issue body 的 Current Status → **Phase**: 抽出 phase；fallback 掃 comments 標題推斷")
TaskCreate(name="format_output", description="組 #N [phase] title 表格 + footer 統計")
TaskCreate(name="report_and_suggest_next", description="輸出 table 並列出每個 issue 的 Suggested next 命令")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。**TaskCreate 清單 = 真實的步驟清單；任何寫在 skill 裡但沒列進 TaskCreate 的步驟，都視為 skill 的 bug，必須補進 Task 清單。**

---

### Step 1: Parse Arguments

| Flag | 預設 | 說明 |
|------|------|------|
| `--state` | `open` | `open` / `closed` / `all` |
| `--label` | _(none)_ | 單一 label filter |
| `--limit` | `20` | 最多顯示筆數 |
| `--repo` | _(from config)_ | 覆寫 config 的 repo |

### Step 2: Fetch Issues

```bash
gh issue list \
    --repo "$GITHUB_REPO" \
    --state "$STATE" \
    --limit "$LIMIT" \
    ${LABEL:+--label "$LABEL"} \
    --json number,title,state,labels,updatedAt,body,comments
```

按 `updatedAt` desc 排序（最新活動在最上面）。

### Step 3: Extract Phase

每個 issue 的 body 由 `idd-update` 管理的 `## Current Status` 區塊含 `**Phase**: {phase}` 行。優先從這裡讀。

Phase 值（與 `idd-update` 一致）：

- `created` — 新建，無 diagnosis
- `diagnosed` — 已 diagnose
- `planning` — 有 implementation plan
- `implemented` — 有 implementation complete
- `verified` — verify 通過
- `needs-fix` — verify 失敗，待修
- `closed` — 已結案

**解析策略**：

1. 掃 body 尋找 `**Phase**:` 行，取第一個 match 的值
2. 找不到 → 掃 comments 的標題推斷（`## Diagnosis` → `diagnosed`，`## Implementation Complete` → `implemented`，`## Verify (PASS)` → `verified`，`## Verify (FAIL)` → `needs-fix`，`## Closing Summary` → `closed`）
3. 仍推不出 → 顯示 `(no phase)`（legacy issue，建議手動 `/idd-update`）

### Step 4: Format Output

```
Repo: PsychQuant/che-apple-mail-mcp  (state: open, limit: 20)

#8   [verified]    bug: 中文檔名附件導致 AppleScript error (-2741)
     labels: bug           | updated 1h ago  | 3 comments

#6   [diagnosed]   fix: create_draft AppleScript error -2741 on multiline CJK
     labels: bug, cjk      | updated 22d ago | 0 comments

───────────────────────────────────────────────────────────────
2 open issue(s) — 1 verified, 1 diagnosed
```

格式規則：

- `#N` 左對齊，寬度 4（單 digit #N 也對齊）
- `[phase]` 後接 title，title 不截斷
- Labels 按字母序，逗號分隔，無 label 則省略該欄
- 時間顯示相對值（`2h ago`, `3d ago`, `2mo ago`）
- Footer 顯示總數 + phase 分佈

若沒有 issue，顯示 `No issues found. 🎉`。

### Step 5: Suggest Next Actions

Footer 之後列出每個 issue 的建議下一步：

```
Suggested next:
  #8 [verified]  → /idd-close #8
  #6 [diagnosed] → /idd-implement #6
```

對應規則：

| Phase | Next |
|-------|------|
| `created` | `/idd-diagnose #N` |
| `diagnosed` | `/idd-implement #N` |
| `planning` | `/idd-implement #N` |
| `implemented` | `/idd-verify #N` |
| `verified` | `/idd-close #N` |
| `needs-fix` | `/idd-diagnose #N`（重新分析為什麼 verify fail）|
| `closed` | _(略)_ |
| `(no phase)` | `/idd-update #N` 先同步狀態，再 `/idd-diagnose #N` |

## 鐵律

- **不亂猜 repo**。偵測不到就明確要求 `--repo`，不 fallback 到「最近用的 repo」。
- **不截斷 title**。IDD issue 標題通常是唯一的語意標記，截斷等於丟資訊。
- **按 updatedAt 排序**，不是 createdAt。最近被動的 issue 通常最該注意。
- **Phase 推斷失敗不是錯誤**。顯示 `(no phase)` 讓使用者自己決定，並建議先跑 `idd-update`。

## 手動呼叫

```
/issue-driven-dev:idd-list                       # 當前 repo 的 open issues
/issue-driven-dev:idd-list --state all           # 所有狀態
/issue-driven-dev:idd-list --label bug --limit 5 # 只看 bug label
/issue-driven-dev:idd-list --repo owner/name     # 覆寫 repo
```

## 與 `gh issue list` 的差異

| 能力 | `gh issue list` | `idd-list` |
|------|-----------------|-----------|
| 原始 issue metadata | ✅ | ✅ |
| IDD phase 顯示 | ❌ | ✅ |
| 建議 next action | ❌ | ✅ |
| 自動用 config 的 repo | ❌ | ✅ |
| Phase 分佈統計 | ❌ | ✅ |

`idd-list` 不是 `gh issue list` 的替代，是 **IDD workflow 視角的增強包裝**。若只想要原始 issue 列表，直接用 `gh issue list` 更輕量。
