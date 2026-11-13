## 1. 測試先行

- [x] 1.1 判斷規則照規格的四個步驟實作，資料取自規格：依 requirement「Open Spectra changes do not turn the spectra bridge on」的 Example「which wordings list open changes as a signal」，suite spectra-bridge-detect 從主規格讀這張表（29 列），逐列執行規則；函式在括號、逗號、頓號、分號（有沒有空白都算）、句號切子句，「不算」的說明要寫在提到之後；測試檔帶標記 spec-example: spectra-bridge-detection / which wordings list open changes as a signal。驗證：把函式換回第 1 輪的版本，有列失敗；每一個切點、每一個字、每一個步驟各改壞一次，至少有一列失敗。
- [x] 1.2 規則與 skill 怎麼寫對話脈絡有檢查：依 requirement「Conversation context does not turn the spectra bridge on」的 Example「what the rule and the skill say about conversation context」，規則那一行只在偵測表的下方找；偵測表每一列不提對話脈絡，中英文都比對；idd-comment Step 0.7 區塊下方有一行寫明對話脈絡不是訊號並點名 --resume-spectra；鐵律「Spectra context 不可靜默忽略」點名 SPECTRA_BRIDGE_ACTIVE=1 並寫明不從對話推斷；測試檔帶標記 spec-example: spectra-bridge-detection / what the rule and the skill say about conversation context。驗證：改 skill 之前，skill 的五個檢查失敗；把規則那一行搬到表的上方時檢查失敗。
- [x] 1.3 Step 7 的檢查比對「僅當 SPECTRA_BRIDGE_ACTIVE=1」：依 Example「Step 7 applies only when the bridge is on」；測試檔帶標記 spec-example: spectra-bridge-detection / Step 7 applies only when the bridge is on。驗證：把標題的「僅當」改成「當」時檢查失敗。

## 2. skill

- [x] 2.1 skills/idd-comment/SKILL.md：Step 0.7 區塊下方加一行（對話脈絡不是訊號，從 spectra-discuss 的討論中途呼叫要帶 --resume-spectra）；鐵律「Spectra context 不可靜默忽略」改成 Step 0.7 判定 SPECTRA_BRIDGE_ACTIVE=1 時必須印 resume prompt，並寫明這個判定不從對話推斷。偵測的區塊不改。驗證：1.2 全部通過；Example「what turns the spectra bridge on」的八列照舊通過。

## 3. 收尾

- [x] 3.1 CHANGELOG 的 Unreleased 條目（#525）照修正後的內容改寫。驗證：相對於 main，git diff 只有新增行。
- [x] 3.2 跑 spectra-bridge-detect（bash 5、macOS 內建的 bash 3.2、兩者加 LC_ALL=C）、bridge-path 與整套測試（run-all-tests.sh 與 spectra-archive-post-ic）。驗證：結束碼都是 0。
