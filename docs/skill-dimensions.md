# Skill Dimensions: How IDD Skills Differ from Each Other

> **Purpose**:把「設計向度」(design dimensions)明確化,讓 IDD plugin 維護者 + contributor 在加新 skill / 修舊 skill 時,**explicitly 對齊每個 dimension 的設計選擇**,而非 implicit drift。

> **狀態**:maintained（#122 補完 2026-07-17 — skeleton → 對齊 v2.96 現實）。Maintained 維護紀律見 § Provenance。

---

## TL;DR

IDD plugin 已累積 14+ skills(`idd-issue` / `idd-diagnose` / `idd-implement` / `idd-verify` / `idd-close` / `idd-update` / `idd-comment` / `idd-edit` / `idd-list` / `idd-plan` / `idd-report` / `idd-all` / `idd-all-chain` / `idd-route` / ...)。

各 skill 在以下 10+ 個設計**向度**上各自有立場。本文件**橫切**:每個向度是一個 axis,每個 skill 在 axis 上有一個值。

**為什麼要列出這些向度**:
- 加新 skill 時,先過所有 axis,確認每個選擇都 deliberate,而非 default-drift
- 改舊 skill 時,看 axis matrix 確認改動跨多少 dimensions(改一個 axis 比改三個 axis 影響範圍小)
- 開發者 onboarding 時,看 matrix 一眼看清楚 IDD plugin 的 design space

---

## How to read this doc

1. **§ Dimension Catalog**:逐個 axis 詳述
2. **§ Skill × Dimension Matrix**:看 matrix 快速 lookup
3. **§ Cross-links to authoritative sources**:axis 的權威定義位置(避免本文件 drift)
4. **§ Open Dimensions**:待 user 填 — AI agent 看不到的 axis

---

## Dimension Catalog

### D1: Separation vs Automation

**定義**:每個 skill step 是「強制獨立 entry point + commit boundary + deliberation moment」(separation),還是「被 wrapper 串起來一次跑完」(automation)。

**為什麼重要**:
- Deliberation moment(diagnose / plan / discuss)被 swallow 進 automation = 紀律 silently 失效
- Convenience 是 opt-in,Discipline 是 default — 這個 design principle 在其他 axis 一致,只在這裡破例

**Values**:
- `Separation` — 必須親手 invoke 下一步,系統拒絕跳過
- `Automation` — wrapper 串連,中間步驟透明
- `Supervised Automation`(中間態)— wrapper 跑但 deliberation moment 強制 fail-fast,提供 explicit escape hatch(flag),**不**用 AskUserQuestion soft gate

**判斷準則**:「這一步如果 AI 做錯,reversible 嗎?」
- YES → automation OK
- NO → 強制 separation

**Anti-pattern**:把「diagnose 是 deliberation moment」的紀律,放進「user 信任 AI 預設」的 automation 中。

**Cross-link**:#122 — 本向度的完整 design discussion + 3 個變更建議。

---

### D2: Atomic vs Orchestrator

**定義**:skill 是執行**一個** lifecycle step(atomic),還是把多個 atomic skills 串起來(orchestrator)。

**Values**:
- `Atomic` — 一個 lifecycle step;一次 invocation 一個 deliberation gate
- `Orchestrator` — 多 atomic 串聯;一次 invocation 多 gate(各 atomic 仍須 honor)
- `Sub-orchestrator` — 對齊 external mechanism(e.g. `idd-plan` 對齊 `EnterPlanMode`)

**為什麼重要**:Orchestrator 的 design challenge 是「**不該替 atomic skill 跳過 atomic skill 的紀律**」 — D1 violation 的主要場景。

**Anti-pattern**:orchestrator 內部用 helper script 重新實作 atomic 邏輯,造成 atomic skill 規則更新後 orchestrator 沒同步。**Orchestrator 應該 `Skill(skill="atomic-name", ...)` 真實呼叫 atomic,而非 inline 複製邏輯**。

---

### D3: Deliberation vs Execution

