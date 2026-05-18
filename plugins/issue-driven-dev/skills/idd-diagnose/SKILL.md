---
name: idd-diagnose
description: |
  對照 GitHub Issue 找 root cause（bug）或分析需求（feature/refactor）。
  輸出 diagnosis report：原因、影響範圍、修復/實作策略。
  支援 batch mode（v2.34.0+）：多個 #N 依序跑（如 `#34 #36 #38`），各自 post diagnosis comment。
  Use when: issue 建立後、開始寫 code 之前。
  防止的失敗：修了表象，沒修根本原因。
argument-hint: "#issue [#issue ...] [--cwd /path/to/clone] e.g. '#42' or '#34 #36 #38' (batch)"
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

## Cross-repo invocation（v2.40.0+）

支援 `--cwd /path/to/local/clone` flag,讓 diagnose 在指定 local clone 上跑(不依賴 Claude Code session cwd)。Step 0 解析 `--cwd` 後,後續所有 `git`/`gh` 命令依 [`references/cross-repo-cwd.md`](../../references/cross-repo-cwd.md) 的 substitution rule 改寫:

- `git X` → `git -C "$CWD" X`
- `gh issue/pr/repo X` → `gh ... X -R "$GITHUB_REPO"`

完整 algorithm + 失敗模式見 reference 文件。**本 skill 內所有 bash 範例為 cwd-only 寫法以保持可讀性,執行時請套用 substitution rule。**

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
TaskCreate(name="vagueness_precheck", description="Step 3.4 (v2.50+): Layer V Vagueness Pre-check — 用 .claude/rules/attribute-assessment.md 的 6-point Likert anchors 評 V1 + V4,trigger ≥ 4 跳 Hybrid 3-option (clarify/proceed/escalate),audit trail PATCH 到 Diagnosis comment。Unattended mode 自動 proceed + audit trail")
TaskCreate(name="complexity_assessment", description="Step 3.5: 5-layer 判定 Simple / Plan / Spectra 並寫入 report 的 Complexity 欄位(v2.36+ Spectra rename;v2.50+ Layer V 在 Layer 1 之後 Layer 2 之前)")
TaskCreate(name="sister_concern_surfacing", description="Step 3.6: re-read posted Diagnosis content + scout session log for sister-concern markers (也有 / sister / 同樣的 / 另外 / etc); AskUserQuestion 3-option per canonical references/ic-r011-checkpoint.md; PATCH Diagnosis comment with `### Sister Concerns Filed` audit trail (per IC_R011 #528)")
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

### Step 3.4: Vagueness Pre-check (Layer V, v2.50.0+)

Diagnosis 完成、Step 3.5 Complexity Assessment 之前,評估 issue 的「需求清晰度」。如果模糊到無法可靠 routing,先讓 user 表態:澄清 / 照做 / 升級 Plan。

**為何在 Step 3.5 之前**:Layer V 是 routing 決策的一階信號,放在 Step 3.5 之後等於 routing 已經做完才檢查 — 太晚。Layer 1 disqualifier 仍最優先(narrative / ad-hoc 強制 Simple,vagueness 不該推翻),所以 Step 3.4 在 Layer 1 之後、Layer 2/3/P 之前。

#### A. 載入 attribute-assessment 規則(必要)

```bash
RULE_PATH=".claude/rules/attribute-assessment.md"
if [ -f "$RULE_PATH" ]; then
  ANCHOR_SOURCE="$RULE_PATH"
else
  echo "⚠ Layer V: This repo has no project rule for attribute-assessment;using plugin built-in anchors"
  ANCHOR_SOURCE="plugin built-in (see plugins/issue-driven-dev/rules/sdd-integration.md Layer V section)"
fi
```

Anchors 載入後,AI 對 issue body 評 V1 + V4 兩個 score(每個 1–6),依 anchor 給的 example 校準。

#### B. Likert scoring (per-axis)

對 issue body(若 Step 3.6 已澄清過,用更新後的 body)評估:

- **V1 (vague WHAT)** — 「要做什麼」的清晰度
- **V4 (vague ACCEPTANCE)** — 「完成定義」的清晰度

