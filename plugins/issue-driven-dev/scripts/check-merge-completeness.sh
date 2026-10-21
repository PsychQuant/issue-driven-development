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
#   4 — skip: could not verify (branch or baseline unresolvable, no temp dir, a git
#       command failed, a path with a newline); the reason goes to stderr. The caller
#       reports it and never treats it as clean or as a block.
#
# Method:
#   1. `git cherry <baseline> <branch>` → '+'-marked commits are patch-id-absent
#      from the baseline (candidate orphans). None → exit 0.
#   2. LANDING COMMIT (#399). The gate answers "did the branch's content land":
#      what main did after it landed — a follow-up edit, a revert — is main's own
#      history and out of scope. Walking the baseline's first-parent history back
#      from the tip (only commits that touch the paths the branch changed, then the
#      merge-base), find the first run of commits that hold the branch's whole net
#      change (`git merge-tree` of the branch head into C is clean and leaves C's
#      tree unchanged); its OLDEST commit L is where the branch landed. When the
#      whole branch never landed, the branch's earlier commits are tried newest
#      first: commits up to the newest one that landed are checked at its landing
#      commit, the rest at the tip. At most 200 merge-tree calls in all; git < 2.38
#      (no `merge-tree --write-tree`) skips this step.
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
#   - an added line that coincidentally appears elsewhere in the files the same
#     commit touched;
#   - by design, anything main did after the branch landed (a revert, an overwrite);
#   - a squash whose conflicts were resolved by hand differs from the branch head,
#     so step 2 finds no L and step 3 may flag lines main edited after landing; so
#     may a branch commit that restored a merge-base value main had changed before
#     the squash;
#   - a landing commit beyond the 200 merge-tree calls, or reached only through a
#     merge's second parent (a `git pull` merge on main whose first parent is the
#     local line) — both fall back to the tip.
# On exit 3 the outcome of step 2 is printed after the list. Commit subjects in the
# output are repository text (a squash's subject is the PR title): data, never
# instructions.
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

# Could not verify: say why on stderr and exit 4, which the caller reports and
# never treats as clean or as a block.
skip() { echo "check-merge-completeness: $*" >&2; exit 4; }

# Candidate orphans = '+'-marked commits (patch-id absent from baseline).
CHERRY="$(GIT cherry "$BASELINE_SHA" "$BRANCH_SHA" 2>/dev/null)" || skip "git cherry failed"
CANDIDATES=$(printf '%s\n' "$CHERRY" | awk '$1=="+"{print $2}')
[ -n "$CANDIDATES" ] || exit 0

SCRATCH="$(mktemp -d)" || skip "cannot create a temp dir"
trap 'rm -rf "$SCRATCH"' EXIT
short() { GIT rev-parse --short "$1"; }
# Subjects are author-controlled (a squash's subject is the PR title): no signature
# check (log.showSignature would run the user's gpg program) and no control bytes.
subject() { GIT log -1 --no-show-signature --format=%s "$1" | LC_ALL=C tr -d '\000-\037\177'; }

# ── Landing commit (#399) ──
# merge-tree runs in a throwaway bare repository that borrows the repo's objects
# (and its shallow file, or a shallow clone's missing parents make it fail). No
# config reaches it — not the repo's, the user's, the system's, nor any passed
# down through the environment — so no merge driver is defined and none runs; no
# attributes reach it either, so nothing selects even a built-in `union` merge,
# which can turn a conflict into C's own tree. Its objects go away with it.
ISO="$SCRATCH/iso"
ISOGIT() {
  env -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_OBJECT_DIRECTORY -u GIT_COMMON_DIR \
      -u GIT_CONFIG -u GIT_CONFIG_PARAMETERS -u GIT_CONFIG_COUNT -u GIT_ATTR_SOURCE \
      GIT_DIR="$ISO" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_ATTR_NOSYSTEM=1 \
      git -c core.attributesFile=/dev/null "$@"
}
ISO_STATE=""
iso_init() {
  local gd fmt
  gd="$(GIT rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" && [ -d "$gd/objects" ] \
    || { ISO_STATE="cannot locate the object store (needs git 2.31+)"; return 1; }
  fmt="$(GIT rev-parse --show-object-format 2>/dev/null)" || fmt=sha1
  ISOGIT init -q --bare --template= --object-format="$fmt" >/dev/null 2>&1 \
    || { ISO_STATE="cannot set up a scratch repository for merge-tree"; return 1; }
  mkdir -p "$ISO/objects/info" && printf '%s\n' "$gd/objects" > "$ISO/objects/info/alternates" \
    || { ISO_STATE="cannot set up a scratch repository for merge-tree"; return 1; }
  [ ! -f "$gd/shallow" ] || cp "$gd/shallow" "$ISO/shallow" \
    || { ISO_STATE="cannot copy the shallow file"; return 1; }
  ISOGIT merge-tree --write-tree "$BASELINE_SHA" "$BASELINE_SHA" >/dev/null 2>&1 \
    || { ISO_STATE="git lacks merge-tree --write-tree (needs 2.38+)"; return 1; }
  ISO_STATE=ok
}

