## Context

IDD plugin v2.72.0 開發過程中持續觀察到 supersession workaround 累積。具體 ≥ 6 個 instances:`#515` supersession bridge(idd-close gate fork 處理 Strategy/Plan pre-impl checkbox 殘留)、`#148` retroactive `## Implementation Complete` post(配 #515 觸發 supersession)、`#149` retroactive `## Closing Summary` post(被 commit-body trap auto-close 後事後補)、IC_R011 audit blocks 在 single comment 內不斷 append(`### Sister Concerns Filed` / `### Closing Follow-ups Filed` / `### Distribution Sync` / `### Residue Acknowledgement` 共存,沒收斂)、canonical reference 文檔自由 grow(`ic-r011-checkpoint.md` 301→397 行)、本 issue #150 自身 body 被 bad bash sed 寫壞(2026-05-25 03:10 UTC instance)。

每個新 IDD feature 撞到「AI-authored stale state」就重新發明 workaround。痛點 root cause 是 IDD 缺乏 first-class principle 約束 modify-action 該怎麼存在 — implicit hybrid rule 散在 7+ artifact sites,各 SKILL.md 各自處理,無 single normative source 讓 plugin author 或 future contributor 知道「我這個新 action 屬哪類 / 該不該允許 modify / 該怎麼 declare scope」。

User 在 `/spectra-discuss` 階段 challenge 我原本的 actor-based framing(「AI 不能 modify AI 舊 output / user 可以」),指出 `/idd-edit` 不該被留為 blanket exempt 黑洞 — 結構上跟 raw bash sed 同類(沒 scope declaration)。 User pivot 為「**每個動作都要有 scope**」,把 discipline 從 actor-identity-based 改為 action-scope-based,uniform enforcement。

**Stakeholders**:
- **Plugin maintainer**(主要 author):需要 normative rule 引用、需要 7-category 決策樹幫助 classify 新 action
- **Future plugin contributor**:沒有 implicit hybrid context,需要 explicit principle file 上手
- **IDD user**(`idd-edit` 用戶):`--section` flag BREAKING,需要 migration notice
- **Sister #137 / #151 implementer**:design 必須 align 本 principle

**Constraints**:
- BREAKING 限縮在 `idd-edit`(其他 action 已隱性 compliant,retroactive label 即可)
- 必須 backward-compat:既有 closed issues 不能變不能 close;legacy issue patterns(`Implementation Complete > Checklist` 缺失)走 fallback
- Must dogfood:本 change 在 spec-driven 流程內驗證(spectra-apply 完成後,本 plugin 自己用新 principle 操作 issue / comments)

## Goals / Non-Goals

**Goals:**

- Codify 「action-scoped modify discipline」 為 first-class plugin principle(parallel to IC_R007 / IC_R010 / IC_R011 pattern)
- 提供 7-category action taxonomy 涵蓋目前 ≥ 8 個 既有 actions + decision tree 幫 future plugin author classify 新 action
- 明定 `(undeclared) → REFUSE` default,塞死 unrestricted modify entry(包含 raw bash sed corruption pattern)
- Generalize `#515` Path C gate-logic 「only-look-at-latest」 pattern 從單一 idd-close site 推廣到 4 個 gate sites
- 透過 `--section` flag spec change 把 `/idd-edit` 從 blanket user-modify entry 改為 scope-compliant action
- Unblock sister `#137`(unattended Clarity contract)+ `#151`(commit-body auto-close trap remediation)的 design alignment

**Non-Goals:**

- **不**約束跨 plugin(che-msg / che-zotero 等各自 file own principle issue)
- **不**處理 GitHub-level UX(comment 累積閱讀體驗、PR review UI、issue timeline 等屬 GitHub 產品 non-actionable)
- **不**改 `spectra archive` 既有 delta-promote-to-main hybrid 行為(已 work,無痛點)
- **不**做廣義 shell-scripting safety 防護(rule 只透過 `(undeclared) → REFUSE` 間接 cover bash sed corruption pattern,不寫專門 shell safety rule)
- **不**回溯改既有 closed issues(本 incident `#150` body recovery 已完成是 one-off,不 retroactive scan 整個 repo)
- **不**做 tooling-level static analyzer(本 change 只 codify principle + spec normative gate refuse;tooling gate enforcement 屬 follow-up issue)
- **不**改 IC_R007 verbatim-preserve 既有 scope(本 rule 引 IC_R007 作為 `verbatim-preserve` category 的 instance,不重新定義)

## Decisions

### Decision 1: Action-scoped discipline 取代 actor-based exemption

**選擇**:每個 modify-action SHALL declare scope category(1 of 7)。 AI invocation 與 user invocation 受同等約束。 未 declare 屬 `(undeclared)` → SHALL REFUSE(by skill spec + future tooling gate)。

**Rationale**:User explicit pivot — actor-based framing 把 `/idd-edit` 留為黑洞,結構上跟 raw bash sed 同類(沒 scope declaration)。 Action-scoped 把 「modify 該怎麼存在」 從 actor identity 改為 declared scope,uniform tooling-enforceable。

**Alternatives considered**:
- (A) Actor-based exemption(原 A4):AI 限制 / user free pass。 **Reject**:結構性弱,把 future tooling gate 變不可能(actor identity hard to verify reliably);本 session 自身 sed corruption 就是「user explicit invocation 但 sed 內含未檢查 substitution」,exemption 漏掉。
- (C) 直接禁所有 modify,只允許 append:過嚴,既有 `/idd-update` Current Status REPLACE / checkbox flip 本來就 work 且需要,blanket ban 大幅 regression。

### Decision 2: 7-category action taxonomy

**選擇**:`state-field-update` / `bounded-section-replace` / `audit-block-append` / `inline-replace-before-publish` / `verbatim-preserve` / `append-only` / `free-rewrite`。

每 category 規格:
- **`state-field-update`**:改 machine-readable state field(phase / timestamp / status enum / checkbox boolean)。 不動 prose。 範例:`/idd-update` Current Status phase / `/idd-clarify` status field / `spectra task done` checkbox flip / Step 0.5 dismiss row。
- **`bounded-section-replace`**:整個 *named section* REPLACE,section 邊界 explicit declared(section identifier 是 invocation contract 的一部分)。 不溢出。 範例:`/idd-update` REPLACE `## Current Status` 整段 / `/idd-edit --section "## Foo"` REPLACE 指定 section。
- **`audit-block-append`**:新增 audit block 到 *named comment* 的 *named section*。 不動既有內容,只在 declared section 內 append。 範例:IC_R011 sister sweep PATCH `### Sister Concerns Filed` / Layer V PATCH `### Vagueness Pre-check` / Step 4.6 Clarity Surface block emit。
- **`inline-replace-before-publish`**:Modify 發生在 publish *之前*(draft 階段)。Publish 之後 artifact 落 `append-only` 規則。 範例:`/idd-close` Step 3.5 inline replace `「follow up later」` → `「(see #NEW)」` 在 closing summary publish 前。
- **`verbatim-preserve`**:絕對不能改。 IC_R007 場景。 範例:Issue body above `---` separator(user-authored prose)/ 引用 blockquote(原文 verbatim quote)/ frozen spec contract。
- **`append-only`**:只新增,不改舊。 範例:GitHub comments(post 後)/ CHANGELOG.md 新版本加頂 / tasks.md history rows / spectra archive snapshot。
- **`free-rewrite`**:docs / code 範疇,屬作品本身不是 audit,可以 rewrite。 範例:SKILL.md / canonical reference `.md` / source code(`.rs` / `.py` / `.swift` etc)。

**Rationale**:7 categories 從 IDD 親身觀察的 ≥ 8 個既有 action 行為 cluster 出來,涵蓋面足。 Each category 定義 tight + 含 example list 校準。

**Alternatives considered**:
- 3-category(append / modify / hybrid):太粗,塞不下「inline-replace-before-publish」這類 boundary case;「modify」籠統,無法 distinguish state-field 與 bounded-section。
- 10+ category(每個 action 一類):過細,decision tree 失去 abstraction value。

### Decision 3: Path C gate-logic generalization(`only-look-at-latest`)

**選擇**:4 個 gate sites(`idd-close` Step 0 / `idd-verify` checklist scan / `idd-update` body sync gate / `idd-implement` Step 5 Checklist Sync)統一採用 `authoritative_source` resolution:

```
authoritative_source = first_exists([
  "## Implementation Complete > ### Checklist",
  "## Current Status > ### Tasks",
  "## Todo / Tasks / Checklist (top-level)"
])
```

有 authoritative_source → 只看它,Strategy/Plan/Implementation Plan 視為 superseded snapshot(歷史 reference,不 gate);無 authoritative_source → fall back legacy scan all sources(`#515` 現行 backward-compat 行為)。

**Rationale**:`#515` 已部分驗證 pattern 在 `idd-close` 可行。 Generalize 到其他 3 個 gate sites 是同模式 copy,implementation risk 低。 解 90% 的「pre-impl checkbox stale」 supersession workaround 痛點。

**Alternatives considered**:
- 保留 `#515` 為 single-site fix:其他 3 個 gate 各自累積同類 workaround,違反 codify 初衷。
- Path B 採用(AI modify AI 舊 output 改 checkbox `[x]`):modify blast radius 大(本 incident sed corruption 證據);需 atomic API + pre-modify snapshot + dry-run mode mitigation,成本高於 Path C 的 archaeology cost。

### Decision 4: `/idd-edit` BREAKING 加 `--section` flag

**Scope clarification (post user-pivot 2)**:`/idd-edit` 是 **comment-only** skill(既有 argument syntax `comment:<id>` / `#NNN --last`),不負責 issue body modify。 Issue body 各 zone 有專屬 skills:`/idd-clarify`(`### Clarity Surface` rows)/ `/idd-update`(`## Current Status`)/ 上半 verbatim zone 無 modify path(故意)。 本 Decision 限縮在 comment-side 行為。

**選擇**:三 mode (`--append` / `--prepend-note` / `--replace`) 分類處理 + verbatim-preserve refuse for user-authored comments:

| Mode | Category | BREAKING? | 處理 |
|------|----------|-----------|------|
| `--append` | `audit-block-append`(scope = trailing block;already inherent) | No | 加 inline note `(category: audit-block-append, scope: trailing block)` in SKILL.md |
| `--prepend-note` | `audit-block-append`(scope = leading errata marker;already inherent) | No | 加 inline note `(category: audit-block-append, scope: leading errata marker)` |
| `--replace` | `(undeclared)` 預設 ⚠ → 須 explicit scope | **Yes** | 必須加 `--scope whole-comment`(explicit acknowledgment whole-comment overwrite)OR `--section <heading-within-comment>`(限縮到 comment 內 named subsection like `### Sister Concerns Filed`)。 未帶任一 → REFUSE。 |

**Verbatim-preserve guard**(新增,independent of mode):若 target comment `author_association ≠ OWNER` 且非已知 bot user(`github-actions[bot]` 等),`/idd-edit` 任何 mode SHALL REFUSE,除非帶 `--override-user-content` flag 並提供 `--reason="..."` rationale。 對齊 IC_R007 「不改 user-authored prose」discipline 在 comment 層級。

**Rationale**:User 兩階段 pivot 收斂出乾淨分工:
1. **Pivot 1**(actor-based exemption rejected)— `/idd-edit` 不能是 blanket user-exempt 黑洞
2. **Pivot 2**(scope clarification)— `/idd-edit` 本來就 comment-only,issue body 各 zone 已有專屬 skill,不該擴張 `/idd-edit` scope

結果:BREAKING 集中在 `--replace`(唯一 destructive mode)+ verbatim-preserve guard(IC_R007 alignment for comments)。 `--append` / `--prepend-note` 仍 work,只加 inline category note(non-breaking)。

**Migration**:CHANGELOG.md `BREAKING` 標記 `/idd-edit --replace` 必須 `--scope` 或 `--section`;migration 範例 `/idd-edit comment:NNN --replace --body "..."` → `/idd-edit comment:NNN --replace --scope whole-comment --body "..."`(或更精準的 `--section "<subsection>"`)。

**Alternatives considered**:
- 保留 blanket `--replace` + warning:會 erode 紀律(user 看到 warning 仍照舊用)
- BREAKING all 3 modes:過嚴 — `--append` / `--prepend-note` 本身 scope-bounded,加 BREAKING 對 user 無 benefit
- 把 issue body editing 從 `/idd-edit` 開出來給新 `/idd-body-edit`:**rejected** — issue body 各 zone 已有 `/idd-clarify` / `/idd-update` cover,新 skill 是 dead weight

### Decision 5: Principle 落地獨立 rule file 不併 manifesto

**選擇**:`plugins/issue-driven-dev/rules/append-vs-modify.md`(parallel to existing IC_R007 / IC_R010 / IC_R011 file pattern)。 Manifesto 留 high-level overview pointer 即可。

**Rationale**:既有 plugin principle 都各有 own rule file(本 plugin 已 IC_R007 / IC_R010 / IC_R011 file precedent)。 Maintainer mental model 一致。 預期 rule 內容 ≥ 200 行(7-category mapping table + decision tree + IC 邊界 + Path C pattern + backward-compat fallback),manifesto 塞不下。

**Alternatives considered**:
- 併 manifesto 一節:rule 規模超出 manifesto 慣例;後續 update rule 變成 update manifesto 觸動 unrelated content。

### Decision 6: Retroactive scope classification scope

**選擇**:本 change 為 ≥ 8 個 既有 actions 標 category(retroactive label,不改實作 logic):
- `/idd-update` → `bounded-section-replace`(Current Status section)
- `/idd-clarify` → `state-field-update`(status field)
- `/idd-close` Step 3.5 inline replace → `inline-replace-before-publish`
- IC_R011 audit PATCH(各 skill 內)→ `audit-block-append`
- `spectra task done` checkbox flip → `state-field-update`
- 各 skill 寫 issue body 上半 → `verbatim-preserve` enforcement(透過 `/idd-update` REPLACE 邊界保護)
- GitHub comments post → `append-only`(GitHub mechanism 強制)
- CHANGELOG.md / docs / SKILL.md → `free-rewrite`

每 action 在對應 SKILL.md 加 inline note `(category: <name>)`。

**Rationale**:Retroactive labeling 讓既有 action 變 first-class compliant,不需要重寫實作。 Future audit 可掃 SKILL.md note 確認 coverage。

**Alternatives considered**:
- 不 retroactive label,只 cover 新 action:既有 action 仍 implicit,future contributor 不知道 model,規則沒推廣。

## Implementation Contract

**Behavior(observable to plugin author / contributor)**:

- 開啟 `plugins/issue-driven-dev/rules/append-vs-modify.md` 看 7-category table + decision tree
- 寫新 skill / 改既有 skill 時,SKILL.md 內 modify-action 描述必須加 inline note `(category: <name>)` 或 `(scope: <section_id>)`
- 違規 case:寫一個 skill 改 body 但沒 declare scope → analyzer / dogfood 階段 catch
- 違規 case:`/idd-edit` 未帶 `--section` → CLI / skill body refuse + 提示

**Interface / data shape**:

- 新 rule file path:`plugins/issue-driven-dev/rules/append-vs-modify.md`
- 新 spec path:`openspec/specs/append-vs-modify-discipline/spec.md`
- `/idd-edit` CLI signature(BREAKING):`/idd-edit <issue-ref> --section <section-name> [--mode replace|prepend|append]`
- SKILL.md inline note format:`(category: state-field-update)` / `(category: bounded-section-replace, scope: "## Current Status")` / etc
- Gate `authoritative_source` resolution helper(可選實作:shared bash helper `_resolve_authoritative_source.sh` 給 4 個 gate site reuse,或各 site inline 重複邏輯)

**Failure modes**:

- `/idd-edit` 未帶 `--section` → exit code 1 + 「Refuse: `--section` flag required (action-scoped discipline)」 message + 指 rule file URL
- `/idd-edit --section "## Problem"`(targeting `verbatim-preserve` zone)→ exit code 1 + 「Refuse: section "## Problem" is in verbatim-preserve zone (above `---`)」
- 既有 issue legacy pattern(`Implementation Complete > Checklist` 缺失)→ fall back legacy scan all sources(behavior unchanged from `#515`)
- 既有 issue 在 fresh authoritative_source 之上仍有 `[ ]` Strategy/Plan checkbox → gate 不再 refuse(superseded snapshot,不 gate)

**Acceptance criteria**:

- `plugins/issue-driven-dev/rules/append-vs-modify.md` 存在 + 含 7-category section + decision tree + IC 邊界 + Path C pattern + backward-compat fallback note
- `openspec/specs/append-vs-modify-discipline/spec.md` 含 ≥ 5 SHALL requirements(每 category declare / undeclared refuse / Path C gate pattern / `--section` flag / retroactive label coverage)
- `/idd-edit` SKILL.md 含 `--section` flag 規格 + 至少 1 個 positive example + 至少 1 個 refuse example
- 4 個 gate site SKILL.md(close / verify / update / implement)含 `authoritative_source` resolution 邏輯 + backward-compat fallback note
- CHANGELOG.md 加 `[X.Y.Z]` entry 標 `BREAKING` 對 `/idd-edit`
- 至少 1 個 dogfood test scenario:在新 rule ship 後 invoke `/idd-edit` 不帶 `--section` 驗證 refuse;invoke 帶 `--section "## Current Status"` 驗證 work

**Scope boundaries**:
- **In scope**:本 change 落地 7-category rule + spec + 4 個 gate site update + `/idd-edit` `--section` flag + 8+ actions retroactive label + CHANGELOG BREAKING note
- **Out of scope**:tooling-level static analyzer 自動 enforce(屬 follow-up issue);ConcurrentTransaction / lock 機制(本 rule 純行為 discipline,non-concurrency);retroactive scan/fix repo 既有 issue body(本 incident `#150` recovery 已完成是 one-off);spec auto-generation from SKILL.md inline notes(屬 future tooling)

## Risks / Trade-offs

| Risk | Severity | Mitigation |
|------|----------|------------|
| **`/idd-edit` BREAKING 打破既有 user workflow** | HIGH | (a) CHANGELOG `BREAKING` prominent + 短文 migration note;(b) 給 `--section` 預設值 `## Current Status` 的選項?(否決:對「修 Problem section typo」 case 無效);(c) 既有 user-typed invocation 數量小(該 skill 不常用),且 refuse error message 直接教 user 怎麼補 flag |
| **Path C gate 對 legacy issue 漏 catch real-incomplete work** | MEDIUM | Fallback 設計:無 `authoritative_source` → scan all sources 同 `#515` 行為。Pre-implementation snapshot 是 honest-forgetting safety net,新規則只解 motivated-cheating 與 stale-state 噪音 |
| **7-category 不夠 future-proof** | MEDIUM | Decision tree 結尾留 `(undeclared) → REFUSE` 作為 honest-default;future 新 category 透過 follow-up issue + minor rule version bump 加入(本 rule 是 living document) |
| **Retroactive label 8+ actions 工作量被低估** | MEDIUM | Tasks.md 把每 action label 列為獨立 task;不要 group 為「label all actions」一個 task |
| **Sister #137 / #151 design 需 align,可能要重做** | LOW | 本 issue body 已記 Sister 受影響;#137 / #151 在本 change apply 後 diagnose 才動,避免 wasted work |
| **本 rule 自我 dogfood paradox(本 change 走 spec-driven 流程,但 spec-driven 流程本身可能不 compliant)** | LOW | spec-driven `proposal.md` / `design.md` / `tasks.md` 屬 `free-rewrite`(docs);`spec.md` 屬 frozen contract,本 change ship 後落 `verbatim-preserve` |
| **Decision tree 用詞 ambiguous 讓 plugin author 誤 classify** | LOW | Rule 內含 5+ worked example(每 category 至少 2 個 既有 action 範例);analyzer flag SKILL.md 內未 declare scope 的 modify-action;dogfood 過程 catch 早期 misclassification |

## Migration Plan

**Phase 1**(本 change apply):
1. Write rule file + spec(by spectra-apply)
2. Update 4 個 gate site SKILL.md(Path C generalize)
3. Add `--section` flag to `/idd-edit` SKILL.md spec + refuse logic stub
4. Retroactively label 8+ existing actions in their SKILL.md
5. CHANGELOG.md 加 entry(`[X.Y.Z]` BREAKING)
6. Manifesto 加 one-section overview pointer(若 manifesto 存在)

**Phase 2**(rule ship 後 short-term):
- Plugin marketplace sync(`/plugin-update issue-driven-dev`)
- 觀察 7 天 dogfood 自己使用,catch misclassification
- Sister `#137` / `#151` resume diagnose with new principle

**Phase 3**(long-term,屬 follow-up issue):
- Tooling-level analyzer:scan SKILL.md 內 modify-action 是否標 category
- Auto-suggest category for new SKILL.md changes(IDE plugin / git hook)

**Rollback**:
- 若 `/idd-edit --section` 強制 break 太多 user → 可加 `IDD_EDIT_ALLOW_UNSCOPED=true` env var 暫時 escape hatch(per existing `AI_LOW_BAR_ISSUE_FILING=false` precedent);長期 rollback 整個 rule = revert proposal commit,既有 SKILL.md 變化在 git history。

## Open Questions

1. **`authoritative_source` resolution 是否要抽 shared bash helper?** 4 個 gate site 都需要同邏輯。 抽 helper = DRY 但增 indirection;inline 重複 = 簡單但 4 處需同步 update。 建議實作時 decide。
2. **Manifesto 是否該大改?** 本 rule 引入「action-scoped discipline」是 IDD 主軸 evolution。 manifesto 應該升上「discipline core」一節還是只塞 pointer? 建議先塞 pointer + 留 follow-up issue 評估 manifesto 大改。
3. **7-category 名稱是否要對齊 LANGUAGE.md?** 目前 LANGUAGE.md 不存在;若日後 establish,本 rule 引入的 7 category name 應註冊。 不 block 本 change。
4. **`/idd-edit` `--section` flag implementation** 是純 SKILL.md spec 約束(skill 內 bash 檢查 + refuse)還是要動 plugin-level CLI parser? 建議 stage-by-stage:Phase 1 SKILL.md 內檢查;Phase 2(follow-up)若有 CLI parser layer 再升 native flag。 不 block 本 change apply。
5. **Dogfood test scenario 寫在哪?** 目前 IDD plugin 無 formal test infra。 建議 tasks.md 列 manual dogfood checklist 作為 acceptance(post-apply user 自己跑 `/idd-edit` 不帶 flag + 帶 flag scenarios)。
