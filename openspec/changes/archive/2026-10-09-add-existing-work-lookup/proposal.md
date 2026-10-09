## Why

`idd-all` 與 `idd-diagnose` 不檢查「已經有 PR 或 branch 在處理這張 issue」。唯一從 issue 查到 PR 的地方是 `idd-close` Step 1.5，而它在收尾才擋。所以對一張已有 open PR 的 issue 跑 `/idd-all #N`，會重新診斷、開新的 `idd/N-*` branch 再實作一次，重複要到 review 或 close 才被發現（#366）。

## What Changes

- 新增共用 helper `scripts/check-existing-work.sh`：一次取回 open PR、merged PR 與 remote branch，逐 issue 做精確比對，輸出每張 issue 的證據與 verdict。
- 證據是封閉列舉（討論定案，見 #366 決議留言）：E1 宣告該 issue 的 open PR、E2 只提到的 open PR、E3 已 merge 的宣告 PR 而 issue 仍 OPEN、E4 `idd/N`／`idd/N-*` branch、E6 帶 `Refs #N` 的未 merge commit。**不做內容相似度比對。**
- 「引用」分兩層：宣告（`Refs`／`Closes`／`Fixes`／`Resolves` 開頭的一行帶 `#N`）會擋；只在內文提到不擋。實測 9 張 issue 中 5 張只被 PR 提及。
- 已 merge 的殘留 branch（tip 等於某個 merged PR 的 `headRefOid`）不算證據。
- 呼叫端：`idd-all`（PR 模式在建 branch 之前）、`idd-all-chain` Phase 0.4、`idd-implement` 入口、`idd-diagnose`（寫進 Diagnosis 的 `### Existing work`，只報告不擋）；`idd-close` Step 1.5（open PR 的 gate）改用同一份比對，gate 語意不變（E1 與 E2 都擋，自家的也擋）；查詢 open PR 失敗時改為拒絕結案（比現行更嚴）。
- 擋下時：attended 問使用者（接著在該 PR 上做、用 `idd-verify #N --pr P` 驗證它、忽略）；unattended 停掉該張、批次繼續，並在 Phase 6 的 `## Action items (require human review)` 加一行。
- `references/pr-issue-matching.md` 改寫成這份契約，呼叫端表補齊（含 #368 的 `idd-list`）。

## Non-Goals

- 內容相似度（沒提到 `#N` 但其實解決了它的 PR）：不做。判準不是封閉列舉，unattended 時沒人覆核。
- 其他前綴的 branch（`<prefix>/N-*`，E5）：不做。兩個 repo 的實測顯示多 issue 的 branch 名（`codex/119-124-…`）只會認出第一個號碼，範圍與成對無法由名稱分辨；沒開 PR 的 branch 由 E6（commit 的 `Refs #N`）兜底。
- 兩個 open PR 對不同 issue 改同一批檔案的衝突：另一件事。
- `idd-list` 的私有 matcher（#368）：先在本 change 的呼叫端表裡登記，改用 helper 另開 change。
- `idd-close` 改成只擋「宣告」類 PR：本 change 維持現狀（E1 與 E2 都擋），因為那是改變 close 的 gate 語意，要另案決定。
- `idd-close` Step 1.55（merge-completeness）：不遷移。它需要已 merge 的「只提及」PR 與 `headRefOid`，helper 不回報這些；硬遷移就得改它的語意。
- 把本 helper 併進 #316 的 `idd_actionability_verdict`：後者是純函式、這是網路呼叫，且 #316 尚未合併；日後可把本 helper 的結果當輸入傳進去，不必改 helper。

## Capabilities

### New Capabilities

- `idd-existing-work-lookup`: 查詢某張 issue 是否已有 PR 或 branch 在處理它的 helper 契約、證據種類、verdict 與各呼叫端的行為。

### Modified Capabilities

- `idd-pr-hitl-modes`: 新增一條需求，PR 模式的 `idd-all` 必須在建立 feature branch 之前先做存在工作檢查。

## Impact

- Affected specs: 新 capability `idd-existing-work-lookup`；`idd-pr-hitl-modes`（ADDED 一條）
- Affected code: 新增 `plugins/issue-driven-dev/scripts/check-existing-work.sh` 與 `scripts/tests/check-existing-work/test.sh`；修改 `references/pr-issue-matching.md`、`skills/idd-all/SKILL.md`、`skills/idd-all-chain/SKILL.md`、`skills/idd-diagnose/SKILL.md`、`skills/idd-implement/SKILL.md`、`skills/idd-close/SKILL.md`；`CHANGELOG.md`、plugin 版本與文件目錄（`docs-catalog-sync` 會檢查）
- 注意：`idd-all` 與 `idd-implement` 的 SKILL.md 在 `idd/316-actionability-gate` 上有未提交的修改，實作前要先處理 #316 或疊在它上面
