## 1. Blocking 1：目標 repo 的機制不讓 run 停下

- [x] 1.1 測試先寫。Requirement「Between two issues one helper settles the working tree」：`endings.py` 加 `stop-in-implement-hooks-reject` 與 `stop-in-implement-ignored-files` 兩列（ignore 規則由那一張 branch 的 commit 實際加入）；`test.sh` 加 Example `commit hooks that reject the leftovers are skipped for that commit`（三種 hook）、`files that only the issue's branch ignores are stashed`（含照報告寫的指令把 stash 套回去）、Scenario `commit hooks that accept the leftovers run` 與 `a hook that fails after the checkout`。原本把 pre-commit hook 當成暫時失敗的 `fail-commit` 檢查改掉。完成時：這些檢查在目前的 `rest-queue.py` 上失敗。
- [x] 1.2 `rest-queue.py settle`：commit 被 hook 拒絕時重新 stage、不經 repo 的 hook 再 commit，訊息正文與狀態寫明；checkout 回報失敗而工作樹已在預設 branch 時算完成；切回後只剩「在那一張 branch 被忽略」的未追蹤路徑時收進 stash，立刻記進狀態；重跑時由固定的 commit 訊息與 stash 訊息找回漏記的紀錄（Example `a commit the run state missed is found again`）。完成時：1.1 通過。

## 2. Blocking 2：`--review` 存進 run 的狀態

- [x] 2.1 測試先寫。Requirement「A rest run keeps its review flag」：Example `the review flag across a resumed run`（四列）、`the close stage cannot be told that review is off`（五列，實際呼叫 `close-stage.py init`）、Scenario `the flag is printed for an issue in flight`。Requirement「Each issue is attempted at most once per run」的兩個 in flight Example（輸出多了 `review`）。完成時：這些檢查在目前的程式上失敗。
- [x] 2.2 `rest-queue.py`：`start --review yes|no` 必填、存進狀態（版本 3，沒有這個值的狀態檔不能用）、接續時只能加上；`next` 印出 `review`。`close-stage.py init`：rest 的狀態寫著 review、那一張 in flight、而 `--review` 是 no 時以 64 結束。完成時：2.1 與 `scripts/tests/close-stage/test.sh` 通過。

## 3. 小修正：helper

- [x] 3.1 測試先寫，再改 `rest-queue.py`。Requirement「Between two issues…」：`endings.py` 的最後一欄照每一列設定 GitHub 那一側（verified、blocked、meeting），加 `stop-after-diagnose-failed-download` 一列，表的六欄都與規格比對；Example `a long branch name does not cut off the next step`、`a worktree folder at the top is never committed from below`；manifest 最後才丟；預設 branch 以 `refs/heads/<default>` 重驗、checkout 帶 `--`；`settle` 每一個以 3 結束的出口都是同一個格式。
- [x] 3.2 Requirement「Start prints the list and resumes an unfinished run」：Example `a new run does not start in a working tree an earlier run left`、`a run that is not on the PR path is refused`（原因行不含完整的 `/idd-all` 指令）。
- [x] 3.3 Requirement「The outcome of an issue is read from GitHub」與「A stopped issue does not stop the run and a stopped run hands out nothing」：issue 已結案時保留原因（表多一列）；`--reason-stdin`（Example `a reason on standard input is taken as it is`）；`stop` 去掉 `rest-queue: ` 前綴（Example `a reason copied from the helper keeps its end`）。
- [x] 3.4 Requirement「Report lists what happened and ends the run」：Example `the report says what to do with a kept branch`（刪掉 branch 之後開新的 run 確認）、`a closed issue whose run reported a stop`、`the report says where the working tree may be`；hook 被略過與 stash 的說明；`verified` 那一行。`classify_args` 的兩則拒絕原因不再說「every remaining issue」。
- [x] 3.5 `settle_matrix.py`：預期值加上新的行為（hook、stash 不在窮舉範圍；維度不變時只更新註解），0 處不符。

## 4. 小修正：skill、盤點與文件

- [x] 4.1 `skills/idd-all/SKILL.md`。Requirement「idd-all runs rest mode as a loop over the single-issue pipeline」：`start` 帶 `--review "$REVIEW_YN"`；每一張的 `REVIEW_YN` 取 `next` 印出的值；`record` 與 `stop` 用 `--reason-stdin`；停止表兩列寫「旗標相同」；Step 0.5 與 Step 0.6 開頭指回 `## Rest mode`；「呼叫錯了」那一段補上 `--cwd` 寫錯的情況；第 6 步的表補 hook 與 stash；「結束」一節與「這一節不做的事」改寫（保留 branch 的下一步、`--cwd` 在子目錄時的 tree-lock、`verified` 那一行）；節標題與範例標題不再說「剩下的全部」。完成時：四個新的 skill 文字 Example 的檢查通過。
- [x] 4.2 新檔 `references/working-tree-writers.md`：寫入端的盤點（位置、寫入端、歸類、沒有查到的照實標明、檢查看不到的範圍），逐列重新對照程式；`test.sh` 加 Example `every location the plugin names is in the inventory` 的檢查。
- [x] 4.3 文件：`references/parallel-orchestration.md` 第 76 行；README 的依賴表與 rest 的說明；plugin 的 `CLAUDE.md`；`references/usecase-routing.md`；`docs/commands.md`；`docs/workflows.md`；CHANGELOG（hook、stash、`--review`、寫入權）；規格的 Purpose 一句。完成時：`scripts/tests/docs-catalog-sync/test.sh` 通過。

