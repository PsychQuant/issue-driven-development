## Context

`idd-diagnose` v2.36+ 用 4 層 gate 判定 Complexity(Simple / Plan / Spectra),邏輯記在 `plugins/issue-driven-dev/rules/sdd-integration.md`:

```
Layer 1 (disqualifier) → Layer 2 (Spectra necessary) + Layer 3 (Spectra confirmation) → Layer P (Plan signals) → Simple (default)
```

4 層全在量「**改動的形狀**」(narrative deliverable / API surface / files & risk / ordered steps),完全沒衡量「**需求清晰度**」。經 issue #12 + spectra-discuss 收斂,確認 vagueness 是 routing 缺失的一階信號。

Routing parser 散在三處(`idd-diagnose` Step 3.5、`idd-implement` line 271、`idd-all` line 358),都用 grep `### Complexity` 一致字串。任何 verdict 改動需同步三處。

IC_R011 已建立 canonical「3-option AskUserQuestion + PATCH audit trail」pattern(idd-diagnose Step 3.6 / idd-issue Step 4.7 / idd-close Step 3.5 已驗證),Layer V 直接複用此 pattern,不重新發明。

## Goals / Non-Goals

**Goals:**

- 加入 `idd-diagnose` Step 3.4 Vagueness Pre-check,涵蓋 V1 (vague WHAT) + V4 (vague ACCEPTANCE) 兩個 routing 缺口
- 用 Likert 6-point per-axis AI 評分取代 keyword matching,評分理由顯化在 Diagnosis comment 留 audit trail
- 把 Layer V 嵌入 5 層 evaluation order(Layer 1 → V → 2+3 → P → Simple),Layer 1 disqualifier 仍最優先
- 抽出 meta-rule `屬性評分一律用 Likert,不用 keyword` 到 repo-local `.claude/rules/attribute-assessment.md`,適用範圍超越 vagueness
- 維持 6-skill 的 plugin surface(不新增 `idd-clarify`)
- attended / unattended mode 行為一致:attended 跳 3-option,unattended 採 proceed default + audit trail 標記

**Non-Goals:**

- 不處理 V2 (vague HOW):已被 Layer P "decision-heavy" 覆蓋
- 不處理 V3 (vague SCOPE):由 IC_R011 sister sweep (idd-diagnose Step 3.6) 處理,職責不重疊
- 不新增 `idd-clarify` skill (Approach B):plugin surface 維持 6 個
- 不直接讓 vagueness 升級 routing tier (Approach A):EnterPlanMode 是 approve plan 不是 clarify what,語意應分離
- 不採 keyword matching heuristic:中文 hedge 詞 brittle,Likert AI judge 顯化判斷比 keyword 命中更有意義
- 不採 LLM judge 做 routing tier 升降:只用 Likert 給 user 看,trigger 後 user 仍是決策者
- 不對既有 Simple verdict 做回溯重判:Layer V 只對 v2.50+ 之後新跑的 diagnosis 生效
- 不加 `--ignore-vagueness` flag:option B (proceed anyway) 已涵蓋此需求
- 不在 idd-list / idd-report 標記「pre-Vagueness」:noise 大於價值

## Decisions

### D1: Approach C (Step 3.4 in `idd-diagnose`),不新增獨立 skill

**Rejected alternatives:**

- **Approach A (vagueness 直接升 routing tier)**:vague + small → Plan,vague + large → Spectra。reject 理由:EnterPlanMode 設計語意是「approve plan」,不是「clarify what」;routing 結果混合 vagueness + scope 兩個信號,future debug 難分清是哪個觸發。
- **Approach B (新增 `idd-clarify` skill)**:routing 前獨立 clarify step。reject 理由:plugin surface 從 6 → 7,認知負擔上升;與 spectra-discuss 功能 overlap 需要重新定義邊界;Step 3.4 內處理已足夠,沒必要外提。

**Chosen Approach C**:在 `idd-diagnose` Step 3.5 Complexity Assessment 之前插入 Step 3.4 Vagueness Pre-check,trigger 時跳 IC_R011-style 3-option,user 表態後 Step 3.5 才執行。優點:(1) 維持 6-skill surface;(2) 複用既有 IC_R011 canonical pattern,實作成本低;(3) Vagueness 與 Complexity 是兩個正交決策,語意分離。

