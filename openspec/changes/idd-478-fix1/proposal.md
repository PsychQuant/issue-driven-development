## Problem

`/idd-all` 的 rest mode（#478）在 verify 第 1 輪被找到五個缺陷，都在 `scripts/rest-queue.py` 的分類、報告，以及 skill 對失敗的處理：

1. 正文的最後編輯者帳號讀不到時，被當成有寫入權。GraphQL 的 `editor` 在「從未編輯」與「編輯者帳號讀不到」兩種情況都是 null，查詢沒有取 `lastEditedAt`，所以分不出來。規格寫的是帳號讀不到也算 outsider。
2. 正文有字、但 GitHub 渲染成空字串的 issue（例如正文只有一段 HTML 註解）會讓 `list`、`start`、`next` 整個以結束碼 3 失敗，skill 再把它變成整個 run 停下。讀渲染排在 outsider 判定之前，任何能開 issue 的帳號都做得到。
3. 總報告把這次 run 已經試過的 issue 再列進 `not run` 各類。
4. 等人回答的問題整列被截成 300 字，Source 夠長時問題本身會被截掉。
5. 第一次 `start` 失敗時還沒有狀態檔，skill 要求的 `stop` 與 `report` 都只會回結束碼 1，沒有走得完的失敗處理。
6. rest 不重跑已經 verified 的 issue，也不接手已經有 PR 或 branch 的 issue，所以一張 issue 只被 rest 試一次，之後每次都跳過。這與 issue 寫的「每一張走到結案」「verify 沒過不算必須要人」不一致。維護者在 2026-11-15 決定在這張 issue 裡改成接手。

## Root Cause

- 第 1 項：照抄 close stage 的寫法（`editor` 為 null 就略過），沒有對照自己的規格文字。
- 第 2 項：沿用 close stage 對單張 issue 的 fail-closed（讀不到渲染就停），但這裡的範圍是整個 backlog，一張讀不到不該讓其他張都不能跑。
- 第 3、4 項：`cmd_report` 直接印重新分類的清單，沒有扣掉 attempts；`listing()` 用給停止原因的長度上限去截問題。
- 第 5 項：skill 的停止表把所有結束碼 3 都導向 `stop`，沒有分「run 還沒開始」的情況。

## Proposed Solution

- 查詢加讀 `lastEditedAt`：正文編輯過而沒有回編輯者時，「最後編輯者有寫入權」為否。
- 判定表多一類 `unreadable`，排在 `tracker` 之後：正文有字而讀不到渲染的 issue 不跑、列在清單與報告裡，命令不失敗。帳號的判定不讀渲染，所以沒有寫入權的帳號開的這種 issue 仍是 `outsider`。
- 報告的 `not run` 各類扣掉這次 run 的 attempts；等人回答的問題整列印出；`verified` 與 `existing work:` 的 issue 寫明要指名 `/idd-all #N` 才會繼續。
- skill：`start` 自己以 3 結束時，直接把原因告訴使用者就結束，不呼叫 `stop` 與 `report`。
- 接手既有的工作：判定表拿掉 `verified` 這一類（剩八類），已經 verified 的 issue 是一般的 candidate，`start` 的清單標出它們；已經有 PR 或 branch 的 issue 照單張流程的處置表（自己的 `idd/N-*` branch 就接著做，別人的 PR 或已合併的 PR 不開始）。為了不重做一輪又停在同一個地方，還有沒回應的略過確認（無人值守時取的預設）的 issue 歸 `needs-person`：`lib/intent.py` 新增 `unanswered_confirmations`，close stage 與 rest 共用。

同一輪一併修的小項不改 requirement：狀態寫不進去或沒預期的錯誤一律是一行原因與結束碼 3、`--reason ""` 視同沒有原因、狀態檔不能用時 `start` 明說、`--repo` 不接受 `.` 與 `..`、skill 文字（單引號與跳脫、不接手時的清理、`other` 的說明、`--target` 提示）、測試 fixture 加上標題、`docs/commands.md` 與 `docs/workflows.md`。

## Non-Goals

- 分辨一張 verified 的 issue 上次為什麼停下（CI、close stage 的其他閘門、`--review`）：除了略過確認之外都會再跑一輪 verify。
- 替「別的 session 同時在跑同一張 issue」上鎖：push 不強推，後到的那一個會停下。
- `.claude/.idd/state/` 沒有被 ignore 的目標 repo：單張流程的 unattended 標記有同一個前提，另開 issue 一起處理。
- close stage 的 `check_issue_authors` 對讀不到的編輯者也是略過：另開 issue。
- verify 的停止規則與輪數上限（#423）。

## Success Criteria

- 正文編輯過、GitHub 沒有回編輯者的 issue 歸 `outsider`；從未編輯過的 issue 照舊。
- 一張正文只有 HTML 註解的 issue 存在時，`list` 的結束碼是 0，那一張歸 `unreadable`（作者沒有寫入權時歸 `outsider`），其他 issue 照常排序。
- 這次 run 試過的 issue 不出現在報告的 `not run` 各類。
- 正文的 Phase 是 verified 的 issue 在 run order 裡，`start` 的清單標出它；有沒回應的略過確認的 issue 歸 `needs-person`，有 Decision comment 回應之後才是 candidate。
- 超過 300 字的釐清列在報告裡完整出現。
- skill 的 rest 一節寫明 `start` 失敗時不呼叫 `stop` 與 `report`。
- `scripts/tests/rest-queue/test.sh` 全部通過，每個新的 Example 都有帶標記的測試，而且在修正前的程式上會失敗。

## Impact

- Affected specs: `idd-all-rest`（修改六條 requirement，新增一條）
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/rest-queue.py
  - Modified: plugins/issue-driven-dev/scripts/lib/intent.py
  - New: plugins/issue-driven-dev/scripts/tests/rest-queue/confirmations_check.py
  - Modified: plugins/issue-driven-dev/scripts/tests/rest-queue/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/rest-queue/tables_check.py
  - Modified: plugins/issue-driven-dev/scripts/tests/rest-queue/scenario.py
  - Modified: plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
  - Modified: docs/commands.md
  - Modified: docs/workflows.md
  - Modified: docs/wiki/Path-Map.md
  - New: plugins/issue-driven-dev/scripts/tests/rest-queue/fixtures/body-comment-only.md
  - New: plugins/issue-driven-dev/scripts/tests/rest-queue/fixtures/body-comment-only.html
  - New: plugins/issue-driven-dev/scripts/tests/rest-queue/fixtures/body-long-row.md
  - New: plugins/issue-driven-dev/scripts/tests/rest-queue/fixtures/body-long-row.html
