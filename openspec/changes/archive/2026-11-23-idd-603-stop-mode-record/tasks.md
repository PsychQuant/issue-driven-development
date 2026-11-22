## 1. 測試先寫

- [x] 1.1 requirement「A run with a stop mode leaves a record of how its verify loop ended」：新測試套件 `scripts/tests/stop-mode-log/test.sh`——`append` 對五種情況寫或不寫（Example 的五列）；同一個 run 寫兩次，`summary` 只算一次；Phase 4 的 `next` 區塊配假的 `close-stage.py` 跑，寫出紀錄；紀錄路徑寫不進去時印警告、`NEXT_JSON` 與 `NEXT_RC` 不變。帶標記 `spec-example: idd-pr-hitl-modes / what append writes`。驗證：寫程式前這些斷言失敗。

## 2. 實作

- [x] 2.1 [after: 1.1] `scripts/stop-mode-log.py`：`append`、`summary`；紀錄檔 `~/.claude/.idd/stop-mode-runs.jsonl`（`IDD_STOP_LOG` 可改）；run-state 用 `close-stage.py` 的 `read_state` 讀。驗證：1.1 中 `append` 與 `summary` 的情境通過。
- [x] 2.2 [after: 2.1] `skills/idd-all/SKILL.md` Phase 4 的 `next` 區塊呼叫 `append`，失敗只警告；`references/config-protocol.md` 的 `verify_stop` 一節說明紀錄與 `summary`。驗證：1.1 中 Phase 4 區塊的情境通過。

## 3. 回歸

- [x] 3.1 [after: 2.1, 2.2] 新套件與 `run-all-tests.sh` 全過。
