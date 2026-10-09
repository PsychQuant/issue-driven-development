## 1. 先寫測試（RED）

- [x] 1.1 `scripts/tests/check-existing-work/test.sh`：以 `gh` 與 `git` 的 PATH shim 餵固定 fixture（寫法同 `check-diagnosis-readiness/test.sh`），涵蓋 spec `idd-existing-work-lookup` 的每個情境：宣告與只提及的區分、fenced 區內的宣告、`codex-pro#7` 跨 repo 形式、早於 issue 的 PR、`codex/119-124-…` 不被報、`stale-merged` 的殘留 branch 與未 merge 的 `idd/N-*`、E3 與 reopen 例外、自家 PR 與別人宣告 PR 並存、`gh` 失敗與列表達上限。驗證：helper 尚不存在時整份 suite 失敗（RED）。 需求：`Evidence kinds SHALL be a closed list and SHALL NOT include content similarity`、`A merged leftover branch SHALL NOT count as work in progress`、`An issue SHALL get exactly one verdict`、`A failed lookup or a truncated list SHALL be reported as unknown, never as clear`（設計 D3、D4、D5、D6、D9）。
- [x] 1.2 取回只做一次的測試：shim 計數 `gh pr list` 與 `git ls-remote` 的呼叫次數，三個 issue 一次呼叫時各只呼叫一次。驗證：RED，且斷言失敗訊息說出實際次數。 需求：`One helper SHALL answer whether work already exists for an issue`（設計 D1、D2）。

## 2. Helper

- [x] 2.1 `scripts/check-existing-work.sh`：批次取回 open PR、merged PR 與 remote branch，依 spec 的封閉證據列表與精確比對輸出每張 issue 的 verdict 與證據 JSON，退出碼 0／1／2 如 spec。驗證：1.1 與 1.2 全綠。 設計 D1：helper script，不是文件裡的 snippet，也不併進 actionability verdict；D3：證據是封閉列舉，每一種有自己的邊界；D5：verdict 與優先序；D6：`unknown` 不擋，但一定講出來；D9：fenced code 內的行不算宣告。
- [x] 2.2 E3 的 reopen 例外只在命中 E3 時才查 issue timeline。驗證：fixture 中沒有 E3 時 shim 記錄的 timeline 呼叫次數為 0；有 E3 且 reopen 在 merge 之後時 verdict 不是 `blocked` 但證據仍列出。
- [x] 2.3 變異檢查：把宣告判準放寬成「任何提及」、把 `stale-merged` 的判定改成只比 branch 名、把失敗處理改成回 `clear`，各自至少讓一個具名測試失敗。驗證：三個變異各有失敗測試，並把結果寫進 PR 說明。

## 3. 契約文件與呼叫端

- [x] 3.1 [P] 改寫 `references/pr-issue-matching.md`：宣告與提及兩層、封閉證據列表（「只有這五種，不得依相似性類推」）、helper 為唯一實作、呼叫端表補齊（含 `idd-list` 並指向 #368）。驗證：`scripts/tests/docs-catalog-sync` 與 `closing-summary-prose-drift` 通過；表中每個列出的 SKILL.md 確實引用 helper 或 #368。
- [x] 3.2 `idd-all` Step 0.4：PR 模式在 Phase 0.5 建 branch 之前呼叫 helper，`blocked` 時 attended 問三個選項、unattended 停該張並在 Phase 6 Action items 加一行，`resume` 時繼續，`unknown` 印出並繼續；呼叫 `idd-implement` 時帶 `--existing-work-checked`。驗證：`scripts/tests/plan-routing-consistency` 通過；SKILL.md 內不再有私有的 PR 比對。 需求：`Starting skills SHALL act on a blocked verdict` 與 `PR mode SHALL check for existing work before it creates a feature branch`（設計 D7：各呼叫端的職責；D8：attended 的三個選項與 unattended 的 outcome）。
- [x] 3.3 [P] `idd-all-chain` Phase 0.4：與 diagnosis-readiness 並列，對每個 root 呼叫 helper，行為同 3.2，在建立 cluster branch 與 manifest 之前。驗證：SKILL.md 中此檢查位於 Phase 0.5 之前，由 `plan-routing-consistency` 或新增的順序斷言檢查。
- [x] 3.4 [P] `idd-implement` 入口：直接被呼叫時呼叫 helper 並問，帶 `--existing-work-checked` 時略過。驗證：兩條路徑各有一個 fixture 或文字斷言。
- [x] 3.5 [P] `idd-diagnose`：Step 1 之後呼叫 helper，把證據寫進 Diagnosis 的 `### Existing work`（含 `unknown` 與 `(none)`），任何 verdict 都不停止。驗證：SKILL.md 中該步驟沒有 abort 或 exit 路徑；Diagnosis 範本含該標題。 需求：`idd-diagnose SHALL report existing work and SHALL NOT stop on it`（設計 D7）。
- [x] 3.6 `idd-close` Step 1.5：open PR 改由 helper 取得，gate 維持：任何 open PR（E1 與 E2，自家的也擋）都擋；查詢 open PR 失敗或達上限時拒絕結案；Step 1.55 不遷移。需求：`idd-close SHALL use the same evidence for its open-PR gate`（設計 D7）。驗證：`scripts/tests/check-existing-work/test.sh` 內的接線斷言（見 4.1）、`merge-completeness` 與 `check-closed-without-summary` 不變地通過。

## 4. 收尾

- [x] 4.1 `CHANGELOG.md` 一條（Unreleased），寫明 E5 不做的理由、E4／E6 只顯示、`idd-close` Step 1.5 的 gate 不變但查詢失敗時更嚴、Step 1.55 不遷移；不更新 plugin 版本（發版是另一個決定，且 #316 的 idd-all／idd-implement 工作在同一個 branch 上）；沒有新增 skill，文件目錄不變。驗證：`scripts/run-all-tests.sh` 的失敗集合與基線相同（見下）。
- [x] 4.2 在 safari-browser 的 open PR 上實跑 helper，與診斷表對照。結果：#258、#259、#193、#262 為 `resume`（自家 PR，E1＋E4）；#265、#266、#268、#270、#272 只有 E2，`clear`，與診斷表一致。實跑另外發現並修掉一個缺陷：本機 `origin/HEAD` 過期使預設 branch 上的 `Refs #N` commit 被報成 E6，已改為向 GitHub 問預設 branch，並加回歸測試。
