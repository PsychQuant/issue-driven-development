---
name: idd-all
description: |
  自動串連 IDD 完整 workflow（issue → diagnose → implement → verify），按 pr_policy 解析 path 與 interaction 兩軸：PR + unattended（自動化、/loop friendly）或 direct-commit + attended（HITL、user 在 keyboard，sub-skill AskUserQuestion 自然 fire）。停在 verified 等 user 自己 close（永不 auto-close）。
  Use when: 想一次跑完整條 IDD pipeline、信任 6-AI verify 會抓錯、希望 fire-and-forget；HITL 模式則用於 solo repo 想被 sub-skill 諮詢的情境。
  防止的失敗：手動跑 5 個 idd-* skill 太繁瑣、忘記中間某一步、orchestration 一致性。
argument-hint: "[#NNN | 'issue description'] [--pr | --no-pr] [--cwd /path/to/clone] (empty = interactive; --no-pr 觸發 HITL direct-commit + attended)"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
  - Bash(grep:*)
  - Bash(find:*)
  - Read
  - Glob
  - Grep
  - AskUserQuestion
  - Skill
---

# /idd-all — 自動 IDD Pipeline

把 idd-issue → idd-diagnose → idd-implement → idd-verify 串成一條自動跑的鏈。**Mode 由 `pr_policy` config 與 `--pr/--no-pr` flag 共同推導**：PR mode 在 feature branch + 開 PR + sub-skill unattended；direct-commit mode 留在當前 branch + 不開 PR + sub-skill attended。停在 verified 讓 user 親自 close — **不論 mode 都不 auto-close**。

## 核心原則

> Orchestrator skill 的 contract:**便利不能犧牲安全,attended 與否是模式而非預設**。
>
> - **Two-axis mode resolution**: idd-all 在 Phase 0.5 從 `pr_policy` config + `--pr/--no-pr` flag 解析 `(path, interaction)` tuple — 兩軸從同一 source 推導,避免 duplicate config surface。完整 algorithm 見 [pr-flow.md](../../references/pr-flow.md)。
>   - `(PR, unattended)`: 強制 feature branch、push、開 PR;sub-skill 收到 `UNATTENDED MODE` directive 抑制 `AskUserQuestion`。**v2.40.0 既有 caller(如 `/loop`)的 default 行為**。
>   - `(direct-commit, attended)`: 留在當前 branch、不 push、不開 PR;sub-skill 不收 unattended hint,native attended 行為(`AskUserQuestion`、`EnterPlanMode`、`Park/Apply` prompt)自然 fire。HITL 場景。
> - **Attended assumes user in session**: attended interaction 模式下,idd-all **不**對 sub-skill `AskUserQuestion` / `EnterPlanMode` prompt 設任何 silent timeout。user 沒回應就一直等。Attended mode = user 在 keyboard 是契約前提;若 user 預期不在,該選 unattended。
> - **Branch behavior follows path**: PR mode 從 default branch 開 `idd/<N>-<slug>` feature branch;direct-commit mode 留在 user 當前 checkout 的 branch(可能是 main、可能是 feature branch、可能是 wip/foo)。
> - **Verify is the terminal phase regardless of mode**: 不論 PR 或 direct-commit,idd-all 都停在 Phase 6 report,**永不**自動跑 `idd-close`。Closing summary 含 root cause + solution narrative,該由人寫才有審計價值。
> - **Fail-safe escalation**: 遇到 ambiguity 寧可 abort,絕不亂猜 — 但 SDD path 預設是「文件化 assumption 後繼續」(見 Phase 3b),不是 abort。Abort 是最後手段。

## 與其他 idd-* skills 的關係

| Skill | 模式 | 用途 |
|-------|------|------|
| `idd-issue/diagnose/implement/verify/close` | Atomic — 手動逐步 | 細緻控制、需要中途插手 |
| **`idd-all`** | **Orchestrator — 一鍵跑完** | 信任 pipeline、想 fire-and-forget |

idd-all 不取代 atomic skills,而是包它們。每個 phase 仍透過 `Skill(skill=...)` 呼叫對應的 atomic skill,所有 sub-skill 的 stage TaskList、auto-update、IDD 紀律都繼承下來。

## Configuration

從 `.claude/issue-driven-dev.local.md` frontmatter 讀 `github_repo`。如不存在,呼叫 `idd-issue` 流程會自動處理。

## Execution

### Step 0: Bootstrap Stage Task List(強制)

**動任何事之前**先用 `TaskCreate` 建 stage-level todo list:

