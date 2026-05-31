# issue-driven-dev — CLAUDE.md

## Purpose

Issue-driven development：每個改動都從 issue 出發，每個 issue 都有驗證過的結案。

Issue 是人和 AI 的介面 — 人負責「什麼是對的」，AI 負責「怎麼做到」。

## 鐵律:Step 0 Bootstrap Stage Task List(v2.18.0+)

**每個 stage skill 的第一個動作必須是 `TaskCreate`**,把該 stage 的所有 execution sub-steps 建成 harness-level todo list。完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。

為什麼:
- Stage 內部的步驟(讀 issue / comment 到 GitHub / 建 milestone / 上傳圖片)容易漏做
- 歷史上看過:診斷完沒 comment / 建完 issue 沒建 milestone / verify findings 沒 post 到 issue
- TaskList 讓進度在 UI 可視化、中斷後可恢復、完成即打勾
- 與 `idd-implement` Step 2.5 的 Strategy-level TaskList 互補(Stage-level 追 skill sub-steps,Strategy-level 追改動 bullets)

## Skills

**流程 skills（主 workflow）**：
| Skill | 防止的失敗 | 用途 |
|-------|-----------|------|
| `idd-issue` | 改了東西卻沒有記錄「為什麼改」;順序 bundle 變散落孤兒 issue | 建立 well-documented GitHub Issue;v2.52.0+ 支援 ordered/unordered bundle flags(`--parent` / `--blocked-by` / `--bundle-mode`,見 `## Ordered Bundle Pattern` 段落)|
| `idd-diagnose` | 修了表象，沒修根本原因 | 找 root cause / 分析需求；判定 Complexity（Simple / Plan / Spectra，v2.36.0+）|
| `idd-plan` | Diagnosis 漏 case → 動手才發現要重做（v2.36.0+）| Plan tier 的 approval gate：用 EnterPlanMode 把 Implementation Plan 呈現給 user 審查、approve 後才 chain to idd-implement。介於 Simple 和 Spectra 之間 |
| `idd-implement` | Scope creep | 按 diagnosis 紀律實作；走 PR path 或 direct-commit path |
| `idd-verify` | 自以為修好了 | 用 Codex CLI 獨立驗證 |
| `idd-close` | 三個月後沒人知道做了什麼 | 寫 closing comment + 關 issue；偵測 unmerged PR 阻擋 close |

**輔助 skills（流程外與 comment 管理）**：
| Skill | 防止的失敗 | 用途 |
|-------|-----------|------|
| `idd-update` | Issue body 過時，要讀完所有 comments 才知道現狀 | 同步 body Current Status 區塊 |
| `idd-list` | 不知道有什麼要做、漏掉卡 verify 的 issue | 列出 open issues 含 IDD phase + 建議 next action |
| `idd-report` | 進度不透明，stakeholder 看不到現況 | 產出進度報告到 GitHub Discussions |
| `idd-comment` | 非流程性決定 / 外部 context 散落在 chat | Template-guided comment（decision/note/question/correction/link/errata）|
| `idd-edit` | 手動 `gh api PATCH` 容易字串 escape 誤覆蓋 | 編輯既有 comment（append/replace/prepend-note 三種 mode）|
| `idd-config` | 跑 `idd-issue` 才發現 config 缺、predicate 寫錯只在實際 issue 創建時才報、不知 cwd 落在哪個 candidate / group | 管理 `.claude/issue-driven-dev.local.json` 生命週期：`show` / `init` / `validate` / `which`（v2.31.0）|

**Orchestrator skill**：
| Skill | 防止的失敗 | 用途 |
|-------|-----------|------|
| `idd-all` | 手動跑 5 個 idd-* 太繁瑣、容易漏步驟、orchestration 一致性 | 一鍵跑完 issue→diagnose→implement→verify。v2.46.0+ **從 `pr_policy` + `--pr/--no-pr` 解析 `(path, interaction)` tuple**：`(PR, unattended)` = feature branch + push + PR + sub-skill UNATTENDED MODE（v2.40.0 default + `/loop` friendly）；`(direct-commit, attended)` = 留當前 branch + 不開 PR + sub-skill native attended（HITL）。停在 verified 等人 close — 兩 mode 都不 auto-close。Spectra path 走 discuss→propose→apply chain — v2.46.0 |
| `idd-all-chain` | Root issue 衍生鏈被切成 N 個獨立 PR,reviewer 失去 holistic view;手動逐一跑 `/idd-all #M` 太繁瑣 | **chain-solve mode**(v2.55.0+ single-root,v2.60.0+ multi-root):驅動 root issue + auto-emergent spawn(sub-skill sister sweep / verify follow-up / mid-plan tangential / sister concern)through ONE cluster branch + ONE review PR。Thin shell over `/idd-all`,內部 recursive 用 `--in-chain` flag 推導 4th mode tuple `(direct-commit, unattended)`。v2.60.0+ 支援 multi-root invocation(`#A #B #C`)+ DFS/BFS traversal mode(`--bfs` opt-in,default DFS)。Hard caps:per-root depth=3、global max-issues=10(v2.60.0+, was 2/5)。Eligibility = same-file OR same-skill OR sister-bug。Verify FAIL = per-root halt(continue 其他 root subtree)+ preserve commits。停在 verified、永不 auto-close。Spawn manifest v2 at `.claude/.idd/state/chain-spawned-issues.json`(含 root_issues/traversal/per-spawn root_id),4 sub-skill 共同 conformant write |

