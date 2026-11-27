## 1. 修正

- [x] 1.1 requirement「A configured stop mode decides when the fix loop stops and whether the run merges」的 Example 新增的那一列：重讀之後再記錄下一輪的測試先寫（`scripts/tests/close-stage/scenarios.sh`），再改 `close-stage.py` 的 `record_round`。驗證：三個檢查在第 3 輪的程式上失敗，close-stage 套件全過。

## 2. 回歸

- [x] 2.1 [after: 1.1] 整套測試通過（`bash plugins/issue-driven-dev/scripts/run-all-tests.sh`）。
