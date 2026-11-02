## Context

`main` 上的 IDD 沒有讀 CI 狀態的閘門，`idd-all` 不自動合併。#392 的 close stage 在另一條尚未合併的分支上實作，驗證到第 6 輪；它的 CI 檢查程式本 change 撰寫時讀不到。維護者已定：所有 repo 預設本機、發版前仍要遠端綠燈、沒有本機指令時停下來問。

## Goals / Non-Goals

**Goals:**

- 一個可獨立呼叫的閘門，`idd-all` 與之後的 close stage 共用
- 結果不受工作目錄內未提交檔案或殘留建置物影響
- clone 別人的 repo 不會因此自動執行該 repo 的程式

**Non-Goals:**

- 與遠端環境等價
- 併入 #392 的 close stage 實作

## Decisions

### 閘門是獨立 script，不是 close stage 的一部分

`idd-ci-gate.sh` 以結束碼為介面。#392 收斂中，把新需求塞進去會拉長它；反過來，兩邊都只依賴結束碼，合併順序不影響。

### 指令只來自本機未追蹤的 config

只讀 walk-up 找到的 `.claude/.idd/local.json`；該檔被 git 追蹤時拒絕採用（exit 4）。這樣「所有 repo 預設本機」不必為別人的 repo 開例外：跑的永遠是這台機器的使用者自己設定的指令。代價是每個 clone 第一次要設定一次。

### 用 detached worktree 當乾淨 checkout

`git worktree add --detach <暫存目錄> <commit>`：不必重新 clone，且只含該 commit 追蹤的檔案。結束後一律移除。

### 逾時預設 3600 秒，算失敗

估計值：依 #465 那批 Linux CI 約 30 分鐘取兩倍；實際跑過幾個 repo 後可由觀察到的最長時間修正。可用 `ci.timeout_seconds` 調整。

### 紀錄只在失敗時帶輸出末段，且先換掉路徑

公開 repo 的 comment 不該含本機路徑，`gh-egress.sh` 也會拒絕 `/Users/<name>`。通過時只記 commit、指令、時間、結束碼；失敗或逾時另帶最後 40 行，`$HOME` 換成 `~`、checkout 路徑換成 `<checkout>`。完整 log 只留本機。

## Implementation Contract

**Behavior**：`idd-ci-gate.sh run --commit <sha> [--cwd <clone>]` 跑閘門；stdout 印 `RESULT=`、`RECORD=<紀錄檔>`、`LOG=<完整 log>`。

**Config**：

```json
{ "ci": { "mode": "local", "command": "bash scripts/ci.sh", "timeout_seconds": 3600 } }
```

`ci` 或 `mode` 缺席視同 `local`。

**結束碼**（封閉列舉）：

| 碼 | RESULT | 意思 |
|---|---|---|
| 0 | pass | 指令結束碼 0 |
| 1 | fail | 指令結束碼非 0 |
| 2 | timeout | 超過逾時，整個 process group 已終止 |
| 3 | not-configured | `mode=local` 且沒有 `command`；指令未執行 |
| 4 | error | 閘門本身無法判定：config 無法解析、被追蹤、`mode` 或逾時值不合法、commit 不存在、checkout 失敗 |
| 10 | remote | `mode=remote`；指令未執行，呼叫端改看遠端 CI |

**Failure modes**：閘門本身出錯一律不算通過。紀錄送不出去（例如 `gh-egress.sh` 拒絕）不改變結果，但要回報。

**Acceptance**：`plugins/issue-driven-dev/scripts/tests/idd-ci-gate/test.sh` 涵蓋每個結束碼、未提交檔案不進 checkout、config 被追蹤時拒絕、暫存 worktree 被移除；`plugins/issue-driven-dev/scripts/run-all-tests.sh` 通過。

**In scope**：script、config 文件、`idd-all` 接線、`idd-close` 發版前檢查。**Out of scope**：close stage、容器隔離、依賴安裝。

## Risks / Trade-offs

- [本機與遠端環境不同] → 合併後 `main` 可能才變紅；遠端紅燈要回報，發版前要綠燈。
- [長時間佔用機器] → 逾時後終止；使用者可選 `mode=remote`。
- [預設改變會讓既有 repo 停下來] → 訊息要指明設定方式與 `mode=remote` 這條退路。
- [輸出末段含未預期的敏感內容] → 仍經 `gh-egress.sh` 與隱私自審；只換路徑不保證其他內容安全。
