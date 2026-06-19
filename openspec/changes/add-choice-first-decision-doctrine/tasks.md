# Tasks — choice-first decision rendering doctrine

## 1. Doctrine prose (MANIFESTO)

- [ ] 1.1 在 `plugins/issue-driven-dev/MANIFESTO.md` 新增 doctrine 段落:「Choice-First Decision Rendering」— 決策點選項可列舉 → SHALL render `AskUserQuestion` 候選;free-text 是具名例外。連結到既有「Human-in-the-loop: IDD 即 NSQL Confirmation Protocol」/ Read-Only for Humans。

## 2. idd-diagnose SKILL.md patches

- [ ] 2.1 Step 3.4 Layer V D.1（`clarify now` handler,~line 407-409）:把「優先 render 候選讓 user 挑、無法列舉才 free-text」改為**顯式引用** choice-first doctrine（標明這是 doctrine 在 vagueness 情境的 instance），不再就地重新陳述規則。
- [ ] 2.2 Step 4（確認 + Routing）/ aggregate stakeholder-decision surfacing:新增一句 normative 指示 — 可列舉的 stakeholder 決策 SHALL 用 `AskUserQuestion` render 選項,不只散文列。引用 doctrine。
- [ ] 2.3 確認 unattended 行為文字與 doctrine 的 unattended scenario 一致（自動 apply 推薦項 + audit trail,不 block）。

## 3. Spec sync (DOC_R009-style triple-layer, if applicable)

- [ ] 3.1 確認新 spec `choice-first-decision-rendering` 與 `idd-diagnose` 既有 spec 無衝突(`spectra-drift` / `spectra-validate`)。
- [ ] 3.2 若 repo 有 skill-index / capability registry,登記新 doctrine。

## 4. Validation

- [ ] 4.1 `spectra-validate`（或 openspec validate）通過,spec delta 格式正確。
- [ ] 4.2 Grep `idd-*` SKILL.md 找其他「散文列決策請 user 回」的點,評估是否同樣套用（surface,不一定本 change 全改 — rule-of-three）。
- [ ] 4.3 Self-consistency:doctrine 的 free-text named-exception 與 D.1 既有 fallback 文字對齊,無矛盾。

## 5. 不做（Non-Goals 對應）

- [ ] 5.1 確認**未**動 `idd-clarify`（不同軸）。
- [ ] 5.2 確認**未**把純資訊提示 / 進度輸出納入 doctrine scope。
- [ ] 5.3 確認**未**改 (PR/HITL) mode resolution。
