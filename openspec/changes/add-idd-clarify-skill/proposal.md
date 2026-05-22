## Why

IDD skill graph 目前只覆蓋兩個 quality axis:

| Axis | Existing safeguard | Skill |
|---|---|---|
| Confidence(客戶是否真的反映)| IC_R010 | `idd-issue` Step 4.4 + `idd-diagnose` Step 3.4 |
| Verbatim(原文是否被改寫)| IC_R007 | `idd-issue` Step 1 source preservation |

第三軸 **Terminology / Semantic accuracy**(source 用詞是否正確;隱含 missing context)無對應 safeguard。`idd-diagnose` 預設 issue body 已 framed correctly,只做 routing + complexity。當 source 用了錯誤 / 不精確 domain term,downstream chain(diagnose / plan / implement / verify / close)繼承錯誤越走越歪。

**Concrete incident**(2026-05-21 #804):客戶 docx 寫「特徵值」實際意思是「分群變數 / distinguishing variable」。AI 沿用「特徵值」於 issue body + diagnosis comment。Spec.md 階段意外修對(因為 AI 獨立知道 K-means context 的 canonical term),但這是運氣 — 若 source term 跟 canonical term 有語意衝突且 AI 無獨立 domain knowledge,錯誤會繼承到 implementation。

**Recursive evidence**(本 session 4 instances):D06 group registry collision(#815)/ v3 design Step 4.8 collision(scout 抓到)/ `df_qef_customer_attributes` 來源未指定 / Design 三輪過抽象。每一次都需要 user push back。Codify `idd-clarify` 後 AI 不會繼續犯這類 — 而是 surface 給 user dismiss / resolve。

## What Changes

新增 **composable primitive `/idd-clarify`** + 既有 skills 兩處 patch:

1. **New skill `idd-clarify`** — surfacing-only,annotation-block output schema,status: surfaced / dismissed / resolved
2. **Patch `idd-issue` SKILL.md** — 加 Step 4.6 Clarity Surface auto-delegate(在 4.5 milestone 跟 4.7 sister sweep 之間;Step 4.8 已被 Split Umbrella SOP 佔用故選 4.6)
3. **Patch `idd-diagnose` SKILL.md** — 加 Step 0.5 Clarity Surface PR Gate(hard refuse on unresolved rows)
4. **New `references/terminology-canonical.md`** — initial seed library(6 rows + rule-of-three promotion threshold + open PR contribution)
5. **Migrate #135 conversation chain into `discussion.md`** — audit trail per IDD MANIFESTO

## Non-Goals

- **不做 resolution**(失職 gatekeeper paradox)— user 自己標 dismissed / resolved
- **不替代 IC_R007 verbatim preservation** — source blockquote 始終保留原文
- **不替代 `/spectra-discuss`** — clarify = text-level audit,discuss = concept-level design alignment
- **不在 `idd-edit` / `idd-update` integrate**(留給 sister #136 P3)
- **不解 unattended-mode interaction contract gap**(留給 sister #137 P2)

## Capabilities

### New Capabilities

- `idd-clarify-skill`: standalone primitive that scans an issue body for terminology mismatches, ambiguity, and missing-context gaps, then annotates the issue body with `### Clarity Surface` block(advisory, surfacing-only, status: surfaced / dismissed / resolved).
- `idd-issue-clarity-step`: new Step 4.6 in `idd-issue` skill — auto-delegates to `idd-clarify` after issue creation, except in `--multi-finding` mode. Inserts between Step 4.5 Milestone and Step 4.7 Sister Sweep.
- `idd-diagnose-clarity-gate`: new Step 0.5 in `idd-diagnose` skill — hard-refuses to proceed when target issue body has unresolved `### Clarity Surface` rows.

### Modified Capabilities

(none)

## Impact

- **Affected specs**:
  - New: `openspec/specs/idd-clarify-skill/spec.md`(本 change 產出)
  - New: `openspec/specs/idd-issue-clarity-step/spec.md`(本 change 產出)
  - New: `openspec/specs/idd-diagnose-clarity-gate/spec.md`(本 change 產出)

- **Affected code**:
  - New: `plugins/issue-driven-dev/skills/idd-clarify/SKILL.md` — primitive skill 完整實作
  - New: `plugins/issue-driven-dev/references/terminology-canonical.md` — initial seed library
  - New: `openspec/changes/add-idd-clarify-skill/discussion.md` — migrate #135 conversation chain
  - Modified: `plugins/issue-driven-dev/skills/idd-issue/SKILL.md` — 加 Step 4.6 auto-delegate + Step 0 Bootstrap TaskCreate entry
  - Modified: `plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md` — 加 Step 0.5 Clarity Surface gate
  - Modified: `plugins/issue-driven-dev/plugin.json` — minor version bump(new skill = backward compat additive)
  - Modified: `plugins/issue-driven-dev/README.md` — 加 idd-clarify 進 skill matrix + changelog row
  - Modified: `plugins/issue-driven-dev/MANIFESTO.md` — 加 三軸 framing 進 quality-axis section(若無則新建)
