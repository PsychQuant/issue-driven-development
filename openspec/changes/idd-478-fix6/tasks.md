## 1. 性質與檢查

- [ ] 1.1 新檔 `scripts/tests/rest-queue/treecheck.py`：`settle` 之前記下 git 資料夾以外每個檔的雜湊，之後逐一交代（沒變、在 `settle` 的 commit 裡、在記下的 stash 裡、是丟掉的紀錄、或是預設 branch 的內容），交出時被忽略的檔必須沒變。對應 requirement「Between two issues one helper settles the working tree」的性質段落。完成時：它對一個手動做出的遺失（把被忽略的檔刪掉）回報失敗。
- [ ] 1.2 `endings.py`：每一列都由真正的 `start`、`next`、`record` 產生 run 的狀態；範本 repo 加上 `tools/`（含 `.gitignore`）、頂層 `.gitignore` 與兩個原本就在的被忽略檔；每一列跑 1.1 的檢查（以 0 或 3 結束都跑）；結束方式表加五列、改一列（Example「endings of the single-issue pipeline」，共 27 列）。完成時：新的幾列在目前的 `rest-queue.py` 上失敗。
- [ ] 1.3 `settle_matrix.py`：狀態由真正的 `start` 與 `next` 產生，加一個維度「那一張的 commit 對 ignore 規則做了什麼」（沒動、刪掉 `tools/` 連同 `.gitignore`、改寫頂層 `.gitignore`），每一種組合跑 1.1 的檢查。完成時：0 處不符。

## 2. 三項 Blocking

- [ ] 2.1 測試先寫（`test.sh`，各帶 `spec-example` 標記）。Requirement「Each issue is attempted at most once per run」：Example `a new issue is handed out only on a clean default branch` 與 Scenario `an issue in flight is handed out again wherever the working tree is`。Requirement「Between two issues…」：Example `a file that was there before the run is left where it is`、`a path the default branch no longer ignores goes into the local exclude file`、`a file the issue stopped tracking does not stop the run`（兩列）、`a file the default branch tracks is not overwritten`（改成交出時就在的路徑）、`a settle that stopped gives no delete step for a pushed branch`、`what a rejecting hook wrote is looked at again`（兩列）。完成時：這些檢查在目前的程式上失敗。
- [ ] 2.2 `rest-queue.py`：`next` 交出新的一張之前檢查工作樹並記下被忽略的路徑（狀態版本 4）；`settle` 把這些路徑留在原處，保留的 commit 只 stage 明列的路徑，被擋之後重新檢查；checkout 之前 fetch、移動本機預設 branch 的 ref、把擋路的檔收進 stash；切回之後把交出時就在而不再被忽略的路徑寫進 `.git/info/exclude`；記下 upstream；fetch 失敗時最後才停。完成時：1.2、1.3、2.1 通過。

## 3. In-scope fix

- [ ] 3.1 hook 與紀錄。Requirement「Between two issues…」的 hook Example 加一列（名稱含空白的設定型 `prepare-commit-msg`）；設定型 hook 不論名稱都關掉；`found_stash` 遞迴列出檔案（Example `a stash the run state missed is found again` 改成巢狀路徑）；狀態裡的 commit 必須是 40 字元的十六進位。
- [ ] 3.2 Requirement「Start prints the list and resumes an unfinished run」：Example `a state that cannot be used`（三列）與 `a run that was never reported is not forgotten`。24 小時內不能用的狀態檔讓 `start` 以 3 結束；超過 24 小時而沒有報告的 run 先印出它留下的東西。原本斷言「不能用就換成新的 run」的測試一併改。
- [ ] 3.3 Requirement「A rest run keeps its review flag」：`start` 加上旗標時說明擋不住已經在跑的 close stage；`close-stage.py init` 的訊息寫出兩種出路；24 小時的起算寫明。Requirement「Report lists what happened and ends the run」：多個 stash、寫進 exclude 的路徑、沒有 upstream 紀錄時不給刪除的步驟、`settle` 停下時列出沒有自己 commit 的 branch、hook 那一句寫明看的是有沒有 hook。
- [ ] 3.4 訊息與停下的表：「找不到 run」的訊息寫出兩種原因；checkout 被擋的步驟補上之後未追蹤的檔；requirement「Between two issues…」停下的表後面列出其他每一種停下。
- [ ] 3.5 `skills/idd-all/SKILL.md`。Requirement「idd-all runs rest mode as a loop over the single-issue pipeline」：Example `the skill says the flags are to be the same`（涵蓋 Examples 一節）與 `the skill says to leave the working tree alone`；in flight 那一張的 PR 內文依 `next` 的 review；第 6 步、停止表、「結束」與「不做的事」對齊新的行為（原本就在的檔、exclude、兩種 stash、附件的說法）；權限一節那一句。
- [ ] 3.6 文件：`references/working-tree-writers.md`（`.git/info/exclude` 多一個寫入端、歸類的說明、原本就在的檔那一列）；CHANGELOG（性質、exclude、狀態版本 4 與 24 小時內舊狀態的處理、指名 issue 的 run 會讀 rest 的狀態、不經 hook 重做看的是有沒有 hook、rest run 期間不要動工作樹）；`docs/commands.md`。Requirement「idd-all-chain skill SHALL drive root issue plus auto-emergent spawn through one cluster branch and one PR」（capability `idd-all-chain`）與「Mode resolution from pr_policy and flags」（capability `idd-pr-hitl-modes`）各改一句，指向 `idd-all-rest`；這兩處只改規格的說法，沒有程式要改。

## 4. 驗證

- [ ] 4.1 對 `rest-queue.py` 新增的分支做變異檢查，每一處至少有一個測試失敗；其中一個變異是把「交出時就在的路徑」的排除拿掉，1.1 的檢查必須失敗。
- [ ] 4.2 請同一位沒有參與實作的 reviewer 在臨時 repo 實際執行，任務只有一個：找出一個交出之前就在、`settle` 之後不見或變了的檔。
- [ ] 4.3 跑 `scripts/tests/rest-queue/test.sh`、`scripts/tests/close-stage/test.sh` 與 `scripts/run-all-tests.sh`，全部通過。