**定義**:skill 屬性是「人類決策時刻」(deliberation),還是「執行已決定的事」(execution)。

**Values**:
- `Deliberation` — diagnose / plan / discuss / propose;產出**判斷**(root cause / strategy / spec)
- `Execution` — implement / verify / close;產出**結果**(code / verify report / closing summary)
- `Side effect`(中間)— issue / comment / edit / update;單純更新外部 state(GitHub issue body),既非判斷也非執行

**為什麼重要**:Deliberation skill **不該** unattended-capable(D8),否則違反 NSQL P1(Read-Only for Humans);Execution skill 可以。

**Cross-link**:`plugins/issue-driven-dev/MANIFESTO.md` § Human-in-the-loop section。

---

### D4: Read-only vs Write

**定義**:skill 是否會 mutate state(GitHub / git / filesystem)。

**Values**:
- `Read-only` — `idd-list`(query GitHub)/ `idd-route recommend`(no state change)
- `Write` — 絕大多數 IDD skills

**為什麼重要**:Read-only skill 適合 `/loop` autonomous mode + CI;Write skill 必有 fail-safe + idempotency 考量。

---

### D5: Forward-rolling vs Backward-rolling

**定義**:skill 推動 issue lifecycle 往前(forward),還是收束既有 work 往後(backward)。

**Values**:
- `Forward-rolling` — issue → diagnose → plan → implement;每步開啟新 commitment
- `Backward-rolling` — verify → close → report;每步收束既有 commitment,要求 audit trail 對齊

**為什麼重要**:Backward-rolling skill 的 quality gate 更嚴(structural + semantic check, e.g. `idd-close` two-tier gate),因為一旦 close 就難 reopen。

**Cross-link**:MANIFESTO § Falsifiability — `idd-close` two-tier gate(structural + semantic)為什麼是 strict superset。

---

### D6: Single-target vs Batch vs Cluster vs Chain

**定義**:單次 invocation 處理 issue 數量 + 結構。

**Values**:
- `Single` — 1 issue per invocation(most skills baseline)
- `Batch` — N issue,各自獨立執行(`idd-diagnose #34 #36 #38`)
- `Cluster` — N issue + 1 PR(`idd-all #34 #36 --pr`,共用 branch + cluster diff)
- `Chain` — 1 root + auto-emergent spawn(`idd-all-chain #34`,遞迴 spawn manifest)

**為什麼重要**:
- Batch 對 deliberation skill 安全(N 個獨立 diagnose,各 user-reviewable)
- Cluster 對 execution skill 安全(N 個 implement 共 1 PR,review surface 集中)
- Chain 對**兩者都有風險** — root diagnose 錯 → N spawn 全錯;cluster PR rollback 棘手

**Cross-link**:`plugins/issue-driven-dev/references/batch-and-cluster.md`(canonical contract)。

---

### D7: Mandatory(SHALL) vs Advisory(SHOULD)

**定義**:skill step 是強制執行(SHALL),還是 heuristic 觸發(SHOULD)。

**Values**:
- `Mandatory (SHALL)` — `idd-diagnose` Step 3.4 Layer V Vagueness Pre-check / `idd-implement` TDD discipline / `idd-close` two-tier gate
- `Advisory (SHOULD)` — `idd-issue` Step 4.7 sister sweep / `idd-diagnose` Step 3.6 sister surface(per IC_R011)
- `Soft (heuristic + opt-out)` — Step 0 attached doc detection(presence vs absence)

**為什麼重要**:Advisory step 用 AskUserQuestion 3-option pattern(per IC_R011 canonical);Mandatory step 不該降級成 AskUserQuestion(那是 soft gate,等於 advisory)。

**Cross-link**:`plugins/issue-driven-dev/references/ic-r011-checkpoint.md`(canonical pattern)。

---

### D8: Attended vs Unattended-Capable

**定義**:skill 是否能在無 user TTY 環境(CI / `/loop` / autonomous mode)執行。

