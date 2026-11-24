**GitHub-side tracker**: #603（verify 第 2 輪的修正）

## Why

#603 verify 第 2 輪（Claude reviewers）：`GATE_JSON` 在 gate 區塊設定，`append` 在另一個 Bash 呼叫裡讀它；shell 沒保留變數時傳進去的是空字串，被當成「沒有被取代」，第 1 輪的 Blocking 從最常見的路徑回來。0600 的測試用 `stat -f %Lp`，在 GNU coreutils（CI 的 ubuntu-latest）上意思不同，整套測試在 CI 會失敗。另外：不是 UTF-8 的一行讓 `summary` 整個崩潰；文字輸出只跳脫理由，模式與 to-fix 序列沒有跳脫，C1 控制字元也沒擋。

## What Changes

- `scripts/stop-mode-log.py`：`--gate` 給了但是空的，就不寫並在 stderr 說明；紀錄以 bytes 逐行讀，解碼失敗的行算成讀不了；文字輸出的模式、to-fix 序列與理由都跳脫 C0、C1 控制字元。
- `skills/idd-all/SKILL.md` Phase 4：`next` 區塊說明 `GATE_JSON` 遺失時先從 gate 區塊的輸出補回。
- 測試 `scripts/tests/stop-mode-log/test.sh`：檔案權限改用 python 讀；補上空的 `--gate`、遺失 `GATE_JSON` 的區塊、不是 UTF-8 的行、非物件的 rounds、預設紀錄路徑、模式與 to-fix 的跳脫。
- 規格 `idd-pr-hitl-modes`：上述行為；寫明在 gate 讀 run state 之前就被取代的 run 這裡分不出來，要 #618 的 run identity。

## Non-Goals

- 在 verify 期間就被取代（gate 讀到的已是新 run 的身分）：要 init 時記下的 run identity，屬於 #618。
- 以 fix 結束的 run（安全性中止、自動修正失敗）不留紀錄：列 follow-up。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：一個 requirement。

## Impact

- Affected specs: `idd-pr-hitl-modes`
- Affected code: plugins/issue-driven-dev/scripts/stop-mode-log.py, plugins/issue-driven-dev/skills/idd-all/SKILL.md, plugins/issue-driven-dev/scripts/tests/stop-mode-log/test.sh
