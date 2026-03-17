---
name: idd-verify
description: |
  驗證 uncommitted/committed code 是否滿足 Issue 的所有要求。
  使用 Codex CLI (gpt-5.4) 進行獨立驗證。也可不帶 #NNN 做通用 code review。
  Use when: 實作完成後、commit 之前。
  防止的失敗：自以為修好了，沒跑驗證。
argument-hint: "#issue [effort] e.g. '#42' or '#42 high' or (no args for general review)"
allowed-tools:
  - Bash(codex:*)
  - Bash(git:*)
  - Bash(gh:*)
  - Bash(mktemp:*)
  - Bash(rm:*)
  - Read
  - Grep
  - AskUserQuestion
---

# /verify — 驗證實作

用獨立的 AI（Codex CLI, gpt-5.4）驗證 code 是否滿足 issue 要求。

## 核心原則

> 「應該沒問題」不是驗證。跑了驗證、看了輸出、確認通過，才是驗證。

## 兩種模式

| 模式 | 用法 | 場景 |
|------|------|------|
| Issue-focused | `verify #42` | 對照 issue 要求逐條檢查 |
| General | `verify` | 通用 code review，不綁 issue |

## Configuration

讀取 `.claude/issue-driven-dev.local.md` frontmatter。如不存在，詢問 `github_repo` 並建立。

## Effort Levels

| Level | 適用場景 | 指定方式 |
|-------|---------|---------|
| `medium` | 小改動 (<50 lines) | `verify #42 medium` |
| `high` | 中等改動 (50-200 lines) | `verify #42 high` |
| `xhigh` | 大改動 (>200 lines) | `verify #42`（預設） |

未指定時，依 diff 大小自動選擇。

追加 `fast` 使用 `service_tier="fast"`：`verify #42 fast`

## Execution

### Step 1: 檢查是否有未提交的改動

```bash
git status --short
git diff --stat
```

如果沒有改動，通知使用者並停止。

### Step 2: 取得 Issue 內容（如有 #NNN）

```bash
gh issue view $NUMBER --repo $GITHUB_REPO --json title,body,labels
```

### Step 3: 執行 Codex Review

**Mode A: Issue-focused（有 #NNN）**

將 diff 和 issue 要求一起餵給 Codex：

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

**Mode B: General（無 #NNN）**

```bash
codex review \
  -c 'model="gpt-5.4"' \
  -c "model_reasoning_effort=\"$EFFORT\"" \
  --uncommitted
```

### Step 4: 呈現結果

```markdown
## Verify: #NNN — {title}

### 要求覆蓋率
X / Y requirements addressed

### Findings
- ...

### Scope Check
{有沒有超出 issue 範圍的改動}
```

### Step 5: 後續動作

| 結果 | 動作 |
|------|------|
| 全部通過 | 提示：`可以 commit 了。要 close 嗎？ /issue-driven-dev:idd-close #NNN` |
| 有 findings | 提示：`要修正嗎？修完後再跑一次 /issue-driven-dev:idd-verify #NNN` |
| Scope creep detected | 提示：`有超出範圍的改動。要開新 issue 還是 revert？` |

## 鐵律

- **不跳過驗證**。「看起來對了」不算。
- **有 findings 就不 commit**。先修，再 verify，再 commit。
- **Verify 不是自己驗證自己**。用獨立的 AI (Codex) 來檢查，避免自我盲點。

## Next Step

驗證通過後，進入 `close`：

```
/issue-driven-dev:idd-close #NNN
```
