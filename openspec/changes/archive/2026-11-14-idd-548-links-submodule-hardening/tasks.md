## 1. 測試先行

- [x] 1.1 requirement「Added and modified requirements carry an executable check」的 Example「markers in submodules」第 16 到 35 列各有一個檢查：在 `plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 的「links: markers in submodules」區塊，依表的順序為二十列各加檢查，每列斷言 `status`、結束碼與該列對原因文字的要求；第 21、22、31 列另外斷言 `config` 指定的指令沒有執行（執行的話會產生一個標記檔），第 23 列對外面有與沒有 repository 各跑一次並斷言結果相同，第 19、20 列斷言原因裡沒有 git 的錯誤訊息，第 32、33 列斷言沒有東西被抓進 submodule。同一項裡補上第 4、5 列 fixture 的失敗檢查（在 submodule 工作樹做較新 commit 的兩行加 `|| setup_failed`，並在跑 `links` 之前斷言工作樹的 commit 與主 repo 記錄的不同）。fixture 用通用字樣，不含任何專案名稱或本機路徑。驗證：改 `spec-change.py` 之前執行整個檔案，新的檢查除了第 27、35 列可能已通過之外，每一列至少一項失敗，既有的檢查全部通過；實作者列出每一列的結果。

## 2. 實作與說明

- [x] 2.1 [after: 1.1] 依 design「找到就停，主 repo 先搜尋」「只在符合六個條件的目錄跑 git」「在 submodule 目錄跑 git 的方式」「submodule 裡的失敗算搜尋不了」「路徑照位元組處理」「規格目錄底下的 gitlink 略過」「原因文字有上限」改 `plugins/issue-driven-dev/scripts/spec-change.py` 的 `marker_files()` 與 `cmd_links()`，並加一個只用在 submodule 目錄的 git 包裝。驗證：1.1 的檢查全部通過；`tests/spec-change/test.sh` 既有的檢查全部通過、檢查數不減、沒有任何既有檢查被改寬；`python3 -m py_compile plugins/issue-driven-dev/scripts/spec-change.py` 通過。
- [x] 2.2 [after: 2.1] 說明文件：`spec-change.py` 檔頭的 `links` 段寫明 submodule 要取出並有記錄的 commit 才搜尋得了、主 repo 找到標記就不看 submodule；`plugins/issue-driven-dev/references/spec-wrapper.md` 在講 submodule 的那一句之後補上「檢查前先跑 `git submodule update --init --recursive`」與「樹裡記成 submodule、`.gitmodules` 卻沒有對應項目的路徑無法取出」；`plugins/issue-driven-dev/CHANGELOG.md` 改寫這條分支加的 #548 條目，寫出最後的行為。驗證：`git diff` 對 CHANGELOG 只動 #548 那一條；文字不含任何特定專案的名稱或本機路徑。

## 3. 收尾

- [x] 3.1 [after: 2.2] 跑整套測試：`bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 與 `bash .claude/scripts/tests/spectra-archive-post-ic/test.sh`。驗證：結束碼都是 0；實作者的沙箱寫不進某個 suite 需要的位置時，由協調者在沙箱外重跑整套並記錄。
- [x] 3.2 [after: 3.1] 協調者驗收（在實作者寫不到的目錄）：逐行讀改動；在一份只套用新測試檔、script 維持 `afd0021` 的複本上重跑 1.1，確認哪些列失敗，並確認第 21 列的標記檔在那份複本上確實被建立；重跑 `tests/spec-change/test.sh` 與整套測試；用舊測試檔配新 script 確認既有檢查沒有少；對沒有 gitlink 的 repo，以及有 gitlink 而標記都在主 repo 的 repo，比對新 script 與這條分支之前的 script（`6ed8dec`）的輸出逐位元組相同；重放協調者的兩個重現與第一輪審查者的重現（tree 讀不到、部分 clone 而遠端連不到、路徑結尾是空白、規格目錄底下沒取出的 submodule、`GIT_DIR`、缺 blob、含 `..` 的路徑、經過 symbolic link 的路徑）。驗證：驗收紀錄寫在這一項底下，每個結果附指令。

  驗收紀錄（2026-11-14；1.1 到 3.1 由實作者模型 Codex gpt-6-astra 依工作單完成，3.2 由協調者 Claude Fable 5.2 在實作者寫不到的目錄執行。數字以最後的測試檔為準，含 4.1 補的列）：

  - 逐行讀過 `spec-change.py`、`tests/spec-change/test.sh`、`references/spec-wrapper.md`、`CHANGELOG.md` 的改動。
  - 只套用新測試檔、script 維持 `afd0021` 的複本，跑 `bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh`：587 通過、61 失敗，失敗的都在第 16 到 41 列。其中第 21、22、31 列的「植入的指令沒有執行」在這份複本上失敗（標記檔被建立了），第 32、33 列的「沒有抓取」也失敗（檔案內容被抓回）。所以這些檢查分辨得出第一輪找到的問題。實作者交回時的測試檔（第 16 到 35 列）在同一份複本上是 562 通過、50 失敗；第 27、35 列在舊 script 上已經通過，其餘每一列至少一項失敗。
  - 工作樹的複本跑同一個指令：648 通過、0 失敗。舊測試檔配新 script：`afd0021` 的測試檔 497 通過、`6ed8dec` 的測試檔 431 通過，都是 0 失敗，既有的檢查沒有少。
  - 輸出不變的兩種 repo，新 script 對照這條分支之前的 script（`6ed8dec`），輸出與結束碼逐位元組相同：沒有 gitlink 的 repo（這個 repo 自己的三段歷史 `401cd33..6ed8dec`、`2dc56ab..6ed8dec`、`fdf8d0d..4921b71`）；有 gitlink 而標記都在主 repo 的臨時 repo（一個取出的 submodule、一個沒取出的 gitlink、一個路徑不是合法 UTF-8 的 gitlink，兩個 Example）。
  - 協調者的兩個重現：路徑不是合法 UTF-8 的 gitlink、標記在主 repo，新 script 回 `ok`（`afd0021` 的 script 以 traceback 結束）；形狀像 git 目錄的資料夾，新 script 回 `error`、原因是 `tests/sub/emb: not checked out`、標記檔不存在（`afd0021` 的 script 建立了標記檔）。
  - 第一輪審查者的重現各自成為 Example 的一列，由測試執行，不另外重放：tree 讀不到（第 18、19 列）、部分 clone（第 32、33 列）、路徑結尾是空白（第 25 列）、規格目錄底下沒取出的 submodule（第 26 列）、`GIT_DIR`（第 28 列）、缺檔案內容（第 20 列）、含 `..` 的路徑（第 23 列）、經過 symbolic link 的路徑（第 24 列）。
  - 變異測試：在追蹤檔案的複本上各拿掉一處防護，再跑 `tests/spec-change/test.sh`，共 22 種。21 種都有檢查失敗；唯一沒有的是留著 `GIT_INDEX_FILE`（原因見 design「在 submodule 目錄跑 git 的方式」）。
  - `python3 -m py_compile plugins/issue-driven-dev/scripts/spec-change.py` 通過。
  - 整套測試在沙箱外、最後的檔案上跑：`bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 74 個 suite、0 個失敗，結束碼 0；`bash .claude/scripts/tests/spectra-archive-post-ic/test.sh` 141 通過、0 失敗。實作者在沙箱裡跑的那一次有三個 suite（correct-flow、edit-run、in-place-correction）因為寫不進暫存位置而失敗，與這次改動無關。

## 4. 封存前的補強（spectra-verify 之後）

- [x] 4.1 [after: 3.2] 依 `spectra-verify` 的三項 warning 與兩項建議補強：依 design「submodule 裡的失敗算搜尋不了」，submodule 的搜尋沒找到算數的檔案而 git 有錯誤輸出時（含結束碼 0），算搜尋不了；Example「markers in submodules」加第 36 到 41 列與對應的檢查（標記只在 `.md`、另一個檔案讀不到；git 回報別的目錄是頂層；路徑順序與走訪順序不同；路徑含 `.` 的段；六個繼承的變數都指向主 repo；繼承的 `GIT_ALTERNATE_OBJECT_DIRECTORIES` 指向另一個有記錄的 commit 的物件庫）；第 22 列加一個檢查，記錄每一次 git 呼叫，確認沒有任何一次在 submodule 目錄；判斷 blob 在不在的檢查改成只列本機物件。驗證：第 36 列在補上修正之前失敗、之後通過；第 37 到 41 列以變異測試確認（各拿掉對應的一處程式，該列失敗）；六個繼承的變數裡，只有 `GIT_INDEX_FILE` 留著時沒有任何檢查會失敗，原因記在 design；`bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 全部通過。

  紀錄（2026-11-14；這一項是協調者自己寫的改動，沒有經過實作者模型。封存前的 `spectra-verify` 讀的是補強之前的檔案，而且沒有執行測試。這一項沒有獨立讀者審過，交給下一步的 verify）：

  - `spectra-verify` 的第一項 warning 重現成立：submodule 裡標記只出現在 `.md` 檔、另一個檔案的內容讀不到時，`git grep` 回 0 並在錯誤輸出留下訊息，實作者的 script 把它當成搜尋過而回 `missing`（第 36 列的四項檢查失敗，其餘通過）。補上之後回 `error`。
  - 第二項（「git 回報別的目錄是頂層」的分支沒有測試）：第 37 列。第三項（第 29 列分辨不出有沒有排序）：第 38 列，fixture 的走訪順序與路徑順序不同。
  - 兩項建議：路徑含 `.` 的段（第 39 列）；`GIT_DIR` 以外的繼承變數（第 40、41 列）。第 41 列是變異測試之後加的：留著 `GIT_ALTERNATE_OBJECT_DIRECTORIES` 時，submodule 自己沒有的 commit 會被當成有，結果變成 `ok`。
  - 另外加的檢查：第 22 列以一個會記錄的 git 包裝再跑一次，確認主 repo 有標記時沒有任何 git 指令在 submodule 目錄執行；判斷檔案內容在不在物件庫的檢查改成只列本機物件，不依賴 `GIT_NO_LAZY_FETCH`。
  - 變異測試裡對應這一項的結果：不排序 → 第 38 列失敗；接受 `.` → 第 39 列失敗；不比對 git 回報的頂層 → 第 37 列失敗；忽略 submodule 搜尋的錯誤輸出 → 第 20、36 列失敗；找到之後繼續走訪 → 第 22 列的新檢查失敗；留著 `GIT_WORK_TREE`、`GIT_OBJECT_DIRECTORY`、`GIT_COMMON_DIR` → 第 40 列失敗；留著 `GIT_ALTERNATE_OBJECT_DIRECTORIES` → 第 41 列失敗；留著 `GIT_INDEX_FILE` → 沒有檢查失敗。
  - 補強之後 `bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh`：648 通過、0 失敗。Example 表現在是四十一列。
