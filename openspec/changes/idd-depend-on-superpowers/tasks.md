## 1. 依賴宣告（design: D1 — 依賴宣告走 native dependencies，target = claude-plugins-official；spec: Superpowers install-time dependency declaration）

- [x] 1.1 [P] 在 plugins/issue-driven-dev/.claude-plugin/plugin.json 新增 `dependencies` 陣列，含條目 `{"name": "superpowers", "marketplace": "claude-plugins-official"}`（無 version 欄位），實現 requirement「Superpowers install-time dependency declaration」的宣告半邊。完成判準：`claude plugin validate` 通過 manifest 檢查，且 grep `"dependencies"` 於 plugin.json 命中該條目。
- [x] 1.2 [P] 在 .claude-plugin/marketplace.json 新增 `"allowCrossMarketplaceDependenciesOn": ["claude-plugins-official"]`，實現同 requirement 的 allowlist 半邊。完成判準：`python3 -m json.tool` 通過且欄位值含 `claude-plugins-official`，對應 scenario「Cross-marketplace resolution is allowlisted」。

## 2. Pre-flight helper（design: D2 — hard 語意 = 缺席即 fail-fast，無 vendored fallback（與 pai 刻意分岔）+ D5 — pre-flight 雙重驗證，接口 = skill 名稱；spec: Dual pre-flight at delegation sites）

- [x] 2.1 延伸 plugins/issue-driven-dev/scripts/check-plugin-presence.sh 支援 skill-level 檢查，實現 requirement「Dual pre-flight at delegation sites」：新增第三個可選參數（目標 skill 名稱），檢查 plugin cache 內該 plugin 最高版本目錄下 `skills/<name>/SKILL.md` 存在；缺 plugin 或缺 skill 皆非零 exit，stderr 訊息含一步安裝指令 `claude plugin install superpowers@claude-plugins-official` 並指名缺失的 skill，絕不 fallback。完成判準：手動以存在 / 不存在的 plugin 與 skill 名稱各跑一次，exit code 與訊息符合上述（4 個 case 全驗）。

## 3. Delegation 三點（design: D3 — delegation 三點、keep 三類；spec: Process-discipline delegation）

- [x] 3.1 修改 plugins/issue-driven-dev/skills/idd-implement/SKILL.md：TDD 執行段改為 pre-flight（呼叫 2.1 helper，帶 skill 名 `test-driven-development`）+ invoke `superpowers:test-driven-development` 的指示，移除內建 RED-GREEN-REFACTOR 等價敘述；保留 IDD 的 commit refs #N 與 scope 控制段落（requirement「Process-discipline delegation」的 wrapper 紀律保留半邊）。完成判準：SKILL.md 內 grep 不到獨立的內建 TDD loop 敘述、grep 得到 delegation 指示與 fail-fast 模板，對應 scenario「TDD loop delegates while commit discipline stays」。
- [x] 3.2 同檔完成前檢查段：pre-flight + invoke `superpowers:verification-before-completion`，保留 IDD 的 Implementation Complete comment 格式。完成判準：grep 得到該 delegation 指示；comment 模板未被移除。
- [x] 3.3 修改 plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md：bug 型 Step 2 的執行框架改為 pre-flight + invoke `superpowers:systematic-debugging`，保留 Diagnosis Report 模板與 comment 紀律。完成判準：grep 得到 delegation 指示；`## Diagnosis` report 模板原樣，對應 scenario「Bug RCA delegates while report format stays」。

## 4. R1 rule（design: D4 — R1 rule 內容以 pai 案例為 exemplar）

- [x] 4.1 [P] 新增 .claude/rules/deep-integration-over-hardcode.md：判準鏈（canonical 套件存在 → 上游接口穩定 → 深度整合形狀選擇 fail-fast / frozen-fork）、三個具名例外（上游無穩定契約、隱私/安全邊界、時序解耦）各附記錄格式、pai 案例（idd-verify-depend-on-pai-engine）與本 change 作為兩個 exemplar。完成判準：檔案存在且含上述三段（content review），**並在專案 CLAUDE.md `## Project Rules` @-import**（R1 verify #2 更正：同層不 import 不會載入 — attribute-assessment.md 的「常駐」正是靠 @-import 達成）。

## 5. 行為驗證與掃尾

- [x] 5.1 模擬 superpowers 缺席（暫時 rename `~/.claude/plugins/cache/claude-plugins-official/superpowers`）：驗證 2.1 helper 對三個 delegation 用的 skill 名稱皆 fail-fast 且訊息含安裝指令；恢復後重跑皆通過。完成判準：缺席/恢復兩態 × helper 呼叫全數符合 scenario「Plugin absent triggers fail-fast」與「Plugin present but target skill renamed upstream」（後者以假 skill 名模擬）。
- [x] 5.2 [P] 驗證 keep 列未被觸碰，實現 requirement「Kept disciplines are excluded from delegation」：git diff 確認 plugins/issue-driven-dev/skills/idd-verify/SKILL.md、worktree isolation 相關檔案、plugins/issue-driven-dev/skills/idd-plan/SKILL.md 零改動。完成判準：git diff 路徑清單不含上述任何檔案，對應 scenario「Verify backend unaffected」。
- [x] 5.3 CHANGELOG 新增 2.90.0 條目（標 **BREAKING**：升級後未裝 superpowers 的 idd-implement / idd-diagnose bug 路徑 abort，附一步修復指令）；plugin.json 與 marketplace.json 版本同步 2.90.0；README 安裝段補 dependencies 自動安裝說明與 Claude Code 最低版本註記（v2.1.110+ / v2.1.143+）。完成判準：三檔版本字串一致（grep 2.90.0 三處命中）。
- [x] 5.4 跑 `spectra validate idd-depend-on-superpowers` 與 `spectra analyze idd-depend-on-superpowers`，Critical/Warning 清零。完成判準：兩命令輸出無 Critical/Warning。
