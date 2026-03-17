---
name: issue
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

### Step 4: 附加圖片（如果有）

```bash
# 建立 issue 後才知道 issue number
gh release upload $ATTACHMENTS_RELEASE issue_${NUMBER}_${DESC}.png \
  --repo $GITHUB_REPO --clobber
# 編輯 issue body 加入圖片連結
gh issue edit $NUMBER --repo $GITHUB_REPO --body "..."
```

### Step 5: 回報

輸出：issue number、URL、labels、type。

提示下一步：`/issue-driven-dev:diagnose #NNN`

## 來源文件規則

### One Point = One Issue

- **每個要點**獨立建一個 issue
- **不合併** — 類似主題也分開
- **不跳過** — 重複可以之後關，遺漏 = 遺忘
- 處理完畢後驗證：`文件要點數 == 建立的 issue 數`

## Next Step

建立 issue 後，進入 `diagnose`：

```
/issue-driven-dev:diagnose #NNN
```
