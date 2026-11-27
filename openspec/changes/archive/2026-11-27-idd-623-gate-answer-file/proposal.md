**GitHub-side tracker**: #623（第一項：第 1、2 列，連同第 7 列）

## Why

Phase 4 的 gate 區塊用 shell 的重導向寫 `idd-all-gate-<N>.json`：重導向會跟著那個路徑上的 symbolic link 走，也照預設 umask 建檔；同一個目錄的其他檔都經過 `close-stage.py` 的防護（`state_dir`、`safe_path`、`mkstemp` + `os.replace`）。讀的那一端，`stop-mode-log.py` 的 `gate_answer` 用一般的 `open()` 讀 `--gate-file`，同樣會跟著連結走，也讀任何給它的路徑（#623 第 1、2 列）。寫入失敗時舊的答案留著（第 7 列）。

## What Changes

- `scripts/close-stage.py`：`gate --write-answer yes` 經過 run state 的防護寫答案檔；遇到連結就拒絕、不跟著走；寫入失敗時刪掉舊的答案、只警告；stdout 與結束碼不變。
- `skills/idd-all/SKILL.md`：gate 區塊改成帶 `--write-answer yes`，拿掉重導向。
- `scripts/stop-mode-log.py`：`--gate-file` 只接受這張 issue 在 state 目錄裡的一般檔案，用 `O_NOFOLLOW` 開。
- 測試：close-stage 與 stop-mode-log 兩個套件。
- 規格 `idd-pr-hitl-modes`：同一個 requirement 加一個 Scenario 與三個 Example。

## Non-Goals

- #623 的其他列另開一張 follow-up；第 6、9、16 列跟 #622／#618。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：一個 requirement。

## Impact

- Affected specs: `idd-pr-hitl-modes`
- Affected code: plugins/issue-driven-dev/scripts/close-stage.py, plugins/issue-driven-dev/scripts/stop-mode-log.py, plugins/issue-driven-dev/skills/idd-all/SKILL.md, plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh, plugins/issue-driven-dev/scripts/tests/stop-mode-log/test.sh
