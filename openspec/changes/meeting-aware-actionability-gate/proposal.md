## Problem

`type=meeting` 的 issue 經 `/idd-diagnose` 依 meeting 分支寫出 Diagnosis 後，`/idd-all` Phase 2 與 `/idd-plan` Step 1 的 actionability gate 一律判為不可路由：Complexity 段寫一句說明時是 `complexity-unparseable`，不寫 Complexity 段時是 `complexity-missing`。

- `/idd-all` 因此 abort，並要求使用者「修正 Diagnosis」，但那份 Diagnosis 是照 meeting 規格寫的，沒有東西可修
- `/idd-plan` 產不出 meeting-issue-type 規格要求的 Meeting Plan
- `/idd-list` 把 meeting issue 歸到 parked（unparseable）或 undiagnosed（missing，並建議重跑 diagnose），下一步都是錯的
- `/idd-update` 的 phase 表不認得 `## Meeting Plan`，meeting issue 的 phase 永遠停在 `diagnosed`

結果是 meeting issue 走不完任何 orchestrated 路徑，執行者只能違反 gate 的文字自行繞過（#383）。

## Root Cause

actionability gate（#316，2026-10-06）把可路由的 `### Complexity` 值域定為 `Simple` / `Plan` / `Spectra` / `SDD-warranted` 四個 tier，而 `idd_actionability_verdict` 只收 `--complexity-exit`、`--parking-label`、`--blocking-section` 三個訊號，沒有 issue type。meeting 類型（#57，2026-07-07）依 meeting-issue-type 規格刻意不產生 tier。兩份規格互不引用，gate 的回歸語料也沒有任何 meeting Diagnosis，所以 #316 的測試全綠也抓不到這個衝突。

## Proposed Solution

- 共用 helper 新增 `idd_diagnosis_type`：讀最新受信任 Diagnosis（作者為 OWNER／MEMBER／COLLABORATOR）的 `### Type`，回 `bug`／`feature`／`refactor`／`docs`／`meeting`／`unknown`；沒有 Diagnosis 時回 `none`。type 只信這一份文字：issue 本文由 issue 作者自由改寫，不能決定路由（verify r4 之後的 maintainer 裁決，2026-10-14；前四輪的 `idd_issue_type` 讀 label 與本文，已移除）
- `idd_actionability_verdict` 新增選填 `--diagnosis-type`：`meeting` 時不評 complexity 訊號，`parking-lot` label 與 `### Blocking` 照評；`none`（沒有 Diagnosis）照常回報 `complexity-missing`；未傳或其他值時行為與現在逐 byte 相同
- 四份 gate block（`idd-implement` 兩份、`idd-plan`、`idd-all`）以相同改法取得 Diagnosis type 並傳入 verdict；機器行加 `TYPE=` 欄位
- 呼叫端依 type 先分派：
  - `idd-all`：attended → 送 meeting 版 `/idd-plan`；unattended → 停在 diagnosed 並記一條 Action item；兩種模式都不進 implement、verify，也不開 PR；後續 phase 也只讀受信任的 Diagnosis
  - `idd-plan`：meeting → 產出 Meeting Plan
  - `idd-implement`：meeting → 以 meeting 專屬訊息拒絕
  - `idd-list`：meeting 判定 actionable 時依 phase 給下一步（非 `planning` → `/idd-plan` 或 `/idd-close`，`planning` → `/idd-close`）
- `idd-update` 的 phase 表加 `## Meeting Plan` → `planning`
- `idd-diagnose` Step 1 只在 `meeting` type label，或沒有 type label 而本文 `## Type` 宣告 meeting 且 issue 作者是 OWNER／MEMBER／COLLABORATOR 時，把 `meeting` 寫進 `### Type`；依內容推斷不得產生 meeting（verify r5：`idd-all` 每次重跑 diagnose，照抄本文會讓作者繞過 gate）
- 規格：actionability-gate 與 meeting-issue-type 各補 requirement 並互相引用；`references/actionability-gate.md` 補上 meeting 的處理

**裁決（maintainer 2026-10-14 確認，原為 unattended 下寫下的假設）**：meeting 在 unattended 模式不跑 `/idd-plan`，停在 diagnosed 並留 Action item，因為 Meeting Plan 的核准閘門需要人在場。日後若要改成 unattended 也產出 Meeting Plan 草稿，只需改 `idd-all` 的分派列，不影響 helper。

## Success Criteria

- 受信任 Diagnosis 的 `### Type` 是 meeting（Complexity 寫說明句，或沒有 Complexity 段）、沒有 `parking-lot` label、`### Blocking` 為空 → `idd_actionability_verdict --diagnosis-type meeting` 回 exit 0
- 同一個 issue 若沒有受信任的 Diagnosis（`--diagnosis-type none`）→ `complexity-missing`、歸 undiagnosed；本文寫 meeting 但 Diagnosis 寫 bug → 照 bug 判定，不放行
- 同上但有 `parking-lot` label → exit 1，reason 為 `parking-lot-label`；`### Blocking` 非空 → exit 1，reason 為 `blocking-nonempty`
- 未傳 `--diagnosis-type`，或傳任何非 meeting 的值（`bug`、`feature`、`refactor`、`docs`、`unknown`、`none`）時，`corpus-complexity.json`、`corpus-blocking.json`、`parked-routing.json` 三份 fixture 的判定逐筆不變
- `idd_diagnosis_type`：`### Type` 第一行為 `meeting` 或 `meeting（…）` → `meeting`；為 `bug` → `bug`；沒有 `### Type` → `unknown`；空字串 → `none`
- 四份 gate block 仍逐 byte 相同，`scripts/tests/actionability-gate/test.sh` 全數通過
- `idd-update`：最新的 phase comment 是 `## Meeting Plan` 時推為 `planning`
- `idd-diagnose`：沒有 type label、本文 `## Type` 宣告 meeting 的 issue，作者 association 是 OWNER／MEMBER／COLLABORATOR 時採用 meeting，其他（含查不到）不採用
- `idd-all`：Phase 2 當成 code work 分派的 run，Phase 4／5 讀到 meeting 的 Diagnosis 時停下，不 verify、不 push

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `actionability-gate`: verdict 新增 Diagnosis type 輸入；受信任 Diagnosis 為 meeting 時不評 complexity 訊號；Diagnosis type 的讀取納入共用實作
- `meeting-issue-type`: 新增 orchestrated routing 的要求（`idd-all`、`idd-list`、`idd-implement`、`idd-update` 對 meeting issue 的行為），以及 `idd-diagnose` 何時可以把 `meeting` 寫進 `### Type`

## Impact

- Affected specs: actionability-gate, meeting-issue-type
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/lib/actionability.sh, plugins/issue-driven-dev/scripts/tests/actionability-gate/test.sh, plugins/issue-driven-dev/references/actionability-gate.md, plugins/issue-driven-dev/skills/idd-all/SKILL.md, plugins/issue-driven-dev/skills/idd-plan/SKILL.md, plugins/issue-driven-dev/skills/idd-implement/SKILL.md, plugins/issue-driven-dev/skills/idd-list/SKILL.md, plugins/issue-driven-dev/skills/idd-update/SKILL.md, plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md, plugins/issue-driven-dev/CHANGELOG.md, plugins/issue-driven-dev/README.md, plugins/issue-driven-dev/.claude-plugin/plugin.json, .claude-plugin/marketplace.json, README.md
  - New: plugins/issue-driven-dev/scripts/tests/actionability-gate/fixtures/meeting-routing.json
