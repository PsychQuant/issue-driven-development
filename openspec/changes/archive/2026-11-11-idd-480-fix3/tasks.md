## 1. spec-change.py

- [x] 1.1 `declared` 與 `requirements()` 共用 CommonMark 的 fence 判斷，fence 不論縮排都算，換行只認 `\n`、`\r\n`、`\r`；標題前允許 0 到 3 格空白（requirement「Every implemented issue leaves a spec change or a declared exemption」、「Added and modified requirements carry an executable check」）。驗證：Example「reading the Spec line」新增兩列、「what the link check reports」新增兩列，各一個檢查，先看到失敗。
- [x] 1.2 `.spectra.yaml` 在 revision 上是目錄或 symlink 回 `error`；`spec_dir` 以 `:` 開頭回 `error`；git 一律用 literal pathspec；找不到 git 回 `error`（一行 JSON、exit 2）；錯誤訊息裡的值截到 60 字（requirement「The spec directory is resolved the way Spectra resolves it」）。驗證：Example「spec directory by .spectra.yaml」新增兩列，以及找不到 git 的檢查，先看到失敗。

## 2. skills 與契約

- [x] 2.1 `idd-close` Step 1.57：fetch 之後檢查 `FETCH_HEAD`；用 python 判斷宣告形式；結果表補「沒有輸出、不是 JSON、或狀態不在表上 → 停下」（requirement「Close requires the issue's change to be archived」）。驗證：`spec-close-gate` 實跑「遠端已撤銷封存、本機追蹤 ref 沒動」一列，先看到失敗。
- [x] 2.2 `idd-verify`：`SPEC_FILES` 只列主規格；改掉過時的說明（「不含別人的散文」、code profile「逐 byte 不變」的範圍）；規格的 Example「the spec context the reviewers get」三列由 `spec-wrapper-contract` 實跑並帶標記（`idd-verify` 的 requirement「Reviewers check behaviour against the specs」）。驗證：三列各一個檢查。
- [x] 2.3 契約第 5 步的連結檢查：`gh repo view`、`git fetch`、`git merge-base` 任一失敗或 `SPEC_BASE` 為空就停下。驗證：`spec-wrapper-contract` 檢查這段文字。
