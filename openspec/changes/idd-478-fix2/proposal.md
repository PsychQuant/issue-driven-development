## Problem

verify 第 2 輪（#478）判定 FAIL，6 項 Blocking 幾乎都在修正輪 1 新增的「rest 接手已經 verified 與已經有 PR 或 branch 的 issue」上：rest 只靠 GitHub 上的資料看不出一張 verified 的 issue 上次是不是已經交給人，重跑會把帶 `--review` 留給人看的 issue 合併；verify 沒過的 issue 被歸成 blocked；既有工作的查詢不看 PR 的作者；本機 branch 的檢查不夠。維護者在 2026-11-15 決定這一版不含接手，接手移到 #566。

同一輪另外指出幾個與接手無關的小缺陷：run 結束時清 unattended 標記沒有 requirement、記為 closed 之後被重開的 issue 的問題沒有列在報告裡、`/idd-all last` 被當成新 issue 的描述、空的位置引數沒有定義、`report` 自己失敗時 skill 沒有走得完的路徑、狀態檔裡的原因原樣印出、`rest_run` 這個 task 被加進所有 run 的清單、其他文件裡不帶 issue 的 `/idd-all --pr` 例子。

## Root Cause

修正輪 1 把一個新的設計（接手）與第 1 輪的修正放在同一輪。接手需要 close stage 把停止原因留在 GitHub 上，這個前提不在 #478 的範圍內。

## Proposed Solution

- 還原接手：判定表回到九類，`verified` 是不跑的一類；已經有 PR 或 branch 的 issue 不接手，記為 `existing work`；拿掉「略過的確認歸等人回答」與 `lib/intent.py` 的 `unanswered_confirmations`，close stage 的意圖檢查回到原本的寫法；拿掉「本機已經有 branch 時不問就接著做」。
- 補小缺陷：規格寫明兩處清 unattended 標記；報告裡 closed 的 issue 現在等人回答時列出它的問題；單獨的 `last` 與空的位置引數被拒絕；`report` 以 3 結束時直接回報；清單讀不到時不論原因都照樣印出已記錄的結果；從狀態檔印出的原因一律清成一行；skill 寫明指名 issue 的 run 不建 `rest_run`；文件裡的例子帶上 issue 號。

## Non-Goals

- rest 接手既有的工作（#566），包含 verify 沒過的 issue 被歸成 blocked（#445）、PR 的作者檢查、停止原因留在 GitHub 上。
- in flight 的 issue 重新交出時重新分類：列為已知的限制，merge 仍有 close stage 的檢查。
- `.claude/.idd/state/` 沒有被 ignore 的目標 repo（#564）；close stage 對讀不到的編輯者（#565）。

## Success Criteria

- 正文的 Phase 是 verified 的 issue 歸 `verified`、不在 run order；`rest-queue.py` 與 `lib/intent.py` 裡沒有 `unanswered_confirmations`；close-stage suite 照舊通過。
- `rest-queue.py args -- last` 與 `args -- ''` 都是 `refuse`，結束碼 1。
- 記為 closed 之後被重開、正文有兩列未回答問題的 issue，報告在 closed 那一段列出它與兩列問題。
- 狀態檔裡兩行的原因，`start` 與 `report` 印成一行。
- skill 的 rest 一節有兩處 `clear_unattended "$CWD"`，並寫明 `report` 以 3 結束時不再呼叫 `stop` 與 `report`。
- `scripts/tests/rest-queue/test.sh` 全部通過，每個 Example 都有帶標記的測試。

## Impact

- Affected specs: `idd-all-rest`（修改七條 requirement，移除一條）
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/rest-queue.py
  - Modified: plugins/issue-driven-dev/scripts/lib/intent.py
  - Modified: plugins/issue-driven-dev/scripts/tests/rest-queue/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/rest-queue/tables_check.py
  - Modified: plugins/issue-driven-dev/scripts/tests/rest-queue/scenario.py
  - Modified: plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-issue/SKILL.md
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
  - Modified: plugins/issue-driven-dev/MANIFESTO.md
  - Modified: plugins/issue-driven-dev/README.md
  - Modified: docs/commands.md
  - Removed: plugins/issue-driven-dev/scripts/tests/rest-queue/confirmations_check.py
  - Removed: plugins/issue-driven-dev/scripts/tests/rest-queue/fixtures/comment-default-record.md
  - Removed: plugins/issue-driven-dev/scripts/tests/rest-queue/fixtures/comment-default-record.html
  - Removed: plugins/issue-driven-dev/scripts/tests/rest-queue/fixtures/comment-default-in-code.md
  - Removed: plugins/issue-driven-dev/scripts/tests/rest-queue/fixtures/comment-default-in-code.html
  - Removed: plugins/issue-driven-dev/scripts/tests/rest-queue/fixtures/comment-layerv-record.md
  - Removed: plugins/issue-driven-dev/scripts/tests/rest-queue/fixtures/comment-layerv-record.html
  - Removed: plugins/issue-driven-dev/scripts/tests/rest-queue/fixtures/comment-decision.md
  - Removed: plugins/issue-driven-dev/scripts/tests/rest-queue/fixtures/comment-decision.html