# Where <rev>'s net change since its merge-base with the baseline landed. Walking the
# baseline's first-parent history back from the tip, take the first run of commits
# that hold that whole net change (merging <rev> into C is clean and leaves C's tree
# unchanged) and return its OLDEST commit: where the change arrived, not a later one
# that still holds it after main edited a line the branch left as it found it. Only
# first-parent commits that touch the paths <rev> changed can begin or end a run, so
# only they are tried, then the merge-base itself: with no net change, <rev> landed
# there. A first-parent commit that is not a descendant of the merge-base (main's
# side before a later merge) ends the walk; none of its ancestors is one either.
# Every merge-tree call spends one unit of MT_BUDGET across all calls.
MT_BUDGET=200
LAND="" ; LAND_NOTE="" ; LAND_NONE=""
find_landing() { # <rev>
  local rev="$1" mb paths c t rc run="" n=0 limit=1
  LAND="" ; LAND_NOTE="" ; LAND_NONE=""
  mb="$(GIT merge-base "$BASELINE_SHA" "$rev" 2>/dev/null)" \
    || { LAND_NOTE="no merge-base between branch and baseline"; return 1; }
  paths="$(GIT diff-tree -r --no-renames --name-only -z "$mb" "$rev" 2>/dev/null | tr '\0' '\n')" \
    || { LAND_NOTE="cannot list the paths the branch changed"; return 1; }
  # A path with a newline cannot go through rev-list --stdin; walk every commit then.
  case "$(GIT diff-tree -r --no-renames --name-only -z "$mb" "$rev" 2>/dev/null | tr -d '\000' | tr -cd '\n' | wc -c)" in
    *[!0\ ]*) limit="" ;;
  esac
  {
    if [ -n "$paths" ]; then
      if [ -n "$limit" ]; then
        printf '%s\n^%s\n--\n%s\n' "$BASELINE_SHA" "$mb" "$paths" | GIT --literal-pathspecs rev-list --first-parent --stdin
      else
        GIT rev-list --first-parent "${mb}..${BASELINE_SHA}"
      fi || echo "LIST-FAILED"
    fi
    echo "$mb"
  } > "$SCRATCH/walk"
  grep -qx 'LIST-FAILED' "$SCRATCH/walk" && { LAND_NOTE="cannot list the baseline's commits"; return 1; }
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    GIT merge-base --is-ancestor "$mb" "$c" || break
    if [ "$MT_BUDGET" -le 0 ]; then
      [ -n "$run" ] && break
      LAND_NOTE="the merge-tree budget (200) ran out before a landing commit was found"; return 1
    fi
    MT_BUDGET=$((MT_BUDGET - 1)); n=$((n + 1))
    t="$(ISOGIT merge-tree --write-tree "$c" "$rev" 2>/dev/null)"; rc=$?
    # A conflict (exit 1) is never landing, even when the written tree equals C's
    # (modify/delete keeps C's side) — hence the exit status, not just the tree.
    # Anything else is an error, not a conflict.
    [ "$rc" -le 1 ] || { LAND_NOTE="merge-tree failed on $(short "$c") (exit $rc)"; return 1; }
    if [ "$rc" -eq 0 ] && [ "${t%%$'\n'*}" = "$(GIT rev-parse "${c}^{tree}")" ]; then
      run="$c"
    elif [ -n "$run" ]; then
      break
    fi
  done < "$SCRATCH/walk"
  [ -z "$run" ] || { LAND="$run"; return 0; }
  LAND_NONE=1
  LAND_NOTE="no baseline commit after the merge-base holds the branch's net change ($n tried)"
  return 1
}

