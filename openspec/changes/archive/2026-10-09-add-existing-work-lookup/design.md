## Context

`idd-all`、`idd-diagnose`、`idd-implement` 都不問「是否已有人在做這張 issue」；`idd-close` Step 1.5 在收尾才擋 open PR。比對規則（#293／#305）是 `references/pr-issue-matching.md` 的散文契約，每個呼叫端各貼一段 jq，已經分岔過一次（#368：`idd-list` 有第八個私有 matcher，不在契約的七處列表裡）。#316 的前例：同一條規則被三個 consumer 各寫一份、安靜地分岔，解法是一個共用實作。

`idd-all-chain` Phase 0.4 已有「開工前檢查」的先例（`scripts/check-diagnosis-readiness.sh`，在建 branch 與 manifest 之前跑）。

## Goals / Non-Goals

**Goals:**

- 一個實作回答「這張 issue 現在有沒有人在做」，所有呼叫端共用。
- 不誤擋：只有「宣告」該 issue 的工作會擋。
- 查詢失敗時不假裝「沒有」。

**Non-Goals:**

- 內容相似度、其他前綴的 branch、PR 間的檔案衝突、`idd-list` 改用 helper、`idd-close` 語意變更、併入 #316 的 actionability verdict。理由見 proposal 的 Non-Goals。

## Decisions

### D1：helper script，不是文件裡的 snippet，也不併進 actionability verdict

`scripts/check-existing-work.sh <owner/repo> <issue>...`，輸出 JSON，測試放 `scripts/tests/check-existing-work/test.sh`（`run-all-tests.sh` 會掃到）。與 `check-merge-completeness.sh`、`check-diagnosis-readiness.sh` 同一家族。否決併進 `idd_actionability_verdict`：它是純函式（輸入呼叫端已取得），這是網路呼叫；#316 還在進行。否決「每處一段 snippet」：那是造成 #305、#368 的現狀。

### D2：批次取回一次，逐 issue 在 client 端比對

一次呼叫取 open PR 與 merged PR（`--limit 100`，與 `idd-list` 一致）；branch 來自一次 `git fetch --prune origin` 加 remote-tracking refs（所以 `--cwd` 必須是該 repo 的 clone；fetch 失敗記為錯誤，結果變 `unknown`），對每個未 merge、非預設的 branch 用 `git log origin/<default>..origin/<branch>` 取 commit 訊息。每張 issue 另有一次 `gh issue view`（取建立時間與狀態）。實作時由 `git ls-remote` 改為 fetch：E6 本來就要本地物件，兩者用同一個來源才不會互相矛盾。 **預設 branch 問 GitHub**（`gh repo view`），不用 clone 的 `origin/HEAD`：後者是 clone 當時的快照，在真實 clone 上指向過期的 feature branch，使預設 branch 上帶 `Refs #N` 的 commit 全被報成 E6（實跑才發現）；`origin/HEAD` 只當 GitHub 問不到時的退路。不用 `in:body "#N"` 搜尋當主要來源（它是粗篩，#293）。列表筆數達上限時 `truncated: true`。

### D3：證據是封閉列舉，每一種有自己的邊界

| 種類 | 條件 | 效果 |
|---|---|---|
| E1 | open PR，body 在**非 fenced 區**有一行以 `Refs`／`Closes`／`Fixes`／`Resolves`（不分大小寫）開頭、且該行帶精確比對的 `#N`；PR 建立時間不早於 issue | 擋；head 是 `idd/N`／`idd/N-*` 時為 resume |
| E2 | open PR，body 精確比對到 `#N` 但不是 E1；與 E1 一樣，PR 建立時間早於 issue 的不報 | 只顯示 |
| E3 | merged PR 符合 E1 的條件，issue 仍 OPEN | 擋；issue timeline 上有晚於該 PR `mergedAt` 的 `reopened` 事件時只顯示 |
| E4 | remote branch 名為 `idd/N` 或 `idd/N-*`，且不是 `stale-merged` | 只顯示（`resume-candidate`） |
| E6 | 不在預設 branch 上的 commit，訊息有精確比對的 `Refs #N`，其 branch 不是 `stale-merged` | 只顯示 |

精確比對沿用既有規則：`#N` 前不得緊鄰 `[A-Za-z0-9_/-]`、後不得緊鄰數字。宣告行的判準放在 helper 內，**一處**。

