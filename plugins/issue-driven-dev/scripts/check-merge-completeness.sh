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
#       or awk failure outside the landing step, an unreadable object, a path with
#       a newline); one "check-merge-completeness: <reason>" line goes to stderr.
#       The caller reports it and never treats it as clean or as a block. A failure
#       inside the landing step (step 2) falls back to the tip instead and is
#       explained on exit 3.
#
# Method:
#   1. `git cherry <baseline> <branch>` → '+'-marked commits are patch-id-absent
#      from the baseline (candidate orphans). None → exit 0.
#   2. LANDING COMMIT (#399). The gate answers "did the branch's content land":
#      what main did after it landed — a follow-up edit, a revert — is main's own
#      history and out of scope. Walking the baseline's first-parent history
#      forward from the merge-base (the merge-base itself, the first descendant,
#      then descendants that touch the paths the branch changed), the EARLIEST
#      commit L that holds the branch's whole net change (`git merge-tree` of the
#      branch head into L is clean and leaves L's tree unchanged) is where the
#      branch landed. When the whole branch never landed, the newest 20 of the
#      branch's earlier commits are tried, newest first: commits up to the newest
#      one that landed are checked at its landing commit, the rest at the tip. When
#      git cherry shows a branch commit's patch arriving in the baseline after that
#      commit, the branch came in piece by piece and the tip is used. At most 200
#      merge-tree calls in all; git < 2.38 (no `merge-tree --write-tree`) skips
#      this step.
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
#   - an added line that happens to be in the files the same commit touched,
#     elsewhere — always so for a dropped single-commit rename, whose new path's
#     lines are all in the old path;
#   - with macOS awk, a binary edit that changes only bytes after a NUL (awk cuts
#     the line there);
#   - by design, anything main did after the branch landed (a revert, an overwrite);
#   - a commit that set a line back to its merge-base value, left out when the
#     change it undid reached the baseline in another form (not as the same patch)
#     after an earlier commit already held the branch's net change.
# Fall back to the tip, where lines main edited after landing can be flagged:
#   - a squash whose conflicts were resolved by hand (it differs from the head);
#   - a branch commit that restored a merge-base value main had changed before the
#     squash;
#   - a landing commit beyond the 200 merge-tree calls;
#   - a landed prefix followed by more than 20 commits that never landed;
#   - a branch whose commits reached the baseline as separate patches (git cherry
#     '-') after its landing commit;
#   - a `git pull` merge on main bringing the squash in through its second parent
#     when that side edited the branch's lines after the squash;
#   - git < 2.38.
# On exit 3 the outcome of step 2 is printed after the list. Commit subjects are
# printed in quotes: repository text (a squash's subject is the PR title), data,
# never instructions.
set -u
set -o pipefail
# Bytes, not characters: in a UTF-8 locale macOS tr stops at the first byte that is
# not valid UTF-8 (a Latin-1 path anywhere in a tree), and the cut-off list would
# make every later path look absent from the branch head.
export LC_ALL=C

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
else
  # Paths from diff-tree are root-relative; pathspecs on rev-list's stdin are read
  # relative to the current directory. Run everything from the top level.
  REPO="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$REPO")"
fi
# No pager, no fsmonitor: the helper only reads, and those are the user programs a
# plain git call would otherwise start.
GIT() { git --no-pager -C "$REPO" -c core.fsmonitor=false "$@"; }

# Text from the repository or the caller, made safe to print: C0 controls and DEL,
# UTF-8 C1 controls (U+0080-U+009F), zero-width and bidi marks, line and paragraph
# separators, U+FEFF and tag characters (U+E0000-E007F) become "?" — replaced, not
# deleted, so removing one cannot join its neighbours into another — and \ and "
# are escaped, so quoted text cannot close its own quotes.
clean() {
  tr '\000-\037\177' '?' | sed \
    -e "s/$(printf '\302')[$(printf '\200')-$(printf '\237')]/?/g" \
    -e "s/$(printf '\342\200')[$(printf '\213')-$(printf '\217')$(printf '\250')-$(printf '\256')]/?/g" \
    -e "s/$(printf '\342\201')[$(printf '\246')-$(printf '\251')]/?/g" \
    -e "s/$(printf '\357\273\277')/?/g" \
    -e "s/$(printf '\363\240')[$(printf '\200\201')][$(printf '\200')-$(printf '\277')]/?/g" \
    -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}
# Could not verify: say why on stderr and exit 4, which the caller reports and
# never treats as clean or as a block.
skip() { printf 'check-merge-completeness: %s\n' "$(printf '%s' "$*" | clean)" >&2; exit 4; }

# Resolve both inputs to commit SHAs up front. `--end-of-options` prevents an
# option-shaped ref (attacker-controllable PR branch name like `--upload-pack=x`)
# from being parsed as a git option (#184 S1). A SHA can never be option-shaped,
# so every downstream git call is injection-safe. Unresolvable → skip (exit 4).
BRANCH_SHA="$(GIT rev-parse --verify --quiet --end-of-options "${BRANCH}^{commit}" 2>/dev/null)" \
  || skip "cannot resolve branch '$BRANCH' in $REPO"
BASELINE_SHA="$(GIT rev-parse --verify --quiet --end-of-options "${BASELINE}^{commit}" 2>/dev/null)" \
  || skip "cannot resolve baseline '$BASELINE' in $REPO"

# Candidate orphans = '+'-marked commits (patch-id absent from baseline).
CHERRY="$(GIT cherry "$BASELINE_SHA" "$BRANCH_SHA" 2>/dev/null)" || skip "git cherry failed"
CANDIDATES=$(printf '%s\n' "$CHERRY" | awk '$1=="+"{print $2}') || skip "cannot read git cherry's output"
[ -n "$CANDIDATES" ] || exit 0
CHERRY_DASH=$(printf '%s\n' "$CHERRY" | awk '$1=="-"{print $2; exit}')

SCRATCH="$(mktemp -d)" || skip "cannot create a temp dir"
trap 'rm -rf "$SCRATCH"' EXIT
short() { GIT rev-parse --short "$1" 2>/dev/null; }
# Subjects are author-controlled (a squash's subject is the PR title): no signature
# check (log.showSignature would run the user's gpg program), cleaned, and printed
# in quotes so they read as quoted repository text, not as the helper's own words.
subject() { GIT log -1 --no-show-signature --format=%s "$1" 2>/dev/null | clean; }
# Paths go to awk one per line, so a path containing LF cannot be checked (a CR
# stays inside the line and matches exactly). rev-list --stdin also drops a
# trailing CR, so the landing walk does not path-limit when a path has either.
has_lf() { [ "$(tr -cd '\n' < "$1" | wc -c | tr -d ' ')" != 0 ]; }
has_crlf() { [ "$(tr -cd '\r\n' < "$1" | wc -c | tr -d ' ')" != 0 ]; }

# ── Landing commit (#399) ──
# merge-tree runs in a throwaway bare repository that borrows the repo's objects
# (and its shallow file, or a shallow clone's missing parents make it fail). No
# config reaches it — not the repo's, the user's, the system's, nor any passed
# down through the environment — so no merge driver is defined and none runs; no
# attributes reach it either, so nothing selects even a built-in `union` merge,
# which can turn a conflict into C's own tree. No objects are added to the
# repository (git may refresh the mtime of objects it would have written).
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

# Where <rev>'s net change since its merge-base with the baseline landed: the
# EARLIEST commit, walking the baseline's first-parent history forward from the
# merge-base, that holds that whole net change (merging <rev> into C is clean and
# leaves C's tree unchanged). The merge-base is tried first: with no net change,
# <rev> landed there. Only descendants of the merge-base count: a first-parent
# commit on main's side of a later merge is measured against an older base, where
# a branch that undoes its own starting point looks contained. The first
# first-parent descendant is always tried (merge-tree's own merge-base changes
# there, e.g. the merge that brings a stacked branch's base in); after it, only
# descendants that touch the paths <rev> changed — one that does not touch them
# merges exactly like its parent. Every merge-tree call spends one unit of
# MT_BUDGET, shared by all calls, so the prefix search below is bounded too (each
# attempt tries at least the merge-base).
MT_BUDGET=200
LAND="" ; LAND_NOTE="" ; LAND_NONE="" ; LAND_AT_MB="" ; WALK_MB=""
holds() { # <commit> <rev> -> 0 holds, 1 does not, 2 error (LAND_NOTE set)
  local t rc
  if [ "$MT_BUDGET" -le 0 ]; then
    LAND_NOTE="the merge-tree budget (200) ran out before a landing commit was found"; return 2
  fi
  MT_BUDGET=$((MT_BUDGET - 1))
  t="$(ISOGIT merge-tree --write-tree "$1" "$2" 2>/dev/null)"; rc=$?
  # A conflict (exit 1) is never landing, even when the written tree equals C's
  # (modify/delete keeps C's side) — hence the exit status, not just the tree.
  # Anything else is an error, not a conflict.
  [ "$rc" -le 1 ] || { LAND_NOTE="merge-tree failed on $(short "$1") (exit $rc)"; return 2; }
  [ "$rc" -eq 0 ] && [ "${t%%$'\n'*}" = "$(GIT rev-parse "${1}^{tree}" 2>/dev/null)" ]
}
find_landing() { # <rev>
  local rev="$1" mb c n=0 rc fail="cannot list the baseline's commits"
  LAND="" ; LAND_NOTE="" ; LAND_NONE="" ; LAND_AT_MB=""
  mb="$(GIT merge-base "$BASELINE_SHA" "$rev" 2>/dev/null)" \
    || { LAND_NOTE="no merge-base between branch and baseline"; return 1; }
  n=1; holds "$mb" "$rev"; rc=$?
  case "$rc" in 0) LAND="$mb"; LAND_AT_MB=1; return 0 ;; 2) return 1 ;; esac
  GIT diff-tree -r --no-renames --ignore-submodules=none --name-only -z "$mb" "$rev" \
    > "$SCRATCH/netnames" 2>/dev/null || { LAND_NOTE="cannot list the paths the branch changed"; return 1; }
  if [ "$mb" != "$WALK_MB" ]; then   # the prefix search mostly shares one merge-base
    GIT rev-list --first-parent --reverse "${mb}..${BASELINE_SHA}" > "$SCRATCH/fp" 2>/dev/null \
      || { LAND_NOTE="$fail"; return 1; }
    GIT rev-list --ancestry-path "${mb}..${BASELINE_SHA}" > "$SCRATCH/desc" 2>/dev/null \
      || { LAND_NOTE="$fail"; return 1; }
    WALK_MB="$mb"
  fi
  if has_crlf "$SCRATCH/netnames"; then
    cp "$SCRATCH/fp" "$SCRATCH/pl"
  else
    { printf '%s\n^%s\n--\n' "$BASELINE_SHA" "$mb"; tr '\000' '\n' < "$SCRATCH/netnames"; } \
      | GIT --literal-pathspecs rev-list --first-parent --reverse --stdin > "$SCRATCH/pl" 2>/dev/null \
      || { LAND_NOTE="$fail"; return 1; }
  fi
  # The first first-parent descendant, then the path-touching descendants after it.
  awk 'FILENAME == ARGV[1] { d[$0] = 1; next }
       FILENAME == ARGV[2] { if (first == "" && ($0 in d)) { first = $0; print } next }
       ($0 in d) && $0 != first { print }' "$SCRATCH/desc" "$SCRATCH/fp" "$SCRATCH/pl" \
    > "$SCRATCH/walk" || { LAND_NOTE="$fail"; return 1; }
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    n=$((n + 1)); holds "$c" "$rev"; rc=$?
    case "$rc" in 0) LAND="$c"; return 0 ;; 2) return 1 ;; esac
  done < "$SCRATCH/walk"
  LAND_NONE=1
  LAND_NOTE="neither the merge-base nor any baseline commit after it holds the branch's net change ($n tried)"
  return 1
}

