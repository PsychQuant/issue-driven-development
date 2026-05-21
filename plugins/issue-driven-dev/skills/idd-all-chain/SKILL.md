---
name: idd-all-chain
description: |
  Drive root issue + auto-emergent spawned issues through ONE cluster branch + ONE review PR.
  Recursive shell over /idd-all — sub-skill spawns (sister bug / follow-up finding / tangential / sister concern) detected via spawn manifest, chain-eligible enqueued automatically.
  Use when: root issue likely ripples (refactor with sister bugs / spec change with cross-spec impact / multi-layer feature) and you want single PR review.
  Stops at verified — never auto-close, /idd-close per issue still required.
argument-hint: "[#NNN ...] [--bfs] [--review] [--cwd /path/to/clone] e.g. '#28', '#A #B #C --bfs', '#28 --review' (--review opt-in re-opens NSQL confirmation loop at terminal report)"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
  - Bash(jq:*)
  - Bash(uuidgen:*)
  - Bash(mkdir:*)
  - Bash(rm:*)
  - Bash(mv:*)
  - Bash(cat:*)
  - Bash(echo:*)
  - Bash(shasum:*)
  - Bash(sed:*)
  - Bash(tr:*)
  - Bash(cut:*)
  - Bash(sort:*)
  - Bash(seq:*)
  - Bash(grep:*)
  - Bash(awk:*)
  - Bash(printf:*)
  - Bash(date:*)
  - Bash(head:*)
  - Bash(tail:*)
  - Bash(wc:*)
  - Bash(basename:*)
  - Bash(comm:*)
  - Read
  - Glob
  - Grep
  - AskUserQuestion
  - Skill
---

# /idd-all-chain — Auto-Emergent Multi-Issue Solve

Take 1 root issue, recursively solve any chain-eligible spawned issues (from sub-skill sister sweeps / verify follow-ups / mid-plan tangentials / sister concerns), all on **ONE cluster branch** and reviewed via **ONE PR**.

## 核心原則

> **`/idd-all-chain` is a thin shell over `/idd-all`.** 90% of pipeline logic stays in `/idd-all` (Phase 0-6 unchanged); chain shell only orchestrates the recursion + cluster branch + cluster PR.

> **Chain stops at verified, never at closed.** Per IDD discipline (already in `/idd-all`), close is a human checkpoint. Chain shell stops at all-verified state — user runs `/idd-close #ROOT #SPAWN_1 #SPAWN_2 ...` to finalize each issue.

> **Chain failure mode = halt + preserve.** If any chained `/idd-all #M --in-chain` ends with verify FAIL, halt the queue, preserve all partial commits on the cluster branch, print abort report. No rebase / revert.

## 與 `/idd-all` 的區別

| Skill | When to use | Issue scope | PR scope |
|-------|-------------|-------------|----------|
| `/idd-all #N` | Single issue lifecycle, single PR | 1 pre-known | 1 PR |
| `/idd-all #N #M --pr` (cluster mode) | Multi-issue user-pre-known | N pre-known | 1 PR |
| **`/idd-all-chain #N`** | **Root + auto-emergent ripple, single PR** | **1 root + N hot-emergent** | **1 PR** |

兩個 skill 共存 — chain mode 是 explicit invocation,沒有 default ambiguity (per `docs/design-patterns/default-dilemma.md`)。

## Configuration

Inherits `/idd-all` config protocol (walked-up `.claude/issue-driven-dev.local.json`). Chain-specific cap is hard-coded constants (not config-driven, to avoid config sprawl):

