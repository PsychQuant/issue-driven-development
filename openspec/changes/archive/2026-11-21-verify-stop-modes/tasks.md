## 1. 測試先寫（照 spec 的 Scenario，在改程式之前會失敗）

- [x] 1.1 在 `plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh` 為 requirement「A configured stop mode decides when the fix loop stops and whether the run merges」的八個 Scenario 各加一個情境：用 fixtures 準備 run-state（含 `verify_stop` 與 `rounds`）與 gate 結果，檢查 `close-stage.py next` 印出的 `decision`、`merge`、`reason`，以及 `gate` 重讀同一份報告時 `rounds` 的筆數不變。驗證：`plugins/issue-driven-dev/scripts/tests/close-stage/test.sh` 跑這些情境，改程式前全部失敗。
- [x] 1.2 為 requirement「Clean verify leads to merge and close」新增的 Scenario（設了模式的 run 期限從最後一輪算）與 requirement「Unattended fix loop covers in-scope findings with a two-round limit」新增的 Scenario（沒有模式、`rounds` 有 3 筆時 `run` 停下並寫明兩輪上限）各加一個情境。驗證：同一支 test.sh，改程式前這兩個情境失敗，既有情境照舊通過。

## 2. run-state 的模式與每輪紀錄

- [x] 2.1 [after: 1.1] `close-stage.py init` 接受必填的 `--stop <none|early|exhaustive-blocking|exhaustive-all>`，把模式寫進 run-state 的 `verify_stop`（`none` 寫成 `null`），缺少或其他值以結束碼 64（usage，與 init 其他引數相同）拒絕。驗證：test.sh 的 init 情境（缺 `--stop`、值錯、四個合法值）。
- [x] 2.2 [after: 2.1] 每輪的計數由 gate 寫進 run-state：`close-stage.py gate` 讀到這次 run 還沒讀過的報告（以 comment id 判斷）時，在 `rounds` 加一筆 `round`、`sha`、`blocking`、`in_scope`、`low_in_scope`、`report_id`、`at`；`unparseable` 也記一筆、計數為 `null`；重讀同一份報告不加。gate 印出的 JSON 另帶 `round`。驗證：1.1 的「The same report read twice is one round」情境通過。

## 3. 由 close-stage.py next 判斷要不要再跑一輪

- [x] 3.1 [after: 2.2] 新增 `close-stage.py next`，依 design「要不要再跑一輪由 close-stage.py next 判斷」印出 `decision`、`merge`、`reason`、`mode`、`rounds`。實作三種模式的判定表：收斂數數的是要修的列（`blocking + in_scope - low_in_scope`，`--review`／`--in-chain` 只數 `blocking`）、early stop 以嚴格下降判斷收斂、exhaustive-blocking 用連續兩輪不下降當保底、exhaustive-all 沒有輪數上限；沒有模式時無人值守 2 輪、attended 1 輪後回 stop。讀不到 run-state 或 `rounds` 空的回 stop、`merge: false`、非 0 結束碼。驗證：1.1 的模式情境全部通過。
- [x] 3.2 [after: 3.1] `close-stage.py run` 的合併條件：停下時合併的是最後一輪審過的 commit——有模式的 run 在 `next` 對最後一輪回 `merge: true` 時放行（HEAD 必須等於最後一筆 `rounds` 的 `sha`），沒有模式的 run 仍要求 `clean`，且無人值守 run 的 `rounds` 超過 2 筆時停下並寫明兩輪上限；`--review`、`--in-chain`、meeting 照舊不合併，其餘 guardrail 不變。驗證：1.1 的合併情境與 1.2 的兩輪上限情境通過，既有 merge 測試（`scripts/tests/merge-and-close-contract/`）照舊通過。
- [x] 3.3 [after: 2.2] 設了模式的 run，期限從最後一輪算：`load_state()` 對 `verify_stop` 不是 `null` 的紀錄，以 `rounds` 最後一筆的 `at` 計算年齡（沒有 `rounds` 用建立時間）；沒有模式的紀錄不變。驗證：1.2 的期限情境通過；沒有模式、建立超過 24 小時的既有情境照舊被擋。

## 4. idd-all 照 next 走