# The whole branch landed (LANDING), or only up to PREFIX_TIP: a partial merge drops
# the last commits, so the branch's earlier first-parent commits are tried newest
# first — at most PREFIX_TRIES of them, since a branch that never landed would
# otherwise try every one (landed prefixes are not ordered: a short prefix whose
# line a later branch commit rewrote never reached main even when a longer one did).
# Commits up to PREFIX_TIP are then checked where they landed and only the later
# ones against the tip, so a genuine orphan does not drag main's later edits of
# landed lines into the list.
PREFIX_TRIES=20
LANDING="" ; PREFIX_TIP="" ; LANDING_NOTE=""
if iso_init; then
  if find_landing "$BRANCH_SHA"; then
    LANDING="$LAND"
  else
    LANDING_NOTE="$LAND_NOTE"
    if [ -n "$LAND_NONE" ] && MB="$(GIT merge-base "$BASELINE_SHA" "$BRANCH_SHA" 2>/dev/null)"; then
      for b in $(GIT rev-list --first-parent "$MB..$BRANCH_SHA" 2>/dev/null | sed 1d | head -n "$PREFIX_TRIES"); do
        if find_landing "$b"; then
          # A prefix that undid itself holds its (empty) net change at the merge-base;
          # nothing of the branch landed there, so keep looking.
          [ -z "$LAND_AT_MB" ] || continue
          LANDING="$LAND"; PREFIX_TIP="$b"; LANDING_NOTE=""; break
        fi
        [ -n "$LAND_NONE" ] || { LANDING_NOTE="$LAND_NOTE"; break; }
      done
    fi
  fi
else
  LANDING_NOTE="skipped: $ISO_STATE"
fi

# Some branch commits are in the baseline as separate patches ('-' from git cherry).
# Where those copies sit decides whether the landing commit means anything: a copy
# that is not in the landing commit's history arrived later, so the branch reached
# the baseline piece by piece (cherry-picks, a partial rebase), and the earliest
# commit holding the net change can predate it — a commit that set a line back to
# its merge-base value would then pass although its counterpart was picked and it
# was not. Then the tip is used, as before #399. A copy at or before the landing
# commit (the squash itself, when the branch's net diff equals one commit's patch)
# changes nothing.
if [ -n "$LANDING" ] && [ -n "$CHERRY_DASH" ]; then
  MB="$(GIT merge-base "$BASELINE_SHA" "$BRANCH_SHA" 2>/dev/null)" || skip "no merge-base between branch and baseline"
  COPIES="$(GIT cherry "$BRANCH_SHA" "$BASELINE_SHA" "$MB" 2>/dev/null | awk '$1=="-"{print $2}')" \
    || skip "git cherry failed on the baseline side"
  for c in $COPIES; do
    GIT merge-base --is-ancestor "$c" "$LANDING" 2>/dev/null; rc=$?
    case "$rc" in
      0) ;;
      1) LANDING_NOTE="$(short "$c") brought a branch commit's patch into '$BASELINE' after $(short "$LANDING"), so the branch arrived piece by piece and has no single landing commit"
         LANDING=""; PREFIX_TIP=""; break ;;
      *) skip "cannot place $(short "$c") relative to $(short "$LANDING")" ;;
    esac
  done
fi

# ── Content-verify each candidate by line presence ──
# Against LANDING (for a candidate up to PREFIX_TIP when only a prefix landed), else
# against the tip. Plumbing only (diff-tree, ls-tree, cat-file): porcelain `git
# show` applies diff.external, textconv and color, and any of them can leave a
# patch with no `+` lines; --text keeps a file git treats as binary (a NUL byte, a
# `binary` or `-diff` attribute) from collapsing into "Binary files differ", and
# --ignore-submodules=none keeps submodule.<name>.ignore from hiding a gitlink.
use_landing() { # <candidate> -> 0: against LANDING, 1: against the tip, other: error
  [ -n "$LANDING" ] || return 1
  [ -z "$PREFIX_TIP" ] || GIT merge-base --is-ancestor "$1" "$PREFIX_TIP" 2>/dev/null
}

