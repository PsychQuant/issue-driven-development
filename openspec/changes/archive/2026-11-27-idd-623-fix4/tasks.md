## 1. 修正

- [x] 1.1 兩個 Example（gate 寫答案、append 只讀這張 issue 的 gate 檔）：測試先寫，再改兩支腳本。驗證：三個新檢查（被拒的參數、umask、經過不存在的目錄）在第 4 輪的程式上失敗，改後通過。

## 2. 回歸

- [x] 2.1 [after: 1.1] `run-all-tests.sh` 全部通過。
