## 1. 實作

- [x] 1.1 requirement「A run with a stop mode leaves a record of how its verify loop ended」：測試先寫（`next` 回 `replaced`、gate 回 `replaced` 而 `next` 的回答沒有旗標、Phase 4 區塊遇到 replaced 的 gate、紀錄檔 0600、拒絕 symbolic link、形狀不對的行、跳脫的理由、不寫 bytecode），再改 `stop-mode-log.py`、`skills/idd-all/SKILL.md` 的 Phase 4 呼叫與 `references/config-protocol.md`。驗證：13 個新檢查在舊程式上失敗；`bash plugins/issue-driven-dev/scripts/tests/stop-mode-log/test.sh` 通過。

## 2. 回歸

- [x] 2.1 [after: 1.1] 整套測試通過（`bash plugins/issue-driven-dev/scripts/run-all-tests.sh`）。
