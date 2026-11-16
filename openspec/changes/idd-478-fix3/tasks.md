## 1. 測試先寫（先看到它們失敗）

- [x] 1.1 `scripts/tests/rest-queue/test.sh` 的情境改成在 git working tree 裡跑（`git init`、`.claude/.idd/state/` 寫進 `info/exclude`、本機的 user 設定），既有檢查照舊通過。完成時：在目前的程式上，既有的檢查沒有新的失敗。
- [x] 1.2 Requirement「Between two issues one helper settles the working tree」：六個 Example 的測試（標記各自的 Example 標題），在有 bare origin 的臨時 repo 裡實際執行 `settle`；另有 Scenario 的檢查（有 commit 的 issue branch、別的 issue 的 branch、還在 in flight 的 issue 與別張 issue 回 1、進行中的 merge 回 3）。
- [x] 1.2b 同一條 requirement 的窮舉檢查：path（PR、direct-commit）× 所在 branch（自己的、預設、別張的、detached）× 留下物（無、一般檔、manifest、IDD 不收進 git 的檔）× 預設 branch 與遠端（相同、落後、超前），每一格在臨時 repo 裡實際執行 `settle`，與一張獨立寫成的預期表比對結束碼、有沒有 commit、最後所在的 branch。
- [x] 1.3 Requirement「Each issue is attempted at most once per run」：Example `an issue with a local branch is recorded, not handed out` 的測試。
- [x] 1.4 Requirement「Start prints the list and resumes an unfinished run」：Example `a run state that git would track` 的測試；狀態檔缺 `reason`、`started_at` 讀不出來時視為不能用；`start` 的清單說明已有 PR 或 branch 的 issue 會記為 existing work。
- [x] 1.5 Requirement「The open issues are read completely or not at all」：讀渲染時丟出任何例外的 issue 歸 `unreadable`，命令照樣結束碼 0（以複製的 lib 讓 `open_clarity_rows` 丟出 RuntimeError）。
- [x] 1.6 Requirement「Report lists what happened and ends the run」：existing work 的說明改成留給人、看 reason 寫的 PR 或 branch；settle 保留的 branch 與 commit 列在那一張底下（併在 1.2 的第一個 Example）。
- [x] 1.7 Requirement「A stopped issue does not stop the run and a stopped run hands out nothing」與「idd-all runs rest mode as a loop over the single-issue pipeline」與 `idd-existing-work-lookup` 的「Starting skills SHALL act on a blocked verdict」：skill 文字的檢查（停止表四列、`report` 以 1 或 3 結束那一列、`settle` 在 `record` 之後、in flight 那一列不重跑 Step 0.5.1、rest mode 記錄 existing work 不提問、Step 0.5.1 指回 rest 一節、前置步驟只做一次、`stop` 自己失敗時往報告走、direct-commit 在哪裡結束），標記 `the skill names the loop commands in order`、`the skill ends when the report itself fails`、`the skill goes on to the report when stop fails`、`the skill says where a direct-commit run ends`、`the skill runs the preflight steps once`、`the skill continues an issue in flight`、`rest mode records existing work instead of acting on it`。

## 2. 程式與 skill

- [x] 2.1 `rest-queue.py`：新增 `settle` 子命令（封閉表、commit 只在這張自己的 branch、`.claude/.idd/` 的排除、fetch 與快轉、run 狀態記錄 `kept`）；`next` 的本機 branch 檢查；`start` 的 ignore 檢查；`read_state` 的驗證；讀渲染的例外；報告的 existing work 說明與 `kept`。完成時：1.2 至 1.6 的測試通過。
- [x] 2.2 `skills/idd-all/SKILL.md`：第 5 步改成 `settle`；停止表四列；in flight 那一列；existing work 的 `--reason` 帶上下一步、不提問；Step 0.1 的說法；「這一節不做的事」（push 與開 PR 的那半句、本機 branch、settle 的 commit）；「re-run /idd-all」改成帶 issue 號；已知限制補上模型自己以空引數呼叫的影響；attended 的說明；報告裡的問題原文是資料。完成時：1.7 的檢查通過。
- [x] 2.3 `scripts/close-stage.py`：run-state 過期那一則訊息改成帶 issue 號。完成時：`scripts/tests/close-stage/test.sh` 通過。

## 3. 文件

- [x] 3.1 `docs/commands.md`（rest 那一列：只跑 candidate、其他類別與 existing work 列在報告、#566、PR mode 才是一次跑完）、`CHANGELOG.md`（settle、本機 branch、start 的檢查、#566）、`references/usecase-routing.md`（Note、第 27 列、#37 那幾行）、plugin 的 `CLAUDE.md`（idd-all 那一列與單張 orchestrator 那一句）。完成時：`scripts/tests/docs-catalog-sync/test.sh` 通過。

## 4. 驗證

- [ ] 4.1 跑 `scripts/tests/rest-queue/test.sh`、`scripts/tests/close-stage/test.sh` 與 `scripts/run-all-tests.sh`，全部通過。
