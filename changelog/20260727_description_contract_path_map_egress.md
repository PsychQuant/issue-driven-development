# 2026-07-27 — #276 Phase 1 merge + Path Map + egress 資料安全 cluster

## 已 merge 至 main（PR #279）

- **#276 Phase 1 — skill description contract**：`idd-plan` ↔ `idd-diagnose` 順序寫在三個 surface，唯一在「AI 決定叫哪個 skill」當下被讀的（frontmatter description）恰好沒寫 — 根因修正 + 5 個 skill 補 house pattern + 新 drift-guard `skill-description-contract`（RED 8 → GREEN）。merge 後 main 41 suites 0 fail。

## Open PRs（等 review）

- **PR #280（#276 Phase 2）**：Path Map — workflows.md 新 `## Path Flowchart`（mermaid 主幹鏡像 decision tree + legend 群組，36 條 path 全覆蓋）+ `scripts/generate-path-map.py` 確定性渲染 `docs/wiki/Path-Map.md` + drift-guard `path-map-sync`（freshness / coverage / discovery）。**wiki [Path-Map](https://github.com/PsychQuant/issue-driven-development/wiki/Path-Map) 頁已同步上線**、sidebar 加導航區。
- **PR #281（#275 + #273 cluster）**：
  - **#275 empty-body guard**（exit 15，band 紀律修正 issue 建議的 exit 5）— 空 body 通過所有網照常派送、edit 覆寫 = 資料遺失（07-22 實際事故）；`--allow-empty-body` 顯式出口。
  - **#273 edit-comment verb**（diagnosis correction 記錄在案）— idd-edit Step-6 PATCH 原走 raw `gh api`，是 #226 rollout 白名單的「tracked separately」通道、**繞過全部網**；新 verb 接線後全網自動套用，batch 雙桶報表消費 band（final exit 仍 4）。
  - Dogfood 亮點：commit 2 首次 sweep 被 **#163 contract layer 當場抓到**新 code 的 `$SCRUB_LEVEL` 無 provenance — 該層上線同 session 即立功。

**收尾（同日）**：PR #280/#281 review + merged（main 42 suites 0 fail）；#276/#275/#273 依 close ritual 結案（各自獨立 summary + body sync + dashboard）；**v2.102.0 已發版**、marketplace 已同步。

CLAUDE.md：無需更新。
