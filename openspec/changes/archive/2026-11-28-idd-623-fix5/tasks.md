## 1. 修正

- [x] 1.1 兩個 Example（gate 寫答案、append 只讀這張 issue 的 gate 檔）：測試先寫，再改 `close-stage.py`。驗證：三個新檢查（看起來像旗標的值、旗標給兩次、只能穿越的祖先目錄）在第 5 輪的程式上失敗，改後通過。

## 2. 回歸

- [x] 2.1 [after: 1.1] `run-all-tests.sh` 全部通過。
