# Surfacing-only Primitive Family（#140, v2.97.0+）

IDD 的 skill 分兩類：**lifecycle skills**（issue → diagnose → implement → verify → close，推動 phase 前進、mutate state）與 **surfacing-only primitives**（輕量 read-only，augment 主 pipeline 但不參與 phase 流程）。本檔是後者的 family 契約 — 新增第 4 員時照此檢查，不重造 boilerplate、不混入 lifecycle 行為。這就是 skill-dimension 的 **D12 軸：Surfacing vs Lifecycle**。

## 現任成員

| Member | 軸 | 回答的問題 |
|--------|-----|-----------|
| `/idd-list`（v2.51+） | structural triage | 「現在有什麼、在哪個 phase、哪個 PR」 |
| `/idd-clarify`（#135, v2.72+） | terminology / semantic accuracy | 「這個詞用得準不準、誰需要釐清」 |
| `/idd-find`（#139, v2.97+） | semantic lookup | 「之前是不是處理過類似的問題、在哪」 |
| `/idd-ask`（#72, v2.99+） | grounded QA | 「當時為什麼這樣決定 / X 怎麼運作」→ **合成答案**＋引用（鏡像 /spectra-ask） |

四員互補、零重疊：list 吃 filters、find 吃 free-text query → ranked hits、ask 吃 question → 合成答案、clarify 吃 issue 內文語意 — 輸入/輸出形狀不同是「該開新 skill 而非塞 flag」的判準（#139 Option A 裁決的一般化）。ask 的 retrieval delegate find 的 backend（本檔「lifecycle 不重造唯讀查詢」鐵律同樣適用於 primitive 之間）。增員三題的誠實記錄（#72）：第 3 題（delegate 消費者）**弱命中** — ask 類 skill 的消費者本來就是人（spectra-ask 同構先例），以此 judgment 開員；若未來第 3 題弱的候選無同構先例，先當 reference 文件。

## D12 軸：Surfacing vs Lifecycle

| Axis | Surfacing-only | Lifecycle |
|------|----------------|-----------|
| State mutation | **禁止**（no `gh issue create` / `edit` / `close` / `comment` / label） | 核心職責（phase 前進、comment、body sync） |
| 何時可跑 | 任何時候，standalone，不需 in-flight context | 有 phase 前置條件（gate） |
| 可被 delegate | 是 — 其他 skill 可內嵌呼叫消費輸出 | 否 — lifecycle step 由人 / orchestrator 依序驅動 |
| 定位 | augmentation not replacement | pipeline 本體 |

**鐵律**：surfacing primitive 想「順手」寫 state（quick-fix 按鈕、auto-file、auto-tag）→ 必須升級成 lifecycle 提案走 diagnose，不得在 primitive 內偷渡。反向同理：lifecycle skill 的唯讀查詢需求優先 delegate 給 family 成員（如 idd-issue 建案前 delegate idd-find 查重、idd-issue Step 4.6 delegate idd-clarify），不重造查詢邏輯。

## Family boilerplate（第 4 員 checklist）

新增成員時逐項照抄慣例，不重造：

- [ ] **Step 0 TaskCreate bootstrap**（強制，同所有 IDD skill）
- [ ] **config-protocol 解析 repo**（`--repo` per-invocation override → walk-up → git remote fallback；read-only skill 只用 path / git predicates）
- [ ] **Unattended fallback**：無互動 gate 或 gate 有 non-blocking 預設（不 AskUserQuestion 卡死 `/loop`）
- [ ] **`--limit N`** 之類的 bounded output（防 context 爆量）
- [ ] **空結果是合法輸出** — 誠實降級，不編造
- [ ] **allowed-tools 鎖 read-only**（frontmatter 不含寫入動作）
- [ ] **drift-guard suite**（`scripts/tests/<name>/test.sh`，鎖 read-only 禁令與分工敘述）
- [ ] plugin CLAUDE.md 輔助 skills 表 + `usecase-routing.md` 情境列

## 該不該加第 4 員（review 判準）

1. **輸入/輸出形狀**與現任三員都不同？（相同 → 塞既有 skill 的 flag）
2. 是**唯讀**的嗎？（要寫 state → lifecycle 提案，不進 family）
3. 至少一個 lifecycle skill 會 delegate 它？（沒有消費者 → 可能不需要 skill，先當 reference 文件）

三題全 yes 才開新 skill — skill 數量是 cognitive cost（#139 Risks），family 慣例把增員成本壓在 boilerplate 而非設計。
