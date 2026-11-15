## 1. 測試先行：參數與判定表

- [x] 1.1 [P] 參數形式：依 requirement「Rest mode is selected by a closed list of argument forms」的 Example「argument forms」，新 suite rest-queue 對 `rest-queue.py args` 跑表上十六列，另對小世界（位置參數取自 rest、#12、一段文字，最多兩個；旗標的所有子集，外加一個不認得的旗標）窮舉檢查 Unknown flags are refused 與「rest 只在沒有其他位置參數時成立」，帶標記 spec-example: idd-all-rest / argument forms。驗證：實作前這組檢查失敗。
- [x] 1.2 [P] 判定表：依 requirement「Every open issue falls into exactly one class」的 Example「class precedence」，rest-queue suite 對純函式 classify 跑表上各列（7.1 之後是十二列），並對所有輸入組合（7.1 之後是 512 種）窮舉檢查「恰好一類」與表的先後順序（Decision table is data, checked exhaustively），帶標記 spec-example: idd-all-rest / class precedence。驗證：實作前失敗。

## 2. 測試先行：讀取、排序、釐清問題

- [x] 2.1 fake gh：rest-queue suite 的 fake-gh.py 依情境目錄回答 GraphQL 分頁、單一 issue 的 REST comments、collaborator permission 與 issue 狀態，並記錄每一次呼叫。驗證：suite 內一個自我檢查對 fake 問兩頁 issue，拿到兩頁。
- [x] 2.2 排序：依 requirement「Candidates run diagnosed first and then by issue number」的 Example「four candidates in run order」，`rest-queue.py list --json` 的 order 是 12、20、3、9，帶標記 spec-example: idd-all-rest / four candidates in run order。驗證：實作前失敗。
- [x] 2.3 讀取失敗：依 requirement「The open issues are read completely or not at all」的 Example「second page fails」，第二頁回結束碼 1 時 list 的結束碼不是 0、stdout 是空的，帶標記 spec-example: idd-all-rest / second page fails。驗證：實作前失敗。
- [x] 2.4 comment 超過 100 則：依同一條 requirement 的 Example「Diagnosis older than the last 100 comments」，130 則 comment、Diagnosis 在第 5 則的 issue 被判成 actionable，而且 fake gh 的呼叫紀錄有那一張的 REST comments 讀取，帶標記 spec-example: idd-all-rest / Diagnosis older than the last 100 comments。驗證：實作前失敗。
- [x] 2.5 [P] 釐清問題：依 requirement「All open clarity rows are available from one implementation」的 Example「two open rows and one resolved row」，對 GitHub 渲染的 fixture 呼叫 open_clarity_rows 得到兩筆、open_clarity_row 等於第一筆，帶標記 spec-example: idd-all-rest / two open rows and one resolved row。驗證：實作前失敗（函式不存在）。

## 3. 測試先行：run 的狀態

- [x] 3.1 途中新開的 issue：依 requirement「Each issue is attempted at most once per run」的 Example「a spawned issue is picked up」，next 依序回 5、9、12、done，帶標記 spec-example: idd-all-rest / a spawned issue is picked up。驗證：實作前失敗。
- [x] 3.2 in flight：依同一條 requirement 的 Example「the in-flight issue is repeated」，沒有 record 時第二次 next 回同一張且 in_flight 為 true，狀態檔只有一筆 attempt，帶標記 spec-example: idd-all-rest / the in-flight issue is repeated。驗證：實作前失敗。
- [x] 3.3 結果由 GitHub 決定：依 requirement「The outcome of an issue is read from GitHub」的 Example「outcomes by issue state」跑三列，另檢查對不是 in flight 的 issue 號 record 結束碼 1、狀態檔不變，帶標記 spec-example: idd-all-rest / outcomes by issue state。驗證：實作前失敗。
- [x] 3.4 整個 run 停下：依 requirement「A stopped issue does not stop the run and a stopped run hands out nothing」的 Example「stop ends the run」，stop 之後 next 回 stopped 與原因、不交出 #9；另檢查單張 stopped 之後 next 照常交出下一張，帶標記 spec-example: idd-all-rest / stop ends the run。驗證：實作前失敗。
- [x] 3.5 接續：依 requirement「Start prints the list and resumes an unfinished run」的 Example「resume within 24 hours」，2 小時前的狀態被接續、next 回 9，start 的輸出只有 issue 號、沒有任何標題文字，帶標記 spec-example: idd-all-rest / resume within 24 hours。驗證：實作前失敗。
- [x] 3.6 過期的狀態：依同一條 requirement 的 Example「a state older than 24 hours starts a new run」，25 小時前的狀態不被接續、next 回 5，帶標記 spec-example: idd-all-rest / a state older than 24 hours starts a new run。驗證：實作前失敗。
- [x] 3.7 總報告：依 requirement「Report lists what happened and ends the run」的 Example「report with one closed, one stopped and one waiting issue」，輸出有 #5、#9 與它的原因、#14 的兩個問題，狀態檔被刪除，之後 next 結束碼 1；另檢查清單重讀失敗時仍印出已記錄的結果並刪除狀態檔，帶標記 spec-example: idd-all-rest / report with one closed, one stopped and one waiting issue。驗證：實作前失敗。

