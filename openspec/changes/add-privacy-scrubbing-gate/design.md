## Context

每個 IDD skill 最終都會把 AI 起草的 body 送上 GitHub（`gh issue create` / `comment` / `edit`）。這是 IDD 的 **egress boundary**——過了這條線內容就公開、通知就送出、無法回收。目前這條線上**沒有 privacy gate**：唯一相關機制 `sanitize_source_label`（#75，`skills/idd-issue/SKILL.md:1815-1865`）只清 source label 的 control-char + `@`-mention，不看整個 body 的語意層 private identifier，且只存在於 idd-issue 一個 site。

在 third-party clone（#192）與公開 repo 上，起草 body 夾帶本機 home path、`~/.claude.json` project basename、collaborator 真名、未發表 context 的機率很高，一旦 dispatch 不可逆。本 change 在 egress boundary 補上一個 **repo-aware privacy-scrubbing gate**。

核心張力是：偵測要**語意廣度**（private identifier 的形態無窮、跨語言、人名靠 context），這是 LLM 的強項、固定 regex 的死穴；但「gate 有沒有真的跑」不能靠 AI 自覺，必須有 deterministic 保證。本設計把這兩件事拆開：**偵測交給 LLM，執行交給一個 minimal deterministic checkpoint。**

## Goals / Non-Goals

### Goals

- egress boundary 上有一個 gate，dispatch 前對 body 做 privacy 自審。
- 偵測是 LLM 語意判斷，**零維護 pattern set**。
- 「gate 跑過」被 deterministically 保證（choke-point wrapper enforce）。
- 依 repo visibility 分三級嚴格度（third-party / own-public / private）。
- ENFORCE 時 block-with-diff、要 confirm，不 silent redact。
- 契約抽成 shared home（rule + wrapper），不 trapped 在 idd-issue。

### Non-Goals

- 維護固定 denylist / regex / NLP name-detector。
- silent auto-redact。
- 改 `sanitize_source_label` 既有行為。
- 一次 retrofit 全部 12 site（idd-issue 先，其餘 follow-up）。

## Decisions

### D1: Detection = LLM 語意自審，NOT 固定 regex / denylist（CRITICAL — owner 明確否決固定偵測）

Gate 在 egress time **指示 AI** 對起草的 body 做語意檢查，找出 private identifiers。**不維護任何 pattern set。** 人名偵測由 LLM 語意判斷（AI 從 context 理解誰是私人的、哪個是未發表資訊），**不用** NLP name-detector 也**不用**固定名單。

**為什麼不是固定偵測**：

- private identifier 的形態無窮且跨語言（home path、機構內部代號、未發表研究名、真名 vs 公開 handle……）。固定 regex/denylist 必然漏（false negative）又必然誤傷（把公開的 `Tarski` 當私人）。
- 這與本 repo `.claude/rules/attribute-assessment.md` 的立場一致：**「Deterministic match on a wrong feature is worse than honest AI judgment because it hides its mistake behind a rule.」** 私隱偵測正是 attribute-assessment 型任務（判斷「這段內容是否私人」），該用 AI judgment + 揭露理由，不是 keyword matching。
- owner 在 discuss 明確否決固定偵測。本 change 不得引入 maintained pattern set 當**主要**偵測。

### D2: Enforcement = minimal deterministic checkpoint（偵測 vs 執行的分離）

> 關鍵區分：**偵測是 LLM（語意、非固定）；但「gate 有沒有跑」必須 deterministic。** 「規則說 AI 該自審」若沒有 deterministic 保證，就只是祈禱 AI 記得——在 12 個 site、長 context、unattended `/loop` 下必然有時漏。

引入單一 choke-point wrapper **`scripts/gh-egress.sh`**。所有 egress site 改呼叫它，**不再直接** `gh issue create/comment/edit`。wrapper 做且只做兩件事：

