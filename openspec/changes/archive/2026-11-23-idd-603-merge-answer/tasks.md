## 1. 實作

- [x] 1.1 requirement「A run with a stop mode leaves a record of how its verify loop ended」：`stop-mode-log.py` 的 `next_merge` 與 summary 的字面、測試、`config-protocol.md`。驗證：`scripts/tests/stop-mode-log/test.sh` 通過，summary 不印 merged。

## 2. 回歸

- [x] 2.1 [after: 1.1] `run-all-tests.sh` 全過。