# Every path a candidate touched is numbered once by one awk pass (bash 3.2 has no
# associative arrays, and a linear search is quadratic on a wide commit); each
# candidate's numbers go to its own file, which awk reads later, never argv.
# -z so a space or a non-ASCII name (quoted by core.quotePath) stays the real path.
: > "$SCRATCH/pairs"; k=0; NEED_TIP=""; NPATHS=""; SIDE_OF=""
for sha in $CANDIDATES; do
  GIT diff-tree --root --no-commit-id --ignore-submodules=none --name-only -r -z "$sha" \
    > "$SCRATCH/names" 2>/dev/null || skip "cannot list the paths $(short "$sha") touched"
  has_lf "$SCRATCH/names" && skip "$(short "$sha") touches a path with a newline in its name"
  tr '\000' '\n' < "$SCRATCH/names" | awk -v k="$k" '{ print k "\t" $0 }' >> "$SCRATCH/pairs" \
    || skip "cannot index the paths $(short "$sha") touched"
  [ -s "$SCRATCH/names" ] && NPATHS="$NPATHS $k"
  use_landing "$sha"; rc=$?
  case "$rc" in
    0) SIDE_OF="$SIDE_OF land" ;;
    1) SIDE_OF="$SIDE_OF tip"; NEED_TIP=1 ;;
    *) skip "cannot tell whether $(short "$sha") is in the landed part of the branch" ;;
  esac
  k=$((k + 1))
done
LC_ALL=C awk -v d="$SCRATCH" '
  { i = index($0, "\t"); k = substr($0, 1, i - 1); p = substr($0, i + 1)
    if (!(p in idx)) { idx[p] = n++; print p > (d "/paths") }
    f = d "/c." k; print idx[p] >> f; close(f) }' "$SCRATCH/pairs" || skip "cannot index the touched paths"
for k in $NPATHS; do [ -s "$SCRATCH/c.$k" ] || skip "lost the path list of candidate $k"; done

# What each side has at every touched path: one `ls-tree -r -z` of the whole tree
# per side, matched by exact path (no line-based object lookup, which drops a
# trailing CR and, before git 2.51, reports a gitlink as missing). Each path maps
# to "blob <oid>", "link <oid>" (a gitlink, which diff prints as "Subproject commit
# <oid>") or "none". Each distinct blob is then read once; a listed blob that cannot
# be read is an error, never an empty file.
classify() { # <rev> <side> -> $SCRATCH/<side>.map, one line per path in $SCRATCH/paths
  GIT ls-tree -r -z --full-tree "$1" > "$SCRATCH/$2.tree" 2>/dev/null || return 1
  has_lf "$SCRATCH/$2.tree" && return 2   # a path with a newline would split records
  tr '\000' '\n' < "$SCRATCH/$2.tree" | LC_ALL=C awk -v paths="$SCRATCH/paths" -v out="$SCRATCH/$2.map" '
    BEGIN { while ((r = getline p < paths) > 0) need[p] = n++; if (r < 0) bad = 1; close(paths) }
    { i = index($0, "\t"); p = substr($0, i + 1)
      if (!(p in need)) next
      split(substr($0, 1, i - 1), m, " ")
      e[need[p]] = (m[2] == "commit" ? "link " : "blob ") m[3] }
    END { if (bad) exit 2
          for (j = 0; j < n; j++) print ((j in e) ? e[j] : "none") > out }'
}
SIDES="head"
[ -z "$LANDING" ] || SIDES="$SIDES land"
[ -z "$NEED_TIP" ] || SIDES="$SIDES tip"
if [ -f "$SCRATCH/paths" ]; then
  for side in $SIDES; do
    case "$side" in head) rev="$BRANCH_SHA" ;; land) rev="$LANDING" ;; tip) rev="$BASELINE_SHA" ;; esac
    classify "$rev" "$side"; rc=$?
    case "$rc" in
      0) ;;
      2) skip "the tree of $(short "$rev") has a path with a newline in its name" ;;
      *) skip "cannot list the tree of $(short "$rev")" ;;
    esac
  done
  for side in $SIDES; do cat "$SCRATCH/$side.map"; done | awk '$1 == "blob" { print $2 }' | sort -u \
    > "$SCRATCH/blobs" || skip "cannot list the blobs to read"
  # One file per blob, read by awk one at a time, so a file without a final newline
  # cannot run into the next one.
  while IFS= read -r oid; do
    GIT cat-file blob "$oid" > "$SCRATCH/blob.$oid" 2>/dev/null || skip "cannot read blob $oid"
  done < "$SCRATCH/blobs"
