## 1. 測試先行

- [x] 1.1 requirement「A repository without a remote can opt into its local default branch」— spec-archive-local：Example 新增的列（`.git` 命名的 separate git dir、bare 主 repo、空白與空字串的 url），`master~1` 與條目內重複鍵兩列補原因斷言，linked worktree 那一列補 `has_remote` 與原因；第 5 步 remote 路徑照原文執行一次（有可 fetch 的 origin、沒有條目），fetch 失敗時附上 `link-base` 的原因。驗證：空白與空字串的 url、fetch 失敗的原因在改之前失敗；第 5 步 remote 路徑在「永遠不 fetch」的變異上失敗。
- [x] 1.2 requirement「spec-change.py reads the repository that holds --cwd」— spec-archive-local：Example 改名為 a top level whose name ends in whitespace，補換行結尾與 `preflight` 的列。驗證：換行結尾那列在改之前失敗。
- [x] 1.3 requirement「Close requires the issue's change to be archived」— spec-close-gate：「stops, naming the change」各列補 `not_archived` 的斷言；requirement「The helper can skip the branch lookup」— check-existing-work 第 4 列補 fetch、notes 與 open PR 的斷言。

## 2. 程式與文件

- [x] 2.1 `spec-change.py`（`one_line`、`remotes_of`、原因文字、link-base docstring）、spec-wrapper 第 5 步。驗證：1.1–1.3 通過。
- [x] 2.2 config-protocol 與 CHANGELOG 寫到目前的規則；issue 的 Proposal 與 Expected 第 3 項註明沒有 remote 時不 fetch。

## 3. 收尾

- [x] 3.1 run-all-tests.sh 與連結檢查。驗證：結束碼 0，links 回 ok。
