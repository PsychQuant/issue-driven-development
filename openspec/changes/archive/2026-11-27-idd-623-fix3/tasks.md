## 1. 修正

- [x] 1.1 兩個 Example（gate 寫答案、append 只讀這張 issue 的 gate 檔）：測試先寫，再改兩支腳本。驗證：新檢查在第 3 輪的程式上失敗（stop-mode-log 的 `..` 情況、close-stage 的警告），改後通過。

## 2. 回歸

- [x] 2.1 [after: 1.1] `run-all-tests.sh` 全部通過。
