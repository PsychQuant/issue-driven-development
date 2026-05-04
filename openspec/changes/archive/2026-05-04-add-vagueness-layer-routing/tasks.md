## 1. Foundation — Attribute Assessment Meta-Rule

- [x] 1.1 建立 `.claude/rules/attribute-assessment.md`,codify「屬性評分用 Likert 6-point per-axis,不用 keyword matching」meta-rule(per D5: Meta-rule `attribute-assessment.md` 放 repo-local `.claude/rules/`)
- [x] 1.2 在 `attribute-assessment.md` 內寫 V1 + V4 6-point anchors + 具體例子(per D2: Likert 6-point per-axis,不用 keyword matching;對應 spec Requirement: Vagueness scoring uses Likert 6-point per axis)
- [x] 1.3 在 `attribute-assessment.md` 註明 V3 不在 Layer V 範圍,推到 IC_R011 sister sweep(addresses R3: V3 / V4 邊界與 IC_R011 重疊)
- [x] 1.4 修改 root `CLAUDE.md` 加 `@.claude/rules/attribute-assessment.md` import(per D5)

## 2. Plugin Routing Rule — sdd-integration.md

- [x] 2.1 在 `plugins/issue-driven-dev/rules/sdd-integration.md` 加新章節 "Layer V: Vagueness signals",描述 trigger threshold per-axis ≥ 4(對應 spec Requirement: Trigger threshold is per-axis ≥ 4)
- [x] 2.2 更新 sdd-integration.md 的 evaluation order 從 4 層 → 5 層(per D4: 5 層 evaluation order:Layer 1 → V → 2+3 → P → Simple;對應 spec Requirement: Vagueness Pre-check executes between Layer 1 and Layer 2)
- [x] 2.3 在 sdd-integration.md Layer V 段落 link 引用 `.claude/rules/attribute-assessment.md`(單一 source of truth,per D5)
- [x] 2.4 加 Layer V retrospective dry-run table 到 sdd-integration.md(類似既有 motivating examples,addresses R2: 過度 trigger(false positive))

## 3. idd-diagnose Step 3.4 Implementation

- [x] 3.1 在 `plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md` Step 3.5 之前插入 Step 3.4 Vagueness Pre-check(per D1: Approach C (Step 3.4 in `idd-diagnose`),不新增獨立 skill)
- [x] 3.2 Step 3.4 包含:讀 issue body → AI 用 attribute-assessment rule 評 V1 + V4 Likert 1-6 → 輸出兩 score + reasoning 到變數(對應 spec Requirement: Vagueness scoring uses Likert 6-point per axis)
- [x] 3.3 Step 3.4 加 attribute-assessment 檔案存在性 fallback check:缺檔印 warning「This repo has no project rule for attribute-assessment;using plugin built-in anchors」並用 plugin internal anchors(addresses R5: 跨 plugin 不一致(rule 在 repo,plugin 不帶))
- [x] 3.4 Step 3.4 trigger 判斷:`max(V1, V4) >= 4` → 進 Hybrid 3-option;否則跳 Step 3.5(對應 spec Requirement: Trigger threshold is per-axis ≥ 4)
- [x] 3.5 實作 Hybrid 3-option AskUserQuestion(`clarify now` / `proceed anyway` / `escalate to Plan`),default option 隨 max score 變(per D3: Hybrid 3-option + score-driven default;對應 spec Requirement: Triggered Layer V presents Hybrid 3-option AskUserQuestion)
- [x] 3.6 實作 `clarify now` choice handler:1-3 focused questions → 拿 user answer → `gh issue edit` append "Clarification (added during diagnose)" 區塊 → 重跑 Step 3.4 + Step 3.5(對應 spec Requirement: 3-option choices have defined effects on routing)
- [x] 3.7 實作 `proceed anyway` choice handler:跳過 clarify,寫 audit trail `Layer V triggered (V1=N V4=M), user opted to proceed`,進 Step 3.5(對應 spec Requirement: 3-option choices have defined effects on routing)
- [x] 3.8 實作 `escalate to Plan` choice handler:verdict 直接設 `Plan via Layer V`,跳過 Step 3.5 Layer 2/3/P 評估(對應 spec Requirement: 3-option choices have defined effects on routing)
- [x] 3.9 PATCH Diagnosis comment 加 `### Vagueness Pre-check` 區段:trigger / 不 trigger 都要寫,記 V1 / V4 score + reasoning + user choice + 結果(對應 spec Requirement: Audit trail SHALL be appended to Diagnosis comment)
- [x] 3.10 更新 Step 0 TaskCreate 清單加 `vagueness_precheck` task(對齊 stage task list 強制要求)

