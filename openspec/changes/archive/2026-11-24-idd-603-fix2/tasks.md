## 1. 實作

- [x] 1.1 requirement「A run with a stop mode leaves a record of how its verify loop ended」：測試先寫（空的 `--gate`、遺失 `GATE_JSON` 的 Phase 4 區塊、不是 UTF-8 的行、非物件的 rounds、預設紀錄路徑、模式與 to-fix 的跳脫，權限改用 python 讀），再改 `stop-mode-log.py` 與 `skills/idd-all/SKILL.md`。驗證：新檢查在舊程式上失敗；`bash plugins/issue-driven-dev/scripts/tests/stop-mode-log/test.sh` 通過。

## 2. 回歸

- [x] 2.1 [after: 1.1] 整套測試通過（`bash plugins/issue-driven-dev/scripts/run-all-tests.sh`）。
