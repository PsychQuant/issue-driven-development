## Problem

verify 第 6 輪（#478 的 comment 6991471219）在 `a47bcd6` 判定 FAIL：3 項 Blocking，其中 1 項 HIGH。

1. **HIGH：原本就在的檔被 commit 進保留的 branch。** rest 在兩張 issue 之間由 `rest-queue.py settle` 整理工作樹。它在那一張的 branch 上用 `git add -A` 收下「那個 branch 不忽略的一切」。使用者原本就放在工作樹、只被預設 branch 忽略的檔（`.env`、`node_modules/`、virtualenv），在那一張刪掉或改寫了 ignore 規則時，就被當成那一張留下的東西 commit 進本機 branch，切回預設 branch 時從工作樹消失。報告還把它列為「這張留下的」並建議刪掉那個 branch。
2. **把檔案改成不追蹤的 issue 停掉整個 run。** `git rm --cached` 加一條 ignore 規則之後，檔案仍在工作樹；`settle` 的 checkout（`--no-overwrite-ignore`）被它擋下，以 3 結束，連已經 merge 並結案的那一張也一樣。
3. **報告對已經推上去的 branch 寫「它沒有 upstream，刪掉之後會重跑」。** `settle` 在保留的 commit 之後停下時，紀錄還沒有 upstream 這一欄，報告把缺欄位當成沒有。

另有 21 項 In-scope fix。

## Root Cause

第 1、2 項同源：`settle` 判斷「工作樹裡有什麼」用的是那一張 branch 的 git 狀態，沒有區分「這張 issue 開始之前就在的東西」與「這張 issue 留下的東西」。修正輪 4 盤點的是 plugin 自己寫的位置；使用者自己的、被忽略的檔不在盤點裡，也不在任何一個測試情境裡。

測試會漏掉，是因為 `endings.py` 與 `settle_matrix.py` 用 `git status` 列出留下物，和 helper 用的是同一個視角；手寫的 run 狀態也沒有經過真正的 `start` 與 `next`。

## Proposed Solution

先把性質寫進規格並加檢查，再修。

**性質**：一張 issue 被交出時就在工作樹的檔，`settle` 之後都要交代得出去。當時 git 沒有追蹤的檔，`settle` 之後在原處、內容不變（以 0 或 3 結束都一樣），`settle` 不 commit、不 stash、不搬、不刪；當時有追蹤的檔，以 0 結束後是預設 branch 的版本。

**檢查**：測試直接走檔案系統。`settle` 之前把 git 資料夾以外的每個檔算雜湊，之後逐一交代：沒變、在保留的 commit 裡、在記下的 stash 裡、是丟掉的會重新產生的紀錄、或被 checkout 寫成預設 branch 的內容。每個情境都有原本就在、被忽略的檔，run 的狀態由真正的 `start` 與 `next` 寫出。

**做法**：

1. `next` 交出新的一張時，要求工作樹在乾淨的預設 branch 上（接續的 run 也檢查），並把當時 git 忽略的路徑記進狀態。狀態版本改為 4。
2. `settle` 把落在這份紀錄裡的路徑留在原處。保留的 commit 改成只 stage 明列的路徑；commit 被 hook 擋下之後重新讀留下物、重做前兩步的檢查再 stage。
3. checkout 之前先 fetch；本機預設 branch 落後而沒有自己的 commit 時，先把它的 ref 往前移。那一張的 branch 忽略、預設 branch 有追蹤、而且不在交出時紀錄裡的檔，checkout 之前收進一個 stash。checkout 仍帶 `--no-overwrite-ignore`。fetch 失敗時先把本機的事做完，最後才以 3 結束，工作樹停在乾淨的預設 branch。
4. 切回預設 branch 之後仍未追蹤的路徑：交出時紀錄裡的，寫進 `.git/info/exclude` 並記下（維護者 2026-11-20 的 Decision）；在那一張 branch 被忽略的，收進 stash（同修正輪 5）；其他的照舊以 3 結束。
5. 記下保留的 commit 時就記 upstream；報告只對紀錄寫明沒有 upstream 的 branch 給刪除的步驟。`settle` 停在那一張的 branch 時，報告列出那一張沒有自己 commit 的 branch。

**21 項 In-scope fix**：設定型 hook 不論名稱都關掉；找回 stash 時遞迴列路徑；狀態裡的 commit 必須是 40 字元的十六進位；24 小時內讀不出來的狀態檔讓 `start` 以 3 結束；超過 24 小時而沒有報告的 run 先印出它留下的東西；`start` 加上 `--review` 時的說明、PR 內文、`init` 的訊息；「找不到 run」的訊息；skill 的 Examples 與「不做的事」；停下的表列出每一種停下；共用工作樹的說明；`idd-all-chain` 與 `idd-pr-hitl-modes` 兩份規格指向 `idd-all-rest`。

## Non-Goals

- 每張 issue 用獨立的 git worktree。維護者 2026-11-19 選的是在同一個工作樹再修一輪。
- 那一張 issue 自己把預設 branch 忽略的檔 commit 進去之後的 checkout（單張流程本來的行為）。
- 單張流程自己的一般 checkout（#587）。
- 把 `/idd-all` 限定為只由人呼叫（#457）。
- 同一個工作樹裡別人還沒 commit 的改動：`settle` 分不出來，這一輪只寫進文件。

## Success Criteria

- 規格 `idd-all-rest` 的結束方式表每一列，以及 `settle_matrix.py` 的每一種組合，都通過檔案系統層的檢查：交出時被忽略的檔在原處、內容不變。
- 第 6 輪第 1 項的重現（那一張刪掉 `tools/` 連同它的 `.gitignore`，repo 有密鑰掃描 hook）：`tools/.env` 不在保留的 commit 裡、仍在工作樹，hook 沒有被略過。
- 把檔案改成不追蹤的 issue 不論停下或已 merge，`settle` 都以 0 結束，下一張被交出。
- `settle` 在保留的 commit 之後停下、branch 有 upstream 時，報告不寫刪除的步驟。
- `scripts/tests/rest-queue/test.sh`、`scripts/tests/close-stage/test.sh` 與 `scripts/run-all-tests.sh` 全部通過；對新程式的變異檢查每一處都有測試失敗。

## Impact

- Affected specs: `idd-all-rest`（修改 6 條 requirement）、`idd-all-chain`（修改 1 條）、`idd-pr-hitl-modes`（修改 1 條）
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/rest-queue.py
  - Modified: plugins/issue-driven-dev/scripts/close-stage.py
  - Modified: plugins/issue-driven-dev/scripts/tests/rest-queue/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/rest-queue/endings.py
  - Modified: plugins/issue-driven-dev/scripts/tests/rest-queue/settle_matrix.py
  - New: plugins/issue-driven-dev/scripts/tests/rest-queue/treecheck.py
  - Modified: plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - Modified: plugins/issue-driven-dev/references/working-tree-writers.md
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
  - Modified: docs/commands.md
