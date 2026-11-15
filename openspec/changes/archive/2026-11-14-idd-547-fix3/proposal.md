**GitHub-side tracker**: #547（第 3 輪 verify：comment 6875253859；本輪計畫：comment 6875265846；不在範圍的三項合成 #552）

## Problem

第 3 輪 verify 找到 1 項 Blocking：第 2 輪把 `repo_top()` 改成只去換行，連帶讓 `archived`、`links`、`preflight` 對結尾有空白的路徑讀對了 repo（原本會讀到同名的兄弟目錄），但沒有 requirement 寫明、沒有測試。另有 11 項 In-scope fix：`--separate-git-dir` 主工作樹的 linked worktree 算錯 key（git 不記錄這種主工作樹在哪，改成不猜 key、說明原因）、`git log` 的輸出編碼沒固定、重複鍵的記號放在資料裡、沒有 remote 的 repo 仍去 fetch（git 會把名為 `origin` 的本機路徑當成 remote）、`"spec_archive": null` 擋住普通 repo，以及幾處標籤、文件與測試細節。

## Root Cause

前兩輪逐項修邊界時，共用的 helper 改動沒有回頭補到其他子命令的規格；主工作樹與重複鍵的判斷用了推論而不是 git 與 parser 直接給的答案。

## Proposed Solution

新增 requirement「spec-change.py reads the repository that holds --cwd」，修改「Close requires the issue's change to be archived」與「A repository without a remote can opt into its local default branch」（見 specs/），照著改程式、文件與測試。

## Non-Goals

- 設定檔擁有者檢查、開工檢查的 `unknown` 雜訊、Step 1.55 的 fetch：#552。
- ASSUMPTION: 不升版號。

## Success Criteria

- 新的測試在改程式之前失敗，改之後通過；run-all-tests 全過；links 回 ok。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `spec-on-every-issue`: 新增一條、修改兩條 requirement。

## Impact

- Affected specs: spec-on-every-issue
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/spec-change.py
  - Modified: plugins/issue-driven-dev/scripts/check-existing-work.sh
  - Modified: plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - Modified: plugins/issue-driven-dev/references/spec-wrapper.md
  - Modified: plugins/issue-driven-dev/references/config-protocol.md
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-archive-local/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-close-gate/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/check-existing-work/test.sh
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
