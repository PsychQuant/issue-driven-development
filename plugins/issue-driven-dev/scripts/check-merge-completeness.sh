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
#      commit L that holds the branch's whole net change is where the branch landed:
#      every line the net change adds is in place in L and every line it deletes is
#      no longer in place there, compared by two-way diffs (no merge, so main's own
#      edits elsewhere, even on the next line, do not matter). When the whole branch
#      never landed, the newest 20 of the branch's earlier commits are tried, newest
#      first: commits up to the newest one that landed are checked at its landing
#      commit, the rest at the tip. A branch with no net change "lands" at the
#      merge-base; the same search finds a prefix of it that landed later, and if
#      none did but git cherry shows some of its commits in the baseline as separate
#      patches, it came in piece by piece and the tip is used. At most 200 checks.
#   3. CONTENT-VERIFY each candidate, NOT by cherry-picking it. A cherry-pick is a
#      3-way merge and conflicts when the same file was touched by >1 commit and
#      then squash-merged — the common TDD branch shape — which flagged fully-landed
#      branches as false orphans (#184 DA-2). Instead we ask: do the effects of the
#      commit that the branch head still shows appear where it landed (the tip when
#      there is no L)? An effect is an added line or path the head still has, or a
#      deleted one the head still lacks (tests/merge-completeness/SPEC.md defines it).
#      At L each effect is checked in its own place, by two-way diffs: a line the
#      commit added is missing when the head still has it there and L does not; a
#      line it deleted is missing when the head no longer has it there and L still
#      does. At the tip, where main's own edits are unknown, only line presence is
#      compared. Squash → the effects are there → not an orphan. Partial merge → a
#      dropped commit's effect is missing → orphan.
#   Every comparison reads trees with `git diff`, `ls-tree` and `cat-file`: no merge,
#   so no merge driver or attribute can steer the answer, and no git-version floor.
#
# Warn-only contract: exit 3 is surfaced via AskUserQuestion by idd-close; it is
# NOT a hard block, because the check is best-effort. Not effects at all (SPEC.md's
# definition): a file mode, a blank line, a final newline. Known blind spots (only
# these):
#   - at the tip, an added line already elsewhere in the files the same commit
#     touched, or a deleted line the branch head still has there (a moved or
#     duplicated line);
#   - a deletion from a file that main renamed or moved away (the old path is gone
#     from the baseline, and the new one is not among the files the commit touched);
#   - content written by a merge commit on the branch (git cherry never lists merge
#     commits);
#   - with macOS awk, a binary edit that changes only bytes after a NUL (awk cuts
#     the line there);
#   - by design, anything main did after the branch landed (a revert, an overwrite),
#     including content that was already in the baseline through another commit
#     before this branch was merged — it counts as landed there — and a commit of
#     main's own that completes the branch's net change later (a line a dropped
#     commit deleted, which main then replaced): it counts as the landing commit;
#   - in a branch with no net change, a commit that set a line back to its merge-base
#     value, left out when the change it undid reached the baseline in a form no earlier
#     state of the branch matches (a squash of the earlier commits edited by hand) and
#     not as a separate patch; 3.5.0 caught some of these at the tip.
# Fall back to the tip, where lines main edited after landing can be flagged:
#   - a squash whose conflicts were resolved by hand, leaving one of the branch's own
#     lines out of place;
#   - a landing commit beyond the 200 checks;
#   - a landed prefix followed by more than 20 commits that never landed;
#   - a branch with no net change some of whose commits were cherry-picked;
#   - a commit after the landed prefix that landed on its own, if main edited its
#     lines afterwards;
#   - a `git pull` merge on main bringing the squash in through its second parent
#     when that side edited the branch's lines after the squash;
#   - a stacked branch merged after its base branch, when the base branch changed
#     the stack's lines after the stack was cut.
# Nothing of the branch landed: the check is at the tip as well. The verdict (exit 3)
# is right, but the list can include, or miss, a commit whose text main added or
# removed on its own.
# At the tip a deleted line main has elsewhere in the same files, or main put back,
# can be flagged as well. At the landing commit the check sees where a change is, not
# which commit made it: a commit that landed and was undone by a later commit that
# landed too, then changed again by one that did not land, is listed with that last
# one (the verdict, exit 3, is still right); and when main itself edited a line a
# commit edited, before landing or in the landing step, so that L holds the value from
# before that commit (or a third value), the commit is listed although it landed. The
# trees are the same as if it had been dropped, so no check that reads trees can tell.
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
# the quotation marks that look like the closing quote, U+201C, U+201D and U+FF02
# (a subject could otherwise appear to end and be followed by text of the helper's own);
# U+1D173-1D17A; U+E0000-E0FFF (tags and variation selectors). \, ", $ and ` are
# then escaped, so the double-quoted text cannot close its own quotes. It is meant to
# be read, not pasted into an interactive shell, where `!` still triggers history
# expansion inside double quotes. (A lone C1 byte outside UTF-8 is left alone; it
# only acts on a terminal not in UTF-8 mode.)
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
    -e "s/$(b '\342\200')[$(b '\213')-$(b '\217')$(b '\234\235')$(b '\250')-$(b '\256')]/?/g" \
    -e "s/$(b '\357\274\202')/?/g" \
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
CHERRY="$(GIT cherry "$BASELINE_SHA" "$BRANCH_SHA" 2>/dev/null)" || {
  # In a partial clone git cherry needs blobs that were never fetched, and this check
  # does not fetch them (GIT_NO_LAZY_FETCH above); say so, so the cause is visible.
  [ -n "$(GIT config --get extensions.partialClone 2>/dev/null)" ] \
    && skip "git cherry failed: this is a partial clone, and the check does not fetch missing blobs (fetch them, or check by hand)"
  skip "git cherry failed"
}
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

# ── Comparing two trees line by line, in place (#399) ──
# Everything at a landing commit is decided by two-way diffs read position by
# position: which old-side lines a diff changes, and which lines it adds or deletes.
# There is no three-way merge anywhere: a merge conflicts when two edits merely sit
# on adjacent lines, and round 11 read such a conflict as "landed" (#399 verify
# round 11). Every option that shapes the alignment is pinned, so no config,
# attribute or external program changes it: no external diff, no textconv, --text
# for files git calls binary, no rename pairing, myers with the indent heuristic
# (git's defaults, which diff.algorithm or diff.indentHeuristic could change), fixed
# a/ and b/ prefixes, no color, and submodules as "Subproject commit <oid>" lines.
EMPTY_TREE="$(GIT hash-object -t tree /dev/null 2>/dev/null)" || skip "cannot name the empty tree"
pdiff() { # <a> <b> <paths file, NUL-separated> -> unified diff with no context, limited to those paths
  local p
  local -a ps
  ps=()
  while IFS= read -r -d '' p; do ps+=("$p"); done < "$3"
  [ "${#ps[@]}" -gt 0 ] || return 0
  GIT -c core.quotePath=true --literal-pathspecs diff -U0 --no-color --no-ext-diff --no-textconv \
    --text --no-renames --diff-algorithm=myers --indent-heuristic --src-prefix=a/ --dst-prefix=b/ \
    --no-relative --ignore-submodules=none --submodule=short "$1" "$2" -- "${ps[@]}"
}
# One record per line, "<kind><TAB><line number><TAB><path>": C, an old-side line the
# diff changes; A, a new-side line it adds; D, an old-side line it deletes (A and D
# skip blank lines, which SPEC.md's definition ignores). Within a hunk an old and a
# new line at the same offset with the same text are unchanged (a dropped final
# newline, or two equal lines diff happened to pair). Paths come from the ---/+++
# lines, C-unquoted when git quoted them.
pparse() {
  LC_ALL=C awk '
    function unq(s,    out, i, c, d) {
      if (substr(s, 1, 1) != "\"") return s
      s = substr(s, 2, length(s) - 2); out = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if (c != "\\") { out = out c; continue }
        c = substr(s, ++i, 1)
        if (c ~ /[0-7]/) { d = (c * 64) + (substr(s, i + 1, 1) * 8) + substr(s, i + 2, 1); i += 2; out = out sprintf("%c", d) }
        else if (c == "n") out = out "\n"; else if (c == "t") out = out "\t"; else if (c == "a") out = out "\a"
        else if (c == "b") out = out "\b"; else if (c == "f") out = out "\f"; else if (c == "r") out = out "\r"
        else if (c == "v") out = out "\v"; else out = out c
      }
      return out
    }
    function blank(t) { return t ~ /^[ \t\r\f\v]*$/ }
    function flush(   i) {
      for (i = 0; i < no; i++) if (!(i < nn && O[i] == N[i])) {
        print "C\t" (os + i) "\t" path
        if (!blank(O[i])) print "D\t" (os + i) "\t" path
      }
      for (i = 0; i < nn; i++) if (!(i < no && O[i] == N[i]) && !blank(N[i])) print "A\t" (ns + i) "\t" path
      no = 0; nn = 0
    }
    /^diff --git / { flush(); h = 0; oldp = ""; next }
    # git ends a ---/+++ line with a tab when an unquoted name has a space in it
    function name(s) { if (substr(s, 1, 1) != "\"" && substr(s, length(s)) == "\t") s = substr(s, 1, length(s) - 1); return unq(s) }
    !h && /^--- / { oldp = name(substr($0, 5)); next }
    !h && /^\+\+\+ / { p = name(substr($0, 5))
      if (p == "/dev/null") p = oldp
      path = substr(p, 3); next }
    /^@@ / { flush(); split($2, o, ","); os = substr(o[1], 2) + 0
             split($3, n, ","); ns = substr(n[1], 2) + 0; h = 1; next }
    !h { next }
    /^-/ { O[no++] = substr($0, 2); next }
    /^\+/ { N[nn++] = substr($0, 2); next }
    END { flush() }'
}
present() { GIT cat-file -e "$1:$2" 2>/dev/null; }   # <rev> <path>: does <rev> have it

