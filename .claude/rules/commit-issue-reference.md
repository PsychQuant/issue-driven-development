# Commit Issue-Reference Discipline（防 GitHub auto-close trap）

> **Scope**：本 repo 任何 Claude session 撰寫的 commit message 與 PR body。
> **Canonical 全文**：`plugins/issue-driven-dev/CLAUDE.md` § Commit Conventions（含 #97 引用反例寫作紀律、#151 direct-commit path 分析）。本檔是**常駐蒸餾層** — plugin-root CLAUDE.md 不會載入 project context（`claude plugin validate` 明示），故最小指令集放此處 @-import 常駐；完整理據與歷史案例以 canonical 為準，不在此複製（per [[deep-integration-over-hardcode]] 反複製判準）。

## 鐵律

1. **Issue 引用一律放 subject 尾端 `(#N)`，或 body 用 `Refs #N`。**
2. **絕不讓 `close` / `fix` / `resolve` 任何詞形（含 conventional-commit 前綴 `fix:`）鄰接 `#<數字>`。** GitHub auto-close parser 是 server-side、context-blind：`fix: #209 R1 verify findings — …` 這種 subject 在 push 到 main 的瞬間 auto-close #209（2026-07-03 本 repo 親身實證，見 #209 closing comment 的 close-mechanics note；更早前例 `8ac8206`→#70、`a82867d`→#26）。
3. **引用 trap pattern 當反例時**：code fence + literal letter `N`（如 `` `Closes #N` ``），或改用連結引用 — 引號/斜體/粗體都**不會**抑制 parser。
4. **Direct-commit path（本 repo 常態）沒有任何 preventive gate** — 這條寫作紀律是唯一防線（機械 gate 見 #211 追蹤）。Close 動作永遠由 `/idd-close` 執行，不由 trailer 代勞。
