## 1. 測試先行

- [x] 1.1 第二輪找到的行為各有可執行的檢查：在 `plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 為 requirement「Added and modified requirements carry an executable check」的 Example「markers in submodules」第 42 到 48 列與「what the link check reports」新增的一列各加檢查；為 requirement「The repository's top directory is read as git prints it」的 Example「top directory names」三列各加檢查，測試檔的標記清單加上 spec-example: spec-on-every-issue / top directory names。同一項裡：第 11、12 列的 fixture 設定 `submodule.recurse` 的那一步加失敗檢查並確認設定值；第 22 列的 git 呼叫紀錄另外確認沒有列出 gitlink 的呼叫（`ls-tree -r -z <commit>`；讀設定檔與列規格檔的 `ls-tree` 不算），並以一個標記不在主 repo 的 fixture 確認這種呼叫確實會被記下。fixture 用通用字樣，不含任何專案名稱或本機路徑。驗證：改 `spec-change.py` 之前執行整個檔案，第 42、43、46、47 列、「top directory names」的 `archived` 與 `preflight` 兩列、非 UTF-8 那一列的原因各至少一項失敗，第 44、45、48 列與 `links` 那一列通過，既有的檢查全部通過；實作者列出每一列的結果。
  - 驗收紀錄（協調者，在一份只換測試檔、script 維持 `7ad9152` 的複本上執行 `bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh`）：724 項通過、21 項失敗。失敗的是：非 UTF-8 那一列的原因（1 項）、第 42 列（2 項）、第 46 列（5 項）、第 47 列的兩種情況（各 4 項）、「top directory names」的 `archived`（3 項）與 `preflight`（2 項）。第 44、45、48 列與 `links` 那一列通過，和預期相同。
  - 與這一項寫的預期不同的一處：第 43 列在 `7ad9152` 的 script 上也通過。外層搜尋失敗、標記哪裡都沒有時，改之前的程式同樣回 `error`、只點名外層，所以這一列固定的是答案不變；分辨得出第二輪第 2 列的是第 42 列。預期是工作單寫錯，不是實作的問題。

## 2. 實作與說明

- [x] 2.1 [after: 1.1] 依 design「頂層目錄的讀法放在 repo_top()」「以 rev-list 的 --missing=print 決定讀不讀得完」「搜尋失敗之後仍然列 gitlink」「git 比 2.45 舊時不在 submodule 目錄跑 git」「改的是 requirement 的句子，不是把程式改回去」改 `plugins/issue-driven-dev/scripts/spec-change.py` 的 `repo_top()`、`marker_files()`、`cmd_links()`。驗證：1.1 的檢查全部通過；`tests/spec-change/test.sh` 既有的檢查全部通過、檢查數不減、沒有任何既有檢查被改寬；`python3 -m py_compile plugins/issue-driven-dev/scripts/spec-change.py` 通過。
- [x] 2.2 [after: 2.1] 說明文件：`spec-change.py` 檔頭的 `links` 段寫明搜尋 submodule 需要 git 2.45 或更新的版本；`plugins/issue-driven-dev/references/spec-wrapper.md` 在講 submodule 的地方補上最低的 git 版本，以及取出 submodule 會連到那條分支的 `.gitmodules` 指定的位址、所以只在信任它時執行；`plugins/issue-driven-dev/CHANGELOG.md` 的 #548 條目改寫成最後的行為。驗證：`git diff` 對 CHANGELOG 只動 #548 那一條；文字不含任何特定專案的名稱或本機路徑。

## 3. 收尾

- [x] 3.1 [after: 2.2] 跑整套測試：`bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 與 `bash .claude/scripts/tests/spectra-archive-post-ic/test.sh`。驗證：結束碼都是 0；實作者的沙箱寫不進某個 suite 需要的位置時，由協調者在沙箱外重跑整套並記錄。
  - 驗收紀錄（協調者，在最後的檔案上、封存之前的工作樹執行）：`bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 74 個 suite、0 個失敗；`bash .claude/scripts/tests/spectra-archive-post-ic/test.sh` 141 項通過。
- [x] 3.2 [after: 3.1] 協調者驗收（在實作者寫不到的目錄）：逐行讀改動；在一份只套用新測試檔、script 維持 `7ad9152` 的複本上重跑 1.1，確認哪些列失敗；重跑 `tests/spec-change/test.sh` 與整套測試；用舊測試檔配新 script 確認既有檢查沒有少；對沒有 gitlink 的 repo 與有 gitlink 而標記都在主 repo 的 repo，比對新 script 與 `6ed8dec` 的 script 輸出逐位元組相同；重放第二輪的三個重現；執行 design「把性質改壞的變異也要有檢查擋住」列的變異與第二個 change 的二十二種，記下每一種有沒有檢查失敗。驗證：驗收紀錄寫在這一項底下，每個結果附指令。
  - 驗收紀錄。以下每一項都在最後的檔案上重跑過（4.1 的補強之後）。
  - 新測試檔配新 script：`bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` → 745 項通過、0 項失敗。配 `7ad9152` 的 script：見 1.1 底下。
  - 舊測試檔配新 script（同一個指令，測試檔取自各 commit）：`7ad9152` 的 648 項、`afd0021` 的 497 項、`6ed8dec` 的 431 項都通過，既有的檢查沒有少。
  - 輸出不變的兩種 repo，`python3 plugins/issue-driven-dev/scripts/spec-change.py links --base <base> --head <head> --cwd <repo>` 的輸出與結束碼，新 script 與 `6ed8dec` 的 script 逐位元組相同：沒有 gitlink 的 repo（這個 repo 自己的三段歷史 `401cd33..6ed8dec`、`2dc56ab..6ed8dec`、`fdf8d0d..4921b71`）；有 gitlink 而標記都在主 repo 的臨時 repo。
  - 第二輪的三個重現，在臨時 repo 上：submodule 完整、哪裡都沒有標記，設 `GIT_TRACE=1` 與不設都回 `missing`，兩次是同一行；外層 submodule 少一個無關的檔案內容、標記在完整的巢狀 submodule 裡，回 `ok`；頂層目錄名稱以空白結尾的 repo 回 `ok`（`6ed8dec` 的 script 回 `error`）。第一輪的兩個重現仍然成立：路徑不是合法 UTF-8 的 gitlink、標記在主 repo → `ok`；形狀像 git 目錄的資料夾 → `error`、原因是 not checked out。
  - 變異測試：每一種各改 script 一處，在複本上跑 `tests/spec-change/test.sh`，共 34 種。拿掉防護的 21 種是第二個 change 的 22 種重新對位（原來的「不看 submodule 搜尋的錯誤輸出」那一種已經沒有對應的程式）；把性質改壞的 13 種是 design 列的那些，加上 4.1 補的。32 種各有檢查失敗。
  - 沒有檢查失敗的兩種，是 design 記為明文例外的那兩種：留著 `GIT_INDEX_FILE`；submodule 的 tree 列不出來時不另外記原因。兩種都沒有輸入能分辨。
  - 第一次執行變異測試時（33 種）另有三種沒有檢查失敗：submodule 的搜尋以其他結束碼結束時不算失敗、讀不出的版號當成夠新、主 repo 搜尋失敗時原因不帶 git 的訊息。4.1 為它們補了檢查。
  - 逐行讀改動時改回一處：實作者把主 repo 搜尋失敗的原因縮成固定文字，協調者改回這條分支之前的寫法（那一行與 `7ad9152` 相同）。

## 4. 封存前的補強（驗收之後）

- [x] 4.1 [after: 3.2] 驗收的變異測試有三種沒有檢查擋住，各補一個檢查與一列 Example：requirement「Added and modified requirements carry an executable check」的 Example「markers in submodules」第 49 列（物件在、但已損壞的 submodule）與第 47 列的第二種情況（讀不出的 git 版號），以及「what the link check reports」的一列（主 repo 的 tree 讀不到時，原因是 `git grep failed: ` 加上 git 錯誤輸出的前 200 個字元）。同一項裡把主 repo 搜尋失敗時的原因改回這條分支之前的文字（實作者依工作單的一句話把 git 的訊息拿掉了，那一句寫得不清楚），並把 requirement 裡兩句關於 git 錯誤輸出的話限定在 submodule（主 repo 的原因本來就帶 git 的訊息）。驗證：三種變異、加上「主 repo 的原因不截到 200 個字元」這一種，各自有檢查失敗；`bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 全部通過。
  - 驗收紀錄。補的三處由協調者撰寫，沒有獨立讀者看過；第三輪 verify 會讀到。
  - 量測（臨時 repo，git 2.55.0）：把一個檔案內容的物件換成讀不出來的資料之後，`git rev-list --objects --no-walk --missing=print` 回 0、沒有 `?` 開頭的行，`git grep` 回 128。所以這種情況只有搜尋的結束碼看得出來，第 49 列固定它。主 repo 裡刪掉規格目錄以外的一個 tree 物件之後，列規格檔的 `git ls-tree` 仍然成功，`git grep` 回 128、訊息是 `fatal: unable to read tree (...)`。
  - 三處裡，只有「讀不出的版號」在 `7ad9152` 的 script 上會失敗（那時沒有版本檢查）。第 49 列與主 repo 那一列在 `7ad9152` 上也通過：它們固定的是原本就對的行為，擋的是變異。
  - 封存前重讀 delta 時發現兩句話寫得比行為寬，已經限定在 submodule：「git 的錯誤輸出不改變答案」與「原因不帶 git 錯誤輸出的文字」。主 repo 搜尋失敗時的原因從這條分支之前就帶 git 的訊息，實測設了 `GIT_TRACE=1` 時那個原因的文字會跟著變。主 repo 那一列因此寫成實際的行為（`git grep failed: ` 加上 git 錯誤輸出的前 200 個字元），檢查改成與 git 寫出的訊息逐字比對，另加一項確認較長的訊息截到 200 個字元。
  - 補完之後重跑的結果記在 3.1 與 3.2 底下。
