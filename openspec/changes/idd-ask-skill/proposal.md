# Proposal: idd-ask-skill

## Why

IDD 的知識庫（issues + comments + linked PRs：diagnoses、decisions、closing summaries）沒有 grounded 問答入口。查歷史只能手動 `gh issue list` + 逐一 view — 三個月後想還原「當時為什麼這樣決定」，AI 沒有 skill 層路徑（#72，鏡像 `/spectra-ask` 的空缺）。`/idd-find`（#139）解了「在哪裡」（query → ranked hits），沒解「為什麼」（question → 有引用的合成答案）。

## What Changes

1. **新 skill `/idd-ask <question>`**：surfacing family **第 4 員** — 自然語言問題 → decide-to-search gate → retrieval（**delegate `idd-find` 的 search backend**，不重造）→ 讀取 top-N 命中 issue 全文（body + comments）→ grounded 回答（首行 blockquote 原問題、每個 claim 附 issue/comment 引用、不腦補）→ `### Referenced Issues` 區段。
2. **Source priority**（類比 spectra-ask）：closed-with-PR issue > open issue > orphaned comment — 已關已 ship 是 ground truth，open 標注「進行中、可能會變」。
3. **Read-only 鐵律**：不 create / edit / comment / close；問題長得像 bug report 也**不**觸發 diagnose（引導語提示 `/idd-issue`）。
4. **#140 增員程序首次實戰**：三題判準記錄 + boilerplate checklist 逐項 + `references/surfacing-primitives.md` 成員表同步（canonical 更新）。
5. **可發現性**：plugin CLAUDE.md 表 + usecase-routing 情境列；drift-guard suite `scripts/tests/idd-ask/`。

## 增員判準（#140 三題，誠實記錄）

1. **I/O 形狀與現任三員不同？** ✓ — list（filters→triage 表）/ clarify（內文→標注）/ find（query→ranked hits）/ **ask（question→合成答案+引用）**
2. **唯讀？** ✓（issue 明訂設計約束）
3. **有 delegate 消費者？** **弱命中** — 主要消費者是人（同 spectra-ask）；潛在 skill 消費者（diagnose 查歷史 rationale）未接線。per family doc 此題弱時「先當 reference 文件」是選項，但本案有使用者裁決 + spectra-ask 同構先例（ask 類 skill 的消費者本來就是人），judgment：開 skill、把第 3 題弱命中記入 family doc 成員表註記。

## Non-Goals

- Embedding 語意搜尋（#72 Residue — `gh search` 詞法檢索是誠實邊界，與 idd-find 同界）
- Local cache / index 建置（retrieval 成本用 top-N + limit 控，不建基建）
- 觸發任何 lifecycle step（ask 是純問答）

## Impact

- Affected specs: `idd-ask`（ADDED，新 capability）
- Affected code: 新 `skills/idd-ask/SKILL.md`、`references/surfacing-primitives.md`（成員表 +1）、plugin `CLAUDE.md`、`references/usecase-routing.md`、新 suite

## Refs

Issue #72（Spectra opt-out → propose；「鏡像 /spectra-ask」定案）；family 契約 #140；retrieval backend 先例 #139