- `chain_max_depth = 3` — applies **per root subtree**: each root starts at depth 0, immediate spawns at depth 1, deepest allowed at depth 3 (v2.60+, #46)
- `chain_max_issues = 10` — **hard cap** as ripple-chain guardrail (per #119: cap 是 ripple subtree 安全上限, 非 batch knob — multi-root batch 應走 `/idd-all #N #M ... --pr` cluster-pr path 而非 chain). Global cap across all root subtrees combined; both caps apply independently, whichever triggers first wins (v2.60+, #46;v2.71+, #119)

當 spawn 超過 cap 時:仍 file 為 follow-up issue (sub-skill 既有 audit trail 不變),但**不**加進 chain queue。

## Execution

### Step 0: Bootstrap Stage Task List(強制)

**動任何事之前**先用 `TaskCreate` 建 stage-level todo list:

```
TaskCreate(name="preflight", description="Phase 0: 解析 args (≥1 root + optional --bfs/--review)、gh auth、確認每個 root issue 都 OPEN")
TaskCreate(name="parse_review_flag", description="Phase 0: 解析 --review flag → $REVIEW_FLAG (Phase 2 chain loop 傳到 sub-/idd-all --in-chain;Phase 4 final report wording 切換 verify-gated default vs awaiting human acceptance;per #102 NSQL doctrine)")
TaskCreate(name="check_diagnosis_readiness", description="Phase 0.4 (v2.55+ #47, helper extracted v2.57+ #51, multi-root v2.60+ #46): invoke scripts/check-diagnosis-readiness.sh <github-repo> <root1> [<root2> ...] → JSON {ready/not_ready}; not_ready=0 → silent pass; not_ready>0 → AskUserQuestion 3-option (run /idd-diagnose first / proceed anyway / cancel). Placed before cluster branch / manifest creation so cancel has zero side effect.")
TaskCreate(name="cap_exceeded_preflight", description="Phase 0.4.5 (v2.71+, #119): fail-fast refuse if ${#ROOTS[@]} > CHAIN_MAX_ISSUES — cite docs/workflows.md Anti-pattern A3 (P-chain-from-root 多 root 用 batch 跑) + suggest batch /idd-diagnose path. Placed before Phase 0.5 cluster branch so refuse leaves zero side effect.")
TaskCreate(name="setup_cluster_branch", description="Phase 0.5: 建 cluster branch — N=1 用 idd/chain-<N>-<slug>, N>1 用 idd/chain-multi-<hash8>-<root1-slug> from default branch + 初始化 spawn manifest schema v2 (root_issues + traversal)")
TaskCreate(name="init_queue", description="Phase 1: QUEUE seeded with all roots (sorted asc), per-root DEPTH_MAP[$root]=0, ROOT_ID_MAP, FAIL_ROOTS set, CHAIN_MAX_DEPTH=3 + CHAIN_MAX_ISSUES=10")
TaskCreate(name="chain_loop", description="Phase 2: 主 loop — DFS push-front / BFS push-back for new spawns, per-root depth cap + global max-issues cap, per-root halt on verify FAIL (Q4 Option C — purge same-root pending, other roots continue)")
TaskCreate(name="open_cluster_pr", description="Phase 3: 開 cluster PR — N=1 title 'chain: <title>', N>1 title 'chain (multi-root): N issues — <root#1 title>', Refs all chained #N (roots first), body cluster overview table 含 root_id 欄位 + per-issue collapsed details")
TaskCreate(name="report_and_stop", description="Phase 4: 印 forest tree printout + per-root PASS/FAIL summary + filed-only-not-chained list, 停在 verified 等 user /idd-close #N #M #K")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。

---

### Phase 0: Pre-flight + cluster branch setup

#### Step 0.1: Argument Parsing

Same as `/idd-all`,plus:
- Required: ≥1 issue number (root) — N=1 single-root (backward compat) or N>1 multi-root forest
- Optional: `--bfs` flag — select BFS traversal mode (default = DFS)
- Optional: `--cwd /path/to/clone` for cross-repo invocation

```bash
declare -a ROOT_ISSUES=()
TRAVERSAL="dfs"   # default
CWD_FLAG=""
REVIEW_FLAG=""    # "" | "--review" — set by --review flag (v2.65+ #102)
for ((i=0; i<${#ARGS[@]}; i++)); do
  arg="${ARGS[i]}"
  case "$arg" in
    \#[0-9]*)
      ROOT_ISSUES+=("${arg#\#}") ;;
    --bfs)
      TRAVERSAL="bfs" ;;
    --review)
      # v2.65+ #102 — opt-in re-open NSQL confirmation loop.
      # Propagated to each chained /idd-all #M --in-chain in Phase 2 so per-issue
      # Phase 6 reports also reflect; Phase 4 chain final report also dispatches.
      # Orchestrator-scope messaging-only effect (per #108 DA3) — does NOT make chain wait. Per MANIFESTO
      # "Human-in-the-loop: IDD 即 NSQL Confirmation Protocol" doctrine.
      REVIEW_FLAG="--review" ;;
    --cwd=*) CWD_FLAG="${arg#--cwd=}" ;;
    --cwd)   i=$((i+1)); CWD_FLAG="${ARGS[i]}" ;;
  esac
done
[ ${#ROOT_ISSUES[@]} -eq 0 ] && abort "Usage: /idd-all-chain #NNN [#MMM ...] [--bfs] [--review] [--cwd /path]"

# Sort roots ascending for deterministic hash + lowest-root-first slug selection
IFS=$'\n' ROOT_ISSUES_SORTED=($(sort -n <<<"${ROOT_ISSUES[*]}"))
unset IFS

N_ROOTS=${#ROOT_ISSUES_SORTED[@]}
LOWEST_ROOT="${ROOT_ISSUES_SORTED[0]}"
ROOT_ISSUE="$LOWEST_ROOT"   # legacy alias: many downstream blocks refer to the "primary" root
```

#### Step 0.2: Working tree resolution

Same as `/idd-all` Step 0.2 (CWD / GITHUB_REPO / CONFIG_PATH discovery)。

#### Step 0.3: Universal pre-flight gates

```bash
# 1. Git repo
git -C "$CWD" rev-parse --git-dir > /dev/null 2>&1 || abort "'$CWD' is not a git repo"
# 2. gh auth
gh auth status > /dev/null 2>&1 || abort "gh CLI not authenticated"
# 3. Every root issue exists + OPEN
for r in "${ROOT_ISSUES_SORTED[@]}"; do
  STATE=$(gh issue view "$r" -R "$GITHUB_REPO" --json state -q .state 2>/dev/null) \
    || abort "Issue #$r not found in $GITHUB_REPO"
  [ "$STATE" = "OPEN" ] || abort "Issue #$r state=$STATE (must be OPEN)"
done
```

#### Step 0.4 (NEW, v2.55+ #47): Diagnosis-readiness check

Chain 預期 root issue 已 spec 收斂(有 `## Diagnosis` comment)。沒收斂就跑 chain → unattended idd-diagnose Layer V 自動 `proceed anyway` → idd-implement 基於 vague spec 做 design 猜測 → 6-AI verify 抓不到根本問題(因為 reviewers 也只看到 partial spec)。

**Why ASK not BLOCK**:fresh-issue + quick-iter scenarios 有時 explicit 想跳過 prior diagnose;hard block 太嚴。AskUserQuestion + audit trail 是 IC_R011 canonical pattern 的 balance point。

**Why placed here (before cluster branch / manifest creation)**:user 選 `cancel` 時 zero side effect to clean — 不會留 dangling branch / manifest。

##### Detection (bash)

Delegated to `scripts/check-diagnosis-readiness.sh` (v2.57.0+, #51) — variadic helper following `manifest-append.sh` precedent. v1 single-root invocation;ready for #46 multi-root extension to call with multiple issue numbers without API change.

```bash
# Helper script does the per-issue gh+jq detection (regex test("(?m)^## Diagnosis") per #53).
# Returns: {"ready":[N,...],"not_ready":[N,...]} JSON to stdout.
# Exit: 0 success / 1 gh-jq failure / 2 usage error.
# Multi-root (v2.60+, #46): pass all roots in one invocation; helper aggregates.
set -e

READINESS_JSON=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/check-diagnosis-readiness.sh" \
                  "$GITHUB_REPO" "${ROOT_ISSUES_SORTED[@]}")

# Parse: count not_ready entries (aggregated across all roots).
NOT_READY_COUNT=$(echo "$READINESS_JSON" | jq -r '.not_ready | length')
NOT_READY_LIST=$(echo "$READINESS_JSON" | jq -r '.not_ready | map(tostring) | join(", #")')

# Defensive: jq failure → abort (helper script already failed-fast via exit 1 to stderr,
# but if jq parse here also fails the abort still fires).
if ! [[ "$NOT_READY_COUNT" =~ ^[0-9]+$ ]]; then
  abort "Diagnosis-readiness parse failed: helper output not parsable JSON. Investigate scripts/check-diagnosis-readiness.sh output."
fi
```

If `NOT_READY_COUNT == 0` → diagnosis comment exists → silent pass, fall through to Step 0.5。

If `NOT_READY_COUNT > 0` → no diagnosis comment → enter the AskUserQuestion deliberation moment described below。

##### AskUserQuestion deliberation (prose — NOT a bash function call)

> **Why prose instead of bash**: `AskUserQuestion` is a Claude Code tool invoked at the agent level, **not** a binary on `$PATH` or a shell function. Embedding `AskUserQuestion(...)` inside a fenced bash block was a category error caught in /idd-verify #47 (P1 finding 2). The agent reads the bash detection logic, branches at the agent level on `NOT_READY_COUNT > 0`, then handles the deliberation as described in prose here. Same pattern as `idd-all/SKILL.md` Phase 0.5 ask-policy interaction.

When `NOT_READY_COUNT > 0`, the agent invokes the **AskUserQuestion** tool with this question structure (per IC_R011 canonical 3-option pattern). For single-root invocations the question names that one issue; for multi-root invocations the question aggregates all not-ready roots in one prompt (NO repeated AskUserQuestion per root):

> "Root issue(s) #${NOT_READY_LIST} 沒有 diagnosis comment(${NOT_READY_COUNT} 個 root not ready)。沒 diagnose 跑 chain 風險:unattended idd-diagnose Layer V 自動 proceed 可能基於 vague spec 做出 design 猜測。怎麼處理?"
>
> Options (default = first):
> - **`run /idd-diagnose first`** — halt chain + preserve nothing (本 step 前無 branch/manifest) + 提示跑 `/idd-diagnose #${NOT_READY_LIST}`(batch mode 一次補完),完成後重 invoke `/idd-all-chain`
> - **`proceed anyway`** — 繼續 chain;對**每個 not-ready root** PATCH issue body 加 `### Chain pre-flight: diagnosis bypassed` audit section
> - **`cancel`** — abort + 印 cleanup commands (本 step 前無 side effect,只 exit)

Based on the user's selection:

- **`run /idd-diagnose first`** → echo `"→ Halt: please run /idd-diagnose #${NOT_READY_LIST} first, then re-invoke /idd-all-chain"`, then `exit 0` (clean halt — user's deliberate choice, not an error)
- **`proceed anyway`** → for each issue in the `.not_ready` array, invoke the proceed-anyway audit trail PATCH bash below (substituting `$ROOT_ISSUE` for each not-ready issue number), then continue to Step 0.5
- **`cancel`** → echo `"→ Aborted by user. No state changes made (Phase 0.4 ran before any branch/manifest creation)."`, then `exit 0`

##### proceed-anyway audit trail PATCH (bash)

```bash
# Build audit block (defined as inline expansion, not a function — avoids
# forward-reference issues caught in /idd-verify #47 P1 finding 3).
AUDIT_BLOCK=$(cat <<EOF

### Chain pre-flight: diagnosis bypassed

- **At**: $(date -u +%Y-%m-%dT%H:%M:%SZ) by /idd-all-chain
- **User choice**: proceed anyway despite no diagnosis comment
- **Implication**: chain went through /idd-all which ran idd-diagnose unattended;Layer V might have triggered with auto-'proceed' default
EOF
)

CURRENT_BODY=$(gh issue view "$ROOT_ISSUE" -R "$GITHUB_REPO" --json body -q .body)

# Insert audit BEFORE first separator if one exists, else prepend with new separator.
# Avoids `---` accumulation caught in /idd-verify #47 P3 finding 8.
# Use line-split shell pipeline (not `awk -v` with multi-line value, which
# fails on macOS awk per /idd-verify re-verify finding).
SEP_LINE=$(echo "$CURRENT_BODY" | head -50 | grep -n '^---$' | head -1 | cut -d: -f1)
if [ -n "$SEP_LINE" ]; then
  # Body already has a separator within first 50 lines — insert audit before it
  BEFORE=$(echo "$CURRENT_BODY" | sed -n "1,$((SEP_LINE - 1))p")
  AFTER=$(echo "$CURRENT_BODY" | sed -n "${SEP_LINE},\$p")
  NEW_BODY="${BEFORE}${AUDIT_BLOCK}

${AFTER}"
else
  # No separator — prepend audit + new separator
  NEW_BODY="${AUDIT_BLOCK}

---

${CURRENT_BODY}"
fi

gh issue edit "$ROOT_ISSUE" -R "$GITHUB_REPO" --body "$NEW_BODY"
```

> **#46 multi-root extension hook** (v2.57.0+, #51 shipped): detection logic is now extracted to `plugins/issue-driven-dev/scripts/check-diagnosis-readiness.sh` with variadic positional signature `<github-repo> <issue-number> [<issue-number>...]` returning `{"ready":[N,...],"not_ready":[N,...]}` JSON. v1 single-root invocation; ready for #46 multi-root chain to call with multiple issue numbers + aggregate AskUserQuestion across roots without API change. See `references/chain-flow.md` for canonical signature.

> **Removed pseudo-fallback for unattended caller**: 早期 design 含 `IN_CHAIN_CONTEXT` env var 偵測作 unattended fallback,但實際 repo 中**無任何 producer** sets this var(/idd-verify #47 P1 finding 1)。`/idd-all-chain` 是 user-invoked deliberation moment,沒 unattended caller path,該 env detection 是 dead code,移除。若未來真有 unattended caller,需明確設計 producer + 文件化 detection convention。

#### Step 0.4.5: Cap-exceeded fail-fast preflight (v2.71+, #119)

當 user 傳入的 root 數量 > `CHAIN_MAX_ISSUES`(hard cap=10,per Configuration 段)時,**fail-fast refuse** 並 cite `docs/workflows.md` Anti-pattern A3(P-chain-from-root 多 root 用 batch 跑)。Placed before Phase 0.5 cluster branch / manifest creation,refuse 留零 side effect。

> **Why fail-fast not silent-truncate**:Pre-v2.71 行為是 user 傳 14 roots → Phase 2 loop 處理到第 10 個 break,剩下 4 個 root 被 "filed only, not chained" silent truncate。User 看不出有 4 個沒被處理(#103 F4 "irreversible side effect" failure mode)。本 step 把 quantitative gate 移到 Phase 0,**user 看到 refuse 即知**該換 path(batch `/idd-diagnose` + per-cluster `/idd-all`),而不是等 chain 跑完才發現一半工作沒做。
>
> **Why hard refuse not warn-continue**:per #119 reframing decision,cap 是 ripple-chain guardrail(N>cap = 設計初衷外的使用場景),不是 batch knob。`docs/workflows.md` A3 文件 already 教育 user「14 sibling roots 不適合 chain」;skill 端 fail-fast 強制 explicit choice(narrow scope 或 switch path),消除 silent partial-success 失敗模式。

```bash
# Phase 0.4.5: cap-exceeded fail-fast preflight (#119)
if [[ ${#ROOTS[@]} -gt $CHAIN_MAX_ISSUES ]]; then
  echo "✗ refuse: ${#ROOTS[@]} roots exceeds chain_max_issues=$CHAIN_MAX_ISSUES (hard cap as ripple-chain guardrail)"
  echo ""
  echo "本 invocation 看起來不適合 chain (N roots 大於 ripple chain 安全上限)。"
  echo "Per docs/workflows.md Anti-pattern A3 (P-chain-from-root 多 root 用 batch 跑):"
  echo "  → 應走 batch /idd-diagnose $(printf '#%s ' "${ROOTS[@]}") + (P-atomic 或 P-cluster-pr) per cluster"
  echo "  → 或 narrow scope 到 single root + ripple-chain semantic"
  exit 1
fi
```

#### Step 0.5: Cluster branch setup

```bash
# Working tree must be clean
[ -z "$(git -C "$CWD" status --porcelain)" ] || abort "Cluster branch needs clean working tree"

# Must be on default branch
DEFAULT=$(gh repo view "$GITHUB_REPO" --json defaultBranchRef -q .defaultBranchRef.name)
CURRENT=$(git -C "$CWD" branch --show-current)
[ "$CURRENT" = "$DEFAULT" ] || abort "Cluster branch must start from $DEFAULT (currently on $CURRENT)"

# Build cluster branch name — dispatch on N
TITLE=$(gh issue view "$LOWEST_ROOT" -R "$GITHUB_REPO" --json title -q .title)
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]/-/g; s/-+/-/g; s/^-//; s/-$//' \
    | cut -c1-40)

if [ $N_ROOTS -eq 1 ]; then
  # N=1: backward-compatible naming
  CLUSTER_BRANCH="idd/chain-${LOWEST_ROOT}-${SLUG}"
else
  # N>1: hash-based naming. Hash = first 8 hex of sha256 over sorted-asc roots joined by '-'.
  # Slug = lowest root's title slug.
  ROOTS_JOINED=$(IFS=-; echo "${ROOT_ISSUES_SORTED[*]}")
  HASH8=$(printf '%s' "$ROOTS_JOINED" | shasum -a 256 | cut -c1-8)
  CLUSTER_BRANCH="idd/chain-multi-${HASH8}-${SLUG}"

  # hash8 collision fallback → hash16
  if git -C "$CWD" show-ref --verify --quiet "refs/heads/$CLUSTER_BRANCH"; then
    HASH16=$(printf '%s' "$ROOTS_JOINED" | shasum -a 256 | cut -c1-16)
    CLUSTER_BRANCH="idd/chain-multi-${HASH16}-${SLUG}"
    echo "→ hash8 collision detected; retrying with hash16: $CLUSTER_BRANCH" >&2

    # hash16 double-collision (extremely rare) → abort
    if git -C "$CWD" show-ref --verify --quiet "refs/heads/$CLUSTER_BRANCH"; then
      abort "Cluster branch '$CLUSTER_BRANCH' (hash16) also exists. Manual cleanup required: git -C $CWD branch -D <existing-chain-multi-*>"
    fi
  fi
fi

# Refuse if branch already exists (single-root naming collision: chain re-run requires manual cleanup)
if [ $N_ROOTS -eq 1 ] && git -C "$CWD" show-ref --verify --quiet "refs/heads/$CLUSTER_BRANCH"; then
  abort "Cluster branch '$CLUSTER_BRANCH' already exists. Run: git -C $CWD branch -D $CLUSTER_BRANCH or pick a different root issue."
fi

git -C "$CWD" checkout -b "$CLUSTER_BRANCH"
echo "→ Cluster branch created: $CLUSTER_BRANCH (N=$N_ROOTS roots: ${ROOT_ISSUES_SORTED[*]}, traversal=$TRAVERSAL)"
```

#### Step 0.6: Initialize spawn manifest

Per `references/spawn-manifest.md` schema v2 (v2.60+, #46: multi-root + traversal):

```bash
MANIFEST_DIR="$CWD/.claude/.idd/state"
MANIFEST="$MANIFEST_DIR/chain-spawned-issues.json"
mkdir -p "$MANIFEST_DIR"

SESSION_ID=$(uuidgen)
# Build root_issues JSON array from sorted bash array
ROOTS_JSON=$(printf '%s\n' "${ROOT_ISSUES_SORTED[@]}" | jq -R 'tonumber' | jq -s .)

jq -n \
  --argjson roots "$ROOTS_JSON" \
  --arg session "$SESSION_ID" \
  --arg traversal "$TRAVERSAL" \
  '{
    schema_version: 2,
    session_id: $session,
    root_issues: $roots,
    traversal: $traversal,
    spawned: []
  }' > "$MANIFEST"

echo "→ Spawn manifest initialized: $MANIFEST (session=$SESSION_ID, roots=${ROOT_ISSUES_SORTED[*]}, traversal=$TRAVERSAL)"
```

---

### Phase 1: Initialize chain state

```bash
# Multi-root forest state (v2.60+, #46)
declare -a QUEUE=("${ROOT_ISSUES_SORTED[@]}")     # seed with all roots in sorted order
declare -A DEPTH_MAP=()                            # issue_num → depth within its root's subtree
declare -A ROOT_ID_MAP=()                          # issue_num → owning root_id (which subtree)
declare -A PROCESSED=()                            # issue → "verified" | "failed"
declare -a CHAINED_ORDER=()                        # ordered list for cluster PR body
declare -A FAIL_ROOTS=()                           # root_id → 1 when that root's subtree failed
declare -a FAILED_AT=()                            # ordered list of failing issues (for Phase 4 report)

# Each root starts at depth 0 in its own subtree
for r in "${ROOT_ISSUES_SORTED[@]}"; do
  DEPTH_MAP["$r"]=0
  ROOT_ID_MAP["$r"]="$r"
done

# Cap values (v2.60+, #46 D3: max-depth=3 primary + max-issues=10 safety net, independent apply)
CHAIN_MAX_DEPTH=3
CHAIN_MAX_ISSUES=10
```

---

### Phase 2: Main chain loop

DFS (default) pushes new spawns to **front** of queue (rich subtree first); BFS pushes to **back** (level-by-level across roots). Per-root verify FAIL halts only that root's subtree — other roots' subtrees continue. Per-root `CHAIN_MAX_DEPTH=3` independently; `CHAIN_MAX_ISSUES=10` global cap.

```bash
while [ ${#QUEUE[@]} -gt 0 ]; do
  # Global cap check (max-issues=10 applies to total across all root subtrees)
  if [ ${#PROCESSED[@]} -ge $CHAIN_MAX_ISSUES ]; then
    echo "⚠ chain_max_issues=$CHAIN_MAX_ISSUES reached. Remaining queue (filed but NOT chained): ${QUEUE[*]} (per docs/workflows.md anti-pattern A3)"
    break
  fi

  CURRENT="${QUEUE[0]}"
  QUEUE=("${QUEUE[@]:1}")   # pop front (same for both DFS and BFS — only push semantics differ)
  CURRENT_ROOT="${ROOT_ID_MAP[$CURRENT]}"

  # If the issue's owning root has already FAILed (Q4 Option C: per-root halt),
  # skip it. Defensive — queue should already be filtered, but cover concurrent
  # FAIL during long /idd-all invocation.
  if [ -n "${FAIL_ROOTS[$CURRENT_ROOT]:-}" ]; then
    echo "  ⊘ #$CURRENT skipped (root #$CURRENT_ROOT subtree already FAILed earlier)"
    continue
  fi

  echo ""
  echo "════════════════════════════════════════"
  echo "Chain processing #$CURRENT (depth=${DEPTH_MAP[$CURRENT]}, root_id=$CURRENT_ROOT, traversal=$TRAVERSAL)"
  echo "════════════════════════════════════════"

  # Capture pre-invocation manifest length
  PRE_LEN=$(jq '.spawned | length' "$MANIFEST")

  # Invoke /idd-all in chain context. Export current root_id so sub-skills can
  # propagate it to manifest-append.sh (per D1 schema v2 root_id field).
  # Propagate $REVIEW_FLAG (v2.65+ #102) so each per-issue Phase 6 report also
  # reflects the verify-gated vs awaiting-human-acceptance disposition.
  # ${REVIEW_FLAG:+ $REVIEW_FLAG} appends with a leading space ONLY when set,
  # avoiding a stray space when REVIEW_FLAG="" — otherwise args parse fragility.
  export IDD_CHAIN_CURRENT_ROOT_ID="$CURRENT_ROOT"
  Skill(skill="issue-driven-dev:idd-all", args="#$CURRENT --in-chain --cwd $CWD${REVIEW_FLAG:+ $REVIEW_FLAG}")
  unset IDD_CHAIN_CURRENT_ROOT_ID

  # Determine /idd-all completion state — read latest verify comment phase
  PHASE=$(gh issue view "$CURRENT" -R "$GITHUB_REPO" --json body -q .body \
      | grep -oE 'Phase\*\*: [a-z-]+' | head -1 | awk '{print $NF}')

  case "$PHASE" in
    verified)
      PROCESSED["$CURRENT"]="verified"
      CHAINED_ORDER+=("$CURRENT")
      echo "✓ #$CURRENT verified (root_id=$CURRENT_ROOT)"
      ;;
    needs-fix|*)
      PROCESSED["$CURRENT"]="failed"
      FAIL_ROOTS["$CURRENT_ROOT"]=1
      FAILED_AT+=("$CURRENT")
      echo "✗ #$CURRENT verify FAIL (phase=$PHASE) — halting root #$CURRENT_ROOT subtree"

      # Per-root halt (Q4 Option C, D4): remove from QUEUE all pending issues
      # whose owning root == CURRENT_ROOT. Other roots' subtrees continue.
      NEW_QUEUE=()
      PURGED=()
      for q in "${QUEUE[@]}"; do
        if [ "${ROOT_ID_MAP[$q]}" = "$CURRENT_ROOT" ]; then
          PURGED+=("$q")
        else
          NEW_QUEUE+=("$q")
        fi
      done
      QUEUE=("${NEW_QUEUE[@]}")

      if [ ${#PURGED[@]} -gt 0 ]; then
        echo "  → purged from queue (same root_id=$CURRENT_ROOT): ${PURGED[*]}"
      fi
      echo "  → other root subtrees continue (FAIL_ROOTS=${!FAIL_ROOTS[*]})"
      continue
      ;;
  esac

  # Read newly added manifest entries (PRE_LEN .. now)
  POST_LEN=$(jq '.spawned | length' "$MANIFEST")
  if [ $POST_LEN -gt $PRE_LEN ]; then
    NEW_SPAWN_INDICES=$(seq $PRE_LEN $((POST_LEN - 1)))
    for idx in $NEW_SPAWN_INDICES; do
      SPAWN=$(jq ".spawned[$idx]" "$MANIFEST")
      SPAWN_NUM=$(echo "$SPAWN" | jq -r '.issue_number')
      SAME_FILE=$(echo "$SPAWN" | jq -r '.same_file_as_root')
      SAME_SKILL=$(echo "$SPAWN" | jq -r '.same_skill_as_root')
      KIND=$(echo "$SPAWN" | jq -r '.spawn_kind')
      CURRENT_DEPTH="${DEPTH_MAP[$CURRENT]}"
      NEXT_DEPTH=$((CURRENT_DEPTH + 1))

      # Eligibility check (per spec: same_file OR same_skill OR sister-bug)
      if [ "$SAME_FILE" = "true" ] || [ "$SAME_SKILL" = "true" ] || [ "$KIND" = "sister-bug" ]; then
        # Per-root depth check (D3: max-depth applies per root subtree independently)
        if [ $NEXT_DEPTH -le $CHAIN_MAX_DEPTH ]; then
          # Global max-issues check (D3: max-issues applies to total)
          if [ $((${#PROCESSED[@]} + ${#QUEUE[@]} + 1)) -le $CHAIN_MAX_ISSUES ]; then
            # Push semantics dispatch (D2: DFS=push-front, BFS=push-back)
            if [ "$TRAVERSAL" = "dfs" ]; then
              QUEUE=("$SPAWN_NUM" "${QUEUE[@]}")   # push to front
            else
              QUEUE+=("$SPAWN_NUM")                 # push to back
            fi
            DEPTH_MAP["$SPAWN_NUM"]=$NEXT_DEPTH
            ROOT_ID_MAP["$SPAWN_NUM"]="$CURRENT_ROOT"   # inherit owning root
            echo "  → enqueued #$SPAWN_NUM (kind=$KIND, depth=$NEXT_DEPTH, root_id=$CURRENT_ROOT, push=${TRAVERSAL})"
          else
            echo "  ⊘ #$SPAWN_NUM eligible but max-issues cap reached — filed only, not chained (per docs/workflows.md anti-pattern A3)"
          fi
        else
          echo "  ⊘ #$SPAWN_NUM eligible but depth>$CHAIN_MAX_DEPTH (per-root) — filed only, not chained"
        fi
      else
        echo "  ⊘ #$SPAWN_NUM ineligible (cross-cutting) — filed only, not chained"
      fi
    done
  fi
done

echo ""
echo "════════════════════════════════════════"
echo "Chain complete: ${#PROCESSED[@]} issues processed (${#FAIL_ROOTS[@]} root subtree(s) FAILed)"
echo "  Verified: ${CHAINED_ORDER[*]}"
[ ${#FAIL_ROOTS[@]} -gt 0 ] && echo "  Failed roots: ${!FAIL_ROOTS[*]}"
echo "════════════════════════════════════════"
```

---

### Phase 3: Open cluster PR

```bash
# Push cluster branch
git -C "$CWD" push -u origin "$CLUSTER_BRANCH"

# Build refs list — roots first (in sorted order), then chained spawns in CHAINED_ORDER order
# Note: CHAINED_ORDER already contains every processed issue including roots, but we surface
# roots-first for the Refs line per the spec contract.
declare -a REFS_PARTS=("${ROOT_ISSUES_SORTED[@]}")
for issue in "${CHAINED_ORDER[@]}"; do
  # Skip if already a root (would be duplicate)
  is_root=0
  for r in "${ROOT_ISSUES_SORTED[@]}"; do
    [ "$issue" = "$r" ] && { is_root=1; break; }
  done
  [ $is_root -eq 0 ] && REFS_PARTS+=("$issue")
done
REFS_LIST=$(printf "#%s " "${REFS_PARTS[@]}")

# Build per-issue collapsed sections + cluster overview rows (includes root_id column for multi-root)
OVERVIEW_ROWS=""
DETAILS_BLOCKS=""
LOWEST_ROOT_TITLE=$(gh issue view "$LOWEST_ROOT" -R "$GITHUB_REPO" --json title -q .title)

for issue in "${CHAINED_ORDER[@]}"; do
  ITITLE=$(gh issue view "$issue" -R "$GITHUB_REPO" --json title -q .title)
  HEAD_COMMIT=$(git -C "$CWD" log --oneline --grep "#$issue" -1 --format='%h' | head -1)
  IROOT="${ROOT_ID_MAP[$issue]}"

  # Determine spawn source: if issue is a root, label "root"; else read from manifest
  is_root=0
  for r in "${ROOT_ISSUES_SORTED[@]}"; do
    [ "$issue" = "$r" ] && { is_root=1; break; }
  done
  if [ $is_root -eq 1 ]; then
    SOURCE="root"
  else
    SOURCE=$(jq -r ".spawned[] | select(.issue_number == $issue) | \"\(.spawned_by) \(.spawn_step)\"" "$MANIFEST")
  fi

  OVERVIEW_ROWS+="| #$issue | $IROOT | $SOURCE | verified | $HEAD_COMMIT |"$'\n'
  DETAILS_BLOCKS+=$'\n'"<details>"$'\n'"<summary>#$issue (root_id=$IROOT) — $ITITLE</summary>"$'\n\n'
  DETAILS_BLOCKS+="See issue #$issue for diagnose / verify / commit history."$'\n\n'"</details>"$'\n'
done

# PR title dispatch on N (D6: PR title format)
if [ $N_ROOTS -eq 1 ]; then
  PR_TITLE="chain: $LOWEST_ROOT_TITLE"
  SUMMARY_LINE="Cluster of ${#CHAINED_ORDER[@]} issues solved as one chain (root #${LOWEST_ROOT} + auto-emergent spawn) via \`/idd-all-chain\` (v2.55+)."
else
  PR_TITLE="chain (multi-root): ${N_ROOTS} issues — $LOWEST_ROOT_TITLE"
  SUMMARY_LINE="Multi-root chain (N=${N_ROOTS} roots: ${ROOT_ISSUES_SORTED[*]}) solved as one cluster via \`/idd-all-chain\` (v2.60+, traversal=${TRAVERSAL}). Total ${#CHAINED_ORDER[@]} processed issues across all root subtrees."
fi

# Compose review-state checklist line with explicit if/else BEFORE heredoc
# interpolation (v2.65.1+ fix for the broken ${VAR:-word} mutex attempt that
# this file shipped with — that idiom returns $VAR when set, not the
# alternative branch, so the --review path leaked the literal `--review` at
# the end of the rendered line. Build the line in a single var, then
# interpolate, so the heredoc only sees the final string.)
if [ -n "$REVIEW_FLAG" ]; then
  REVIEW_CHECKLIST_LINE="- [ ] **Pending: human acceptance review of cluster PR** (per --review flag) + /idd-close $REFS_LIST after merge"
else
  REVIEW_CHECKLIST_LINE="- [x] **Verify-gated**: per-issue verify PASS — cluster ready to merge → /idd-close $REFS_LIST per issue after merge"
fi

PR_BODY=$(cat <<EOF
Refs $REFS_LIST

## Summary

$SUMMARY_LINE

## Cluster overview

| # | root_id | Spawn source | Phase | PR commit |
|---|---------|-------------|-------|-----------|
$OVERVIEW_ROWS

## Per-issue details
$DETAILS_BLOCKS

## Review status

- [x] Diagnose ✓ for all ${#CHAINED_ORDER[@]} issues
- [x] Implement ✓
- [x] Verify ✓ (per-issue 6-AI ensemble)
$REVIEW_CHECKLIST_LINE

---

🤖 Generated by /idd-all-chain. **Do NOT add GitHub close trailers** (Closes/Fixes/Resolves) — IDD discipline requires manual /idd-close per issue after merge to enforce checklist gate + per-issue closing summary.
EOF
)

PR_URL=$(gh pr create -R "$GITHUB_REPO" \
    --title "$PR_TITLE" \
    --body "$PR_BODY" \
    --base "$DEFAULT" --head "$CLUSTER_BRANCH")

echo "→ Cluster PR opened: $PR_URL"
```

---

### Phase 4: Final report and stop

Phase 4 emits a forest-tree visualization (one tree per root) plus a per-root PASS/FAIL summary plus a flat list of filed-only-not-chained issues. Status icons: `✓` PASS, `✗` FAIL, `⊘` filed but unprocessed (cap or eligibility).

```bash
# Build forest tree printout.
# For each root in ROOT_ISSUES_SORTED, walk its subtree by iterating CHAINED_ORDER + manifest spawns.
FOREST_OUTPUT=""
for r in "${ROOT_ISSUES_SORTED[@]}"; do
  # Determine root status
  if [ -n "${FAIL_ROOTS[$r]:-}" ]; then
    R_ICON="✗"
    # Find the failed issue within this root's subtree
    FAILED_AT_THIS_ROOT=""
    for f in "${FAILED_AT[@]}"; do
      if [ "${ROOT_ID_MAP[$f]}" = "$r" ]; then
        FAILED_AT_THIS_ROOT="$f"
        break
      fi
    done
    R_LABEL="root #$r (depth 0) — FAIL at #${FAILED_AT_THIS_ROOT}"
  elif [ "${PROCESSED[$r]:-}" = "verified" ]; then
    R_ICON="✓"
    R_LABEL="root #$r (depth 0)"
  else
    R_ICON="⊘"
    R_LABEL="root #$r (depth 0) — filed but unprocessed"
  fi
  FOREST_OUTPUT+="  $R_ICON $R_LABEL"$'\n'

  # Walk this root's subtree (descendants whose ROOT_ID_MAP value == r, ordered by depth then id)
  for issue in "${CHAINED_ORDER[@]}"; do
    [ "$issue" = "$r" ] && continue
    [ "${ROOT_ID_MAP[$issue]}" != "$r" ] && continue
    D="${DEPTH_MAP[$issue]}"
    PAD=$(printf '%*s' $((D * 2)) '')
    SPAWN_INFO=$(jq -r ".spawned[] | select(.issue_number == $issue) | \"\(.spawned_by) \(.spawn_step) (\(.spawn_kind))\"" "$MANIFEST")
    FOREST_OUTPUT+="  ${PAD}  ✓ #$issue (depth $D, $SPAWN_INFO)"$'\n'
  done

  # Show failed subtree members under their root
  for f in "${FAILED_AT[@]}"; do
    [ "${ROOT_ID_MAP[$f]}" != "$r" ] && continue
    D="${DEPTH_MAP[$f]}"
    PAD=$(printf '%*s' $((D * 2)) '')
    SPAWN_INFO=$(jq -r ".spawned[] | select(.issue_number == $f) | \"\(.spawned_by) \(.spawn_step) (\(.spawn_kind))\"" "$MANIFEST")
    [ "$f" = "$r" ] && continue   # already labeled above
    FOREST_OUTPUT+="  ${PAD}  ✗ #$f (depth $D, $SPAWN_INFO)"$'\n'
  done
done

# Per-root PASS/FAIL summary block
SUMMARY_BLOCK=""
for r in "${ROOT_ISSUES_SORTED[@]}"; do
  if [ -n "${FAIL_ROOTS[$r]:-}" ]; then
    FAILED_AT_THIS=""
    for f in "${FAILED_AT[@]}"; do
      if [ "${ROOT_ID_MAP[$f]}" = "$r" ]; then
        FAILED_AT_THIS="$f"
        break
      fi
    done
    SUMMARY_BLOCK+="  #$r: FAIL (verify FAIL at #$FAILED_AT_THIS — subtree halted)"$'\n'
  elif [ "${PROCESSED[$r]:-}" = "verified" ]; then
    # Count spawn processed in this root's subtree
    SPAWN_COUNT=0
    for issue in "${CHAINED_ORDER[@]}"; do
      [ "$issue" = "$r" ] && continue
      [ "${ROOT_ID_MAP[$issue]}" = "$r" ] && SPAWN_COUNT=$((SPAWN_COUNT + 1))
    done
    SUMMARY_BLOCK+="  #$r: PASS ($SPAWN_COUNT spawn processed)"$'\n'
  else
    # Root not processed at all — likely skipped due to max-issues cap or not-OPEN
    SUMMARY_BLOCK+="  #$r: SKIPPED (max-issues cap or root not OPEN)"$'\n'
  fi
done

# Filed-only-not-chained list: scan manifest for spawns that never made it into CHAINED_ORDER
FILED_ONLY=""
TOTAL_SPAWNS=$(jq '.spawned | length' "$MANIFEST")
for i in $(seq 0 $((TOTAL_SPAWNS - 1))); do
  S_NUM=$(jq -r ".spawned[$i].issue_number" "$MANIFEST")
  in_chained=0
  for c in "${CHAINED_ORDER[@]}"; do
    [ "$c" = "$S_NUM" ] && { in_chained=1; break; }
  done
  [ $in_chained -eq 1 ] && continue
  S_KIND=$(jq -r ".spawned[$i].spawn_kind" "$MANIFEST")
  S_ROOT=$(jq -r ".spawned[$i].root_id" "$MANIFEST")
  FILED_ONLY+="  ⊘ #$S_NUM (root_id=$S_ROOT, kind=$S_KIND) — filed but not chained (cap or ineligible)"$'\n'
done

cat <<EOF
✓ /idd-all-chain complete (${#PROCESSED[@]} issues processed, ${#FAIL_ROOTS[@]} root subtree FAILed)

Forest summary (traversal: $TRAVERSAL):

$FOREST_OUTPUT
Per-root PASS/FAIL:

$SUMMARY_BLOCK
EOF

if [ -n "$FILED_ONLY" ]; then
  cat <<EOF
Filed but not chained:

$FILED_ONLY
EOF
fi

# Verify-gated terminal disposition (v2.65.0+ #102) — dispatch on $REVIEW_FLAG
# Build "Next" steps before the heredoc to avoid the ${VAR:-word} mutex pitfall
# that PR #109 verify (F1) caught and that #108 doctrine now governs.
if [ -n "$REVIEW_FLAG" ]; then
  VERIFY_LINE="Verify:         verify-gated PASS across cluster — awaiting human acceptance (re-opened confirmation loop per --review)"
  NEXT_STEPS=$(cat <<NEXT
Next:
  1. Review PR $PR_URL (per --review opt-in)
  2. Merge after acceptance (squash recommended — single review surface)
  3. /idd-close $REFS_LIST (per-issue closing summary required, no shortcut)
NEXT
)
else
  VERIFY_LINE="Verify:         verify-gated PASS across cluster — cluster ready to merge"
  NEXT_STEPS=$(cat <<NEXT
Next:
  1. Merge $PR_URL (squash recommended — single review surface)
  2. /idd-close $REFS_LIST (per-issue closing summary required, no shortcut)
NEXT
)
fi

cat <<EOF
  Cluster branch: $CLUSTER_BRANCH
  Refs:           $REFS_LIST
  PR:             $PR_URL
  $VERIFY_LINE

$NEXT_STEPS
EOF
```

**STOP**。不 auto-merge,不 auto-close。Per-issue close summary 是 IDD 紀律核心,chain mode 不省略。

---

## Failure handling

### `print_abort_report()`

```bash
print_abort_report() {
  cat <<EOF

════════════════════════════════════════
✗ /idd-all-chain HALTED at #$CURRENT
════════════════════════════════════════

Successfully chained (commits preserved on $CLUSTER_BRANCH):
$(for i in "${CHAINED_ORDER[@]}"; do echo "  ✓ #$i"; done)

Failed:
  ✗ #$CURRENT — verify FAIL (phase=$PHASE)
    See verify findings: gh issue view $CURRENT --json comments

Skipped (still in queue when halt fired):
$(for i in "${QUEUE[@]}"; do echo "  ⊘ #$i"; done)

To recover:
  1. /idd-verify --pr <future-PR> to inspect FAIL details
  2. Fix the failing issue manually OR
  3. /idd-implement #$CURRENT --branch-override $CLUSTER_BRANCH to retry on cluster branch
  4. Re-run /idd-all-chain $CURRENT (creates new branch, leaves this one for cleanup) OR
  5. Discard cluster: gh pr close + git checkout main + git branch -D $CLUSTER_BRANCH

Cluster branch is NOT auto-deleted. Investigate before discarding.
EOF
}
```

---

## Failure modes

| 情況 | 行為 |
|------|------|
| 0 root tokens passed | Phase 0.1 abort with usage hint |
| Any root issue not OPEN | Phase 0.3 abort, listing the offending root(s) |
| Diagnosis comment missing on any root + user picks `cancel` | Phase 0.4 clean halt (no branch/manifest yet) |
| Diagnosis comment missing on any root + user picks `run /idd-diagnose first` | Phase 0.4 clean halt + 提示 batch diagnose `/idd-diagnose #N #M ...` |
| Working tree dirty | Phase 0.5 abort, 提示 stash/commit |
| Not on default branch | Phase 0.5 abort, 提示 checkout default |
| Cluster branch already exists (N=1 single-root naming) | Phase 0.5 abort, 提示手動清理 |
| Cluster branch hash8 collision (N>1) | Phase 0.5 fallback to hash16; double collision → abort with cleanup hint |
| `/idd-all #M --in-chain` 沒在 cluster branch | sub-skill 自己 abort (Step 0.5 sanity check) |
| Chained verify FAIL (single root subtree) | Phase 2 halt that root's subtree only; other root subtrees continue; commits preserved; Phase 4 per-root FAIL/PASS report |
| Chained verify FAIL (the only root subtree) | Equivalent to halting the whole queue; commits preserved; Phase 4 report shows single root FAIL |
| Chain depth > 3 (per root) | Spawn filed (sub-skill audit trail) but NOT enqueued, chain continues |
| Chain total issues > 10 | Same — filed only, not enqueued, chain continues |
| Chain total roots > 10 at Phase 0 (v2.71+, #119) | Phase 0.4.5 fail-fast refuse with anti-pattern A3 cite (no cluster branch / no manifest created) |
| Manifest helper invoked with 8 args under v2 helper | Helper exits 2 (usage error); sub-skill should pass 9th `root_id` arg |
| Manifest helper detects v1 schema on disk | Helper exits 1 (schema mismatch); migration hint printed |
| `gh pr create` 失敗 | Phase 3 abort, branch 已 push, 提示手動開 PR |

---

## 鐵律

- **永不 auto-close**:per-issue close summary 是 IDD 核心紀律,chain mode 也要 user manual `/idd-close #N #M #K`
- **永不 auto-merge**:即使 chain verify all PASS,reviewer 看 cluster diff 是另一層 gate
- **Cluster branch 嚴格命名**:N=1 用 `idd/chain-<root>-<slug>`,N>1 用 `idd/chain-multi-<hash8>-<root1-slug>` — sub `/idd-all --in-chain` Step 0.5 sanity check 認這兩個 prefix,不符 abort
- **Chain depth + max-issues 是 hard cap**:不可繞過;`max_depth=3` 對每 root subtree 獨立 apply,`max_issues=10` 是 global 總額;超過 cap 的 spawn 仍 file 但不 chain
- **Verify discipline 不省略**:每個 chained issue 跑完整 6-AI ensemble verify;single-root chain 失敗 halt 全 queue,multi-root chain 失敗只 halt 該 root's subtree 並繼續其他 root(D4 Option C)
- **DFS default, BFS opt-in**:default = DFS(rich subtree first,reviewer cognitive load 低);`--bfs` opt-in for fairness across roots
- **Schema v2 hard-break**:helper + chain shell 同 PR ship v2;v1 manifest on disk → fail-fast(不 silent migrate / silent overwrite)

## Auto-Update

Sub `/idd-all #M --in-chain` 內部 sub-skill 各自跑 idd-update,issue body Current Status 各自 sync 到 verified。Chain shell 不需額外 update。

## Next Step

`/idd-all-chain` 結束後 — user 接手:

```bash
# 1. Review PR
gh pr view <PR_URL>

# 2. Merge (squash recommended)
gh pr merge <PR_NUM> --squash

# 3. Per-issue close (cluster-PR mode of /idd-close)
/issue-driven-dev:idd-close #<ROOT> #<SPAWN_1> #<SPAWN_2> ...
```

Per `references/batch-and-cluster.md` cluster-PR close mode,each issue gets independent closing summary。

## See Also

- `references/spawn-manifest.md` — spawn manifest cross-skill contract
- `references/chain-flow.md` — chain shell algorithm contract
- `references/pr-flow.md` — `/idd-all` PR mode (chain mode 借用 4th tuple)
- `docs/design-patterns/default-dilemma.md` — why chain is separate skill
- `idd-all/SKILL.md` — single-issue baseline orchestrator (recursively called)