# Where <rev>'s net change since its merge-base with the baseline landed: the
# EARLIEST commit, walking the baseline's first-parent history forward from the
# merge-base, that holds that whole net change. C holds it when, in every path the
# net change touches, each line <rev> added (not blank) is still in place in C
# (diff(rev→C) leaves it unchanged) and each line it deleted is no longer in place
# (diff(merge-base→C) changes it); a path with no such line (an empty file, a mode or
# blank-line change) must exist in C exactly when it exists in <rev>. Edits main made
# on its own elsewhere, even on the next line, do not matter. The merge-base is
# tried first: with no net change, <rev> landed there. Only descendants of the
# merge-base count: a first-parent commit on main's side of a later merge is measured
# against an older base, where a branch that undoes its own starting point looks
# contained. The first first-parent descendant is always tried; after it, only
# descendants that touch the paths <rev> changed — one that does not touch them holds
# exactly what its parent holds. Every check spends one unit of BUDGET, shared by all
# calls, so the prefix search below is bounded too (each attempt tries at least the
# merge-base).
BUDGET=200
LAND="" ; LAND_NOTE="" ; LAND_NONE="" ; LAND_AT_MB="" ; WALK_MB="" ; NET_KEY=""
net_of() { # <merge-base> <rev> -> $SCRATCH/net.{z,diff,bare} for that pair, cached
  [ "$NET_KEY" = "$1 $2" ] && return 0
  GIT diff-tree -r -z --name-only --no-renames --ignore-submodules=none "$1" "$2" \
    > "$SCRATCH/net.z" 2>/dev/null || return 1
  # A path with LF in its name cannot go through the line-based steps below.
  has_lf "$SCRATCH/net.z"; [ $? -eq 1 ] || return 1
  pdiff "$1" "$2" "$SCRATCH/net.z" | pparse > "$SCRATCH/net.diff" || return 1
  # The paths with no line to compare, and whether <rev> has each.
  tr '\000' '\n' < "$SCRATCH/net.z" | LC_ALL=C awk -v d="$SCRATCH/net.diff" '
    BEGIN { while ((r = getline l < d) > 0) { if (l ~ /^[AD]\t/) { i = index(substr(l, 3), "\t"); seen[substr(l, 3 + i)] = 1 } }
            if (r < 0) exit 2 }
    !($0 in seen) { print }' > "$SCRATCH/net.bare" || return 1
  : > "$SCRATCH/net.has"
  while IFS= read -r p; do
    if present "$2" "$p"; then printf '1\t%s\n' "$p"; else printf '0\t%s\n' "$p"; fi
  done < "$SCRATCH/net.bare" > "$SCRATCH/net.has" || return 1
  NET_KEY="$1 $2"
}
holds() { # <commit> <rev> -> 0 holds, 1 does not, 2 error (LAND_NOTE set); HOLD_MB is <rev>'s merge-base
  local c="$1" rev="$2" p want
  if [ "$BUDGET" -le 0 ]; then
    LAND_NOTE="the budget of 200 checks ran out before a landing commit was found"; return 2
  fi
  BUDGET=$((BUDGET - 1))
  net_of "$HOLD_MB" "$rev" || { LAND_NOTE="cannot read the net change of $(short "$rev")"; return 2; }
  { pdiff "$rev" "$c" "$SCRATCH/net.z" | pparse > "$SCRATCH/h.rev" \
    && pdiff "$HOLD_MB" "$c" "$SCRATCH/net.z" | pparse > "$SCRATCH/h.mb"; } \
    || { LAND_NOTE="cannot compare $(short "$c") with the branch"; return 2; }
  LC_ALL=C awk -F '\t' -v net="$SCRATCH/net.diff" -v hrev="$SCRATCH/h.rev" -v hmb="$SCRATCH/h.mb" '
    function key(l) { return substr(l, 3) }       # "<line number><TAB><path>"
    BEGIN {
      while ((r = getline l < hrev) > 0) if (substr(l, 1, 1) == "C") moved[key(l)] = 1
      if (r < 0) exit 2
      while ((r = getline l < hmb) > 0) if (substr(l, 1, 1) == "C") gone[key(l)] = 1
      if (r < 0) exit 2
      while ((r = getline l < net) > 0) {
        t = substr(l, 1, 1)
        if (t == "A" && (key(l) in moved)) exit 1      # an added line is not in place
        if (t == "D" && !(key(l) in gone)) exit 1      # a deleted line is still in place
      }
      if (r < 0) exit 2
      exit 0
    }'
  case $? in 0) ;; 1) return 1 ;; *) LAND_NOTE="cannot compare $(short "$c") with the branch"; return 2 ;; esac
  while IFS= read -r p; do
    want="${p%%$'\t'*}"; p="${p#*$'\t'}"
    if present "$c" "$p"; then [ "$want" = 1 ] || return 1; else [ "$want" = 0 ] || return 1; fi
  done < "$SCRATCH/net.has"
  return 0
}
find_landing() { # <rev>
  local rev="$1" mb c n=0 rc fail="cannot list the baseline's commits"
  LAND="" ; LAND_NOTE="" ; LAND_NONE="" ; LAND_AT_MB=""
  mb="$(GIT merge-base "$BASELINE_SHA" "$rev" 2>/dev/null)" \
    || { LAND_NOTE="no merge-base between branch and baseline"; return 1; }
  HOLD_MB="$mb"
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
LANDING="" ; PREFIX_TIP="" ; LANDING_NOTE="" ; LANDING_AT_MB="" ; PREFIX_NOTE=""
prefix_search() { # -> 0 a prefix landed after the merge-base (LANDING, PREFIX_TIP set), 1 none, 2 error
  local mb b
  mb="$(GIT merge-base "$BASELINE_SHA" "$BRANCH_SHA" 2>/dev/null)" || { PREFIX_NOTE="no merge-base between branch and baseline"; return 2; }
  for b in $(GIT rev-list --first-parent "$mb..$BRANCH_SHA" 2>/dev/null | sed 1d | head -n "$PREFIX_TRIES"); do
    if find_landing "$b"; then
      # A prefix that undid itself holds its (empty) net change at the merge-base;
      # nothing of the branch landed there, so keep looking.
      [ -z "$LAND_AT_MB" ] || continue
      LANDING="$LAND"; PREFIX_TIP="$b"; return 0
    fi
    [ -n "$LAND_NONE" ] || { PREFIX_NOTE="$LAND_NOTE"; return 2; }
  done
  return 1
}
if find_landing "$BRANCH_SHA"; then
  LANDING="$LAND"; LANDING_AT_MB="$LAND_AT_MB"
  # A branch with no net change "lands" at the merge-base whatever reached main.
  # When a prefix of it landed later (a squash of its first commits, before the
  # commits that undid them), that prefix is where it landed, and the commits
  # after it are checked at the tip. Without this a dropped restore was missed
  # (3.5.0 caught it; #399 verify round 10).
  if [ -n "$LANDING_AT_MB" ]; then
    prefix_search; rc=$?
    case "$rc" in
      0) LANDING_AT_MB="" ;;
      2) LANDING_NOTE="$PREFIX_NOTE"; LANDING=""; LANDING_AT_MB="" ;;
    esac
  fi