```
TaskCreate(name="preflight", description="Phase 0: 解析 args(含 --pr/--no-pr/--cwd)、gh auth、resolve target repo")
TaskCreate(name="resolve_mode", description="Phase 0.5: 從 pr_policy + flag + fork detection 解析 (path, interaction) tuple,印 notice line。PR mode 才檢查 git clean + on-default-branch + 建 feature branch;direct-commit mode 留在當前 branch。")
TaskCreate(name="ensure_issue", description="Phase 1: 若 from-scratch 則跑 idd-issue; from-issue 則 verify issue 存在")
TaskCreate(name="diagnose", description="Phase 2: 跑 idd-diagnose,讀回 complexity 判定")
TaskCreate(name="implement_or_sdd", description="Phase 3: Simple/Plan → idd-implement; Spectra → spectra-discuss → spectra-propose → spectra-apply。Args 含 UNATTENDED MODE 與否依 Phase 0.5 解析的 interaction 軸決定。")
TaskCreate(name="verify_loop", description="Phase 4: idd-verify; blocking findings 處理(unattended 自動修復最多 2 round, attended 把控制交回 user); follow-ups → 開新 issue")
TaskCreate(name="open_pr", description="Phase 5: PR mode → git push + gh pr create(body 含 Refs #N, 不含 Closes); direct-commit mode → skip,進 Phase 6")
TaskCreate(name="report_and_stop", description="Phase 6: 依 mode 顯示對應 next-step(PR → review/merge/close; direct-commit → review last N commits/close)。永不 auto-invoke idd-close。")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。

`idd-all` 內部呼叫的 atomic skill 會各自建自己的 stage TaskList(那是它們的責任),idd-all 的 task list 只追 phase-level 進度。

---

### Phase 0: Pre-flight Checks

#### Step 0.1: Argument Parsing

| 輸入 | Mode | 行為 |
|------|------|------|
| `/idd-all` | interactive | AskUserQuestion: 建新 issue 還是用既有 issue? |
| `/idd-all #19` | from-issue | 直接從 #19 進 diagnose,mode 由 Phase 0.5 解析 |
| `/idd-all #19 --pr` | from-issue, force PR | 強制 (PR, unattended) — v2.40.0 既有行為,/loop friendly |
| `/idd-all #19 --no-pr` | from-issue, force HITL | 強制 (direct-commit, attended) — user 在 keyboard,sub-skill 自然問問題 |
| `/idd-all #19 --cwd /path/to/clone` | from-issue cross-repo | 在指定 local clone 跑(不依賴 session cwd);可與 `--pr/--no-pr` 並用 |
| `/idd-all "bug: foo doesn't work"` | from-scratch | 用該字串當 issue title 進 idd-issue |
| `/idd-all path/to/spec.md` | from-scratch | 把檔案當 issue 描述進 idd-issue |

#### Step 0.2: Resolve Working Tree(v2.39.0+ 新增)

idd-all 的所有 git/gh 操作都針對單一 target repo。先解析這個 repo:

```bash
# 1. 解析 --cwd flag(per-invocation override)
CWD_FLAG=""
for arg in "$@"; do
    case "$arg" in
        --cwd=*) CWD_FLAG="${arg#--cwd=}" ;;
        --cwd)   shift; CWD_FLAG="$1" ;;
    esac
done

# 2. 確定 working tree 路徑
if [ -n "$CWD_FLAG" ]; then
    [ -d "$CWD_FLAG" ] || abort "--cwd path '$CWD_FLAG' does not exist."
    CWD="$CWD_FLAG"
else
    CWD="$(pwd)"
fi

# 3. 從 working tree 推導 GITHUB_REPO
GITHUB_REPO=$(git -C "$CWD" remote get-url origin 2>/dev/null \
    | sed -E 's#.*[:/]([^/]+/[^/]+?)(\.git)?$#\1#') \
    || abort "Could not determine github_repo from $CWD/.git/config (no 'origin' remote?)"
```

**為什麼需要 explicit `--cwd`**:Skill tool 呼叫繼承 Claude Code session-level cwd,不會跟著 mid-session `cd` 移動。跨 repo 工作(例如 thesis 在 repo A、要對 repo B 跑 idd-all)時,沒有 `--cwd` 就只能重啟 Claude Code session — 違反 unattended pipeline contract。

#### Step 0.3: Universal pre-flight gates

不論 mode,以下兩個 gate 都必須過。所有 git 操作用 `git -C "$CWD"`,所有 gh 操作用 `gh -R "$GITHUB_REPO"`。

```bash
# 1. 必須在 git repo
git -C "$CWD" rev-parse --git-dir > /dev/null 2>&1 \
    || abort "'$CWD' is not a git repository.
   Either:
     - cd to the target repo first, then re-run /idd-all
     - OR pass --cwd /path/to/local/clone"

# 2. 必須 gh auth
gh auth status > /dev/null 2>&1 || abort "gh CLI not authenticated. Run: gh auth login"
```

> **Mode-specific gates(working tree clean、on default branch)移到 Phase 0.5**:那些 gate 只在 PR mode 必須,direct-commit mode 預設留在 user 當前 branch + 容許未 commit 變更(由 user 自負其責)。

#### Step 0.4: Resolve Issue Number

- **from-issue mode**(`/idd-all #19`): 確認 issue #19 存在且 OPEN(`gh issue view 19 -R "$GITHUB_REPO" --json state -q .state`); 若 state=CLOSED → abort
- **from-scratch mode**: skip 到 Phase 1 跑 idd-issue
- **interactive mode**: AskUserQuestion 兩選一

#### Step 0.5: Resolve Mode + Conditional Branch Setup

**先解析 `(path, interaction)` tuple,再依 path 決定 branch 行為。** 完整 algorithm 見 [pr-flow.md](../../references/pr-flow.md)「`idd-all` path resolution」段。

**Resolution precedence(first match wins)**:

```
1. --pr flag                                      → (PR, unattended)
2. --no-pr flag                                   → (direct-commit, attended)
3. Fork detected (gh repo view --json isFork)     → (PR, unattended)  [override config]
4. pr_policy: always                              → (PR, unattended)
5. pr_policy: never                               → (direct-commit, attended)
6. pr_policy: ask  (or absent)                    → AskUserQuestion; first answer locks tuple
```

```bash
# 讀 pr_policy from cascading config
PR_POLICY=$(jq -r '.pr_policy // "ask"' "$CONFIG_PATH" 2>/dev/null || echo "ask")

# 1-2. Explicit flags
if   [ "$PR_FLAG" = "--pr" ];     then PATH_AXIS="PR";            INTERACTION="unattended"; REASON="flag=--pr"
elif [ "$PR_FLAG" = "--no-pr" ];  then PATH_AXIS="direct-commit"; INTERACTION="attended";   REASON="flag=--no-pr"
else
  # 3. Fork detection
  IS_FORK=$(gh repo view "$GITHUB_REPO" --json isFork -q .isFork 2>/dev/null || echo "false")
  if [ "$IS_FORK" = "true" ]; then
    PATH_AXIS="PR"; INTERACTION="unattended"; REASON="fork detected (override pr_policy=$PR_POLICY)"
  else
    # 4-5. Config
    case "$PR_POLICY" in
      always) PATH_AXIS="PR";            INTERACTION="unattended"; REASON="pr_policy=always" ;;
      never)  PATH_AXIS="direct-commit"; INTERACTION="attended";   REASON="pr_policy=never" ;;
      *)
        # 6. Ask
        ANSWER=$(AskUserQuestion "Path?" "PR (feature branch + PR + unattended)" "direct-commit (current branch + no PR + attended)")
        if [ "$ANSWER" = "PR" ]; then
          PATH_AXIS="PR"; INTERACTION="unattended"; REASON="pr_policy=ask, user picked PR"
        else
          PATH_AXIS="direct-commit"; INTERACTION="attended"; REASON="pr_policy=ask, user picked direct-commit"
        fi
        ;;
    esac
  fi
fi

# Resolved-tuple notice (mandatory — print before any state-mutating action)
echo "→ Path: ${PATH_AXIS} (${INTERACTION}) — ${REASON}"
```

**PR mode branch setup**(只在 `PATH_AXIS=PR` 執行):

```bash
if [ "$PATH_AXIS" = "PR" ]; then
  # PR-mode-only preconditions
  if [ -n "$(git -C "$CWD" status --porcelain)" ]; then
    echo "Uncommitted changes detected in $CWD. PR mode needs a clean working tree."
    git -C "$CWD" status --short
    abort "Run 'git -C $CWD stash' or commit first, then re-run /idd-all."
  fi

  CURRENT=$(git -C "$CWD" branch --show-current)
  DEFAULT=$(gh repo view "$GITHUB_REPO" --json defaultBranchRef -q .defaultBranchRef.name)
  if [ "$CURRENT" != "$DEFAULT" ]; then
    abort "$CWD is currently on '$CURRENT'. PR mode must start from '$DEFAULT'.
   Run: git -C $CWD checkout $DEFAULT"
  fi

  # Build feature branch name
  N="19"  # 從 args 或 idd-issue 結果取得
  TITLE=$(gh issue view "$N" -R "$GITHUB_REPO" --json title -q .title)
  SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' \
      | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g' \
      | cut -c1-40)
  BRANCH="idd/${N}-${SLUG}"

  if git -C "$CWD" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    # AskUserQuestion: checkout 繼續 or 用 idd/19-...-2?
    :
  fi

  git -C "$CWD" checkout -b "$BRANCH"
fi
```

**Direct-commit mode**(`PATH_AXIS=direct-commit`):

```bash
if [ "$PATH_AXIS" = "direct-commit" ]; then
  CURRENT_BRANCH=$(git -C "$CWD" branch --show-current)
  echo "→ direct-commit path: committing to ${CURRENT_BRANCH}, no PR will be opened"
  # 不檢查 working-tree clean,不檢查 on default branch
  # 不建 feature branch — 留在 user 當前 checkout
  BRANCH="$CURRENT_BRANCH"
fi
```

> **為什麼 direct-commit 不強制 clean tree / default branch**: HITL 場景下 user 可能在自己的 wip branch 上工作、可能有未 commit 的 staging — idd-all 不該擾動這些 user state。Trade-off: user 自負「commit 落在哪個 branch」的責任。
>
> **為什麼 PR mode 仍從 default branch 起跳**: PR 是給人 review 的;從 feature-on-feature 起跳的 PR diff 會包含上層 feature 的所有 commit,review noise 太大 — 應 abort 讓 user 想清楚。

---

### Phase 1: Ensure Issue Exists

```
if [ from-scratch mode ]:
    Skill(skill="issue-driven-dev:idd-issue", args="<arg from /idd-all> --target $GITHUB_REPO")
    # idd-issue 會 post issue 並 print 出 number → capture 它
    N = parse from idd-issue output
elif [ from-issue mode ]:
    # already validated in Phase 0.3
    pass
```

> **`--target` not `--cwd` for idd-issue**: idd-issue 是 read-only(只 `gh issue create`),不 touch local git。所以用 `--target $GITHUB_REPO` 即可,不需要 `--cwd`。

---

### Phase 2: Diagnose

idd-all 必須把 `--cwd "$CWD"` 傳給 idd-diagnose,否則 sub-skill 會在 Claude Code session 的 default cwd 跑(可能是錯的 repo):

```
Skill(skill="issue-driven-dev:idd-diagnose", args="#$N --cwd $CWD")
```

**讀回 complexity**:idd-diagnose 結束後 fetch issue comments,grep 最新 `## Diagnosis` 區塊的 `### Complexity` 欄位:

```bash
COMPLEXITY=$(gh issue view "$N" --json comments \
    | python3 -c "
import json, sys, re
d = json.load(sys.stdin)
diagnosis_comments = [c for c in d['comments'] if '## Diagnosis' in c['body']]
if not diagnosis_comments:
    print('UNKNOWN'); exit(0)
latest = diagnosis_comments[-1]['body']
m = re.search(r'### Complexity\n(.+?)\n', latest)
print(m.group(1).strip() if m else 'UNKNOWN')
")
```

| Complexity 值 | 下一步 |
|--------------|--------|
| `Simple` | Phase 3a: idd-implement |
| `Plan` | Phase 3a: idd-implement(unattended → Plan deliberation 跳過;attended → Plan tier `EnterPlanMode` approval gate 自然 fire) |
| `Spectra` | Phase 3b: spectra-discuss → spectra-propose → spectra-apply(unattended → 一輪收斂;attended → multi-turn 對話自然進行) |
| `SDD-warranted` (legacy alias) | 視同 `Spectra` 處理(v2.36.0+ backward compat) |
| `UNKNOWN` | **abort** — diagnose 沒判定 complexity,user 需手動釐清 |

> **Plan tier under (PR, unattended)**: Plan tier 的核心價值是 user approval via `EnterPlanMode`/`ExitPlanMode`。unattended 沒有 user 在 review plan,所以 Plan path 直接跳到 idd-implement,**在 final report 標記 `[Plan tier deliberation skipped under unattended mode]`**。
>
> **Plan tier under (direct-commit, attended)**: 不傳 unattended hint,idd-implement 進 Plan tier、`EnterPlanMode` 呈現 plan 給 user,user `ExitPlanMode` approve 後才繼續。這是 attended mode 的設計目的之一。
>
> **SDD path under (PR, unattended)**: 三步 chain `spectra-discuss → spectra-propose → spectra-apply`,每步傳 `UNATTENDED MODE` directive 抑制 `AskUserQuestion`,一輪收斂、不停 Park。
>
> **SDD path under (direct-commit, attended)**: 三步同樣 chain,但**完全不傳** unattended hint。`spectra-discuss` 多輪節奏、`spectra-propose` Step 10 Park/Apply 問題、`spectra-apply` Step 4 continue-confirmation 都自然 fire。這是 HITL 的核心場景。

---

### Phase 3a: Simple/Plan Path — idd-implement

依 Phase 0.5 的 `(PATH_AXIS, INTERACTION)` 條件組 invocation args。**Args 構造遵守「two axes derived from one source」原則**(見 spec `idd-orchestrator-modes`「Attended interaction permits sub-skill questions」requirement):

```bash
# Build args conditionally — UNATTENDED MODE directive only when interaction == unattended
IMPL_ARGS="#$N --cwd $CWD"
if [ "$PATH_AXIS" = "PR" ]; then
  IMPL_ARGS="$IMPL_ARGS --pr"
elif [ "$PATH_AXIS" = "direct-commit" ]; then
  IMPL_ARGS="$IMPL_ARGS --no-pr"
fi

if [ "$INTERACTION" = "unattended" ]; then
  # Inline directive — sub-skill suppresses AskUserQuestion / EnterPlanMode prompts
  IMPL_ARGS="$IMPL_ARGS

UNATTENDED MODE — called by /idd-all orchestrator. Suppress AskUserQuestion. If complexity is Plan, skip the EnterPlanMode approval gate and proceed straight to TDD; mark in your final comment that Plan deliberation was skipped."
fi

Skill(skill="issue-driven-dev:idd-implement", args="$IMPL_ARGS")
```

> **Why conditional, not unconditional `UNATTENDED MODE`** (Task 4.1, Requirement: "Attended interaction permits sub-skill questions"): when interaction = `attended`, idd-all MUST NOT inject the directive — `idd-implement`'s native attended-by-default behavior (Plan tier `EnterPlanMode`, mid-implementation `AskUserQuestion`) is precisely what the HITL user wants.

