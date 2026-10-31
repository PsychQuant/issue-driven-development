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
#       commit touching a path with a newline in its name, a file a checked commit
#       touched that a later commit deletes where git skipped its rename detection
#       (more than 1000 files added and deleted: whether the file moved cannot be
#       told), a temp dir whose path has a backslash or a newline, a partial clone
#       with git older than 2.45); one
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
#      the net change touches. Two-way diffs, each file compared with itself (no
#      merge, so main's own edits elsewhere, even on the next line, do not matter,
#      nor does main's edit of a file the branch moved). Where L fails only on lines whose
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
#      is judged by its position alone. Every file is followed across moves commit by
#      commit, as `git log --follow` does (git's rename detection inside each commit),
#      and known by its name in the branch head; every comparison holds each file under
#      that name, so a file moved twice, moved and then mostly rewritten, or moved with
#      a new file put at its old name is still one file, in every revision. Copies are
#      counted only in a file the commit edited (each revision's file under the name
#      it has there), never for a submodule pointer. What L^1 gained or lost since the merge-base is main's,
#      unless another commit of the branch that changes the copies reached L^1 (its
#      own change all in place there): the finding then stands. At the tip, where main's own edits are
#      unknown, only line presence is compared, each file read under its name there.
#      Squash → the effects are there → not an orphan. Partial merge
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
#   - a move git does not see inside one commit (a file moved and rewritten by more
#     than half in the same commit), unless the merge-base and the head pair the two
#     names: the file reads as deleted and another added;
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
# fetched now: git >= 2.45 reports it unreadable (exit 4); with older git, which
# cannot be told not to fetch, the check stops before reading anything (exit 4).
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
# No pager, no fsmonitor, no hooks: the helper only reads, and those are the user
# programs a plain git call would otherwise start (writing the scratch index of the
# filtered trees below runs post-index-change, #399 verify round 15). core.hooksPath
# covers the hooks directory; a hook defined in the configuration
# (hook.<name>.event, git 2.54 and later) runs even so, and only its event's switch
# turns it off (round 16). Older git ignores the unknown key. No precomposeUnicode (on by default on macOS):
# it turns every path on the command line into NFC, and a path the tree stores in NFD
# (a name from Linux or an older git) then matches nothing, so every diff limited to
# the branch's paths came back empty and a branch that never landed read as landed
# at the merge-base (#399 verify round 13). The paths given here come from git's own
# listings, byte for byte.
GIT() { git --no-pager -C "$REPO" -c core.fsmonitor=false -c core.precomposeUnicode=false -c core.hooksPath=/dev/null \
  -c hook.post-index-change.enabled=false "$@"; }

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

# In a partial clone, git before 2.45 has no way to refuse fetching a blob it never
# fetched (GIT_NO_LAZY_FETCH above is 2.45's): the check would run the user's
# transport and write into the repository (#399 verify round 16).
if [ -n "$(GIT config --get extensions.partialClone 2>/dev/null)" ]; then
  GIT_V="$(git version 2>/dev/null | LC_ALL=C awk '{ split($3, v, "."); printf "%d %d", v[1], v[2] }')" \
    || skip "cannot read git's version"
  set -- $GIT_V
  if [ "${1:-0}" -lt 2 ] || { [ "${1:-0}" -eq 2 ] && [ "${2:-0}" -lt 45 ]; }; then
    skip "this is a partial clone, and git older than 2.45 would fetch the blobs it never fetched (use git 2.45 or newer, or check by hand)"
  fi
fi

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

SCRATCH0="$(mktemp -d)" || skip "cannot create a temp dir"
trap 'rm -rf "$SCRATCH0"' EXIT
# Absolute: git runs with -C "$REPO" and would read a relative path from there (a
# relative TMPDIR), while the shell reads it from the caller's directory. No CDPATH,
# which would make cd print the directory and add a second line (#399 verify round
# 15). Scratch paths reach awk through -v, which decodes a backslash: a temp dir whose
# path has one is refused rather than read wrong.
SCRATCH="$(CDPATH= cd -P -- "$SCRATCH0" && pwd -P)" || skip "cannot resolve the temp dir"
case "$SCRATCH" in *\\*|*$'\n'*) skip "the temp dir's path has a backslash or a newline (set TMPDIR to another directory)" ;; esac
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

# Paths go on a command line only up to PATHS_MAX bytes. Beyond that, two trees
# holding only the listed paths are built in a scratch object store (the repository
# is never written) and compared whole: git then pairs renames among exactly the
# same paths as on the command line. Comparing the full trees instead let git pair a
# listed path with one main had moved it to, outside the list, and the listed path's
# records were dropped (#399 verify round 13).
PATHS_MAX=65536

