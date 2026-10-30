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
#      from the baseline (candidate orphans). None → exit 0. On every path a
#      candidate touched the tip has exactly what the head has → exit 0: nothing is
#      left to land, however main got there (#399's first test).
#   2. LANDING COMMIT (#399). The gate answers "did the branch's content land":
#      what main did after it landed — a follow-up edit, a revert — is main's own
#      history and out of scope. Walking the baseline's first-parent history
#      forward from the merge-base (the merge-base itself, the first descendant,
#      then descendants that touch the paths the branch changed), the EARLIEST
#      commit L that holds the branch's whole net change is where the branch landed:
#      every line the net change adds is in place in L, every line it deletes is no
#      longer in place there, and L has exactly the paths the head has among those
#      the net change touches. Two-way diffs with renames detected (no merge, so
#      main's own edits elsewhere, even on the next line, do not matter, nor does
#      main's edit of a file the branch moved). Where L fails only on lines whose
#      text occurs more than once (git may pair equal lines one way when it builds L
#      and another way here), L holds the net change when its own step changes the
#      number of copies of each such text exactly as the net change does, for a text
#      at most one commit of the branch touches (adds or deletes a line of it) and
#      whose number of copies the net change changes (a move has none to compare),
#      when some other line of the net change is in place in L that L's own step
#      brought (not already in place in its parent) and L is not a merge commit (a
#      merge's step brings other commits too). When the whole branch
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
#      does. A position identifies a line only while the lines around it say which one
#      it is: git may have put main's edit on one of several equal lines when it built
#      L and paired them the other way here, and next to a block of repeated lines it
#      can pair even a unique line with another. So every finding stands only when the
#      copies agree too (L, less what main added or removed before L, has fewer copies
#      of an added line than what landed there, or more of a deleted one); a unique
#      line must also be in L as often as in what landed, before main's copies are
#      counted, and one the commit moved (its step leaves the number of copies alone)
#      is judged by its position alone. Copies are counted only in a file the commit
#      edited (each revision's file under the name it has there), never for a
#      submodule pointer. What L^1 gained or lost since the merge-base is main's,
#      unless another commit of the branch that changes the copies reached L^1 (its
#      own change all in place there): the finding then stands. At the tip, where main's own edits are
#      unknown, only line presence is compared, each file read under the names it has
#      in the head too. Squash → the effects are there → not an orphan. Partial merge
#      → a dropped commit's effect is missing → orphan.
#   Every comparison reads trees with `git diff`, `ls-tree` and `cat-file`: no merge,
#   so no merge driver or attribute can steer the answer. (Above 64 KB of paths, two
#   trees holding only those paths are written to a temporary object store and
#   compared; nothing is written into the repository, though git may refresh the
#   timestamp of a tree object it already has.)
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
#   - at the landing commit, a copy of a line next to an identical line, or next to
#     an identical line another PR inserted: diff may pair the copies either way, so
#     a copy that never landed (or a deletion that did not) can read as in place,
#     and a branch can look landed where only part of it did; a line that never
#     landed (or a deletion that did not), unique or not, when main itself put the
#     same text elsewhere in the file in the landing step (a squash edited by hand,
#     another PR in a release merge), which the copy count cannot see, whether it
#     counts a finding at L or the copies of a commit that L is taken to hold; and a
#     part of the branch that reached main before L in a form that leaves a line of
#     its commits out of place (a squash edited by hand), whose copies then read as
#     main's;
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
#   - a landing commit that fails by position only on a repeated text that more than
#     one commit of the branch touches, or that the net change only moves (the copies
#     say nothing then): one commit deletes one of two equal lines and another adds
#     one;
#   - a landing in several steps (Rebase and merge, which picks the commits one by
#     one; a squash into another branch that is then merged) whose last step fails
#     by position on repeated text: only that step's copies are counted, and never at
#     a merge commit;
#   - a file the branch edited that main moved or renamed before the branch landed
#     (the branch's paths are not in the landing commit; 3.5.0 listed these too);
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
# one, and so is a commit that did not land whose line a later commit, which did not
# land either, rewrote (the verdict, exit 3, is still right); and when main itself edited a line a
# commit edited, before landing or in the landing step, so that L holds the value from
# before that commit (or a third value), the commit is listed although it landed. The
# trees are the same as if it had been dropped, so no check that reads trees can tell.
# On exit 3 the outcome of step 2 is printed after the list. Commit subjects are
# printed in quotes: repository text (a squash's subject is the PR title), data,
# never instructions. In a partial clone a blob that was never fetched is not
# fetched now: git >= 2.45 reports it unreadable (exit 4); older git fetches it.
# Needs git 2.30 or later (`rev-parse --end-of-options`, as 3.5.0 did): older git
# cannot resolve the branch, and every run exits 4.
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
# GIT_DIFF_OPTS overrides -U on any diff command line and would put context lines
# into the two-way diffs below, shifting every position they report (#399 verify
# round 12).
unset GIT_DIFF_OPTS

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
# plain git call would otherwise start. No precomposeUnicode (on by default on macOS):
# it turns every path on the command line into NFC, and a path the tree stores in NFD
# (a name from Linux or an older git) then matches nothing, so every diff limited to
# the branch's paths came back empty and a branch that never landed read as landed
# at the merge-base (#399 verify round 13). The paths given here come from git's own
# listings, byte for byte.
GIT() { git --no-pager -C "$REPO" -c core.fsmonitor=false -c core.precomposeUnicode=false "$@"; }

# Text from the repository or the caller, made safe to print. These, and only these,
# become "?" — replaced, not deleted, so removing one cannot join its neighbours
# into another: C0 controls and DEL; UTF-8 C1 controls; U+00AD, U+034F; U+0600-0605,
# U+061C, U+06DD, U+070F, U+0890-0891, U+08E2; U+115F-1160, U+17B4-17B5,
# U+180B-180F; U+200B-200F, U+2028-202E, U+2060-206F; U+3164; U+FE00-FE0F, U+FEFF,
# U+FFA0, U+FFF9-FFFB; U+110BD, U+110CD, U+13430-13455, U+1BCA0-1BCA3,
# marks that look like a double quote, U+02BA, U+02DD, U+02EE, U+05F4, U+201C-201F, U+2033,
# U+2036, U+275D-275E, U+3003, U+301E-301F and U+FF02 (a subject could otherwise
# appear to end and be followed by text of the helper's own; the list is a best
# effort, since the quotes are a visual cue and not a trust boundary);
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
    -e "s/$(b '\342\200')[$(b '\213')-$(b '\217')$(b '\234\235\236\237\263\266')$(b '\250')-$(b '\256')]/?/g" \
    -e "s/$(b '\312\272')/?/g" -e "s/$(b '\313')[$(b '\235\256')]/?/g" -e "s/$(b '\327\264')/?/g" \
    -e "s/$(b '\342\235')[$(b '\235\236')]/?/g" -e "s/$(b '\343\200')[$(b '\203\236\237')]/?/g" \
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
# Absolute: git runs with -C "$REPO" and would read a relative path from there (a
# relative TMPDIR), while the shell reads it from the caller's directory.
SCRATCH="$(cd "$SCRATCH" && pwd -P)" || skip "cannot resolve the temp dir"
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

# The test-only trace (bounded.py): never overwrites a file, never changes the answer.
trace_out() { # stdin -> $CHECK_MERGE_COMPLETENESS_TRACE
  if [ -n "${CHECK_MERGE_COMPLETENESS_TRACE:-}" ] && [ ! -e "$CHECK_MERGE_COMPLETENESS_TRACE" ] \
     && [ ! -L "$CHECK_MERGE_COMPLETENESS_TRACE" ]; then
    ( set -C; cat > "$CHECK_MERGE_COMPLETENESS_TRACE" ) 2>/dev/null || :
  else
    cat > /dev/null
  fi
}

