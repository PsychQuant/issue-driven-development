**GitHub-side tracker**: #607（verify 第 3 輪的修正）

## Why

#607 第 3 輪 verify 找到：gate 重讀同一份報告時發現某一行不完整，只套用在最新一輪的暫存副本；下一輪記錄後，上一輪又退回初讀的值，跨輪比較就不算那個缺口（例如 `early` 的 `2 → 1` 變成 `1 → 1`，停下並合併）。另外，規格寫 `next` 只根據 mode 與 round record 回答，實際也讀 `last_gate`。

## What Changes

- `scripts/close-stage.py` 的 `record_round`：重讀已記錄的報告時，把那一行的完整與否和那一輪的紀錄取「且」，不完整就一直不完整；計數不變、不新增 round。
- 規格：`next` 的來源寫成 run-state 紀錄（mode、round record 與最新的 gate 結果）；補上重讀之後那一輪保持不完整的規則與一列 Example。
- 測試：重讀之後再記錄下一輪（經過 gate）。

## Non-Goals

- 沒有停止模式時的行為不變。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：同一個 requirement。

## Impact

- Affected specs: `idd-pr-hitl-modes`
- Affected code: plugins/issue-driven-dev/scripts/close-stage.py, plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh
