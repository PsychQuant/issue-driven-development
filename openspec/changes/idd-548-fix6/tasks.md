## 1. 測試先寫

- [x] 1.1 依 design「清單只有兩個目錄，而且寫明是封閉的」「往上比對只到頂層目錄為止」「解析後就是頂層目錄的路徑符合第 2 個條件」，為 requirement「Added and modified requirements carry an executable check」的 Example「markers in submodules」第 56 到 59 列寫 fixture 與檢查，加在 `plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 第 55 列的檢查之後。第 56 列：linked worktree 的頂層目錄裡放著主 repo，link 指進主 repo 的 git 目錄裡人工放的 clone；fixture 先確認 git 在頂層印的兩個目錄不同、放 clone 的位置在 git 目錄內；檢查 `status` 是 `error`、結束碼 2、原因點名路徑與 path leaves the repository、記錄 git 呼叫的程式沒有看到任何一次在那個目錄的呼叫。第 57 列：外層 submodule 的 `.git` 是真目錄，link 指進它；檢查回 `ok`。第 58 列：頂層目錄在主 repo 的 git 目錄裡面，submodule 照一般方式取出；fixture 先確認 git 在頂層同時回報在工作目錄內與在 git 目錄內；檢查回 `ok`。第 59 列：記錄的路徑經過 link 回到頂層目錄本身，記錄的是主 repo 較早、有標記的 commit；檢查回 `ok`。驗證：這時 script 還沒改，`bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 只有第 56 列的檢查失敗；失敗的檢查名稱記在這一項底下。
  - 紀錄（script 未改，git 2.55.0、macOS）：821 項通過、4 項失敗，四項都是第 56 列：`links: submodule row 56: linked worktree that holds the main repository — status`（要 `error`，得到 `ok`）、同名的 `— exit`（要 2，得到 0）、`links: submodule row 56 — reason names Example and path`、`links: submodule row 56 — no git command ran in the planted directory`。第 57、58、59 列與第 56 列的另外三項（回報的項目數、只有一行 JSON、記錄 git 呼叫的程式看到 worktree）通過。

## 2. 程式

- [x] 2.1 [after: 1.1] 依 design「兩個目錄分兩次問，相對路徑接在頂層目錄後面」「往上比對只到頂層目錄為止」與 Implementation Contract：`plugins/issue-driven-dev/scripts/spec-change.py` 在主 repo 的頂層問 `--absolute-git-dir` 與 `--git-common-dir`，解析後的目錄或它到頂層目錄之間的任何一層是兩者之一時，原因是 path leaves the repository，不呼叫 `submodule_git()`；檔頭與函式的說明改成同樣的說法。驗證：`bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 全部通過、0 項失敗；標記在主 repo 的 repo，git 呼叫的次數與修改前相同（第 22 列既有的檢查）。

## 3. 文字

- [ ] 3.1 [after: 2.1] 依 design「條文寫比對的內容，不寫『工作目錄』」與 Implementation Contract：`plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 第 55 列的註解，與 `plugins/issue-driven-dev/CHANGELOG.md` 的 #548 條目講這個條件的那一句，改成新的說法。驗證：`git diff` 對 CHANGELOG 只動 `[Unreleased]` 裡 #548 那一條；文字不含任何特定專案的名稱或本機路徑；測試仍然全部通過。

## 4. 收尾

- [ ] 4.1 [after: 3.1] 依 Implementation Contract 驗收：`bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 與 `bash .claude/scripts/tests/spectra-archive-post-ic/test.sh` 結束碼都是 0；把 2.1 新加的比對（common 目錄）拿掉時只有第 56 列的檢查失敗；第 55 列仍回 `error`；一般的 linked worktree（主 repo 在旁邊）裡照一般方式取出的 submodule 仍回 `ok`；`python3 plugins/issue-driven-dev/scripts/spec-change.py links --base origin/main --cwd .` 的結果。驗證：驗收紀錄寫在這一項底下；封存之後的結果寫在 issue 的 Implementation Complete 留言。
