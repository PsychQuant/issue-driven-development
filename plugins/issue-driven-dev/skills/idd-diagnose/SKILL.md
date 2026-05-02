---
name: idd-diagnose
description: |
  對照 GitHub Issue 找 root cause（bug）或分析需求（feature/refactor）。
  輸出 diagnosis report：原因、影響範圍、修復/實作策略。
  支援 batch mode（v2.34.0+）：多個 #N 依序跑（如 `#34 #36 #38`），各自 post diagnosis comment。
  Use when: issue 建立後、開始寫 code 之前。
  防止的失敗：修了表象，沒修根本原因。
argument-hint: "#issue [#issue ...] e.g. '#42' or '#34 #36 #38' (batch)"
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

## Batch mode（v2.34.0+）

`idd-diagnose #34 #36 #38` 對 3 個 issue **依序**跑完整 diagnose 流程（每個 issue 各自 post diagnosis comment + auto-update phase）。語意同單一 issue，只是包了一層 loop。完整契約見 [batch-and-cluster.md](../../references/batch-and-cluster.md)。

Aggregate report 在最後輸出（每個 issue 的 complexity 判定 + comment URL）。Per-issue abort 不停 batch — 失敗的 issue 標 `aborted` 在 report 裡，使用者個別處理。

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
TaskCreate(name="download_attachments", description="偵測 issue body/comments 的 attachment URL 全部下載到 .claude/.idd/attachments/issue-NNN/,寫 _manifest.json,parse(MCP-first: che-word-mcp / che-pdf-mcp / Read for images)。依 rules/process-attachments.md。忽略附件 = 忽略來源,違反鐵律。")
TaskCreate(name="diagnose_by_type", description="依 issue type 做診斷: bug→RCA / feature→需求分析 / refactor→現狀分析")
TaskCreate(name="post_diagnosis_report", description="產出 Diagnosis Report 並 comment 到 issue(非只在對話中顯示)")
TaskCreate(name="complexity_assessment", description="3-tier 判定 Simple / Plan / Spectra 並寫入 report 的 Complexity 欄位（v2.36+，Spectra rename from SDD-warranted；新增 Plan tier 介於 Simple 和 Spectra 之間）")
TaskCreate(name="confirm_and_route", description="與使用者確認診斷正確,依 complexity 顯示下一步命令")
TaskCreate(name="auto_update_body", description="Step 5: 跑 /idd-update #NNN 同步 issue body Current Status phase → diagnosed（強制，常被漏；同 idd-close 2.18.1 模式）")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。**TaskCreate 清單 = 真實的步驟清單；任何寫在 skill 裡但沒列進 TaskCreate 的步驟，都視為 skill 的 bug，必須補進 Task 清單。**

特別提醒:**`post_diagnosis_report` 必須 comment 到 GitHub**,不是只在對話中回答。歷史上多次看到「診斷完但忘了 comment」→ 下次回來看不到脈絡。**`auto_update_body` 同樣常被漏跑** — 跟 idd-close 2.18.0 同樣的坑（narrative Auto-Update section 沒被升成強制 step），於 2.18.1 修正 idd-close、本次（2.19.0）一併修 idd-diagnose。

**v2.32.0+ tagging 規則**：若 diagnosis comment 中要 @-tag 任何人（例如要通知 owner 看 root cause），**必須**遵循 [`rules/tagging-collaborators.md`](../../rules/tagging-collaborators.md) 5 步協定（gh api → fuzzy match → AskUserQuestion fallback → @login 不用 display name → post 前 verify）。違反 = 通知錯人，不可逆。

---

### Step 1: 讀取 Issue

```bash
gh issue view $NUMBER --repo $GITHUB_REPO --json title,body,labels,comments
```

識別 issue type：bug / feature / refactor / docs。

### Step 1.5: 下載 Attachment(強制)

依 [`rules/process-attachments.md`](../../rules/process-attachments.md),helper script 處理機械工作:

