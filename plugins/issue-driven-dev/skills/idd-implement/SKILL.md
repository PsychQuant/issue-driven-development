---
name: idd-implement
description: |
  按照 diagnosis 的策略實作，嚴格控制 scope。
  只改 issue 要求的東西，每個 commit 引用 #NNN。
  支援 cluster-PR mode（v2.34.0+）：多個 #N 共用 1 feature branch + 1 PR（如 `#34 #36 #38 --pr`），每個 commit 用 `Refs #N` 紀律標示。
  Use when: diagnosis 確認後、開始寫 code 時。
  防止的失敗：scope creep — 改 #42 順手重構了三個不相關的檔案。
argument-hint: "#issue [#issue ...] [--pr | --no-pr] [--cwd /path/to/clone] [--with-skill <skill>] [--extra '<requirement>'] e.g. '#42 --with-skill perspective-writer --extra ''要 500–800 字''' or '#34 #36 #38 --pr' (cluster-PR mode) or '#43 --pr --cwd /path/to/other/repo' (cross-repo)"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
  - TaskCreate
  - TaskUpdate
  - TaskList
---

# /implement — 紀律實作

按 diagnosis 的策略寫 code，不多做也不少做。每個 checklist item 都有 TaskList 條目追蹤，`idd-close` 會強制驗收。

## 核心原則

> 每一行改動都必須能追溯到 #NNN。追溯不到的改動 → 開新 issue。
>
> **Strategy 上的每個 `- [ ]` 都是契約**——`idd-implement` 開始時進 TaskList，`idd-close` 會 refuse 關任何還有未勾項的 issue。

## Cross-repo invocation（v2.40.0+）

支援 `--cwd /path/to/local/clone` flag,讓 implement 在指定 local clone 上做 commit、checkout、push(不依賴 Claude Code session cwd)。Step 0 解析 `--cwd` 後,後續所有 `git`/`gh` 命令依 [`references/cross-repo-cwd.md`](../../references/cross-repo-cwd.md) 的 substitution rule 改寫:

- `git X` → `git -C "$CWD" X`(包含 fork detection、branch checkout、add、commit、push)
- `gh issue/pr/repo X` → `gh ... X -R "$GITHUB_REPO"`

**特別重要**:Phase 0.5 fork detection、Phase 5.5 PR 建立、Step 5 commit 都必須用 `git -C "$CWD"`,否則會 commit 到錯的 repo。完整 algorithm + 失敗模式見 reference 文件。

**本 skill 內所有 bash 範例為 cwd-only 寫法以保持可讀性,執行時請套用 substitution rule。**

## Cluster-PR mode（v2.34.0+）

`idd-implement #34 #36 #38 --pr` 觸發 cluster-PR mode：3 個 issue 共用 1 個 feature branch + 1 個 PR，但每個 commit 仍以 `Refs #N`（可多）紀律標示對應 issue。Strategy-level TaskList 從各 issue 的 diagnosis 聚合，scope guard 仍逐 issue 檢查。

