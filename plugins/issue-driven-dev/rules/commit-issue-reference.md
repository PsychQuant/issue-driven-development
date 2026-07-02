# Commit Issue-Reference Discipline（user-facing canonical）

> **Scope**：任何使用 IDD 的 repo 的 commit message / PR body 撰寫。GitHub 的 auto-close parser 是 server-side、**context-blind** — 在 direct-commit path 上，這些鐵律是唯一防線（preventive gate 見 PsychQuant/issue-driven-development#211）。
>
> 本檔是 canonical：`plugins/issue-driven-dev/rules/commit-issue-reference.md`（#214 自 dev 層升格）。SessionStart hook（`hooks/session-start-commit-rule.sh`）每 session 注入 ≤5 行蒸餾；drift guard：`scripts/tests/session-start-commit-rule/test.sh`。

## 四條鐵律

1. **Issue ref 放 commit subject 尾端 `(#N)`**，或 body 用 `Refs #N`。
2. **絕不讓 close / fix / resolve 任何詞形（含 conventional-commit 前綴如 `fix:`）鄰接 `#<數字>`**。`fix: #209 R1 verify findings — …` 這種 subject 在 push 到 main 的瞬間 auto-close 了 #209（2026-07-03 實證；更早前例：subject `resolves #70` 形式關掉 #70、`fix #26` 形式關掉 #26）。引號、粗體、斜體、「Do NOT」前後文都**不會**抑制 parser。
3. **引用 trap pattern 作反例時**：code fence + literal letter `N`（如 `` `Closes #N` ``），或改用連結引用不重複 keyword。
4. **Close 永遠由 `/idd-close` 執行**（checklist gate + closing summary + 掃尾），不由 trailer 代勞。已被 trap auto-close 的 issue 用 `/idd-close --retroactive #N` 補救。

## 完整理據與歷史案例

見 plugin CLAUDE.md「Commit Conventions」章（#97 引用反例寫作紀律、#151 direct-commit path 分析、#173 hyphen-split 陷阱、#176 retroactive 補救）。
