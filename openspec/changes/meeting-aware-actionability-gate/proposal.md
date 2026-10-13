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

- 共用 helper 新增 `idd_issue_type`：照 `/idd-diagnose` Step 1 的順序解析 issue type（GitHub label 優先；label 沒有 type 時讀 body 的 `## Type`；兩者衝突時 label 勝；都沒有時回 `unknown`，視為非 meeting）
- `idd_actionability_verdict` 新增選填 `--issue-type` 與 `--diagnosis-present yes|no`（後者在 `meeting` 時必填，verify r1 加入）：`meeting` 且有受信任的 Diagnosis 時不評 complexity 訊號，`parking-lot` label 與 `### Blocking` 照評；沒有 Diagnosis 的 meeting 照常回報 `complexity-missing`；未傳 type 或其他值時行為與現在逐 byte 相同
- 四份 gate block（`idd-implement` 兩份、`idd-plan`、`idd-all`）以相同改法加入 type 解析並把 type 傳入 verdict；機器行加 `TYPE=` 欄位
- 呼叫端依 type 先分派：
  - `idd-all`：attended → 送 meeting 版 `/idd-plan`；unattended → 停在 diagnosed 並記一條 Action item；兩種模式都不進 implement、verify，也不開 PR
  - `idd-plan`：meeting → 產出 Meeting Plan
  - `idd-implement`：meeting → 以 meeting 專屬訊息拒絕
  - `idd-list`：meeting 判定 actionable 時依 phase 給下一步（`diagnosed` → `/idd-plan`，已有 Meeting Plan → `/idd-close`）
- `idd-update` 的 phase 表加 `## Meeting Plan` → `planning`
- 規格：actionability-gate 與 meeting-issue-type 各補 requirement 並互相引用；`references/actionability-gate.md` 補上 meeting 的處理

**假設（unattended 下未經人確認，可挑戰）**：meeting 在 unattended 模式不跑 `/idd-plan`，因為 Meeting Plan 的核准閘門需要人在場；若 maintainer 希望 unattended 也產出 Meeting Plan 草稿，只需改 `idd-all` 的分派列，不影響 helper。

## Success Criteria

- 一份 meeting Diagnosis（Complexity 寫說明句，或沒有 Complexity 段）、沒有 `parking-lot` label、`### Blocking` 為空 → `idd_actionability_verdict --issue-type meeting --diagnosis-present yes` 回 exit 0；同一個 issue 若完全沒有受信任的 Diagnosis（`--diagnosis-present no`）→ `complexity-missing`、歸 undiagnosed
- 同上但有 `parking-lot` label → exit 1，reason 為 `parking-lot-label`；`### Blocking` 非空 → exit 1，reason 為 `blocking-nonempty`
- 未傳 `--issue-type`，或傳任何非 meeting 的 type（`bug`、`feature`、`refactor`、`docs`、`unknown`）時，`corpus-complexity.json`、`corpus-blocking.json`、`parked-routing.json` 三份 fixture 的判定逐筆不變
- `idd_issue_type`：label `meeting` → `meeting`；label 沒有 type 而 body `## Type` 為 meeting → `meeting`；label `bug` 而 body 寫 meeting → `bug`；都沒有 → `unknown`
- 四份 gate block 仍逐 byte 相同，`scripts/tests/actionability-gate/test.sh` 全數通過
- `idd-update`：最新的 phase comment 是 `## Meeting Plan` 時推為 `planning`

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `actionability-gate`: verdict 新增 issue type 輸入；type=meeting 不評 complexity 訊號；issue type 解析納入共用實作
- `meeting-issue-type`: 新增 orchestrated routing 的要求（`idd-all`、`idd-list`、`idd-implement`、`idd-update` 對 meeting issue 的行為）

## Impact

- Affected specs: actionability-gate, meeting-issue-type
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/lib/actionability.sh, plugins/issue-driven-dev/scripts/tests/actionability-gate/test.sh, plugins/issue-driven-dev/references/actionability-gate.md, plugins/issue-driven-dev/skills/idd-all/SKILL.md, plugins/issue-driven-dev/skills/idd-plan/SKILL.md, plugins/issue-driven-dev/skills/idd-implement/SKILL.md, plugins/issue-driven-dev/skills/idd-list/SKILL.md, plugins/issue-driven-dev/skills/idd-update/SKILL.md, plugins/issue-driven-dev/CHANGELOG.md, plugins/issue-driven-dev/.claude-plugin/plugin.json
  - New: plugins/issue-driven-dev/scripts/tests/actionability-gate/fixtures/meeting-routing.json
