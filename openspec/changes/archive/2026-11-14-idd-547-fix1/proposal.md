**GitHub-side tracker**: #547（第 1 輪 verify：comment 6871443624；本輪計畫：comment 6871456743）

## Problem

第 1 輪 verify 找到 1 項 Blocking 與 24 項 In-scope fix：`archive-ref` 對兩個指向同一路徑的 key 回 `error`，requirement 卻沒寫這一種；沒設 `spec_archive` 的 repo，設定檔只要是空檔、`null`、帶 BOM 或非 UTF-8 就被擋下，違反「沒設就不變」；`link-base` 先驗 `--issue` 再看設定，讓沒設定的 repo 也可能在連結檢查停下；`branch` 接受 revision 語法；`#N` 沒有左邊界；有幾項規則沒有測試能分辨對錯（讀的是設定的 branch 還是 HEAD、Step 1.5 有沒有真的把旗標傳給 helper）。

## Root Cause

第一版把「設定讀不了」與「設定寫錯」一起當成 `error`，但前者在沒設 `spec_archive` 的 repo 也會發生；把 `--issue` 的驗證放在設定解析之前；branch 只檢查存在；測試的 fixture 只有一條 branch、`HEAD` 永遠在設定的 branch 上，分不出兩種讀法。

## Proposed Solution

修改 `spec-on-every-issue` 的兩條 requirement（見 specs/），並照著改 `spec-change.py`、`check-existing-work.sh`、idd-close Step 1.57、spec-wrapper 第 5 步、idd-all Step 3b.6、config-protocol，補齊各 Example 的測試。

## Non-Goals

- 設定檔的擁有者與權限檢查、`idd-all`／`idd-implement` 在沒有 remote 的 repo 的 `unknown`：Follow-up。
- ASSUMPTION: 不升版號，CHANGELOG 的 Unreleased 條目照實補充。

## Success Criteria

- 新增與改動的測試在改程式之前失敗，改之後通過；run-all-tests 全過；links 回 ok。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `spec-on-every-issue`: 「Close requires the issue's change to be archived」與「A repository without a remote can opt into its local default branch」。

## Impact

- Affected specs: spec-on-every-issue（MODIFIED 兩條）
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/spec-change.py
  - Modified: plugins/issue-driven-dev/scripts/check-existing-work.sh
  - Modified: plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - Modified: plugins/issue-driven-dev/references/spec-wrapper.md
  - Modified: plugins/issue-driven-dev/references/config-protocol.md
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-archive-local/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-close-gate/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/check-existing-work/test.sh
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
