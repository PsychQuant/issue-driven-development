**GitHub-side tracker**: #623（verify 第 7 輪的修正）

## Why

#623 第 7 輪 verify 找到：刪不掉舊答案而改成清空時，只用 `fstat` 檢查型別與連結數，沒有確認開到的就是先前用 `lstat` 找到的那個檔案，名稱在兩步之間被換成另一個檔案時會把它清空；讀取的測試沒有驗證成功的那一次開檔確實用固定檔名與受防護的目錄描述符；SKILL.md 的註解把清理寫成一定成功。

## What Changes

- `close-stage.py`：清空前比對 `lstat` 與 `fstat` 的裝置與 inode，不同就不清空並回報舊答案可能還在。
- `skills/idd-all/SKILL.md`：Phase 4 的註解說清理是盡力而為，做不到時會警告。
- 測試：刪除前名稱被換成另一個檔案；成功的讀取以固定檔名相對於目錄描述符開檔。
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
- Affected code: plugins/issue-driven-dev/scripts/close-stage.py, plugins/issue-driven-dev/skills/idd-all/SKILL.md, plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh, plugins/issue-driven-dev/scripts/tests/stop-mode-log/test.sh
