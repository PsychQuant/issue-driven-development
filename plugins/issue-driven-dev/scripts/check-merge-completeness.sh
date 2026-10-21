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
#   4 — skip: branch or baseline unresolvable, or no temp dir — caller skips the gate, never blocks
#
# Method:
#   1. `git cherry <baseline> <branch>` → '+'-marked commits are patch-id-absent
#      from the baseline (candidate orphans). None → exit 0.
#   2. LANDING COMMIT (#399). A squash keeps the branch's final content, not each
#      commit, and main may edit it afterwards. Walking the baseline's first-parent
#      history back from the tip, find the newest commit L that descends from the
#      merge-base and holds the branch's whole net change (`git merge-tree` of the
#      branch head into L is clean and leaves L's tree unchanged). The gate answers
#      "did the branch's content land": what main did after L — a follow-up edit, a
#      revert — is main's own history and out of scope. At most the newest 200
#      commits are tried; git < 2.38 (no `merge-tree --write-tree`) skips this step.
#   3. CONTENT-VERIFY each candidate by *line presence*, NOT cherry-pick. A
#      cherry-pick is a 3-way merge and conflicts when the same file was touched
#      by >1 commit and then squash-merged — the common TDD branch shape — which
#      flagged fully-landed branches as false orphans (#184 DA-2). Instead we ask:
#      are the commit's ADDED lines present in L's version of the files it touched
#      (the tip's when there is no L)? Squash → lines present → not an orphan.
#      Partial merge → the dropped commit's lines are absent → orphan. A line the
#      branch head itself no longer has in those files (a later branch commit
#      rewrote or deleted it) is skipped (#399).
#
# Warn-only contract: exit 3 is surfaced via AskUserQuestion by idd-close; it is
# NOT a hard block, because the check is best-effort. Known blind spots:
#   - a dropped pure deletion (no added lines to look for);
#   - an added line that coincidentally appears elsewhere in the touched files;
#   - by design, anything main did after the branch landed (a revert, an overwrite);
#   - a squash whose conflicts were resolved by hand differs from the branch head,
#     so step 2 finds no L and step 3 may flag lines main edited after landing;
#   - a landing commit more than 200 first-parent commits behind the tip.
# On exit 3 the outcome of step 2 is printed after the list.
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

# Landing commit (#399): the newest first-parent baseline commit L, descending from
# the merge-base, that holds the branch's whole net change — merging the branch
# head into L is clean and leaves L's tree unchanged. Lines are then checked against
# L, so main's later edits to them (#408: a release date changed after the squash)
# and the squash of a never-rebased branch both pass.
#
# merge-tree runs in a throwaway bare repository that borrows the repo's objects.
# No config reaches it — not the repo's, the user's, the system's, nor any passed
# down through the environment — so no merge driver is defined and none runs,
# whatever .gitattributes, .git/info/attributes or merge.default name; attributes
# can then pick only git's built-in text/binary/union merges, none of which turns
# a conflict into C's own tree. The objects it writes go away with it.
LANDING_WALK=200   # newest N; idd-close runs right after the merge, so L is near the tip
LANDING="" ; LANDING_NOTE=""
SCRATCH="$(mktemp -d)" || { echo "cannot create a temp dir" >&2; exit 4; }
trap 'rm -rf "$SCRATCH"' EXIT
ISO="$SCRATCH/iso"
ISOGIT() {
  env -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY -u GIT_COMMON_DIR \
      -u GIT_CONFIG -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT \
      GIT_DIR="$ISO" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null git "$@"
}
iso_init() {
  local objs
  objs="$(GIT rev-parse --path-format=absolute --git-common-dir 2>/dev/null)/objects" && [ -d "$objs" ] || return 1
  ISOGIT init -q --bare --template= >/dev/null 2>&1 || return 1
  mkdir -p "$ISO/objects/info" && printf '%s\n' "$objs" > "$ISO/objects/info/alternates"
}
find_landing() {
  local mb list c t n=0
  mb="$(GIT merge-base "$BASELINE_SHA" "$BRANCH_SHA" 2>/dev/null)" \
    || { LANDING_NOTE="no merge-base between branch and baseline"; return 1; }
  iso_init || { LANDING_NOTE="skipped: could not set up a scratch repository for merge-tree"; return 1; }
  ISOGIT merge-tree --write-tree "$BASELINE_SHA" "$BASELINE_SHA" >/dev/null 2>&1 \
    || { LANDING_NOTE="skipped: git lacks merge-tree --write-tree (needs 2.38+)"; return 1; }
  list="$(GIT rev-list --first-parent "${mb}..${BASELINE_SHA}" 2>/dev/null)"
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    # Only descendants of the merge-base. A first-parent commit merely unreachable
    # from it (main's side before a later merge) is measured against an OLDER base,
    # where a branch that undoes its own starting point looks contained. Once one is
    # not a descendant, none of its first-parent ancestors is.
    GIT merge-base --is-ancestor "$mb" "$c" || break
    if [ "$n" -ge "$LANDING_WALK" ]; then
      LANDING_NOTE="no landing commit among the newest $LANDING_WALK baseline commits after the merge-base (older ones not tried)"
      return 1
    fi
    n=$((n + 1))
    # A conflict is never landing, even when the written tree equals C's
    # (modify/delete keeps C's side) — hence the exit status, not just the tree.
    t="$(ISOGIT merge-tree --write-tree "$c" "$BRANCH_SHA" 2>/dev/null)" || continue
    [ "${t%%$'\n'*}" = "$(GIT rev-parse "${c}^{tree}")" ] && { LANDING="$c"; return 0; }
  done <<< "$list"
  LANDING_NOTE="no baseline commit after the merge-base holds the branch's net change ($n tried)"
  return 1
}
find_landing
TARGET="${LANDING:-$BASELINE_SHA}"

# Content-verify each candidate by line presence against TARGET. Plumbing only
# (diff-tree, cat-file): porcelain `git show` applies the user's diff.external,
# textconv and color settings, any of which can leave a patch with no `+` lines.
#
# TARGET's and the branch head's content of every path a candidate touched, read
# once per path (absent file -> empty): a CHANGELOG every commit edits is read
# twice, not twice per commit. -z so a space or a non-ASCII name (quoted by
# core.quotePath) reaches cat-file as the real path (#184 R2: a bad path empties
# the content). The echo keeps a file without a final newline from running into
# the next one. Indexed arrays and a linear search: bash 3.2 has no associative
# arrays.
UPATHS=() ; CIDX=() ; k=0
for sha in $CANDIDATES; do
  idx=""
  while IFS= read -r -d '' f; do
    j=0; while [ "$j" -lt "${#UPATHS[@]}" ] && [ "${UPATHS[$j]}" != "$f" ]; do j=$((j + 1)); done
    [ "$j" -lt "${#UPATHS[@]}" ] || UPATHS[$j]="$f"
    idx="$idx $j"
  done < <(GIT diff-tree --root --no-commit-id --name-only -r -z "$sha" 2>/dev/null)
  CIDX[$k]="$idx"; k=$((k + 1))
done
j=0
while [ "$j" -lt "${#UPATHS[@]}" ]; do
  { GIT cat-file blob "${TARGET}:${UPATHS[$j]}" 2>/dev/null; echo; } > "$SCRATCH/t.$j"
  { GIT cat-file blob "${BRANCH_SHA}:${UPATHS[$j]}" 2>/dev/null; echo; } > "$SCRATCH/h.$j"
  j=$((j + 1))
done

orphan_p() { # <commit-sha> <indices of the paths it touched> -> 0 if genuinely orphaned
  local sha="$1" j T="$SCRATCH/target" H="$SCRATCH/head" A="$SCRATCH/added"
  local -a tf=() hf=()
  for j in $2; do tf+=("$SCRATCH/t.$j"); hf+=("$SCRATCH/h.$j"); done
  : > "$T"; : > "$H"
  if [ ${#tf[@]} -gt 0 ]; then cat "${tf[@]}" > "$T"; cat "${hf[@]}" > "$H"; fi
  # added lines in this commit (strip the +++ file header; drop leading '+')
  GIT diff-tree --root --no-commit-id -r -p --no-ext-diff --no-textconv --no-color "$sha" 2>/dev/null \
    | grep -E '^\+' | grep -vE '^\+\+\+' | sed 's/^\+//' > "$A"
  # Orphan when some added line, not blank, is in the branch head's version of the
  # files and not in TARGET's. A line the head no longer has was superseded within
  # the branch itself (#399), so its absence from TARGET says nothing. One awk pass
  # with exact whole-line matching: a grep per line costs minutes on a branch that
  # edits a large CHANGELOG. No added content (e.g. a pure deletion) -> not
  # detectable here.
  LC_ALL=C awk '
    FILENAME == ARGV[1] { head[$0] = 1; next }
    FILENAME == ARGV[2] { target[$0] = 1; next }
    /^[ \t\r\f\v]*$/    { next }
    ($0 in head) && !($0 in target) { found = 1; exit }
    END { exit !found }' "$H" "$T" "$A"
}

ORPHANS="" ; k=0
for sha in $CANDIDATES; do
  if orphan_p "$sha" "${CIDX[$k]}"; then ORPHANS="$ORPHANS$sha"$'\n'; fi
  k=$((k + 1))
done

ORPHANS="$(printf '%s' "$ORPHANS" | sed '/^$/d')"
[ -n "$ORPHANS" ] || exit 0

echo "Orphan commits on '$BRANCH' whose content did NOT land in '$BASELINE':"
while IFS= read -r sha; do
  [ -n "$sha" ] || continue
  printf '  %s  %s\n' "$(GIT rev-parse --short "$sha")" "$(GIT log -1 --format=%s "$sha")"
done <<< "$ORPHANS"
if [ -n "$LANDING" ]; then
  printf "Landing check (#399): the branch's net change landed in %s  %s; the lines above are not in it.\n" \
    "$(GIT rev-parse --short "$LANDING")" "$(GIT log -1 --format=%s "$LANDING")"
else
  echo "Landing check (#399): $LANDING_NOTE; lines were checked against '$BASELINE'."
fi
exit 3
