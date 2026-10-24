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
#       or awk failure outside the landing step, an unreadable object, a checked
#       commit touching a path with a newline in its name); one
#       "check-merge-completeness: <reason>" line goes to stderr.
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
#      one that landed are checked at its landing commit, the rest at the tip. A
#      branch with no net change "lands" at the merge-base; if git cherry shows some
#      of its commits in the baseline as separate patches, it came in piece by
#      piece and the tip is used. At most 200 merge-tree calls in all; git < 2.38
#      (no `merge-tree --write-tree`) skips this step.
#   3. CONTENT-VERIFY each candidate by *line presence*, NOT cherry-pick. A
#      cherry-pick is a 3-way merge and conflicts when the same file was touched
#      by >1 commit and then squash-merged — the common TDD branch shape — which
#      flagged fully-landed branches as false orphans (#184 DA-2). Instead we ask:
#      do the effects of the commit that the branch head still shows appear in L's
#      version of the files it touched (the tip's when there is no L)? An effect is
#      an added line or path the head still has, or a deleted one the head still
#      lacks (tests/merge-completeness/SPEC.md defines it). At L, copies are counted
#      against the clean merge of the landed part onto main just before L (what L
#      would hold had all of it landed), so a line main added or removed on its own
#      does not count against the branch. At the tip, where main's own edits are
#      unknown, only presence is compared. Squash → the
#      effects are there → not an orphan. Partial merge → a dropped commit's effect
#      is missing → orphan.
#
# Warn-only contract: exit 3 is surfaced via AskUserQuestion by idd-close; it is
# NOT a hard block, because the check is best-effort. Known blind spots (only these):
#   - an added line already elsewhere in the files the same commit touched, or a
#     deleted line the branch head still has there (a moved or duplicated line);
#   - a commit that only changes a file mode, only adds or deletes blank lines in a
#     file that exists before and after it, or only adds or drops the final newline;
#   - a deletion from a file that main renamed or moved away (the old path is gone
#     from the baseline, and the new one is not among the files the commit touched);
#   - content written by a merge commit on the branch (git cherry never lists merge
#     commits);
#   - with macOS awk, a binary edit that changes only bytes after a NUL (awk cuts
#     the line there);
#   - by design, anything main did after the branch landed (a revert, an overwrite),
#     including content that was already in the baseline through another commit
#     before this branch was merged — it counts as landed there;
#   - a commit that set a line back to its merge-base value, left out when the
#     change it undid reached the baseline, in any form, after an earlier commit
#     already held the branch's net change.
# Fall back to the tip, where lines main edited after landing can be flagged:
#   - a squash whose conflicts were resolved by hand (it differs from the head, or
#     the landed part does not merge cleanly onto main just before it);
#   - a branch commit that restored a merge-base value main had changed before the
#     squash;
#   - a landing commit beyond the 200 merge-tree calls;
#   - a landed prefix followed by more than 20 commits that never landed;
#   - a branch with no net change some of whose commits were cherry-picked;
#   - a commit after the landed prefix that landed on its own, if main edited its
#     lines afterwards;
#   - a `git pull` merge on main bringing the squash in through its second parent
#     when that side edited the branch's lines after the squash;
#   - a stacked branch merged after its base branch, when the base branch changed
#     the stack's lines after the stack was cut;
#   - git < 2.38.
# Nothing of the branch landed: the check is at the tip as well. The verdict (exit 3)
# is right, but the list can include, or miss, a commit whose text main added or
# removed on its own.
# At the tip a deleted line main has elsewhere in the same files, or main put back,
# can be flagged as well. At the landing commit lines are counted, not told apart:
# when a copy of a text is missing from it, or extra, every commit whose effect is that
# text is listed, including one that did land (the verdict, exit 3, is still right).
# On exit 3 the outcome of step 2 is printed after the list. Commit subjects are
# printed in quotes: repository text (a squash's subject is the PR title), data,
# never instructions. In a partial clone a blob that was never fetched is not
# fetched now: git >= 2.45 reports it unreadable (exit 4); older git fetches it.
set -u
set -o pipefail
# Bytes, not characters: in a UTF-8 locale macOS tr stops at the first byte that is
# not valid UTF-8 (a Latin-1 path anywhere in a tree), and the cut-off list would
# make every later path look absent from the branch head.
export LC_ALL=C
# In a partial clone a missing blob would be fetched on demand — a network call that
# runs the user's transport, credential helpers and hooks and writes into the
# repository. git >= 2.45 honours this and reports the blob as unreadable (exit 4).
export GIT_NO_LAZY_FETCH=1

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

