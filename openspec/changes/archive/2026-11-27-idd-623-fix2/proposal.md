**GitHub-side tracker**: #623（verify 第 2 輪的修正）

## Why

#623 第 2 輪 verify 找到：讀寫兩端檢查狀態目錄之後又用路徑重新解析，檢查與開啟沒有綁在同一個目錄；清空舊答案時先以 `O_TRUNC` 開檔再驗證，硬連結的檔案會連另一個路徑一起被清空；讀不到舊檔的狀態時說成沒有舊答案；測試沒有狀態目錄本身是連結、以及移除與清空都失敗的情況。

## What Changes

- `close-stage.py`：新的 `open_state_dir` 逐層不跟著連結開啟狀態目錄；`inside` 以那個目錄為工作目錄（macOS 的 `os.replace` 不支援 `dir_fd`），寫入、移動、刪除與清空都用相對名稱；`clear_old_gate_answer` 先 `lstat`，清空前以 `fstat` 確認是只有一個連結的一般檔，讀不到狀態時回報舊答案可能還在。
- `stop-mode-log.py`：用 `open_state_dir` 取得目錄。
- 測試：狀態目錄是連結、移除與清空都失敗、硬連結的舊答案；清空時的警告。
- 規格 `idd-pr-hitl-modes`：同一個 requirement 與 gate 的 Example。

## Non-Goals

- 第 3–5、8–10、12–16 列（另開 follow-up，或交給 #622／#618）。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：同一個 requirement。

## Impact

- Affected specs: `idd-pr-hitl-modes`
- Affected code: plugins/issue-driven-dev/scripts/close-stage.py, plugins/issue-driven-dev/scripts/stop-mode-log.py, plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh
