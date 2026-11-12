**GitHub-side tracker**: #512

## Problem

`idd-close` 的 Step 6.3（doc-sync 檢查）有一句「位置」，說這一步在結案摘要貼出之後、`gh issue close` 之前做。同一份 SKILL.md 的其他地方都是先關閉：Step 4 在同一個 bash 區塊裡貼摘要、接著關閉 issue；步驟的順序是 Step 4、Step 6、Step 6.3、Step 6.5；Step 0.5 的清單也是 `publish_and_close`、`auto_update_body`、`doc_sync_sweep`、`distribution_sync_chain_detection`。照步驟順序執行的人到 Step 6.3 時 issue 已經關了；照那一句執行的人要自己把 Step 4 的區塊拆開。兩種讀法做出來的順序不同。

## Root Cause

Step 6.3 加進來的時候（#220），「位置」那一句寫的是當時的打算，這一步實際被放在 Step 4 與 Step 6 之後。沒有任何檢查比對這一句、步驟的順序與清單，也沒有規格寫明這一步在什麼時候做，所以矛盾一直留著。

## Proposed Solution

- 維護者已決定（2026-11-11）：doc-sync 檢查留在 issue 關閉之後，只改「位置」那一句，不把檢查移到貼出摘要之前。
- 那一句改成說狀態：issue 已關閉、結案摘要已貼出之後，在 Step 6 body sync 之後、Step 6.5 distribution sync 之前。
- 新增一條 requirement，寫明這個位置，以及 SKILL.md 講到它的三處要一致。
- doc-sync-sweep 的測試加一個檢查程式：讀 SKILL.md，比對步驟的順序、清單的順序與「位置」那一句；並用七份改壞的副本確認每一項檢查都抓得到。

## Non-Goals

- 把 doc-sync 檢查移到關閉之前，或讓它能擋下結案：維護者選了相反的做法。
- 改 Step 4、Step 6、Step 6.5 或 Step 0.5 清單的內容：它們已經一致。
- 寫明 `--retroactive` 模式跑不跑 Step 6.3：那張表沒有列這一步，是另一個問題，另開 issue。
- 檢查執行者實際照什麼順序跑：步驟由照 SKILL.md 執行的模型做，這次只檢查它讀的文字。
- ASSUMPTION: 不升版號，CHANGELOG 加在既有的 Unreleased 區塊。

## Success Criteria

- doc-sync-sweep 新增的檢查在改 SKILL.md 之前失敗（現行的檔案不通過），改之後通過；七份改壞的副本各自被抓到，原因是它改壞的那一項。
- doc-sync-sweep 原有的七個檢查照舊通過。
- run-all-tests 的全部 suite 與 spectra-archive-post-ic 通過。
- 連結檢查對新增的 requirement 回 ok。

## Capabilities

### New Capabilities

- `idd-close-doc-sync`: 寫明 `/idd-close` 的 doc-sync 檢查在什麼時候做（issue 關閉、結案摘要貼出之後），以及 SKILL.md 講到這個位置的幾處要一致。

### Modified Capabilities

(none)

## Impact

- Affected specs: idd-close-doc-sync（新增，ADDED requirement「The doc-sync sweep runs after the issue is closed」）
- Affected code:
  - Modified: plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - Modified: plugins/issue-driven-dev/scripts/tests/doc-sync-sweep/test.sh
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
