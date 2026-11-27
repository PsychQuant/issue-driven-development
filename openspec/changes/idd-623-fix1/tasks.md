## 1. 修正

- [x] 1.1 兩個 Example（gate 寫答案、append 只讀這張 issue 的 gate 檔）：測試先寫（`scripts/tests/close-stage/scenarios.sh`、`scripts/tests/stop-mode-log/test.sh`），再改兩支腳本。驗證：新檢查在第 1 輪的程式上失敗（stop-mode-log 8 項、close-stage 1 項），改後通過。

## 2. 回歸

- [x] 2.1 [after: 1.1] `run-all-tests.sh` 全部通過。