## Use-Case Routing（v2.37.0+）

不確定該跑哪個 skill / 帶什麼 flag？查 [`references/usecase-routing.md`](references/usecase-routing.md) — 24 個常見情境的對照表（含 single / batch / cluster-PR / external-agent / Plan / Spectra），每個情境直接告訴你 skill chain + flag + contract 文件 link。

特別注意 #4-#8（external-agent verify）：Codex / Copilot / 遠端 agent 開的 PR 走 `idd-verify --pr <N>`，PR 是 master comment、ref'd issue 拿 pointer，issue↔PR 對應強制檢查。完整契約見 [`references/external-agent-delegation.md`](references/external-agent-delegation.md)。

## Multi-issue Invocation（v2.34.0+）

7 個 skill 接受多個 `#NNN` 觸發兩種模式之一（依 skill 性質）：

| Mode | Skills | 語意 |
|------|--------|------|
| **Batch** | `idd-diagnose`, `idd-update`, `idd-comment`, `idd-edit` | 對每個 issue 依序跑單一邏輯。Pure idempotent，無共享 state。各自 post comment、各自 auto-update phase、各自留 audit trail |
| **Cluster-PR** | `idd-implement`, `idd-verify`, `idd-close` | 多 issue 共用 1 feature branch + 1 PR；commit message 以 `Refs #N`（可多）標示對應 issue；verify report 按 issue 分區段；close 各寫獨立 summary（不偷懶合併）|

完整契約見 [`references/batch-and-cluster.md`](references/batch-and-cluster.md)。
單一 issue 行為（`/idd-implement #19`）完全不變 — backward compatible。

`idd-issue`、`idd-list`、`idd-report`、`idd-config`、`idd-all` 不參與這個機制（idd-issue 是 input phase 不該 batch；list/report 本來就 multi；config N/A；idd-all = single-issue orchestrator）。

## Attachments(v2.35.0+)

Issue body / comments 含 attachment(docx / pdf / 圖片)時,**忽略附件 = 忽略來源**。依 [`rules/process-attachments.md`](rules/process-attachments.md):

| 階段 | 責任 |
|------|------|
| 上游(`idd-issue`, `idd-diagnose`) | 偵測 URL → curl 下載到 `.claude/.idd/attachments/issue-NNN/` → 寫 `_manifest.json` → MCP-first parser(che-word-mcp / che-pdf-mcp / Read for images) |
| 下游(`idd-implement`, `idd-verify`, `idd-close`, `idd-report`) | 檢查 manifest 涵蓋當下 attachment list,缺漏警告但不 auto-fetch(回上游修) |
| 不適用 | `idd-list`、`idd-config`(不分析 issue 內容) |

引用 attachment 一律用 repo 相對 path,禁止只貼 URL(會 expire / private 看不到)。

## Namespace Migration(v2.35.0+)

idd config / state / attachments 統一搬到 `.claude/.idd/`:

```
.claude/.idd/
  ├── local.md           # was .claude/issue-driven-dev.local.md
  ├── local.json         # was .claude/issue-driven-dev.local.json
  ├── state/
  │   └── bridge.json    # was .claude/state/idd-bridge.json
  └── attachments/
      └── issue-NNN/     # 新功能
```