```bash
IDD_CALLER=idd-diagnose bash $CLAUDE_PLUGIN_ROOT/scripts/process-attachments.sh download $NUMBER
```

Exit code:
- `0` — 下載完成(或 issue 無 attachment,empty manifest 已寫)
- `1` — 部分檔案下載失敗(error 條目已寫進 manifest,警告 surface 給使用者)
- `2` — usage / repo resolution 失敗

下載完成後 **必須** 用 MCP-first parser 讀檔案內容(由 Claude 而非 script 處理):

| 副檔名 | 工具 |
|--------|------|
| `.docx` | `che-word-mcp` MCP tool;fallback `pandoc -f docx -t markdown` |
| `.pdf` | `che-pdf-mcp` MCP tool;fallback `pdftotext` |
| `.png` / `.jpg` / 等圖片 | `Read` tool(多模態直讀) |

把 attachment 摘要納入 diagnosis 的 source-of-truth,在 Diagnosis Report 引用時用相對 path:`.claude/.idd/attachments/issue-NNN/檔名`。

**沒有 attachment** → script 寫空 manifest 後 exit 0,Diagnosis Report 標明「issue 無 attachment」。

**有 attachment 但 fetch 失敗** → script 把 error 條目寫進 manifest,Report 標明「attachment X 未能讀取,後續分析可能不完整」(禁止靜默)。

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
{Simple / Plan / Spectra}
{如果 Plan，列出觸發的 Layer P 信號}
{如果 Spectra，列出 Layer 2 + Layer 3 觸發項}

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

### Step 3.5: Complexity Assessment (3-tier: Simple / Plan / Spectra)

Diagnosis 完成後，依 4 層 gate 判定 Complexity。**Default = Simple。** 完整邏輯見 [`rules/sdd-integration.md`](../../rules/sdd-integration.md)。

> **v2.36.0+ rename**：原本是二元 `Simple` / `SDD-warranted`，現在是三層 `Simple` / `Plan` / `Spectra`。`SDD-warranted` 是 `Spectra` 的 backward-compat alias（既有 issue 不需重寫）。Plan 是新增的中間層，覆蓋「想先想清楚再動手，但沒到要寫 spec contract」的常見場景。

#### 評估順序（必須照此順序）

1. **Layer 1 disqualifiers** 任一命中 → `Simple`，停止
2. **Layer 2 + Layer 3** 都命中 → `Spectra`
3. **Layer P** 任一命中 → `Plan`
4. 否則 → `Simple`（default）

#### Layer 1: Simple-required disqualifiers（任一命中 → 強制 Simple）

- 主要 deliverable 是 narrative / prose（摘要改寫、論文段落、報告、closing summary、wording polish、translation）
- 主要 deliverable 是 ad-hoc analysis script（一次性 R/Python/Julia 分析,腳本本身不會被別 caller 呼叫;產出 tables/figures/reports 給人看）
- 主要 deliverable 是更新既有 prose 但不改 behavior（typo、wording cleanup、文件 restructure）
- Multi-file 但每個檔案 independent（parallel doc updates、parallel script tweaks;檔案數不是 routing 信號）

任一命中 → 直接判 Simple，**完全跳過** Layer 2 / Layer P。**Plan / Spectra 對 fluid narrative / one-shot analysis 是 dead weight。**

#### Spectra（Layer 2 + Layer 3，兩者皆需）

`Spectra` 保留給「**為 future callers 產出 frozen contract**」的改動。

**Layer 2: Necessary condition**

- 改動會對外暴露 published API / protocol / skill / tool surface 給 future callers（function、MCP tool、plugin skill、agent、public Swift API、REST endpoint、OOXML element handler 等），**且** abstraction 的 behavior contract 應該為這些 callers 寫成 documented spec

未命中 Layer 2 → **不走 Spectra**，掉到 Layer P（Plan）評估。

**Layer 3: Spectra confirmation signals（至少一個命中，加在 Layer 2 之上）**

