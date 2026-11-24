## 1. 測試（先寫）

- [x] 1.1 requirement「Change metadata carries no author address」的 Example「lines of change metadata before and after」：在 plugins/issue-driven-dev/scripts/tests/spec-change/test.sh 逐列檢查，標記 `spec-example: spec-on-every-issue / lines of change metadata before and after`。每列比對 `spec-change.py scrub-authors` 之後的檔案位元組與 `cleaned` 清單。驗證：2.1 之前這些列失敗，之後通過。
- [x] 1.2 同一個 requirement 的 Example「which files scrub-authors reads」：同一個檔裡逐列檢查，標記 `spec-example: spec-on-every-issue / which files scrub-authors reads`。驗證：2.1 之前這些列失敗，之後通過。
- [x] 1.3 同一個 requirement 的 Example「the wrapper's two calls」：同一個檔裡讀 references/spec-wrapper.md 的兩節，標記 `spec-example: spec-on-every-issue / the wrapper's two calls`。驗證：2.2 之前失敗，之後通過。

- [x] 1.4 requirement 同上，Example「the close-out order restated by idd-implement and idd-all」：同一個檔裡讀 idd-implement 與 idd-all 的 SKILL.md，標記 `spec-example: spec-on-every-issue / the close-out order restated by idd-implement and idd-all`。另在 1.2 的表加兩列：已 stage 的檔、遇到非 UTF-8 時一個檔都不改；1.3 加檢查 `go on with` 那一列。spectra-verify 之後補上（WARNING 1、2 與建議 1、2、3、4）。驗證：2.3 之前這些列失敗（6 項），之後通過。

## 2. 實作

- [x] 2.1 plugins/issue-driven-dev/scripts/spec-change.py 的 `cmd_scrub_authors`，註冊為 `scrub-authors`：
  - 從工作樹解析 repo 頂層與規格目錄；
  - 用 git 列出 `<spec dir>/changes/` 底下未追蹤或已修改的 `.openspec.yaml`；
  - 只改行尾是 `<…@…>` 的 `created_by` 與 `archived_by` 行；
  - 印一行 JSON。
  驗證：1.1 與 1.2 通過。
- [x] 2.2 plugins/issue-driven-dev/references/spec-wrapper.md：
  - 第 3 步在 change 建立之後、任何 commit 之前跑這個子命令；
  - 第 5 步在 `spectra archive` 與封存 commit 之間跑；
  - 兩處都印出拿掉了哪些檔，不是 `ok` 就停下；
  - 第 4、5 步不新增 bash 區塊，因為那兩步的區塊會被其他 suite 照原文執行。
  驗證：1.3 通過，spec-wrapper-contract 與 spec-archive-local 兩個 suite 通過。

- [x] 2.3 照 spectra-verify 的回報：
  - `cmd_scrub_authors` 先讀完、檢查完所有檔才寫，error 不帶 `cleaned`；已 stage 的檔改完再 stage 一次。
  - spec-wrapper.md 第 3 步表格的 `go on with` 列與那段的條件都涵蓋沿用開著的 change。
  - idd-implement 兩處、idd-all 一處重述的收尾序列加上 scrub-authors；idd-all Step 3b.3 在 propose 之後跑它。
  驗證：1.4 與新增的列通過。

- [x] 2.4 照第二次 spectra-verify：
  - 讀檔與寫檔的 OSError 都回 JSON error，寫檔出錯時列出已改的檔；重新 stage 失敗時訊息出得來。
  - wrapper、idd-implement 另兩處 propose 與 idd-all 修正輪都寫明跑 scrub-authors。
  - proposal 的 Success Criteria 與 Impact 對上。
  驗證：1.2 的表新增「讀不到的檔」一列並通過。

- [x] 2.5 照 IC 前的跨模型審查（OpenAI，兩席）：
  - 工作樹與 HEAD 相同就不改。
  - 合併衝突中的檔、讀不到的子目錄都回 error，而且在任何改寫之前回。
  - 只在 CR、LF、CRLF 切行，保留 BOM。
  - 改寫時換成新檔，hard link 指向的舊檔不變。
  - requirement 寫明 ignored 檔與 symlink 不讀。
  驗證：1.1 與 1.2 的表新增的列通過，wrapper 順序檢查改成比對編號項目。

- [x] 2.6 照第 2 輪外部審查：
  - 沒有 `changes/` 或那裡是 symlink 就沒有東西可掃，不是錯誤。
  - 先比 HEAD 再解碼；HEAD 有這個路徑卻讀不到是錯誤。
  - 重新 stage 之後讀回暫存區那份，還有地址就是錯誤。
  - requirement 寫明讀的範圍是 `git status` 回報的檔、行的形狀、場景標題。
  驗證：1.2 的表新增三列並通過；hard link 那列也比對 `h` 的內容；BOM 那列補上 `created_with`。

- [x] 2.7 照第 3 輪外部審查：在讀 `git status` 之前先檢查 `changes/`，沒有或是 symlink 就直接回 `ok`；路徑中間有 symlink 目錄的檔不讀；暫存區那份讀不到、不是 UTF-8、還有地址分別報錯。驗證：1.2 的表新增 symlink 那一列並通過。

- [x] 2.8 照第 4 輪窄驗：名稱以兩個點開頭的目錄（`..draft`）照常讀；路徑上的目錄讀不到（找不到以外的錯誤）是錯誤，不是略過。驗證：1.2 的表新增 `..draft` 一列並通過。

## 3. 全部測試

- [x] 3.1 spec-change、spec-wrapper-contract、spec-archive-local 三個 suite 與 run-all-tests.sh 都通過。