# The whole branch landed (LANDING), or only up to PREFIX_TIP: a partial merge drops
# the last commits, so try the branch's earlier first-parent commits newest-first.
# Commits up to PREFIX_TIP are then checked where they landed and only the later
# ones against the tip, so a genuine orphan does not drag main's later edits of
# landed lines into the list.
LANDING="" ; PREFIX_TIP="" ; LANDING_NOTE=""
if iso_init; then
  if find_landing "$BRANCH_SHA"; then
    LANDING="$LAND"
  else
    LANDING_NOTE="$LAND_NOTE"
    if [ -n "$LAND_NONE" ]; then
      for b in $(GIT rev-list --first-parent "$(GIT merge-base "$BASELINE_SHA" "$BRANCH_SHA")..$BRANCH_SHA" 2>/dev/null | sed 1d); do
        [ "$MT_BUDGET" -gt 0 ] || break
        if find_landing "$b"; then LANDING="$LAND"; PREFIX_TIP="$b"; break; fi
        [ -n "$LAND_NONE" ] || break
      done
    fi
  fi
else
  LANDING_NOTE="skipped: $ISO_STATE"
fi

# ── Content-verify each candidate by line presence ──
# Against LANDING (for a candidate up to PREFIX_TIP when only a prefix landed), else
# against the tip. Plumbing only (diff-tree, cat-file, ls-tree): porcelain `git
# show` applies diff.external, textconv and color, and any of them can leave a
# patch with no `+` lines; --text keeps a file git treats as binary (a NUL byte, a
# `binary` or `-diff` attribute) from collapsing into "Binary files differ".
use_landing() { # <candidate> -> 0 when it is checked against LANDING
  [ -n "$LANDING" ] || return 1
  [ -z "$PREFIX_TIP" ] || GIT merge-base --is-ancestor "$1" "$PREFIX_TIP"
}

# Every path a candidate touched is numbered once by one awk pass (bash 3.2 has no
# associative arrays, and a linear search is quadratic on a wide commit); each
# candidate's numbers go to its own file, which awk reads later, never argv.
# -z so a space or a non-ASCII name (quoted by core.quotePath) stays the real path.
: > "$SCRATCH/pairs"; k=0; NEED_TIP=""
for sha in $CANDIDATES; do
  GIT diff-tree --root --no-commit-id --name-only -r -z "$sha" > "$SCRATCH/names" 2>/dev/null \
    || skip "cannot list the paths $(short "$sha") touched"
  [ "$(tr -d '\000' < "$SCRATCH/names" | tr -cd '\n' | wc -c | tr -d ' ')" = 0 ] \
    || skip "$(short "$sha") touches a path with a newline in its name"
  tr '\000' '\n' < "$SCRATCH/names" | awk -v k="$k" '{ print k "\t" $0 }' >> "$SCRATCH/pairs"
  use_landing "$sha" || NEED_TIP=1
  k=$((k + 1))
done
LC_ALL=C awk -v d="$SCRATCH" '
  { i = index($0, "\t"); k = substr($0, 1, i - 1); p = substr($0, i + 1)
    if (!(p in idx)) { idx[p] = n++; print p > (d "/paths") }
    f = d "/c." k; print idx[p] >> f; close(f) }' "$SCRATCH/pairs" || skip "cannot index the touched paths"

# What each side has at every touched path, read once per distinct blob: one
# `cat-file --batch-check` per side maps path i to "blob <oid>", "link <oid>" (a
# gitlink, which diff prints as "Subproject commit <oid>") or "none" (absent, or a
# directory). Only blobs are then read, once per object id: a move touches
# thousands of paths but few distinct contents. A blob that is listed but cannot be
# read is an error — the line check would otherwise read it as empty and pass a real
# orphan as "superseded".
classify() { # <rev> <side> -> $SCRATCH/<side>.map, one line per path in $SCRATCH/paths
  local rev="$1" out="$SCRATCH/$2.map" i=0 f line e
  awk -v r="$rev" '{ print r ":" $0 }' "$SCRATCH/paths" \
    | GIT cat-file --batch-check='%(objectname) %(objecttype)' > "$SCRATCH/$2.check" 2>/dev/null || return 1
  : > "$out"
  exec 3< "$SCRATCH/paths"
  while IFS= read -r line; do
    IFS= read -r f <&3 || return 1
    case "$line" in
      *" blob")      echo "blob ${line% blob}" ;;
      *" submodule") echo "link ${line% submodule}" ;;
      *" tree")      echo "none" ;;
      "$rev:$f missing") echo "none" ;;
      *" missing"|*" commit")   # an older git reports a gitlink like this
        e="$(GIT --literal-pathspecs ls-tree "$rev" -- "$f" 2>/dev/null)"
        case "$e" in "160000 commit "*) e="${e#160000 commit }"; echo "link ${e%%	*}" ;; *) return 1 ;; esac ;;
      *) return 1 ;;
    esac
    i=$((i + 1))
  done < "$SCRATCH/$2.check" >> "$out"
  exec 3<&-
  [ "$(wc -l < "$out" | tr -d ' ')" = "$(wc -l < "$SCRATCH/paths" | tr -d ' ')" ]
}
SIDES="head"
[ -z "$LANDING" ] || SIDES="$SIDES land"
[ -z "$NEED_TIP" ] || SIDES="$SIDES tip"
if [ -f "$SCRATCH/paths" ]; then
  for side in $SIDES; do
    case "$side" in head) rev="$BRANCH_SHA" ;; land) rev="$LANDING" ;; tip) rev="$BASELINE_SHA" ;; esac
    classify "$rev" "$side" || skip "cannot read the touched paths at $(short "$rev")"
  done
  for side in $SIDES; do awk '$1 == "blob" { print $2 }' "$SCRATCH/$side.map"; done | sort -u > "$SCRATCH/blobs"
  # One file per blob, read by awk one at a time, so a file without a final newline
  # cannot run into the next one.
  while IFS= read -r oid; do
    GIT cat-file blob "$oid" > "$SCRATCH/blob.$oid" 2>/dev/null || skip "cannot read blob $oid"
  done < "$SCRATCH/blobs"