else
  LANDING_NOTE="$LAND_NOTE"
  if [ -n "$LAND_NONE" ]; then
    prefix_search; rc=$?
    case "$rc" in 0) LANDING_NOTE="" ;; 2) LANDING_NOTE="$PREFIX_NOTE" ;; esac
  fi
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
  GIT ls-tree -r -z --full-tree "$1" > "$SCRATCH/$2.tree" 2>/dev/null || return 1
  tr '\n\000' '\001\n' < "$SCRATCH/$2.tree" | LC_ALL=C awk -v paths="$SCRATCH/paths" -v out="$SCRATCH/$2.map" '
    BEGIN { while ((r = getline p < paths) > 0) need[p] = n++; if (r < 0) bad = 1; close(paths) }
    { i = index($0, "\t"); p = substr($0, i + 1)
      if (!(p in need)) next
      split(substr($0, 1, i - 1), m, " ")
      e[need[p]] = (m[2] == "commit" ? "link " : "blob ") m[3] }
    END { if (bad) exit 2
          for (j = 0; j < n; j++) print ((j in e) ? e[j] : "none") > out }'
}
# The tip is compared by line presence (orphan_p), so only the head and the tip are
# listed; the landing commit is compared in place (land_orphan_p).
SIDES="head"
[ -z "$NEED_TIP" ] || SIDES="$SIDES tip"
if [ -f "$SCRATCH/paths" ]; then
  for side in $SIDES; do
    case "$side" in head) rev="$BRANCH_SHA" ;; tip) rev="$BASELINE_SHA" ;; esac
    classify "$rev" "$side" || skip "cannot list the tree of $(short "$rev")"
  done
  for side in $SIDES; do cat "$SCRATCH/$side.map"; done | awk '$1 == "blob" { print $2 }' | sort -u \
    > "$SCRATCH/blobs" || skip "cannot list the blobs to read"
  # One file per blob, read by awk one at a time, so a file without a final newline
  # cannot run into the next one.
  while IFS= read -r oid; do
    GIT cat-file blob "$oid" > "$SCRATCH/blob.$oid" 2>/dev/null || skip "cannot read blob $oid"
  done < "$SCRATCH/blobs"
