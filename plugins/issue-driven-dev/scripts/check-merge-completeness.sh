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
#   0. CONTAINMENT (#399). A squash keeps the branch's final content, not each
#      commit, so first ask whether some first-parent baseline commit descending
#      from the merge-base held the branch's whole net change (`git merge-tree` of
#      the branch head into it is clean and leaves its tree unchanged). Yes → exit 0
#      — "landed at some point". Not trusted when every path the branch changed is
#      back to its merge-base state at the baseline tip (a wholesale revert). Only
#      the oldest 200 such commits are tried; git < 2.40 (no `merge-tree
#      --write-tree` / `--attr-source`) skips this step.
#   1. `git cherry <baseline> <branch>` → '+'-marked commits are patch-id-absent
#      from the baseline (candidate orphans).
#   2. CONTENT-VERIFY each candidate by *line presence*, NOT cherry-pick. A
#      cherry-pick is a 3-way merge and conflicts when the same file was touched
#      by >1 commit and then squash-merged — the common TDD branch shape — which
#      flagged fully-landed branches as false orphans (#184 DA-2). Instead we ask:
#      are the commit's ADDED lines present in the baseline's version of the files
#      it touched? Squash → lines present → not an orphan. Partial merge → the
#      dropped commit's lines are absent → orphan. A line the branch head itself no
#      longer has (a later branch commit rewrote it) is skipped (#399).
#
# Warn-only contract: exit 3 is surfaced via AskUserQuestion by idd-close; it is
# NOT a hard block, because the check is best-effort. Known blind spots:
#   - a dropped pure deletion (no added lines to look for);
#   - an added line that coincidentally appears elsewhere in the baseline;
#   - after the branch landed, a later baseline commit that overwrote only PART of
#     its change (indistinguishable from a follow-up edit) — step 0 accepts it;
#   - a squash whose conflicts were resolved by hand differs from the branch head,
#     so step 0 cannot match it and step 2 may flag lines main edited after landing.
# On exit 3 the result of step 0 is printed after the list.
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