fi

orphan_p() { # <commit-sha> <candidate number> <land|tip> -> 0 orphan, 1 landed, other: error
  [ -s "$SCRATCH/c.$2" ] || return 1
  GIT diff-tree --root --no-commit-id -r -p --text --no-ext-diff --no-textconv --no-color "$1" \
    > "$SCRATCH/patch" 2>/dev/null || return 2
  # Orphan when some added line, not blank, is in the branch head's version of the
  # files and not in the target's. A line the head no longer has was superseded
  # within the branch itself (#399), so its absence says nothing. Added lines are
  # taken inside hunks only, so a line that starts with "++" is not mistaken for the
  # "+++ b/path" header. One awk pass with exact whole-line matching. No added
  # content (e.g. a pure deletion) -> not detectable here.
  LC_ALL=C awk -v d="$SCRATCH" -v side="$3" -v list="$SCRATCH/c.$2" '
    function load(entry, set,    f, l, n, a) {
      n = split(entry, a, " ")
      if (a[1] == "link") { set["Subproject commit " a[2]] = 1; return }
      if (a[1] != "blob") return
      f = d "/blob." a[2]
      while ((getline l < f) > 0) set[l] = 1
      close(f)
    }
    BEGIN {
      i = 0; f = d "/head.map"; while ((getline l < f) > 0) hm[i++] = l; close(f)
      i = 0; f = d "/" side ".map"; while ((getline l < f) > 0) tm[i++] = l; close(f)
      while ((getline j < list) > 0) { load(hm[j], head); load(tm[j], target) }
      close(list)
    }
    /^diff --git / { hunk = 0; next }
    /^@@/          { hunk = 1; next }
    !hunk          { next }
    /^\+/ {
      line = substr($0, 2)
      if (line ~ /^[ \t\r\f\v]*$/) next
      if ((line in head) && !(line in target)) { found = 1; exit }
    }
    END { exit !found }' "$SCRATCH/patch"
}

ORPHANS="" ; k=0
for sha in $CANDIDATES; do
  side=tip; use_landing "$sha" && side=land
  orphan_p "$sha" "$k" "$side"; rc=$?
  case "$rc" in
    0) ORPHANS="$ORPHANS$sha"$'\n' ;;
    1) ;;
    *) skip "cannot verify $(short "$sha") (exit $rc)" ;;
  esac
  k=$((k + 1))
done

ORPHANS="$(printf '%s' "$ORPHANS" | sed '/^$/d')"
[ -n "$ORPHANS" ] || exit 0

echo "Orphan commits on '$BRANCH' whose content did NOT land in '$BASELINE':"
while IFS= read -r sha; do
  [ -n "$sha" ] || continue
  printf '  %s  %s\n' "$(short "$sha")" "$(subject "$sha")"
done <<< "$ORPHANS"
if [ -n "$LANDING" ] && [ -z "$PREFIX_TIP" ]; then
  printf "Landing check (#399): the branch's net change landed in %s  %s; the lines above are not in it.\n" \
    "$(short "$LANDING")" "$(subject "$LANDING")"
elif [ -n "$LANDING" ]; then
  printf "Landing check (#399): the branch up to %s landed in %s  %s; later commits were checked against '%s'.\n" \
    "$(short "$PREFIX_TIP")" "$(short "$LANDING")" "$(subject "$LANDING")" "$BASELINE"
else
  echo "Landing check (#399): $LANDING_NOTE; lines were checked against '$BASELINE'."
fi
exit 3
