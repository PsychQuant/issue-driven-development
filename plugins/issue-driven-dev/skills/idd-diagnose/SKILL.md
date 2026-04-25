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

## Configuration

按 [config-protocol](../../references/config-protocol.md) 解析 target repo:

- `--repo owner/repo` flag → per-invocation override
- Walk-up `.claude/issue-driven-dev.local.json`(從 cwd 往上找)
- Path / git predicates 自動匹配

**Group/predicate 行為**:`idd-diagnose` 操作既存 issue,只用 path/git 類 predicate。Group config 會 fall through 到 primary repo。

## Execution

### Step 0: Bootstrap Stage Task List（強制)

**在動任何事之前**先用 `TaskCreate` 為這個 stage 建 todo list:

```
TaskCreate(name="read_issue", description="gh issue view #NNN 讀 title/body/labels/comments")
TaskCreate(name="diagnose_by_type", description="依 issue type 做診斷: bug→RCA / feature→需求分析 / refactor→現狀分析")
TaskCreate(name="post_diagnosis_report", description="產出 Diagnosis Report 並 comment 到 issue(非只在對話中顯示)")
TaskCreate(name="complexity_assessment", description="Simple vs SDD-warranted 判定並寫入 report 的 Complexity 欄位")
TaskCreate(name="confirm_and_route", description="與使用者確認診斷正確,依 complexity 顯示下一步命令")
TaskCreate(name="auto_update_body", description="Step 5: 跑 /idd-update #NNN 同步 issue body Current Status phase → diagnosed（強制，常被漏；同 idd-close 2.18.1 模式）")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。**TaskCreate 清單 = 真實的步驟清單；任何寫在 skill 裡但沒列進 TaskCreate 的步驟，都視為 skill 的 bug，必須補進 Task 清單。**

特別提醒:**`post_diagnosis_report` 必須 comment 到 GitHub**,不是只在對話中回答。歷史上多次看到「診斷完但忘了 comment」→ 下次回來看不到脈絡。**`auto_update_body` 同樣常被漏跑** — 跟 idd-close 2.18.0 同樣的坑（narrative Auto-Update section 沒被升成強制 step），於 2.18.1 修正 idd-close、本次（2.19.0）一併修 idd-diagnose。

---

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
- **預設** Next Step：`/spectra-discuss`（先對齊方向，再進 propose）
- **opt-out** Next Step：`/spectra-propose`（僅當方向極度明確時跳過 discuss）
- Spectra change 的 proposal 應引用 issue #NNN 作為 motivation
- 後續流程：`[spectra-discuss →] spectra-propose → spectra-apply → idd-verify #NNN → idd-close #NNN + spectra-archive`

> **為什麼 discuss 是 default?** AI 常常高估 diagnosis 的完整度。一份看起來詳盡的 diagnosis 可能仍留下關鍵的未決項:命名、範圍邊界、多個合理方案中該選哪個、新產物要放哪裡。直接跳到 `spectra-propose` 會產生建立在未確認假設之上的 proposal。`spectra-discuss` 是對齊的 safety net — 強制把假設列出、讓使用者修正。跳過它應該是例外,不是預設。
>
> **何時可 opt-out 跳過 discuss?** 當且僅當以下**全部**成立:使用者已在 issue body 或 diagnosis 對話中明確選定方向、無命名/範圍/trade-off 的 open questions、Strategy 沒有未決項、遵循既有 pattern 無新抽象。任一不成立,保留 discuss。

如果 Simple：
- 照常走 `/idd-implement #NNN`

> **核心原則**：不是所有 issue 都需要 SDD，但所有 SDD 都值得有一個 issue。
> SDD 是 IDD 的 special case — issue 始終是工作的入口和出口。

### Step 4: 確認 + Routing

Diagnosis comment 到 #NNN 後，進行兩階段確認:

#### Stage 1: 確認 diagnosis 正確性

詢問使用者：「Diagnosis 已 comment 到 #NNN。正確嗎？要調整策略嗎？」