# Containment (#399): a squash keeps the branch's FINAL content, not each commit.
# If some first-parent baseline commit C that descends from the merge-base holds
# the branch's whole net change — merging the branch head into C is clean and
# leaves C's tree unchanged — the branch landed in C. Trying every such C, not only
# the tip, lets a later follow-up that edits the same lines pass (#408: a release
# date changed after the squash); the 3-way merge lets a squash of a never-rebased
# branch pass. What it accepts is "landed at some point": a squash that main later
# reverted WHOLESALE is caught below, but a later commit that overwrites only PART
# of the change cannot be told apart from a follow-up edit and is accepted. Repo
# merge drivers are neutralised (empty attribute source) so a `merge=ours`-style
# driver cannot make a conflict look contained. merge-tree writes unreachable
# tree/blob objects into the repo's object store; gc prunes them.
CONTAINMENT_WALK=200   # oldest N baseline commits after the merge-base; a squash is normally among the first
EMPTY_TREE="$(GIT hash-object -t tree /dev/null 2>/dev/null)"
MT() { git -C "$REPO" -c core.attributesFile=/dev/null --attr-source="$EMPTY_TREE" merge-tree --write-tree "$@"; }
CONTAINMENT_NOTE=""
contained_in_baseline() {
  local mb list c t p
  local -a paths=()
  mb="$(GIT merge-base "$BASELINE_SHA" "$BRANCH_SHA" 2>/dev/null)" \
    || { CONTAINMENT_NOTE="no merge-base between branch and baseline"; return 1; }
  # merge-tree --write-tree (git 2.38) and --attr-source (git 2.40); an older git fails this probe
  [ -n "$EMPTY_TREE" ] && MT "$BASELINE_SHA" "$BASELINE_SHA" >/dev/null 2>&1 \
    || { CONTAINMENT_NOTE="skipped: git lacks merge-tree --write-tree / --attr-source (needs 2.40+)"; return 1; }
  # Wholesale revert: every path the branch changed is back to its merge-base state
  # at the tip, so nothing of the branch is in the baseline now, whatever landed.
  while IFS= read -r -d '' p; do paths+=("$p"); done < <(GIT diff --no-renames --name-only -z "$mb" "$BRANCH_SHA" --)
  if [ ${#paths[@]} -gt 0 ] && GIT --literal-pathspecs diff --quiet "$mb" "$BASELINE_SHA" -- "${paths[@]}" 2>/dev/null; then
    CONTAINMENT_NOTE="every path the branch changed is back to its merge-base state at '$BASELINE' (reverted)"; return 1
  fi
  # --ancestry-path: only descendants of the merge-base. A first-parent commit that
  # is merely unreachable from it (main's side of a later merge) is measured against
  # an OLDER base, where a branch that undoes its own starting point looks empty.
  list="$(GIT rev-list --first-parent --ancestry-path --reverse "${mb}..${BASELINE_SHA}" 2>/dev/null | head -n "$CONTAINMENT_WALK")"
  [ -n "$list" ] || { CONTAINMENT_NOTE="no baseline commit descends from the merge-base"; return 1; }
  while IFS= read -r c; do
    # A conflict is never containment, even when the written tree equals C's
    # (modify/delete keeps C's side) — hence the exit status, not just the tree.
    t="$(MT "$c" "$BRANCH_SHA" 2>/dev/null)" || continue
    [ "${t%%$'\n'*}" = "$(GIT rev-parse "${c}^{tree}")" ] && return 0
  done <<< "$list"
  CONTAINMENT_NOTE="none of the oldest $CONTAINMENT_WALK baseline commits after the merge-base contains the branch's net change"
  return 1
}
contained_in_baseline && exit 0

# Lines the branch still adds at its head (net change since the merge-base). A line
# an earlier branch commit added and a later one rewrote is not among them: its
# absence from the baseline says nothing about whether the branch landed (#399).
NET_ADDED="" ; HAVE_NET=""
if MB_NET="$(GIT merge-base "$BASELINE_SHA" "$BRANCH_SHA" 2>/dev/null)"; then
  NET_ADDED="$(GIT diff -M --format= "$MB_NET" "$BRANCH_SHA" 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+' | sed 's/^\+//')"
  HAVE_NET=1
fi

# Candidate orphans = '+'-marked commits (patch-id absent from baseline).
CANDIDATES=$(GIT cherry "$BASELINE_SHA" "$BRANCH_SHA" 2>/dev/null | awk '$1=="+"{print $2}')
[ -n "$CANDIDATES" ] || exit 0

# Content-verify each candidate by line presence against the baseline.
orphan_p() { # <commit-sha> -> 0 if genuinely orphaned (added content missing from baseline)
  local sha="$1" f base_content added line
  # files this commit touched
  local files; files="$(GIT show --format= --name-only "$sha" 2>/dev/null | sed '/^$/d')"
  # baseline content of those files (absent file -> empty -> its added lines count
  # as missing). while-read (not `for f in $files`) so paths with spaces are not
  # word-split into bogus filenames — which would empty base_content and false-flag
  # a landed commit (#184 R2: same false-positive class, retriggered by a space).
  base_content=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    base_content+="$(GIT show "${BASELINE_SHA}:${f}" 2>/dev/null)"$'\n'
  done <<< "$files"
  # added lines in this commit (strip the +++ file header; drop leading '+')
  added="$(GIT show --format= -p "$sha" 2>/dev/null | grep -E '^\+' | grep -vE '^\+\+\+' | sed 's/^\+//')"
  [ -n "$added" ] || return 1   # no added content (e.g. pure deletion) -> not detectable here
  while IFS= read -r line; do
    [ -z "${line//[[:space:]]/}" ] && continue          # ignore blank / whitespace-only lines
    # superseded within the branch itself (#399): not evidence of anything missing
    if [ -n "$HAVE_NET" ] && ! printf '%s\n' "$NET_ADDED" | grep -Fxq -- "$line"; then continue; fi
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
[ -z "$CONTAINMENT_NOTE" ] || echo "Containment check (#399): $CONTAINMENT_NOTE"
exit 3
