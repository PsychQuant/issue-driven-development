# 2026-11-02 本機 CI 閘門（#465）

- 新增 `scripts/idd-ci-gate.sh`：對指定 commit 建乾淨 checkout、跑本機設定的指令，以結束碼回報，並產出紀錄。
- config 新增 `ci` 欄位（`mode`、`command`、`timeout_seconds`）。指令只來自未追蹤的 `.claude/.idd/local.json`。
- **預設行為改變**：`idd-all` 在 verify 之後跑這個閘門。沒設定 `ci.command` 的 repo 會停下來：attended 問指令，unattended 回報。要沿用遠端 CI，設 `ci.mode` 為 `remote`。
- 本機模式下遠端 CI 紅燈只回報、不擋合併；`idd-close` Step 6.5 在發版前仍要求遠端 check 綠燈。