完整契約見 [batch-and-cluster.md](../../references/batch-and-cluster.md)。Cluster-PR mode 強制 PR path:`--no-pr` 或 `pr_policy=never` 撞 cluster 時,Phase 0.5 印 explicit override notice(`→ cluster mode (N issues) → PR path enforced (overriding --no-pr / pr_policy=never)`,mirror fork detection 既有 pattern)後 proceed as PR mode — 不 abort、不 silent ignore。完整 resolution semantics 見 [pr-flow.md § Cluster mode override](../../references/pr-flow.md#cluster-mode-override)。Branch 命名 `idd/cluster-{slug}`,PR 標題前綴 `cluster:`。

實用情境：04/27 那種「7 個 issue 分成 Docs + Sanitizer-hardening 2 個 themed PR」的工作流。Single-issue 模式（`idd-implement #19`）行為不變。

**何時該 bundle vs 拆 atomic PR**：見 [batch-and-cluster.md § Cluster-PR eligibility](../../references/batch-and-cluster.md#cluster-pr-eligibility-when-to-bundle-vs-split) — same-file / same-skill / same-root-issue 才適合 bundle;只共用 parent label 通常太弱,review surface > 50 行就拆。

## Configuration

按 [config-protocol](../../references/config-protocol.md) 解析 target repo:

- `--repo owner/repo` flag → per-invocation override
- Walk-up `.claude/issue-driven-dev.local.json`(從 cwd 往上找)
- Path / git predicates 自動匹配

**Group/predicate 行為**:`idd-implement` 操作既存 issue,只用 path/git 類 predicate。Group config 會 fall through 到 primary repo。

**PR vs Direct-commit path**:由 `--pr` / `--no-pr` flag、`pr_policy` config 欄位、與 fork detection 共同決定。完整 algorithm 見 [pr-flow](../../references/pr-flow.md)。Phase 0.5 會明確解析並印出選擇的 path。

## Execution

### Step 0: Bootstrap Stage Task List（強制)

**在動任何事之前**先用 `TaskCreate` 為這個 stage 建 stage-level todo list(與 Step 2.5 的 per-Strategy-item TaskList 不同層):

```
TaskCreate(name="resolve_pr_path", description="Phase 0.5: --pr/--no-pr flag → fork detection → pr_policy config → ask. 若 PR path: 建 feature branch")
TaskCreate(name="read_issue_and_diagnosis", description="gh issue view + 確認最新 diagnosis comment 的 Strategy")
TaskCreate(name="check_attachments", description="確認 .claude/.idd/attachments/issue-NNN/ 存在且 _manifest.json 涵蓋當下 issue attachment list;偵測新增 attachment 補 fetch。manifest 缺漏 → 警告並引導使用者重跑 idd-diagnose,不 auto-repair。依 rules/process-attachments.md。")
TaskCreate(name="draft_implementation_plan", description="依 Strategy 起草 Implementation Plan 並 comment 到 issue")
TaskCreate(name="bootstrap_strategy_tasklist", description="Step 2.5: Simple complexity → 為每個 - [ ] bullet 建 TaskCreate; SDD → 跳過(spectra-apply 管)")
TaskCreate(name="execute_tdd_loop", description="Step 3: pre-flight superpowers（check-plugin-presence.sh 三參數，缺席 fail-fast）→ 對每個 strategy item invoke superpowers:test-driven-development 完成 TDD 執行 → commit (#NNN) → TaskUpdate completed（#209 delegation）")
TaskCreate(name="scope_guard", description="實作中發現不相關問題 → 開新 issue,不混入本 #NNN")
TaskCreate(name="sync_checklist_and_summary", description="Step 5: 把最終 checklist 狀態寫回 Implementation Complete comment")
TaskCreate(name="open_pr_if_pr_path", description="Phase 5.5: PR path 才執行 — git push + gh pr create with Refs #NNN body")
TaskCreate(name="sister_bug_sweep", description="Step 5.7: review session log + reproduction trace, identify sister bugs / refactor opportunities / TODOs encountered; AskUserQuestion 3-option per canonical references/ic-r011-checkpoint.md; PATCH Implementation Complete comment with `### Sister Bugs Filed` audit trail (per IC_R011 #526)")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。

**v2.32.0+ tagging 規則**：若 Implementation Plan / Implementation Complete comment 中要 @-tag reviewer 或 stakeholder，**必須**遵循 [`rules/tagging-collaborators.md`](../../rules/tagging-collaborators.md) 5 步協定（gh api → fuzzy match → AskUserQuestion fallback → @login 不用 display name → post 前 verify）。違反 = 通知錯人，不可逆。

> **兩層 task 的關係**:
> - **Stage-level TaskList(此 Step 0)** — 追蹤 idd-implement 本身的 6 個 execution steps
> - **Strategy-level TaskList(Step 2.5 Bootstrap)** — 追蹤具體改動清單的每個 checklist bullet
> 兩者並存。Stage-level 的 `execute_tdd_loop` 那一項,會持續等到 Strategy-level 所有 items 完成後才 mark 為 completed。

---

### Step 0.4: Tree-lock acquire / asymmetric escalation（v2.85.0+, #183）

**在 Step 0.5 path resolution 之前**，先嘗試取得 shared working-tree lock。這把 line 210 的 advisory「prefer a worktree」變成 **normative 機制**：第一個 session 免費持有 main tree（direct-commit 零稅），後到的 session 偵測到 live holder 就**自己** escalate 進 worktree —— 沒有 session 需要預測未來或事後搬 tree（converged Option D，#183 discuss 2026-06-03）。

```bash
# Identity for the lock: a PERSISTENT process pid. $PPID = the harness shell,
# stable across this claude instance's Bash calls and dead once the instance
# exits — the correct cross-terminal liveness anchor. Do NOT use $$ (this bash's
# own pid, dead the instant the command returns → the lock would never hold,
# #183 verify B1). Same-instance sub-agent concurrency (shared $PPID) is the
# already-deferred Case A (worktree-isolation.md), out of scope here.
TREE_LOCK="$CLAUDE_PLUGIN_ROOT/scripts/idd-tree-lock.sh"
bash "$TREE_LOCK" acquire --repo "$CWD" --pid "$PPID" --id "${IDD_SESSION_ID:-tree-$PPID}"
LOCK_RC=$?
case "$LOCK_RC" in
  0) echo "→ tree lock acquired — solo on shared tree ($CWD), zero worktree tax" ;;
  3) # Another LIVE session holds the tree. Self-escalate into an isolated
     #    worktree — do NOT wait for the holder (idle != done; isolate now).
     echo "→ tree held by a live session → escalating to an isolated worktree"
     WT=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/idd-worktree.sh" create "$NUMBER" --repo-root "$CWD" 2>/dev/null | tail -1)
     if [ -n "$WT" ] && [ -d "$WT" ]; then
       CWD="$WT"   # all later git -C "$CWD" plumbing now routes to the worktree
       echo "→ working in $CWD (own worktree + branch; merge back at close)"
     else
       echo "⚠ worktree escalation failed — proceeding on shared tree (collision risk; review carefully)"
     fi
     ;;
  4) # Lock infra unwritable → FAIL OPEN. The lock is a convenience; the
     #    correctness backstop is the #184 merge-completeness gate. Never block work.
     echo "⚠ tree-lock dir unwritable — proceeding on main tree without isolation (fail-open)" ;;
  *) echo "⚠ tree-lock acquire returned $LOCK_RC — proceeding on main tree (fail-open)" ;;
esac
```

> **Asymmetric, never predictive**：first-comer 持 tree（exit 0），later-comer 偵測 live holder（exit 3）自己隔離。Lock 只回答「此 tree 還有別的 live session 嗎？」用 PID liveness 判定，**永不**問「holder 做完了嗎？」（這次 ai_martech incident 的 watcher 證明 process-quiet ≠ session-done）。Stale lock（dead holder）由 helper 在 acquire 時自動 reclaim。
>
> **Fail-open 紀律（exit 4 / 其他）**：lock infra 壞掉**不擋工作** —— 留在 main tree + 印 visible warning 繼續。Lock 是便利層，正確性的兜底是 #184 merge-completeness gate（escalated session branch+merge，orphan 由 #184 抓）。
>
> **Release**：lock 在 `idd-close` 釋放（見該 skill）；session 異常結束留下的 stale lock 由下一個 starter 的 acquire 自動 reclaim。

完整契約見 [`references/worktree-isolation.md`](../../references/worktree-isolation.md) § Tree-lock。

### Step 0.5: Resolve PR vs Direct-commit Path

完整 resolution algorithm 見 [references/pr-flow.md](../../references/pr-flow.md)。簡述:

```
0. Cluster mode (≥2 #N args)     → pre-empts entire table; PR path forced
                                    (see pr-flow.md § Cluster mode override)
1. --pr flag                     → PR path
2. --no-pr flag                  → direct-commit path
3. gh repo view --json isFork    → 若 true,強制 PR path(無法 push 到 upstream)
4. config.pr_policy = "always"   → PR path
5. config.pr_policy = "never"    → direct-commit path
6. config.pr_policy = "ask" / 缺省 → AskUserQuestion(同 conversation 內 cache 答案)
```

```bash
# 1. Parse flag + count DISTINCT well-formed issue args (cluster mode = ≥2 #N)
#
# v2.70.0+ #100 Finding 2 — glob hardening:
#   - Previous glob `\#[0-9]*` matched any `#<digit><anything>` including
#     malformed tokens like `#42abc` (the `*` absorbed the trailing letters)
#   - Duplicate args like `#34 #34` over-counted as 2, tripping CLUSTER_MODE
#     on a single distinct issue
#   - Strict regex `^#[0-9]+$` (matching batch-and-cluster.md documented form)
#     + associative-array dedup closes both issues
PR_FLAG=""  # "pr" / "no-pr" / ""
declare -A SEEN_ISSUES=()
ISSUE_COUNT=0
for arg in "$@"; do
    case "$arg" in
        --pr)     PR_FLAG="pr" ;;
        --no-pr)  PR_FLAG="no-pr" ;;
        \#*)
            # Strict integer check + dedup (v2.70.0+ #100)
            arg_num="${arg#\#}"
            if [[ "$arg_num" =~ ^[0-9]+$ ]] && [ -z "${SEEN_ISSUES[$arg_num]:-}" ]; then
                SEEN_ISSUES[$arg_num]=1
                ISSUE_COUNT=$((ISSUE_COUNT + 1))
            fi
            ;;
    esac
