## 1. idd-plan

- [x] 1.1 Step 3.5 的 bash 段（requirement「Plan-tier approval covers the change as it will be applied」）：parked 就 unpark，讀 `spectra instructions apply --json` 的 `changeDir`，缺 proposal、tasks 或 spec delta 就停下，印出目錄與檔案；Step 4 附上這些檔案的原文；Revised 先改檔案、跑 `spectra validate`、重跑這一段再重新呈現；Aborted 先 park 回去。驗證：`spec-wrapper-contract` 以假的 `spectra` 實跑這一段，Example「the step-3.5 block」五列各一個檢查，加上 Revised、Aborted 與 Step 4 的文字檢查，先看到失敗。

## 2. 同一區的小項

- [x] 2.1 `idd-implement` 的說明不再說直接呼叫時「照舊先問」要不要改走 `/idd-plan`；契約第 3 步在 plan 點名別的 change（`proposed` 或 `rejected`）時，stop 訊息寫出兩個名稱。驗證：`spec-wrapper-contract` 的檢查先看到失敗。
- [x] 2.2 第 6 輪的 #2、#4、#5、#6、#8、#9、#10 開成一張 follow-up issue。驗證：issue 號寫進 Implementation Complete。（#496）
