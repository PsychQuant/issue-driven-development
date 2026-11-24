**GitHub-side tracker**: #602

## Why

#595 verify 第 5 輪留下三項 run-state 的問題（維護者選擇合併後開成 #602）：比對 `created_at` 與寫檔之間沒有鎖，另一個 `init` 可以夾在中間，舊 gate 把整份舊紀錄寫回去；紀錄缺 `verify_stop` 欄位時被當成沒有模式；第一次 gate 寫不進紀錄時，`next` 回答無法決定，沒有模式的 run 少修一輪。另外 close-stage 套件的 `cipending` 情境在高負載下偶爾失敗。

## What Changes

- 每張 issue 一個鎖檔（`fcntl.flock`），`init`、gate 記錄一輪、`next` 記錄修正答案都在鎖內寫；`init` 寫一個隨機的 `run_id`，gate 開始時讀到的 `created_at` 與 `run_id` 在鎖內比對。
- `read_state` 要求 `verify_stop` 欄位存在，值是 `null` 或三種模式之一；否則 `next` 與 close stage 拒絕。
- `next` 印出的回答帶 `decided`；idd-all Phase 4 沒有模式的 run 在 `decided: false` 時自己數輪數。
- `cipending` 情境的等待時間不再依賴機器負載。

## Non-Goals

- 不處理 #607（`next` 對 coverage 不完整的一輪回答合併）。
- 不改停止模式的判定表。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：修改「A configured stop mode decides when the fix loop stops and whether the run merges」與「Unattended fix loop covers in-scope findings with a two-round limit」。

## Impact

- Affected specs: `idd-pr-hitl-modes`
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/close-stage.py, plugins/issue-driven-dev/skills/idd-all/SKILL.md, plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh
  - New: none
  - Removed: none