**`--cwd` flag is mandatory when forwarded from idd-all**: 確保 idd-implement 在跟 idd-all 同一個 local clone 跑(否則 sub-skill 跑在 session cwd,branch/commit 會 land 錯地方)。

**Branch behavior**:
- PR mode → idd-implement 看到 `--pr` flag + 已在 feature branch → reuse(Step 0.5 fork detection 直接認得)
- direct-commit mode → idd-implement 看到 `--no-pr` flag → 不再開 branch,直接在當前 branch commit

**PR creation timing**: PR mode 下,idd-implement 的 Step 5.5(PR creation)用 `gh pr list --head $BRANCH` 先查當前 branch 有沒有 open PR,有就 skip — 與 idd-all Phase 5 自然相容(idd-all 在 verify PASS 後才開 PR with verify result)。direct-commit mode 下 idd-implement 收到 `--no-pr` 不會嘗試開 PR,Phase 5 也直接 skip。

### Phase 3b: SDD Path — discuss → propose → apply (mode-aware chain)

idd-all 走 SDD path 時,**必須**串完三步:`spectra-discuss` → `spectra-propose` → `spectra-apply`(無論 mode — `spectra-propose` 本身有禁令 `NEVER invoke /spectra-apply`,所以 chain 由 idd-all 主導)。

**每步的 args 構造依 `INTERACTION` 軸條件化**(Task 4.2, Requirement: "Attended interaction permits sub-skill questions"):

> - `INTERACTION=unattended` → 每個 spectra-* args 都附加 **`UNATTENDED MODE` directive block**(下方範例的 attended-only 區段;sub-skill 看到直接抑制 `AskUserQuestion`)
> - `INTERACTION=attended` → **完全不傳** unattended hint。`spectra-discuss` 多輪節奏、`spectra-propose` Step 10 Park/Apply 問題、`spectra-apply` Step 4 continue-confirmation 都 native fire,user 在 keyboard 自然回應
>
> idd-all 不修改 spectra 任何檔案 — 全程用 args 傳指示(或不傳)override sub-skill 的 attended 預設。

#### Step 3b.1: Capture issue context for prompt

```bash
ISSUE_TITLE=$(gh issue view "$N" --repo "$GITHUB_REPO" --json title -q .title)
ISSUE_BODY=$(gh issue view "$N" --repo "$GITHUB_REPO" --json body -q .body | head -50)
DIAGNOSIS=$(gh issue view "$N" --repo "$GITHUB_REPO" --json comments \
    | python3 -c "import json,sys; cs=json.load(sys.stdin)['comments']; \
        ds=[c for c in cs if '## Diagnosis' in c['body']]; \
        print(ds[-1]['body'] if ds else '')")
```

#### Step 3b.2: Discuss

Build args conditionally — **inline comment cross-references "Attended interaction permits sub-skill questions" requirement**(Task 4.4):

```bash
DISCUSS_ARGS="Topic: ${ISSUE_TITLE} (#${N})

Context (from issue body + diagnosis):
${ISSUE_BODY}
${DIAGNOSIS}"

# Conditional: unattended only — see spec idd-orchestrator-modes,
# requirement "Attended interaction permits sub-skill questions".
if [ "$INTERACTION" = "unattended" ]; then
  DISCUSS_ARGS="$DISCUSS_ARGS

UNATTENDED MODE — called by /idd-all orchestrator.

Discipline overrides for this invocation:
- Converge in ONE round. Do NOT use AskUserQuestion to pace the discussion across multiple turns.
- If you have a strong recommendation among 2-3 options, pick it and state your reasoning.
- If multiple viable approaches exist, choose the one with the smallest blast radius and document the trade-off.
- End your output with a single line: 'Conclusion: <chosen approach in one sentence>' so the orchestrator can pass it to spectra-propose.
- Do NOT pause to ask the user — there is no user available."
fi

Skill(skill="spectra-discuss", args="$DISCUSS_ARGS")
```

Capture the conclusion line(unattended)or summary(attended)for the next step.

#### Step 3b.3: Propose

```bash
PROPOSE_ARGS="<conclusion line from Step 3b.2>

Original issue: #${N} ${ISSUE_TITLE}"

# Conditional: unattended only — see spec idd-orchestrator-modes,
# requirement "Attended interaction permits sub-skill questions".
if [ "$INTERACTION" = "unattended" ]; then
  PROPOSE_ARGS="$PROPOSE_ARGS

UNATTENDED MODE — called by /idd-all orchestrator.

Discipline overrides for this invocation:
- Skip ALL AskUserQuestion checkpoints. Make reasonable decisions and document them inline in the proposal/design artifacts.
- Step 10 'Park or Apply' question: SUPPRESS. Do NOT call spectra park. Do NOT call /spectra-apply (your guardrail at L267 still applies). Just end the workflow after artifact validation succeeds.
- If a 'plan file' check (Step 1.x) finds an existing plan, use it without asking.
- If context is insufficient, prefer making a documented assumption over asking — write the assumption explicitly in proposal.md so it can be challenged later.
- Output the final change-name on its own line as 'Change: <name>' so the orchestrator can pass it to spectra-apply."
fi
# Attended mode: spectra-propose's Step 10 Park/Apply prompt fires natively.
# If user picks Park, the chain stops here — idd-all reports the parked state and exits.

Skill(skill="spectra-propose", args="$PROPOSE_ARGS")
```

