**GitHub-side tracker**: #607（verify 第 2 輪的修正）

## Why

#607 第 2 輪 verify 找到：

1. `effective_rounds()` 把 `last_gate` 缺欄當成完整，與規格「兩筆都記為完整」不符。舊版 gate 重讀同一份報告時寫的 `last_gate` 沒有這兩欄，`next` 可能又預告 close stage 不會做的合併。
2. 沒有測「round 記為不完整、最新讀取變完整」的方向。
3. reviewers 重讀沒有經過 gate 的測試。

## What Changes

- `scripts/lib/stopmode.py`：最新讀取沒有這一欄時不算確認完整。
- 測試：`last_gate` 缺欄、兩個方向的重讀（coverage 與 reviewers，都經過 gate）；新的 `edit_last_report` 輔助函式。
- 規格：同一個 requirement 補一句與 Example 的列。

## Non-Goals

- 沒有停止模式時的行為不變。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：同一個 requirement。

## Impact

- Affected specs: `idd-pr-hitl-modes`
- Affected code: plugins/issue-driven-dev/scripts/lib/stopmode.py, plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh
