**GitHub-side tracker**: #547（第 2 輪 verify：comment 6872782744；本輪計畫：comment 6872785819）

## Problem

第 2 輪 verify 找到 1 項 Blocking：issue repo 與程式 repo 分開時，程式 repo 的 commit 以 `owner/repo#N` 引用 issue，`link-base` 的左邊界把這種寫法排除，本機模式的連結檢查起點永遠找不到。另有 19 項 In-scope fix：`git log` 沒關簽章顯示也沒分隔路徑、key 當不了時退回 `.`（放寬方向）、remote 的判定漏了 pushurl 與舊式檔案、baseline tag 可以就在 HEAD、`spec_archive` 字面重複的 key 被吞掉、原因文字帶絕對路徑與錯誤的標籤，以及幾項測試沒有真正測到 Example。

## Root Cause

第 1 輪把 `#N` 的判斷照搬 `pr-issue-matching.md`，那份契約是給「PR 與 issue 在同一個 repo」用的；這個功能的前提正好是兩個 repo 分開。其餘是邊界沒有逐一列出。

## Proposed Solution

修改 `spec-on-every-issue`「A repository without a remote can opt into its local default branch」（見 specs/），照著改 `spec-change.py`、idd-close Step 1.5／1.57、spec-wrapper 第 5 步、config-protocol，並補測試。

## Non-Goals

- 設定檔的擁有者與權限檢查、`idd-all`／`idd-implement` 的 `unknown` 雜訊、`origin` 被 git 當成路徑：Follow-up。
- ASSUMPTION: 不升版號。

## Success Criteria

- 新的測試在改程式之前失敗，改之後通過；run-all-tests 全過；links 回 ok。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `spec-on-every-issue`: 「A repository without a remote can opt into its local default branch」。

## Impact

- Affected specs: spec-on-every-issue（MODIFIED 一條）
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/spec-change.py
  - Modified: plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - Modified: plugins/issue-driven-dev/references/spec-wrapper.md
  - Modified: plugins/issue-driven-dev/references/config-protocol.md
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-archive-local/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-close-gate/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/check-existing-work/test.sh
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
