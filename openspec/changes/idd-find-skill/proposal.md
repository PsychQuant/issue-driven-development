# Proposal: idd-find-skill

## Why

IDD 沒有語意查找入口：「之前是不是處理過類似的問題？」只能靠人記憶或手動 `gh search`。`idd-list` 是結構 triage（state / phase / PR cluster）、`idd-clarify` 是語意精確度軸 — 兩者都不回答「跨 open+closed 語料找相關 issue」。#139 使用者拍板 **Option A：新增 `/idd-find` skill**（surfacing-only family 第 3 員）— 查找的輸入/輸出形狀（query → ranked hits）與 list 的 triage 形狀差異大，塞進 idd-list 會讓兩者都難用；family 第 3 員成立同時解鎖 #140 的 pattern 文件化。

## What Changes

1. **新 skill `skills/idd-find/SKILL.md`**：`/idd-find <query>` — 對 open+closed 全語料跑 GitHub search relevance，輸出 ranked hits 並疊加 IDD phase + open-PR/cluster 資訊。
2. **Surfacing-only 契約**：read-only（不 mutate 任何 state）、standalone runnable、可被其他 skill delegate — 與 idd-list / idd-clarify 同 family（#140 文件化）。
3. **v1 誠實邊界**：搜尋 backend = GitHub search relevance（`gh search issues` / `gh issue list --search`），**不做 embedding 語意搜尋** — 跨措辭同義查找是已知限制，留 residue。
4. **Routing / docs 同步**：plugin CLAUDE.md 輔助 skills 表、`references/usecase-routing.md` 加入情境列。
5. **Drift-guard suite** `scripts/tests/idd-find/`。

## Non-Goals

- Embedding-based 語意搜尋（#139 Residue — v1 明確不做，GitHub relevance 是誠實邊界）
- 寫入任何 state（phase / label / comment）— surfacing-only 鐵律
- 取代 idd-list 的 triage（互補不重疊；分工見 #140 family 文件）

## Impact

- Affected specs: `idd-find`（ADDED，新 capability）
- Affected code: 新 `skills/idd-find/SKILL.md`、`CLAUDE.md`（plugin）、`references/usecase-routing.md`、新 suite `scripts/tests/idd-find/`
- 解鎖 #140（同 cluster branch、本案落地後）

## Refs

Issue #139（使用者裁決 Option A，2026-07-17；Spectra opt-out → propose）