1. **Enforce 自審跑過** — dispatch 前要求呼叫端提供「privacy 自審已執行」的 deterministic attestation（明確 flag / structured handshake token，而非 body 內容比對）。缺 attestation → **refuse dispatch**。這保證 gate 的**存在**是 deterministic 的，即使 gate 的**內容**是 LLM 的。
2. **極小 last-resort safety net** — 只攔 2-3 個 zero-tolerance **機械**項目：literal 絕對 home path（`/Users/<name>` 字面）與 verbatim `~/.claude.json` 內容。這是 belt-and-suspenders，不是偵測主體。

**wrapper 明確不做**語意 pattern matching——那正是 D1 否決的固定偵測。語意廣度 100% 是 LLM 的職責；wrapper 只保證「LLM 有被叫來做這件事」+ 攔死絕不可外洩的兩三個字面樣態。

> attestation 的**確切格式**（flag 名 / env / handshake token 結構）標記為 apply-time / Open Question Q1，不在 proposal 凍死。

### D3: Classification = 重用 viewerPermission + 新增 `isPrivate` query

重用既有 third-party 偵測（`references/config-protocol.md:238-268`，viewerPermission-based own vs third-party），**並新增一支 `isPrivate` query**——目前 `gh repo view` 只取 `isFork` + `viewerPermission`，加 `isPrivate` 後才能分「own-public vs own-private」。三級嚴格度：

| visibility | 判準 | gate 行為 |
|---|---|---|
| **third-party** | viewerPermission ∉ {WRITE,MAINTAIN,ADMIN}（沿用 #192 detection，含 fail-safe）| **ENFORCE** — block + 顯示 redaction diff + 要求 confirm |
| **own-public** | 你有 write 權 AND `isPrivate=false` | **WARN** — flag 疑慮，預設 proceed |
| **private** | `isPrivate=true` | **LIGHT** — 仍 honor CLAUDE.md「raw 第三方逐字內容不進 remote」規則，但不 block 一般 identifier |

**resolves residue**：`add-third-party-clone-setup/design.md:145` 標記 push-permission 是機械 proxy，把 own+public 與 own+private 混為一談。加 `isPrivate` query 後，這個 visibility proxy 的殘留被解掉——gate 能對 public 與 private 給不同嚴格度。（人名 / 「什麼算 private」的語意殘留**不因此消失**，見 Open Questions。）

### D4: Redact vs Block = ENFORCE 時 block-with-diff，NOT silent auto-redact

ENFORCE 級別偵測到 private identifier 時：偵測 → **顯示 redaction diff**（原文 vs 建議 redacted）→ **拒絕 dispatch 直到 user confirm**。不偷偷改 body。

**為什麼 refuse 不 strip**：mirror 既有 `sanitize_source_label`（#75）的「refuse not strip」哲學——silent 修改 body 會破壞 audit trail、藏起 AI 的判斷、讓 user 失去否決權。block-with-diff 把判斷攤在 user 面前，由 user 拍板（與 tagging-collaborators.md「never guess，AskUserQuestion fallback」同構）。

WARN 級別則相反：flag + 一行摘要，**預設 proceed**（不 block），因為 own-public repo 上多數 identifier 是可接受的，過度 block 會惱人。

### D5: Shared home = rule + wrapper，抽出 skill-local

privacy 契約目前 trapped 在 `skills/idd-issue/SKILL.md:1815-1865`（sanitize_source_label #75 machinery），其他 site 無覆蓋。抽成：

- **`rules/privacy-scrubbing.md`** — policy / behavioral rule，sibling to `rules/tagging-collaborators.md`。描述三級嚴格度、LLM 自審指示、block-with-diff 契約、與 sanitize_source_label 的分工。所有 egress skill 在 Step 0 task list 引用。
- **`scripts/gh-egress.sh`** — choke-point wrapper（D2 的 enforcement）。與既有 `scripts/git-ignore-block.sh` 同層（`plugins/issue-driven-dev/scripts/`）。
- **references/-level 契約**（若 convention warrant）— 若 gate 的呼叫契約需要跨 skill 文件化，補一份 reference（如 `references/egress-gate.md`）；否則 rule + wrapper 內註即足。

