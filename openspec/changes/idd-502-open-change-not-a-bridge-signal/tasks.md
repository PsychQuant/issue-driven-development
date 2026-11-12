## 1. 測試先行

- [x] 1.1 偵測區塊有可執行的檢查：依 requirement「Open Spectra changes do not turn the spectra bridge on」的 Example「what turns the spectra bridge on」，新增 suite spectra-bridge-detect：從 idd-comment 的 SKILL.md 抽出 Step 0.7 的 bash 區塊，放進空目錄、只有假的 spectra 的環境執行，Example 的七列各一個檢查，另加一個檢查確認七列都沒有呼叫 spectra；測試檔帶標記 spec-example: spectra-bridge-detection / what turns the spectra bridge on。驗證：改 SKILL.md 之前，「只有開著的 change」那一列與「沒有呼叫 spectra」失敗，其餘六列通過。
- [x] 1.2 列出訊號的四個地方有檢查：依 Example「where the bridge signals are listed」，同一個 suite 檢查規則偵測表的每一列、idd-comment Step 0 的 task 描述、plugin 的 CLAUDE.md 與 README 列出訊號的那一句，都沒有把開著的 change 列為訊號，而且 CLAUDE.md 與 README 的那一句寫的是 bridge 檔的 active_spectra_session；測試檔帶標記 spec-example: spectra-bridge-detection / where the bridge signals are listed。驗證：改文字之前這些檢查失敗。

## 2. skill、規則與說明

- [x] 2.1 idd-comment Step 0.7 拿掉查開著的 change 的那一段，bridge 檔那一段的編號改成 Signal 3，區塊下面加一句說明為什麼開著的 change 不算；Step 0 的 task 描述拿掉那個訊號。驗證：1.1 全部通過；bridge-path 照舊通過。
- [x] 2.2 rules/spectra-bridge.md 的偵測表拿掉那一列，結論那一句後面加一句說明開著的 change 不算。驗證：1.2 對規則的檢查通過；Hard rule 6 仍在第 116 行（idd-comment 與 bridge-path 用行號引用它）。
- [x] 2.3 plugin 的 CLAUDE.md 與 README 列出訊號的那一句：拿掉那個訊號，bridge 檔寫成存在而且 active_spectra_session 是 true。驗證：1.2 對這兩個檔的檢查通過。

## 3. 收尾

- [x] 3.1 CHANGELOG 的 Unreleased 加 Fixed 條目（#502）。驗證：git diff 只有新增行，已發布版本的條目沒有改動。
- [x] 3.2 跑 spectra-bridge-detect、bridge-path 與整套測試（run-all-tests.sh 與 spectra-archive-post-ic）。驗證：結束碼都是 0。
