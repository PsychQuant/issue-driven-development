**GitHub-side tracker**: #603（verify 第 3 輪的修正）

## Why

#603 verify 第 3 輪（Claude reviewers）：`GATE_JSON` 在 Claude Code 每一輪幾乎都會遺失（gate 與 next 是兩次 Bash 呼叫），第 2 輪要模型從輸出手抄回來，而 gate 的理由常含撇號，手抄容易壞；壞掉的、不是物件的 gate 回答又被當成「沒有被取代」而寫入。另外，空 gate 的警告在 fix 答案、沒有 stop mode 的 run 也會出現，模型照提示重跑區塊會再問一次 `next`，fix 就變成 stop，等於改變了 run。測試也沒有檢查 `decision`、`decided`，以及文字輸出真的印出跳脫後的內容。

## What Changes

- `skills/idd-all/SKILL.md` Phase 4：gate 區塊把回答寫進 `.claude/.idd/state/idd-all-gate-<N>.json`；`next` 區塊以 `--gate-file` 傳給 `append`，並說明不要為了沒寫的紀錄重跑；Phase 6 清理一併刪掉這個檔。
- `scripts/stop-mode-log.py`：先處理所有不寫的情況（fix、replaced、沒有 run state、沒有 stop mode），不讀 gate、不印訊息；之後 gate 的回答缺少、空的、不是 JSON、不是物件、或 round 與 `next` 不同，都不寫並說明；檔尾沒有換行時先補一個。
- `references/config-protocol.md`：gate 檔與不寫的情況。
- 測試 `scripts/tests/stop-mode-log/test.sh`：上述情況、`decision`／`decided`、跳脫後的文字、預設路徑測試清掉 `IDD_STOP_LOG`、gate 區塊寫檔。
- 規格 `idd-pr-hitl-modes`：上述行為。

## Non-Goals

- 在 verify 期間就被取代的 run：#622（要 #618 的 run identity）。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：一個 requirement。

## Impact

- Affected specs: `idd-pr-hitl-modes`
- Affected code: plugins/issue-driven-dev/scripts/stop-mode-log.py, plugins/issue-driven-dev/skills/idd-all/SKILL.md, plugins/issue-driven-dev/references/config-protocol.md, plugins/issue-driven-dev/scripts/tests/stop-mode-log/test.sh
