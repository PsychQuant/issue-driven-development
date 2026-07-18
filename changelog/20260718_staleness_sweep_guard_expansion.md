# 2026-07-18 — Staleness sweep + guard 擴網（v2.99.1）＋ pai 治理深度整合（pai 2.20.0）

## 已 merge 至 main（PR #268）

- **#267 README pins + docs 回填 + guard 擴網**：README 3 根 stale `gpt-5.5` pin（其中 2 根是 guard 擴網後**當場抓到**、手掃漏掉的）+ stale vendored 敘述修正；docs/workflows.md + skill-dimensions.md 回填至 v2.99（五 path、matrix 三列含 pre-#122 legacy gap 的 idd-config、D12 第 4 員）。**結構性防範雙向**：`model-generation-sync` 網擴及 README + catalog docs（31 assertions）；新 suite `docs-catalog-sync` 要求每個 `skills/*/` 目錄名出現在 catalog docs — **#122 根因（無強制回填機制）從此 test-detectable**（首 RED 即抓 idd-ask + idd-config）。全 sweep 38 suites 0 fail。**v2.99.1** 發版（今日第三版）。

## 生態系（使用者 mid-turn 裁決：pai 自家 skill 也必須深度整合 codex-pro）

- **pai 2.20.0**（pai#23，已結案）：新 `references/codex-governance.md`（canonical 解析 + fail-fast）；code-review / academic-review / compose(--codex) 接線傳 `codexModel`/`codexEffort`；engine 與 bin/codex-call 的 baked default 降級為**治理 snapshot**（bump gpt-5.6-sol + authoritative 註記）；一手散文世代中立。**生態系終態：世代 pin 唯一存在於 codex-pro `defaults.json`** — pai 出 executable、codex-pro 出治理、IDD 與 pai skills 皆為 contract consumer。

#267 已依 close ritual 結案（summary + body sync + dashboard）。

CLAUDE.md：無需更新。
