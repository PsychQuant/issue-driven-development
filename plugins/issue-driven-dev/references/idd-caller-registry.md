# IDD_CALLER Registry（#161）

`IDD_CALLER=<value>` 是 IDD skills 呼叫 helper scripts 時的 **caller 身分慣例**。本檔是唯一的
中央註冊表 — 新值加入時**必須**同步登記一列（drift-guard `scripts/tests/idd-caller-registry/`
以動態 grep 對照樹上實值與本表，漏登記即 RED）。

## 語意（semantic intent）

**Audit trail** — 記錄「哪個 skill 觸發了這次 helper 呼叫」，寫入產物供事後考古。
目前**沒有** conditional behavior（helper 不依 caller 改變行為）；若未來某 helper 需要
對特定 caller 差異化，先在本檔把該 value 的語意升級為 behavioral contract 再實作。

## 值域慣例

- 基本形：**skill name**（`idd-<skill>`）— 例 `idd-diagnose`
- 子 mode 形：**skill name + `-<mode>` 後綴** — 例 `idd-comment-errata`（idd-comment 的 errata flow）
- charset：`[a-z-]`（小寫 + dash）

## Registry

| Value | Emitted by | Reads it | Semantic intent |
|-------|-----------|----------|-----------------|
| `idd-diagnose` | `skills/idd-diagnose/SKILL.md` Step 1.5（attachments `download`）| `scripts/process-attachments.sh` | manifest `fetched_by` audit trail |
| `idd-implement` | `skills/idd-implement/SKILL.md` Step 1.2（attachments `check`）| 同上 | 同上 |
| `idd-verify` | `skills/idd-verify/SKILL.md` Step 0（attachments `check`）| 同上 | 同上 |
| `idd-close` | `skills/idd-close/SKILL.md` Step 1.4（attachments `verify`）| 同上 | 同上 |
| `idd-comment-errata` | `skills/idd-comment/SKILL.md` errata flow（#154，經 `/idd-edit` 委派）| 同上 | errata 委派鏈的 caller 身分（子 mode 形式首例）|

## Reader contract

**`scripts/process-attachments.sh`** 是目前唯一 reader：把 `$IDD_CALLER` 記入
`_manifest.json` 的 **`fetched_by`** 欄位。**Unset 時 fallback `idd-skill`**
（`${IDD_CALLER:-idd-skill}`）— 代表「非 skill 直呼」（手動 CLI / 測試）。
manifest 消費端（下游 skills）把 `fetched_by` 當純 audit 資訊，不得據以分流。

## 新值加入 checklist

1. 本表加一列（value / emitter / reader / intent）
2. 跑 `bash scripts/tests/idd-caller-registry/test.sh` 確認綠
3. 若新值需要 reader 端差異化行為 → 先在本檔升級語意宣告，再改 helper

## Validation 姿態

**Informal（刻意）** — helper **不**驗證 value 在 allowed list（無 warn/reject）。
理由：現無 drift 事故，runtime validation 是未觸發的複雜度；anti-drift 由本表 +
drift-guard 的**編輯時**對照承擔。若未來出現「未知 caller 造成實害」再升級。

Refs #161（成案）、#154（第 6 值 `idd-comment-errata` 的 silent 加入即本表動機）。