每軸獨立評分 1–6,**不**用 keyword matching(brittle 且 cross-language drift)。Score + 一句話 reasoning(引具體證據:行號 / 引用 / 結構觀察 — 不可寫「感覺像 X」)。

V2(vague HOW)已被 Layer P "decision-heavy" 覆蓋,本步驟**不**評。
V3(vague SCOPE)由 IC_R011 sister sweep(Step 3.6)處理,本步驟**不**評。

#### C. Trigger 判斷

```
trigger = (V1 >= 4) OR (V4 >= 4)
max_score = max(V1, V4)
```

`trigger == false` → 跳過 D,直接進 E(audit trail untriggered)再進 Step 3.5。

#### D. Hybrid 3-option AskUserQuestion(僅在 trigger 時)

依 `max_score` 決定 default option(AskUserQuestion 第一選項):

| max_score | Default option       |
|-----------|----------------------|
| 4         | `proceed anyway`     |
| 5         | `clarify now`        |
| 6         | `escalate to Plan`   |

```
AskUserQuestion(
  question = "Layer V triggered (V1=$V1, V4=$V4). 模糊度 $max_score/6 — 怎麼處理?",
  options = [
    # 順序依 max_score 重排,把 default 放第一個
    {label: "clarify now",      description: "Claude 問 1-3 個 focused questions → 拿你回答 → append 到 issue body 'Clarification (added during diagnose)' 區塊 → 重跑 Layer V + Step 3.5"},
    {label: "proceed anyway",   description: "跳過 clarify,routing 進 Layer 2/3/P。trigger 事實寫入 audit trail"},
    {label: "escalate to Plan", description: "verdict 直接設 Plan via Layer V,跳過 Step 3.5。Routing 進 /idd-plan EnterPlanMode 對齊"}
  ]
)
```

#### D.1 Choice handlers

**`clarify now`**:
1. AI 根據 V1 / V4 評分理由,挑出 1–3 個最不清楚的點問 user
2. User 回答後,組合成 markdown 區塊:
   ```markdown
   ## Clarification (added during diagnose)

   **Q**: <question>
   **A**: <user answer>

   (repeat for each Q/A pair)
   ```
3. 用 `gh issue edit $NUMBER --repo $GITHUB_REPO --body "$NEW_BODY"` append 到 issue body(放在 `---` separator 上,Current Status 之前)
4. **重跑 Step 3.4**(Layer V 用更新後的 body 重新評分;若仍 trigger 再問,但循環不超過 2 次)+ Step 3.5

**`proceed anyway`**:
- 不澄清,不修 issue body
- Audit trail entry(見 E)記 `Layer V triggered (V1=N V4=M), user opted to proceed`
- 進 Step 3.5 Layer 2/3/P 評估

**`escalate to Plan`**:
- 直接設 verdict = `Plan via Layer V`(會被 Step 3.5 的 verdict format 採納)
- 跳過 Step 3.5 Layer 2/3/P 評估
- Routing 直接進 `/idd-plan` 走 EnterPlanMode approval gate

#### E. Audit trail PATCH(無論是否 trigger 都要寫)

把 Step 3.4 結果 append 到剛 post 的 Diagnosis comment:

```bash
COMMENT_ID=<剛 post 的 comment id>
CURRENT_BODY=$(gh api "/repos/$GITHUB_REPO/issues/comments/$COMMENT_ID" --jq '.body')

# Trigger case
if [ "$trigger" = "true" ]; then
  AUDIT_BLOCK="
### Vagueness Pre-check

- **V1**: $V1 — $V1_REASONING
- **V4**: $V4 — $V4_REASONING
- **Triggered**: yes (max=$max_score)
- **User choice**: $USER_CHOICE
- **Effect**: $EFFECT_DESCRIPTION
"
else
  AUDIT_BLOCK="
### Vagueness Pre-check

- **V1**: $V1 — $V1_REASONING
- **V4**: $V4 — $V4_REASONING
- **Triggered**: no — both axes ≤ 3
"
fi

NEW_BODY="${CURRENT_BODY}${AUDIT_BLOCK}"
gh api -X PATCH "/repos/$GITHUB_REPO/issues/comments/$COMMENT_ID" -f body="$NEW_BODY"
```

#### F. `idd-all` Unattended mode

