## Problem

verify 第 5 輪（#478，range `6c26645..a78b933`）判 FAIL：2 項 Blocking（都是 MEDIUM）、20 項 In-scope fix、1 項 Follow-up。這一輪沒有 HIGH。

1. 目標 repo 自己的機制會讓一張 issue 停掉整個 run。`settle` 保留留下物的 commit 會跑 repo 的 commit hook，hook 拒絕半成品時 `settle` 以 3 結束；那一張的 commit 加了 ignore 規則、執行又產生那些檔時，切回預設 branch 後它們變成未追蹤，也以 3 結束。兩種都實測過。
2. 旗標沒有持久的來源。`--review` 只在模型的記憶裡；接續一個 run 時不比對，長 run 中途壓縮後可能被推回「沒有」，之後每一張 verify 乾淨的 issue 都會被 merge 並 close。

20 項小修正中較重的三項：結束方式表的最後一欄與單張流程不符，報告給人的下一步因此對最常見的情況不成立；`start` 的拒絕訊息丟掉原本的旗標；commit 成功而狀態還沒寫入時中斷，重跑會漏記那個 commit。

## Root Cause

- 修正輪 4 的盤點只涵蓋 plugin 自己的寫入端，沒有把目標 repo 的 hook 與 ignore 規則當成結束方式的一部分。
- run 的狀態存了 path 與預設 branch，沒有存 `--review`；決定 merge 與否的值經過模型才到 close stage。
- 結束方式表的測試讓每一列的 issue 在 GitHub 上都是 candidate，所以表上「之後的 run」那一欄只驗到本機 branch 的規則；報告給人的步驟沒有任何測試實際做過。

## Proposed Solution

維護者 2026-11-19 的 Decision：保留用的 commit 先照常跑 hook，被拒絕才不經 hook 再 commit 一次，並註明。

1. **保留用的 commit**：hook 拒絕時重新 stage、不經 repo 的 hook 再 commit，commit 訊息的正文與 run 的狀態都寫明 hook 被略過；報告註明這個 commit 沒有過 hook，推上去之前要先看過。checkout 之後才失敗的 hook 不算 checkout 失敗。
2. **只在那一張 branch 被忽略的檔**：切回預設 branch 之後若只剩這類未追蹤的檔，收進一個 stash（訊息固定），不刪任何檔；stash 的 commit 與路徑記進狀態、列在報告，並寫明怎麼取回。這一半維護者沒有被問到，是實作的預設。
3. **`--review` 存進 run 的狀態**（新的 requirement）：`start --review yes|no`；接續時只能加上、不能拿掉；`next` 每交出一張都印出；`close-stage.py init` 在 rest 的狀態寫著 review 而呼叫給的是 no 時拒絕，close stage 因此停在 verified。
4. **結束方式表**：最後一欄改成之後的 run 看到的類別（交出、existing work、不跑：verified／blocked／meeting、已結案），測試讓 GitHub 那一側照每一列的結束方式設定；補三列（hook 拒絕、只在 branch 被忽略、下載到一半失敗）。
5. **報告給人的步驟都要有測試實際做過**：只有沒有 upstream 的保留 branch 才寫「刪掉就會重跑」，測試刪掉後開新的 run 確認；有 upstream 的只說留給人。
6. 其餘小項：重跑時由固定的 commit 訊息與 stash 訊息找回漏記的紀錄；停止原因不重複 branch 名稱、下一步不被截掉；`stop` 去掉 `rest-queue: ` 前綴；issue 已結案時保留 `record` 的原因；不收進 git 的位置同時在 `--cwd` 與 repo 頂層比對；新的 run 要求工作樹在乾淨的預設 branch；`record` 與 `stop` 的原因改從 stdin 傳；Step 0.5 與 Step 0.6 指回 rest 的規則；下載失敗的附件算會重新產生的紀錄、manifest 最後才丟；寫入端的盤點寫成 `references/working-tree-writers.md` 並加檢查；文件用字。

## Non-Goals

- direct-commit 與 attended 的 rest（#583）、接手保留的 branch（#566）、把共用紀錄檔帶回預設 branch（#584）、`idd-diagnose` 下載附件時的目前目錄（#586）。
- `--cwd` 在 repo 頂層以下時，tree-lock 的 ignore 規則由它的寫入端加在頂層，不涵蓋子目錄。這一版只寫進文件，不改寫入端。
- 單張流程本身不改，`close-stage.py` 只加 `init` 的那一項檢查。

## Success Criteria

- 規格這一輪新增與修改的每一個 Example 都有帶標記的測試，在修正前的程式上失敗。
- 有拒絕半成品的 pre-commit hook 的 repo 裡，一張停在 implement 的 issue 之後，`settle` 以 0 結束，下一張被交出。
- rest 的狀態寫著 review 時，`close-stage.py init --review no` 對 in flight 的那一張以 64 結束、不留下 run state。
- 報告寫的「刪掉 branch」做完之後，新的 run 交出那一張。
- `scripts/tests/rest-queue/test.sh`、`scripts/tests/close-stage/test.sh` 與 `scripts/run-all-tests.sh` 全部通過。

## Impact

- Affected specs: `idd-all-rest`
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/rest-queue.py
  - Modified: plugins/issue-driven-dev/scripts/close-stage.py
  - Modified: plugins/issue-driven-dev/scripts/tests/rest-queue/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/rest-queue/endings.py
  - Modified: plugins/issue-driven-dev/scripts/tests/rest-queue/settle_matrix.py
  - New: plugins/issue-driven-dev/references/working-tree-writers.md
  - Modified: plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - Modified: plugins/issue-driven-dev/references/parallel-orchestration.md
  - Modified: plugins/issue-driven-dev/references/usecase-routing.md
  - Modified: plugins/issue-driven-dev/README.md
  - Modified: plugins/issue-driven-dev/CLAUDE.md
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
  - Modified: docs/commands.md
  - Modified: docs/workflows.md
