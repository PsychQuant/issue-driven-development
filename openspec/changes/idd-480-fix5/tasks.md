## 1. spec-change.py

- [x] 1.1 `plan` 認得 `proposed (change <名稱>)`，標題比對限定 `## Implementation Plan` 後接行尾、空白或 `(`；讀 git 路徑一律 NUL 分隔；`install-spectra` 的訊息寫 `brew install --cask spectra-app` 與正確網址（requirement「Spec changes go through Spectra behind IDD wrappers」、「Added and modified requirements carry an executable check」、「A repository without Spectra stops and a third-party clone proceeds」）。驗證：Example「reading the Spec plan line」新增兩列、「what the link check reports」新增 `quo"te` 一列，以及訊息的檢查，先看到失敗。

## 2. skills、契約與測試

- [x] 2.1 契約第 3 步：檢查 `spectra list` 的結果，印一行判定（`propose`、`go on with <名稱>` 或停下並說明怎麼繼續）；`idd-plan` 進 plan mode 前寫 `proposed`、核准後改 `change`、Abort 改 `rejected`；`idd-implement` 與修正輪在 propose 前寫 plan 行；直接呼叫的 Plan-tier 只在 Step 0.6 問一次。驗證：`spec-wrapper-contract` 以假的 `spectra` 與 `gh` 實跑第 3 步，Example「an open change is checked against the newest plan」七列各一個檢查，先看到失敗；文字檢查涵蓋三個 skill。
- [x] 2.2 `idd-verify` 的 `SPEC_FILES` 用 `diff -z`；preflight 測試對 idd-all 那份也斷言 `PF_RC`。驗證：`spec-wrapper-contract` 的檢查。
- [x] 2.3 Example「reading the Spec plan line」從 requirement「The spec directory is resolved the way Spectra resolves it」底下搬到 wrapper 那條（fix4 誤接），標題與標記不變。驗證：`spec-change.py links` 對 branch 印 `ok`，標題在 capability 裡仍唯一。
- [x] 2.4 封存前 `spectra-verify` 的 warning：`idd-plan` 是開著的 change 唯一的核准路徑，`proposed`、`rejected`、沒有 plan 點名、plan 點名別的 change 都由它重新呈現；契約不再說 plan 行一律在 propose 之前；`spectra list` 印出不是 JSON 時停下；`idd-implement` 對這些情況都指向 `/idd-plan`；`idd-all` 的修正輪先貼 plan 行；Step 2.5 那一格不再給出又取消的指示。驗證：`spec-wrapper-contract` 新增的檢查先看到失敗，Example「an open change is checked against the newest plan」新增「不是 JSON」一列並以假的 `spectra` 實跑。
