---
name: idd-verify
description: |
  驗證 uncommitted/committed code 是否滿足 Issue 的所有要求。
  支援 Codex CLI 或 claude -p 做獨立驗證。可 --loop 自動修到通過。
  Use when: 實作完成後、commit 之前。
  防止的失敗：自以為修好了，沒跑驗證。
argument-hint: "#issue [engine] [--loop [N]] e.g. '#42', '#42 claude', '#42 --loop', '#42 both --loop 5'"
allowed-tools:
  - Bash(codex:*)
  - Bash(claude:*)
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
/idd-verify #42                     → Codex 驗證（預設）
/idd-verify #42 claude              → claude -p 驗證
/idd-verify #42 both                → 兩個都跑，交叉比對
/idd-verify #42 --loop              → 驗證-修復迴圈（預設最多 3 輪）
/idd-verify #42 --loop 5            → 最多 5 輪
/idd-verify #42 claude --loop       → 用 claude -p + 迴圈
/idd-verify                         → 通用 code review（無 issue）
```

## Configuration

讀取 `.claude/issue-driven-dev.local.md` frontmatter。如不存在，詢問 `github_repo` 並建立。

## 驗證引擎

| Engine | 工具 | 優勢 | 需求 |
|--------|------|------|------|
| `codex`（預設） | Codex CLI + gpt-5.4 | ~1M context、深度推理 | Codex CLI + ChatGPT Pro |
| `claude` | claude -p | 不需額外工具、可讀本地檔案 | Claude Code 已安裝 |
| `both` | 兩個都跑 | 交叉比對，覆蓋更廣 | 兩者都需要 |

## Effort Levels

| Level | 適用場景 |
|-------|---------|
| `medium` | 小改動 (<50 lines) |
| `high` | 中等改動 (50-200 lines) |
| `xhigh` | 大改動 (>200 lines，預設) |

未指定時，依 diff 大小自動選擇。Codex 追加 `fast` 使用低延遲模式。

## Execution（單次模式）

### Step 1: 檢查是否有改動

```bash
git status --short
git diff --stat
```

如果沒有改動，通知使用者並停止。

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

claude -p "$(cat $PROMPT_FILE)" --output-format text --max-turns 3

rm "$PROMPT_FILE"
```

#### Engine: both

依序執行 Codex 和 claude，合併 findings（去重），標註來源。

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

### Step 5: 後續動作

| 結果 | 動作 |
|------|------|
| 全部通過 | 提示 `idd-close` |
| 有 findings | 提示修正後再跑，或用 `--loop` 自動修 |
| Scope creep | 提示開新 issue 或 revert |

---

## Loop 模式（驗證-修復迴圈）

加上 `--loop` 後，自動進入修復迴圈：

```
verify → findings → Claude fixes → verify → findings → fixes → verify → clean ✓
  ↑ 獨立 AI                ↑ 當前 session
```

### 迴圈流程

```
FOR round = 1 to MAX_ROUNDS (預設 3):

  1. 執行驗證（Codex / claude / both）
  2. 解析 findings

  IF 0 findings:
    → PASS，結束迴圈
    → 提示 idd-close

  IF findings 數量 > 上一輪:
    → STOP：regression detected
    → 顯示新增的 findings，請人介入

  IF 某個 finding 已出現 3 次:
    → STOP：recurring finding，自動修不掉
    → 請人介入

  3. 分類 findings:
     - IN_SCOPE（跟 #NNN 相關）→ 自動修復
     - OUT_OF_SCOPE（不相關）→ 標記 SKIPPED

  4. Claude 修復 IN_SCOPE findings
  5. 進入下一輪

IF 達到 MAX_ROUNDS 仍有 findings:
  → STOP：列出剩餘 findings
  → 提示：「超過上限，可能是架構問題」
```

### 每輪輸出

```markdown
## Round 1/3 — Engine: codex

### Findings: 3
- [FIXED] handleUpload() 缺少 null check
- [FIXED] 測試沒覆蓋空輸入
- [SKIPPED] 建議加 rate limiting（不在 #42 範圍）

### 修復摘要
修改了 src/upload.ts、tests/upload.test.ts
```

### 終止條件

| 條件 | 動作 |
|------|------|
| 0 findings | 通過，提示 `idd-close` |
| 達到上限 | 停止，列出剩餘 findings |
| Findings 增加 | 停止，警告 regression — 修復引入了新問題 |
| 同一 finding 出現 3 次 | 停止，這個修不掉，需要人 |

### 安全設計

- **修復者和驗證者是不同的 AI**：Claude 修、Codex/claude -p 驗。避免自我盲點。
- **Scope 守衛**：迴圈中只修 #NNN 相關的 findings，不相關的標 SKIPPED。
- **上限 3 輪**：超過 3 輪 = 可能是架構問題，不是 bug。跟 systematic-debugging 的原則一致。
- **Regression 偵測**：findings 變多 = 修復引入新問題，立即停止。

---

## 鐵律

- **不跳過驗證**。「看起來對了」不算。
- **有 findings 就不 commit**。先修，再 verify，再 commit。
- **Verify 不是自己驗證自己**。用獨立的 AI 來檢查，避免自我盲點。
- **Loop 中不修 scope 外的問題**。不在 #NNN 範圍的 → SKIPPED。

## Next Step

驗證通過後，進入 `idd-close`：

```
/issue-driven-dev:idd-close #NNN
```
