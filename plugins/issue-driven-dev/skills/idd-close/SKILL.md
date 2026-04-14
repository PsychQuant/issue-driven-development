---
name: idd-close
description: |
  寫 closing comment 並關閉 GitHub Issue。
  強制記錄做了什麼、怎麼驗證的。
  Use when: verify 通過後、commit 之後。
  防止的失敗：修完了但三個月後沒人知道當時做了什麼。
argument-hint: "#issue e.g. '#42'"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
  - Read
  - AskUserQuestion
---

# /close — 結案

寫 closing comment，然後關閉 issue。三分鐘的紀錄，省三十分鐘的考古。

## 核心原則

> 沒有 closing comment 就不關 issue。沒有例外。
>
> **沒打勾就不關。** 每一個 `- [ ]` 都必須變成 `- [x]`（完成）、`- [~]`（刻意跳過）、或 `- [-]`（won't fix / scope 調整）才能 close。

## Execution

### Step 0: Checklist Gate Check

在動任何 closing comment 之前先 gate — 若有未完成的 todo，**refuse close** 並列出未勾項。

**掃描範圍**：

掃 issue body + **所有 comments** 的 **結構化區段**：

| 區段標題 (`## ` 或 `### `) | 當成 checklist source |
|----------------------------|---------------------|
| `Strategy` | ✅ |
| `Implementation Plan` | ✅ |
| `Implementation Complete` → `Checklist` | ✅（這是 `idd-implement` Step 5 寫回的 source of truth）|
| `Todo` / `Tasks` / `Checklist` | ✅ |
| `Current Status` → `Tasks` | ✅ |
| `Problem` / `Repro` / `Steps to reproduce` / `Workaround` / `Expected` / `Actual` | ❌ 忽略（描述性區段，checkbox 是情境不是 todo）|
| _(未列出的標題)_ | ❌ 忽略（保守：不掃不認識的區段）|

**解析規則**：

對每個符合條件的區段，逐行匹配 regex `^\s*-\s*\[(.)\]\s*(.+)$`：

| 標記 | 意義 | Blocking? |
|------|------|-----------|
| `- [ ]` | open todo | 🔴 **阻擋 close** |
| `- [x]` / `- [X]` | 完成 | ✅ 通過 |
| `- [~]` | skipped（刻意跳過，可能以後再做）| ✅ 通過（**但需附 skip reason**，見下）|
| `- [-]` | won't fix / out of scope | ✅ 通過（**但需附 won't fix reason**）|
| `- [?]` | unknown / need input | 🟡 **阻擋 close**（語意同 open）|
| 其他 | 不識別 | ⚠️ warning，視為 open |

**Skip / Won't-fix reason 檢查**：

`- [~]` 或 `- [-]` 的 line 必須在同一行或下一個縮排 bullet 附說明原因（例如 `- [~] foo — deferred: pending upstream fix`）。若沒有 reason，**阻擋 close**——強迫使用者紀錄為什麼跳過。

**Comment 去重**：

若多個 comments 含相同 source 標題（例如使用者 re-ran `idd-implement` 並發了多個 `## Implementation Complete`），**只看最後一個**（按 comment `createdAt` desc 取第一個）——那是最新的 source of truth。

**Gate 決策**：

```
blocking_count = len([- [ ]]) + len([- [?]]) + len([- [~]] without reason) + len([- [-]] without reason)

if blocking_count > 0:
    REFUSE close
    列出每個 blocking 項目（含來源區段 + 原文）
    建議：
      - 要做的 → /idd-implement #NNN 繼續做
      - 刻意跳過的 → 用 /idd-edit 把 - [ ] 改成 - [~] 並附 reason
      - 不做的 → 用 /idd-edit 改成 - [-] 並附 won't-fix reason
else:
    PASS → 繼續 Step 1
```

**沒找到任何 checklist（legacy issue）**：

顯示 warning `(no checklist detected — legacy issue pattern)`，**不阻擋**（向後相容），但建議使用者考慮先跑 `idd-update` 補 Current Status。

### Step 1: 檢查前置條件

```bash
gh issue view $NUMBER --repo $GITHUB_REPO --json state,title,body
```

確認：
- Issue 是 open 狀態
- 有相關的 commit 引用 #NNN

```bash
git log --oneline --grep="#$NUMBER" | head -10
```

如果沒有相關 commit，警告使用者：「找不到引用 #NNN 的 commit。確定要關嗎？」

### Step 2: 寫 Closing Comment

根據 issue body、diagnosis、commits 自動生成：

```markdown
## Closing Summary

### Problem
{問題是什麼，影響範圍}

### Root Cause
{為什麼會發生（bug）/ 需求背景（feature）}

### Solution
{改了什麼，關鍵邏輯}

### Verification
{怎麼驗證的：verify 結果、測試、截圖}

### Changes
{相關 commit 列表}
```

### Step 3: 確認

將 closing comment 顯示給使用者確認。

### Step 4: 發佈並關閉

```bash
gh issue comment $NUMBER --repo $GITHUB_REPO --body "$CLOSING_COMMENT"
gh issue close $NUMBER --repo $GITHUB_REPO
```

> **數學公式格式**：GitHub 支援 `$...$`（inline）和 `$$...$$`（display）。含底線的程式變數名**不放 math mode**，改用 backtick code。

### Step 5: 回報

```
✓ Issue #NNN closed
  Closing comment: {URL}
  Commits: {list}
```

## Closing Comment 的價值

| 沒有 closing comment | 有 closing comment |
|---------------------|-------------------|
| 三個月後：「這個 issue 改了什麼？」→ 翻 git log 猜 | 三個月後：直接看 closing comment |
| 類似 bug 再出現：「上次怎麼修的？」→ 不知道 | 類似 bug 再出現：參考上次的 root cause + solution |
| 新人接手：「為什麼這段 code 長這樣？」→ 沒人知道 | 新人接手：issue 裡有完整的脈絡 |

## Auto-Update

Close 完成後，自動執行 `idd-update` 更新 issue body 的 Current Status（phase → `closed`）。

## 鐵律

- **沒打勾就不關。** Step 0 的 Checklist Gate Check 是硬性 gate，不給 `--force` bypass。刻意跳過的 todo 必須明確改為 `- [~]` / `- [-]` 並附 reason——這本身就是一個 decision，值得留紀錄。
- **不跳過 closing comment**。即使是小 fix 也要寫。
- **Closing comment 要有 Root Cause**。「改了 X」不夠，要寫「因為 Y 所以改了 X」。
- **列出所有相關 commit**。讓 issue 成為這次改動的完整入口。

## 為什麼不給 `--force`？

「強制關掉」是肌肉記憶殺手。第一次是 "我趕時間"，第三次就變成「反正都 force」。Gate check 的意義是**強迫使用者面對那個未勾項**——要嘛做完、要嘛明確標記「不做，因為 X」，兩種都比 silent 跳過好。

要真的 override，應該走 `/idd-edit #NNN` 把 `- [ ]` 改成 `- [~]` 並寫 reason。多打 30 秒的字，換回 3 個月後的可追溯性。
