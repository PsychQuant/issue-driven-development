---
name: diagnose
description: |
  對照 GitHub Issue 找 root cause（bug）或分析需求（feature/refactor）。
  輸出 diagnosis report：原因、影響範圍、修復/實作策略。
  Use when: issue 建立後、開始寫 code 之前。
  防止的失敗：修了表象，沒修根本原因。
argument-hint: "#issue e.g. '#42'"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
  - Bash(grep:*)
  - Bash(find:*)
  - Read
  - Glob
  - Grep
  - AskUserQuestion
---

# /diagnose — 理解問題

在寫任何一行 code 之前，先確認你真的理解問題。

## 核心原則

> 不理解問題就動手 = 修表象。修表象 = 問題會回來。

## Execution

### Step 1: 讀取 Issue

```bash
gh issue view $NUMBER --repo $GITHUB_REPO --json title,body,labels,comments
```

識別 issue type：bug / feature / refactor / docs。

### Step 2: 依類型診斷

#### Bug → Root Cause Analysis

1. **重現問題**
   - 找到觸發條件
   - 如果不能穩定重現 → 蒐集更多資訊，不要猜

2. **Trace 資料流**
   - 從錯誤訊息 / stack trace 出發
   - 往上追到源頭：壞的值是從哪裡來的？
   - 每個環節都確認，不跳過

3. **檢查最近的變更**
   ```bash
   git log --oneline -20
   git diff HEAD~5
   ```
   - 什麼改動可能引發這個問題？

4. **找到 working example**
   - Codebase 裡有沒有類似的、正常運作的 code？
   - 壞的跟好的差在哪裡？

5. **形成假設**
   - 明確陳述：「我認為 root cause 是 X，因為 Y」
   - 一次一個假設，不要同時猜多個

#### Feature → 需求分析

1. **拆解需求**
   - Issue 要求的每個功能點列出來
   - 模糊的地方標出來，詢問使用者

2. **影響範圍**
   - 需要改哪些檔案？
   - 有沒有既有的 pattern 可以參考？

3. **實作策略**
   - 有幾種做法？各自的 trade-off？
   - 推薦哪種？為什麼？

#### Refactor → 現狀分析

1. **為什麼要重構**
   - 現在的問題是什麼？（效能？可讀性？耦合？）

2. **風險評估**
   - 改動範圍多大？
   - 有沒有 test coverage 保護？
   - 有沒有隱藏的依賴？

3. **重構策略**
   - 一步到位還是漸進式？
   - 如何確保行為不變？

### Step 3: 輸出 Diagnosis Report

輸出格式（直接寫在對話中，不存檔）：

```markdown
## Diagnosis: #NNN — {title}

### Type
{bug / feature / refactor}

### Root Cause / Analysis
{bug: root cause + evidence}
{feature: requirements breakdown}
{refactor: current state + problems}

### Impact
- 影響的檔案：...
- 影響的使用者流程：...

### Strategy
{具體的修復 / 實作計畫}
- [ ] 改 A
- [ ] 改 B
- [ ] 加測試 C

### Risks
{可能出錯的地方}
```

### Step 4: 確認

詢問使用者：「Diagnosis 正確嗎？要調整策略嗎？」

確認後提示下一步：`/issue-driven-dev:implement #NNN`

## 鐵律

- **不跳過 diagnosis**。就算「很明顯」也要做。簡單的問題做 diagnosis 只要 2 分鐘，但省下的是 2 小時的重工。
- **發現多個問題 → 開新 issue**。一個 issue 修一個問題。
- **不確定就問**。問使用者比猜測好。

## Next Step

Diagnosis 確認後，進入 `implement`：

```
/issue-driven-dev:implement #NNN
```