**既有 `sanitize_source_label` 原封不動** — 它繼續做 control-char strip + `@`-mention refuse（source label 層）。privacy scrubbing 是疊在**上面**的新語意層（whole-body、repo-aware）。兩者職責不重疊：sanitize = 字元/mention 衛生；privacy = 語意 private identifier。

### D6: Egress retrofit = 邏輯一處，site 只換呼叫；idd-issue 先落地

~12 個 site 跑 `gh issue create/comment/edit`：`idd-issue`, `idd-comment`, `idd-edit`, `idd-diagnose`, `idd-implement`, `idd-plan`, `idd-update`, `idd-clarify`, `idd-close`, `idd-verify`, `idd-all-chain`，加上 multi-finding Stage 4 dispatch。retrofit = 各 site 從 `gh issue comment ...` 改成 `bash scripts/gh-egress.sh comment ...`。**邏輯只放 wrapper 一處**，site 端是純呼叫替換。

**Phasing（APPROVED）**：spec 覆蓋全部 site，但實作 **idd-issue 先**（主要 authoring path、body 最長、最可能夾帶 private identifier、風險最高）。其餘 site 為 follow-up（見 tasks.md §5，逐一標 `- [ ]` 但歸在 Phase 2）。這讓高風險路徑最快受保護，同時避免 12-site big-bang 的 regression 面積。

## Implementation Contract

### Observable Behavior

1. 在 third-party clone 首跑 `/idd-issue`，起草 body 含 `/Users/alice/proj` → gate ENFORCE：顯示 redaction diff + 要求 confirm，未 confirm 不 dispatch。
2. 在 own-public repo 起草 body 含疑似私人 context → gate WARN：印一行 flag，預設 proceed（不 block）。
3. 在 own-private repo 起草一般 identifier → gate LIGHT：不 block；但 body 含 raw 第三方逐字內容 → 仍依 CLAUDE.md 規則提醒。
4. 任一 egress site 略過自審直接嘗試 dispatch → wrapper 因缺 attestation **refuse**（deterministic）。
5. body 含 literal `/Users/<name>` 或 verbatim `~/.claude.json` 內容 → 即使 LLM 漏判，wrapper 機械 net 仍攔下。
6. `sanitize_source_label` 對 source label 的行為與今日**完全一致**（無退化）。

### Acceptance Criteria

- [ ] 偵測是 LLM 語意自審；codebase 無新增 maintained private-identifier pattern set / denylist / name-detector。
- [ ] `scripts/gh-egress.sh` 為單一 choke point；缺 self-check attestation → refuse dispatch。
- [ ] wrapper 機械 net 只攔 literal home path + verbatim `~/.claude.json`；不做語意 pattern matching。
- [ ] classification 三級：third-party=ENFORCE / own-public=WARN / private=LIGHT；`isPrivate` query 已加入 `gh repo view`。
- [ ] ENFORCE = block-with-diff + confirm；無 silent auto-redact code path。
- [ ] `rules/privacy-scrubbing.md` 存在，sibling to tagging-collaborators.md。
- [ ] idd-issue 走 wrapper（Phase 1）；其餘 site retrofit 在 spec 內、實作 follow-up。
- [ ] `sanitize_source_label` 行為位元不變。

### Out of Scope

- 「什麼算 private」的固定化（永遠 LLM judgment）。
- 一次 retrofit 全部 12 site（idd-issue 先）。
- 非 GitHub egress（Telegram / email / 其他 MCP）——本 gate 只管 `gh issue` egress。

## Risks / Trade-offs

