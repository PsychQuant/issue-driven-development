---
name: idd-verify
description: |
  驗證 uncommitted/committed code 是否滿足 Issue 的所有要求。
  驗證 uncommitted/committed code 是否滿足 Issue 的所有要求。
  支援 Codex CLI、claude -p、Gemini CLI 做獨立驗證，可三引擎平行。
  Use when: 實作完成後、commit 之前。
  防止的失敗：自以為修好了，沒跑驗證。
argument-hint: "#issue [engine] [--loop [N]] e.g. '#42', '#42 claude', '#42 all', '#42 --loop'"
allowed-tools:
  - Bash(codex:*)
  - Bash(claude:*)
  - Bash(gemini:*)
  - Bash(git:*)
  - Bash(gh:*)
  - Bash(mktemp:*)
  - Bash(rm:*)
  - Bash(wc:*)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# /idd-verify — 驗證實作

用獨立的 AI 驗證 code 是否滿足 issue 要求。Claude 修、獨立 AI 驗。

## 核心原則

> 「應該沒問題」不是驗證。跑了驗證、看了輸出、確認通過，才是驗證。

## 參數

```
/idd-verify #42                     → Codex + claude 平行驗證（預設 both）
/idd-verify #42 codex               → 只用 Codex
/idd-verify #42 claude              → 只用 claude -p
/idd-verify #42 gemini              → 只用 Gemini CLI
/idd-verify #42 all                 → Codex + claude + Gemini 三引擎平行
/idd-verify #42 --loop              → 驗證 + ralph-loop 自動修復迴圈
/idd-verify                         → 通用 code review（無 issue）
```

## Configuration

讀取 `.claude/issue-driven-dev.local.md` frontmatter。如不存在，詢問 `github_repo` 並建立。

## 驗證引擎

| Engine | 工具 | 模型 | 優勢 | 需求 |
|--------|------|------|------|------|
| `both`（預設） | Codex + claude | gpt-5.4 + Opus 4.6 | 雙引擎交叉比對 | 兩者都需要 |
| `codex` | Codex CLI | gpt-5.4 | ~1M context、深度推理 | Codex CLI + ChatGPT Pro |
| `claude` | claude -p | Opus 4.6 | 可讀本地檔案、最強推理 | Claude Code 已安裝 |
| `gemini` | Gemini CLI | 最新可用模型 | 1M context、免費 | Gemini CLI 已安裝 |
| `all` | 三個都跑 | — | 三引擎平行、覆蓋最廣 | 三者都需要 |

## Effort Levels

未指定時，依 diff 大小自動選擇 effort level。

| 改動規模 | Level |
|---------|-------|
| <50 lines | `medium` |
| 50-200 lines | `high` |
| >200 lines | `max`（預設） |

### Effort 設定方式（三種 engine 語法不同）

| Engine | 語法 | 可用值 |
|--------|------|-------|
| **Codex CLI** | `-c "model_reasoning_effort=\"$EFFORT\""` | `medium`, `high`, `xhigh` |
| **claude -p** | `--effort $EFFORT` | `low`, `medium`, `high`, `max`（`max` 限 Opus 4.6） |
| **Gemini CLI** | `-p` prompt 中指定 | Gemini 無 effort 參數，預設用最高推理 |

> **注意**：三者的 level 名稱不同！
> 自動選擇：`大改動 → Codex xhigh / claude max / Gemini 預設`。

## Execution（單次模式）

### Step 1: 檢查是否有改動

```bash
git status --short
git diff --stat          # uncommitted changes
git diff --stat HEAD~1   # last commit (if just committed)
```

如果沒有 uncommitted 也沒有 recent commit 改動，通知使用者並停止。

> **重要**：如果改動已 committed（`idd-implement` 之後），用 `git diff HEAD~1` 取代 `git diff`。
> 範本中的 `=== CHANGES ===` 區塊也要改用 `git diff HEAD~1`。

### Step 2: 取得 Issue 內容（如有 #NNN）

```bash
gh issue view $NUMBER --repo $GITHUB_REPO --json title,body,labels
```

### Step 3: 執行驗證

#### Engine: Codex

**Issue-focused（有 #NNN）**：

```bash
PROMPT_FILE=$(mktemp /tmp/codex_review_XXXXX)

{
  echo "You are reviewing code changes for GitHub Issue #$NUMBER: $TITLE"
  echo ""
  echo "Issue requirements:"
  echo "$BODY"
  echo ""
  echo "YOUR PRIMARY TASK:"
  echo "1. Go through EACH requirement in the issue"
  echo "2. For each requirement, determine if it is addressed"
  echo "3. List: FULLY addressed, PARTIALLY addressed, NOT addressed"
  echo "4. Flag unrelated changes (scope creep)"
  echo "5. Check for regressions or new bugs introduced"
  echo ""
  echo "=== UNCOMMITTED CHANGES ==="
  git diff
  git diff --cached
} > "$PROMPT_FILE"

codex review \
  -c 'model="gpt-5.4"' \
  -c "model_reasoning_effort=\"$EFFORT\"" \
  - < "$PROMPT_FILE"

rm "$PROMPT_FILE"
```

**General（無 #NNN）**：

```bash
codex review \
  -c 'model="gpt-5.4"' \
  -c "model_reasoning_effort=\"$EFFORT\"" \
  --uncommitted
```

#### Engine: claude

