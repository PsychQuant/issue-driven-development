**GitHub-side tracker**: #607（verify 第 1 輪的修正）

## Why

#607 第 1 輪 verify 找到五列：

1. 沒有停止模式的 run，`next` 給的每輪 to-fix count 也加了覆蓋率的缺口。
2. gate 再讀同一份報告、發現某一行變得不完整時，`next` 仍照先前記下的值回答，可能又預告 close stage 不會做的合併。
3. 測試只直接寫入 run-state，沒有經過 gate 把報告的那兩行帶到 `next`。
4. 測試只斷言決定，沒有斷言調整後的計數。
5. 第一個 change 的規格 delta 只帶了這個 requirement 的前半段，封存後刪掉了與 #607 無關的 Scenario、Example 與 `@trace`。

## What Changes

- `scripts/lib/stopmode.py`：覆蓋率缺口只在停止模式的表裡計入；最新一輪的兩行，要 round 與同一份報告最新一次的讀取都記為完整才算完整。
- `scripts/close-stage.py`：gate 的 `last_gate` 也記下兩行完不完整。
- 測試：經過 gate 的三組、計數的斷言、沒有停止模式的計數、同一份報告重讀。
- 規格：以 origin/main 上完整的 requirement 為底，只加入 #607 的內容，補回被刪掉的部分。

## Non-Goals

- 沒有停止模式時的停止與合併判斷不變。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：同一個 requirement。

## Impact

- Affected specs: `idd-pr-hitl-modes`
- Affected code: plugins/issue-driven-dev/scripts/lib/stopmode.py, plugins/issue-driven-dev/scripts/close-stage.py, plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh
