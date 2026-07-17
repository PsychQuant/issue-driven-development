# IDD Workflow Paths (Sanctioned Path Catalog)

> **Purpose**:把所有 sanctioned 的 IDD workflow paths 命名 + 文件化,讓使用者**explicit 選 path**,而非依賴 plugin 強制單一紀律。

> **狀態**:initial skeleton(由 AI agent 從既有 design corpus distill,user 補充未列 paths)。Maintained 維護紀律見 § Provenance。

---

## TL;DR

IDD plugin 不是「單一主幹道」,是「**航線圖**」:從 `idd-issue` 到 `idd-close`,有多條合法 path,各自服務不同 use case + mode + complexity tier。

本文件**命名 + 文件化**這些 paths,讓:
- 使用者在 invoke skill 之前 explicit 知道「我選的是哪條 path」
- Plugin 設計者加新功能時 explicit 知道「這要新增 path 還是 modify 既有 path」
- Plugin reviewer 評估 PR 時 explicit 看到「這條 path 跟其他 path 怎麼共存」

**對比強制紀律**:強制紀律假設只有一條對的 path,把其他 path 都當違規;path catalog 承認多 path 並存,各 path 有 named use case,**discipline 在使用者選 path 時 explicit**,不是 plugin 替使用者強制。

---

## How to read this doc

1. **§ Path Catalog**:逐 path 列名稱、串連、use case、mode、assumptions、risks
2. **§ Path × Skill Matrix**:看 matrix 查 skill 出現在哪些 path
3. **§ Path Selection Decision Tree**:依情境選 path
4. **§ Anti-patterns**:列 misuse pattern
5. **§ Provenance**:本文件來源 + maintenance discipline

---

## Path Catalog

### A. Single-issue lifecycle paths(typical bug / feature flow)

#### P-atomic — Simple complexity baseline

```
idd-issue → idd-diagnose → idd-implement → idd-verify → idd-close
```

- **Use case**:典型 bug fix,clear root cause,單檔 / Follow existing pattern
- **Mode**:Attended(每步 user-reviewable)
- **觸發點數**:5 invocations
- **Assumptions**:diagnose 後 verdict = `Simple`
- **Risks**:無特別風險;最低 friction discipline-default path
- **Cross-link**:MANIFESTO § 5-checkpoint design

#### P-plan-gated — Plan tier with EnterPlanMode approval

```
idd-issue → idd-diagnose → idd-plan → idd-implement → idd-verify → idd-close
```

- **Use case**:multi-file ordered dependency / 5+ steps / decision-heavy / risk-sensitive boundary
- **Mode**:Attended(EnterPlanMode 必須 user approve)
- **觸發點數**:6
- **Assumptions**:diagnose 後 verdict = `Plan`,user 對 Implementation Plan 親 review
- **Risks**:Plan 過度 framing 可能 over-design;以 30 秒 read-time 為標準

#### P-spectra-discuss-first — Spectra tier with alignment

```
idd-issue → idd-diagnose → spectra-discuss → spectra-propose → spectra-apply → idd-verify → idd-close
```

- **Use case**:對外暴露 published API / protocol / skill / tool surface 給 future callers
- **Mode**:Attended(多 deliberation moments)
- **觸發點數**:7
- **Assumptions**:diagnose 後 verdict = `Spectra`,有命名 / 範圍 / trade-off 的 open questions
- **Risks**:over-trigger(narrative work 不該升 Spectra)— 看 MANIFESTO anti-pattern section

#### P-spectra-opt-out — Spectra with direction pre-confirmed(罕用)

```
idd-issue → idd-diagnose → spectra-propose → spectra-apply → idd-verify → idd-close
```

- **Use case**:Spectra tier 但方向已在 issue / diagnosis 明確選定,零 open questions
- **Mode**:Attended(propose 仍需 user review)
- **觸發點數**:6
- **Assumptions**:**ALL opt-out conditions 成立**(per `idd-diagnose` SKILL.md Step 3.5)
- **Risks**:跳過 discuss 容易 build proposal on unconfirmed assumptions

