**GitHub-side tracker**: #525

## Problem

#502 的 verify 留下三個小項，都在 spectra bridge 的偵測（`/idd-comment` 判斷這次呼叫是不是從 spectra-discuss 的討論中途進來的）：

- `rules/spectra-bridge.md` 的偵測表有一列「Conversation context」（呼叫的 skill 知道自己是從 spectra 進來的），表上方寫任一訊號成立就啟動。`idd-comment` Step 0.7 的區塊沒有這個訊號，skill 的文字也沒有叫執行的模型依對話判斷。規格在「No executable check」那一行說這一列由執行 skill 的模型判斷，等於替一個沒有人執行的訊號背書。
- 規格說舊路徑的 bridge 檔只在新路徑沒有檔案時才算，但 Example 與測試都沒有「兩個檔同時存在」的列。把區塊改成先讀舊路徑，現在的測試不會發現。
- 檢查三處說明文字（`idd-comment` 的 task 描述、plugin 的 `CLAUDE.md` 與 `README.md`）有沒有把開著的 change 列成訊號時，只比對兩個英文說法。用中文把那個訊號寫回去，suite 仍然全過。

## Root Cause

#502 只處理「開著的 change」那個訊號，表裡的「Conversation context」當時列為不動的範圍；測試照當時改到的寫法寫，沒有涵蓋相鄰的情況。

## Proposed Solution

- 維護者已決定（2026-11-13）：不補自動的路。從 spectra-discuss 中途留言要自己帶 `--resume-spectra="<主題>"`。
- `rules/spectra-bridge.md` 的偵測表拿掉「Conversation context」那一列，表的下方加一行：對話脈絡不是訊號，從 spectra-discuss 中途呼叫要帶 `--resume-spectra`。行數不變。
- 修改 requirement「Open Spectra changes do not turn the spectra bridge on」：寫明兩個 bridge 檔同時存在時只讀新路徑的；寫明說明文字不得用任何語言把開著的 change 列成訊號，而「不算」的說明不是列入；Step 7 的標題要寫明只在 bridge 啟動時執行，取代原本「No executable check」的那一行。
- 新增 requirement「Conversation context does not turn the spectra bridge on」。
- `spectra-bridge-detect` 補上對應的檢查。`idd-comment` Step 0.7 的區塊不改。

## Non-Goals

- 另外兩個做法（讓 spectra-discuss 那一側寫 bridge 檔；在 `idd-comment` 寫明由執行的模型依對話判斷）：維護者沒有選。
- bridge 由 `--source` 或 bridge 檔啟動時主題是空的；規則的「Skill responsibilities」表把 `idd-issue` 寫成已實作：#524。
- 列 4（更正 #502 兩則留言裡的同一句）：已在 2026-11-13 完成。
- ASSUMPTION: 不升版號，CHANGELOG 加在既有的 Unreleased 區塊。
- ASSUMPTION: 「開著的 change」的中文比對涵蓋「開著的」「進行中的」「未封存的」三種說法；其他說法不在這次的範圍。

## Success Criteria

- 新的檢查各有失敗的紀錄：規則的三個檢查在改規則之前失敗；把區塊改成先讀舊路徑時，「兩個檔同時存在」的檢查失敗；在三處用中文把訊號寫回去的副本上，改之前的 suite 全過、改之後失敗。
- `bridge-path` 照舊通過；`rules/spectra-bridge.md` 的 Hard rule 6 仍在第 116 行。
- `spectra-bridge-detect` 在 bash 5 與 macOS 內建的 bash 3.2 都通過，`LC_ALL=C` 之下也通過。
- run-all-tests 的全部 suite 與 spectra-archive-post-ic 通過；連結檢查對改到與新增的 requirement 回 ok。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `spectra-bridge-detection`: 對話脈絡不是訊號；兩個 bridge 檔同時存在時只讀新路徑的；說明文字的檢查不分語言；Step 7 只在 bridge 啟動時執行。

## Impact

- Affected specs: spectra-bridge-detection（MODIFIED requirement「Open Spectra changes do not turn the spectra bridge on」；ADDED requirement「Conversation context does not turn the spectra bridge on」）
- Affected code:
  - Modified: plugins/issue-driven-dev/rules/spectra-bridge.md
  - Modified: plugins/issue-driven-dev/scripts/tests/spectra-bridge-detect/test.sh
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