fi

orphan_p() { # <commit-sha> <candidate number> -> 10 orphan, 11 landed, other: error (at the tip)
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
  # that the head has and the target does not (an empty file). Only presence is
  # compared: at the tip the edits main made itself are unknown (SPEC.md D1, D2).
  LC_ALL=C awk -v d="$SCRATCH" -v list="$SCRATCH/c.$2" -v dels="$SCRATCH/D.$2" -v adds="$SCRATCH/A.$2" '
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
    # h, t: whether the head and the tip have the line (or the path).
    function missing(h, t) { return h && !t }
    function kept(h, t) { return !h && t }
    function paths(f, del,    l, r, j, h, t) {
      while ((r = getline l < f) > 0) {
        if (!(l in pidx)) { bad = 1; break }
        j = pidx[l]; h = hm[j] != "none"; t = tm[j] != "none"
        if (del ? kept(h, t) : missing(h, t)) found = 1
      }
      if (r < 0) bad = 1; close(f)
    }
    BEGIN {
      slurp(d "/head.map", hm); slurp(d "/tip.map", tm)
      while ((r = getline j < list) > 0) { load(hm[j], head); load(tm[j], target) }
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
      if (missing(line in head, line in target)) { found = 1; exit }
    }
    /^-/ {
      line = substr($0, 2)
      if (line ~ /^[ \t\r\f\v]*$/) next
      if (kept(line in head, line in target)) { found = 1; exit }
    }
    END { if (bad) exit 2; exit (found ? 10 : 11) }' "$SCRATCH/patch"
}

# For tests/merge-completeness/bounded.py only: where each candidate was checked.
# It only ever creates a new file (noclobber; an existing file or symlink is left
# alone), and a failed write is ignored, so a stray variable cannot overwrite a file
# or change the gate's answer.
if [ -n "${CHECK_MERGE_COMPLETENESS_TRACE:-}" ] && [ ! -e "$CHECK_MERGE_COMPLETENESS_TRACE" ] \
   && [ ! -L "$CHECK_MERGE_COMPLETENESS_TRACE" ]; then
  ( set -C
    { printf 'landing %s prefix %s\n' "${LANDING:--}" "${PREFIX_TIP:--}"
      set -- $SIDE_OF
      for sha in $CANDIDATES; do printf 'side %s %s\n' "$sha" "$1"; shift; done
    } > "$CHECK_MERGE_COMPLETENESS_TRACE" ) 2>/dev/null || :