| Risk | Mitigation |
|---|---|
| LLM 漏判某個 private identifier（false negative）| 三層縱深：LLM 語意（主）+ wrapper 機械 net（literal home path / `.claude.json`）+ ENFORCE 的 block-with-diff 讓 user 有最後否決點 |
| wrapper 的機械 net 被誤當成「固定偵測」而擴張 | 明訂上限 2-3 zero-tolerance 機械項；spec scenario 鎖死「不做語意 pattern matching」；擴張需另開 change |
| `isPrivate` query 多一支 / 改 `gh repo view` 欄位 | 折進既有 `gh repo view --json` 呼叫（已取 isFork/viewerPermission，加一欄零額外 round-trip，同 #192 手法）|
| 12-site retrofit regression 面積 | Phasing：idd-issue 先；邏輯只在 wrapper 一處，site 端純呼叫替換，降低 per-site 風險 |
| deterministic attestation 被呼叫端造假（硬塞 flag 不真自審）| attestation 保證的是「步驟存在」而非「判斷正確」；判斷正確靠 LLM + block-with-diff。造假 flag 是 process 違規，非本機制目標（同 checklist 契約：打勾沒做屬 semantic gate 範疇）|
| WARN 級被 alert-fatigue 忽略 | WARN 只印一行、預設 proceed；ENFORCE（真正高風險）才 block。分級即為降噪 |

## Migration Plan

### Deploy

Additive + phased。Phase 1：新增 `rules/privacy-scrubbing.md` + `scripts/gh-egress.sh` + `isPrivate` query，retrofit **idd-issue** 走 wrapper。Phase 2（follow-up）：其餘 11 site 逐一 retrofit。無 schema migration。Bump `idd-issue`（Phase 1）+ 各 site skill（Phase 2）plugin minor version。

### Rollback

移除 wrapper 呼叫 → site 回到直接 `gh issue ...`；`rules/privacy-scrubbing.md` 可獨立 revert。`sanitize_source_label` 從未被動，rollback 不影響它。已加的 `isPrivate` query 無害（多一欄 metadata）。

### Backward Compat

- `sanitize_source_label`（#75）行為不變——privacy scrubbing 是新增層。
- 未 retrofit 的 site（Phase 2 前）行為與今日一致——直到各自 retrofit。
- 既有 config / detection（#192 viewerPermission）不變，只**加** `isPrivate`；own vs third-party 判準沿用。
- own-private repo 的 LIGHT 級近乎今日行為（不 block 一般 identifier），對 solo/private 工作流零額外摩擦。

## Open Questions

### Q1: deterministic attestation 的確切格式？

wrapper 如何 deterministically 確認「自審跑過」？候選：(a) 必填 flag（`--scrub-attested`）由自審步驟末尾產生；(b) structured handshake token（self-review 輸出一段 wrapper 驗證的 marker）；(c) two-call protocol（先 `gh-egress.sh review` 再 `dispatch`，wrapper 記 state）。傾向 (a)/(b) 的輕量形式。**確切格式 apply-time 定**，不在 proposal 凍死。原則：保證「步驟存在」的 determinism，不假裝保證「判斷正確」。

### Q2: 人名 / 「什麼算 private」的語意殘留（residue，不靜默吞掉）

D3 的 `isPrivate` query 解掉了 **visibility proxy** 殘留（own-public vs own-private 現在可分）。但**「這個人名/這段內容是否私人」永遠是 LLM 語意判斷**，不是機械可判定——這是 D1 的直接後果，也是刻意的（固定名單必漏必誤傷）。明確標記為 **acknowledged residue**：gate 的偵測品質等同當下 LLM 的語意判斷品質，會隨模型演進，不承諾「零漏判」。這與 `.claude/rules/attribute-assessment.md` 一致——AI judgment + 揭露理由 > 藏在規則後的機械誤判。

### Q3: 非 `gh issue` egress 是否納入同一 gate？

本 change 只管 `gh issue create/comment/edit`。其他外洩面（`gh pr` body、Discussions、跨 MCP）是否共用 `gh-egress.sh` 或另立 gate？列 follow-up；先把最高頻的 issue egress 做穩。
