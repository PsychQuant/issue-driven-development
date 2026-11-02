# 2026-11-02 本機 CI 閘門（#465）

- 新增 `scripts/idd-ci-gate.sh`：對指定 commit 建乾淨 checkout、跑本機設定的指令，以結束碼回報，並產出紀錄。
- config 新增 `ci` 欄位（`mode`、`command`、`timeout_seconds`）。指令只來自未追蹤的 `.claude/.idd/local.json`。
- **預設行為改變**：`idd-all` 在 verify 之後跑這個閘門。沒設定 `ci.command` 的 repo 會停下來：attended 問指令，unattended 回報。要沿用遠端 CI，設 `ci.mode` 為 `remote`。
- 本機模式下遠端 CI 紅燈只回報、不擋合併；`idd-close` Step 6.5 在發版前仍要求遠端 check 綠燈。
- 安全修正：config 只讀 repo 根目錄、不往上層找；被追蹤（含大小寫變體）、符號連結、別人的或他人可寫都拒絕。紀錄預設不含指令與輸出，要附輸出末段設 `ci.post_output_tail`。
- 再修：`.claude` 是 submodule、子目錄裡的假 git 目錄、repo 的 hook、外洩的 `GIT_*` 變數都不再能讓 gate 執行 repo 提供的指令；指令改寫自己的 config 時結果作廢。`idd-close` 發版前也看舊式 commit status，零個 check 要使用者確認。
