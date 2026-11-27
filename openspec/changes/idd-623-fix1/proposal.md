**GitHub-side tracker**: #623（verify 第 1 輪的修正）

## Why

#623 第 1 輪 verify 找到：`append` 檢查的是正規化後的路徑，開的卻是原本的參數，`..` 接在連結後面時兩者會到不同的地方；先阻塞地開檔再檢查型別，沒有寫入端的 FIFO 會讓它卡住；寫入與刪除都失敗時，舊的答案仍可能被讀到；寫入失敗的測試直接呼叫 helper，沒有比對 `gate` 的 stdout 與結束碼；讀取的測試沒有分開驗證目錄限制與兩種拒絕訊息。

## What Changes

- `stop-mode-log.py`：在檢查過的狀態目錄裡用固定檔名開檔（`dir_fd`），加上 `O_NONBLOCK`，先 `fstat` 再讀。
- `close-stage.py`：寫入失敗時刪不掉舊答案就把它清空；兩者都不行時警告說舊答案還在。
- 測試：注入的失敗經過 `cmd_gate`，比對完整 stdout 與結束碼；同名檔在狀態目錄外、`..` 接在連結後、FIFO、兩種拒絕訊息。
- 規格 `idd-pr-hitl-modes`：同一個 requirement 與兩個 Example。

## Non-Goals

- 第 3–5、8–10、12、13、16 列（另開 follow-up，或交給 #622／#618）。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：同一個 requirement。

## Impact

- Affected specs: `idd-pr-hitl-modes`
- Affected code: plugins/issue-driven-dev/scripts/stop-mode-log.py, plugins/issue-driven-dev/scripts/close-stage.py, plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh, plugins/issue-driven-dev/scripts/tests/stop-mode-log/test.sh