# Text from the repository or the caller, made safe to print. These, and only these,
# become "?" — replaced, not deleted, so removing one cannot join its neighbours
# into another: C0 controls and DEL; UTF-8 C1 controls; U+00AD, U+034F; U+0600-0605,
# U+061C, U+06DD, U+070F, U+0890-0891, U+08E2; U+115F-1160, U+17B4-17B5,
# U+180B-180F; U+200B-200F, U+2028-202E, U+2060-206F; U+3164; U+FE00-FE0F, U+FEFF,
# U+FFA0, U+FFF9-FFFB; U+110BD, U+110CD, U+13430-13455, U+1BCA0-1BCA3,
# U+1D173-1D17A; U+E0000-E0FFF (tags and variation selectors). \, ", $ and ` are
# then escaped, so the double-quoted text cannot close its own quotes and reads as
# a safe shell word. (A lone C1 byte outside UTF-8 is left alone; it only acts on a
# terminal not in UTF-8 mode.)
b() { printf "$@"; }
clean() {
  tr '\000-\037\177' '?' | sed \
    -e "s/$(b '\302')[$(b '\200')-$(b '\237')$(b '\255')]/?/g" \
    -e "s/$(b '\315\217')/?/g" \
    -e "s/$(b '\330')[$(b '\200')-$(b '\205\234')]/?/g" \
    -e "s/$(b '\333\235')/?/g" -e "s/$(b '\334\217')/?/g" \
    -e "s/$(b '\340\242')[$(b '\220\221')]/?/g" -e "s/$(b '\340\243\242')/?/g" \
    -e "s/$(b '\341\205')[$(b '\237\240')]/?/g" \
    -e "s/$(b '\341\236')[$(b '\264\265')]/?/g" \
    -e "s/$(b '\341\240')[$(b '\213')-$(b '\217')]/?/g" \
    -e "s/$(b '\342\200')[$(b '\213')-$(b '\217')$(b '\250')-$(b '\256')]/?/g" \
    -e "s/$(b '\342\201')[$(b '\240')-$(b '\257')]/?/g" \
    -e "s/$(b '\343\205\244')/?/g" \
    -e "s/$(b '\357\270')[$(b '\200')-$(b '\217')]/?/g" \
    -e "s/$(b '\357\273\277')/?/g" \
    -e "s/$(b '\357\276\240')/?/g" \
    -e "s/$(b '\357\277')[$(b '\271')-$(b '\273')]/?/g" \
    -e "s/$(b '\360\221\202\275')/?/g" -e "s/$(b '\360\221\203\215')/?/g" \
    -e "s/$(b '\360\223\220')[$(b '\260')-$(b '\277')]/?/g" \
    -e "s/$(b '\360\223\221')[$(b '\200')-$(b '\225')]/?/g" \
    -e "s/$(b '\360\233\262')[$(b '\240')-$(b '\243')]/?/g" \
    -e "s/$(b '\360\235\205')[$(b '\263')-$(b '\272')]/?/g" \
    -e "s/$(b '\363\240')[$(b '\200')-$(b '\277')][$(b '\200')-$(b '\277')]/?/g" \
    -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\$/\\$/g' -e 's/`/\\`/g'
}
# Could not verify: say why on stderr and exit 4, which the caller reports and
# never treats as clean or as a block.
skip() { printf 'check-merge-completeness: %s\n' "$*" >&2; exit 4; }
# The caller's refs, cleaned once, always printed in double quotes.
B="\"$(printf '%s' "$BRANCH" | clean)\""; S="\"$(printf '%s' "$BASELINE" | clean)\""
RP="\"$(printf '%s' "$REPO" | clean)\""

