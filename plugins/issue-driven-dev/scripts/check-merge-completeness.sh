#!/usr/bin/env bash
# check-merge-completeness.sh — detect orphan commits on an issue branch that
# never landed in the baseline (PsychQuant/issue-driven-development#184).
#
# `idd-close` Step 1.5 only checks the PR is *merged*; it cannot see that a
# *partial* merge left a fix commit on the branch but not on main. This helper
# closes that gap: it finds commits on <branch> whose CONTENT is absent from
# <baseline> (usually origin/<default>), filtering the squash-merge false
# positive (squash rewrites every patch-id, so `git cherry` alone flags
# everything — we content-verify each candidate before reporting it).
#
# Usage:
#   check-merge-completeness.sh --branch <ref> --baseline <ref> [--repo <root>]
#
# Exit codes:
#   0 — clean: no genuine orphan (branch fully landed, or only false positives)
#   2 — usage error
#   3 — genuine orphan(s) found; SHAs + subjects printed to stdout
#   4 — skip: branch or baseline unresolvable (e.g. direct-commit issue with no
#       branch, or branch ref deleted) — caller should skip the gate, never block
#
# Warn-only contract: the caller (idd-close) surfaces exit 3 via AskUserQuestion;
# it does NOT hard-block, because content-verify is best-effort.
set -u

usage() { echo "usage: $0 --branch <ref> --baseline <ref> [--repo <root>]" >&2; exit 2; }

BRANCH="" ; BASELINE="" ; REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --branch)   BRANCH="${2:-}";   shift 2 || usage ;;
    --baseline) BASELINE="${2:-}"; shift 2 || usage ;;
    --repo)     REPO="${2:-}";     shift 2 || usage ;;
    *) usage ;;
  esac
done
[ -n "$BRANCH" ] && [ -n "$BASELINE" ] || usage

if [ -z "$REPO" ]; then
  REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 2; }
fi
GIT() { git -C "$REPO" "$@"; }

# Skip (exit 4, never block) when either ref is unresolvable.
GIT rev-parse --verify --quiet "$BRANCH"   >/dev/null || exit 4
GIT rev-parse --verify --quiet "$BASELINE" >/dev/null || exit 4

# Candidate orphans = `+`-marked commits (patch-id absent from baseline).
# `git cherry <upstream> <head>`: '+' not-in-upstream, '-' in-upstream.
CANDIDATES=$(GIT cherry "$BASELINE" "$BRANCH" 2>/dev/null | awk '$1=="+"{print $2}')
[ -n "$CANDIDATES" ] || exit 0   # nothing even patch-id-absent → clean

# Throwaway worktree checked out at the baseline; content-verify each candidate
# by cherry-picking it on top and inspecting the result.
BASE_TMP="$(mktemp -d)"
WT="$BASE_TMP/wt"
cleanup() {
  GIT worktree remove --force "$WT" >/dev/null 2>&1
  rm -rf "$BASE_TMP"
}
trap cleanup EXIT
if ! GIT worktree add --detach -q "$WT" "$BASELINE" >/dev/null 2>&1; then
  # Cannot stand up a verification worktree → skip rather than mis-report.
  exit 4
fi

ORPHANS=""
for sha in $CANDIDATES; do
  git -C "$WT" cherry-pick --no-commit "$sha" >/dev/null 2>&1
  if git -C "$WT" ls-files -u 2>/dev/null | grep -q .; then
    # conflict → the change touches content that diverged from baseline → orphan
    ORPHANS="$ORPHANS$sha"$'\n'
  elif git -C "$WT" diff --cached --quiet 2>/dev/null; then
    : # nothing staged → content already present in baseline → false positive
  else
    # staged a real change not in baseline → genuine orphan
    ORPHANS="$ORPHANS$sha"$'\n'
  fi
  # reset the worktree for the next candidate
  git -C "$WT" cherry-pick --abort >/dev/null 2>&1
  git -C "$WT" reset --hard "$BASELINE" -q >/dev/null 2>&1
  git -C "$WT" clean -fdxq >/dev/null 2>&1
done

ORPHANS="$(printf '%s' "$ORPHANS" | sed '/^$/d')"
[ -n "$ORPHANS" ] || exit 0

echo "Orphan commits on '$BRANCH' whose content is NOT in '$BASELINE':"
while IFS= read -r sha; do
  [ -n "$sha" ] || continue
  printf '  %s  %s\n' "$(GIT rev-parse --short "$sha")" "$(GIT log -1 --format=%s "$sha")"
done <<< "$ORPHANS"
exit 3
