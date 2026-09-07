## Why

> **第 2 輪 re-baseline（2026-08-15）**：`/idd-verify --pr 318` FAIL（2 CRITICAL / 21 HIGH）。CRITICAL-2 以 90 筆真實語料證偽第 1 輪的封閉值域前提；`/idd-reorganize #316` 完成裁定；`/idd-diagnose #316` 第 2 輪以 **159 筆完整 corpus** 重新定出值域規則（158/158，0 false positive）。本 proposal 的 What Changes / Impact 已依該結論重寫；design D1/D3/D5 與 spec R1/R3/R7 同步重寫，其餘決策經裁定為 still-valid 而保留。
>
> **Re-scope note（2026-08-14）**：本 change 於 #298 仍 open 時提出。走完 discuss → propose、進入 apply 時發現 **#298 已由 PR #309 / #306 修掉並 close** —— 但修正**只落在 `idd-list`**，另三個 consumer（`idd-all` / `idd-implement` / `idd-plan`）未動，且 `idd-list` 自身 Step 5 仍文載會截斷的 regex，與新增的 Step 3.7 直接矛盾。本 change 遂 re-scope 為**承接剩餘缺口**，追蹤於 **#316**；已完成的共用 helper、canonical 契約與回歸測試（全新檔、與已 merge 內容零衝突）原樣保留。Migration 相關 task 因目標 issue 全數 close 而 moot。


2026-08-10 對本 repo 真實的 22-issue backlog 跑 `/idd-list`，routing 把 **8 個 parked/deferred/blocked issue 判成「Actionable now」**（11 個 diagnosed 裡只有 1 個判對）。其中 #131 與 #200 帶有使用者 2026-07-07 親自下的 defer 裁決 —— 照 routing 執行等於自動推翻已記錄的人為決策。失敗是**靜默的**：輸出的表格語法正確、格式正常、沒有任何 warning。

`/idd-diagnose #298` 的 root cause：**`### Complexity` 的值域從未被定義為封閉列舉，也沒有「unparseable → 保守 + surface」契約** —— 而結構相同的姊妹欄位 `### Conflict Class` 兩者都有（見 openspec/specs/parallel-orchestration/spec.md）。producer 寫出 `Simple when triggered` 並未違反任何明文規則，於是三個 consumer 各自發明了互不相容的窄化方式：`idd-list` 靜默截斷成 `Simple`；`idd-all` 與 `idd-implement` 得到非法字串，既不匹配任何 dispatch row 也不是 `UNKNOWN`，落入未定義行為（既有的 `UNKNOWN` 安全網只在 regex 完全沒 match 時觸發，結構上接不住此案例）。

更深一層：**把會變的狀態存進不可變的 artifact**。`### Complexity` 活在 append-only 的 Diagnosis comment 裡，但 parked 是會變的狀態（trigger 一成立就該 unpark）。#136 的 comment 寫 bare `Spectra`、body 寫 `Spectra when triggered (parking lot)`，正是狀態被凍住後自己漂移出去的自然實驗。IDD 其實已經知道正確做法 —— `### Blocking` 正因為會變才放在 body 由 `idd-update` 維護。

## What Changes

- **`### Complexity` 的 tier 以 prefix 抽取，容許同行理由** —— 剝裝飾 → 取 ` via ` 之前的 tier prefix → tier 須為 `Simple` / `Plan` / `Spectra` / `SDD-warranted` 之一。tier 之後的理由、括號說明、provenance 後綴**皆為合法**，不影響抽取。
- **延期以語彙偵測，並有獨立 reason** —— 對**整個值**掃 `when triggered` / `parking lot` / `deferred` / `暫緩`，命中則不路由，reason 為 `complexity-deferral-marker`（與 `complexity-unparseable` 分離 —— 前者是正常狀態、後者是資料錯誤，人的處置不同）。
- **`parking-lot` label 是 parked 的主要訊號**，延期語彙是次要安全網。語彙清單取高精度、容忍低召回。
- **新增 actionability gate** —— 三訊號 OR 判定（Complexity 不可路由、`parking-lot` label、`### Blocking` 非空），放行需三者皆不成立，**且四個 consumer 必須實際呼叫它**。
- **三個 consumer 的 Complexity 解析統一** —— `idd-list`、`idd-all`、`idd-implement`（含 `idd-plan` 的 tier 確認）改用共用 helper，消除各自窄化。
- **`### Blocking` 抽取重構為 gate 的 input** —— #84 既有的 Blocked 分組輸出行為不得退化。
- **`idd-diagnose` producer 端明訂延期意圖走 label** —— 不再宣告封閉值域；改為「tier 寫清楚、延期貼 label、不要把延期寫進本欄」。
- **零 migration** —— 新規則對既有 159 筆語料 158/158 全對，不需回填 label、不需改寫任何 Diagnosis comment。
- **`references/ic-r011-checkpoint.md` 的 parking 慣例收斂** —— `blocker:infeasible` / `blocker:waiting` 目前 0 個 issue 在用，實際在用的是 `parking-lot`。

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
- 追蹤 issue 由 #298 改為 **#316**（#298 已由 PR #309 / #306 修掉並 close，只涵蓋 `idd-list`）。
- 配套 issue：#310（parked issue 無回訪機制）—— 本變更把 parked 藏得更乾淨，會放大該問題，但不在本次範圍內。