fi

# At a landing commit L each commit c is checked in its own place, the way SPEC.md
# defines an orphan. Over the paths c touched: a line c added (not blank) is an effect
# the head still shows when diff(c→head) leaves it unchanged, and it is missing when
# diff(c→L) changes it; a line c deleted is an effect the head shows when
# diff(c^→head) changes it, and it is still there when diff(c^→L) leaves it unchanged.
# A path c added or deleted with no line to compare (an empty file) is missing when
# the head has it and L does not, or the other way round. Main's own edits elsewhere
# in L, even on the next line, and main's own copy of the same text elsewhere, do not
# count; a mode change, a blank line and a final newline are not effects.
land_orphan_p() { # <commit-sha> <candidate number> -> 10 orphan, 11 landed, other: error
  local c="$1" par p
  [ -s "$SCRATCH/c.$2" ] || return 11
  par="$(GIT rev-parse -q --verify "$c^1^{commit}" 2>/dev/null)" || par="$EMPTY_TREE"
  # the candidate's paths, NUL-separated (none has LF: those were refused above)
  LC_ALL=C awk -v paths="$SCRATCH/paths" 'BEGIN { while ((getline l < paths) > 0) P[n++] = l }
    { printf "%s%c", P[$0], 0 }' "$SCRATCH/c.$2" > "$SCRATCH/cp.z" || return 2
  { pdiff "$par" "$c" "$SCRATCH/cp.z" | pparse > "$SCRATCH/l.own" \
    && pdiff "$c" "$BRANCH_SHA" "$SCRATCH/cp.z" | pparse > "$SCRATCH/l.hc" \
    && pdiff "$c" "$LANDING" "$SCRATCH/cp.z" | pparse > "$SCRATCH/l.lc" \
    && pdiff "$par" "$BRANCH_SHA" "$SCRATCH/cp.z" | pparse > "$SCRATCH/l.hp" \
    && pdiff "$par" "$LANDING" "$SCRATCH/cp.z" | pparse > "$SCRATCH/l.lp"; } || return 2
  LC_ALL=C awk -v d="$SCRATCH" '
    function load(f, set,    l, r) {
      while ((r = getline l < f) > 0) if (substr(l, 1, 1) == "C") set[substr(l, 3)] = 1
      if (r < 0) exit 2
    }
    BEGIN {
      load(d "/l.hc", hc); load(d "/l.lc", lc); load(d "/l.hp", hp); load(d "/l.lp", lp)
      while ((r = getline l < (d "/l.own")) > 0) {
        t = substr(l, 1, 1); k = substr(l, 3)
        if (t == "A" && !(k in hc) && (k in lc)) exit 10    # added, still in the head, not in L
        if (t == "D" && (k in hp) && !(k in lp)) exit 10    # deleted, gone from the head, still in L
      }
      if (r < 0) exit 2
      exit 11
    }'
  case $? in 10) return 10 ;; 11) ;; *) return 2 ;; esac
  # Paths the candidate added or deleted whole with no line to compare.
  LC_ALL=C awk -v own="$SCRATCH/l.own" 'BEGIN { while ((getline l < own) > 0) if (l ~ /^[AD]\t/) { i = index(substr(l, 3), "\t"); seen[substr(l, 3 + i)] = 1 } }
    !($0 in seen) { print }' "$SCRATCH/A.$2" > "$SCRATCH/l.bare" || return 2
  while IFS= read -r p; do
    present "$BRANCH_SHA" "$p" && ! present "$LANDING" "$p" && return 10
  done < "$SCRATCH/l.bare"
  LC_ALL=C awk -v own="$SCRATCH/l.own" 'BEGIN { while ((getline l < own) > 0) if (l ~ /^[AD]\t/) { i = index(substr(l, 3), "\t"); seen[substr(l, 3 + i)] = 1 } }
    !($0 in seen) { print }' "$SCRATCH/D.$2" > "$SCRATCH/l.bare" || return 2
  while IFS= read -r p; do
    ! present "$BRANCH_SHA" "$p" && present "$LANDING" "$p" && return 10
  done < "$SCRATCH/l.bare"
  return 11
}
ORPHANS="" ; k=0
set -- $SIDE_OF
for sha in $CANDIDATES; do
  side="$1"; shift
  if [ "$side" = land ]; then land_orphan_p "$sha" "$k"; else orphan_p "$sha" "$k"; fi; rc=$?
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
