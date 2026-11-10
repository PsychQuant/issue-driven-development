## Problem

#480 的 verify 第 3 輪（2026-11-11，審查 `03f5559..6758bf3`）沒有 HIGH；9 項 MEDIUM 標為 Blocking，9 項 LOW／INFO 為 In-scope fix。大多是解析器在邊界上放行：

- `declared` 仍用舊的 fence 規則；fence 只認 0 到 3 格縮排，列表裡縮排 4 格的 fence 裡的 `No executable check:` 照樣算數；前面有空白的 `### Requirement:` 被整條跳過；`splitlines` 會在 U+2028 等字元上斷行。
- 某個 revision 上 `.spectra.yaml` 是目錄時退回 `openspec`；`spec_dir` 以 `:` 開頭時被 git 當成 pathspec，`links` 回 `ok`；找不到 git 時噴 traceback。
- `idd-close` Step 1.57：fetch 成功後檢查的 `origin/<default>` 可能是舊的；用 `jq` 判斷宣告形式；結果表缺「沒有輸出就停下」。規格要求讀不到預設 branch 一律停下，沒有限定宣告的形式。
- `idd-verify`：規格裡的 `No executable check:` 理由不再成立（那段已經有實跑的測試）；`VERIFY_PROFILE` 靠執行者設定，規格沒寫；`SPEC_FILES` 也列出封存的 delta；幾處說明過時。
- 契約的收尾連結檢查沒檢查各步的 exit code。

## Root Cause

第 2 輪把 CommonMark 的 fence 只套在 `links`；路徑與檔案型別的檢查只做在 working tree；skill 的 bash 依賴 `jq` 與 remote-tracking ref 這兩個沒有寫明的前提。

## Proposed Solution

- `declared` 與 `requirements()` 共用同一個 fence 判斷，fence 不論縮排都算，換行只認 `\n`、`\r\n`、`\r`；標題前允許 0 到 3 格空白。
- `.spectra.yaml` 在 revision 上必須是一般檔案；`spec_dir` 不得以 `:` 開頭；所有 git 呼叫用 literal pathspec；找不到 git 時回 `error`。
- Step 1.57 在 fetch 之後檢查 `FETCH_HEAD`，用 python 判斷宣告形式，結果表補一列；規格的停下條件限定在宣告了 change 時。
- `idd-verify` 規格把那行 `No executable check:` 換成 Example，連到契約測試裡實跑規格對照的三種情況；寫明 `VERIFY_PROFILE` 與沒有範圍時的處理；`SPEC_FILES` 只列主規格。
- 契約收尾的連結檢查在 `SPEC_BASE` 取不到時停下。

## Non-Goals

- 縮排的 code block 與多行 HTML 註解藏住的行（DA 判 LOW）：#491。
- 從受審 revision 讀 `.spectra.yaml`：#493；預設 branch 與 `origin` 可能不同：#494。

## Success Criteria

- 每一列新增的 Example 都有帶標記的測試，並在修正前失敗。
- `spec-change.py links` 對整條 branch 印 `ok`；`archived --ref HEAD` 對四個 change 的宣告印 `pass`。
- verify 第 4 輪沒有 HIGH，也沒有範圍內的 MEDIUM。

## Impact

- Affected specs: spec-on-every-issue, idd-verify
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/spec-change.py
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-change/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-close-gate/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-wrapper-contract/test.sh
  - Modified: plugins/issue-driven-dev/references/spec-wrapper.md
  - Modified: plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-verify/SKILL.md
