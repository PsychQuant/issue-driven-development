## 1. 測試先寫

- [x] 1.1 依 design「照條文改程式，不改條文去配合程式」與「原因沿用 path leaves the repository」，為 requirement「Added and modified requirements carry an executable check」的 Example「markers in submodules」第 55 列寫 fixture 與檢查，加在 `plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 第 54 列的檢查之後：head 記錄一個 gitlink，它的上層目錄是指進主 repo git 目錄的 symbolic link，那裡有人工放進去、持有記錄的 commit 與標記的 clone。fixture 先確認 clone 持有那個 commit、那個 commit 有標記、而且 git 回報那個位置在 git 目錄內。檢查：`status` 是 `error`、結束碼 2、原因點名路徑與 path leaves the repository、記錄 git 呼叫的程式沒有看到任何一次在那個目錄的呼叫。驗證：這時 script 還沒改，`bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 只有第 55 列的檢查失敗；失敗的檢查名稱記在這一項底下。
  - 紀錄（script 還是 `8003a7b` 的版本）：`bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 802 項通過、4 項失敗、結束碼 1。失敗的四項都是第 55 列：`status`（得到 `ok`）、結束碼（得到 0）、原因（空的）、「no git command ran in the planted directory」（記錄到在那個目錄的呼叫）。同一列通過的三項是不分修正前後都成立的：回報的項目數是 0、只印一行 JSON、記錄 git 呼叫的程式看到主 repo 的呼叫。

## 2. 程式

- [x] 2.1 [after: 1.1] 依 design「git 目錄的位置問 git，用目錄的身分比，不比名稱」「只排除主 repo 自己的 git 目錄」「只在第一次要檢查 submodule 的目錄時問一次」與 Implementation Contract：`plugins/issue-driven-dev/scripts/spec-change.py` 的 `marker_files()` 在「解析後的目錄在頂層目錄內」之後多一個判斷，解析後的目錄是主 repo 的 git 目錄或在它底下時，原因是 path leaves the repository，不呼叫 `submodule_git()`。驗證：`bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 全部通過、0 項失敗；標記在主 repo 的 repo，git 呼叫的次數與修改前相同（第 22 列既有的檢查）。

## 3. 第五輪第 2 到 5 列

- [x] 3.1 [after: 2.1] 依 design「第 29 列：改 fixture，不改列」「建不出暫存目錄就停」「第 7 到 12 列的標籤改名」：`plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 的第 29 列 fixture 改成七個來源有標記、停在記錄的 commit、再 deinit 的 submodule，斷言不變；`mktemp` 失敗或結果不是目錄時印出原因並以 1 結束；第 7 到 12 列的 26 個標籤與這一段的註解、標題改用現在的 Example 標題的用詞。驗證：測試全部通過；`TMPDIR` 指向不存在的目錄時測試以 1 結束，而且沒有任何一行訊息提到根目錄下的路徑。
- [x] 3.2 [after: 3.1] 依 design「照條文改程式，不改條文去配合程式」與 Implementation Contract：`plugins/issue-driven-dev/CHANGELOG.md` 的 #548 條目兩處：條件的敘述寫明主 repo 自己的 git 目錄不算在工作目錄內；補一句 `submodule.recurse` 打開時答案會變的情況。驗證：`git diff` 對 CHANGELOG 只動 `[Unreleased]` 裡 #548 那一條；文字不含任何特定專案的名稱或本機路徑。

## 4. 收尾

- [ ] 4.1 [after: 3.2] 依 Implementation Contract 驗收：`bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 與 `bash .claude/scripts/tests/spectra-archive-post-ic/test.sh` 結束碼都是 0；把 2.1 的判斷拿掉時只有第 55 列的檢查失敗；link 指向工作目錄內另一個 clone 時仍回 `ok`、指到頂層目錄之外時仍回 `error`；`python3 plugins/issue-driven-dev/scripts/spec-change.py links --base origin/main --cwd .` 的結果。驗證：驗收紀錄寫在這一項底下；封存之後的結果寫在 issue 的 Implementation Complete 留言。
  - 驗收紀錄。這個 change 的文件、規格差異、測試與程式都由同一個協調者撰寫，沒有實作者模型，也沒有獨立讀者；第六輪 verify 是第一次獨立審查。環境：macOS、git 2.55.0、Python 3.13.5。
  - 整套測試（`dd8d2b9`，封存之前）：`bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 75 個 suite、0 個失敗、沒有逾時；`bash .claude/scripts/tests/spectra-archive-post-ic/test.sh` 141 項通過、0 項失敗。`bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 806 項通過、0 項失敗（第 55 列加了 7 項）。
  - 變異：在一份副本裡把 2.1 加的那個判斷拿掉，測試檔 802 項通過、4 項失敗，失敗的就是 1.1 記錄的那四項（第 55 列的 `status`、結束碼、原因、沒有在那個目錄執行 git）。
  - 三個 fixture，各用 4.1.0、修改前（`8003a7b`）、修改後的 script 跑一次，並記錄 git 呼叫。link 指進主 repo 的 `.git`：`missing`、`ok`（在那個目錄 5 次呼叫）、`error`（path leaves the repository，0 次）。link 指向工作目錄內的另一個 clone：`missing`、`ok`、`ok`（修改前後都是 5 次）。link 指到頂層目錄之外：`missing`、`error`、`error`（都是 0 次）。
  - 另外三種情況，修改前與修改後各跑一次。link 的目標寫成 `.GIT`（這個 volume 會折疊大小寫）：修改前 `error`（not checked out，在那個目錄執行了 1 次 git），修改後 `error`（path leaves the repository，0 次）。git 目錄用 `--separate-git-dir` 放在頂層目錄內、取名 `gd`，link 指進它：修改前 `ok`（5 次），修改後 `error`（0 次）。主 repo 是 linked worktree、submodule 照一般方式取出：修改前後都 `ok`，在 submodule 裡都是 5 次呼叫，整次執行的呼叫從 18 次變成 19 次（多的那一次是問 git 目錄在哪裡）；它的主 worktree 也一樣。
  - 暫存目錄：`TMPDIR` 指向不存在的目錄時，測試印出 mktemp 的錯誤與一行 FATAL，以 1 結束，共兩行，沒有任何一行提到根目錄下的路徑。
  - 連結檢查，封存之前（`python3 plugins/issue-driven-dev/scripts/spec-change.py links --base origin/main --cwd .`）：`{"status": "ok", "missing": [], "reason": ""}`。封存之後的結果寫在 issue 的 Implementation Complete 留言。
  - 沒有做的：測試只在 macOS 上跑過；記錄的路徑離開頂層目錄再回到頂層目錄本身的那一種情況沒有處理（design 的 Risks，#559）；外層 submodule 自己的 `.git` 真目錄那一種沒有實測。