- 如果要調整 → 修改後用 `gh issue comment` 追加修正,然後回到這個 Stage 1 重新確認

#### Stage 2: Routing（根據 Complexity 選下一步）

**如果 Complexity = Simple**:
- 直接提示下一步命令:
  ```
  /issue-driven-dev:idd-implement #NNN
  ```

**如果 Complexity = SDD-warranted**:
- **必須**使用 **AskUserQuestion 工具**強制使用者在 `spectra-discuss` 和 `spectra-propose` 之間明確選擇,不可預設任一方向自動繼續
- AskUserQuestion 的 question 和 options 範例:
  ```
  question: "SDD-warranted。預設走 spectra-discuss 對齊方向，要 opt-out 嗎？"
  options:
    - label: "spectra-discuss (default)"
      description: "先列 assumptions 讓你 correct，對齊後才寫 proposal。適用於還有 naming / 範圍 / trade-off 的不確定。"
    - label: "spectra-propose (opt-out)"
      description: "方向已在 issue 或 diagnosis 中明確選定，直接進 formal proposal。僅當零 open questions 時選這個。"
  ```
- 根據使用者選擇**顯示**對應命令讓使用者**自行執行**（不要自動 invoke,使用者應主導 pacing）:
  - 選 `spectra-discuss` → 顯示:`/spectra-discuss` 並附上 topic 建議(例如 issue 標題或核心議題)
  - 選 `spectra-propose` → 顯示:`/spectra-propose`

> **為什麼強制選擇而非給 default?** diagnose 階段 AI 常常高估 strategy 的確定性。若只給「建議」使用者容易忽略並直接跳 propose。AskUserQuestion 把這個決定明確化,避免「忘記走 discuss」。
>
> **為什麼只顯示命令而不自動 invoke?** 使用者應該主導流程節奏。自動 invoke spectra skills 會讓使用者失去對何時進入下一階段的 visibility 和控制。idd-diagnose 的職責到「告訴使用者下一步是什麼」為止,實際執行由使用者主導。

### Step 5: Auto-Update Issue Body（強制，不可省略）

Step 4 確認 / routing 完成後**立刻**執行，更新 issue body 的 `Current Status` 區塊（phase → `diagnosed`）：

```
Skill(skill="issue-driven-dev:idd-update", args="#NNN")
```

或等價手動執行 `/idd-update #NNN`。

**為何強制**：diagnosis comment 已 post 到 issue，但 body 的 Current Status phase 還停留在 `created`。沒做 Step 5 會導致：

- `gh issue view` / `idd-list` 仍顯示 `created`，掃不到「這個 issue 已 diagnosed」
- 下一次回來不知道是 `diagnosed` 還是 `(no phase)`
- 與 idd-close 2.18.0 同樣的「narrative Auto-Update 沒升 Step」漏跑模式（見 idd-close 2.18.1 fix `4762e64`）

## 鐵律

- **不跳過 diagnosis**。就算「很明顯」也要做。簡單的問題做 diagnosis 只要 2 分鐘，但省下的是 2 小時的重工。
- **發現多個問題 → 開新 issue**。一個 issue 修一個問題。
- **不確定就問**。問使用者比猜測好。
- **Step 5 Auto-Update 是工作流真實終點**，不是可選 nice-to-have。Step 4 confirm-and-route 完成後馬上跑 `/idd-update`。

## Next Step

Diagnosis 確認後,依 Complexity 分流:

**Complexity = Simple**:
```
/issue-driven-dev:idd-implement #NNN
```

**Complexity = SDD-warranted (default — discuss first)**:
```
/spectra-discuss
```
對齊方向後再執行 `/spectra-propose`。

**Complexity = SDD-warranted (opt-out — 方向已明確)**:
```
/spectra-propose
```

> Step 4 會透過 AskUserQuestion 強制使用者在 discuss / propose 之間選擇,避免漏走 discuss。