```bash
PROMPT_FILE=$(mktemp /tmp/claude_review_XXXXX)

{
  echo "You are reviewing code changes for GitHub Issue #$NUMBER: $TITLE"
  echo ""
  echo "Issue requirements:"
  echo "$BODY"
  echo ""
  echo "YOUR PRIMARY TASK:"
  echo "1. Go through EACH requirement in the issue"
  echo "2. For each requirement: FULLY / PARTIALLY / NOT addressed"
  echo "3. Flag scope creep and regressions"
  echo "4. Output as structured markdown"
  echo ""
  echo "=== UNCOMMITTED CHANGES ==="
  git diff
  git diff --cached
} > "$PROMPT_FILE"

claude -p "$(cat $PROMPT_FILE)" --output-format text --max-turns 10 --effort $EFFORT

rm "$PROMPT_FILE"
```

#### Engine: gemini

```bash
PROMPT_FILE=$(mktemp /tmp/gemini_review_XXXXX)

{
  echo "You are reviewing code changes for GitHub Issue #$NUMBER: $TITLE"
  echo ""
  echo "Issue requirements:"
  echo "$BODY"
  echo ""
  echo "YOUR PRIMARY TASK:"
  echo "1. Go through EACH requirement in the issue"
  echo "2. For each requirement: FULLY / PARTIALLY / NOT addressed"
  echo "3. Flag scope creep and regressions"
  echo "4. Output as structured markdown with [P1] [P2] severity tags"
  echo ""
  echo "=== UNCOMMITTED CHANGES ==="
  git diff
  git diff --cached
} > "$PROMPT_FILE"

gemini -p "$(cat $PROMPT_FILE)" --approval-mode plan

rm "$PROMPT_FILE"
```

> **注意**：Gemini CLI 用 `--approval-mode plan` 確保只讀不改。

#### Engine: both

平行執行 Codex 和 claude（兩個 `run_in_background`），合併 findings（去重），標註來源。

#### Engine: all（推薦）

**三引擎平行**：同時啟動 Codex、claude -p、Gemini CLI，全部 `run_in_background`。

```
┌─ Codex (gpt-5.4, xhigh) ──────┐
│                                │
├─ claude -p (Opus 4.6, max) ────┤ → 合併 findings → 去重 → 標註來源
│                                │
└─ Gemini CLI (2.5 Pro, plan) ───┘
```

執行方式：在同一個訊息中發出三個 `Bash(run_in_background=true)` 呼叫，等全部完成後合併結果。

合併規則：
- 相同 finding（相同檔案 + 相似描述）→ 只保留一個，標註 `[codex+claude+gemini]`
- 不同 finding → 全部保留，各自標註來源
- severity 以最高者為準（P1 > P2 > P3）

### Step 4: 呈現結果

```markdown
## Verify: #NNN — {title}

### Engine
{codex / claude / both}

### 要求覆蓋率
X / Y requirements addressed

### Findings
- [engine] finding description

### Scope Check
{有沒有超出 issue 範圍的改動}
```

### Step 5: Comment 驗證結果到 issue

**每次驗證結果都 comment 到 issue**（含 loop 的每輪）：

```bash
gh issue comment $NUMBER --repo $GITHUB_REPO --body "$VERIFY_REPORT"
```

這樣 issue 上會有完整的驗證軌跡：哪些通過、哪些沒通過、用了什麼 engine。

### Step 6: 後續動作

| 結果 | 動作 |
|------|------|
| 全部通過 | 提示 `idd-close` |
| 有 findings | 提示修正後再跑，或用 `--loop` 自動修 |
| Scope creep | 提示開新 issue 或 revert |

---

## Loop 模式（ralph-loop 驅動）

加上 `--loop` 後，用 `/ralph-loop:ralph-loop` 驅動驗證-修復迴圈：

```
ralph-loop 啟動 → verify(both) → findings → 修復 → verify(both) → ... → 0 findings → <promise>
```

### 啟動方式

當偵測到 `--loop` 參數時，呼叫：

```
/ralph-loop:ralph-loop "針對 Issue #NNN 執行驗證-修復迴圈：
1. 用 Codex + claude -p 平行驗證（run_in_background）
2. 合併 findings，按 severity 排序
3. 修復所有 IN_SCOPE findings（不修 scope 外的）
4. 每次修復後 commit（引用 #NNN）
5. 重複直到 0 findings
只修 #NNN 範圍內的問題。超出範圍的標 SKIPPED。"
--completion-promise "All findings from both Codex and claude verification have been resolved. 0 findings remaining."
--max-iterations 5
```

### 每輪流程

1. Codex + claude 平行驗證（兩個 `run_in_background` Bash 呼叫）
2. 等兩個結果回來，合併 findings
3. 分類：IN_SCOPE → 修復；OUT_OF_SCOPE → SKIPPED
4. 修復 + commit
5. ralph-loop 的 Stop hook 自動重新餵入 prompt

### 終止條件

| 條件 | 行為 |
|------|------|
| 0 findings | 輸出 `<promise>All findings...resolved</promise>`，ralph-loop 結束 |
| 達到 max-iterations | ralph-loop 自動停止 |
| 用戶 `/cancel-ralph` | 手動停止 |

### 安全設計

- **修復者和驗證者是不同的 AI**：Claude 修、Codex + claude -p 驗。
- **Scope 守衛**：只修 #NNN 相關 findings。
- **max-iterations 5**：超過 = 可能是架構問題，不是 bug。
- **每輪 commit**：可以 revert 任何一輪的修復。

---

## 鐵律

- **不跳過驗證**。「看起來對了」不算。
- **有 findings 就不 commit**。先修，再 verify，再 commit。
- **Verify 不是自己驗證自己**。用獨立的 AI 來檢查，避免自我盲點。
- **Loop 中不修 scope 外的問題**。不在 #NNN 範圍的 → SKIPPED。

## Auto-Update

Verify comment 完成後，自動執行 `idd-update` 更新 issue body 的 Current Status（phase → `verified` 或 `needs-fix`）。

## Next Step

驗證通過後，進入 `idd-close`：

```
/issue-driven-dev:idd-close #NNN
```
