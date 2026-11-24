**GitHub-side tracker**: #602（verify 第 1 輪的修正）

## Why

#602 verify 第 1 輪（Claude reviewers）找到 Phase 4 後備數法的三個缺陷：第二輪起又拿 `next` 的輪數（它只數記下的輪），寫入一直失敗時沒有輪數上限、失敗一次時第三輪可以合併；另一個 `/idd-all` 換掉紀錄時，舊的 run 走同一條後備繼續修正與推送。另有 `reset` 不拿鎖，以及幾個沒有測試的規格條文。

## What Changes

- `close-stage.py`：`Replaced` 例外；gate 與 `next` 因替換被拒時答案帶 `replaced: true`；`reset` 在鎖內刪除。
- `skills/idd-all/SKILL.md` Phase 4：`replaced` 一律停下；一旦後備自己數，整個 run 都自己數。兩段放在標記之間，由新測試執行。
- 測試：close-stage 套件補上 init、`next` 修正答案、`reset` 拿鎖，等鎖，非法的 `verify_stop` 值，gate 寫不進去之後 `next` 未決，替換的標記；新套件 `idd-all-phase4-count`。

## Non-Goals

- 跨輪的 run 身分（Phase 4 帶自己的 `run_id` 給每一次 gate 與 `next`）另開 follow-up。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：兩個 requirement。

## Impact

- Affected specs: `idd-pr-hitl-modes`
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/close-stage.py, plugins/issue-driven-dev/skills/idd-all/SKILL.md, plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh
  - New: plugins/issue-driven-dev/scripts/tests/idd-all-phase4-count/test.sh
  - Removed: none
