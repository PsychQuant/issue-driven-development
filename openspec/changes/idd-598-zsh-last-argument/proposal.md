**GitHub-side tracker**: #598

## Why

`/idd-all` Step 0.2、`/idd-all-chain` Step 0.1 與 `/idd-clarify` Step 1 用 `for ((i=0; i<${#ARGS[@]}; i++))` 讀參數。zsh 的陣列從 1 起算，所以在 zsh（Claude Code Bash 工具的 shell）下最後一個參數永遠讀不到：放在最後的 `--review`、`--pr`、`--stop=…`、`--cwd=…` 會被靜默丟掉，要求停在 verified 的 run 可能走到 close stage。`/idd-all-chain` 另外用 `${ROOT_ISSUES_SORTED[0]}` 取最小的 root，在 zsh 下是空的；它的迴圈也沒有自己設 `ARGS`。

## What Changes

- 三段解析改用 `while [ $# -gt 0 ]; … shift` 讀參數，不用陣列索引；每個旗標的意思、衝突檢查與取值規則不變。
- `/idd-all-chain` 取最小的 root 不再用從 0 起算的索引。
- 三段都放在 `# >>> arg-parse` 與 `# <<< arg-parse` 標記之間，讓測試能在 bash 與 zsh 下各跑一次。

## Non-Goals

- 不加新旗標，也不改任何旗標的意思。
- 這三個 skill 的其他 bash 區塊不在這裡檢查 zsh（`idd-all-chain` 的 `${QUEUE[0]}` 另開 issue）。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：新增 requirement「idd-all reads every argument in bash and zsh」。
- `idd-all-chain`：新增 requirement「idd-all-chain reads every argument in bash and zsh」（含最小的 root）。
- `idd-clarify`：新增 requirement「idd-clarify reads every argument in bash and zsh」。

## Impact

- Affected specs: `idd-pr-hitl-modes`, `idd-all-chain`, `idd-clarify`
- Affected code:
  - Modified: plugins/issue-driven-dev/skills/idd-all/SKILL.md, plugins/issue-driven-dev/skills/idd-all-chain/SKILL.md, plugins/issue-driven-dev/skills/idd-clarify/SKILL.md
  - New: plugins/issue-driven-dev/scripts/tests/skill-arg-parsing/test.sh
  - Removed: none