**Values**:
- `Attended-only` — Stage 2 picker / EnterPlanMode / `/spectra-discuss`(必須 user 在場回應)
- `Unattended-capable` — `idd-implement`(TDD loop)/ `idd-verify`(6-AI ensemble,no user interaction)/ `idd-list` / `idd-route`
- `Hybrid (attended preferred, unattended degraded)` — `idd-all`(attended:Plan tier 走 EnterPlanMode;unattended:auto-proceed default)/ `idd-all-chain` Phase 0.4

**為什麼重要**:Hybrid skills 是 D1(Separation vs Automation)的衝突 hotspot — unattended mode 容易 silent-bypass deliberation moment。

**Anti-pattern**:用 AskUserQuestion 在 unattended mode silent default to `proceed anyway` — 等於把 deliberation 自動化。

**Cross-link**:MANIFESTO § `--review` flag section(opt-in re-open confirmation loop)。

---

### D9: Invocation Modifier(flag) vs Separate Skill

**定義**:新功能是加 flag 到既有 skill,還是另開 separate skill。

**Values**:
- `Flag` — `--bundle-mode` / `--parent` / `--blocked-by` / `--multi-finding` / `--review` / `--cwd`
- `Separate skill` — `/idd-all-chain` vs `/idd-all --chain`(rejected per default-dilemma)

**為什麼重要**:flag 路徑成本是「default 設計 tax × every invocation」,separate skill 路徑成本是「skill 數量 cognitive cost」。**N 大時 separate skill 反而便宜**。

**Decision framework**:Default Dilemma trilemma(off / auto / ask 三個 default 都有 plausible 失敗)→ 證明 binary choice,該另開 skill。

**Cross-link**:`docs/design-patterns/default-dilemma.md`(本向度的完整 framework + IDD 內既有 case study)。

---

### D10: Closure-defining vs Closure-non-defining

**定義**:skill 是否定義 IDD 的 DONE state(可量化的 project completeness)。

**Values**:
- `Closure-defining` — **唯一只有 `idd-close`**。Two-tier gate(structural + semantic)後才視為 closed
- `Closure-non-defining` — 其他全部 skills。最多 advance phase,但不宣告 DONE

**為什麼重要**:Closure axis 是 IDD 跟 TDD/SDD 的核心差別。`idd-close` 不可被 swallow / 不可 auto(no auto-close even after 6/6 verify PASS)。

**Cross-link**:MANIFESTO § Two-dimension model(Verification × Closure)。

---

### D11: Workflow Membership

**定義**:skill 出現在哪幾條 sanctioned workflow paths(`docs/workflows.md` 的 path catalog)。

**為什麼重要**:從「skill A 出現在 5 條 paths」看出該 skill 是 universal(e.g. `idd-issue` / `idd-close` 跨多 paths);從「skill X 只在 P-spectra path 出現」看出該 skill 是 niche(e.g. `spectra-discuss` 只在 spectra paths)。

**Values**:per skill 列出 path 集合(e.g. `idd-implement` ∈ {P-atomic, P-plan-gated, P-spectra(via apply), P-auto-from-diagnosed, P-cluster-pr, P-chain-from-root, P-implement-retry, P-loop-autopilot})。

**Cross-link**:[`docs/workflows.md`](workflows.md) — 完整 path catalog + Path × Skill Matrix 給 reverse lookup。

---

## Open Dimensions (待 user 補)

下列 dimensions 是 AI agent 從 corpus distill 不出,但 user 可能已有的:

- **D12**: **Surfacing vs Lifecycle**（#140 定義完成，v2.97.0）— surfacing-only primitive family：idd-list / idd-clarify / idd-find。canonical 定義（軸對照表、雙向鐵律、增員判準）見 [`plugins/issue-driven-dev/references/surfacing-primitives.md`](../plugins/issue-driven-dev/references/surfacing-primitives.md)
- **D12-alt**: ? (cost / token / time 維度?)
- **D13**: ? (cross-repo / cross-skill 整合?)
- **D14**: ? (retroactive vs forward-looking?)
- **D15**: ? (formal vs informal / spec-bound vs ad-hoc?)
- **D16**: ? (irreversibility classification — close / merge / archive 之間差別?)
- **D17**: ? (...)

