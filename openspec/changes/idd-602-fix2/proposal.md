**GitHub-side tracker**: #602（verify 第 2 輪的修正）

## Why

#602 verify 第 2 輪（Claude reviewers）：後備計數的 run 有一輪沒記進紀錄，close stage 看不出來，能不能合併只靠 Phase 4 的記憶；規格一邊寫「不合併」一邊在 Example 允許第 2 輪合併。另有：紀錄被刪掉時不算 replaced、replaced 的停下會清掉取代者的狀態、後備也接手了「修正答案記不下」的停下、reset 的鎖帶來新的失敗與副作用、幾個測試沒有走到它標的 Example。

## What Changes

- `close-stage.py`：gate 列出這次 run 的 verify 報告 id，`merge_gate` 遇到不在紀錄裡的報告就不合併（有沒有停止模式都一樣）；讀的紀錄被刪掉也算 replaced；`reset` 沒東西可刪時什麼都不建、鎖拿不到時照刪並警告；`init` 的鎖拿不到時回錯誤訊息。
- `skills/idd-all/SKILL.md` Phase 4：replaced 改走 `stop_replaced`，不做 abort 的清理；自己數輪數只在 round 0 開始；這一段不再決定合併。
- 測試：close-stage 的 ledger、刪除即 replaced、reset 等鎖再刪、reset 與 init 的鎖、late-pr-check 的等待；`idd-all-phase4-count` 的新情境。

## Non-Goals

- 跨輪的 run 身分（#618）。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：兩個 requirement。

## Impact

- Affected specs: `idd-pr-hitl-modes`
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/close-stage.py, plugins/issue-driven-dev/skills/idd-all/SKILL.md, plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh, plugins/issue-driven-dev/scripts/tests/idd-all-phase4-count/test.sh
  - New: none
  - Removed: none