done
CLUSTER_MODE="false"
[ "$ISSUE_COUNT" -ge 2 ] && CLUSTER_MODE="true"

# 2. Fork check
IS_FORK=$(gh repo view "$GITHUB_REPO" --json isFork -q .isFork 2>/dev/null || echo "false")

# 3. Config policy
PR_POLICY=$(jq -r '.pr_policy // "ask"' "$CONFIG_PATH" 2>/dev/null || echo "ask")

# 4. Resolve (cluster mode is a precondition that pre-empts the table; see pr-flow.md § Cluster mode override)
if [ "$CLUSTER_MODE" = "true" ]; then
    PATH_CHOICE="pr"
    # If --no-pr or pr_policy=never collides, print explicit override notice (mirror fork detection)
    OVERRIDE_SRC=""
    [ "$PR_FLAG" = "no-pr" ] && OVERRIDE_SRC="--no-pr"
    [ "$PR_POLICY" = "never" ] && OVERRIDE_SRC="${OVERRIDE_SRC:+$OVERRIDE_SRC / }pr_policy=never"
    if [ -n "$OVERRIDE_SRC" ]; then
        echo "→ cluster mode ($ISSUE_COUNT issues) → PR path enforced (overriding $OVERRIDE_SRC)"
    fi
    # If fork ALSO detected, print fork notice too (both pre-emptions independently force PR)
    [ "$IS_FORK" = "true" ] && echo "→ Repo is a fork; PR path enforced."
elif [ "$PR_FLAG" = "pr" ]; then
    PATH_CHOICE="pr"
elif [ "$PR_FLAG" = "no-pr" ]; then
    PATH_CHOICE="no-pr"
elif [ "$IS_FORK" = "true" ]; then
    PATH_CHOICE="pr"
    echo "→ Repo is a fork; PR path enforced."
elif [ "$PR_POLICY" = "always" ]; then
    PATH_CHOICE="pr"
elif [ "$PR_POLICY" = "never" ]; then
    PATH_CHOICE="no-pr"
else
    # ask via AskUserQuestion
    PATH_CHOICE=$(ask_user "Open a PR for #$NUMBER?" \
        "PR path (feature branch + push + gh pr create)" \
        "Direct-commit path (commit to current branch, no PR)")
fi

echo "→ Path: $PATH_CHOICE"
```

#### If PR path: create feature branch

Pre-conditions:
- Working tree clean
- On default branch

```bash
# Skip if already on the expected feature branch (re-running idd-implement after verify findings)
EXPECTED="idd/${NUMBER}-${SLUG}"
CURRENT=$(git branch --show-current)

if [ "$CURRENT" = "$EXPECTED" ]; then
    echo "→ Already on $EXPECTED, continuing."
elif [[ "$CURRENT" =~ ^idd/${NUMBER}(-|$) ]]; then
    # Slug-agnostic worktree-branch acceptance (idd-worktree.sh create #N):
    # git forbids two worktrees on the default branch, so a helper-created
    # worktree is necessarily already on idd/<N>-<slug>. Accept any slug after
    # idd/<N>- (and bare idd/<N>) for THIS issue — same outcome as the EXPECTED
    # path above, bypassing the default-branch precondition.
    echo "→ On worktree feature branch $CURRENT (idd-worktree.sh), continuing."
elif [ "$CURRENT" = "$DEFAULT_BRANCH" ]; then
    git checkout -b "$EXPECTED"
else
    abort "PR path requires starting from $DEFAULT_BRANCH (currently on $CURRENT)."