當 idd-diagnose 在 `idd-all` UNATTENDED MODE directive 下執行(透過 args 偵測),Step 3.4 仍評分 + 寫 audit trail,但**不**跳 AskUserQuestion。自動 apply `proceed anyway`,audit trail 寫:

```
[Layer V: V1=$V1 V4=$V4, clarify-default skipped under unattended mode, defaulting to proceed]
```

跟 Plan tier 在 unattended mode 也跳過 EnterPlanMode 同樣設計(user 不在現場,沒法 review prompt)。User 後續 review final report 仍能看到 audit trail 上的 trigger 記錄,可以手動重 route。

### Step 3.5: Complexity Assessment (3-tier: Simple / Plan / Spectra)

Diagnosis 完成 + Step 3.4 Vagueness Pre-check 結束後，依 5 層 gate 判定 Complexity。**Default = Simple。** 完整邏輯見 [`rules/sdd-integration.md`](../../rules/sdd-integration.md)。

> **v2.36.0+ rename**：原本是二元 `Simple` / `SDD-warranted`，現在是三層 `Simple` / `Plan` / `Spectra`。`SDD-warranted` 是 `Spectra` 的 backward-compat alias（既有 issue 不需重寫）。Plan 是新增的中間層，覆蓋「想先想清楚再動手，但沒到要寫 spec contract」的常見場景。
>
> **v2.50.0+ Layer V**：Step 3.4 Vagueness Pre-check 在 Layer 1 之後、Layer 2 之前評估「需求清晰度」。若 user 在 Step 3.4 選 `escalate to Plan`，verdict 直接設 `Plan via Layer V`,本 step 跳過 Layer 2/3/P 評估。

#### 評估順序（必須照此順序，5 層）

1. **Layer 1 disqualifiers** 任一命中 → `Simple`，停止
2. **Layer V (Step 3.4)** Vagueness 已在 Step 3.4 處理:
   - User 選 `escalate to Plan` → verdict = `Plan via Layer V`,**本 step 結束**
   - User 選 `clarify now` → 已重跑 Layer V + 進到本 step
   - User 選 `proceed anyway` 或 V≤3 → 繼續以下評估
3. **Layer 2 + Layer 3** 都命中 → `Spectra`
4. **Layer P** 任一命中 → `Plan`
5. 否則 → `Simple`（default）

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

### Step 3.6: Sister Concern Surfacing (v2.47.0+, kiki830621/ai_martech_global_scripts#528)