### D2: Likert 6-point per-axis,不用 keyword matching

**Rejected alternative:**

- **Keyword + structural check**(原 discuss assumption #3):中英 hedge 詞 + 結構檢查(缺 `## Expected` 區段等)。reject 理由:中文 hedge 詞 brittle —「感覺」可能是 vague 也可能是 confident assertion,deterministic 但常常判錯;規則一旦寫死,跨文化適應差。

**Chosen Likert 6-point** (1=完全清楚 → 6=完全模糊),per-axis V1 + V4 各別評分,trigger ≥ 4。優點:(1) 強迫 AI 顯化判斷,留 audit trail 給 user 校準 / 抓 drift;(2) 6 點無中位(中切點落在 3↔4),強迫表態同時保留 nuance;(3) per-axis 透明,知道是哪個維度模糊,易 debug。

**Anchor requirement**:每個 Likert score 必須附 concrete example anchor(否則 AI 飄)。Anchors 寫在 `.claude/rules/attribute-assessment.md` 的 vagueness 範例段落。

### D3: Hybrid 3-option + score-driven default

**Rejected alternatives:**

- **Always ask**:V=4/5/6 全跳同一個 3-option,user 永遠主導但 V=6 也問顯得繁瑣
- **Score-driven**:V=4 自動 proceed / V=5 跳 3-option / V=6 強制 escalate。reject 理由:V=6 強制升級剝奪 user override 權

**Chosen Hybrid**:三段都跳 3-option,但 default option(AskUserQuestion 第一選項)隨 score 變:

| Score | Default option | Rationale |
|-------|----------------|-----------|
| V=4 | proceed anyway | 輕度模糊,通常 user 心中有 mental model |
| V=5 | clarify now | 中度模糊,建議追問 |
| V=6 | escalate to Plan | 重度模糊,建議走 Plan tier 對齊 |

User 任何 score 都能選任何 option,只是 default 不同。AskUserQuestion 預設 highlight first option,改變 default 等於改變 user 路徑的「重力方向」。

### D4: 5 層 evaluation order:Layer 1 → V → 2+3 → P → Simple

Layer 1 disqualifier 仍最優先(narrative / ad-hoc / typo / multi-file independent → 強制 Simple,vagueness 不該推翻)。Layer V 在 Layer 2 之前,因為 V1/V4 命中的 issue 連 diagnose 都做不下去,後面三層的判斷會基於模糊假設。

| Layer 命中順序 | Verdict |
|--------------|---------|
| Layer 1 命中 | Simple(vagueness 也不升)|
| Layer 1 未中 + Layer V 命中 + Layer 2 命中 | Spectra(vagueness 列為觸發因素之一)|
| Layer 1 未中 + Layer V 命中 + Layer 2 未中 | **Plan**(vagueness-driven Plan,verdict format 標記 `Plan via Layer V`)|
| Layer 1 未中 + Layer V 未中 + Layer 2 命中 + Layer 3 命中 | Spectra |
| Layer 1 未中 + Layer V 未中 + Layer P 命中 | Plan |
| 其他 | Simple(default)|

### D5: Meta-rule `attribute-assessment.md` 放 repo-local `.claude/rules/`

**Rejected alternatives:**

- **Plugin `rules/attribute-assessment.md`**:scope = skill execution time,只在 plugin skill 被呼叫時透過 link 載入。reject 理由:屬性評分是 Claude session-wide 行為,不該綁在 plugin 內部
- **Global `~/.claude/CLAUDE.md`**:跨 repo 適用。reject 理由:目前只 IDD 用得到,跨 repo 太廣,先 dogfood 再 promote

**Chosen `.claude/rules/attribute-assessment.md`** + CLAUDE.md `@.claude/rules/attribute-assessment.md` import。優點:(1) repo-local session-wide,Claude 在這個 repo 做任何屬性評估都遵守(包括非 IDD 場景);(2) 留 promote 路徑,證明有用後再升級到 plugin 或 global;(3) plugin 端 `rules/sdd-integration.md` 用 link 引用 `.claude/rules/attribute-assessment.md`,單一 source of truth。

Trade-off 已知:rule 不跟 plugin 走,其他 repo 安裝 plugin 後沒這條 rule。先驗證有用後再移植到 plugin/global。

### D6: 5-axis → 6-axis,新增 Alignment quality 到 MANIFESTO

`MANIFESTO.md` 既有 5-axis bug-fix model(Diagnosis / Fix completeness / Verification independence / Regression prevention / Audit traceability)。新增 **Alignment quality**(問題本身的清晰度)為第 6 軸,evidence = Layer V Vagueness Pre-check。對照表:TDD ❌ / SDD ❌(spec 出現時通常已 align)/ IDD ✅(Layer V 強制檢查)。

## Risks / Trade-offs

### R1: Likert AI judge drift(跨 session 評分不穩定)

**Risk**:同一 issue body 不同 session / 不同 Claude model 可能評出不同分數,routing 不一致。

**Mitigation**:
- Anchor 寫死在 `.claude/rules/attribute-assessment.md`,例子越具體 AI 漂移越小
- AI 必須在 Diagnosis comment 顯示分數 + 理由(audit trail),user 校準 / 抓 drift 直接靠 inspect
- Trigger 後仍是 user 透過 3-option 決策,評分本身不是 routing terminal — 即使分數略有抖動,user 表態能修正
- 後續可加 retrospective table(類似 sdd-integration.md 既有的 motivating examples)記錄誤判 case

### R2: 過度 trigger(false positive)

**Risk**:每個 issue 都被打 V≥4,user 疲勞 → 學會無視 prompt → checkpoint 失效

**Mitigation**:
- Anchor 設計刻意把「3 (偏清楚)」放寬,避免 inflation
- Trigger 後 default option 隨 score 變(V=4 default proceed),輕度模糊不打擾
- Tasks 包含 dry-run section:對既有 close 的 issues 跑一次 retrospective scoring,fine-tune anchor

### R3: V3 / V4 邊界與 IC_R011 重疊

**Risk**:V4 (vague acceptance) 跟 IC_R011 sister sweep 在某些 case 都能觸發 → user 看到 Step 3.4 + Step 3.6 兩個 prompt,困惑

**Mitigation**:
- Spec scenario 明確區分 V4 (主軸完成定義模糊) vs sister concern (主軸清楚 + 周邊有 sibling)
- `attribute-assessment.md` 加註:V3 (vague scope) 不在 Layer V 範圍,推到 IC_R011

### R4: Backward compat — 既有 Simple verdict 沒 Layer V 評估

**Risk**:既有 `Simple` verdict diagnoses 從未做 vagueness check,可能有「應該 Plan 但被路 Simple」的舊 issue 散落

**Decision**:接受 risk,不做回溯重判。Audit trail 完整性比回溯一致性重要。後續可手動 re-diagnose 高優先 issue。

### R5: 跨 plugin 不一致(rule 在 repo,plugin 不帶)

**Risk**:Plugin 安裝到其他 repo 後,沒 `.claude/rules/attribute-assessment.md`,Layer V 機制 partial broken

**Mitigation**:
- `idd-diagnose` Step 3.4 開頭檢查 `.claude/rules/attribute-assessment.md` 是否存在,缺就 fallback 到 plugin internal anchor 並印 warning「This repo has no project rule for attribute-assessment;using plugin built-in anchors」
- 或 Tasks 包含後續 promote step:dogfood 一個 release cycle 後 promote 到 plugin internal

### R6: `idd-all` unattended mode 失去 alignment 價值

**Risk**:unattended mode 採 proceed default,vagueness trigger 等於沒做檢查

**Decision (per D3 + idd-all 既有 pattern)**:接受 — unattended mode 本來就是「user 不在現場」的情境,跟 Plan tier 在 unattended 也直接跳過同樣設計。Trigger 事實寫進 audit trail (`[Layer V: V1=N V4=M, clarify-default skipped under unattended mode, defaulting to proceed]`),user 後續 review 仍能看到。
