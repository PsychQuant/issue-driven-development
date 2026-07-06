# Rules Layering（受益者軸）

> **Scope**：本 repo 維護者決定「一條 rule 該放哪一層」時。dev-only rule（判準的受眾是維護者，不隨 plugin 發佈）。建立於 #214。

## 判準（受益者軸）

- rule 約束的行為發生在「**任何使用 IDD 的 repo / 人**」→ **plugin 層** `plugins/issue-driven-dev/rules/`（隨 plugin 發佈；skill 執行時由 SKILL.md 引用）。若該紀律的主戰場在 **skill 之外**（如手動 commit），需 ambient 觸達 → 加 SessionStart hook 極簡版，**輸出行數上限 5**（所有使用者每 session 付 context 稅，由 drift-guard 測試硬鎖）。
- rule 只約束「**開發 IDD 本身**的決策」→ **dev 層** `.claude/rules/` + 專案 CLAUDE.md `## Project Rules` @-import（不 import 不會載入 — #209 R1 verify 教訓）。

## 現狀對照（2026-07-03）

| Rule | 層 | 依據 |
| ---- | --- | ---- |
| attribute-assessment | dev | 自述未達 rule-of-three promote 門檻 |
| deep-integration-over-hardcode | dev | #209 Clarity row 3 使用者裁決（「是我開發要用的」）|
| rules-layering（本檔）| dev | 判準受眾是維護者 |
| commit-issue-reference | **plugin**（#214 升格）| auto-close trap 咬所有 IDD 使用者；dev 層留蒸餾指回 |
| tagging-collaborators / privacy-scrubbing / append-vs-modify / sdd-integration / process-attachments / spectra-bridge / github-math-format | plugin | 約束 skill 執行時的使用者行為 |

## 歸位程序（#215 全面盤點用）

1. 問「這條 rule 保護／約束的行為，發生在誰身上？」— 使用者 → plugin 層；維護者 → dev 層。
2. 進 plugin 層且主戰場在 skill 外 → 評估 ambient 注入（SessionStart hook，≤5 行；值不值得付 context 稅是逐案 maintainer judgment）。
3. 移動時**絕不留平行複本** — 原位置縮為蒸餾 + 指回 canonical（per [[deep-integration-over-hardcode]] 反複製判準）。
4. 歸位依據記入對應 issue / PR（audit trail）。