### D4：`stale-merged` 用 `headRefOid` 判定

squash merge 的 repo 裡，已結案 issue 的 `origin/idd/N-*` 仍在，tip 不是預設 branch 的祖先（實測 #255 的 branch 如此）。所以 branch tip 等於某個 merged PR 的 `headRefOid` 就標 `stale-merged`，不算 E4／E6。與 `idd-close` Step 1.55 用 `headRefOid` 而非 branch 名是同一個理由。

### D5：verdict 與優先序

每張 issue 一個 verdict：`blocked`（有非自家的 E1 或 E3）、`resume`（沒有 blocked 證據，但有自家 `idd/N-*` 的 PR 或 branch）、`unknown`（查詢失敗或 `truncated`，且沒有 blocked 證據）、`clear`。證據一律列出，包含只顯示的。同時有自家 PR 與別人的宣告 PR 時是 `blocked`。「自家」只以 `idd/` 前綴判定，因為那是 `idd-implement` 建 branch 的慣例。

### D6：`unknown` 不擋，但一定講出來

查詢失敗（`gh` 或 `git ls-remote` 非零）與 `truncated` 都回 `unknown`，不是 `clear`。呼叫端印出並繼續；unattended 時同樣加一行 Action items。理由：重複實作是可逆的，一個壞掉的網路不該停掉整批；但「沒有」與「不知道」必須能分辨。`idd-close` 對查詢 open PR 失敗改為拒絕結案（它擋的是不可逆的 close）。這比現行更嚴：現行的 `gh pr list | jq` 在 `gh` 失敗時 `OPEN_PRS` 為空，gate 安靜通過；這是實作時才發現的，不是沿用。

### D7：各呼叫端的職責

| 呼叫端 | 時點 | 行為 |
|---|---|---|
| `idd-all` | Step 0.4，PR 模式在 Step 0.5 建 branch 之前 | `blocked` → attended 問、unattended 停該張；`resume` → 在該 PR／branch 上繼續 |
| `idd-all-chain` | Phase 0.4，與既有的 diagnosis-readiness 並列 | 同 `idd-all`，對每個 root |
| `idd-implement` | 入口；`idd-all` 呼叫時帶 `--existing-work-checked`，略過 | 直接被呼叫時 `blocked` → 問 |
| `idd-diagnose` | Step 1 之後 | 只寫 `### Existing work`，**絕不擋**（診斷是唯讀的） |
| `idd-close` | Step 1.5 | 改呼叫 helper 取證據，gate 語意不變：任何 open PR（E1 與 E2，自家的也擋）都擋。Step 1.55 不遷移（需要已 merge 的只提及 PR 與 `headRefOid`，helper 不回報） |

### D8：attended 的三個選項與 unattended 的 outcome

attended：接著在該 PR 上做／用 `idd-verify #N --pr P` 驗證它／忽略（寫一行 audit 到 issue body）。unattended：該張的 outcome 為 `existing PR #P`（E3 為 `already merged in PR #P → /idd-close #N`），批次繼續，Phase 6 的 `## Action items (require human review)` 加一行。不新增報告段落（#137、#120 已是同一個彙整出口）。

### D9：fenced code 內的行不算宣告

PR body 引用範例（例如文件裡寫 `Closes #N` 當反例）不應被當成宣告。`idd-list` 已為此在掃描前剝除 fenced block（#14）。缺點：縮排的 code block 不剝，與 `idd-list` 相同。

## Risks / Trade-offs

- **宣告判準未對其他 agent 抽樣**：`Refs`／`Closes` 開頭一行是否符合 Codex、Copilot 開的 PR，沒量過。誤判方向是「宣告被當成提及」＝漏擋，不是誤擋；漏擋的代價是重複實作，與現狀相同。
- **宣告被不同人寫成 `Fixes: #N`**（冒號）：正規式容許冒號與空白，要有測試。
- **與 #316 重疊**：`idd-all`、`idd-implement` 兩個 SKILL.md 有未提交的修改；實作要在 #316 落地後或疊在其上。
- **API 成本**：每次執行固定 3 次呼叫加一次 `git ls-remote`，再加每個 E3 命中一次 timeline；沒量過。
- **reopen 例外多一次查詢**：只在命中 E3 時才查。
- **`idd-implement` 的略過旗標**：若呼叫端漏帶，會重複詢問；不會錯擋。
