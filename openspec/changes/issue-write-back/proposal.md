## Why

討論一張 issue 時，問題本身、診斷、以及新的資訊或決定都會改變，但 IDD 目前只會往下追加 comment：`/idd-edit --correct` 每次都要使用者確認，偵測到錯誤的 skill 只列出 `### Proposed Corrections`（unattended 時只列不做），`idd-diagnose` 要調整診斷時另貼一則修正 comment。結果 issue 正文和 Diagnosis 停在第一版，讀者要讀完整串才知道現況；#399 就這樣累積了五份沒套用的更正稿。#424 定案（2026-10-25）：由 AI 判斷改變屬於哪一類並自己寫回，不再停下來確認。

## What Changes

- 新增 plugin 規則 `plugins/issue-driven-dev/rules/issue-write-back.md`：討論中的改變分三類寫回——問題的改變寫回 issue 正文的段落；診斷的改變寫回 Diagnosis 留言的段落，連帶更新 Implementation Plan 受影響的段落，並在既有 verify 報告開頭加一行指向更正後的診斷；新的資訊與決定新增一則 comment。觸發來源是使用者在 session 裡的討論，以及別人在 GitHub 上的 comment（下一次被讀到時；見下方的信任邊界）。只改寫自己的內容，別人的內容改貼 errata 或 correction comment。每次寫回都在對話裡回報，寫回前照常做 privacy 自審。
- SessionStart 注入加一行提醒，讓 skill 之外的討論也套用；IDD 的 SessionStart 輸出維持在 5 行以內。
- **BREAKING** `/idd-edit --correct` 不再用 AskUserQuestion 確認：預覽與 diff 改成在對話裡回報後直接套用。`--prepend-note` 在目標通過 `--correct` 的嚴格作者檢查時同樣不確認；`--append`、`--replace` 維持確認。privacy 自審、#272 閘、寫入前重讀、歸檔照常執行。
- **BREAKING** `idd-verify`、`idd-diagnose`、`idd-reorganize` 偵測到已發表的內容有錯時直接套用：自己的內容走 `/idd-edit --correct`（範圍見下方四項決定），別人的內容只列出；報告的 `### Proposed Corrections` 改為 `### Applied Corrections`，attended 與 unattended 行為相同。
- `idd-diagnose` Step 4 Stage 1：診斷要調整時用 `/idd-edit --correct` 改 Diagnosis 留言本身，不再追加修正 comment。
- **verify 第 1 輪後的四項決定（2026-11-03）：** 別人的 comment 只信 OWNER、MEMBER、COLLABORATOR，AI 要自己查證，`### Type`、`### Complexity` 不由 comment 改；偵測 skill 只改 Diagnosis 的事實（`### Root Cause / Analysis`、`### Impact`、`### Risks`），主 agent 親自用 repo 證據查證，其餘一律列出不改；明確定案才寫回，假設與提問不算，已關閉的 issue 不改；`--correct` 改寫的段落尾留一行可見文字。
- 不問的路徑收窄：隱私自審在任何等級命中都停（attended 問、unattended 捨棄），沒有寫入權的 repo 照舊確認；`/idd-edit` 在 unattended 不再提問，捨棄時記下原因。
- 新增 `scripts/writeback-candidates.py`，`idd-diagnose`、`idd-plan`、`idd-update` 用它找出別人的新 comment。
- 診斷更正讓既有實作的前提不成立，或問題改變時，改走 `idd-reorganize`。
- **verify 第 2 輪後的兩項決定（2026-11-03，comment 6611450882）：** 別人的 comment 只在 `idd-diagnose`、`idd-plan`、`idd-implement` 開始時看，`idd-update` 與 `idd-verify` 不看；`idd-verify` 不自動改任何東西，已發表內容的錯誤一律列成 finding；`idd-diagnose`、`idd-reorganize` 的自動更正只限 `### Type` 是 bug、只改 Diagnosis，Implementation Plan 列出不改。
- 交給人的更正（`listed` 且落在 Expected、範圍、checklist、Type、Complexity）經 `idd-update` 進 `### Blocking`，unattended 的 actionability gate 會停；`idd-update` 只採受信任作者的 comment。
- plugin 版本 3.7.0，CHANGELOG 與 README 同步。

## Capabilities

### New Capabilities

- `issue-write-back`: 討論中的改變依類別寫回 issue 正文、Diagnosis 留言或新的 comment，由 AI 判斷、不確認、只改自己的內容、每次回報。

### Modified Capabilities

- `in-place-correction`: `/idd-edit --correct` 改為回報後直接套用、不再確認；偵測到錯誤的 skill 由「只提議」改為「在封閉範圍內直接套用並回報」。
- `append-vs-modify-discipline`: `in-place-correction` 分類不再要求確認，改寫處留可見文字。
- `user-rule-injection`: SessionStart 多一行寫回提醒，印出規則檔的安裝路徑。

## Impact

- Affected specs: `issue-write-back`（新增）、`in-place-correction`（修改）、`append-vs-modify-discipline`（修改）、`user-rule-injection`（修改）
- Affected code:
  - New: plugins/issue-driven-dev/scripts/writeback-candidates.py, plugins/issue-driven-dev/scripts/tests/writeback-candidates/test.sh, plugins/issue-driven-dev/rules/issue-write-back.md, plugins/issue-driven-dev/scripts/tests/issue-write-back/test.sh
  - Modified: plugins/issue-driven-dev/scripts/idd-edit-helper.py, plugins/issue-driven-dev/hooks/archive-read-guard.py, plugins/issue-driven-dev/skills/idd-plan/SKILL.md, plugins/issue-driven-dev/skills/idd-implement/SKILL.md, plugins/issue-driven-dev/skills/idd-update/SKILL.md, plugins/issue-driven-dev/skills/idd-close/SKILL.md, plugins/issue-driven-dev/hooks/session-start-commit-rule.sh, plugins/issue-driven-dev/scripts/tests/session-start-commit-rule/test.sh, plugins/issue-driven-dev/skills/idd-edit/SKILL.md, plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md, plugins/issue-driven-dev/skills/idd-verify/SKILL.md, plugins/issue-driven-dev/skills/idd-reorganize/SKILL.md, plugins/issue-driven-dev/skills/idd-comment/SKILL.md, plugins/issue-driven-dev/scripts/tests/in-place-correction/test.sh, plugins/issue-driven-dev/rules/append-vs-modify.md, plugins/issue-driven-dev/README.md, plugins/issue-driven-dev/CHANGELOG.md, plugins/issue-driven-dev/.claude-plugin/plugin.json, .claude-plugin/marketplace.json, README.md