> Maintainer:請 user 補充 D11+,並把對應 anchor 文件 cross-link 上來。

---

## Skill × Dimension Matrix

**Legend**:`Sep`=Separation, `Auto`=Automation, `Sup`=Supervised Automation, `Atom`=Atomic, `Orch`=Orchestrator, `Sub`=Sub-orchestrator, `Delib`=Deliberation, `Exec`=Execution, `Side`=Side effect, `R`=Read-only, `W`=Write, `Fwd`=Forward, `Bwd`=Backward, `S/B/C/Ch`=Single/Batch/Cluster/Chain, `SHALL`/`SHOULD`/`SOFT`=advisory level, `Att`=Attended, `Unatt`=Unattended-capable, `Hyb`=Hybrid, `F`=Flag, `Sk`=Separate skill, `Cl-def`=Closure-defining, `Cl-non`=Closure-non-defining。

| Skill | D1 | D2 | D3 | D4 | D5 | D6 | D7 | D8 | D9 | D10 |
|-------|----|----|----|----|----|----|----|----|----|-----|
| `idd-issue` | Sep | Atom | Side | W | Fwd | S, Bundle, Multi-finding | mostly SHALL + advisory sister sweep | Att | Sk + flags | Cl-non |
| `idd-diagnose` | Sep | Atom | Delib | W | Fwd | S / Batch | SHALL Layer V + SHOULD sister surface | Att (Hyb degraded) | Sk | Cl-non |
| `idd-plan` | Sep | Sub | Delib | W | Fwd | S | SHALL (EnterPlanMode gate) | Att-only | Sk | Cl-non |
| `idd-implement` | Sep | Atom | Exec | W | Fwd | S | SHALL TDD | Unatt-capable | Sk | Cl-non |
| `idd-verify` | Sep | Atom | Exec | W | Bwd | S | SHALL (6-AI ensemble) | Unatt-capable | Sk + flags | Cl-non |
| `idd-close` | Sep | Atom | Exec | W | Bwd | S / Batch | SHALL two-tier gate | Att-only | Sk | **Cl-def** (唯一) |
| `idd-update` | Sep | Atom | Side | W | Fwd | S / Batch | SHALL phase sync | Unatt-capable | Sk | Cl-non |
| `idd-comment` | Sep | Atom | Side | W | Fwd | S / Batch | SHOULD template | Unatt-capable | Sk + flags | Cl-non |
| `idd-edit` | Sep | Atom | Side | W | (任) | S / Batch | SHALL preview before write | Att-only | Sk | Cl-non |
| `idd-list` | (n/a) | Atom | n/a | R | (查) | S | n/a | Unatt-capable | Sk + flags | Cl-non |
| `idd-clarify` | Sep | Atom | Delib(surface-only) | W (annotation block) | Fwd | S | SHALL hard-gate consumer (diagnose Step 0.5) | Unatt (deferred-row 機制 #137) | Sk + flags | Cl-non |
| `idd-report` | Sep | Atom | Side | W | Bwd | S | SHALL aggregate | Att | Sk | Cl-non |
| `idd-route` | (n/a) | Atom | n/a | R (recommend) / W (record) | (查) | S | n/a | Unatt-capable | Sk | Cl-non |
| `idd-all` | **Auto (Hyb degraded)** ⚠ | Orch | (跨 D / E / Side) | W | (跨) | S / Batch (v2.83 conflict-class ordered) / Cluster | mostly SHALL but soft Phase 0.4 | Hyb | Sk + flags | Cl-non |
| `idd-all-chain` | **Auto × N (Hyb degraded)** ⚠ | Orch | (跨) | W | (跨) | Ch (1 root + N spawn) | mostly SHALL but soft Phase 0.4 | Hyb | Sk + flags | Cl-non |

⚠ = D1 design tension（#122 原 framing）— 已由 path-catalog 裁決取代：不強制 Sup，改為本 catalog 把各 path 的 risk 顯式列出、discipline 在 user 選 path 時 explicit（見 workflows.md Anti-patterns + #120 的 Layer V deferred-record 機制）。

---

## Cross-Dimension Reinforcement

Dimensions **不正交** — 某些值組合互相 reinforce,某些互相 conflict:

| 組合 | 關係 | 案例 |
|---|---|---|
| D1=Sep + D3=Delib + D7=SHALL | **Reinforce** | `idd-diagnose`、`idd-plan`(deliberation moment 必該 separation 且 mandatory) |
| D1=Auto + D8=Unatt | **Reinforce** | `idd-implement`(unattended TDD 是合理 automation) |
| D1=Sep + D8=Unatt | **Conflict** | 純 separation skill 通常需要 attended;若 unattended,degraded mode 必須明示 |
| D3=Delib + D8=Unatt | **Conflict** | 違反 NSQL P1。`idd-all-chain` Phase 0.4 unattended auto-proceed 是此 conflict 的 hotspot |
| D6=Ch + D7=SHALL Layer V | **Reinforce risk-mitigation** | Chain 風險高 → Layer V 應該強制 block,不該 advisory |
| D9=Flag + D2=Atom | **Reinforce** | 加 flag 不該升 atomic 成 orchestrator(D9 trilemma 通常 push 你開 separate skill) |
| D10=Cl-def + D8=Unatt | **Hard conflict** | `idd-close` 永不該 unattended(MANIFESTO 鐵律)|

---

## Cross-links to Authoritative Sources

本文件是 **navigation index**,具體 axis 規則的權威定義位置:

| Dimension / 概念 | 權威 source |
|---|---|
| D1 Separation vs Automation(完整 design discussion + 3 變更建議) | #122 |
| D3 Deliberation 哲學 + Human-in-the-loop | `plugins/issue-driven-dev/MANIFESTO.md` § Human-in-the-loop section |
| D5 Closure axis + falsifiability | MANIFESTO § Two-dimension model |
| D6 Batch vs Cluster vs Chain canonical contract | `plugins/issue-driven-dev/references/batch-and-cluster.md` |
| D7 IC_R011 advisory checkpoint pattern | `plugins/issue-driven-dev/references/ic-r011-checkpoint.md` |
| D9 Flag vs Separate Skill framework | `docs/design-patterns/default-dilemma.md` |
| D10 Closure-defining 鐵律 | MANIFESTO § auto-merge / auto-close 區隔 |
| D11 Workflow Membership(path catalog) | [`docs/workflows.md`](workflows.md) |
| Overall philosophy + 5-checkpoint design | MANIFESTO 全文 |

---

## Provenance

- **首次版本**:2026-05-21 — AI agent skeleton,由 `/idd-issue` invocation 過程 distill(session at `ai_martech_global_scripts` repo,user observed `idd-all-chain` 預設 swallow `idd-diagnose` 的 design tension)
- **觸發 insight**:user 一句「在idd裡面分成 idd-issue → idd-diagnose → idd-all/idd-all-chain 等三步奏,也就是 idd-all 不能跳過 diagonose」
- **D11 補入**:2026-05-21(同日)— user 提出 reframing:「不是強制,而是要把所有可能的 path 都列出來」→ 新增 `docs/workflows.md` path catalog,D11 連結到該文件
- **Companion issue**:#122 strict separation proposal(原 framing,reframing 後 supersede 為 path catalog approach,issue body 不變但 design intent 已調整;原 marketplace#89 已 transfer 過來)

### Maintenance discipline

- **Single source of truth**:具體 axis 規則住在各 `references/*.md` / SKILL.md / MANIFESTO.md。本文件**只**是 navigation index + matrix view。
- **加新 dimension 時**:先在對應 authoritative source 文件化,再到本文件加 navigation entry。**避免**本文件 grow 成 second source of truth(會 drift)。
- **新 skill 加入時**:必填 matrix 該 skill 行(15 個 dimension 值不能空白 — `n/a` 是合法,空白不行)。