---

#### P-meeting — meeting-type deliberation（#57，v2.93+）

`idd-issue --type meeting` → `idd-diagnose`（type=meeting 最優先分流：Phase A/B/C 審議 Strategy，**不進** Layer 1 / Layer V / Spectra / 硬閘 / Layer P，無 complexity verdict）→ `idd-plan`（meeting-adapted Plan body：議程 → 決策點 → 行動項；**不 chain** idd-implement）→ 會議本體（user-driven）→ `idd-close`（meeting-specific gate：最新 Meeting Plan Phase C → fallback diagnose Strategy Phase C，行動項逐條 disposition；decision→action mapping，無 /idd-verify）。

- **Use case**：審議/決策工作 — deliverable 是決策與 follow-up，不是 code
- **Touchpoints**：4（issue → 審議 plan approve → 會議 → close disposition）
- **Risk**：low — 全程 attended by nature

### B. Convenience-orchestrator paths(快速 lifecycle 完成)

#### P-auto-from-diagnosed — diagnose 已過,跑自動化

```
[idd-issue → idd-diagnose 已完成]
↓
idd-all #N
```

- **Use case**:diagnose 階段已 surface complexity verdict,user 已 review;接下來 implement+verify+close 走 automation
- **Mode**:Hybrid(Plan tier 仍走 EnterPlanMode,Simple/Spectra 不阻擋)
- **觸發點數**:1(after diagnose)
- **Assumptions**:`gh issue view #N` 已有 `## Diagnosis` comment
- **Risks**:低 — deliberation 已 user-honored
- **Note**:本 path 是 P-atomic / P-plan-gated 的 implement-onward 加速版

#### P-auto-full-swallow — legacy `idd-all` 一次跑完

```
idd-issue → idd-all #N
```

- **Use case**:trusted automation context;user 接受 internal diagnose 走 Layer V `proceed anyway` default
- **Mode**:Hybrid degraded(unattended diagnose / attended Plan gate)
- **觸發點數**:2
- **Assumptions**:user 信任 AI 對 issue 的 internal diagnose 不會 misalign
- **Risks**:**中-高** — deliberation moment 被 swallow;若 issue body 模糊,AI auto-proceed 可能 mis-route
- **適用情境**:`/loop` autonomous mode / quick housekeeping P3 issues
- **Cross-link**:#122 提案改 Supervised Automation

#### P-batch-drain — multi-issue conflict-class-ordered sequential（v2.83+，#182）

`idd-all #a #b #c`（≥2 distinct #N）= 對 backlog 做 **sequential** drain，外圈按各 issue Diagnosis 的 `### Conflict Class` 排序（E/D 先、B/C 同資源相鄰、A 順序不拘）。**誠實邊界：不是並發** — taxonomy 是「手動跨 session / 未來 primitive」的並行安全契約。

- **Use case**：積壓清倉（本 repo 2026-07 focused drain 即此 path 實例）
- **Touchpoints**：2 + 決策檢查點（decision-heavy issue 停在 diagnosed 等拍板）
- **Risk**：middle — unattended 段沿用 P-auto 系列 risk；排序保證同資源不交錯

#### P-cluster-pr — N issues 共 1 PR

```
[各 issue 各自 idd-diagnose]
↓
idd-all #N #M #K --pr
```

- **Use case**:同根 N issues 同 cluster 處理,1 PR review surface
- **Mode**:Attended/Hybrid
- **觸發點數**:1(+ per-issue close after merge)
- **Assumptions**:N issues 同根 / 同 cluster 主題;每 issue 已 diagnose
- **Risks**:cluster PR 內某 issue verify FAIL 影響整個 PR;close 階段需 per-issue closing summary
- **Cross-link**:`references/batch-and-cluster.md`

#### P-chain-from-root — 1 root + auto-emergent spawn

```
[idd-issue → idd-diagnose for root]
↓
idd-all-chain #N
```

- **Use case**:預期 root issue 會 ripple 出 sister bugs / follow-up findings,想單 PR 解決整個 ripple
- **Mode**:Hybrid(Phase 0.4 detect no-diagnosis 會 AskUserQuestion)
- **觸發點數**:1(+ per-issue close after merge)
- **Assumptions**:root 已 diagnose;spawn 依靠 sub-skill manifest 自動偵測
- **Risks**:**高** — root diagnose 錯 → N spawn 全錯;chain cap depth=3 / max-issues=10 hard cap

#### P-chain-multi-root — 多 root forest chain

```
[batch idd-diagnose for N roots]
↓
idd-all-chain #N #M --bfs
```

- **Use case**:N 個 root 屬 sibling cluster(同 source doc),想一次 chain
- **Mode**:Hybrid
- **觸發點數**:1
- **Assumptions**:N roots 都 OPEN + 都已 diagnose;N ≤ 10(chain max-issues cap)
- **Risks**:**很高** — N×spawn 放大;一個 root fail 該 root subtree halt 但其他 root 繼續

---

### C. Batch paths(N issues 各自 atomic)

#### P-batch-diagnose

```
idd-diagnose #N #M #K
```

- **Use case**:同 doc 來源 N issues,各自 diagnose 各 user-reviewable
- **Mode**:Attended(per-issue verdict review)
- **Touchpoints**:1 invocation
- **Risk**:低 — 每 issue 各自 diagnose 不互相影響

#### P-batch-comment

```
idd-comment #N #M --type note --body "..."
```

- **Use case**:批次加同一段 note(e.g.「blocked by upstream」)到多 issue
- **Mode**:Unattended-capable

#### P-batch-update

```
idd-update #N #M
```

- **Use case**:批次同步 Current Status phase

#### P-batch-edit

```
idd-edit comment:NNN comment:MMM --replace --body "..."
```

- **Use case**:批次套同一段 edit 到多 issue 既存 comment

#### P-batch-close

```
idd-close #N #M
```

- **Use case**:cluster PR merge 後批次 close,**每個 issue 仍各自獨立 closing summary**
- **Critical**:**禁止偷懶**寫一段共用 summary;cluster-PR close mode 強制 per-issue summary

---

### D. Multi-finding dispatch paths(source-driven mixed routing)

#### P-multi-finding(auto-triggered)

```
idd-issue source.docx   # source 含 ≥2 findings 自動 trigger
```

- **Use case**:文件含多個獨立 finding,部分 → NEW issue,部分 → COMMENT/EDIT 既存 issue
- **Mode**:Attended(per-finding picker + Stage 3 batch preview)
- **Touchpoints**:1 invocation(含 N AskUserQuestion)
- **Risks**:Stage 4 dispatch 中途某 action 失敗 → warn-continue,user 需手動補

#### P-no-multi-finding(force single-issue)

```
idd-issue source.docx --no-multi-finding
```

- **Use case**:強制把整個 source 變 1 issue body;適用 source 雖含多段但本質是同一議題
- **Mode**:Attended

---

### E. Verify-only / PR-review paths(external agent integration)

#### P-pr-verify

```
idd-verify --pr 71
```

- **Use case**:外部 agent(Codex / Copilot)開的 PR,IDD 6-AI ensemble verify
- **Mode**:Unattended-capable
- **Assumptions**:PR 已 reference 某 issue(`Refs #N` / `Closes #N`)
- **Risk**:低 — verify 是 read-only verification,findings post 成 comment

#### P-pr-verify-then-merge

```
idd-verify --pr 71 → (verify-gated PASS) → gh pr merge 71 --squash
```

- **Use case**:verify-gated PASS 後 user 主動 merge,**per IDD MANIFESTO**「auto-merge 須走 #37,目前禁止」
- **Mode**:Attended(merge 由 user 觸發)
- **Critical**:即使 verify 全 PASS,**禁止** plugin 自動 merge;`idd-close` 仍要跑

---

### F. Resume / continuation paths(mid-work recovery)

#### P-spectra-resume

```
[change in progress, requirements changed]
↓
/spectra-ingest → /spectra-apply
```

