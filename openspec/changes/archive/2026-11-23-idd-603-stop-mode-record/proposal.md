**GitHub-side tracker**: #603

## Why

#595 加了三種停止模式，但跑完的 run 沒有留下可以量的東西：每一輪的計數只在本機的 run-state 裡，24 小時後不讀、下一次同一張 issue 的 `reset` 就刪掉；run report 的 `stop mode:` 那一行只印在對話裡。要回答每種模式值不值得，先要每個 run 留一筆紀錄。

## What Changes

- 新的 `scripts/stop-mode-log.py`：`append` 在有停止模式的 run 收到 `fix` 以外的 `next` 回答時寫一行 JSON（repo、issue、run 的 `created_at`、模式、決定、是否合併、`decided`、原因、每一輪的計數與報告 id）；`summary` 依模式彙整（run 數、合併數、每個 run 的輪數、to-fix 序列、停下原因），同一個 run 取最後一行。
- 紀錄檔放在所有 repo 之外：`~/.claude/.idd/stop-mode-runs.jsonl`（`IDD_STOP_LOG` 可改）。
- idd-all Phase 4 跑 `next` 的那個 bash 區塊呼叫 `append`；寫失敗只印警告，不改變 run。
- `references/config-protocol.md` 的 `verify_stop` 一節說明紀錄在哪、怎麼讀。

## Non-Goals

- 不推算每一輪修掉幾個、新找到幾個（紀錄留報告 id，之後可以從報告算）。
- 不追蹤合併後是否需要後續 issue，也不寫每種模式的建議；這兩項要等真的 run，留作後續。
- 不改 `close-stage.py`。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：新增「A run with a stop mode leaves a record of how its verify loop ended」。

## Impact

- Affected specs: `idd-pr-hitl-modes`
- Affected code:
  - Modified: plugins/issue-driven-dev/skills/idd-all/SKILL.md, plugins/issue-driven-dev/references/config-protocol.md
  - New: plugins/issue-driven-dev/scripts/stop-mode-log.py, plugins/issue-driven-dev/scripts/tests/stop-mode-log/test.sh
  - Removed: none
