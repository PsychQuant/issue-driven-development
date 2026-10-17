## Why

Issue 是下游 skill 與日後 session 的記憶。錯誤內容留在原處、只在後面追加 errata，讀的人（尤其是 AI）仍會照錯的做（#351）。現行 `append-vs-modify` 規則與 `idd-comment` errata 流程正好規定「只能追加」，所以要先改規則，再給 `idd-edit` 一條「確認後就地取代、舊版歸檔且 AI 讀不到」的路。

## What Changes

- `append-vs-modify` 規則新增第 8 類 `in-place-correction`：內容確定錯誤、經人確認後，可就地取代，取代前必須歸檔舊版。`verbatim-preserve` 縮小為 `Original text` 引用區塊與第三方原話。
- `idd-edit` 新增 `--correct` 模式：目標可以是 comment（`comment:<id>`）或 issue 正文（`issue:<N>`，只接受 `--section`）。取代前由 helper 歸檔舊版，正文只留帶 `backup-id` 的標記。
- 歸檔位置 `.claude/.idd/archive/edits/<backup-id>.md`：不進 git（寫入前確認已被 ignore，否則拒絕）、檔案權限設為不可讀。還原走 helper 的 `restore` 子命令，內容不經過 stdout。
- IDD plugin 新增 PreToolUse hook：Claude 的 Read、Grep、Glob、Edit、Write 與 Bash 只要指向歸檔路徑一律拒絕，並說明原因。
- `idd-comment --type errata` 對你自己的 comment 改走 `idd-edit --correct`（更正被拒絕時改貼 errata）；別人寫的 comment（含 OWNER 由別人執行時、bot）維持只貼更正 comment、不改原文（2026-10-17 使用者決定）。
- `idd-verify`、`idd-diagnose`、`idd-reorganize` 發現 issue 既有內容有錯時，列出更正提議與可直接執行的 `/idd-edit --correct` 指令；只有使用者確認才執行，unattended 只列不做。
- **BREAKING**（行為面）：`idd-comment --type errata` 對自己的 comment 不再追加 errata comment 與頂端警示，改為就地取代。

## Capabilities

### New Capabilities

- `in-place-correction`: `idd-edit --correct` 的目標、範圍、保護區、確認、標記，以及其他 skill 只能提議的規則
- `correction-archive`: 歸檔的位置、命名、不進 git 與不可讀的保證、還原，以及擋讀取的 hook

### Modified Capabilities

- `append-vs-modify-discipline`: 封閉列舉由 7 類改為 8 類；`verbatim-preserve` 範圍縮小；`--correct` 不接受 `--override-user-content`

## Impact

- Affected specs: `in-place-correction`（新）、`correction-archive`（新）、`append-vs-modify-discipline`（修改）
- Affected code:
  - New: plugins/issue-driven-dev/hooks/archive-read-guard.py, plugins/issue-driven-dev/scripts/tests/correction-archive/test.sh, plugins/issue-driven-dev/scripts/tests/in-place-correction/test.sh
  - Modified: plugins/issue-driven-dev/rules/append-vs-modify.md, plugins/issue-driven-dev/scripts/idd-edit-helper.py, plugins/issue-driven-dev/skills/idd-edit/SKILL.md, plugins/issue-driven-dev/skills/idd-comment/SKILL.md, plugins/issue-driven-dev/skills/idd-verify/SKILL.md, plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md, plugins/issue-driven-dev/skills/idd-reorganize/SKILL.md, plugins/issue-driven-dev/hooks/hooks.json, plugins/issue-driven-dev/CHANGELOG.md, plugins/issue-driven-dev/.claude-plugin/plugin.json, .gitignore
- Related issues: #351（本 change）、#347（`idd-edit` 編輯正文；本 change 只實作 `--correct` 的正文目標，其餘模式留在 #347）
