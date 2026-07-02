## Why

IDD 內建多套 process 紀律（TDD loop、bug 系統性除錯、完成前驗證檢查）與 superpowers plugin 的 canonical skills 同構重複，重演 pai 案例「同一機件兩處維護、同一 bug 修兩次」的維護稅（參 #205 / pai#20）。#209 已裁決確立「深度整合 >> hard-coded」原則 — 生態系有 canonical 套件時依賴它，不在 IDD 內部複製等價邏輯 — 並指定 superpowers 為首個新整合對象（hard dependency、缺席即 fail-fast，D1–D5 決策逐字在 #209 decision comment）。

## What Changes

1. **依賴宣告（D1）**：plugins/issue-driven-dev/.claude-plugin/plugin.json 新增 dependencies 條目 — superpowers、marketplace 指向 claude-plugins-official、unversioned（官方 marketplace 無 name--vX.Y.Z tag convention）。安裝 IDD 時 Claude Code 自動 resolve + 安裝 superpowers，enable 具遞移性。
2. **Cross-marketplace allowlist（D1）**：本 repo .claude-plugin/marketplace.json 新增 allowCrossMarketplaceDependenciesOn 陣列，含 claude-plugins-official。
3. **三個 delegation 點（D3）** — **BREAKING**（未裝 superpowers 的既有使用者升級後，下列路徑 abort with 安裝指引）：
   - idd-implement 的 TDD loop 段 → delegate 至 superpowers:test-driven-development
   - idd-implement 的完成前檢查 → delegate 至 superpowers:verification-before-completion
   - idd-diagnose 的 bug Root Cause Analysis 執行框架 → delegate 至 superpowers:systematic-debugging
4. **雙重 pre-flight（D2 + D5）**：delegation 點檢查 plugin 存在 + 目標 skill 名稱存在；缺席 fail-fast + 一步安裝指引，不做 vendored fallback、不 silent degrade。
5. **R1 rule（D4）**：新增 .claude/rules/deep-integration-over-hardcode.md（dev-only 專案 rule，不隨 plugin 發佈）— 判準鏈 + 具名例外，以 pai 三層解析鏈案例為 exemplar。
6. **發佈掃尾**：CHANGELOG、plugin.json 與 marketplace.json 版本 2.89.0 → 2.90.0、README 安裝段補 dependencies 自動安裝說明與最低 Claude Code 版本註記。

## Capabilities

### New Capabilities

- `superpowers-integration`: IDD 對 superpowers plugin 的 hard-dependency 契約 — dependency 宣告、雙重 pre-flight（plugin + skill 名稱）、三個 delegation 點的 fail-fast 行為與安裝指引格式。

### Modified Capabilities

(none) — idd-verify ensemble（pai canonical，既有 idd-verify spec 不動）、worktree isolation、planning 紀律皆為 keep（D3），不觸碰既有 specs。

## Impact

- Affected specs: superpowers-integration（NEW）
- Affected code:
  - New: .claude/rules/deep-integration-over-hardcode.md
  - Modified: plugins/issue-driven-dev/.claude-plugin/plugin.json, .claude-plugin/marketplace.json, plugins/issue-driven-dev/skills/idd-implement/SKILL.md, plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md, plugins/issue-driven-dev/scripts/check-plugin-presence.sh, plugins/issue-driven-dev/CHANGELOG.md, plugins/issue-driven-dev/README.md
  - Removed: (none)
