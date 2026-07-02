## Context

#214（A1–A5 使用者確認在 decision comment）。現狀：dev 層 3 條 rules 經專案 CLAUDE.md @-import 常駐（僅本 repo）；plugin 層 7 條 rules 全 skill-scope；plugin 無 hooks dir；plugin-root CLAUDE.md 不載入使用者 session（`claude plugin validate` 警告）。commit-issue-reference 的保護對象是所有 IDD 使用者，但 skill 外手動 commit（trap 主戰場，#209 close 時親身實證）目前無任何管道可達使用者。

## Goals / Non-Goals

**Goals:**

- 分層判準文件化（受益者軸），可供 #215 全面盤點重用
- commit-issue-reference 以 single canonical source 觸達使用者：ambient（hook 極簡版）+ skill-scope（完整版）
- hook 輸出與 canonical 內容有機械 drift guard

**Non-Goals:**

- 不做全面 rules 盤點歸位（#215，blocked by 本 change 的判準）
- 不動其他 6 條 plugin rules、不動 deep-integration / attribute-assessment（dev-only 維持）
- 不做動態 hook 內容生成（A4：static + 測試對齊）
- 不處理 hook 的 per-user 關閉開關（YAGNI；使用者可自行 disable plugin hook，需求出現再議）

## Decisions

### D1 — 分層判準 = 受益者軸，判準檔留 dev 層

rule 約束的行為發生在「任何使用 IDD 的 repo / 人」→ plugin 層（隨發佈）；只約束「開發 IDD 本身的決策」→ dev 層。判準檔受眾是維護者 → dev 層 + @-import。替代方案「判準隨 plugin 發佈」被排除：對使用者是 noise。

### D2 — canonical 遷移與蒸餾鏈

single canonical = plugins/issue-driven-dev/rules/commit-issue-reference.md（user-facing 完整版）。dev 層原檔縮為 ≤5 行蒸餾 + 指回；plugin CLAUDE.md § Commit Conventions 保留歷史案例、normative core 加一行指向 rules 檔。替代方案「三份平行維護」違反反複製判準（deep-integration-over-hardcode 既有 rule）。

### D3 — 注入機制並用；hook 輸出 ≤5 行

SessionStart hook（唯一能蓋 skill 外 commit 的 ambient 管道）印 4 行鐵律 + 1 行指路；完整版供 skill-scope。hooks.json 用 `${CLAUDE_PLUGIN_ROOT}` 解析 script 路徑（生態系 SessionStart 先例同型）。替代方案：只 hook（skill 內失去錨點）、只 skill-scope（主戰場裸奔）、README 教學（依賴手動）— 皆劣。行數上限是硬約束：所有使用者每 session 付 context 稅，超過即 drift guard 測試 FAIL。

### D4 — hook static 內容 + drift-guard 測試

hook script 印 static 文字；scripts/tests/session-start-commit-rule/test.sh 斷言：(1) 輸出 ≤5 行 (2) 關鍵 token（`(#N)`、`Refs #N`、`close/fix/resolve`、`/idd-close`、rules 檔路徑）同時存在於 hook 輸出與 canonical rules 檔（token 對齊而非全文 diff — 允許措辭差異、擋語意漂移）(3) script 可執行且 exit 0。替代方案「sed 從 rules 檔動態抽」脆弱且讓 hook 依賴檔案佈局。

### D5 — 版本 2.91.0（minor）

hook 為 additive 新元件、無 breaking。repo 2.x 慣例（#209 close 時確認）。

## Implementation Contract

- hooks/hooks.json 為合法 JSON，SessionStart entry 指向 `${CLAUDE_PLUGIN_ROOT}/hooks/session-start-commit-rule.sh`；script 可執行、輸出 ≤5 行、含 D4 列舉的關鍵 token — 全部由 drift-guard 測試可驗
- plugins rules 檔含四條鐵律（(#N) 尾端 / 不鄰接 / code-fence reference / /idd-close 唯一 close 管道）+ trap 歷史指回 plugin CLAUDE.md
- dev 層 commit-issue-reference.md ≤10 行且含指回路徑；rules-layering.md 含判準 + 對照表 + 歸位程序，CLAUDE.md @-import 三處 rule 齊列
- idd-implement / idd-all 的 commit 段各含一行 rules 檔指向（grep 可驗）
- 行為驗證：直接執行 hook script 檢查輸出；`claude plugin validate` 通過；三檔版本 2.91.0 一致
- spectra validate 綠；測試套件全綠

## Risks / Trade-offs

- 所有使用者每 session 付 ~5 行 context 稅 — 上限由測試硬鎖，超標即 FAIL
- hook 與 rules 檔措辭漂移 — token 對齊測試擋語意層，不擋純措辭（可接受）
- 使用者若 disable hook 則回到 skill-scope-only 保護 — 已知且可接受（他們的選擇）
