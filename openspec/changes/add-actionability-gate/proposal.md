## Why

> **Re-scope note（2026-08-14）**：本 change 於 #298 仍 open 時提出。走完 discuss → propose、進入 apply 時發現 **#298 已由 PR #309 / #306 修掉並 close** —— 但修正**只落在 `idd-list`**，另三個 consumer（`idd-all` / `idd-implement` / `idd-plan`）未動，且 `idd-list` 自身 Step 5 仍文載會截斷的 regex，與新增的 Step 3.7 直接矛盾。本 change 遂 re-scope 為**承接剩餘缺口**，追蹤於 **#316**；已完成的共用 helper、canonical 契約與回歸測試（全新檔、與已 merge 內容零衝突）原樣保留。Migration 相關 task 因目標 issue 全數 close 而 moot。


2026-08-10 對本 repo 真實的 22-issue backlog 跑 `/idd-list`，routing 把 **8 個 parked/deferred/blocked issue 判成「Actionable now」**（11 個 diagnosed 裡只有 1 個判對）。其中 #131 與 #200 帶有使用者 2026-07-07 親自下的 defer 裁決 —— 照 routing 執行等於自動推翻已記錄的人為決策。失敗是**靜默的**：輸出的表格語法正確、格式正常、沒有任何 warning。

`/idd-diagnose #298` 的 root cause：**`### Complexity` 的值域從未被定義為封閉列舉，也沒有「unparseable → 保守 + surface」契約** —— 而結構相同的姊妹欄位 `### Conflict Class` 兩者都有（見 openspec/specs/parallel-orchestration/spec.md）。producer 寫出 `Simple when triggered` 並未違反任何明文規則，於是三個 consumer 各自發明了互不相容的窄化方式：`idd-list` 靜默截斷成 `Simple`；`idd-all` 與 `idd-implement` 得到非法字串，既不匹配任何 dispatch row 也不是 `UNKNOWN`，落入未定義行為（既有的 `UNKNOWN` 安全網只在 regex 完全沒 match 時觸發，結構上接不住此案例）。

更深一層：**把會變的狀態存進不可變的 artifact**。`### Complexity` 活在 append-only 的 Diagnosis comment 裡，但 parked 是會變的狀態（trigger 一成立就該 unpark）。#136 的 comment 寫 bare `Spectra`、body 寫 `Spectra when triggered (parking lot)`，正是狀態被凍住後自己漂移出去的自然實驗。IDD 其實已經知道正確做法 —— `### Blocking` 正因為會變才放在 body 由 `idd-update` 維護。

## What Changes

- **`### Complexity` 回歸純封閉值域** —— 合法值僅 `Simple` / `Plan` / `Spectra` / `SDD-warranted`，各自可帶既有的 ` via <來源>` 後綴慣例。`when triggered` 這類限定詞不再寫進此欄位。**BREAKING**：既有 9 筆帶限定詞的 diagnosis 值在新契約下為非法，需 migration。
- **parked 狀態改由 `parking-lot` label 單獨承載** —— 人可貼可撕，成為唯一 source of truth。實測 11 個 issue 中限定詞與 label 只有 5 個一致，證明兩者不是重複而是會分岔的兩個訊號。
- **新增 actionability gate** —— 三訊號 OR 判定，放行需三者皆不成立：`### Complexity` 非合法值、`parking-lot` label 存在、`### Blocking` 區塊非空。
- **default-on-unparseable = not-actionable + surface** —— 對稱於 `### Conflict Class` 的 `D_diagnose_first` 契約：不放行、必須顯示原始值、絕不靜默。
- **三個 consumer 的 Complexity 解析統一** —— `idd-list`、`idd-all`、`idd-implement`（含 `idd-plan` 的 tier 確認）改用共用 helper，消除各自窄化。
- **`### Blocking` 抽取重構為 gate 的 input** —— #84 既有的 Blocked 分組輸出行為不得退化。
- **`idd-diagnose` producer 端宣告封閉值域** —— 明訂限定詞不得寫入，parked 意圖改以 label 表達。
- **既有 9 筆 diagnosis migration** —— 8 筆機械處理（剝限定詞、必要時補 label）、#128 需人重新判斷（其值為散文，非 tier 加限定詞結構）。
- **`references/ic-r011-checkpoint.md` 的 parking 慣例收斂** —— 該檔宣稱的 `blocker:infeasible` 與 `blocker:waiting` 目前 0 個 issue 在用，實際在用的是 `parking-lot`（6 個）。

## Capabilities

### New Capabilities

- `actionability-gate`: 定義 `### Complexity` 的封閉值域、parked 狀態的歸屬（label 而非 comment）、三訊號 actionability gate 的判定規則，以及 unparseable 時的保守處置與強制 surface。

### Modified Capabilities

(none)

為何無 modified capability：硬閘與 Layer V 這兩份既有 spec 所產出的帶後綴 verdict（形如 tier 後接 " via " 再接來源）在新封閉值域下**仍為合法值**，其 requirement 不需修改；conflict-class 規範對 Complexity 欄位的正交性敘述同樣維持成立。

## Impact

- Affected specs: 新增 `actionability-gate`
- Affected code:
  - New:
    - `plugins/issue-driven-dev/references/actionability-gate.md`
    - `plugins/issue-driven-dev/scripts/lib/actionability.sh`
    - `plugins/issue-driven-dev/scripts/tests/actionability-gate/test.sh`
    - `plugins/issue-driven-dev/scripts/tests/actionability-gate/fixtures/parked-routing.json`
  - Modified:
    - `plugins/issue-driven-dev/skills/idd-list/SKILL.md`
    - `plugins/issue-driven-dev/skills/idd-all/SKILL.md`
    - `plugins/issue-driven-dev/skills/idd-implement/SKILL.md`
    - `plugins/issue-driven-dev/skills/idd-plan/SKILL.md`
    - `plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md`
    - `plugins/issue-driven-dev/references/ic-r011-checkpoint.md`
  - Removed: (none)
- 同檔衝突：#299（`--limit` 先於排序生效）同樣修改 `plugins/issue-driven-dev/skills/idd-list/SKILL.md`，兩者需序列化或合併處理。
- 配套 issue：#310（parked issue 無回訪機制）—— 本變更把 parked 藏得更乾淨，會放大該問題，但不在本次範圍內。
