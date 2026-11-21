## 1. 測試先寫

- [x] 1.1 requirement「A configured stop mode decides when the fix loop stops and whether the run merges」新增的三個 Scenario 各一個情境（`plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh`）：回答過 fix 的結果再問一次回 stop；兩輪持平但留下一列 HIGH In-scope fix 時 `run` 停下並寫明；`exhaustive-all` 帶 `--review` 時 0 Blocking 就 stop、不合併、原因寫沒有 Blocking。驗證：改程式前這些斷言失敗。
- [x] 1.2 requirement「Unattended fix loop covers in-scope findings with a two-round limit」新增的 Scenario：沒有模式、round 紀錄是空的、報告乾淨時 `run` 停下並寫明 Phase 4 沒判過。`run_stage` 預設先跑一次 gate（照實際流程 Phase 4 一定判過），要測沒判過的情境另設 `NO_PREGATE=1`。驗證：改程式前這個斷言失敗，既有情境照舊通過。

## 2. 實作

- [x] 2.1 [after: 1.1] `verify-gate.py` 對每種判定輸出 `high_in_scope`（Severity 是 CRITICAL／HIGH／P0／P1 的 In-scope fix 列數）；`close-stage.py` 的 `merge_gate` 在停止模式下要求它存在且為 0。驗證：1.1 的 HIGH 情境通過。
- [x] 2.2 [after: 1.1] `next` 回答 fix 時，把那個結果（commit 與報告 id）記進 run-state 的 `fix_answers`；`decide` 遇到已經記過的結果回 stop、不合併，有沒有模式都一樣。`exhaustive-all` 的 `--review`／`--in-chain` 原因寫「沒有 Blocking」。驗證：1.1 的重問情境與 `--review` 情境通過。
- [x] 2.3 [after: 1.2] `merge_gate` 沒有模式的分支：最新報告不在 round 紀錄裡就停，空紀錄也一樣。驗證：1.2 的情境通過。
- [x] 2.4 idd-all SKILL.md：Step 0.2 在 `jq` 裡比對三個值，輸出驗證過的模式或無效標記（含空字串）；Phase 4 沒有 run-state 時，沒有模式的 run 照以前自己數輪數。驗證：Step 0.2 的解析在 bash 下對 `"early\n"`、`""`、`"fast"`、`{"mode":"early"}` 各跑一次；內容審查 Phase 4。

## 3. 回歸

- [x] 3.1 [after: 2.1, 2.2, 2.3, 2.4] close-stage、verify-gate、merge-and-close-contract 套件全過，`run-all-tests.sh` 全過。
