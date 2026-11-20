## Problem

verify 第 7 輪（#478 的 comment 7030373381，只有 Codex 一席）在 `48fe423` 判定 FAIL：4 項 Blocking，都判 HIGH。

1. git 設定成不顯示未追蹤檔（`status.showUntrackedFiles no`）時，`start` 與 `next` 的乾淨檢查看不到未追蹤的檔，照樣交出 issue；`settle` 卻列得出它，把使用者原本就在的檔 commit 進那一張的 branch。
2. `settle` 在保留的 commit 做完之後、檢查之前被中止時，重跑不再檢查那個 commit。
3. 讓 commit 通過的 hook 可以把不收進 git 的位置的檔帶進保留的 commit；hook 擋下 commit 之後重新辨識出的「會重新產生的紀錄」沒有被丟掉。
4. `close-stage.py` 與 `rest-queue.py` 對「狀態檔能不能用」的判定不一致，close stage 可能採用一個 `start` 會拒絕的檔裡的 review 值。

另有 9 項 In-scope fix。

## Root Cause

三個根源，各自對應一類，不只對應被指出的那一個點：

- **讀工作樹有兩種讀法。** 交出時用單純的 `git status --porcelain`，`settle` 用明確列出未追蹤檔的參數。修正輪 6 的性質有一句前提「交出時工作樹是乾淨的，所以沒追蹤的檔都是被忽略的檔」，這句話在兩種讀法不一致時不成立。現有的 suite 把 git 的全域設定設成空的，所以沒有一個測試看得到這一類。
- **`settle` 中途被中止之後，重跑靠的是第一次留在記憶體裡的東西。** 第 2、5 項是這一類的兩個點。寫了窮舉檢查之後，在 `48fe423` 上 477 個中止點有 71 處不符，分成六種。
- **保留的 commit 只在 commit 之前檢查留下物，沒有檢查 commit 本身。** hook 可以在兩者之間加東西。

第 4、9 項同源：rest 的狀態檔有三個讀法（`rest-queue.py`、`close-stage.py`、skill Phase 5 的 `jq`）。

## Proposed Solution

依維護者 2026-11-20 的決定（comment 7030459650）與做法說明（comment 7030508945）。

1. **讀工作樹只有一個入口。** `rest-queue.py` 只留一個 `git status` 呼叫，明確列出每個未追蹤檔、關掉 rename 偵測；`start`、`next`、`settle` 的每一個判斷都經過它。結束方式表與窮舉另外在一份會改變 git 預設顯示的全域設定下各跑一次。
2. **在任何一步被中止，重跑的結果相同。** `settle` 在做「之後無從得知」的步驟之前，先把需要的資訊寫進 run 的狀態：要丟的紀錄、要搬開的檔、那一張 branch 忽略的路徑（離開那個 branch 之前）、要寫進 exclude 的路徑。stash 的紀錄一律列出 stash 裡的檔，不論是當場寫的還是事後找回的。新 suite `rest-queue-sweep` 對 13 種結束方式的每一個中止點重跑並比對。
3. **保留的 commit 只有一個檢查。** commit 做完之後看它的路徑：交出時就在的路徑，撤回重做；不收進 git 的位置，撤回並以 3 結束。新做的 commit、不經 hook 的重做、重跑時找回的 commit 走同一個；工作樹已在預設 branch 時才發現的，以 3 結束並指出那個 commit。hook 擋下之後重新辨識出的紀錄照常丟掉。
4. **狀態檔只有一個判定。** 新檔 `scripts/lib/reststate.py`；`close-stage.py` 多一個子命令 `rest-review`，skill 的 Phase 5 改呼叫它。

其餘：寫進 exclude 之後確認真的生效，沒生效（預設 branch 有 `!` 規則）就把那一行拿掉、照實以 3 結束；comment 重讀之後核對數量；整個資料夾被忽略時「missing」只看那個資料夾，規格與文件照實寫；`settle` 在那一張的 branch 上停下、而那個 branch 追蹤了交出時就在的檔時，報告列出這些檔並說明手動 checkout 之前要先複製；結束方式表的 `existing-work` 列改成真的以 `existing work:` 記錄；接續說明的旗標；另一個 repo 的狀態檔的說法。

**凍結前的獨立檢查找到的（tasks 3.2）**：`diff.relative` 加上 `--cwd` 在子目錄時，「兩邊都追蹤、內容不同」的檢查失效，checkout 換掉使用者的檔；`settle` 停在那一張的 branch 時，原因行叫人「commit 或移除剩下的」，而 git 在那個 branch 上顯示的東西裡有使用者原本就在的檔；檔名含 carriage return 時讀到的路徑對不上；`origin` 在被忽略的資料夾的位置放了一個檔時，資料夾裡原本就在的檔被收進 stash；exclude 沒生效時連使用者自己寫的那一行也拿掉。處置寫在 tasks 2.4。

## Non-Goals

- 每張 issue 用獨立的 worktree（維護者 2026-11-20 沒有選）。
- 交出時就在的檔被那一張的 run 改了內容、或整個被忽略的資料夾裡少了個別的檔：不記內容與個別檔名，照實寫進規格。
- `submodule.<name>.ignore`、skip-worktree、assume-unchanged、`core.fileMode` 這幾種設定：沒有檢查，規格列出。
- 單張流程其餘的一般 checkout（#587）。

## Success Criteria

- `scripts/tests/rest-queue-sweep/test.sh` 通過：13 種結束方式、每一個中止點；結束方式表 29 列與窮舉 288 種組合在另一份 git 設定下通過；helper 只有一個 `git status` 呼叫。
- 第 7 輪第 1 項的重現（設定一行、一個未追蹤檔）：`start` 與 `next` 以 3 結束並指出那個檔。
- `close-stage.py rest-review` 對八種狀態檔印出規格表上的字；缺欄位的三種，`start` 以 3 結束、`run` 停在 verified。
- `scripts/run-all-tests.sh` 全部通過；對新程式的變異檢查每一處都有測試失敗。

## Impact

- Affected specs: `idd-all-rest`（修改 7 條 requirement）
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/rest-queue.py
  - Modified: plugins/issue-driven-dev/scripts/close-stage.py
  - Modified: plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - Modified: plugins/issue-driven-dev/scripts/tests/rest-queue/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/rest-queue/endings.py
  - Modified: plugins/issue-driven-dev/scripts/tests/rest-queue/settle_matrix.py
  - New: plugins/issue-driven-dev/scripts/lib/reststate.py
  - New: plugins/issue-driven-dev/scripts/tests/rest-queue-sweep/test.sh
  - New: plugins/issue-driven-dev/scripts/tests/rest-queue-sweep/kill_sweep.py
