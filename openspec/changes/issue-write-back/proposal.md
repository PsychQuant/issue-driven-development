## Why

討論一張 issue 時，問題本身、診斷、以及新的資訊或決定都會改變，但 IDD 目前只會往下追加 comment：`/idd-edit --correct` 每次都要使用者確認，`idd-diagnose` 要調整診斷時另貼一則修正 comment。結果 issue 正文和 Diagnosis 停在第一版，讀者要讀完整串才知道現況；#399 就這樣累積了五份沒套用的更正稿。#424 定案（2026-10-25）：由 AI 判斷改變屬於哪一類並自己寫回，不再停下來確認。

## What Changes

- 新增 plugin 規則 `plugins/issue-driven-dev/rules/issue-write-back.md`：使用者在 session 裡定案的改變分三類寫回——問題的改變寫回 issue 正文的段落；診斷的改變寫回 Diagnosis 留言的段落，連帶更新 Implementation Plan 受影響的段落（verify 報告不動），改了診斷的決定另貼 decision comment 記下原話；新的資訊與決定新增一則 comment。只有明確定案才算，假設與提問不算，已關閉的 issue 不改；別人的 comment 只在使用者於 session 提到並決定採納時才算，要寫進去的內容先列出再問。實作之後定案、同一個 PR 跟著改的改變也就地寫回，PR 合併後才擴大的範圍開新 issue 承接，只有已建好的東西要作廢時才走 `idd-reorganize`。只改寫自己的內容，別人的內容改貼 errata 或 correction comment。在有寫入權的 repo 不先問，每次寫回在對話裡回報依據；寫回前做 privacy 自審，命中就停（credential 在任何等級都算）。
- SessionStart 注入加一行提醒（印出規則檔的安裝路徑），讓 skill 之外的討論也套用；IDD 的 SessionStart 輸出維持在 5 行以內。
- **BREAKING** `/idd-edit --correct` 不再用 AskUserQuestion 確認：預覽與 diff 改成在對話裡回報後直接套用，改寫的段落尾留一行可見文字（`--note`）。`--prepend-note`、`--append`、`--replace` 維持確認。privacy 自審、#272 閘、寫入前重讀、歸檔照常執行。
- `idd-diagnose` Step 4 Stage 1：診斷要調整時用 `/idd-edit --correct` 改 Diagnosis 留言本身，不再追加修正 comment。
- 偵測到錯誤的 skill（`idd-verify`、`idd-diagnose`、`idd-reorganize`）維持 3.6.0 的提議流程；選了「現在執行」就是確認：問句附上替換內容全文，引數帶 `--repo` 與 `--note`，`/idd-edit --correct` 不再問第二次。
- 第一版另有「別人的 comment 自動觸發寫回」與「偵測 skill 自動更正」兩塊，四輪 verify 都沒過、不收斂，維護者 2026-11-04 決定砍掉（comment 6616229678）；第 5 輪後再拿掉 verify 報告註記、`--body-file` 私人路徑閘與 `/idd-edit` 的 unattended 分支（comment 6617788666）；第 6 輪後改了診斷的決定兩處都寫、可見文字拿掉「AI 判斷」（comment 6619279709）；第 7 輪後合併後擴大的範圍開新 issue（comment 6620544269）。
- plugin 版本 3.7.0，CHANGELOG 與 README 同步。

## Capabilities

### New Capabilities

- `issue-write-back`: 討論中定案的改變依類別寫回 issue 正文、Diagnosis 留言或新的 comment，由 AI 判斷、不確認、只改自己的內容、每次回報、留可見文字。

### Modified Capabilities

- `in-place-correction`: `/idd-edit --correct` 改為回報後直接套用、不再確認；偵測 skill 選執行後不再有第二次確認。
- `append-vs-modify-discipline`: `in-place-correction` 分類不再要求確認，改寫處留可見文字。
- `user-rule-injection`: SessionStart 多一行寫回提醒，印出規則檔的安裝路徑。

## Impact

- Affected specs: `issue-write-back`（新增）、`in-place-correction`（修改）、`append-vs-modify-discipline`（修改）、`user-rule-injection`（修改）
- Affected code:
  - New: plugins/issue-driven-dev/rules/issue-write-back.md, plugins/issue-driven-dev/scripts/tests/issue-write-back/test.sh
  - Modified: plugins/issue-driven-dev/scripts/idd-edit-helper.py, plugins/issue-driven-dev/hooks/session-start-commit-rule.sh, plugins/issue-driven-dev/scripts/tests/session-start-commit-rule/test.sh, plugins/issue-driven-dev/scripts/tests/edit-run/test.sh, plugins/issue-driven-dev/skills/idd-edit/SKILL.md, plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md, plugins/issue-driven-dev/skills/idd-verify/SKILL.md, plugins/issue-driven-dev/skills/idd-reorganize/SKILL.md, plugins/issue-driven-dev/skills/idd-comment/SKILL.md, plugins/issue-driven-dev/skills/idd-close/SKILL.md, plugins/issue-driven-dev/scripts/tests/in-place-correction/test.sh, plugins/issue-driven-dev/rules/append-vs-modify.md, plugins/issue-driven-dev/CLAUDE.md, plugins/issue-driven-dev/README.md, plugins/issue-driven-dev/CHANGELOG.md, plugins/issue-driven-dev/.claude-plugin/plugin.json, .claude-plugin/marketplace.json, README.md, .claude/rules/rules-layering.md
