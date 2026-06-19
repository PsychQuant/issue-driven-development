# Tasks — choice-first decision rendering doctrine

## 1. Doctrine prose (MANIFESTO)

- [x] 1.1 在 `plugins/issue-driven-dev/MANIFESTO.md` 新增 doctrine 段落「Choice-first decision rendering（人挑，不要人寫）」於「Human-in-the-loop: IDD 即 NSQL Confirmation Protocol」section 內，連結 Read-Only for Humans + cite #190。

## 2. idd-diagnose SKILL.md patches

- [x] 2.1 Step 3.4 Layer V D.1（`clarify now` handler）:改為**顯式引用** choice-first doctrine（標明 vagueness 情境的 instance、single source of truth 在 doctrine），保留可列舉/無法列舉兩 bullet。
- [x] 2.2 Step 4 Stage 1:新增 normative note — 可列舉的 stakeholder 決策 SHALL 用 `AskUserQuestion` render，不只散文列;batch/aggregate 同理;unattended 自動取推薦項。
- [x] 2.3 unattended 行為文字與 doctrine 的 unattended scenario 一致（D.1 + Step 4 + spec 三處對齊，不 block）。

## 3. Spec sync

- [x] 3.1 `openspec validate add-choice-first-decision-doctrine` 通過（spec delta 格式正確、與既有 spec 無衝突）。
- [ ] 3.2 （N/A）repo 無獨立 skill-index/capability registry 需手動登記 — openspec specs/ 即 registry，archive 時自動 promote。

## 4. Validation

- [x] 4.1 `openspec validate` 通過。
- [x] 4.2 Grep `idd-*` SKILL.md 「散文列決策請 user 回」的點 — 主要 instance（idd-diagnose Step 4 + Layer V D.1）已收口;其他 skill（idd-plan / idd-issue Spectra routing）已用 AskUserQuestion，無新增 violation。rule-of-three:未來新點按 doctrine 套用。
- [x] 4.3 Self-consistency:doctrine named-exception fallback 文字與 D.1 既有 fallback 對齊，無矛盾。

## 5. 不做（Non-Goals 對應）

- [x] 5.1 確認**未**動 `idd-clarify`（不同軸:術語 vs 決策渲染）。
- [x] 5.2 確認**未**把純資訊提示 / 進度輸出納入 doctrine scope（spec scenario 明文排除）。
- [x] 5.3 確認**未**改 (PR/HITL) mode resolution。
