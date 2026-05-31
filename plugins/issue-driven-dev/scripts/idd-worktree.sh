#!/usr/bin/env bash
# idd-worktree.sh — git-worktree lifecycle helper for parallel IDD (Case B)
#
# Lets multiple IDD pipelines run concurrently in separate Claude Code windows
# without working-tree / branch / staging collision. Each issue gets its own
# worktree at `.claude/worktrees/idd-<N>/` on a feature branch, driven via the
# existing `--cwd` flag (e.g. `idd-implement #N --cwd <path>`).
#
# See: plugins/issue-driven-dev/references/worktree-isolation.md
#      PsychQuant/issue-driven-development#167
#
# Usage:
#   idd-worktree.sh create  <N> [--slug <s>] [--repo-root <path>]
#   idd-worktree.sh cleanup <N> [--force]    [--repo-root <path>]
#   idd-worktree.sh list                     [--repo-root <path>]
#
# create stdout (success): the absolute worktree path (for `--cwd`). Nothing else.
# All diagnostics go to stderr.
#
# Exit codes:
#   0  success (incl. idempotent re-create / cleanup no-op)
#   1  generic error
#   2  usage error (bad subcommand / non-numeric or missing N)
#   3  target is not a git repository
#   4  branch-name conflict (idd/<N>-* already checked out on a DIFFERENT worktree)
#   5  cleanup refused — worktree has uncommitted changes and --force not given
#
# Env:
#   IDD_WORKTREE_NO_GH=1   skip the gh-title slug derivation (offline / hermetic)

set -u

PROG="$(basename "$0")"

err()   { printf '%s\n' "$*" >&2; }
usage() {
  err "Usage:"
  err "  $PROG create  <N> [--slug <s>] [--repo-root <path>]"
  err "  $PROG cleanup <N> [--force]    [--repo-root <path>]"
  err "  $PROG list                     [--repo-root <path>]"
}

# --- arg parse ----------------------------------------------------------------

SUBCMD="${1:-}"
[ -n "$SUBCMD" ] || { usage; exit 2; }
shift || true

N=""
SLUG=""
FORCE=""
REPO_ROOT_FLAG=""

# First positional (the issue number) is only consumed for create/cleanup.
case "$SUBCMD" in
  create|cleanup)
    # Peek: the next non-flag token is N.
    if [ "${1:-}" != "" ] && [ "${1#-}" = "$1" ]; then
      N="$1"; shift
    fi
    ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --slug)      shift; SLUG="${1:-}" ;;
    --slug=*)    SLUG="${1#--slug=}" ;;
    --force)     FORCE=1 ;;
    --repo-root) shift; REPO_ROOT_FLAG="${1:-}" ;;
    --repo-root=*) REPO_ROOT_FLAG="${1#--repo-root=}" ;;
    -* )         err "Unknown flag: $1"; usage; exit 2 ;;
    * )          err "Unexpected argument: $1"; usage; exit 2 ;;
  esac
  shift || true
done

# --- repo root resolution -----------------------------------------------------

RESOLVE_FROM="${REPO_ROOT_FLAG:-$PWD}"
[ -d "$RESOLVE_FROM" ] || { err "✗ path does not exist: $RESOLVE_FROM"; exit 3; }
git -C "$RESOLVE_FROM" rev-parse --git-dir >/dev/null 2>&1 || {
  err "✗ not a git repository: $RESOLVE_FROM (pass --repo-root /path/to/repo)"
  exit 3
}
# Anchor on the MAIN worktree root (where .claude/worktrees/ physically lives),
# NOT the current linked worktree. `git worktree list` shares the repo's worktree
# set, and its first entry is always the main worktree regardless of which
# worktree we're invoked from. Using `rev-parse --show-toplevel` instead would
# return the *current* linked worktree when called from inside one (e.g. idd-close
# GC running with --cwd <worktree>), making cleanup/list look in the wrong tree
# and silently no-op. (#167 verify P2 — codex fixture)
REPO_ROOT="$(git -C "$RESOLVE_FROM" worktree list --porcelain 2>/dev/null \
  | awk '/^worktree /{print substr($0, 10); exit}')"
