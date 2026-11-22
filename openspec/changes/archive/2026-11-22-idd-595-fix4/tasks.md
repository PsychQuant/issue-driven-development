## 1. 規格

- [x] 1.1 規格寫明 Phase 5 的唯讀讀法、被取代的 run 不記錄、重讀計數一致、attempt 少於 round 不合併、`--stop` 重複或接旗標時中止。驗證：close-stage 套件裡對應的情境（`stop-run-readonly`、`stop-gate-replaced`、`stop-run-counts`、`stop-nomode-noattempts`）通過，Step 0.2 的 `--stop` 解析在 bash 下對六種參數跑過；`spectra validate idd-595-fix4` 通過。
