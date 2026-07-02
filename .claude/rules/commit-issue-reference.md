# Commit Issue-Reference（dev 蒸餾 — canonical 在 plugin 層）

> **Canonical（user-facing 完整版）**：`plugins/issue-driven-dev/rules/commit-issue-reference.md`（#214 升格；SessionStart hook 每 session 注入蒸餾版）。本檔僅為 dev session 常駐提醒，normative 修改一律改 canonical。

- Issue ref 放 subject 尾端 `(#N)` 或 body `Refs #N`；close / fix / resolve（含 `fix:` 前綴）**絕不**鄰接 `#<數字>` — `fix: #209 …` 親身踩過即 auto-close（#209）
- 引用反例：code fence + literal `N`；close 一律走 `/idd-close`（被 trap 關掉用 `--retroactive`）

（#213 建立；#214 遷移 canonical 至 plugin 層）
