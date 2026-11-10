## 1. spec-change.py

- [x] 1.1 所有 git 呼叫帶 `-c core.quotePath=false`；`spec_dir` 依引號判斷註解；`ic` 接住 `RecursionError`（requirement「Added and modified requirements carry an executable check」、「The spec directory is resolved the way Spectra resolves it」、「One way to choose the Implementation Complete comment」）。驗證：中文 capability、引號內的 ` #`、巢狀太深的 JSON 各一個檢查，先看到失敗。

## 2. skills、契約與測試

- [x] 2.1 `idd-implement` Step 2.5 只略過 TaskList 的建立，分流表照常看；`**Spec plan**:` 行的三種形式寫進契約；`idd-plan` 在 Abort 時把它改成 `rejected`；契約第 3 步只在最新的 Implementation Plan 寫著 `change <名稱>` 時沿用既有的 change（requirement「Spec changes go through Spectra behind IDD wrappers」）。驗證：`spec-wrapper-contract` 檢查這幾處文字，先看到失敗。
- [x] 2.2 契約第 3、4 步的 bash 用假的 `spectra` 實跑，Example「contract steps 3 and 4 run as written」四列各一個檢查；preflight 的測試逐列驗「繼續或停下」（`PF_RC`）。驗證：先看到 unpark 與 `PF_RC` 的檢查失敗或缺席。
- [x] 2.3 `idd-verify` 的 `SPEC_FILES` 帶 `-c core.quotePath=false`。驗證：`spec-wrapper-contract` 檢查這段。
