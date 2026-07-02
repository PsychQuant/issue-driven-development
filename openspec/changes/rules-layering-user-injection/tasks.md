## 1. 分層判準（design: D1 — 分層判準 = 受益者軸，判準檔留 dev 層；A1）

- [x] 1.1 [P] 新增 .claude/rules/rules-layering.md：受益者軸判準（使用者行為 → plugin 層 / 維護者決策 → dev 層）、兩層現有 rules 對照表（dev 3 + plugin 7）、歸位程序（供 #215 使用），並在專案 CLAUDE.md `## Project Rules` @-import。完成判準：檔案存在含三段（content review）+ grep CLAUDE.md 命中 @-import 行。

## 2. Canonical 遷移（design: D2 — canonical 遷移與蒸餾鏈；A2；spec: Canonical user-facing rule location）

- [x] 2.1 [P] 新增 plugins/issue-driven-dev/rules/commit-issue-reference.md（user-facing 完整版 normative core，實現 requirement「Canonical user-facing rule location」）：四條鐵律、trap 機制說明、歷史案例指回 plugins/issue-driven-dev/CLAUDE.md § Commit Conventions。完成判準：檔案含四條鐵律（content review），對應 scenario「Single canonical source」。
- [x] 2.2 縮寫 .claude/rules/commit-issue-reference.md 為 ≤10 行蒸餾 + 指回 canonical 路徑；plugins/issue-driven-dev/CLAUDE.md § Commit Conventions 開頭加一行 normative-core 指向。完成判準：dev 檔 `wc -l` ≤ 10 且含 canonical 路徑；plugin CLAUDE.md grep 命中指向行。

## 3. SessionStart hook + drift guard（design: D3 — 注入機制並用；hook 輸出 ≤5 行 + D4 — hook static 內容 + drift-guard 測試；A3/A4；spec: SessionStart rule injection is minimal and canonical-aligned）

- [x] 3.1 TDD RED：新增 plugins/issue-driven-dev/scripts/tests/session-start-commit-rule/test.sh，斷言 (1) hooks/hooks.json 合法 JSON 且含 SessionStart entry 指向 `${CLAUDE_PLUGIN_ROOT}/hooks/session-start-commit-rule.sh` (2) script 可執行、exit 0 (3) 輸出 ≤ 5 行 (4) 關鍵 token（`(#N)`、`Refs #N`、close-keyword 警語、`/idd-close`、canonical 路徑）同現於 hook 輸出與 canonical rules 檔。完成判準：實作前跑 suite 為 RED（hook 未存在），對應 scenario「Drift guard enforces alignment」。
- [x] 3.2 實作 plugins/issue-driven-dev/hooks/hooks.json + hooks/session-start-commit-rule.sh（static ≤5 行輸出，實現 requirement「SessionStart rule injection is minimal and canonical-aligned」）。完成判準：3.1 suite 全 GREEN + `claude plugin validate` 通過，對應 scenario「Hook fires on session start」。

## 4. Skill-scope 引用（design: D3 — 注入機制並用（skill-scope 半邊）；spec: Skill-scope reference at commit-authoring sites）

- [x] 4.1 idd-implement 與 idd-all 的 commit 規範段各加一行指向 plugins/issue-driven-dev/rules/commit-issue-reference.md，實現 requirement「Skill-scope reference at commit-authoring sites」。完成判準：兩檔 grep `rules/commit-issue-reference.md` 各 ≥1 hit，對應 scenario「Skill references present」。

## 5. 發佈掃尾（design: D5 — 版本 2.91.0（minor）；A5）

- [x] 5.1 CHANGELOG 新增 2.91.0 條目（additive）；plugin.json 與 marketplace.json 版本 2.90.0 → 2.91.0；README 補 SessionStart hook 行為說明。完成判準：grep 2.91.0 三檔命中。
- [x] 5.2 跑 `spectra validate rules-layering-user-injection` 與 `spectra analyze rules-layering-user-injection`，Critical/Warning 清零；全 hook 測試 suite GREEN。完成判準：命令輸出無 Critical/Warning、suite exit 0。
