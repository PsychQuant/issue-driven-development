## 1. 測試先行

- [x] 1.1 submodule 裡的標記有可執行的檢查：依 requirement「Added and modified requirements carry an executable check」的 Example「markers in submodules」，在 `plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 為十列各加一個檢查，測試檔帶標記 spec-example: spec-on-every-issue / markers in submodules；fixture 用本機路徑建立 submodule（`-c protocol.file.allow=always`），capability、路徑與檔名用通用字樣；沒取出的情況用 `git submodule deinit -f`，缺 commit 的情況用 `git update-index --cacheinfo` 記一個不存在的 commit。驗證：改 `spec-change.py` 之前執行，第 1、2、3、4、8、10 列的檢查失敗，第 5、6、7、9 列通過；實作者列出每一列的結果。

## 2. 實作與說明

- [x] 2.1 [after: 1.1] 依 design「links 自己列出 gitlink 並逐一搜尋」「找不到而且有地方沒看過時回 error」「排除規則套用在接上 submodule 路徑之後的名稱」「gitlink 的清單與可搜尋性在一次執行內只算一次」「在 submodule 目錄裡只跑唯讀的 git 指令」改 `plugins/issue-driven-dev/scripts/spec-change.py` 的 `marker_files()` 與 `cmd_links()`。驗證：1.1 的十個檢查全部通過；`tests/spec-change/test.sh` 既有的檢查全部通過、檢查數不減；`python3 -m py_compile plugins/issue-driven-dev/scripts/spec-change.py` 通過。
- [x] 2.2 [after: 2.1] 說明文件：`spec-change.py` 檔頭的 `links` 段寫明 submodule 的讀法與 `error` 的情況；`plugins/issue-driven-dev/references/spec-wrapper.md` 在講標記的地方加一句（標記可以在 submodule 的已追蹤檔案裡，讀主 repo 記錄的 commit；檢查時 submodule 要已經取出，否則找不到標記的 Example 會讓檢查回 `error`）；`plugins/issue-driven-dev/CHANGELOG.md` 的 Unreleased 加一條（#548）。驗證：`git diff` 對 CHANGELOG 只有新增行；文字不含任何特定專案的名稱或本機路徑。

## 3. 收尾

- [x] 3.1 [after: 2.2] 跑整套測試：`bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 與 `bash .claude/scripts/tests/spectra-archive-post-ic/test.sh`。驗證：結束碼都是 0；有 suite 因為機器負載逾時的話，單獨重跑那個 suite 並記錄。
- [x] 3.2 [after: 3.1] 協調者驗收（在實作者寫不到的目錄）：逐行讀改動；在一份只套用測試的複本上重跑 1.1，確認六個失敗、四個通過；重跑 `tests/spec-change/test.sh` 與整套測試；對一個沒有 gitlink 的 repo 比對改動前後 `links` 的輸出相同。驗證：驗收紀錄寫在這一項底下，每個結果附指令。

  驗收紀錄（2026-11-14；1.1 到 3.1 由實作者模型 Codex gpt-6-astra 依工作單完成，3.2 由協調者 Claude Fable 5.2 在實作者寫不到的目錄執行。沒有獨立讀者審過，交給下一步的 verify）：

  - 逐行讀過 `spec-change.py`、`tests/spec-change/test.sh`、`references/spec-wrapper.md`、`CHANGELOG.md` 的改動。
  - 只套用新測試檔、script 維持 `6ed8dec` 的複本，跑 `bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh`：454 通過、20 失敗。失敗的是第 1、2、3、4、8、10 列的檢查（每列 status、回報筆數、結束碼三項，第 8、10 列另有原因文字一項）；第 5、6、7、9 列與既有的檢查全部通過。
  - 工作樹的複本跑同一個指令：474 通過、0 失敗。舊測試檔配新 script：431 通過、0 失敗，既有的檢查沒有少。
  - 沒有 gitlink 的 repo：對這個 repo 自己的三段歷史（`401cd33..6ed8dec`、`2dc56ab..6ed8dec`、`fdf8d0d..4921b71`）跑改動前後的 `links`，輸出與結束碼逐位元組相同。
  - `python3 -m py_compile plugins/issue-driven-dev/scripts/spec-change.py` 通過。
  - 整套測試在沙箱外重跑：`bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 74 個 suite、0 個失敗，結束碼 0；`bash .claude/scripts/tests/spectra-archive-post-ic/test.sh` 141 通過、0 失敗。實作者在沙箱裡跑的那一次有三個 suite（correct-flow、edit-run、in-place-correction）因為寫不進 `/var/tmp` 而失敗，與這次改動無關，沙箱外都通過。
  - 在一個有五個 submodule 的 repo 上，新的 `links` 跑完整段範圍約 2.6 秒。
  - 對 `<head>` 記錄的 commit 搜尋，不論物件來自哪個目錄，內容都由 commit 的雜湊決定；所以 submodule 目錄是否在工作樹內不影響找到的標記是否屬於記錄的那一版。沒有另外加路徑檢查。

## 4. 封存前的補強（spectra-verify 之後）

- [x] 4.1 依 `spectra-verify` 的一項 warning 與四項建議補強：Example「markers in submodules」加第 11 到 15 列與對應的檢查（`submodule.recurse` 開啟時，主 repo 有標記仍為 `ok`、缺 commit 仍點名 Example 與路徑；兩個 submodule 都沒取出時兩個路徑以分號相連；巢狀 submodule 沒取出時點名內層的路徑；掛在規格目錄底下的 submodule 裡的標記不算）；依 design「git 自己的遞迴一律關掉」在 `git grep` 加 `--no-recurse-submodules`；fixture 步驟失敗時先印一行再結束。驗證：加旗標之前第 11、12 列的三項檢查失敗、其餘通過；加旗標之後 `bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 全部通過。

  紀錄（2026-11-14；這一項是協調者自己寫的改動，沒有經過實作者模型，交給下一步的 verify）：

  - 實測 git 2.55.0：`submodule.recurse=true` 時，`git grep <tree>` 會自己搜尋 submodule，記錄的 commit 不在物件庫時以 128 結束；加上 `--no-recurse-submodules` 後回到不遞迴的行為。
  - 新測試在加旗標之前：494 通過、3 失敗（第 11 列的 status 與結束碼、第 12 列的原因文字）。加旗標之後：497 通過、0 失敗。
  - 第 13、14、15 列在加旗標之前就通過：它們檢查的是規格已經寫明、先前沒有測試的三件事。
  - Example 表現在是十五列；1.1 寫的「十列」是補強之前的數字。
