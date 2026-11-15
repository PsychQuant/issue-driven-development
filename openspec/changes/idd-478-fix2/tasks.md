## 1. 還原接手（測試先，再程式）

- [ ] 1.1 Requirement「Every open issue falls into exactly one class」與「The open issues are read completely or not at all」：`scripts/tests/rest-queue/` 的 `test.sh`、`tables_check.py`、`scenario.py` 回到九類（`verified` 是一類、1024 種組合），拿掉略過確認與本機 branch 的測試、`confirmations_check.py` 與 `fixtures/comment-*`。完成時：這些測試在目前的程式上失敗。
- [ ] 1.2 Requirement「idd-all runs rest mode as a loop over the single-issue pipeline」：`rest-queue.py`、`lib/intent.py` 與 `skills/idd-all/SKILL.md` 回到不接手的版本（`verified` 類、`existing work`、沒有 `unanswered_confirmations`、沒有本機 branch 的規則）。完成時：1.1 的測試與 `scripts/tests/close-stage/test.sh` 通過。

## 2. 第 2 輪的小項（測試先，再程式）

- [ ] 2.1 Requirement「Rest mode is selected by a closed list of argument forms」：Example `argument forms` 的表多六列（空的引數、兩個空白、`last`、`last --pr`、`last call for papers`），`tables_check.py` 的對照與小世界跟著加（標記 `spec-example: idd-all-rest / argument forms` 保留）；`classify_args` 拒絕空的位置引數與單獨的 `last`。完成時：表上每一列通過。
- [ ] 2.2 Requirement「Report lists what happened and ends the run」：Example `a closed issue that was reopened carries its open questions` 的測試（標記 `spec-example: idd-all-rest / a closed issue that was reopened carries its open questions`）；`cmd_report` 在 closed 那一段列出重開而等人回答的 issue 與它的問題；清單讀不到時不論原因都照樣印出已記錄的結果（測試：`listing` 丟出沒預期的例外）。
- [ ] 2.3 Requirement「Start prints the list and resumes an unfinished run」：Example `a reason with a line break is printed on one line` 的測試（標記 `spec-example: idd-all-rest / a reason with a line break is printed on one line`）；`start`、`next` 與 `report` 印狀態檔裡的原因時一律清成一行。
- [ ] 2.4 Requirement「A stopped issue does not stop the run and a stopped run hands out nothing」：Example `the skill ends when the report itself fails` 的測試（標記 `spec-example: idd-all-rest / the skill ends when the report itself fails`）；Scenario「a failed start leaves an earlier run as it was」的 helper 測試；skill 的停止表多一列 `report` 以 3 結束。
- [ ] 2.5 Requirement「idd-all runs rest mode as a loop over the single-issue pipeline」：Example `the skill clears the unattended marker` 的測試（標記 `spec-example: idd-all-rest / the skill clears the unattended marker`）；skill 文字已有兩處清理，確認位置（不接手的 issue 記錄之前、`report` 之後）。
- [ ] 2.6 skill 與文件：`skills/idd-all/SKILL.md` 的 description（每張在一次 run 裡只試一次）、Step 0 寫明指名 issue 的 run 不建 `rest_run`、Step 0.1 的表加 `last` 與空引數、「這一節不做的事」寫上 #566 與兩個已知的限制（in flight 的 issue 不重新分類；宣告某張 issue 的 open PR 會讓 rest 不跑那一張）；`MANIFESTO.md`、`skills/idd-issue/SKILL.md`、`README.md` 的例子帶上 issue 號；`docs/commands.md` 與 `CHANGELOG.md` 跟著改。完成時：`grep` 找不到還把接手當成現有行為的文字。

## 3. 驗證

- [ ] 3.1 跑 `scripts/tests/rest-queue/test.sh`、`scripts/tests/close-stage/test.sh` 與 `scripts/run-all-tests.sh`，全部通過。
