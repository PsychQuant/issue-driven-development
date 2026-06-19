# Design — choice-first decision rendering doctrine

## Context

`#190` 的洞察:當 AI 需要 user 對可列舉的決策拍板時,render 候選選項比請 user 自由文字描述,讓 user **更確定**。IDD 已部分實踐（Layer V D.1）但未規範化。本 change 把它升為跨 skill doctrine。

**關鍵 reframe（grounding 確認）**:`idd-clarify`（已完成的 change `add-idd-clarify-skill`,9/9 tasks done）是 **text-level 術語審計**（source 是否用對 canonical term),其 Non-Goal 明寫「不替代 spectra-discuss」。本 doctrine 是**不同的軸** — decision-rendering UX。因此本 change **不**動 `idd-clarify`,只動 `idd-diagnose` + MANIFESTO + 新 doctrine spec。

## Decisions（spectra-discuss 對齊結論,2026-06-19）

### Decision 1 — 歸宿:跨 skill doctrine（而非只改 idd-diagnose / 只放寬 Layer V）

choice-first 原則寫進 **MANIFESTO + 新 spec capability `choice-first-decision-rendering`**,所有 `idd-*` skill 遵守。

- **Rationale**:single source of truth;這是 cross-cutting UX 原則,不該散落各 skill。
- **Rejected**:(a)「只改 idd-diagnose」— 低 blast radius 但其他 skill（idd-plan、未來 skill）不被涵蓋,原則會再次散落;(b)「只放寬 Layer V D.1 trigger」— 最小改動但最不結構化,等於把 doctrine 藏在一個 sub-step 裡。
- **Trade-off accepted**:blast radius 最大(規範性宣告影響所有 skill maintainer),但這正是 doctrine 的目的。

### Decision 2 — 強度:SHALL + 具名 fallback

選項**可列舉** → **SHALL** render choices;要用 free-text → 須寫明「為何無法列舉」(named exception)。

- **Rationale**:可 enforce、防 AI 偷懶跳過（本 incident 就是 AI 沒 fire choice-first）。具名 fallback 保留「空間真的開放時 free-text 才對」的判斷,但要求 AI **顯式**說明,不能默默 articulate。
- **Rejected**:SHOULD(advisory)— 較不 over-trigger,但容易被忽略（正是這次 incident 的失敗模式:沒人強制,AI 就忘了)。
- **逃生口保留**:doctrine 是 prefer-choices 不是 mandate-no-text;genuinely-open 決策仍可 free-text,只是要具名。

### Decision 3 — 與 Layer V D.1 的關係:抽出共用,D.1 引用它

把 choice-first 抽成一條共用 doctrine;`idd-diagnose` Step 3.4 Layer V D.1 重構成「在 vagueness 情境**套用**該 doctrine」的一個 instance。

- **Rationale**:避免重複;D.1 現有文字（「可列舉 → AskUserQuestion render;無法列舉 fallback free-text」)其實就是 doctrine 的具體化,讓它顯式引用 doctrine = single source of truth。
- **Rejected**:「新增一條、不動 D.1」— 改動隔離但兩處說類似的事,日後 drift 風險。

## Scope of normative change

- **New capability spec**: `choice-first-decision-rendering`（ADDED requirement + scenarios,含 unattended 自動 proceed + D.1-as-instance scenario）。
- **MANIFESTO patch**: 新增 doctrine 段落（連結 NSQL Confirmation Protocol / Read-Only for Humans）。
- **idd-diagnose SKILL.md patch**: Step 3.4 Layer V D.1 改為引用 doctrine;Step 4 stakeholder-decision surfacing 加 choice-first 套用。

## Open questions (resolved in discuss)

| Q | Resolution |
|---|---|
| 套用範圍 | 跨 skill doctrine (Decision 1) |
| 強度 | SHALL + named fallback (Decision 2) |
| 與 D.1 關係 | 抽共用、D.1 引用 (Decision 3) |
| unattended 行為 | 自動 apply 推薦項 + audit trail（沿用 Layer V 既有 unattended 設計，不新增） |
| 與 idd-clarify 關係 | 正交,不動 idd-clarify（不同軸:術語 vs 決策渲染） |

## Risks

- **Scope creep**:「所有 user-input 都 render choices」會膨脹。**Mitigation**:doctrine scope 明文限「決策/澄清點」,排除純資訊提示。
- **Over-prescription**:抹掉「genuinely-open 才 free-text」判斷。**Mitigation**:named fallback 明文保留 free-text,只要求具名。
- **碰撞 in-flight change**:`add-idd-clarify-skill` 已 9/9 done + in sync,風險低;且本 change 不動 idd-clarify。