[ -n "$REPO_ROOT" ] || {
  err "✗ could not resolve main worktree root from $RESOLVE_FROM"
  exit 3
}

WT_BASE="$REPO_ROOT/.claude/worktrees"

# --- shared helpers -----------------------------------------------------------

# Validate N is a positive integer. Strict — blocks path-injection via the
# worktree dir name (Scoundrel lens: `create ../../etc` must never resolve).
require_numeric_n() {
  case "$N" in
    "" )            err "✗ missing issue number"; usage; exit 2 ;;
    *[!0-9]* | 0* ) err "✗ issue number must be a positive integer: '$N'"; exit 2 ;;
  esac
}

# Default base branch for new feature branches: prefer origin/HEAD's target,
# then a local main/master, else current HEAD.
default_base() {
  local ref
  ref="$(git -C "$REPO_ROOT" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)"
  if [ -n "$ref" ]; then printf '%s\n' "${ref#refs/remotes/}"; return; fi
  for b in main master; do
    if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$b"; then
      printf '%s\n' "$b"; return
    fi
  done
  printf 'HEAD\n'
}

# slugify: lowercase, non-alnum runs → '-', trim, cap 40 chars.
slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
    | cut -c1-40 \
    | sed -E 's/-+$//'
}

# Resolve slug: --slug, else gh issue title (unless disabled / unavailable), else "".
resolve_slug() {
  if [ -n "$SLUG" ]; then slugify "$SLUG"; return; fi
  if [ -z "${IDD_WORKTREE_NO_GH:-}" ] && command -v gh >/dev/null 2>&1; then
    local title
    title="$(gh issue view "$N" --json title -q .title 2>/dev/null)" || title=""
    if [ -n "$title" ]; then slugify "$title"; return; fi
  fi
  printf ''   # bare → branch idd/<N>
}

