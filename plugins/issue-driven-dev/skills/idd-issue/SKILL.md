---
name: idd-issue
description: |
  建立 well-documented GitHub Issue。每個改動的起點。
  Use when: 報 bug、追蹤需求、任何需要正式記錄的工作。
  防止的失敗：改了東西卻沒有文件記錄「為什麼改」。
argument-hint: "[description or path to .docx]"
allowed-tools:
  - Bash(gh:*)
  - Bash(cp:*)
  - Bash(ls:*)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# /issue — 定義問題

每個改動都從 issue 開始。Issue 是人和 AI 的介面。

## Configuration

讀取 `.claude/issue-driven-dev.local.md` frontmatter：

```yaml
---
github_repo: "owner/repo"
github_owner: "owner"
attachments_release: "attachments"
---
```

如果不存在，詢問使用者並建立。

## Execution

### Step 1: 讀取來源（如果是 .docx）

```
mcp__che-word-mcp__get_document_text(source_path: "path")
mcp__che-word-mcp__list_images(source_path: "path")
```

### Step 2: 蒐集資訊

缺少的話詢問使用者：

1. **Title** — 一句話描述問題
2. **Type** — bug / feature / refactor / docs
3. **Priority** — P0（立即）/ P1（本週）/ P2（排程）/ P3（有空再做）
4. **Description** — 問題描述（bug: 重現步驟 + expected + actual；feature: 需求 + 目的）

### Step 3: 建立 Issue

```bash
gh issue create \
  --repo $GITHUB_REPO \
  --title "$TITLE" \
  --body "$(cat <<'EOF'
## Problem

> **Original text**:
> 「...exact original text...」
> — Source: {source}

{Plain language interpretation}

## Type
{bug / feature / refactor / docs}

## Expected
...

## Actual
...

## Impact
...
EOF
)" \
  --label "$TYPE"
```

> **CRITICAL**: 來自文件的 issue **必須**逐字引用原文。AI 摘要會失真，原文是唯一不會漂移的東西。

> **數學公式格式**：GitHub 支援 `$...$`（inline）和 `$$...$$`（display）。含底線的程式變數名**不放 math mode**，改用 backtick code。混合寫法：`$R_I = J \cdot$` `` `mse_info` ``。

### Step 4: 附加圖片（如果有）

```bash
# 確保 attachments release 存在
gh release view $ATTACHMENTS_RELEASE --repo $GITHUB_REPO 2>/dev/null || \
  gh release create $ATTACHMENTS_RELEASE --repo $GITHUB_REPO \
    --title "Attachments" --notes "Issue attachments and figures"

# 上傳圖片到 release
gh release upload $ATTACHMENTS_RELEASE issue_${NUMBER}_${DESC}.png \
  --repo $GITHUB_REPO --clobber

# 圖片 URL 格式（private 和 public repo 都適用）
# https://github.com/$GITHUB_REPO/releases/download/$ATTACHMENTS_RELEASE/issue_${NUMBER}_${DESC}.png

# 編輯 issue body 加入圖片連結
gh issue edit $NUMBER --repo $GITHUB_REPO --body "..."
```

> **Private repo 圖片渲染**：Release asset URL 在 issue/comment 的 markdown 中可以正常渲染，前提是查看者是 repo 的 collaborator 且已登入 GitHub。不需要把 repo 改成 public。

### Step 5: 回報並停止

輸出：issue number、URL、labels、type。

提示下一步：`/issue-driven-dev:idd-diagnose #NNN`

> **CRITICAL: 建立 issue 後必須停止。不要自動開始 diagnose 或 implement。**
> Issue 建立是人的決定點 — 人決定優先級、分配、時機。
> AI 不應該擅自開始解決問題。等使用者明確說「開始做」或呼叫 `idd-diagnose` 才繼續。

## 來源文件規則

### One Point = One Issue

- **每個要點**獨立建一個 issue
- **不合併** — 類似主題也分開
- **不跳過** — 重複可以之後關，遺漏 = 遺忘
- 處理完畢後驗證：`文件要點數 == 建立的 issue 數`

## Next Step

建立 issue 後，進入 `diagnose`：

```
/issue-driven-dev:idd-diagnose #NNN
```