# Resolve both inputs to commit SHAs up front. `--end-of-options` prevents an
# option-shaped ref (attacker-controllable PR branch name like `--upload-pack=x`)
# from being parsed as a git option (#184 S1). A SHA can never be option-shaped,
# so every downstream git call is injection-safe. Unresolvable → skip (exit 4).
BRANCH_SHA="$(GIT rev-parse --verify --quiet --end-of-options "${BRANCH}^{commit}" 2>/dev/null)" \
  || skip "cannot resolve branch $B in $RP"
BASELINE_SHA="$(GIT rev-parse --verify --quiet --end-of-options "${BASELINE}^{commit}" 2>/dev/null)" \
  || skip "cannot resolve baseline $S in $RP"

# Candidate orphans = '+'-marked commits (patch-id absent from baseline).
CHERRY="$(GIT cherry "$BASELINE_SHA" "$BRANCH_SHA" 2>/dev/null)" || skip "git cherry failed"
CANDIDATES=$(printf '%s\n' "$CHERRY" | awk '$1=="+"{print $2}') || skip "cannot read git cherry's output"
[ -n "$CANDIDATES" ] || exit 0
CHERRY_DASH=$(printf '%s\n' "$CHERRY" | awk '$1=="-" && !f { print $2; f = 1 }') || skip "cannot read git cherry's output"

SCRATCH="$(mktemp -d)" || skip "cannot create a temp dir"
trap 'rm -rf "$SCRATCH"' EXIT
short() { GIT rev-parse --short "$1" 2>/dev/null; }
# Subjects are author-controlled (a squash's subject is the PR title): no signature
# check (log.showSignature would run the user's gpg program), cleaned, and printed
# in quotes so they read as quoted repository text, not as the helper's own words.
subject() { printf '%s' "$(GIT log -1 --no-show-signature --format=%s "$1" 2>/dev/null)" | clean; }
# Paths go to awk one per line, so a candidate path containing LF cannot be checked
# (a CR stays inside the line and matches exactly). In tree listings an LF inside a
# path is swapped for \001, so such a path elsewhere in the tree changes nothing;
# \001 is therefore refused in candidate paths too. rev-list --stdin also drops a
# trailing CR, so the landing walk does not path-limit when a path has CR or LF.
count_of() { # <bytes> <file> -> prints how many of those bytes the file has; fails on error
  tr -cd "$1" < "$2" | wc -c | tr -d ' '
}
has_lf() { local n; n="$(count_of '\n\001' "$1")" || return 2; [ "$n" != 0 ]; }    # 0 yes, 1 no, 2 error
has_crlf() { local n; n="$(count_of '\r\n' "$1")" || return 2; [ "$n" != 0 ]; }

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
  has_crlf "$SCRATCH/netnames"; rc=$?
  if [ "$rc" -eq 0 ]; then
    cp "$SCRATCH/fp" "$SCRATCH/pl" || { LAND_NOTE="$fail"; return 1; }
  elif [ "$rc" -ne 1 ]; then
    LAND_NOTE="cannot read the paths the branch changed"; return 1
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
LANDING="" ; PREFIX_TIP="" ; LANDING_NOTE="" ; LANDING_AT_MB=""
if iso_init; then
  if find_landing "$BRANCH_SHA"; then
    LANDING="$LAND"; LANDING_AT_MB="$LAND_AT_MB"
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

