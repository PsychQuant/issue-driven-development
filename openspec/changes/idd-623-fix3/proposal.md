**GitHub-side tracker**: #623（verify 第 3 輪的修正）

## Why

#623 第 3 輪 verify 找到：`mkstemp(dir=".")` 把目錄變成絕對路徑，暫存檔的建立、搬移與清理沒有全程用相對名稱；`--gate-file` 的檢查先以字串折疊 `..`，連結後面的 `..` 指到狀態目錄外時，只要狀態目錄裡有正式的答案就會寫出紀錄；狀態目錄開不了或進不去時，警告沒有說舊答案可能還在，而且回到原本目錄需要讀取權限；硬連結的 Example 沒有比對 stdout 與結束碼。

## What Changes

- `close-stage.py`：暫存檔用相對名稱、`O_CREAT | O_EXCL` 建立；狀態目錄用不了時警告舊答案可能還在；`inside` 在讀不到原本目錄時改用路徑回去。
- `stop-mode-log.py`：`--gate-file` 的目錄部分跟著每個連結解到底再比對。
- 測試：狀態目錄有正式答案時，連結後面的 `..` 仍被拒絕；連結的狀態目錄的警告；硬連結的 stdout 與結束碼。
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
