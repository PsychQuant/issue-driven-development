---
name: idd-list
description: |
  列出 GitHub issues（預設 open），顯示每個 issue 的 IDD phase 和建議 next action。
  按 config-protocol 解析 target repo(walk-up cascading + --target flag),支援 --state / --label / --limit filter。
  Use when: 開工前 triage、想知道有哪些還沒處理完的 issue、回到專案看進度。
  防止的失敗：不知道有什麼要做、重複 diagnose 已處理的 issue、漏掉卡在 verify 的 issue。
argument-hint: "[--state open|closed|all] [--label <name>] [--limit N] [--target owner/repo]"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
  - Read
---

# /idd-list — 列出 Issues

快速看 repo 有哪些 issue 在 IDD workflow 的哪個階段，並顯示每個 issue 的下一步。

## 核心原則

> 開工前先看 open issues — 避免重複 diagnose、漏掉卡 verify 的、或不知從哪開始。

## Configuration

按 [config-protocol](../../references/config-protocol.md) 解析 target repo。priority(由高到低):

1. `--repo owner/repo` flag (per-invocation override)
2. Walk-up `.claude/issue-driven-dev.local.json`(從 cwd 往上找,first-match wins)
3. Path predicates (`when.path_contains` / `path_matches` / `git_remote_matches` 等)在 candidates / groups 上自動匹配
4. `ask_each_time: true` → AskUserQuestion menu
5. Fallback: `gh repo view --json nameWithOwner -q .nameWithOwner` 偵測 git remote
6. 偵測不到 → 要求明確 `--repo`

**注意**:`idd-list` 不會評估內容類 predicate(`title_matches` / `label_in` 等),因為這個 skill 不蒐集 issue title/labels。只 path / git 類 predicate 會生效。

**Group 行為**:若解析結果是 group,預設只列 primary repo 的 issues;加 `--all-tracked` 可同時列所有 tracking repos。

## Execution

### Step 0: Bootstrap Stage Task List（強制)

**在動任何事之前**先用 `TaskCreate` 為這個 stage 建 todo list,確保每個 sub-step 都被追蹤:

```
TaskCreate(name="parse_args", description="Parse --state / --label / --limit / --repo flags 並 fallback 到 .claude/issue-driven-dev.local.json")
TaskCreate(name="fetch_issues", description="gh issue list 取 number/title/state/labels/updatedAt/body/comments")
TaskCreate(name="fetch_open_prs", description="Step 2.5 (v2.51+): gh pr list --state open --json number,body,title,isDraft,mergeable,headRefName,createdAt --limit 100 一次抓所有 open PR")
TaskCreate(name="extract_phase", description="從每個 issue body 的 Current Status → **Phase**: 抽出 phase；fallback 掃 comments 標題推斷")
TaskCreate(name="build_issue_pr_index", description="Step 3.5 (v2.51+): client-side regex scan PR body 找 #N refs,反向建 issue→PR map + identify clusters (PR refs ≥ 2 issues)")
TaskCreate(name="format_output", description="組 #N [phase] title 表格;有 PR 加 └─ 子行 (cluster leader 顯示 cluster: #X #Y / member 顯示 → see PR #N) + footer 統計含 PR/cluster 數")
TaskCreate(name="report_and_suggest_next", description="輸出 table 並列出每個 issue 的 Suggested next 命令 (依 phase × PR state matrix)")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。**TaskCreate 清單 = 真實的步驟清單；任何寫在 skill 裡但沒列進 TaskCreate 的步驟，都視為 skill 的 bug，必須補進 Task 清單。**

---

### Step 1: Parse Arguments

| Flag | 預設 | 說明 |
|------|------|------|
| `--state` | `open` | `open` / `closed` / `all` |
| `--label` | _(none)_ | 單一 label filter |
| `--limit` | `20` | 最多顯示筆數 |
| `--repo` | _(from config)_ | 覆寫 config 的 repo |

### Step 2: Fetch Issues

```bash
gh issue list \
    --repo "$GITHUB_REPO" \
    --state "$STATE" \
    --limit "$LIMIT" \
    ${LABEL:+--label "$LABEL"} \
    --json number,title,state,labels,updatedAt,body,comments
