---
name: idd-plan
description: Plan-mode 實作。在 idd-implement 的 TDD loop 之前，先用 Claude Plan Mode 把 Implementation Plan 呈現給使用者審查、approve 後才動手。介於 Simple（直接 implement）和 Spectra（完整 spec/proposal/tasks artifacts）之間的中間層。
---

# /idd-plan — Plan-mode 實作

「**Think before leap, but no spec contract**」的 IDD 路徑。在 TDD execution 之前插入 `EnterPlanMode` approval gate — 使用者在 plan-mode UI 看完整 Implementation Plan，approve 後才執行任何 stateful tool。

## 核心原則

> Plan tier 的價值 = approval checkpoint。只多花 30 秒 review，省下 30 分鐘的「diagnosis 漏了 edge case → 6-AI verify 才抓到 P1 → 補 commit」迴圈。
>
> Plan-mode 不是 confirmation 按鈕。`EnterPlanMode` 鎖到 read-only tool set，必須透過 `ExitPlanMode` 提交 plan 給使用者 approve 才能解鎖。沒有「啊我順便動一下」的 escape hatch。

## 何時用 idd-plan vs idd-implement vs spectra-discuss

由 `idd-diagnose` Step 3.5 的 Complexity verdict 決定（見 [`rules/sdd-integration.md`](../../rules/sdd-integration.md)）：

| Verdict | Skill | 場景 |
|---------|-------|------|
| `Simple` | `/idd-implement #NNN` | clear root cause、單檔 fix、follow existing pattern |
| `Plan` | `/idd-plan #NNN` (本 skill) | 2+ 互依檔案 / 5+ ordered steps / decision-heavy / risk-sensitive boundary，**但無 published API contract** |
| `Spectra` | `/spectra-discuss` then `/spectra-propose` | 對外 API/protocol/skill/tool 給 future callers + spec contract 需要 frozen |

如果 user 直接 `/idd-plan` 而 issue 的 Complexity 是 Simple → 仍允許執行（user 主動要 deliberate 沒問題）。如果 Complexity 是 Spectra → 提示「Spectra 應該走 `/spectra-discuss`，Plan tier 不會產出 spec/proposal/tasks artifacts，可能不是你要的；繼續嗎？」並 AskUserQuestion 確認。

## Configuration

按 [config-protocol](../../references/config-protocol.md) 解析 target repo。同 idd-implement 的 config protocol。

## Execution

### Step 0: Bootstrap Stage Task List（強制）

```
TaskCreate(name="resolve_pr_path", description="Phase 0.5: --pr/--no-pr flag → fork detection → pr_policy config → ask. 若 PR path: 建 feature branch")
TaskCreate(name="read_issue_and_diagnosis", description="gh issue view + 確認最新 diagnosis comment 的 Strategy + Complexity == Plan/Simple")
TaskCreate(name="draft_implementation_plan", description="依 Strategy 起草 Implementation Plan（5 段：files + reasoning + tests + risks + sequence）並 comment 到 issue")
TaskCreate(name="tangential_sweep", description="Step 2.5: review session log from Step 1 to here, identify mid-plan tangential discoveries (sister bugs / unrelated quality issues / user-mentioned sub-concerns); AskUserQuestion to file as follow-up issues; append filed list to plan body before ExitPlanMode (per IC_R011 #524)")
TaskCreate(name="enter_plan_mode_for_approval", description="Step 4: EnterPlanMode → 呈現 full Implementation Plan → ExitPlanMode 等 user approve / revise / abort")
TaskCreate(name="handle_plan_response", description="Step 5: Approved → 進 Step 6 chain to idd-implement / Revised → 修改 Implementation Plan comment + 重新 EnterPlanMode / Aborted → idd-update phase=needs-fix 並結束")
TaskCreate(name="chain_to_idd_implement", description="Step 6: 呼叫 /idd-implement #NNN，pass 已 approved 的 Implementation Plan via context（idd-implement 跳過 Step 2 自動偵測現有 plan）")
TaskCreate(name="auto_update_body", description="Step 7: idd-update phase → planning（v2.36+ 新 phase 介於 diagnosed 和 implemented 之間）")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。

### Step 1: 讀取 Issue + Diagnosis + Confirm Complexity

```bash
gh issue view $NUMBER --repo $GITHUB_REPO --json title,body,labels,comments
```

確認最新的 `## Diagnosis` comment 存在且 `### Complexity` 是 `Plan`（或 `Simple`，user 主動 deliberate）。