# A branch with no net change "lands" at the merge-base. If some of its commits are
# also in the baseline as separate patches ('-' from git cherry), the branch did
# reach the baseline, commit by commit, after that point — e.g. a change that was
# cherry-picked while the commit that set the line back was left behind. The
# merge-base says nothing about that, so the tip is used, as before #399.
if [ -n "$LANDING_AT_MB" ] && [ -n "$CHERRY_DASH" ]; then
  LANDING_NOTE="the branch has no net change, and $(short "$CHERRY_DASH") reached $S as a separate patch"
  LANDING=""; PREFIX_TIP=""
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
  has_lf "$SCRATCH/names"; case "$?" in
    0) skip "$(short "$sha") touches a path with a newline (or \\001) in its name" ;;
    1) ;;
    *) skip "cannot read the paths $(short "$sha") touched" ;;
  esac
  tr '\000' '\n' < "$SCRATCH/names" | awk -v k="$k" '{ print k "\t" $0 }' >> "$SCRATCH/pairs" \
    || skip "cannot index the paths $(short "$sha") touched"
  # The paths it deletes and adds as a whole (subsets of the names above, so no LF).
  for f in D A; do
    GIT diff-tree --root --no-commit-id --ignore-submodules=none --name-only --diff-filter=$f -r -z "$sha" \
      > "$SCRATCH/dz" 2>/dev/null && tr '\000' '\n' < "$SCRATCH/dz" > "$SCRATCH/$f.$k" \
      || skip "cannot list the paths $(short "$sha") deleted or added"
  done
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
  if [ "$2" = expect ]; then
    ISOGIT ls-tree -r -z --full-tree "$1" > "$SCRATCH/$2.tree" 2>/dev/null || return 1
  else
    GIT ls-tree -r -z --full-tree "$1" > "$SCRATCH/$2.tree" 2>/dev/null || return 1
  fi
  tr '\n\000' '\001\n' < "$SCRATCH/$2.tree" | LC_ALL=C awk -v paths="$SCRATCH/paths" -v out="$SCRATCH/$2.map" '
    BEGIN { while ((r = getline p < paths) > 0) need[p] = n++; if (r < 0) bad = 1; close(paths) }
    { i = index($0, "\t"); p = substr($0, i + 1)
      if (!(p in need)) next
      split(substr($0, 1, i - 1), m, " ")
      e[need[p]] = (m[2] == "commit" ? "link " : "blob ") m[3] }
    END { if (bad) exit 2
          for (j = 0; j < n; j++) print ((j in e) ? e[j] : "none") > out }'
}
# At a landing commit L a line can also be main's own: main may have added or removed
# the same text before the branch landed (a version string another PR bumped to, a
# closing brace). So L is compared with EXPECT, the clean merge of the landed part of
# the branch onto L's first parent (main just before L): what L would hold had every
# commit of that part landed. When L is the merge-base this is the branch itself; when
# L's first parent already holds the branch (a stacked branch squashed before its base
# was merged) it is that parent. The merge runs in the scratch repository, so the
# expect side is read from there. A conflict means L was resolved by hand: the tip is
# used instead.
EXPECT_TREE=""
if [ -n "$LANDING" ] && [ -n "$CANDIDATES" ]; then
  PREV_REV="$(GIT rev-parse -q --verify "$LANDING^1^{commit}" 2>/dev/null)" || PREV_REV=""
  REF="${PREFIX_TIP:-$BRANCH_SHA}"
  if [ -z "$PREV_REV" ]; then
    EXPECT_TREE="$(GIT rev-parse "$REF^{tree}" 2>/dev/null)" || skip "cannot read the tree of $(short "$REF")"
  else
    t="$(ISOGIT merge-tree --write-tree "$PREV_REV" "$REF" 2>/dev/null)"; rc=$?
    if [ "$rc" -eq 0 ]; then
      EXPECT_TREE="${t%%$'\n'*}"
    else
      [ "$rc" -eq 1 ] && why="does not merge cleanly onto main just before it (resolved by hand)" \
        || why="could not be merged onto main just before it (merge-tree exit $rc)"
      LANDING_NOTE="the branch landed in $(short "$LANDING"), but its landed part $why"
      LANDING=""; PREFIX_TIP=""; NEED_TIP=1; SIDE_OF="$(printf '%s' "$SIDE_OF" | sed 's/land/tip/g')"
    fi
  fi