**Compliance**: this step implements [IC_R011](https://github.com/kiki830621/ai_martech_global_scripts/issues/516) commercial low-bar filing for the **mid-diagnosis deliberation window** per the canonical [`references/ic-r011-checkpoint.md`](../../references/ic-r011-checkpoint.md) pattern (3-option AskUserQuestion + audit trail + rollback hatch).

**Why this step**: Diagnosis posting (Step 3) often contains sister-concern markers — phrases like 「也有」 / 「same pattern in」 / 「the related X」 / 「另外」 / 「sister」 — referencing files / functions / scenarios beyond the current issue scope. Without mechanical checkpoint, these mentions live only in conversation + Diagnosis comment, never tracked as follow-ups. Diagnosis is a **prime deliberation moment** (Strategy section often surfaces tangential concerns) — same lifecycle position as `idd-plan` Step 2.5 (#524) but earlier in the IDD chain.

**Rule (SHALL)**: 在 Step 4 (確認 + Routing) 前，**必須** review the just-posted Diagnosis comment + session log from Step 1 (Read Issue) for sister-concern markers; AskUserQuestion 3-option per canonical reference doc. Empty list 是合法結果，但 step 本身不可省略。

**Heuristic — what counts as "sister concern worth surfacing"** (per IC_R011 default-on triggers, full list in `ic-r011-checkpoint.md` §2):

- **Sister-pattern markers in Diagnosis content**: 「也有」 / 「same pattern」 / 「related」 / 「另外」 / 「sister」 / 「likewise affects」 — references to other files where the same root cause might apply
- **"This won't solve X" disclaimers** in Strategy section — explicit out-of-scope mentions that should be tracked
- **Verifiable behavior gap** observed during root-cause analysis but excluded from current issue scope
- **Adjacent code quality issues** encountered while investigating root cause (TODOs / FIXMEs / drift)

**Default-off exemptions**: per canonical reference doc §3 — purely exploratory observations / existing issue covers / hallucinated without evidence / CONSTRAINT not TODO.

**Procedure**:

1. **Surface list**: AI re-reads the just-posted Diagnosis content + scout session log, lists candidates per canonical format:

   ```
   {N}. [paragraph in Diagnosis: "{quoted excerpt}"] suggests follow-up: {1-line description}
        Trigger: {sister marker phrase or pattern}
        Proposed type: bug / refactor / docs / test
        Proposed labels: confidence:confirmed, priority:P3
   ```

2. **AskUserQuestion** 3-option (per canonical reference doc §1):
   - `file all` → loop `gh issue create --repo "$GITHUB_REPO"` per item
   - `file selected` → numbered checklist for cherry-pick
   - `skip` → audit-trail line documenting reason

3. **File issues** (if "file all" or "file selected"):

   ```bash
   for item in $selected_items; do
     NEW_ISSUE_URL=$(gh issue create --repo "$GITHUB_REPO" \
       --title "[$type] $description (sister concern from #$NNN)" \
       --body "$BODY_WITH_SOURCE_LINK" \
       --label "$type,confidence:confirmed,priority:P3")
     NEW_ISSUE=$(basename "$NEW_ISSUE_URL")

     # Chain context manifest write (per spawn-manifest contract, v2.55+ #44; v2.60+ #46 schema v2)
     # spawn_kind classification:
     # - 真的同主題 sister concern (same root cause, different file) → "sister-concern"
     # - cross-cutting / upstream tracking (e.g. 跟 idd repo 無關的 upstream gap) → "upstream-tracking"
     # `same_file` / `same_skill` 依 sister-concern evidence 判斷;upstream-tracking 兩個都 false
     # 9th arg root_id: prefer chain shell's exported IDD_CHAIN_CURRENT_ROOT_ID env var;
     # fallback to current diagnosing issue's $NNN (single-root chain or root self-spawn).
     # Defensive guard (v2.60+ #46 L2): skip explicitly if no root_id available.
     ROOT_ID_FOR_MANIFEST="${IDD_CHAIN_CURRENT_ROOT_ID:-${NNN:-}}"
     if [ -n "$ROOT_ID_FOR_MANIFEST" ]; then
       bash "$CLAUDE_PLUGIN_ROOT/scripts/manifest-append.sh" \
         "$REPO_ROOT" "$NEW_ISSUE" "idd-diagnose" "Step 3.6 sister concern surfacing" \
         "$item_kind" "$item_same_file" "$item_same_skill" "$item_title" "$ROOT_ID_FOR_MANIFEST" \
         2>/dev/null || true   # silent skip when chain context inactive
     fi
   done
   ```

   Body MUST contain `**Source**: surfaced during /idd-diagnose #$NNN sister concern surfacing (Step 3.6)` for traceability.

   Manifest write is **additive** — 無 chain context 時 helper 靜默 exit 0,baseline behavior 不變。See `references/spawn-manifest.md` for the cross-skill contract.

4. **Update Diagnosis comment** (Step 3 已 post): PATCH the comment to append `### Sister Concerns Filed (mid-diagnose, v2.47.0+ #528)` section per canonical heading conventions table:
   - "file all/selected" → `Filed: #NNN, #MMM, #PPP`
   - "skip" → `Skipped per user choice (N items: brief list of descriptions)`
   - empty surface list → `none surfaced`
   - `AI_LOW_BAR_ISSUE_FILING=false` env var → `skipped (AI_LOW_BAR_ISSUE_FILING=false, per IC_R011 rollback)`

**Rollback escape hatch**: per canonical reference doc §5 — `AI_LOW_BAR_ISSUE_FILING=false` env var or `# Disable IC_R011` flag in repo CLAUDE.md silently skips checkpoint while preserving audit trail.

> **Why is this SHALL not SHOULD?** Diagnosis is a **deliberation moment** (per canonical eligibility criteria §6) — Strategy authoring is when sister concerns naturally surface. Closing tier (`#527` Step 3.5) is SHOULD because it's an after-the-fact text scan;diagnosis is a creative + analytical authoring moment where the mention is fresh + actionable.

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
