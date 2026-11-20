## 1. 三條性質與它們的檢查

- [x] 1.1 helper 加上中止點（測試用，與其他測試 hook 同一個環境變數才生效）；新 suite `scripts/tests/rest-queue-sweep/`：`kill_sweep.py` 對 13 種結束方式的每一個中止點重跑並比對（requirement「Between two issues one helper settles the working tree」的 Example `settle killed at any point and run again ends where an undisturbed settle ends`）。完成時：在還沒改的 `rest-queue.py` 上有不符（實測 477 個中止點、71 處）。
- [x] 1.2 同一個 suite：結束方式表與窮舉在另一份 git 全域設定下各跑一次（Example `what git shows by default does not change what settle does`）；helper 只有一個 `git status` 呼叫（Example `the helper reads the working tree in one place`）。`endings.py` 與 `settle_matrix.py` 接受測試用的全域設定路徑。
- [x] 1.3 `scripts/tests/rest-queue/test.sh`（各帶 `spec-example` 標記）。Requirement「Between two issues…」：Example `what git shows by default does not change what is handed out`、`a hook that lets the commit through cannot add a file that is never committed`、`a record a rejecting hook wrote is discarded, not committed`、`a kept commit that holds a file from before the run stops settle on the default branch`、`a rule of the default branch that un-ignores the file stops settle`。Requirement「The open issues are read completely or not at all」：Example `fewer comments than the issue has`。Requirement「A rest run keeps its review flag」：Example `the review flag of a rest run has one reader`。Requirement「Report lists what happened and ends the run」：Example `the report says what to copy before a checkout by hand`。完成時：這些檢查在還沒改的程式上失敗。

## 2. 實作

- [x] 2.1 `rest-queue.py`：一個 `status_z`；`keep_tip` 與 `not_to_keep`（commit 之後的檢查，新做的與找回的走同一個）；`settle_tree` 在每個「之後無從得知」的步驟之前先寫狀態（`discarded`、`holding`、`left`、`excluded`），stash 的紀錄列出檔；`unexclude_locally`；comment 數量核對；另一個 repo 的狀態檔的說法；報告的複製步驟。完成時：1.1、1.2、1.3 通過。
- [x] 2.2 新檔 `scripts/lib/reststate.py`；`close-stage.py` 的 `rest_review` 用它，並加子命令 `rest-review`；`skills/idd-all/SKILL.md` Phase 5 改呼叫它，接續說明補上旗標。完成時：1.3 的 review 檢查與 `scripts/tests/close-stage/test.sh` 通過。
- [x] 2.3 文件：`skills/idd-all/SKILL.md` 的 rest 一節（一個讀法、中止後重跑、commit 的檢查、exclude 沒生效時停下、missing 的限制、手動 checkout 之前的複製）；`references/working-tree-writers.md`；CHANGELOG。結束方式表的 `existing-work` 列與兩列 stash 的說法。

- [x] 2.4 3.2 的 reviewer 找到的（requirement「Between two issues…」與「Report lists what happened and ends the run」）：helper 的每個 git 呼叫帶固定的設定、輸出以位元組讀取（Example `what git is configured to print does not change what settle compares`、`a carriage return in a file name`）；資料夾的紀錄涵蓋資料夾本身的路徑（Example `a file that origin puts where an ignored folder stands`）；exclude 只拿掉自己加的行（Example `a line of the local exclude file that settle did not add stays`）；`settle` 停在那一張的 branch 時，報告列出 git 顯示出來的原本就在的檔（Example `the report says which files in sight are not what the run left`）。完成時：這五個 Example 的測試通過。

## 3. 驗證

- [x] 3.1 對新程式做變異檢查，變異檢查同時跑 `rest-queue` 與 `rest-queue-sweep` 兩個 suite；每一處至少有一個測試失敗。
- [x] 3.2 請一位沒有參與實作的 reviewer 在臨時 repo 實際執行，任務只有一個：在任何一步中止 `settle`，或設任何 git 設定，然後找出一個交出之前就在、之後不見或變了的檔。
- [x] 3.3 跑 `scripts/run-all-tests.sh`，全部通過。