```

按 `updatedAt` desc 排序（最新活動在最上面）。

### Step 2.5: Fetch Open PRs (v2.51.0+)

一次 batch fetch 所有 open PR(支援 cluster detection — per-issue query 看不到 sibling refs):

```bash
gh pr list \
    --repo "$GITHUB_REPO" \
    --state open \
    --limit 100 \
    --json number,title,body,isDraft,mergeable,headRefName,createdAt,url
```

**為何不用 `gh pr list --search "in:body \"#${N}\""` 對每個 issue 單獨查**:N+1 query 不可,且 per-issue query **無法偵測 cluster**(同 PR ref 多 issue 時,從單一 issue 角度查只看到自己被 ref,看不到 sibling)。

**Limit 為何 100**:dogfood repo 通常 < 50 open PR;100 是保守上限。若 repo 真有 100+ open PR(罕見),`idd-list` 仍可用,但可能漏掉最舊的 PR。後續若有需求可加 `--pr-limit N` flag(目前 out-of-scope,見 issue #13 R2)。

**為何只看 open PR**:list 的目的是「actionable next step」,closed/merged PR 對應 issue 應已 close 或 catch-up close,本 step 不重複處理。

### Step 3: Extract Phase

每個 issue 的 body 由 `idd-update` 管理的 `## Current Status` 區塊含 `**Phase**: {phase}` 行。優先從這裡讀。

Phase 值（與 `idd-update` 一致）：

- `created` — 新建，無 diagnosis
- `diagnosed` — 已 diagnose
- `planning` — 有 implementation plan
- `implemented` — 有 implementation complete
- `verified` — verify 通過
- `needs-fix` — verify 失敗，待修
- `closed` — 已結案

**解析策略**：

1. 掃 body 尋找 `**Phase**:` 行，取第一個 match 的值
2. 找不到 → 掃 comments 的標題推斷（`## Diagnosis` → `diagnosed`，`## Implementation Complete` → `implemented`，`## Verify (PASS)` → `verified`，`## Verify (FAIL)` → `needs-fix`，`## Closing Summary` → `closed`）
3. 仍推不出 → 顯示 `(no phase)`（legacy issue，建議手動 `/idd-update`）

### Step 3.5: Build Issue→PR Index (v2.51.0+)

對 Step 2.5 抓到的每個 open PR,scan body 找 issue refs,反向建 `issue_number → [pr_info, ...]` map。同時偵測 cluster(同一 PR ref ≥ 2 個 issue):

```python
# Pseudocode
import re

PR_REF_RE = re.compile(r'#(\d+)\b')

issue_to_prs = {}  # issue_number -> [pr_info, ...]
clusters = {}      # pr_number -> [issue_number, ...] (only when len >= 2)

for pr in open_prs:
    refs = set(int(m) for m in PR_REF_RE.findall(pr['body'] or ''))
    if not refs:
        continue
    pr_info = {
        'number': pr['number'],
        'title': pr['title'],
        'is_draft': pr['isDraft'],
        'mergeable': pr['mergeable'],
        'url': pr['url'],
        'cluster_members': sorted(refs) if len(refs) >= 2 else None,
    }
    for issue_num in refs:
        issue_to_prs.setdefault(issue_num, []).append(pr_info)
    if len(refs) >= 2:
        clusters[pr['number']] = sorted(refs)
```

**Regex 說明**:`#(\d+)\b` 偵測任何 `#NNN` 提及(`Refs #N` / `(#N)` / `Closes #N` / 純內文 `see #N` 都會中)。

**Known false positive (第一版接受)**:fenced code block 內的 `#N`(例如 PR body 含 `\`\`\`bash\ngit commit -m "Refs #99"\n\`\`\``)會被誤當 ref。Markdown-aware filter 是 follow-up issue **#14**(R1)。

**Cluster leader 規則**:`min(cluster_members)` — deterministic、易預測。設定不同規則(如 `cluster_leader: primary`)是 follow-up issue **#15**(R3)。