# <commit> -> $SCRATCH/rn.<commit>: the names in the branch head of the files the
# commit touched that a later commit of the branch moved, one per line (an LF inside
# a name becomes \001, as in the tree listings). Read by a two-tree diff with renames
# detected, from the commit to the head, so a file moved twice comes out under its
# last name. A commit's effects are in the head under those names: read under the
# commit's own name, a file the branch later moved is in neither the head nor the
# tip, and its unlanded lines read as landed (#399 verify round 14).
head_names() {
  [ -f "$SCRATCH/rn.$1" ] && return 0
  GIT diff-tree --root --no-commit-id --ignore-submodules=none --name-only -r -z "$1" 2>/dev/null \
    | tr '\n\000' '\001\n' > "$SCRATCH/rn.own" || return 2
  GIT diff-tree -r -z -M -l1000 --name-status --ignore-submodules=none "$1" "$BRANCH_SHA" 2>/dev/null \
    | tr '\n\000' '\001\n' | LC_ALL=C awk -v own="$SCRATCH/rn.own" '
      BEGIN { while ((r = getline l < own) > 0) mine[l] = 1; if (r < 0) exit 2 }
      want == 0 { st = $0; want = (st ~ /^[RC]/) ? 2 : 1; got = 0; next }
      { got++; if (got == 1) src = $0
        if (got == want) { if (st ~ /^R/ && (src in mine)) print $0; want = 0 } }
      END { if (want) exit 2 }' > "$SCRATCH/rn.tmp" && mv "$SCRATCH/rn.tmp" "$SCRATCH/rn.$1"
}

# ── The head's content is already at the tip (#399) ──
# The issue's own first test: when, on every path a candidate touched, the tip has
# exactly what the head has (the same blob, or no file on either side), there is
# nothing left to land, however main got there (a squash resolved by hand to the
# head's tree, a later commit of main's own). Plumbing, so no diff setting applies.
# A candidate path with a newline is left to the check below, which refuses it. (A
# file the branch moved after a candidate is compared too: the commit that moved it
# carries its content and is a candidate as well: git cherry's patch ids include the
# content, so only a move of the same content on main matches it.)
GIT diff-tree -r -z --name-only --no-renames --ignore-submodules=none "$BRANCH_SHA" "$BASELINE_SHA" \
  > "$SCRATCH/headtip.z" 2>/dev/null || skip "cannot compare the branch head with $S"
: > "$SCRATCH/cand.z"
for sha in $CANDIDATES; do
  GIT diff-tree --root --no-commit-id --ignore-submodules=none --name-only -r -z "$sha" \
    >> "$SCRATCH/cand.z" 2>/dev/null || skip "cannot list the paths $(short "$sha") touched"
done
has_lf "$SCRATCH/cand.z"; rc=$?
if [ "$rc" -eq 1 ]; then
  tr '\000' '\n' < "$SCRATCH/headtip.z" > "$SCRATCH/headtip" \
    && tr '\000' '\n' < "$SCRATCH/cand.z" > "$SCRATCH/cand" || skip "cannot read the paths the branch touched"
  # exit 3: a candidate touched a path where the head and the tip differ
  LC_ALL=C awk -v d="$SCRATCH/headtip" '
    BEGIN { while ((r = getline l < d) > 0) differ[l] = 1; if (r < 0) exit 2 }
    ($0 in differ) { exit 3 }' "$SCRATCH/cand"; rc=$?
  if [ "$rc" -eq 0 ]; then
    printf 'landing - prefix -\nshortcut\n' | trace_out
    exit 0
  fi
fi

