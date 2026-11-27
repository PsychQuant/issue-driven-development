## 1. 修正

- [x] 1.1 requirement「A configured stop mode decides when the fix loop stops and whether the run merges」的 Example 新增的列：`last_gate` 缺欄的測試先寫（`scripts/tests/close-stage/scenarios.sh`），再改 `stopmode.py` 的 `effective_rounds`；兩個方向的重讀測試經過 gate。驗證：缺欄的兩個檢查在第 2 輪的程式上失敗，close-stage 套件全過。

## 2. 回歸

- [x] 2.1 [after: 1.1] 整套測試通過（`bash plugins/issue-driven-dev/scripts/run-all-tests.sh`）。
