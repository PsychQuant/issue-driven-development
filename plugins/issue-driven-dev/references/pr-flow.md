# PR Flow Reference

Single source of truth for **PR path** vs **direct-commit path** routing in IDD.

Both `idd-implement` and `idd-all` consume this — both resolve dynamically per invocation. `idd-all` v2.46.0+ derives `(path, interaction)` tuple from the same `pr_policy` config + `--pr/--no-pr` flags (see "idd-all path resolution" section below). v2.40.0–v2.45.0 hardcoded PR path; v2.46.0+ removes that hardcode while preserving the v2.40.0 default for absent config.

## Two paths

| Path | Branch | Push | PR | When |
|------|--------|------|----|----|
| **PR path** | `idd/<N>-<slug>` (feature branch off default) | `git push -u` after each phase | `gh pr create` after verify | Multi-contributor repos, fork contributions, CI gating, code review required |
| **Direct-commit path** | Current branch (typically default) | Optional | None | Solo project, personal marketplace, quick fix where review = noise |

Both paths share IDD discipline: every commit references `#NNN`, no `Closes`/`Fixes`/`Resolves` trailers, `idd-close` enforces checklist gate.

## Resolution algorithm

When `idd-implement` (or any IDD skill that needs to know the path) starts, resolve in this order. **Cluster mode (≥2 `#N` invocations) is a precondition that pre-empts this table — see [Cluster mode override](#cluster-mode-override) below.**

```
1. --pr flag                     → PR path (per-invocation)
2. --no-pr flag                  → direct-commit path (per-invocation)
3. Repo is a fork                → PR path (forced — no push to upstream)
4. Config: pr_policy = "always"  → PR path
5. Config: pr_policy = "never"   → direct-commit path
6. Config: pr_policy = "ask"     → AskUserQuestion (explicitly set)
7. Default (no config / field absent, not fork) → consumer-specific:
   - idd-implement → AskUserQuestion (treat absent as ask)
   - idd-all       → PR path, unattended (v2.40.0 backward-compat default; protects /loop callers)
```

> **Why idd-implement and idd-all diverge on absent config**: idd-implement is invoked single-issue per-call, often interactively — defaulting absent to `ask` is fine, the user is already at the prompt. idd-all is the orchestrator typically called by automation (`/loop`, scheduled cron). Defaulting absent to `ask` would hang fire-and-forget callers. The divergence is intentional; both consumers honor explicit `pr_policy` values identically.

### Why fork detection forces PR path

Forks have no push permission to upstream. Direct-commit would commit to the fork's default branch with no path back to upstream. PR is the only meaningful contribution route.

Detection:

```bash
IS_FORK=$(gh repo view "$GITHUB_REPO" --json isFork -q .isFork)
```

If `true`, override `pr_policy` regardless of config — print one-line notice ("repo is a fork → PR path enforced") and proceed.

### Cluster mode override

Cluster mode — any IDD skill invoked with **≥2 `#N` arguments** (`idd-implement`, `idd-verify`, `idd-close`) — is a multi-issue mode where all cluster issues share one feature branch + one PR.

**Path resolution is `idd-implement`'s job** — it is the only skill that resolves PR-vs-direct-commit. For `idd-implement`, cluster mode is a precondition that pre-empts the [Resolution algorithm](#resolution-algorithm) above and **forces PR path**, with the same explicit override semantics as fork detection. `idd-verify` / `idd-close` are cluster-aware but operate on the cluster's already-existing PR — they consume the path decision, they don't make it.

**Why pre-empt**: a cluster is one reviewable unit (1 feature branch + 1 PR + cross-issue scope). Direct-commit on a cluster would either (a) commit N issues' changes to current branch (typically default) with no PR review gate — i.e., stacked half-isolated changes on default branch — or (b) lose the "one-PR-spans-N-issues" semantic. Both defeat cluster's purpose.

**Override notice**: when `--no-pr` or `pr_policy = "never"` collides with cluster mode, Phase 0.5 prints (mirror fork detection):

```
→ cluster mode (N issues) → PR path enforced (overriding --no-pr / pr_policy=never)
```

Then proceeds as PR path. **No abort, no silent ignore** — the flag is acknowledged but cannot satisfy cluster's contract. User stays informed; future single-issue invocation restores `--no-pr` / `pr_policy:"never"` honoring.

**Fork + cluster co-occurrence**: both pre-emptions independently force PR path — they are not mutually exclusive. When repo is a fork AND cluster mode is invoked AND `--no-pr` (or `pr_policy=never`) is set, Phase 0.5 prints **both** notices (cluster override first, then fork) and proceeds as PR path. There is no precedence question to resolve: both pre-emptions reach the same destination (PR path), they just each independently announce their own reason.

**Why not abort**: cluster's typical caller is `idd-implement #34 #36 #38 --pr` (explicit). The `--no-pr` collision case is rare (user with `pr_policy:"never"` config who happens to run cluster). Aborting would block legitimate work; the override notice lets work proceed while making the precedence visible.

**Single-issue invocation behavior is unchanged** — the cluster carve-out only fires on ≥2 `#N`. Backward compatibility preserved.

#### Feature-branch + cluster + direct-commit — rejected case (v2.70.0+, #100 Finding 1)

PR #99 (#96 implementation, Option A) chose to unconditionally force PR for cluster mode, regardless of the starting branch. Devil's Advocate during verify flagged that the "force PR" rationale (stacked half-isolated changes on default branch) **only holds when the user starts from the default branch**. On a non-default feature branch, cluster direct-commit just stacks N `Refs #N` commits on that feature branch — a legitimate workflow (one local feature tracking N issues, shipped as one PR later).

The alternative was **Option B** (branch-context-gated cluster direct-commit): if current branch != default branch, honor `--no-pr` / `pr_policy=never`; otherwise force PR as today. This issue confirms **Option A is final**:

| Aspect | Option A (current) | Option B (rejected) |
|--------|--------------------|--------------------|
| Contract simplicity | Cluster → PR. Uniform regardless of branch context. | Cluster → PR if default branch, else direct-commit. Two paths. |
| Override notice | One wording, mirrors fork detection | Two wordings depending on branch context |
| `git symbolic-ref` dependency | None | Required (detached HEAD / merge-state edge cases) |
| Cluster-on-feature-branch frequency | Rare (most cluster invocations are explicit `--pr`) | Same rare frequency, but now requires branch-context check overhead |

**Recommendation**: keep Option A. The feature-branch direct-commit workflow remains viable for **single-issue** invocations (which honor `--no-pr` / `pr_policy=never`). Users who want cluster-on-feature-branch direct-commit pattern can: (a) run cluster as PR + cherry-pick or rebase to feature branch post-merge, or (b) run N atomic single-issue `--no-pr` invocations on the feature branch.

If cluster-on-feature-branch direct-commit becomes a common pattern (not anticipated based on current usage), revisit Option B in a future issue. Until then, contract simplicity wins.

Cross-reference: full cluster semantics in [batch-and-cluster.md](batch-and-cluster.md).

### `pr_policy` config field

Add to `.claude/issue-driven-dev.local.json`:

```json
{
  "github_repo": "owner/repo",
  "pr_policy": "always" | "never" | "ask"
}
```

| Value | Meaning |
|-------|---------|
| `always` | Every `idd-implement` opens a feature branch + PR. Same path resolution as `idd-all` with `--pr` or `pr_policy: always`. |
| `never` | Every `idd-implement` commits to current branch, no PR. Suits solo repos. |
| `ask` | First-time `AskUserQuestion`; subsequent invocations within the same conversation reuse the answer. **Default when field absent.** |

`pr_policy` is per-config (cascading walk-up applies). Per-issue overrides via `--pr` / `--no-pr` flags.

## PR path execution

### Branch naming

```bash
N=42  # issue number
TITLE=$(gh issue view "$N" --repo "$GITHUB_REPO" --json title -q .title)
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g' \
    | cut -c1-40)
BRANCH="idd/${N}-${SLUG}"
```

Example: issue #42 titled "Fix login button race condition" → `idd/42-fix-login-button-race-condition`.

### Branch creation

Pre-conditions:
- Working tree clean (`git status --porcelain` empty)
- On default branch (`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`)

If branch already exists:
- AskUserQuestion: checkout existing / create `${BRANCH}-2` suffix / abort

```bash
git checkout -b "$BRANCH"
```

### Concurrent-session isolation (worktree) — #947

The shared working tree is single-occupant. When two `/idd` sessions run against the same clone, in-tree branch switching collides: the second session's branch acquisition pulls the tree out from under the first, and any "clear the tree first" step (`git stash` + `git checkout`) **parks the first session's uncommitted/untracked WIP** — silent data loss. Reproduced live (ai_martech_global_scripts #941↔#942): a concurrent session manually stashed + branch-switched a tree that held another session's WIP, yanking it. Note the root cause was **agentic** — the documented clean-tree abort below already prevents the flow from yanking; the collision came from a session manually clearing the tree to "make room".

**Rules (PR path):**

1. **Default to an isolated `git worktree`, not in-tree `checkout -b`.** Provision the feature branch in its own working directory so concurrent PR-path sessions never share one tree:
   ```bash
   WORKTREE="${WORKTREE_ROOT:-$(git -C "$CWD" rev-parse --git-dir)/idd-worktrees}/${BRANCH##*/}"
   git -C "$CWD" worktree add "$WORKTREE" -b "$BRANCH" "$DEFAULT_BRANCH"
   CWD="$WORKTREE"   # all subsequent git/gh ops reuse the existing `git -C "$CWD"` plumbing
   # ... after the PR is opened (or the run aborts): git worktree remove "$WORKTREE"
   ```
   The existing `--cwd` cross-repo substitution (`git -C "$CWD"`) already routes every downstream step to the worktree — no other step changes. Repo-specific **gitignored** symlinks (e.g. a `00_principles` symlink) are NOT recreated in a fresh worktree; provide them via a repo-level setup hook if the run's tests need them, otherwise those tests skip (acceptable for codegen-only helpers).

2. **The clean-tree + on-default abort guard is the floor — never bypass it by manually clearing the tree.** A session MUST NOT `git stash` / `git checkout` a shared working tree that may hold another session's WIP to "make room" for its own branch. If the tree is dirty or on another `idd/*` branch: use a worktree (rule 1), or abort and let the human decide — do **not** stash-and-switch.

3. **Single-occupant fallback.** Where worktrees are unavailable, the documented clean-tree/on-default abort stands: refuse rather than yank.

### PR creation (after verify PASS)

```bash
git push -u origin "$BRANCH"

PR_BODY=$(cat <<EOF
Refs #${N}

## Summary
{from issue title + diagnosis Strategy}

## Verification
{verify report summary — link to issue #${N} verify comment}

## Checklist
- [x] Diagnose
- [x] Implement (${COMMIT_COUNT} commits)
- [x] Verify
- [x] **Verify-gated**: verify PASS — ready to merge → after merge, run /idd-close to finalize this issue (manual gate + closing summary; no auto-close trailer)

## Related
{follow-up issues, if any}

---
Generated by IDD. **Do NOT add a GitHub close trailer** (Closes/Fixes/Resolves) — IDD discipline requires manual /idd-close after merge to enforce checklist gate + closing summary.
EOF
)

gh pr create --title "$PR_TITLE" --body "$PR_BODY" \
    --base "$DEFAULT_BRANCH" --head "$BRANCH" --repo "$GITHUB_REPO"
```

### Forbidden in PR body

`Closes #N`, `Fixes #N`, `Resolves #N` trailers — same reason as commit messages: they bypass `idd-close`'s checklist gate. PR body uses `Refs #${N}` only.

## Direct-commit path execution

### Branch decision

Stay on current branch. Typically the default branch (`main`/`master`), but IDD does not enforce this — if the user is already on a working branch, respect it.

Print one-line notice at start: `direct-commit path → committing to ${CURRENT_BRANCH}, no PR`.

### Push policy

`idd-implement` does not auto-push on direct-commit path. The user controls when to push (could be after multiple issues, or never if local-only).

`idd-close` does not push either. Pushing is an out-of-band concern in this path.

### Commit format

Identical to PR path: `<type>: <description> (#NNN)`, no auto-close trailers.

## Interaction with `idd-close`

`idd-close` queries open PRs referencing the issue:

```bash
OPEN_PRS=$(gh pr list --repo "$GITHUB_REPO" --state open \
    --search "in:body \"#${N}\" OR in:body \"Refs #${N}\"" \
    --json number,url,headRefName)
```

Decision:

| Path taken in implement | Open PR found? | `idd-close` behavior |
|-------------------------|----------------|---------------------|
| PR path | Yes, unmerged | **Refuse close** — print PR URL, instruct user to merge first (`gh pr merge <N>`) |
| PR path | Yes, merged (closed PR with merged=true) | Proceed — post closing comment + close issue |
| PR path | No PR found | Warn but proceed (user may have abandoned / closed PR; respect explicit close) |
| Direct-commit path | (typically none) | Proceed — same as today |

The check is signal-based, not state-based: if a PR ref exists, IDD assumes PR path was used and gates accordingly.

## Decision matrix: which path?

| Situation | Recommended path | Rationale |
|-----------|------------------|-----------|
| Solo developer, own repo, single contributor | `never` | Review = noise; trust your own commits |
| Personal marketplace (psychquant-claude-plugins style) | `never` | Same as above |
| Open-source own repo with external contributors | `always` | PR signals intent and gives CI a chance |
| Fork of someone else's repo | `always` (auto, fork-detected) | No push to upstream; PR is the only route |
| Work repo with mandatory review | `always` | Compliance |
| Mixed personal/team repo | `ask` | Decide per issue |

## `idd-all` path resolution (v2.46.0+)

`idd-all` consumes `pr_policy` per the **same precedence chain as `idd-implement`** for explicit values; the orchestrator's `interaction` axis (`attended` vs `unattended`) is derived from the same source so a single `pr_policy` value drives both. The one intentional divergence is on absent config (no file or no field) — see "Why idd-implement and idd-all diverge on absent config" above.

| Resolved | `(path, interaction)` | When |
|----------|----------------------|------|
| `--pr` flag | `(PR, unattended)` | Explicit override; matches v2.40.0 default + `/loop` automation |
| `--no-pr` flag | `(direct-commit, attended)` | Explicit HITL override |
| Fork detected | `(PR, unattended)` | Always — overrides `pr_policy: never` |
| `pr_policy: always` | `(PR, unattended)` | Config-driven |
| `pr_policy: never` | `(direct-commit, attended)` | Config-driven HITL |
| `pr_policy: ask` (explicitly set) | first answer locks both axes | Interactive prompt via `AskUserQuestion` (Claude tool) |
| `pr_policy` absent (no config / field missing) | `(PR, unattended)` | v2.40.0 backward-compat default; `/loop` callers never hang |

**Why "two axes from one source"**: a `(PR, attended)` mix would mean opening a PR but pausing on every sub-skill prompt — defeats automation. A `(direct-commit, unattended)` mix would mean fire-and-forget commits to whatever branch the user happened to be on — too dangerous. The two paired tuples cover the real-world use cases (`/loop` automation vs solo HITL); orthogonal flags would just multiply the failure modes. If a future use case demands a mixed tuple, an explicit `--attended/--unattended` flag can be added without restructuring this contract.

**Resolved-tuple notice**: `idd-all` MUST print one line before any state-mutating action, e.g. `→ Path: direct-commit (attended) — pr_policy=never`. The notice line cites the precedence reason (flag, fork, or config) so the user can see which gate fired.

## Why this lives in references, not in each SKILL.md

Three skills consume this contract (`idd-implement`, `idd-all`, `idd-close`). Inlining would mean three copies that drift. References file = one canonical definition; SKILLs link here.
