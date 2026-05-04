## Why

`idd-diagnose` 的 Complexity routing(`rules/sdd-integration.md` v2.36+ 4 層 gate)完全沒衡量「需求清晰度」 — 4 層全在量「改動的形狀」(scope / API surface / risk)。

結果:**scope 小 + 需求模糊** 的 issue(例:「menu 感覺怪怪的,改一下」)會被一律判 Simple → AI 直接進 TDD loop → pattern-match 一個方向就動手 → 改完才發現「不是這個意思」→ 重做。

這個失敗模式 `spectra-discuss` 想防(已承認「AI 常常高估 diagnosis 完整度」),但只在 Spectra path 內處理 — Simple path 沒有對應的 alignment gate,Plan path 的 EnterPlanMode 也只在被路到 Plan 後才會觸發。**vagueness 沒進入 routing 信號的話,quadrant A(small + vague)永遠不會被路到 Plan**。

來源:GitHub issue [#12](https://github.com/PsychQuant/issue-driven-development/issues/12)

## What Changes

- **新增 Layer V (Vagueness Pre-check)** 進 `idd-diagnose` Step 3.4(Step 3.5 Complexity Assessment 之前)
- **Likert 6-point 評分**(無中位):AI 對 V1(vague WHAT)+ V4(vague ACCEPTANCE)各別評分 1–6,trigger ≥ 4
- **Hybrid 3-option AskUserQuestion**:trigger 後跳 user(`clarify now` / `proceed anyway` / `escalate to Plan`),default option 隨 score 變(V=4 → proceed / V=5 → clarify / V=6 → escalate)
- **5 層 evaluation order**:Layer 1 disqualifier → **Layer V** → Layer 2+3 (Spectra) → Layer P (Plan) → Simple (default)
- **Verdict 升級規則**:vagueness 命中且 Layer 2 沒命中 → Plan;vagueness 命中且 Layer 2 命中 → Spectra(本來就是);vagueness 命中且 Layer 1 命中 → 仍守 Simple(disqualifier 優先)
- **新增 meta-rule 檔案** `.claude/rules/attribute-assessment.md`:codify「**屬性評分一律用 Likert,不用 keyword matching**」原則,適用範圍超越 vagueness(未來其他 attribute scoring 場景沿用)
- **CLAUDE.md** 加 `@.claude/rules/attribute-assessment.md` import 讓 Claude session-wide 遵守
- **MANIFESTO.md** 5-axis bug-fix model → 6-axis,新增「**Alignment quality**」軸,evidence = Layer V
- **無 backward compat 回溯**:既有 `Simple` verdict diagnoses 不重判;Layer V 只對 v2.50+ 之後新跑的 diagnosis 生效
- **不加 `--ignore-vagueness` flag**:option B(proceed anyway)已涵蓋此需求,加 flag 會讓 user 養成繞過習慣

## Non-Goals

- **不改 V2 / V3 處理**:V2(vague HOW)已被 Layer P "decision-heavy" 覆蓋,維持原樣;V3(vague SCOPE)由 IC_R011 sister sweep 處理(已存在於 idd-diagnose Step 3.6),不重複機制
- **不新增 `idd-clarify` skill**(rejected Approach B):plugin surface 維持 6 個 skill;clarify 的對齊責任放在 Step 3.4 內,不外提到獨立 skill
- **不直接升級 routing tier**(rejected Approach A):vagueness 命中不直接改 verdict,而是透過 user 在 3-option 內表態(clarify / proceed / escalate)— EnterPlanMode 是「approve plan」不是「clarify what」,語意應分離
- **不採用 keyword matching heuristic**(rejected Approach):中文 hedge 詞(「感覺」「之類」)brittle 且文化差異大,Likert AI judge 顯化判斷 + 留 audit trail 比 keyword 命中更有意義
- **不採 LLM judge 做 routing tier 升降**(只用 Likert 顯化 score 給 user 看,trigger 後 user 仍是決策者):AI 自評做 routing 直接決定會引入跨 session 不穩定
- **不在 idd-list / idd-report 標記「pre-Vagueness」**:noise 大於價值,既有 verdict 維持原樣

## Capabilities

### New Capabilities

- `routing-vagueness-layer`: `idd-diagnose` Step 3.4 Vagueness Pre-check 機制 — Likert 6-point per-axis (V1, V4) 評分 + 6-point anchor + Hybrid 3-option trigger + audit trail PATCH 到 Diagnosis comment + 5 層 routing order 說明

### Modified Capabilities

(none)

## Impact

- Affected code:
  - New: `.claude/rules/attribute-assessment.md`
  - New: `openspec/specs/routing-vagueness-layer/spec.md`(由 spectra apply 階段產生)
  - Modified: `CLAUDE.md`(加 `@.claude/rules/attribute-assessment.md` import)
  - Modified: `plugins/issue-driven-dev/rules/sdd-integration.md`(加 Layer V 段落、更新 4 層 → 5 層 evaluation order、加 retrospective dry-run table)
  - Modified: `plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md`(加 Step 3.4、TaskCreate 清單對齊、Step 3.5 verdict format 加 `### Vagueness Pre-check` 區段)
  - Modified: `plugins/issue-driven-dev/skills/idd-implement/SKILL.md`(line 271 parser 接受 Vagueness-driven Plan 標記)
  - Modified: `plugins/issue-driven-dev/skills/idd-all/SKILL.md`(line 358 parser 同上;unattended mode 標記 `[Layer V: clarify-default skipped under unattended mode, defaulting to proceed]`)
  - Modified: `plugins/issue-driven-dev/MANIFESTO.md`(5-axis → 6-axis,新增 Alignment quality)
  - Modified: `plugins/issue-driven-dev/CHANGELOG.md`(v2.50.0 entry)
  - Modified: `plugins/issue-driven-dev/.claude-plugin/plugin.json`(version bump)
- Affected processes:
  - `idd-diagnose` 流程多一步 Step 3.4(只在 vagueness trigger 時對 user 可見)
  - `idd-all` unattended mode 對 vagueness trigger 採 proceed default,attended mode 仍跳 3-option
- Affected docs:
  - GitHub Issue #12 將被 Spectra change 鏈結,完成後 close 並 archive
