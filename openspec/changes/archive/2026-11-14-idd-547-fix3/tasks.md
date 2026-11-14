## 1. 測試先行

- [x] 1.1 requirement「spec-change.py reads the repository that holds --cwd」— spec-archive-local：Example「a top level whose name ends in a space」三列，帶標記 spec-example: spec-on-every-issue / a top level whose name ends in a space。
- [x] 1.2 requirement「A repository without a remote can opt into its local default branch」— spec-archive-local：Example 新增的各列（separate-git-dir 加 linked worktree、各種重複鍵、偽造記號、`null`、`vcs`、`has_remote`、UTF-16 log），以及第 3 輪第 4 列要補的三個細節斷言。驗證：改之前新的列失敗。
- [x] 1.3 requirement「Close requires the issue's change to be archived」— spec-close-gate：名為 `origin` 的本機 repo 不會讓沒有 remote 的 repo 通過，也不 fetch。驗證：改之前失敗。
- [x] 1.4 requirement「The helper can skip the branch lookup」— check-existing-work：`--skip-branches` 而 `gh repo view` 失敗時不讀 `origin/HEAD`、不記預設 branch 的錯誤；spec-wrapper 第 5 步 `link-base:` 標籤。

## 2. 程式與文件

- [x] 2.1 `spec-change.py`、`check-existing-work.sh`、idd-close Step 1.57、spec-wrapper 第 5 步。驗證：1.1–1.4 通過。
- [x] 2.2 docstring、config-protocol、CHANGELOG 寫到目前的規則。

## 3. 收尾

- [x] 3.1 run-all-tests.sh 與連結檢查。驗證：結束碼 0，links 回 ok。
