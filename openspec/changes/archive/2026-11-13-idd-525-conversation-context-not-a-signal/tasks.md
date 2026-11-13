## 1. 測試先行

- [x] 1.1 兩個 bridge 檔同時存在的情況有檢查：依 requirement「Open Spectra changes do not turn the spectra bridge on」的 Example「what turns the spectra bridge on」新增的第八列，suite spectra-bridge-detect 加一個檢查（新路徑的檔是 false、舊路徑的檔是 true，結果 0），「沒有呼叫 spectra」的檢查改成涵蓋八列；測試檔帶標記 spec-example: spectra-bridge-detection / what turns the spectra bridge on。驗證：區塊現在是對的，這個檢查一加上就通過；把區塊抽出來改成先讀舊路徑之後，這個檢查失敗。
- [x] 1.2 說明文字的檢查不分語言：依 Example「which wordings list open changes as a signal」，同一個 suite 把「這一句有沒有把開著的 change 列成訊號」寫成函式，Example 的七列各一個檢查，再把函式套用到 Example「where the bridge signals are listed」的三處（task 描述、plugin 的 CLAUDE.md 與 README）；測試檔帶標記 spec-example: spectra-bridge-detection / which wordings list open changes as a signal。驗證：在三處都用中文把那個訊號寫回去的副本上，改之前的 suite 全過，改之後這三個檢查失敗。
- [x] 1.3 規則怎麼寫對話脈絡有檢查：依 requirement「Conversation context does not turn the spectra bridge on」的 Example「what the rule says about conversation context」，同一個 suite 檢查偵測表剛好三列訊號、每一列都沒有提到對話脈絡、表的下方有一行寫明它不是訊號而且要帶 --resume-spectra；測試檔帶標記 spec-example: spectra-bridge-detection / what the rule says about conversation context。驗證：改規則之前這些檢查失敗。
- [x] 1.4 Step 7 的適用條件有檢查：依 Example「Step 7 applies only when the bridge is on」，同一個 suite 檢查 idd-comment 的 SKILL.md 只有一個 Step 7 的標題，而且標題寫明 SPECTRA_BRIDGE_ACTIVE=1；測試檔帶標記 spec-example: spectra-bridge-detection / Step 7 applies only when the bridge is on。驗證：標題現在就這樣寫，檢查一加上就通過；在副本裡把標題的條件拿掉之後，這個檢查失敗。

## 2. 規則

- [x] 2.1 rules/spectra-bridge.md 的偵測表拿掉「Conversation context」那一列，在「Open Spectra changes…」那一行後面加一行，寫明對話脈絡不是訊號、從 spectra-discuss 中途呼叫要帶 --resume-spectra。驗證：1.3 全部通過；檔案的行數不變，Hard rule 6 仍在第 116 行（idd-comment 與 bridge-path 用行號引用它）；bridge-path 照舊通過。

## 3. 收尾

- [x] 3.1 CHANGELOG 的 Unreleased 加條目（#525）。驗證：git diff 只有新增行，已發布版本的條目沒有改動。
- [x] 3.2 跑 spectra-bridge-detect、bridge-path 與整套測試（run-all-tests.sh 與 spectra-archive-post-ic）；spectra-bridge-detect 另外用 macOS 內建的 bash 3.2 與 LC_ALL=C 各跑一次。驗證：結束碼都是 0。
