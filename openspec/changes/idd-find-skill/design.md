# Design: idd-find-skill

## D1 — Surfacing-only 契約是硬邊界

`/idd-find` 屬 surfacing-only primitive family（idd-list / idd-clarify / idd-find；#140 文件化）：**read-only**（allowed-tools 不含 issue 寫入動作；skill 文本明文禁止 `gh issue create/edit/close/comment`）、**standalone**（不需 in-flight phase context）、**delegate-able**（其他 skill 可內嵌呼叫，如 idd-issue 建案前查重）。任何未來想讓 find「順手」寫 state 的擴充都必須升級成 lifecycle skill 提案，不得在 find 內偷渡。

## D2 — v1 搜尋 backend：GitHub search relevance，誠實邊界

- 主查詢：`gh search issues "<query>" --repo $GITHUB_REPO --state all --limit N --json number,title,state,updatedAt`（GitHub 全文 relevance 排序）
- fallback（`gh search` 不可用 / rate-limit）：`gh issue list --search "<query> in:title,body" --state all`
- **明文限制**：GitHub relevance 是詞面比對 + 排序，跨措辭同義（「白畫面」vs「blank screen」）查不到 — SKILL 印一行邊界提示，embedding 留 #139 residue。誠實邊界勝過假裝語意。

## D3 — 輸出 shape：ranked hits + IDD overlay

每個 hit 一列：`#N [state/phase] title — updated <rel>`；open issue 疊加 phase（body `**Phase**:` 解析，同 idd-list Step 3 規則）與 open-PR ref（`#(\d+)\b` body scan，同 idd-list Step 3.5 精簡版 — 只標 `→ PR #M`，不做完整 cluster leader 邏輯：find 是查找不是 triage，需要完整 cluster 視圖時導流 idd-list）。closed issue 附 Closing Summary 存在與否（有 → 這是可考古的結案紀錄）。

## D4 — Family boilerplate conformance

依 #140 family 慣例：Step 0 TaskCreate bootstrap、config-protocol 解析 repo（`--repo` override）、unattended 下不 AskUserQuestion（查無結果就輸出空表 + 建議放寬 query）、`--limit N`（預設 15）。

## D5 — 與 idd-list 的分工（防定位稀釋）

| | idd-list | idd-find |
|---|---|---|
| 問題 | 「現在有什麼、在哪個 phase」 | 「有沒有處理過類似 X」 |
| 輸入 | filters（state/label/limit） | 自然語言 query |
| 語料 | open（預設） | **open+closed 全語料** |
| 排序 | updatedAt | GitHub relevance |

idd-find 不接受 phase/label filter（那是 list 的事）；idd-list 不接受 free-text query。互補、零重疊 — #139 Risks「定位稀釋」的設計答案。

## Alternatives considered

- **Option C（idd-list `--find` flag）**：使用者否決 — 查找 I/O 形狀與 triage 差異大，同 skill 兩用互相拖累。
- **v1 就上 embedding**：拒絕 — 需要 index 基建與同步策略，超出 surfacing primitive 的輕量定位；GitHub relevance 已覆蓋大多數「找舊案」場景。