# ── Comparing two trees line by line, in place (#399) ──
# Everything at a landing commit is decided by two-way diffs read position by
# position: which old-side lines a diff changes, and which lines it adds or deletes.
# There is no three-way merge anywhere: a merge conflicts when two edits merely sit
# on adjacent lines, and round 11 read such a conflict as "landed" (#399 verify
# round 11). Every option that shapes the output is pinned, so no config, attribute
# or external program changes it: no context lines between hunks
# (diff.interHunkContext; GIT_DIFF_OPTS is unset above), no external diff, no
# textconv, --text for files git calls binary, rename detection with git's default
# threshold and limit (diff.renames, diff.renameLimit), myers with the indent
# heuristic (diff.algorithm, diff.indentHeuristic), fixed a/ and b/ prefixes
# (diff.noprefix, diff.mnemonicPrefix), quoted names (core.quotePath), no color, no
# order file (diff.orderFile: a missing one makes git diff fail, which sent every
# check to the tip, #399 verify round 13; an existing one is opened and read),
# and submodules as "Subproject commit <oid>" lines (diff.submodule). Renames are
# detected because a moved file is otherwise all new lines, and one line main edited
# in it makes no commit hold the branch's net change (round 12). The helper runs at
# the top level, where diff.relative changes nothing. git's messages are discarded:
# they can quote repository text (an invalid attribute name).
EMPTY_TREE="$(GIT hash-object -t tree /dev/null 2>/dev/null)" || skip "cannot name the empty tree"
# Paths go on a command line only up to PATHS_MAX bytes. Beyond that, two trees
# holding only the listed paths are built in a scratch object store (the repository
# is never written) and compared whole: git then pairs renames among exactly the
# same paths as on the command line. Comparing the full trees instead let git pair a
# listed path with one main had moved it to, outside the list, and the listed path's
# records were dropped (#399 verify round 13).
PATHS_MAX=65536
# Set up here, once: pdiff runs inside pipelines (subshells), where a lazy setup
# would not be remembered.
SOBJ="$SCRATCH/objects"
COMMON="$(GIT rev-parse --git-common-dir 2>/dev/null)" && mkdir "$SOBJ" || skip "cannot set up a scratch object store"
case "$COMMON" in /*) ;; *) COMMON="$REPO/$COMMON" ;; esac
# The repository's object directory goes first in the alternates list, C-quoted, so a
# ':' in its path does not split it (git reads an entry that starts with '"' quoted).
SALT="\"$(printf '%s' "${GIT_OBJECT_DIRECTORY:-$COMMON/objects}" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')\"${GIT_ALTERNATE_OBJECT_DIRECTORIES:+:$GIT_ALTERNATE_OBJECT_DIRECTORIES}"
# No split index: with core.splitIndex on, update-index writes its shared index into
# the repository's own .git, not next to GIT_INDEX_FILE (#399 verify round 14). The
# scratch store never writes into the repository; write-tree may still refresh the
# timestamp of a tree the repository already has.
unset GIT_TEST_SPLIT_INDEX
SGIT() { GIT_OBJECT_DIRECTORY="$SOBJ" GIT_ALTERNATE_OBJECT_DIRECTORIES="$SALT" GIT -c core.splitIndex=false "$@"; }
# <rev> <list key> -> the tree of <rev>'s entries at the paths in $SCRATCH/ft.list.<key>,
# built once per tree and list (pdiff runs in subshells, so the cache is on disk, keyed
# by the tree's id and the list's hash). Every listed entry must reach the index:
# update-index skips, with a warning and exit 0, a path it refuses (a .git component,
# an NTFS or HFS form of one), and the tree would then lack it while the pathspec form
# sees it (#399 verify round 14). --missing-ok: the tree is only compared, so a blob a
# partial clone never fetched is not needed unless the diff reads it.
ftree() {
  local tree out
  tree="$(GIT rev-parse -q --verify "$1^{tree}" 2>/dev/null)" || return 2
  out="$SCRATCH/ft.$2.$tree"
  [ -s "$out" ] && { cat "$out"; return 0; }
  rm -f "$SCRATCH/ft.idx"
  GIT ls-tree -r -z --full-tree "$tree" 2>/dev/null | tr '\n\000' '\001\n' \
    | LC_ALL=C awk -v list="$SCRATCH/ft.list.$2" 'BEGIN { while ((r = getline l < list) > 0) want[l] = 1; if (r < 0) exit 2 }
        { i = index($0, "\t"); if (substr($0, i + 1) in want) print }' > "$SCRATCH/ft.in" || return 2
  tr '\n' '\000' < "$SCRATCH/ft.in" \
    | GIT_INDEX_FILE="$SCRATCH/ft.idx" SGIT update-index -z --index-info 2>/dev/null || return 2
  [ "$(GIT_INDEX_FILE="$SCRATCH/ft.idx" SGIT ls-files -s -z 2>/dev/null | tr -cd '\000' | wc -c | tr -d ' ')" \
    = "$(wc -l < "$SCRATCH/ft.in" | tr -d ' ')" ] || return 2
  GIT_INDEX_FILE="$SCRATCH/ft.idx" SGIT write-tree --missing-ok > "$out.tmp" 2>/dev/null \
    && [ -s "$out.tmp" ] && mv "$out.tmp" "$out" || return 2
  cat "$out"
}
DIFF_OPTS=(-c core.quotePath=true --literal-pathspecs diff -U0 --inter-hunk-context=0 --no-color -O/dev/null
  --no-ext-diff --no-textconv --text --find-renames -l1000 --diff-algorithm=myers --indent-heuristic
  --src-prefix=a/ --dst-prefix=b/ --ignore-submodules=none --submodule=short)
pdiff() { # <a> <b> <paths file, NUL-separated> -> unified diff with no context
  local p n ta tb lk
  local -a ps
  ps=()
  [ -r "$3" ] || return 2
  n="$(wc -c < "$3" | tr -d ' ')" || return 2
  [ "$n" -gt 0 ] || return 0
  if [ "$n" -le "$PATHS_MAX" ]; then
    while IFS= read -r -d '' p; do ps+=("$p"); done < "$3" || return 2
    GIT "${DIFF_OPTS[@]}" "$1" "$2" -- "${ps[@]}" 2>/dev/null
  else
    lk="$(GIT hash-object --stdin < "$3" 2>/dev/null)" || return 2
    [ -s "$SCRATCH/ft.list.$lk" ] || tr '\000' '\n' < "$3" > "$SCRATCH/ft.list.$lk" || return 2
    ta="$(ftree "$1" "$lk")" && tb="$(ftree "$2" "$lk")" || return 2
    SGIT "${DIFF_OPTS[@]}" "$ta" "$tb" 2>/dev/null
  fi
}
# One record per line, "<kind><TAB><line number><TAB><path>": C, an old-side line the
# diff changes; A, a new-side line it adds; D, an old-side line it deletes (A and D
# skip blank lines, which SPEC.md's definition ignores). Within a hunk an old and a
# new line at the same offset with the same text are unchanged (two equal lines diff
# happened to pair), and so is a last line whose final newline alone changed, paired
# with the equal line on the other side wherever it sits in the hunk. Paths come
# from the ---/+++ lines (the new name for a renamed file), C-unquoted when git
# quoted them, and only the paths in <paths file> are kept: a pathspec also matches
# what lies under a directory of that name, and a decoded name with a newline in it
# would split a record (the listed paths have none; those were refused above).
# Anything unexpected inside a hunk (a context line, from a setting the options
# above do not cover) fails the whole read (exit 2) rather than shift a position.
# A renamed file with hunks also gets two records, "N<TAB>0<TAB><new name>" and right
# after it "O<TAB>0<TAB><old name>", so the copy counts below can read the file under
# the name each revision has (old_of); every other reader skips them.
pparse() { # <paths file, NUL-separated>
  local list="$SCRATCH/pparse.list"
  tr '\000' '\n' < "$1" > "$list" || return 2
  LC_ALL=C awk -v list="$list" '
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
    # git ends a ---/+++ line with a tab when the name has a space in it, quoted or not
    function name(s) { if (substr(s, length(s)) == "\t") s = substr(s, 1, length(s) - 1); return unq(s) }
    function blank(t) { return t ~ /^[ \t\r\f\v]*$/ }
    function flush(   i, j) {
      for (i = 0; i < no; i++) po[i] = 0
      for (j = 0; j < nn; j++) pn[j] = 0
      for (i = 0; i < no && i < nn; i++) if (O[i] == N[i]) { po[i] = 1; pn[i] = 1 }
      if (onl >= 0 && !po[onl]) for (j = 0; j < nn; j++) if (!pn[j] && N[j] == O[onl]) { po[onl] = 1; pn[j] = 1; break }
      if (nnl >= 0 && !pn[nnl]) for (i = 0; i < no; i++) if (!po[i] && O[i] == N[nnl]) { po[i] = 1; pn[nnl] = 1; break }
      if (keep) {
        for (i = 0; i < no; i++) if (!po[i]) {
          print "C\t" (os + i) "\t" path
          if (!blank(O[i])) print "D\t" (os + i) "\t" path
        }
        for (j = 0; j < nn; j++) if (!pn[j] && !blank(N[j])) print "A\t" (ns + j) "\t" path
      }
      no = 0; nn = 0; onl = -1; nnl = -1; last = ""
    }
    BEGIN { while ((r = getline l < list) > 0) want[l] = 1; if (r < 0) { bad = 1; exit }; onl = -1; nnl = -1 }
    /^diff --git / { flush(); h = 0; oldp = ""; next }
    !h && /^--- / { oldp = name(substr($0, 5)); next }
    !h && /^\+\+\+ / { p = name(substr($0, 5))
      if (p == "/dev/null") p = oldp
      path = substr(p, 3); keep = (path in want)
      if (keep && oldp != "/dev/null" && substr(oldp, 3) != path && (substr(oldp, 3) in want)) {
        print "N\t0\t" path; print "O\t0\t" substr(oldp, 3)
      }
      next }
    /^@@ / { flush(); split($2, o, ","); os = substr(o[1], 2) + 0
             split($3, n, ","); ns = substr(n[1], 2) + 0; h = 1; next }
    !h { next }
    /^-/ { O[no++] = substr($0, 2); last = "O"; next }
    /^\+/ { N[nn++] = substr($0, 2); last = "N"; next }
    /^\\/ { if (last == "O") onl = no - 1; else if (last == "N") nnl = nn - 1; next }
    { bad = 1; exit }
    END { if (bad) exit 2; flush() }'
}
# <rev> <path>: prints "blob" or "commit" (a submodule) and returns 0 when <rev> has
# one at exactly <path>; 1 when it does not (a directory there counts as no file); 2
# when the tree cannot be read. Read from the tree entry: "<rev>:<path>" names the
# object a gitlink points at, which may be missing, a commit, or even a blob of the
# superproject (#399 verify round 13).
entry_of() {
  local out
  out="$(GIT --literal-pathspecs ls-tree -z --full-tree "$1" -- "$2" 2>/dev/null | tr '\000' '\n')" || return 2
  case "$out" in
    *" blob "*"	$2") [ "${out#*	}" = "$2" ] && { echo blob; return 0; } ;;
    *" commit "*"	$2") [ "${out#*	}" = "$2" ] && { echo commit; return 0; } ;;
  esac
  return 1
}

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
LAND="" ; LAND_MB="" ; LAND_NOTE="" ; LAND_NONE="" ; LAND_AT_MB="" ; WALK_MB="" ; NET_KEY=""
net_of() { # <merge-base> <rev> -> $SCRATCH/net.{z,list,diff} for that pair, cached
  [ "$NET_KEY" = "$1 $2" ] && return 0
  GIT diff-tree -r -z --name-only --no-renames --ignore-submodules=none "$1" "$2" \
    > "$SCRATCH/net.z" 2>/dev/null || return 1
  # A path with LF in its name cannot go through the line-based steps below.
  has_lf "$SCRATCH/net.z"; [ $? -eq 1 ] || return 1
  pdiff "$1" "$2" "$SCRATCH/net.z" | pparse "$SCRATCH/net.z" > "$SCRATCH/net.diff" || return 1
  tr '\000' '\n' < "$SCRATCH/net.z" > "$SCRATCH/net.list" || return 1
  NET_KEY="$1 $2"; NET_GEN=$((NET_GEN + 1))
}
NET_GEN=0 ; NETN_GEN="" ; NETN=0
# <rev> <path> <out>: <rev>'s file at <path> into <out>, empty when there is none;
# 1 for a submodule there (no lines to count), 2 on error.
file_of() {
  local ty
  ty="$(entry_of "$1" "$2")"
  case $? in 1) : > "$3"; return 0 ;; 0) ;; *) return 2 ;; esac
  [ "$ty" = blob ] || return 1
  GIT cat-file blob "$1:$2" > "$3" 2>/dev/null || return 2
}
# <records> <path>: the name <path> had before a rename the pparse records hold
# (nothing when they hold none). name_in: the name a file has in a revision, the
# first of the given names it has (nothing when it has none), 2 on error.
# (Paths reach awk through the environment, never -v, which would decode a backslash
# in a name: "a\nb" became a newline and matched nothing, #399 verify round 14.)
old_of() {
  P="$2" LC_ALL=C awk 'BEGIN { p = ENVIRON["P"] } substr($0, 1, 2) == "N\t" { n = substr($0, 5); next }
    substr($0, 1, 2) == "O\t" && n == p { print substr($0, 5); exit } { n = "" }' "$1"
}
name_in() { # <rev> <name> ...: the first of the names <rev> has (empty names skipped)
  local r="$1" n; shift
  for n in "$@"; do
    [ -n "$n" ] || continue
    entry_of "$r" "$n" > /dev/null
    case $? in 0) printf '%s' "$n"; return 0 ;; 1) ;; *) return 2 ;; esac
  done
}
# A position says which line it is only while the line's text is unique. When a
# commit fails to hold the net change only on lines whose text repeats (in the
# branch's file or the merge-base's), git may have paired the copies one way when it
# built the commit and another way in the diffs above: deleting one of two equal
# lines next to a line main edited reads as the other copy deleted (#399 verify round
# 13). The commit then holds the net change when its own step (its first parent to
# it) changes the number of copies of each such text exactly as the net change does:
# a clean squash applies the branch's hunks to its parent and nothing else. A merge
# commit's step also brings every other commit of the side it merges (a release
# merge, a `git pull`), so the count says nothing there and only positions decide.
# 0 holds, 1 not, 2 error. The texts and their copies in the branch and the
# merge-base are cached per net change and path (rep.<generation>.<path number>).
# <rev> <path> <old name> <records>: keeps only the records whose text at most one
# commit of the whole branch touches (adds or deletes a line of it, or changes how
# many copies there are). A copy one commit added and a later one took away again
# would otherwise count in a step that brought in only the first (an earlier squash of
# the branch); a copy a commit after <rev> added would count for a prefix <rev> in the
# step that brought both; and a commit that moved a line of the text, which leaves the
# number of copies alone, could be dropped unseen. Each of these read as holding the
# net change (#399 round 14, found by bounded.py --landing two and --pairs). <rev>
# only names the branch's file the records are read from.
single_changer() {
  local b n0 n1 rc side r n key
  : > "$SCRATCH/sc.texts"
  key="$({ printf '%s\000%s' "$2" "${3:-}"; } | GIT hash-object --stdin 2>/dev/null)" || return 2
  GIT --literal-pathspecs rev-list --no-merges "$HOLD_MB..$BRANCH_SHA" -- "$2" ${3:+"$3"} > "$SCRATCH/sc.revs" 2>/dev/null || return 2
  while IFS= read -r b; do
    GIT rev-parse -q --verify "$b^1^{commit}" > /dev/null 2>&1 || continue
    # Every text the commit touches in the file, read once per commit and file (the
    # prefix search asks again for each earlier commit's net change, #399 verify
    # round 14): the texts whose copies it changes, and those of the lines it adds or
    # deletes.
    if [ ! -f "$SCRATCH/sc.t.$b.$key" ]; then
      n1="$(name_in "$b" "$2" "$3")" && n0="$(name_in "$b^1" "$2" "$3")" || return 2
      for side in 1 0; do
        [ "$side" = 1 ] && r="$b" n="$n1" || r="$b^1" n="$n0"
        if [ -n "$n" ]; then file_of "$r" "$n" "$SCRATCH/sc.$side"; rc=$?; else rc=1; fi
        [ "$rc" -le 1 ] || return 2
        [ "$rc" -eq 0 ] || : > "$SCRATCH/sc.$side"
      done
      # the commit's own diff of the file (under both names when it moved it)
      { [ -z "$n1" ] || printf '%s\0' "$n1"; [ -z "$n0" ] || [ "$n0" = "$n1" ] || printf '%s\0' "$n0"; } > "$SCRATCH/sc.z"
      pdiff "$b^1" "$b" "$SCRATCH/sc.z" | pparse "$SCRATCH/sc.z" > "$SCRATCH/sc.rec" || return 2
      LC_ALL=C awk -v f1="$SCRATCH/sc.1" -v f0="$SCRATCH/sc.0" -v own="$SCRATCH/sc.rec" 'BEGIN {
          while ((r = getline l < f1) > 0) { N1[++n1] = l; c1[l]++ }
          if (r < 0) exit 2
          while ((r = getline l < f0) > 0) { N0[++n0] = l; c0[l]++ }
          if (r < 0) exit 2
          for (x in c1) if (c1[x] != c0[x] + 0) hit[x] = 1
          for (x in c0) if (c0[x] != c1[x] + 0) hit[x] = 1
          while ((r = getline l < own) > 0) {
            t = substr(l, 1, 1); i = index(substr(l, 3), "\t"); k = substr(l, 3, i - 1) + 0
            if (t == "A" && k >= 1 && k <= n1) hit[N1[k]] = 1
            if (t == "D" && k >= 1 && k <= n0) hit[N0[k]] = 1
          }
          if (r < 0) exit 2
          for (x in hit) print x }' > "$SCRATCH/sc.t.tmp" && mv "$SCRATCH/sc.t.tmp" "$SCRATCH/sc.t.$b.$key" || return 2
    fi
    # the texts of <records> this commit touches
    LC_ALL=C awk -v rec="$4" 'BEGIN {
        while ((r = getline l < rec) > 0) { x = l; for (j = 1; j <= 4; j++) x = substr(x, index(x, "\t") + 1); T[x] = 1 }
        if (r < 0) exit 2 }
      ($0 in T) { print }' "$SCRATCH/sc.t.$b.$key" >> "$SCRATCH/sc.texts" || return 2
  done < "$SCRATCH/sc.revs"
  LC_ALL=C awk -v t="$SCRATCH/sc.texts" 'BEGIN { while ((r = getline l < t) > 0) n[l]++; if (r < 0) exit 2 }
    { x = $0; for (j = 1; j <= 4; j++) x = substr(x, index(x, "\t") + 1); if (n[x] + 0 <= 1) print }' "$4" > "$4.tmp" \
    && mv "$4.tmp" "$4"
}
# <path> <rep file>: 0 when every failing record of <path> is in <rep file>, 1 when one
# is not, 2 on error.
in_rep() {
  P="$1" LC_ALL=C awk -v rep="$2" '
    BEGIN { p = ENVIRON["P"]; while ((r = getline l < rep) > 0) { split(l, f, "\t"); want[f[1] "\t" f[2]] = 1 }; if (r < 0) exit 2 }
    { i = index(substr($0, 3), "\t"); if (substr($0, 3 + i) != p) next
      if (!((substr($0, 1, 1) "\t" substr($0, 3, i - 1)) in want)) exit 1 }' "$SCRATCH/h.fail"
}
holds_by_copies() { # <commit> <rev> (the failing records are in $SCRATCH/h.fail)
  local c="$1" rev="$2" par p i rc old n rf r
  [ "$c" != "$HOLD_MB" ] || return 1
  # Some line of the net change must be in place by position: a squash carries the
  # branch's change, while a commit of main's own that adds the same text elsewhere
  # carries none of it and would count (#399 round 14, bounded.py's plain mode). The
  # net change's line count is kept per net change; this check comes first, as the
  # cheapest of the refusals here.
  if [ "$NETN_GEN" != "$NET_GEN" ]; then
    NETN="$(LC_ALL=C awk '/^[AD]\t/ { n++ } END { print n + 0 }' "$SCRATCH/net.diff")" || return 2
    NETN_GEN="$NET_GEN"
  fi
  [ "$NETN" -gt "$(wc -l < "$SCRATCH/h.fail" | tr -d ' ')" ] || return 1
  if [ -f "$SCRATCH/repnone.$NET_GEN" ]; then
    LC_ALL=C awk -v none="$SCRATCH/repnone.$NET_GEN" 'BEGIN { while ((r = getline l < none) > 0) N[l] = 1; if (r < 0) exit 2 }
      { i = index(substr($0, 3), "\t"); if (substr($0, 3 + i) in N) exit 1 }' "$SCRATCH/h.fail"
    case $? in 0) ;; 1) return 1 ;; *) return 2 ;; esac
  fi
  par="$(GIT rev-parse -q --verify "$c^1^{commit}" 2>/dev/null)" || return 1
  ! GIT rev-parse -q --verify "$c^2^{commit}" > /dev/null 2>&1 || return 1
  LC_ALL=C awk '{ i = index(substr($0, 3), "\t"); p = substr($0, 3 + i); if (!(p in s)) { s[p] = 1; print p } }' \
    "$SCRATCH/h.fail" > "$SCRATCH/h.fpaths" || return 2
  # First every failing line must repeat (cached reads of the branch and the
  # merge-base only), then the commit's own step is counted.
  LC_ALL=C awk -v list="$SCRATCH/net.list" 'BEGIN { while ((r = getline l < list) > 0) n[l] = ++k; if (r < 0) exit 2 }
    ($0 in n) { print n[$0]; next } { exit 2 }' "$SCRATCH/h.fpaths" > "$SCRATCH/h.fidx" || return 2
  while IFS= read -r p && IFS= read -r i <&3; do
    if [ ! -f "$SCRATCH/rep.$NET_GEN.$i" ]; then
      # each net record of the path whose text occurs at least twice in the branch's
      # file or the merge-base's: "<kind><TAB><line><TAB><copies there><TAB><copies
      # in the merge-base><TAB><text>"
      # (a file the branch renamed is read at the merge-base under its old name)
      old="$(old_of "$SCRATCH/net.diff" "$p")" && n="$(name_in "$HOLD_MB" "$p" "$old")" || return 2
      rc=1
      if [ ! -f "$SCRATCH/rep.$NET_GEN.$i.raw" ]; then
        file_of "$rev" "$p" "$SCRATCH/rf.rev"; rc=$?
        [ "$rc" -le 1 ] || return 2
        if [ "$rc" -eq 0 ]; then
          if [ -n "$n" ]; then file_of "$HOLD_MB" "$n" "$SCRATCH/rf.mb"; rc=$?; else : > "$SCRATCH/rf.mb"; fi
        fi
        [ "$rc" -le 1 ] || return 2
      fi
      if [ "$rc" -eq 0 ]; then
        P="$p" LC_ALL=C awk -F '\t' -v fr="$SCRATCH/rf.rev" -v fm="$SCRATCH/rf.mb" '
          BEGIN { p = ENVIRON["P"]
            while ((r = getline l < fr) > 0) { R[++nr] = l; cr[l]++ }
            if (r < 0) exit 2
            while ((r = getline l < fm) > 0) { M[++nm] = l; cm[l]++ }
            if (r < 0) exit 2
          }
          { i = index(substr($0, 3), "\t"); if (substr($0, 3 + i) != p) next
            k = substr($0, 3, i - 1) + 0; t = substr($0, 1, 1)
            if (t == "A" && k >= 1 && k <= nr) x = R[k]
            else if (t == "D" && k >= 1 && k <= nm) x = M[k]
            else next
            if (cr[x] + 0 >= 2 || cm[x] + 0 >= 2) print t "\t" k "\t" (cr[x] + 0) "\t" (cm[x] + 0) "\t" x }' \
          "$SCRATCH/net.diff" > "$SCRATCH/rep.$NET_GEN.$i.raw" || return 2
      fi
      # A failing line whose text does not repeat refuses the commit before the
      # branch's commits are read: single_changer only ever removes records (#399
      # verify round 14 measured it re-reading the whole branch for such lines).
      [ -f "$SCRATCH/rep.$NET_GEN.$i.raw" ] || : > "$SCRATCH/rep.$NET_GEN.$i.raw" || return 2
      in_rep "$p" "$SCRATCH/rep.$NET_GEN.$i.raw"; rc=$?; [ "$rc" -eq 0 ] || return "$rc"
      cp "$SCRATCH/rep.$NET_GEN.$i.raw" "$SCRATCH/rep.$NET_GEN.$i.tmp" || return 2
      if [ -s "$SCRATCH/rep.$NET_GEN.$i.tmp" ]; then
        single_changer "$rev" "$p" "$old" "$SCRATCH/rep.$NET_GEN.$i.tmp" || return 2
      fi
      mv "$SCRATCH/rep.$NET_GEN.$i.tmp" "$SCRATCH/rep.$NET_GEN.$i" || return 2
      # a path none of whose records repeat refuses every failing line at once next time
      [ -s "$SCRATCH/rep.$NET_GEN.$i" ] || printf '%s\n' "$p" >> "$SCRATCH/repnone.$NET_GEN"
    fi
    in_rep "$p" "$SCRATCH/rep.$NET_GEN.$i"; rc=$?; [ "$rc" -eq 0 ] || return "$rc"
  done < "$SCRATCH/h.fpaths" 3< "$SCRATCH/h.fidx"
  while IFS= read -r p && IFS= read -r i <&3; do
    old="$(old_of "$SCRATCH/net.diff" "$p")" || return 2
    for rf in c par; do
      [ "$rf" = c ] && r="$c" || r="$par"
      n="$(name_in "$r" "$p" "$old")" || return 2
      if [ -n "$n" ]; then file_of "$r" "$n" "$SCRATCH/rf.$rf"; rc=$?; [ "$rc" -eq 0 ] || return "$rc"
      else : > "$SCRATCH/rf.$rf"; fi
    done
    P="$p" LC_ALL=C awk -v rep="$SCRATCH/rep.$NET_GEN.$i" -v fc="$SCRATCH/rf.c" -v fp="$SCRATCH/rf.par" '
      BEGIN { p = ENVIRON["P"]
        while ((r = getline l < rep) > 0) {
          n = split(l, f, "\t"); key = f[1] "\t" f[2]
          x = l; for (j = 1; j <= 4; j++) x = substr(x, index(x, "\t") + 1)
          want[key] = f[3] - f[4]; txt[key] = x
        }
        if (r < 0) exit 2
        while ((r = getline l < fc) > 0) cc[l]++
        if (r < 0) exit 2
        while ((r = getline l < fp) > 0) cp[l]++
        if (r < 0) exit 2
      }
      { i = index(substr($0, 3), "\t"); if (substr($0, 3 + i) != p) next
        key = substr($0, 1, 1) "\t" substr($0, 3, i - 1)
        if (!(key in want)) exit 1                         # a unique line out of place
        if (want[key] == 0) exit 1                         # a move: no count to compare
        if (cc[txt[key]] - cp[txt[key]] != want[key]) exit 1 }' "$SCRATCH/h.fail"
    case $? in 0) ;; 1) return 1 ;; *) return 2 ;; esac
  done < "$SCRATCH/h.fpaths" 3< "$SCRATCH/h.fidx"
  # The line in place must be one the commit's own step brought: a line of the net
  # change already in place in its parent (an earlier part of the branch) says nothing
  # about this commit, and a commit of main's own that adds the same text elsewhere
  # was taken for the landing commit (#399 verify round 14).
  { pdiff "$rev" "$par" "$SCRATCH/net.z" | pparse "$SCRATCH/net.z" > "$SCRATCH/h.prev" \
    && pdiff "$HOLD_MB" "$par" "$SCRATCH/net.z" | pparse "$SCRATCH/net.z" > "$SCRATCH/h.pmb"; } || return 2
  LC_ALL=C awk -v net="$SCRATCH/net.diff" -v hrev="$SCRATCH/h.prev" -v hmb="$SCRATCH/h.pmb" -v fail="$SCRATCH/h.fail" '
    function key(l) { return substr(l, 3) }
    BEGIN {
      while ((r = getline l < hrev) > 0) if (substr(l, 1, 1) == "C") moved[key(l)] = 1
      if (r < 0) exit 2
      while ((r = getline l < hmb) > 0) if (substr(l, 1, 1) == "C") gone[key(l)] = 1
      if (r < 0) exit 2
      while ((r = getline l < fail) > 0) failc[l] = 1
      if (r < 0) exit 2
      while ((r = getline l < net) > 0) {
        t = substr(l, 1, 1)
        if (t != "A" && t != "D") continue
        if (l in failc) continue                           # not in place in the commit
        if ((t == "A" && (key(l) in moved)) || (t == "D" && !(key(l) in gone))) exit 0   # not in place in its parent
      }
      if (r < 0) exit 2
      exit 1
    }'
}
# A commit that holds the net change has a file exactly where <rev> has one among the
# paths the net change touches (a file the branch moved is at its new name only, an empty
# file the branch added is there, a file it deleted is gone, and a directory is not a
# file): diff-tree reports none of them added or deleted between <rev> and the commit.
# One plumbing call per commit, whatever the number of paths.
same_paths() { # <rev> <commit> -> 0 the same, 1 not, 2 error
  local p n
  local -a ps
  ps=()
  n="$(wc -c < "$SCRATCH/net.z" | tr -d ' ')" || return 2
  if [ "$n" -le "$PATHS_MAX" ]; then
    while IFS= read -r -d '' p; do ps+=("$p"); done < "$SCRATCH/net.z" || return 2
  fi
  GIT --literal-pathspecs diff-tree -r -z --no-renames --name-status --ignore-submodules=none "$1" "$2" \
    -- ${ps[@]+"${ps[@]}"} > "$SCRATCH/same.z" 2>/dev/null || return 2
  # "<status> NUL <path> NUL" pairs; an LF in a name elsewhere becomes \001, so it can
  # match no listed path
  tr '\n\000' '\001\n' < "$SCRATCH/same.z" | LC_ALL=C awk -v list="$SCRATCH/net.list" '
    BEGIN { while ((r = getline l < list) > 0) want[l] = 1; if (r < 0) exit 2 }
    NR % 2 == 1 { st = $0; next }
    (st == "A" || st == "D") && ($0 in want) { exit 1 }'
}
holds() { # <commit> <rev> -> 0 holds, 1 does not, 2 error (LAND_NOTE set); HOLD_MB is <rev>'s merge-base
  local c="$1" rev="$2" p want
  if [ "$BUDGET" -le 0 ]; then
    LAND_NOTE="the budget of 200 checks ran out before a landing commit was found"; return 2
  fi
  BUDGET=$((BUDGET - 1))
  net_of "$HOLD_MB" "$rev" || { LAND_NOTE="cannot read the net change of $(short "$rev")"; return 2; }
  { pdiff "$rev" "$c" "$SCRATCH/net.z" | pparse "$SCRATCH/net.z" > "$SCRATCH/h.rev" \
    && pdiff "$HOLD_MB" "$c" "$SCRATCH/net.z" | pparse "$SCRATCH/net.z" > "$SCRATCH/h.mb"; } \
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
        if ((t == "A" && (key(l) in moved)) ||         # an added line is not in place
            (t == "D" && !(key(l) in gone))) {         # a deleted line is still in place
          print l; bad = 1
        }
      }
      if (r < 0) exit 2
      exit bad
    }' > "$SCRATCH/h.fail"
  case $? in
    0) ;;
    1) holds_by_copies "$c" "$rev"
       case $? in 0) ;; 1) return 1 ;; *) LAND_NOTE="cannot compare $(short "$c") with the branch"; return 2 ;; esac ;;
    *) LAND_NOTE="cannot compare $(short "$c") with the branch"; return 2 ;;
  esac
  same_paths "$rev" "$c"
  case $? in 0) ;; 1) return 1 ;; *) LAND_NOTE="cannot compare the files of $(short "$c") with the branch"; return 2 ;; esac
  return 0
}
find_landing() { # <rev>
  local rev="$1" mb c n=0 rc fail="cannot list the baseline's commits"
  LAND="" ; LAND_NOTE="" ; LAND_NONE="" ; LAND_AT_MB=""
  mb="$(GIT merge-base "$BASELINE_SHA" "$rev" 2>/dev/null)" \
    || { LAND_NOTE="no merge-base between branch and baseline"; return 1; }
  HOLD_MB="$mb"
  n=1; holds "$mb" "$rev"; rc=$?
  case "$rc" in 0) LAND="$mb"; LAND_MB="$mb"; LAND_AT_MB=1; return 0 ;; 2) return 1 ;; esac
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
    case "$rc" in 0) LAND="$c"; LAND_MB="$mb"; return 0 ;; 2) return 1 ;; esac
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
LANDING="" ; LANDING_MB="" ; PREFIX_TIP="" ; LANDING_NOTE="" ; LANDING_AT_MB="" ; PREFIX_NOTE=""
prefix_search() { # -> 0 a prefix landed after the merge-base (LANDING, PREFIX_TIP set), 1 none, 2 error, 3 none among the tries
  local mb b total
  mb="$(GIT merge-base "$BASELINE_SHA" "$BRANCH_SHA" 2>/dev/null)" || { PREFIX_NOTE="no merge-base between branch and baseline"; return 2; }
  GIT rev-list --first-parent "$mb..$BRANCH_SHA" > "$SCRATCH/prefixes" 2>/dev/null \
    || { PREFIX_NOTE="cannot list the branch's commits"; return 2; }
  total=$(( $(wc -l < "$SCRATCH/prefixes") - 1 ))
  for b in $(sed 1d "$SCRATCH/prefixes" | head -n "$PREFIX_TRIES"); do
    if find_landing "$b"; then
      # A prefix that undid itself holds its (empty) net change at the merge-base;
      # nothing of the branch landed there, so keep looking.
      [ -z "$LAND_AT_MB" ] || continue
      LANDING="$LAND"; LANDING_MB="$LAND_MB"; PREFIX_TIP="$b"; return 0
    fi
    [ -n "$LAND_NONE" ] || { PREFIX_NOTE="$LAND_NOTE"; return 2; }
  done
  [ "$total" -gt "$PREFIX_TRIES" ] || return 1
  PREFIX_NOTE="no prefix among the branch's newest $PREFIX_TRIES earlier commits landed"
  return 3
}
if find_landing "$BRANCH_SHA"; then
  LANDING="$LAND"; LANDING_MB="$LAND_MB"; LANDING_AT_MB="$LAND_AT_MB"
  # A branch with no net change "lands" at the merge-base whatever reached main.
  # When a prefix of it landed later (a squash of its first commits, before the
  # commits that undid them), that prefix is where it landed, and the commits
  # after it are checked at the tip. Without this a dropped restore was missed
  # (3.5.0 caught it; #399 verify round 10).
  # When the search ran out of tries, an older prefix may have landed: the tip is used.
  if [ -n "$LANDING_AT_MB" ]; then
    prefix_search; rc=$?
    case "$rc" in
      0) LANDING_AT_MB="" ;;
      1) ;;
      *) LANDING_NOTE="$PREFIX_NOTE"; LANDING=""; LANDING_AT_MB="" ;;
    esac
  fi
else
  LANDING_NOTE="$LAND_NOTE"
  if [ -n "$LAND_NONE" ]; then
    prefix_search; rc=$?
    case "$rc" in 0) LANDING_NOTE="" ;; 1) ;; *) LANDING_NOTE="$PREFIX_NOTE" ;; esac
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

# ── Content-verify each candidate ──
# At LANDING (for a candidate up to PREFIX_TIP when only a prefix landed), in place,
# with the two-way diffs above; else at the tip, by line presence, reading trees and
# blobs with plumbing only (diff-tree, ls-tree, cat-file), which no diff setting
# reaches: --text keeps a file git treats as binary (a NUL byte, a `binary` or
# `-diff` attribute) from collapsing into "Binary files differ", and
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
    # At the tip its lines are looked for under the names its files have in the head
    # too (head_names above).
    1) SIDE_OF="$SIDE_OF tip"; NEED_TIP=1
       head_names "$sha" && awk -v k="$k" '{ print k "\t" $0 }' "$SCRATCH/rn.$sha" >> "$SCRATCH/pairs" \
         || skip "cannot index the names $(short "$sha")'s files have in the branch head" ;;
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
# The tip is compared by line presence (orphan_p), so the head and the tip are listed
# only when a commit is checked there; the landing commit is compared in place
# (land_orphan_p).
SIDES="head tip"
if [ -n "$NEED_TIP" ] && [ -f "$SCRATCH/paths" ]; then
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
  # Renames detected, as in the landing step: a moved file is otherwise all new lines,
  # and every line main edited in it, even before the squash, would list the commit
  # (#399 verify round 13). A rename that never landed is still seen: its old path is
  # in the commit's deleted paths and its new one in its added paths (below). The
  # head and the tip are read under the names the commit's files have in the head as
  # well (head_names): with renames detected, the commit that later moved a file no
  # longer carries the lines an earlier commit added to it (#399 verify round 14).
  GIT diff-tree --root --no-commit-id -r -p --text --no-ext-diff --no-textconv --no-color -M -l1000 \
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
{ printf 'landing %s prefix %s\n' "${LANDING:--}" "${PREFIX_TIP:--}"
  set -- $SIDE_OF
  for sha in $CANDIDATES; do printf 'side %s %s\n' "$sha" "$1"; shift; done
} | trace_out

# At a landing commit L each commit c is checked in its own place, the way SPEC.md
# defines an orphan. Over the paths c touched: a line c added (not blank) is an effect
# the head still shows when diff(c→head) leaves it unchanged, and it is missing when
# diff(c→L) changes it; a line c deleted is an effect the head shows when
# diff(c^→head) changes it, and it is still there when diff(c^→L) leaves it unchanged.
# A path c added or deleted with no line to compare (an empty file) is missing when
# the head has it and L does not, or the other way round. Main's own edits elsewhere
# in L, even on the next line, and main's own copy of the same text elsewhere, do not
# count; a mode change, a blank line and a final newline are not effects.
# A position says which line it is only while the lines around it do. When the text of
# a line found missing above occurs more than once, git may have paired the copies one
# way when it built the landing commit and another way in the diffs above: main's edit
# of one copy then reads as the commit's own line changed (#399 verify round 12); and
# next to a block of repeated lines even a unique line can be paired with another
# (round 14). So a finding stands only if the copies say so too: the landing commit,
# less the copies main itself added or removed before it (L^ against the merge-base;
# none of them may come from another commit of the branch), has fewer copies of an added line than what
# landed there (the landed prefix's last commit, or the head), or more copies of a
# deleted one. Not the head when only a prefix landed: the later commits never reached
# L, and a copy one of them added would cancel a copy the checked commit failed to
# delete. A unique line the commit moved is judged by position alone: its step leaves
# the number of copies as it was, so the count cannot see the move.
count_of_line() { # <rev> <path> <text file> -> copies of that line in <rev>:<path>, 0 when absent, "x" for a submodule
  local ty
  ty="$(entry_of "$1" "$2")"
  case $? in 1) echo 0; return 0 ;; 0) ;; *) return 2 ;; esac
  [ "$ty" = blob ] || { echo x; return 0; }
  GIT cat-file blob "$1:$2" > "$SCRATCH/cnt.blob" 2>/dev/null || return 2
  LC_ALL=C awk -v t="$3" 'BEGIN { if ((getline x < t) < 0) exit 2 } $0 == x { n++ } END { print n + 0 }' "$SCRATCH/cnt.blob"
}
# <rev> <text file> <name> ...: copies of the line in <rev>'s file at the first of the
# names it has, 0 when it has none, "x" for a submodule.
count_named() {
  local r="$1" t="$2" n; shift 2
  n="$(name_in "$r" "$@")" || return 2
  [ -n "$n" ] || { echo 0; return 0; }
  count_of_line "$r" "$n" "$t"
}
# $SCRATCH/net.ren: pparse's rename records (N, O) for the branch's whole change since
# the merge-base, so a file can be found under the name it had there.
net_renames() {
  [ -f "$SCRATCH/net.ren" ] && return 0
  GIT diff-tree -r -z --name-only --no-renames --ignore-submodules=none "$LANDING_MB" "$BRANCH_SHA" \
    > "$SCRATCH/ren.z" 2>/dev/null || return 2
  has_lf "$SCRATCH/ren.z"; case $? in 0) : > "$SCRATCH/net.ren"; return 0 ;; 1) ;; *) return 2 ;; esac
  pdiff "$LANDING_MB" "$BRANCH_SHA" "$SCRATCH/ren.z" | pparse "$SCRATCH/ren.z" \
    | LC_ALL=C awk 'substr($0, 1, 2) == "N\t" || substr($0, 1, 2) == "O\t"' > "$SCRATCH/net.ren.tmp" \
    && mv "$SCRATCH/net.ren.tmp" "$SCRATCH/net.ren" || { rm -f "$SCRATCH/net.ren.tmp"; return 2; }
}
# <commit> <name> ...: 0 when the commit's own change of the file (under the first of
# the names it has) is all in place in L^1: each line it added unchanged there, each
# line it deleted gone. 1 when not, or when the commit has no line in that file to
# check; 2 on error.
in_l1() {
  local b="$1" par lp n
  shift
  par="$(GIT rev-parse -q --verify "$b^1^{commit}" 2>/dev/null)" || return 1
  lp="$(GIT rev-parse -q --verify "$LANDING^1^{commit}" 2>/dev/null)" || return 2
  : > "$SCRATCH/i1.z" || return 2
  for n in "$@"; do [ -z "$n" ] || printf '%s\000' "$n" >> "$SCRATCH/i1.z"; done || return 2
  { pdiff "$par" "$b" "$SCRATCH/i1.z" | pparse "$SCRATCH/i1.z" > "$SCRATCH/i1.own" \
    && pdiff "$b" "$lp" "$SCRATCH/i1.z" | pparse "$SCRATCH/i1.z" > "$SCRATCH/i1.bc" \
    && pdiff "$par" "$lp" "$SCRATCH/i1.z" | pparse "$SCRATCH/i1.z" > "$SCRATCH/i1.pc"; } || return 2
  # (exit inside a rule still runs END, whose own exit would replace the status: the
  # outcome goes through a variable)
  LC_ALL=C awk -v bc="$SCRATCH/i1.bc" -v pc="$SCRATCH/i1.pc" '
    function load(f, set,    l, r) {
      while ((r = getline l < f) > 0) if (substr(l, 1, 1) == "C") set[substr(l, 3)] = 1
      if (r < 0) { rc = 2; exit }
    }
    BEGIN { rc = 0; load(bc, BC); load(pc, PC) }
    /^A\t/ { n++; if (substr($0, 3) in BC) { rc = 1; exit } }     # an added line L^1 changes
    /^D\t/ { n++; if (!(substr($0, 3) in PC)) { rc = 1; exit } }  # a deleted line still in L^1
    END { if (!rc && !n) rc = 1; exit rc }' "$SCRATCH/i1.own"
}
# 0 when another commit of the branch that changes how many copies of the line its
# file has reached L^1 (in_l1: its own change all in place there), so L^1's copies are
# not main's alone; 1 when none did; 2 on error. Only such a commit can make main's
# count wrong: one that never reached L^1 changes nothing there. It covers every way a
# part of the branch reaches main before L: a squash of its first commits (round 13
# read its copy as main's and cleared the commit that undid it), a pick, two later
# commits squashed before an earlier one, a squash older than any search would try.
# Before round 15 any other commit that changed the count kept the finding, and any
# earlier part of the branch in L^1 did, whatever file it touched: a function copied
# twice, or a hotfix picked to main early, listed a clean squash (#399 verify round
# 14). Subtracting the copies of the newest earlier prefix L^1 holds was tried too, and
# failed where L^1 holds that prefix only because a deletion counts as landed once its
# line is replaced: the prefix's state was not what L^1 had (round 15, bounded.py).
other_copies() { # <commit> <text file> <name> ...
  local c="$1" t="$2" b n1 n2 n
  local -a ns
  shift 2; ns=()
  for n in "$@"; do [ -z "$n" ] || ns+=("$n"); done
  GIT --literal-pathspecs rev-list --no-merges "$LANDING_MB..$BRANCH_SHA" -- "${ns[@]}" > "$SCRATCH/cnt.revs" 2>/dev/null || return 2
  while IFS= read -r b; do
    [ "$b" != "$c" ] || continue
    GIT rev-parse -q --verify "$b^1^{commit}" > /dev/null 2>&1 || continue
    n1="$(count_named "$b^1" "$t" "${ns[@]}")" || return 2
    n2="$(count_named "$b" "$t" "${ns[@]}")" || return 2
    [ "$n1" != "$n2" ] || continue
    in_l1 "$b" "${ns[@]}"
    case $? in 0) return 0 ;; 1) ;; *) return 2 ;; esac
  done < "$SCRATCH/cnt.revs"
  return 1
}
confirm() { # <commit> <parent> <"A|D<TAB>line<TAB>path"> -> 0 missing, 1 landed after all, 2 error
  local c="$1" par="$2" t line path src sname old nold ty n_src n_oth n_head n_ref n_land n_prev n_mb
  local T="$SCRATCH/cnt.text"
  t="${3%%$'\t'*}"; line="${3#*$'\t'}"; path="${line#*$'\t'}"; line="${line%%$'\t'*}"
  # Only lines of a file the commit edited are counted, each revision's file read
  # under the name it has there (the records carry the commit's new name; the parent
  # has the old one if the commit renamed the file, and the merge-base the one before
  # the branch renamed it). Anything else keeps the finding: a submodule pointer (its
  # record is "Subproject commit <oid>", not a line of a file), a file the commit
  # added or deleted, a root commit (#399 verify round 13).
  [ "$par" != "$EMPTY_TREE" ] || return 0
  old="$(old_of "$SCRATCH/l.own" "$path")" && net_renames && nold="$(old_of "$SCRATCH/net.ren" "$path")" || return 2
  ty="$(entry_of "$par" "${old:-$path}")"
  case $? in 0) ;; 1) return 0 ;; *) return 2 ;; esac
  [ "$ty" = blob ] || return 0
  ty="$(entry_of "$c" "$path")"
  case $? in 0) ;; 1) return 0 ;; *) return 2 ;; esac
  [ "$ty" = blob ] || return 0
  if [ "$t" = A ]; then src="$c"; sname="$path"; else src="$par"; sname="${old:-$path}"; fi
  GIT cat-file blob "$src:$sname" 2>/dev/null | LC_ALL=C awk -v k="$line" 'NR == k { print; f = 1 } END { exit !f }' \
    > "$T" || return 2
  n_src="$(count_of_line "$src" "$sname" "$T")" || return 2
  n_head="$(count_named "$BRANCH_SHA" "$T" "$path" "$old" "$nold")" || return 2
  n_ref="$(count_named "${PREFIX_TIP:-$BRANCH_SHA}" "$T" "$path" "$old" "$nold")" || return 2
  n_land="$(count_named "$LANDING" "$T" "$path" "$old" "$nold")" || return 2
  case "$n_src$n_head$n_ref$n_land" in *x*) return 0 ;; esac
  # A line whose text is unique and which the commit moved (its own step leaves the
  # number of copies alone) is judged by its position: a count cannot see a move.
  # Every other finding is checked against the copies too. A unique line is no
  # exception: next to a block of repeated lines the two diffs can pair it with a
  # different line, and a clean squash was listed (#399 verify round 14). But a unique
  # line has one copy, so main's own edit cannot have been put on the branch's copy:
  # it must also be in L as often as in what landed, before main's own copies are
  # counted (round 15: main replaced the line before landing, and a restore of it that
  # never landed read as landed).
  if [ "$n_src" -le 1 ] && [ "$n_head" -le 1 ] && [ "$n_ref" -le 1 ] && [ "$n_land" -le 1 ]; then
    if [ "$t" = A ]; then
      n_oth="$(count_of_line "$par" "${old:-$path}" "$T")" || return 2
      [ "$n_land" -ge "$n_ref" ] || return 0
    else
      n_oth="$(count_of_line "$c" "$path" "$T")" || return 2
      [ "$n_land" -le "$n_ref" ] || return 0
    fi
    [ "$n_oth" != "$n_src" ] || return 0
  fi
  # The copies main itself added or removed before the landing commit (L^1 against the
  # merge-base)
  n_prev=0; n_mb=0
  if [ -n "$LANDING_MB" ] && [ "$LANDING" != "$LANDING_MB" ]; then
    n_prev="$(count_named "$LANDING^1" "$T" "$path" "$old" "$nold")" || return 2
    n_mb="$(count_named "$LANDING_MB" "$T" "$path" "$old" "$nold")" || return 2
    case "$n_prev$n_mb" in *x*) return 0 ;; esac
  fi
  if [ "$t" = A ]; then
    [ $((n_land - n_prev + n_mb)) -lt "$n_ref" ] && return 0
  else
    [ $((n_land - n_prev + n_mb)) -gt "$n_ref" ] && return 0
  fi
  # The copies say landed. That holds only if no other commit of the branch that changes
  # them reached L^1.
  [ -n "$LANDING_MB" ] && [ "$LANDING" != "$LANDING_MB" ] || return 1
  other_copies "$c" "$T" "$path" "$old" "$nold"
  case $? in 0) return 0 ;; 1) return 1 ;; *) return 2 ;; esac
}
land_orphan_p() { # <commit-sha> <candidate number> -> 10 orphan, 11 landed, other: error
  local c="$1" par f
  [ -s "$SCRATCH/c.$2" ] || return 11
  par="$(GIT rev-parse -q --verify "$c^1^{commit}" 2>/dev/null)" || par="$EMPTY_TREE"
  # the candidate's paths, NUL-separated (none has LF: those were refused above)
  LC_ALL=C awk -v paths="$SCRATCH/paths" 'BEGIN { while ((getline l < paths) > 0) P[n++] = l }
    { printf "%s%c", P[$0], 0 }' "$SCRATCH/c.$2" > "$SCRATCH/cp.z" || return 2
  { pdiff "$par" "$c" "$SCRATCH/cp.z" | pparse "$SCRATCH/cp.z" > "$SCRATCH/l.own" \
    && pdiff "$c" "$BRANCH_SHA" "$SCRATCH/cp.z" | pparse "$SCRATCH/cp.z" > "$SCRATCH/l.hc" \
    && pdiff "$c" "$LANDING" "$SCRATCH/cp.z" | pparse "$SCRATCH/cp.z" > "$SCRATCH/l.lc" \
    && pdiff "$par" "$BRANCH_SHA" "$SCRATCH/cp.z" | pparse "$SCRATCH/cp.z" > "$SCRATCH/l.hp" \
    && pdiff "$par" "$LANDING" "$SCRATCH/cp.z" | pparse "$SCRATCH/cp.z" > "$SCRATCH/l.lp"; } || return 2
  LC_ALL=C awk -v d="$SCRATCH" '
    function load(f, set,    l, r) {
      while ((r = getline l < f) > 0) if (substr(l, 1, 1) == "C") set[substr(l, 3)] = 1
      if (r < 0) exit 2
    }
    BEGIN {
      load(d "/l.hc", hc); load(d "/l.lc", lc); load(d "/l.hp", hp); load(d "/l.lp", lp)
      while ((r = getline l < (d "/l.own")) > 0) {
        t = substr(l, 1, 1); k = substr(l, 3)
        if (t == "A" && !(k in hc) && (k in lc)) print l    # added, still in the head, not in L
        if (t == "D" && (k in hp) && !(k in lp)) print l    # deleted, gone from the head, still in L
      }
      if (r < 0) exit 2
    }' > "$SCRATCH/l.flag" || return 2
  while IFS= read -r p; do
    confirm "$c" "$par" "$p"; case $? in 0) return 10 ;; 1) ;; *) return 2 ;; esac
  done < "$SCRATCH/l.flag" || return 2
  # Paths the candidate added or deleted whole with no line to compare (an empty file,
  # or a file a pure move took away or brought in): missing when it added one the head
  # has and L does not, or deleted one the head lacks and L still has. The two trees
  # are listed once for all candidates: a commit that moves thousands of files has
  # that many such paths (#399 verify round 13).
  for f in A D; do
    LC_ALL=C awk -v own="$SCRATCH/l.own" 'BEGIN { while ((r = getline l < own) > 0) if (l ~ /^[AD]\t/) { i = index(substr(l, 3), "\t"); seen[substr(l, 3 + i)] = 1 }; if (r < 0) exit 2 }
      !($0 in seen) { print }' "$SCRATCH/$f.$2" > "$SCRATCH/l.bare.$f" || return 2
  done
  [ -s "$SCRATCH/l.bare.A" ] || [ -s "$SCRATCH/l.bare.D" ] || return 11
  listing "$BRANCH_SHA" "$SCRATCH/ls.head" && listing "$LANDING" "$SCRATCH/ls.land" || return 2
  LC_ALL=C awk -v h="$SCRATCH/ls.head" -v l="$SCRATCH/ls.land" -v a="$SCRATCH/l.bare.A" -v dl="$SCRATCH/l.bare.D" '
    function load(f, set,    r, p) { while ((r = getline p < f) > 0) set[p] = 1; if (r < 0) exit 2; close(f) }
    BEGIN {
      load(h, H); load(l, L)
      while ((r = getline p < a) > 0) if ((p in H) && !(p in L)) exit 10
      if (r < 0) exit 2
      while ((r = getline p < dl) > 0) if (!(p in H) && (p in L)) exit 10
      if (r < 0) exit 2
      exit 11
    }'
}
# <rev> <out>: every path in <rev> that holds a file or a submodule, one per line (an
# LF inside a name becomes \001, as in the candidates' path lists, which have none);
# listed once per revision.
listing() {
  [ -f "$2" ] && return 0
  GIT ls-tree -r -z --full-tree "$1" 2>/dev/null | tr '\n\000' '\001\n' \
    | LC_ALL=C awk '{ i = index($0, "\t"); split(substr($0, 1, i - 1), m, " ")
                      if (m[2] == "blob" || m[2] == "commit") print substr($0, i + 1) }' > "$2.tmp" \
    && mv "$2.tmp" "$2" || { rm -f "$2.tmp"; return 2; }
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