| Complexity | 行為 |
|-----------|------|
| `Plan` | ✅ 預期 — 繼續 |
| `Simple` | ⚠️ 詢問 user：「Complexity 判定為 Simple，確定要走 Plan tier 多一道 approval gate 嗎？」 |
| `Spectra` (含 alias `SDD-warranted`) | ⛔ 提示「Spectra 應走 `/spectra-discuss`，Plan tier 不會產出 spec/proposal/tasks artifacts」，AskUserQuestion abort 或 continue（continue 等於 user 自願降級到 Plan tier） |
| _(missing)_ | ⛔ 提示「找不到 diagnosis，先跑 `/idd-diagnose #NNN`」並 abort |

### Step 2: Draft Implementation Plan

依 Strategy 起草詳細的 Implementation Plan。**比 idd-implement Step 2 的 plan 更詳盡**，因為這份 plan 是要過 user 在 plan mode UI 審查的，是 deliberation tier 的核心 artifact。

格式：

```markdown
## Implementation Plan (Plan tier)

### Files & Changes
- [ ] `path/to/file1.ext` — {改什麼 + 為什麼這樣改}
- [ ] `path/to/file2.ext` — {改什麼 + 與 file1 的依賴關係}
- [ ] `tests/path/to/test_file.ext` — {測什麼 invariant，RED→GREEN expectation}

### Family-wide scope (shared-abstraction hard-gate trigger only)
{僅當 #129 硬閘因 **shared abstraction** 命中時填：列舉該抽象的**所有已知 call site / family member** 為 in-scope，而非只覆蓋 issue 標題點名的觸發檔。例：scoring helper 被 CR + PTSR + PCQ 三個 sibling 量表共用 → 三個 sibling 全列入 Files & Changes。這是硬閘的產出契約（#44 教訓：Plan 只覆蓋一個量表、漏了同 family 的 sibling，兩次 close 才補齊）。非 shared-abstraction 觸發時填 `n/a`。}

### Sequencing & Dependencies
{file A 的改動先 land，因為 file B 的測試會 import file A 的新 helper / file B 改完才能測 end-to-end / 等等}

### Decision Points
{若 diagnosis 的 Strategy 提到 2+ approaches，本 plan 明確 pick 哪一個 + 為什麼。例：選 regex splice 而非 DOM walker，因為 cached run 的 rawXML 是已知 shape, regex 更輕量且不引入新依賴}

### Risks & Mitigations
{列出 risk-sensitive boundary 怎麼 mitigate。例：concurrency → serial execution / migration → idempotent / save-durability → atomic rename / etc.}

### Test Plan
{每個 test 對應哪個 file 改動的哪個 invariant。RED test 預期失敗訊息、GREEN 預期通過行為}

### Out-of-scope (will NOT be touched)
{明確列出 diagnosis 提過但本 PR 不做的，避免 scope creep}

### Tangential Observations (filed mid-plan, v2.42.0+ #524)
{由 Step 2.5 填入：filed issue numbers list / `none surfaced` / `skipped per user choice` / `skipped (AI_LOW_BAR_ISSUE_FILING=false)`}
```

post 到 issue：

```bash
gh issue comment $NUMBER --repo $GITHUB_REPO --body "$IMPLEMENTATION_PLAN"
```

> **為什麼比 idd-implement 的 plan 詳盡？** Plan tier 的 user 審查是事前 deliberation 的 core moment — plan 越具體，user 越容易抓出 missing case / wrong assumption / better alternative。idd-implement 的 plan 是「執行清單」，本 plan 是「decision artifact」。

> **`type=meeting` 用 meeting-adapted Plan body schema（#57）**：上面的 code-centric 模板（Files & Changes / Sequencing / Test Plan）**不適用** meeting。`type=meeting` 改用審議 Plan body：
>
> ```markdown
> ## Meeting Plan: Issue #NNN
> ### Phase A — 議程（本次要談的議題）
> - {議題 1} …
> ### Phase B — 決策點（需拍板 + 候選選項）
> - {決策點 1：候選 A / B / C} …
> ### Phase C — 行動項（decision → follow-up action + owner）
> - [ ] {action} …
> ```
>
> meeting plan 過 user approve 後 **不 chain 到 /idd-implement**（見 Step 6 skip-chain）。

### Step 2.5: Tangential Observations Sweep

**Per IC_R011 follow-up filing checkpoint** (see [`references/ic-r011-checkpoint.md`](../../references/ic-r011-checkpoint.md))。

**Trigger condition**: 在 ExitPlanMode 前（Step 4 前），review session log from Step 1（Read Issue + Diagnosis）起到本 step 為止，identify mid-plan tangential discoveries — Phase 1 scouting / Phase 2 design / Phase 3 review 期間 surface 但 **沒 categorization** 的項目（既沒進 In-scope 也沒進 Out-of-scope，會隨 conversation 流失）。empty list 是合法結果，但 step 本身不可省略。

**Per-step deviation**:

- **Mid-plan deliberation window**：本 step 的 surface 來源是 Plan-tier deliberation 三個 phase（Phase 1 Explore agents return summary 提到 unrelated file/function quality issue / Phase 2 Design 起草時 grep / file read 撞到 sister bug / drift / misleading TODO / Phase 3 Review 期間 user inline-mention 的 sub-concern beyond plan focus）。
- **Out-of-scope 區塊互補**：surface 對象特別包括 Plan 結尾 Out-of-scope 區塊**沒**列出但 user 後續 close 時可能忘的「曾提到但無 categorization」項目。
- **Plan body PATCH**：當 default file path 完成或 skip 結果出爐後，必須 PATCH Step 2 已 post 的 Implementation Plan comment 的 `### Tangential Observations` section（不是新 comment），保持 plan artifact single source of truth。
- **Chain context manifest write**：filing 時若 `IDD_CHAIN_CURRENT_ROOT_ID` env var set（fallback `$NNN`），呼叫 `scripts/manifest-append.sh` 以 `spawn_kind=tangential` + `same_file` / `same_skill` evidence 寫入 spawn manifest（per [`references/spawn-manifest.md`](../../references/spawn-manifest.md) v2.60+ #46 schema v2）。無 chain context 時 helper 靜默 exit 0，baseline behavior 不變。

**Audit trail target**: `### Tangential Observations (filed mid-plan, v2.42.0+ #524)` in Implementation Plan comment

**Default behavior (v2.72.0+)**: File by default per canonical Section 1.1。Skip requires 3-category taxonomy per Section 1.4。Source footer per Section 7.2：`**Source**: surfaced during /idd-plan #N tangential sweep (Step 2.5)`。Escape hatches (`AI_LOW_BAR_ISSUE_FILING=false` env var / `# Disable IC_R011` repo flag) per Section 5。

> **為什麼是 SHALL 而非 SHOULD？** Plan-tier issues 走完整 deliberation cycle，30 秒 file 一個 follow-up vs. 30 分鐘將來重新 reconstruct（per IC_R011 cost ratio）；audit trail 缺漏的代價 vs. 多 file 一個 issue 的代價，後者大幅低。SHALL 起來，empty list 是合法結果，no friction added。

### Step 3: 確認 plan post 成功

確認 comment URL 已拿到（capture-then-write SOP）。Plan 必須 post 到 issue 後才進 Step 4，否則 plan-mode UI 呈現的內容沒留 audit trail。

### Step 4: EnterPlanMode → present plan → ExitPlanMode for approval

呼叫 `EnterPlanMode` 工具進入 plan mode（read-only tool set 鎖定）。然後在 plan-mode 的視窗呈現完整 Implementation Plan markdown，並透過 `ExitPlanMode` 提交給 user approve。

> **重要**: 在 plan mode 期間 **不能呼叫任何 stateful tool**（Edit / Write / Bash with mutations / gh commenting / etc.）— runtime 會 reject。所以 Implementation Plan comment 必須在 Step 2 就 post 完，Step 4 只用 `EnterPlanMode` / `ExitPlanMode` 這兩個 mode-control tool。

`ExitPlanMode` 的 plan 內容：

```markdown
# Implementation Plan: Issue #NNN

(貼上 Step 2 起草的完整 Implementation Plan markdown)

---

**Approval semantics**:
- ✅ Approve → 解除 plan mode，chain to /idd-implement，TDD loop 開始執行
- 📝 Revise → 我會根據你的 feedback 修改 Plan comment，再次進入 plan mode 等 approve
- ❌ Reject / abort → idd-update phase 改為 needs-fix，結束本次 idd-plan 執行；user 後續可手動修 diagnosis 或重新評估 Complexity
```

### Step 5: Handle Plan Mode Response

`ExitPlanMode` 回傳 user 的選擇：

| User response | 行為 |
|---------------|------|
| Approved | 進 Step 6 — chain to `/idd-implement` |
| Revised (with feedback) | 修改 Implementation Plan comment（用 `gh api PATCH` 更新原 comment 而非新 comment 避免散亂），再次 `EnterPlanMode` 呈現新版 |
| Aborted | 跑 `/idd-update #NNN` 改 phase 為 `needs-fix`，並 post 一個 comment 說明「Plan tier deliberation 中止：{reason}；建議重新 `/idd-diagnose #NNN` 或調整 Complexity」 |

### Step 6: Chain to /idd-implement

> **`type=meeting` → 跳過本步（skip-chain，#57）**：meeting 是 user-driven deliberation，不是 TDD loop。`type=meeting` 的 plan 用 **meeting-adapted Plan body** schema（Phase A/B/C 審議計畫：議程 → 決策點 → 行動項，非 code-centric 的 Files & Changes），且 **不 chain 到 /idd-implement**（輸出不含對 `/idd-implement` 的邀請 / 呼叫）。plan 過 user approve 後即結束於 deliberation artifact；closing 走 decision→action mapping、無 `/idd-verify` TDD pass（見 idd-close）。以下 chain 僅適用於 code-centric（bug / feature / refactor）plan。