# ── Which file is which, across moves (#399 verify round 16) ──
# Every check below compares one file of the branch across revisions: the branch's
# commits, the merge-base, the head, and main's commits. A file the branch (or main)
# moved has other names in some of them. Round 16 paired the names with one rename
# detection between two trees, or picked the first of four fixed names a revision
# had; a file moved twice, a file moved away and a new file put at its old name, and
# a file moved and then mostly rewritten were paired wrongly, and commits that never
# landed read as landed (#399 verify round 16). Here a file is followed commit by
# commit, as `git log --follow` does: git's rename detection runs inside each
# non-merge commit since the fork point (the merge-base of the baseline and the
# branch's first commit), and a file's name in a revision is what the moves of that
# revision's own commits make of it, in order. A path that is there before and after
# keeps its file (deleted and later restored, it is the same file); a path a move
# left and a new file then took holds another file. Each file is known by its name in
# the branch head (its last name on the branch when the head no longer has it), and
# every diff below compares trees holding each file under that name, so no
# comparison asks git to guess a move between two trees.
#   - Only the moves, and the additions and deletions of a name some move involves,
#     matter: every other name is the same file in every revision, and with no move
#     at all every comparison reads the repository's own trees, as before.
#   - A move spread over two commits of the branch (one deletes a file, a later one
#     adds it under another name) is taken from one rename detection between the
#     merge-base and the head, limited to the files added or deleted between them.
#   - On main, a file a squash or a pick created is the branch's file when it has a
#     name that file had on the branch (latest first) and no other file of the branch
#     came there by its own history.
#   - A commit whose added times deleted files exceed 1000 x 1000 had git's rename
#     detection skipped (git warns and pairs nothing more): a file it deleted may have
#     moved. That matters only when it deletes a file an earlier candidate touched,
#     whose effects would then look gone from the head; such a candidate cannot be
#     verified (exit 4). Anywhere else the file is taken as deleted.
IDENT="" ; FORK="" ; IDENT_MB=""
# <rev> -> its commit id. A full commit id (the helper passes its own) is taken as it
# is; anything else ("<id>^1") is resolved.
commit_of() {
  case "$1" in
    ''|*[!0-9a-f]*) ;;
    *) if [ "${#1}" -eq 40 ] || [ "${#1}" -eq 64 ]; then printf '%s\n' "$1"; return 0; fi ;;
  esac
  GIT rev-parse -q --verify "$1^{commit}" 2>/dev/null
}
ident_build() { # -> IDENT=0 (nothing a check reads moved) or 1; 2 on error
  [ -z "$IDENT" ] || return 0
  local mb first na nd n p lk ta tb
  local -a ps
  mb="$(GIT merge-base "$BASELINE_SHA" "$BRANCH_SHA" 2>/dev/null)" || return 2
  first="$(GIT rev-list --first-parent "$mb..$BRANCH_SHA" 2>/dev/null | tail -n 1)" || return 2
  FORK="$mb"; IDENT_MB="$mb"
  if [ -n "$first" ] && GIT rev-parse -q --verify "$first^1^{commit}" > /dev/null 2>&1; then
    FORK="$(GIT merge-base "$BASELINE_SHA" "$first^1" 2>/dev/null)" || return 2
  fi
  # (no order file: a missing diff.orderFile makes git fail, #399 verify round 13)
  GIT log --no-merges --topo-order --reverse --no-show-signature --no-color -O/dev/null -M -l1000 -z \
    --ignore-submodules=none --format='%x01%H' --name-status "$BRANCH_SHA" "$BASELINE_SHA" "^$FORK" -- \
    > "$SCRATCH/ops.raw" 2>/dev/null || return 2
  # One token per line (an LF inside a name becomes \001, so it matches no name a check
  # reads: those have none). A commit's header is \001 and its id; the separator after
  # it reaches the next token as a leading \001. Out: "@" <id>, "R" <old> <new>,
  # "A" <name>, "D" <name>, one per line; $SCRATCH/unc lists the commits whose rename
  # detection was skipped, and unc.<id> the files each deleted.
  : > "$SCRATCH/unc" || return 2
  tr '\n\000' '\001\n' < "$SCRATCH/ops.raw" | LC_ALL=C awk -v d="$SCRATCH" '
    function endc(   i, f) {
      if (cur != "" && na * nd > 1000000) {
        print cur >> (d "/unc"); f = d "/unc." cur
        for (i = 1; i <= ndl; i++) print dl[i] > f
        close(f)
      }
      na = 0; nd = 0; ndl = 0
    }
    want == 0 && substr($0, 1, 1) == "\001" && substr($0, 2) ~ /^[0-9a-f]+$/ && length($0) >= 41 {
      endc(); cur = substr($0, 2); print "@"; print cur; sep = 1; next }
    want == 0 {
      st = $0; if (sep && substr(st, 1, 1) == "\001") st = substr(st, 2)
      sep = 0; k = substr(st, 1, 1); want = (k == "R" || k == "C") ? 2 : 1; got = 0; next }
    { got++; p[got] = $0
      if (got < want) next
      want = 0
      if (k == "R") { print "R"; print p[1]; print p[2] }
      else if (k == "A") { print "A"; print p[1]; na++ }
      else if (k == "D") { print "D"; print p[1]; nd++; dl[++ndl] = p[1] } }
    END { if (want) exit 2; endc() }' > "$SCRATCH/ops.all" || return 2
  # A move spread over two commits of the branch: the files added or deleted between the
  # merge-base and the head, paired by one rename detection among them alone ("L" <old>
  # <new>). Best effort: beyond git's limit no such pair is made, and the file is taken
  # as deleted and another added (a dropped commit may then be listed; nothing is
  # missed by it).
  : > "$SCRATCH/links" || return 2
  GIT diff-tree -r -z -O/dev/null --no-renames --name-status --diff-filter=AD --ignore-submodules=none "$mb" "$BRANCH_SHA" \
    > "$SCRATCH/ad.z" 2>/dev/null || return 2
  : > "$SCRATCH/ad.names" || return 2
  tr '\n\000' '\001\n' < "$SCRATCH/ad.z" | LC_ALL=C awk -v out="$SCRATCH/ad.names" '
    NR % 2 == 1 { st = $0; next }
    index($0, "\001") { next }
    { printf "%s%c", $0, 0 > out; if (st == "A") na++; else nd++ }
    END { print na + 0, nd + 0 }' > "$SCRATCH/ad.n" || return 2
  read -r na nd < "$SCRATCH/ad.n" || return 2
  n="$(wc -c < "$SCRATCH/ad.names" | tr -d ' ')" || return 2
  if [ "$na" -gt 0 ] && [ "$nd" -gt 0 ] && [ $((na * nd)) -le 1000000 ]; then
    if [ "$n" -le "$PATHS_MAX" ]; then
      ps=()
      while IFS= read -r -d '' p; do ps+=("$p"); done < "$SCRATCH/ad.names" || return 2
      GIT --literal-pathspecs diff-tree -r -z -O/dev/null -M -l1000 --name-status --ignore-submodules=none "$mb" "$BRANCH_SHA" \
        -- "${ps[@]}" > "$SCRATCH/links.z" 2>/dev/null || return 2
    else
      # (the trees filtered to those paths, as pdiff does)
      lk="$(GIT hash-object --stdin < "$SCRATCH/ad.names" 2>/dev/null)" || return 2
      tr '\000' '\n' < "$SCRATCH/ad.names" > "$SCRATCH/ft.list.$lk" || return 2
      ta="$(ftree "$mb" "$lk")" && tb="$(ftree "$BRANCH_SHA" "$lk")" || return 2
      SGIT diff-tree -r -z -O/dev/null -M -l1000 --name-status --ignore-submodules=none "$ta" "$tb" > "$SCRATCH/links.z" 2>/dev/null || return 2
    fi
    tr '\n\000' '\001\n' < "$SCRATCH/links.z" | LC_ALL=C awk '
      want == 0 { st = $0; want = (st ~ /^[RC]/) ? 2 : 1; got = 0; next }
      { got++; p[got] = $0; if (got < want) next; want = 0
        if (st ~ /^R/) { print "L"; print p[1]; print p[2] } }
      END { if (want) exit 2 }' > "$SCRATCH/links" || return 2
  fi
  # The names some move involves; nothing else needs following.
  cat "$SCRATCH/links" "$SCRATCH/ops.all" | LC_ALL=C awk '
    st == "" { st = $0; need = (st == "R" || st == "L") ? 2 : 1; got = 0; next }
    { got++; if (st == "R" || st == "L") if (!($0 in seen)) { seen[$0] = 1; print }
      if (got == need) st = "" }' > "$SCRATCH/tracked" || return 2
  if [ ! -s "$SCRATCH/tracked" ]; then IDENT=0; return 0; fi
  # The log reduced to the commits' headers, the moves and the additions and deletions
  # of those names
  LC_ALL=C awk -v tr="$SCRATCH/tracked" '
    BEGIN { while ((r = getline l < tr) > 0) T[l] = 1; if (r < 0) exit 2 }
    st == "" { st = $0; need = (st == "R") ? 2 : 1; got = 0; next }
    { v[++got] = $0; if (got < need) next
      if (st == "@" || st == "R" || ((st == "A" || st == "D") && (v[1] in T))) {
        print st; print v[1]; if (st == "R") print v[2] }
      st = "" }' "$SCRATCH/ops.all" > "$SCRATCH/ops.f" || return 2
  # the tracked names that hold a file at the fork point
  ps=()
  while IFS= read -r p; do ps+=("$p"); done < "$SCRATCH/tracked" || return 2
  : > "$SCRATCH/fork.names" || return 2
  n="$(wc -c < "$SCRATCH/tracked" | tr -d ' ')" || return 2
  if [ "$n" -le "$PATHS_MAX" ]; then
    GIT --literal-pathspecs ls-tree -r -z --full-tree "$FORK" -- "${ps[@]}" > "$SCRATCH/fork.ls" 2>/dev/null || return 2
  else
    GIT ls-tree -r -z --full-tree "$FORK" > "$SCRATCH/fork.ls" 2>/dev/null || return 2
  fi
  tr '\n\000' '\001\n' < "$SCRATCH/fork.ls" | LC_ALL=C awk -v tr="$SCRATCH/tracked" '
    BEGIN { while ((r = getline l < tr) > 0) T[l] = 1; if (r < 0) exit 2 }
    { i = index($0, "\t"); p = substr($0, i + 1); if (p in T) print p }' > "$SCRATCH/fork.names" || return 2
  # The head's view: every file's name there, or its last one (the key every diff uses)
  GIT rev-list "$FORK..$BRANCH_SHA" > "$SCRATCH/head.set" 2>/dev/null || return 2
  ident_sim "$SCRATCH/head.set" > "$SCRATCH/canon" || return 2
  GIT rev-list "$FORK..$mb" > "$SCRATCH/mb.set" 2>/dev/null || return 2
  ident_sim "$SCRATCH/mb.set" > "$SCRATCH/ia.mb" || return 2
  IDENT=1
}
# <file of commit ids> -> every file the tracked names ever held, four lines each: its
# identity, 1 if it exists after those commits (0 if not), its name then (its last
# one when it does not exist), and every name it had ("\001"-separated, oldest first).
# The log's commits are applied in order, those of the given set only.
ident_sim() {
  LC_ALL=C awk -v ops="$SCRATCH/ops.f" -v links="$SCRATCH/links" -v fork="$SCRATCH/fork.names" -v set="$1" '
    function newid(n,   id) { id = cur ":" n; ids[++nid] = id; hist[id] = n; return id }
    function del(o,   id) {
      id = holder[o]; if (id == "") return
      delete holder[o]; tomb[o] = id; alive[id] = 0; name[id] = o
    }
    # (the moves of one commit at once: a file may move to a name another one left in
    # the same commit)
    function flushc(   i, id) {
      for (i = 1; i <= nq; i++) if (qt[i] == "R") { id = holder[qa[i]]; if (id == "") id = newid(qa[i]); qi[i] = id }
      for (i = 1; i <= nq; i++) if (qt[i] == "R") delete holder[qa[i]]
      for (i = 1; i <= nq; i++) if (qt[i] == "R") { id = qi[i]; holder[qb[i]] = id; name[id] = qb[i]; alive[id] = 1; hist[id] = hist[id] "\001" qb[i] }
      for (i = 1; i <= nq; i++) if (qt[i] == "D") del(qa[i])
      for (i = 1; i <= nq; i++) if (qt[i] == "A") add(qa[i])
      nq = 0
    }
    function add(n,   id) {
      if (n in holder) return
      if (n in tomb) { id = tomb[n]; delete tomb[n] }
      else if ((n in link) && (link[n] in tomb)) { id = tomb[link[n]]; delete tomb[link[n]]; hist[id] = hist[id] "\001" n }
      else id = newid(n)
      holder[n] = id; name[id] = n; alive[id] = 1
    }
    BEGIN {
      while ((r = getline l < fork) > 0) { id = "F:" l; holder[l] = id; name[id] = l; alive[id] = 1; hist[id] = l; ids[++nid] = id }
      if (r < 0) exit 2
      while ((r = getline l < set) > 0) inset[l] = 1
      if (r < 0) exit 2
      st = ""
      while ((r = getline l < links) > 0) {
        if (st == "") { st = l; got = 0; continue }
        v[++got] = l; if (got < 2) continue
        link[v[2]] = v[1]; st = ""
      }
      if (r < 0) exit 2
      # Within a commit the moves first, then the deletions, then the additions: git lists
      # them by path, and an addition read before the deletion it follows would miss it.
      st = ""; act = 0; nq = 0
      while ((r = getline l < ops) > 0) {
        if (st == "") { st = l; need = (l == "R") ? 2 : 1; got = 0; continue }
        v[++got] = l; if (got < need) continue
        t = st; st = ""
        if (t == "@") { flushc(); cur = v[1]; act = (cur in inset); continue }
        if (!act) continue
        qt[++nq] = t; qa[nq] = v[1]; qb[nq] = (t == "R") ? v[2] : ""
      }
      if (r < 0) exit 2
      flushc()
      for (i = 1; i <= nid; i++) { id = ids[i]; print id; print alive[id] + 0; print name[id]; print hist[id] }
    }'
}
# <rev> -> $SCRATCH/nm.<commit id>: each file of the head's view under its name in
# <rev>, two lines per file: its key (its name in the head) and its name in <rev>
# (empty when <rev> has none). A revision of the branch's history is read by history
# alone. For a revision of main, three steps, in order:
#   1. A file that existed at the merge-base and that the branch moved, which history
#      leaves at its merge-base name (or nowhere) in <rev>, is the file main itself
#      created at a name the file had on the branch, latest first (its name in the head,
#      or an earlier one when only part of the branch landed), when there is one: a
#      squash that moves a file and puts a new one at its old name records no move
#      (git sees the old path still there), so by history alone the new file would be
#      taken for it (round 17's rename fuzz).
#   2. Every other file of the head's view by history, as on the branch.
#   3. A file still without a name takes a file main created itself, or one step 1
#      freed, at a name the file had on the branch, latest first.
# A key two files share (one gone from the head, one there) is the one there.
ident_map() {
  local sha main
  sha="$(commit_of "$1")" || return 2
  [ -f "$SCRATCH/nm.$sha" ] && return 0
  main=0
  GIT merge-base --is-ancestor "$sha" "$BRANCH_SHA" 2>/dev/null; case $? in 0) ;; 1) main=1 ;; *) return 2 ;; esac
  GIT rev-list "$FORK..$sha" > "$SCRATCH/ia.set.$sha" 2>/dev/null || return 2
  ident_sim "$SCRATCH/ia.set.$sha" > "$SCRATCH/ia.$sha" || return 2
  LC_ALL=C awk -v canon="$SCRATCH/canon" -v x="$SCRATCH/ia.$sha" -v mbf="$SCRATCH/ia.mb" -v main="$main" '
    function load(f, A, N, own,    r, l, q, id) {
      q = 0
      while ((r = getline l < f) > 0) {
        if (++q == 1) { id = l; if (own) { ho[++nh] = id; hid[id] = 1 } }
        else if (q == 2) A[id] = l; else if (q == 3) N[id] = l; else { q = 0; if (own) hh[id] = l } }
      if (r < 0) exit 2
    }
    BEGIN {
      load(canon, ha, hc, 1); load(x, xa, xn, 0); load(mbf, ma, mn, 0)
      for (id in xa) if (xa[id] == 1) { at[xn[id]] = id; if (!(id in hid)) mo[xn[id]] = id }
      if (main == 1)       # 1: a moved file main created at a name it had on the branch
        for (i = 1; i <= nh; i++) {
          id = ho[i]; c = hc[id]
          if (ha[id] != 1 || ma[id] != 1 || mn[id] == c || (c in done)) continue
          if (xa[id] == 1 && xn[id] != mn[id]) continue    # history followed its move there
          k = split(hh[id], hn, "\001")
          for (j = k; j >= 1; j--) {
            if (hn[j] == mn[id] || !(hn[j] in mo) || (hn[j] in used)) continue
            out[c] = hn[j]; used[hn[j]] = 1; done[c] = 1
            if (xa[id] == 1) free[xn[id]] = 1
            break
          }
        }
      # 2: by history, the files the head has first, so a shared key goes to the one there
      for (pass = 1; pass <= 2; pass++)
        for (i = 1; i <= nh; i++) {
          id = ho[i]; c = hc[id]
          if ((pass == 1) != (ha[id] == 1) || (c in done)) continue
          if (xa[id] == 1 && !(xn[id] in free) && !(xn[id] in used)) { out[c] = xn[id]; used[xn[id]] = 1; done[c] = 1 }
        }
      for (i = 1; i <= nh; i++) {
        id = ho[i]; c = hc[id]
        if (c in done) continue
        done[c] = 1; out[c] = ""
        if (main != 1) continue
        k = split(hh[id], hn, "\001")   # 3
        for (j = k; j >= 1; j--)
          if (((hn[j] in mo) || (hn[j] in free)) && !(hn[j] in used)) { out[c] = hn[j]; used[hn[j]] = 1; break }
      }
      for (c in done) { print c; print out[c] }
    }' > "$SCRATCH/nm.$sha.tmp" && mv "$SCRATCH/nm.$sha.tmp" "$SCRATCH/nm.$sha"
}
# <rev> <in, NUL-separated keys> <out> -> two lines for each key <rev> has a file for:
# its name in <rev> and the key (a key no move touches is its own name; whether <rev>
# has a file there is not checked).
names_in() {
  local sha
  if [ "$IDENT" = 1 ]; then
    sha="$(commit_of "$1")" || return 2
    ident_map "$sha" || return 2
  fi
  tr '\000' '\n' < "$2" | LC_ALL=C awk -v tr="$SCRATCH/tracked" -v nm="${sha:+$SCRATCH/nm.$sha}" -v id="${IDENT:-0}" '
    BEGIN {
      if (id == 1) {
        while ((r = getline l < tr) > 0) T[l] = 1; if (r < 0) exit 2
        while ((r = getline l < nm) > 0) { if (++q == 1) k = l; else { M[k] = l; q = 0 } }; if (r < 0) exit 2
      }
    }
    { if (id == 1 && ($0 in T)) { if (($0 in M) && M[$0] != "") { print M[$0]; print } }
      else { print; print } }' > "$3"
}
# <rev> <key> -> the name <rev> has the file under (nothing when it has none)
name_at() {
  local sha
  if [ "$IDENT" != 1 ] || ! grep -qxF -- "$2" "$SCRATCH/tracked" 2>/dev/null; then printf '%s' "$2"; return 0; fi
  sha="$(commit_of "$1")" || return 2
  ident_map "$sha" || return 2
  K="$2" LC_ALL=C awk 'BEGIN { k = ENVIRON["K"] } ++q == 1 { c = $0; next } { q = 0; if (c == k) { printf "%s", $0; exit } }' "$SCRATCH/nm.$sha"
}
# <key> -> every name the file had on the branch, NUL-separated (the key alone when no
# move touches it)
aliases_of() {
  if [ "$IDENT" != 1 ] || ! grep -qxF -- "$1" "$SCRATCH/tracked" 2>/dev/null; then printf '%s\000' "$1"; return 0; fi
  K="$1" LC_ALL=C awk 'BEGIN { k = ENVIRON["K"] }
    { if (++q == 1) id = $0; else if (q == 2) a = $0; else if (q == 3) c = $0
      else { q = 0; if (c == k) { n = split($0, h, "\001"); for (i = 1; i <= n; i++) if (!(h[i] in s)) { s[h[i]] = 1; printf "%s%c", h[i], 0 } } } }
    END { if (!(k in s)) printf "%s%c", k, 0 }' "$SCRATCH/canon"
}

