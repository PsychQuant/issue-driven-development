# Design: idd-ask-skill

## D1 — 與 find 的分工：lookup vs QA（防第 4 員定位稀釋）

| | `idd-find` | `idd-ask` |
|---|---|---|
| 問題 | 「有沒有處理過類似 X、在哪」 | 「當時為什麼這樣決定 / X 是怎麼運作的」 |
| 輸出 | ranked hits（人自己去讀） | **合成答案**（AI 讀完引用回答） |
| 讀取深度 | metadata + overlay（O(1)/hit） | top-N 命中的**全文**（body + comments） |
| Token 成本 | 低 | 高（有界：top-N 預設 5、`--limit` 可調） |

ask 的輸出**必附** `### Referenced Issues`，讓人可以 fall through 到 find 式的自行閱讀 — 兩員互補成「先問、不滿意再自己翻」的鏈。

## D2 — Retrieval delegate idd-find backend（family 慣例：不重造唯讀查詢）

Step「搜尋」直接沿用 `idd-find` 的 search backend 契約：`gh search issues`（relevance、`--state all` 全語料）主 + `gh issue list --search` fallback。**引用 idd-find SKILL 的 backend 段落，不內嵌分歧副本**（同 #137 反 typo-drift 紀律）。ask 疊加自己的第二步：對 top-N hits `gh issue view --json body,comments` 抓全文。跨措辭限制同界（詞法檢索），輸出尾端同樣揭露。

## D3 — Grounded 回答契約（spectra-ask 規矩移植）

1. 首行 blockquote 引用使用者原問題
2. 每個 claim 附來源（`#N` + comment 錨點或區段名）；**語料裡沒有的不寫**（查無 → 誠實說查無 + 建議換 phrasing 或 `/idd-find` 自行翻）
3. **Source priority**：closed-with-PR > open > orphaned comment。衝突時取高優先源，並標注低優先源的分歧（「#A（closed）採 X；#B（open，進行中）傾向 Y」）
4. 結尾 `### Referenced Issues`：`#N (title) — URL`，只列實際引用的

## D4 — Decide-to-search gate（不是每個輸入都搜）

greeting / 純 meta-tool 問題（「idd-ask 怎麼用」）→ 不搜，直接答或引導。問題長得像 bug report → **不觸發 diagnose**，回答已知歷史後附一行「要立案 → `/idd-issue`」。無 question 且對話 context 可推 → 確認後搜；推不出 → 要求明確問題。

## D5 — #140 boilerplate checklist 逐項（第 4 員首戰）

Step 0 TaskCreate bootstrap ✓；config-protocol（`--repo` override；group 搜尋 = `--target group:<label>` 依 issue 需求，v1 先單 repo + 註記 group 為 residue）✓；unattended fallback（無互動 gate；decide-to-search 的「確認後搜」在 unattended 下改直接搜 + audit line）✓；bounded output（top-N=5、`--limit` 上限 10；讀全文的 token 成本是 ask 的本質成本，明文揭露）✓；read-only allowed-tools ✓；drift-guard ✓；CLAUDE.md + usecase-routing ✓。`references/surfacing-primitives.md` 成員表 +1（第 3 題弱命中入註記）。

## Alternatives considered

- **塞進 idd-find 當 `--answer` flag**：否 — I/O 形狀不同（hits vs 合成答案）、token 成本量級不同，正是 #139 Option A 拒絕合併的同一論證
- **建 local cache / embedding index**：否 — 基建成本不符 surfacing primitive 輕量定位；誠實邊界與 find 一致
- **先只寫 reference 文件（第 3 題弱）**：否 — spectra-ask 同構先例證明 ask 類 skill 的消費者是人，等 skill 消費者出現才開會讓「還原 decision rationale」繼續無入口