# Print the worktree path checked out on a branch matching idd/<N> or idd/<N>-*,
# if any. Empty if none. Uses porcelain for robust parsing.
worktree_for_issue() {
  git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null | awk -v n="$N" '
    /^worktree / { path = substr($0, 10) }
    /^branch /   {
      b = substr($0, 8); sub(/^refs\/heads\//, "", b)
      if (b == "idd/" n || b ~ ("^idd/" n "-")) { print path; exit }
    }
  '
}

# Is PATH a registered worktree of this repo?
is_registered_worktree() {
  git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null \
    | grep -qxF "worktree $1"
}

ensure_gitignore() {
  local gi="$REPO_ROOT/.gitignore"
  # Refuse to append through a symlinked .gitignore (would write to the link
  # target). Warn + continue — not gitignoring the worktree dir is degraded but
  # non-fatal (it shows as untracked). (#167 verify LOW — agents:security)
  if [ -L "$gi" ]; then
    err "⚠ $gi is a symlink — not appending '.claude/worktrees/' (add it manually if desired)."
    return 0
  fi
  if ! grep -qxF '.claude/worktrees/' "$gi" 2>/dev/null; then
    {
      [ -s "$gi" ] && printf '\n'
      printf '# IDD parallel worktree isolation (idd-worktree.sh #167) — not tracked in main tree\n'
      printf '.claude/worktrees/\n'
    } >> "$gi"
  fi
}

# --- subcommands --------------------------------------------------------------

cmd_create() {
  require_numeric_n
  local wt_dir="$WT_BASE/idd-$N"

  # 1. Idempotent: canonical worktree already registered AND on this issue's
  #    branch → print path, done. A canonical path registered on a wrong branch
  #    (idd/999-*) is a conflict, not idempotent success — returning exit 0 there
  #    would mislead the caller into using a worktree on the wrong issue's branch.
  #    (#167 verify P2 — codex + agents:logic cross-confirmed)
  if is_registered_worktree "$wt_dir"; then
    local cur_branch
    cur_branch="$(git -C "$wt_dir" branch --show-current 2>/dev/null)"
    case "$cur_branch" in
      "idd/$N" | "idd/$N-"*)
        printf '%s\n' "$wt_dir"
        return 0
        ;;
      *)
        err "✗ worktree $wt_dir exists but is on branch '$cur_branch' (expected idd/$N or idd/$N-*)."
        err "  It does not belong to issue #$N — resolve manually or clean it up first."
        return 4
        ;;
    esac
  fi

  # 2. Conflict: issue N already checked out on a DIFFERENT worktree → refuse.
  local existing
  existing="$(worktree_for_issue)"
  if [ -n "$existing" ] && [ "$existing" != "$wt_dir" ]; then
    err "✗ issue #$N is already checked out on a worktree at: $existing"
    err "  (a branch idd/$N-* is in use elsewhere). Use that worktree, or clean it up first."
    return 4
  fi

  ensure_gitignore
  mkdir -p "$WT_BASE"

  local slug branch
  slug="$(resolve_slug)"
  branch="idd/$N${slug:+-$slug}"

  # 3. Reuse: branch exists but not checked out anywhere (e.g. left by cleanup).
  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
    if ! git -C "$REPO_ROOT" worktree add -q "$wt_dir" "$branch" 2>/dev/null; then
      err "✗ failed to attach worktree to existing branch $branch"
      return 1
    fi
  else
    # 4. Fresh: create the feature branch from the default base.
    local base; base="$(default_base)"
    if ! git -C "$REPO_ROOT" worktree add -q -b "$branch" "$wt_dir" "$base" 2>/dev/null; then
      err "✗ failed to create worktree $wt_dir on new branch $branch (base $base)"
      return 1
    fi
  fi

  printf '%s\n' "$wt_dir"
  return 0
}

cmd_cleanup() {
  require_numeric_n
  local wt_dir="$WT_BASE/idd-$N"

  # No-op if not a registered worktree (idempotent).
  if ! is_registered_worktree "$wt_dir"; then
    return 0
  fi

  # Refuse dirty unless --force — own pre-check for a clean exit-5 (not git's
  # generic error), so callers can distinguish "blocked by uncommitted work".
  if [ -z "$FORCE" ]; then
    if [ -n "$(git -C "$wt_dir" status --porcelain 2>/dev/null)" ]; then
      err "✗ worktree has uncommitted changes: $wt_dir"
      err "  commit/stash them, or re-run with --force to discard."
      return 5
    fi
  fi

  local force_flag=""
  [ -n "$FORCE" ] && force_flag="--force"
  if ! git -C "$REPO_ROOT" worktree remove $force_flag "$wt_dir" 2>/dev/null; then
    err "✗ git worktree remove failed for $wt_dir"
    return 1
  fi
  # Branch is intentionally left intact (an associated PR may be open/merged).
  return 0
}

cmd_list() {
  git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null | awk '
    /^worktree / { path = substr($0, 10); branch = "" }
    /^branch /   { branch = substr($0, 8); sub(/^refs\/heads\//, "", branch) }
    /^$/         { emit() }
    END          { emit() }
    function emit() {
      if (path == "") return
      # only IDD worktrees: .../.claude/worktrees/idd-<N>
      if (match(path, /\/\.claude\/worktrees\/idd-[0-9]+$/)) {
        n = path; sub(/.*\/idd-/, "", n)
        printf "%s\t%s\t%s\n", n, branch, path
      }
      path = ""; branch = ""
    }
  '
  return 0
}

case "$SUBCMD" in
  create)  cmd_create ;;
  cleanup) cmd_cleanup ;;
  list)    cmd_list ;;
  *)       err "Unknown subcommand: $SUBCMD"; usage; exit 2 ;;
esac
exit $?
