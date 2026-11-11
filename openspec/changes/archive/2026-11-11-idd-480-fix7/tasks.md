## 1. spec-change.py

- [x] 1.1 `plan` 不再認 `rejected (change <名稱> left parked)`，讀成 `invalid`（requirement「Spec changes go through Spectra behind IDD wrappers」）。驗證：Example「reading the Spec plan line」改過的兩列（Planning notes 那列改用 `change`、`rejected` 那列回 `invalid` exit 1）各一個檢查，先看到失敗。

## 2. skills、契約與文件

- [x] 2.1 `idd-plan` 不 propose：要寫規格時 plan 行在進 plan mode 前寫 `proposed (change idd-<N>-<slug>)`，核准後改 `change <名稱>`，已有開著的 change 時寫那個名稱，Step 6 交名稱給 `idd-implement`；拿掉 Step 3.5、Step 4 附檔案的說明、範本那一行、`read_change_files`；Revised、Aborted、Revise 說明回到 #480 之前。驗證：`spec-wrapper-contract` 檢查 `idd-plan` 沒有 `Skill(skill="spectra-propose"`、沒有 `### Step 3.5:`、Step 6 交出名稱，先看到失敗。
- [x] 2.2 `idd-implement` 從 `idd-plan` 來時用核准的名稱以輕量形式 propose，change 已開著就直接用；Step 0.6 不提 `rejected`。契約第 3 步拿掉 `rejected` 那一支、「`idd-plan` 會先建好」與五種寫法的說法；Example「an open change is checked against the newest plan」拿掉 `rejected` 那一列。`rules/sdd-integration.md`、`idd-diagnose` 的 route 表、CHANGELOG 改成核准 Implementation Plan、propose 在 `idd-implement`。驗證：`spec-wrapper-contract` 的檢查先看到失敗；fix4 到 fix6 對 `rejected`、Step 3.5 的檢查改成相反的斷言或拿掉。
- [x] 2.3 第 6 輪 follow-up 留言（comment 6784058096）的去向用 `idd-edit --correct` 更正（第 7 輪 #12）。驗證：留言的 Follow-up 段列出 #496。
- [x] 2.4 封存前 `spectra-verify` 的 warning：README 不再說 `idd-plan` 呈現 proposal；`spec-wrapper-contract/test.sh` 只留一份（先前誤貼兩次）；`idd-plan` 用 `spectra list` 找這張 issue 開著的 change（`allowed-tools` 加 `Bash(spectra:*)`），規格寫明它不跑第 3 步的檢查；Aborted 列不再說還沒有 change；Step 6 的範例帶 `--spec-change`，流程圖改成 `idd-implement` 在 Step 2 propose。驗證：`spec-wrapper-contract` 新增的檢查先看到失敗。