## 4. 程式

- [x] 4.1 `rest-queue.py` 的 args 子命令與 classify 純函式，判定表是有順序的資料（One helper owns selection and run state）。驗證：1.1、1.2 通過。
- [x] 4.2 `intent.py` 加 open_clarity_rows，open_clarity_row 改成取第一筆（Judgement is reused, not copied）。驗證：2.5 通過；close-stage suite 照舊通過。
- [x] 4.3 `rest-queue.py` 的 list 子命令：一次分頁的 GraphQL 讀取、comment 超過 100 則時讀完整、經暫存檔呼叫 actionability.sh、can_write、從渲染後的正文讀 Phase、排序；任何一步失敗就整個失敗（Fail closed on an incomplete read、Candidate order ignores Conflict Class）。驗證：2.2、2.3、2.4 通過。
- [x] 4.4 `rest-queue.py` 的 start、next、record、stop、report 與狀態檔：交出時就記錄、24 小時內接續、record 自己讀 issue 狀態、清單只印號碼（Attempt-once is recorded when an issue is handed out、record reads the outcome from GitHub、Listings print issue numbers, not titles）。驗證：3.1 到 3.7 通過。

## 5. skill 與文件

- [x] 5.1 skill 的文字檢查：依 requirement「idd-all runs rest mode as a loop over the single-issue pipeline」的 Example「the skill names the loop commands in order」，rest-queue suite 檢查 `skills/idd-all/SKILL.md` 的 Step 0.1 有 args 的呼叫與參數表的 rest 兩列，rest 一節依序有 start、next、record、stop、report 的呼叫，整個 run 的停止條件列的是三種加使用者中斷，帶標記 spec-example: idd-all-rest / the skill names the loop commands in order。驗證：改 SKILL.md 之前失敗。
- [x] 5.2 `skills/idd-all/SKILL.md`：Step 0.1 先跑 args 並依 mode 分流、參數表拿掉提問那一列並加上 rest 的列、Step 0.4 拿掉 interactive、新增 rest 一節（流程、整個 run 的停止條件、總報告由 report 印出）、範例加一段 rest、frontmatter 的 description 提到不帶參數的行為、權限一節說明 rest 的每一張各自過 close stage 的閘門。驗證：5.1 通過；skill-description-contract、merge-and-close-contract、spec-wrapper-contract、actionability-gate 這四個讀 SKILL.md 的 suite 照舊通過。
- [x] 5.3 [P] `references/parallel-orchestration.md` 與 `references/batch-and-cluster.md`：寫明 rest 是批次模式之外的另一種選法、同樣依序；後者把 idd-all 從沒有批次的那一欄移到有批次的一欄，selector 那一句改成「明列的 #N，或 idd-all 的 rest」。驗證：兩個檔不再有「idd-all 沒有批次」與「selector 只能是明列的 #N」這兩句；docs-catalog-sync 與 doc-sync-sweep suite 照舊通過。
- [x] 5.4 [P] plugin 的 README 與 MANIFESTO：README 的 idd-all 用法加上不帶參數與 rest；MANIFESTO 提到 #37 的那一段補上 #478 把不帶參數的入口做成 rest。驗證：兩個檔都提到 rest 與 #478；讀這兩個檔的既有 suite 照舊通過。
- [x] 5.5 CHANGELOG 的 Unreleased 加一條 Added 與一條 BREAKING 說明（#478）。驗證：已發布版本的條目沒有改動；版本號沒有改動。

## 6. 收尾

- [x] 6.1 對真實的 repo 唯讀跑一次 `rest-queue.py list --repo PsychQuant/issue-driven-development --json`，確認每一張 open issue 都被分類、各類張數與 Diagnosis 記的同一個量級（候選約 166、等人約 18、blocked 4、verified 4）。驗證：把實際數字寫進 Implementation Complete。
- [x] 6.2 跑 run-all-tests.sh 與連結檢查。驗證：結束碼都是 0，links 回 ok。

## 7. verify 之前的補強

- [x] 7.1 判定表第 1 類加上留言者：任何一則 comment 的作者沒有寫入權（bot 不算）就歸 outsider，類別由 author 改名；comment 超過查詢回傳的數量時讀完整再判。驗證：tables_check.py 的 512 種組合與 rest-queue suite 的 classes 情境（#16、#17、#18）通過。
- [x] 7.2 已經有 PR 或 branch 的 issue 不接手：rest 流程第 3 步寫明 Step 0.5.1 回 resume 或 blocked 時記為 stopped、原因寫 `existing work: `，Step 0.5.1 有一句指回這一步。驗證：rest-queue suite 的 skill 文字檢查。
- [x] 7.3 Phase 6 開頭加一句：rest mode 下印完這一張的報告後回 Rest mode 流程第 4 步。驗證：rest-queue suite 的 skill 文字檢查。

