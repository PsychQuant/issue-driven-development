## Why

兩層 rules（dev 層 `.claude/rules/` vs plugin 層 `plugins/issue-driven-dev/rules/`）的分層判準只存在於隱性實踐；而 commit-issue-reference（auto-close trap 紀律，#213）保護的是**所有 IDD 使用者**，卻只常駐在維護者的 dev session — 使用者端沒有任何 ambient 注入管道（plugin-root CLAUDE.md 不載入 project context、plugin 無 hooks dir），trap 的主戰場（skill 之外的手動 commit）完全裸奔。#214 A1–A5 設計決策已由使用者確認（decision comment 逐字在案）。

## What Changes

1. **分層判準文件化（A1）**：dev 層新增 .claude/rules/rules-layering.md — 受益者軸判準（使用者行為 → plugin 層；維護者決策 → dev 層）、兩層對照表、歸位程序（供 #215 全面盤點使用）+ 專案 CLAUDE.md @-import。
2. **canonical 遷移（A2）**：新增 plugins/issue-driven-dev/rules/commit-issue-reference.md（user-facing 完整版，normative core）；dev 層 .claude/rules/commit-issue-reference.md 縮為蒸餾指回；plugins/issue-driven-dev/CLAUDE.md § Commit Conventions 加 canonical 指向。
3. **注入機制並用（A3）**：新增 plugins/issue-driven-dev/hooks/hooks.json + hooks/session-start-commit-rule.sh — SessionStart 印 **≤5 行**極簡鐵律 + 指路完整版；idd-implement / idd-all 的 commit 規範段各加一行指向 rules 檔（skill-scope 引用）。
4. **Drift guard（A4）**：plugins/issue-driven-dev/scripts/tests/session-start-commit-rule/test.sh — 比對 hook 輸出關鍵 token 與 rules 檔一致 + 行數上限斷言。
5. **發佈掃尾（A5）**：CHANGELOG 2.91.0 條目（additive，非 breaking）、plugin.json 與 marketplace.json 版本 2.90.0 → 2.91.0、README hook 行為說明。

## Capabilities

### New Capabilities

- `user-rule-injection`: plugin 對使用者 session 的 user-facing rule 注入契約 — SessionStart hook 極簡輸出（行數上限、內容 token 與 canonical rules 檔對齊）、canonical rule 檔位置、skill-scope 引用。

### Modified Capabilities

(none)

## Impact

- Affected specs: user-rule-injection（NEW）
- Affected code:
  - New: .claude/rules/rules-layering.md, plugins/issue-driven-dev/rules/commit-issue-reference.md, plugins/issue-driven-dev/hooks/hooks.json, plugins/issue-driven-dev/hooks/session-start-commit-rule.sh, plugins/issue-driven-dev/scripts/tests/session-start-commit-rule/test.sh
  - Modified: .claude/rules/commit-issue-reference.md, plugins/issue-driven-dev/CLAUDE.md, plugins/issue-driven-dev/skills/idd-implement/SKILL.md, plugins/issue-driven-dev/skills/idd-all/SKILL.md, plugins/issue-driven-dev/CHANGELOG.md, plugins/issue-driven-dev/README.md, plugins/issue-driven-dev/.claude-plugin/plugin.json, .claude-plugin/marketplace.json
  - Removed: (none)
