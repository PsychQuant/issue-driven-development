## 1. Blocking 1：目標 repo 的機制不讓 run 停下

- [ ] 1.1 測試先寫。Requirement「Between two issues one helper settles the working tree」：`endings.py` 加 `stop-in-implement-hooks-reject` 與 `stop-in-implement-ignored-files` 兩列（ignore 規則由那一張 branch 的 commit 實際加入）；`test.sh` 加 Example `commit hooks that reject the leftovers are skipped for that commit`（三種 hook）、`files that only the issue's branch ignores are stashed`（含照報告寫的指令把 stash 套回去）、Scenario `commit hooks that accept the leftovers run` 與 `a hook that fails after the checkout`。原本把 pre-commit hook 當成暫時失敗的 `fail-commit` 檢查改掉。完成時：這些檢查在目前的 `rest-queue.py` 上失敗。
- [ ] 1.2 `rest-queue.py settle`：commit 被 hook 拒絕時重新 stage、不經 repo 的 hook 再 commit，訊息正文與狀態寫明；checkout 回報失敗而工作樹已在預設 branch 時算完成；切回後只剩「在那一張 branch 被忽略」的未追蹤路徑時收進 stash，立刻記進狀態；重跑時由固定的 commit 訊息與 stash 訊息找回漏記的紀錄（Example `a commit the run state missed is found again`）。完成時：1.1 通過。

## 2. Blocking 2：`--review` 存進 run 的狀態

- [ ] 2.1 測試先寫。Requirement「A rest run keeps its review flag」：Example `the review flag across a resumed run`（四列）、`the close stage cannot be told that review is off`（五列，實際呼叫 `close-stage.py init`）、Scenario `the flag is printed for an issue in flight`。Requirement「Each issue is attempted at most once per run」的兩個 in flight Example（輸出多了 `review`）。完成時：這些檢查在目前的程式上失敗。
- [ ] 2.2 `rest-queue.py`：`start --review yes|no` 必填、存進狀態（版本 3，沒有這個值的狀態檔不能用）、接續時只能加上；`next` 印出 `review`。`close-stage.py init`：rest 的狀態寫著 review、那一張 in flight、而 `--review` 是 no 時以 64 結束。完成時：2.1 與 `scripts/tests/close-stage/test.sh` 通過。

## 3. 小修正：helper

- [ ] 3.1 測試先寫，再改 `rest-queue.py`。Requirement「Between two issues…」：`endings.py` 的最後一欄照每一列設定 GitHub 那一側（verified、blocked、meeting），加 `stop-after-diagnose-failed-download` 一列，表的六欄都與規格比對；Example `a long branch name does not cut off the next step`、`a worktree folder at the top is never committed from below`；manifest 最後才丟；預設 branch 以 `refs/heads/<default>` 重驗、checkout 帶 `--`；`settle` 每一個以 3 結束的出口都是同一個格式。
- [ ] 3.2 Requirement「Start prints the list and resumes an unfinished run」：Example `a new run does not start in a working tree an earlier run left`、`a run that is not on the PR path is refused`（原因行不含完整的 `/idd-all` 指令）。
- [ ] 3.3 Requirement「The outcome of an issue is read from GitHub」與「A stopped issue does not stop the run and a stopped run hands out nothing」：issue 已結案時保留原因（表多一列）；`--reason-stdin`（Example `a reason on standard input is taken as it is`）；`stop` 去掉 `rest-queue: ` 前綴（Example `a reason copied from the helper keeps its end`）。
- [ ] 3.4 Requirement「Report lists what happened and ends the run」：Example `the report says what to do with a kept branch`（刪掉 branch 之後開新的 run 確認）、`a closed issue whose run reported a stop`、`the report says where the working tree may be`；hook 被略過與 stash 的說明；`verified` 那一行。`classify_args` 的兩則拒絕原因不再說「every remaining issue」。
- [ ] 3.5 `settle_matrix.py`：預期值加上新的行為（hook、stash 不在窮舉範圍；維度不變時只更新註解），0 處不符。

## 4. 小修正：skill、盤點與文件

- [ ] 4.1 `skills/idd-all/SKILL.md`。Requirement「idd-all runs rest mode as a loop over the single-issue pipeline」：`start` 帶 `--review "$REVIEW_YN"`；每一張的 `REVIEW_YN` 取 `next` 印出的值；`record` 與 `stop` 用 `--reason-stdin`；停止表兩列寫「旗標相同」；Step 0.5 與 Step 0.6 開頭指回 `## Rest mode`；「呼叫錯了」那一段補上 `--cwd` 寫錯的情況；第 6 步的表補 hook 與 stash；「結束」一節與「這一節不做的事」改寫（保留 branch 的下一步、`--cwd` 在子目錄時的 tree-lock、`verified` 那一行）；節標題與範例標題不再說「剩下的全部」。完成時：四個新的 skill 文字 Example 的檢查通過。
- [ ] 4.2 新檔 `references/working-tree-writers.md`：寫入端的盤點（位置、寫入端、歸類、沒有查到的照實標明、檢查看不到的範圍），逐列重新對照程式；`test.sh` 加 Example `every location the plugin names is in the inventory` 的檢查。
- [ ] 4.3 文件：`references/parallel-orchestration.md` 第 76 行；README 的依賴表與 rest 的說明；plugin 的 `CLAUDE.md`；`references/usecase-routing.md`；`docs/commands.md`；`docs/workflows.md`；CHANGELOG（hook、stash、`--review`、寫入權）；規格的 Purpose 一句。完成時：`scripts/tests/docs-catalog-sync/test.sh` 通過。

## 5. 驗證

- [ ] 5.1 對 helper 新增的分支再做一次變異檢查，每一處至少有一個測試失敗。
- [ ] 5.2 跑 `scripts/tests/rest-queue/test.sh`、`scripts/tests/close-stage/test.sh` 與 `scripts/run-all-tests.sh`，全部通過。