- 修改既有 published spec 的 normative behavior（MUST/SHALL clause changes,影響 downstream maintainers）
- 影響 2+ 既有 specs 需要 consistency-checking（cross-spec impact,需要協調更新）
- Architectural decision with long-term maintenance implications（不是 method-level choice,是會被 future engineers 繼承的結構性決定）

**Plan-Spectra 分界**：「published API/protocol 給 future callers」就是 line。內部 refactor 5 個檔案 → Plan；加新 MCP tool / plugin skill / public API → Spectra。

#### Plan（Layer P，至少一個命中）

如果 Layer 1 沒命中、Layer 2 沒滿足 Spectra，評估 Plan signals：

- **2+ 檔案有順序依賴** — 檔案 A 的改動影響檔案 B 必須怎麼改，無法 parallel edit
- **Strategy 有 5+ ordered steps** — sequential 複雜度，受惠於 explicit checkpoint
- **Decision-heavy with 2+ valid approaches** — diagnosis 列出 2+ 實作策略，選哪個會影響 code shape（例如 regex splice vs DOM walker、optimistic-locking vs pessimistic、batch vs streaming）
- **觸及 risk-sensitive 邊界** — concurrency、migrations、backward-compat shims、security-critical paths、save-durability、ordering semantics、atomic operations
- **Cross-file refactor 但無 external contract change** — 抽 shared logic 成 helper、拆 god-function、rename internal API used by ≥3 callers

任一命中 → `Plan`。Plan path 在 diagnosis 和 TDD execution 之間插入 `EnterPlanMode` approval gate — user 在 plan-mode UI 看 Implementation Plan，approve 或修改後再進 implementation。

#### Simple（default，沒命中以上任何條件）

- Bug fix with clear root cause + self-contained fix
- 單檔案 change
- 跟既有 pattern 走（例如加上第 N 個已知 visitor instance）
- Cross-file research analysis（R/Python script + outputs + docs + abstract）
- Narrative revision
- Ad-hoc one-shot analysis where script is the deliverable
- Multi-step workflow with no shared abstraction

#### Verdict 寫入 Diagnosis Report

把判定結果寫進 Diagnosis Report 的 `### Complexity` 區段。格式：

```
### Complexity
{Simple / Plan / Spectra}

{對 Simple：列出哪個 Layer 1 命中、或 Layer 2/P 都沒命中的說明}
{對 Plan：列出觸發的 Layer P 信號}
{對 Spectra：列出 Layer 2 + Layer 3 觸發項}
```

#### 各 verdict 的 Next Step

| Verdict | Next Step | Flow |
|---------|-----------|------|
| `Simple` | `/idd-implement #NNN` | diagnose → implement → verify → close |
| `Plan` | `/idd-plan #NNN` | diagnose → plan (EnterPlanMode 審查 Implementation Plan → 使用者 approve via ExitPlanMode) → implement → verify → close |
| `Spectra` (default) | `/spectra-discuss` | diagnose → discuss → propose → apply → verify → close + archive |
| `Spectra` (opt-out) | `/spectra-propose` | diagnose → propose → apply → verify → close + archive（僅當 ALL opt-out conditions 成立） |

> **為什麼 discuss 是 Spectra default?** AI 常常高估 diagnosis 的完整度。一份看起來詳盡的 diagnosis 可能仍留下關鍵的未決項:命名、範圍邊界、多個合理方案中該選哪個、新產物要放哪裡。直接跳到 `spectra-propose` 會產生建立在未確認假設之上的 proposal。`spectra-discuss` 是對齊的 safety net — 強制把假設列出、讓使用者修正。跳過它應該是例外,不是預設。
>
> **何時可 opt-out 跳過 discuss?** 當且僅當以下**全部**成立:使用者已在 issue body 或 diagnosis 對話中明確選定方向、無命名/範圍/trade-off 的 open questions、Strategy 沒有未決項、遵循既有 pattern 無新抽象。任一不成立,保留 discuss。
>
> **為什麼 Plan 用 EnterPlanMode?** Plan tier 的價值是「approval checkpoint before any tool that modifies state」。Claude Plan Mode 是這個約束的 first-class API — `EnterPlanMode` 鎖到 read-only tool set，user 必須對呈現的 plan 點 approve（透過 `ExitPlanMode`）才能繼續。比 AskUserQuestion 更強約束（後者只是 yes/no 確認，agent 仍可以「忘了」就動手）。

