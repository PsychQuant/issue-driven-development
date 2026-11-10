## Problem

#480 的 verify 第 4 輪（2026-11-11，審查 `03f5559..93f8991`）有 2 項 HIGH、3 項 MEDIUM 為 Blocking，4 項 In-scope fix：

- `idd-implement` Step 2.5 新加的「有 change 時跳過這一步」連帶跳過整張分流表：直接呼叫 `/idd-implement` 處理 Plan issue 時，原本「建議改走 `/idd-plan`」的確認不再發生（HIGH，#480 造成的退化）。
- `**Spec plan**:` 這一行後續步驟依它分流，規格與契約都沒寫到（HIGH）。
- `git ls-tree` 與 `git diff` 會把非 ASCII 路徑加上引號，`links` 對中文 capability 新增的 requirement 回 `ok`，`SPEC_FILES` 印 `(none)`。
- preflight 的測試只驗印出的狀態，沒驗「繼續或停下」；契約第 3、4 步（判定無人值守、unpark）是固定的 bash，規格卻以「由模型執行」為理由不寫檢查。
- `idd-plan` 在核准前就 propose，Abort 之後 change 留著，下一次 `idd-implement` 會把被拒絕的 proposal 當成已核准而 apply。
- `.spectra.yaml` 裡引號內的 ` #` 被當成註解；`ic` 讀到巢狀太深的 JSON 時 exit 1。

## Root Cause

為了「有 change 時不建 TaskList」而跳過整個步驟；「這個 change 有沒有被核准」沒有寫下來的訊號，只能從 change 存不存在推測；git 的預設輸出格式（引號）沒有被當成輸入格式處理。

## Proposed Solution

- Step 2.5 只略過 TaskList 的建立，分流表照常看；直接呼叫處理 Plan issue 時照舊先問要不要改走 `/idd-plan`。
- 規格與契約寫明 Implementation Plan 留言的 `**Spec plan**:` 行：`change <名稱>`、`no behaviour change (<a|b|c|d>)`、`rejected (change <名稱> left parked)`。`idd-plan` 在 Abort 時把它改成 `rejected`；wrapper 只在最新的 Implementation Plan 寫著 `change <名稱>` 時沿用既有的 change。
- 所有 git 呼叫帶 `-c core.quotePath=false`；`SPEC_FILES` 同樣。
- preflight 測試逐列驗「繼續或停下」；契約第 3、4 步的 bash 以假的 `spectra` 實跑，寫成 Example。
- `spec_dir` 依引號判斷註解；`ic` 接住 `RecursionError`。

## Non-Goals

- `idd-verify/spec.md` 舊的 profile requirement 裡「byte-identical」的說法（LOW）：改它會牽動那條舊 requirement 的檢查，另行處理。
- 第 4 輪的 Follow-up：#491、#488、#493。

## Success Criteria

- 每一列新增的 Example 都有帶標記的測試，並在修正前失敗。
- `spec-change.py links` 對整條 branch 印 `ok`；`archived --ref HEAD` 對五個 change 的宣告印 `pass`。
- verify 第 5 輪沒有 HIGH，也沒有範圍內的 MEDIUM。

## Impact

- Affected specs: spec-on-every-issue
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/spec-change.py
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-change/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-wrapper-contract/test.sh
  - Modified: plugins/issue-driven-dev/references/spec-wrapper.md
  - Modified: plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-verify/SKILL.md
