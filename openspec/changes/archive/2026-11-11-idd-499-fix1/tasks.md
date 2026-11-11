## 1. 測試先行

- [x] 1.1 查詢在 issue 號不是數字時停下：依 requirement「Spec changes go through Spectra behind IDD wrappers」的 Example「idd-plan looks up the open change of the issue」新增的六列（NUMBER 沒設、空字串、abc、帶井號的 7、點加星號、07），spec-wrapper-contract 的查詢那一組加六個檢查，各自要印出以 stop: 開頭的一行，另加一個檢查確認這些情況不執行任何 spectra 指令；測試檔已帶標記 spec-example: spec-on-every-issue / idd-plan looks up the open change of the issue。驗證：改區塊之前這七個檢查失敗。
- [x] 1.2 三個檢查各有自測，用應該被抓到的資料餵給檢查本身（spec-wrapper-contract）：(a)「核准之後才 propose」的檢查抓得到寫著「沒有核准」的句子；(b) 同一個檢查抓得到契約講 plan 行那一段拿掉「經 idd-plan 的 run」之後的句子；(c)「沒有跳過 Step 2」的檢查在同一行另有否定句時，仍抓得到真的說跳過的那一句，而且不誤判單純的否定句。驗證：改檢查之前 (a)(b)(c) 的自測失敗。
- [x] 1.3 作者的限定有檢查（spec-wrapper-contract）：idd-implement Step 2 與契約裡每一行說「就不再貼」的都寫明有寫入權的帳號；Step 2 指名最新那則 plan 是 spec-change.py plan 讀的那一則，而且沒有「不看留言是誰貼的」這句話。驗證：改文字之前這些檢查失敗。

## 2. skills、契約與檢查

- [x] 2.1 idd-plan 的查詢區塊先檢查 NUMBER：沒設、以 0 開頭或不是十進位數字時印一行 stop: 並說明原因，不執行 spectra list；其餘情況與原本相同，查詢的三行仍與契約第 3 步逐行相同。區塊下面的說明改寫：限制回到兩個，並寫明契約第 3 步的查詢還沒有這個檢查（#496）；區塊前一句寫明 NUMBER 要在同一次 Bash 呼叫裡設好。驗證：1.1 通過；既有的查詢檢查（十列、逐行比對、stop 原因相同）照舊通過。
- [x] 2.2 idd-implement Step 2 與契約第 3 步的說明限定作者：最新那則 plan 是 spec-change.py plan 讀的那一則（有寫入權的帳號貼的）；Spec tasks 留言只有有寫入權的帳號貼過才算已經貼過；拿掉「不看留言是誰貼的」。驗證：1.3 通過；Step 2 原有的檢查照舊通過。
- [x] 2.3 三個檢查改嚴：「核准之後才 propose」的豁免字樣不接受「沒有核准」，並且不再只看帶有 tier 名稱的句子；「沒有跳過 Step 2」的否定判斷只看緊接在「跳過」前面的否定詞，不以整行為單位。驗證：1.2 通過；三個檢查對現行的檔案照舊通過。

## 3. 收尾

- [x] 3.1 CHANGELOG 的 Unreleased 條目補上這一輪的修正（#499 那一條底下）。驗證：git diff 只有新增行，已發布版本的條目沒有改動。
- [x] 3.2 讀到這些檔案的 suite 全部通過：run-all-tests.sh 的 73 個 suite 與 spectra-archive-post-ic。驗證：兩者結束碼 0。