- [x] 4.1 [after: 2.1] idd-all SKILL.md Step 0.2 解析 `--stop`，值不在三個之內時在 Phase 1 之前停下並列出三個值；Step 0.7 照 config 值寫錯時當成沒有模式的規則解析 `verify_stop.mode`（印一行），把結果以 `--stop` 交給 `close-stage.py init`，並在模式通知那一行印出停止模式。驗證：內容審查 SKILL.md 的 Step 0.2 與 0.7，並以 1.1 的「Flag over config」情境的 init 部分對照。
- [x] 4.2 [after: 3.1, 4.1] idd-all SKILL.md Phase 4 改成一條由 `close-stage.py next` 驅動的迴圈：每輪 verify → gate → next，照 `decision` 修或停；設了模式的 attended run 也自動修（安全漏洞仍停下交回）；`MAX_ROUND` 這個名字從 SKILL.md 移除。驗證：`grep -c MAX_ROUND plugins/issue-driven-dev/skills/idd-all/SKILL.md` 為 0；內容審查 Phase 4 的 pseudocode 對照 spec 的判定表。
- [x] 4.3 [after: 3.2, 4.2] idd-all SKILL.md Phase 5c 的兩張表與 Phase 6 的 Run report：寫明有模式時的合併條件、剩下的列合成一張 follow-up issue、回報列出模式、輪數、每輪的 to-fix count 與 `next` 的 `reason`。驗證：內容審查 Phase 5c 與 Phase 6，對照 requirement「A configured stop mode decides when the fix loop stops and whether the run merges」的最後一段。

## 5. 文件與回歸

- [x] 5.1 `plugins/issue-driven-dev/references/config-protocol.md` 新增 `verify_stop` 欄位一節：三個值、沒有設定時的行為、寫錯時當成沒有模式、`--stop` 優先於 config、各模式的合併條件與風險（不乾淨的 commit 可能自動合併）。驗證：內容審查，與 design 的「config 值寫錯時當成沒有模式」一致。
- [x] 5.2 [after: 3.2, 3.3, 4.3, 5.1] 全部 close-stage 與 idd-all 相關測試通過，沒有設定模式時輸出與改動前相同。驗證：`plugins/issue-driven-dev/scripts/tests/close-stage/test.sh` 與 `plugins/issue-driven-dev/scripts/tests/merge-and-close-contract/` 的測試全部通過。

## 6. spectra-verify 與 spectra-review 之後的修正

- [x] 6.1 停止模式的合併也要求覆蓋率行與 reviewers 行完整：`verify-gate.py` 對每種判定輸出 `coverage_complete`、`reviewers_complete`，`close-stage.py` 的 `merge_gate` 在停止模式下要求兩者為 `true`。驗證：close-stage 的 `stop-run-cover`、`stop-run-noreviewers` 情境停下；拿掉這道檢查時 8 個斷言失敗。
- [x] 6.2 沒有模式的 run 以 `attempts`（每個被判過的 commit 一筆）計輪數；`decide` 的沒有模式分支每個回答都帶 `round` 與 `limit`，Rejected 與 clean 留給 gate；`merge_gate` 擋下 Phase 4 沒判過的報告。驗證：close-stage 的沒有模式情境（缺報告的第 2 輪、第 1 輪有 Rejected、第 3 輪 clean、`stop-nomode-unseen`）；改回只數報告時 3 個斷言失敗。
- [x] 6.3 run-state 只有一種讀法（`read_state`，檢查形狀）與一種寫法（`write_state`，`mkstemp` 建暫存檔）；gate 寫紀錄失敗時回 `unparseable`；`next` 出錯時的回答帶 `mode` 與 `rounds`；unparseable 那一輪不保留計數；`next` 的每一輪帶 `to_fix`。驗證：close-stage 的 `stop-gate-broken` 與 to-fix 列表情境。
- [x] 6.4 idd-all SKILL.md：`--stop` 沒有值時中止；`verify_stop` 不是 object 時印一行；PR 正文在停止模式要合併時照實寫；停下並合併前檢查剩下的列有沒有安全漏洞；三處舊文字更新。驗證：Step 0.2 的停止模式解析在 bash 下實際跑過（zsh 下最後一個參數讀不到是既有的問題，另開 #598）；內容審查 Phase 4、Phase 5、Failure Modes。
- [x] 6.6 同一個 commit 上的新報告也算一輪：`record_round` 的 `attempts` 在 commit 換了、或讀到新報告時加一筆；Phase 5c guardrail 表第 1 列照程式改寫（數 `attempts`、覆蓋率與 reviewers 行）。驗證：close-stage 的「a new report on the same commit is a new attempt」斷言。
- [x] 6.5 測試：`verify_comment` 可設 severity、覆蓋率行與 reviewers 行；補上 spec「The same report read twice is one round」的兩輪版本、停止模式的 Rejected、`run` 實際合併 MEDIUM 列的兩條路徑。驗證：close-stage 套件 624 項全過。

