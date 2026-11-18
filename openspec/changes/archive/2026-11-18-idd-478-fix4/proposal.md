## Problem

verify 第 4 輪（#478，range `3b87909..7002ba7`）判 FAIL，6 項 Blocking、19 項 In-scope fix。6 項 Blocking 都在「兩張 issue 之間」：

1. `settle` 的 `--default` 與 `--path` 沒有來源：第一張是 existing work、在 Phase 0.5 abort，或接續一個 run 時，skill 還沒有讀到這兩個值。
2. `settle` 把附件列為不收進 git 的檔，與 plugin 自己的附件規則（預設 commit 進 repo）相反；下載了附件而在 implement 之前停下的 issue 會讓整個 run 停下。
3. diagnose 對每一張都寫 `_manifest.json`。`settle` 把它 commit 在那一張的 branch，branch 因此被保留，之後每一次 rest 都把那一張記為 existing work，不再跑。
4. direct-commit 的 rest 幾乎在第一張就結束：manifest 留在工作樹、`routing-stats.jsonl` 在 commit 之後才寫。
5. 維護者 2026-11-16 的 Decision 要的「單張流程的每一種結束方式 × 它留下什麼 → rest 怎麼處理」的表沒有寫出來；192 種組合的檢查只證明程式照規格，而規格把第 2、3、4 項寫成了預期值。
6. `settle` 中斷後重跑，會用沒有 commit 的紀錄蓋掉先前記下的 commit。

## Root Cause

修正輪 3 的 `settle` 依「工作樹現在的樣子」處理，並假設每一個留下的檔都是那一張 issue 的工作。這個假設不成立。從寫入端盤點（單張流程在 repo 裡寫入的 29 類位置）得到三個事實：

- diagnose 每次都重跑，每次都重寫附件資料夾（沒有附件也寫一份 `files` 是空的 manifest）。這些檔是下一次 diagnose 會重新產生的紀錄，不是工作。
- `routing-stats.jsonl`（裝了 `idd-route` 時）在 verify 與 idd-close 才寫，在最後一個 commit 之後；它是所有 issue 共用的紀錄。
- PR path 的 branch 在 diagnose 之前就建好，而且從 `origin/<default>` 建，不讀本機的預設 branch。

另外兩個原因：`settle` 需要的兩個值由 skill 在單張流程的中途才取得；direct-commit 沒有每張自己的 branch，留下的東西沒有地方放。

## Proposed Solution

1. **rest 只走 PR path。** 前置檢查與 path 的解析（含會把 path 降級的那一步）移到 `start` 之前、只做一次；`start --path` 不是 `PR` 就以 3 結束、不寫任何東西，並說明怎麼做。direct-commit 的 rest 另開 issue。
2. **helper 自己記 path 與預設 branch。** `start` 向 GitHub 讀預設 branch，連同 path 存進 run state；`settle` 只收 `--issue`。
3. **留下物照寫入端分成封閉的三類**（工作樹在這張自己的 branch 上時）：
   - 會被重新產生的紀錄（這張的附件資料夾）：manifest 是那個資料夾裡唯一的留下物時丟掉；branch 還沒有自己的 commit、而留下的全是 manifest 與它列出且雜湊相符的附件時，全部丟掉。丟掉是指刪掉未追蹤的檔、把已追蹤的檔還原。
   - 寫入端自己排除在 git 之外的位置（run 狀態、編輯備份、鎖、worktree）：出現就以 3 結束，不 commit。
   - 其他一律留在這張的 branch：commit 在那裡（只在本機），branch、commit 與路徑記進 run state，報告列出路徑；其中屬於所有 issue 共用的紀錄檔，報告另外標明。
4. **預設 branch 只在落後時快轉。** 本機預設 branch 有自己的 commit 不再讓 run 停下。
5. **`settle` 重跑時保留第一次記下的 commit 與路徑。**
6. **`next` 對 in flight 的那張回報它有沒有本機 branch**：沒有就從 Step 0.4 重新開始（包含 existing-work 檢查），有才從中斷處接著做。
7. **結束方式的表寫進規格**，作為 `settle` 那條 requirement 的 Example；測試以結束方式為鍵，附件與 manifest 由 `process-attachments.sh download` 實際產生，檢查的是結果：下一張起始的檢查（`git status --porcelain`）通過、被丟掉的只有會重新產生的紀錄、留下的 branch 與 run state 一致、沒有 branch 的那一張在之後的 run 會再被交出。
8. 第 4 輪的 In-scope fix（第 7 到 25 項）一併處理，對照寫在 tasks。

## Non-Goals

- direct-commit 與 attended 的 rest：這一版拒絕，另開 issue。
- 接手已經有 branch 或 PR 的 issue（含 `settle` 保留的 branch）：#566。報告給人的下一步只寫現在確定可行的做法（刪掉 branch 讓之後的 rest 重跑，或先看過 branch）。
- 把所有 issue 共用的紀錄檔（`routing-stats.jsonl`）的新內容帶回預設 branch：這一版把它留在那一張的 branch 並在報告標明，帶回去另開 issue。
- 單張流程本身不改：誰把附件 commit 進 repo、PR path 下本機 branch 已存在時的提問，都維持現狀。

## Success Criteria

- `settle` 那條 requirement 的每一個 Example（含結束方式的表）都有帶標記、實際在臨時 git repo 執行的測試，而且在修正前的程式上會失敗。
- 沒有附件的 issue 在 implement 之前停下之後：工作樹在預設 branch、`git status --porcelain` 沒有輸出、那一張沒有 branch；新的 run 的 `next` 會交出它。
- `start --path direct-commit` 以 3 結束，不留下 run state。
- skill 的 `settle` 呼叫不帶 `--default` 與 `--path`；`start` 的呼叫帶 `--path`。
- `scripts/tests/rest-queue/test.sh`、`scripts/tests/close-stage/test.sh` 與 `scripts/run-all-tests.sh` 全部通過。

## Impact

- Affected specs: `idd-all-rest`、`idd-existing-work-lookup`
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/rest-queue.py
  - Modified: plugins/issue-driven-dev/scripts/close-stage.py
  - Modified: plugins/issue-driven-dev/scripts/check-existing-work.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/rest-queue/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/rest-queue/fake-gh.py
  - Modified: plugins/issue-driven-dev/scripts/tests/rest-queue/settle_matrix.py
  - New: plugins/issue-driven-dev/scripts/tests/rest-queue/endings.py
  - Modified: plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - Modified: plugins/issue-driven-dev/references/parallel-orchestration.md
  - Modified: docs/commands.md
  - Modified: plugins/issue-driven-dev/README.md
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