Capture the change-name line(unattended)or whatever spectra-propose prints last(attended).

#### Step 3b.4: Apply

```bash
APPLY_ARGS="<change-name from Step 3b.3>

Issue ref: #${N}"

# Conditional: unattended only — see spec idd-orchestrator-modes,
# requirement "Attended interaction permits sub-skill questions".
if [ "$INTERACTION" = "unattended" ]; then
  APPLY_ARGS="$APPLY_ARGS

UNATTENDED MODE — called by /idd-all orchestrator.

Discipline overrides for this invocation:
- Skip Step 4 continue-confirmation. Proceed directly through implementation tasks.
- If validation reveals ambiguity that would normally trigger AskUserQuestion: document the assumption in tasks.md (mark with 'ASSUMPTION:'), proceed with the most conservative interpretation, and surface it in the verify phase.
- Every commit MUST reference (#${N}) — same convention as idd-implement.
- All commits land on the branch from Phase 0.5 ('${BRANCH}')."
else
  # Attended: tell spectra-apply where commits land but let its native checkpoints fire.
  APPLY_ARGS="$APPLY_ARGS

Commits land on '${BRANCH}' (Phase 0.5 resolved branch). Native AskUserQuestion / continue-confirmation prompts may fire — user is in session."
fi

Skill(skill="spectra-apply", args="$APPLY_ARGS")
```

#### Failure handling

