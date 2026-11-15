## 1. 測試先寫（每一項先看到它失敗）

- [x] 1.1 `scenario.py` 與 fixtures：每個 issue node 帶 `lastEditedAt` 與 `title`（標題含一段不該被印出的字）；新增鍵 `edited=yes`（編輯過但沒有回編輯者）；新增 fixture `body-comment-only`（正文只有 HTML 註解、渲染是空字串）與 `body-long-row`（一列超過 300 字、問題以 `END-OF-QUESTION` 結尾的釐清表，用 `../verify-gate/render-fixtures.sh` 取 GitHub 的渲染）。完成時：`scenario.py` 產生的 `issues.json` 每個 node 都有這兩個欄位，兩組 fixture 的 `.md` 與 `.html` 都在。
- [x] 1.2 `tables_check.py`：`class precedence` 的十六列（多一欄 readable）與規格逐列相同，獨立寫的 oracle 改成九類，窮舉 1024 種組合。標記 `spec-example: idd-all-rest / class precedence` 保留。完成時：在修正前的 `rest-queue.py` 上這個檢查失敗。
- [x] 1.3 `test.sh`：Example `edited by an account that cannot be read` 的測試（標記 `spec-example: idd-all-rest / edited by an account that cannot be read`）：#5 從未編輯、#6 由有寫入權的帳號編輯、#7 編輯過而沒有編輯者；斷言 #5、#6 在 run order，#7 是 `outsider`。
- [x] 1.4 `test.sh`：Example `a body GitHub renders as nothing` 的測試（標記 `spec-example: idd-all-rest / a body GitHub renders as nothing`）：斷言結束碼 0、#6 是 `unreadable`、#7 是 `outsider`、run order 是 5。
- [x] 1.5 `test.sh`：Example `an attempted issue is not listed as not run`（標記 `spec-example: idd-all-rest / an attempted issue is not listed as not run`）與 `a long clarity row is printed in full`（標記 `spec-example: idd-all-rest / a long clarity row is printed in full`）的測試。
- [x] 1.6 `test.sh`：Example `the skill reports a failed start directly` 的測試（標記 `spec-example: idd-all-rest / the skill reports a failed start directly`），以及 Scenario「a failed start leaves no run behind」的 helper 檢查（`start` 結束碼 3、沒有狀態檔、`stop` 結束碼 1）。
- [x] 1.7 `test.sh`：不屬於 Example 的檢查：狀態目錄寫不進去時 `start` 是結束碼 3 與一行原因、stderr 沒有 `Traceback`；`record --reason ""` 記成 `no reason given`；狀態檔內容壞掉時 `start` 的輸出說明找到不能用的狀態檔；`--repo ../x` 與 `--repo o/..` 是結束碼 2；`start`、`list` 與 `report` 的輸出不含 fixture 標題裡那段字；skill 文字含不接手時的清理、run 結束時的 `clear_unattended`、單引號與跳脫的說明。

## 2. 程式

- [x] 2.1 Requirement「Every open issue falls into exactly one class」與「The open issues are read completely or not at all」：`rest-queue.py` 查詢加 `lastEditedAt`，`checked()` 檢查它；`editor_writes` 照規格三種情況判定；`TABLE` 加第三類 `unreadable`（輸入 `readable`），`read_classes` 先判定帳號、再讀渲染，讀不到時 `readable` 為否、`open_clarity` 與 `verified` 為否；`LABELS`、`list_lines` 與說明文字跟著改。完成時：1.2、1.3、1.4 的測試通過。
- [x] 2.2 Requirement「Report lists what happened and ends the run」：`rest-queue.py` 的 `listing()` 的問題整列保留（只清成一行）；`cmd_report` 的 `not run` 各類扣掉 attempts，`verified` 與 `existing work:` 寫明指名 `/idd-all #N` 才會繼續。完成時：1.5 的測試通過。
- [x] 2.3 `rest-queue.py`：`save_state` 的建目錄與建暫存檔移進 try；`main` 對沒預期的例外印一行原因、結束碼 3；`--reason` 接受空字串；`start` 遇到不能用的狀態檔時說明；`--repo` 的兩段拒絕 `.` 與 `..`。完成時：1.7 的 helper 檢查通過。
- [x] 2.4 Requirement「A stopped issue does not stop the run and a stopped run hands out nothing」：`skills/idd-all/SKILL.md` 判定表加 `unreadable`；停止表加「`start` 自己以 3 結束」一列；不接手的 issue 先做該張的清理再記錄，「結束」一節在 `report` 之後 `clear_unattended`；`--reason` 與 Step 0.1 的引數改用單引號並寫明跳脫方式；mode 表 `other` 的說明與 `--target` 提示。完成時：1.6 與 1.7 的 skill 文字檢查通過。

## 3. 文件

- [x] 3.1 `docs/commands.md`（Syntax、不帶參數那一列、拒絕的形式）與 `docs/workflows.md` 的 P-cron-autopilot（改成指名 issue，另寫明不帶參數是 rest mode 與它的風險），再跑 `scripts/generate-path-map.py` 重新產生 `docs/wiki/Path-Map.md`。完成時：`scripts/tests/path-map-sync/test.sh` 通過。
- [x] 3.2 `CHANGELOG.md` 的 `[Unreleased]`：寫入九類、`unreadable`、報告的改動，BREAKING 補一句提醒既有的排程與 `/loop /idd-all`；`README.md`、`MANIFESTO.md`、`references/` 裡提到八類或類別清單的地方跟著改。完成時：`grep` 找不到還寫八類的地方。

## 4. 驗證

- [ ] 4.1 跑 `scripts/tests/rest-queue/test.sh`、`scripts/tests/close-stage/test.sh` 與每一個讀到這次改動檔案的 suite，全部通過。完成時：`scripts/run-all-tests.sh` 沒有失敗的 suite。
