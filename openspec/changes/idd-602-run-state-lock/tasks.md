## 1. 測試先寫

- [x] 1.1 requirement「A configured stop mode decides when the fix loop stops and whether the run merges」：close-stage 套件新增情境——同一個 `created_at`、不同 `run_id` 的紀錄由 `record_round` 拒絕；鎖是互斥的，`record_round` 會拿鎖；沒有 `verify_stop` 欄位的紀錄被 `next` 與 `run` 拒絕。帶標記 `spec-example: idd-pr-hitl-modes / the run state is identified and locked`。驗證：改程式前這些斷言失敗。
- [x] 1.2 requirement「Unattended fix loop covers in-scope findings with a two-round limit」：`next` 印出 `decided`（還沒有 gate 紀錄時 false、有一輪 not_clean 時 true）。帶標記 `spec-example: idd-pr-hitl-modes / next says whether it decided`；`cipending` 情境改用不依賴負載的等待時間。驗證：改程式前 `decided` 的斷言失敗。

## 2. 實作

- [x] 2.1 [after: 1.1] `close-stage.py`：鎖檔與 `run_id`；`init`、`record_round`、`next` 的修正答案在鎖內寫；`read_state` 要求 `verify_stop`。驗證：1.1 的情境通過。
- [x] 2.2 [after: 1.2] `close-stage.py next` 印出 `decided`；`skills/idd-all/SKILL.md` Phase 4 沒有模式的 run 在 `decided` 為 false 時自己數輪數。驗證：1.2 的情境通過；內容審查 Phase 4。

## 3. 回歸

- [ ] 3.1 [after: 2.1, 2.2] close-stage 套件與 `run-all-tests.sh` 全過。
