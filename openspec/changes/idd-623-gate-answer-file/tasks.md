## 1. 實作

- [x] 1.1 requirement「A run with a stop mode leaves a record of how its verify loop ended」的三個新 Example：測試（`scripts/tests/close-stage/scenarios.sh`、`scripts/tests/stop-mode-log/test.sh`），`close-stage.py` 的 `write_gate_answer` 與 `gate --write-answer`，`stop-mode-log.py` 的 `gate_answer`，SKILL.md 的 gate 區塊。驗證：新檢查在 main 的程式上失敗（stop-mode-log 9 項、close-stage 4 項），改後兩個套件全過。

## 2. 回歸

- [x] 2.1 [after: 1.1] 整套測試通過（`bash plugins/issue-driven-dev/scripts/run-all-tests.sh`）。
