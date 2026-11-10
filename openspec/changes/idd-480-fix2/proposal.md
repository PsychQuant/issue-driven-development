## Problem

#480 的 verify 第 2 輪（2026-11-11，審查 `03f5559..90f1b5a`）沒有 HIGH，但有 6 項 MEDIUM 與 1 項 LOW 標成 Blocking，另有 2 項 MEDIUM、5 項 LOW 標成 In-scope fix：

- `links` 的解析可以被繞過：同名的 requirement 會蓋掉前一條；寫在 code fence 裡的 `##### Example:` 與 `No executable check:` 被當成正式內容；fence 的結束沒照 CommonMark 比長度。
- `preflight` 讀不到 `.spectra.yaml` 時噴 traceback、exit 1、沒有 JSON；wrapper 的對照表沒有「沒有輸出或不是 JSON 就停下」這一列。
- 從 `idd-diagnose` 交出去、手動走的 Spectra 路徑沒有 preflight。
- `idd-verify` 的規格對照靠一個要人改寫的 `VERIFY_PROFILE` 字面值決定要不要跑；DA focus 的後綴在每個 profile 都加上；`verify-profiles.md` 仍說 code profile 逐 byte 不變。
- 規格對照帶著受審規格裡的標題與留言片段進 reviewer 的 prompt，外面沒有 sentinel。
- wrapper 那條 requirement 的 `No executable check:` 理由不成立：Phase 3b 先跑 preflight 是確定性的 bash，可以實跑測試。
- `idd-close` Step 1.57 沒檢查 `gh repo view` 與 `git fetch` 的結果。
- checklist 來源的規則沒有 requirement；`--retroactive` 有沒有略過 Step 1.57 沒有定義；`case "$PERM"` 沒有測試；`docs/commands.md` 仍說 close 之後才封存；`git ls-tree` 沒加 `--`；marker 前有空白時選不到留言；`--path-format=absolute` 需要 git 2.31。

## Root Cause

規格寫的是每個指令對每種輸入印什麼，但解析器只認得它預期的格式，其餘當成「沒有」；skill 裡的 bash 把失敗當成空值往下傳；規格對照把資料與規則放在同一段沒有邊界的文字裡。

## Proposed Solution

- `requirements()` 照 CommonMark 判斷 fence，Example 與 `No executable check:` 只看 fence 外的行，同一個 capability 裡的同名 requirement 回 `error`。
- `preflight` 把讀檔失敗轉成 `error`（exit 2）；契約、`idd-all` Step 3b.0、`idd-close` Step 1.57 都在沒有輸出、不是 JSON 或未知狀態時停下。用假的 `gh` 實跑契約與 `idd-all` 的 preflight 區塊，確認兩份從權限到狀態的對應一致。
- 手動的 Spectra 路徑在 `/spectra-discuss` 之前跑同一個 preflight。
- `idd-verify` 只在有 git 範圍（code profile）時組規格對照，資料包在每次產生的 nonce fence 裡，DA 的後綴只在 code profile 加；說明「不變」的是 lens 組合與輸入偵測。
- `idd-close` Step 1.57 對 `gh repo view` 或 `git fetch` 失敗回 `error`；`--retroactive` 略過這一道。
- 其餘 LOW 一併修掉。

## Non-Goals

- legacy 宣告、宣告的 change 沒有綁定到 issue：#491。
- Spectra 沒有宣告成 plugin 依賴、preflight 不檢查 Spectra 的 skill：#492。

## Success Criteria

- 每一列新增的 Example 都有帶標記的測試，並在修正前失敗。
- `spec-change.py links` 對整條 branch 印 `ok`；`archived --ref HEAD` 對三個 change 的宣告印 `pass`。
- verify 第 3 輪沒有 HIGH，也沒有範圍內的 MEDIUM。

## Impact

- Affected specs: spec-on-every-issue, idd-verify
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/spec-change.py
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-change/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-close-gate/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-wrapper-contract/test.sh
  - Modified: plugins/issue-driven-dev/references/spec-wrapper.md
  - Modified: plugins/issue-driven-dev/references/verify-profiles.md
  - Modified: plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-verify/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - Modified: plugins/issue-driven-dev/rules/sdd-integration.md
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
  - Modified: docs/commands.md