- **Use case**:Spectra change 中途 requirements 變更,重新對齊 spec 後繼續
- **Mode**:Attended

#### P-implement-retry

```
idd-implement #N --branch-override <existing-branch>
```

- **Use case**:Chain mode 某 issue verify FAIL,retry on cluster branch(避免另開新 branch)
- **Mode**:Attended

---

### G. Non-lifecycle / ancillary paths(maintenance + observation)

#### P-list-triage

```
idd-list --label "company:QEF_DESIGN" --state open
```

- **Use case**:開工前 triage,看哪些 open issue,各自 phase 為何
- **Mode**:Unattended-capable
- **Risk**:無(read-only)

#### P-route-recommend

```
idd-route recommend --complexity Plan --signals ... --candidates ...
```

- **Use case**:選 agent(Codex / Claude / etc.)
- **Mode**:Unattended-capable

#### P-comment-only(非 lifecycle 推進)

```
idd-comment #N --type decision --body "..."
```

- **Use case**:加 decision / note / question / correction / link / errata 到既存 issue,不走 phase
- **Mode**:Attended/Unattended hybrid
- **6 types**:decision / note / question / correction / link / errata

#### P-edit-only

```
idd-edit comment:NNN --append --body "..."
```

- **Use case**:編輯既存 comment(append / replace / prepend-note)
- **Mode**:Attended(show 原 body + preview 新 body)

---

#### P-discussions-intake — Discussions 盲點橋接（#221，v2.95+）

`idd-list --discussions`（opt-in surface：Q&A/Ideas ∧ 未答 ∧ 未被 issue 引用）→ **人判斷** → `idd-issue --from-discussion <url>`（Provenance verbatim seed + draft-and-confirm 回文）→ 進任一 single-issue lifecycle path。

- **鐵律**：絕不 auto-file、絕不 auto-post 回文（unattended draft-only）
- **Use case**：使用者回報以 GitHub Discussion 抵達（che-ical-mcp 105 事故的制度化解）
- **Risk**：low — surfacing read-only；outward write 有 confirm gate

#### P-clarify-audit — terminology / semantic surfacing（#135，v2.72+）

`idd-clarify #N`（standalone，或被 idd-issue Step 4.6 delegate、被 idd-diagnose Step 0.5 gate 消費）→ `### Clarity Surface` annotation block（surfaced/resolved/dismissed rows）。Read-only surfacing primitive — 不 mutate lifecycle state，但其 surfaced rows 會 hard-block 後續 diagnose（gate 在 diagnose 端）。

- **Use case**：issue body 用詞/語意精度審查；retroactive audit
- **Risk**：low — 唯一副作用是 annotation block 寫入

### H. Unsupervised / autopilot paths(no human-in-loop)

#### P-loop-autopilot

```
/loop /idd-all #N
```

- **Use case**:autonomous 持續執行;適合 well-bounded simple issues
- **Mode**:Unattended
- **Risks**:**極高** — deliberation 完全 absent;若 issue 模糊 / multi-step / Plan tier,Plan gate 仍 trigger 但 EnterPlanMode 無人 approve → 卡住

#### P-cron-autopilot

```
/schedule "0 2 * * 0" /idd-all
```

- **Use case**:cron-scheduled ETL / housekeeping
- **Mode**:Unattended

#### P-cron-list-triage

```
/schedule "0 9 * * 1" /idd-list --state open --limit 50
```

- **Use case**:每週一 9am 印出 open issue triage report
- **Mode**:Unattended
- **Risk**:低(只 list,不 mutate)

---

## Path × Skill Matrix