# <rev> <in, NUL-separated names in <rev>> <out> -> two lines per name: the name and
# its key (a name no move touches is its own key)
key_pairs() {
  local sha
  if [ "$IDENT" != 1 ]; then
    tr '\000' '\n' < "$2" | LC_ALL=C awk '{ print; print }' > "$3"; return
  fi
  sha="$(commit_of "$1")" || return 2
  ident_map "$sha" || return 2
  tr '\000' '\n' < "$2" | LC_ALL=C awk -v tr="$SCRATCH/tracked" -v nm="$SCRATCH/nm.$sha" '
    BEGIN { while ((r = getline l < tr) > 0) T[l] = 1; if (r < 0) exit 2
            while ((r = getline l < nm) > 0) { if (++q == 1) k = l; else { if (l != "") K[l] = k; q = 0 } }; if (r < 0) exit 2 }
    { print; print (($0 in T) && ($0 in K)) ? K[$0] : $0 }' > "$3"
}
# <rev> <in, NUL-separated names in <rev>> <out, NUL-separated keys, each once>
keys_of() {
  key_pairs "$1" "$2" "$3.kp" || return 2
  LC_ALL=C awk 'NR % 2 == 0 && !($0 in s) { s[$0] = 1; printf "%s%c", $0, 0 }' "$3.kp" > "$3"
}
# <NUL-separated keys> -> 0 when one of them is a name some move involves, 1 when none
# is, 2 on error
has_tracked() {
  [ "$IDENT" = 1 ] || return 1
  tr '\000' '\n' < "$1" | LC_ALL=C awk -v tr="$SCRATCH/tracked" '
    BEGIN { while ((r = getline l < tr) > 0) T[l] = 1; if (r < 0) { e = 1; exit } }
    ($0 in T) { f = 1; exit }
    END { if (e) exit 2; exit !f }'
}
# <a> <b> <keys file, NUL-separated> -> 0 when a key some move involves is not, in <a>
# or in <b>, the file's own name there (so the diff needs the trees by key, ctree); 1 when
# every such key is (the key's path holds that file in both, and no other), or none of
# the keys is a name a move involves: the repository's own trees then; 2 on error. One
# awk over the tracked names and both revisions' name maps.
diff_by_key() {
  local sa sb
  [ "$IDENT" = 1 ] || return 1
  if [ "$1" = "$EMPTY_TREE" ]; then sa=""; else sa="$(commit_of "$1")" && ident_map "$sa" || return 2; fi
  if [ "$2" = "$EMPTY_TREE" ]; then sb=""; else sb="$(commit_of "$2")" && ident_map "$sb" || return 2; fi
  tr '\000' '\n' < "$3" | LC_ALL=C awk -v tr="$SCRATCH/tracked" -v na="${sa:+$SCRATCH/nm.$sa}" -v nb="${sb:+$SCRATCH/nm.$sb}" '
    function load(f, S,    r, l, q, k) {
      if (f == "") return
      while ((r = getline l < f) > 0) { if (++q == 1) k = l; else { q = 0; if (l == k) S[k] = 1 } }
      if (r < 0) e = 1
    }
    BEGIN { while ((r = getline l < tr) > 0) T[l] = 1; if (r < 0) e = 1; load(na, A); load(nb, B); if (e) exit }
    ($0 in T) && (na == "" || !($0 in A) || nb == "" || !($0 in B)) { f = 1; exit }
    END { if (e) exit 2; exit !f }'
}
# <rev> <keys file, NUL-separated> <out> -> one line per key in the file's order: what
# <rev> holds for it, "blob <oid>", "link <oid>" (a submodule) or "none". One
# `ls-tree -r -z`, matched by exact path (no line-based object lookup, which drops a
# trailing CR and, before git 2.51, reports a gitlink as missing).
entries_of() {
  names_in "$1" "$2" "$3.pairs" || return 2
  GIT ls-tree -r -z --full-tree "$1" 2>/dev/null | tr '\n\000' '\001\n' > "$3.tree" || return 2
  tr '\000' '\n' < "$2" | LC_ALL=C awk -v pairs="$3.pairs" -v tree="$3.tree" '
    BEGIN {
      while ((r = getline l < pairs) > 0) { if (++q == 1) n = l; else { q = 0; nk[n] = nk[n] SUBSEP l } }
      if (r < 0) exit 2
      while ((r = getline l < tree) > 0) {
        i = index(l, "\t"); p = substr(l, i + 1)
        if (!(p in nk)) continue
        split(substr(l, 1, i - 1), m, " ")
        k = split(nk[p], ks, SUBSEP)
        for (j = 2; j <= k; j++) e[ks[j]] = (m[2] == "commit" ? "link " : "blob ") m[3]
      }
      if (r < 0) exit 2
    }
    { print (($0 in e) ? e[$0] : "none") }' > "$3"
}

# ── Comparing two trees line by line, in place (#399) ──
# Everything at a landing commit is decided by two-way diffs read position by
# position: which old-side lines a diff changes, and which lines it adds or deletes.
# There is no three-way merge anywhere: a merge conflicts when two edits merely sit
# on adjacent lines, and round 11 read such a conflict as "landed" (#399 verify
# round 11). Every option that shapes the output is pinned, so no config, attribute
# or external program changes it: no context lines between hunks
# (diff.interHunkContext; GIT_DIFF_OPTS is unset above), no external diff, no
# textconv, --text for files git calls binary, no rename detection (diff.renames),
# myers with the indent heuristic (diff.algorithm, diff.indentHeuristic), fixed a/
# and b/ prefixes (diff.noprefix, diff.mnemonicPrefix), quoted names
# (core.quotePath), no color, no order file (diff.orderFile: a missing one makes git
# diff fail, which sent every check to the tip, #399 verify round 13; an existing one
# is opened and read), and submodules as "Subproject commit <oid>" lines
# (diff.submodule). A moved file is still one file: when the files listed include one
# some move involves, both sides are trees that hold each file under its name in the
# head (ctree, from the identities above), so a moved file is not all new lines and
# one line main edited in it does not keep a commit from holding the branch's net
# change (round 12), and no rename detection between two trees has to guess (round
# 16). The helper runs at the top level, where diff.relative changes nothing. git's
# messages are discarded: they can quote repository text (an invalid attribute name).
EMPTY_TREE="$(GIT hash-object -t tree /dev/null 2>/dev/null)" || skip "cannot name the empty tree"
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
# <rev> <list key> -> a tree holding, under each key in $SCRATCH/ft.list.<key>, the
# entry <rev> has for that file (at its own name there), built once per commit and list
# in the scratch store: the diffs between two such trees pair each file with itself,
# whatever it is called in either revision (#399 verify round 16). A file <rev> has no
# name for is left out; every entry found must reach the index, as in ftree.
ctree() {
  local sha out n p
  local -a ps
  if [ "$1" = "$EMPTY_TREE" ]; then printf '%s\n' "$EMPTY_TREE"; return 0; fi
  sha="$(commit_of "$1")" || return 2
  out="$SCRATCH/ct.$2.$sha"
  [ -s "$out" ] && { cat "$out"; return 0; }
  tr '\n' '\000' < "$SCRATCH/ft.list.$2" > "$SCRATCH/ct.keys" \
    && names_in "$sha" "$SCRATCH/ct.keys" "$SCRATCH/ct.pairs" || return 2
  LC_ALL=C awk 'NR % 2 == 1 { printf "%s%c", $0, 0 }' "$SCRATCH/ct.pairs" > "$SCRATCH/ct.names" || return 2
  n="$(wc -c < "$SCRATCH/ct.names" | tr -d ' ')" || return 2
  if [ "$n" -eq 0 ]; then printf '%s\n' "$EMPTY_TREE" > "$out"; cat "$out"; return 0; fi
  if [ "$n" -le "$PATHS_MAX" ]; then
    ps=()
    while IFS= read -r -d '' p; do ps+=("$p"); done < "$SCRATCH/ct.names" || return 2
    GIT --literal-pathspecs ls-tree -r -z --full-tree "$sha" -- ${ps[@]+"${ps[@]}"} > "$SCRATCH/ct.ls" 2>/dev/null || return 2
  else
    GIT ls-tree -r -z --full-tree "$sha" > "$SCRATCH/ct.ls" 2>/dev/null || return 2
  fi
  rm -f "$SCRATCH/ft.idx"
  tr '\n\000' '\001\n' < "$SCRATCH/ct.ls" | LC_ALL=C awk -v pairs="$SCRATCH/ct.pairs" '
    BEGIN { while ((r = getline l < pairs) > 0) { if (++q == 1) n = l; else { q = 0; nk[n] = nk[n] SUBSEP l } }; if (r < 0) exit 2 }
    { i = index($0, "\t"); p = substr($0, i + 1); if (!(p in nk)) next
      k = split(nk[p], ks, SUBSEP); for (j = 2; j <= k; j++) print substr($0, 1, i) ks[j] }' > "$SCRATCH/ct.in" || return 2
  [ -s "$SCRATCH/ct.in" ] || { printf '%s\n' "$EMPTY_TREE" > "$out"; cat "$out"; return 0; }
  tr '\n' '\000' < "$SCRATCH/ct.in" \
    | GIT_INDEX_FILE="$SCRATCH/ft.idx" SGIT update-index -z --index-info 2>/dev/null || return 2
  [ "$(GIT_INDEX_FILE="$SCRATCH/ft.idx" SGIT ls-files -s -z 2>/dev/null | tr -cd '\000' | wc -c | tr -d ' ')" \
    = "$(wc -l < "$SCRATCH/ct.in" | tr -d ' ')" ] || return 2
  GIT_INDEX_FILE="$SCRATCH/ft.idx" SGIT write-tree --missing-ok > "$out.tmp" 2>/dev/null \
    && [ -s "$out.tmp" ] && mv "$out.tmp" "$out" || return 2
  cat "$out"
}
DIFF_OPTS=(-c core.quotePath=true --literal-pathspecs diff -U0 --inter-hunk-context=0 --no-color -O/dev/null
  --no-ext-diff --no-textconv --text --no-renames --diff-algorithm=myers --indent-heuristic
  --src-prefix=a/ --dst-prefix=b/ --ignore-submodules=none --submodule=short)