## 4. Unattended Mode Adaptation

- [x] 4.1 idd-diagnose Step 3.4 偵測 UNATTENDED MODE directive,trigger 時自動 apply `proceed anyway` + 寫 audit `[Layer V: V1=N V4=M, clarify-default skipped under unattended mode, defaulting to proceed]`(per D3 + 對應 spec Requirement: Unattended mode skips clarify default and proceeds;addresses R6: `idd-all` unattended mode 失去 alignment 價值)
- [x] 4.2 更新 `plugins/issue-driven-dev/skills/idd-all/SKILL.md` line 358 區段附近,記錄 Layer V 在 unattended mode 的 fallback 行為到 final report

## 5. Routing Parser Updates(idd-implement / idd-all)

- [x] 5.1 更新 `plugins/issue-driven-dev/skills/idd-implement/SKILL.md` line 271 parser:接受 `### Complexity\nPlan via Layer V` 並提取 canonical tier = `Plan`(對應 spec Requirement: Routing parsers SHALL recognize Plan via Layer V verdict)
- [x] 5.2 更新 `plugins/issue-driven-dev/skills/idd-all/SKILL.md` line 358 parser regex 同上
- [x] 5.3 確認 backward compat:bare `Plan` verdict(無 suffix)行為不變(對應 spec Requirement: Routing parsers SHALL recognize Plan via Layer V verdict — Backward compat scenario)

## 6. MANIFESTO Update — 6-Axis Bug-fix Model

- [x] 6.1 在 `plugins/issue-driven-dev/MANIFESTO.md` 把 5-axis 表擴成 6-axis,新增「6. Alignment quality(問題本身的清晰度)」軸,evidence = Layer V Vagueness Pre-check(per D6: 5-axis → 6-axis,新增 Alignment quality 到 MANIFESTO)
- [x] 6.2 在 6-axis 表標 TDD ❌ / SDD ❌ / IDD ✅,並寫 1-2 句 rationale(per D6)

## 7. Backward Compatibility

- [x] 7.1 在 sdd-integration.md 加 backward compat 段落:既有 `Simple` / `Plan` / `Spectra` / `SDD-warranted` verdict 全部保留,Layer V 只對 v2.50+ 之後新跑的 diagnosis 生效(對應 spec Requirement: Backward compatibility with pre-Layer V diagnoses)
- [x] 7.2 在 sdd-integration.md 註明:不加 `--ignore-vagueness` flag(option B 已涵蓋此需求,addresses R4: Backward compat — 既有 Simple verdict 沒 Layer V 評估)

## 8. Dry-run + Anchor Calibration

- [x] 8.1 跑 retrospective scoring on 既有 closed issues(取 5-10 個 sample),驗證 anchors 合理 + 沒 inflation(addresses R1: Likert AI judge drift(跨 session 評分不穩定);addresses R2: 過度 trigger(false positive))
- [x] 8.2 根據 dry-run 結果 fine-tune `attribute-assessment.md` anchors(若 inflation 嚴重就放寬「3 偏清楚」邊界)
- [x] 8.3 在 sdd-integration.md retrospective table 記錄 dry-run sample 結果(類似既有 motivating examples format)

## 9. Release & Cross-link

- [x] 9.1 Bump `plugins/issue-driven-dev/.claude-plugin/plugin.json` version → 2.50.0
- [x] 9.2 更新 `plugins/issue-driven-dev/CHANGELOG.md` 加 v2.50.0 entry,描述 Layer V Vagueness Pre-check + meta-rule attribute-assessment + 6-axis MANIFESTO update
- [x] 9.3 在 issue #12 留 comment cross-link Spectra change `add-vagueness-layer-routing`,等 spectra-archive 後 close issue
- [x] 9.4 跑 `/plugin-tools:plugin-update issue-driven-dev` sync marketplace