| Skill | A:atomic | A:plan | A:spectra | B:auto | B:cluster | B:chain | C:batch | D:multi-finding | E:pr-verify | F:resume | G:non-lifecycle | H:autopilot |
|-------|---|---|---|---|---|---|---|---|---|---|---|---|
| `idd-issue` | ✓ | ✓ | ✓ | (前提) | (前提) | (前提) | | ✓ multi-finding | | | | |
| `idd-diagnose` | ✓ | ✓ | ✓ | (前提) | (前提) | (前提) | ✓ batch | | | | | |
| `idd-plan` | | ✓ | | (inside auto) | | | | | | | | |
| `spectra-discuss` | | | ✓ | | | | | | | (前提) | | |
| `spectra-propose` | | | ✓ (含 opt-out) | | | | | | | (前提) | | |
| `spectra-apply` | | | ✓ | | | | | | | ✓ resume | | |
| `idd-implement` | ✓ | ✓ | (within apply) | (inside auto) | (inside cluster) | (inside chain) | | | | ✓ retry | | (inside loop) |
| `idd-verify` | ✓ | ✓ | ✓ | (inside auto) | (inside cluster) | (inside chain) | | | ✓ standalone | | | (inside loop) |
| `idd-close` | ✓ | ✓ | ✓ | (after auto) | ✓ batch | ✓ batch | ✓ batch | | (after merge) | | | (after loop) |
| `idd-update` | (auto-called) | (auto-called) | (auto-called) | (auto-called) | | | ✓ batch | | | | | |
| `idd-comment` | | | | | | | ✓ batch | | | | ✓ standalone | |
| `idd-edit` | | | | | | | ✓ batch | | | | ✓ standalone | |
| `idd-list` | | | | | | | | | | | ✓ triage | ✓ cron |
| `idd-clarify` | (issue 內 delegate) | | | | | | | | | | ✓ standalone audit | |
| `idd-report` | | | | | | | | | | | ✓ aggregate | |
| `idd-route` | | | | | | | | | | | ✓ recommend | |
| `idd-all` | | | | ✓ all variants | ✓ cluster | | | | | | | ✓ loop |
| `idd-all-chain` | | | | | | ✓ all variants | | | | | | ✓ rare |

---

## Path Selection Decision Tree

```
Q1: 是 single issue 還是 multi issues?
├── Single
│   └── Q1.5: type=meeting? ── Yes → P-meeting（複雜度評估前分流）
│   └── Q2: 預期是 Simple / Plan / Spectra?（#129 硬閘：≥5 檔互依概念 / shared abstraction → MUST Plan，先於 Layer P）
│       ├── Simple
│       │   └── Q3: attended (你在 keyboard)?
│       │       ├── Yes → P-atomic (5 touchpoints)
│       │       └── No (autonomous) → P-auto-full-swallow (2 touchpoints, risk: middle)
│       ├── Plan
│       │   └── P-plan-gated (6 touchpoints, EnterPlanMode required)
│       └── Spectra
│           └── Q4: direction 已明確 (零 open questions)?
│               ├── Yes → P-spectra-opt-out (rare)
│               └── No  → P-spectra-discuss-first (default)
│
└── Multi
    └── Q5: 同根 cluster 還是 ripple chain?
        ├── 同根 (parallel cluster)
        │   └── P-batch-diagnose → P-cluster-pr
        ├── Ripple (1 root + auto-emerge)
        │   └── P-batch-diagnose root + P-chain-from-root
        ├── Forest (N roots independent)
        │   └── P-batch-diagnose all + P-chain-multi-root (or N × P-atomic)
        └── Source-driven mixed routing
            └── P-multi-finding (auto-trigger when source ≥2 findings)
```

---

## Anti-patterns(不該走的 path combination)

### A1. 跳過 diagnose 走 P-spectra-opt-out

> 「issue body 我寫得很詳細,直接 propose 吧」

**Wrong**:Spectra opt-out 的 ALL conditions(per `idd-diagnose` SKILL.md Step 3.5)必須先走 diagnose 才知道是否成立。**不能** issue body 寫詳細就跳 diagnose。

### A2. P-loop-autopilot 跑 Plan tier issue