pdiff() { # <a> <b> <keys file, NUL-separated> -> unified diff with no context
  local p n ta tb lk rc
  local -a ps
  ps=()
  [ -r "$3" ] || return 2
  n="$(wc -c < "$3" | tr -d ' ')" || return 2
  [ "$n" -gt 0 ] || return 0
  # a file some move involves, which either revision has under another name (or not at
  # all, its key's path perhaps holding another file): each revision's file under its key
  diff_by_key "$1" "$2" "$3"; rc=$?
  if [ "$rc" -eq 0 ]; then
    lk="$(GIT hash-object --stdin < "$3" 2>/dev/null)" || return 2
    [ -s "$SCRATCH/ft.list.$lk" ] || tr '\000' '\n' < "$3" > "$SCRATCH/ft.list.$lk" || return 2
    ta="$(ctree "$1" "$lk")" && tb="$(ctree "$2" "$lk")" || return 2
    SGIT "${DIFF_OPTS[@]}" "$ta" "$tb" 2>/dev/null || return 2
  elif [ "$rc" -ne 1 ]; then
    return 2
  elif [ "$n" -le "$PATHS_MAX" ]; then
    while IFS= read -r -d '' p; do ps+=("$p"); done < "$3" || return 2
    GIT "${DIFF_OPTS[@]}" "$1" "$2" -- "${ps[@]}" 2>/dev/null || return 2
  else
    lk="$(GIT hash-object --stdin < "$3" 2>/dev/null)" || return 2
    [ -s "$SCRATCH/ft.list.$lk" ] || tr '\000' '\n' < "$3" > "$SCRATCH/ft.list.$lk" || return 2
    ta="$(ftree "$1" "$lk")" && tb="$(ftree "$2" "$lk")" || return 2
    SGIT "${DIFF_OPTS[@]}" "$ta" "$tb" 2>/dev/null || return 2
  fi
}
# One record per line, "<kind><TAB><line number><TAB><key>": C, an old-side line the
# diff changes; A, a new-side line it adds; D, an old-side line it deletes (A and D
# skip blank lines, which SPEC.md's definition ignores). Within a hunk an old and a
# new line at the same offset with the same text are unchanged (two equal lines diff
# happened to pair), and so is a last line whose final newline alone changed, paired
# with the equal line on the other side wherever it sits in the hunk. The diffs above
# detect no renames: a file is one key on both sides (a file's name in each revision
# was resolved before the diff, ctree), so a record joins the records of any other
# diff by its key and its line number on one revision. Names come from the ---/+++
# lines, C-unquoted when git quoted them; a file is kept when its name is in <paths
# file> (a pathspec also matches what lies under a directory of that name). A decoded
# name with a newline in it would split a record: it fails the whole read (exit 2),
# and so does anything unexpected inside a hunk (a context line, from a setting the
# options above do not cover) rather than shift a position.
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
    /^diff --git / { flush(); h = 0; oldp = ""; keep = 0; next }
    !h && /^(rename|copy) (from|to) / { bad = 1; exit }
    !h && /^--- / { oldp = name(substr($0, 5)); next }
    !h && /^\+\+\+ / { p = name(substr($0, 5))
      path = (p == "/dev/null") ? substr(oldp, 3) : substr(p, 3)
      if (index(path, "\n")) { bad = 1; exit }
      keep = (path in want)
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

# Each candidate's files, listed once: the names it touched (refused when one has a
# newline), the ones it deletes and adds as a whole (D.<n>, A.<n>, with their keys in
# Dk.<n>, Ak.<n>), and the keys of all of them (keys.<n>), each file's name in the
# head. Every path a candidate touched is numbered once by one awk pass (bash 3.2 has
# no associative arrays, and a linear search is quadratic on a wide commit); each
# candidate's numbers go to its own file, which awk reads later, never argv. -z so a
# space or a non-ASCII name (quoted by core.quotePath) stays the real path.
ident_build || skip "cannot follow the files the branch or the baseline moved"
: > "$SCRATCH/pairs"; k=0; NPATHS=""
for sha in $CANDIDATES; do
  GIT diff-tree --root --no-commit-id --no-renames --ignore-submodules=none --name-status -r -z "$sha" \
    > "$SCRATCH/ns.z" 2>/dev/null || skip "cannot list the paths $(short "$sha") touched"
  has_lf "$SCRATCH/ns.z"; case "$?" in
    0) skip "$(short "$sha") touches a path with a newline (or \\001) in its name" ;;
    1) ;;
    *) skip "cannot read the paths $(short "$sha") touched" ;;
  esac
  # "<status> NUL <path> NUL": a path the commit deleted is in its parent, any other in it
  : > "$SCRATCH/D.$k.z" && : > "$SCRATCH/A.$k.z" && : > "$SCRATCH/in.z" \
    && tr '\000' '\n' < "$SCRATCH/ns.z" | LC_ALL=C awk -v d="$SCRATCH" -v k="$k" '
      NR % 2 == 1 { st = $0; next }
      { if (st == "D") printf "%s%c", $0, 0 > (d "/D." k ".z")
        else { printf "%s%c", $0, 0 > (d "/in.z"); if (st == "A") printf "%s%c", $0, 0 > (d "/A." k ".z") } }' \
    && tr '\000' '\n' < "$SCRATCH/D.$k.z" > "$SCRATCH/D.$k" && tr '\000' '\n' < "$SCRATCH/A.$k.z" > "$SCRATCH/A.$k" \
    || skip "cannot read the paths $(short "$sha") touched"
  par="$(GIT rev-parse -q --verify "$sha^1^{commit}" 2>/dev/null)" || par=""
  if [ -n "$par" ]; then
    key_pairs "$par" "$SCRATCH/D.$k.z" "$SCRATCH/Dk.$k" || skip "cannot follow the files $(short "$sha") deleted"
  else
    : > "$SCRATCH/Dk.$k"
  fi
  # (an added path counts as an effect only while it is still that file's path in the
  # head, its key: a later move took the file elsewhere, and a new file there is
  # another one, #399 round 17's rename fuzz)
  key_pairs "$sha" "$SCRATCH/in.z" "$SCRATCH/Ik.$k" && key_pairs "$sha" "$SCRATCH/A.$k.z" "$SCRATCH/Ak.$k" \
    && LC_ALL=C awk 'NR % 2 == 1 { n = $0; next } $0 == n { print n }' "$SCRATCH/Ak.$k" > "$SCRATCH/As.$k" \
    || skip "cannot follow the files $(short "$sha") touched"
  LC_ALL=C awk -v k="$k" 'NR % 2 == 0 && !($0 in s) { s[$0] = 1; print k "\t" $0 }' "$SCRATCH/Ik.$k" "$SCRATCH/Dk.$k" \
    >> "$SCRATCH/pairs" || skip "cannot index the paths $(short "$sha") touched"
  [ -s "$SCRATCH/ns.z" ] && NPATHS="$NPATHS $k"
  k=$((k + 1))
