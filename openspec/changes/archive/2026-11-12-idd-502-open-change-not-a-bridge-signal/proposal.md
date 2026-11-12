**GitHub-side tracker**: #502

## Problem

`idd-comment` Step 0.7 判斷這次呼叫是不是從 spectra-discuss 中斷進來的，判成是的時候 Step 7 會寫 bookmark 並印 resume prompt。四個訊號任一成立就算，其中一個是「repo 裡有開著的 Spectra change」。這個訊號說的是 repo 的狀態，不是這次呼叫從哪裡來：只要 repo 裡有任何一個開著的 change，每一次 `/idd-comment` 都被判成從 spectra-discuss 進來，主題還是空的。4.0.0 之後每張實作中的 issue 在封存前都有一個開著的 change，所以在這個 repo 幾乎每次都成立。#126 報過同一件事，當時只追蹤、沒有改。

## Root Cause

`rules/spectra-bridge.md` 把這個訊號標成 60%（could be unrelated），結論那一句卻寫「任一訊號成立就啟動」，區塊照著實作。沒有規格寫這段偵測，也沒有測試執行它（`bridge-path` 只檢查 bridge 檔的路徑）。

## Proposed Solution

- 維護者已決定（2026-11-12）：拿掉這個訊號。
- `idd-comment` Step 0.7 的區塊拿掉查開著的 change 的那一段，不再執行 `spectra`。其他三個訊號不變：`--resume-spectra`、`--source` 含 `spectra-discuss`、bridge 檔的 `active_spectra_session` 是 true。
- `rules/spectra-bridge.md` 的偵測表拿掉那一列，並寫一句為什麼不算。
- plugin 的 `CLAUDE.md` 與 `README.md` 各有一句列出訊號，一起改；這兩句把 bridge 檔那個訊號寫成「檔案存在」，改成與規則一致的「存在而且 `active_spectra_session` 是 true」。
- 新增一條 requirement 與兩個 Example；新增 suite `spectra-bridge-detect`，把區塊抽出來執行。

## Non-Goals

- 另外兩個做法（要有另一個訊號同時成立才算、只認名稱點名這張 issue 的 change）：前者等於拿掉，後者在這個 repo 仍會誤判，維護者沒有選。
- bridge 由 `--source` 或 bridge 檔啟動時主題是空的：另一個問題，#524。
- 規則的「Skill responsibilities」表把 `idd-issue` 寫成已實作：#524。
- 規則表裡「Conversation context」那一列：那是由執行 skill 的模型判斷的，不在區塊裡，這次不動。
- ASSUMPTION: 不升版號，CHANGELOG 加在既有的 Unreleased 區塊。

## Success Criteria

- `spectra-bridge-detect` 在改動前失敗：只有開著的 change 時區塊啟動了 bridge、而且呼叫了 `spectra`；四個地方都還列著那個訊號。改動後全部通過。
- 另外三個訊號各自單獨成立時仍然啟動（改動前後都通過）。
- `bridge-path` 照舊通過；`rules/spectra-bridge.md` 的 Hard rule 6 仍在第 116 行。
- run-all-tests 的全部 suite 與 spectra-archive-post-ic 通過；連結檢查對新增的 requirement 回 ok。

## Capabilities

### New Capabilities

- `spectra-bridge-detection`: 寫明 IDD skill 憑哪些訊號判斷自己是從 spectra-discuss 中斷進來的（`rules/spectra-bridge.md` 的 bridge），以及哪些不算。

### Modified Capabilities

(none)

## Impact

- Affected specs: spectra-bridge-detection（新增，ADDED requirement「Open Spectra changes do not turn the spectra bridge on」）
- Affected code:
  - Modified: plugins/issue-driven-dev/skills/idd-comment/SKILL.md
  - Modified: plugins/issue-driven-dev/rules/spectra-bridge.md
  - Modified: plugins/issue-driven-dev/CLAUDE.md
  - Modified: plugins/issue-driven-dev/README.md
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
  - New: plugins/issue-driven-dev/scripts/tests/spectra-bridge-detect/test.sh
