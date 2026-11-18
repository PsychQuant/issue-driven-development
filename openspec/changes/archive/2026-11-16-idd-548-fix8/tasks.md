## 1. 測試

- [x] 1.1 依 design「第 50 列的 fixture 記下結束碼，不停下」「測試檔的註解寫量到的版本」與 Implementation Contract：`plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 第 50 列，註解換成新的說法，前提檢查那一行換成「記下 `git grep` 的結束碼，大於 1 時印說明行」。驗證：改之前的測試檔在 git 2.56.0 上停在第 50 列；改之後 `bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 在 git 2.54.0、2.55.0、2.56.0 上都是 878 項通過、0 項失敗，只有 2.56.0 印出說明行；`git diff` 對 `plugins/issue-driven-dev/scripts/spec-change.py` 沒有輸出。
  - 紀錄，改之前（`e5022f4` 的測試檔，git 2.56.0 在 PATH 最前面，macOS）：559 項通過之後印出 `FATAL: spec-change suite: fixture setup failed: the search of a submodule with an empty object must end with 0 or 1`，結束碼 1。與 PR #572 的 CI（git 2.56.1、ubuntu-26.04）停在同一行。
  - 紀錄，改之後（同一台機器，`spectra` 在 PATH 上）：git 2.54.0、2.55.0、2.56.0 各跑一次，都是 878 項通過、0 項失敗、結束碼 0。2.54.0 與 2.55.0 沒有印說明行；2.56.0 印出 `~ note: this git ends the search of an empty object with exit code 128, row 50 takes the path of row 49`。
  - 同一個輸入上三個版本的 `git grep` 結束碼：1、1、128。前兩個印 `error: … unable to read …`，第三個印 `fatal: loose object … is corrupt`。
  - git 2.56.0 是把 Homebrew 的 bottle 解到暫存目錄執行的，沒有安裝。CI 用的 2.56.1 沒有在本機跑過。
  - `git diff` 對 `spec-change.py` 沒有輸出；測試檔的差異只有第 50 列：註解 2 行換成 4 行，前提檢查 1 行換成 4 行。

## 2. 文字

- [x] 2.1 依 design「Example 第一欄寫兩種情形，不寫版本號」與 Implementation Contract：這個 change 的規格差異把 requirement「Added and modified requirements carry an executable check」的 Example「markers in submodules」第 50 列第一欄的後半句換掉，其他不變。驗證：規格差異與現行 requirement 逐行比對，只有那一列不同；`spectra validate idd-548-fix8` 通過。
  - 紀錄：規格差異由腳本從現行 requirement 產生，只做一處取代，而且要求恰好一處相符。現行 123 行，差異 123 行，移除 1 行、加入 1 行，就是第 50 列；Example 仍是 65 列。`spectra validate idd-548-fix8` 回 valid。

## 3. 收尾

- [x] 3.1 [after: 1.1, 2.1] 依 Implementation Contract 驗收：封存之前 `bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 與 `bash .claude/scripts/tests/spectra-archive-post-ic/test.sh` 結束碼都是 0，數字記在這一項底下。封存之後的三項檢查（`spec-change.py links` 從預設分支到 HEAD、`archived`、現行規格與封存前只差那一列）要等封存完才能跑，結果記在 issue 的實作摘要，不記在這裡。
  - 驗收紀錄。這個 change 的文件、規格差異與測試修改都由同一個協調者撰寫，沒有獨立讀者，也不開 verify 輪（維護者的決定，留言 6910032608）。環境：macOS、Python 3.13.5、git 2.55.0。
  - 封存之前，在改過的工作目錄上：`bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 75 個 suite、0 個失敗，結束碼 0，其中 `spec-change` 878 項通過；`bash .claude/scripts/tests/spectra-archive-post-ic/test.sh` 141 項通過、0 項失敗，結束碼 0。
  - 沒有做的：這個 change 沒有在 Linux 上跑過；推上去之後 PR #572 的 CI 會跑，第 50 列以後的檢查是第一次在那裡執行。design 的 Risks 第一點（git 2.56 起沒有只有「先問哪些物件打不開」那一步才抓得到的測試輸入）沒有處理。
