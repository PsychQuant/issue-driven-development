## Why

討論一張 issue 時，問題本身、診斷、以及新的資訊或決定都會改變，但 IDD 目前只會往下追加 comment：`/idd-edit --correct` 每次都要使用者確認，偵測到錯誤的 skill 只列出 `### Proposed Corrections`（unattended 時只列不做），`idd-diagnose` 要調整診斷時另貼一則修正 comment。結果 issue 正文和 Diagnosis 停在第一版，讀者要讀完整串才知道現況；#399 就這樣累積了五份沒套用的更正稿。#424 定案（2026-10-25）：由 AI 判斷改變屬於哪一類並自己寫回，不再停下來確認。

## What Changes

- 新增 plugin 規則 `plugins/issue-driven-dev/rules/issue-write-back.md`：討論中的改變分三類寫回——問題的改變寫回 issue 正文的段落；診斷的改變寫回 Diagnosis 留言的段落，連帶更新 Implementation Plan 受影響的段落，並在既有 verify 報告開頭加一行指向更正後的診斷；新的資訊與決定新增一則 comment。觸發來源是使用者在 session 裡的討論，以及任何人在 GitHub 上的 comment（下一次被讀到時）。只改寫自己的內容，別人的內容改貼 errata 或 correction comment。每次寫回都在對話裡回報，寫回前照常做 privacy 自審。
- SessionStart 注入加一行提醒，讓 skill 之外的討論也套用；IDD 的 SessionStart 輸出維持在 5 行以內。
- **BREAKING** `/idd-edit --correct` 不再用 AskUserQuestion 確認：預覽與 diff 改成在對話裡回報後直接套用。`--prepend-note` 在目標通過 `--correct` 的嚴格作者檢查時同樣不確認；`--append`、`--replace` 維持確認。privacy 自審、#272 閘、寫入前重讀、歸檔照常執行。
- **BREAKING** `idd-verify`、`idd-diagnose`、`idd-reorganize` 偵測到已發表的內容有錯時直接套用：自己的內容走 `/idd-edit --correct`，別人的內容自動貼 errata 或 correction comment；報告的 `### Proposed Corrections` 改為 `### Applied Corrections`，attended 與 unattended 行為相同。
- `idd-diagnose` Step 4 Stage 1：診斷要調整時用 `/idd-edit --correct` 改 Diagnosis 留言本身，不再追加修正 comment。
- plugin 版本 3.7.0，CHANGELOG 與 README 同步。

## Capabilities

### New Capabilities

- `issue-write-back`: 討論中的改變依類別寫回 issue 正文、Diagnosis 留言或新的 comment，由 AI 判斷、不確認、只改自己的內容、每次回報。

### Modified Capabilities

- `in-place-correction`: `/idd-edit --correct` 改為回報後直接套用、不再確認；偵測到錯誤的 skill 由「只提議」改為「直接套用並回報」。

## Impact

- Affected specs: `issue-write-back`（新增）、`in-place-correction`（修改）
- Affected code:
  - New: plugins/issue-driven-dev/rules/issue-write-back.md, plugins/issue-driven-dev/scripts/tests/issue-write-back/test.sh
  - Modified: plugins/issue-driven-dev/hooks/session-start-commit-rule.sh, plugins/issue-driven-dev/scripts/tests/session-start-commit-rule/test.sh, plugins/issue-driven-dev/skills/idd-edit/SKILL.md, plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md, plugins/issue-driven-dev/skills/idd-verify/SKILL.md, plugins/issue-driven-dev/skills/idd-reorganize/SKILL.md, plugins/issue-driven-dev/skills/idd-comment/SKILL.md, plugins/issue-driven-dev/scripts/tests/in-place-correction/test.sh, plugins/issue-driven-dev/rules/append-vs-modify.md, plugins/issue-driven-dev/README.md, plugins/issue-driven-dev/CHANGELOG.md, plugins/issue-driven-dev/.claude-plugin/plugin.json, .claude-plugin/marketplace.json, README.md
