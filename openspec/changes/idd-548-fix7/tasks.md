## 1. 測試先寫

- [x] 1.1 依 design「四列 Example，只在不分大小寫的磁碟上執行」，為 requirement「Added and modified requirements carry an executable check」的 Example「markers in submodules」第 60 到 63 列寫 fixture 與檢查，加在 `plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 第 59 列的檢查之後；先偵測放 fixture 的磁碟是否區分大小寫，區分時印出一行說明並略過這四列。第 60 列：link 的目標把頂層目錄寫成另一種大小寫，submodule 在工作目錄裡，`links` 回 `ok`，git 在記錄的路徑搜尋。第 61 列：樹裡記 `tests/sub`、磁碟上的目錄是 `Tests/sub`，回 `ok`。第 62 列：link 指到頂層目錄之外、目標用另一種大小寫，回 `error`（path leaves the repository），git 不在那個目錄執行，也沒有問那兩個目錄。第 63 列：link 指進主 repo 的 git 目錄、目標把頂層目錄寫成另一種大小寫，回 `error`（path leaves the repository），git 不在那個目錄執行，而且問過那兩個目錄。macOS 上 `/System/Volumes/Data` 的拼法指得到 fixture 時，用它重跑第 60 列的輸入。驗證：在不分大小寫的磁碟上執行 `bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh`，script 還沒改時第 60、61 列的檢查與第 63 列「問過那兩個目錄」的檢查失敗，第 62 列與第 63 列的其他檢查通過，第 1 到 59 列的檢查全部通過。
  - 紀錄（script 未改，git 2.55.0、macOS、不分大小寫的 APFS、`spectra` 在 PATH 上）：859 項通過、9 項失敗。失敗的是第 60 列的三項（`status` 要 `ok` 得到 `error`、結束碼要 0 得到 2、git 沒有在記錄的路徑搜尋）、第 60 列改用 `/System/Volumes/Data` 拼法的兩項（`status`、結束碼）、第 61 列的三項（同第 60 列的三項）、第 63 列的一項（git 沒有被問那兩個目錄）。第 62 列的七項、第 63 列的其他六項與第 1 到 59 列的檢查都通過。
- [x] 1.2 [after: 2.1] 依 design「落在規格目錄裡的 submodule 不搜尋，不論路徑叫什麼」，為 Example「markers in submodules」第 64、65 列寫 fixture 與檢查，加在同一個測試檔：第 64 列放在需要不分大小寫的磁碟的那一段裡（樹裡記的路徑把規格目錄寫成另一種大小寫，clone 落在規格目錄裡），第 65 列放在那一段之後（link 指進規格目錄，任何磁碟都執行）。兩列都要 `links` 回 `missing`、列出一項、結束碼 1，而且 git 沒有在那個目錄執行。略過的說明改成第 60 到 64 列。驗證：在 2.1 之後的 script 上，第 64、65 列的檢查失敗（`status` 得到 `ok`，git 在那個目錄執行過），其餘檢查全部通過。
  - 紀錄（script 是 2.1 之後的，同一環境）：870 項通過、8 項失敗，第 64、65 列各四項：`status` 要 `missing` 得到 `ok`、列出的項數要 1 得到 0、結束碼要 1 得到 0、git 在那個目錄執行過。

## 2. 程式

- [x] 2.1 [after: 1.1] 依 design「『在頂層目錄底下』的意思是往上走會遇到頂層目錄」「往上走經過的目錄，就是與那兩個 git 目錄比對的清單」「第 5 個條件用同一種比對」「檢查不到的目錄略過」與 Implementation Contract：`plugins/issue-driven-dev/scripts/spec-change.py` 新增 `directories_below_top()`、`leaves_repository()`、`same_directory()`，`under_git_directory()` 改成比對一份清單，`marker_files()` 的第 2、5 個條件改用它們；檔頭與函式的說明改成同樣的說法。驗證：`bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 全部通過；第七輪協調者的兩個重現（上游只改大小寫後 pull；link 的目標寫成 `/System/Volumes/Data` 的拼法）都回 `ok`。
  - 紀錄（`54d1775`，同一環境）：868 項通過、0 項失敗。兩個重現用這份 script 重跑：上游把 `Tests/sub` 改成 `tests/sub` 之後 pull，`links` 回 `ok`；link 的目標寫成 `/System/Volumes/Data` 的拼法回 `ok`，對照（一般的拼法）也回 `ok`。
- [x] 2.2 [after: 1.2] 依 design「落在規格目錄裡的 submodule 不搜尋，不論路徑叫什麼」與 Implementation Contract：`plugins/issue-driven-dev/scripts/spec-change.py` 新增 `in_spec_directory()`，`marker_files()` 在第 2 個條件之後多一個分支：往上走經過的目錄裡有規格目錄時，這個 submodule 不搜尋，也不列為搜尋不到；檔頭的說明加上這一點。驗證：`bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 全部通過。
  - 紀錄（`9fb5cc1`，同一環境）：878 項通過、0 項失敗。

## 3. 文字

- [ ] 3.1 [after: 2.2] 依 design「條文的三句（第七輪第 3、4 列）」與 Implementation Contract：`plugins/issue-driven-dev/CHANGELOG.md` 的 #548 條目講第 2、5 個條件與規格目錄的那兩句，與 `plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 第 57 列的註解，改成新的說法。驗證：`git diff` 對 CHANGELOG 只動 `[Unreleased]` 裡 #548 那一條；文字不含任何特定專案的名稱或本機路徑；測試仍然全部通過。

## 4. 收尾

- [ ] 4.1 [after: 3.1] 依 design「照名稱比對而這次不動的地方」與 Implementation Contract 驗收：`bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 與 `bash .claude/scripts/tests/spectra-archive-post-ic/test.sh` 結束碼都是 0；逐一把 2.1 的每一處改回去或改壞（第 2 個條件改回字串比對、第 5 個條件改回字串相等、拿掉與 git 目錄的比對、往上走一律當成遇到頂層目錄、把頂層目錄與它的上層也拿去比對、與 git 目錄的比對改回名稱、檢查不到的目錄不略過、拿掉規格目錄的檢查），記下每一種讓哪些列的檢查失敗；在區分大小寫的磁碟上跑一次測試檔，確認略過的說明印出來、其餘全部通過；重量 git 呼叫次數；找有沒有第 60、61 列以外、答案從 `error` 變成 `ok` 的輸入；`python3 plugins/issue-driven-dev/scripts/spec-change.py links --base origin/main --cwd .` 回 `ok`。把結果與各環境下的檢查項數寫在這一項底下。
