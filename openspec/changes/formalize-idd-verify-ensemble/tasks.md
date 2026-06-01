## 1. Phase 0 — Codex 終止 spike（gates D3）

- [x] 1.1 [Requirement: Cross-model verifier runs with a bounded lifetime] [D3] 驗證「停止一個 workflow agent 能 clean-kill 它 shell-out 的 hung `codex exec` 子程序」。**Behavior**：於 workflow agent 內跑一個故意 hang 的 codex 呼叫，對該 agent 發 stop 後子程序被終止、無 orphan。**Verification**：spike trace 記錄 pass/fail，`ps` 確認無殘留 codex；結果寫進 design.md「Codex clean-kill」open question，據此定 Decision D3 走 inside-workflow（pass）或 external + timeout（fail）。

## 2. Phase 1 — workflow 核心 + findings 契約

- [x] [P] 2.1 [Requirement: Independent-agent cross-verification ensemble] 定義 workflow structured findings 的 JSON schema，保留現行 merged 輸出 shape（severity / file / title / body / lens）。**Behavior**：workflow agent 回傳的 findings 通過 schema 驗證，欄位與現行 manual 合併輸出等價。**Verification**：schema 對樣本 findings validate 通過；對照現行 master report 欄位無缺漏（content review）。
- [x] [P] 2.3 [D2] 解決 Decision D2：確認 plugin 能否 bundle / register saved workflow 給 consuming session，選 bundled-by-name 或 inline，把決定 + registration path 寫回 design.md。**Behavior**：idd-verify 能以選定機制取得並執行該 workflow。**Verification**：乾淨 session 觸發 idd-verify 能跑到 workflow（manual）；決定與路徑記於 design.md（content review）。
- [x] 2.2 [Requirement: Deterministic core runs on the dynamic-workflow primitive when available] [Requirement: Independent-agent cross-verification ensemble] [D1] [D3] 實作 verify-ensemble 的 dynamic-workflow script：fan-out 5 reviewers → 每個 review 完成即由 devil's-advocate 對抗驗證的 pipeline → cross-model pass → merge + dedup → 回傳 validated findings array；依 1.1 spike 結果決定 Codex 放 workflow 內或外。**Behavior**：對真實 PR 跑該 workflow，產出 merged + deduped findings array、severity 取最高。**Verification**：workflow 於 `/workflows` 可見、回傳非空 findings array；對已知有 finding 的 PR 能抓到（manual assertion）。依賴 1.1、2.1、2.3。

## 3. Skill 整合（hybrid split + capability gate + fallback）

- [ ] 3.1 [Requirement: Graceful degradation to manual fan-out with an identical findings contract] [D1] [D4] 在 idd-verify skill 加 capability detection + backend 選擇：primitive 可用 → 跑 workflow 並 await findings；不可用 → 跑現行 manual fan-out；兩條路皆印 backend notice。**Behavior**：`/idd-verify #N` 依 primitive 可用性自動選 backend 並印 notice，兩條路產出相同 findings contract。**Verification**：primitive 開 / 關各跑一次，findings shape + 下游 posting/triage 一致（manual assertion）。依賴 2.2。
- [ ] 3.2 [Requirement: Deterministic core executes under unattended interaction semantics] [D1] [D5] 確保 gates（input-source / PR↔issue / auto-close 偵測）、GitHub master + pointer 發文、follow-up triage、verify-fix loop 全留在 skill、在 core 之前 / 之後執行，core 內零 user input。**Behavior**：core 執行期間無任何 AskUserQuestion；user-facing 決策在 core 前 / 後。**Verification**：一次完整 verify 跑程中 core 階段無 prompt（manual observation）；gates / triage 照常觸發。依賴 3.1。
- [ ] 3.3 [Requirement: Graceful degradation to manual fan-out with an identical findings contract] [D4] 保留 manual fan-out 為 live fallback（zero-regression）。**Behavior**：無 primitive 的環境，idd-verify 行為與本 change 前完全相同。**Verification**：關閉 primitive 跑一次，結果與現行 baseline 等價（manual assertion）。依賴 3.1。

## 4. Spec Purpose 確保 + 分發

- [ ] 4.1 archive 後確認 `openspec/specs/idd-verify/spec.md` 帶真 Purpose 而非 TBD stub；若 archive 未 materialize delta 的 Purpose（Spectra Purpose gap，見 kaochenlong/spectra-app#100），手動填入 delta 內 Purpose 文字。**Behavior**：materialized spec 的 Purpose 非 `TBD ... Update Purpose after archive`。**Verification**：`grep -L "Update Purpose after archive" openspec/specs/idd-verify/spec.md` 確認無 stub（CLI）。
- [ ] 4.2 CHANGELOG 條目 + version bump（plugin.json + marketplace.json 同步）。**Behavior**：版本反映新 feature，CHANGELOG 記錄 idd-verify spec + workflow 採用。**Verification**：plugin.json 與 marketplace.json 版本一致且高於前版、CHANGELOG 有條目（content review）。依賴 3.x、4.1。