**多 PR ref 同 issue**(罕見:超過一個 open PR 都 ref 同一 issue,可能是 wip + amendment)→ Step 4 顯示所有對應 PR 各一行 `└─` 子行。

### Step 4: Format Output

```
Repo: PsychQuant/issue-driven-development  (state: open, limit: 20)

#42  [implemented] feat: foo bar baz
     labels: feature       | updated 1h ago  | 3 comments
     └─ PR #99 (ready, MERGEABLE) — cluster: #42 #43 #44

#43  [implemented] feat: bar baz qux
     └─ → see PR #99 (cluster member)

#44  [verified]    feat: baz qux quux
     └─ → see PR #99 (cluster member)

#45  [verified]    fix: independent fix
     labels: bug           | updated 2d ago  | 1 comment
                                                          ← direct-commit path,無 PR 子行

#8   [verified]    bug: 中文檔名附件導致 AppleScript error (-2741)
     labels: bug           | updated 4d ago  | 3 comments
     └─ PR #100 (draft, MERGEABLE)

───────────────────────────────────────────────────────────────
5 open issue(s) — 3 implemented, 2 verified
3 issues bundled in 1 cluster (PR #99); 1 solo PR (#100); 1 direct-commit
```

格式規則：

- `#N` 左對齊，寬度 4（單 digit #N 也對齊）
- `[phase]` 後接 title，title 不截斷
- Labels 按字母序，逗號分隔，無 label 則省略該欄
- 時間顯示相對值（`2h ago`, `3d ago`, `2mo ago`）
- Footer 顯示總數 + phase 分佈

**v2.51.0+ PR sub-line 規則**:

- **無 PR refs(direct-commit path)**:不加 `└─` 子行(完全 backward compatible:無 PR 的 issue 顯示與 v2.50 一致)
- **Single-PR(該 issue 只被 1 個 PR ref,且 PR refs 只此 1 issue)**:`└─ PR #N (status, mergeable)`
- **Cluster leader(該 issue 是 cluster 的 `min(refs)`)**:`└─ PR #N (status, mergeable) — cluster: #X #Y #Z`(列出 cluster 全部 members,含 leader 自己)
- **Cluster member(非 leader 但屬於 cluster)**:`└─ → see PR #N (cluster member)`(redirect 引讀者去 leader 那行)
- **Status format**:`(draft|ready, MERGEABLE|CONFLICTING|UNKNOWN)` — 從 `isDraft` + `mergeable` 對應
- **多 PR ref 同 issue**(罕見):每個 PR 各一行 `└─`,順序 by PR number asc

**v2.51.0+ Footer 擴充**:

- 第二行新增 PR/cluster 統計:`N issues bundled in M cluster(s) (PR #X, #Y); P solo PR(s); Q direct-commit`
- `cluster` 計數:有 ≥ 2 issue refs 的 open PR 數
- `solo PR`:只 ref 1 issue 的 open PR 數
- `direct-commit`:無任何 open PR ref 的 issue 數
- 若無任何 open PR,Footer 維持原 v2.50 格式(只有 phase 分佈),不加第二行

若沒有 issue，顯示 `No issues found. 🎉`。

### Step 5: Suggest Next Actions

Footer 之後列出每個 issue 的建議下一步。**v2.51.0+ phase × PR state matrix**:依 issue phase 和 Step 3.5 抓到的 PR state 組合決定 next action。

```
Suggested next:
  #42 [implemented] → /idd-verify --pr 99 (covers cluster #42 #43 #44)
  #45 [verified]    → /idd-close #45
  #8  [verified]    → gh pr ready 100 → gh pr review 100 → gh pr merge 100 → /idd-close #8
```

#### Phase × PR state matrix(v2.51.0+)

