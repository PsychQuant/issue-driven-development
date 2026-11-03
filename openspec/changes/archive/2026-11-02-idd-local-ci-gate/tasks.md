## 1. 閘門 script

- [x] 1.1 `idd-ci-gate.sh` 解析 config 並回報 not-configured、remote、error（含 config 被追蹤、mode 與逾時值不合法）：`scripts/tests/idd-ci-gate/test.sh` 對應案例先失敗後通過（Requirements: Local mode is the default; The command comes only from untracked local configuration）
- [x] 1.2 [after: 1.1] 在 detached worktree 執行指令並回報 pass、fail、timeout，逾時終止整個 process group，每條路徑都移除 worktree：測試涵蓋未提交檔案不進 checkout、背景子程序被終止、`git worktree list` 無殘留（Requirements: The command runs from a clean checkout of the named commit; Exit codes report the result）
- [x] 1.3 [after: 1.2] 產出紀錄：通過不含輸出，失敗與逾時含最後 40 行且路徑已換掉：測試斷言紀錄不含家目錄（Requirements: Each run produces a record）

## 2. 文件

- [x] 2.1 [after: 1.1] `references/config-protocol.md` 記載 `ci` 欄位、預設值與 `mode=remote` 退路：`scripts/tests/doc-sync-sweep` 與人工核對欄位名稱一致

## 3. 接線

- [x] 3.1 [after: 1.3] `idd-all` 在 verify 後呼叫閘門，依結束碼繼續或停下，紀錄經 `gh-egress.sh` 貼出；exit 3 時 attended 問指令、unattended 停下回報：SKILL 內容審查，並在一個測試 repo 手動跑一次 exit 0 與 exit 3（Requirements: idd-all stops at the gate unless it passes）
- [x] 3.2 [after: 3.1] 本機模式下遠端 check 紅燈時，報告列出該 check 且不擋合併：SKILL 內容審查（Requirements: Remote CI reports but does not block merging in local mode）
- [x] 3.3 `idd-close` distribution sync 在遠端 check 失敗、進行中或讀不到時停在發版前並回報：SKILL 內容審查，並以 `gh pr checks` 的輸出手動核對三種狀態（Requirements: Releases still require green remote CI）

## 4. 收尾

- [x] 4.1 [after: 1.3, 3.1, 3.2, 3.3] 新測試納入彙總且 `scripts/run-all-tests.sh` 全過，CHANGELOG 記載預設行為改變；留一則 comment 到 #392，說明 close stage 應呼叫 `idd-ci-gate.sh`
