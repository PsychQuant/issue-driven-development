## 1. 測試先行

- [x] 1.1 第三輪找到的行為各有可執行的檢查：在 `plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 為 requirement「Added and modified requirements carry an executable check」的 Example「markers in submodules」第 50 到 54 列、「what the link check reports」新增的一列（`specs/` 以外的非 UTF-8 路徑）與主 repo 搜尋失敗的那一列（前 200 個字元）各加或改檢查；為 requirement「The repository's top directory is read as git prints it」的 Example「top directory names」名稱以換行結尾的三列各加檢查。列的文字與檢查的範圍依 design「句子與測試各自收窄到做得到的範圍」。同一項裡，依 design「測試檔自己的環境」：開頭確認 git 版本、清掉繼承的 git 環境變數、`setup_failed` 在命令替換裡也讓整個測試停下。驗證：改 `spec-change.py` 之前執行整個檔案，第 50、51、52 列各至少一項檢查失敗；第 53、54 列、非 UTF-8 那一列、前 200 個字元、名稱以換行結尾的三列通過（它們固定現在的行為）；既有的檢查全部通過。
  - 驗收紀錄（在一份只換測試檔、script 維持 `726050b` 的複本上執行 `bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh`）：786 項通過、13 項失敗。失敗的是第 50 列（4 項）、第 51 列（3 項）、第 52 列（6 項）。第 52 列在舊 script 上的答案每次執行不一定相同（那正是它要抓的缺陷），所以失敗的項數會變：改 script 之前的另一次執行是 9 項、總數 16 項。第 53、54 列、`specs/` 以外的非 UTF-8 路徑、前 200 個字元、名稱以換行結尾的三列都通過，與預期相同。

## 2. 實作與說明

- [x] 2.1 [after: 1.1] 依 design「用 cat-file --batch-check 確認物件打得開」與「搜尋中途中止時不採用它印出的內容」改 `plugins/issue-driven-dev/scripts/spec-change.py`：`submodule_git()` 加 `stdin` 參數、新增 `submodule_lacks_objects()`、`marker_files()` 改用它並在搜尋中止時不讀輸出。驗證：1.1 的檢查全部通過；既有的檢查全部通過、沒有任何既有檢查被改寬；`python3 -m py_compile plugins/issue-driven-dev/scripts/spec-change.py` 通過。
- [x] 2.2 [after: 2.1] 說明文件：`spec-change.py` 檔頭的 `links` 段、`plugins/issue-driven-dev/references/spec-wrapper.md` 的提醒（加上 submodule 記錄的 commit 裡的 `.gitmodules`，以及內容會被取出到工作樹）、`plugins/issue-driven-dev/CHANGELOG.md` 的 #548 條目。驗證：`git diff` 對 CHANGELOG 只動 #548 那一條；文字不含任何特定專案的名稱或本機路徑。

## 3. 收尾

- [x] 3.1 [after: 2.2] 跑整套測試：`bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 與 `bash .claude/scripts/tests/spectra-archive-post-ic/test.sh`。驗證：結束碼都是 0。
  - 驗收紀錄（在最後的檔案上、封存之前的工作樹執行）：`bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 74 個 suite、0 個失敗；`bash .claude/scripts/tests/spectra-archive-post-ic/test.sh` 141 項通過。這次執行之後，測試檔只再改了第 49 列上方的三行註解（它說的「沒有缺任何物件」已經不對）；改完後單獨重跑 `tests/spec-change/test.sh`，799 項通過。
- [x] 3.2 [after: 3.1] 驗收：在一份只套用新測試檔、script 維持 `726050b` 的複本上重跑 1.1，確認哪些列失敗；舊測試檔（`726050b`、`7ad9152`、`afd0021`、`6ed8dec`）配新 script；沒有 gitlink 的 repo 與標記都在主 repo 的 repo 對照 `6ed8dec` 的 script 逐位元組比對；重放第三輪第 1、3 列的重現；執行上一個 change 的 34 種變異與 design「每一處改動各有一種變異」列的五種；單獨確認 `setup_failed` 在命令替換裡會讓主 shell 停下（bash 5 與 bash 3.2）。驗證：驗收紀錄寫在這一項底下，變異逐項列出有沒有檢查失敗。
  - 驗收紀錄。這個 change 的測試、程式與文件都由同一個協調者撰寫，沒有實作者模型，也沒有獨立讀者；第四輪 verify 是第一次獨立審查。
  - 新測試檔配新 script：799 項通過、0 項失敗。配 `726050b` 的 script：見 1.1 底下。
  - 舊測試檔配新 script：`726050b` 的 745 項、`7ad9152` 的 648 項、`afd0021` 的 497 項、`6ed8dec` 的 431 項都通過。
  - 輸出不變的兩種 repo，`python3 plugins/issue-driven-dev/scripts/spec-change.py links --base <base> --head <head> --cwd <repo>` 的輸出與結束碼，新 script 與 `6ed8dec` 的 script 逐位元組相同：這個 repo 自己的三段歷史（`401cd33..6ed8dec`、`2dc56ab..6ed8dec`、`fdf8d0d..4921b71`）；有 gitlink 而標記都在主 repo 的臨時 repo。
  - 第三輪的重現，在臨時 repo 上：帶標記的檔案的物件檔是空的，新 script 回 `error`（`726050b` 的 script 回 `missing`）；哪裡都沒有標記、一個無關檔案的物件檔是空的，新 script 回 `error`（`726050b` 回 `missing`）；兩千個檔案的 submodule 裡一個檔案內容損壞、標記在同一個 submodule，新 script 30 次都回 `error`（`726050b` 的 script 10 次裡 9 次 `error`、1 次 `ok`）。第一輪與第二輪的重現仍然成立。
  - `setup_failed` 在命令替換裡：一支只含這個函式、`commit` 失敗、`X=$(commit)` 之後印一行字的腳本，在 bash 5.3 與 bash 3.2 都以結束碼 1 結束，沒有印出那一行。
  - 變異測試：每一種各改 script 一處，在複本上跑 `tests/spec-change/test.sh`，共 41 種（上一個 change 的 34 種，加上這次的 7 種：P14 到 P20）。39 種各有檢查失敗；沒有的兩種（G20、P09）是上一個 change 記為明文例外的那兩種。P04 與 P08 的改法照新的程式重新對位；P04 第一次沒有套用成功，對位後單獨重跑。逐項結果（括號裡是失敗的檢查所屬的列）：
  - G01 keep walking after a marker is found in the main repository：3 項檢查失敗（row 22; row 48）
  - G02 no .git entry required：1 項檢查失敗（row 21）
  - G03 no safe.bareRepository：1 項檢查失敗（row 31）
  - G04 lazy fetch left on：1 項檢查失敗（row 33）
  - G05 no containment checks：10 項檢查失敗（row 23）
  - G06 strip() on the top that git reports for a submodule：2 項檢查失敗（row 25）
  - G07 inherited GIT_* variables kept：7 項檢查失敗（row 28; row 40; row 41）
  - G09 gitlinks under the spec directory not skipped：3 項檢查失敗（row 26）
  - G10 strict UTF-8 for gitlink paths：1 項檢查失敗（row 17）
  - G11 every unsearchable submodule listed：3 項檢查失敗（row 29）
  - G12 long paths not cut：2 項檢查失敗（row 34）
  - G13 only the symbolic-link test removed：3 項檢查失敗（row 27）
  - G14 git's refusal reported as not checked out：2 項檢查失敗（row 30; row 31）
  - G15 unsearchable submodules not sorted：1 項檢查失敗（row 38）
  - G16 a '.' component accepted：1 項檢查失敗（row 39）
  - G17 GIT_WORK_TREE kept：2 項檢查失敗（row 40）
  - G18 GIT_OBJECT_DIRECTORY kept：2 項檢查失敗（row 40）
  - G19 GIT_COMMON_DIR kept：2 項檢查失敗（row 40）
  - G20 GIT_INDEX_FILE kept (reading a commit does not use the index: no input can show it)：沒有檢查失敗
  - G21 GIT_ALTERNATE_OBJECT_DIRECTORIES kept：3 項檢查失敗（row 41）
  - G22 the top that git names for a submodule is not compared：4 項檢查失敗（row 37）
  - P01 a found marker does not settle the Example when a submodule could not be searched：4 項檢查失敗（row 42; row 44）
  - P02 a file found in a submodule that lacks objects does not count：2 項檢查失敗（row 45）
  - P03 the submodules inside an unreadable submodule are skipped：2 項檢查失敗（row 42）
  - P04 output on git's error stream counts as unreadable again：5 項檢查失敗（row 46）
  - P05 the git version is not checked：8 項檢查失敗（row 47）
  - P06 repo_top strips white space again：18 項檢查失敗（top directory names: links trailing space; top directory names: links; top directory names: archived trailing space）
  - P07 the object store is not asked which objects it lacks：16 項檢查失敗（row 20; row 36）
  - P08 a search of a submodule that exits with another code is not a failure：10 項檢查失敗（row 52）
  - P09 a tree of a submodule that cannot be listed is not reported：沒有檢查失敗
  - P10 the reason for a non-UTF-8 path under the spec directory is the exception text：1 項檢查失敗（invalid-UTF-8 spec path）
  - P11 a version that cannot be read counts as new enough：4 項檢查失敗（row 47）
  - P12 the main repository's failed search loses git's message：2 項檢查失敗（unreadable main tree）
  - P13 the main repository's failed search reports git's whole message, not its first 200 characters：1 項檢查失敗（unreadable main tree）
  - P14 an object that is present but cannot be opened does not count as lacking (no --batch-check)：4 項檢查失敗（row 50）
  - P15 the output of rev-list is split at carriage returns too：3 項檢查失敗（row 51）
  - P16 whole records, not object ids, are given to --batch-check：23 項檢查失敗（row 5; row 6）
  - P17 what a search printed before it ended early is used：9 項檢查失敗（row 52）
  - P18 the main repository's failed search keeps the last 200 characters：1 項檢查失敗（unreadable main tree）
  - P19 repo_top removes every trailing line feed：9 項檢查失敗（top directory names: links trailing line feed; top directory names: links, line feed; top directory names: archived trailing line feed）
  - P20 the exit code of the search alone does not make a submodule one that could not be searched：4 項檢查失敗（row 54）
  - 已知的限制：第 52 列靠的是舊行為有時回 `ok`，所以對應的變異（P08、P17）是以機率被擋下的；兩個檔案的 submodule 上，舊行為單次回 `ok` 的比例在第三輪審查者的量測是 40 次裡 39 次；協調者自己在 `726050b` 的 script 上跑了兩次這個測試檔，第 52 列的六次執行裡五次回 `ok`。三次執行都剛好回 `error`、讓變異漏網的機會因此很小，但不是零。整個測試只在 macOS 上跑過（git 2.55.0）。名稱不是合法 UTF-8 的頂層目錄沒有測試。
