## Context

IDD plugin 既有 14+ skill,組成完整的 issue-driven dev pipeline:
`idd-issue → idd-diagnose → idd-plan / idd-implement → idd-verify → idd-close`(含 orchestrator `idd-all` + cluster `idd-all-chain`)。

但 quality safeguard 只覆蓋兩軸:
- **Confidence**(IC_R010):客戶是否真的反映?
- **Verbatim**(IC_R007):原文是否被改寫?

第三軸 **Terminology / Semantic accuracy**(source 用詞是否正確;隱含 missing context)無對應 mechanism。

具體缺口(per #804 incident):客戶 docx 寫「特徵值」實際意思是「分群變數」,AI 沿用 source 原詞到 issue body + diagnosis。Spec.md 階段 AI 獨立修對是運氣,不是 systematic safeguard。

本 session 4 instances of recursive evidence(D06 collision / Step 4.8 collision / customer_attributes 來源未指定 / 三輪 design over-abstract)— 每一次 user 抓到 AI under-verification。**Codify 後 AI 對下一個 issue 不會繼續犯**。

Stakeholders:
- IDD plugin maintainer(本 PR owner)
- All IDD plugin consumers(QEF_DESIGN / ai_martech_global_scripts / l4_enterprise 各 commercial repo)
- Future IDD skill designers(三軸 framing 是 design principle)

## Goals / Non-Goals

### Goals

- 補上 IDD skill graph 第三 quality axis(terminology / semantic accuracy)
- Surface-only 機制:不替 user 找答案(沒 oracle 不可能),只把 doubt 放到 issue body
- 跟既有 IC_R007 verbatim preservation 共存(blockquote 原文不動,annotation 加在另一 section)
- Composable primitive 設計:`/idd-clarify` 可獨立 retroactive run,也可被 `idd-issue` Step 4.6 delegate

### Non-Goals

- 不做 resolution(失職 gatekeeper paradox)— user 自己標 dismissed / resolved
- 不替代 `/spectra-discuss`(concept-level design alignment) — 不重疊 scope
- 不整合 `/idd-edit` / `/idd-update`(symmetry expansion,留給 sister #136 P3)
- 不解 unattended-mode contract gap(留給 sister #137 P2 同步 design)
- 不做動態 LLM-fetched terminology library(初版用靜態 `references/terminology-canonical.md`,plugin-level extensible)

## Decisions

### D1: Step 4.6 placement(不 4.8 / 4.9)

`idd-issue` Step 4.6 auto-invoke `/idd-clarify`,夾在 Step 4.5 milestone 跟 Step 4.7 sister sweep 之間。

**Why 4.6 不 4.8**:scout 抓到 Step 4.8 已被 `Split Umbrella SOP`(#11 v2.54+)佔用。沿用 v3 design 寫的 4.8 會 collision。

**Why 4.6 不 4.9**:semantic order — terminology accuracy check 先於 coverage gap scan(sister sweep 4.7)。Clarity 改 body 後 sister sweep 看到更新版本。Anti-order(clarity 在 sister 之後)會讓 sister scan 看到 source 原詞 surface 出 sister concern,但其實只是 terminology problem 該被 clarify 處理 — 兩個 axis 混淆。

**Alternatives considered**:
- 4.9 在 4.8 之後 — semantic order 顛倒,scout / sister 之後跑 clarity 不自然
- 重編 4.6/4.7/4.8(rename existing Split Umbrella) — breaking change,backward compat issue

### D2: Hard refuse gate strength(idd-diagnose Step 0.5)

`idd-diagnose` Step 0.5 PR Gate 看到 unresolved `### Clarity Surface` rows → **REFUSE** with actionable message:
```
Issue #N has X unresolved Clarity Surface rows. Resolve via:
  - /idd-clarify #N --status resolved=<idx>   (記錄 user judgment)
  - /idd-clarify #N --status dismissed=<idx>  (記錄 false positive + reason)
  - LINE/email domain expert and update issue body manually
```

**Why hard refuse 不 warn-continue**:
- 同 PR Gate Check precedent(idd-close Step 1.5 拒 close 直到 unmerged PR 處理)
- 同 idd-all-chain #119 fail-fast 強制 explicit choice precedent
- Warn-continue 會讓 surface 被 silent ignore = 整個 skill 沒用,違反 codify 初衷
- Dismiss 是 1-step 操作(`--status dismissed=N`),user 想 skip 1 秒鐘的事 — refuse + easy-dismiss 等價於 explicit choice,不擾人

**Alternatives considered**:
- SHOULD advisory(同 closing-followup-keyword-scan):closure 是 mechanical action 故 advisory 合理;但 diagnose 是 decision moment,strength 不對等
- Configurable per-issue:複雜度過高,違反 simple-by-default

### D3: Auto-trigger scope(idd-issue Step 4.6)

- **doc source(.docx / .pdf):auto-run** — 客戶 / 老師慣用詞最常入侵,高 terminology risk
- **pasted-text:auto-run** — cheap heuristic check,low cost
- **`--multi-finding` mode:SKIP** — 每個 finding 自己 sub-invocation 跑會 multiply prompt;multi-finding 有自己 classification

**Why doc + pasted-text 都跑**:source 是 plain text,scan 都 cheap。把 trigger 限縮成 doc-only 會漏掉 LINE 對話 / customer email pasted 進來的 case(實際上 #804 incident 的「特徵值」也是書面客戶建議,但若是 LINE pasted 也該抓)。

**Why `--multi-finding` skip**:multi-finding 把單一 source split N 個 findings,每個 finding 又跑一次 clarify 會 N×N 個 prompt(以 5 findings × avg 1.5 misuse pattern = 7-8 prompt 從一個 docx 來,擾人)。multi-finding 自己的 confidence triage 已 cover semantic分類,加 clarity 重複。

**Alternatives considered**:
- Only doc source — 漏掉 pasted email / LINE conversation
- All including --multi-finding — 過度打擾

### D4: Library governance(rule-of-three + open PR + plugin-level extension)

`references/terminology-canonical.md` 初版 seed 6 rows(對齊 #135 body 列出的 6 個 misuse pattern):

1. 特徵值 (eigenvalue) + K-means context → 分群變數 / distinguishing variable
2. PCA + K-means 混用 → 確認 dimensionality reduction vs clustering
3. 回歸 + ANOVA 用詞混用 → 看 H0 / 自變數結構決定
4. 「準確率」+ regression context → RMSE / R²
5. 「P 值」+ Bayesian context → posterior / credible interval
6. 「分群」+ 有 ground truth label → 分類 / classification(non-unsupervised)

**Promotion threshold**:同 misuse 在不同 codebase 出現 3 次升格進 canonical(rule-of-three,IDD 既有 promotion discipline,從 #815 SOP 學)。

**Open contribution**:user PR welcome,加 new row 經 maintainer review。

**Plugin-level extension**(future):允許 plugin-specific terminology library — e.g. medical plugin 寫 `references/terminology-canonical-medical.md`,idd-clarify 載入時 chain merge。

**Why 不 dynamic LLM-fetched**:固定庫可預測 + reproducible + user 可 audit;dynamic LLM 每次都不同 surface,違反 IDD audit trail discipline。

**Alternatives considered**:
- Maintainer closed contribution — plugin ecosystem 無法擴
- Dynamic LLM library — non-reproducible
- Per-issue inline library — duplicate maintenance

### D5: Clarity vs Spectra-discuss boundary(text-level vs concept-level)

| Skill | Scope | Output |
|---|---|---|
| `/idd-clarify` | **既有 issue body** 文字 audit(terminology / ambiguity / missing-context)| Annotation block in issue body |
| `/spectra-discuss` | **Design space** alignment(assumption listing / decision exploration / future-shape)| proposal / design / discussion artifacts |

**Cross-link rule**:clarify 發現 missing-context 需要 design discussion → annotation 標 「Recommend /spectra-discuss for row N」,但 **clarify 不自動進 spectra workflow**。User 看完 annotation 自己決定要不要起 spectra change。

**Why 不互相 chain**:
- Spectra workflow 是 deep multi-turn(discuss → propose → apply),expensive
- Clarify 是 light-touch annotation,cheap
- 自動 chain 會把 clarity-level surface 升級成 spectra workflow,過度

**Alternatives considered**:
- 自動 chain on missing-context — overkill
- Merge clarify into spectra-discuss — 不同 scope(text vs concept)

## Implementation Contract

### Observable Behavior

#### Behavior 1: `/idd-clarify #N` standalone invocation

Given an existing issue #N with body containing potential terminology / ambiguity / missing-context issues, when user invokes `/idd-clarify #N`, the skill SHALL:

1. Read issue body via `gh issue view #N`
2. Scan body against `references/terminology-canonical.md` heuristic rules
3. Scan body for ambiguity markers(per skill SKILL.md heuristic — multiple plausible interpretations,under-specified critical variables)
4. Scan body for missing-context markers(per heuristic — analysis requires X but X 來源 not specified)
5. Compose `### Clarity Surface(idd-clarify run <ISO timestamp>)` block with rows:
   - Type column(terminology / ambiguity / missing-context)
   - Source column(quoted excerpt from issue body)
   - Suggested canonical column(per heuristic lookup or detected gap)
   - Status column(default `surfaced`)
6. PATCH issue body to append the block(per IC_R007:do NOT modify original blockquote,append new section)
7. Echo summary to user:`{N} rows surfaced. Resolve via /idd-clarify #{N} --status resolved=<idx>|dismissed=<idx>`

Empty surface case:Step 6 PATCH 仍 emit `### Clarity Surface` block with row `(none — no issues detected)`,Status 標 `passed`。

#### Behavior 2: `/idd-clarify #N --status <action>=<row_idx>[,<reason>]` resolution

User update individual row status:
- `resolved=<idx>` — 已 clarify(經 LINE / email / 對話跟 domain expert 確認,canonical 已選定);`reason` 描述 resolution(e.g. 「老師確認用 'distinguishing variable'」)
- `dismissed=<idx>` — false positive(AI heuristic 誤判,原 source 用詞正確);`reason` 描述原因(e.g. 「特徵值在這裡指數學意義 eigenvalue,客戶懂統計」)

Skill PATCH 對應 row Status column;**不**刪除 row(保留 audit trail)。

#### Behavior 3: `idd-issue` Step 4.6 auto-delegate

`idd-issue` Step 4.6(insert between 既有 4.5 + 4.7)Bootstrap TaskCreate 加 entry:
```
TaskCreate(name="clarity_surface", description="Step 4.6: delegate to /idd-clarify $NEW_ISSUE_NUMBER per IC clarity axis")
```

Step 4.6 body:當 issue 成功 file(post Step 3 issue creation + post Step 4 attachments)、source 是 doc 或 pasted-text 且**不是** `--multi-finding` mode → `Skill(skill="idd-clarify", args="#$NEW_ISSUE_NUMBER")` delegate。

`--multi-finding` mode 強制 skip(per D3)。

#### Behavior 4: `idd-diagnose` Step 0.5 PR Gate

`idd-diagnose` Step 0.5(insert before Step 1 read issue)Bootstrap TaskCreate 加 entry:
```
TaskCreate(name="clarity_gate_check", description="Step 0.5: grep issue body for ### Clarity Surface unresolved rows; refuse if any per D2 hard refuse")
```

Step 0.5 body:
1. `gh issue view #N --json body` 讀 body
2. Grep `### Clarity Surface` block
3. Count rows with `Status: surfaced`(default)— `unresolved_count`
4. If `unresolved_count > 0` → REFUSE with structured message(D2 quoted text)
5. If `unresolved_count = 0`(全 dismissed / resolved / passed)→ proceed to Step 1

### Acceptance Criteria

- Behavior 1:對 6 個 #135 seed pattern 在 fixture issue body 跑,正確 surface 對應 row(integration test)
- Behavior 2:`--status` flag 3 種 action 都正確 PATCH 對應 row;invalid `<idx>` 報 actionable error
- Behavior 3:`idd-issue` 對 `.docx` source 跑後,issue body 末段含 `### Clarity Surface` section(E2E test)
- Behavior 4:Issue body 含 surfaced row → `/idd-diagnose` exit non-zero with REFUSE message;全 dismissed → 正常 proceed

### Out of Scope

- 不解 `idd-edit` / `idd-update` integration(sister #136)
- 不解 unattended-mode interaction contract(sister #137)
- 不做 dynamic LLM-fetched library
- 不改 IC_R007 blockquote source preservation

## Risks / Trade-offs

| Risk | Severity | Mitigation |
|---|---|---|
| Self-reference recursion(本 PR 自己 design 過 #135 v3 implementation)| LOW | spectra-discuss 階段 reviewer 可 push back(本 propose 已收斂 5 decision)|
| Backward compat break(idd-issue Step 4.6 + idd-diagnose Step 0.5 都是 normative add)| MEDIUM | 既有 issue 缺 Clarity Surface block → idd-diagnose Step 0.5 grep 0 rows → 自然 proceed(無 silent break)|
| Terminology heuristic over-trigger(false positive 過多)| MEDIUM | Surfacing-only + 1-step dismiss + status audit;Rule-of-three 確保庫成長 conservative |
| Maintainer authority for terminology library | LOW | Initial seed 6 rows 已覆蓋 K-means + 統計常見 misuse;Rule-of-three 自然限制 frivolous PR;Open contribution 民主 |
| `/idd-all` unattended mode 跟 Step 4.6 auto-invoke 衝突(sister #137)| MEDIUM | 本 PR 範圍**不**解 — sister #137 P2 同步 design;暫定 unattended auto-dismiss + audit trail,implementation 階段對齊 |
| Plugin version 升級對 cluster ralph-loop / /goal caller 影響 | LOW | Minor version bump(new skill = backward compat additive);既有 caller invoke 行為不變 |
| Library file 跨 commit drift(library 改但 idd-clarify 沒重 load)| LOW | idd-clarify 每次 invoke 都 fresh read library(no cache),drift 自然解 |

## Migration Plan

### Deploy

1. Merge PR → IDD plugin minor version bump(v2.71.0 估)
2. User 跑 `claude plugin update issue-driven-dev`(transparent — 既有 cmd 跟 issue 不變,只新增 `/idd-clarify`)
3. Auto-trigger Step 4.6 對新 issue 立即生效;既有 issue 不受影響(no retroactive surface)
4. Step 0.5 gate 對所有 issue 生效:無 Clarity Surface block 的舊 issue grep 0 rows → 自然 proceed
5. Retroactive audit(optional):user 自己跑 `/idd-clarify #N` 對舊 issue 一個一個 audit

### Rollback

- Plugin version 降級 → 舊版無 Step 4.6 / Step 0.5 gate,既有 Clarity Surface block 保留但不檢
- Issue body 含 `### Clarity Surface` section 在 plugin downgrade 後是 dead annotation,但**不**有害(plain markdown,不影響 idd-issue / idd-diagnose 既有流程)
- 庫檔 `references/terminology-canonical.md` 留在 IDD repo,user 可繼續引用做 manual reference

### Backward Compat

| 既有 caller | 行為 |
|---|---|
| `idd-issue` 新建 issue(doc source) | Step 4.6 auto-delegate,annotation 加進 body,流程不變,只多一段 audit |
| `idd-issue --multi-finding` | Skip Step 4.6,行為跟 v2.70 完全一致 |
| `idd-diagnose` 跑既有 issue(無 Clarity Surface) | Step 0.5 grep 0 → proceed,行為跟 v2.70 一致 |
| `idd-diagnose` 跑新 issue(有 unresolved Clarity Surface) | Step 0.5 REFUSE — **NEW BEHAVIOR**,user 需 resolve / dismiss |
| `idd-all` PR mode | 兼容 — sub-skill idd-diagnose 可能 REFUSE,idd-all 收到 abort 自然處理(per idd-all 既有 abort flow)|
| `idd-all-chain` | 同 idd-all;若某 issue REFUSE,cluster fail-fast 一致 |
| Retroactive `/idd-clarify #N` | New behavior;user voluntary,不 break 任何 caller |

## Open Questions

### Q1: Sister #137 unattended-mode contract specifics

Step 4.6 在 `/idd-all` PR mode unattended 下行為:
- 選項 a:auto-dismiss all surfaced rows + audit `(auto-dismissed under unattended mode)`(同 Layer V Step 3.4 unattended fallback)
- 選項 b:Step 0.5 gate fail-fast → idd-all abort(cluster fail-fast)
- 選項 c:auto-status `pending-review`(中間態,downstream not-blocked but visibility-flagged)

**Resolution**:sister #137 在本 PR implementation 期間 parallel design;若沒 ship 之前,**暫定選 b**(fail-fast,符合既有 idd-all-chain #119 哲學),implementation 階段若客戶反映擾人改 a。

### Q2: Library file naming convention for plugin-level extension

`references/terminology-canonical.md` 是 plugin base library。若 future medical / legal plugin 也要加 terminology library:
- 選項 a:`references/terminology-canonical-{domain}.md`(domain 在 plugin metadata declare)
- 選項 b:plugin 自己 ship `references/terminology-canonical.md`,IDD chain-load

**Resolution**:本 PR 範圍**不**解 — initial seed 只放 IDD plugin own。Future plugin extension 等實際有 medical / legal plugin 才 design,鬆綁 over-engineering。

### Q3: Multi-language source — terminology library bilingual support

#804 source 是中文 docx,canonical term 也是中文。但若 source 是 English paper / Japanese feedback,terminology library 是否 multi-lingual?

**Resolution**:initial seed 6 rows 都是中文 misuse(per #135 body context),English / Japanese 等留給 rule-of-three 累積後再 design library structure。

### Q4: Status state machine — can dismissed → resolved transition?

User 標 dismissed 後改變心意要 resolved(經 domain expert 確認其實 misuse 是真的)— 允許嗎?

**Resolution**:**允許,且 audit trail 保留歷史**。`Status: resolved (was: dismissed @ <ISO>)` 格式記前狀態 + 切換時間。Implementation 階段 SKILL.md 寫明。
