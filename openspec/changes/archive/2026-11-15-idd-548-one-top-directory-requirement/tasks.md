## 1. 標記與說明

- [x] 1.1 依 design「標記改指向已發布的 Example，不讓兩個 Example 並存」與「六列搬過去，一列一列寫，不合併」：`plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 檔頭的標記與「top directory names」那一段的標題，改指向 requirement「spec-change.py reads the repository that holds --cwd」的 Example「a top level whose name ends in whitespace」（它新增的六列就是這一段既有的檢查）；斷言不新增、不移除、不改。驗證：`bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 799 項通過、0 項失敗；`git diff` 對這個檔案只有這兩處。
- [x] 1.2 [after: 1.1] 依 design「留已發布的那一條，移除這條分支的那一條」：`plugins/issue-driven-dev/CHANGELOG.md` 的 #548 條目拿掉 4.1.0 已經發布的那一句，改寫成 Example 新增的列。驗證：`git diff` 對 CHANGELOG 只動 `[Unreleased]` 裡 #548 那一條；文字不含任何特定專案的名稱或本機路徑。

## 2. 收尾

- [x] 2.1 [after: 1.2] 依 design「讀 git 印出的路徑只用一個 helper」與 Implementation Contract 驗收：`bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 與 `bash .claude/scripts/tests/spectra-archive-post-ic/test.sh` 結束碼都是 0；`tests/spec-archive-local/test.sh` 通過；合併前後讀路徑的兩種寫法對同一組位元組輸入回傳相同；`python3 plugins/issue-driven-dev/scripts/spec-change.py links --base origin/main --cwd .` 在封存之前回 `missing`、只列出要被移除的那一條 requirement（它的 Example 已經沒有標記，而移除它的 delta 要到封存才套用），封存之後回 `ok`。驗證：封存之前的結果寫在這一項底下；封存之後的結果寫在 issue 的 Implementation Complete 留言。
  - 驗收紀錄。這個 change 的文件、規格差異與兩處修改都由同一個協調者撰寫，沒有實作者模型，也沒有獨立讀者；第五輪 verify 是第一次獨立審查。
  - 整套測試跑了兩次。合併 commit（`f08839f`）上：`bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 75 個 suite、0 個失敗，`bash .claude/scripts/tests/spectra-archive-post-ic/test.sh` 141 項通過。這個 change 的兩處修改提交之後（`6758b3d`，封存之前的工作樹）：75 個 suite、0 個失敗，`spectra-archive-post-ic` 141 項通過。
  - `bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 799 項通過、0 項失敗；`bash plugins/issue-driven-dev/scripts/tests/spec-archive-local/test.sh` 126 項通過，這個檔案與預設分支（`3b87909`）的逐位元組相同。
  - `git diff 54a9092 6758b3d -- plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 只有兩行不同：檔頭的標記與這一段的標題。第四輪審過的測試檔（`54a9092` 的版本）配合併後的 script：799 項通過。
  - 讀路徑的兩種寫法（合併前：在位元組上去掉一個行尾再 `os.fsdecode`；合併後：`one_line(os.fsdecode(...))`），十組位元組輸入回傳相同：結尾一個換行、空白加換行、兩個換行、沒有換行、空的、只有換行、兩個不合法的 UTF-8 位元組、中文、CR 加 LF、不合法位元組加兩個換行。
  - 連結檢查，封存之前（`6758b3d`，`python3 plugins/issue-driven-dev/scripts/spec-change.py links --base origin/main --cwd .`）：`status` 是 `missing`，只列一項：requirement「The repository's top directory is read as git prints it」的 Example「top directory names」沒有標記。這是預期的：標記已經改指向留下的那個 Example，而移除這條 requirement 的 delta 到封存才套用。封存之後的結果記在 issue 的 Implementation Complete 留言。
  - 沒有做的：這個 change 沒有新的變異測試（斷言沒有改，script 的兩處在合併 commit 裡、回傳值不變）；測試只在 macOS 上跑過。
