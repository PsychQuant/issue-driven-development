## Problem

#480 的 verify 第 5 輪（2026-11-11，審查 `03f5559..f089db8`）有 1 項 HIGH、1 項 MEDIUM 為 Blocking，8 項 In-scope fix：

- `idd-plan` 在進 plan mode 之前就貼出 `**Spec plan**: change <名稱>`。session 沒走到 Abort 就結束時，這一行看起來像核准過，下次 `/idd-implement` 會把沒被核准的 proposal apply（HIGH）。
- `core.quotePath=false` 之後，含 `"`、`\`、TAB 的路徑仍被 git 加上引號，`links` 對這些 capability 回 `ok`。
- 契約第 3 步吞掉 `spectra list` 的錯誤，讀不到清單時當成「沒有 change」；有開著的 change 卻沒有 plan 點名時每次都停，沒說怎麼繼續；`install-spectra` 的訊息沒有安裝指令，網址也不對。
- 直接呼叫時「要不要改走 `/idd-plan`」可能問兩次；plan 的 Example 掛在 spec 目錄那條 requirement 底下；idd-all 那份 preflight 沒有斷言 `PF_RC`；`PLAN_RE` 用前綴比對；Abort 留言的建議過時。

## Root Cause

「已提出」與「已核准」共用同一個形式；路徑仍靠 git 的文字輸出切分；探測步驟把失敗當成空結果。

## Proposed Solution

- 新增 `proposed (change <名稱>)`：`idd-plan` 進 plan mode 前寫它，核准後改成 `change <名稱>`，Abort 改成 `rejected`。`idd-implement` 與修正輪都在 propose 之前寫 plan 行。停下時訊息寫明重跑 `/idd-plan`。
- `spec-change.py` 讀 git 路徑一律用 NUL 分隔（`ls-tree -z`），`idd-verify` 的 `SPEC_FILES` 用 `diff -z`。
- 契約第 3 步檢查 `spectra list` 的結果，讀不到就停下，並印出一行判定（`propose`、`go on with <名稱>` 或停下的原因），以假的 `spectra` 實跑成 Example。
- `install-spectra` 的訊息寫 `brew install --cask spectra-app` 與正確網址。
- 其餘 LOW 一併修。

## Non-Goals

- 第 5 輪的 Follow-up：#488、#487、#493、#491。

## Success Criteria

- 每一列新增的 Example 都有帶標記的測試，並在修正前失敗。
- `spec-change.py links` 對整條 branch 印 `ok`；`archived --ref HEAD` 對六個 change 的宣告印 `pass`。
- verify 第 6 輪沒有 HIGH，也沒有範圍內的 MEDIUM。

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
  - Modified: plugins/issue-driven-dev/skills/idd-all/SKILL.md