fi
```

If branch already exists from a prior aborted run: AskUserQuestion (checkout / `${EXPECTED}-2` suffix / abort).

> **Concurrent-session isolation (#947)**: the `abort` branch above is the floor — it refuses rather than yanking when the tree is on another branch. **Prefer an isolated `git worktree`** for PR-path branch acquisition so concurrent `/idd` sessions never share one tree (set `CWD` to the worktree; the existing `git -C "$CWD"` plumbing routes the rest of the flow). And **never** manually `git stash` / `git checkout` a shared tree that may hold another session's WIP to "make room" — that is the silent-data-loss path reproduced in #941↔#942 (the yank was an agentic manual action, not this documented flow). Full rule: [`references/pr-flow.md`](../../references/pr-flow.md) → "Concurrent-session isolation". **Single canonical mechanism（#169 統一）**: `scripts/idd-worktree.sh create <N>`（issue-keyed `.claude/worktrees/idd-<N>/`, gitignored, `create`/`cleanup`/`list` + `idd-close` auto-GC）— pr-flow 的 snippet 已改呼叫同一 helper，兩處不再是「different ergonomic tiers」而是同一入口；見 [`references/worktree-isolation.md`](../../references/worktree-isolation.md) (#167/#169)。

> **Worktree-branch acceptance（v2.75.0+, #167）**：當 `idd-implement #N --cwd <worktree>` 跑在 `idd-worktree.sh create N` 建出的 worktree 上時，`git branch --show-current` 已是 `idd/<N>-<slug>`（git 不允許兩個 worktree 共用 default branch）。上面 `^idd/${NUMBER}(-|$)` 那條 clause 是 **slug-agnostic** 的：任何 `idd/<N>-` 後綴（或裸 `idd/<N>`）都接受為 feature branch，跳過建 branch 與 default-branch 前置檢查。不同 issue 號的 branch（如實作 #167 時落在 `idd/999-*`）不匹配，照原 resolution 走。

> 注意：這條 clause **不限定** `--cwd`/worktree 情境 —— 任何工作目錄(含主 tree)只要 current branch 是 `idd/<N>-*` 就接受。這是**刻意的**，與上面既有的 exact-`$EXPECTED` resume clause 一致(re-run idd-implement after verify findings 時也是在 feature branch 上直接續做、非 default branch)。代價是 stale same-issue branch 也會被接受續用，符合「同一 issue 的 work 在自己 branch 上續做」的語意。

契約見 [`references/worktree-isolation.md`](../../references/worktree-isolation.md)。

#### If direct-commit path: print notice, stay on current branch

```bash
echo "→ Direct-commit path: committing to $CURRENT, no PR will be opened."
```

No branch operations. Whatever branch the user is on, commits land there.

---

### Step 1: 讀取 Issue + Diagnosis

```bash
gh issue view $NUMBER --repo $GITHUB_REPO --json title,body,labels
```

回顧對話中的 diagnosis report，確認 strategy。

### Step 1.2: 檢查 Attachment(下游)

依 [`rules/process-attachments.md`](../../rules/process-attachments.md):

```bash
IDD_CALLER=idd-implement bash $CLAUDE_PLUGIN_ROOT/scripts/process-attachments.sh check $NUMBER
```

