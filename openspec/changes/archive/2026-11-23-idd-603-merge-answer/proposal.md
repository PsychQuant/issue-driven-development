**GitHub-side tracker**: #603

## Why

`idd-603-stop-mode-record` 記下的 `merge` 是 `next` 的回答，`summary` 卻印成「merged」。#607 之下兩者會不同：`next` 答合併、close stage 仍可能因 coverage 停下（#598 的 PR #609 就是這樣），照舊的字面會把沒合併的 run 算成合併。

## What Changes

- 紀錄的欄位改名 `next_merge`；`summary` 的 JSON 與文字改成「`next` 答合併」的次數，不寫 merged。
- `references/config-protocol.md` 的說明同步。

## Non-Goals

- 不讀 close stage 的結果（合併後是否需要 follow-up 本來就不在範圍內）。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：「A run with a stop mode leaves a record of how its verify loop ended」。

## Impact

- Affected specs: `idd-pr-hitl-modes`
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/stop-mode-log.py, plugins/issue-driven-dev/scripts/tests/stop-mode-log/test.sh, plugins/issue-driven-dev/references/config-protocol.md
  - New: none
  - Removed: none
