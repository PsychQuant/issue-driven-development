## 1. spec-change.py

- [x] 1.1 `ic` 子指令選出 Implementation Complete 留言（requirement「One way to choose the Implementation Complete comment」）。驗證：Example「choosing the Implementation Complete comment」八列各一個檢查，寫在 `scripts/tests/spec-change/test.sh` 並帶標記，先看到它們失敗。
- [x] 1.2 `links` 對解析不了的 requirement 標題、head 上 `specs/` 沒有追蹤檔案回 `error`；標記只在標題之後只剩空白或註解結尾時才算（requirement「Added and modified requirements carry an executable check」）。驗證：Example「what the link check reports」新增的三列各一個檢查，先看到它們失敗。
- [x] 1.3 `preflight` 的 `error` 寫進規格（requirement「A repository without Spectra stops and a third-party clone proceeds」）。驗證：Example「preflight by write access and Spectra state」新增的那一列有檢查（非 git 目錄 → `error`、exit 2）。

## 2. skills 與契約

- [x] 2.1 `idd-close` Step 1.57 以 `gh api --paginate` 取留言、以 `ic` 選留言，取不到就停下（requirement「Close requires the issue's change to be archived」）。驗證：`scripts/tests/spec-close-gate/test.sh` 把 Step 1.57 的 bash 抽出來，用假的 `gh` 實跑三列：沒有 Implementation Complete → passes、取不到留言 → stops、最新的宣告未封存 → stops；先看到它們失敗。
- [x] 2.2 `idd-verify` 以 `ic` 選留言，`No executable check:` 的理由交給 reviewer 審（`idd-verify` 的 requirement「Reviewers check behaviour against the specs」）。驗證：`spec-wrapper-contract` 檢查規格對照那段呼叫 `ic`、審查規則寫到 `No executable check:`。
- [x] 2.3 `idd-all` Phase 3b：preflight 在檢查 Spectra 是否安裝之前；propose 的參數帶 Example、標題唯一、測試標記；自動修正處理被否決的 `no behaviour change`（requirement「Spec changes go through Spectra behind IDD wrappers」、「A fix after a verify round goes through the same wrapper」）。驗證：`spec-wrapper-contract` 檢查 Phase 3b 裡 preflight 的位置在 `command -v spectra` 之前、`PROPOSE_ARGS` 帶 `spec-example:`、修正規則寫到被否決的豁免。
- [x] 2.4 契約與文件：讀不到權限就停下，不當成第三方；被否決的豁免照第 3 到 5 步建第一個 change；linked worktree 對每一張 issue 都會停（`idd-implement` 的 tree-lock 說明、`idd-all` 的 batch 說明、CHANGELOG）。驗證：`spec-wrapper-contract` 檢查這三處文字。

## 3. 收尾

- [x] 3.1 開一張 follow-up issue：legacy 宣告放行（無法分辨舊留言與漏寫）、宣告的 change 沒綁定到 issue、第 1 輪 verify 的 LOW。驗證：issue 號寫進 Implementation Complete。（#491）
