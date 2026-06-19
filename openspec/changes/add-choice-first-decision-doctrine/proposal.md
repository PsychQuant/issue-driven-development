## Why

IDD 的 human-in-the-loop 介面是 NSQL Confirmation Protocol —「AI 寫，人讀」(Read-Only for Humans)。這個原則在**部分**決策點已落實成「render 候選讓 user 挑、而非請 user 用自由文字 articulate」：`idd-diagnose` Step 3.4 Layer V D.1 在 vagueness trigger 時用 `AskUserQuestion` render 候選詮釋。

但這個 choice-first 行為**只綁在 Layer V vagueness trigger（V1/V4 ≥ 4）**，未涵蓋 `idd-diagnose` 結尾 surface 的一般 stakeholder 決策，也未升為所有 `idd-*` skill 共用的 doctrine。結果是:choice-first 是否 fire 取決於 AI 自覺,而非規範。

**Concrete incident（#190 觸發事件，2026-06-19）**:一次 `idd-diagnose` batch（12 個 QEF 客戶 issue）結束後,AI 在 aggregate report 用**散文**列出 4 個需 stakeholder 拍板的決策,並反問 user「要不要我用 AskUserQuestion 把這些做成選項」。User 回饋:

> 「需要 clarify 的部分,與其要我說,不如給我幾個選擇我比較確定。」

AI 散文列決策 = choice-first 原則在 Layer V 以外的決策點沒 fire。這正是本 doctrine 要消除的 gap。

## What Changes

新增一條跨 skill **choice-first decision rendering** doctrine,並把既有實例收口到它之下:

1. **New doctrine（MANIFESTO + new spec capability `choice-first-decision-rendering`）** — 任何 `idd-*` skill 在決策/澄清點需要 human input 且**選項可列舉**時,**SHALL** 用 `AskUserQuestion` render 候選選項（含推薦項）。Free-text 是**具名例外** fallback:**只在**選項空間真的開放、AI 無法列舉候選時才用,且須寫明「為何無法列舉」。
2. **Refactor `idd-diagnose` Step 3.4 Layer V D.1** — 從「自帶 choice-rendering 規則」改成「**引用**該 doctrine 的一個實例（在 vagueness 情境套用）」,避免重複、single source of truth。
3. **Patch `idd-diagnose` Step 4 stakeholder-decision surfacing** — 可列舉的 stakeholder 決策 render 選項,不只散文列。

## Non-Goals

- **不強制「所有 `AskUserQuestion` 都這樣」**:doctrine scope 限**決策 / 澄清點**,不含純資訊提示或進度回報。
- **不移除 free-text**:選項空間真的開放時 free-text 仍正確 — doctrine 是 **prefer choices + named fallback**,不是 mandate-no-text。保留 D.1 既有的「無法列舉才 fallback」逃生口。
- **不替代 `idd-clarify`**:`idd-clarify` 是 text-level 術語審計（issue 是否用對 canonical term,surfacing-only,不同軸）;本 doctrine 是 decision-rendering UX。兩者正交。
- **不改 (PR / HITL) mode resolution**:doctrine 在 **attended** 場景套用;**unattended** 不 block,取該 skill 既有的安全 non-blocking 預設 + 寫 audit trail（如 Layer V 的 `proceed anyway` 慣例,未必是推薦項）。
