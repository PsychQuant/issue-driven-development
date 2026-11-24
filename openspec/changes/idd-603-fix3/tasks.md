## 1. 實作

- [x] 1.1 requirement「A run with a stop mode leaves a record of how its verify loop ended」：測試先寫（壞掉或不是物件的 gate 回答、別的 round、fix 與沒有 stop mode 時不印訊息、`decision`／`decided`、跳脫後的文字、檔尾沒有換行、gate 區塊寫檔、`next` 區塊用 `--gate-file`），再改 `stop-mode-log.py`、`skills/idd-all/SKILL.md` 的 gate、`next` 區塊與 Phase 6 清理、`references/config-protocol.md`。驗證：22 個新檢查在舊程式上失敗；`bash plugins/issue-driven-dev/scripts/tests/stop-mode-log/test.sh` 通過。

## 2. 回歸

- [x] 2.1 [after: 1.1] 整套測試通過（`bash plugins/issue-driven-dev/scripts/run-all-tests.sh`）。