| Phase | PR state | Suggested next |
|-------|----------|----------------|
| `created` | (任何 PR state — 未開始) | `/idd-diagnose #N` |
| `diagnosed` | (PR 通常還沒) | 依 diagnosis 的 `### Complexity`(見下方表) |
| `planning` | no PR | `/idd-implement #N` (plan 已 approved) |
| `planning` | has PR | `/idd-implement #N` (continue,plan-mode 不會自己開 PR;若 PR 已開可能是先前 round 留下) |
| `implemented` | no PR (direct-commit) | `/idd-verify #N` |
| `implemented` | draft PR | `gh pr ready N → /idd-verify --pr N` |
| `implemented` | ready, MERGEABLE | `/idd-verify --pr N` |
| `implemented` | CONFLICTING | `gh pr checkout N → resolve conflicts → /idd-verify --pr N` |
| `verified` | no PR (direct-commit) | `/idd-close #N` |
| `verified` | ready, MERGEABLE | `gh pr review N → gh pr merge N → /idd-close #N` |
| `verified` | merged (catch-up edge) | `/idd-close #N` (PR 已合,issue 還 open) |
| `verified` | CONFLICTING | `gh pr checkout N → resolve → /idd-verify --pr N` (re-verify after fix) |
| `needs-fix` | (任何) | `/idd-diagnose #N` (重新分析為什麼 verify fail) |
| `closed` | _(略)_ | _(略)_ |
| `(no phase)` | (任何) | `/idd-update #N` 先同步狀態,再 `/idd-diagnose #N` |

**Cluster member 的 next action 特殊處理**:

當 issue 是 cluster member 時(屬於 `clusters[pr] = [...]` 且不是 leader):

- next action 顯示 `→ 操作 leader (#X) 的 cluster` 引導 user 到 leader
- Cluster operations(verify / close)鼓勵用 cluster-PR mode(`idd-verify --pr N` 或 `idd-close #X #Y #Z`),不是逐 issue 操作

範例:

```
Suggested next:
  #42 [implemented] → /idd-verify --pr 99 (covers cluster #42 #43 #44)
  #43 [implemented] → see #42 (cluster member, follow leader's next action)
  #44 [implemented] → see #42 (cluster member, follow leader's next action)
```

#### `diagnosed` phase 的 Complexity-aware sub-routing(v2.36.0+ 既有)

| Complexity | Next |
|-----------|------|
| `Simple` | `/idd-implement #N` |
| `Plan` | `/idd-plan #N` |
| `Spectra` (含 alias `SDD-warranted`) | `/spectra-discuss` (default) 或 `/spectra-propose` (opt-out) |
| 推不出 | `/idd-implement #N` (保守 default) |

**Complexity 解析**：對 phase=`diagnosed` 的 issue，掃最新 `## Diagnosis` comment 的 `### Complexity` 行（regex `### Complexity\n([A-Za-z-]+)`），取第一個 token。`SDD-warranted` 視同 `Spectra`。Verdict 後綴(如 `Plan via Layer V`,v2.50.0+)用 `split(' via ')[0]` 取 canonical tier。

## 鐵律

- **不亂猜 repo**。偵測不到就明確要求 `--repo`，不 fallback 到「最近用的 repo」。
- **不截斷 title**。IDD issue 標題通常是唯一的語意標記，截斷等於丟資訊。
- **按 updatedAt 排序**，不是 createdAt。最近被動的 issue 通常最該注意。
- **Phase 推斷失敗不是錯誤**。顯示 `(no phase)` 讓使用者自己決定，並建議先跑 `idd-update`。

## 手動呼叫

```
/issue-driven-dev:idd-list                       # 當前 repo 的 open issues
/issue-driven-dev:idd-list --state all           # 所有狀態
/issue-driven-dev:idd-list --label bug --limit 5 # 只看 bug label
/issue-driven-dev:idd-list --repo owner/name     # 覆寫 repo
```

## 與 `gh issue list` 的差異

| 能力 | `gh issue list` | `idd-list` |
|------|-----------------|-----------|
| 原始 issue metadata | ✅ | ✅ |
| IDD phase 顯示 | ❌ | ✅ |
| 建議 next action | ❌ | ✅ |
| 自動用 config 的 repo | ❌ | ✅ |
| Phase 分佈統計 | ❌ | ✅ |

`idd-list` 不是 `gh issue list` 的替代，是 **IDD workflow 視角的增強包裝**。若只想要原始 issue 列表，直接用 `gh issue list` 更輕量。
