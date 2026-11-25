**GitHub-side tracker**: #603（verify 第 1 輪的修正）

## Why

#603 verify 第 1 輪（Claude reviewers）：#602 合併之後，另一個 `/idd-all` 取代了 run state 時，`next` 或 gate 會回 `replaced: true`。`append` 這時讀到的是新 run 的 state，把舊 run 的結局記在新 run 的 `created_at` 與模式底下，requirement 寫的是「拿到這個回答的那個 run」，不允許這樣。同一輪另外找到：`summary` 遇到解析得了但形狀不對的行會崩；紀錄檔建成 0644，而且會跟隨那個路徑上的 symbolic link；存下的理由原樣帶著控制字元印到終端機；`append` 會把 bytecode 寫進 plugin 目錄；`config-protocol.md` 沒有列 `decided`。

## What Changes

- `scripts/stop-mode-log.py`：`append` 多收 `--gate <gate 的 JSON>`，`next` 或 gate 的回答帶 `replaced` 時什麼都不寫；紀錄檔以 `O_NOFOLLOW` 開啟、建成 0600；`summary` 把形狀不對的行算成讀不了的行，理由裡的控制字元跳脫後才印；不寫 bytecode。
- `skills/idd-all/SKILL.md` Phase 4：`next` 區塊傳 `--gate "${GATE_JSON:-}"`。
- `references/config-protocol.md`：紀錄的欄位加上 `decided`、interaction、`review`、`in_chain`；檔案 0600；被取代的 run 不寫。
- 測試：`scripts/tests/stop-mode-log/test.sh`。
- 規格 `idd-pr-hitl-modes`：上面那個 requirement。

## Non-Goals

- 紀錄的 key 維持（repository、issue、`created_at`）：同一秒開始的兩個 run 只可能是被取代的 run，而它現在不寫。
- `exhaustive-all` 的 to-fix 數不含 LOW 的 In-scope：那是 #595 的定義，這裡沿用，原始計數都有記下。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：一個 requirement。

## Impact

- Affected specs: `idd-pr-hitl-modes`
- Affected code: plugins/issue-driven-dev/scripts/stop-mode-log.py, plugins/issue-driven-dev/skills/idd-all/SKILL.md, plugins/issue-driven-dev/references/config-protocol.md, plugins/issue-driven-dev/scripts/tests/stop-mode-log/test.sh