Exit code:
- `0` — manifest up-to-date,可繼續實作
- `1` — manifest missing 或 issue 有新 attachment 未抓 → **不 auto-repair**,警告使用者重跑 `/idd-diagnose #$NUMBER`
- `2` — gh/jq fetch 失敗(#186)或 manifest 損毀/格式錯(0-byte / 非 JSON object / 缺 `files` array,#189)→ 資料層失敗,重跑 `/idd-diagnose #$NUMBER` 重建 manifest

下游 skill 看到 exit 1 時:**warn 但不 abort**(讓使用者決定要不要先 refresh 再 implement)。實作期引用 attachment 一律用 repo 相對 path(`.claude/.idd/attachments/issue-NNN/檔名`),不重複 paste 全文。

### Step 1.5: Resolve Extra Requirements

合併三個來源的「額外要求」，記錄成 `EXTRA_REQUIREMENTS` 字典供 Step 2 / Step 3 使用：

| 來源 | 範例 | 用途 |
|------|------|------|
| `--with-skill <name>` flag | `--with-skill perspective-writer` | Step 3 的 GREEN 階段呼叫該 skill 而非直接 Edit |
| `--extra "<text>"` flag | `--extra '500–800 字、避免 em dash'` | 自由文字額外約束，寫入 Implementation Plan |
| Diagnosis Strategy 中的「透過 X」/「via X」/「使用 X-skill」模式 | Strategy item: "新增 news_release.md（**透過 perspective-writer 撰寫**）" | 自動偵測，避免使用者每次都要重打 flag |

```python
# Pseudocode
extra_requirements = {
    "with_skill": parse_flag("--with-skill") or detect_in_diagnosis("透過|via|使用 (\S+)\s*skill"),
    "extra_text": parse_flag("--extra"),
}
```

#### 行為差異

| `with_skill` 是否設定 | Step 3 GREEN 行為 |
|----------------------|-------------------|
| 未設定 | 直接 Edit / Write 完成該 strategy item |
| 已設定 | 在 GREEN 階段 `Skill(skill="<name>", args="<strategy item description + extra_text>")`；該 skill 完成寫檔後，idd-implement 接手 commit + checklist |

#### 鐵律

- **不可靜默忽略 extra requirements**：若 `--with-skill` 設了但 GREEN 階段沒呼叫該 skill，視為違規 — Step 5 checklist sync 時必須能驗證 sub-skill 確實有跑（看 Skill 工具呼叫 log 或檔案內容對比）
- **Diagnosis 自動偵測優先級低於 explicit flag**：若 flag 給 perspective-writer 但 diagnosis 沒提，仍要跑；若 flag 沒給但 diagnosis 寫了「透過 X」，視同 flag 給了
- **Spectra 路徑（SDD-warranted complexity）忽略 `--with-skill`**：spectra-apply 自己有 sub-skill orchestration，不疊兩層

#### 為什麼要這個 flag

idd-implement 是 **orchestration**（issue tracking、plan、checklist、body sync），具體「**怎麼**寫」是另一件事。當 deliverable 是 prose（新聞稿、論文段落、信件）時，呼叫 perspective-writer 套用 voice 模型 + anti-pattern 檢查，比直接 Edit 寫得更穩。當 deliverable 是 code 時通常不用 sub-skill；但若 issue 要求「跟 X-skill 的測試模式一致」，flag 也派上用場。

歷史脈絡：`kiki830621/collaboration_gukai#4` 第一次出現「idd-implement × perspective-writer」整合需求時，當下用 free-form Implementation Plan bullet 寫「透過 perspective-writer 撰寫」hack 過去；但 skill 沒明文支援，沒辦法在 checklist 階段驗證 sub-skill 有跑。本 flag 把這個整合升格為 first-class feature。

---

### Step 2: 列出變更清單並 comment 到 issue

根據 diagnosis 的 strategy 與 Step 1.5 的 `EXTRA_REQUIREMENTS`，列出具體要改的檔案：

```markdown
## Implementation Plan

- [ ] 修改 src/foo.ts — {改什麼}
- [ ] 修改 src/bar.ts — {改什麼}
- [ ] 新增 tests/foo.test.ts — {測什麼}

### Extra Requirements (if any)
- **With-skill**: `/perspective-writer` （GREEN 階段呼叫，不直接 Edit）
- **Extra**: 500–800 字繁體中文；避免 em dash；套用 Decision guardrails (#42 issue body)
```

**鐵律**：
- 若 Step 1.5 解出 `with_skill` 或 `extra_text` 不為空，**必須**寫到 `### Extra Requirements` 段落 — 不寫 = Step 5 sync 時無法驗證
- 若兩者皆空，整個 `### Extra Requirements` 段可省略

**Scope check**: 清單裡的每一項都能對應到 issue 的某個要求？
- 對應不上 → 移除，或開新 issue
- Issue 的要求沒被覆蓋 → 補上

**Comment 到 issue**（留下實作計畫的紀錄）：

```bash
gh issue comment $NUMBER --repo $GITHUB_REPO --body "$IMPLEMENTATION_PLAN"
```

### Step 2.5: Bootstrap TodoList（non-Spectra case）

**判斷 Complexity routing**：讀最新的 diagnosis comment 的 `### Complexity` 欄位（v2.36.0+ 三路；v2.50+ 加 Layer V variant）：

> **v2.50+ Parser 規則**：verdict 文字可能含 ` via X` 後綴(例如 `Plan via Layer V`),parser 必須提取 canonical tier。實作:
>
> ```python
> raw_complexity = match_group_after("### Complexity\n").strip()
> canonical_tier = raw_complexity.split(" via ")[0].strip()  # "Plan via Layer V" → "Plan"
> # bare "Plan" / "Simple" / "Spectra" / "SDD-warranted" 都不含 " via ",backward compat 保留
> ```
>
> 對應 spec Requirement: Routing parsers SHALL recognize Plan via Layer V verdict。

| Canonical tier | 行為 |
|-----------|------|
| `Simple` | ✅ 本 step 啟動 TaskList 追蹤每個 checklist item |
| `Plan` (含 `Plan via Layer V`) | ✅ 同 Simple — TaskList 啟動。**注意**：使用者通常透過 `/idd-plan #NNN` 呼叫進來，approval gate 已在 idd-plan 處理完，本 skill 直接走 TDD loop。若使用者直接呼叫 `/idd-implement` 而 Complexity=Plan，**先提示**「Complexity 判定為 Plan，建議改走 `/idd-plan #NNN` 進入 approval gate；繼續直接 implement 等於跳過 Plan tier 的 deliberation 價值」並用 AskUserQuestion 確認 continue/abort。`Plan via Layer V` 同樣行為(routing 一致),只是 verdict 標記提示這是 Layer V 觸發 |
| `Spectra` | ⏭ 跳過本 step（由 `spectra-apply` 管 `openspec/changes/<name>/tasks.md`）|
| `SDD-warranted` (legacy alias) | ⏭ 跳過本 step — 視同 `Spectra` 處理（v2.36.0+ backward compat）|
| _(missing / unclear)_ | ✅ 預設當 Simple，啟動 TaskList（保守作法）|

**Simple / Plan case 執行**：

1. 從 Implementation Plan（Step 2 剛 comment 的）擷取每個 `- [ ]` bullet 當 task subject
2. 對每個 bullet 呼叫 `TaskCreate`，subject 用 bullet 第一行、description 用完整 bullet（含子項）
3. 保留 task IDs 的映射表（`bullet_index → task_id`），之後用來 `TaskUpdate`

> **為什麼用 harness-level TaskList 而不是只靠 comment checkbox?**
> Comment checkbox 是**紀錄**，TaskList 是**即時狀態**。TaskList 讓進度在 UI 可視化、session 中斷不會丟狀態、完成一項就打勾。兩者並存：TaskList 是工作中的 source of truth，`## Implementation Complete` comment 是工作後的不可變紀錄。

### Step 3: TDD 執行 + Task tracking（v2.90.0+ #209: superpowers delegation）

**Pre-flight（code 變更項必經；適用範圍與例外見下段）** — per spec `superpowers-integration`「Dual pre-flight at delegation sites」：

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/check-plugin-presence.sh" \
  claude-plugins-official superpowers test-driven-development || exit 1
```

缺 plugin 或缺目標 skill → helper 印出含一步安裝指令（`claude plugin install superpowers@claude-plugins-official`）的錯誤，**立即 abort**。不做 vendored fallback、不 silent degrade（#209 D2）— superpowers 是 install-time hard dependency（plugin.json `dependencies` 已宣告，正常安裝下必在；缺席代表安裝壞了，該修安裝而不是繞過紀律）。

**適用範圍（#209 R1 verify F8）**：pre-flight 針對會走 TDD delegation 的 code 變更項；若本次變更清單**全部**屬下方「IDD 專屬路由例外」（純 prose / `with_skill`），此 pre-flight 可跳過 — 該路由本來就不 invoke superpowers。**注意（F10 → #212 已解）**：pre-flight 現亦查 enabled 狀態 — disabled 會在 pre-flight 即 exit 3 並印 enable 指令；CLI 缺席時 graceful degrade 回磁碟檢查。

每個變更項依序執行：

0. **TaskUpdate → `in_progress`**（開始做這一項之前）

1. **TDD 執行 = `superpowers:test-driven-development`（canonical process source）**

   invoke `Skill(skill="superpowers:test-driven-development")`，依該 skill 的 RED → GREEN → REFACTOR 紀律完成本變更項的測試先行與最小實作。IDD 不再內嵌自己的 TDD 步驟敘述 — 執行框架以 superpowers 為 single source（同 idd-verify 依賴 pai canonical 引擎的先例，#209 D3）。

   **Wrapper 補充紀律（issue-anchored，superpowers 結構上無法涵蓋 — #209 R2 verify）**：測試描述用 **issue 的語言**（superpowers 是 issue-agnostic，不知道當前 issue 語彙）；commit 前**全套件**測試綠（上游 GREEN checklist 已含 "All tests pass"，此處為 IDD 端再保險，防 collateral regression）。

   **IDD 專屬路由例外（不 delegate）**：
   - **deliverable 是 prose**（信件、新聞稿、論文段落等非 code 文本）：跳過正式測試，改用 perspective-writer 的 anti-pattern checklist 作驗收 gate
   - **Step 1.5 設了 `with_skill`**：呼叫該 skill 完成寫檔，不直接 Edit
     ```python
     # 範例：with_skill="perspective-writer"
     Skill(
       skill="perspective-writer:perspective-writer",
       args=f"{strategy_item_description}. Extra: {extra_text}. Issue: #{NUMBER}"
     )
     ```
     Sub-skill 完成後 idd-implement 接手後續步驟（commit / checklist update）

2. **Commit**（IDD wrapper 紀律，不 delegate）
   ```bash
   git add {changed files}
   git commit -m "fix: {description} (#NNN)"
   ```

3. **TaskUpdate → `completed`**（確認該項真的做完了才打勾）

**鐵律**：

- 測試還在 red → 不能 `completed`
- 只改了一半、等使用者確認 → 維持 `in_progress`
- 完全不做了（scope 調整、won't fix）→ 用 `TaskUpdate` 改 subject 加 `[SKIP]` 前綴，維持 `pending` 或改 `deleted`；之後在 `## Implementation Complete` comment 裡寫成 `- [~]` 或 `- [-]`（見 CLAUDE.md Checklist Conventions）

### Step 4: Scope 守衛

實作過程中發現的問題：

| 發現 | 處理 |
|------|------|
| 不相關的 bug | 開新 issue，繼續 #NNN |
| 不相關的 code smell | 開新 issue，繼續 #NNN |
| #NNN 的前置依賴 | 確認是否 blocker。是 → 先處理依賴；不是 → 記錄在 issue comment |
| 比預期更大的改動 | 停下來，回到 diagnosis 重新評估 |

**鐵律**：不在 #NNN 的 branch 上修不相關的東西。

### Step 5: Checklist Sync + 完成確認

所有變更清單項目完成後：

**Step 5a: Checklist Sync**

`## Implementation Complete > ### Checklist` 在 v2.73.0+ 是 **authoritative_source winner**(priority 1 in [`rules/append-vs-modify.md`](../../rules/append-vs-modify.md))— 一旦本 Step 寫回此 section,所有 downstream gate(`idd-close` Step 0 / `idd-verify` checklist scan / `idd-update` body sync gate)都以該 section 為 implementation truth source,Strategy / Implementation Plan 的 `- [ ]` 視為 superseded snapshot 不再 gate-block。 若本 Step 跳過(無 Implementation Complete > Checklist),downstream gate fall back legacy scan all sources(保留 backward compat,但 Strategy/Plan checkbox 會被視為「未完成」可能 refuse close)。

呼叫 `TaskList` 取當前所有 task 狀態，對照 Implementation Plan 的 bullet，把最終狀態寫回 `## Implementation Complete` comment 的 checkbox：

| TaskList status | Comment checkbox | 意義 |
|-----------------|------------------|------|
| `completed` | `- [x]` | 做完，測試通過 |
| `in_progress` | `- [ ]` | ⚠️ 還沒做完——**不該走到 Step 5** |
| `pending` | `- [ ]` | ⚠️ 還沒開始——**不該走到 Step 5** |
| subject 含 `[SKIP]` | `- [~]` | 刻意跳過（須在 comment 附說明原因）|
| `deleted` | `- [-]` | 決定不做（scope 調整 / won't fix）|

**鐵律**：若 TaskList 還有 `pending` 或 `in_progress` 的 task，**停下**——回到 Step 3 做完，或明確改成 `[SKIP]` / `deleted` 並說明原因。不能用 `- [x]` 假裝做完了。

```bash
git status --short
git diff --stat HEAD~{N}
```

**Step 5b: 完成前驗證（v2.90.0+ #209: superpowers delegation）**

Pre-flight（同 Step 3 的 dual pre-flight 契約，缺席 fail-fast）：

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/check-plugin-presence.sh" \
  claude-plugins-official superpowers verification-before-completion || exit 1
```

**適用範圍（同 Step 3，#209 R2 verify）**：純 prose / `with_skill` 變更清單的 invocation 不經 superpowers delegation — 本 pre-flight 一併跳過，完成前驗證改用 perspective-writer anti-pattern checklist 或 sub-skill 自身驗收。

通過後 invoke `Skill(skill="superpowers:verification-before-completion")` 執行完成前驗證紀律。驗證框架 delegate 給 superpowers；以下 **IDD wrapper 檢查**保留（issue-anchored，superpowers 不覆蓋）：

- 每個 commit 都引用了 #NNN？
- 變更範圍跟 diagnosis 的 strategy 一致？
- 沒有超出 scope 的改動？
- TaskList 最終狀態與 `## Implementation Complete` comment 的 checkbox 一致？

**如果有產出圖表**，上傳到 attachments release：

```bash
# 讀取 .claude/issue-driven-dev.local.json 的 attachments_release 設定
gh release upload $ATTACHMENTS_RELEASE {figure_files}.png \
  --repo $GITHUB_REPO --clobber
```

圖片 URL 格式：`https://github.com/$GITHUB_REPO/releases/download/$ATTACHMENTS_RELEASE/{filename}.png`

**Comment 實作摘要到 issue**（含圖片）：

```bash
gh issue comment $NUMBER --repo $GITHUB_REPO --body "$(cat <<'EOF'
## Implementation Complete

### Checklist (synced from TaskList)
- [x] {plan item 1} → commit {hash}
- [x] {plan item 2} → commit {hash}
- [~] {plan item 3} — skipped: {reason why we chose not to do this now}
- [-] {plan item 4} — won't fix: {why this is out of scope}

> Legend: `- [x]` done · `- [~]` skipped (may revisit) · `- [-]` won't fix (scope)
> `idd-close` will refuse to close if any `- [ ]` remains in this checklist.

### Changes
- {commit 1 hash}: {description}
- {commit 2 hash}: {description}

### Files Changed
{git diff --stat output}

### Figures (if any)

**鐵律：每張圖下方必須附內容說明**。圖不會自己解釋自己——只貼圖沒文字，讀者需要回去翻 script 才能理解。說明必須包含三個要素：

1. **資料**：N、變項、組別、誤差線意義（圖上看不到的資訊要補）
2. **統計**：檢定方法、p-value、effect size、CI（若有）
3. **結論**：一句話說明圖在講什麼（方向、顯著性、實務意義）

格式：

```markdown
![{description}](https://github.com/$GITHUB_REPO/releases/download/$ATTACHMENTS_RELEASE/{filename}.png)

**圖 X. {Figure title}** — {資料描述}。{統計結果}。{結論一句話}。
```

實際範例：

```markdown
![5-group total score](https://.../fig1.png)

**圖 1. 5-group 記憶表現比較** — 每組 N=13（Speaker / NN / NY / YN / YY），誤差線 ± SE。ANCOVA (group + MS_c) 中 RobotAgent contrast β=+1.09, p=.005；加 Age + MoCA 後 p=.0005。Speaker (53.8%) 顯著低於 Exp2 四組平均 (71.0%)，差距 17 個百分點——老師「Speaker 最佳」假設被反駁。
```

若圖是探索性/視覺化、沒跑特定檢定：說明仍要寫圖呈現的模式（何者高何者低、分布特徵）與是否符合主結論。

### Scope Compliance
{是否有超出範圍的改動，如有則說明}

### Next: verification pending
EOF
)"
```

### Step 5.5: Open PR (PR path only, idempotent)

**Skip if direct-commit path was chosen in Step 0.5.**

Idempotent — if a PR already targeting `$BRANCH` is open, skip creation. This makes orchestration safe: `idd-all` may have pre-created a PR; verify-fix iterations re-running idd-implement won't duplicate.

```bash
# Re-confirm: only proceed if PR path
[ "$PATH_CHOICE" != "pr" ] && exit 0

# Idempotency check
EXISTING_PR=$(gh pr list --repo "$GITHUB_REPO" --head "$BRANCH" --state open --json number -q '.[0].number')
if [ -n "$EXISTING_PR" ]; then
    echo "→ PR #$EXISTING_PR already open for $BRANCH; skipping creation."
    exit 0
fi

git push -u origin "$BRANCH"

PR_TITLE=$(gh issue view "$NUMBER" --repo "$GITHUB_REPO" --json title -q .title)

PR_BODY=$(cat <<EOF
Refs #${NUMBER}

## Summary
{from issue title + Implementation Plan}

## Checklist
- [x] Diagnose
- [x] Implement (${COMMIT_COUNT} commits)
- [ ] Verify (run /idd-verify #${NUMBER})
- [x] **Verify-gated**: post-verify PASS = ready to merge → after merge, run /idd-close to finalize this issue (manual gate + closing summary; no auto-close trailer)

---
Generated by /idd-implement on PR path. **Do NOT add a GitHub close trailer** (Closes/Fixes/Resolves) — IDD discipline requires manual /idd-close after merge to enforce checklist gate + closing summary.
EOF
)

gh pr create --title "$PR_TITLE" --body "$PR_BODY" \
    --base "$DEFAULT_BRANCH" --head "$BRANCH" --repo "$GITHUB_REPO"
```

完整 PR body template + branch naming + 禁止 trailers 的理由見 [pr-flow.md](../../references/pr-flow.md)。

### Step 5.7: Sister Bug Sweep (v2.44.0+, kiki830621/ai_martech_global_scripts#526)

**Per IC_R011 follow-up filing checkpoint** (see [`references/ic-r011-checkpoint.md`](../../references/ic-r011-checkpoint.md))。

**Trigger condition**: 在 chain to /idd-verify (Step 6) 前，review session log from Step 1 (Read Issue) through Step 5.5 (PR opened, if applicable) for sister-bug discoveries surfaced during TDD execution (Step 3) — manual reproduction often reveals same-root-cause sister bugs in adjacent files. Empty list 是合法結果，但 step 本身不可省略。

**Per-step deviation**:
- **Reproduction trace evidence**: surface candidates from session log + grep paths + TDD reproduction trace (not just diffs). 2026-05-03 cluster pattern `#510 → #518 → #520` (gen_*.R / fix_wiser / _build.R, 3 separate same-pattern bugs each required user manual reminder to file) motivates the SHALL strength here — without mechanical checkpoint, AI spirit-alignment drifts.
- **Source footer** (per canonical §7): each filed issue body MUST contain `**Source**: surfaced during /idd-implement #$NNN reproduction (Step 5.7)`.
- **Chain manifest write** (additive, v2.55+ #44 / v2.60+ #46 schema v2): when chain context is active, also append a machine-readable entry per [`references/spawn-manifest.md`](../../references/spawn-manifest.md). Sister bugs from same-cause reproduction are typically `same_skill=true`. Root id: prefer `IDD_CHAIN_CURRENT_ROOT_ID` env var, fallback to `$NNN`; if both unset/empty, skip manifest write explicitly (defensive guard per #46 L2):

  ```bash
  ROOT_ID_FOR_MANIFEST="${IDD_CHAIN_CURRENT_ROOT_ID:-${NNN:-}}"
  if [ -n "$ROOT_ID_FOR_MANIFEST" ]; then
    bash "$CLAUDE_PLUGIN_ROOT/scripts/manifest-append.sh" \
      "$REPO_ROOT" "$NEW_ISSUE" "idd-implement" "Step 5.7 sister bug sweep" \
      "sister-bug" "$item_same_file" "true" "$item_title" "$ROOT_ID_FOR_MANIFEST" \
      2>/dev/null || true   # silent skip if no manifest (chain context inactive)
  fi
  ```

**Audit trail target**: `### Sister Bugs Filed (mid-impl, v2.44.0+ #526)` in Implementation Complete comment (PATCH the Step 5-posted comment to append this section per canonical §4.1 heading conventions). **`(category: audit-block-append, scope: "### Sister Bugs Filed")` per [`rules/append-vs-modify.md`](../../rules/append-vs-modify.md)** — adds new audit block to named section without modifying existing Implementation Complete prose.

**Default behavior (v2.72.0+)**: File by default per canonical §1.1. Skip requires 3-category taxonomy per canonical §1.4.

提示下一步：`/issue-driven-dev:idd-verify #NNN`

## Commit 規範

> **User-facing canonical**：[`rules/commit-issue-reference.md`](../../rules/commit-issue-reference.md)（#214）— 四條鐵律以該檔為準。

```
<type>: <description> (#NNN)
```

- type: `fix` / `feat` / `refactor` / `docs` / `test` / `chore`
- description: 用 issue 的語言描述改了什麼
- **必須**引用 issue：用 `(#NNN)` 或 `Refs #NNN`（會產生 cross-link 但**不會** auto-close）

### 禁止用 `Closes` / `Fixes` / `Resolves` trailer

**Do NOT** use GitHub 的 auto-close trailers in IDD commits:

```
❌ fix: resolve foo (#42)\n\nCloses #42
❌ fix: resolve foo\n\nFixes #42
❌ fix: resolve foo\n\nResolves #42
✅ fix: resolve foo (#42)
✅ fix: resolve foo — Refs #42
```

**為什麼禁止**：

1. **Auto-close 繞過 `idd-close` 的 Step 0 Checklist Gate Check**。GitHub 直接把 issue closed，`idd-close` 從未執行，沒人驗收 `Strategy` / `Implementation Plan` 的 checkbox 狀態——這違反 v2.17.0 的核心契約「沒打勾就不關」。
2. **沒有 Closing Summary**。auto-close 只改 issue state，不 post 任何 comment。3 個月後回來看 issue 只會看到 diagnosis + implementation plan，然後突然 closed——沒有 Solution / Verification / Root Cause 的最終紀錄。
3. **Issue 流程的 audit trail 斷裂**。IDD 的承諾是「每個 issue 都有 verified resolution」。auto-close 跳過這層驗證，變成「實作完就算結案」，退化成純 GitHub workflow。

### 正確的 close 流程

close 一律透過 `/idd-close #NNN` skill 走：

1. `idd-close` Step 0 掃 checklist gate
2. 若有未勾 todo → refuse（v2.17.0 行為）
3. 若全部勾完 → post Closing Summary
4. 最後由 skill 呼叫 `gh issue close` 關閉

這樣 gate 和 summary 都有保障，而且 issue 仍然會被實際關掉。

### 如果不小心用了 trailer 怎麼辦

1. Push 之後 GitHub 立刻 auto-close — 來不及挽救
2. 補救做法：
   - 仍然走 `/idd-close` 的精神，用 retroactive mode：post 一個標明 `(retroactive — auto-closed via Closes trailer)` 的 Closing Summary，確保 audit trail 完整
   - 不要 reopen → re-close，這是 noise
3. Amend commit 拿掉 trailer 只在 **commit 尚未 push** 時可行；push 之後 trailer 的 side effect（auto-close）無法 undo

**歷史脈絡**：`Closes` trailer 看起來很方便，#1/#2/#6 的 zombie issue 就是因為**沒用** trailer 而堆積 26 天。但 v2.17.0 introduced gate check 後，trailer 的「方便」變成了 gate bypass。正確的合成：**用 skill 關 issue**，skill 會負責既 enforce gate 又實際 close 掉（透過 `gh issue close`），兩全其美。

## Auto-Update

Implementation comment 完成後，自動執行 `idd-update` 更新 issue body 的 Current Status（phase → `implemented`）。

## Next Step

實作完成後，進入 `verify`：

```
/issue-driven-dev:idd-verify #NNN
```
