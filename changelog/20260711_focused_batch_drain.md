# 2026-07-11 — Focused batch drain：freshness gate、IDD_CALLER registry、Discussions intake bridge

## 已 merge 至 main

- **#228 idd-verify diff-freshness gate**（PR #253，`c487ac7`）：凍結 diff 時記 `FROZEN_SHA`（PR mode 記 PR head oid），Step 2.9 於 merge/aggregate 前比對 — 不一致拒絕 aggregate、要求 re-freeze + delta round；「verify in-flight 不 commit、修復累積到 round 結束」升為正式紀律（DA-CRIT-1 事故機制化）。新 drift-guard `verify-diff-freshness/`（10 assertions）。
- **#161 IDD_CALLER registry**（PR #254，`b70475f`）：新 `references/idd-caller-registry.md`（5 現值、reader 契約 `fetched_by`、unset fallback `idd-skill`、informal-validation 姿態）；drift-guard `idd-caller-registry/` 做動態樹掃描 — 未登記新值即 RED。`process-attachments.sh` header cross-link。

## 進行中（PR #255 待 review）

- **#221 Discussions intake bridge**（Spectra change `discussions-intake-bridge`，6/6 tasks）：`idd-list --discussions`（opt-in surface：probe → Q&A/Ideas + 未答 filter → dedup → actionable 區塊）+ `idd-issue --from-discussion`（Provenance verbatim blockquote + draft-and-confirm 回文，unattended 絕不 post）；契約 + GraphQL 樣板 single-source 於 `references/discussions-intake.md`。drift-guard 30 assertions。

## 流程產出（無 code）

- 8 份 batch 診斷（#225–#228、#161、#140、#157、#158）；#140/#157/#146 誠實 re-bucket 回 parked；4 個設計決策拍板記錄（#227 refusal 碼帶 ≥10、#225 python3 統一解析、#226 phased rollout、#158 per-comment refuse）。

## 待發版

`c487ac7` + `b70475f`（+ #221 merge 後）尚未發版 — 計畫湊齊後一次 bump **v2.95.0**（plugin CHANGELOG.md 屆時同步）。

CLAUDE.md：無需更新 — 本日變更皆 plugin 內部（skill prose + reference + tests），repo 層架構與指令無異動。