| Situation | Action |
|---|---|
| `spectra-discuss` doesn't emit a `Conclusion:` line | Re-prompt once with explicit format requirement; if still missing, abort with branch preserved |
| `spectra-propose` doesn't emit a `Change:` line | Same as above |
| `spectra-propose` hits a hard stop (e.g. spec validation fail it can't auto-fix) | Abort, preserve artifacts, instruct user to run `/spectra-propose` manually |
| `spectra-apply` reports tasks remaining unfinished | Continue to Phase 4 (verify) — verify will surface incompleteness |

> **Why idd-all overrides spectra defaults via args, not by modifying spectra**: spectra is a separate plugin with its own attended-by-default contract that's correct for solo use. idd-all is the one promising "unattended", so it's idd-all's responsibility to configure each sub-skill invocation to honor that promise. Args-based override keeps the boundary clean.

---

### Phase 4: Verify Loop

Args 構造同樣依 `INTERACTION` 軸條件化(Task 4.3, Requirement: "Attended interaction permits sub-skill questions"):

```bash
# Build idd-verify args conditionally — see spec idd-orchestrator-modes,
# requirement "Attended interaction permits sub-skill questions".
VERIFY_ARGS="#$N --cwd $CWD"
if [ "$INTERACTION" = "unattended" ]; then
  VERIFY_ARGS="$VERIFY_ARGS

UNATTENDED MODE — called by /idd-all orchestrator. Do not pause for AskUserQuestion; emit findings to the verify comment as usual."
fi
```

```python
for round in 1..MAX_ROUND:
    Skill(skill="issue-driven-dev:idd-verify", args=VERIFY_ARGS)

    findings = parse_verify_report(latest verify comment)

    if findings.blocking_count == 0:
        break  # PASS

    if INTERACTION == "attended":
        # User is in session — surface findings and let them decide whether to keep iterating.
        # Do NOT auto-fix in attended mode; that defeats the purpose of HITL.
        report_findings_and_exit_to_user()
        break

    # unattended path: auto-fix attempt
    if round == MAX_ROUND:
        abort_with_message("verify still failing after MAX_ROUND rounds; manual intervention needed")

    attempt_auto_fix(findings.blocking)
```

**`MAX_ROUND` defaults**: 2 for unattended (best-effort auto-recover), 1 for attended (one read-out, hand back).

**Auto-fix 策略**(unattended only — best-effort):

對每個 blocking finding,讀其描述 + suggested action,套用 Edit/Write 修正:

- 文法/拼字/字串 typo → 安全可修
- 邏輯錯誤(null check, edge case) → 嘗試但 risky
- 安全漏洞 → **不 auto-fix**,直接 abort 讓 user 處理

每個 auto-fix commit:`fix: address verify finding — {finding summary} (#$N)`

**Follow-up findings**(設計決策 #4:auto-create issues):

每個 P3/follow-up finding → 呼叫 `Skill(skill="issue-driven-dev:idd-issue", args="<title> --target $GITHUB_REPO")` 建新 issue(用 `--target` 而非 `--cwd`,因為 idd-issue read-only),body 引用本次 verify report 原文。新 issue target main(不是當前 branch)。

---

### Phase 5: Push + Open PR (PR mode only)

**Direct-commit mode short-circuit** (Task 3.2):

```bash
if [ "$PATH_AXIS" = "direct-commit" ]; then
  echo "→ direct-commit path: skipping push + PR"
  # Jump directly to Phase 6
  goto Phase 6
fi
```

**PR mode** (preserves v2.40.0 behavior — Task 2.2):

```bash
git -C "$CWD" push -u origin "$BRANCH"

# 組 PR body
PR_BODY=$(cat <<EOF
Refs #${N}

## Summary
{從 issue title + diagnosis 的 Strategy 摘要}

## Verification
6-AI cross-model verification PASS(Agent Team + Codex xhigh)。詳見 issue #${N} 的 Verify comment。

## Checklist
- [x] Diagnose ✓
- [x] Implement(${COMMIT_COUNT} commits)
- [x] Verify ✓
- [ ] **Pending: human review of this PR + /idd-close after merge**

## Related
{若有 follow-up issues,列出 #N #M ...}

---
🤖 Generated by /idd-all. **Do NOT add 'Closes #${N}'** — IDD discipline requires manual /idd-close after merge to enforce checklist gate + closing summary.
EOF
)

gh pr create -R "$GITHUB_REPO" --title "$PR_TITLE" --body "$PR_BODY" \
    --base "$DEFAULT" --head "$BRANCH"
```

> **絕對不能在 PR body 用 Closes/Fixes/Resolves trailer**。理由見 idd-implement skill 裡的 trailer 禁令說明 — auto-close 會繞過 idd-close 的 checklist gate 和 closing summary。

---

### Phase 6: Report and Stop (mode-aware)

**Verify is the terminal phase regardless of mode** (Task 5.1) — `idd-all` 在兩個 mode 下都停在這裡,**永不**自動跑 `/idd-close`。

#### PR mode report

```
✓ idd-all complete (PR mode)

  Issue:        #${N} — ${TITLE}
  Branch:       ${BRANCH}
  Commits:      ${COMMIT_COUNT} (implementation + ${FIX_ROUND_COUNT} verify-fix rounds)
  PR:           ${PR_URL}
  Verify:       PASS
  Follow-ups:   ${FOLLOWUP_ISSUE_LIST or "(none)"}

Next: review PR ${PR_URL}, merge, then run /idd-close #${N}
```

#### direct-commit mode report

```
✓ idd-all complete (direct-commit mode — HITL)

  Issue:        #${N} — ${TITLE}
  Branch:       ${BRANCH}  (commits landed on user's current checkout)
  Commits:      ${COMMIT_COUNT} (implementation + ${FIX_ROUND_COUNT} verify-fix rounds)
  Verify:       ${VERIFY_STATE}  (PASS, or findings deferred to user in attended mode)
  Follow-ups:   ${FOLLOWUP_ISSUE_LIST or "(none)"}

Next: review last ${COMMIT_COUNT} commits (git log -${COMMIT_COUNT}), then run /idd-close #${N}
```

**STOP**。不 auto-merge(PR mode)、不 auto-close(both modes)。user 可能想看 diff、跑 CI、找其他人 review、或在 attended mode 下對 verify findings 做進一步處理。

---

## Failure Modes(每個都該明確 abort,不該 swallow)

| 情況 | 行為 |
|------|------|
| `--cwd /path` 不存在 | Phase 0.2 abort,提示 user 確認 path |
| `--cwd` 給的目錄沒 origin remote | Phase 0.2 abort,顯示 cd path 與 git config 修法 |
| 沒給 --cwd 且 session cwd 不是 git repo | Phase 0.3 abort,訊息含「pass --cwd /path」alternative |
| Working tree dirty | Phase 0.3 abort,顯示 `git -C $CWD status` |
| Not on default branch | Phase 0.3 abort,提示 `git -C $CWD checkout $DEFAULT` |
| gh auth 沒設定 | Phase 0.3 abort,提示 gh auth login |
| Issue #N 不存在 / CLOSED | Phase 0 abort |
| Branch 已存在 | Phase 0 AskUserQuestion(checkout / -2 suffix / abort) |
| Diagnose 判定 UNKNOWN complexity | Phase 2 abort,提示手動跑 idd-diagnose |
| spectra-discuss 沒 emit `Conclusion:` line(unattended hint 失敗)| Re-prompt 一次;再失敗 abort,branch 保留 |
| spectra-propose 沒 emit `Change:` line | 同上 |
| spectra-propose 遇到 unrecoverable validation error | Phase 3b abort,artifacts 保留,提示手動 `/spectra-propose` |
| spectra-apply 留下 unfinished tasks | 不 abort — Phase 4 verify 會抓出來 |
| Verify 2 round 後仍 blocking | Phase 4 abort,留 branch 給 user 手動修 |
| `gh pr create` fail | Phase 5 abort,branch 已 push,提示手動開 PR |

abort 時:
- TaskList 標記當前 phase 為 in_progress(不要 mark completed)
- 顯示「自己手動接手」的具體命令(例:`/idd-verify #19` 或 `gh pr create ...`)
- branch 不刪除(保留進度,user 可繼續)

---

## 鐵律

- **PR mode 一律在 feature branch**。direct-commit mode 留在 user 當前 branch — 兩者都是合法 path。
- **永遠停在 verified**。不論 mode,close 是人類 checkpoint(closing summary 含 root cause + solution + verification trail,該由人寫不該由機器猜)。
- **永遠不 auto-merge PR**(PR mode)。即使 verify PASS,PR review 是另一層保險(CI、其他 reviewer、user 自己再看一次)。
- **Attended mode 沒有 silent timeout**。user 沒回應就一直等;若 user 不在,該選 unattended。
- **abort 比硬撐好**。任何 ambiguity → 停下、保留進度、告訴 user 怎麼接手。

## Examples

### Trace 1: `(PR, unattended)` — v2.40.0 regression

```
/idd-all #42 --pr
```

Phase 0.5 印 `→ Path: PR (unattended) — flag=--pr`,sub-skill args 全帶 `UNATTENDED MODE` directive。

```
✓ idd-all complete (PR mode)
  Issue:        #42 — bug: login button stops after 3 failed attempts
  Branch:       idd/42-bug-login-button-stops-after-3-faile
  Commits:      3 (implementation + 0 verify-fix rounds)
  PR:           https://github.com/owner/repo/pull/87
  Verify:       PASS
  Follow-ups:   (none)

Next: review PR https://github.com/owner/repo/pull/87, merge, then run /idd-close #42
```

`/loop` 自動化 caller 觀察行為與 v2.40.0 完全一致 — feature branch、push、PR 帶 `Refs #42`、無 `Closes`、停在 verified。

### Trace 2: `(direct-commit, attended)` — HITL 場景

`.claude/issue-driven-dev.local.json` 含 `"pr_policy": "never"`,user 在 keyboard:

```
/idd-all #42
```

Phase 0.5 印 `→ Path: direct-commit (attended) — pr_policy=never`,sub-skill args **不帶** unattended hint。

中間流程:
- Phase 2 diagnose 判定 `Plan` → Phase 3a `idd-implement` 進 Plan tier、`EnterPlanMode` 把 plan 呈現給 user → user `ExitPlanMode` approve 後才繼續 TDD
- Phase 4 verify 找到 1 個 P3 finding → 不 auto-fix(attended mode trade-off),直接 surface 給 user

```
✓ idd-all complete (direct-commit mode — HITL)
  Issue:        #42 — bug: login button stops after 3 failed attempts
  Branch:       main  (commits landed on user's current checkout)
  Commits:      3 (implementation + 0 verify-fix rounds)
  Verify:       PASS with 1 P3 finding (deferred to user)
  Follow-ups:   (none)

Next: review last 3 commits (git log -3), then run /idd-close #42
```

無 push、無 PR、commits 直接落在 main(或 user 開頭 checkout 的 branch)。

### 從零開始 — 文字描述

```
/idd-all "bug: login button stops responding after 3 failed attempts"
```

跑 idd-issue 建 issue #N → Phase 0.5 解析 mode → 後續依 mode 走 PR 或 direct-commit path。

### 從零開始 — 用 spec 檔

```
/idd-all docs/specs/new-feature.md
```

把 spec 內容當 issue body 跑 idd-issue → 後續同上。

### 跨 repo invocation(v2.39.0+)

當 Claude Code session 的 cwd 不在目標 repo(例如同時在 thesis 工作要對 ooxml-swift 跑 idd-all):

```
/idd-all #43 --cwd /Users/che/Developer/macdoc/packages/ooxml-swift --pr
```

idd-all 在指定 local clone 跑完整 pipeline。`--pr` 與 `--cwd` 可並用;不帶 `--pr/--no-pr` 則由 walked-up config 的 `pr_policy` 決定。

idd-all 會在指定 local clone 跑完整 pipeline,branch 開在那邊、commits land 那邊、PR 從那 push。Claude Code session cwd 不變。

---

## Auto-Update

每個 sub-skill(idd-issue / idd-diagnose / idd-implement / idd-verify)在自己的 Step N Auto-Update 都會跑 idd-update,所以 issue body 的 Current Status 會在每個 phase 後自動 sync。idd-all 不需要額外 update。

## Next Step

idd-all 結束後,user 接手 — 步驟依 resolved mode 而異。

### PR mode

```bash
# 1. Review PR
gh pr view <PR_URL>

# 2. Merge(approve 後)
gh pr merge <N> --squash  # or --merge / --rebase

# 3. Close issue with summary
/issue-driven-dev:idd-close #${N}
```

### direct-commit mode

```bash
# 1. Review last N commits (no PR to view)
git log -<N> --stat

# 2. (Optional) push if commits should land remote
git push

# 3. Close issue with summary
/issue-driven-dev:idd-close #${N}
```

兩個 mode 共通:**`/idd-close` 始終由 user 主動觸發**,idd-all 自身永不 auto-close。
