## 1. 修正

- [x] 1.1 Example「the gate writes its answer without following a symbolic link」：測試先寫（`scripts/tests/close-stage/scenarios.sh`），再改兩支腳本。驗證：硬連結與「可能還在」的檢查在第 2 輪的程式上失敗，改後通過；stop-mode-log 的測試照常通過。

## 2. 回歸

- [x] 2.1 [after: 1.1] `run-all-tests.sh` 全部通過。
