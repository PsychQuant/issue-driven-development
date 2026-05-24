## Why

IC_R011 follow-up filing checkpoint(IDD plugin canonical reference `plugins/issue-driven-dev/references/ic-r011-checkpoint.md`,301 行)目前在 7 個 skill SKILL.md site inline 實作為「3-option AskUserQuestion」(`file all` / `file selected` / `skip`)。本 session 連續 3 次 invocation(`/idd-plan`、`/idd-diagnose`、`/idd-verify`)user 都選 `file` 變體,證實「ask 3-option」是 ceremony 而非 signal — 使用者真的想 file。

User 在 issue #148 明示「**預設要開起 issue,不然過去的問題就會消失了吧,除非是無法解決的問題**」。當前 default「ask」造成:**(1)** 不主動選 = 建議消失到對話 log;**(2)** skip path 無 reason 記錄,事後無法 audit 為何沒 file;**(3)** 7 sites inline 同樣 procedure body — drift risk,本 issue 自身就是要 sync 7 places 的痛點 source。

## What Changes

- **BREAKING** Default 從「ask 3-option」翻成「**file by default + 3-category skip taxonomy**」(Option B)。5 個 SHALL/未 framing site 採新 default:`idd-diagnose` Step 3.6 / `idd-plan` Step 2.5 / `idd-implement` Step 5.7 / `idd-issue` Step 4.7 / `idd-verify` Step 5b。
- `idd-close` Step 3.5(SHOULD-tier)**保留** 3-option ask 不翻 default(closing 是 wrap-up moment,非 deliberation,翻 default 增加 friction 無 proportional value)。
- 新增 3-category skip taxonomy:**(a) unactionable observation**(真 skip,無 issue)/ **(b) infeasible-but-understood**(auto-file P3 + `blocker:infeasible` label)/ **(c) blocked-on-external**(auto-file P3 + `blocker:waiting` label)。只有 (a) 真不 file,(b)(c) 仍進 parking lot。
- **BREAKING** 既有 escape hatch 語意 shift:`AI_LOW_BAR_ISSUE_FILING=false` 從「silent skip checkpoint」改為「**revert to 3-option ask 行為**」;`# Disable IC_R011`(repo CLAUDE.md flag)同步語意。CI / unattended 環境設定 `=false` 後仍 functional,只是行為從 silent skip 變 3-option ask;無 TTY 時 fallback 到 implicit skip + audit trail(per `/idd-issue` Stage 4.5 既有 unattended-mode fallback pattern)。
- **Centralize procedure body 到 canonical reference**:`plugins/issue-driven-dev/references/ic-r011-checkpoint.md` 成為 normative single source of truth(現況已 301 行接近),6 個 skill SKILL.md(5 SHALL + 1 close)從 inline 大段 procedure 改為 `### Step N.M: <name> (per IC_R011)` + 1-line invoke + per-step deviation(若有)。
- 確認 `idd-all-chain` 的 IC_R011 reference 屬於 spawn-manifest pass-through(非 standalone AskUserQuestion checkpoint),**不**在本 change 改寫 scope 內(propose 階段 verify 後 freeze)。
- 順手 fix `#149`:`idd-verify` Step 5b 沒用 canonical「Rule (SHALL/SHOULD)」framing,在本 change 一併補上(改 default 同時統一 framing)。

## Non-Goals

留 design.md 處理(本 change 會建 design.md)。

## Capabilities

### New Capabilities

- `idd-ic-r011-checkpoint`: formal spec for the IC_R011 follow-up filing checkpoint pattern — default behavior,3-category skip taxonomy,SHALL/SHOULD 異質 site treatment,backward-compat semantic shift of existing escape hatches,centralization contract between canonical reference + skill implementations

### Modified Capabilities

(none — IC_R011 currently lives as a reference doc with no corresponding spec;本 change 首度將 normative behavior 形式化為 spec)

## Impact

- Affected specs:`openspec/specs/idd-ic-r011-checkpoint/spec.md`(new)
- Affected code:
  - New:
    - `openspec/specs/idd-ic-r011-checkpoint/spec.md` — 新 spec 形式化 IC_R011 normative behavior
  - Modified:
    - `plugins/issue-driven-dev/references/ic-r011-checkpoint.md` — canonical reference doc 更新:Option B 預設 + 3-category skip taxonomy + 既有 escape hatch 語意 shift
    - `plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md` — Step 3.6 改 cite + per-step deviation
    - `plugins/issue-driven-dev/skills/idd-plan/SKILL.md` — Step 2.5 改 cite
    - `plugins/issue-driven-dev/skills/idd-implement/SKILL.md` — Step 5.7 改 cite
    - `plugins/issue-driven-dev/skills/idd-issue/SKILL.md` — Step 4.7 改 cite
    - `plugins/issue-driven-dev/skills/idd-verify/SKILL.md` — Step 5b 改 cite + 補 canonical「Rule (SHALL)」framing(closes #149)
    - `plugins/issue-driven-dev/skills/idd-close/SKILL.md` — Step 3.5 改 cite(保留 SHOULD + 3-option ask 不翻 default,只 normalize wording 跟其他 site 一致)
    - `plugins/issue-driven-dev/CHANGELOG.md` — BREAKING 行為 change entry
  - Removed:(none — inline procedure body 移轉到 canonical ref 不是刪除,是 relocation)
- Closes issues:#148(default-flip)+ #149(verify Step 5b framing gap,順手 fix)