**Backward compat**:walk-up 同時找新舊路徑,新路徑優先;偵測到 legacy 印 migration hint。Migration 命令見 [`references/config-protocol.md`](references/config-protocol.md#migration)。

## Tagging Collaborators（v2.32.0+）

任何 IDD skill 在 GitHub 上 post `@xxx` mention 都**必須**走 [`rules/tagging-collaborators.md`](rules/tagging-collaborators.md) 5 步協定：

1. **Detect intent** — flag (`--mention <login>`) 或自然語言（"tag X" / "ping X" / "通知 X"）
2. **Fetch real list** — `gh api repos/$REPO/collaborators` (+ org members 若是 org repo)
3. **Resolve** — fuzzy match 對 login + name，唯一匹配直接用
4. **AskUserQuestion fallback** — 0 或 2+ 匹配時必選，options 是真實 collaborator list
5. **Verify** — post 前 grep `@\w+` token 全部對照已驗證 set，未驗證 token = abort

**禁止**：訓練記憶 / 聊天歷史 / git log 推測 @handle，或用 display name 當 mention。GitHub 通知不可逆。

flag 支援：`idd-issue`、`idd-comment`（其他 skill 走 prose detection）。

## Spectra ↔ IDD Bridge（v2.32.0+）

當 IDD skill 在 `spectra-discuss` session 中被叫起來（例如討論到一半要把結論 comment 到 issue），依 [`rules/spectra-bridge.md`](rules/spectra-bridge.md) 提供 round-trip context：

1. **Step 0.7 Detect** — `--resume-spectra="<topic>"` flag、`--source` 含 `spectra-discuss`、`spectra list` 有 in-flight、`.claude/.idd/state/bridge.json` 存在 — 任一觸發 `SPECTRA_BRIDGE_ACTIVE=1`
2. **Step N-1 寫 bookmark** — `.claude/.idd/state/bridge.json` 含 topic / issue / open_questions / next_step_hint
3. **Step N 印 Resume Prompt** — 可貼回 spectra-discuss 的 prompt block，使用者控 pacing

skill 不會自動 invoke `/spectra-discuss`。目前覆蓋：`idd-comment`（首發），`idd-issue`、`idd-edit` 後續視需求加。

## PR vs Direct-commit Path（v2.27.0+）

`idd-implement` 區分兩條路徑:

| Path | 行為 | 適用 |
|------|------|------|
| **PR path** | 開 feature branch `idd/<N>-<slug>` + push + `gh pr create` | 多人協作、fork、需 CI / review |
| **Direct-commit path** | 在當前 branch commit,不 push、不開 PR | Solo project、個人 marketplace、quick fix |

決策順序(高到低):

1. `--pr` / `--no-pr` flag(per-invocation)
2. Fork detection(`gh repo view --json isFork` true → 強制 PR)
3. `pr_policy` config 欄位(`always` / `never` / `ask`)
4. Config 缺省(沒 file 或沒 field)→ 默認 `(PR, unattended)`(v2.40.0 backward compat,保護 `/loop` 等舊 caller)

`idd-all` v2.46.0+ 兩 mode:`(PR, unattended)` 與 `(direct-commit, attended)` 從 `pr_policy` + flag 解析。`idd-close` 偵測 open PR 引用本 issue 時 refuse close。完整 contract:[references/pr-flow.md](references/pr-flow.md)。

## Workflow

```
issue → diagnose ─┬→ implement → verify → close                          (Simple)
  ①        ②      │      ③         ④       ⑤
                   │
                   └→ spectra-discuss → spectra-propose → spectra-apply → verify → close + archive  (SDD)
                            ②b               ②c              ③b           ④       ⑤
                            ↑
                            default; opt-out to direct propose only when direction is crystal clear

每個 skill 都吃 #NNN，issue 貫穿全部。
diagnose 判斷 Complexity → Simple 走 implement，SDD-warranted 預設走 spectra-discuss 對齊方向。

**Default = Simple**(v2.36.0+)。SDD 升級需通過三層檢查:Layer 1 disqualifiers(narrative / ad-hoc analysis 強制 Simple)→ Layer 2 必要條件(新可重用抽象)→ Layer 3 supplementary signals。前版 「any 1 of 5 OR」 trigger 易把 cross-file research analysis 誤判 SDD,新邏輯預設不升級,只在真正需要 spec contract 時才走。完整邏輯見 [`rules/sdd-integration.md`](rules/sdd-integration.md)。

`idd-all` 走 SDD path 時(v2.28.0+)會把 discuss → propose → apply 三步串成 unattended chain — 每步用 args 傳 hint 抑制 spectra 的 AskUserQuestion checkpoint。手動跑 SDD path 仍維持 attended（每個 spectra-* 自己會問 user）。
```

### Chain-Solve Mode (v2.55.0+)

當 root issue 解到一半,sub-skill spawn 出 follow-up issue(sister bug / verify follow-up / mid-plan tangential / sister concern)時,**`/idd-all-chain #N`** 自動把 root + auto-emergent spawn 整鏈拉進**單一 cluster branch + 單一 review PR**:

```
/idd-all-chain #28
  ├─ Phase 0: 建 idd/chain-28-<slug> branch + 初始化 spawn manifest
  ├─ Phase 2: queue=[#28] → /idd-all #28 --in-chain
  │   └─ idd-implement Step 5.7 spawn #34 (sister-bug, same skill) → manifest 記下
  │       → eligibility check pass → enqueue
  ├─ Phase 2: pop #34 → /idd-all #34 --in-chain → ...
  ├─ Phase 3: 開 cluster PR (title prefix `chain:`, collapsed details per issue)
  └─ Phase 4: STOP — user 接手 review → merge → /idd-close #28 #34 ...
```

跟既有 mechanism 的關係:

| Mechanism | When | Issue scope | PR scope |
|-----------|------|-------------|----------|
| `/idd-all #N` | Single issue lifecycle | 1 pre-known | 1 PR |
| `/idd-all #N #M --pr` (cluster-PR) | Multi-issue user-pre-known | N pre-known | 1 PR |
| **`/idd-all-chain #N`** | **Root + auto-emergent ripple** | **1 root + N hot-emergent** | **1 PR** |

Hard caps(寫死,v2.60.0+ 多 root 配套放寬):per-root `chain_max_depth=3`、global `chain_max_issues=10`(舊版 single-root 為 2/5)。Eligibility = `same_file_as_root OR same_skill_as_root OR spawn_kind="sister-bug"`(不 eligible 仍 file 為 follow-up issue,但不 chain solve)。Verify FAIL = per-root halt(同 root_id 從 QUEUE 移除,其他 root subtree 繼續)+ preserve commits + Phase 4 per-root PASS/FAIL report。永不 auto-close、永不 auto-merge。

完整契約見 [`references/chain-flow.md`](references/chain-flow.md)(chain shell algorithm)+ [`references/spawn-manifest.md`](references/spawn-manifest.md)(spawn manifest cross-skill schema)。設計理由見 `docs/design-patterns/default-dilemma.md`(為何不是 `/idd-all --chain` flag)。

### SDD 和 TDD 都是 IDD 的特例

業界通常把 TDD、SDD、issue tracking 當作三個獨立的方法論，團隊自行決定要用哪些、怎麼組合。IDD 的核心主張是：**它們不是平行的選擇，而是存在包含關係。**

#### 為什麼 TDD 和 SDD 天然需要 issue

- **TDD 脫離 issue 是不完整的**：TDD 回答「code 是否正確」，但不回答「為什麼要寫這個 code」。沒有 issue，測試只能驗證行為符合規格，卻無法追溯規格本身是否合理。Issue 是 TDD 的錨點 — 它定義了「正確」的標準。
- **SDD 脫離 issue 是不完整的**：SDD 回答「系統如何演進」，但不回答「為什麼要演進」。沒有 issue，spec 只是一份設計文件，缺少「什麼問題觸發了這個設計」的脈絡。Issue 是 SDD 的 motivation。
- **Issue 不需要 TDD 或 SDD 也能獨立存在**：一個 issue 可以只是一筆記錄（docs type）、一個不需要測試的配置改動、或一個需要人工處理的流程問題。Issue 的完整性不依賴於 TDD 或 SDD。

因此包含關係成立：TDD ⊂ IDD，SDD ⊂ IDD，但 IDD ⊄ TDD 且 IDD ⊄ SDD。

#### 在 IDD 中的具體位置

```
IDD (Issue-Driven Development)
 ├── TDD — 內嵌的實作紀律（RED → GREEN → commit）
 │         不管走哪條路，implement 都強制 TDD
 │
 └── SDD — 條件觸發的設計流程
           diagnose 判斷 complexity → SDD-warranted 才走 Spectra
```

| 機制 | 性質 | 觸發條件 | 在 IDD 的位置 |
|------|------|---------|--------------|
| **TDD** | 內嵌強制 | 每次 implement 都執行 | `idd-implement` Step 3 |
| **3-tier routing** (v2.36.0+) | 條件分支 | Layer 1 disqualifiers / Layer 2+3 (Spectra) / Layer P (Plan) | `idd-diagnose` Step 3.5 判定 |

> 不是所有 issue 都需要 Plan / Spectra，但所有 Plan / Spectra 都值得有一個 issue。
> TDD 不是可選的 — 它是 `idd-implement` 的強制步驟。

**Complexity routing**（v2.36.0+ 三路）：

- **Simple**（bug fix、單檔改動、follow existing pattern）→ `/idd-implement #N` 直接 TDD loop
- **Plan**（2+ 互依檔案、5+ ordered steps、decision-heavy、risk-sensitive boundary，**但無 published API contract**）→ `/idd-plan #N` 先 EnterPlanMode 給 user approve Implementation Plan，再 chain to idd-implement
- **Spectra**（對外 API/protocol/skill/tool 給 future callers + spec contract 需要 frozen，含 backward-compat alias `SDD-warranted`）→ `/spectra-discuss → spectra-propose → spectra-apply`
- **進度追蹤**：Simple/Plan 用 IDD checklist + TaskList；Spectra 用 `tasks.md`，issue 只掛一句 `→ see spectra change: <name>`
- **驗證**：統一用 `idd-verify #NNN`（6-AI 交叉驗證）
- **結案**：`idd-close #NNN`（Spectra 同時觸發 `spectra-archive`）

完整 routing 邏輯見 [`rules/sdd-integration.md`](rules/sdd-integration.md)。

## Configuration

首次使用 `idd-issue` 時會建立 `.claude/issue-driven-dev.local.json`(注意:從 v2.25.0 起是 JSON,不是 YAML/markdown)。

最小設定:

```json
{
  "github_repo": "owner/repo",
  "github_owner": "owner",
  "attachments_release": "attachments"
}
```

完整 schema 和解析規則見 [references/config-protocol.md](references/config-protocol.md)。摘要:

### Six 機制(優先順序由高到低)

1. **per-invocation flag** — `idd-issue --target owner/repo` 或 `--target group:<label>`;sibling skills 用 `--repo owner/repo`
2. **Candidates menu** — config 有 `candidates` + `ask_each_time: true` → AskUserQuestion 選單
3. **Predicates** — `candidates[].when` / `groups[].when` 自動匹配(`path_contains` / `title_matches` / `label_in` 等)
4. **Cascading config** — 從 cwd 往上找 `.claude/issue-driven-dev.local.json`,first match wins(同 eslint/tsconfig 模式)
5. **git remote fallback** — 沒任何 config 時用 `git remote get-url origin`
6. **Groups**(orthogonal) — 一個邏輯 issue 跨多 repo,primary + tracking + cross-link comment

### 範例:Monorepo 路由

```json
{
  "github_repo": "owner/big-monorepo",
  "candidates": [
    {
      "label": "Music sub-package",
      "github_repo": "owner/music",
      "when": { "path_contains": "/packages/music" }
    },
    {
      "label": "Plugin marketplace (auto by title)",
      "github_repo": "PsychQuant/psychquant-claude-plugins",
      "when": { "title_matches": "(?i)\\b(plugin|skill|hook)\\b" }
    }
  ]
}
```

`cd ~/big-monorepo/packages/music && /idd-issue` → 自動路由 `owner/music`(path 預判)。
若使用者輸入 title 含「plugin」,Step 2.5 會問是否切到 plugin marketplace repo。

### 範例:跨 repo coordinated issue

```json
{
  "github_repo": "PsychQuant/foo",
  "groups": [
    {
      "label": "Cross-stack: foo+bar+glue",
      "repos": [
        {"github_repo": "PsychQuant/foo",  "role": "primary"},
        {"github_repo": "PsychQuant/bar",  "role": "tracking"},
        {"github_repo": "PsychQuant/glue", "role": "tracking"}
      ],
      "when": { "label_in": ["cross-package"] }
    }
  ]
}
```

當 issue 加 `cross-package` label,Step 2.5 會切到 group 模式:在 `foo` 建 primary issue,`bar` / `glue` 建 tracking issues(body 首行 `> Tracking primary: foo#N`),最後在 primary issue 留 comment 列出所有 tracking refs。

### Backward compatibility

舊有的單一 `github_repo` config 完全不受影響 — 沒有 `candidates` / `groups` / `when` 就走原本的單一 repo 行為。所有新欄位都是 additive。

## Checklist Conventions

IDD 把 checkbox 當成**契約**，不是願望清單。`idd-implement` 會 bootstrap TaskList 追蹤進度，`idd-close` 會 refuse 關任何還有未勾項的 issue。

### 標記語意

| 標記 | 意義 | 阻擋 close? | 需附 reason? |
|------|------|-------------|-------------|
| `- [ ]` | Open todo，還沒做 | 🔴 是 | — |
| `- [x]` / `- [X]` | 完成，測試通過 | ✅ 否 | — |
| `- [~]` | Skipped（刻意跳過，可能回來做）| ✅ 否 | **必須**附原因 |
| `- [-]` | Won't fix / out of scope（決定不做）| ✅ 否 | **必須**附原因 |
| `- [?]` | Unknown / need input | 🟡 是（同 open）| — |

**Reason 格式**：寫在同一行 dash 後，或下一個縮排 bullet：

```markdown
- [~] Add Redis cache layer — deferred: waiting on infra team's Redis rollout (ETA 2026-05)
- [-] Support Windows paths
  - Won't fix: MCP server is macOS-only; Windows would need a separate binary
```

### 哪些區段會被掃描

`idd-close` 的 Gate Check 只掃**結構化的 checklist 區段**，避免誤判 `## Repro` 或 `## Steps to reproduce` 裡的情境 checkbox：

| 標題 (`## ` 或 `### `) | 掃描 |
|------------------------|------|
| `Strategy` | ✅ |
| `Implementation Plan` | ✅ |
| `Implementation Complete` → `Checklist` | ✅（`idd-implement` Step 5 寫回的 source of truth）|
| `Todo` / `Tasks` / `Checklist` | ✅ |
| `Current Status` → `Tasks` | ✅ |
| `Problem` / `Repro` / `Workaround` / `Expected` / `Actual` | ❌ |
| _其他未列出的標題_ | ❌（保守：只掃白名單）|

### 去重規則

同一個 issue 可能有多個 comments 含相同 source 標題（例如 re-run `idd-implement` 後發了兩個 `## Implementation Complete`）。Gate check **只看最後一個**（按 comment `createdAt` desc），那是最新的 source of truth。

### 為什麼這麼嚴格？

「Strategy 上列了 5 個 bullet，實作了 3 個就 close issue」是最常見的隱形 scope creep：
- 沒做的 2 個被遺忘，3 個月後變成新 bug 報告
- 或者其實根本不打算做，但沒人記錄「為什麼不做」
- 下一次類似需求再次走一遍 diagnose → 討論 → 決定不做 → 忘記 → …

強制 `- [~]` / `- [-]` + reason 的代價是多打 30 秒字，換來的是「這個決定有紀錄」。這在 issue-driven dev 裡比 velocity 重要。

### Two-Tier Gate（v2.29.0+）

`idd-close` 有兩層 gate,各自防一種失敗模式:

| Gate | Check what | 防什麼失敗 | 失敗行為 |
|------|-----------|-----------|---------|
| Step 0 — **Structural** (v2.17.0+) | 有沒有 `- [ ]` 未勾 | Honest forgetting(忘了打勾) | 🔴 REFUSE close,不給 `--force` |
| Step 1.6 — **Semantic** (v2.29.0+) | 打勾的 bullet 是否有對應 commit/artifact | Motivated cheating(打勾了但沒做) | 🟡 WARN + AskUserQuestion(proceed / investigate / edit) |

兩層的差別:
- **Structural** = audit completeness — 所有 todo 都 explicit。FALSE NEGATIVE 不可能(打了勾就是有條目)。FALSE POSITIVE 不可能(沒打勾就 refuse)。可以硬 refuse。
- **Semantic** = audit truthfulness — 打勾的事真做了。FALSE POSITIVE 有可能(test 的 commit 在更早的 PR、不在 #NNN log 裡)。所以 warn-only,讓 user 表態。

兩層加總後 IDD 的 audit trail 守住「沒寫 = 不算做」+「打勾沒做 = 至少要解釋一下」雙重契約。

### Falsifiability claim(v2.29.0+)

加了 Step 1.6 後,`idd-close` 的 falsifiability surface 是:

```
falsifiability(IDD) = falsifiability(TDD)         ← idd-implement Step 3 RED→GREEN→commit (繼承)
                    ∪ falsifiability(SDD)         ← spectra-apply spec/code conformance (條件繼承,SDD-warranted path)
                    ∪ semantic_check              ← Step 1.6 keyword → commit/file 驗證 (IDD-only)
                    ∪ process_compliance          ← issue why、closing summary root cause (IDD-only,non-mechanical)
```

Strict superset TDD/SDD:IDD 把它們的 outcome verification 全部繼承,加上 issue-level audit semantic check,還有 process compliance 層。後者(process)不是 mechanical falsifiable,但前三項都是。所以「IDD 比 TDD/SDD 弱」這個質疑在 v2.29.0 後不成立 — IDD ⊋ TDD ∪ SDD on falsifiability surface。

## Commit Conventions

IDD 的 close 流程是由 `idd-close` skill 執行的——它會跑 gate check、post Closing Summary、再實際關閉 issue。**不能**讓 GitHub 繞過這條流程 auto-close issue。

### 規則：一律走 skill，不用 auto-close trailer

| Trailer | 行為 | 在 IDD 裡 |
|---------|------|----------|
| `(#NNN)` / `Refs #NNN` | Cross-reference，不 auto-close | ✅ 推薦 |
| `Closes #NNN` | GitHub 立即 auto-close | ❌ 禁止 |
| `Fixes #NNN` | GitHub 立即 auto-close | ❌ 禁止 |
| `Resolves #NNN` | GitHub 立即 auto-close | ❌ 禁止 |

Commit message 只要用 `(#NNN)` 或 `Refs #NNN` 產生 cross-link 就好。Close 動作由 `/idd-close` 負責。

### 為什麼

#### 失敗模式 A：用 `Closes` trailer → gate bypass

1. Commit message 寫 `Closes #42`
2. Push 觸發 GitHub auto-close
3. `idd-close` 從未執行 → Step 0 Checklist Gate Check 從未跑
4. Strategy 的 `- [ ]` 可能還沒勾完——沒人攔
5. 沒有 Closing Summary——3 個月後回來看 issue 只剩 diagnosis，沒有 Solution / Root Cause 的最終紀錄

→ IDD 的核心契約「沒打勾就不關」+「結案必留 summary」被 silent 繞過。

#### 失敗模式 B：完全不 reference issue → zombie

1. Commit message 完全不寫 `#NNN`
2. Fix 沒 link 到 issue
3. Issue 保持 open，沒人回來 close
4. 堆積成 zombie（#1/#2/#6 都是這個模式，closed 前放 26 天）

→ Issue 被遺忘，類似 bug 再度報告時要重走 diagnose。

### 正確做法

**Both fix at once**: commit message 用 `(#NNN)` 或 `Refs #NNN` reference issue（防 zombie），close 時跑 `/idd-close` skill（enforce gate + post summary + 關 issue）。兩邊責任清楚：

- **Commit** 負責「留 cross-reference 痕跡」
- **Skill** 負責「驗收 + 記錄 + 關閉」

這樣 commit 是 fix 的紀錄、issue 是 workflow 的紀錄，不會互相 bypass。

### 歷史脈絡

- **#1 / #2 / #6** (2026-03)：commit message 用了 `(#1)` 但**沒有** `Closes` trailer，結果 GitHub 不 auto-close，issue 堆積 26 天變 zombie。當時學到的 lesson 是「用 `Closes` trailer」。
- **#11 / #13** (2026-04-14)：套用上面那個 lesson 在 commit message 寫 `Closes #11` 和 `Closes #13`，push 後 GitHub 立即 auto-close——但 v2.17.0 剛加的 `idd-close` gate check **從未跑過**，Closing Summary 也沒 post。之後補 retroactive comments 做補救。

兩個 lesson 綜合後的正確合成：**用 skill 做 close，用 cross-reference 做 commit link**。`Closes` trailer 本身沒有錯，只是對 IDD 的 close 流程有害——我們選擇讓 skill 成為唯一的 close pathway，換回可預期、可驗收的 close 契約。

### 補救：commit 已 push 且 trailer 已觸發 auto-close

1. 不要 reopen → re-close，那是 noise。
2. 補一個 retroactive Closing Summary comment，標題加 `(retroactive — auto-closed via Closes trailer)`，內容照 `idd-close` 的模板：Problem / Root Cause / Solution / Verification / Changes。
3. 在 comment 裡標記 Strategy checklist 的最終狀態（本來 gate 會驗收的東西），確保 audit trail 完整。
4. 記得在日後的 commit message 裡不要再犯。

### 引用 trap pattern 作反例的寫作紀律（v2.61.0+, #97）

GitHub auto-close parser 掃 commit message 和 PR body 是 **context-blind** — 單/雙引號、markdown bold、surrounding 「Do NOT」prose、italics 全都不抑制。當 commit body 或 PR body 需要**引用** trap pattern 作為反例（verify findings 解釋、diagnosis prose、debug 報告、這條規則本身），必須選下列任一安全形式：

| 形式 | 範例 | 為何安全 |
|------|------|---------|
| **Markdown code fence**（首選） | `` `Closes #N` `` | 渲染成 code 視覺、讀者一看就知道是 example；parser 仍會看到，但結合「literal letter N」更安全 |
| **Literal letter N**（搭配） | `Closes #N`（大寫 N，沒有數字） | 缺 `#<digit>` 數字 → GitHub regex 不 match。Mirrors existing safe pattern in [`references/pr-flow.md:127`](references/pr-flow.md) |
| **改用連結引用**（無 keyword） | `見 PR #94 #issuecomment-...` | 完全不重複 keyword，連 example 都不寫；最強但可讀性最低 |

**Anti-pattern**：單引號、雙引號、italics 包住 `Closes: #87`（含真實數字）**不會**抑制 parser。PR #94 commit `d918270` 的 messageBody 中 single-quote 例子就是這樣弄掛 `#87`（merge 後 2 秒 auto-closed），#97 整個 issue 都在修這個 channel。

**Why context-blind 不可繞**：GitHub parser 是 server-side regex，本地 markdown 渲染或 IDD 紀律對它無感。唯一可控的是輸入字串本身——要嘛 keyword 後沒數字、要嘛根本不寫 keyword。

`/idd-verify --pr` Step 0.8 v2.61.0+ Source 2（per-commit body scan）會在 verify 時 surface 命中，但只是 warn-only 防禦縱深；本紀律才是 commit-body 端的根本修法。

### Direct-commit path 沒有自動 auto-close gate（v2.75.2+, #151）

> **這條路徑上，commit-body 寫作紀律是你唯一的保護。**

IDD 的 auto-close 偵測（`idd-verify` Step 0.8）**只在 `--pr` mode 跑**。它綁在 PR review 這個 touchpoint 上 —— 走 **direct-commit path**（`idd-implement --no-pr`、或手動 `git commit && git push` 到 default branch）時，從「寫 commit body」到「GitHub auto-close parser 觸發」之間**沒有任何 client-side 攔截點**。一旦含 `close`/`fix`/`resolve` keyword + `#<digit>` 的 commit body land 上 default branch，GitHub 立即關掉對應 issue，繞過整個 `/idd-close` gate（checklist / semantic / sister-sweep / residue / distribution-sync）—— 而且**沒有 PR、沒有 verify、沒有任何 plugin 步驟會先看到它**。

實務守則：

| 情境 | 做法 |
|------|------|
| commit body 要 reference issue（防 zombie） | **預設 `Refs #N`**（cross-link、不 auto-close）。這是 direct-commit path 上 audit reference 的 default，不是 `Closes/Fixes/Resolves #<digit>` |
| commit body 要*引用* trap pattern 當反例 | 套用上面「引用 trap pattern 作反例的寫作紀律」(#97)：code fence + literal letter N，或根本不寫 keyword |
| 已經被 commit-body trap auto-close 了 | post retroactive `## Closing Summary`（標 `(retroactive — auto-closed via commit-body trap)`），補回 gate 會驗的東西 |

**回溯 safety net**：`/idd-list --audit-closes` 掃出「CLOSED 但無 `## Closing Summary`」的 issue（#151）—— reactive，不是 preventive，但能在事後抓到漏網的。standalone 版是 `scripts/check-closed-without-summary.sh`。

**為什麼沒有 preventive gate**：direct-commit path 上唯一能在 push *前*攔截的是 client-side git hook（`pre-push`），那需要 per-user 安裝、且不 cover CI/server push —— 列為 power-user opt-in（#151 Path A，deferred）。所以這條路徑的根本保護就是上面的寫作紀律 + Step 0.8（走 PR 時）+ #173 的 `pr-body-autoclose-guard`（防 template regression）。三者各守一段；direct-commit + 手寫 commit body 這段，紀律是最後一道。

## 設計哲學

> **核心論述見 [`MANIFESTO.md`](MANIFESTO.md)** — IDD 跟 TDD/SDD 的差異、5-axis 解 bug 能力拆解、closure axis、case study (`che-word-mcp` #56 cluster)。本段只列濃縮版。

### 五個 Skill = 五個 Checkpoint

每個 skill 是一個強制停頓點：

| Checkpoint | 確認什麼 |
|-----------|---------|
| `idd-issue` 之後 | 我們同意問題是什麼了嗎？ |
| `idd-diagnose` 之後 | 我們理解為什麼了嗎？ |
| `idd-implement` 之後 | 我們只改了該改的嗎？ |
| `idd-verify` 之後 | 真的修好了嗎？ |
| `idd-close` 之後 | 記錄完整嗎？ |

### 與其他方法論的差異

本 plugin 是 **issue-driven**（問題驅動），不是 process-driven（流程驅動）。
所有決策都圍繞 `#NNN`，不是圍繞流程步驟。

IDD 不是把 TDD + SDD + issue tracking 拼在一起的 combo —
而是指出 issue 是更基本的單位，TDD 和 SDD 是從 issue 自然衍生的特化流程。
這解釋了為什麼單獨使用 TDD 或 SDD 時總覺得「少了什麼」：少的就是 issue 提供的 why。

### 參考

- **superpowers** (claude-plugins-official) — 小粒度 skill 設計、verification 獨立化
- 本 plugin 的優勢：per-project config (`.local.md`)、具體 CLI 指令

## Development

- Update after changes: `/plugin-tools:plugin-update issue-driven-dev`
- Health check: `/plugin-tools:plugin-health`