> **核心原則**：不是所有 issue 都需要 Plan / Spectra，但所有 Plan / Spectra 都值得有一個 issue。三層都是 IDD 的 special case — issue 始終是工作的入口和出口。
>
> **Anti-pattern: 三層 over-trigger**：
> - Spectra over-trigger：cross-file refactor 沒對外暴露 API → 應該 Plan，不是 Spectra
> - Plan over-trigger：clear root cause 單檔 fix → 應該 Simple，不是 Plan
> - Simple under-served：che-word-mcp#104 P1 sub-bug — diagnosis 漏了 rawXML-shadowing case，approval gate 會抓到 → 應該 Plan

### Step 3.7: Agent Routing Recommendation (v2.38.0+, optional)

If `idd-route` is installed (`command -v idd-route`), call it for an agent recommendation based on observed track record + the static heuristic fallback. The recommendation is informational — user accepts or overrides during Step 4 routing. **Skip silently if binary missing.**

```bash
if command -v idd-route &>/dev/null; then
  REPO_PATH=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  STATS="$REPO_PATH/.claude/.idd/routing-stats.jsonl"
  GLOBAL="$HOME/.cache/idd-route/stats.jsonl"

  # Detect signals from issue body + diagnosis (controlled vocabulary in
  # idd-route plugin's references/signal-vocabulary.md). Common signals:
  # explicit_acceptance, single_handler, sibling_sweep_needed, design_negotiation,
  # cross_repo, breaking_change, requires_changelog, public_api, hot_context, etc.
  SIGNALS="..."  # comma-separated, derived from your diagnosis

  # Estimate scope LOC from diagnosis Strategy (rough — counting bullets,
  # mentioned files, etc.)
  SCOPE_LOC="..."

  RECOMMENDATION=$(idd-route recommend \
    --stats-file "$STATS" \
    --global-stats-file "$GLOBAL" \
    --complexity "$COMPLEXITY" \
    --scope-loc-estimate "$SCOPE_LOC" \
    --signals "$SIGNALS" \
    --candidates codex-gpt-5.5-xhigh,claude-opus-4.7,claude-sonnet-4.6,claude-haiku-4.5 \
    2>&1)
  EXIT=$?  # 0=warm data-driven, 3=cold static heuristic, other=error
fi
```

If recommendation succeeded, append a section to the diagnosis comment:

```markdown
### Recommended Agent: <recommended>
**Confidence**: <confidence>  (0.0-1.0; lower = less data, take with grain of salt)
**Data source**: <data_source>  (per_repo / global / static_heuristic)
**Expected**: <round_trips> avg round trips, <blocking> avg blocking, <merge_rate>% merge rate
**Reasoning**: <reasoning>

**Compare**:
| Agent | N | Avg RT | Avg blocking | Merge% | Score |
|-------|---|--------|-------------|--------|-------|
| codex-gpt-5.5-xhigh | 8 | 1.0 | 0.2 | 87% | 4.35 |
| claude-opus-4.7 | 4 | 2.5 | 1.5 | 100% | 0.40 |
| claude-sonnet-4.6 | 0 | — | — | — | insufficient_data |
| claude-haiku-4.5 | 0 | — | — | — | insufficient_data |
```

Full integration contract: [`references/agent-routing.md`](../../references/agent-routing.md).

### Step 4: 確認 + Routing

Diagnosis comment 到 #NNN 後，進行兩階段確認:

#### Stage 1: 確認 diagnosis 正確性

詢問使用者：「Diagnosis 已 comment 到 #NNN。正確嗎？要調整策略嗎？」