done
LC_ALL=C awk -v d="$SCRATCH" '
  { i = index($0, "\t"); k = substr($0, 1, i - 1); p = substr($0, i + 1)
    if (!(p in idx)) { idx[p] = n++; print p > (d "/paths") }
    f = d "/c." k; print idx[p] >> f; close(f) }' "$SCRATCH/pairs" || skip "cannot index the touched paths"
for k in $NPATHS; do [ -s "$SCRATCH/c.$k" ] || skip "lost the path list of candidate $k"; done
# <candidate number> -> $SCRATCH/cp.z: its keys, NUL-separated (none has LF: those were
# refused above)
cand_keys() {
  LC_ALL=C awk -v paths="$SCRATCH/paths" 'BEGIN { while ((getline l < paths) > 0) P[n++] = l }
    { printf "%s%c", P[$0], 0 }' "$SCRATCH/c.$1" > "$SCRATCH/cp.z"
}

# ── The head's content is already at the tip (#399) ──
# The issue's own first test: when, on every path a candidate touched, the tip has
# exactly what the head has (the same blob, or no file on either side), there is
# nothing left to land, however main got there (a squash resolved by hand to the
# head's tree, a later commit of main's own). Plumbing, so no diff setting applies.
# Both the paths and the files: a file a later commit moved is compared under its
# name in the head and its name in the tip (the commit that moved it may have reached
# main as a pick, and then it is no candidate; #399 verify round 16).
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
  if [ "$rc" -eq 0 ] && [ "$IDENT" = 1 ]; then
    for k in $NPATHS; do cand_keys "$k" && cat "$SCRATCH/cp.z"; done > "$SCRATCH/p0.z" \
      || skip "cannot read the files the branch touched"
    if has_tracked "$SCRATCH/p0.z"; then
      entries_of "$BRANCH_SHA" "$SCRATCH/p0.z" "$SCRATCH/p0.h" && entries_of "$BASELINE_SHA" "$SCRATCH/p0.z" "$SCRATCH/p0.t" \
        || skip "cannot compare the branch head with $S"
      cmp -s "$SCRATCH/p0.h" "$SCRATCH/p0.t" || rc=3
    fi
  fi
  if [ "$rc" -eq 0 ]; then
    printf 'landing - prefix -\nshortcut\n' | trace_out
    exit 0
  fi
fi


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
  # The files that differ, by key: a name the change deleted is in the merge-base, any
  # other in <rev>. A path with LF in its name cannot go through the line-based steps
  # below.
  GIT diff-tree -r -z --name-status --no-renames --ignore-submodules=none "$1" "$2" \
    > "$SCRATCH/net.ns" 2>/dev/null || return 1
  has_lf "$SCRATCH/net.ns"; [ $? -eq 1 ] || return 1
  : > "$SCRATCH/net.dn" && : > "$SCRATCH/net.nn" && tr '\000' '\n' < "$SCRATCH/net.ns" | LC_ALL=C awk -v d="$SCRATCH" '
    NR % 2 == 1 { st = $0; next }
    { printf "%s%c", $0, 0 > (d (st == "D" ? "/net.dn" : "/net.nn")) }' || return 1
  keys_of "$1" "$SCRATCH/net.dn" "$SCRATCH/net.dk" && keys_of "$2" "$SCRATCH/net.nn" "$SCRATCH/net.nk" || return 1
  cat "$SCRATCH/net.nn" "$SCRATCH/net.dn" > "$SCRATCH/net.names" && tr '\000' '\n' < "$SCRATCH/net.names" > "$SCRATCH/net.nlist" || return 1
  cat "$SCRATCH/net.nk" "$SCRATCH/net.dk" | tr '\000' '\n' \
    | LC_ALL=C awk '!($0 in s) { s[$0] = 1; printf "%s%c", $0, 0 }' > "$SCRATCH/net.z" || return 1
  pdiff "$1" "$2" "$SCRATCH/net.z" | pparse "$SCRATCH/net.z" > "$SCRATCH/net.diff" || return 1
  tr '\000' '\n' < "$SCRATCH/net.z" > "$SCRATCH/net.list" || return 1
  NET_KEY="$1 $2"; NET_GEN=$((NET_GEN + 1))
}
NET_GEN=0 ; NETN_GEN="" ; NETN=0
# <rev> <key> <out>: <rev>'s file of that key (under its name there) into <out>,
# empty when there is none; 1 for a submodule there (no lines to count), 2 on error.
file_of() {
  local ty n
  n="$(name_at "$1" "$2")" || return 2
  [ -n "$n" ] || { : > "$3"; return 0; }
  ty="$(entry_of "$1" "$n")"
  case $? in 1) : > "$3"; return 0 ;; 0) ;; *) return 2 ;; esac
  [ "$ty" = blob ] || return 1
  GIT cat-file blob "$1:$n" > "$3" 2>/dev/null || return 2
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
# is unused; the file is <key>'s, listed by every name it had on the branch (a commit
# that edited it under a name it no longer has touches it too, #399 verify round 16).
single_changer() { # <rev> <key> <records>
  local b rc side r key p
  local -a al
  : > "$SCRATCH/sc.texts"
  key="$(printf '%s' "$2" | GIT hash-object --stdin 2>/dev/null)" || return 2
  aliases_of "$2" > "$SCRATCH/sc.al" || return 2
  al=()
  while IFS= read -r -d '' p; do al+=("$p"); done < "$SCRATCH/sc.al" || return 2
  GIT --literal-pathspecs rev-list --no-merges "$HOLD_MB..$BRANCH_SHA" -- "${al[@]}" > "$SCRATCH/sc.revs" 2>/dev/null || return 2
  while IFS= read -r b; do
    GIT rev-parse -q --verify "$b^1^{commit}" > /dev/null 2>&1 || continue
    # Every text the commit touches in the file, read once per commit and file (the
    # prefix search asks again for each earlier commit's net change, #399 verify
    # round 14): the texts whose copies it changes, and those of the lines it adds or
    # deletes.
    if [ ! -f "$SCRATCH/sc.t.$b.$key" ]; then
      for side in 1 0; do
        [ "$side" = 1 ] && r="$b" || r="$b^1"
        file_of "$r" "$2" "$SCRATCH/sc.$side"; rc=$?
        [ "$rc" -le 1 ] || return 2
        [ "$rc" -eq 0 ] || : > "$SCRATCH/sc.$side"
      done
      # the commit's own diff of the file
      printf '%s\000' "$2" > "$SCRATCH/sc.z"
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
    LC_ALL=C awk -v rec="$3" 'BEGIN {
        while ((r = getline l < rec) > 0) { x = l; for (j = 1; j <= 4; j++) x = substr(x, index(x, "\t") + 1); T[x] = 1 }
        if (r < 0) exit 2 }
      ($0 in T) { print }' "$SCRATCH/sc.t.$b.$key" >> "$SCRATCH/sc.texts" || return 2
  done < "$SCRATCH/sc.revs"
  LC_ALL=C awk -v t="$SCRATCH/sc.texts" 'BEGIN { while ((r = getline l < t) > 0) n[l]++; if (r < 0) exit 2 }
    { x = $0; for (j = 1; j <= 4; j++) x = substr(x, index(x, "\t") + 1); if (n[x] + 0 <= 1) print }' "$3" > "$3.tmp" \
    && mv "$3.tmp" "$3"
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
  local c="$1" rev="$2" par p i rc rf r
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
      # (each revision's file read by its key, under the name it has there)
      rc=1
      if [ ! -f "$SCRATCH/rep.$NET_GEN.$i.raw" ]; then
        file_of "$rev" "$p" "$SCRATCH/rf.rev"; rc=$?
        [ "$rc" -le 1 ] || return 2
        if [ "$rc" -eq 0 ]; then file_of "$HOLD_MB" "$p" "$SCRATCH/rf.mb"; rc=$?; fi
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
        single_changer "$rev" "$p" "$SCRATCH/rep.$NET_GEN.$i.tmp" || return 2
      fi
      mv "$SCRATCH/rep.$NET_GEN.$i.tmp" "$SCRATCH/rep.$NET_GEN.$i" || return 2
      # a path none of whose records repeat refuses every failing line at once next time
      [ -s "$SCRATCH/rep.$NET_GEN.$i" ] || printf '%s\n' "$p" >> "$SCRATCH/repnone.$NET_GEN"
    fi
    in_rep "$p" "$SCRATCH/rep.$NET_GEN.$i"; rc=$?; [ "$rc" -eq 0 ] || return "$rc"
  done < "$SCRATCH/h.fpaths" 3< "$SCRATCH/h.fidx"
  while IFS= read -r p && IFS= read -r i <&3; do
    for rf in c par; do
      [ "$rf" = c ] && r="$c" || r="$par"
      file_of "$r" "$p" "$SCRATCH/rf.$rf"; rc=$?; [ "$rc" -eq 0 ] || return "$rc"
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
# By the names themselves, not the files' keys: a move that never landed leaves the
# file at its old name, and the commit then does not hold the net change (round 17's
# rename fuzz: read by key, a squash without the move held a prefix that moved the
# file). One plumbing call per commit, whatever the number of paths.
same_paths() { # <rev> <commit> -> 0 the same, 1 not, 2 error
  local p n
  local -a ps
  ps=()
  n="$(wc -c < "$SCRATCH/net.names" | tr -d ' ')" || return 2
  if [ "$n" -le "$PATHS_MAX" ]; then
    while IFS= read -r -d '' p; do ps+=("$p"); done < "$SCRATCH/net.names" || return 2
  fi
  GIT --literal-pathspecs diff-tree -r -z --no-renames --name-status --ignore-submodules=none "$1" "$2" \
    -- ${ps[@]+"${ps[@]}"} > "$SCRATCH/same.z" 2>/dev/null || return 2
  # "<status> NUL <path> NUL" pairs; an LF in a name elsewhere becomes \001, so it can
  # match no listed path
  tr '\n\000' '\001\n' < "$SCRATCH/same.z" | LC_ALL=C awk -v list="$SCRATCH/net.nlist" '
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

# Where each candidate is checked (its files were listed above).
k=0; NEED_TIP=""; SIDE_OF=""
for sha in $CANDIDATES; do
  use_landing "$sha"; rc=$?
  case "$rc" in
    0) SIDE_OF="$SIDE_OF land" ;;
    1) SIDE_OF="$SIDE_OF tip"; NEED_TIP=1 ;;
    *) skip "cannot tell whether $(short "$sha") is in the landed part of the branch" ;;
  esac
  k=$((k + 1))
