---
name: idd-update
description: |
  更新 GitHub Issue body 的 Current Status 區塊，反映最新進度。
  保留原始記錄（Problem/Type/Expected），只更新狀態區塊。
  由其他 idd-* skills 自動呼叫，也可手動執行。
  Use when: issue 狀態改變時（自動）、或手動同步現狀。
  防止的失敗：issue body 過時，要讀完所有 comments 才知道現狀。
argument-hint: "#issue e.g. '#42'"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
  - Read
  - Edit
---

# /idd-update — 同步 Issue 現狀

保持 issue body 永遠反映最新狀態，不用翻 comments 就知道現在在哪。

## 核心原則

> 原始記錄不動，現狀即時更新。Comment 是歷史，Body 是現狀。

## 設計

Issue body 分為兩個區域：

```markdown
## Problem            ← 不動（原始記錄）
## Type               ← 不動
## Expected           ← 不動
## Actual             ← 不動
## Impact             ← 不動

---

## Current Status     ← idd-update 管理這塊
```

`---` 分隔線以上 = 永遠不改。以下 = 每次 idd-update 重寫。

## Configuration

讀取 `.claude/issue-driven-dev.local.md` frontmatter 取得 `github_repo`。

## Execution

### Step 1: 讀取 Issue 完整資訊

```bash
gh issue view $NUMBER --repo $GITHUB_REPO --json title,body,labels,state,comments
```

### Step 2: 判斷當前 Phase

從 comments 中推斷 issue 目前所在階段：

| 最後的 comment 類型 | Phase |
|---------------------|-------|
| 無 comment | `created` |
| Diagnosis | `diagnosed` |
| Implementation Plan | `planning` |
| Implementation Complete | `implemented` |
| Verify (PASS) | `verified` |
| Verify (FAIL / findings) | `needs-fix` |
| Closing Summary | `closed` |

判斷依據：掃描 comments 中的 `## Diagnosis`、`## Implementation Plan`、`## Implementation Complete`、`## Verify`、`## Closing Summary` 標題。

### Step 3: 從 Comments 提取關鍵資訊

掃描所有 comments，提取：

1. **Key Decisions**：策略改變、重要發現、scope 調整
   - 從 diagnosis 的 Strategy 區塊
   - 從 implementation 中的 scope 說明
   - 從 verify 的 findings

2. **Scope Changes**：跟原始 issue 不同的地方
   - 新增的需求
   - 移除的需求
   - 調整的做法

3. **Blocking**：當前的阻塞項
   - verify 未通過的 findings
   - 等待使用者確認的問題
   - 依賴其他 issue

4. **Related Commits**：引用此 issue 的 commits

```bash
git log --oneline --grep="#$NUMBER" | head -10
```

### Step 4: 組裝 Current Status 區塊

```markdown
---

## Current Status

**Phase**: {phase}
**Last updated**: {YYYY-MM-DD} by {which idd-* skill}

### Key Decisions
- {decision 1}
- {decision 2}

### Scope Changes
- {change 1, or "(none)"}

### Blocking
- {blocker 1, or "(none)"}

### Commits
- `{hash}` {message}
```

### Step 5: 更新 Issue Body

將原始 body 的 `---` 分隔線（含）以下替換為新的 Current Status。

如果原始 body 沒有 `---` 分隔線和 Current Status 區塊，在 body 尾部**新增**。

```bash
gh issue edit $NUMBER --repo $GITHUB_REPO --body "$UPDATED_BODY"
```

### Step 6: 靜默完成

`idd-update` 被其他 skill 自動呼叫時，**不輸出額外訊息**，只在最後一行顯示：

```
✓ Issue #NNN status updated → {phase}
```

手動呼叫時，顯示完整的 Current Status 內容。

## 被其他 Skills 呼叫

每個 idd-* skill 在最後一步呼叫 idd-update：

```
# 在 idd-diagnose 結尾
→ idd-update #NNN（自動，phase = diagnosed）

# 在 idd-implement 結尾
→ idd-update #NNN（自動，phase = implemented）

# 在 idd-verify 結尾
→ idd-update #NNN（自動，phase = verified 或 needs-fix）

# 在 idd-close 結尾
→ idd-update #NNN（自動，phase = closed）
```

## 手動呼叫

```
/issue-driven-dev:idd-update #42
```

用途：
- 手動補充 comments 後同步 body
- Issue 長時間沒動，重新整理現狀
- 修正 Current Status 中的過時資訊

## 鐵律

- **永遠不改 `---` 以上的內容**。原始記錄是審計軌跡。
- **Key Decisions 只加不刪**。新的加在最上面，舊的保留。
- **簡潔**。每個 bullet 一行，不超過 100 字。
- **Phase 必須準確**。如果推斷不出來，標 `unknown` 並提醒使用者。
