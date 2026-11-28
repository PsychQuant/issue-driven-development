**GitHub-side tracker**: #623（verify 第 5 輪的修正）

## Why

#623 第 5 輪 verify 找到：參數被拒後的補救掃描逐個 token 看，會把另一個選項的值當成 `--write-answer`，而同一個旗標給兩次時又把它排除（HIGH）；`open_state_dir` 逐層以讀取權限開目錄，祖先目錄只能穿越、不能列出時，gate 的讀寫都失效；Example 用「最後兩項」指稱，加了新案例之後指錯了；`fchmod` 失敗時暫存檔的描述符沒有關。

## What Changes

- `close-stage.py`：補救掃描照旗標與值成對讀，同一個旗標給兩次且值相同算一次；目錄改以只需搜尋權限的方式開（Linux `O_PATH`、macOS `O_SEARCH`，都沒有時才用讀取）；暫存檔先交給 `fdopen` 再 `fchmod`。
- 測試：看起來像旗標的值、旗標給兩次、只能穿越的祖先目錄（寫入端與讀取端）。
- 規格 `idd-pr-hitl-modes`：同一個 requirement 與兩個 Example，案例改成直接指名。

## Non-Goals

- 第 3–6、8–10、12–16 列（另開 follow-up，或交給 #622／#618）。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：同一個 requirement。

## Impact

- Affected specs: `idd-pr-hitl-modes`
- Affected code: plugins/issue-driven-dev/scripts/close-stage.py, plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh, plugins/issue-driven-dev/scripts/tests/stop-mode-log/test.sh
