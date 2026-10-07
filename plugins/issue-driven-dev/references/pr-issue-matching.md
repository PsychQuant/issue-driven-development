# 找「引用某 issue 的 PR」——精確比對契約（#293 / #305 / #366）

## 問題

GitHub 的 issue/PR search **對 `#N` 做 tokenize 後的比對，不是 issue-reference 解析**。加引號也不會變成精確比對。實測（`PsychQuant/perspective-writer`）：

```
$ gh pr list --state merged --search 'in:body "#7"' --json number
[{"number":2}]            # PR #2 body 內實際出現的是 codex-pro#7，不是 #7

$ gh pr list --state merged --search 'in:body "#10"' --json number
[{"number":2}]            # PR #2 body 內根本沒有 #10
```

所有呼叫點都直接把 `.[0]` 當答案用，所以誤配會安靜地變成錯誤的 gate 判定、錯誤的 branch、錯誤的 verify 目標。

## 契約

**search 只當粗篩，判定一律在 client 端做。**

```bash
# 1. 粗篩（縮小結果集，允許誤中）
CANDIDATES=$(gh pr list --repo "$REPO" --state "$STATE" \
               --search "in:body \"#${N}\"" \
               --json number,body,createdAt,headRefOid,mergedAt)

# 2. 精篩：#N 前面不得緊鄰 [A-Za-z0-9_/-]，後面不得緊鄰數字
#    —— 這一條同時排除 owner/repo#N 與 repo#N 的跨 repo 形式，以及 #12 誤中 #123
MATCHED=$(printf '%s' "$CANDIDATES" | jq --argjson n "$N" '
  map(select((.body // "") | test("(^|[^A-Za-z0-9_/-])#\($n)([^0-9]|$)")))')

# 3. 時序檢查（#305）：PR 若在 issue 開立之前就建立，不可能是它的 feature branch
ISSUE_CREATED=$(gh issue view "$N" --repo "$REPO" --json createdAt --jq .createdAt)
MATCHED=$(printf '%s' "$MATCHED" | jq --arg t "$ISSUE_CREATED" 'map(select(.createdAt >= $t))')
```

**多筆命中時不得預設取 `.[0]`** —— 依呼叫點的語意決定（最新 merge、或提示使用者），並把「有多筆」這件事印出來。

## 「引用」有兩層：宣告與提及（#366）

上面那條精篩回答的是「這個 PR 的 body 有沒有出現 `#N`」，也就是**提及**。「這個 PR 在處理這張 issue」是另一個問題：實測一個 repo 的 9 張 issue，有 5 張只被別的 PR 在「Recorded, not changed」那類句子裡提到。把提及當成「已有人在做」，會誤擋。所以：

| 層 | 判準 | 用途 |
|---|---|---|
| **宣告** | body 在**非 fenced 區**有一行以 `Refs`／`Closes`／`Fixes`／`Resolves`（不分大小寫）開頭，且該行有精確比對的 `#N` | 「這個 PR 在處理這張 issue」 |
| **提及** | body 有精確比對的 `#N`，但不是宣告 | 只提供脈絡，**不得**據此擋任何動作 |

兩層都套用上面的精篩與時序檢查。

## 「這張 issue 現在有沒有人在做」：共用 helper（#366）

查詢「issue N 是否已有 PR 或 branch 在處理」**只有一個實作**：`scripts/check-existing-work.sh`。呼叫端不得自帶 pattern。介面、退出碼與證據種類以 spec `idd-existing-work-lookup` 為準；這裡只留會被讀者拿去推論的部分，**而且是封閉列舉**：

**證據只有這五種，不得依相似性類推第六種**（不比對內容，只比對有沒有引用）：

| 種類 | 內容 | 效果 |
|---|---|---|
| E1 | open PR，宣告該 issue（上表）；head 是 `idd/N`／`idd/N-*` 時為自家的 resume | 擋 |
| E2 | open PR，只提及 | 只顯示 |
| E3 | 已 merge 的宣告 PR，issue 仍 OPEN；merge 之後 issue 被 reopen 過則只顯示 | 擋 |
| E4 | remote branch `idd/N` 或 `idd/N-*`，且不是已 merge 的殘留 | 只顯示，verdict `resume` |
| E6 | 不在預設 branch 上、commit 訊息有以 `Refs` 開頭的一行帶 `#N`，且 branch 不是已 merge 的殘留 | 只顯示 |

- **為什麼沒有「其他前綴的 branch」**：多個 issue 的 branch 名（`codex/119-124-…`）只會被認出第一個號碼，範圍與成對也無法由名稱分辨；沒開 PR 的 branch 由 E6 兜底。
- **已 merge 的殘留 branch** 用 `headRefOid` 判定（branch tip 等於某個 merged PR 的 head commit），不用 branch 名。squash merge 的 repo 裡，已結案 issue 的 branch 仍在，tip 也不是預設 branch 的祖先。
- **verdict**：`blocked`（有非自家的 E1，或未被 reopen 免除的 E3）、`resume`、`unknown`（查詢失敗或列表達上限，**不是** `clear`）、`clear`。

## 為什麼不用 GraphQL 的 `CrossReferencedEvent`

那是最接近權威的來源，但語意不完全一致（它包含任何 cross-reference，不限於「這個 PR 要修這個 issue」），且需要 GraphQL 分頁。**本契約是務實解，不是權威解** —— 這一點要留在實作註解裡，免得後人以為問題已從根解決。

## 呼叫點

兩類：**用 helper**（上一節，沒有自己的 pattern）與**自帶 jq 精篩**（上面「契約」那段）。

| 位置 | 用途 | 方式 | 誤配後果 |
|---|---|---|---|
| `skills/idd-all/SKILL.md` Step 0.4 | 開工前檢查（PR 模式在建 branch 之前） | helper | 重複診斷與實作 |
| `skills/idd-all-chain/SKILL.md` Phase 0.4 | 開工前檢查 | helper | 同上 |
| `skills/idd-implement/SKILL.md` 入口 | 直接被呼叫時的開工前檢查 | helper | 同上 |
| `skills/idd-diagnose/SKILL.md` Step 1 之後 | 寫進 Diagnosis 的 `### Existing work`，只報告 | helper | 診斷漏掉已有的 PR |
| `skills/idd-close/SKILL.md` Step 1.5 | PR gate | helper（gate 語意不變：E1 與 E2 都擋） | 誤以為有未 merge 的 PR → **擋住合法的 close** |
| `skills/idd-close/SKILL.md` Step 1.55 | branch resolution | 自帶 jq | 拿到別的 PR 的 headRefOid → merge-completeness 比對錯的 branch |
| `skills/idd-verify/SKILL.md` Step 0.5 | auto-detect input source | 自帶 jq | 對錯的 PR 跑 verify |
| `skills/idd-report/SKILL.md` | 統計 | 自帶 jq | 數字偏誤 |
| `skills/idd-list/SKILL.md` Step 3.5 | issue→PR 索引與 cluster | **私有 regex `#(\d{1,7})\b`，不符合本契約**（#368） | 跨 repo 形式與只提及都被算成「有 PR」 |
| `references/pr-flow.md` | 文件範例 | 文字 | 會被照抄 |
| `references/usecase-routing.md` | 文件範例 | 文字 | 會被照抄 |
| `references/external-agent-delegation.md` | 文件範例 | 文字 | 會被照抄 |