- 如果要調整 → 修改後用 `gh issue comment` 追加修正,然後回到這個 Stage 1 重新確認

#### Stage 2: Routing（根據 Complexity 選下一步）

**如果 Complexity = `Simple`**:
- 直接顯示下一步命令:
  ```
  /issue-driven-dev:idd-implement #NNN
  ```

**如果 Complexity = `Plan`**:
- 直接顯示下一步命令:
  ```
  /issue-driven-dev:idd-plan #NNN
  ```
- `idd-plan` 內部會呼叫 `EnterPlanMode`、呈現完整 Implementation Plan 給使用者審查、等 user 透過 `ExitPlanMode` approve 後才 chain 到 `idd-implement`。
- 不要自動 invoke — 使用者應主導 pacing（同 Spectra 路徑慣例）。

**如果 Complexity = `Spectra`**（含 backward-compat alias `SDD-warranted`）:
- **必須**使用 **AskUserQuestion 工具**強制使用者在 `spectra-discuss` 和 `spectra-propose` 之間明確選擇,不可預設任一方向自動繼續
- AskUserQuestion 的 question 和 options 範例:
  ```
  question: "Spectra。預設走 spectra-discuss 對齊方向，要 opt-out 嗎？"
  options:
    - label: "spectra-discuss (default)"
      description: "先列 assumptions 讓你 correct，對齊後才寫 proposal。適用於還有 naming / 範圍 / trade-off 的不確定。"
    - label: "spectra-propose (opt-out)"
      description: "方向已在 issue 或 diagnosis 中明確選定，直接進 formal proposal。僅當零 open questions 時選這個。"
  ```
- 根據使用者選擇**顯示**對應命令讓使用者**自行執行**（不要自動 invoke,使用者應主導 pacing）:
  - 選 `spectra-discuss` → 顯示:`/spectra-discuss` 並附上 topic 建議(例如 issue 標題或核心議題)
  - 選 `spectra-propose` → 顯示:`/spectra-propose`

> **為什麼 Spectra 強制選擇而非給 default?** diagnose 階段 AI 常常高估 strategy 的確定性。若只給「建議」使用者容易忽略並直接跳 propose。AskUserQuestion 把這個決定明確化,避免「忘記走 discuss」。
>
> **為什麼 Simple / Plan 不需要 AskUserQuestion?** 兩條路徑都只有一個合理 next command（idd-implement / idd-plan），沒有 opt-out 分支需要決定。
>
> **為什麼只顯示命令而不自動 invoke?** 使用者應該主導流程節奏。自動 invoke 下游 skills 會讓使用者失去對何時進入下一階段的 visibility 和控制。idd-diagnose 的職責到「告訴使用者下一步是什麼」為止,實際執行由使用者主導。

> **Backward compat (v2.36.0+)**：若 diagnosis comment 寫了 `SDD-warranted`（pre-v2.36 格式），routing 視同 `Spectra` 處理。新 diagnosis comment **必須**寫 `Spectra`。

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

Diagnosis 確認後,依 Complexity 分流（v2.36.0+ 三路）:

**Complexity = `Simple`**:
```
/issue-driven-dev:idd-implement #NNN
```

**Complexity = `Plan`**:
```
/issue-driven-dev:idd-plan #NNN
```
`idd-plan` 內部會用 EnterPlanMode 把 Implementation Plan 呈現給使用者審查，approve 後才執行 TDD loop。

**Complexity = `Spectra` (default — discuss first)**:
```
/spectra-discuss
```
對齊方向後再執行 `/spectra-propose`。

**Complexity = `Spectra` (opt-out — 方向已明確)**:
```
/spectra-propose
```

> Step 4 會透過 AskUserQuestion 強制使用者在 discuss / propose 之間選擇,避免漏走 discuss。
>
> **Backward compat**: 若舊 issue 的 Complexity 寫 `SDD-warranted`，視同 `Spectra` 處理。新 diagnosis 必須寫 `Spectra`。
