---
name: idd-diagnose
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

產生 diagnosis report 並 **comment 到 issue 底下**（預設行為）：

```markdown
## Diagnosis

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

### Complexity
{Simple / SDD-warranted}
{如果 SDD-warranted，列出原因}

### Risks
{可能出錯的地方}
```

```bash
gh issue comment $NUMBER --repo $GITHUB_REPO --body "$DIAGNOSIS_REPORT"
```

> **數學公式格式**：GitHub 支援 `$...$`（inline）和 `$$...$$`（display）math mode。
> 含底線的程式變數名（如 `mse_info`）**不放進 math mode** — KaTeX 無法可靠渲染底線跳脫。
> 改用混合寫法：數學部分用 `$R_I = J \cdot$`，變數名用 backtick code `` `mse_info` ``。
> 純數學符號（$\theta$, $\hat{d}_J$ 等）放 math mode 沒問題。

> **為什麼 comment 到 issue？** Diagnosis 是 issue 的一部分 — 三個月後回來看，issue 裡就有完整的「問題 → 診斷 → 解法」脈絡，不用翻對話紀錄。

> **原文引用格式**：所有逐字引用的原文（使用者對話、老師回饋、文件段落）**必須**使用 blockquote（`>`）格式，與分析/解讀在視覺上明確區分。

同時在對話中顯示 report，讓使用者可以即時確認。

### Step 3.5: Complexity Assessment（SDD 判斷）

Diagnosis 完成後，評估是否需要走 Spec-Driven Development (SDD)：

**SDD 觸發條件**（任一為 Yes → SDD-warranted）：
- 改動跨 3+ 檔案且邏輯互相依賴？
- 需要新的共用抽象（新函式、新模組、新 protocol）？
- 涉及架構決策或設計 trade-off？
- 影響多個既有 capability / spec？
- Strategy 裡有 5+ 個步驟且有順序依賴？

**判定結果寫入 Diagnosis Report 的 `### Complexity` 區段。**

如果 SDD-warranted：
- Diagnosis report 的 Next Step 改為：`/spectra-propose`（自動綁 #NNN）
- Spectra change 的 proposal 應引用 issue #NNN 作為 motivation
- 後續流程：`spectra-propose → spectra-apply → idd-verify #NNN → idd-close #NNN + spectra-archive`

如果 Simple：
- 照常走 `/idd-implement #NNN`

> **核心原則**：不是所有 issue 都需要 SDD，但所有 SDD 都值得有一個 issue。
> SDD 是 IDD 的 special case — issue 始終是工作的入口和出口。

### Step 4: 確認

詢問使用者：「Diagnosis 已 comment 到 #NNN。正確嗎？要調整策略嗎？」

- 如果要調整 → 修改後用 `gh issue comment` 追加修正
- 如果 Complexity = SDD-warranted → 提示：`/spectra-propose`（綁 #NNN）
- 如果 Complexity = Simple → 提示：`/issue-driven-dev:idd-implement #NNN`

## 鐵律

- **不跳過 diagnosis**。就算「很明顯」也要做。簡單的問題做 diagnosis 只要 2 分鐘，但省下的是 2 小時的重工。
- **發現多個問題 → 開新 issue**。一個 issue 修一個問題。
- **不確定就問**。問使用者比猜測好。

## Auto-Update

Diagnosis comment 完成後，自動執行 `idd-update` 更新 issue body 的 Current Status（phase → `diagnosed`）。

## Next Step

Diagnosis 確認後，進入 `implement`：

```
/issue-driven-dev:idd-implement #NNN
```
