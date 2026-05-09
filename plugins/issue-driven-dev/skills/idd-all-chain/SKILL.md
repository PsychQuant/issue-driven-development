---
name: idd-all-chain
description: |
  Drive root issue + auto-emergent spawned issues through ONE cluster branch + ONE review PR.
  Recursive shell over /idd-all — sub-skill spawns (sister bug / follow-up finding / tangential / sister concern) detected via spawn manifest, chain-eligible enqueued automatically.
  Use when: root issue likely ripples (refactor with sister bugs / spec change with cross-spec impact / multi-layer feature) and you want single PR review.
  Stops at verified — never auto-close, /idd-close per issue still required.
argument-hint: "[#NNN] [--cwd /path/to/clone] e.g. '#28', '#28 --cwd /path/to/repo'"
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

- `chain_max_depth = 2` — root is depth 0, immediate spawns are depth 1, spawns of spawns are depth 2
- `chain_max_issues = 5` — root + at most 4 chained issues per chain run

當 spawn 超過 cap 時:仍 file 為 follow-up issue (sub-skill 既有 audit trail 不變),但**不**加進 chain queue。

## Execution

### Step 0: Bootstrap Stage Task List(強制)

**動任何事之前**先用 `TaskCreate` 建 stage-level todo list:

```
TaskCreate(name="preflight", description="Phase 0: 解析 args、gh auth、確認 root issue OPEN")
TaskCreate(name="check_diagnosis_readiness", description="Phase 0.4 (NEW, v2.55+ #47): gh issue view --json comments + jq filter '## Diagnosis'; found → silent pass; not found → AskUserQuestion 3-option (run /idd-diagnose first / proceed anyway / cancel). Placed before cluster branch / manifest creation so cancel has zero side effect.")
TaskCreate(name="setup_cluster_branch", description="Phase 0: 建 cluster branch idd/chain-N-<slug> from default branch + 初始化 spawn manifest")
TaskCreate(name="init_queue", description="Phase 1: queue = [root], depth_map = {root: 0}, closed_set = {}")
TaskCreate(name="chain_loop", description="Phase 2: 主 loop — pop queue, invoke /idd-all #current --in-chain, read manifest, enqueue eligible spawns until queue empty / depth limit / max-issues cap reached / verify FAIL halt")
TaskCreate(name="open_cluster_pr", description="Phase 3: 開 cluster PR — title 'chain: <root title>', Refs all chained #N, body schema cluster overview + per-issue collapsed details")
TaskCreate(name="report_and_stop", description="Phase 4: 印 final report, 停在 verified 等 user /idd-close #N #M #K")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。

---

### Phase 0: Pre-flight + cluster branch setup

#### Step 0.1: Argument Parsing

Same as `/idd-all`,plus:
- Required: 1 issue number (root) — chain mode 不支援 multi-arg
- Optional: `--cwd /path/to/clone` for cross-repo invocation

```bash
ROOT_ISSUE=""
CWD_FLAG=""
for ((i=0; i<${#ARGS[@]}; i++)); do
  arg="${ARGS[i]}"
  case "$arg" in
    \#[0-9]*)
      [ -n "$ROOT_ISSUE" ] && abort "/idd-all-chain accepts exactly 1 root issue (got '$ROOT_ISSUE' and '$arg'). For multi-issue cluster, use /idd-implement #N #M --pr."
      ROOT_ISSUE="${arg#\#}" ;;
    --cwd=*) CWD_FLAG="${arg#--cwd=}" ;;
    --cwd)   i=$((i+1)); CWD_FLAG="${ARGS[i]}" ;;
  esac
done
[ -z "$ROOT_ISSUE" ] && abort "Usage: /idd-all-chain #NNN [--cwd /path]"
```

#### Step 0.2: Working tree resolution

Same as `/idd-all` Step 0.2 (CWD / GITHUB_REPO / CONFIG_PATH discovery)。

#### Step 0.3: Universal pre-flight gates

```bash
# 1. Git repo
git -C "$CWD" rev-parse --git-dir > /dev/null 2>&1 || abort "'$CWD' is not a git repo"
# 2. gh auth
gh auth status > /dev/null 2>&1 || abort "gh CLI not authenticated"
# 3. Root issue exists + OPEN
STATE=$(gh issue view "$ROOT_ISSUE" -R "$GITHUB_REPO" --json state -q .state 2>/dev/null) || abort "Issue #$ROOT_ISSUE not found in $GITHUB_REPO"
[ "$STATE" = "OPEN" ] || abort "Issue #$ROOT_ISSUE state=$STATE (must be OPEN)"
```

#### Step 0.4 (NEW, v2.55+ #47): Diagnosis-readiness check

Chain 預期 root issue 已 spec 收斂(有 `## Diagnosis` comment)。沒收斂就跑 chain → unattended idd-diagnose Layer V 自動 `proceed anyway` → idd-implement 基於 vague spec 做 design 猜測 → 6-AI verify 抓不到根本問題(因為 reviewers 也只看到 partial spec)。

**Why ASK not BLOCK**:fresh-issue + quick-iter scenarios 有時 explicit 想跳過 prior diagnose;hard block 太嚴。AskUserQuestion + audit trail 是 IC_R011 canonical pattern 的 balance point。

**Why placed here (before cluster branch / manifest creation)**:user 選 `cancel` 時 zero side effect to clean — 不會留 dangling branch / manifest。

```bash
# Detect via comments[*].body — NOT issue body
# (precise — avoids false-positive on issue body discussing "diagnosis" concept)
HAS_DIAGNOSIS=$(gh issue view "$ROOT_ISSUE" -R "$GITHUB_REPO" --json comments \
    | jq -r '[.comments[] | select(.body | contains("## Diagnosis"))] | length')

if [ "$HAS_DIAGNOSIS" = "0" ]; then
  # Sanity check for unattended caller misuse (e.g. /loop --in-chain accidentally)
  # If chain shell sets IN_CHAIN_CONTEXT env, default to 'proceed' + audit trail.
  if [ -n "$IN_CHAIN_CONTEXT" ]; then
    echo "→ Diagnosis-readiness: NOT FOUND, proceeding under unattended fallback"
    bypass_audit_trail
  else
    # AskUserQuestion 3-option per IC_R011 canonical pattern
    # Default option (first in list): run /idd-diagnose first — safest path
    AskUserQuestion(
      question="Issue #${ROOT_ISSUE} 沒有 diagnosis comment。沒 diagnose 跑 chain 風險:unattended idd-diagnose Layer V 自動 proceed 可能基於 vague spec 做出 design 猜測。怎麼處理?",
      options=[
        {label: "run /idd-diagnose first", description: "halt chain + preserve nothing (本 step 前無 branch/manifest) + 提示跑 /idd-diagnose #N,完成後重 invoke /idd-all-chain"},
        {label: "proceed anyway", description: "繼續 chain;PATCH issue body 加 ### Chain pre-flight: diagnosis bypassed audit section"},
        {label: "cancel", description: "abort + 印 cleanup commands (本 step 前無 side effect,只 exit)"}
      ]
    )
  fi
  case "$user_choice" in
    "run /idd-diagnose first")
      echo "→ Halt: please run /idd-diagnose ${ROOT_ISSUE} first, then re-invoke /idd-all-chain"
      exit 0  # clean halt, no error code (user's deliberate choice)
      ;;
    "proceed anyway")
      bypass_audit_trail  # PATCH issue body
      ;;
    "cancel")
      echo "→ Aborted by user. No state changes made (Phase 0.4 ran before any branch/manifest creation)."
      exit 0
      ;;
  esac
fi

# Helper function used in 'proceed' branch
bypass_audit_trail() {
  AUDIT_BLOCK="
### Chain pre-flight: diagnosis bypassed

- **At**: $(date -u +%Y-%m-%dT%H:%M:%SZ) by /idd-all-chain
- **User choice**: proceed anyway despite no diagnosis comment
- **Implication**: chain went through /idd-all which ran idd-diagnose unattended;Layer V might have triggered with auto-'proceed' default
"
  CURRENT_BODY=$(gh issue view "$ROOT_ISSUE" -R "$GITHUB_REPO" --json body -q .body)
  # Place audit at TOP of body (above '---' separator if exists, else prepend)
  NEW_BODY="${AUDIT_BLOCK}

---

${CURRENT_BODY}"
  gh issue edit "$ROOT_ISSUE" -R "$GITHUB_REPO" --body "$NEW_BODY"
}
```

> **Future #46 multi-root extension hook**:helper function 在實作時 signature 設計成 `check_diagnosis_readiness(issue_numbers...)` return `[ready_list, not_ready_list]` struct,#46 multi-root 落地時可直接 reuse 做 per-root readiness aggregation。本 step v1 仍 single-root,但 design 上保留擴展。

#### Step 0.5: Cluster branch setup

```bash
# Working tree must be clean
[ -z "$(git -C "$CWD" status --porcelain)" ] || abort "Cluster branch needs clean working tree"

# Must be on default branch
DEFAULT=$(gh repo view "$GITHUB_REPO" --json defaultBranchRef -q .defaultBranchRef.name)
CURRENT=$(git -C "$CWD" branch --show-current)
[ "$CURRENT" = "$DEFAULT" ] || abort "Cluster branch must start from $DEFAULT (currently on $CURRENT)"

# Build cluster branch name
TITLE=$(gh issue view "$ROOT_ISSUE" -R "$GITHUB_REPO" --json title -q .title)
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]/-/g; s/-+/-/g; s/^-//; s/-$//' \
    | cut -c1-40)
CLUSTER_BRANCH="idd/chain-${ROOT_ISSUE}-${SLUG}"

# Refuse if branch already exists (chain re-run requires manual cleanup)
if git -C "$CWD" show-ref --verify --quiet "refs/heads/$CLUSTER_BRANCH"; then
  abort "Cluster branch '$CLUSTER_BRANCH' already exists. Run: git -C $CWD branch -D $CLUSTER_BRANCH or pick a different root issue."
fi

git -C "$CWD" checkout -b "$CLUSTER_BRANCH"
echo "→ Cluster branch created: $CLUSTER_BRANCH"
```

#### Step 0.6: Initialize spawn manifest

Per `references/spawn-manifest.md` schema v1:

```bash
MANIFEST_DIR="$CWD/.claude/.idd/state"
MANIFEST="$MANIFEST_DIR/chain-spawned-issues.json"
mkdir -p "$MANIFEST_DIR"

SESSION_ID=$(uuidgen)
cat > "$MANIFEST" <<EOF
{
  "schema_version": 1,
  "session_id": "$SESSION_ID",
  "root_issue": $ROOT_ISSUE,
  "spawned": []
}
EOF
echo "→ Spawn manifest initialized: $MANIFEST (session=$SESSION_ID)"
```

---

### Phase 1: Initialize chain state

```bash
declare -a QUEUE=("$ROOT_ISSUE")
declare -A DEPTH_MAP=(["$ROOT_ISSUE"]=0)
declare -A PROCESSED=()       # issue → "verified" | "failed"
declare -a CHAINED_ORDER=()   # ordered list for cluster PR body
CHAIN_MAX_DEPTH=2
CHAIN_MAX_ISSUES=5
```

---

### Phase 2: Main chain loop

```bash
while [ ${#QUEUE[@]} -gt 0 ]; do
  # Cap check
  if [ ${#PROCESSED[@]} -ge $CHAIN_MAX_ISSUES ]; then
    echo "⚠ chain_max_issues=$CHAIN_MAX_ISSUES reached. Remaining queue (filed but NOT chained): ${QUEUE[*]}"
    break
  fi

  CURRENT="${QUEUE[0]}"
  QUEUE=("${QUEUE[@]:1}")   # pop front

  echo ""
  echo "════════════════════════════════════════"
  echo "Chain processing #$CURRENT (depth=${DEPTH_MAP[$CURRENT]})"
  echo "════════════════════════════════════════"

  # Capture pre-invocation manifest length
  PRE_LEN=$(jq '.spawned | length' "$MANIFEST")

  # Invoke /idd-all in chain context
  Skill(skill="issue-driven-dev:idd-all", args="#$CURRENT --in-chain --cwd $CWD")

  # Determine /idd-all completion state — read latest verify comment phase
  PHASE=$(gh issue view "$CURRENT" -R "$GITHUB_REPO" --json body -q .body \
      | grep -oE 'Phase\*\*: [a-z-]+' | head -1 | awk '{print $NF}')

  case "$PHASE" in
    verified)
      PROCESSED["$CURRENT"]="verified"
      CHAINED_ORDER+=("$CURRENT")
      echo "✓ #$CURRENT verified"
      ;;
    needs-fix|*)
      PROCESSED["$CURRENT"]="failed"
      echo "✗ #$CURRENT verify FAIL (phase=$PHASE) — halting chain"
      print_abort_report
      exit 1
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
        # Depth check
        if [ $NEXT_DEPTH -le $CHAIN_MAX_DEPTH ]; then
          # Issues check
          if [ $((${#PROCESSED[@]} + ${#QUEUE[@]} + 1)) -le $CHAIN_MAX_ISSUES ]; then
            QUEUE+=("$SPAWN_NUM")
            DEPTH_MAP["$SPAWN_NUM"]=$NEXT_DEPTH
            echo "  → enqueued #$SPAWN_NUM (kind=$KIND, depth=$NEXT_DEPTH)"
          else
            echo "  ⊘ #$SPAWN_NUM eligible but max-issues cap reached — filed only, not chained"
          fi
        else
          echo "  ⊘ #$SPAWN_NUM eligible but depth>$CHAIN_MAX_DEPTH — filed only, not chained"
        fi
      else
        echo "  ⊘ #$SPAWN_NUM ineligible (cross-cutting) — filed only, not chained"
      fi
    done
  fi
done

echo ""
echo "════════════════════════════════════════"
echo "Chain complete: ${#PROCESSED[@]} issues processed"
echo "  Verified: ${CHAINED_ORDER[*]}"
echo "════════════════════════════════════════"
```

---

### Phase 3: Open cluster PR

```bash
# Push cluster branch
git -C "$CWD" push -u origin "$CLUSTER_BRANCH"

# Build refs list and overview table
REFS_LIST=$(printf "#%s " "${CHAINED_ORDER[@]}")

# Build per-issue collapsed sections + cluster overview rows
OVERVIEW_ROWS=""
DETAILS_BLOCKS=""
ROOT_TITLE=$(gh issue view "$ROOT_ISSUE" -R "$GITHUB_REPO" --json title -q .title)

for issue in "${CHAINED_ORDER[@]}"; do
  ITITLE=$(gh issue view "$issue" -R "$GITHUB_REPO" --json title -q .title)
  HEAD_COMMIT=$(git -C "$CWD" log --oneline --grep "#$issue" -1 --format='%h' | head -1)

  if [ "$issue" = "$ROOT_ISSUE" ]; then
    SOURCE="root"
  else
    SOURCE=$(jq -r ".spawned[] | select(.issue_number == $issue) | \"\(.spawned_by) \(.spawn_step)\"" "$MANIFEST")
  fi

  OVERVIEW_ROWS+="| #$issue | $SOURCE | verified | $HEAD_COMMIT |"$'\n'
  DETAILS_BLOCKS+=$'\n'"<details>"$'\n'"<summary>#$issue — $ITITLE</summary>"$'\n\n'
  DETAILS_BLOCKS+="See issue #$issue for diagnose / verify / commit history."$'\n\n'"</details>"$'\n'
done

PR_BODY=$(cat <<EOF
Refs $REFS_LIST

## Summary

Cluster of ${#CHAINED_ORDER[@]} issues solved as one chain (root + auto-emergent spawn) via \`/idd-all-chain\` (v2.55+).

## Cluster overview

| # | Spawn source | Phase | PR commit |
|---|-------------|-------|-----------|
$OVERVIEW_ROWS

## Per-issue details
$DETAILS_BLOCKS

## Pending review

- [x] Diagnose ✓ for all ${#CHAINED_ORDER[@]} issues
- [x] Implement ✓
- [x] Verify ✓ (per-issue 6-AI ensemble)
- [ ] **Pending: human review of cluster PR + /idd-close $REFS_LIST after merge**

---

🤖 Generated by /idd-all-chain. **Do NOT add 'Closes #N'** trailers — IDD discipline requires manual /idd-close per issue after merge to enforce checklist gate + per-issue closing summary.
EOF
)

PR_URL=$(gh pr create -R "$GITHUB_REPO" \
    --title "chain: $ROOT_TITLE" \
    --body "$PR_BODY" \
    --base "$DEFAULT" --head "$CLUSTER_BRANCH")

echo "→ Cluster PR opened: $PR_URL"
```

---

### Phase 4: Final report and stop

```
✓ /idd-all-chain complete

  Root:           #$ROOT_ISSUE — $ROOT_TITLE
  Cluster branch: $CLUSTER_BRANCH
  Chained issues: $REFS_LIST
  Chain depth:    max(${DEPTH_MAP[@]})
  PR:             $PR_URL
  Verify:         all PASS

Next:
  1. Review PR $PR_URL
  2. Merge (squash recommended — single review surface)
  3. /idd-close $REFS_LIST (per-issue closing summary required, no shortcut)
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
| Root issue not OPEN | Phase 0.3 abort |
| Working tree dirty | Phase 0.4 abort, 提示 stash/commit |
| Not on default branch | Phase 0.4 abort, 提示 checkout default |
| Cluster branch already exists | Phase 0.4 abort, 提示手動清理 |
| `/idd-all #M --in-chain` 沒在 cluster branch | sub-skill 自己 abort (Step 0.5 sanity check) |
| Chained verify FAIL | Phase 2 halt, partial commits 保留, abort report 印 recovery options |
| Chain depth > 2 | Spawn filed (sub-skill audit trail) but NOT enqueued, chain continues |
| Chain max-issues > 5 | Same — filed only, not enqueued, chain continues |
| `gh pr create` 失敗 | Phase 3 abort, branch 已 push, 提示手動開 PR |

---

## 鐵律

- **永不 auto-close**:per-issue close summary 是 IDD 核心紀律,chain mode 也要 user manual `/idd-close #N #M #K`
- **永不 auto-merge**:即使 chain verify all PASS,reviewer 看 cluster diff 是另一層 gate
- **Cluster branch 嚴格命名**:`idd/chain-<root>-<slug>` — sub `/idd-all --in-chain` Step 0.5 sanity check 認這個 prefix,不符 abort
- **Chain depth + max-issues 是 hard cap**:不可繞過;超過 cap 的 spawn 仍 file 但不 chain
- **Verify discipline 不省略**:每個 chained issue 跑完整 6-AI ensemble verify;chain failure halt 比 cost saving 重要

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
