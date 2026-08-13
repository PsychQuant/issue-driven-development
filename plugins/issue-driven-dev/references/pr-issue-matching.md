# 找「引用某 issue 的 PR」——精確比對契約（#293 / #305）

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

## 為什麼不用 GraphQL 的 `CrossReferencedEvent`

那是最接近權威的來源，但語意不完全一致（它包含任何 cross-reference，不限於「這個 PR 要修這個 issue」），且需要 GraphQL 分頁。**本契約是務實解，不是權威解** —— 這一點要留在實作註解裡，免得後人以為問題已從根解決。

## 呼叫點（全部七處）

| 位置 | 用途 | 誤配後果 |
|---|---|---|
| `skills/idd-close/SKILL.md` Step 1.5 | PR gate | 誤以為有未 merge 的 PR → **擋住合法的 close** |
| `skills/idd-close/SKILL.md` Step 1.55 | branch resolution | 拿到別的 PR 的 headRefOid → merge-completeness 比對錯的 branch |
| `skills/idd-verify/SKILL.md` Step 0.5 | auto-detect input source | 對錯的 PR 跑 verify |
| `skills/idd-report/SKILL.md` | 統計 | 數字偏誤 |
| `references/pr-flow.md` | 文件範例 | 會被照抄 |
| `references/usecase-routing.md` | 文件範例 | 會被照抄 |
| `references/external-agent-delegation.md` | 文件範例 | 會被照抄 |
