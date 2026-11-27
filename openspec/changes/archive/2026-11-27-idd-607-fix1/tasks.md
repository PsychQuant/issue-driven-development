## 1. 修正

- [x] 1.1 requirement「A configured stop mode decides when the fix loop stops and whether the run merges」的 Example「an incomplete coverage line counts as one Blocking finding」（計數與沒有停止模式的列）、「the gate carries the coverage and reviewers lines to next」、「an incomplete reviewers line stops without a merge」（重讀那一列）：測試先寫（`scripts/tests/close-stage/scenarios.sh`），再改 `stopmode.py` 與 `close-stage.py`。驗證：沒有停止模式的計數與重讀的五個檢查在第 1 輪的程式上失敗，close-stage 套件全過。
- [x] 1.2 規格 delta 以 origin/main 的完整 requirement 為底（Scenario、Example、`@trace` 都在），封存後對 origin/main 的差異只剩 #607 的內容。驗證：`git diff origin/main` 這個檔沒有刪除行以外的 #607 內容（只有改寫的三處）。

## 2. 回歸

- [x] 2.1 [after: 1.1, 1.2] 整套測試通過（`bash plugins/issue-driven-dev/scripts/run-all-tests.sh`）。
