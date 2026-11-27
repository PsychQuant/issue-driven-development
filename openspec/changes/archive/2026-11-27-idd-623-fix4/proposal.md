**GitHub-side tracker**: #623（verify 第 4 輪的修正）

## Why

#623 第 4 輪 verify 找到：gate 的參數被拒時在寫答案之前就結束，上一輪的答案還在，下一個區塊可能把它當成這一輪的；`realpath` 不嚴格，`missing/..` 這種系統解不開的路徑也會通過檢查；暫存檔的權限受 umask 影響，遮掉擁有者的讀取時 append 讀不到。

## What Changes

- `close-stage.py`：參數被拒但 `--cwd`、`--issue` 可用且帶了 `--write-answer yes` 時，照寫入失敗的方式移除或清空舊答案（空值讓 `parse` 整行拒絕，所以這三個旗標另外讀）；暫存檔 `fchmod` 成 0600。
- `stop-mode-log.py`：`--gate-file` 的目錄部分要能由系統解開（`os.stat`），解不開就當成讀不到。
- 測試：被拒的參數（空的 `--base`）、umask 477、經過不存在目錄的路徑。
- 規格 `idd-pr-hitl-modes`：同一個 requirement 與兩個 Example。

## Non-Goals

- 第 3–6、8–10、12–16 列（另開 follow-up，或交給 #622／#618）。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：同一個 requirement。

## Impact

- Affected specs: `idd-pr-hitl-modes`
- Affected code: plugins/issue-driven-dev/scripts/close-stage.py, plugins/issue-driven-dev/scripts/stop-mode-log.py, plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh, plugins/issue-driven-dev/scripts/tests/stop-mode-log/test.sh