done

# What each side has for every touched file (by key, under its name on that side):
# "blob <oid>", "link <oid>" (a gitlink, which diff prints as "Subproject commit
# <oid>") or "none" (entries_of). Each distinct blob is then read once; a listed blob
# that cannot be read is an error, never an empty file.
classify() { # <rev> <side> -> $SCRATCH/<side>.map, one line per key in $SCRATCH/paths
  tr '\n' '\000' < "$SCRATCH/paths" > "$SCRATCH/cls.z" && entries_of "$1" "$SCRATCH/cls.z" "$SCRATCH/$2.map"
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
  local par rc
  [ -s "$SCRATCH/c.$2" ] || return 11
  # The commit's own change of each file, by key (a file it moved is one file, so a
  # move alone is no line; a moved file is otherwise all new lines, and every line main
  # edited in it, even before the squash, would list the commit, #399 verify round 13).
  # A move that never landed is still seen: its old path is in the commit's deleted
  # paths and its new one in its added paths (below). The head and the tip are read
  # by key, each under the name the file has there: a file a later commit moved, or
  # moved and rewrote, or moved and replaced by a new file at the old name, is the
  # same file (#399 verify rounds 14, 16).
  # (with no moved file among them, the commit's own patch, unfiltered: a path list too
  # long for the command line would need the filtered trees, which a path update-index
  # refuses cannot reach, #399 verify round 14)
  par="$(GIT rev-parse -q --verify "$1^1^{commit}" 2>/dev/null)" || par="$EMPTY_TREE"
  cand_keys "$2" || return 2
  has_tracked "$SCRATCH/cp.z"; rc=$?
  case $rc in
    0) pdiff "$par" "$1" "$SCRATCH/cp.z" > "$SCRATCH/patch" || return 2 ;;
    1) GIT diff-tree --root --no-commit-id -r -p --text --no-ext-diff --no-textconv --no-color --no-renames \
         --ignore-submodules=none --submodule=short "$1" > "$SCRATCH/patch" 2>/dev/null || return 2 ;;
    *) return 2 ;;
  esac
  listing "$BRANCH_SHA" "$SCRATCH/ls.head" && listing "$BASELINE_SHA" "$SCRATCH/ls.tip" || return 2
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
  LC_ALL=C awk -v d="$SCRATCH" -v list="$SCRATCH/c.$2" -v dels="$SCRATCH/D.$2" -v adds="$SCRATCH/As.$2" \
    -v lsh="$SCRATCH/ls.head" -v lst="$SCRATCH/ls.tip" '
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
    # a path, by its name: whether the head and the tip have a file there
    function paths(f, del,    l, r, h, t) {
      while ((r = getline l < f) > 0) {
        h = (l in HP); t = (l in TP)
        if (del ? kept(h, t) : missing(h, t)) found = 1
      }
      if (r < 0) bad = 1; close(f)
    }
    function set(f, s,    r, l) { while ((r = getline l < f) > 0) s[l] = 1; if (r < 0) bad = 1; close(f) }
    BEGIN {
      slurp(d "/head.map", hm); slurp(d "/tip.map", tm)
      while ((r = getline j < list) > 0) { load(hm[j], head); load(tm[j], target) }
      if (r < 0) bad = 1; close(list)
      set(lsh, HP); set(lst, TP)
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
count_of_line() { # <rev> <key> <text file> -> copies of that line in <rev>'s file, 0 when absent, "x" for a submodule
  local ty n
  n="$(name_at "$1" "$2")" || return 2
  [ -n "$n" ] || { echo 0; return 0; }
  ty="$(entry_of "$1" "$n")"
  case $? in 1) echo 0; return 0 ;; 0) ;; *) return 2 ;; esac
  [ "$ty" = blob ] || { echo x; return 0; }
  GIT cat-file blob "$1:$n" > "$SCRATCH/cnt.blob" 2>/dev/null || return 2
  # Compared as text: awk compares two values that both look like numbers as numbers,
  # and "1", "01" and "1.0" were counted as copies of one line (#399 verify round 16).
  LC_ALL=C awk -v t="$3" 'BEGIN { if ((getline x < t) < 0) exit 2 } ("x" $0) == ("x" x) { n++ } END { print n + 0 }' "$SCRATCH/cnt.blob"
}
# <commit> <key> ...: 0 when the commit's own change of the file (by key, each
# revision's file under its name there) is all in place in L^1: each line it added unchanged there, each
# line it deleted gone. 1 when not, or when the commit has no line in that file to
# check; 2 on error.
in_l1() { # <commit> <keys file, NUL-separated>
  local b="$1" par lp
  par="$(GIT rev-parse -q --verify "$b^1^{commit}" 2>/dev/null)" || return 1
  lp="$(GIT rev-parse -q --verify "$LANDING^1^{commit}" 2>/dev/null)" || return 2
  cp "$2" "$SCRATCH/i1.z" || return 2
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
other_copies() { # <commit> <text file> <key>
  local c="$1" t="$2" k="$3" b n1 n2 nk rc p
  local -a al
  # in_l1 depends on the commit and the file only, not on the text: its answer is kept
  # per commit and key (one finding after another asks again, #399 verify round 15
  # measured a landed 150-commit branch five times slower than round 13). The
  # branch's commits are listed by every name the file had on the branch: a commit
  # that edited it under a name it no longer has is one of them (#399 verify round 16:
  # a file moved twice, edited under its middle name).
  nk="$(printf '%s' "$k" | GIT hash-object --stdin 2>/dev/null)" || return 2
  aliases_of "$k" > "$SCRATCH/oc.al" || return 2
  al=()
  while IFS= read -r -d '' p; do al+=("$p"); done < "$SCRATCH/oc.al" || return 2
  GIT --literal-pathspecs rev-list --no-merges "$LANDING_MB..$BRANCH_SHA" -- "${al[@]}" > "$SCRATCH/cnt.revs" 2>/dev/null || return 2
  while IFS= read -r b; do
    [ "$b" != "$c" ] || continue
    GIT rev-parse -q --verify "$b^1^{commit}" > /dev/null 2>&1 || continue
    n1="$(count_of_line "$b^1" "$k" "$t")" || return 2
    n2="$(count_of_line "$b" "$k" "$t")" || return 2
    [ "$n1" != "$n2" ] || continue
    if [ -f "$SCRATCH/i1c.$b.$nk" ]; then
      rc="$(cat "$SCRATCH/i1c.$b.$nk")"
    else
      printf '%s\000' "$k" > "$SCRATCH/i1.k"
      in_l1 "$b" "$SCRATCH/i1.k"; rc=$?
      [ "$rc" -gt 1 ] || echo "$rc" > "$SCRATCH/i1c.$b.$nk"
    fi
    case $rc in 0) return 0 ;; 1) ;; *) return 2 ;; esac
  done < "$SCRATCH/cnt.revs"
  return 1
}
confirm() { # <commit> <parent> <"A|D<TAB>line<TAB>key"> -> 0 missing, 1 landed after all, 2 error
  local c="$1" par="$2" t line key src sname ty n_src n_oth n_head n_ref n_land n_prev n_mb
  local T="$SCRATCH/cnt.text"
  t="${3%%$'\t'*}"; line="${3#*$'\t'}"; key="${line#*$'\t'}"; line="${line%%$'\t'*}"
  # Only lines of a file the commit edited are counted, each revision's file read by
  # its key, under the name it has there. Anything else keeps the finding: a
  # submodule pointer (its record is "Subproject commit <oid>", not a line of a file),
  # a file the commit deleted for an added line or created for a deleted one, a root
  # commit (#399 verify round 13). A line in a file the commit created is counted like
  # any other (round 15's verify: one the two diffs paired differently stood as
  # missing).
  [ "$par" != "$EMPTY_TREE" ] || return 0
  if [ "$t" = A ]; then src="$c"; else src="$par"; fi
  sname="$(name_at "$src" "$key")" || return 2
  [ -n "$sname" ] || return 0
  ty="$(entry_of "$src" "$sname")"
  case $? in 0) ;; 1) return 0 ;; *) return 2 ;; esac
  [ "$ty" = blob ] || return 0
  GIT cat-file blob "$src:$sname" 2>/dev/null | LC_ALL=C awk -v k="$line" 'NR == k { print; f = 1 } END { exit !f }' \
    > "$T" || return 2
  n_src="$(count_of_line "$src" "$key" "$T")" || return 2
  n_head="$(count_of_line "$BRANCH_SHA" "$key" "$T")" || return 2
  n_ref="$(count_of_line "${PREFIX_TIP:-$BRANCH_SHA}" "$key" "$T")" || return 2
  n_land="$(count_of_line "$LANDING" "$key" "$T")" || return 2
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
      n_oth="$(count_of_line "$par" "$key" "$T")" || return 2
      [ "$n_land" -ge "$n_ref" ] || return 0
    else
      n_oth="$(count_of_line "$c" "$key" "$T")" || return 2
      [ "$n_land" -le "$n_ref" ] || return 0
    fi
    [ "$n_oth" != x ] && [ "$n_oth" != "$n_src" ] || return 0
  fi
  # The copies main itself added or removed before the landing commit (L^1 against the
  # merge-base)
  n_prev=0; n_mb=0
  if [ -n "$LANDING_MB" ] && [ "$LANDING" != "$LANDING_MB" ]; then
    n_prev="$(count_of_line "$LANDING^1" "$key" "$T")" || return 2
    n_mb="$(count_of_line "$LANDING_MB" "$key" "$T")" || return 2
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
  other_copies "$c" "$T" "$key"
  case $? in 0) return 0 ;; 1) return 1 ;; *) return 2 ;; esac
}
land_orphan_p() { # <commit-sha> <candidate number> -> 10 orphan, 11 landed, other: error
  local c="$1" par f
  [ -s "$SCRATCH/c.$2" ] || return 11
  par="$(GIT rev-parse -q --verify "$c^1^{commit}" 2>/dev/null)" || par="$EMPTY_TREE"
  # the candidate's files, by key
  cand_keys "$2" || return 2
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
  # (by name; a file whose key has a line record is checked by its lines)
  for f in A D; do
    LC_ALL=C awk -v f="$f" -v own="$SCRATCH/l.own" 'BEGIN { while ((r = getline l < own) > 0) if (l ~ /^[AD]\t/) { i = index(substr(l, 3), "\t"); seen[substr(l, 3 + i)] = 1 }; if (r < 0) exit 2 }
      NR % 2 == 1 { n = $0; next } !($0 in seen) && (f != "A" || $0 == n) { print n }' "$SCRATCH/${f}k.$2" > "$SCRATCH/l.bare.$f" || return 2
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
# <commit> <candidate number> <revision it is compared with> -> 0, or 1 (UNC_NOTE set)
# when a later commit whose rename detection git skipped deletes one of its files:
# that file may have moved, and the commit's lines would then be read in the wrong
# place; 2 on error. Such a commit is a candidate the check cannot verify. On the
# branch, any such deletion after the commit (its lines would look gone from the
# head); on main, before the revision it is compared with, the deletion of a file the
# head still has (one the branch deleted itself is gone either way: a squash that
# replaces a thousand files deletes the same ones, #399 verify round 16).
UNC_NOTE=""
unc_check() {
  local u main
  [ -s "$SCRATCH/unc" ] || return 0
  cand_keys "$2" && names_in "$BRANCH_SHA" "$SCRATCH/cp.z" "$SCRATCH/unc.h" && listing "$BRANCH_SHA" "$SCRATCH/ls.head" || return 2
  while IFS= read -r u; do
    [ "$u" != "$1" ] || continue
    GIT merge-base --is-ancestor "$u" "$1" 2>/dev/null; case $? in 0) continue ;; 1) ;; *) return 2 ;; esac
    main=0
    GIT merge-base --is-ancestor "$u" "$BRANCH_SHA" 2>/dev/null; rc=$?
    if [ "$rc" -eq 1 ]; then
      main=1
      GIT merge-base --is-ancestor "$u" "$3" 2>/dev/null; rc=$?
      case $rc in 0) ;; 1) continue ;; *) return 2 ;; esac
    elif [ "$rc" -ne 0 ]; then return 2; fi
    GIT rev-parse -q --verify "$u^1^{commit}" > /dev/null 2>&1 || continue
    names_in "$u^1" "$SCRATCH/cp.z" "$SCRATCH/unc.n" || return 2
    if LC_ALL=C awk -v del="$SCRATCH/unc.$u" -v main="$main" -v hp="$SCRATCH/unc.h" -v ls="$SCRATCH/ls.head" '
         BEGIN { while ((r = getline l < del) > 0) D[l] = 1; if (r < 0) exit 2
                 if (main == 1) {
                   while ((r = getline l < ls) > 0) L[l] = 1; if (r < 0) exit 2
                   while ((r = getline l < hp) > 0) { if (++q == 1) n = l; else { q = 0; if (n in L) alive[l] = 1 } }; if (r < 0) exit 2 } }
         NR % 2 == 1 { n = $0; next }
         (n in D) && (main != 1 || ($0 in alive)) { f = 1; exit } END { exit !f }' "$SCRATCH/unc.n"; then
      UNC_NOTE="git did not look for moves in $(short "$u") (more than 1000 files added and deleted), which deletes a file $(short "$1") touched; whether that file moved cannot be told (a higher diff.renameLimit does not change this check)"
      return 1
    fi
  done < "$SCRATCH/unc"
  return 0
}
ORPHANS="" ; k=0
set -- $SIDE_OF
for sha in $CANDIDATES; do
  side="$1"; shift
  if [ "$side" = land ]; then tgt="$LANDING"; else tgt="$BASELINE_SHA"; fi
  unc_check "$sha" "$k" "$tgt"; case $? in 0) ;; 1) skip "cannot verify $(short "$sha"): $UNC_NOTE" ;; *) skip "cannot verify $(short "$sha") (exit 2)" ;; esac
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