fi
SIDES="head"
[ -z "$LANDING" ] || SIDES="$SIDES land expect"
[ -z "$NEED_TIP" ] || SIDES="$SIDES tip"
if [ -f "$SCRATCH/paths" ]; then
  for side in $SIDES; do
    case "$side" in
      head) rev="$BRANCH_SHA" ;; land) rev="$LANDING" ;; tip) rev="$BASELINE_SHA" ;;
      expect) rev="$EXPECT_TREE" ;;
    esac
    classify "$rev" "$side" || skip "cannot list the tree of $(short "$rev")"
  done
  for side in $SIDES; do cat "$SCRATCH/$side.map"; done | awk '$1 == "blob" { print $2 }' | sort -u \
    > "$SCRATCH/blobs" || skip "cannot list the blobs to read"
  # One file per blob, read by awk one at a time, so a file without a final newline
  # cannot run into the next one.
  while IFS= read -r oid; do
    GIT cat-file blob "$oid" > "$SCRATCH/blob.$oid" 2>/dev/null \
      || { [ -n "$EXPECT_TREE" ] && ISOGIT cat-file blob "$oid" > "$SCRATCH/blob.$oid" 2>/dev/null; } \
      || skip "cannot read blob $oid"
  done < "$SCRATCH/blobs"
fi

orphan_p() { # <commit-sha> <candidate number> <land|tip> -> 10 orphan, 11 landed, other: error
  [ -s "$SCRATCH/c.$2" ] || return 11
  GIT diff-tree --root --no-commit-id -r -p --text --no-ext-diff --no-textconv --no-color \
    --ignore-submodules=none --submodule=short "$1" > "$SCRATCH/patch" 2>/dev/null || return 2
  # Exit 10 = orphan, 11 = landed; anything else (a crash, a read error) is an error.
  # Orphan when an effect of the commit that the head still shows is missing from the
  # target: an added line (not blank) the head has, or a deleted one the head lacks
  # (SPEC.md). A line the head no longer has (added) or has again (deleted) was
  # superseded within the branch itself (#399), so it says nothing. Lines are taken
  # inside hunks only, so "++"/"--" lines are not mistaken for the "+++"/"---"
  # headers. One awk pass with
  # exact whole-line matching; a file it cannot read is an error (exit 2), not an
  # empty set. A path the commit deletes, which the head no longer has and the
  # target still has, is an orphan too (a dropped rename, an emptied file, a
  # submodule removal: deletions with no line to compare), and so is a path it adds
  # that the head has and the target does not (an empty file). At a landing commit
  # the counts are compared with EXPECT instead of with the head (see SIDES above).
  LC_ALL=C awk -v d="$SCRATCH" -v side="$3" -v list="$SCRATCH/c.$2" -v dels="$SCRATCH/D.$2" -v adds="$SCRATCH/A.$2" '
    function slurp(f, arr,    l, r, i) {
      i = 0; while ((r = getline l < f) > 0) arr[i++] = l
      if (r < 0) bad = 1; close(f)
    }
    function load(entry, set,    f, l, r, a) {   # counts each line
      split(entry, a, " ")
      if (a[1] == "link") { set["Subproject commit " a[2]]++; return }
      if (a[1] != "blob") return
      f = d "/blob." a[2]
      while ((r = getline l < f) > 0) set[l]++
      if (r < 0) bad = 1; close(f)
    }
    # h, t, e: how many times the head, the target and EXPECT have the line (or the
    # path, as 0 or 1). At a landing commit the target must hold what EXPECT holds; at
    # the tip, where the changes main made itself are unknown, only presence counts.
    function missing(h, t, e) { return side == "land" ? h > 0 && t < e : h > 0 && t == 0 }
    function kept(h, t, e) { return side == "land" ? t > 0 && t > e : h == 0 && t > 0 }
    function paths(f, del,    l, r, j, h, t, e) {
      while ((r = getline l < f) > 0) {
        if (!(l in pidx)) { bad = 1; break }
        j = pidx[l]; h = hm[j] != "none"; t = tm[j] != "none"; e = em[j] != "none"
        if (del ? kept(h, t, e) : missing(h, t, e)) found = 1
      }
      if (r < 0) bad = 1; close(f)
    }
    BEGIN {
      slurp(d "/head.map", hm); slurp(d "/" side ".map", tm)
      if (side == "land") slurp(d "/expect.map", em)
      while ((r = getline j < list) > 0) {
        load(hm[j], head); load(tm[j], target)
        if (side == "land") load(em[j], expect)
      }
      if (r < 0) bad = 1; close(list)
      while ((r = getline l < (d "/paths")) > 0) pidx[l] = np++
      if (r < 0) bad = 1; close(d "/paths")
      paths(dels, 1); paths(adds, 0)
      if (bad || found) exit
    }
    /^diff --git / { hunk = 0; next }
    /^@@/          { hunk = 1; next }
    !hunk          { next }
    /^\+/ {
      line = substr($0, 2)
      if (line ~ /^[ \t\r\f\v]*$/) next
      if (missing(head[line], target[line], expect[line])) { found = 1; exit }
    }
    /^-/ {
      line = substr($0, 2)
      if (line ~ /^[ \t\r\f\v]*$/) next
      if (kept(head[line], target[line], expect[line])) { found = 1; exit }
    }
    END { if (bad) exit 2; exit (found ? 10 : 11) }' "$SCRATCH/patch"
}

