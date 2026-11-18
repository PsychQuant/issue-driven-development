## 1. 測試先寫（先看到它們失敗）

- [x] 1.1 Requirement「Between two issues one helper settles the working tree」：新檔 `scripts/tests/rest-queue/endings.py`，以 Example `endings of the single-issue pipeline` 的表為鍵，每一列一個臨時 git repo（有 bare origin）。附件資料夾由 `process-attachments.sh download` 實際寫出（`gh` 與 `curl` 用 PATH 上的替身），`routing-stats.jsonl` 的寫入端是外部程式，以附加一行模擬。每一列檢查：結束碼；結束碼 0 時工作樹在預設 branch 而且 `git status --porcelain` 沒有輸出；#5 的 branch 與 run state 的 `kept` 一致；被丟掉的只有規格列出的那幾種檔；新的 run 的 `next` 交出 #5 或記為 existing work；結束碼 3 時 HEAD、所在 branch 與 `git status` 的輸出都沒有變。完成時：在修正前的 `rest-queue.py` 上這個檔有失敗的列。
- [x] 1.2 同一條 requirement 的其他 Example 與 Scenario，寫在 `scripts/tests/rest-queue/test.sh`，各帶 `spec-example` 標記：`leftovers on the issue's own branch are kept there`（commit 不含 manifest、報告列出路徑）、`a file IDD keeps out of git is never committed`（改用 tree-lock）、`a local default branch with commits of its own does not stop the run`、`a shared log is committed and named as such`、`an interrupted settle keeps its commit`（origin 連不上之後再連上）、`the working tree below the top of the repository`；Scenario：有 upstream 的 branch 保留、同一張 issue 兩個 branch。另外對 `settle` 的每一個 git 步驟（commit、checkout、fetch、快轉）各注入一次失敗再重跑，檢查 `kept` 不變。移除 direct-commit 的 Example 與它的標記。完成時：新檢查在修正前的程式上失敗。
- [x] 1.3 `scripts/tests/rest-queue/settle_matrix.py`：拿掉 path 這一維與「附件以 3 結束」的預期；預期值改成檢查結果性質（同 1.1），加上 upstream 這一維，以及「manifest 與鎖同時留下」這一種留下物（以 3 結束時什麼都不丟）；同一張兩個 branch 由 1.2 的 Scenario 測。完成時：組合數與 0 處不符印在 suite 輸出。
- [x] 1.4 Requirement「Start prints the list and resumes an unfinished run」：Example `a run that is not on the PR path is refused`、`start stores the default branch`（`fake-gh.py` 回答 `repo view` 的預設 branch）、`candidates with a local branch are listed apart`、`an account without write access cannot start a run`（`fake-gh.py` 的 `perm-<login>.403`）；沒有 path 與預設 branch 的狀態檔視為不能用；拿掉附件提醒的檢查。
- [x] 1.5 Requirement「Each issue is attempted at most once per run」：Example `the in-flight issue is repeated`（輸出多了 `"branch": null`）與 `the in-flight issue names its branch`。
- [x] 1.6 Requirement「Report lists what happened and ends the run」：Example `the report says what to do with a kept branch`。
- [x] 1.7 Requirement「idd-all runs rest mode as a loop over the single-issue pipeline」與「A stopped issue does not stop the run and a stopped run hands out nothing」：skill 文字的檢查。`the skill runs the preflight steps once` 改成讀 `start` 之前那個編號步驟、`start` 那一行與 `settle` 那一行（不再用要找的字串當篩選條件）；`the skill continues an issue in flight`（`branch` 是 `null` 時從 Step 0.4 重來）；`the skill ends a refused run without a marker`。`idd-existing-work-lookup` 的 Requirement「Starting skills SHALL act on a blocked verdict」只改用字（rest 仍然呼叫 helper，不同的只有 `resume` 與 `blocked` 的處置），既有帶標記的檢查 `rest mode records existing work instead of acting on it` 照舊通過。完成時：三個檢查在目前的 skill 文字上失敗。

## 2. 程式

- [x] 2.1 `scripts/rest-queue.py` 的 `start`：必填 `--path`，不是 `PR` 就以 3 結束、不寫任何東西；新的 run 向 GitHub 讀預設 branch，連同 path 存進 run state（state 版本 2，缺這兩個值的狀態檔不能用）；清單把有本機 branch 的 candidate 另列一行；拿掉附件的提醒。讀寫入權遇到 HTTP 403（rate limit 除外）時，`rest-queue.py` 給出「需要有寫入權的帳號」的原因。完成時：1.4 通過。
- [x] 2.2 `settle`：只收 `--issue`，預設 branch 取自 run state；路徑以 `--cwd` 相對於 repo 根目錄的位置為基準；封閉表改成三列與三個步驟（會重新產生的紀錄、寫入端排除的位置、其他留在這張的 branch）；commit 的路徑記進 `kept`；fetch 後只在落後時快轉；重跑時保留先前記下的 commit 與路徑；原因行先寫下一步、最多三個路徑、不超過原因的長度上限，由 `settle` 呼叫的讀取失敗時也帶 issue 號與所在 branch。完成時：1.1、1.2、1.3 通過。
- [x] 2.3 `next`：in flight 時多印 `branch`。`report`：`kept` 的路徑、共用紀錄檔的說明、給人的下一步（刪掉 branch 或先看過），不再寫「name it」。完成時：1.5、1.6 通過。
- [x] 2.4 「再跑一次」的提示帶上原本的旗標：`rest-queue.py` 的 `AGAIN`、`scripts/close-stage.py` run-state 過期那一則、`skills/idd-all/SKILL.md` Phase 0.5 的 abort 訊息，改成「同一個 /idd-all 指令（含旗標）」。`scripts/check-existing-work.sh` 與 `rest-queue.py` 的 branch 命名規則互相註記。完成時：`scripts/tests/close-stage/test.sh` 通過。

## 3. skill 與文件

- [x] 3.1 `skills/idd-all/SKILL.md` 的 rest 一節：流程第 1 步改成前置檢查與 path 解析（Step 0.2、0.3、0.35、Step 0.5 的解析、Step 0.6，只做一次，不寫 unattended 標記、不建 branch；`pr_policy: ask` 只問要不要以 PR path 開始）；`start` 帶 `--path "$PATH_AXIS"`；每一張沿用解析結果、不再降級；in flight 那一列照 `branch`；`settle` 不帶 `--default` 與 `--path`，說明三類留下物；停止表第一列加上 path 不是 PR 並清掉標記；拿掉 direct-commit 與 attended 的段落；「這一節不做的事」補上：direct-commit 與 attended、共用紀錄檔留在那一張的 branch、bot 的留言不算 outsider、執行帳號要有寫入權；Step 0.1 補上 `args` 本身失敗時的處理；rest 的 task 說明補 `parse_review_flag`；description、argument-hint 與 Step 0.1 的表改成「每一張可以跑的 open issue」。完成時：1.7 通過。
- [x] 3.2 文件：`references/parallel-orchestration.md` 第 76 行改成 `settle` 的行為；`README.md` 與 `docs/commands.md` 的 rest 說明（只走 PR path、只跑 candidate、留下物的去處）；`CHANGELOG.md` 的 #478 條目。完成時：`scripts/tests/docs-catalog-sync/test.sh` 通過。

## 4. 驗證

- [x] 4.1 跑 `scripts/tests/rest-queue/test.sh`、`scripts/tests/close-stage/test.sh` 與 `scripts/run-all-tests.sh`，全部通過。