> `/loop /idd-all #N`(其中 #N diagnose 後 verdict = Plan)

**Wrong**:Plan tier EnterPlanMode 需 user approve,unsupervised loop 無人 approve,**卡住**。應改 verdict 為 Simple,或拒絕進 loop。

### A3. P-chain-from-root 多 root 用 batch 跑

> `idd-all-chain "14 個 issues"`

**Wrong**:14 > chain max-issues=10 cap;且 14 個 sibling 不是 ripple chain。應走 P-batch-diagnose 14 + (P-atomic 或 P-cluster-pr) per cluster。

### A4. P-cluster-pr 把不同根的 issue 強塞

> `idd-all #100 #200 #300 --pr`(三個無關 issues)

**Wrong**:cluster PR 預期 issues 共享 review surface(同根問題、同檔案範圍)。不同根 → reviewer cognitive load 爆表;應分 3 個 P-atomic。

### A5. 自動 close 走 verify-gated path

> verify PASS → 自動 `gh issue close`

**Wrong**:MANIFESTO 鐵律「auto-merge ≠ auto-close」;close 仍需 user invoke `idd-close` + closing summary。**verify-gated PASS** 只代表 ready to merge,**不**代表 done。

### A6. P-multi-finding 跟 P-bundle 混用

> `idd-issue source.docx --bundle-mode ordered`

**Wrong**:multi-finding(source-driven mixed routing)跟 bundle(explicit 多 issue creation + dependency)語意不同。Spec refuse 同時 set。

---

## Cross-links to Authoritative Sources

| Path concept | 權威 source |
|---|---|
| Single-issue lifecycle 5-checkpoint | `plugins/issue-driven-dev/MANIFESTO.md` § 5 Skill = 5 Checkpoint |
| Complexity tier(Simple/Plan/Spectra)決定走哪條 path | `plugins/issue-driven-dev/rules/sdd-integration.md` § 4-layer / 3-tier |
| Batch / Cluster contract | `plugins/issue-driven-dev/references/batch-and-cluster.md` |
| Chain shell algorithm | `plugins/issue-driven-dev/references/chain-flow.md` |
| Spectra workflow(discuss → propose → apply → archive) | `plugins/issue-driven-dev/skills/spectra-*/SKILL.md` |
| Multi-finding mode | `plugins/issue-driven-dev/skills/idd-issue/SKILL.md` § Multi-finding source mode |
| auto-merge vs auto-close 鐵律 | MANIFESTO § auto-merge 的合法性與限制 |
| Default dilemma framework(指引何時加 flag vs 開 separate skill) | `docs/design-patterns/default-dilemma.md` |
| Skill dimensions(原子單位的軸) | `docs/skill-dimensions.md` |

---

## Provenance

> **2026-07-17（#122 補完）**：catalog 由 skeleton 補至 v2.96 現實 — 新增 P-meeting（#57）、P-batch-drain（#182）、P-discussions-intake（#221）、P-clarify-audit（#135）；decision tree 補 meeting 分流 + #129 硬閘；matrix 補 idd-clarify 列。後續新 path 隨 feature 落地就地 iterate（使用者裁決：本檔可就地補、不另開 issue）。


- **首次版本**:2026-05-21 — AI agent skeleton,由 user 對 #122(原 marketplace#89,已 transfer 過來)提出 reframing(「不是強制,而是把所有可能 path 都列出來」)觸發
- **觸發 insight**:user observation:強制單一 path 違反 user agency;path catalog 讓 discipline 在 user 選 path 時 explicit

### Maintenance discipline

- **Single source of truth**:具體 path 規則住在各 `references/*.md` / SKILL.md / MANIFESTO.md。本文件**只**是 path catalog 的 navigation。
- **加新 path 時**:
  1. 先在對應 authoritative source 文件化(e.g. references/batch-and-cluster.md)
  2. 再到本文件加 path entry(name / use case / skills / mode / assumptions / risks)
  3. 更新 § Path × Skill Matrix 該 path 欄
  4. 評估是否需要新增到 § Path Selection Decision Tree
- **棄用 path 時**:不要刪掉,**標記 deprecated**並 cross-link 到取代 path,保留歷史 audit trail
- **避免 drift**:本文件 grow 成 second source of truth(各 path 具體規則在這邊複製,而非 cross-link 出去)= violation
