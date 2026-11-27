**GitHub-side tracker**: #607（也涵蓋 #610）

## Why

設了停止模式時，`close-stage.py next` 只看一輪的計數（Blocking、In-scope fix、LOW）。覆蓋率行與 reviewers 行完不完整，只有 close stage 的 `merge_gate` 在 `next` 回答之後才檢查。於是一輪 0 Blocking、覆蓋率不完整的報告，`next` 回 stop 並 merge，close stage 卻拒絕合併，迴圈已經停了（#607；#610 是 `early` 的同一件事）。

## What Changes

- `scripts/close-stage.py`：gate 記錄一輪時，連同報告的覆蓋率行與 reviewers 行是否完整一起記下；`merge_gate` 的訊息「has no a complete …」改成「lacks a complete …」。
- `scripts/lib/stopmode.py`：覆蓋率行不完整（或沒有記錄）在每種模式的規則裡都算一個 Blocking，to-fix count 也算；reviewers 行不完整時，原本會合併的停止改成不合併並說明原因。
- 測試：`scripts/tests/close-stage/scenarios.sh` 新增兩組；`scripts/tests/stop-mode-log/test.sh` 的 round fixture 補上兩個欄位。
- 規格 `idd-pr-hitl-modes`：停止模式那個 requirement。

## Non-Goals

- 沒有停止模式的 run 不變（照舊由 gate 的 `clean` 判定，`clean` 本來就要求覆蓋率完整）。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：一個 requirement。

## Impact

- Affected specs: `idd-pr-hitl-modes`
- Affected code: plugins/issue-driven-dev/scripts/close-stage.py, plugins/issue-driven-dev/scripts/lib/stopmode.py, plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh, plugins/issue-driven-dev/scripts/tests/stop-mode-log/test.sh
