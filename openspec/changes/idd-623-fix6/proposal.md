**GitHub-side tracker**: #623（verify 第 6 輪的修正）

## Why

#623 第 6 輪 verify 找到：`append` 用 `os.stat` 看路徑解不解得開，再用另一次 `realpath` 看解到哪裡，兩次之間路徑改變時，解不開的參數仍會通過；只能穿越的祖先目錄的測試沒有分平台的開檔旗標與帳號的權限；看起來像旗標的值那一案只檢查檔案還在，沒有比對內容。

## What Changes

- `stop-mode-log.py`：`--gate-file` 的目錄部分只由系統解析一次（`os.stat`），以裝置與 inode 和受防護的目錄描述符比對。
- 測試：第二次查詢與第一次不一致的情況；只能穿越的祖先目錄依平台旗標與帳號能不能列出決定預期；看起來像旗標的值比對內容。
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
- Affected code: plugins/issue-driven-dev/scripts/stop-mode-log.py, plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh, plugins/issue-driven-dev/scripts/tests/stop-mode-log/test.sh