fi

orphan_p() { # <commit-sha> <candidate number> <land|tip> -> 0 orphan, 1 landed, other: error
  [ -s "$SCRATCH/c.$2" ] || return 1
  GIT diff-tree --root --no-commit-id -r -p --text --no-ext-diff --no-textconv --no-color \
    --ignore-submodules=none --submodule=short "$1" > "$SCRATCH/patch" 2>/dev/null || return 2
  # Orphan when some added line, not blank, is in the branch head's version of the
  # files and not in the target's. A line the head no longer has was superseded
  # within the branch itself (#399), so its absence says nothing. Added lines are
  # taken inside hunks only, so a line that starts with "++" is not mistaken for the
  # "+++ b/path" header. One awk pass with exact whole-line matching; a file it
  # cannot read is an error (exit 2), not an empty set. No added content (e.g. a
  # pure deletion) -> not detectable here.
  LC_ALL=C awk -v d="$SCRATCH" -v side="$3" -v list="$SCRATCH/c.$2" '
    function slurp(f, arr,    l, r, i) {
      i = 0; while ((r = getline l < f) > 0) arr[i++] = l
      if (r < 0) bad = 1; close(f)
    }
    function load(entry, set,    f, l, r, a) {
      split(entry, a, " ")
      if (a[1] == "link") { set["Subproject commit " a[2]] = 1; return }
      if (a[1] != "blob") return
      f = d "/blob." a[2]
      while ((r = getline l < f) > 0) set[l] = 1
      if (r < 0) bad = 1; close(f)
    }
    BEGIN {
      slurp(d "/head.map", hm); slurp(d "/" side ".map", tm)
      while ((r = getline j < list) > 0) { load(hm[j], head); load(tm[j], target) }
      if (r < 0) bad = 1; close(list)
      if (bad) exit
    }
    /^diff --git / { hunk = 0; next }
    /^@@/          { hunk = 1; next }
    !hunk          { next }
    /^\+/ {
      line = substr($0, 2)
      if (line ~ /^[ \t\r\f\v]*$/) next
      if ((line in head) && !(line in target)) { found = 1; exit }
    }
    END { if (bad) exit 2; exit !found }' "$SCRATCH/patch"
}

ORPHANS="" ; k=0
set -- $SIDE_OF
for sha in $CANDIDATES; do
  side="$1"; shift
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

B="$(printf '%s' "$BRANCH" | clean)"; S="$(printf '%s' "$BASELINE" | clean)"
echo "Orphan commits on '$B' whose content did NOT land in '$S' (quoted subjects are repository text):"
while IFS= read -r sha; do
  [ -n "$sha" ] || continue
  printf '  %s  "%s"\n' "$(short "$sha")" "$(subject "$sha")"
done <<< "$ORPHANS"
if [ -n "$LANDING" ] && [ -z "$PREFIX_TIP" ]; then
  printf "Landing check (#399): the branch's net change landed in %s \"%s\"; the lines above are not in it.\n" \
    "$(short "$LANDING")" "$(subject "$LANDING")"
elif [ -n "$LANDING" ]; then
  printf "Landing check (#399): the branch up to %s landed in %s \"%s\"; later commits were checked against '%s'.\n" \
    "$(short "$PREFIX_TIP")" "$(short "$LANDING")" "$(subject "$LANDING")" "$S"
else
  printf "Landing check (#399): %s; lines were checked against '%s'.\n" "$(printf '%s' "$LANDING_NOTE" | clean)" "$S"
fi
exit 3
