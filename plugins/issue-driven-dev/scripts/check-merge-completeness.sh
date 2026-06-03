#!/usr/bin/env bash
# check-merge-completeness.sh — detect orphan commits on an issue branch whose
# content never landed in the baseline (PsychQuant/issue-driven-development#184).
#
# `idd-close` Step 1.5 only checks the PR is *merged*; it cannot see that a
# *partial* merge left a fix commit on the branch but not on main. This helper
# closes that gap.
#
# Usage:
#   check-merge-completeness.sh --branch <ref-or-sha> --baseline <ref> [--repo <root>]
#
#   --branch may be a branch name OR a commit SHA. idd-close passes the merged
#   PR's headRefOid (a SHA), which stays resolvable after GitHub deletes the
#   head branch on merge — a bare branch name does not (#184 DA-1).
#
# Exit codes:
#   0 — clean: no genuine orphan
#   2 — usage error
#   3 — genuine orphan(s) found; SHAs + subjects printed to stdout
#   4 — skip: branch or baseline unresolvable — caller skips the gate, never blocks
#
# Method:
#   1. `git cherry <baseline> <branch>` → '+'-marked commits are patch-id-absent
#      from the baseline (candidate orphans).
#   2. CONTENT-VERIFY each candidate by *line presence*, NOT cherry-pick. A
#      cherry-pick is a 3-way merge and conflicts when the same file was touched
#      by >1 commit and then squash-merged — the common TDD branch shape — which
#      flagged fully-landed branches as false orphans (#184 DA-2). Instead we ask:
#      are the commit's ADDED lines present in the baseline's version of the files
#      it touched? Squash → lines present → not an orphan. Partial merge → the
#      dropped commit's lines are absent → orphan.
#
# Warn-only contract: exit 3 is surfaced via AskUserQuestion by idd-close; it is
# NOT a hard block, because line-presence is best-effort (it cannot see a dropped
# pure-deletion, and a line could coincidentally appear elsewhere).
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

# Resolve both inputs to commit SHAs up front. `--end-of-options` prevents an
# option-shaped ref (attacker-controllable PR branch name like `--upload-pack=x`)
# from being parsed as a git option (#184 S1). A SHA can never be option-shaped,
# so every downstream git call is injection-safe. Unresolvable → skip (exit 4).
BRANCH_SHA="$(GIT rev-parse --verify --quiet --end-of-options "${BRANCH}^{commit}" 2>/dev/null)"   || exit 4
BASELINE_SHA="$(GIT rev-parse --verify --quiet --end-of-options "${BASELINE}^{commit}" 2>/dev/null)" || exit 4

# Candidate orphans = '+'-marked commits (patch-id absent from baseline).
CANDIDATES=$(GIT cherry "$BASELINE_SHA" "$BRANCH_SHA" 2>/dev/null | awk '$1=="+"{print $2}')
[ -n "$CANDIDATES" ] || exit 0

# Content-verify each candidate by line presence against the baseline.
orphan_p() { # <commit-sha> -> 0 if genuinely orphaned (added content missing from baseline)
  local sha="$1" f base_content added line
  # files this commit touched
  local files; files="$(GIT show --format= --name-only "$sha" 2>/dev/null | sed '/^$/d')"
  # baseline content of those files (absent file -> empty -> its added lines count as missing)
  base_content=""
  for f in $files; do
    base_content+="$(GIT show "${BASELINE_SHA}:${f}" 2>/dev/null)"$'\n'
  done
  # added lines in this commit (strip the +++ file header; drop leading '+')
  added="$(GIT show --format= -p "$sha" 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+' | sed 's/^\+//')"
  [ -n "$added" ] || return 1   # no added content (e.g. pure deletion) -> not detectable here
  while IFS= read -r line; do
    [ -z "${line//[[:space:]]/}" ] && continue          # ignore blank / whitespace-only lines
    printf '%s\n' "$base_content" | grep -Fxq -- "$line" || return 0   # an added line is absent -> orphan
  done <<< "$added"
  return 1   # every added line present in baseline -> landed
}

ORPHANS=""
for sha in $CANDIDATES; do
  if orphan_p "$sha"; then ORPHANS="$ORPHANS$sha"$'\n'; fi
done

ORPHANS="$(printf '%s' "$ORPHANS" | sed '/^$/d')"
[ -n "$ORPHANS" ] || exit 0

echo "Orphan commits on '$BRANCH' whose content is NOT in '$BASELINE':"
while IFS= read -r sha; do
  [ -n "$sha" ] || continue
  printf '  %s  %s\n' "$(GIT rev-parse --short "$sha")" "$(GIT log -1 --format=%s "$sha")"
done <<< "$ORPHANS"
exit 3