## 5. 驗證

- [x] 5.1 對 helper 新增的分支再做一次變異檢查，每一處至少有一個測試失敗。
- [x] 5.2 跑 `scripts/tests/rest-queue/test.sh`、`scripts/tests/close-stage/test.sh` 與 `scripts/run-all-tests.sh`，全部通過。

## 6. 獨立規格對照之後的修正

- [x] 6.1 測試先寫。Requirement「A rest run keeps its review flag」：Example `review added while an issue is in flight`（兩列，實際呼叫 `close-stage.py run`）與 Scenario `a rest run state that cannot be read stops the close stage`。`close-stage.py run` 自己讀同一個 `--cwd` 的 rest 狀態：帶 review 而那一張 in flight 就停，24 小時內的狀態檔讀不出來也停。完成時：這兩項檢查在改之前失敗、改之後通過。
- [x] 6.2 測試先寫。Requirement「Between two issues one helper settles the working tree」：Example `a file the default branch tracks is not overwritten`、`the steps a stop names lead to a run that starts`（六列，照原因行寫的步驟做完再開新的 run）、`a commit that fails without a commit hook is not made again`（兩列）、`a second keep commit keeps the first`、`a stash whose branch was deleted`、`a stash the run state missed is found again`；`endings.py` 加 `stop-before-commit-ignored-files` 與 `file-the-default-branch-tracks` 兩列，兩列 closed 的 GitHub 端不再列出 #5、並檢查之後的 run，表的六欄都與規格比對。`rest-queue.py settle`：checkout 與快轉帶 `--no-overwrite-ignore`；只有 repo 有 commit 之前會跑的 hook 時才不經 hook 重做 commit；第二次 keep commit 合併先前的紀錄；記下 stash 指的 branch 有沒有留下；丟掉的紀錄存進狀態、第二次 `settle` 一併印出；每一種停下的後續步驟寫完整；原因行只在開頭寫一次工作樹所在的 branch。
- [x] 6.3 Requirement「Start prints the list and resumes an unfinished run」與「Report lists what happened and ends the run」：`start` 的兩則拒絕原因寫完整的步驟，`--pr` 那一句改成取代 `--no-pr`；報告的 stash 那一行分 branch 還在與已刪掉兩種寫法，兩次 commit 都列出，「工作樹可能還在某張的 branch 上」那一行寫完整的步驟（Example `the step for a working tree that was not settled`）；報告叫人做的步驟改成封閉列舉。
- [x] 6.4 `skills/idd-all/SKILL.md`。Requirement「idd-all runs rest mode as a loop over the single-issue pipeline」：`record` 的程式區塊移到行首（Example `the skill's record command works as written`，實際執行區塊）；`REVIEW_FLAG` 也取 `next` 的值、Step 0.7 重跑時 rest 不回頭看原始引數（Example `the skill takes both review values from next`）；第 6 步與停止表補上不覆寫被忽略的檔、hook 的條件、停下之後的步驟。
- [x] 6.5 `references/working-tree-writers.md` 四列改正（附件資料夾有一處以名稱 stage、編輯備份寫在主工作樹、routing-stats 寫在 shell 所在工作樹的頂層、issue-runs 是否 commit 標為未查到），歸類加「stashed」與「stops」；CHANGELOG、`docs/commands.md`、`MANIFESTO.md` 的說法對齊。
- [x] 6.6 對 6.1 與 6.2 新增的分支做變異檢查，每一處至少有一個測試失敗；請同一位獨立 reviewer 重跑它原先的重現步驟。
- [x] 6.7 reviewer 重驗之後。測試先寫：Example `a file the default branch tracks is not overwritten` 加長檔名的四個檔、`the steps a stop names lead to a run that starts` 加四列（共十列）、hook 的 Example 加三列設定型 hook、`a second keep commit keeps the first` 加紀錄遺失的情況、`a stash whose branch was deleted` 做到開新的 run、`a long branch name does not cut off the next step` 加兩個長名稱。`rest-queue.py`：叫人切回預設 branch 的地方都給 `git checkout --no-overwrite-ignore`；`commit_hooks` 用 `git hook list`、重做時關掉設定裡的 hook；keep commit 之前先由訊息找回遺失的那一筆；原因行開頭的 branch 名稱只在放不下時才縮短。完成時：`fix5` 的變異檢查對這幾處各有測試失敗。