# For tests/merge-completeness/bounded.py only: where each candidate was checked.
if [ -n "${CHECK_MERGE_COMPLETENESS_TRACE:-}" ]; then
  { printf 'landing %s prefix %s\n' "${LANDING:--}" "${PREFIX_TIP:--}"
    set -- $SIDE_OF
    for sha in $CANDIDATES; do printf 'side %s %s\n' "$sha" "$1"; shift; done
  } > "$CHECK_MERGE_COMPLETENESS_TRACE" || skip "cannot write the trace file"
fi

ORPHANS="" ; k=0
set -- $SIDE_OF
for sha in $CANDIDATES; do
  side="$1"; shift
  orphan_p "$sha" "$k" "$side"; rc=$?
  case "$rc" in
    10) ORPHANS="$ORPHANS$sha"$'\n' ;;
    11) ;;
    *) skip "cannot verify $(short "$sha") (exit $rc)" ;;
  esac
  k=$((k + 1))
done

[ -n "$ORPHANS" ] || exit 0

echo "Orphan commits on $B whose content did NOT land in $S (quoted subjects are repository text):"
while IFS= read -r sha; do
  [ -n "$sha" ] || continue
  printf '  %s  "%s"\n' "$(short "$sha")" "$(subject "$sha")"
done <<< "$ORPHANS"
if [ -n "$LANDING" ] && [ -z "$PREFIX_TIP" ]; then
  printf "Landing check (#399): the branch's net change landed in %s \"%s\"; the commits above are not reflected in it.\n" \
    "$(short "$LANDING")" "$(subject "$LANDING")"
elif [ -n "$LANDING" ]; then
  printf "Landing check (#399): the branch up to %s landed in %s \"%s\"; later commits were checked against %s.\n" \
    "$(short "$PREFIX_TIP")" "$(short "$LANDING")" "$(subject "$LANDING")" "$S"
else
  printf "Landing check (#399): %s; lines were checked against %s.\n" "$LANDING_NOTE" "$S"
fi
exit 3
