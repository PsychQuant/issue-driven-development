# Cross-Repo CWD — `--cwd` Flag Convention

> **Applies to**: `idd-all`, `idd-diagnose`, `idd-implement`, `idd-verify` (v2.40.0+)
> **Purpose**: Decouple IDD skills from Claude Code session-level working directory so cross-repo invocation works without session restart.

## The Problem

Skill tool calls inherit Claude Code's session-level `cwd` — they do **not** follow mid-session `cd`. When you start Claude Code in repo A but want to run an IDD skill against repo B (e.g. thesis work in repo A, want pipeline on dependency repo B), every `git status`/`git checkout`/`gh issue view` defaults to repo A's tree, breaking the workflow.

Pre-v2.40.0 workaround: exit Claude Code, `cd /path/to/repo-B`, re-launch. Loses session context, breaks unattended assumption.

## The Convention

All cwd-aware IDD skills accept `--cwd /path/to/local/clone`:

```bash
/idd-diagnose #43 --cwd /Users/che/Developer/macdoc/packages/ooxml-swift
/idd-implement #43 --pr --cwd /path/to/clone
/idd-verify #43 --cwd /path/to/clone
/idd-all #43 --cwd /path/to/clone   # forwards --cwd to its sub-skill calls
```

## Resolution Algorithm (apply at Step 0 of every cwd-aware skill)

```bash
# 1. Parse --cwd flag (per-invocation override; takes precedence over everything)
CWD_FLAG=""
for arg in "$@"; do
    case "$arg" in
        --cwd=*) CWD_FLAG="${arg#--cwd=}" ;;
        --cwd)   shift; CWD_FLAG="$1" ;;
    esac
done

# 2. Determine working tree path
if [ -n "$CWD_FLAG" ]; then
    [ -d "$CWD_FLAG" ] || abort "--cwd path '$CWD_FLAG' does not exist."
    CWD="$CWD_FLAG"
else
    CWD="$(pwd)"
fi

# 3. Derive GITHUB_REPO from origin remote (BSD-sed-compatible)
ORIGIN_URL=$(git -C "$CWD" remote get-url origin 2>/dev/null) \
    || abort "$CWD has no 'origin' remote. Pass --cwd /path/to/cloned/repo."
GITHUB_REPO=$(echo "$ORIGIN_URL" | sed -E 's#^.*github\.com[:/]##; s#\.git$##')
[ -n "$GITHUB_REPO" ] || abort "Could not parse owner/repo from $ORIGIN_URL"
```

## Substitution Rule

Once `$CWD` and `$GITHUB_REPO` are bound, **every subsequent bash example in this skill MUST be substituted**:

| Pattern shown in skill | Substitute when executing |
|------------------------|---------------------------|
| `git X` | `git -C "$CWD" X` |
| `gh issue X` (any subcommand) | `gh issue X -R "$GITHUB_REPO"` |
| `gh pr X` | `gh pr X -R "$GITHUB_REPO"` |
| `gh repo X` | `gh repo X -R "$GITHUB_REPO"` (or pass repo as arg) |
| `gh release X` | `gh release X -R "$GITHUB_REPO"` |
| `gh api X` (with `repos/...` paths) | use `repos/$GITHUB_REPO/...` in the path |

**The substitution applies even if the skill's bash example shows the bare command.** Skill bodies are written in cwd-only style for readability; the LLM interpreting the skill is responsible for applying `--cwd` consistently.

## Failure Modes

| Situation | Action |
|---|---|
| `--cwd /path` does not exist | Abort with: `--cwd path '$CWD_FLAG' does not exist.` |
| `--cwd` directory has no `.git` | Abort with: `'$CWD' is not a git repository.` |
| `--cwd` directory has no `origin` remote | Abort: `$CWD has no 'origin' remote. Pass --cwd /path/to/cloned/repo.` |
| `--cwd` not given AND session cwd is not a git repo | Abort with both alternatives in the message: `cd /path && retry, OR pass --cwd /path/to/clone` |

## Backward Compatibility

Omitting `--cwd` reads from session `pwd` — identical to pre-v2.40.0 behavior. No flag deprecations. Single-repo workflows work exactly as before.

## Sibling Flags

Some skills also accept `--target owner/repo` (e.g. `idd-issue`, `idd-list`, `idd-comment`, `idd-edit`) for **read-only** cross-repo work that doesn't need a local clone. When a skill supports both:

- `--target` alone → only `gh -R` substitution; no local git ops needed
- `--cwd` alone → both `git -C` and `gh -R` substitution (repo derived from clone's origin)
- Both given → must agree (`gh repo view -R $GITHUB_REPO` must point at same repo as `git -C $CWD remote get-url origin`); abort if mismatch

`idd-implement` / `idd-verify` / `idd-all` require `--cwd` (not just `--target`) because they do local git writes that need a real working tree.

## Parallel Worktree Pattern

A git worktree of the **same** repo is a valid `--cwd` target: it has its own `.git` link and inherits the repo's `origin` remote, so the Step 0 resolution algorithm derives the same `$GITHUB_REPO` and treats it like any other clone. To run multiple IDD pipelines concurrently, give each issue its own worktree instead of fighting over one working tree:

```bash
WT=$(bash plugins/issue-driven-dev/scripts/idd-worktree.sh create 43)  # prints .claude/worktrees/idd-43/
/idd-diagnose #43 --cwd "$WT"
/idd-implement #43 --cwd "$WT"
/idd-verify  #43 --cwd "$WT"
```

每個 issue 一個 worktree → N 條 pipeline 互不踩 working tree，各自開各自的 PR。完整 convention（layout、lifecycle、N-PRs-not-merge-back convergence）見 [`worktree-isolation.md`](worktree-isolation.md)。

## See Also

- [`pr-flow.md`](pr-flow.md) — PR vs direct-commit path resolution (orthogonal to cwd)
- [`config-protocol.md`](config-protocol.md) — `.claude/issue-driven-dev.local.md` config (also independent of cwd flag)
- [`worktree-isolation.md`](worktree-isolation.md) — parallel IDD via git worktrees (`--cwd` per issue, Case B isolation)