User approved → invoke idd-implement skill 繼續 TDD loop：

```
Skill(skill="issue-driven-dev:idd-implement", args="#NNN")
```

idd-implement 會偵測到 issue 已有 `## Implementation Plan` comment（Step 2 post 的），跳過自己 Step 2 的 plan drafting，直接進 Step 2.5 bootstrap TaskList + Step 3 TDD loop。

> **為什麼 chain 而不是把 idd-implement 的內容 inline？** 保持 single source of truth — idd-implement 的 TDD discipline / scope guard / commit conventions / PR flow 全部由 idd-implement 定義，idd-plan 只在前面加 approval gate。Inline 會 drift。

### Step 7: Auto-Update Issue Body

idd-implement 結束後，已自帶 idd-update 同步（phase → `implemented`）。但 idd-plan 自己也要在 Step 4 之後立刻跑一次 idd-update（phase → `planning`）標記「已 enter plan mode」這個中間狀態：

```
Skill(skill="issue-driven-dev:idd-update", args="#NNN")
```

phase 流程：`diagnosed` → (idd-plan Step 4 completed) `planning` → (idd-implement done) `implemented` → (verify) `verified` → (close) `closed`

## 鐵律

- **不跳過 EnterPlanMode**。AskUserQuestion 是不夠的 — 它只是 yes/no 確認，agent 仍有「忘了就動手」的可能。`EnterPlanMode` 用 runtime constraint 強制 read-only。
- **Implementation Plan 必須先 post 到 issue 才 enter plan mode**。Plan mode 期間不能 post，沒先 post 就沒 audit trail。
- **不在 plan mode 期間呼叫 stateful tools**。Runtime 會 reject，但更重要的是 design intent — plan mode 是 deliberation moment，不是 execution moment。
- **Aborted 不直接 close issue**。User 可能只是「現在不想做」，不是「永遠不做」。phase 改 `needs-fix` 而非 `closed`，留 escape hatch。
- **Revise 用 PATCH 更新原 comment 而非新 comment**。多個 plan 版本散在 issue timeline 會干擾 idd-close 的 checklist gate（gate 只看最後一個 `## Implementation Plan`，但 user 看 issue 會困惑哪個是 final）。

## Auto-Update

- Step 4 completed → `idd-update` phase → `planning`
- 整個 idd-plan 結束（含 chain to idd-implement 完成）→ idd-implement 自帶的 auto-update 把 phase 推到 `implemented`

## Next Step

idd-plan 結束 = idd-implement 結束。所以 next step 沿用 idd-implement 的 next step：

```
/issue-driven-dev:idd-verify #NNN
```

## 與 idd-implement 的關係

idd-plan 不取代 idd-implement，它是 idd-implement 的 superset：

```
idd-plan #NNN
  ├─ Step 1-3: read + draft + post Implementation Plan
  ├─ Step 4: EnterPlanMode → user reviews → ExitPlanMode (approve / revise / abort)
  └─ Step 6: → idd-implement #NNN
              ├─ Step 0-1: bootstrap + read (re-read same issue, plan already posted)
              ├─ Step 2: SKIP (existing plan detected)
              ├─ Step 2.5: bootstrap TaskList
              ├─ Step 3: TDD loop
              ├─ Step 4: scope guard
              ├─ Step 5: checklist sync + Implementation Complete comment
              └─ Step 5.5: PR (if PR path) / Step 6: idd-update phase=implemented
```

idd-implement 偵測「已有 `## Implementation Plan` comment 在 issue 上」就跳過自己的 Step 2，避免 plan duplication。

## 與 idd-all 的整合

`idd-all` Phase 3 的 routing 也會新增 Plan path（v2.36.0+）：

```
| Complexity 值 | Phase 3 行為 |
|--------------|-------------|
| Simple       | Phase 3a: idd-implement --pr |
| Plan         | Phase 3p: idd-plan --pr (chains to idd-implement --pr internally) |
| Spectra      | Phase 3b: spectra-discuss → spectra-propose → spectra-apply (unattended chain) |
```

unattended idd-all 模式下，idd-plan 的 EnterPlanMode 會被怎麼處理？— **idd-all 不該走 Plan path**。Plan tier 的核心價值是 user approval，unattended 直接跳過 = 退化成 Simple。idd-all Phase 3 看到 Complexity=Plan 應該 fallback 走 Simple path（idd-implement 直接），並在 final report 標記「Plan tier deliberation skipped under unattended mode」。
