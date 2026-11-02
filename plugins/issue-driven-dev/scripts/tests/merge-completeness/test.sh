#!/usr/bin/env bash
# test.sh — fixtures for check-merge-completeness.sh (PsychQuant/issue-driven-development#184)
#
# The gate detects commits on an issue's branch whose CONTENT did not land in
# the baseline (origin/<default>). The hard part is the squash-merge false
# positive: after a squash, every branch commit's patch-id differs from the
# squashed commit, so `git cherry` alone flags everything — the content-verify
# step must filter those out. The fixtures below ARE the spec for that step.
#
#   exit 0 = clean (no genuine orphan)
#   exit 3 = genuine orphan(s) found
#   exit 4 = skip: could not verify (a file the branch touched was moved or renamed,
#            SPEC.md's "Moves"; unresolvable
#            ref, a git or awk failure outside the landing step, an unreadable object,
#            a checked commit touching a path with a newline in its name, a partial
#            clone with git older than 2.45 or one whose missing blobs a check needs, a
#            file a candidate touched deleted later in a commit
#            where git skipped its detection); never clean, never a block
#
# Defenses no fixture pins (removing one still passes the suite; only these, checked
# by mutating each in rounds 13 and 14): the --literal-pathspecs and --full-tree flags,
# the error return when a prefix's landing search fails, the walk's fallback for a CR
# or LF in a changed path, -c core.fsmonitor=false, --end-of-options on ref
# resolution, the `|| skip` on CHERRY_DASH, and the error on a deleted path missing from
# the path index (it cannot happen while the index is built from the same listing). A failed listing of a commit's
# deleted paths is pinned only through awk, which refuses the missing file. Belt and
# braces that git already provides in these calls, so no fixture can tell them apart
# from their absence: --no-ext-diff, --no-textconv and --no-color on diff-tree
# (plumbing ignores diff.external, textconv and color config), --no-renames on
# diff-tree (plumbing does not detect renames by default), --no-pager (the output is
# never a terminal), and --diff-algorithm=myers and --indent-heuristic on the two-way
# diffs (fixture 128 sets another algorithm and turns the heuristic off, and no answer
# changes). Backstops behind another defense: pparse keeping only the listed paths
# (fixture 117 needs only that a landing commit have the head's files among the net
# change's paths, which fixtures 102, 102b and 130 pin), pparse giving up on a stray
# line inside a hunk (the pinned options leave none), pparse pairing equal lines at one
# offset (inside a -U0 hunk only a final-newline change puts them there, and the
# no-newline pairing covers it), file_of refusing a submodule (its pointer's line is
# unique, so the copy rule refuses it either way), and holds_by_copies refusing the
# merge-base itself (no line of the net change is in place there, which the copy rule
# needs already), and the paths given to the awk calls that read a file's repeated texts
# and a renamed file's old name through the environment rather than -v (round 15: a
# name -v decodes matches nothing, so the list of repeated texts comes out empty and the
# commit is refused, which in_rep, reading the name correctly, does too). Speed only:
# holds_by_copies refusing a unique failing line before it reads the commit's files, and
# refusing it again before single_changer reads the branch (the count pass refuses it
# too), and the check that more lines of the net change exist than fail (the check for a
# line the commit's own step brought needs one in place already). The same answers either way: whether the paths go on the command
# line (up to 64 KB) or into two trees filtered to them (round 14 ran the whole suite
# with the threshold at 0; fixtures 139-141 pin the filtered form); putting every list
# on the command line fails only at about 1 MB (macOS) or 2 MB (Linux) of names, which
# no fixture builds. Pinned by no fixture although they could matter: entry_of
# reporting an unreadable tree as an error (only a damaged repository gets there) and
# taking only a file or a submodule for an entry (a directory reaches it only at a path
# outside the net change); a commit's added or deleted whole path checked at the
# landing commit (the landing commit has every path the net change touches, so only a
# path outside the net change, which main itself changed before landing, gets there);
# the empty tree as the parent of a root commit (a root commit reaches the check only
# when the branch merged an unrelated history, and merge commits on the branch are
# outside what this suite builds); and the merge-base half of the net-change cache key
# (equivalent: the baseline is fixed for a run, so the merge-base is a function of the
# revision). Also unpinned: the note when the prefix search after a merge-base landing
# fails (it needs the check budget to run out inside that search), and the `! -e` /
# `! -L` tests before the trace file is written (noclobber already refuses an existing
# regular file; the tests matter only for a FIFO or a device, which a fixture cannot
# use without hanging). Round 14's other survivors got fixtures, each checked to fail
# on its mutant: renames at the tip (151), either entry check in confirm() (152, 152b),
# other branch commits' copies (153), the branch's rename since the merge-base (154),
# and counting copies at a merge commit (156). Round 15's mutants (fixtures 158-173 were
# written for its changes, each red on round 14 or on its mutant) leave unpinned:
# `write-tree --missing-ok` in the filtered trees (it matters only in a partial clone above
# 64 KB of paths), making SCRATCH absolute (macOS mktemp ignores a relative TMPDIR, so the
# suite cannot build one there), and keying the filtered-tree cache on the path list as
# well as the tree (the fixtures never filter one revision to two different lists, which
# the landing walk can do for the net changes of the branch and of a prefix). Round 16's
# mutants (fixtures 174-180 were written for its changes; 174-178 are red on round 15,
# 179-180 pin the accepted routes) leave unpinned the `CDPATH=` and backslash checks on
# the temp dir (macOS mktemp ignores a relative TMPDIR); round 17 replaced its rename
# records and its skipped-rename error. Round 17 (fixtures 181-195: 181-184, 186-187,
# 188b, 189, 191 and 195 are red on round 16; 185, 191, 193, 194 and 195 were red on round
# 17's own drafts; 188's small
# case is green on round 16, which wrote no index for a small branch; 190 keeps the move
# across two commits that round 16 found by one rename detection between two trees)
# leaves unpinned:
# pparse refusing a decoded name with a newline (has_lf keeps such names out of every
# list before a diff), a rename or copy header inside a diff (--no-renames keeps git from
# printing one), and a commit of main's own whose rename detection git skipped deleting a
# file the head still has (no fixture builds a thousand-file commit on main before the
# landing commit). Each of round 17's twelve mutants is caught: no deletions in the
# identities (190), no first rule on main (185), other_copies or single_changer by the key
# alone (181, 192), lines compared as numbers (187), the configured hook back on (188),
# no partial clone check (189), no skipped-detection check, or one on any main deletion,
# or round 16's error everywhere (186b, 186), no move over two commits (190), the tip's
# patch through the filtered trees (167). Round 18 (fixtures 196-212: 196-202 and 204-207
# are red on round 17; 197, 204, 205 and 207-212 were red on round 18's own drafts; 203
# pins main's own move, which round 16 missed) leaves unpinned: the
# head-equals-tip shortcut by the candidates' head names (round 16; a commit main took as a
# pick matches only when main already had the line it moved, so no fixture can tell), the
# join of a link at the end of a view and the link's merge-base file (each pairing of a
# deletion with the copies made before it covers the shapes that reach them), and the weak
# reading's alias rule (once a landed prefix that holds a copy and its original counts
# both names, no built history reaches the tip with nothing landed and a name main never
# changed). Each other mutant of round 18 is caught: a check that stops reading a pipe
# early (199), a reference dropped for any ancestor of the head (205), the tip by the
# head's names (204), the tip's or the landing commit's paths by name (204, 209), no
# same_files (205), the landing search reading the strong way in all three places (204),
# the weak reading never or always deferring to history (204, 191) or deciding by names
# where main changed the file (212, found on the draft by the first rename fuzzer), no pairing of a
# deletion with earlier copies (208), the oldest of two files winning a key (210), a
# reference's other names not wanted or given to another file (210, 211), the tip ignoring
# other names (210), no promisor check (200), hooks not off by name (206), no merge-base
# as an error (202), a path split on awk's subscript separator (201). Round 19 (fixtures
# 213-220: 213-216, 218 and 219 are red on round 18; 217 and 220 pin round 19's own rules,
# 220 against a mutant) leaves unpinned: the tip's route for a deleted name holding a file
# no head file has there (the landing commit's route is 216's), step 1's check that a file
# history puts at a name has a place of its own (step 3's, which 214 and 215 pin, gives the
# same answer), the reference's primary names freed once their file has a place elsewhere,
# history's exception narrowed to a head file at the reference name, and a content tie
# going to history (each reached by the round-18 reviewers' repros and the rename fuzzers,
# not by a fixture). Each other mutant of round 19 is caught: no check of a view against
# its revision's tree (213), the landing commit's deleted names by file only (216), a place
# the file already took not counting (214), deleted lines at the tip by the main name only
# (197 and 29 more), GIT_CONFIG kept (218), no partial clone filter check (219),
# same_files always passing (205). Round 20 (the maintainer's decision of 2026-11-01:
# moves are not judged; SPEC.md, Definition, "Moves"): fixtures 71, 105, 120-122, 128 (the
# rename case), 136, 138, 139, 143, 146, 151, 154, 158, 158b, 159, 174-177, 181-184, 188,
# 190-192, 195, 196b, 197-199, 203-205, 207-209, 212-216 now expect exit 4, and their
# assertions on the list are gone (their comments still describe the answers of rounds 16
# to 19, which followed files across moves); 99 (main archives the files after the squash)
# stays 0; 206 moved to the wide path, the only one that still builds a scratch index.
# Fixtures 221-229 pin round 20: 221a, 221c and 228 are red on rounds 17 and 19 (the first
# PR's commit listed, as every version since 3.5.0 does), 222, 223b, 224b and 226 on rounds
# 17 and 19 (an answer, not exit 4; 226's is 0 on round 19, the false clean its verify
# found). Mutants of round 20 caught: P0 over the candidates' paths only (226), a move in a
# commit of the branch taken as main's (227), commits at the tip despite a move (222, 224b),
# no second check after a merge of main (221a), the merges newest first (228), one listing
# for every landing commit (229), a move after the landing commit not judged (224a).
# Rounds 21 and 22 looked for shims, moves onto existing names, copies and renamed directories;
# each regressed histories without moves, and the maintainer decided on 2026-11-02 to read those
# by path as known limits: fixtures 230, 230b, 231, 237, 239, 240 and 242 pin the limits, 241 and
# 247 that no such move counts. 243, 244 and 248 pin renames inside the branch's merges; 232,
# 233, 235 and 245 the two Update-branch checks; rc_why checks the exit-4 reason.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$HERE/../../check-merge-completeness.sh"
. "$HERE/../../lib/assert-helpers.sh"

# Isolated temp repo per fixture; deterministic identity, quiet.
mk_repo() {
  local d; d="$(mktemp -d)"
  git -C "$d" init -q
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name t
  git -C "$d" config commit.gpgsign false
  printf 'base\n' > "$d/base.txt"
  git -C "$d" add -A && git -C "$d" commit -qm base
  # Fixtures reference `main` explicitly; machines with unset init.defaultBranch
  # (git default: master — most CI runners too) would 6/7 false-FAIL without
  # this self-sufficient rename (idempotent when already main). Refs #224.
  git -C "$d" branch -M main
  echo "$d"
}

run_helper() { # repo branch baseline  -> echoes exit code
  "${BASH:-bash}" "$HELPER" --repo "$1" --branch "$2" --baseline "$3" >/dev/null 2>&1
  echo $?
}

echo "merge-completeness gate"

# ── Fixture 1: genuine orphan — branch adds a file the baseline never got ──
R="$(mk_repo)"
git -C "$R" checkout -q -b feat
printf 'crash fix\n' > "$R/orphan.txt"
git -C "$R" add -A && git -C "$R" commit -qm "fix: crash (orphan)"
# main stays at base — the orphan never merged
assert_exit "fixture-1 genuine orphan flagged" 3 "$(run_helper "$R" feat main)"
OUT1=$("${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main 2>/dev/null)
assert_exit "fixture-1 renders the subject exactly" 0 \
  "$(printf '%s\n' "$OUT1" | grep -qFx "  $(git -C "$R" rev-parse --short feat)  \"fix: crash (orphan)\""; echo $?)"
rm -rf "$R"

# ── Fixture 2: squash false-positive — branch's content IS in main as a squash ──
R="$(mk_repo)"
git -C "$R" checkout -q -b feat
printf 'b\n' > "$R/b.txt"; git -C "$R" add -A && git -C "$R" commit -qm "add b"
printf 'c\n' > "$R/c.txt"; git -C "$R" add -A && git -C "$R" commit -qm "add c"
# main gets ONE squashed commit carrying both files (distinct sha/patch-id)
git -C "$R" checkout -q main
printf 'b\n' > "$R/b.txt"; printf 'c\n' > "$R/c.txt"
git -C "$R" add -A && git -C "$R" commit -qm "squash: add b+c"
assert_exit "fixture-2 squash content present -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 3: unresolvable branch -> skip (never block) ──
R="$(mk_repo)"
assert_exit "fixture-3 missing branch -> skip" 4 "$(run_helper "$R" does-not-exist main)"
rm -rf "$R"

# ── Fixture 4: mixed — one orphan + one already-present commit on same branch ──
R="$(mk_repo)"
git -C "$R" checkout -q -b feat
printf 'd\n' > "$R/d.txt"; git -C "$R" add -A && git -C "$R" commit -qm "add d (will land)"
printf 'e\n' > "$R/e.txt"; git -C "$R" add -A && git -C "$R" commit -qm "add e (orphan)"
git -C "$R" checkout -q main
printf 'd\n' > "$R/d.txt"; git -C "$R" add -A && git -C "$R" commit -qm "land d only"
# d is present in main, e is not -> exactly one genuine orphan -> flagged
assert_exit "fixture-4 partial-merge orphan flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 5 (DA-2): same FILE edited by >1 commit + squash → must NOT flag ──
# This is the common TDD branch shape. The old cherry-pick content-verify
# conflicts when replaying the intermediate same-file commit onto the squashed
# tip → false orphan. The line-presence verify must see all added lines present.
R="$(mk_repo)"
git -C "$R" checkout -q -b feat
printf 'line1\n'        > "$R/shared.txt"; git -C "$R" add -A && git -C "$R" commit -qm "shared: add line1"
printf 'line1\nline2\n' > "$R/shared.txt"; git -C "$R" add -A && git -C "$R" commit -qm "shared: add line2"
git -C "$R" checkout -q main
printf 'line1\nline2\n' > "$R/shared.txt"; git -C "$R" add -A && git -C "$R" commit -qm "squash: shared line1+line2"
assert_exit "fixture-5 same-file squash (DA-2) NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 6 (DA-1): branch ref deleted, resolve by persistent SHA (headRefOid) ──
# After merge GitHub deletes the head branch; idd-close must pass the head SHA
# (gh pr view --json headRefOid), which still resolves to the commit object.
R="$(mk_repo)"
git -C "$R" checkout -q -b feat
printf 'orphan2\n' > "$R/orphan2.txt"; git -C "$R" add -A && git -C "$R" commit -qm "orphan2"
SHA=$(git -C "$R" rev-parse feat)
git -C "$R" checkout -q main
git -C "$R" branch -D feat >/dev/null 2>&1   # branch gone, SHA still reachable
assert_exit "fixture-6 SHA input after branch deleted (DA-1) flagged" 3 "$(run_helper "$R" "$SHA" main)"
rm -rf "$R"

# ── Fixture 7 (R2): a path with a SPACE must not word-split into false orphans ──
# Old `for f in $files` split "sp ace.txt" → empty baseline content → landed
# commit mis-flagged. Same DA-2 false-positive class, retriggered by a space.
R="$(mk_repo)"
git -C "$R" checkout -q -b feat
printf 'l1\n'     > "$R/sp ace.txt"; git -C "$R" add -A && git -C "$R" commit -qm "spaced: l1"
printf 'l1\nl2\n' > "$R/sp ace.txt"; git -C "$R" add -A && git -C "$R" commit -qm "spaced: l2"
git -C "$R" checkout -q main
printf 'l1\nl2\n' > "$R/sp ace.txt"; git -C "$R" add -A && git -C "$R" commit -qm "squash: spaced"
assert_exit "fixture-7 spaced filename squash NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixtures 8–133 (#399): a squash keeps the branch's FINAL content, not each commit ──
# A line one branch commit adds and a later one rewrites exists in no final tree,
# and main may edit the branch's lines after the squash (#408: a release date
# changed by a follow-up commit). The gate answers "did the branch's content land":
# when the tip already has the head's content on every path the branch touched, it
# did; otherwise the gate finds the earliest baseline commit, the merge-base itself included, that
# holds the branch's whole net change (the landing commit) and checks each commit's lines
# against THAT, skipping lines the branch head itself no longer has. What main did after landing — a follow-up, a
# revert — is out of scope. Finding the landing commit must not accept what never
# landed, and no merge driver, diff driver or color setting may decide.


mk_rewrite_branch() { # repo -> feat: x added, then rewritten
  printf 'h1\nh2\nh3\n' > "$1/a.py"; git -C "$1" add -A && git -C "$1" commit -qm "a.py"
  git -C "$1" checkout -q -b feat
  printf 'h1\nh2\nh3\nx = 1\n' > "$1/a.py"; git -C "$1" commit -qam "add x"
  printf 'h1\nh2\nh3\nx = 2\n' > "$1/a.py"; git -C "$1" commit -qam "change x"
}
squash_feat() { git -C "$1" checkout -q main && git -C "$1" merge -q --squash feat >/dev/null 2>&1 && git -C "$1" commit -qm "squash feat"; }
edit_x() { printf 'h1\nh2\nh3\nx = 3\n' > "$1/a.py"; git -C "$1" commit -qam "follow-up edits the branch's line"; }
out_of() { "${BASH:-bash}" "$HELPER" --repo "$1" --branch "$2" --baseline "$3" 2>/dev/null; }
has() { printf '%s\n' "$1" | grep -qF -- "$2"; echo $?; }   # 0 = present
# The exit code and, for exit 4, which reason: "4 moved" (a move counts), "4 unc" (git did
# not look for moves), "4 other"; any other exit, its code (#399 verify round 21: the exit-4
# fixtures checked the code only, so a setup error passed as a move).
rc_why() { # repo branch baseline
  local out rc
  out="$("${BASH:-bash}" "$HELPER" --repo "$1" --branch "$2" --baseline "$3" 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -ne 4 ]; then echo "$rc"; return; fi
  case "$out" in
    *"was moved or renamed (in "*) echo "4 moved" ;;
    *"git did not look for moves"*) echo "4 unc" ;;
    *) echo "4 other" ;;
  esac
}

R="$(mk_repo)"; mk_rewrite_branch "$R"; squash_feat "$R"
assert_exit "fixture-8 rewritten line, squash -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

R="$(mk_repo)"; mk_rewrite_branch "$R"; squash_feat "$R"
printf 'h1\nh2\nh3\nx = 2\ny = 3\n' > "$R/a.py"; git -C "$R" commit -qam "follow-up on the same file"
assert_exit "fixture-9a squash + later follow-up adding to the same file -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 9b is the #408 shape: a follow-up edits the very line the branch added. Only the
# landing step can clear it — `x = 2` is in the branch head and not at the tip.
R="$(mk_repo)"; mk_rewrite_branch "$R"; squash_feat "$R"; edit_x "$R"
assert_exit "fixture-9b squash + follow-up editing the branch's line -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

R="$(mk_repo)"; mk_rewrite_branch "$R"
git -C "$R" checkout -q main
printf 'H1\nh2\nh3\n' > "$R/a.py"; git -C "$R" commit -qam "concurrent main edit"
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat (not rebased)"
assert_exit "fixture-10 non-rebased squash, main changed the same file -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

R="$(mk_repo)"; mk_rewrite_branch "$R"
printf 'orphan\n' > "$R/orphan11.txt"; git -C "$R" add -A && git -C "$R" commit -qm "orphan (never landed)"
git -C "$R" checkout -q main
git -C "$R" checkout -q feat~1 -- a.py && git -C "$R" commit -qm "land a.py only"
OUT11=$(out_of "$R" feat main); RC11=$?
assert_exit "fixture-11 rewrite shape + a genuine orphan -> flagged" 3 "$RC11"
assert_exit "fixture-11 lists the genuine orphan" 0 "$(has "$OUT11" 'orphan (never landed)')"
assert_exit "fixture-11 does not list the rewritten 'add x'" 1 "$(has "$OUT11" 'add x')"
assert_exit "fixture-11 note: the branch landed up to 'change x', the orphan checked at the tip" 0 "$(has "$OUT11" "the branch up to")"
assert_exit "fixture-11 note does not claim a revert" 1 "$(has "$OUT11" 'revert')"
rm -rf "$R"

# ── Fixture 12: at most 200 landing checks ──
# The walk goes forward from the merge-base (tried first) through first-parent
# commits that touch the branch's paths; here 198 or 199 of them come before the
# squash.
add_touching_commits() { # repo n — append n commits on main that rewrite a.py's first line
  local b p i blob tree
  b=$(git -C "$1" rev-parse 'main:base.txt'); p=$(git -C "$1" rev-parse main)
  for ((i = 0; i < $2; i++)); do
    blob=$(printf 'h1-%s\nh2\nh3\n' "$i" | git -C "$1" hash-object -w --stdin)
    tree=$(printf '100644 blob %s\tbase.txt\n100644 blob %s\ta.py\n' "$b" "$blob" | git -C "$1" mktree)
    p=$(git -C "$1" commit-tree "$tree" -p "$p" -m "noise $i")
  done
  git -C "$1" update-ref refs/heads/main "$p"
}
R="$(mk_repo)"; mk_rewrite_branch "$R"; add_touching_commits "$R" 198; squash_feat "$R"; edit_x "$R"
assert_exit "fixture-12a squash is the 200th check -> found" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"
R="$(mk_repo)"; mk_rewrite_branch "$R"; add_touching_commits "$R" 199; squash_feat "$R"; edit_x "$R"
OUT12=$(out_of "$R" feat main); RC12=$?
assert_exit "fixture-12b squash would be the 201st -> not tried, flagged" 3 "$RC12"
assert_exit "fixture-12b note says the budget ran out" 0 "$(has "$OUT12" 'budget of 200')"
rm -rf "$R"

# ── Fixture 13: a revert after landing is main's own history — out of scope ──
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'f1\n' > "$R/f.txt"; git -C "$R" add -A && git -C "$R" commit -qm "add f"
printf 'f1\nf2\n' > "$R/f.txt"; git -C "$R" commit -qam "extend f"
squash_feat "$R"; git -C "$R" revert --no-edit HEAD >/dev/null 2>&1
assert_exit "fixture-13 squash then revert -> NOT flagged (landed; revert out of scope)" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 14: a baseline commit that is not a descendant of the merge-base ──
# feat forks from a side branch, undoes it (v=1) and adds w.txt; main had a
# parallel commit that added the same w.txt before merging side. That parallel
# commit is reachable from main but not from the merge-base, and measured against
# its own (older) merge-base the branch's net change — w.txt only — is already in
# it. The restore of v=1 never landed.
R="$(mk_repo)"
printf 'v = 1\n' > "$R/v.txt"; git -C "$R" add -A && git -C "$R" commit -qm "v=1"
git -C "$R" checkout -q -b side; printf 'v = 2\n' > "$R/v.txt"; git -C "$R" commit -qam "side: v=2"
git -C "$R" checkout -q -b feat; printf 'v = 1\n' > "$R/v.txt"; printf 'w\n' > "$R/w.txt"
git -C "$R" add -A && git -C "$R" commit -qm "restore v=1 + add w (restore never landed)"
git -C "$R" checkout -q main; printf 'w\n' > "$R/w.txt"; git -C "$R" add -A && git -C "$R" commit -qm "parallel main commit adds w"
git -C "$R" merge -q --no-ff -m "merge side" side
assert_exit "fixture-14 non-descendant baseline commit does not count -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixtures 15, 17, 18: no merge driver may decide the landing step ──
# `merge=keepours` resolves every conflict to main's version, which would make a
# branch change that never landed look contained. The driver can be named in the
# tree's .gitattributes (15), in .git/info/attributes (17), or by merge.default (18).
mk_keepours() { # repo -> feat sets v=2, main sets v=9; returns nothing
  printf 'v = 1\n' > "$1/a.py"; git -C "$1" add -A && git -C "$1" commit -qm "a.py"
  git -C "$1" config merge.keepours.driver true
  git -C "$1" checkout -q -b feat; printf 'v = 2\n' > "$1/a.py"; git -C "$1" commit -qam "fix: v=2 (never landed)"
  git -C "$1" checkout -q main; printf 'v = 9\n' > "$1/a.py"; git -C "$1" commit -qam "main: v=9"
}
R="$(mk_repo)"; printf 'a.py merge=keepours\n' > "$R/.gitattributes"; git -C "$R" add -A && git -C "$R" commit -qm attrs
mk_keepours "$R"
assert_exit "fixture-15 keep-ours driver in .gitattributes ignored -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"
R="$(mk_repo)"; mk_keepours "$R"; printf 'a.py merge=keepours\n' > "$R/.git/info/attributes"
assert_exit "fixture-17 keep-ours driver in .git/info/attributes ignored -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"
R="$(mk_repo)"; mk_keepours "$R"; git -C "$R" config merge.default keepours
assert_exit "fixture-18 keep-ours driver via merge.default ignored -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 16: main overwrote PART of a landed squash — out of scope ──
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'A\n' > "$R/g.txt"; git -C "$R" add -A && git -C "$R" commit -qm "add A"
printf 'A\nB\n' > "$R/g.txt"; git -C "$R" commit -qam "add B"
squash_feat "$R"; printf 'A\n' > "$R/g.txt"; git -C "$R" commit -qam "later edit drops B"
assert_exit "fixture-16 partial overwrite after landing -> NOT flagged (out of scope)" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 19: a commit that restores a merge-base value never landed ──
# P sets debug and adds RETRIES; O sets the level back to info. Main took P only.
# The branch's net change (RETRIES) is in main, so a landing commit exists; O's
# line is in the branch head and not in that commit.
R="$(mk_repo)"
printf 'LOG = "info"\na\nb\nc\nd\ne\n' > "$R/cfg.py"; git -C "$R" add -A && git -C "$R" commit -qm cfg
git -C "$R" checkout -q -b feat
printf 'LOG = "debug"\na\nb\nc\nd\ne\nRETRIES = 3\n' > "$R/cfg.py"; git -C "$R" commit -qam "P: debug + retries"
printf 'LOG = "info"\na\nb\nc\nd\ne\nRETRIES = 3\n' > "$R/cfg.py"; git -C "$R" commit -qam "O: back to info (never landed)"
git -C "$R" checkout -q main
printf 'LOG = "debug"\na\nb\nc\nd\ne\nRETRIES = 3\n' > "$R/cfg.py"; git -C "$R" commit -qam "land P only"
OUT19=$(out_of "$R" feat main); RC19=$?
assert_exit "fixture-19 dropped restore-to-merge-base commit -> flagged" 3 "$RC19"
assert_exit "fixture-19 lists O" 0 "$(has "$OUT19" 'O: back to info')"
assert_exit "fixture-19 note names the landing commit" 0 "$(has "$OUT19" "landed in")"
assert_exit "fixture-19 note names its subject" 0 "$(has "$OUT19" "land P only")"
rm -rf "$R"

# ── Fixture 20: diff settings must not hide added lines ──
# An external diff, a textconv that prints nothing, or forced color all turn a
# porcelain patch into something with no `+` lines.
mk_orphan_x() { # repo -> feat adds x=1 then x=2; main never gets x
  printf 'v = 0\n' > "$1/a.py"; git -C "$1" add -A && git -C "$1" commit -qm "a.py"
  git -C "$1" checkout -q -b feat; printf 'v = 0\nx = 1\n' > "$1/a.py"; git -C "$1" commit -qam "add x (never landed)"
  printf 'v = 0\nx = 1\ny = 1\n' > "$1/a.py"; git -C "$1" commit -qam "add y (never landed)"
  git -C "$1" checkout -q main; printf 'o\n' > "$1/o.txt"; git -C "$1" add -A && git -C "$1" commit -qm "unrelated main work"
}
R="$(mk_repo)"; mk_orphan_x "$R"; git -C "$R" config diff.external /usr/bin/true
assert_exit "fixture-20a diff.external set -> orphan still flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"
R="$(mk_repo)"; mk_orphan_x "$R"; git -C "$R" config color.ui always
assert_exit "fixture-20b color.ui=always -> orphan still flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"
R="$(mk_repo)"; printf '*.py diff=blank\n' > "$R/.gitattributes"; git -C "$R" add -A && git -C "$R" commit -qm attrs
mk_orphan_x "$R"; git -C "$R" config diff.blank.textconv true
assert_exit "fixture-20c textconv that prints nothing -> orphan still flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 21: a file moved by copy-then-delete that never landed ──
R="$(mk_repo)"
printf 'p1\np2\np3\n' > "$R/old.py"; git -C "$R" add -A && git -C "$R" commit -qm old
git -C "$R" checkout -q -b feat
cp "$R/old.py" "$R/new.py"; git -C "$R" add -A && git -C "$R" commit -qm "move 1/2: add new.py"
git -C "$R" rm -q old.py && git -C "$R" commit -qm "move 2/2: drop old.py"
git -C "$R" checkout -q main
assert_exit "fixture-21 copy-then-delete never landed -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 22: a commit that still has a path the branch deleted is not where it landed ──
# feat deletes d.txt and adds L to e.txt. Main's C1 modified d.txt and has L;
# C2 changed L. C1 still has d.txt, so the branch's deletion is not in place there.
# (Rounds 4-11 asked a three-way merge, which writes C1's tree for this
# modify/delete conflict, so only its exit status said no.)
R="$(mk_repo)"
printf 'd1\n' > "$R/d.txt"; printf 'e1\n' > "$R/e.txt"; git -C "$R" add -A && git -C "$R" commit -qm de
git -C "$R" checkout -q -b feat
git -C "$R" rm -q d.txt; printf 'e1\nL\n' > "$R/e.txt"; git -C "$R" add -A && git -C "$R" commit -qm "rm d, add L"
git -C "$R" checkout -q main
printf 'd1\nd2\n' > "$R/d.txt"; printf 'e1\nL\n' > "$R/e.txt"; git -C "$R" commit -qam C1
printf 'e1\nL2\n' > "$R/e.txt"; git -C "$R" commit -qam C2
assert_exit "fixture-22 modify/delete conflict is not landing -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 23: stacked branch — the merge-base is an older commit of a side branch ──
# feat forks from side~1; side gets one more commit and is merged with a merge
# commit; feat is squashed; a follow-up edits feat's line. The merge commit and
# the squash descend from the merge-base even though the merge's second parent
# is ahead of it.
R="$(mk_repo)"; printf 'h1\nh2\nh3\n' > "$R/a.py"; git -C "$R" add -A && git -C "$R" commit -qm "a.py"
git -C "$R" checkout -q -b side; printf 's1\n' > "$R/s.txt"; git -C "$R" add -A && git -C "$R" commit -qm s1
git -C "$R" checkout -q -b feat
printf 'h1\nh2\nh3\nx = 1\n' > "$R/a.py"; git -C "$R" commit -qam "add x"
printf 'h1\nh2\nh3\nx = 2\n' > "$R/a.py"; git -C "$R" commit -qam "change x"
git -C "$R" checkout -q side; printf 's1\ns2\n' > "$R/s.txt"; git -C "$R" commit -qam s2
git -C "$R" checkout -q main; git -C "$R" merge -q --no-ff -m "merge side" side
squash_feat "$R"; edit_x "$R"
assert_exit "fixture-23 stacked branch squash + follow-up -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 24: a file the branch added and later deleted is not looked for ──
# lost.txt is gone at the branch head, so its lines are superseded; main edited the
# branch's file after landing and then restored it.
R="$(mk_repo)"; mk_rewrite_branch "$R"
printf 'h1\nh2\nh3\nx = 2\nz = 1\n' > "$R/a.py"; git -C "$R" commit -qam "add z"
printf 'gone\n' > "$R/lost.txt"; git -C "$R" add -A && git -C "$R" commit -qm "add lost"
git -C "$R" rm -q lost.txt && git -C "$R" commit -qm "drop lost"
squash_feat "$R"
printf 'h1\nh2\nh3\nx = 2\n' > "$R/a.py"; git -C "$R" commit -qam "main drops z after landing"
printf 'h1\nh2\nh3\nx = 2\nz = 1\n' > "$R/a.py"; git -C "$R" commit -qam "main restores z"
assert_exit "fixture-24 landed branch with a superseded file -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 25: a non-ASCII path must reach cat-file as the real path ──
# core.quotePath (on by default) turns 中文.txt into "\344\270\255..." in
# --name-only output. Looking that up finds nothing on BOTH sides: the head looks
# empty, every line looks superseded, and a genuine orphan in that file vanishes.
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'q1\n' > "$R/中文.txt"; git -C "$R" add -A && git -C "$R" commit -qm "add q1"
printf 'q1\nq2\n' > "$R/中文.txt"; git -C "$R" commit -qam "add q2"
squash_feat "$R"; printf 'q1\nq2\nq3\n' > "$R/中文.txt"; git -C "$R" commit -qam "follow-up adds q3"
assert_exit "fixture-25a non-ASCII path squash -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'q1\n' > "$R/中文.txt"; git -C "$R" add -A && git -C "$R" commit -qm "add q1 (never landed)"
git -C "$R" checkout -q main
assert_exit "fixture-25b orphan in a non-ASCII path -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 26: a file without a final newline must not run into the next one ──
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'k1' > "$R/k.txt"; printf 'm1\n' > "$R/m.txt"; git -C "$R" add -A && git -C "$R" commit -qm "add k + m"
printf 'k1\nk2' > "$R/k.txt"; git -C "$R" commit -qam "extend k"
squash_feat "$R"
assert_exit "fixture-26 squash touching a file with no final newline -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 27: no merge driver runs and nothing is written ──
# Round 12 runs no merge at all, so these hold trivially; they stay as guards.
# A driver that would run leaves a sentinel. It is named by the tree's
# .gitattributes and defined in the repo config (27a), or chosen by merge.default
# in the user's global config (27b), the system config (27c) or config passed down
# through the environment (27d). None may run, and the helper must not leave
# objects in the repository (27e).
mk_sentinel_repo() { # repo sentinel -> keepours-shaped branch; driver = touch sentinel
  mk_keepours "$1"
  git -C "$1" config merge.sentinel.driver "touch '$2'"
}
S27="$(mktemp -d)/ran"
R="$(mk_repo)"; printf 'a.py merge=sentinel\n' > "$R/.gitattributes"; git -C "$R" add -A && git -C "$R" commit -qm attrs
mk_sentinel_repo "$R" "$S27"
assert_exit "fixture-27a driver named in .gitattributes -> flagged" 3 "$(run_helper "$R" feat main)"
assert_exit "fixture-27a the driver did not run" 1 "$([ -e "$S27" ]; echo $?)"
rm -rf "$R" "$S27"
H27="$(mktemp -d)"
printf '[merge]\n\tdefault = sentinel\n[merge "sentinel"]\n\tdriver = touch %s\n' "'$S27'" > "$H27/gitconfig"
R="$(mk_repo)"; mk_keepours "$R"
assert_exit "fixture-27b merge.default in the global config -> flagged" 3 "$(GIT_CONFIG_GLOBAL="$H27/gitconfig" run_helper "$R" feat main)"
assert_exit "fixture-27b the driver did not run" 1 "$([ -e "$S27" ]; echo $?)"
rm -f "$S27"
assert_exit "fixture-27c merge.default in the system config -> flagged" 3 "$(GIT_CONFIG_SYSTEM="$H27/gitconfig" run_helper "$R" feat main)"
assert_exit "fixture-27c the driver did not run" 1 "$([ -e "$S27" ]; echo $?)"
rm -f "$S27"
assert_exit "fixture-27d merge.default passed through the environment -> flagged" 3 \
  "$(GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=merge.default GIT_CONFIG_VALUE_0=sentinel \
     GIT_CONFIG_KEY_1=merge.sentinel.driver GIT_CONFIG_VALUE_1="touch '$S27'" run_helper "$R" feat main)"
assert_exit "fixture-27d the driver did not run" 1 "$([ -e "$S27" ]; echo $?)"
rm -rf "$R" "$H27" "$(dirname "$S27")"
R="$(mk_repo)"; mk_rewrite_branch "$R"; squash_feat "$R"; edit_x "$R"
B27=$(git -C "$R" count-objects | cut -d' ' -f1)
run_helper "$R" feat main >/dev/null
assert_exit "fixture-27e no objects left in the repository" 0 "$([ "$(git -C "$R" count-objects | cut -d' ' -f1)" = "$B27" ]; echo $?)"
rm -rf "$R"

# ── Fixture 27f–j: the environment and attributes change nothing ──
# Written for the scratch repository rounds 4-11 ran merge-tree in: GIT_COMMON_DIR
# would point it at the user's own, GIT_OBJECT_DIRECTORY would send writes into the
# user's store, GIT_CONFIG_PARAMETERS carries `git -c` config.
S27="$(mktemp -d)/ran"
R="$(mk_repo)"; mk_sentinel_repo "$R" "$S27"
GIT_COMMON_DIR="$R/.git" run_helper "$R" feat main >/dev/null
assert_exit "fixture-27f the repository's driver did not run" 1 "$([ -e "$S27" ]; echo $?)"
assert_exit "fixture-27f GIT_COMMON_DIR leaves the repository non-bare" 0 \
  "$([ "$(git -C "$R" rev-parse --is-bare-repository)" = false ]; echo $?)"
B27=$(git -C "$R" count-objects | cut -d' ' -f1)
GIT_OBJECT_DIRECTORY="$R/.git/objects" run_helper "$R" feat main >/dev/null
assert_exit "fixture-27g GIT_OBJECT_DIRECTORY gets no objects" 0 \
  "$([ "$(git -C "$R" count-objects | cut -d' ' -f1)" = "$B27" ]; echo $?)"
rm -rf "$R"
R="$(mk_repo)"; mk_keepours "$R"
# Control (needs merge-tree --write-tree in the git running this suite): the same
# config through `git -c` does run the driver in the repository, so the assert below
# is not vacuous.
if git -C "$R" merge-tree --write-tree main main >/dev/null 2>&1; then
  git -C "$R" -c merge.default=sentinel -c "merge.sentinel.driver=touch '$S27'" merge-tree --write-tree main feat >/dev/null 2>&1
  assert_exit "fixture-27h control: the driver runs when config reaches merge-tree" 0 "$([ -e "$S27" ]; echo $?)"
  rm -f "$S27"
fi
GIT_CONFIG_PARAMETERS="'merge.default'='sentinel' 'merge.sentinel.driver'='touch $S27'" run_helper "$R" feat main >/dev/null
assert_exit "fixture-27h GIT_CONFIG_PARAMETERS driver did not run" 1 "$([ -e "$S27" ]; echo $?)"
rm -rf "$R" "$(dirname "$S27")"
# merge=union keeps both sides of a conflict, so a deletion that never landed can
# look contained in C; the lines are then checked at C, where Z still is, instead
# of at the tip, where it was changed. Attributes from the user's XDG file or from
# GIT_ATTR_SOURCE must not reach the scratch repo.
mk_union_shape() { # repo -> feat drops X and adds Z; main rewrote X, added Z, then changed Z
  printf 'keep\nX\n' > "$1/a.txt"; printf 'b0\n' > "$1/b.txt"; git -C "$1" add -A && git -C "$1" commit -qm ab
  git -C "$1" checkout -q -b feat
  printf 'keep\n' > "$1/a.txt"; printf 'b0\nZ\n' > "$1/b.txt"; git -C "$1" commit -qam "drop X, add Z (X never dropped on main)"
  git -C "$1" checkout -q main
  printf 'keep\nY\n' > "$1/a.txt"; printf 'b0\nZ\n' > "$1/b.txt"; git -C "$1" commit -qam "C: X->Y, add Z"
  printf 'b0\nZ2\n' > "$1/b.txt"; git -C "$1" commit -qam "D: Z->Z2"
}
X27="$(mktemp -d)"; mkdir -p "$X27/git"; printf '* merge=union\n' > "$X27/git/attributes"
R="$(mk_repo)"; mk_union_shape "$R"
RC27=$(run_helper "$R" feat main)
assert_exit "fixture-27i merge=union from the XDG attributes file -> same answer as without" "$RC27" "$(XDG_CONFIG_HOME="$X27" run_helper "$R" feat main)"
U27=$(printf '* merge=union\n' | git -C "$R" hash-object -w --stdin)
T27=$(printf '100644 blob %s\t.gitattributes\n' "$U27" | git -C "$R" mktree)
assert_exit "fixture-27j merge=union via GIT_ATTR_SOURCE -> same answer as without" "$RC27" "$(GIT_ATTR_SOURCE="$T27" run_helper "$R" feat main)"
rm -rf "$R" "$X27"

# ── Fixture 28: a branch commit restored a merge-base value; main edits it after landing ──
# The squash took the whole branch, so the branch landed there. The follow-up also
# "holds the net change" (the restored line is net-unchanged), but it is not where
# the branch landed and must not be the commit the lines are checked against.
R="$(mk_repo)"
printf 'timeout = 30\na\nb\nc\nd\ne\nf\ng\nh\n' > "$R/cfg.py"; git -C "$R" add -A && git -C "$R" commit -qm cfg
git -C "$R" checkout -q -b feat
printf 'timeout = 60\na\nb\nc\nd\ne\nf\ng\nh\n' > "$R/cfg.py"; git -C "$R" commit -qam "try timeout 60"
printf 'timeout = 60\na\nb\nc\nd\ne\nf\ng\nh\nn = 1\n' > "$R/cfg.py"; git -C "$R" commit -qam "add n"
git -C "$R" revert --no-edit HEAD~1 >/dev/null 2>&1
squash_feat "$R"
printf 'timeout = 45\na\nb\nc\nd\ne\nf\ng\nh\nn = 1\n' > "$R/cfg.py"; git -C "$R" commit -qam "follow-up: timeout 45"
OUT28=$(out_of "$R" feat main); RC28=$?
assert_exit "fixture-28 restored line edited after landing -> NOT flagged" 0 "$RC28"
rm -rf "$R"

# ── Fixtures 29, 30: one genuine orphan must not drag main's later edits into the list ──
# The whole branch never landed, but everything before the orphan did. Those
# commits are checked where they landed; only the orphan is listed.
R="$(mk_repo)"; mk_rewrite_branch "$R"; squash_feat "$R"
git -C "$R" checkout -q feat; printf 'o\n' > "$R/o29.txt"; git -C "$R" add -A && git -C "$R" commit -qm "orphan29 (never landed)"
git -C "$R" checkout -q main; edit_x "$R"
OUT29=$(out_of "$R" feat main); RC29=$?
assert_exit "fixture-29 9b shape + orphan -> flagged" 3 "$RC29"
assert_exit "fixture-29 lists the orphan" 0 "$(has "$OUT29" 'orphan29')"
assert_exit "fixture-29 does not list 'change x' (main edited it after landing)" 1 "$(has "$OUT29" 'change x')"
rm -rf "$R"
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'A\n' > "$R/g.txt"; git -C "$R" add -A && git -C "$R" commit -qm "add A"
printf 'A\nB\n' > "$R/g.txt"; git -C "$R" commit -qam "add B"
squash_feat "$R"; printf 'A\n' > "$R/g.txt"; git -C "$R" commit -qam "later edit drops B"
git -C "$R" checkout -q feat; printf 'o\n' > "$R/o30.txt"; git -C "$R" add -A && git -C "$R" commit -qm "orphan30 (never landed)"
git -C "$R" checkout -q main
OUT30=$(out_of "$R" feat main); RC30=$?
assert_exit "fixture-30 16 shape + orphan -> flagged" 3 "$RC30"
assert_exit "fixture-30 lists the orphan" 0 "$(has "$OUT30" 'orphan30')"
assert_exit "fixture-30 does not list 'add B' (main dropped it after landing)" 1 "$(has "$OUT30" 'add B')"
rm -rf "$R"

# ── Fixture 31: a submodule pointer is a gitlink, not a blob ──
G1=1111111111111111111111111111111111111111; G2=2222222222222222222222222222222222222222; G3=3333333333333333333333333333333333333333
mk_gitlink() { git -C "$1" update-index --add --cacheinfo "160000,$2,sub" && git -C "$1" commit -qm "$3"; }
R="$(mk_repo)"; mk_gitlink "$R" "$G1" "sub at 1"
git -C "$R" checkout -q -b feat; mk_gitlink "$R" "$G2" "bump sub (never landed)"
git -C "$R" checkout -q main; printf 'o\n' > "$R/o.txt"; git -C "$R" add o.txt && git -C "$R" commit -qm "unrelated main work"
assert_exit "fixture-31a dropped submodule bump -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"
R="$(mk_repo)"; mk_gitlink "$R" "$G1" "sub at 1"
git -C "$R" checkout -q -b feat; mk_gitlink "$R" "$G2" "bump sub to 2"; mk_gitlink "$R" "$G3" "bump sub to 3"
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat >/dev/null 2>&1; git -C "$R" commit -qm "squash feat"
assert_exit "fixture-31b landed submodule bumps -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 32: a file git treats as binary must still show its added lines ──
mk_binaryish() { # repo attrs-line-or-empty file nul? -> feat adds ORPHAN_LINE to file, never landed
  [ -z "$2" ] || { printf '%s\n' "$2" > "$1/.gitattributes"; git -C "$1" add -A && git -C "$1" commit -qm attrs; }
  if [ "${4:-}" = nul ]; then printf 'a\000b\n' > "$1/$3"; else printf 'a\n' > "$1/$3"; fi
  git -C "$1" add -A && git -C "$1" commit -qm "$3"
  git -C "$1" checkout -q -b feat
  if [ "${4:-}" = nul ]; then printf 'a\000b\nORPHAN_LINE = 1\n' > "$1/$3"; else printf 'a\nORPHAN_LINE = 1\n' > "$1/$3"; fi
  git -C "$1" commit -qam "orphan in $3 (never landed)"
  git -C "$1" checkout -q main; printf 'o\n' > "$1/o.txt"; git -C "$1" add o.txt && git -C "$1" commit -qm "unrelated main work"
}
R="$(mk_repo)"; mk_binaryish "$R" '*.cfg -diff' x.cfg
assert_exit "fixture-32a -diff attribute -> orphan still flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"
R="$(mk_repo)"; mk_binaryish "$R" '*.pbx binary' x.pbx
assert_exit "fixture-32b binary attribute -> orphan still flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"
R="$(mk_repo)"; mk_binaryish "$R" '' n.dat nul
assert_exit "fixture-32c file with a NUL byte -> orphan still flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 33: an added line that itself starts with ++ is still an added line ──
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'int i;\n' > "$R/c.c"; git -C "$R" add -A && git -C "$R" commit -qm "c.c"
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat >/dev/null 2>&1; git -C "$R" commit -qm "squash c.c"
git -C "$R" checkout -q feat; printf 'int i;\n++i;\n' > "$R/c.c"; git -C "$R" commit -qam "increment (never landed)"
git -C "$R" checkout -q main
assert_exit "fixture-33 dropped commit adding a '++' line -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 34: a branch with no net change since the merge-base landed at the merge-base ──
# feat merged main after its squash, so the merge-base is the squash; main then
# edited the branch's line. Nothing of feat is missing.
R="$(mk_repo)"; mk_rewrite_branch "$R"; squash_feat "$R"
git -C "$R" checkout -q feat; git -C "$R" merge -q --no-edit main >/dev/null 2>&1
git -C "$R" checkout -q main; edit_x "$R"
assert_exit "fixture-34 branch with no net change after merging main -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

R="$(mk_repo)"; printf 'L = 0\na\nb\n' > "$R/l.py"; git -C "$R" add -A && git -C "$R" commit -qm l
git -C "$R" checkout -q -b feat
printf 'L = 1\na\nb\n' > "$R/l.py"; git -C "$R" commit -qam "try L = 1"
printf 'L = 0\na\nb\n' > "$R/l.py"; git -C "$R" commit -qam "back to L = 0"
git -C "$R" checkout -q main; printf 'L = 2\na\nb\n' > "$R/l.py"; git -C "$R" commit -qam "main: L = 2"
assert_exit "fixture-34b change then change back, main edits the line later -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 35: a shallow clone ──
R="$(mk_repo)"; mk_rewrite_branch "$R"; squash_feat "$R"; edit_x "$R"
SH35="$(mktemp -d)"; git clone -q --depth 3 --no-single-branch "file://$R" "$SH35/c" 2>/dev/null
assert_exit "fixture-35 #408 shape in a shallow clone -> NOT flagged" 0 \
  "$(run_helper "$SH35/c" origin/feat origin/main)"
rm -rf "$R" "$SH35"

# ── Fixture 36: a SHA-256 repository ──
R="$(mktemp -d)"
if git -C "$R" init -q --object-format=sha256 2>/dev/null; then
  git -C "$R" config user.email t@t.t; git -C "$R" config user.name t; git -C "$R" config commit.gpgsign false
  printf 'base\n' > "$R/base.txt"; git -C "$R" add -A && git -C "$R" commit -qm base; git -C "$R" branch -M main
  mk_rewrite_branch "$R"; squash_feat "$R"; edit_x "$R"
  assert_exit "fixture-36 #408 shape in a SHA-256 repo -> NOT flagged" 0 "$(run_helper "$R" feat main)"
fi
rm -rf "$R"

# ── Fixture 37: the head side keeps files apart too ──
# The orphan adds k.txt without a final newline and m.txt; glued together, the
# head would read "k1m1" and both lines would look superseded.
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'k1' > "$R/k.txt"; printf 'm1\n' > "$R/m.txt"; git -C "$R" add -A && git -C "$R" commit -qm "add k + m (never landed)"
git -C "$R" checkout -q main
assert_exit "fixture-37 orphan touching a file with no final newline -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 38: a side-branch commit whose content main dropped at the merge ──
# side made feat's change (plus g.txt); main merged side with `-s ours`, so the
# change never reached main. Only first-parent commits are where main's content is.
R="$(mk_repo)"; printf 'a\n' > "$R/f.txt"; git -C "$R" add -A && git -C "$R" commit -qm f
git -C "$R" checkout -q -b side; printf 'a\nf\n' > "$R/f.txt"; printf 'g\n' > "$R/g.txt"; git -C "$R" add -A && git -C "$R" commit -qm "side: f + g"
git -C "$R" checkout -q main; git -C "$R" checkout -q -b feat; printf 'a\nf\n' > "$R/f.txt"; git -C "$R" commit -qam "feat: f (never landed)"
git -C "$R" checkout -q main; git -C "$R" merge -q -s ours --no-edit side >/dev/null 2>&1
assert_exit "fixture-38 change dropped by a -s ours merge -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

R="$(mk_repo)"; printf 'a\nb\nc\nd\ne\n' > "$R/f.txt"; git -C "$R" add -A && git -C "$R" commit -qm f
git -C "$R" checkout -q -b side; printf 'a\nb\nc\nd\ne\nf\n' > "$R/f.txt"; printf 'g\n' > "$R/g.txt"; git -C "$R" add -A && git -C "$R" commit -qm "side: f + g"
git -C "$R" checkout -q main; git -C "$R" checkout -q -b feat; printf 'a\nb\nc\nd\ne\nf\n' > "$R/f.txt"; git -C "$R" commit -qam "feat: f (never landed)"
git -C "$R" checkout -q main; printf 'A\nb\nc\nd\ne\n' > "$R/f.txt"; git -C "$R" commit -qam "main: A"
git -C "$R" merge -q --no-commit side >/dev/null 2>&1; printf 'A\nb\nc\nd\ne\nz\n' > "$R/f.txt"; git -C "$R" add -A && git -C "$R" commit -qm "merge side, f replaced by z"
assert_exit "fixture-38b change dropped by an evil merge -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 39: a path with a newline in its name cannot be checked -> skip (4) ──
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'n1\n' > "$R/$(printf 'a\nb.txt')"; git -C "$R" add -A && git -C "$R" commit -qm "newline name"
git -C "$R" checkout -q main
assert_exit "fixture-39 path with a newline -> skip, not clean" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 40: commit subjects are untrusted text ──
# A squash's subject is the PR title. Control bytes must not reach the output, and
# printing it must not run the user's signature-verification program.
R="$(mk_repo)"; mk_rewrite_branch "$R"; squash_feat "$R"
git -C "$R" commit -q --amend -m "$(printf 'squash\r\033[2K\302\2332K\342\200\256all clear\342\201\246')"
git -C "$R" checkout -q feat; printf 'o\n' > "$R/o40.txt"; git -C "$R" add -A && git -C "$R" commit -qm "orphan40"
git -C "$R" checkout -q main
OUT40=$(out_of "$R" feat main)
assert_exit "fixture-40a no control bytes in the output" 1 \
  "$(printf '%s' "$OUT40" | LC_ALL=C grep -q "$(printf '[\r\033]')"; echo $?)"
assert_exit "fixture-40a no C1 control or bidi override in the output" 1 \
  "$(printf '%s' "$OUT40" | LC_ALL=C grep -q -e "$(printf '\302\233')" -e "$(printf '\342\200\256')" -e "$(printf '\342\201\246')"; echo $?)"
# A commit carrying a (fake) signature, and log.showSignature pointing at a program
# that leaves a sentinel.
G40="$(mktemp -d)"; printf '#!/bin/sh\ntouch "%s/ran"\nexit 1\n' "$G40" > "$G40/gpg"; chmod +x "$G40/gpg"
SIGNED=$(git -C "$R" cat-file commit main | awk 'NR == 1 { print; next } !done && /^committer / { print; print "gpgsig -----BEGIN PGP SIGNATURE-----"; print " Zm9v"; print " -----END PGP SIGNATURE-----"; done = 1; next } { print }' \
  | git -C "$R" hash-object -t commit -w --stdin)
git -C "$R" update-ref refs/heads/main "$SIGNED"
git -C "$R" config log.showSignature true; git -C "$R" config gpg.program "$G40/gpg"
out_of "$R" feat main >/dev/null
assert_exit "fixture-40b printing subjects does not run gpg.program" 1 "$([ -e "$G40/ran" ]; echo $?)"
rm -rf "$R" "$G40"

# ── Fixture 41: a path that ends in CR is its own path, not its CR-less sibling ──
# Line readers drop a trailing CR, so "x.txt\r" must never be looked up as x.txt.
R="$(mk_repo)"; printf 'A\n' > "$R/x.txt"; git -C "$R" add -A && git -C "$R" commit -qm x
git -C "$R" checkout -q -b feat; printf 'SECRET = 1\n' > "$R/$(printf 'x.txt\r')"; git -C "$R" add -A && git -C "$R" commit -qm "x.txt<CR> (never landed)"
git -C "$R" checkout -q main
assert_exit "fixture-41 orphan in a path ending in CR -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 42: main breaks and then restores the hold after landing ──
# Fixture 28's shape; afterwards main changes n and reverts that. The branch landed
# at the squash, the earliest commit holding its net change.
R="$(mk_repo)"
printf 'timeout = 30\na\nb\nc\nd\ne\nf\ng\nh\n' > "$R/cfg.py"; git -C "$R" add -A && git -C "$R" commit -qm cfg
git -C "$R" checkout -q -b feat
printf 'timeout = 60\na\nb\nc\nd\ne\nf\ng\nh\n' > "$R/cfg.py"; git -C "$R" commit -qam "try timeout 60"
printf 'timeout = 60\na\nb\nc\nd\ne\nf\ng\nh\nn = 1\n' > "$R/cfg.py"; git -C "$R" commit -qam "add n"
git -C "$R" revert --no-edit HEAD~1 >/dev/null 2>&1
squash_feat "$R"
printf 'timeout = 45\na\nb\nc\nd\ne\nf\ng\nh\nn = 1\n' > "$R/cfg.py"; git -C "$R" commit -qam "follow-up: timeout 45"
printf 'timeout = 45\na\nb\nc\nd\ne\nf\ng\nh\nn = 2\n' > "$R/cfg.py"; git -C "$R" commit -qam "M2: n = 2"
git -C "$R" revert --no-edit HEAD >/dev/null 2>&1
assert_exit "fixture-42 hold broken and restored after landing -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixtures 43, 44: which commits a landed prefix covers ──
# 43: A landed; B never did; C's line reached main another way. Only commits up to
# the landed prefix are checked at its landing commit, so C is checked at the tip.
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'c1\n' > "$R/c.txt"; git -C "$R" add -A && git -C "$R" commit -qm "A: c1"
printf 'b\n' > "$R/b43.txt"; git -C "$R" add -A && git -C "$R" commit -qm "B: orphan43"
printf 'c1\nc2\n' > "$R/c.txt"; git -C "$R" commit -qam "C: c2"
git -C "$R" checkout -q main; git -C "$R" checkout -q feat~2 -- c.txt && git -C "$R" commit -qm "squash A"
printf 'c1x\n' > "$R/c.txt"; git -C "$R" commit -qam "main edits c1"
printf 'c1x\nc2\n' > "$R/c.txt"; git -C "$R" commit -qam "main adds c2 itself"
OUT43=$(out_of "$R" feat main); RC43=$?
assert_exit "fixture-43 partial merge -> flagged" 3 "$RC43"
assert_exit "fixture-43 lists the orphan" 0 "$(has "$OUT43" 'orphan43')"
assert_exit "fixture-43 does not list C (its line is at the tip)" 1 "$(has "$OUT43" 'C: c2')"
rm -rf "$R"
# 44: A and B landed together; main later edited A's line; C never landed. A is in
# the landed prefix, so it is checked at the landing commit, not the tip.
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'a = 1\n' > "$R/a44.txt"; git -C "$R" add -A && git -C "$R" commit -qm "A: a = 1"
printf 'b = 1\n' > "$R/b44.txt"; git -C "$R" add -A && git -C "$R" commit -qm "B: b = 1"
printf 'c\n' > "$R/c44.txt"; git -C "$R" add -A && git -C "$R" commit -qm "C: orphan44"
git -C "$R" checkout -q main; git -C "$R" checkout -q feat~1 -- a44.txt b44.txt && git -C "$R" commit -qm "squash A+B"
printf 'a = 2\n' > "$R/a44.txt"; git -C "$R" commit -qam "main: a = 2"
OUT44=$(out_of "$R" feat main); RC44=$?
assert_exit "fixture-44 partial merge -> flagged" 3 "$RC44"
assert_exit "fixture-44 lists the orphan" 0 "$(has "$OUT44" 'orphan44')"
assert_exit "fixture-44 does not list A (main edited it after landing)" 1 "$(has "$OUT44" 'A: a = 1')"
rm -rf "$R"

# ── Fixture 45: submodule.<name>.ignore=all must not hide a gitlink ──
R="$(mk_repo)"; printf '[submodule "sub"]\n\tpath = sub\n\turl = ./sub\n\tignore = all\n' > "$R/.gitmodules"
git -C "$R" add -A && git -C "$R" commit -qm gitmodules
mk_gitlink "$R" "$G1" "sub at 1"
git -C "$R" checkout -q -b feat; mk_gitlink "$R" "$G2" "bump sub (never landed, ignore=all)"
git -C "$R" checkout -q main; printf 'o\n' > "$R/o.txt"; git -C "$R" add o.txt && git -C "$R" commit -qm "unrelated main work"
assert_exit "fixture-45 dropped bump with ignore = all -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 46: stacked branch squashed BEFORE its base branch was merged ──
# The merge-base is on side and reaches main only through the later merge; the
# squash is not its descendant, the merge is, and it holds the net change.
R="$(mk_repo)"; printf 'h1\nh2\nh3\n' > "$R/a.py"; git -C "$R" add -A && git -C "$R" commit -qm "a.py"
git -C "$R" checkout -q -b side; printf 's1\n' > "$R/s.txt"; git -C "$R" add -A && git -C "$R" commit -qm s1
git -C "$R" checkout -q -b feat
printf 'h1\nh2\nh3\nx = 1\n' > "$R/a.py"; git -C "$R" commit -qam "add x"
printf 'h1\nh2\nh3\nx = 2\n' > "$R/a.py"; git -C "$R" commit -qam "change x"
squash_feat "$R"
git -C "$R" merge -q --no-ff --no-edit side >/dev/null 2>&1
edit_x "$R"
assert_exit "fixture-46 squash before the base branch's merge + follow-up -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 47: a listed blob that cannot be read is an error, not an empty file ──
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'lost = 1\n' > "$R/l47.txt"; git -C "$R" add -A && git -C "$R" commit -qm "add l47 (never landed)"
git -C "$R" checkout -q main
O47=$(git -C "$R" rev-parse feat:l47.txt); rm -f "$R/.git/objects/${O47:0:2}/${O47:2}"
assert_exit "fixture-47 unreadable blob -> skip, not clean" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 47b: the unreadable blob is one only the branch head has (made by merging main
# into the branch), so no candidate's own patch needs it and only the read of the
# head's version can notice it is gone.
R="$(mk_repo)"; printf 'a\nb\nc\nd\ne\n' > "$R/f.txt"; git -C "$R" add -A && git -C "$R" commit -qm f
git -C "$R" checkout -q -b feat; printf 'a\nb\nc\nd\ne\nlost = 1\n' > "$R/f.txt"; git -C "$R" commit -qam "add lost (never landed)"
git -C "$R" checkout -q main; printf 'A\nb\nc\nd\ne\n' > "$R/f.txt"; git -C "$R" commit -qam "main: A"
git -C "$R" checkout -q feat; git -C "$R" merge -q --no-edit main >/dev/null 2>&1; git -C "$R" checkout -q main
O47=$(git -C "$R" rev-parse feat:f.txt); rm -f "$R/.git/objects/${O47:0:2}/${O47:2}"
assert_exit "fixture-47b unreadable head-only blob -> skip, not clean" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 48: a path that is not valid UTF-8, anywhere in the tree ──
# In a UTF-8 locale macOS tr stops at such a byte; every later path would look
# absent from the branch head and the orphan below would pass. Built with plumbing
# only: APFS refuses to check the name out.
R="$(mk_repo)"; L48=$(printf 'latin\n' | git -C "$R" hash-object -w --stdin)
git -C "$R" update-index --add --cacheinfo "100644,$L48,$(printf 'a\351.txt')" && git -C "$R" commit -qm latin1
Z48=$(printf 'ORPHAN = 1\n' | git -C "$R" hash-object -w --stdin)
T48=$( { git -C "$R" ls-tree -z main; printf '100644 blob %s\tz48.txt\000' "$Z48"; } | git -C "$R" mktree -z)
C48=$(git -C "$R" commit-tree "$T48" -p main -m "z48 (never landed)"); git -C "$R" update-ref refs/heads/feat "$C48"
printf 'o\n' > "$R/o.txt"; git -C "$R" add o.txt && git -C "$R" commit -qm "unrelated main work"
assert_exit "fixture-48 Latin-1 path in the tree, UTF-8 locale -> orphan flagged" 3 \
  "$(LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 49: a CR-named file elsewhere in the tree (macOS Icon\r) changes nothing ──
R="$(mk_repo)"; : > "$R/$(printf 'Icon\r')"; git -C "$R" add -A && git -C "$R" commit -qm icon
mk_rewrite_branch "$R"; squash_feat "$R"; edit_x "$R"
assert_exit "fixture-49a Icon<CR> in the tree + #408 shape -> NOT flagged" 0 "$(run_helper "$R" feat main)"
git -C "$R" checkout -q -b feat2; printf 'y\n' > "$R/y49.txt"; git -C "$R" add y49.txt && git -C "$R" commit -qm "y49 (never landed)"
git -C "$R" checkout -q main
assert_exit "fixture-49b Icon<CR> in the tree + genuine orphan -> flagged" 3 "$(run_helper "$R" feat2 main)"
rm -rf "$R"

# ── Fixture 50: --repo given as a subdirectory ──
# Pathspecs on rev-list's stdin are read relative to the current directory; the
# helper must work from the top level. main touches a.py before the squash, so the
# path-limited walk is what reaches the squash.
R="$(mk_repo)"; mkdir -p "$R/sub"; printf 'k\n' > "$R/sub/keep.txt"; git -C "$R" add -A && git -C "$R" commit -qm sub
mk_rewrite_branch "$R"; git -C "$R" checkout -q main
printf 'H1\nh2\nh3\n' > "$R/a.py"; git -C "$R" commit -qam "main edits a.py first"
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat"; edit_x "$R"
assert_exit "fixture-50 --repo is a subdirectory -> NOT flagged" 0 "$(run_helper "$R/sub" feat main)"
rm -rf "$R"

# ── Fixture 51: a branch commit was cherry-picked; the one that undid it was not ──
# P sets debug, O sets info back: no net change, so the merge-base "holds" it. P was
# cherry-picked onto main afterwards and O was left behind; main now says debug.
R="$(mk_repo)"; printf 'LOG = "info"\na\nb\n' > "$R/c51.py"; git -C "$R" add -A && git -C "$R" commit -qm c51
git -C "$R" checkout -q -b feat
printf 'LOG = "debug"\na\nb\n' > "$R/c51.py"; git -C "$R" commit -qam "P: debug"
printf 'LOG = "info"\na\nb\n' > "$R/c51.py"; git -C "$R" commit -qam "O: back to info (never landed)"
git -C "$R" checkout -q main; printf 'o\n' > "$R/o.txt"; git -C "$R" add o.txt && git -C "$R" commit -qm "unrelated main work"
git -C "$R" cherry-pick -x feat~1 >/dev/null 2>&1
OUT51=$(out_of "$R" feat main); RC51=$?
assert_exit "fixture-51 cherry-picked P, dropped O -> flagged" 3 "$RC51"
assert_exit "fixture-51 lists O" 0 "$(has "$OUT51" 'O: back to info')"
rm -rf "$R"

# ── Fixture 52: a prefix that undid itself did not land anywhere ──
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'f\n' > "$R/f52.txt"; git -C "$R" add -A && git -C "$R" commit -qm "add f"
git -C "$R" rm -q f52.txt && git -C "$R" commit -qm "drop f"
printf 'g\n' > "$R/g52.txt"; git -C "$R" add -A && git -C "$R" commit -qm "add g (never landed)"
git -C "$R" checkout -q main
OUT52=$(out_of "$R" feat main); RC52=$?
assert_exit "fixture-52 never-landed branch -> flagged" 3 "$RC52"
assert_exit "fixture-52 note does not claim a landed prefix" 1 "$(has "$OUT52" 'the branch up to')"
rm -rf "$R"

# ── Fixture 53: the landed prefix is three commits behind the head ──
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'a = 1\n' > "$R/a53.txt"; git -C "$R" add -A && git -C "$R" commit -qm "A1: a = 1"
printf 'b = 1\n' > "$R/b53.txt"; git -C "$R" add -A && git -C "$R" commit -qm "A2: b = 1"
for x in B C D; do printf '%s\n' "$x" > "$R/$x.53.txt"; git -C "$R" add -A && git -C "$R" commit -qm "$x: orphan53"; done
git -C "$R" checkout -q main; git -C "$R" checkout -q feat~3 -- a53.txt b53.txt && git -C "$R" commit -qm "squash A1+A2"
printf 'a = 2\n' > "$R/a53.txt"; git -C "$R" commit -qam "main: a = 2"
OUT53=$(out_of "$R" feat main); RC53=$?
assert_exit "fixture-53 partial merge -> flagged" 3 "$RC53"
assert_exit "fixture-53 note names the landed prefix" 0 "$(has "$OUT53" 'the branch up to')"
assert_exit "fixture-53 does not list A1 (main edited it after landing)" 1 "$(has "$OUT53" 'A1: a = 1')"
rm -rf "$R"

# ── Fixture 54: a crafted subject cannot rebuild a control sequence or close its quotes ──
# Deleting the inner C2 9B of C2 C2 9B 9B would leave C2 9B (CSI); a " in the
# subject must not end the quoted text.
R="$(mk_repo)"; git -C "$R" checkout -q -b feat; printf 'x\n' > "$R/x54.txt"; git -C "$R" add -A && git -C "$R" commit -qm tmp
T54=$(git -C "$R" rev-parse 'HEAD^{tree}'); P54=$(git -C "$R" rev-parse HEAD~1)
C54=$( { printf 'tree %s\nparent %s\nauthor t <t@t.t> 1700000000 +0000\ncommitter t <t@t.t> 1700000000 +0000\n\n' "$T54" "$P54"
         printf 'a\302\302\233\2332J \342\200\342\200\256\256 \330\234\342\201\240\357\270\217\363\240\204\200 q"  <- note: close it\n'; } | git -C "$R" hash-object -t commit -w --stdin)
git -C "$R" update-ref refs/heads/feat "$C54"; git -C "$R" checkout -q main
OUT54=$(out_of "$R" feat main)
assert_exit "fixture-54 no C1 control rebuilt" 1 "$(printf '%s' "$OUT54" | grep -q "$(printf '\302\233')"; echo $?)"
assert_exit "fixture-54 no bidi override rebuilt" 1 "$(printf '%s' "$OUT54" | grep -q "$(printf '\342\200\256')"; echo $?)"
assert_exit "fixture-54 no ALM, word joiner, variation selector" 1 \
  "$(printf '%s' "$OUT54" | LC_ALL=C grep -q -e "$(printf '\330\234')" -e "$(printf '\342\201\240')" -e "$(printf '\357\270\217')" -e "$(printf '\363\240\204\200')"; echo $?)"
assert_exit "fixture-54 the quote inside the subject is escaped" 0 "$(printf '%s' "$OUT54" | LC_ALL=C grep -qF 'q\"'; echo $?)"
rm -rf "$R"

# ── Fixtures 55, 56: the branch never landed and what it leaves behind is a deletion ──
# c1 changes a line and c2 deletes the file: c1's line is gone from the head, and
# c2 removes lines only, so line by line nothing looks missing.
R="$(mk_repo)"; printf 'a\nb\nc\n' > "$R/f55.txt"; git -C "$R" add -A && git -C "$R" commit -qm f55
git -C "$R" checkout -q -b feat
printf 'a\nB\nc\n' > "$R/f55.txt"; git -C "$R" commit -qam "c1: b -> B"
git -C "$R" rm -q f55.txt && git -C "$R" commit -qm "c2: drop f55 (never landed)"
git -C "$R" checkout -q main; printf 'o\n' > "$R/o.txt"; git -C "$R" add o.txt && git -C "$R" commit -qm "unrelated main work"
OUT55=$(out_of "$R" feat main); RC55=$?
assert_exit "fixture-55 never-landed deletion-only branch -> flagged" 3 "$RC55"
assert_exit "fixture-55 lists the deleting commit" 0 "$(has "$OUT55" 'c2: drop f55')"
rm -rf "$R"
# 55b: the same with a line deletion: c1 adds a debug line, c2 removes it, c3
# deletes dead(); nothing landed.
R="$(mk_repo)"; printf 'def live():\n  pass\ndef dead():\n  return 0\n' > "$R/m55.py"; git -C "$R" add -A && git -C "$R" commit -qm m55
git -C "$R" checkout -q -b feat
printf 'def live():\n  print("debug")\n  pass\ndef dead():\n  return 0\n' > "$R/m55.py"; git -C "$R" commit -qam "c1: debug"
printf 'def live():\n  pass\ndef dead():\n  return 0\n' > "$R/m55.py"; git -C "$R" commit -qam "c2: no debug"
printf 'def live():\n  pass\n' > "$R/m55.py"; git -C "$R" commit -qam "c3: drop dead() (never landed)"
git -C "$R" checkout -q main; printf 'o\n' > "$R/o.txt"; git -C "$R" add o.txt && git -C "$R" commit -qm "unrelated main work"
OUT55=$(out_of "$R" feat main); RC55=$?
assert_exit "fixture-55b never-landed line deletion -> flagged" 3 "$RC55"
assert_exit "fixture-55b lists the deleting commit" 0 "$(has "$OUT55" 'c3: drop dead()')"
assert_exit "fixture-55b does not list the commit that removed the branch's own debug line" 1 "$(has "$OUT55" 'c2: no debug')"
rm -rf "$R"
# 56: A landed; the tail adds a debug line, removes it, and deletes legacy.py.
R="$(mk_repo)"; printf 'old\n' > "$R/legacy.py"; git -C "$R" add -A && git -C "$R" commit -qm legacy
git -C "$R" checkout -q -b feat
printf 'a = 1\n' > "$R/a56.txt"; git -C "$R" add -A && git -C "$R" commit -qm "A: a56"
printf 'a = 1\nprint(1)\n' > "$R/a56.txt"; git -C "$R" commit -qam "B: debug"
printf 'a = 1\n' > "$R/a56.txt"; git -C "$R" rm -q legacy.py; git -C "$R" add -A && git -C "$R" commit -qm "C: drop debug and legacy.py (never landed)"
git -C "$R" checkout -q main; git -C "$R" checkout -q feat~2 -- a56.txt && git -C "$R" commit -qm "squash A"
OUT56=$(out_of "$R" feat main); RC56=$?
assert_exit "fixture-56 landed prefix + deletion-only tail -> flagged" 3 "$RC56"
assert_exit "fixture-56 lists the deleting commit" 0 "$(has "$OUT56" 'C: drop debug')"
rm -rf "$R"

# ── Fixture 57: squash, revert, then a commit cherry-picked back ──
# The branch landed whole at the squash; the revert and the reland are main's own
# history (out of scope).
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'a\n' > "$R/a57.txt"; git -C "$R" add -A && git -C "$R" commit -qm "A: a57"
printf 'b\n' > "$R/b57.txt"; git -C "$R" add -A && git -C "$R" commit -qm "B: b57"
squash_feat "$R"; git -C "$R" revert --no-edit HEAD >/dev/null 2>&1; git -C "$R" cherry-pick -x feat~1 >/dev/null 2>&1
assert_exit "fixture-57 squash, revert, cherry-pick reland -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 58: a path with a newline elsewhere in the tree changes nothing ──
R="$(mk_repo)"; N58=$(printf 'n\n' | git -C "$R" hash-object -w --stdin)
git -C "$R" update-index --add --cacheinfo "100644,$N58,$(printf 'odd\nname.txt')" && git -C "$R" commit -qm odd
git -C "$R" checkout -q -b feat; printf 'y\n' > "$R/y58.txt"; git -C "$R" add y58.txt && git -C "$R" commit -qm "y58 (never landed)"
git -C "$R" checkout -q main
assert_exit "fixture-58 newline path elsewhere + genuine orphan -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 59: a pipeline whose producer fails is an error (pipefail) ──
# A tr that fails on the tree listing would leave every head path "absent".
R="$(mk_repo)"; git -C "$R" checkout -q -b feat; printf 'y\n' > "$R/y59.txt"; git -C "$R" add -A && git -C "$R" commit -qm "y59 (never landed)"
git -C "$R" checkout -q main
W59="$(mktemp -d)"; TR59="$(command -v tr)"
printf '#!/bin/sh\ncase "$1" in *001*) exit 1 ;; esac\ncase "$2" in *001*) exit 1 ;; esac\nexec "%s" "$@"\n' "$TR59" > "$W59/tr"; chmod +x "$W59/tr"
assert_exit "fixture-59 failing tree-listing pipe -> skip, not clean" 4 "$(PATH="$W59:$PATH" run_helper "$R" feat main)"
rm -rf "$R" "$W59"

# ── Fixture 60: the landed prefix may be up to 20 commits behind the head ──
mk_prefix60() { # repo n — A1+A2 land as a squash, then n commits that never land, then main edits A1's line
  git -C "$1" checkout -q -b feat
  printf 'a = 1\n' > "$1/a60.txt"; git -C "$1" add -A && git -C "$1" commit -qm "A1: a = 1"
  printf 'b = 1\n' > "$1/b60.txt"; git -C "$1" add -A && git -C "$1" commit -qm "A2: b = 1"
  local i; for ((i = 1; i <= $2; i++)); do printf '%s\n' "$i" > "$1/o60-$i.txt"; git -C "$1" add -A && git -C "$1" commit -qm "orphan60 $i"; done
  git -C "$1" checkout -q main; git -C "$1" checkout -q "feat~$2" -- a60.txt b60.txt && git -C "$1" commit -qm "squash A1+A2"
  printf 'a = 2\n' > "$1/a60.txt"; git -C "$1" commit -qam "main: a = 2"
}
R="$(mk_repo)"; mk_prefix60 "$R" 20
OUT60=$(out_of "$R" feat main)
assert_exit "fixture-60a prefix 20 back is found" 1 "$(has "$OUT60" 'A1: a = 1')"
rm -rf "$R"
R="$(mk_repo)"; mk_prefix60 "$R" 21
OUT60=$(out_of "$R" feat main)
assert_exit "fixture-60b prefix 21 back is not looked for (documented)" 0 "$(has "$OUT60" 'A1: a = 1')"
rm -rf "$R"

# ── Fixture 61: a squash whose conflict was resolved by hand, with every deletion made ──
# No commit holds the branch's net change (main changed the same line meanwhile),
# but the branch's lines are there and the line it replaced is gone: nothing to list.
R="$(mk_repo)"; printf 'x\nB\ny\n' > "$R/r61.txt"; git -C "$R" add -A && git -C "$R" commit -qm r61
git -C "$R" checkout -q -b feat; printf 'x\nB2\ny\n' > "$R/r61.txt"; git -C "$R" commit -qam "B -> B2"
git -C "$R" checkout -q main; printf 'x\nBm\ny\n' > "$R/r61.txt"; git -C "$R" commit -qam "main: B -> Bm"
printf 'x\nB2\nBm\ny\n' > "$R/r61.txt"; git -C "$R" commit -qam "squash feat, conflict resolved by hand"
assert_exit "fixture-61 hand-resolved squash with deletions made -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 62: the helper's own sentences are not escaped ──
R="$(mk_repo)"; git -C "$R" checkout -q -b feat; printf 'y\n' > "$R/y62.txt"; git -C "$R" add -A && git -C "$R" commit -qm "y62 (never landed)"
git -C "$R" checkout -q main
OUT62=$(out_of "$R" feat main)
assert_exit "fixture-62 no escaped apostrophe in the helper's text" 1 "$(printf '%s' "$OUT62" | grep -qF "\\'"; echo $?)"
assert_exit "fixture-62 refs are double-quoted" 0 "$(has "$OUT62" 'Orphan commits on "feat" whose content did NOT land in "main"')"
rm -rf "$R"

# ── Fixtures 63–75: deletions are checked commit by commit, like added lines ──
# 63: a deletion-only branch that never landed, with the check budget used up
# by main commits touching the same file: the tip check still sees the deletion.
R="$(mk_repo)"; printf 'h1\nh2\nh3\n' > "$R/a.py"; git -C "$R" add -A && git -C "$R" commit -qm "a.py"
git -C "$R" checkout -q -b feat; printf 'h1\nh3\n' > "$R/a.py"; git -C "$R" commit -qam "drop h2 (never landed)"
git -C "$R" checkout -q main; add_touching_commits "$R" 205
assert_exit "fixture-63 deletion-only, budget used up -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 64: a squash whose conflict was resolved by hand, and the branch moved a line:
# the moved line is still in the head, so its deletion says nothing.
R="$(mk_repo)"; printf 'import a\nimport b\n' > "$R/imp.py"; printf 'k = 1\n' > "$R/conf.txt"
git -C "$R" add -A && git -C "$R" commit -qm i64
git -C "$R" checkout -q -b feat
printf 'import b\nimport a\n' > "$R/imp.py"; git -C "$R" commit -qam "sort imports"
printf 'k = 2\n' > "$R/conf.txt"; git -C "$R" commit -qam "k = 2"
git -C "$R" checkout -q main; printf 'k = 9\n' > "$R/conf.txt"; git -C "$R" commit -qam "main: k = 9"
printf 'import b\nimport a\n' > "$R/imp.py"; printf 'k = 2\nk9 = 9\n' > "$R/conf.txt"; git -C "$R" commit -qam "squash feat, conflict resolved by hand"
assert_exit "fixture-64 hand-resolved squash + moved line -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 65: the same with a deleted function whose closing brace main also has elsewhere.
R="$(mk_repo)"; printf 'int a() {\n  return 1;\n}\nint dead() {\n  return 0;\n}\n' > "$R/f65.c"
git -C "$R" add -A && git -C "$R" commit -qm f65
git -C "$R" checkout -q -b feat
printf 'int a() {\n  return 1;\n}\n' > "$R/f65.c"; git -C "$R" commit -qam "drop dead()"
printf 'g\n' > "$R/g65.txt"; git -C "$R" add -A && git -C "$R" commit -qm "add g65"
git -C "$R" checkout -q main
printf 'int a() {\n  return 1;\n}\nint dead() {\n  return 2;\n}\nint b() {\n  return 3;\n}\n' > "$R/f65.c"; git -C "$R" commit -qam "main: tweak dead(), add b()"
printf 'int a() {\n  return 1;\n}\nint b() {\n  return 3;\n}\n' > "$R/f65.c"; printf 'g\n' > "$R/g65.txt"
git -C "$R" add -A && git -C "$R" commit -qm "squash feat, conflict resolved by hand"
assert_exit "fixture-65 hand-resolved squash, a shared closing brace -> NOT flagged" 0 "$(run_helper "$R" feat main)"
printf 'int c() {\n}\n' >> "$R/f65.c"; git -C "$R" commit -qam "main: add c() later"
assert_exit "fixture-65b ...and main adds another closing brace later -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 66: the landed prefix deleted a line that main put back later (main's own history);
# the commit after the prefix is in main and deletes nothing that is still there.
# (c1 reached main as the same patch, so git cherry does not make it a candidate.)
R="$(mk_repo)"; printf 'import os\nx = 1\n' > "$R/m66.py"; printf '1\n' > "$R/v66.txt"
git -C "$R" add -A && git -C "$R" commit -qm m66
git -C "$R" checkout -q -b feat
printf 'x = 1\n' > "$R/m66.py"; git -C "$R" commit -qam "c1: drop import os"
printf '2\n' > "$R/v66.txt"; git -C "$R" commit -qam "c2: bump version"
git -C "$R" checkout -q main; git -C "$R" checkout -q feat~1 -- m66.py && git -C "$R" commit -qm "squash c1"
printf '2\nbuild 7\n' > "$R/v66.txt"; git -C "$R" commit -qam "main: bump version by hand"
printf 'import os\nx = 1\n' > "$R/m66.py"; git -C "$R" commit -qam "main: import os again"
assert_exit "fixture-66 deletion undone by main after the prefix landed -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 67: A landed; a pure deletion B and an added file C were both dropped.
R="$(mk_repo)"; printf 'old\n' > "$R/lg67.txt"; git -C "$R" add -A && git -C "$R" commit -qm lg67
git -C "$R" checkout -q -b feat
printf 'a\n' > "$R/a67.txt"; git -C "$R" add -A && git -C "$R" commit -qm "A: a67"
git -C "$R" rm -q lg67.txt && git -C "$R" commit -qm "B: drop lg67 (never landed)"
printf 'c\n' > "$R/c67.txt"; git -C "$R" add -A && git -C "$R" commit -qm "C: c67 (never landed)"
git -C "$R" checkout -q main; git -C "$R" checkout -q feat~2 -- a67.txt && git -C "$R" commit -qm "squash A"
OUT67=$(out_of "$R" feat main); RC67=$?
assert_exit "fixture-67 dropped deletion next to a dropped addition -> flagged" 3 "$RC67"
assert_exit "fixture-67 lists the deletion" 0 "$(has "$OUT67" 'B: drop lg67')"
assert_exit "fixture-67 lists the addition" 0 "$(has "$OUT67" 'C: c67')"
rm -rf "$R"

# 68: a submodule removal that never landed.
R="$(mk_repo)"; mk_gitlink "$R" "$G1" "sub at 1"
git -C "$R" checkout -q -b feat; git -C "$R" rm -q --cached sub && git -C "$R" commit -qm "drop sub (never landed)"
git -C "$R" checkout -q main; printf 'o\n' > "$R/o.txt"; git -C "$R" add o.txt && git -C "$R" commit -qm "unrelated main work"
assert_exit "fixture-68 dropped submodule removal -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 69: a failing count of the bytes in a commit's path list is an error, not "none".
R="$(mk_repo)"; git -C "$R" checkout -q -b feat; printf 'y\n' > "$R/y69.txt"; git -C "$R" add -A && git -C "$R" commit -qm "y69 (never landed)"
git -C "$R" checkout -q main
W69="$(mktemp -d)"; TR69="$(command -v tr)"
printf '#!/bin/sh\n[ "$1" = -cd ] && case "$2" in *001*) exit 1 ;; esac\nexec "%s" "$@"\n' "$TR69" > "$W69/tr"; chmod +x "$W69/tr"
assert_exit "fixture-69 failing newline count -> skip, not a verdict" 4 "$(PATH="$W69:$PATH" run_helper "$R" feat main)"
rm -rf "$R" "$W69"

# 70: subjects with other invisible characters (CGJ, interlinear annotation, an
# Arabic number sign, a Mongolian variation selector, a musical format control).
R="$(mk_repo)"; git -C "$R" checkout -q -b feat; printf 'x\n' > "$R/x70.txt"; git -C "$R" add -A && git -C "$R" commit -qm tmp
T70=$(git -C "$R" rev-parse 'HEAD^{tree}'); P70=$(git -C "$R" rev-parse HEAD~1)
C70=$( { printf 'tree %s\nparent %s\nauthor t <t@t.t> 1700000000 +0000\ncommitter t <t@t.t> 1700000000 +0000\n\n' "$T70" "$P70"
         printf 'a\315\217b\357\277\271c\330\200d\341\240\213e\360\235\205\263f\n'; } | git -C "$R" hash-object -t commit -w --stdin)
git -C "$R" update-ref refs/heads/feat "$C70"; git -C "$R" checkout -q main
OUT70=$(out_of "$R" feat main)
assert_exit "fixture-70 the subject is printed with each mark replaced" 0 "$(has "$OUT70" '"a?b?c?d?e?f"')"
rm -rf "$R"

# 70b: $ and ` in a subject are escaped too, so the quoted text is a safe shell word.
R="$(mk_repo)"; git -C "$R" checkout -q -b feat; printf 'z\n' > "$R/z70.txt"; git -C "$R" add -A
git -C "$R" commit -qm 'x $(touch y) `z` (never landed)'; git -C "$R" checkout -q main
OUT70=$(out_of "$R" feat main)
assert_exit "fixture-70b \$ and backtick are escaped" 0 "$(has "$OUT70" '"x \$(touch y) \`z\` (never landed)"')"
rm -rf "$R"

# 71: a rename that never landed: the old path is still in the target and the head
# no longer has it. 71b: the same rename squashed into main.
R="$(mk_repo)"; printf 'alpha\nbeta\n' > "$R/r71.txt"; git -C "$R" add -A && git -C "$R" commit -qm r71
git -C "$R" checkout -q -b feat; git -C "$R" mv r71.txt s71.txt && git -C "$R" commit -qm "rename r71 (never landed)"
git -C "$R" checkout -q main; printf 'o\n' > "$R/o.txt"; git -C "$R" add o.txt && git -C "$R" commit -qm "unrelated main work"
assert_exit "fixture-71 dropped rename -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
squash_feat "$R"
assert_exit "fixture-71b landed rename -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 72: deleting an empty file, and a file of blank lines, that never landed.
R="$(mk_repo)"; : > "$R/e72.txt"; printf '\n\n' > "$R/w72.txt"; git -C "$R" add -A && git -C "$R" commit -qm e72
git -C "$R" checkout -q -b feat; git -C "$R" rm -q e72.txt w72.txt && git -C "$R" commit -qm "drop e72, w72 (never landed)"
git -C "$R" checkout -q main
assert_exit "fixture-72 dropped deletion of files with no lines -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 73: a branch that only deletes, squashed into main: nothing to list.
R="$(mk_repo)"; printf 'keep\ndrop me\n' > "$R/k73.txt"; printf 'gone\n' > "$R/g73.txt"; git -C "$R" add -A && git -C "$R" commit -qm k73
git -C "$R" checkout -q -b feat; printf 'keep\n' > "$R/k73.txt"; git -C "$R" rm -q g73.txt; git -C "$R" add -A && git -C "$R" commit -qm "drop lines and g73"
squash_feat "$R"
assert_exit "fixture-73 landed deletion-only branch -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 74: in a partial clone a missing blob is not fetched into the user's repository;
# the helper says it could not verify (git >= 2.45 honours GIT_NO_LAZY_FETCH).
if git --no-lazy-fetch version >/dev/null 2>&1; then
  R="$(mk_repo)"; git -C "$R" config uploadpack.allowFilter true
  git -C "$R" checkout -q -b feat; printf 'y\n' > "$R/y74.txt"; git -C "$R" add -A && git -C "$R" commit -qm "y74 (never landed)"
  git -C "$R" checkout -q main
  W74="$(mktemp -d)"; git clone -q --filter=blob:none --no-checkout "file://$R" "$W74/c" 2>/dev/null
  P74=$(ls "$W74/c/.git/objects/pack" | wc -l)
  assert_exit "fixture-74 partial clone -> skip, nothing fetched" 4 "$(run_helper "$W74/c" origin/feat origin/main)"
  assert_exit "fixture-74 no pack was added" 0 "$([ "$(ls "$W74/c/.git/objects/pack" | wc -l)" = "$P74" ]; echo $?)"
  rm -rf "$R" "$W74"
else
  echo "  - fixture-74 skipped: this git ($(git --version)) has no --no-lazy-fetch (git < 2.45)"
fi

# 75: a path the branch deleted and later re-created is in the head, so its
# deletion says nothing once the branch landed.
R="$(mk_repo)"; printf 'v1\n' > "$R/p75.txt"; git -C "$R" add -A && git -C "$R" commit -qm p75
git -C "$R" checkout -q -b feat; git -C "$R" rm -q p75.txt && git -C "$R" commit -qm "drop p75"
printf 'v2\n' > "$R/p75.txt"; git -C "$R" add -A && git -C "$R" commit -qm "p75 again"
squash_feat "$R"
assert_exit "fixture-75 deleted then re-created path, squashed -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixtures 76–80: at a landing commit, a deleted line can be main's own ──
# 76: two plugins share a version string: another PR bumps y to 1.2.0 while the
# branch moves x from 1.2.0 to 1.3.0; after the squash, "1.2.0" is y's line.
R="$(mk_repo)"; printf '{\n  "x": {\n    "version": "1.2.0"\n  },\n  "y": {\n    "version": "1.1.0"\n  }\n}\n' > "$R/m76.json"
git -C "$R" add -A && git -C "$R" commit -qm m76
git -C "$R" checkout -q -b feat; printf 'fix\n' > "$R/x76.txt"; git -C "$R" add -A && git -C "$R" commit -qm "x: fix"
printf '{\n  "x": {\n    "version": "1.3.0"\n  },\n  "y": {\n    "version": "1.1.0"\n  }\n}\n' > "$R/m76.json"; git -C "$R" commit -qam "release x 1.3.0"
git -C "$R" checkout -q main
printf '{\n  "x": {\n    "version": "1.2.0"\n  },\n  "y": {\n    "version": "1.2.0"\n  }\n}\n' > "$R/m76.json"; git -C "$R" commit -qam "release y 1.2.0"
squash_feat "$R"
assert_exit "fixture-76 squash after another PR took the old version string -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 77: the branch drops a line that main added a copy of, elsewhere in the file,
# before the squash.
R="$(mk_repo)"; printf 'import os\nx = 1\n' > "$R/m77.py"; printf 'a\n' > "$R/o77.txt"; git -C "$R" add -A && git -C "$R" commit -qm m77
git -C "$R" checkout -q -b feat; printf 'x = 1\n' > "$R/m77.py"; git -C "$R" commit -qam "drop import os"
printf 'b\n' > "$R/o77.txt"; git -C "$R" commit -qam "o77 b"
git -C "$R" checkout -q main; printf 'import os\nx = 1\nimport os\n' > "$R/m77.py"; git -C "$R" commit -qam "main: import os at the end"
squash_feat "$R"
assert_exit "fixture-77 squash, main had added a copy of the deleted line -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 78: the branch creates and later deletes a scratch file; main created its own file
# at that path before the squash.
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'scratch\n' > "$R/n78.md"; git -C "$R" add -A && git -C "$R" commit -qm "scratch notes"
printf 'real\n' > "$R/r78.txt"; git -C "$R" add -A && git -C "$R" commit -qm "real change"
git -C "$R" rm -q n78.md && git -C "$R" commit -qm "drop scratch notes"
git -C "$R" checkout -q main; printf 'main notes\n' > "$R/n78.md"; git -C "$R" add -A && git -C "$R" commit -qm "main: notes"
squash_feat "$R"
assert_exit "fixture-78 squash, main had its own file at a path the branch deleted -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 79: the deletion mirror of fixture 19: c1 adds a line, c2 removes it again, and
# only c1 reached the squash. The squash holds the branch's net change, yet c2 did
# not land.
R="$(mk_repo)"; printf 'a\n' > "$R/f79.txt"; git -C "$R" add -A && git -C "$R" commit -qm f79
git -C "$R" checkout -q -b feat
printf 'y\n' > "$R/y79.txt"; git -C "$R" add -A && git -C "$R" commit -qm "y79"
printf 'a\nDEBUG\n' > "$R/f79.txt"; git -C "$R" commit -qam "c1: debug"
printf 'a\n' > "$R/f79.txt"; git -C "$R" commit -qam "c2: no debug (never landed)"
git -C "$R" checkout -q main; git -C "$R" checkout -q feat~1 -- y79.txt f79.txt && git -C "$R" commit -qm "squash without c2"
OUT79=$(out_of "$R" feat main); RC79=$?
assert_exit "fixture-79 the commit that removed the branch's own line was dropped -> flagged" 3 "$RC79"
assert_exit "fixture-79 lists it" 0 "$(has "$OUT79" 'c2: no debug')"
rm -rf "$R"

# 80: a commit that only adds an empty file, dropped from the squash.
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'p\n' > "$R/p80.py"; git -C "$R" add -A && git -C "$R" commit -qm "p80"
mkdir -p "$R/pkg80"; : > "$R/pkg80/__init__.py"; git -C "$R" add -A && git -C "$R" commit -qm "pkg80 package marker (never landed)"
git -C "$R" checkout -q main; git -C "$R" checkout -q feat~1 -- p80.py && git -C "$R" commit -qm "squash p80"
OUT80=$(out_of "$R" feat main); RC80=$?
assert_exit "fixture-80 dropped empty-file addition -> flagged" 3 "$RC80"
assert_exit "fixture-80 lists it" 0 "$(has "$OUT80" 'pkg80 package marker')"
rm -rf "$R"

# ── Fixtures 81–83: copies of a line main added or removed on its own ──
# 81: main removed its own copy of a line before the squash; the branch adds the
# same line elsewhere. The branch's line is in place in the landing commit.
R="$(mk_repo)"; printf 'x = 1\na\nb\nc\nd\ne\nf\n' > "$R/m81.py"; git -C "$R" add -A && git -C "$R" commit -qm m81
git -C "$R" checkout -q -b feat
printf 'x = 1\na\nb\nc\nd\ne\nf\nx = 1\n' > "$R/m81.py"; git -C "$R" commit -qam "c1: x at the end"
printf 'y\n' > "$R/y81.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c2: y81"
git -C "$R" checkout -q main; printf 'a\nb\nc\nd\ne\nf\n' > "$R/m81.py"; git -C "$R" commit -qam "main: drop x at the top"
squash_feat "$R"
assert_exit "fixture-81 squash, main had dropped its own copy of the added line -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 82: fixture 19 where the restored line also appears elsewhere in the file. The
# dropped commit's line is still missing from the landing commit, by count.
R="$(mk_repo)"
printf 'LOG = "info"\na\nb\nc\nd\ne\nLOG = "info"\n' > "$R/cfg82.py"; git -C "$R" add -A && git -C "$R" commit -qm cfg82
git -C "$R" checkout -q -b feat
printf 'LOG = "debug"\na\nb\nc\nd\ne\nLOG = "info"\nRETRIES = 3\n' > "$R/cfg82.py"; git -C "$R" commit -qam "P: debug + retries"
printf 'LOG = "info"\na\nb\nc\nd\ne\nLOG = "info"\nRETRIES = 3\n' > "$R/cfg82.py"; git -C "$R" commit -qam "O: back to info (never landed)"
git -C "$R" checkout -q main
printf 'LOG = "debug"\na\nb\nc\nd\ne\nLOG = "info"\nRETRIES = 3\n' > "$R/cfg82.py"; git -C "$R" commit -qam "land P only"
# At the tip O is still listed: the "debug" line it deleted is in the tip and not in
# the head. Where it landed, its "info" copy is missing as well.
OUT82=$(out_of "$R" feat main); RC82=$?
assert_exit "fixture-82 dropped restore whose line is also elsewhere -> flagged" 3 "$RC82"
assert_exit "fixture-82 lists O" 0 "$(has "$OUT82" 'O: back to info')"
rm -rf "$R"

# 83: a squash resolved by hand (checked at the tip): the branch adds a function,
# and main removed another one on its own, so the tip has one closing brace fewer
# than the head. At the tip only presence counts.
R="$(mk_repo)"; printf 'int a() {\n  return 1;\n}\nint dead() {\n  return 0;\n}\nint z() {\n  return 9;\n}\n' > "$R/f83.c"
git -C "$R" add -A && git -C "$R" commit -qm f83
git -C "$R" checkout -q -b feat
printf 'int a() {\n  return 1;\n}\nint e() {\n  return 5;\n}\nint dead() {\n  return 0;\n}\nint z() {\n  return 9;\n}\n' > "$R/f83.c"; git -C "$R" commit -qam "add e()"
printf 'g\n' > "$R/g83.txt"; git -C "$R" add -A && git -C "$R" commit -qm "add g83"
git -C "$R" checkout -q main
printf 'int a() {\n  return 1;\n}\nint dead(void) {\n  return 0;\n}\n' > "$R/f83.c"; git -C "$R" commit -qam "main: dead(void), drop z()"
printf 'int a() {\n  return 1;\n}\nint e() {\n  return 5;\n}\nint dead(void) {\n  return 0;\n}\n' > "$R/f83.c"; printf 'g\n' > "$R/g83.txt"
git -C "$R" add -A && git -C "$R" commit -qm "squash feat, conflict resolved by hand"
assert_exit "fixture-83 hand-resolved squash, main dropped a closing brace of its own -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixtures 84, 85: copies main dropped on its own, and a squash resolved by hand ──
# 84: c1 adds a second X, c2 drops B, c3 drops c1's X and never landed; main had
# dropped its own X before the squash. The middle X c3 deleted is still in place in
# the squash, so c3 did not land. (Round 9 compared with the head's count and missed
# it.)
R="$(mk_repo)"; printf 'X = 1\na\nb\nc\nd\ne\nf\nB = 2\ng\nh\ni\n' > "$R/f84.py"; git -C "$R" add -A && git -C "$R" commit -qm f84
git -C "$R" checkout -q -b feat
printf 'X = 1\na\nb\nc\nX = 1\nd\ne\nf\nB = 2\ng\nh\ni\n' > "$R/f84.py"; git -C "$R" commit -qam "c1: X in the middle"
printf 'X = 1\na\nb\nc\nX = 1\nd\ne\nf\ng\nh\ni\n' > "$R/f84.py"; git -C "$R" commit -qam "c2: drop B"
printf 'X = 1\na\nb\nc\nd\ne\nf\ng\nh\ni\n' > "$R/f84.py"; git -C "$R" commit -qam "c3: drop the middle X (never landed)"
git -C "$R" checkout -q main
printf 'a\nb\nc\nd\ne\nf\nB = 2\ng\nh\ni\n' > "$R/f84.py"; git -C "$R" commit -qam "main: drop X at the top"
printf 'a\nb\nc\nX = 1\nd\ne\nf\ng\nh\ni\n' > "$R/f84.py"; git -C "$R" commit -qam "squash c1 and c2"
EXP84=3
OUT84=$(out_of "$R" feat main); RC84=$?
assert_exit "fixture-84 deletion that did not land, main dropped its own copy -> flagged where it landed" "$EXP84" "$RC84"
if [ "$EXP84" = 3 ]; then
  assert_exit "fixture-84 lists c3" 0 "$(has "$OUT84" 'c3: drop the middle X')"
  assert_exit "fixture-84 does not list c1" 1 "$(has "$OUT84" 'c1: X in the middle')"
fi
rm -rf "$R"

# 85: the squash kept the branch's v over main's own v (resolved by hand): it holds
# the branch, but the branch does not merge cleanly onto main just before it, so the
# check is at the tip, and the note says why.
R="$(mk_repo)"; printf 'v = 0\na\nb\nc\n' > "$R/f85.py"; git -C "$R" add -A && git -C "$R" commit -qm f85
git -C "$R" checkout -q -b feat
printf 'v = 2\na\nb\nc\n' > "$R/f85.py"; git -C "$R" commit -qam "c1: v = 2"
printf 'w\n' > "$R/w85.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c2: w85 (never landed)"
git -C "$R" checkout -q main
printf 'v = 1\na\nb\nc\n' > "$R/f85.py"; git -C "$R" commit -qam "main: v = 1"
printf 'v = 2\na\nb\nc\n' > "$R/f85.py"; git -C "$R" commit -qam "squash c1, conflict resolved to the branch's v"
OUT85=$(out_of "$R" feat main); RC85=$?
assert_exit "fixture-85 hand-resolved squash plus a dropped commit -> flagged" 3 "$RC85"
assert_exit "fixture-85 lists c2" 0 "$(has "$OUT85" 'c2: w85')"
assert_exit "fixture-85 does not list c1" 1 "$(has "$OUT85" 'c1: v = 2')"
assert_exit "fixture-85 note names the landing commit (no tip fallback)" 0 "$(has "$OUT85" 'landed in')"
rm -rf "$R"

# ── Fixtures 86–88: a text main has elsewhere, and a landed prefix ──
# 86: b1 drops x, b2 adds y in the middle, b3 puts x back and never landed; main had
# turned its own y at the bottom into x before squashing b1 and b2. b3's x is not in
# its place at the top, even though the text is elsewhere. (Round 9 missed it;
# presence would too.)
R="$(mk_repo)"; printf 'x = 1\na\nb\nc\nd\ne\nf\ny = 2\ng\nh\ni\n' > "$R/f86.py"; git -C "$R" add -A && git -C "$R" commit -qm f86
git -C "$R" checkout -q -b feat
printf 'a\nb\nc\nd\ne\nf\ny = 2\ng\nh\ni\n' > "$R/f86.py"; git -C "$R" commit -qam "b1: drop x"
printf 'a\nb\nc\ny = 2\nd\ne\nf\ny = 2\ng\nh\ni\n' > "$R/f86.py"; git -C "$R" commit -qam "b2: y in the middle"
printf 'x = 1\na\nb\nc\ny = 2\nd\ne\nf\ny = 2\ng\nh\ni\n' > "$R/f86.py"; git -C "$R" commit -qam "b3: x back (never landed)"
git -C "$R" checkout -q main
printf 'x = 1\na\nb\nc\nd\ne\nf\nx = 1\ng\nh\ni\n' > "$R/f86.py"; git -C "$R" commit -qam "main: y at the bottom becomes x"
printf 'a\nb\nc\ny = 2\nd\ne\nf\nx = 1\ng\nh\ni\n' > "$R/f86.py"; git -C "$R" commit -qam "squash b1 and b2"
EXP86=3
OUT86=$(out_of "$R" feat main); RC86=$?
assert_exit "fixture-86 restored line whose text main has elsewhere, dropped -> flagged where it landed" "$EXP86" "$RC86"
if [ "$EXP86" = 3 ]; then
  assert_exit "fixture-86 lists b3" 0 "$(has "$OUT86" 'b3: x back')"
  assert_exit "fixture-86 does not list b1" 1 "$(has "$OUT86" 'b1: drop x')"
fi
rm -rf "$R"

# 87: c1 and c1b landed as one squash; c2 adds a second copy of c1's line and a line
# of its own, and never landed. c1 is compared with the merge of the landed part
# (one copy), not of the whole branch (two copies).
R="$(mk_repo)"; printf 'a\nb\nc\nd\ne\nf\n' > "$R/f87.py"; git -C "$R" add -A && git -C "$R" commit -qm f87
git -C "$R" checkout -q -b feat
printf 'a\nb\nc\nd\ne\nf\nX = 1\n' > "$R/f87.py"; git -C "$R" commit -qam "c1: X"
printf 'y\n' > "$R/y87.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1b: y87"
printf 'X = 1\na\nb\nc\nd\ne\nf\nX = 1\nZ = 3\n' > "$R/f87.py"; git -C "$R" commit -qam "c2: X again and Z (never landed)"
git -C "$R" checkout -q main
printf 'a\nb\nc\nd\ne\nf\nX = 1\n' > "$R/f87.py"; printf 'y\n' > "$R/y87.txt"; git -C "$R" add -A && git -C "$R" commit -qm "squash c1 and c1b"
OUT87=$(out_of "$R" feat main); RC87=$?
assert_exit "fixture-87 landed prefix + a dropped commit sharing its line -> flagged" 3 "$RC87"
assert_exit "fixture-87 lists c2" 0 "$(has "$OUT87" 'c2: X again')"
assert_exit "fixture-87 does not list c1 (it landed)" 1 "$(has "$OUT87" 'c1: X')"
rm -rf "$R"

# 88: c1 adds X and c2 drops it again (the head no longer shows c1's X); main had an X
# of its own, which the landing commit also dropped. c1 says nothing about X.
R="$(mk_repo)"; printf 'a\nb\nc\nd\ne\nf\ng\nh\ni\n' > "$R/f88.py"; git -C "$R" add -A && git -C "$R" commit -qm f88
git -C "$R" checkout -q -b feat
printf 'a\nb\nc\nd\ne\nf\ng\nh\ni\nX = 1\n' > "$R/f88.py"; git -C "$R" commit -qam "c1: X at the end"
printf 'a\nb\nC\nd\ne\nf\ng\nh\ni\n' > "$R/f88.py"; git -C "$R" commit -qam "c2: drop X, C"
git -C "$R" checkout -q main
printf 'X = 1\na\nb\nc\nd\ne\nf\ng\nh\ni\n' > "$R/f88.py"; git -C "$R" commit -qam "main: X at the top"
printf 'a\nb\nC\nd\ne\nf\ng\nh\ni\n' > "$R/f88.py"; git -C "$R" commit -qam "squash feat, and drop main's X"
assert_exit "fixture-88 a superseded line whose text the landing commit dropped from main -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixtures 89–93 (#399 verify round 10) ──
# 89, 90: the landing step carries changes of its own. Each effect is checked in its
# own place, so main's own copy of the same text elsewhere cannot list a commit that
# landed.
# 89: a squash edited by hand: the branch moves x into the middle, and the squash
# also turns main's y into x.
R="$(mk_repo)"; printf 'x = 1\np\nq\nr\ns\nt\nu\ny = 2\n' > "$R/f89.py"; git -C "$R" add -A && git -C "$R" commit -qm f89
git -C "$R" checkout -q -b feat
printf 'x = 1\np\nq\nr\nx = 1\ns\nt\nu\ny = 2\n' > "$R/f89.py"; git -C "$R" commit -qam "b1: x in the middle"
printf 'z = 3\np\nq\nr\nx = 1\ns\nt\nu\ny = 2\n' > "$R/f89.py"; git -C "$R" commit -qam "b2: z at the top"
git -C "$R" checkout -q main
printf 'z = 3\np\nq\nr\nx = 1\ns\nt\nu\nx = 1\n' > "$R/f89.py"; git -C "$R" commit -qam "squash feat, and y becomes x"
EXP89=0
assert_exit "fixture-89 hand-edited squash with a copy of a moved line -> NOT flagged" "$EXP89" "$(run_helper "$R" feat main)"
rm -rf "$R"

# 90: a release merge: main turned y into x; feat drops the top x and adds z; on
# develop the squash is followed by another PR that adds x; main merges develop.
R="$(mk_repo)"; printf 'x = 1\np\nq\nr\ns\nt\nu\ny = 2\n' > "$R/f90.py"; git -C "$R" add -A && git -C "$R" commit -qm f90
git -C "$R" checkout -q -b feat
printf 'p\nq\nr\ns\nt\nu\ny = 2\n' > "$R/f90.py"; git -C "$R" commit -qam "b1: drop x"
printf 'z = 3\np\nq\nr\ns\nt\nu\ny = 2\n' > "$R/f90.py"; git -C "$R" commit -qam "b2: z at the top"
git -C "$R" checkout -q main
printf 'x = 1\np\nq\nr\ns\nt\nu\nx = 1\n' > "$R/f90.py"; git -C "$R" commit -qam "main: y becomes x"
git -C "$R" checkout -q -b develop
printf 'z = 3\np\nq\nr\ns\nt\nu\nx = 1\n' > "$R/f90.py"; git -C "$R" commit -qam "squash feat"
printf 'z = 3\np\nq\nr\nx = 1\ns\nt\nu\nx = 1\n' > "$R/f90.py"; git -C "$R" commit -qam "another PR: x in the middle"
git -C "$R" checkout -q main; printf 'u\n' > "$R/u90.txt"; git -C "$R" add -A && git -C "$R" commit -qm "main: u90"
git -C "$R" merge -q --no-ff --no-edit develop >/dev/null 2>&1
assert_exit "fixture-90 release merge carrying another PR -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 91, 92: the branch has no net change, so it "lands" at the merge-base; a prefix
# landed later, and the commits that undid it never did (3.5.0 caught these).
R="$(mk_repo)"; printf 'cfg = info\na\nb\nc\nd\nother = 1\n' > "$R/f91.py"; git -C "$R" add -A && git -C "$R" commit -qm f91
git -C "$R" checkout -q -b feat
printf 'cfg = debug\na\nb\nc\nd\nother = 1\n' > "$R/f91.py"; git -C "$R" commit -qam "c1: debug"
printf 'cfg = debug\na\nb\nc\nd\nother = 2\n' > "$R/f91.py"; git -C "$R" commit -qam "c2: other 2"
printf 'cfg = info\na\nb\nc\nd\nother = 2\n' > "$R/f91.py"; git -C "$R" commit -qam "c3: info again (never landed)"
printf 'cfg = info\na\nb\nc\nd\nother = 1\n' > "$R/f91.py"; git -C "$R" commit -qam "c4: other 1 again (never landed)"
git -C "$R" checkout -q main; printf 'cfg = debug\na\nb\nc\nd\nother = 2\n' > "$R/f91.py"; git -C "$R" commit -qam "squash c1 and c2"
OUT91=$(out_of "$R" feat main); RC91=$?
assert_exit "fixture-91 no net change, the undoing commits never landed -> flagged" 3 "$RC91"
assert_exit "fixture-91 lists c3" 0 "$(has "$OUT91" 'c3: info again')"
assert_exit "fixture-91 lists c4" 0 "$(has "$OUT91" 'c4: other 1 again')"
assert_exit "fixture-91 does not list c1" 1 "$(has "$OUT91" 'c1: debug')"
rm -rf "$R"

R="$(mk_repo)"; printf 'LEVEL = "info"\na\nb\nc\n' > "$R/f92.py"; git -C "$R" add -A && git -C "$R" commit -qm f92
git -C "$R" checkout -q -b feat
printf 'a\nb\nc\n' > "$R/f92.py"; git -C "$R" commit -qam "b1: drop level"
printf 'LEVEL = "debug"\na\nb\nc\n' > "$R/f92.py"; git -C "$R" commit -qam "b2: level debug"
printf 'LEVEL = "info"\na\nb\nc\n' > "$R/f92.py"; git -C "$R" commit -qam "b3: back to info (never landed)"
git -C "$R" checkout -q main; printf 'u\n' > "$R/u92.txt"; git -C "$R" add -A && git -C "$R" commit -qm u92
printf 'LEVEL = "debug"\na\nb\nc\n' > "$R/f92.py"; git -C "$R" commit -qam "squash b1 and b2"
OUT92=$(out_of "$R" feat main); RC92=$?
assert_exit "fixture-92 no net change, a dropped restore -> flagged" 3 "$RC92"
assert_exit "fixture-92 lists only b3" 0 "$(has "$OUT92" 'b3: back to info')"
assert_exit "fixture-92 does not list b2" 1 "$(has "$OUT92" 'b2: level debug')"
rm -rf "$R"

# 93: the test-only trace variable never overwrites a file and never changes the
# answer (round 10 truncated an existing file, and an unwritable path exited 4).
R="$(mk_repo)"; git -C "$R" checkout -q -b feat; printf 'y\n' > "$R/y93.txt"; git -C "$R" add -A && git -C "$R" commit -qm "y93 (never landed)"
git -C "$R" checkout -q main; printf 'keep me\n' > "$R/keep93"
assert_exit "fixture-93 trace onto an existing file: the answer is unchanged" 3 \
  "$(CHECK_MERGE_COMPLETENESS_TRACE="$R/keep93" "${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main >/dev/null 2>&1; echo $?)"
assert_exit "fixture-93 the existing file is left alone" 0 "$([ "$(cat "$R/keep93")" = "keep me" ]; echo $?)"
assert_exit "fixture-93 an unwritable trace path does not turn the answer into 4" 3 \
  "$(CHECK_MERGE_COMPLETENESS_TRACE="$R/no-such-dir/t" "${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main >/dev/null 2>&1; echo $?)"
rm -rf "$R"



# ── Fixtures 94–101 (#399 verify round 11): edits that sit next to each other ──
# A three-way merge conflicts when two edits merely touch adjacent lines; round 11
# read that conflict as "landed" and missed dropped commits. Round 12 compares in
# place with two-way diffs, which these fixtures pin.

# 94: fixture 19's dropped restore, while another PR inserts a line right below it.
R="$(mk_repo)"; printf 'LOG = "info"\na\nb\nc\nd\ne\n' > "$R/f94.py"; git -C "$R" add -A && git -C "$R" commit -qm f94
git -C "$R" checkout -q -b feat
printf 'LOG = "debug"\na\nb\nc\nd\ne\nRETRIES = 3\n' > "$R/f94.py"; git -C "$R" commit -qam "P: debug and retries"
printf 'LOG = "info"\na\nb\nc\nd\ne\nRETRIES = 3\n' > "$R/f94.py"; git -C "$R" commit -qam "O: back to info (never landed)"
git -C "$R" checkout -q main
printf 'LOG = "info"\nTIMEOUT = 5\na\nb\nc\nd\ne\n' > "$R/f94.py"; git -C "$R" commit -qam "another PR: timeout"
printf 'LOG = "debug"\nTIMEOUT = 5\na\nb\nc\nd\ne\nRETRIES = 3\n' > "$R/f94.py"; git -C "$R" commit -qam "squash P"
OUT94=$(out_of "$R" feat main); RC94=$?
assert_exit "fixture-94 dropped restore next to another PR's line -> flagged" 3 "$RC94"
assert_exit "fixture-94 lists O" 0 "$(has "$OUT94" 'O: back to info')"
assert_exit "fixture-94 does not list P" 1 "$(has "$OUT94" 'P: debug')"
rm -rf "$R"

# 95: the same, with the adjacent line added by the squash itself (edited by hand).
R="$(mk_repo)"; printf 'LOG = "info"\na\nb\nc\nd\ne\n' > "$R/f95.py"; git -C "$R" add -A && git -C "$R" commit -qm f95
git -C "$R" checkout -q -b feat
printf 'LOG = "debug"\na\nb\nc\nd\ne\nRETRIES = 3\n' > "$R/f95.py"; git -C "$R" commit -qam "P: debug and retries"
printf 'LOG = "info"\na\nb\nc\nd\ne\nRETRIES = 3\n' > "$R/f95.py"; git -C "$R" commit -qam "O: back to info (never landed)"
git -C "$R" checkout -q main
printf 'LOG = "debug"\nTIMEOUT = 5\na\nb\nc\nd\ne\nRETRIES = 3\n' > "$R/f95.py"; git -C "$R" commit -qam "squash P, and a timeout"
OUT95=$(out_of "$R" feat main); RC95=$?
assert_exit "fixture-95 dropped restore next to the squash's own line -> flagged" 3 "$RC95"
assert_exit "fixture-95 lists O" 0 "$(has "$OUT95" 'O: back to info')"
rm -rf "$R"

# 96: a commit with two effects of which only one landed (Codex's shape, round 11).
R="$(mk_repo)"; printf 'A\n' > "$R/x.txt"; printf 'C\n' > "$R/y.txt"; git -C "$R" add -A && git -C "$R" commit -qm xy
git -C "$R" checkout -q -b feat
printf 'B\n' > "$R/x.txt"; printf 'D\n' > "$R/y.txt"; git -C "$R" commit -qam "c1: x B, y D"
printf 'A\n' > "$R/x.txt"; printf 'Z\n' > "$R/z.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c2: x back to A, add z"
git -C "$R" checkout -q main
printf 'B\n' > "$R/x.txt"; printf 'D\n' > "$R/y.txt"; printf 'Z\n' > "$R/z.txt"; git -C "$R" add -A && git -C "$R" commit -qm "squash, x left at B"
OUT96=$(out_of "$R" feat main); RC96=$?
assert_exit "fixture-96 commit whose other effect landed, x not set back -> flagged" 3 "$RC96"
assert_exit "fixture-96 lists c2" 0 "$(has "$OUT96" 'c2: x back to A')"
assert_exit "fixture-96 does not list c1" 1 "$(has "$OUT96" 'c1: x B')"
rm -rf "$R"

# 97: main changed the branch's line first, the squash was resolved by hand to the
# branch's side (its tree is the head's), and a follow-up edited the branch's line.
R="$(mk_repo)"; printf 'v = 1\na\nb\nc\n' > "$R/f97.py"; git -C "$R" add -A && git -C "$R" commit -qm f97
git -C "$R" checkout -q -b feat
printf 'v = 2\na\nb\nc\n' > "$R/f97.py"; git -C "$R" commit -qam "c1: v 2"
printf 'v = 2\na\nb\nc\nw = 1\n' > "$R/f97.py"; git -C "$R" commit -qam "c2: w 1"
printf 'v = 2\na\nb\nc\nw = 2\n' > "$R/f97.py"; git -C "$R" commit -qam "c3: w 2"
git -C "$R" checkout -q main
printf 'v = 9\na\nb\nc\n' > "$R/f97.py"; git -C "$R" commit -qam "main: v 9"
printf 'v = 2\na\nb\nc\nw = 2\n' > "$R/f97.py"; git -C "$R" commit -qam "squash, resolved to the branch"
printf 'v = 2\na\nb\nc\nw = 3\n' > "$R/f97.py"; git -C "$R" commit -qam "follow-up: w 3"
assert_exit "fixture-97 hand-resolved squash equal to the head, then a follow-up -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 98: fixture 92's history (no net change, the first commits squashed, the restore
# dropped), with the squash on a side branch where another PR edits the next line,
# merged into main as a release merge.
R="$(mk_repo)"; printf 'LEVEL = "info"\na\nb\nc\n' > "$R/f98.py"; git -C "$R" add -A && git -C "$R" commit -qm f98
git -C "$R" checkout -q -b feat
printf 'a\nb\nc\n' > "$R/f98.py"; git -C "$R" commit -qam "b1: drop level"
printf 'LEVEL = "debug"\na\nb\nc\n' > "$R/f98.py"; git -C "$R" commit -qam "b2: level debug"
printf 'LEVEL = "info"\na\nb\nc\n' > "$R/f98.py"; git -C "$R" commit -qam "b3: back to info (never landed)"
git -C "$R" checkout -q main; git -C "$R" checkout -q -b develop
printf 'LEVEL = "debug"\na\nb\nc\n' > "$R/f98.py"; git -C "$R" commit -qam "squash b1 and b2"
printf 'LEVEL = "debug"\nA\nb\nc\n' > "$R/f98.py"; git -C "$R" commit -qam "another PR: A"
git -C "$R" checkout -q main; printf 'u\n' > "$R/u98.txt"; git -C "$R" add -A && git -C "$R" commit -qm "main: u98"
git -C "$R" merge -q --no-ff --no-edit develop >/dev/null 2>&1
OUT98=$(out_of "$R" feat main); RC98=$?
assert_exit "fixture-98 no net change, release merge with an adjacent edit -> flagged" 3 "$RC98"
assert_exit "fixture-98 lists only b3" 0 "$(has "$OUT98" 'b3: back to info')"
assert_exit "fixture-98 does not list b2" 1 "$(has "$OUT98" 'b2: level debug')"
rm -rf "$R"

# 99: after the squash a later PR moves the change's files into an archive directory
# and edits one (Spectra's archive step, reported on #399 on 2026-10-24).
R="$(mk_repo)"; mkdir -p "$R/openspec/changes/x"; printf 'base\n' > "$R/openspec/README"; git -C "$R" add -A && git -C "$R" commit -qm os
git -C "$R" checkout -q -b feat
printf '# x\nwhy\n' > "$R/openspec/changes/x/proposal.md"; printf -- '- [ ] t1\n' > "$R/openspec/changes/x/tasks.md"
git -C "$R" add -A && git -C "$R" commit -qm "propose x"
printf -- '- [x] t1\n' > "$R/openspec/changes/x/tasks.md"; git -C "$R" commit -qam "apply x"
git -C "$R" checkout -q main
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash x" >/dev/null 2>&1
mkdir -p "$R/openspec/changes/archive/2026-10-24-x"
git -C "$R" mv openspec/changes/x/proposal.md openspec/changes/x/tasks.md openspec/changes/archive/2026-10-24-x/ 2>/dev/null
printf -- '- [x] t1 (archived)\n' > "$R/openspec/changes/archive/2026-10-24-x/tasks.md"; git -C "$R" add -A && git -C "$R" commit -qm "archive x"
assert_exit "fixture-99 squash, then the change archived and edited -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 100: dropped commits whose only change is a blank line or a file mode (not effects
# under SPEC.md's definition).
R="$(mk_repo)"; printf 'a\n\nb\n' > "$R/f100.py"; git -C "$R" add -A && git -C "$R" commit -qm f100
git -C "$R" checkout -q -b feat
printf 'a\n\nb\nx = 1\n' > "$R/f100.py"; git -C "$R" commit -qam "c1: x"
printf 'a\nb\nx = 1\n' > "$R/f100.py"; git -C "$R" commit -qam "c2: drop a blank line (never landed)"
chmod +x "$R/f100.py"; git -C "$R" commit -qam "c3: executable (never landed)"
git -C "$R" checkout -q main
printf 'a\n\nb\nx = 1\n' > "$R/f100.py"; git -C "$R" commit -qam "squash c1"
assert_exit "fixture-100 dropped blank-line and mode-only commits -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 101: quotation marks that look like the closing quote are replaced in subjects.
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'q\n' > "$R/q101.txt"; git -C "$R" add -A && git -C "$R" commit -qm "fix＂ ” (end of list) “x”"
git -C "$R" checkout -q main
OUT101=$(out_of "$R" feat main)
assert_exit "fixture-101 fullwidth and curly double quotes become ?" 1 "$(printf '%s' "$OUT101" | grep -q '＂\|“\|”'; echo $?)"
rm -rf "$R"

# ── Fixtures 102–111 (#399 round 12): pins for the two-way-diff checks ──

# 102 (round 13: a follow-up keeps P0 from deciding it): the branch's whole net change
# is a line and an empty file; another PR put the same line in main first. That commit
# does not hold the net change (no empty file there), so the branch landed at the squash.
R="$(mk_repo)"; printf 'a\nb\n' > "$R/f102.py"; git -C "$R" add -A && git -C "$R" commit -qm f102
git -C "$R" checkout -q -b feat
printf 'a\nb\nx = 1\n' > "$R/f102.py"; : > "$R/e102.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1: x and an empty file"
git -C "$R" checkout -q main
printf 'a\nb\nx = 1\n' > "$R/f102.py"; git -C "$R" commit -qam "another PR: the same x"
: > "$R/e102.txt"; printf 'v\n' > "$R/v102.txt"; git -C "$R" add -A && git -C "$R" commit -qm "squash feat, with a version file"
printf 'a\nb\nx = 2\n' > "$R/f102.py"; git -C "$R" commit -qam "follow-up: x 2"
assert_exit "fixture-102 an empty file decides where the branch landed -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 102b: the mirror: the branch deletes an empty file; another PR made the same line
# change but kept the file, so its commit does not hold the net change either.
R="$(mk_repo)"; printf 'a\nb\n' > "$R/f102b.py"; : > "$R/e102b.txt"; git -C "$R" add -A && git -C "$R" commit -qm f102b
git -C "$R" checkout -q -b feat
printf 'a\nb\nx = 1\n' > "$R/f102b.py"; git -C "$R" rm -q e102b.txt; git -C "$R" add -A && git -C "$R" commit -qm "c1: x, the empty file deleted"
git -C "$R" checkout -q main
printf 'a\nb\nx = 1\n' > "$R/f102b.py"; git -C "$R" commit -qam "another PR: the same x"
git -C "$R" rm -q e102b.txt; printf 'v\n' > "$R/v102b.txt"; git -C "$R" add -A && git -C "$R" commit -qm "squash feat, with a version file"
printf 'a\nb\nx = 2\n' > "$R/f102b.py"; git -C "$R" commit -qam "follow-up: x 2"
assert_exit "fixture-102b a deleted empty file decides where the branch landed -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 103, 104: a final newline and a blank line are not effects, so a squash that left
# them out still holds the branch's net change, and every commit is checked there:
# c3's line, which main edited after landing, landed. (Counted as an effect, the
# squash would not hold it, only c1 would land, and c3 would be checked at the tip
# and listed.)
R="$(mk_repo)"; printf 'a\nb' > "$R/f103.py"; git -C "$R" add -A && git -C "$R" commit -qm f103
git -C "$R" checkout -q -b feat
printf 'x = 1\na\nb' > "$R/f103.py"; git -C "$R" commit -qam "c1: x"
printf 'x = 1\na\nb\n' > "$R/f103.py"; git -C "$R" commit -qam "c2: final newline"
printf 'x = 1\na\nb\ny = 1\n' > "$R/f103.py"; git -C "$R" commit -qam "c3: y"
git -C "$R" checkout -q main
printf 'x = 1\na\nb\ny = 1' > "$R/f103.py"; git -C "$R" commit -qam "squash feat, no final newline"
printf 'x = 1\na\nb\ny = 2' > "$R/f103.py"; git -C "$R" commit -qam "main: y 2"
assert_exit "fixture-103 a final newline does not move the landing commit -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

R="$(mk_repo)"; printf 'a\nb\nc\n' > "$R/f104.py"; git -C "$R" add -A && git -C "$R" commit -qm f104
git -C "$R" checkout -q -b feat
printf 'x = 1\na\nb\nc\n' > "$R/f104.py"; git -C "$R" commit -qam "c1: x"
printf 'x = 1\na\n\nb\nc\n' > "$R/f104.py"; git -C "$R" commit -qam "c2: a blank line"
printf 'x = 1\na\n\nb\nc\ny = 1\n' > "$R/f104.py"; git -C "$R" commit -qam "c3: y"
git -C "$R" checkout -q main
printf 'x = 1\na\nb\nc\ny = 1\n' > "$R/f104.py"; git -C "$R" commit -qam "squash feat, without the blank line"
printf 'x = 1\na\nb\nc\ny = 2\n' > "$R/f104.py"; git -C "$R" commit -qam "main: y 2"
assert_exit "fixture-104 a blank line does not move the landing commit -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 105: a commit that renames a file and edits it, squashed with the rest; renames are
# not paired, so its lines are compared under each path.
R="$(mk_repo)"; printf 'r1\nr2\nr3\nr4\nr5\n' > "$R/r105.txt"; git -C "$R" add -A && git -C "$R" commit -qm r105
git -C "$R" checkout -q -b feat
git -C "$R" mv r105.txt s105.txt; printf 'r1\nr2\nR3\nr4\nr5\n' > "$R/s105.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1: rename and edit"
printf 'z\n' > "$R/z105.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c2: z"
git -C "$R" checkout -q main
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat" >/dev/null 2>&1
printf 'r1\nr2\nR3\nr4\nr5\nr6\n' > "$R/s105.txt"; git -C "$R" commit -qam "follow-up: r6"
assert_exit "fixture-105 rename with an edit, squashed, then a follow-up -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 106: a branch with no net change whose middle commit was cherry-picked alone: no
# prefix holds, so it came in piece by piece and the tip is used (the restore that
# undid the cherry-picked change is missing there).
R="$(mk_repo)"; printf 'P = 0\na\nb\nc\nR = 0\n' > "$R/f106.py"; git -C "$R" add -A && git -C "$R" commit -qm f106
git -C "$R" checkout -q -b feat
printf 'P = 1\na\nb\nc\nR = 0\n' > "$R/f106.py"; git -C "$R" commit -qam "c1: P 1"
printf 'P = 1\na\nb\nc\nR = 1\n' > "$R/f106.py"; git -C "$R" commit -qam "c2: R 1"
printf 'P = 1\na\nb\nc\nR = 0\n' > "$R/f106.py"; git -C "$R" commit -qam "c3: R back to 0 (never landed)"
printf 'P = 0\na\nb\nc\nR = 0\n' > "$R/f106.py"; git -C "$R" commit -qam "c4: P back to 0"
git -C "$R" checkout -q main; git -C "$R" cherry-pick "$(git -C "$R" rev-parse feat~2)" >/dev/null 2>&1
OUT106=$(out_of "$R" feat main); RC106=$?
assert_exit "fixture-106 no net change, a middle commit cherry-picked -> flagged" 3 "$RC106"
assert_exit "fixture-106 lists c3" 0 "$(has "$OUT106" 'c3: R back to 0')"
rm -rf "$R"

# 108: a commit that only deletes a blank line is not an effect, so the squash that
# kept the blank line still holds the branch's net change, and every commit is checked
# there: c3's line, which main edited after landing, landed. (Counted as an effect, the
# blank line would leave only c1 landed, and c3 would be checked at the tip and listed.)
R="$(mk_repo)"; printf 'a\n\nb\nc\n' > "$R/f108.py"; git -C "$R" add -A && git -C "$R" commit -qm f108
git -C "$R" checkout -q -b feat
printf 'x = 1\na\n\nb\nc\n' > "$R/f108.py"; git -C "$R" commit -qam "c1: x"
printf 'x = 1\na\nb\nc\n' > "$R/f108.py"; git -C "$R" commit -qam "c2: drops a blank line"
printf 'x = 1\na\nb\nc\ny = 1\n' > "$R/f108.py"; git -C "$R" commit -qam "c3: y"
git -C "$R" checkout -q main
printf 'x = 1\na\n\nb\nc\ny = 1\n' > "$R/f108.py"; git -C "$R" commit -qam "squash feat, the blank line kept"
printf 'x = 1\na\n\nb\nc\ny = 2\n' > "$R/f108.py"; git -C "$R" commit -qam "main: y 2"
assert_exit "fixture-108 a blank-line deletion does not move the landing commit -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 109, 110: the branch adds a file and deletes it again, and main has a file of its own
# by that name. The deletion is checked at the landing commit by its line, which is not
# in place there (main's file has its own text), so it landed. Also when git writes the
# name with a trailing tab (a space in it) or quotes it (non-ASCII under core.quotePath):
# read wrongly, the name looks like a path with no lines, still present.
for N in 109 110; do
  if [ "$N" = 109 ]; then F="q $N.txt"; else F="$(printf 'q\303\251%s.txt' "$N")"; fi
  R="$(mk_repo)"; printf 'a\n' > "$R/f$N.py"; git -C "$R" add -A && git -C "$R" commit -qm "f$N"
  git -C "$R" checkout -q -b feat
  printf 'a\nb = 1\n' > "$R/f$N.py"; git -C "$R" commit -qam "c0: b"
  printf 'x = 1\n' > "$R/$F"; git -C "$R" add -A && git -C "$R" commit -qm "c1: x in a new file"
  git -C "$R" rm -q -- "$F" && git -C "$R" commit -qm "c2: the file deleted"
  git -C "$R" checkout -q main
  printf 'm\n' > "$R/$F"; git -C "$R" add -A && git -C "$R" commit -qm "main: its own file by that name"
  printf 'a\nb = 1\n' > "$R/f$N.py"; printf 'v\n' > "$R/v$N.txt"; git -C "$R" add -A && git -C "$R" commit -qm "squash feat, with a version file"
  assert_exit "fixture-$N a file added and deleted, main has its own by that name -> NOT flagged" 0 "$(run_helper "$R" feat main)"
  rm -rf "$R"
done

# 107: nothing landed; a line one commit added and the next rewrote is not an effect
# the head shows, so at the tip only the rewrite is listed.
R="$(mk_repo)"; printf 'a\n' > "$R/f107.py"; git -C "$R" add -A && git -C "$R" commit -qm f107
git -C "$R" checkout -q -b feat
printf 'a\nx = 1\n' > "$R/f107.py"; git -C "$R" commit -qam "c1: x 1"
printf 'a\nx = 2\n' > "$R/f107.py"; git -C "$R" commit -qam "c2: x 2"
git -C "$R" checkout -q main
OUT107=$(out_of "$R" feat main); RC107=$?
assert_exit "fixture-107 nothing landed -> flagged" 3 "$RC107"
assert_exit "fixture-107 lists c2" 0 "$(has "$OUT107" 'c2: x 2')"
assert_exit "fixture-107 does not list c1 (its line is not in the head)" 1 "$(has "$OUT107" 'c1: x 1')"
rm -rf "$R"

# 111: a candidate path with byte \001 is refused (exit 4). The tree map writes a
# newline in a name as \001, so main's own "q<LF>r.txt" would otherwise read as the
# branch's "q<\001>r.txt", and the branch's file, which never landed, as present.
R="$(mk_repo)"; B111=$(printf 'x\n' | git -C "$R" hash-object -w --stdin)
I111="$(mktemp)"; rm -f "$I111"
GIT_INDEX_FILE="$I111" git -C "$R" read-tree main
GIT_INDEX_FILE="$I111" git -C "$R" update-index --add --cacheinfo "100644,$B111,q$(printf '\001')r.txt"
F111=$(git -C "$R" commit-tree "$(GIT_INDEX_FILE="$I111" git -C "$R" write-tree)" -p main -m "c1: q-SOH-r (never landed)")
git -C "$R" update-ref refs/heads/feat "$F111"; rm -f "$I111"
GIT_INDEX_FILE="$I111" git -C "$R" read-tree main
GIT_INDEX_FILE="$I111" git -C "$R" update-index --add --cacheinfo "100644,$B111,q
r.txt"
M111=$(git -C "$R" commit-tree "$(GIT_INDEX_FILE="$I111" git -C "$R" write-tree)" -p main -m "main: its own q-LF-r")
git -C "$R" update-ref refs/heads/main "$M111"; rm -f "$I111"
assert_exit "fixture-111 a candidate path with byte 001 -> skip, not a verdict" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixtures 112–119 (#399 round 13): settings and names the two-way diffs must not follow ──

# 112, 113: diff.interHunkContext and GIT_DIFF_OPTS put context lines between nearby
# changes. A dropped restore (decision-table row 16) next to a landed change must
# still be listed, and a squash followed by main's edit of the branch's line (#399's
# second shape) must still be clean.
mk112() { # -> repo: base 1..20; c1 line 14 -> Y; c2 restores it (never landed); c3 line 10 -> X
  local R; R="$(mk_repo)"; seq 1 20 > "$R/n.txt"; git -C "$R" add -A && git -C "$R" commit -qm n
  git -C "$R" checkout -q -b feat
  sed 's/^14$/Y/' "$R/n.txt" > "$R/t" && mv "$R/t" "$R/n.txt"; git -C "$R" commit -qam "c1: 14 to Y"
  sed 's/^Y$/14/' "$R/n.txt" > "$R/t" && mv "$R/t" "$R/n.txt"; git -C "$R" commit -qam "c2: 14 back (never landed)"
  sed 's/^10$/X/' "$R/n.txt" > "$R/t" && mv "$R/t" "$R/n.txt"; git -C "$R" commit -qam "c3: 10 to X"
  git -C "$R" checkout -q main; printf 'o\n' > "$R/other.txt"; git -C "$R" add -A && git -C "$R" commit -qm "another PR"
  seq 1 20 | sed -e 's/^14$/Y/' -e 's/^10$/X/' > "$R/n.txt"; git -C "$R" commit -qam "squash c1 c3"
  echo "$R"
}
mk112b() { # -> repo: base a..e; c1 a -> A; c2 c -> C; main b -> B; squash; main then c -> C2
  local R; R="$(mk_repo)"; printf 'a\nb\nc\nd\ne\n' > "$R/f.txt"; git -C "$R" add -A && git -C "$R" commit -qm f
  git -C "$R" checkout -q -b feat
  printf 'A\nb\nc\nd\ne\n' > "$R/f.txt"; git -C "$R" commit -qam "c1: A"
  printf 'A\nb\nC\nd\ne\n' > "$R/f.txt"; git -C "$R" commit -qam "c2: C"
  git -C "$R" checkout -q main
  printf 'a\nB\nc\nd\ne\n' > "$R/f.txt"; git -C "$R" commit -qam "another PR: B"
  printf 'A\nB\nC\nd\ne\n' > "$R/f.txt"; git -C "$R" commit -qam "squash feat"
  printf 'A\nB\nC2\nd\ne\n' > "$R/f.txt"; git -C "$R" commit -qam "follow-up: C2"
  echo "$R"
}
R="$(mk112)"; git -C "$R" config diff.interHunkContext 5
OUT112=$(out_of "$R" feat main); RC112=$?
assert_exit "fixture-112 diff.interHunkContext: a dropped restore next to a landed change -> flagged" 3 "$RC112"
assert_exit "fixture-112 lists c2" 0 "$(has "$OUT112" 'c2: 14 back')"
rm -rf "$R"
R="$(mk112b)"; git -C "$R" config diff.interHunkContext 1
assert_exit "fixture-112b diff.interHunkContext: squash, then main edits the branch's line -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"
R="$(mk112)"
OUT113=$(GIT_DIFF_OPTS=--unified=3 out_of "$R" feat main); RC113=$?
assert_exit "fixture-113 GIT_DIFF_OPTS: a dropped restore next to a landed change -> flagged" 3 "$RC113"
assert_exit "fixture-113 lists c2" 0 "$(has "$OUT113" 'c2: 14 back')"
rm -rf "$R"
R="$(mk112b)"
assert_exit "fixture-113b GIT_DIFF_OPTS: squash, then main edits the branch's line -> NOT flagged" 0 "$(GIT_DIFF_OPTS=-u1 run_helper "$R" feat main)"
rm -rf "$R"

# 114: a git without --no-relative (before 2.28) answers the same: the two-way diffs
# do not use it (the helper runs at the top level, where diff.relative changes nothing).
R="$(mk112b)"; W114="$(mktemp -d)"; G114="$(command -v git)"
printf '#!/bin/sh\nfor a in "$@"; do [ "$a" = --no-relative ] && { echo "error: unknown option" >&2; exit 129; }; done\nexec "%s" "$@"\n' "$G114" > "$W114/git"
chmod +x "$W114/git"
assert_exit "fixture-114 git without --no-relative: squash, then main edits the branch's line -> NOT flagged" 0 "$(PATH="$W114:$PATH" run_helper "$R" feat main)"
rm -rf "$R" "$W114"

# 115: a last line without a final newline, re-added with it after lines another PR
# appended: the same line, not a change.
R="$(mk_repo)"; printf 'top\n' > "$R/f115.py"; git -C "$R" add -A && git -C "$R" commit -qm f115
git -C "$R" checkout -q -b feat
printf 'top\nadded = 1' > "$R/f115.py"; git -C "$R" commit -qam "c1: added, no final newline"
printf 'top\nadded = 1\nz = 9\n' > "$R/f115.py"; git -C "$R" commit -qam "c2: z"
git -C "$R" checkout -q main
printf 'top\nm = 0\n' > "$R/f115.py"; git -C "$R" commit -qam "another PR: m"
printf 'top\nm = 0\nadded = 1\nz = 9\n' > "$R/f115.py"; git -C "$R" commit -qam "squash feat"
assert_exit "fixture-115 no final newline, re-added after another PR's lines -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 116: row 9 with a name that has a space and a character git quotes: git writes the
# quoted name followed by a tab.
R="$(mk_repo)"; printf 'k\n' > "$R/keep.txt"; git -C "$R" add -A && git -C "$R" commit -qm keep
F116="$(printf 'caf\303\251 x.txt')"
git -C "$R" checkout -q -b feat
printf 's\n' > "$R/$F116"; git -C "$R" add -A && git -C "$R" commit -qm "c1: scratch"
git -C "$R" rm -q -- "$F116" && git -C "$R" commit -qm "c2: scratch deleted"
printf 'k2\n' > "$R/keep.txt"; git -C "$R" commit -qam "c3: keep"
git -C "$R" checkout -q main
printf 'm\n' > "$R/$F116"; git -C "$R" add -A && git -C "$R" commit -qm "main: its own file by that name"
printf 'k2\n' > "$R/keep.txt"; printf 'v\n' > "$R/v116.txt"; git -C "$R" add -A && git -C "$R" commit -qm "squash feat, with a version file"
assert_exit "fixture-116 a name with a space and a quoted character -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 117: a file under a directory named like a path the branch touched is not one of
# the branch's paths, whatever its name: a name that decodes to a newline and a
# forged record cannot hide the commit whose deletion never landed.
R="$(mk_repo)"; printf '1\n2\n3\n4\n5\n' > "$R/f117.txt"; git -C "$R" add -A && git -C "$R" commit -qm f117
git -C "$R" checkout -q -b feat
printf '1\n2\n4\n5\n' > "$R/f117.txt"; : > "$R/x117"; git -C "$R" add -A && git -C "$R" commit -qm "c1: drop 3, add x117 (never landed)"
printf 'g\n' > "$R/g117.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c2: g"
git -C "$R" checkout -q main
B117=$(printf 'z\n' | git -C "$R" hash-object -w --stdin); I117="$(mktemp)"; rm -f "$I117"
GIT_INDEX_FILE="$I117" git -C "$R" read-tree main
GIT_INDEX_FILE="$I117" git -C "$R" update-index --add --cacheinfo "100644,$B117,x117/q
C	3	f117.txt"
M117=$(git -C "$R" commit-tree "$(GIT_INDEX_FILE="$I117" git -C "$R" write-tree)" -p main -m "main: a file under x117/")
git -C "$R" update-ref refs/heads/main "$M117"; rm -f "$I117"; git -C "$R" checkout -q -f main
printf 'g\n' > "$R/g117.txt"; git -C "$R" add g117.txt && git -C "$R" commit -qm "squash c2"
OUT117=$(out_of "$R" feat main); RC117=$?
assert_exit "fixture-117 a forged name under a directory of the branch's path -> flagged" 3 "$RC117"
assert_exit "fixture-117 lists c1" 0 "$(has "$OUT117" 'c1: drop 3')"
rm -rf "$R"

# 118: git's own messages never reach the helper's stderr: an invalid attribute name
# in .gitattributes is printed by git diff verbatim, escape bytes included.
R="$(mk_repo)"; printf '* \033[31mREAD-THIS\033[0m\n* check-merge-completeness:\n' > "$R/.gitattributes"
printf 'x = 1\n' > "$R/f118.py"; git -C "$R" add -A && git -C "$R" commit -qm f118
git -C "$R" checkout -q -b feat
printf 'x = 2\n' > "$R/f118.py"; git -C "$R" commit -qam "c1: x 2"
printf 'x = 2\ny = 1\n' > "$R/f118.py"; git -C "$R" commit -qam "c2: y"
git -C "$R" checkout -q main
printf 'x = 2\ny = 1\n' > "$R/f118.py"; git -C "$R" commit -qam "squash feat"
printf 'x = 3\ny = 1\n' > "$R/f118.py"; git -C "$R" commit -qam "follow-up"
E118="$(mktemp)"; "${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main > /dev/null 2> "$E118"
assert_exit "fixture-118 no escape byte reaches stderr" 1 "$(LC_ALL=C grep -q "$(printf '\033')" "$E118"; echo $?)"
assert_exit "fixture-118 stderr has no line but the helper's own" 1 "$(grep -v '^check-merge-completeness: ' "$E118" | grep -q .; echo $?)"
rm -rf "$R" "$E118"

# 119: a commit with more paths than the helper puts on a command line (over 64 KB
# of names): the two trees are compared whole and the listed paths kept.
R="$(mk_repo)"; printf 'x = 1\n' > "$R/f119.py"; git -C "$R" add -A && git -C "$R" commit -qm f119
git -C "$R" checkout -q -b feat
B119=$(printf 'v\n' | git -C "$R" hash-object -w --stdin)
awk -v b="$B119" 'BEGIN { for (i = 0; i < 6000; i++) printf "100644 %s 0\tvendor/package-%05d/module.txt\n", b, i }' \
  | git -C "$R" update-index --add --index-info
git -C "$R" commit -qm "c1: vendor 6000 files"
git -C "$R" rm -rq --cached vendor && git -C "$R" commit -qm "c2: unvendor"
printf 'x = 2\n' > "$R/f119.py"; git -C "$R" commit -qam "c3: x 2"
printf 'x = 2\ny = 1\n' > "$R/f119.py"; git -C "$R" commit -qam "c4: y"
git -C "$R" checkout -q main
printf 'x = 2\ny = 1\n' > "$R/f119.py"; git -C "$R" commit -qam "squash feat"
assert_exit "fixture-119 a commit with 6000 paths -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 120–122: renames. A moved file is not all new lines: main's edit of the file
# before the squash (merge-ort follows the rename) does not keep the branch from
# landing, and a rename that never landed is still listed.
R="$(mk_repo)"; mkdir -p "$R/src"; printf 'import os\n\ndef run():\n    return os.getcwd()\n' > "$R/src/u120.py"
git -C "$R" add -A && git -C "$R" commit -qm u120
git -C "$R" checkout -q -b feat
mkdir -p "$R/lib"; git -C "$R" mv src/u120.py lib/u120.py && git -C "$R" commit -qm "c1: move u120 to lib"
printf 'r\n' > "$R/r120.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c2: r120"
git -C "$R" checkout -q main
printf 'import os\n\ndef run():\n    return os.getcwd() or "."\n' > "$R/src/u120.py"; git -C "$R" commit -qam "another PR: fallback"
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat" >/dev/null 2>&1
assert_exit "fixture-120 a moved file main edited before the squash -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

mk121() { # -> repo: c1 renames o121.py to n121.py and edits r1; c2 adds z121; main edits r8
  local R; R="$(mk_repo)"; printf 'r1\nr2\nr3\nr4\nr5\nr6\nr7\nr8\n' > "$R/o121.py"; git -C "$R" add -A && git -C "$R" commit -qm o121
  git -C "$R" checkout -q -b feat
  git -C "$R" mv o121.py n121.py; printf 'R1\nr2\nr3\nr4\nr5\nr6\nr7\nr8\n' > "$R/n121.py"
  git -C "$R" add -A && git -C "$R" commit -qm "c1: rename to n121, edit r1"
  printf 'z\n' > "$R/z121.py"; git -C "$R" add -A && git -C "$R" commit -qm "c2: z121"
  git -C "$R" checkout -q main
  printf 'r1\nr2\nr3\nr4\nr5\nr6\nr7\nr8 = main\n' > "$R/o121.py"; git -C "$R" commit -qam "another PR: r8"
  echo "$R"
}
R="$(mk121)"
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat" >/dev/null 2>&1
assert_exit "fixture-121 renamed and edited, main edited another line first -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"
R="$(mk121)"
printf 'z\n' > "$R/z121.py"; git -C "$R" add -A && git -C "$R" commit -qm "squash c2 only"
OUT122=$(out_of "$R" feat main); RC122=$?
assert_exit "fixture-122 the rename never landed -> exit 4 (a move)" 4 "$RC122"
rm -rf "$R"

# 123: the tip has the head's content on every path the branch touched: nothing to
# land, whatever commit holds the net change first (#399's Expected). (a) the squash
# was resolved to the branch's tree after another PR set the same line and added the
# same file; (b) the squash kept main's value and main set the branch's value later.
mk123() { # -> repo: c1 v 2, c2 v back to 1, c3 adds g123; main: another PR sets v 3 and adds g123
  local R; R="$(mk_repo)"; printf 'v = 1\n' > "$R/f123.py"; git -C "$R" add -A && git -C "$R" commit -qm f123
  git -C "$R" checkout -q -b feat
  printf 'v = 2\n' > "$R/f123.py"; git -C "$R" commit -qam "c1: v 2"
  printf 'v = 1\n' > "$R/f123.py"; git -C "$R" commit -qam "c2: v back to 1"
  printf 'z\n' > "$R/g123.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c3: g123"
  git -C "$R" checkout -q main
  printf 'v = 3\n' > "$R/f123.py"; printf 'z\n' > "$R/g123.txt"; git -C "$R" add -A && git -C "$R" commit -qm "another PR: v 3, g123"
  echo "$R"
}
R="$(mk123)"
printf 'v = 1\n' > "$R/f123.py"; git -C "$R" commit -qam "squash feat, resolved to the branch"
assert_exit "fixture-123a the squash's tree is the head's -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"
R="$(mk123)"
printf 'w\n' > "$R/w123.txt"; git -C "$R" add -A && git -C "$R" commit -qm "squash feat, keeping v 3"
printf 'v = 1\n' > "$R/f123.py"; git -C "$R" commit -qam "main: v back to 1"
assert_exit "fixture-123b main later set the head's value -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 124, 125: repeated lines. A position says where a line is only while its text is
# unique: with two copies, git may put main's edit on one copy when it builds the
# squash and pair the copies the other way in the diffs that check a commit. A clean
# squash is not flagged for that (#399 verify round 12). (A copy that never landed is
# still flagged when the copies agree: fixtures 82 and 84.)
R="$(mk_repo)"; printf 'def load(path):\n    with open(path) as f:\n        data = f.read()\n    return data\n' > "$R/io124.py"
git -C "$R" add -A && git -C "$R" commit -qm io124
git -C "$R" checkout -q -b feat
printf 'def load(path):\n    with open(path) as f:\n        data = f.read()\n    return data\n\ndef load_bytes(path):\n    with open(path) as f:\n        data = f.read()\n    return data\n' > "$R/io124.py"
git -C "$R" commit -qam "c1: load_bytes, a copy of load"
printf 'def load_text(path):\n    with open(path) as f:\n        data = f.read()\n    return data\n\ndef load_bytes(path):\n    with open(path) as f:\n        data = f.read()\n    return data\n' > "$R/io124.py"
git -C "$R" commit -qam "c2: load renamed load_text"
git -C "$R" checkout -q main
printf 'def load(path):\n    with open(path) as f:\n        data = f.read().strip()\n    return data\n' > "$R/io124.py"; git -C "$R" commit -qam "another PR: strip"
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat" >/dev/null 2>&1
assert_exit "fixture-124 a copied function, main's edit put on the copy by the squash -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

R="$(mk_repo)"; printf 'A\nB\n' > "$R/f125.txt"; git -C "$R" add -A && git -C "$R" commit -qm f125
git -C "$R" checkout -q -b feat
printf 'A\nB\nA\nB\n' > "$R/f125.txt"; git -C "$R" commit -qam "c1: the block twice"
printf 'A1\nB\nA\nB\n' > "$R/f125.txt"; git -C "$R" commit -qam "c2: A to A1"
git -C "$R" checkout -q main
printf 'A\nBm\n' > "$R/f125.txt"; git -C "$R" commit -qam "another PR: B to Bm"
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat" >/dev/null 2>&1
assert_exit "fixture-125 a duplicated block, main's edit of one copy -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"


# 127: a branch with no net change whose landed prefix is older than the newest 20
# earlier commits: the search runs out, so the tip is used (it was left at the
# merge-base, where no commit can be an orphan, and exited 0).
R="$(mk_repo)"; printf 'x = 1\n' > "$R/f127.py"; printf 'w\n' > "$R/w127.txt"; git -C "$R" add -A && git -C "$R" commit -qm f127
git -C "$R" checkout -q -b feat
printf 'w\nnote\n' > "$R/w127.txt"; git -C "$R" commit -qam "c0: note"
printf 'x = 2\n' > "$R/f127.py"; git -C "$R" commit -qam "c1: x 2"
printf 'x = 2\ny = 0\n' > "$R/f127.py"; git -C "$R" commit -qam "c2: y"
for i in $(seq 1 21); do printf 'x = 2\ny = %s\n' "$i" > "$R/f127.py"; git -C "$R" commit -qam "y $i"; done
printf 'x = 1\n' > "$R/f127.py"; printf 'w\n' > "$R/w127.txt"; git -C "$R" commit -qam "last: back to the start"
git -C "$R" checkout -q main
printf 'o\n' > "$R/o127.txt"; git -C "$R" add -A && git -C "$R" commit -qm "another PR"
printf 'x = 2\n' > "$R/f127.py"; printf 'w\nnote\n' > "$R/w127.txt"; git -C "$R" commit -qam "squash c0 c1"
OUT127=$(out_of "$R" feat main); RC127=$?
assert_exit "fixture-127 no net change, landed prefix beyond the tries -> flagged at the tip" 3 "$RC127"
assert_exit "fixture-127 lists the last commit" 0 "$(has "$OUT127" 'last: back to the start')"
rm -rf "$R"

# 128: the user's porcelain diff settings change nothing (each one is overridden on
# the command line): no prefixes, mnemonic prefixes, no rename detection, raw
# non-ASCII names, color, another algorithm, a submodule log format.
cfg128() { for kv in diff.noprefix=true diff.mnemonicPrefix=true diff.renames=false core.quotePath=false \
                     color.diff=always color.ui=always diff.algorithm=histogram diff.indentHeuristic=false \
                     diff.submodule=log diff.interHunkContext=4 diff.suppressBlankEmpty=true; do
             git -C "$1" config "${kv%%=*}" "${kv#*=}"; done; }
R="$(mk121)"
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat" >/dev/null 2>&1
cfg128 "$R"
assert_exit "fixture-128 hostile diff settings: rename and edit, main's edit first -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"
R="$(mk112)"; cfg128 "$R"
OUT128=$(out_of "$R" feat main); RC128=$?
assert_exit "fixture-128 hostile diff settings: a dropped restore -> flagged" 3 "$RC128"
assert_exit "fixture-128 lists c2" 0 "$(has "$OUT128" 'c2: 14 back')"
rm -rf "$R"
R="$(mk_repo)"; F128="$(printf 'caf\303\251.txt')"; printf 'k\n' > "$R/$F128"; git -C "$R" add -A && git -C "$R" commit -qm f128
git -C "$R" checkout -q -b feat
printf 'k\nx = 1\n' > "$R/$F128"; git -C "$R" commit -qam "c1: x 1"
printf 'k\nx = 1\ny = 1\n' > "$R/$F128"; git -C "$R" commit -qam "c2: y"
git -C "$R" checkout -q main
printf 'k\nx = 1\ny = 1\n' > "$R/$F128"; git -C "$R" commit -qam "squash feat"
printf 'k\nx = 2\ny = 1\n' > "$R/$F128"; git -C "$R" commit -qam "follow-up"
cfg128 "$R"
assert_exit "fixture-128 hostile diff settings: a non-ASCII name, squash, then main's edit -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 129: the other marks that look like a double quote are replaced as well (U+2033,
# U+02BA, U+3003, U+201E, U+275E, U+05F4, and U+02EE since round 14).
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'q\n' > "$R/q129.txt"; git -C "$R" add -A && git -C "$R" commit -qm "$(printf 'fix\342\200\263 a\312\272 b\343\200\203 c\342\200\236 d\342\235\236 e\327\264 f\313\256')"
git -C "$R" checkout -q main
OUT129=$(out_of "$R" feat main)
assert_exit "fixture-129 the subject's quote lookalikes become ?" 0 "$(has "$OUT129" '"fix? a? b? c? d? e? f?"')"
rm -rf "$R"

# 115b: the mirror of 115: the squash writes the branch's last line without its final
# newline, after a line another PR appended; a follow-up then edits it (at the tip the
# line is gone, so only the landing commit can clear the commit).
R="$(mk_repo)"; printf 'top\n' > "$R/f115b.py"; git -C "$R" add -A && git -C "$R" commit -qm f115b
git -C "$R" checkout -q -b feat
printf 'top\nadded = 1\n' > "$R/f115b.py"; git -C "$R" commit -qam "c1: added"
printf 'z\n' > "$R/z115b.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c2: z"
git -C "$R" checkout -q main
printf 'top\nm = 0\n' > "$R/f115b.py"; git -C "$R" commit -qam "another PR: m"
printf 'top\nm = 0\nadded = 1' > "$R/f115b.py"; printf 'z\n' > "$R/z115b.txt"; git -C "$R" add -A && git -C "$R" commit -qm "squash feat, no final newline"
printf 'top\nm = 0\nadded = 2' > "$R/f115b.py"; git -C "$R" commit -qam "follow-up: added 2"
assert_exit "fixture-115b the branch's last line written without its final newline -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 130: a directory at a path where the branch added an empty file is not that file:
# another PR's commit with x130/ and the same line does not hold the branch's net
# change, and the squash never happened, so the commit is listed.
R="$(mk_repo)"; printf 'a\n' > "$R/f130.py"; git -C "$R" add -A && git -C "$R" commit -qm f130
git -C "$R" checkout -q -b feat
printf 'a\nx = 1\n' > "$R/f130.py"; : > "$R/x130"; git -C "$R" add -A && git -C "$R" commit -qm "c1: x and an empty file x130 (never landed)"
git -C "$R" checkout -q main
mkdir "$R/x130"; printf 'k\n' > "$R/x130/keep"; printf 'a\nx = 1\n' > "$R/f130.py"; git -C "$R" add -A && git -C "$R" commit -qm "another PR: x, and a directory x130"
printf 'a\nx = 2\n' > "$R/f130.py"; git -C "$R" commit -qam "follow-up: x 2"
OUT130=$(out_of "$R" feat main); RC130=$?
assert_exit "fixture-130 a directory where the branch added an empty file -> flagged" 3 "$RC130"
assert_exit "fixture-130 lists c1" 0 "$(has "$OUT130" 'c1: x and an empty file')"
rm -rf "$R"

# 131: a restore that never landed is checked where the branch landed (its change and
# the change it undid cancel out in the net change), and its text is in the file
# twice: the copies agree that one is missing (the landing commit has one, what
# landed has two).
R="$(mk_repo)"; printf 'x = 1\na\nb\nx = 1\n' > "$R/f131.py"; git -C "$R" add -A && git -C "$R" commit -qm f131
git -C "$R" checkout -q -b feat
printf 'a\nb\nx = 1\n' > "$R/f131.py"; git -C "$R" commit -qam "c1: first x dropped"
printf 'a\nb\nx = 1\nc\n' > "$R/f131.py"; git -C "$R" commit -qam "c2: c"
printf 'x = 1\na\nb\nx = 1\nc\n' > "$R/f131.py"; git -C "$R" commit -qam "c3: first x back (never landed)"
git -C "$R" checkout -q main
printf 'o\n' > "$R/o131.txt"; git -C "$R" add -A && git -C "$R" commit -qm "another PR"
printf 'a\nb\nx = 1\nc\n' > "$R/f131.py"; git -C "$R" commit -qam "squash c1 c2"
OUT131=$(out_of "$R" feat main); RC131=$?
assert_exit "fixture-131 a repeated line restored, never landed -> flagged where it landed" 3 "$RC131"
assert_exit "fixture-131 lists c3" 0 "$(has "$OUT131" 'c3: first x back')"
rm -rf "$R"

# 132: the copies are counted against what landed, not the head: only b1 landed (a
# squash after main's own A -> B), b2 deleted an A and never landed, and b3, after
# the landed part, added an A of its own. Against the head b3's missing copy would
# cancel the copy b2 left behind. (The slots are laid out as in bounded.py, where
# this case was found.)
f132() { # <slot0> <slot1> <slot2>: three slots, each after three separator lines
  local s
  for s in 0 1 2; do printf -- '-- slot %s a --\n-- slot %s b --\n-- slot %s c --\n' "$s" "$s" "$s"
    eval "[ -z \"\${$((s + 1))}\" ] || printf '%s\n' \"\${$((s + 1))}\""; done
  printf -- '-- end --\n'
}
R="$(mk_repo)"; f132 A "" B > "$R/f132.txt"; git -C "$R" add -A && git -C "$R" commit -qm f132
git -C "$R" checkout -q -b feat
f132 A "" A > "$R/f132.txt"; git -C "$R" commit -qam "b1: slot 2 to A"
f132 A "" "" > "$R/f132.txt"; git -C "$R" commit -qam "b2: slot 2 emptied (never landed)"
f132 A A "" > "$R/f132.txt"; git -C "$R" commit -qam "b3: slot 1 A (never landed)"
git -C "$R" checkout -q main
f132 B "" B > "$R/f132.txt"; git -C "$R" commit -qam "main: slot 0 to B"
f132 B "" A > "$R/f132.txt"; git -C "$R" commit -qam "squash b1"
OUT132=$(out_of "$R" feat main); RC132=$?
assert_exit "fixture-132 copies counted against the landed part -> flagged" 3 "$RC132"
assert_exit "fixture-132 lists b2" 0 "$(has "$OUT132" 'b2: slot 2 emptied')"
rm -rf "$R"

# 133: the mirror of 132 for an added copy: b2 put back the first A and landed with
# b1 in a squash edited by hand that left that A out; b3, after the landed part,
# deleted the other A. Against the head, b3's deletion would cancel the missing copy.
R="$(mk_repo)"; printf 'A\nk1\nk2\nA\nk3\n' > "$R/f133.txt"; git -C "$R" add -A && git -C "$R" commit -qm f133
git -C "$R" checkout -q -b feat
printf 'k1\nk2\nA\nk3\nx\n' > "$R/f133.txt"; git -C "$R" commit -qam "b1: first A dropped, x"
printf 'A\nk1\nk2\nA\nk3\nx\ny\n' > "$R/f133.txt"; git -C "$R" commit -qam "b2: first A back, y"
printf 'A\nk1\nk2\nk3\nx\ny\n' > "$R/f133.txt"; git -C "$R" commit -qam "b3: second A dropped (never landed)"
git -C "$R" checkout -q main
printf 'o\n' > "$R/o133.txt"; git -C "$R" add -A && git -C "$R" commit -qm "another PR"
printf 'k1\nk2\nA\nk3\nx\ny\n' > "$R/f133.txt"; git -C "$R" commit -qam "squash b1 b2, the first A left out"
OUT133=$(out_of "$R" feat main); RC133=$?
assert_exit "fixture-133 an added copy counted against the landed part -> flagged" 3 "$RC133"
assert_exit "fixture-133 lists b2" 0 "$(has "$OUT133" 'b2: first A back')"
rm -rf "$R"

# ── Fixtures 134– (#399 round 14) ──

# 134: a name the tree stores in NFD (from Linux, or an older git) on a git that
# precomposes paths (core.precomposeUnicode, on by default on macOS): the paths the
# helper passes to git are its own listings, byte for byte, so a partial squash is
# still seen (#399 verify round 13).
N134="$(printf 'cafe\314\201.md')"
g134() { git -c core.precomposeUnicode=false -C "$R" "$@"; }
R="$(mk_repo)"; printf 'a\nb\nc\n' > "$R/$N134"; g134 add -A && g134 commit -qm n134
g134 checkout -q -b feat
printf 'a1\nb\nc\n' > "$R/$N134"; g134 commit -qam "c1: a1"
printf 'a1\nb1\nc\n' > "$R/$N134"; g134 commit -qam "c2: b1"
printf 'a1\nb1\nc1\n' > "$R/$N134"; g134 commit -qam "c3: c1 (never landed)"
g134 checkout -q main
printf 'a1\nb1\nc\n' > "$R/$N134"; g134 commit -qam "squash c1 c2"
git -C "$R" config core.precomposeUnicode true
OUT134=$(out_of "$R" feat main); RC134=$?
assert_exit "fixture-134 an NFD name, precomposeUnicode on: a partial squash -> flagged" 3 "$RC134"
assert_exit "fixture-134 lists c3" 0 "$(has "$OUT134" 'c3: c1')"
rm -rf "$R"
R="$(mk_repo)"; printf 'x = 1\n' > "$R/code134.js"; printf 'a\nb\n' > "$R/$N134"; g134 add -A && g134 commit -qm n134
g134 checkout -q -b feat
printf 'x = 2\n' > "$R/code134.js"; g134 commit -qam "c1: x 2"
printf 'a\nb\nnote\n' > "$R/$N134"; g134 commit -qam "c2: a note (never landed)"
g134 checkout -q main
printf 'x = 2\n' > "$R/code134.js"; g134 commit -qam "squash, the note left out"
git -C "$R" config core.precomposeUnicode true
OUT134b=$(out_of "$R" feat main); RC134b=$?
assert_exit "fixture-134b an NFD name, precomposeUnicode on: a commit left out of the squash -> flagged" 3 "$RC134b"
assert_exit "fixture-134b lists c2" 0 "$(has "$OUT134b" 'c2: a note')"
rm -rf "$R"

# 135: a submodule pointer flagged at the landing commit is a finding, not an error:
# R1 counts lines of a file, and a gitlink's record is no line of one (round 13 read
# it as a blob and exited 4). c3 set the pointer again and never landed.
R="$(mk_repo)"; printf 'a\n' > "$R/f135.txt"; git -C "$R" add -A && git -C "$R" commit -qm f135
W135=$(git -C "$R" rev-parse HEAD); X135=$(git -C "$R" commit-tree "$(git -C "$R" rev-parse 'HEAD^{tree}')" -m x135)
git -C "$R" update-index --add --cacheinfo "160000,$W135,sub135" && git -C "$R" commit -qm "sub135 at W"
git -C "$R" checkout -q -b feat
git -C "$R" update-index --cacheinfo "160000,$X135,sub135" && git -C "$R" commit -qm "c1: sub135 to X"
git -C "$R" update-index --cacheinfo "160000,$W135,sub135" && printf 'b\n' > "$R/f135.txt" && git -C "$R" add f135.txt && git -C "$R" commit -qm "c2: sub135 back to W, f b"
git -C "$R" update-index --cacheinfo "160000,$X135,sub135" && git -C "$R" commit -qm "c3: sub135 to X again (never landed)"
git -C "$R" checkout -q main
printf 'b\n' > "$R/f135.txt"; git -C "$R" add f135.txt && git -C "$R" commit -qm "squash c1 c2"
OUT135=$(out_of "$R" feat main); RC135=$?
assert_exit "fixture-135 a submodule pointer that never landed, prefix landed -> flagged (not exit 4)" 3 "$RC135"
assert_exit "fixture-135 lists c3" 0 "$(has "$OUT135" 'c3: sub135 to X again')"
rm -rf "$R"

# 136: a deletion that never landed, in a file the same commit renamed: the records
# carry the new name, which the parent does not have, so the finding stands as found
# (round 13 read the parent at the new name and exited 4).
R="$(mk_repo)"; seq 1 20 > "$R/x136.txt"; git -C "$R" add -A && git -C "$R" commit -qm x136
git -C "$R" checkout -q -b feat
{ seq 1 10; echo 'q unique'; seq 11 20; } > "$R/x136.txt"; git -C "$R" commit -qam "c0: q"
git -C "$R" mv x136.txt y136.txt && { seq 1 20 > "$R/y136.txt"; } && git -C "$R" commit -qam "c1: rename to y136, q dropped"
printf 'o\n' > "$R/o136.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c2: o136"
git -C "$R" checkout -q main
git -C "$R" rm -q x136.txt; { seq 1 10; echo 'q unique'; seq 11 20; } > "$R/y136.txt"; printf 'o\n' > "$R/o136.txt"
git -C "$R" add -A && git -C "$R" commit -qm "squash feat, q kept"
OUT136=$(out_of "$R" feat main); RC136=$?
assert_exit "fixture-136 a renamed file whose deletion never landed -> exit 4 (a move)" 4 "$RC136"
rm -rf "$R"

# 137: the branch landed in two squashes, and c3 (a restore, never landed) puts back a
# copy of a repeated line c1 dropped. The copy L^1 lost since the merge-base is c1's,
# which landed in the first squash, not main's own: it does not explain the missing
# copy away (round 13 cleared c3). (b): c1 was cherry-picked instead.
mk137() { # -> repo: base x/a/b/x; c1 drops the first x; c2 adds c; c3 puts it back
  local R; R="$(mk_repo)"; printf 'x = 1\na\nb\nx = 1\n' > "$R/f137.py"; git -C "$R" add -A && git -C "$R" commit -qm f137
  git -C "$R" checkout -q -b feat
  printf 'a\nb\nx = 1\n' > "$R/f137.py"; git -C "$R" commit -qam "c1: first x dropped"
  printf 'a\nb\nx = 1\nc\n' > "$R/f137.py"; git -C "$R" commit -qam "c2: c"
  printf 'x = 1\na\nb\nx = 1\nc\n' > "$R/f137.py"; git -C "$R" commit -qam "c3: first x back (never landed)"
  git -C "$R" checkout -q main
  printf 'o\n' > "$R/o137.txt"; git -C "$R" add -A && git -C "$R" commit -qm "another PR"
  echo "$R"
}
R="$(mk137)"
printf 'a\nb\nx = 1\n' > "$R/f137.py"; git -C "$R" commit -qam "PR 1: squash c1"
printf 'a\nb\nx = 1\nc\n' > "$R/f137.py"; git -C "$R" commit -qam "PR 2: squash c2"
OUT137=$(out_of "$R" feat main); RC137=$?
assert_exit "fixture-137 two squashes, a repeated line restored and never landed -> flagged" 3 "$RC137"
assert_exit "fixture-137 lists c3" 0 "$(has "$OUT137" 'c3: first x back')"
rm -rf "$R"
R="$(mk137)"
git -C "$R" cherry-pick feat~2 >/dev/null 2>&1
printf 'a\nb\nx = 1\nc\n' > "$R/f137.py"; git -C "$R" commit -qam "squash c2"
OUT137b=$(out_of "$R" feat main); RC137b=$?
assert_exit "fixture-137b c1 cherry-picked, c2 squashed, the restore never landed -> flagged" 3 "$RC137b"
assert_exit "fixture-137b lists c3" 0 "$(has "$OUT137b" 'c3: first x back')"
rm -rf "$R"

# 138: fixture 132 with b2 also moving the file, the move landing with b1: the record
# of b2's deletion carries the new name, and the finding stands as found.
R="$(mk_repo)"; f132 A "" B > "$R/f138.txt"; git -C "$R" add -A && git -C "$R" commit -qm f138
git -C "$R" checkout -q -b feat
f132 A "" A > "$R/f138.txt"; git -C "$R" commit -qam "b1: slot 2 to A"
git -C "$R" mv f138.txt g138.txt; f132 A "" "" > "$R/g138.txt"; git -C "$R" add -A && git -C "$R" commit -qm "b2: moved, slot 2 emptied (never landed)"
f132 A A "" > "$R/g138.txt"; git -C "$R" commit -qam "b3: slot 1 A (never landed)"
git -C "$R" checkout -q main
f132 B "" B > "$R/f138.txt"; git -C "$R" commit -qam "main: slot 0 to B"
git -C "$R" mv f138.txt g138.txt; f132 B "" A > "$R/g138.txt"; git -C "$R" add -A && git -C "$R" commit -qm "squash b1, and the move"
OUT138=$(out_of "$R" feat main); RC138=$?
assert_exit "fixture-138 a deletion in a moved file, never landed -> exit 4 (a move)" 4 "$RC138"
rm -rf "$R"

# 139–141: more than 64 KB of paths, where the trees are filtered to the listed paths
# before they are compared. 139: a wide commit also touched a file main then moved
# away (r.txt -> s.txt); comparing the full trees paired r.txt with s.txt, outside
# the list, and the commit's deletion read as still in place (round 13 listed it).
# 140: fixture 119 with a follow-up, so P0 does not settle it and the landing step
# reads the wide commits. 141: a wide commit that never landed is still listed.
wide139() { # <repo> <content> [count]: writes <count> files with long names under one directory
  LC_ALL=C awk -v d="$1/a_fairly_long_directory_name_for_paths" -v c="$2" -v n="${3:-1700}" \
    'BEGIN { for (i = 1; i <= n; i++) { f = sprintf("%s/file_number_%04d.txt", d, i); printf "%s", c > f; close(f) } }'
}
R="$(mk_repo)"; mkdir -p "$R/a_fairly_long_directory_name_for_paths"; wide139 "$R" 'v\n'
printf 'r1 alpha\nr2 beta\n' > "$R/r.txt"; git -C "$R" add -A && git -C "$R" commit -qm wide
git -C "$R" checkout -q -b feat
printf 'r1 alpha\nr2 beta\nr3 gamma\n' > "$R/r.txt"; git -C "$R" commit -qam "c0: r3"
wide139 "$R" 'v\nw\n'; printf 'r1 alpha\nr2 beta\n' > "$R/r.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1: wide edit, r3 dropped"
git -C "$R" checkout -q main
git -C "$R" mv r.txt s.txt && git -C "$R" commit -qm "main: r.txt moved to s.txt"
git -C "$R" checkout -q feat -- a_fairly_long_directory_name_for_paths && git -C "$R" commit -qm "squash feat"
assert_exit "fixture-139 over 64 KB of paths, main moved a file the commit touched -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

R="$(mk_repo)"; printf 'x = 1\n' > "$R/f140.py"; git -C "$R" add -A && git -C "$R" commit -qm f140
git -C "$R" checkout -q -b feat
B140=$(printf 'v\n' | git -C "$R" hash-object -w --stdin)
awk -v b="$B140" 'BEGIN { for (i = 0; i < 6000; i++) printf "100644 %s 0\tvendor/package-%05d/module.txt\n", b, i }' \
  | git -C "$R" update-index --add --index-info
git -C "$R" commit -qm "c1: vendor 6000 files"
git -C "$R" rm -rq --cached vendor && git -C "$R" commit -qm "c2: unvendor"
printf 'x = 2\n' > "$R/f140.py"; git -C "$R" commit -qam "c3: x 2"
printf 'x = 2\ny = 1\n' > "$R/f140.py"; git -C "$R" commit -qam "c4: y"
git -C "$R" checkout -q main
printf 'x = 2\ny = 1\n' > "$R/f140.py"; git -C "$R" commit -qam "squash feat"
printf 'x = 3\ny = 1\n' > "$R/f140.py"; git -C "$R" commit -qam "follow-up: x 3"
assert_exit "fixture-140 a commit with 6000 paths, squash, then main's edit -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

R="$(mk_repo)"; mkdir -p "$R/a_fairly_long_directory_name_for_paths"; wide139 "$R" 'v\n' 1200
git -C "$R" add -A && git -C "$R" commit -qm wide
git -C "$R" checkout -q -b feat
wide139 "$R" 'v\nw\n' 1200; git -C "$R" add -A && git -C "$R" commit -qm "c1: wide edit (never landed)"
git -C "$R" checkout -q main
printf 'o\n' > "$R/o141.txt"; git -C "$R" add -A && git -C "$R" commit -qm "another PR"
OUT141=$(out_of "$R" feat main); RC141=$?
assert_exit "fixture-141 a wide commit that never landed -> flagged" 3 "$RC141"
assert_exit "fixture-141 lists c1" 0 "$(has "$OUT141" 'c1: wide edit')"
rm -rf "$R"

# 142: a clean squash of a branch that deletes one of two equal adjacent lines, after
# main edited the line before them; a follow-up then edits the branch's line. The two
# diffs pair the copies differently, so no commit holds the net change by position;
# the squash's own step deletes one copy, as the branch does, so it is the landing
# commit (round 13 found none and listed c1 at the tip).
R="$(mk_repo)"; printf 'pad 0\npad 1\n}\n    return data\n    return data\nend\npad 3\nx = 1\npad 5\n' > "$R/o142.txt"
git -C "$R" add -A && git -C "$R" commit -qm o142
git -C "$R" checkout -q -b feat
printf 'pad 0\npad 1\n}\n    return data\nend\npad 3\nx = 2\npad 5\n' > "$R/o142.txt"; git -C "$R" commit -qam "c1: drop a line, x 2"
printf 'z\n' > "$R/z142.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c2: z"
git -C "$R" checkout -q main
printf 'pad 0\npad 1\n} # main\n    return data\n    return data\nend\npad 3\nx = 1\npad 5\n' > "$R/o142.txt"; git -C "$R" commit -qam "another PR: main"
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat" >/dev/null 2>&1
sed 's/^x = 2$/x = 3/' "$R/o142.txt" > "$R/t" && mv "$R/t" "$R/o142.txt"; git -C "$R" commit -qam "follow-up: x 3"
assert_exit "fixture-142 one of two equal lines deleted, main's edit next to them, squash, follow-up -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"
# 142b: the landing commit found that way is still where each commit is checked: c2,
# a restore that never landed, is listed there, and c3, whose line main edited after
# landing, is not (round 13 found no landing for the whole branch and listed c3 too).
R="$(mk_repo)"; printf 'pad 0\npad 1\n}\n    return data\n    return data\nend\npad 3\nx = 1\npad 5\nv = 1\n' > "$R/o142.txt"
git -C "$R" add -A && git -C "$R" commit -qm o142
git -C "$R" checkout -q -b feat
sed 's/^v = 1$/v = 2/' "$R/o142.txt" > "$R/t" && mv "$R/t" "$R/o142.txt"; git -C "$R" commit -qam "c1: v 2"
sed 's/^v = 2$/v = 1/' "$R/o142.txt" > "$R/t" && mv "$R/t" "$R/o142.txt"; git -C "$R" commit -qam "c2: v back to 1 (never landed)"
printf 'pad 0\npad 1\n}\n    return data\nend\npad 3\nx = 2\npad 5\nv = 1\n' > "$R/o142.txt"; git -C "$R" commit -qam "c3: drop a line, x 2"
git -C "$R" checkout -q main
printf 'pad 0\npad 1\n} # main\n    return data\n    return data\nend\npad 3\nx = 1\npad 5\nv = 1\n' > "$R/o142.txt"; git -C "$R" commit -qam "another PR: main"
printf 'pad 0\npad 1\n} # main\n    return data\nend\npad 3\nx = 2\npad 5\nv = 2\n' > "$R/o142.txt"; git -C "$R" commit -qam "squash c1 c3"
sed 's/^x = 2$/x = 3/' "$R/o142.txt" > "$R/t" && mv "$R/t" "$R/o142.txt"; git -C "$R" commit -qam "follow-up: x 3"
OUT142b=$(out_of "$R" feat main); RC142b=$?
assert_exit "fixture-142b a restore that never landed, found at that landing commit -> flagged" 3 "$RC142b"
assert_exit "fixture-142b lists c2" 0 "$(has "$OUT142b" 'c2: v back to 1')"
assert_exit "fixture-142b does not list c3" 1 "$(has "$OUT142b" 'c3: drop a line')"
rm -rf "$R"

# 143: at the tip a moved file is not all new lines either: the branch moved a file and
# dropped one of two equal lines in it, and main edited another line of it before the
# squash (round 13 listed the move at the tip, where main's edit read as the move's
# line missing).
R="$(mk_repo)"; printf 'pad 0\npad 1\npad 2\n}\n    return data\n    return data\nend\npad 3\npad 4\npad 5\n' > "$R/o143.txt"
git -C "$R" add -A && git -C "$R" commit -qm o143
git -C "$R" checkout -q -b feat
git -C "$R" mv o143.txt n143.txt; printf 'pad 0\npad 1\npad 2\n}\n    return data\nend\npad 3\npad 4\npad 5\n' > "$R/n143.txt"
git -C "$R" add -A && git -C "$R" commit -qm "c1: move to n143, drop a line"
printf 'z\n' > "$R/z143.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c2: z"
git -C "$R" checkout -q main
printf 'pad 0\npad 1\npad 2\n} # main\n    return data\n    return data\nend\npad 3\npad 4\npad 5\n' > "$R/o143.txt"; git -C "$R" commit -qam "another PR: main"
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat" >/dev/null 2>&1
assert_exit "fixture-143 a moved file, main's edit before the squash, checked at the tip -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 144: a diff.orderFile that does not exist makes git diff fail; the helper names no
# order file, so the landing commit is still found (round 13 fell back to the tip).
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'x = 1\n' > "$R/a144.py"; git -C "$R" add -A && git -C "$R" commit -qm "add x"
printf 'x = 2\n' > "$R/a144.py"; git -C "$R" commit -qam "change x"
git -C "$R" checkout -q main
printf 'x = 2\n' > "$R/a144.py"; git -C "$R" add -A && git -C "$R" commit -qm "squash feat"
printf 'x = 3\n' > "$R/a144.py"; git -C "$R" commit -qam "follow-up"
git -C "$R" config diff.orderFile "$R/.git/missing-order-file"
assert_exit "fixture-144 a missing diff.orderFile: squash, then main's edit -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 145: diff.submodule=log prints a submodule bump as a "Submodule ..." line, which
# pparse cannot read; the helper asks for "Subproject commit" lines (round 13 relied on
# it with no fixture).
R="$(mk_repo)"; A145=$(printf a | git -C "$R" hash-object -w --stdin); B145=$(printf b | git -C "$R" hash-object -w --stdin)
printf 'x = 1\nk\n' > "$R/f145.py"; git -C "$R" add -A
git -C "$R" update-index --add --cacheinfo "160000,$A145,sub145" && git -C "$R" commit -qm f145
git -C "$R" checkout -q -b feat
git -C "$R" update-index --cacheinfo "160000,$B145,sub145" && git -C "$R" commit -qm "c1: bump sub145"
printf 'x = 2\nk\n' > "$R/f145.py"; git -C "$R" add f145.py && git -C "$R" commit -qm "c2: x 2"
git -C "$R" checkout -q main
printf 'x = 2\nk\n' > "$R/f145.py"; git -C "$R" add f145.py; git -C "$R" update-index --cacheinfo "160000,$B145,sub145" && git -C "$R" commit -qm "squash feat"
printf 'x = 3\nk\n' > "$R/f145.py"; git -C "$R" add f145.py && git -C "$R" commit -qm "follow-up"
git -C "$R" config diff.submodule log
assert_exit "fixture-145 diff.submodule=log: a submodule bump squashed, then main's edit -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 146: 142 in a file the branch also moved: the copies are read at the merge-base and
# in main's commit before the squash under the file's old name (round 13 found no
# landing commit and listed c1 at the tip, where the follow-up's line was missing).
R="$(mk_repo)"; printf 'pad 0\npad 1\n}\n    return data\n    return data\nend\npad 3\npad 4\npad 5\n' > "$R/o146.txt"
git -C "$R" add -A && git -C "$R" commit -qm o146
git -C "$R" checkout -q -b feat
git -C "$R" mv o146.txt n146.txt; printf 'pad 0\npad 1\n}\n    return data\nend\npad 3\npad 4\npad 5 = branch\n' > "$R/n146.txt"
git -C "$R" add -A && git -C "$R" commit -qm "c1: move to n146, drop a line"
printf 'z\n' > "$R/z146.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c2: z"
git -C "$R" checkout -q main
printf 'pad 0\npad 1\n} # main\n    return data\n    return data\nend\npad 3\npad 4\npad 5\n' > "$R/o146.txt"; git -C "$R" commit -qam "another PR: main"
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat" >/dev/null 2>&1
sed 's/^pad 5 = branch$/pad 5 = follow-up/' "$R/n146.txt" > "$R/t" && mv "$R/t" "$R/n146.txt"; git -C "$R" commit -qam "follow-up"
assert_exit "fixture-146 moved, one of two equal lines deleted, main's edit next to them, follow-up -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 147: found by bounded.py --landing two. The branch landed in two squashes (b1, then
# b2) and b3, which deletes a line whose text repeats, never landed. In L^1 the copy b1
# added and the copy main removed on its own cancel out, so the count of main's own
# copies reads zero and R1 cleared b3; L^1 holds b1's net change, so the copies are
# not main's alone and the finding stands.
R="$(mk_repo)"; f132 A "" B > "$R/f147.txt"; printf 'G\n' > "$R/g147.txt"; git -C "$R" add -A && git -C "$R" commit -qm f147
git -C "$R" checkout -q -b feat
f132 B "" B > "$R/f147.txt"; git -C "$R" commit -qam "b1: slot 0 to B"
git -C "$R" rm -q g147.txt && git -C "$R" commit -qm "b2: g147 deleted"
f132 "" "" B > "$R/f147.txt"; git -C "$R" commit -qam "b3: slot 0 emptied (never landed)"
git -C "$R" checkout -q main
f132 A "" A > "$R/f147.txt"; git -C "$R" commit -qam "main: slot 2 to A"
f132 B "" A > "$R/f147.txt"; git -C "$R" commit -qam "PR 1: squash b1"
git -C "$R" rm -q g147.txt && git -C "$R" commit -qm "PR 2: squash b2"
OUT147=$(out_of "$R" feat main); RC147=$?
assert_exit "fixture-147 two squashes, main's own copy cancels the branch's in L^1 -> flagged" 3 "$RC147"
assert_exit "fixture-147 lists b3" 0 "$(has "$OUT147" 'b3: slot 0 emptied')"
rm -rf "$R"

# 148: found by bounded.py --landing two. b1 adds a copy of A that b2 takes away again,
# b3 adds an A elsewhere; everything landed, in two squashes (b1, then b2 and b3). The
# first squash's step adds one A, as the net change does, but that A is b1's: a text
# whose copies more than one branch commit changes is not counted, so the second
# squash is where the branch landed, and nothing is listed.
R="$(mk_repo)"; f132 A "" B > "$R/f148.txt"; git -C "$R" add -A && git -C "$R" commit -qm f148
git -C "$R" checkout -q -b feat
f132 A "" A > "$R/f148.txt"; git -C "$R" commit -qam "b1: slot 2 to A"
f132 A "" B > "$R/f148.txt"; git -C "$R" commit -qam "b2: slot 2 back to B"
f132 A A B > "$R/f148.txt"; git -C "$R" commit -qam "b3: slot 1 A"
git -C "$R" checkout -q main
f132 B "" B > "$R/f148.txt"; git -C "$R" commit -qam "main: slot 0 to B"
f132 B "" A > "$R/f148.txt"; git -C "$R" commit -qam "PR 1: squash b1"
f132 B A B > "$R/f148.txt"; git -C "$R" commit -qam "PR 2: squash b2 b3"
assert_exit "fixture-148 a copy one commit added and the next took away, two squashes -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 149: found by bounded.py --landing two. A later branch commit (b2) reached main first,
# picked on its own, then the rest (b1); b3, which deletes a line whose text repeats,
# never landed. b2 is not a prefix of the branch, and in L^1 its copy cancels the copy
# main removed itself; git cherry finds b2 in L^1, so the copies are not main's alone
# and the finding stands.
R="$(mk_repo)"; f132 A "" B > "$R/f149.txt"; git -C "$R" add -A && git -C "$R" commit -qm f149
git -C "$R" checkout -q -b feat
printf 'x\n' > "$R/x149.txt"; git -C "$R" add -A && git -C "$R" commit -qm "b1: x149"
f132 B "" B > "$R/f149.txt"; git -C "$R" commit -qam "b2: slot 0 to B"
f132 "" "" B > "$R/f149.txt"; git -C "$R" commit -qam "b3: slot 0 emptied (never landed)"
git -C "$R" checkout -q main
f132 A "" "" > "$R/f149.txt"; git -C "$R" commit -qam "main: slot 2 emptied"
git -C "$R" cherry-pick feat~1 >/dev/null 2>&1
printf 'x\n' > "$R/x149.txt"; git -C "$R" add -A && git -C "$R" commit -qm "PR 2: squash b1"
OUT149=$(out_of "$R" feat main); RC149=$?
assert_exit "fixture-149 a later commit picked first, main's own copy cancels it in L^1 -> flagged" 3 "$RC149"
assert_exit "fixture-149 lists b3" 0 "$(has "$OUT149" 'b3: slot 0 emptied')"
rm -rf "$R"

# 150: found by bounded.py --landing two. Only b1's prefix could have landed, and the
# second squash's step adds one B, as b1's change does; but that B is b3's (a commit
# after the prefix, landing in the same step). Copies are counted only for a text no
# two commits of the whole branch change, so no landing commit is found for b1 and it
# is checked at the tip (where the other B hides it, a documented tip blind spot).
R="$(mk_repo)"; f132 A "" B > "$R/f150.txt"; git -C "$R" add -A && git -C "$R" commit -qm f150
git -C "$R" checkout -q -b feat
f132 A B B > "$R/f150.txt"; git -C "$R" commit -qam "b1: slot 1 B (never landed)"
f132 C B B > "$R/f150.txt"; git -C "$R" commit -qam "b2: slot 0 to C"
f132 B B B > "$R/f150.txt"; git -C "$R" commit -qam "b3: slot 0 to B"
git -C "$R" checkout -q main
printf 'u\n' > "$R/u150.txt"; git -C "$R" add -A && git -C "$R" commit -qm "another PR"
f132 C "" B > "$R/f150.txt"; git -C "$R" commit -qam "PR 1: squash b2"
f132 B "" B > "$R/f150.txt"; git -C "$R" commit -qam "PR 2: squash b3"
T150="$(mktemp -d)/trace"
CHECK_MERGE_COMPLETENESS_TRACE="$T150" "${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main > /dev/null 2>&1
assert_exit "fixture-150 a later commit's copy is not counted for an earlier prefix: b1 checked at the tip" 0 \
  "$(grep -qx "side $(git -C "$R" rev-parse feat~2) tip" "$T150"; echo $?)"
rm -rf "$R" "$(dirname "$T150")"

# 151: a moved file checked at the tip. c1 (a debug line) never landed, so no commit
# holds the branch's net change and every commit is checked at the tip; c2 moved
# o151.txt, and main had edited it before taking the move. With renames detected the
# move adds no lines, so only c1 is listed (round 13 listed c2 too: without them every
# line of the moved file is new, and main's edited line read as c2's line missing).
R="$(mk_repo)"; printf 'r1\nr2\nr3\nr4\nr5\nr6\n' > "$R/o151.txt"; printf 'x\n' > "$R/x151.txt"; git -C "$R" add -A && git -C "$R" commit -qm o151
git -C "$R" checkout -q -b feat
printf 'x\ndebug\n' > "$R/x151.txt"; git -C "$R" commit -qam "c1: debug (never landed)"
git -C "$R" mv o151.txt n151.txt && git -C "$R" commit -qm "c2: move to n151"
git -C "$R" checkout -q main
printf 'r1\nr2 = main\nr3\nr4\nr5\nr6\n' > "$R/o151.txt"; git -C "$R" commit -qam "another PR: r2"
git -C "$R" mv o151.txt n151.txt && git -C "$R" commit -qm "squash c2 only"
OUT151=$(out_of "$R" feat main); RC151=$?
assert_exit "fixture-151 a move checked at the tip, main's edit before it -> only the dropped commit -> exit 4 (a move)" 4 "$RC151"
rm -rf "$R"

# 152, 152b: a commit that changed a file into a submodule or back is checked where
# the branch landed when a later commit undid it there and a commit after that, which
# never landed, did it again (D3: listed with that last commit). Its records are the
# pointer and the file's lines, never lines of one file at both ends, so R1 counts
# nothing and the finding stands; reading the pointer as a blob exited 4.
# 152: c1 turns the submodule into a file (its first record is the pointer's removal).
R="$(mk_repo)"; printf 'k\n' > "$R/k152.txt"; git -C "$R" add -A && git -C "$R" commit -qm k152
W152=$(git -C "$R" rev-parse HEAD)
git -C "$R" update-index --add --cacheinfo "160000,$W152,s152" && git -C "$R" commit -qm "s152 a submodule"
git -C "$R" checkout -q -b feat
B152=$(printf 'v\n' | git -C "$R" hash-object -w --stdin)
git -C "$R" update-index --cacheinfo "100644,$B152,s152" && git -C "$R" commit -qm "c1: s152 a file"
git -C "$R" update-index --cacheinfo "160000,$W152,s152" && git -C "$R" commit -qm "c2: s152 a submodule again"
printf 'k2\n' > "$R/k152.txt"; git -C "$R" add k152.txt && git -C "$R" commit -qm "c3: k2"
git -C "$R" update-index --cacheinfo "100644,$B152,s152" && git -C "$R" commit -qm "c4: s152 a file again (never landed)"
git -C "$R" checkout -q -f main
printf 'k2\n' > "$R/k152.txt"; git -C "$R" add k152.txt && git -C "$R" commit -qm "squash c1 c2 c3"
OUT152=$(out_of "$R" feat main); RC152=$?
assert_exit "fixture-152 a submodule turned into a file, checked where it landed -> flagged (not exit 4)" 3 "$RC152"
assert_exit "fixture-152 lists c4" 0 "$(has "$OUT152" 'c4: s152 a file again')"
rm -rf "$R"
# 152b: c1 turns an empty file into a submodule (its first record is the pointer).
R="$(mk_repo)"; printf 'k\n' > "$R/k152.txt"; : > "$R/s152"; git -C "$R" add -A && git -C "$R" commit -qm k152
W152=$(git -C "$R" rev-parse HEAD); E152=$(git -C "$R" rev-parse HEAD:s152)
git -C "$R" checkout -q -b feat
git -C "$R" update-index --cacheinfo "160000,$W152,s152" && git -C "$R" commit -qm "c1: s152 a submodule"
git -C "$R" update-index --cacheinfo "100644,$E152,s152" && git -C "$R" commit -qm "c2: s152 an empty file again"
printf 'k2\n' > "$R/k152.txt"; git -C "$R" add k152.txt && git -C "$R" commit -qm "c3: k2"
git -C "$R" update-index --cacheinfo "160000,$W152,s152" && git -C "$R" commit -qm "c4: s152 a submodule again (never landed)"
git -C "$R" checkout -q -f main
printf 'k2\n' > "$R/k152.txt"; git -C "$R" add k152.txt && git -C "$R" commit -qm "squash c1 c2 c3"
OUT152b=$(out_of "$R" feat main); RC152b=$?
assert_exit "fixture-152b an empty file turned into a submodule, checked where it landed -> flagged (not exit 4)" 3 "$RC152b"
assert_exit "fixture-152b lists c4" 0 "$(has "$OUT152b" 'c4: s152 a submodule again')"
rm -rf "$R"

# 153: b2 (dropping a repeated line) reached main in a squash with b3, before b1 landed
# on its own: neither an earlier prefix nor a patch git cherry finds, so only the
# other commits' copy counts tell that L^1's missing copy is b2's, not main's; b4, the
# restore, never landed and is listed.
R="$(mk_repo)"; printf 'x = 1\na\nb\nx = 1\n' > "$R/f153.py"; git -C "$R" add -A && git -C "$R" commit -qm f153
git -C "$R" checkout -q -b feat
printf 'u\n' > "$R/u153.txt"; git -C "$R" add -A && git -C "$R" commit -qm "b1: u153"
printf 'a\nb\nx = 1\n' > "$R/f153.py"; git -C "$R" commit -qam "b2: first x dropped"
printf 'a\nb\nx = 1\nc\n' > "$R/f153.py"; git -C "$R" commit -qam "b3: c"
printf 'x = 1\na\nb\nx = 1\nc\n' > "$R/f153.py"; git -C "$R" commit -qam "b4: first x back (never landed)"
git -C "$R" checkout -q main
printf 'a\nb\nx = 1\nc\n' > "$R/f153.py"; git -C "$R" commit -qam "PR 1: squash b2 b3"
printf 'u\n' > "$R/u153.txt"; git -C "$R" add -A && git -C "$R" commit -qm "PR 2: squash b1"
OUT153=$(out_of "$R" feat main); RC153=$?
assert_exit "fixture-153 a commit in L^1 that is no prefix and no cherry match -> the restore flagged" 3 "$RC153"
assert_exit "fixture-153 lists b4" 0 "$(has "$OUT153" 'b4: first x back')"
rm -rf "$R"

# 154: fixture 124 after the branch first moved the file: main's edit of a copy is in
# the file under its old name, at the merge-base and in L^1, so main's own copies are
# counted there under that name (round 13 read them under the new name, found none,
# and the copied function's line stood as missing).
R="$(mk_repo)"; printf 'def helper0():\n    return 0\ndef helper1():\n    return 1\ndef helper2():\n    return 2\ndef helper3():\n    return 3\ndef helper4():\n    return 4\ndef helper5():\n    return 5\ndef helper6():\n    return 6\ndef helper7():\n    return 7\ndef load(path):\n    with open(path) as f:\n        data = f.read()\n    return data\n' > "$R/io154.py"
git -C "$R" add -A && git -C "$R" commit -qm io154
git -C "$R" checkout -q -b feat
mkdir -p "$R/lib"; git -C "$R" mv io154.py lib/io154.py && git -C "$R" commit -qm "c0: move io154 to lib"
printf 'def helper0():\n    return 0\ndef helper1():\n    return 1\ndef helper2():\n    return 2\ndef helper3():\n    return 3\ndef helper4():\n    return 4\ndef helper5():\n    return 5\ndef helper6():\n    return 6\ndef helper7():\n    return 7\ndef load(path):\n    with open(path) as f:\n        data = f.read()\n    return data\n\ndef load_bytes(path):\n    with open(path) as f:\n        data = f.read()\n    return data\n' > "$R/lib/io154.py"
git -C "$R" commit -qam "c1: load_bytes, a copy of load"
printf 'def helper0():\n    return 0\ndef helper1():\n    return 1\ndef helper2():\n    return 2\ndef helper3():\n    return 3\ndef helper4():\n    return 4\ndef helper5():\n    return 5\ndef helper6():\n    return 6\ndef helper7():\n    return 7\ndef load_text(path):\n    with open(path) as f:\n        data = f.read()\n    return data\n\ndef load_bytes(path):\n    with open(path) as f:\n        data = f.read()\n    return data\n' > "$R/lib/io154.py"
git -C "$R" commit -qam "c2: load renamed load_text"
git -C "$R" checkout -q main
printf 'def helper0():\n    return 0\ndef helper1():\n    return 1\ndef helper2():\n    return 2\ndef helper3():\n    return 3\ndef helper4():\n    return 4\ndef helper5():\n    return 5\ndef helper6():\n    return 6\ndef helper7():\n    return 7\ndef load(path):\n    with open(path) as f:\n        data = f.read().strip()\n    return data\n' > "$R/io154.py"; git -C "$R" commit -qam "another PR: strip"
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat" >/dev/null 2>&1
assert_exit "fixture-154 the squash went through (git followed the move)" 0 "$(git -C "$R" log -1 --format=%s main | grep -qx 'squash feat'; echo $?)"
assert_exit "fixture-154 fixture 124 after a move: main's copy counted under the old name -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 155: found by bounded.py --pairs. b1 moves a line of repeated text (deletes it in one
# place, adds it in another: the number of copies stays the same), b2 adds another
# copy; only b2 was squashed. That squash's step changes the copies as the net change
# does, but b1 touched the same text: a text more than one commit touches is not
# counted, so no landing commit is found and b1 is checked at the tip (where the other
# copies hide it, a documented tip blind spot) rather than cleared at a false landing.
R="$(mk_repo)"; f132 A "" B > "$R/f155.txt"; git -C "$R" add -A && git -C "$R" commit -qm f155
git -C "$R" checkout -q -b feat
f132 A B "" > "$R/f155.txt"; git -C "$R" commit -qam "b1: B moved from slot 2 to slot 1 (never landed)"
f132 B B "" > "$R/f155.txt"; git -C "$R" commit -qam "b2: slot 0 to B"
git -C "$R" checkout -q main
printf 'u\n' > "$R/u155.txt"; git -C "$R" add -A && git -C "$R" commit -qm "another PR"
f132 B "" B > "$R/f155.txt"; git -C "$R" commit -qam "squash b2"
T155="$(mktemp -d)/trace"
CHECK_MERGE_COMPLETENESS_TRACE="$T155" "${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main > /dev/null 2>&1
assert_exit "fixture-155 a move of repeated text is a touch: b1 checked at the tip, not at a landing by copies" 0 \
  "$(grep -qx "side $(git -C "$R" rev-parse feat~1) tip" "$T155"; echo $?)"
rm -rf "$R" "$(dirname "$T155")"

# 156: found by bounded.py --landing merge. A release merge brings the squash of b2 and
# another PR that adds a copy of A; b1 also added a copy of A and never landed. The
# merge commit's step adds one A, as the net change does, but that A is the other PR's:
# a merge commit's step brings more than the branch, so copies are not counted there,
# and b1 is checked at the tip (where the other copy hides it, a documented tip blind
# spot) rather than cleared at the merge.
R="$(mk_repo)"; f132 A "" B > "$R/f156.txt"; git -C "$R" add -A && git -C "$R" commit -qm f156
git -C "$R" checkout -q -b feat
f132 A A B > "$R/f156.txt"; git -C "$R" commit -qam "b1: slot 1 A (never landed)"
printf 'g\n' > "$R/g156.txt"; git -C "$R" add -A && git -C "$R" commit -qm "b2: g156"
git -C "$R" checkout -q -b dev main
printf 'g\n' > "$R/g156.txt"; git -C "$R" add -A && git -C "$R" commit -qm "squash b2"
f132 A "" A > "$R/f156.txt"; git -C "$R" commit -qam "another PR: slot 2 A"
git -C "$R" checkout -q main
printf 'u\n' > "$R/u156.txt"; git -C "$R" add -A && git -C "$R" commit -qm "u2"
git -C "$R" merge -q --no-ff -m "merge dev" dev >/dev/null 2>&1
T156="$(mktemp -d)/trace"
CHECK_MERGE_COMPLETENESS_TRACE="$T156" "${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main > /dev/null 2>&1
assert_exit "fixture-156 copies are not counted at a merge commit: b1 checked at the tip" 0 \
  "$(grep -qx "side $(git -C "$R" rev-parse feat~1) tip" "$T156"; echo $?)"
rm -rf "$R" "$(dirname "$T156")"

# 157: found by bounded.py (plain mode). b1 adds a copy of A and never landed; main's own
# commit puts an A elsewhere. Every line of the net change is out of place in main's
# commit, so the copy rule does not take it for the landing commit (a squash carries
# some of the branch's change in place); b1 is checked at the tip, where main's A hides
# it (a documented tip blind spot), rather than cleared at main's commit.
R="$(mk_repo)"; f132 A "" B > "$R/f157.txt"; git -C "$R" add -A && git -C "$R" commit -qm f157
git -C "$R" checkout -q -b feat
f132 A A B > "$R/f157.txt"; git -C "$R" commit -qam "b1: slot 1 A (never landed)"
git -C "$R" checkout -q main
f132 A "" A > "$R/f157.txt"; git -C "$R" commit -qam "main: slot 2 A"
T157="$(mktemp -d)/trace"
CHECK_MERGE_COMPLETENESS_TRACE="$T157" "${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main > /dev/null 2>&1
assert_exit "fixture-157 a commit of main's own adding the same text is not a landing: b1 checked at the tip" 0 \
  "$(grep -qx "side $(git -C "$R" rev-parse feat) tip" "$T157"; echo $?)"
rm -rf "$R" "$(dirname "$T157")"

# ── Fixtures 158– (#399 round 15) ──
# 158: found by round 14's verify. c1 adds a fix X to y.txt, c2 moves y.txt to lib/y.txt
# with one more edit; only c2 was cherry-picked. Nothing holds the net change, so both
# are checked at the tip: c1 under its own name y.txt, which neither the head nor the
# tip has, read X as landed, and c2's own patch (renames detected) no longer carried X.
# c1's lines are looked for under the name its file has in the head.
R="$(mk_repo)"; printf 'a0\na1\na2\na3\na4\na5\na6\na7\n' > "$R/y158.txt"; git -C "$R" add -A && git -C "$R" commit -qm y158
git -C "$R" checkout -q -b feat
printf 'a0\na1\nX = fix\na2\na3\na4\na5\na6\na7\n' > "$R/y158.txt"; git -C "$R" commit -qam "c1: the fix X (never landed)"
mkdir -p "$R/lib"; git -C "$R" mv y158.txt lib/y158.txt
printf 'a0\na1\nX = fix\na2\na3\na4\na5\na6\na7 moved\n' > "$R/lib/y158.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c2: move y158 into lib/"
C158="$(git -C "$R" rev-parse feat)"
git -C "$R" checkout -q main
printf 'e\n' > "$R/e158.txt"; git -C "$R" add -A && git -C "$R" commit -qm "early PR"
git -C "$R" cherry-pick "$C158" >/dev/null 2>&1
assert_exit "fixture-158 the move was picked without X" 1 "$(git -C "$R" show main:lib/y158.txt | grep -qx 'X = fix'; echo $?)"
OUT158="$("${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main 2>/dev/null)"; RC158=$?
assert_exit "fixture-158 a fix whose file the branch moved later, never landed -> exit 4 (a move)" 4 "$RC158"
rm -rf "$R"

# 158b: the same shape, landed by a squash resolved by hand that keeps the move and
# drops X.
R="$(mk_repo)"; printf 'a0\na1\na2\na3\na4\na5\na6\na7\n' > "$R/y158.txt"; git -C "$R" add -A && git -C "$R" commit -qm y158
git -C "$R" checkout -q -b feat
printf 'a0\na1\nX\na2\na3\na4\na5\na6\na7\n' > "$R/y158.txt"; git -C "$R" commit -qam "c1: add X (never landed)"
git -C "$R" mv y158.txt z158.txt && git -C "$R" commit -qm "c2: rename y158 to z158"
git -C "$R" checkout -q main
printf 'e\n' > "$R/e158.txt"; git -C "$R" add -A && git -C "$R" commit -qm "early PR"
git -C "$R" mv y158.txt z158.txt && git -C "$R" commit -qm "squash feat (X dropped by hand)"
assert_exit "fixture-158b a squash that kept the move and dropped X -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 159: Codex in round 14's verify. A adds a line to old159.txt, B only renames the file
# to new159.txt, and main renames it the same way without A's line. At the tip A was
# read under old159.txt, which neither side has, and B's own patch (renames detected)
# carries no line: nothing was listed. A's line is looked for in new159.txt.
R="$(mk_repo)"; printf 'base\nline 2\nline 3\nline 4\n' > "$R/old159.txt"; git -C "$R" add -A && git -C "$R" commit -qm old159
git -C "$R" checkout -q -b feat
printf 'base\nUNLANDED\nline 2\nline 3\nline 4\n' > "$R/old159.txt"; git -C "$R" commit -qam "A: add UNLANDED"
git -C "$R" mv old159.txt new159.txt && git -C "$R" commit -qm "B: rename"
git -C "$R" checkout -q main
git -C "$R" mv old159.txt new159.txt && git -C "$R" commit -qm "main: rename only"
assert_exit "fixture-159 a line added before a rename main took alone -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 160: found by round 14's verify (DA). Fixture 124 plus a third copy of the function:
# a clean squash, main's .strip() put on the branch's copy. main's own edit makes L^1's
# copies differ from the merge-base's, and round 14 kept the finding because another
# commit (c3) changes their number, though c3 never reached L^1. Only another commit
# that reached L^1 uncounted keeps it now.
R="$(mk_repo)"; F160='    with open(path) as f:\n        data = f.read()\n'
printf "def load(path):\n$F160    return data\n\n" > "$R/io160.py"; git -C "$R" add -A && git -C "$R" commit -qm io160
git -C "$R" checkout -q -b feat
printf "def load(path):\n$F160    return data\n\ndef load_bytes(path):\n$F160    return data\n\n" > "$R/io160.py"; git -C "$R" commit -qam "c1: load_bytes, a copy of load"
printf "def load_text(path):\n$F160    return data\n\ndef load_bytes(path):\n$F160    return data\n\n" > "$R/io160.py"; git -C "$R" commit -qam "c2: load renamed load_text"
printf "def load_lines(path):\n$F160    return data.splitlines()\n\ndef load_text(path):\n$F160    return data\n\ndef load_bytes(path):\n$F160    return data\n\n" > "$R/io160.py"; git -C "$R" commit -qam "c3: load_lines, another copy"
git -C "$R" checkout -q main
printf "def load(path):\n    with open(path) as f:\n        data = f.read().strip()\n    return data\n\n" > "$R/io160.py"; git -C "$R" commit -qam "another PR: strip"
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat" >/dev/null 2>&1
assert_exit "fixture-160 the squash is the head plus main's own edit" 0 "$(git -C "$R" diff feat main | grep -c '^[-+][^-+]' | grep -qx 2; echo $?)"
assert_exit "fixture-160 a function copied twice, main's edit put on a copy, clean squash -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 161: found by round 14's verify (DA). c2's only line, `def load_text(path):`, is
# unique, but next to the repeated function bodies diff(c2 -> squash) pairs it with
# load_lines while diff(c2 -> head) leaves it alone. A unique line was judged by
# position alone and c2 was listed; every finding is now checked against the copies,
# and L has the line as often as the head.
R="$(mk_repo)"; F161='    with open(path) as f:\n        data = f.read()\n'
printf "def load(path):\n$F161    return data\n\n" > "$R/io161.py"; git -C "$R" add -A && git -C "$R" commit -qm io161
git -C "$R" checkout -q -b feat
printf "def load_bytes(path):\n$F161    return data\n\ndef load(path):\n$F161    return data\n\n" > "$R/io161.py"; git -C "$R" commit -qam "c1: load_bytes, a copy"
printf "def load_bytes(path):\n$F161    return data\n\ndef load_text(path):\n$F161    return data\n\n" > "$R/io161.py"; git -C "$R" commit -qam "c2: load renamed load_text"
printf "def load_bytes(path):\n$F161    return data\n\ndef load_lines(path):\n$F161    return data.splitlines()\n\ndef load_text(path):\n$F161    return data\n\n" > "$R/io161.py"; git -C "$R" commit -qam "c3: load_lines, another copy"
git -C "$R" checkout -q main
printf "def load(path):\n    with open(path) as f:\n        data = f.read().strip()\n    return data\n\n" > "$R/io161.py"; git -C "$R" commit -qam "another PR: strip"
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat" >/dev/null 2>&1
assert_exit "fixture-161 diff pairs the unique line with another function's" 0 \
  "$(git -C "$R" diff -U0 feat~1 main | grep -qx -- '-def load_text(path):'; echo $?)"
assert_exit "fixture-161 a unique line misplaced by the diff, clean squash -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 162: found by round 14's verify (regression). Fixture 124 plus an unrelated commit c0
# (another file) that main cherry-picked before the squash. Round 14 took any part of
# the branch in L^1 to stop R1 for every finding; only a part that changes the copies
# of the text matters, and c0's step changes none.
R="$(mk_repo)"; printf 'def load(path):\n    with open(path) as f:\n        data = f.read()\n    return data\n' > "$R/io162.py"
git -C "$R" add -A && git -C "$R" commit -qm io162
git -C "$R" checkout -q -b feat
printf 'hotfix\n' > "$R/hot162.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c0: hotfix in another file"
printf 'def load(path):\n    with open(path) as f:\n        data = f.read()\n    return data\n\ndef load_bytes(path):\n    with open(path) as f:\n        data = f.read()\n    return data\n' > "$R/io162.py"
git -C "$R" commit -qam "c1: load_bytes, a copy of load"
printf 'def load_text(path):\n    with open(path) as f:\n        data = f.read()\n    return data\n\ndef load_bytes(path):\n    with open(path) as f:\n        data = f.read()\n    return data\n' > "$R/io162.py"
git -C "$R" commit -qam "c2: load renamed load_text"
git -C "$R" checkout -q main
printf 'def load(path):\n    with open(path) as f:\n        data = f.read().strip()\n    return data\n' > "$R/io162.py"; git -C "$R" commit -qam "another PR: strip"
git -C "$R" cherry-pick feat~2 >/dev/null 2>&1
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat" >/dev/null 2>&1
assert_exit "fixture-162 a hotfix of the branch picked early, then a clean squash -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 163: found by round 14's verify (logic). Fixture 142's shape, but the branch's first
# two commits (unrelated files) landed earlier in a PR of their own; the whole branch is
# squashed later and main edits the branch's line after that.
R="$(mk_repo)"; printf 'pad 0\npad 1\n}\n    return data\n    return data\nend\npad 3\nx = 1\npad 5\n' > "$R/o163.txt"
git -C "$R" add -A && git -C "$R" commit -qm o163
git -C "$R" checkout -q -b feat
printf 'u\n' > "$R/u163.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c0a: unrelated u"
printf 'w\n' > "$R/w163.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c0b: unrelated w"
C163="$(git -C "$R" rev-parse feat)"
printf 'pad 0\npad 1\n}\n    return data\nend\npad 3\nx = 2\npad 5\n' > "$R/o163.txt"; git -C "$R" commit -qam "c1: drop a line, x 2"
printf 'z\n' > "$R/z163.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c2: z"
git -C "$R" checkout -q main
git -C "$R" merge -q --squash "$C163" >/dev/null 2>&1 && git -C "$R" commit -qm "PR1: squash c0a c0b" >/dev/null 2>&1
printf 'pad 0\npad 1\n} # main\n    return data\n    return data\nend\npad 3\nx = 1\npad 5\n' > "$R/o163.txt"; git -C "$R" commit -qam "another PR: main"
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat" >/dev/null 2>&1
sed 's/^x = 2$/x = 3/' "$R/o163.txt" > "$R/t" && mv "$R/t" "$R/o163.txt"; git -C "$R" commit -qam "follow-up: x 3"
assert_exit "fixture-163 an earlier PR of unrelated commits, then fixture 142 -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 164: found by round 14's verify (requirements). Fixture 147 with b1 squashed together
# with b1b as PR 1, and 19 filler commits squashed into PR 2 with b2: PR 1 is older than
# the 20 earlier commits searched for a part of the branch in L^1, and round 14 read its
# copy as main's and missed b3. b1 changes the copies and reached L^1 (its line is in
# place there), so the finding stands.
R="$(mk_repo)"; f132 A "" B > "$R/f164.txt"; printf 'G\n' > "$R/g164.txt"; git -C "$R" add -A && git -C "$R" commit -qm f164
git -C "$R" checkout -q -b feat
f132 B "" B > "$R/f164.txt"; git -C "$R" commit -qam "b1: slot 0 to B"
printf 'v\n' > "$R/v164.txt"; git -C "$R" add -A && git -C "$R" commit -qm "b1b: v164"
git -C "$R" rm -q g164.txt && git -C "$R" commit -qm "b2: g164 deleted"
for i in $(seq 1 19); do printf 'u\n' > "$R/u164_$i.txt"; git -C "$R" add -A && git -C "$R" commit -qm "filler $i"; done
f132 "" "" B > "$R/f164.txt"; git -C "$R" commit -qam "b3: slot 0 emptied (never landed)"
git -C "$R" checkout -q main
f132 A "" A > "$R/f164.txt"; git -C "$R" commit -qam "main: slot 2 to A"
f132 B "" A > "$R/f164.txt"; printf 'v\n' > "$R/v164.txt"; git -C "$R" add -A && git -C "$R" commit -qm "PR 1: squash b1 b1b"
git -C "$R" rm -q g164.txt; for i in $(seq 1 19); do printf 'u\n' > "$R/u164_$i.txt"; done
git -C "$R" add -A && git -C "$R" commit -qm "PR 2: squash b2 and the fillers"
OUT164=$(out_of "$R" feat main); RC164=$?
assert_exit "fixture-164 a first PR older than the commits searched, then b3 never landed -> flagged" 3 "$RC164"
assert_exit "fixture-164 lists b3" 0 "$(has "$OUT164" 'b3: slot 0 emptied')"
rm -rf "$R"

# 165: found by round 14's verify (logic). c1 and c3 landed in a squash edited by hand
# that dropped c2 (a second T); then main's own commit adds a T at the end of the file.
# Its step adds a T, as the net change does, and round 14 took it for the landing commit
# because c1's line was in place there, which c1's earlier squash had brought. The line
# in place must be one the commit's own step brought, so the landing is the squash of c1,
# and c2 is checked at the tip.
R="$(mk_repo)"; printf 'a0\na1\nT\na2\na3\na4\na5\na6\na7\n' > "$R/f165.txt"; printf 'g0\ng1\ng2\n' > "$R/g165.txt"
git -C "$R" add -A && git -C "$R" commit -qm f165
git -C "$R" checkout -q -b feat
printf 'g0\nX\ng1\ng2\n' > "$R/g165.txt"; git -C "$R" commit -qam "c1: X"
printf 'a0\na1\nT\na2\na3\nT\na4\na5\na6\na7\n' > "$R/f165.txt"; git -C "$R" commit -qam "c2: second T (never landed)"
printf 'g0\nX\ng1\ng2\nY\n' > "$R/g165.txt"; git -C "$R" commit -qam "c3: Y"
git -C "$R" checkout -q main
printf 'g0\nX\ng1\ng2\nY\n' > "$R/g165.txt"; git -C "$R" commit -qam "PR1: c1 and c3 (c2 dropped by hand)"
printf 'a0\na1\nT\na2\na3\na4\na5\na6\na7\nT\n' > "$R/f165.txt"; git -C "$R" commit -qam "main: its own T at the end"
T165="$(mktemp -d)/trace"
CHECK_MERGE_COMPLETENESS_TRACE="$T165" "${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main > /dev/null 2>&1
assert_exit "fixture-165 a commit of main's own adding a copy is not the landing commit" 1 \
  "$(grep -q "^landing $(git -C "$R" rev-parse main) " "$T165"; echo $?)"
assert_exit "fixture-165 c2 is checked at the tip" 0 "$(grep -qx "side $(git -C "$R" rev-parse feat~1) tip" "$T165"; echo $?)"
rm -rf "$R" "$(dirname "$T165")"

# 166: found by round 14's verify (logic). c2 moves one of two T lines and was dropped
# from a squash edited by hand. The net change moves a T, so the number of copies does
# not change, and round 14 took the squash for the landing commit of the whole branch
# (any commit not touching T matched a change of zero). A move is not counted, and c2
# is checked at the tip.
R="$(mk_repo)"; printf 'a0\nT\na1\na2\nT\na3\na4\na5\na6\n' > "$R/f166.txt"; printf 'g0\ng1\ng2\n' > "$R/g166.txt"
git -C "$R" add -A && git -C "$R" commit -qm f166
git -C "$R" checkout -q -b feat
printf 'g0\nX\ng1\ng2\n' > "$R/g166.txt"; git -C "$R" commit -qam "c1: X"
printf 'a0\nT\na1\na2\na3\na4\na5\nT\na6\n' > "$R/f166.txt"; git -C "$R" commit -qam "c2: move the second T down (never landed)"
printf 'g0\nX\ng1\ng2\nY\n' > "$R/g166.txt"; git -C "$R" commit -qam "c3: Y"
git -C "$R" checkout -q main
printf 'g0\nX\ng1\ng2\nY\n' > "$R/g166.txt"; git -C "$R" commit -qam "squash feat (c2 dropped by hand)"
printf 'a0\nT\na1\na2\nT\na3\na4\na5 main\na6\n' > "$R/f166.txt"; git -C "$R" commit -qam "main: edits f later"
T166="$(mktemp -d)/trace"
CHECK_MERGE_COMPLETENESS_TRACE="$T166" "${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main > /dev/null 2>&1
assert_exit "fixture-166 a moved copy is not counted: c2 checked at the tip" 0 "$(grep -qx "side $(git -C "$R" rev-parse feat~1) tip" "$T166"; echo $?)"
rm -rf "$R" "$(dirname "$T166")"

# 167: found by round 14's verify (security). Above 64 KB of paths the trees are filtered
# into a scratch index, and update-index skips a path it refuses (here GIT~1, an NTFS
# form of .git) with exit 0: the scratch trees lacked it, and a change to it that never
# landed read as landed. Every listed entry must reach the index now, or the read fails
# and the commit is checked at the tip.
R="$(mk_repo)"; G167() { git -C "$R" -c core.protectNTFS=false -c core.protectHFS=false "$@"; }
mkdir -p "$R/a_fairly_long_directory_name_for_paths" "$R/GIT~1"; wide139 "$R" 'v\n' 1200
printf 'v1\nk\n' > "$R/GIT~1/x"; G167 add -A && G167 commit -qm wide167
G167 checkout -q -b feat
wide139 "$R" 'v\nw\n' 1200; printf 'v2\nk\n' > "$R/GIT~1/x"; G167 add -A && G167 commit -qm "c1: wide edit and GIT~1/x"
G167 checkout -q main
wide139 "$R" 'v\nw\n' 1200; G167 add -A && G167 commit -qm "squash, GIT~1/x dropped"
printf 'x\n' > "$R/after167.txt"; G167 add -A && G167 commit -qm "main: later"
assert_exit "fixture-167 GIT~1/x is in the trees, changed only on the branch" 0 \
  "$([ "$(G167 show feat:GIT~1/x)" != "$(G167 show main:GIT~1/x)" ]; echo $?)"
assert_exit "fixture-167 a path update-index refuses, never landed, in a wide commit -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 168: found by round 14's verify (security). The filtered trees again, from a repository
# whose path has ':' in it (the alternates list is ':'-separated) and with
# core.splitIndex on (update-index then wrote its shared index into the repository's
# .git). A clean squash of two commits followed by main's edit of the branch's line: 0,
# and nothing new in .git.
D168="$(mktemp -d)"; mkdir -p "$D168/a:b"; R="$D168/a:b/r"
git init -q "$R"; git -C "$R" config user.email t@t.t; git -C "$R" config user.name t; git -C "$R" config commit.gpgsign false
git -C "$R" config core.splitIndex true
mkdir -p "$R/a_fairly_long_directory_name_for_paths"; wide139 "$R" 'v\n' 1200; printf 'r1\n' > "$R/r168.txt"
git -C "$R" add -A && git -C "$R" commit -qm base; git -C "$R" branch -M main
git -C "$R" checkout -q -b feat
wide139 "$R" 'v\nw\n' 1200; git -C "$R" add -A && git -C "$R" commit -qm "c1: wide edit"
printf 'r1 feat\n' > "$R/r168.txt"; git -C "$R" commit -qam "c2: r1"
git -C "$R" checkout -q main
wide139 "$R" 'v\nw\n' 1200; printf 'r1 feat\n' > "$R/r168.txt"; git -C "$R" add -A && git -C "$R" commit -qm "squash feat"
printf 'r1 main\n' > "$R/r168.txt"; git -C "$R" commit -qam "follow-up: r1"
N168="$(ls "$R/.git" | grep -c '^sharedindex' )"
assert_exit "fixture-168 a wide squash in a repository under a:b, then a follow-up -> NOT flagged" 0 "$(run_helper "$R" feat main)"
assert_exit "fixture-168 no shared index written into the repository" 0 "$([ "$(ls "$R/.git" | grep -c '^sharedindex')" = "$N168" ]; echo $?)"
rm -rf "$D168"

# 169: a unique line the commit moved is judged by its position: c1 moves `t = 1` down,
# c2 moves it back up and was left out of the squash, c3 lands. The count of `t = 1` is
# the same wherever the line is, so only its position shows that c2's restore is
# missing (row 49 for a move).
R="$(mk_repo)"; printf 'a\nt = 1\nb\nc\nd\ne\n' > "$R/m169.txt"; git -C "$R" add -A && git -C "$R" commit -qm m169
git -C "$R" checkout -q -b feat
printf 'a\nb\nc\nd\nt = 1\ne\n' > "$R/m169.txt"; git -C "$R" commit -qam "c1: t down"
printf 'a\nt = 1\nb\nc\nd\ne\n' > "$R/m169.txt"; git -C "$R" commit -qam "c2: t back up (never landed)"
printf 'z\n' > "$R/z169.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c3: z"
git -C "$R" checkout -q main
printf 'a\nb\nc\nd\nt = 1\ne\n' > "$R/m169.txt"; printf 'z\n' > "$R/z169.txt"; git -C "$R" add -A && git -C "$R" commit -qm "squash c1 c3"
OUT169=$(out_of "$R" feat main); RC169=$?
assert_exit "fixture-169 the restore of a moved unique line, left out of the squash -> flagged" 3 "$RC169"
assert_exit "fixture-169 lists c2" 0 "$(has "$OUT169" 'c2: t back up')"
rm -rf "$R"

# 170: found by round 14's verify (security). A name with a backslash (a\nb170.txt) reached
# awk through -v, which decodes it into a newline: the file's records matched nothing, the
# copy rule took main's own commit, which already had the branch's ok170.txt line, for the
# landing commit, and the branch was listed. Paths reach awk through the environment.
R="$(mk_repo)"; P170='a\nb170.txt'
printf 'base\nb2\nb3\nb4\n' > "$R/ok170.txt"; printf 'old\nq1\nq2\nq3\nq4\nq5\nzz\n' > "$R/$P170"
git -C "$R" add -A && git -C "$R" commit -qm f170
git -C "$R" checkout -q -b feat
printf 'base\nok-line\nb2\nb3\nb4\n' > "$R/ok170.txt"; printf 'new\nq1\nq2\nq3\nq4\nq5\nzz\n' > "$R/$P170"
git -C "$R" commit -qam "feat: both"
git -C "$R" checkout -q main
printf 'base\nok-line\nb2\nb3\nb4\n' > "$R/ok170.txt"; printf 'old\nq1\nq2\nq3\nq4\nq5\nZZ\n' > "$R/$P170"
git -C "$R" commit -qam "M1: main's own"
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat" >/dev/null 2>&1
printf 'base\nok-line\nb2\nb3\nB4\n' > "$R/ok170.txt"; git -C "$R" commit -qam "follow-up"
assert_exit "fixture-170 the name has a backslash" 0 "$(git -C "$R" ls-files | grep -qF 'a\\nb170.txt'; echo $?)"
assert_exit "fixture-170 a backslash in a name, main's own commit, squash, follow-up -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 171: found by bounded.py --landing two --touch in round 15. b2 sets slot 0 from A to C
# and b3 back to A; main set slot 0 to B on its own, then squashed b1 only. b3's A is
# missing where the branch landed. A unique line has one copy, so main's own
# replacement of it cannot have gone to the branch's copy: the line must be in the
# landing commit before main's own copies are counted (a count adjusted for main's
# removal read b3's restore as landed).
R="$(mk_repo)"; f132 A "" B > "$R/f171.txt"; git -C "$R" add -A && git -C "$R" commit -qm f171
git -C "$R" checkout -q -b feat
printf 'G\n' > "$R/g171.txt"; git -C "$R" add -A && git -C "$R" commit -qm "b1: g171"
f132 C "" B > "$R/f171.txt"; git -C "$R" commit -qam "b2: slot 0 to C"
f132 A "" B > "$R/f171.txt"; git -C "$R" commit -qam "b3: slot 0 back to A (never landed)"
git -C "$R" checkout -q main
f132 B "" B > "$R/f171.txt"; git -C "$R" commit -qam "main: slot 0 to B"
printf 'G\n' > "$R/g171.txt"; git -C "$R" add -A && git -C "$R" commit -qm "squash b1 (and the rest, which changes nothing)"
OUT171=$(out_of "$R" feat main); RC171=$?
assert_exit "fixture-171 a restore of a unique line main replaced on its own, never landed -> flagged" 3 "$RC171"
assert_exit "fixture-171 lists b3" 0 "$(has "$OUT171" 'b3: slot 0 back to A')"
rm -rf "$R"

# 172: found by bounded.py --landing two in round 15. b1 (slot 0 from A to C) and b3 (an
# unrelated file) were picked to main; b2, which empties slot 0, never landed. The whole
# branch's net change deletes A, and the pick of b1 replaced it, so the landing commit is
# the second pick and b2 is checked there. The copies of C in L^1 are b1's, not main's:
# b1 changes them and its change is in place in L^1, so the finding stands. (Subtracting
# the copies of the newest prefix L^1 holds took b1..b2 for that prefix, since b2's
# deletion of A counts as landed once A is replaced, and cleared b2.)
R="$(mk_repo)"; f132 A "" B > "$R/f172.txt"; printf 'E\n' > "$R/e172.txt"; git -C "$R" add -A && git -C "$R" commit -qm f172
git -C "$R" checkout -q -b feat
f132 C "" B > "$R/f172.txt"; git -C "$R" commit -qam "b1: slot 0 to C"
f132 "" "" B > "$R/f172.txt"; git -C "$R" commit -qam "b2: slot 0 emptied (never landed)"
git -C "$R" rm -q e172.txt && git -C "$R" commit -qm "b3: e172 deleted"
git -C "$R" checkout -q main
f132 A A B > "$R/f172.txt"; git -C "$R" commit -qam "main: slot 1 to A"
git -C "$R" cherry-pick feat~2 >/dev/null 2>&1 && git -C "$R" cherry-pick feat >/dev/null 2>&1
assert_exit "fixture-172 both picks went through" 0 "$(git -C "$R" log -1 --format=%s main | grep -qx 'b3: e172 deleted'; echo $?)"
OUT172=$(out_of "$R" feat main); RC172=$?
assert_exit "fixture-172 a dropped commit after a pick that replaced the branch's deleted line -> flagged" 3 "$RC172"
assert_exit "fixture-172 lists b2" 0 "$(has "$OUT172" 'b2: slot 0 emptied')"
rm -rf "$R"

# 173: fixture 171 for a deletion. b1 adds T and U, b2 deletes T and never landed, b3 is
# unrelated; main put a T of its own in b1's place before squashing b1 and b3. b2's
# deletion is missing where the branch landed: the landing commit has T, the head has
# none. Counted with main's own T taken out, the copies read as landed, and b1, whose U
# main lacks, did not reach L^1 to keep the finding; the unique line still in the
# landing commit does.
R="$(mk_repo)"; f132 "" "" B > "$R/f173.txt"; git -C "$R" add -A && git -C "$R" commit -qm f173
git -C "$R" checkout -q -b feat
f132 T U B > "$R/f173.txt"; git -C "$R" commit -qam "b1: T and U"
f132 "" U B > "$R/f173.txt"; git -C "$R" commit -qam "b2: T deleted (never landed)"
printf 'G\n' > "$R/g173.txt"; git -C "$R" add -A && git -C "$R" commit -qm "b3: g173"
git -C "$R" checkout -q main
f132 T "" B > "$R/f173.txt"; git -C "$R" commit -qam "main: its own T"
f132 T U B > "$R/f173.txt"; printf 'G\n' > "$R/g173.txt"; git -C "$R" add -A && git -C "$R" commit -qm "squash b1 b3"
OUT173=$(out_of "$R" feat main); RC173=$?
assert_exit "fixture-173 a deletion of a unique line main also had, never landed -> flagged" 3 "$RC173"
assert_exit "fixture-173 lists b2" 0 "$(has "$OUT173" 'b2: T deleted')"
rm -rf "$R"

# ── Fixtures 174– (#399 round 16): one name for each side of a diff ──
# Every diff record carries the name of the file on the side its line number belongs
# to. Round 15 keyed every record by the new side's name, so once the branch had moved
# a file, records of two diffs about the same line never met.

# 174: found by round 15's verify (logic). Fixture 153 with the branch moving the file
# after b2; the move reached main in PR 1 together with b2 and b3. b2's deletion is in
# L^1 under the new name, its own record under the old one: in_l1 read b2 as never in
# L^1, L^1's copies passed as main's, and b4, a restore that never landed, was cleared.
R="$(mk_repo)"; P174='p1\np2\np3\np4\np5\np6\np7\np8\n'
printf "x = 1\na\nb\nx = 1\n$P174" > "$R/f174.py"; git -C "$R" add -A && git -C "$R" commit -qm f174
git -C "$R" checkout -q -b feat
printf 'u\n' > "$R/u174.txt"; git -C "$R" add -A && git -C "$R" commit -qm "b1: u174"
printf "a\nb\nx = 1\n$P174" > "$R/f174.py"; git -C "$R" commit -qam "b2: first x dropped"
mkdir -p "$R/lib"; git -C "$R" mv f174.py lib/f174.py && git -C "$R" commit -qm "b2r: move to lib"
printf "a\nb\nx = 1\n${P174}c\n" > "$R/lib/f174.py"; git -C "$R" commit -qam "b3: c"
printf "x = 1\na\nb\nx = 1\n${P174}c\n" > "$R/lib/f174.py"; git -C "$R" commit -qam "b4: first x back (never landed)"
git -C "$R" checkout -q main
git -C "$R" rm -q f174.py; mkdir -p "$R/lib"; printf "a\nb\nx = 1\n${P174}c\n" > "$R/lib/f174.py"
git -C "$R" add -A && git -C "$R" commit -qm "PR 1: squash b2 b2r b3"
printf 'u\n' > "$R/u174.txt"; git -C "$R" add -A && git -C "$R" commit -qm "PR 2: squash b1"
OUT174=$(out_of "$R" feat main); RC174=$?
assert_exit "fixture-174 fixture 153 after the branch moved the file -> exit 4 (a move)" 4 "$RC174"
rm -rf "$R"

# 175: found by round 15's verify (logic). Fixture 146 with the branch's other change an
# inserted line: the branch moves the file, deletes one of two equal lines next to
# main's edit and adds a line. The squash is clean, then main edits the added line. The
# check for a line the squash's own step brought compared the net change (new name)
# with L^1 (old name), found none, refused the squash and listed c1 at the tip.
R="$(mk_repo)"; printf 'pad 0\npad 1\n}\n    return data\n    return data\nend\npad 3\npad 4\npad 5\n' > "$R/o175.txt"
git -C "$R" add -A && git -C "$R" commit -qm o175
git -C "$R" checkout -q -b feat
git -C "$R" mv o175.txt n175.txt
printf 'pad 0\npad 1\n}\n    return data\nend\npad 3\npad 4\npad 5\nbranch line\n' > "$R/n175.txt"
git -C "$R" add -A && git -C "$R" commit -qm "c1: move to n175, drop a line, add a line"
git -C "$R" checkout -q main
printf 'pad 0\npad 1\n} # main\n    return data\n    return data\nend\npad 3\npad 4\npad 5\n' > "$R/o175.txt"; git -C "$R" commit -qam "another PR: main"
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat" >/dev/null 2>&1
sed 's/^branch line$/branch line, follow-up/' "$R/n175.txt" > "$R/t" && mv "$R/t" "$R/n175.txt"; git -C "$R" commit -qam "follow-up"
assert_exit "fixture-175 the squash went through" 0 "$(git -C "$R" log -1 --format=%s main~1 | grep -qx 'squash feat'; echo $?)"
assert_exit "fixture-175 a moved file, one of two equal lines deleted, clean squash, follow-up -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 176: found by round 15's verify (logic). Fixture 153 with the branch moving the file
# last; PR 2 squashes b1 and the move. At the landing commit b4's lines were read under
# the file's old name, which neither the head nor the landing commit has, so b4 read
# as superseded (3.5.0 caught it at the tip).
R="$(mk_repo)"; P176='p1\np2\np3\np4\np5\np6\np7\np8\n'
printf "x = 1\na\nb\nx = 1\n$P176" > "$R/f176.py"; git -C "$R" add -A && git -C "$R" commit -qm f176
git -C "$R" checkout -q -b feat
printf 'u\n' > "$R/u176.txt"; git -C "$R" add -A && git -C "$R" commit -qm "b1: u176"
printf "a\nb\nx = 1\n$P176" > "$R/f176.py"; git -C "$R" commit -qam "b2: first x dropped"
printf "a\nb\nx = 1\n${P176}c\n" > "$R/f176.py"; git -C "$R" commit -qam "b3: c"
printf "x = 1\na\nb\nx = 1\n${P176}c\n" > "$R/f176.py"; git -C "$R" commit -qam "b4: first x back (never landed)"
mkdir -p "$R/lib"; git -C "$R" mv f176.py lib/f176.py && git -C "$R" commit -qm "b5: move to lib"
git -C "$R" checkout -q main
printf "a\nb\nx = 1\n${P176}c\n" > "$R/f176.py"; git -C "$R" commit -qam "PR 1: squash b2 b3"
printf 'u\n' > "$R/u176.txt"; mkdir -p "$R/lib"; git -C "$R" mv f176.py lib/f176.py
git -C "$R" add -A && git -C "$R" commit -qm "PR 2: squash b1 and b5"
OUT176=$(out_of "$R" feat main); RC176=$?
assert_exit "fixture-176 a restore that never landed, in a file the branch moved last -> exit 4 (a move)" 4 "$RC176"
rm -rf "$R"

# 177: found by round 15's verify (Codex). c1 sets a line from A to B, c2 sets it back
# and never landed, c3 only moves the file; main took c1 and the move. The net change
# is a move with no edit, so the landing commit holds it; c2's line, read at the
# landing commit under the file's old name, read as superseded.
R="$(mk_repo)"; printf 'p1\np2\nA\np3\np4\np5\n' > "$R/old177.txt"; git -C "$R" add -A && git -C "$R" commit -qm old177
git -C "$R" checkout -q -b feat
printf 'p1\np2\nB\np3\np4\np5\n' > "$R/old177.txt"; git -C "$R" commit -qam "c1: A to B"
printf 'p1\np2\nA\np3\np4\np5\n' > "$R/old177.txt"; git -C "$R" commit -qam "c2: B back to A (never landed)"
git -C "$R" mv old177.txt new177.txt && git -C "$R" commit -qm "c3: move"
git -C "$R" checkout -q main
git -C "$R" mv old177.txt new177.txt; printf 'p1\np2\nB\np3\np4\np5\n' > "$R/new177.txt"
git -C "$R" add -A && git -C "$R" commit -qm "squash feat (c2 dropped by hand)"
OUT177=$(out_of "$R" feat main); RC177=$?
assert_exit "fixture-177 a revert that never landed, before a move that did -> exit 4 (a move)" 4 "$RC177"
rm -rf "$R"

# 178: found by round 15's verify (security). Writing the scratch index of the filtered
# trees (above 64 KB of paths) ran the repository's post-index-change hook. Every git
# call runs with core.hooksPath=/dev/null.
R="$(mk_repo)"; mkdir -p "$R/a_fairly_long_directory_name_for_paths"; wide139 "$R" 'v\n' 1200
git -C "$R" add -A && git -C "$R" commit -qm wide178
M178="$(mktemp -d)/ran"
printf '#!/bin/sh\necho ran >> "%s"\n' "$M178" > "$R/.git/hooks/post-index-change"; chmod +x "$R/.git/hooks/post-index-change"
git -C "$R" checkout -q -b feat
wide139 "$R" 'v\nw\n' 1200; git -C "$R" add -A && git -C "$R" commit -qm "c1: wide edit (never landed)"
git -C "$R" checkout -q main; rm -f "$M178"
assert_exit "fixture-178 a wide commit that never landed -> flagged" 3 "$(run_helper "$R" feat main)"
assert_exit "fixture-178 the repository's post-index-change hook did not run" 1 "$([ -e "$M178" ]; echo $?)"
rm -rf "$R" "$(dirname "$M178")"

# 179: an accepted limit (#399, 2026-10-31): two commits touch the same repeated text
# (c1 deletes one of two equal lines, c2 adds another copy). The clean squash is not
# counted as the landing commit, the branch is checked at the tip, and main's follow-up
# lists c1. This pins that route (SPEC D1, row 56b), so a change to it shows here.
R="$(mk_repo)"; printf 'pad 0\npad 1\npad 2\nx = 1\n    pass\n    pass\nx = 1\npad 3\npad 4\npad 5\n' > "$R/o179.txt"
git -C "$R" add -A && git -C "$R" commit -qm o179
git -C "$R" checkout -q -b feat
printf 'pad 0\npad 1\npad 2\nx = 1\n    pass\nx = 1\npad 3\npad 4\npad 5 = branch\n' > "$R/o179.txt"; git -C "$R" commit -qam "c1: drop a pass, set pad 5"
printf 'pad 0\n    pass\npad 1\npad 2\nx = 1\n    pass\nx = 1\npad 3\npad 4\npad 5 = branch\n' > "$R/o179.txt"
printf 'z\n' > "$R/z179.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c2: copy + z"
git -C "$R" checkout -q main
printf 'pad 0\npad 1\npad 2\nx = 1 # main\n    pass\n    pass\nx = 1\npad 3\npad 4\npad 5\n' > "$R/o179.txt"; git -C "$R" commit -qam "main edit"
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm squash >/dev/null 2>&1
sed 's/^pad 5 = branch$/pad 5 = follow-up/' "$R/o179.txt" > "$R/t" && mv "$R/t" "$R/o179.txt"; git -C "$R" commit -qam follow-up
T179="$(mktemp -d)/trace"
CHECK_MERGE_COMPLETENESS_TRACE="$T179" "${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main > /dev/null 2>&1
assert_exit "fixture-179 a text two commits touch: no landing commit, c1 checked at the tip" 0 \
  "$(grep -qx "landing - prefix -" "$T179" && grep -qx "side $(git -C "$R" rev-parse feat~1) tip" "$T179"; echo $?)"
rm -rf "$R" "$(dirname "$T179")"

# 180: the other accepted limit: Rebase and merge (the commits picked one by one) whose
# step fails on repeated text. Only c1's pick is found to hold a prefix; c2 is checked
# at the tip, where main's follow-up lists it (SPEC D1, row 56b).
R="$(mk_repo)"; printf 'pad 0\npad 1\npad 2\nend\n}\n}\nend\npad 5\n' > "$R/o180.txt"; git -C "$R" add -A && git -C "$R" commit -qm o180
git -C "$R" checkout -q -b feat
printf 'pad 0\npad 1\npad 2\nend\n}\nend\npad 5 = branch\n' > "$R/o180.txt"; git -C "$R" commit -qam "c1: drop one of two equal lines, edit last"
printf 'pad 0\npad 1\npad 2\nend\n}\nend\npad 5 = branch v2\n' > "$R/o180.txt"; git -C "$R" commit -qam "c2: rewrite last line"
git -C "$R" checkout -q main
printf 'pad 0\npad 1\npad 2\nend # main\n}\n}\nend\npad 5\n' > "$R/o180.txt"; git -C "$R" commit -qam "main edit"
git -C "$R" cherry-pick feat~1 >/dev/null 2>&1 && git -C "$R" cherry-pick feat >/dev/null 2>&1
sed 's/^pad 5 = branch v2$/pad 5 = follow-up/' "$R/o180.txt" > "$R/t" && mv "$R/t" "$R/o180.txt"; git -C "$R" commit -qam follow-up
T180="$(mktemp -d)/trace"
CHECK_MERGE_COMPLETENESS_TRACE="$T180" "${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main > /dev/null 2>&1
assert_exit "fixture-180 Rebase and merge failing on repeated text: c2 checked at the tip" 0 \
  "$(grep -qx "side $(git -C "$R" rev-parse feat) tip" "$T180"; echo $?)"
rm -rf "$R" "$(dirname "$T180")"

# ── Fixtures 181– (#399 round 17): each file followed commit by commit ──

# 181: found by round 16's verify (logic). The branch moves a file twice (f -> mid/f ->
# lib/f); b2 edits it only under the middle name and reached main early as a pick (git
# follows the move and edits f.py there); b4 puts the line back and never landed. Round
# 16 listed the branch's commits by four fixed names, missed b2, read L^1's copy as
# main's own, and cleared b4 (3.5.0 and round 15 listed it). Each file is now followed
# commit by commit, and the branch's commits are listed by every name the file had.
R="$(mk_repo)"; P181='p1\np2\np3\np4\np5\np6\np7\np8\n'
printf 'x = 1\na\nb\nx = 1\n'"$P181" > "$R/f181.py"; git -C "$R" add -A && git -C "$R" commit -qm f181
git -C "$R" checkout -q -b feat
printf 'u\n' > "$R/u181.txt"; git -C "$R" add -A && git -C "$R" commit -qm "b1: u"
mkdir "$R/mid"; git -C "$R" mv f181.py mid/f181.py && git -C "$R" commit -qm "b2r: move to mid"
printf 'a\nb\nx = 1\n'"$P181" > "$R/mid/f181.py"; git -C "$R" commit -qam "b2: first x dropped (in mid)"
printf 'a\nb\nx = 1\n'"$P181"'c\n' > "$R/mid/f181.py"; git -C "$R" commit -qam "b3: c"
mkdir "$R/lib"; git -C "$R" mv mid/f181.py lib/f181.py && git -C "$R" commit -qm "b3r: move mid -> lib"
printf 'x = 1\na\nb\nx = 1\n'"$P181"'c\n' > "$R/lib/f181.py"; git -C "$R" commit -qam "b4: first x back (never landed)"
git -C "$R" checkout -q main
git -C "$R" cherry-pick -x "$(git -C "$R" rev-parse feat~3)" > /dev/null 2>&1
git -C "$R" rm -q f181.py; mkdir -p "$R/lib"; printf 'a\nb\nx = 1\n'"$P181"'c\n' > "$R/lib/f181.py"; printf 'u\n' > "$R/u181.txt"
git -C "$R" add -A && git -C "$R" commit -qm "squash b1..b3r (b4 left out)"
assert_exit "fixture-181 b2 was picked early: main's f181.py lost its first x" 0 \
  "$([ "$(git -C "$R" show main~1:f181.py | head -1)" = a ]; echo $?)"
OUT181=$(out_of "$R" feat main); RC181=$?
assert_exit "fixture-181 a file moved twice, edited under its middle name -> exit 4 (a move)" 4 "$RC181"
rm -rf "$R"

# 182: found by round 16's verify (devil's advocate). A adds a line; B moves old.txt to
# new.txt; C puts a new file (a shim) at old.txt. main picks B and C only. Read by one
# rename detection from A to the head, old.txt was still there (the shim), so A's line
# was looked for in the shim, was not in the head either, and A read as superseded
# (rc 0; 3.5.0 listed it).
R="$(mk_repo)"; printf 'base\nline 2\nline 3\nline 4\nline 5\nline 6\n' > "$R/old182.txt"; git -C "$R" add -A && git -C "$R" commit -qm old182
git -C "$R" checkout -q -b feat
printf 'base\nUNLANDED\nline 2\nline 3\nline 4\nline 5\nline 6\n' > "$R/old182.txt"; git -C "$R" commit -qam "A182: add UNLANDED"
git -C "$R" mv old182.txt new182.txt && git -C "$R" commit -qm "B182: move"
printf 'shim 1\nshim 2\n' > "$R/old182.txt"; git -C "$R" add -A && git -C "$R" commit -qm "C182: shim at the old name"
git -C "$R" checkout -q main
git -C "$R" cherry-pick feat~1 feat > /dev/null 2>&1
OUT182=$(out_of "$R" feat main); RC182=$?
assert_exit "fixture-182 a move, then a new file at the old name, the first commit dropped -> exit 4 (a move)" 4 "$RC182"
rm -rf "$R"

# 183: the same with C rewriting most of the moved file instead (A to the head is below
# git's 50% similarity, so no rename was seen between them). main picks B and takes C's
# rewrite without A's line.
R="$(mk_repo)"; printf 'l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nl10\n' > "$R/old183.txt"; git -C "$R" add -A && git -C "$R" commit -qm old183
git -C "$R" checkout -q -b feat
printf 'l1\nUNLANDED\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nl10\n' > "$R/old183.txt"; git -C "$R" commit -qam "A183: add UNLANDED"
git -C "$R" mv old183.txt new183.txt && git -C "$R" commit -qm "B183: move"
printf 'l1\nUNLANDED\nl2\nm3\nm4\nm5\nm6\nm7\nm8\nm9\nm10\nm11\n' > "$R/new183.txt"; git -C "$R" commit -qam "C183: rewrite most of it"
git -C "$R" checkout -q main
git -C "$R" cherry-pick feat~1 > /dev/null 2>&1
printf 'l1\nl2\nm3\nm4\nm5\nm6\nm7\nm8\nm9\nm10\nm11\n' > "$R/new183.txt"; git -C "$R" commit -qam "C183 picked without A183's line"
OUT183=$(out_of "$R" feat main); RC183=$?
assert_exit "fixture-183 a move, then a rewrite, the first commit dropped -> exit 4 (a move)" 4 "$RC183"
rm -rf "$R"

# 184: fixture 182 with a deletion: A deletes Z, then the move and the shim; main picks B
# and C, so Z is still in main's new184.txt. Round 16 found a landing commit and read
# A's deletion in the shim (rc 0, as 3.5.0).
R="$(mk_repo)"; printf 'l1\nZ = stale\nl2\nl3\nl4\nl5\nl6\n' > "$R/old184.txt"; git -C "$R" add -A && git -C "$R" commit -qm old184
git -C "$R" checkout -q -b feat
printf 'l1\nl2\nl3\nl4\nl5\nl6\n' > "$R/old184.txt"; git -C "$R" commit -qam "A184: delete Z"
git -C "$R" mv old184.txt new184.txt && git -C "$R" commit -qm "B184: move"
printf 'shim 1\nshim 2\n' > "$R/old184.txt"; git -C "$R" add -A && git -C "$R" commit -qm "C184: shim at the old name"
git -C "$R" checkout -q main
git -C "$R" cherry-pick feat~1 feat > /dev/null 2>&1
OUT184=$(out_of "$R" feat main); RC184=$?
assert_exit "fixture-184 a deletion before a move and a shim, never landed -> exit 4 (a move)" 4 "$RC184"
rm -rf "$R"

# 185: found by round 17's rename fuzz. Every commit landed, as picks folded into one
# squash: the squash moves f185.txt to lib/f185.txt and puts the shim at f185.txt in one
# step, which git records as an edit of f185.txt and a new lib/f185.txt (the old path is
# still there). Read by history alone, main's f185.txt (the shim) stood for the branch's
# moved file, and three landed commits were listed. A file the branch moved is the file
# main created at its name in the head, when main created one.
R="$(mk_repo)"; P185=""; for i in 0 1 2 3 4 5 6 7; do P185="${P185}base $i\npad $i a\npad $i b\n"; done
printf "$P185" > "$R/f185.txt"; git -C "$R" add -A && git -C "$R" commit -qm f185
git -C "$R" checkout -q -b feat
sed '/^base 0$/d' "$R/f185.txt" > "$R/t" && mv "$R/t" "$R/f185.txt"; git -C "$R" commit -qam "c0: del base 0"
mkdir "$R/lib"; git -C "$R" mv f185.txt lib/f185.txt && git -C "$R" commit -qm "c1: move"
sed '/^base 5$/d' "$R/lib/f185.txt" > "$R/t" && mv "$R/t" "$R/lib/f185.txt"; git -C "$R" commit -qam "c2: del base 5"
awk '$0 == "pad 3 a" { print "M3 marker" } { print }' "$R/lib/f185.txt" > "$R/t" && mv "$R/t" "$R/lib/f185.txt"; git -C "$R" commit -qam "c3: add"
printf 'shim 4 1\nshim 4 2\n' > "$R/f185.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c4: shim"
git -C "$R" checkout -q main; B185="$(git -C "$R" rev-parse HEAD)"
for c in feat~4 feat~3 feat~2 feat~1 feat; do git -C "$R" cherry-pick "$c" > /dev/null 2>&1; done
git -C "$R" reset -q --soft "$B185" && git -C "$R" commit -qm "PR (squash)"
assert_exit "fixture-185 the squash records no move (f185.txt is still there)" 0 \
  "$(git -C "$R" diff-tree -r -M --name-status main~1 main | grep -qx 'M	f185.txt'; echo $?)"
assert_exit "fixture-185 every commit landed, squashed with a move and a shim -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 186: found by round 16's verify (logic, regression, devil's advocate): a skipped
# rename detection was an error wherever git printed it, so a branch whose later commit
# replaced more than 1000 files (generated assets, no move at all) exited 4 for every
# earlier commit. It matters only where the skipped commit deletes a file a candidate
# touched, read after it; here it does not.
R="$(mk_repo)"; mkdir "$R/old186"; i=1
while [ "$i" -le 1001 ]; do printf 'old %s\nalpha %s\n' "$i" "$((i * 7))" > "$R/old186/o$i.txt"; i=$((i + 1)); done
printf 'a\nb\nc\n' > "$R/a186.txt"; git -C "$R" add -A && git -C "$R" commit -qm old186
git -C "$R" checkout -q -b feat
printf 'a\nb2\nc\n' > "$R/a186.txt"; git -C "$R" commit -qam "c1: edit a186"
git -C "$R" rm -rq old186; mkdir "$R/new186"; i=1
while [ "$i" -le 1001 ]; do printf 'new %s\nzeta %s\n' "$i" "$((i * 13))" > "$R/new186/n$i.txt"; i=$((i + 1)); done
git -C "$R" add -A && git -C "$R" commit -qm "c2: replace the generated files (no move)"
git -C "$R" checkout -q main
git -C "$R" merge -q --squash feat > /dev/null 2>&1 && git -C "$R" commit -qm "squash feat" > /dev/null 2>&1
printf 'a\nb2\nc\nmain follow-up\n' > "$R/a186.txt"; git -C "$R" commit -qam "follow-up"
assert_exit "fixture-186 a later commit replaces 1001 files, squashed, follow-up -> NOT flagged (not exit 4)" 0 "$(run_helper "$R" feat main)"
# ...and when the commit that replaces them also deletes a file c1 touched, whether that
# file moved cannot be told: exit 4, with the reason.
rm -rf "$R"
R="$(mk_repo)"; mkdir "$R/old186"; i=1
while [ "$i" -le 1001 ]; do printf 'old %s\nalpha %s\n' "$i" "$((i * 7))" > "$R/old186/o$i.txt"; i=$((i + 1)); done
printf 'a\nb\nc\n' > "$R/old186/a186.txt"; git -C "$R" add -A && git -C "$R" commit -qm old186b
git -C "$R" checkout -q -b feat
printf 'a\nb2\nc\n' > "$R/old186/a186.txt"; git -C "$R" commit -qam "c1: edit a186 (never landed)"
git -C "$R" rm -rq old186; mkdir "$R/new186"; i=1
while [ "$i" -le 1002 ]; do printf 'new %s\nzeta %s\n' "$i" "$((i * 13))" > "$R/new186/n$i.txt"; i=$((i + 1)); done
git -C "$R" add -A && git -C "$R" commit -qm "c2: replace them all"
git -C "$R" checkout -q main
E186="$("${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main 2>&1 >/dev/null; echo "rc=$?")"
assert_exit "fixture-186b a file c1 edited, deleted later where git skipped rename detection -> exit 4" 0 \
  "$(printf '%s\n' "$E186" | grep -q '^rc=4$'; echo $?)"
assert_exit "fixture-186b the reason names the skipped rename detection" 0 \
  "$(printf '%s\n' "$E186" | grep -q 'did not look for moves'; echo $?)"
rm -rf "$R"

# 187: found by round 16's verify (Codex). awk compares two values that both look like
# numbers as numbers, so "1" and "01" were counted as copies of one line. A changes the
# first of two "1" lines to "01" (and adds a marker), B sets it back; main took A only.
R="$(mk_repo)"; printf 'p\n1\nq\n1\nr\n' > "$R/n187.txt"; git -C "$R" add -A && git -C "$R" commit -qm n187
git -C "$R" checkout -q -b feat
printf 'p\n01\nq\n1\nr\n' > "$R/n187.txt"; printf 'm\n' > "$R/m187.txt"; git -C "$R" add -A && git -C "$R" commit -qm "A187: 1 to 01, marker"
printf 'p\n1\nq\n1\nr\n' > "$R/n187.txt"; git -C "$R" commit -qam "B187: 01 back to 1 (never landed)"
git -C "$R" checkout -q main
printf 'p\n01\nq\n1\nr\n' > "$R/n187.txt"; printf 'm\n' > "$R/m187.txt"; git -C "$R" add -A && git -C "$R" commit -qm "squash A187"
OUT187=$(out_of "$R" feat main); RC187=$?
assert_exit "fixture-187 a line set back from 01 to 1, never landed -> flagged" 3 "$RC187"
assert_exit "fixture-187 lists B187" 0 "$(has "$OUT187" 'B187: 01 back to 1')"
rm -rf "$R"

# 188: found by round 16's verify (security). A hook defined in the configuration
# (hook.<name>.event = post-index-change, git 2.54 and later) ran although
# core.hooksPath pointed at /dev/null. A moved file is read through the scratch index
# (ctree), so a small branch reaches it.
R="$(mk_repo)"; printf 'a\nb\nc\nd\n' > "$R/h188.txt"; git -C "$R" add -A && git -C "$R" commit -qm h188
git -C "$R" checkout -q -b feat
printf 'a\nb2\nc\nd\n' > "$R/h188.txt"; git -C "$R" commit -qam "c1: b2 (never landed)"
git -C "$R" mv h188.txt g188.txt && git -C "$R" commit -qm "c2: move"
git -C "$R" checkout -q main
M188="$(mktemp -d)/ran"
git -C "$R" config hook.probe188.event post-index-change; git -C "$R" config hook.probe188.command "echo ran >> '$M188'"
assert_exit "fixture-188 a branch that never landed, a moved file -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
assert_exit "fixture-188 a configured post-index-change hook did not run" 1 "$([ -e "$M188" ]; echo $?)"
rm -rf "$R"
# ...and above 64 KB of paths (the filtered trees), where round 16 ran it
R="$(mk_repo)"; mkdir -p "$R/a_fairly_long_directory_name_for_paths"; wide139 "$R" 'v\n' 1200
git -C "$R" add -A && git -C "$R" commit -qm wide188
git -C "$R" checkout -q -b feat
wide139 "$R" 'v\nw\n' 1200; git -C "$R" add -A && git -C "$R" commit -qm "c1: wide edit (never landed)"
git -C "$R" checkout -q main
git -C "$R" config hook.probe188.event post-index-change; git -C "$R" config hook.probe188.command "echo ran >> '$M188'"
assert_exit "fixture-188b a wide commit that never landed -> flagged" 3 "$(run_helper "$R" feat main)"
assert_exit "fixture-188b a configured post-index-change hook did not run" 1 "$([ -e "$M188" ]; echo $?)"
rm -rf "$R" "$(dirname "$M188")"

# 189: found by round 16's verify (requirements). In a partial clone git before 2.45
# would fetch a blob it never fetched (the network, the user's credentials, a write
# into the repository): the check stops before any read (exit 4). A git that reports
# 2.44 stands in for an older one.
R="$(mk_repo)"; git -C "$R" checkout -q -b feat; printf 'x\n' > "$R/p189.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1"
git -C "$R" checkout -q main; git -C "$R" config extensions.partialClone origin
B189="$(mktemp -d)"; G189="$(command -v git)"
printf '#!/bin/sh\nif [ "$1" = version ]; then echo "git version 2.44.0"; exit 0; fi\nexec "%s" "$@"\n' "$G189" > "$B189/git"; chmod +x "$B189/git"
E189="$(PATH="$B189:$PATH" "${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main 2>&1 >/dev/null; echo "rc=$?")"
assert_exit "fixture-189 a partial clone with git 2.44 -> exit 4" 0 "$(printf '%s\n' "$E189" | grep -q '^rc=4$'; echo $?)"
assert_exit "fixture-189 the reason names the partial clone" 0 "$(printf '%s\n' "$E189" | grep -q 'partial clone'; echo $?)"
E189b="$("${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main > /dev/null 2>&1; echo "$?")"
assert_exit "fixture-189 with this git (2.45 or newer) the check runs" 0 \
  "$([ "$(git version | awk '{ split($3, v, "."); print (v[1] > 2 || (v[1] == 2 && v[2] >= 45)) }')" = 0 ] || [ "$E189b" = 3 ]; echo $?)"
rm -rf "$R" "$B189"

# 190: a move spread over two commits of the branch (c1 deletes foo190.py, c2 adds
# bar190.py with the same lines and one edit); main edits another line of foo190.py,
# then squashes the branch (git pairs the two names across the branch and puts main's
# edit into bar190.py). Followed commit by commit the two are different files, and no
# commit holds the net change; one rename detection between the merge-base and the head,
# among the files added and deleted there, pairs them as the squash did, so the squash is
# the landing commit. c2 re-adds every line, main's edited one too, so it is listed there
# (D4, as round 16 did at the tip); c1 is not.
R="$(mk_repo)"; printf 'def f():\n    a = 1\n    b = 2\n    c = 3\n    d = 4\n    e = 5\n    return a\n' > "$R/foo190.py"
git -C "$R" add -A && git -C "$R" commit -qm foo190
git -C "$R" checkout -q -b feat
git -C "$R" rm -q foo190.py && git -C "$R" commit -qm "c1: drop foo190.py"
printf 'def f():\n    a = 1\n    b = 2\n    c = 3\n    d = 4\n    e = 50\n    return a\n' > "$R/bar190.py"; git -C "$R" add -A && git -C "$R" commit -qm "c2: bar190.py, e = 50"
git -C "$R" checkout -q main
printf 'def f():\n    a = 10\n    b = 2\n    c = 3\n    d = 4\n    e = 5\n    return a\n' > "$R/foo190.py"; git -C "$R" commit -qam "main: a = 10"
git -C "$R" merge -q --squash feat > /dev/null 2>&1 && git -C "$R" commit -qm "squash feat" > /dev/null 2>&1
assert_exit "fixture-190 the squash put main's edit into bar190.py" 0 "$(git -C "$R" show main:bar190.py | grep -qx '    a = 10'; echo $?)"
# (round 20: the squash records the move, a move on main at the landing commit -> exit 4)
assert_exit "fixture-190 a move over two commits, squashed, main's edit first -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 191: found by round 17's rename fuzz. Only part of the branch landed, as picks folded
# into one squash: c0 (a marker), c2 (f191.txt moved to h191.txt) and c3 (a new file at
# f191.txt); c1 and c4 (h191.txt moved on to g191.txt) never did. The squash moves the
# file and puts the new one at its old name in one step, so git records no move; the
# branch's file is the one main created at h191.txt, a name it had on the branch before
# its last one. Read by history, main's f191.txt (the new file) stood for it, and c0 and c3
# were listed although they landed.
R="$(mk_repo)"; L191=""; for i in 0 1 2 3 4 5 6 7; do L191="${L191}base $i\npad $i a\npad $i b\n"; done
printf "$L191" > "$R/f191.txt"; git -C "$R" add -A && git -C "$R" commit -qm f191
git -C "$R" checkout -q -b feat
awk '$0 == "pad 1 a" { print "M0 marker" } { print }' "$R/f191.txt" > "$R/t" && mv "$R/t" "$R/f191.txt"; git -C "$R" commit -qam "c0: marker"
sed 's/^pad 6 b$/pad 6 b = c1/' "$R/f191.txt" > "$R/t" && mv "$R/t" "$R/f191.txt"; git -C "$R" commit -qam "c1: pad 6 (never landed)"
git -C "$R" mv f191.txt h191.txt && git -C "$R" commit -qm "c2: move to h191.txt"
printf 'shim 1\nshim 2\n' > "$R/f191.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c3: a new f191.txt"
git -C "$R" mv h191.txt g191.txt && git -C "$R" commit -qm "c4: move to g191.txt (never landed)"
git -C "$R" checkout -q main; B191="$(git -C "$R" rev-parse HEAD)"
for c in feat~4 feat~2 feat~1; do git -C "$R" cherry-pick "$c" > /dev/null 2>&1; done
git -C "$R" reset -q --soft "$B191" && git -C "$R" commit -qm "PR (picks of c0, c2, c3, squashed)"
assert_exit "fixture-191 main has the marker in h191.txt and the new f191.txt" 0 \
  "$(git -C "$R" show main:h191.txt | grep -qx 'M0 marker' && git -C "$R" show main:f191.txt | grep -qx 'shim 1'; echo $?)"
OUT191=$(out_of "$R" feat main); RC191=$?
assert_exit "fixture-191 part of the branch landed under a middle name -> exit 4 (a move)" 4 "$RC191"
rm -rf "$R"

# 192: fixture 179's accepted route with the file moved between the two commits that
# touch the repeated text (c3 adds two copies, so the net change does change their
# number). The copy rule counts a text only when one commit of the
# branch touches it; c1 touched it under the file's old name, and listing the branch's
# commits by the file's last name alone saw c2 only, counted the squash as holding the
# net change, and moved c1 off the route 179 pins. The commits are listed by every name
# the file had.
R="$(mk_repo)"; printf 'pad 0\npad 1\npad 2\nx = 1\n    pass\n    pass\nx = 1\npad 3\npad 4\npad 5\n' > "$R/o192.txt"
git -C "$R" add -A && git -C "$R" commit -qm o192
git -C "$R" checkout -q -b feat
printf 'pad 0\npad 1\npad 2\nx = 1\n    pass\nx = 1\npad 3\npad 4\npad 5 = branch\n' > "$R/o192.txt"; git -C "$R" commit -qam "c1: drop a pass, set pad 5"
git -C "$R" mv o192.txt n192.txt && git -C "$R" commit -qm "c2: move"
printf 'pad 0\n    pass\npad 1\npad 2\nx = 1\n    pass\nx = 1\npad 3\n    pass\npad 4\npad 5 = branch\n' > "$R/n192.txt"
printf 'z\n' > "$R/z192.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c3: two copies + z"
git -C "$R" checkout -q main
printf 'pad 0\npad 1\npad 2\nx = 1 # main\n    pass\n    pass\nx = 1\npad 3\npad 4\npad 5\n' > "$R/o192.txt"; git -C "$R" commit -qam "main edit"
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm squash >/dev/null 2>&1
sed 's/^pad 5 = branch$/pad 5 = follow-up/' "$R/n192.txt" > "$R/t" && mv "$R/t" "$R/n192.txt"; git -C "$R" commit -qam follow-up
assert_exit "fixture-192 a text two commits touch, the file moved between them -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 193: found reviewing round 17's own draft: the commit-by-commit log ended on a commit
# with no change (an empty commit, `git commit --allow-empty`), whose header no entry
# followed, and reading the log failed (exit 4) for every branch whose newest commit is
# empty.
R="$(mk_repo)"; git -C "$R" checkout -q -b feat; printf 'b\n' > "$R/e193.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1: b"
git -C "$R" commit -q --allow-empty -m "c2: empty"
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat > /dev/null 2>&1 && git -C "$R" commit -qm squash > /dev/null 2>&1
printf 'b\nc\n' > "$R/e193.txt"; git -C "$R" commit -qam follow-up
assert_exit "fixture-193 the branch's newest commit is empty: squash, follow-up -> NOT flagged (not exit 4)" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 194: found by round 17's rename fuzz. Every commit landed, as picks folded into one
# squash: c0 moves f194.txt to src/g194.txt, c1 moves it on to deep/f194.txt, c2 puts a
# new file at src/g194.txt. main's history follows the file to deep/f194.txt (the squash
# records that move); taking instead the file main created at a name it had on the
# branch (src/g194.txt, the new file) listed c2. That rule applies only where history
# leaves the file at its merge-base name.
R="$(mk_repo)"; L194=""; for i in 0 1 2 3 4 5; do L194="${L194}base $i\npad $i a\npad $i b\n"; done
printf "$L194" > "$R/f194.txt"; git -C "$R" add -A && git -C "$R" commit -qm f194
git -C "$R" checkout -q -b feat
mkdir -p "$R/src"; git -C "$R" mv f194.txt src/g194.txt && git -C "$R" commit -qm "c0: move to src"
mkdir -p "$R/deep"; git -C "$R" mv src/g194.txt deep/f194.txt && git -C "$R" commit -qm "c1: move to deep"
mkdir -p "$R/src"; printf 'shim 1\nshim 2\n' > "$R/src/g194.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c2: a new src/g194.txt"
git -C "$R" checkout -q main; B194="$(git -C "$R" rev-parse HEAD)"
for c in feat~2 feat~1 feat; do git -C "$R" cherry-pick "$c" > /dev/null 2>&1; done
git -C "$R" reset -q --soft "$B194" && git -C "$R" commit -qm "PR (squash)"
assert_exit "fixture-194 two moves and a new file at the middle name, all landed -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 195: found by round 17's rename fuzz. c0 moves f195.txt to h195.txt and c1 puts a new
# file at f195.txt; c2 deletes a line and c4 puts a new file at h195.txt after c3 moved the
# file on to g195.txt; main picks c0, c1 and c3. c0 added the path h195.txt, and the head
# has a file there (c4's), but not c0's: an added path is an effect only while it is still
# the file's path in the head. c0 was listed.
R="$(mk_repo)"; L195=""; for i in 0 1 2 3 4 5 6 7; do L195="${L195}base $i\npad $i a\npad $i b\n"; done
printf "$L195" > "$R/f195.txt"; git -C "$R" add -A && git -C "$R" commit -qm f195
git -C "$R" checkout -q -b feat
git -C "$R" mv f195.txt h195.txt && git -C "$R" commit -qm "c0: move to h195"
printf 'shim 1 1\nshim 1 2\n' > "$R/f195.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1: a new f195.txt"
sed '/^base 7$/d' "$R/h195.txt" > "$R/t" && mv "$R/t" "$R/h195.txt"; git -C "$R" commit -qam "c2: del base 7 (never landed)"
git -C "$R" mv h195.txt g195.txt && git -C "$R" commit -qm "c3: move to g195"
printf 'shim 4 1\nshim 4 2\n' > "$R/h195.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c4: a new h195.txt (never landed)"
git -C "$R" checkout -q main; B195="$(git -C "$R" rev-parse HEAD)"
for c in feat~4 feat~3 feat~1; do git -C "$R" cherry-pick "$c" > /dev/null 2>&1; done
git -C "$R" reset -q --soft "$B195" && git -C "$R" commit -qm "PR (picks of c0, c1, c3, squashed)"
OUT195=$(out_of "$R" feat main); RC195=$?
assert_exit "fixture-195 a path a later move left, taken by a new file that never landed -> exit 4 (a move)" 4 "$RC195"
rm -rf "$R"

# ── Fixtures 196– (#399 round 18): main read by names where the branch landed ──

# 196: found by round 17's verify (devil's advocate, logic). c1 adds b196.txt (a copy of
# a196.txt), c2 deletes a196.txt; the squash records a rename of a196.txt to b196.txt, and
# the head and the tip have the same tree. Round 17 followed main's history, gave
# b196.txt's name to the merge-base file and left the branch's new file without one: the
# head-equals-tip shortcut compared files and listed both commits. The shortcut compares
# names, and a commit taken as (or after) the landing commit holds the branch's files at
# their names in what landed.
R="$(mk_repo)"; L196=""; for i in 1 2 3 4 5 6 7 8; do L196="${L196}line $i\n"; done
printf "$L196" > "$R/a196.txt"; git -C "$R" add -A && git -C "$R" commit -qm a196
git -C "$R" checkout -q -b feat
cp "$R/a196.txt" "$R/b196.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1: copy to b196"
git -C "$R" rm -q a196.txt && git -C "$R" commit -qm "c2: drop a196"
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat > /dev/null 2>&1 && git -C "$R" commit -qm squash > /dev/null 2>&1
assert_exit "fixture-196 a copy then the original deleted, squashed (head = tip) -> NOT flagged" 0 "$(run_helper "$R" feat main)"
sed 's/^line 3$/line 3 (follow-up)/' "$R/b196.txt" > "$R/t" && mv "$R/t" "$R/b196.txt"; git -C "$R" commit -qam "main: follow-up"
assert_exit "fixture-196b ...and a follow-up on main (#399's second shape) -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 197: found by round 17's verify (devil's advocate). Two files swap names over three
# commits (a to t, b to a, t to b); the squash records two edits and no move. c4 deletes
# a line of the new b197.txt and never lands. Read by main's history, b197.txt's key
# (the old a's file) was main's a197.txt, which held the other file, the deleted line
# was not there, and c4 read as landed (round 16 listed it).
R="$(mk_repo)"; for i in 1 2 3 4 5 6 7 8 9 10; do echo "alpha line $i"; done > "$R/a197.txt"
for i in 1 2 3 4 5 6 7 8 9 10; do echo "beta line $i"; done > "$R/b197.txt"; git -C "$R" add -A && git -C "$R" commit -qm ab197
git -C "$R" checkout -q -b feat
git -C "$R" mv a197.txt t197.txt && git -C "$R" commit -qm "c1: a to t"
git -C "$R" mv b197.txt a197.txt && git -C "$R" commit -qm "c2: b to a"
git -C "$R" mv t197.txt b197.txt && git -C "$R" commit -qm "c3: t to b"
sed '/^alpha line 5$/d' "$R/b197.txt" > "$R/t" && mv "$R/t" "$R/b197.txt"; git -C "$R" commit -qam "c4: delete alpha 5 (never landed)"
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat~1 > /dev/null 2>&1 && git -C "$R" commit -qm "PR (squash of the swap)" > /dev/null 2>&1
OUT197=$(out_of "$R" feat main); RC197=$?
assert_exit "fixture-197 two files swapped names, then a deletion that never landed -> exit 4 (a move)" 4 "$RC197"
rm -rf "$R"

# 198: found by round 17's verify (logic). The branch merges main after main squashed its
# first two commits (c1 adds n198.txt, c2 moves it to m198.txt); the same file then
# reaches m198.txt by two lines of history. Which one held the path depended on the
# order the log listed them, and the merge-base (main's commit, merged into the branch)
# had no file for its key: the net change lost c3's deletion, and c3, which never landed,
# read as landed. A path two lines bring a file to holds one file.
R="$(mk_repo)"; T198=1700000000; t198() { T198=$((T198 + 100)); export GIT_AUTHOR_DATE="$T198 +0800" GIT_COMMITTER_DATE="$T198 +0800"; }
git -C "$R" checkout -q -b feat
for i in $(seq 1 30); do echo "line $i of n"; done > "$R/n198.txt"; git -C "$R" add -A; t198; git -C "$R" commit -qm "c1: add n198"
git -C "$R" mv n198.txt m198.txt; t198; git -C "$R" commit -qm "c2: move to m198"
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat > /dev/null 2>&1; t198; git -C "$R" commit -qm "S1: squash c1 c2" > /dev/null
printf 'dup line\ndup line\n' >> "$R/m198.txt"; t198; git -C "$R" commit -qam "V: main adds two copies"
git -C "$R" checkout -q feat; t198
# (both sides add m198.txt: an add/add conflict, resolved to main's version)
git -C "$R" merge -q --no-edit main > /dev/null 2>&1 || { git -C "$R" checkout -q --theirs . && git -C "$R" add -A && git -C "$R" commit -qm "merge main"; }
grep -v '^dup line$' "$R/m198.txt" > "$R/t" && mv "$R/t" "$R/m198.txt"; t198; git -C "$R" commit -qam "c3: drop both copies (never landed)"
git -C "$R" checkout -q main
sed 's/^line 3 of n$/line 3 of n CHANGED/' "$R/m198.txt" > "$R/t" && mv "$R/t" "$R/m198.txt"; t198; git -C "$R" commit -qam "U1"
sed 's/^line 3 of n CHANGED$/line 3 of n/' "$R/m198.txt" > "$R/t" && mv "$R/t" "$R/m198.txt"; t198; git -C "$R" commit -qam "U2"
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
OUT198=$(out_of "$R" feat main); RC198=$?
assert_exit "fixture-198 the branch merged main after a partial squash, a deletion never landed -> exit 4 (a move)" 4 "$RC198"
rm -rf "$R"

# 199: found by round 17's verify (regression). Fixture 139 with the moved file named so
# it sorts before the wide directory. Two checks read the key list through a pipe and
# stopped at the first name a move involves; with pipefail the writer's SIGPIPE (141)
# became the answer, the diffs at the landing commit failed, and the commit was checked
# (or not verified) at the tip.
R="$(mk_repo)"; mkdir -p "$R/a_fairly_long_directory_name_for_paths"; wide139 "$R" 'v\n'
printf 'r1 alpha\nr2 beta\n' > "$R/Ar199.txt"; git -C "$R" add -A && git -C "$R" commit -qm wide199
git -C "$R" checkout -q -b feat
printf 'r1 alpha\nr2 beta\nr3 gamma\n' > "$R/Ar199.txt"; git -C "$R" commit -qam "c0: r3"
wide139 "$R" 'v\nw\n'; printf 'r1 alpha\nr2 beta\n' > "$R/Ar199.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1: wide edit, r3 dropped"
git -C "$R" checkout -q main
git -C "$R" mv Ar199.txt As199.txt && git -C "$R" commit -qm "main: Ar199 moved to As199"
git -C "$R" checkout -q feat -- a_fairly_long_directory_name_for_paths && git -C "$R" commit -qm "squash feat"
assert_exit "fixture-199 a wide squash, a file main moved sorting first -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 200: found by round 17's verify (Codex, requirements, security, devil's advocate). A
# partial clone made by `git clone --filter` has remote.<name>.promisor = true and no
# extensions.partialClone; with git before 2.45 it was not recognized and blobs would
# have been fetched. A git that reports 2.44 stands in for an older one.
R="$(mk_repo)"; git -C "$R" checkout -q -b feat; printf 'x\n' > "$R/p200.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1"
git -C "$R" checkout -q main; git -C "$R" config remote.origin.promisor true
B200="$(mktemp -d)"; G200="$(command -v git)"
printf '#!/bin/sh\nif [ "$1" = version ]; then echo "git version 2.44.0"; exit 0; fi\nexec "%s" "$@"\n' "$G200" > "$B200/git"; chmod +x "$B200/git"
E200="$(PATH="$B200:$PATH" "${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main 2>&1 >/dev/null; echo "rc=$?")"
assert_exit "fixture-200 a promisor remote with git 2.44 -> exit 4, naming the partial clone" 0 \
  "$(printf '%s\n' "$E200" | grep -q '^rc=4$' && printf '%s\n' "$E200" | grep -q 'partial clone'; echo $?)"
rm -rf "$R" "$B200"

# 201: found by round 17's verify (Codex). A path with the byte awk joins subscripts with
# (\034): the tip check split the joined name map on it, read the file as missing on both
# sides, and an edit that never landed read as clean.
R="$(mk_repo)"; F201="$(printf 'a\034b201.txt')"; printf 'one\ntwo\n' > "$R/$F201"; git -C "$R" add -A && git -C "$R" commit -qm f201
git -C "$R" checkout -q -b feat; printf 'one\ntwo\nthree (never landed)\n' > "$R/$F201"; git -C "$R" commit -qam "c1: three"
git -C "$R" checkout -q main; printf 'o\n' > "$R/o201.txt"; git -C "$R" add -A && git -C "$R" commit -qm "main: other"
assert_exit "fixture-201 a path holding byte 034, an edit that never landed -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 202: found by round 17's verify (regression). No merge-base (an orphan branch whose
# file main took): round 17 exited 4 before the head-equals-tip shortcut. Nothing is
# followed then, and the shortcut answers as before.
R="$(mk_repo)"; git -C "$R" checkout -q --orphan feat; git -C "$R" rm -rqf . > /dev/null 2>&1
printf 'x\ny\n' > "$R/o202.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1: o202"
# (main's commit also adds a file of its own, so git cherry lists c1 as a candidate)
git -C "$R" checkout -q main; printf 'x\ny\n' > "$R/o202.txt"; printf 'z\n' > "$R/z202.txt"; git -C "$R" add -A && git -C "$R" commit -qm "main: took o202"
assert_exit "fixture-202 no merge-base, the head's file on main -> NOT flagged (not exit 4)" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 203: a deletion from a file main moved, never landed. Round 16 (and 3.5.0) read the
# tip under the branch's name, found no file there and missed it; with main's file
# followed to its new name it is listed.
R="$(mk_repo)"; printf 'k\nZ = stale\nm\n' > "$R/x203.txt"; git -C "$R" add -A && git -C "$R" commit -qm x203
git -C "$R" checkout -q -b feat; printf 'k\nm\n' > "$R/x203.txt"; git -C "$R" commit -qam "c1: delete Z (never landed)"
git -C "$R" checkout -q main; git -C "$R" mv x203.txt y203.txt && git -C "$R" commit -qm "main: move to y203"
OUT203=$(out_of "$R" feat main); RC203=$?
assert_exit "fixture-203 a deletion from a file main moved, never landed -> exit 4 (a move)" 4 "$RC203"
rm -rf "$R"

# 204: found by round 18's own design review. Two files swap names over three commits
# (c1-c3) and c4 deletes a line of the new b204.txt; nothing of it landed (main took an
# unrelated commit of its own). The tip has no landing to read the head's names by: read
# by them, b204.txt (the old a's file) was main's b204.txt, which holds the other file,
# the deleted line was not there, and c4 read as landed; the moves read as landed too.
# Main never touched either file, so its history says where each file is.
R="$(mk_repo)"; for i in 1 2 3 4 5 6 7 8 9 10; do echo "alpha line $i"; done > "$R/a204.txt"
for i in 1 2 3 4 5 6 7 8 9 10; do echo "beta line $i"; done > "$R/b204.txt"; git -C "$R" add -A && git -C "$R" commit -qm ab204
git -C "$R" checkout -q -b feat
git -C "$R" mv a204.txt t204.txt && git -C "$R" commit -qm "c1: a to t"
git -C "$R" mv b204.txt a204.txt && git -C "$R" commit -qm "c2: b to a"
git -C "$R" mv t204.txt b204.txt && git -C "$R" commit -qm "c3: t to b"
sed '/^alpha line 5$/d' "$R/b204.txt" > "$R/t" && mv "$R/t" "$R/b204.txt"; git -C "$R" commit -qam "c4: delete alpha 5"
git -C "$R" checkout -q main; printf 'own\n' > "$R/own204.txt"; git -C "$R" add -A && git -C "$R" commit -qm "main: own"
OUT204=$(out_of "$R" feat main); RC204=$?
assert_exit "fixture-204 a swap and a deletion, nothing landed -> exit 4 (a move)" 4 "$RC204"
rm -rf "$R"

# 205: found by round 18's second rename fuzz. main squashes a swap of two files (c1-c3);
# the branch merges main, swaps them back (c4-c6) and deletes a line (c7), none of which
# landed. The squash, now in the head's history, was read by that history (its rename
# detection pairs nothing: two edits), so the tip had each file where the other is, and
# the swap back and the deletion read as landed. A commit of main the branch merged is
# still read by the names of what landed.
R="$(mk_repo)"; for i in 1 2 3 4 5 6 7 8 9 10; do echo "alpha line $i"; done > "$R/f205.txt"
for i in 1 2 3 4 5 6 7 8 9 10; do echo "beta line $i"; done > "$R/g205.txt"; git -C "$R" add -A && git -C "$R" commit -qm fg205
git -C "$R" checkout -q -b feat
git -C "$R" mv f205.txt t205.txt && git -C "$R" commit -qm "c1: f to t"
git -C "$R" mv g205.txt f205.txt && git -C "$R" commit -qm "c2: g to f"
git -C "$R" mv t205.txt g205.txt && git -C "$R" commit -qm "c3: t to g"
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat > /dev/null 2>&1 && git -C "$R" commit -qm "PR (squash of the swap)" > /dev/null
git -C "$R" checkout -q feat; git -C "$R" merge -q --no-edit main > /dev/null 2>&1
git -C "$R" mv g205.txt u205.txt && git -C "$R" commit -qm "c4: g to u"
git -C "$R" mv f205.txt g205.txt && git -C "$R" commit -qm "c5: f to g"
git -C "$R" mv u205.txt f205.txt && git -C "$R" commit -qm "c6: u to f (swapped back)"
sed '/^beta line 5$/d' "$R/g205.txt" > "$R/t" && mv "$R/t" "$R/g205.txt"; git -C "$R" commit -qam "c7: delete beta 5"
git -C "$R" checkout -q main
OUT205=$(out_of "$R" feat main); RC205=$?
assert_exit "fixture-205 the branch merged a squash of a swap, swapped back, deleted a line -> exit 4 (a move)" 4 "$RC205"
rm -rf "$R"

# 206: found by round 17's verify (security). hook.post-index-change.enabled, the
# event's own switch, is git 2.55's; git 2.54 already runs hooks defined in the
# configuration and turns one off only by its own name. A git that drops the event
# switch stands in for 2.54: every hook bound to the event is also turned off by name.
# (round 20: over 64 KB of paths, the filtered trees; a small branch with a move, which
# round 17 used, now stops before building any tree)
R="$(mk_repo)"; mkdir -p "$R/a_fairly_long_directory_name_for_paths"; wide139 "$R" 'v\n' 1200
git -C "$R" add -A && git -C "$R" commit -qm wide206
git -C "$R" checkout -q -b feat
wide139 "$R" 'v\nw\n' 1200; git -C "$R" add -A && git -C "$R" commit -qm "c1: wide edit (never landed)"
git -C "$R" checkout -q main
B206="$(mktemp -d)"; M206="$B206/ran"; G206="$(command -v git)"
git -C "$R" config hook.probe206.event post-index-change; git -C "$R" config hook.probe206.command "echo ran >> '$M206'"
cat > "$B206/git" <<SHIM
#!/bin/bash
out=(); a=("\$@"); i=0
while [ \$i -lt \${#a[@]} ]; do
  if [ "\${a[\$i]}" = -c ] && [ "\${a[\$((i + 1))]}" = hook.post-index-change.enabled=false ]; then i=\$((i + 2)); continue; fi
  out+=("\${a[\$i]}"); i=\$((i + 1))
done
exec "$G206" "\${out[@]}"
SHIM
chmod +x "$B206/git"
assert_exit "fixture-206 a branch that never landed, with git 2.54's hook switches -> flagged" 3 \
  "$(PATH="$B206:$PATH" "${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main > /dev/null 2>&1; echo $?)"
assert_exit "fixture-206 the configured hook did not run" 1 "$([ -e "$M206" ]; echo $?)"
rm -rf "$R" "$B206"

# 207: found by round 18's second rename fuzz. c1 copies f207.txt to k207.txt (with a
# marker), c2 deletes f207.txt, c3 moves k207.txt on to t207.txt; main picks c1 and c2
# into one squash (git records a move of f207.txt to k207.txt). The merge-base and the
# head pair f207.txt with t207.txt, but the head's file got there by another route (added
# as k207.txt, then moved), so the deleted original kept a key of its own, the head had
# nothing under it, main had the file there, and c2's deletion and c1's copy read as
# never landed. The deleted file and the file at the paired name are one file.
R="$(mk_repo)"; L207=""; for i in 0 1 2 3 4 5 6 7; do L207="${L207}base $i\npad $i a\npad $i b\n"; done
printf "$L207" > "$R/f207.txt"; printf 'g1\ng2\ng3\n' > "$R/g207.txt"; git -C "$R" add -A && git -C "$R" commit -qm fg207
git -C "$R" checkout -q -b feat
printf 'g1\nM0 marker\ng2\ng3\n' > "$R/g207.txt"; git -C "$R" commit -qam "c0: g marker (never landed)"
{ cat "$R/f207.txt"; echo "C1 copy marker"; } > "$R/k207.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1: copy to k207"
git -C "$R" rm -q f207.txt && git -C "$R" commit -qm "c2: delete f207"
git -C "$R" mv k207.txt t207.txt && git -C "$R" commit -qm "c3: move to t207 (never landed)"
git -C "$R" checkout -q main; B207="$(git -C "$R" rev-parse HEAD)"
for c in feat~2 feat~1; do git -C "$R" cherry-pick "$c" > /dev/null 2>&1; done
git -C "$R" reset -q --soft "$B207" && git -C "$R" commit -qm "PR (picks of c1, c2, squashed)"
OUT207=$(out_of "$R" feat main); RC207=$?
assert_exit "fixture-207 a copy, the original deleted, the copy moved on; main has the first two -> exit 4 (a move)" 4 "$RC207"
rm -rf "$R"

# 208: found by round 18's second rename fuzz. A chain of copies: c1 copies f208.txt to
# g208.txt and c2 deletes f208.txt (both landed, squashed); c3 adds a line to g208.txt,
# c4 copies it to h208.txt and c5 deletes g208.txt (none landed). One rename detection
# between the merge-base and the head pairs f208.txt with h208.txt only, so the middle
# copy was a file of its own, gone from the head, and c3's line read as landed. Each
# deletion is paired with the copies the branch made before it.
R="$(mk_repo)"; L208=""; for i in 0 1 2 3 4 5 6 7; do L208="${L208}base $i\npad $i a\npad $i b\n"; done
printf "$L208" > "$R/f208.txt"; git -C "$R" add -A && git -C "$R" commit -qm f208
git -C "$R" checkout -q -b feat
{ cat "$R/f208.txt"; echo "C1 copy marker"; } > "$R/g208.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1: copy to g208"
git -C "$R" rm -q f208.txt && git -C "$R" commit -qm "c2: delete f208"
awk '$0 == "pad 3 a" { print "M3 marker" } { print }' "$R/g208.txt" > "$R/t" && mv "$R/t" "$R/g208.txt"; git -C "$R" commit -qam "c3: M3 (never landed)"
{ cat "$R/g208.txt"; echo "C4 copy marker"; } > "$R/h208.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c4: copy to h208 (never landed)"
git -C "$R" rm -q g208.txt && git -C "$R" commit -qm "c5: delete g208 (never landed)"
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat~3 > /dev/null 2>&1 && git -C "$R" commit -qm "PR (squash of c1, c2)" > /dev/null
OUT208=$(out_of "$R" feat main); RC208=$?
assert_exit "fixture-208 a chain of copies, the first link landed -> exit 4 (a move)" 4 "$RC208"
rm -rf "$R"

# 209: found by round 18's second rename fuzz. Two files swap names over three commits
# (c1-c3, squashed into main); c4 moves the first file on again, out of g209.txt, and never
# lands. c2 moved the other file out of g209.txt; the landing commit has a file there (the
# first one, which c3 put there), and the head has none. By name that read as c2's
# deletion never landing; the landing commit's file at g209.txt is not c2's.
R="$(mk_repo)"; for i in 1 2 3 4 5 6 7 8 9 10; do echo "alpha line $i"; done > "$R/f209.txt"
for i in 1 2 3 4 5 6 7 8 9 10; do echo "beta line $i"; done > "$R/g209.txt"; git -C "$R" add -A && git -C "$R" commit -qm fg209
git -C "$R" checkout -q -b feat
git -C "$R" mv f209.txt h209.txt && git -C "$R" commit -qm "c1: f to h"
git -C "$R" mv g209.txt f209.txt && git -C "$R" commit -qm "c2: g to f"
git -C "$R" mv h209.txt g209.txt && git -C "$R" commit -qm "c3: h to g"
git -C "$R" mv g209.txt h209.txt && git -C "$R" commit -qm "c4: g to h again (never landed)"
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat~1 > /dev/null 2>&1 && git -C "$R" commit -qm "PR (squash of the swap)" > /dev/null
OUT209=$(out_of "$R" feat main); RC209=$?
assert_exit "fixture-209 a swap landed, a later move never did -> exit 4 (a move)" 4 "$RC209"
rm -rf "$R"

# 210: found by round 18's second rename fuzz. c0 adds a line to g210.txt, c1 copies it
# to t210.txt (with a marker), c2 deletes g210.txt; main squashes c0 and c1. Before the
# deletion the branch holds the file twice; read for c1's prefix, the squash had it at
# g210.txt (its history) rather than t210.txt, so c1's prefix did not land, the landing
# was c0's, and c1, checked at the tip against g210.txt, was listed. A name the
# reference has for the file, the copy's or the original's, is one it wants.
R="$(mk_repo)"; L210=""; for i in 0 1 2 3 4 5 6 7; do L210="${L210}base $i\npad $i a\npad $i b\n"; done
printf "$L210" > "$R/g210.txt"; git -C "$R" add -A && git -C "$R" commit -qm g210
git -C "$R" checkout -q -b feat
awk '$0 == "pad 2 a" { print "M0 marker" } { print }' "$R/g210.txt" > "$R/t" && mv "$R/t" "$R/g210.txt"; git -C "$R" commit -qam "c0: M0"
{ cat "$R/g210.txt"; echo "C1 copy marker"; } > "$R/t210.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1: copy to t210"
git -C "$R" rm -q g210.txt && git -C "$R" commit -qm "c2: delete g210 (never landed)"
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat~1 > /dev/null 2>&1 && git -C "$R" commit -qm "PR (squash of c0, c1)" > /dev/null
OUT210=$(out_of "$R" feat main); RC210=$?
assert_exit "fixture-210 a copy landed, the original's deletion did not -> flagged" 3 "$RC210"
assert_exit "fixture-210 lists c2" 0 "$(has "$OUT210" 'c2: delete g210')"
assert_exit "fixture-210 does not list c1" 1 "$(has "$OUT210" 'c1: copy to t210')"
rm -rf "$R"

# 211: found by round 18's second rename fuzz. c0 copies f211.txt to d211.txt (main picks
# it alone, so c0's prefix landed there), c1 deletes f211.txt and c2 puts a new file
# there; neither landed. The tip is read by c0's names, where the file is at d211.txt and,
# until c1, at f211.txt as well; the new file, at no name in c0, took main's f211.txt as a
# name it had on the branch, and c1's deletion read as landed. A name the reference gives
# one file is no other file's (and with nothing landed, a name main never changed stays
# with the file its history says, the same way).
R="$(mk_repo)"; L211=""; for i in 0 1 2 3 4 5 6 7; do L211="${L211}base $i\npad $i a\npad $i b\n"; done
printf "$L211" > "$R/f211.txt"; git -C "$R" add -A && git -C "$R" commit -qm f211
git -C "$R" checkout -q -b feat
{ cat "$R/f211.txt"; echo "C0 copy marker"; } > "$R/d211.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c0: copy to d211"
git -C "$R" rm -q f211.txt && git -C "$R" commit -qm "c1: delete f211 (never landed)"
printf 'shim 1\nshim 2\n' > "$R/f211.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c2: a new f211 (never landed)"
# (main's own commit first: a pick onto c0's own parent within the same second is c0 itself)
git -C "$R" checkout -q main; printf 'own\n' > "$R/own211.txt"; git -C "$R" add -A && git -C "$R" commit -qm "main: own"
git -C "$R" cherry-pick feat~2 > /dev/null 2>&1
OUT211=$(out_of "$R" feat main); RC211=$?
assert_exit "fixture-211 a copy picked alone, the original's deletion and a new file there not -> flagged" 3 "$RC211"
assert_exit "fixture-211 lists c1 and c2" 0 "$({ has "$OUT211" 'c1: delete f211'; has "$OUT211" 'c2: a new f211'; } | tr -d '\n' | grep -qx 00; echo $?)"
rm -rf "$R"

# 212: found by round 17's rename fuzz on round 18's draft. c0 moves f212.txt to
# h212.txt, c1 deletes a line and c2 rewrites most of the file, c3 puts a new file at
# f212.txt; main picks c1 and c2 (git applies them to f212.txt) into one squash. Nothing
# landed by the landing search, so the tip has the head's names where main changed the
# file: the new file's name took main's f212.txt, which is the branch's file, edited, and
# c2's rewrite read as never landed. Where main changed the file at a name the head gives
# one file and main's history another, the content says which.
R="$(mk_repo)"; L212=""; for i in 0 1 2 3 4 5 6 7 8 9; do L212="${L212}base $i\npad $i a\npad $i b\npad $i c\n"; done
printf "$L212" > "$R/f212.txt"; git -C "$R" add -A && git -C "$R" commit -qm f212
git -C "$R" checkout -q -b feat
git -C "$R" mv f212.txt h212.txt && git -C "$R" commit -qm "c0: move to h212 (never landed)"
sed '/^base 7$/d' "$R/h212.txt" > "$R/t" && mv "$R/t" "$R/h212.txt"; git -C "$R" commit -qam "c1: delete base 7"
awk '/^pad [0-9] [ab]$/ { print "R2 " $2 $3; next } { print }' "$R/h212.txt" > "$R/t" && mv "$R/t" "$R/h212.txt"; git -C "$R" commit -qam "c2: rewrite"
printf 'shim 1\nshim 2\n' > "$R/f212.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c3: a new f212 (never landed)"
git -C "$R" checkout -q main; B212="$(git -C "$R" rev-parse HEAD)"
for c in feat~2 feat~1; do git -C "$R" cherry-pick "$c" > /dev/null 2>&1; done
git -C "$R" reset -q --soft "$B212" && git -C "$R" commit -qm "PR (picks of c1, c2, squashed)"
assert_exit "fixture-212 main's f212.txt is the branch's file with c1 and c2" 0 \
  "$(git -C "$R" show main:f212.txt | grep -q '^R2 ' && ! git -C "$R" show main:f212.txt | grep -qx 'base 7'; echo $?)"
OUT212=$(out_of "$R" feat main); RC212=$?
assert_exit "fixture-212 a move and a new file at the old name never landed, edits did -> exit 4 (a move)" 4 "$RC212"
rm -rf "$R"

# ── Fixtures 213– (#399 round 19): fewer rules, each where the files decide ──

# 213: found by round 18's verify (logic). feat adds gen213.txt and edits it; main
# squashes them and then moves the file to lib/gen213.txt; feat merges main (the head has
# both names) and appends a line to gen213.txt, which never lands. The view of the head
# joined the two arrivals at gen213.txt into one file, main's move took it, and the line
# read as no change at all (exit 0). A name the revision holds that the view lost is a
# file of its own.
R="$(mk_repo)"; T213=1700000000; t213() { T213=$((T213 + 10)); export GIT_AUTHOR_DATE="@$T213 +0800" GIT_COMMITTER_DATE="@$T213 +0800"; }
git -C "$R" checkout -q -b feat
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "G line $i of something unique"; done > "$R/gen213.txt"; git -C "$R" add -A; t213; git -C "$R" commit -qm "b1: add gen213"
echo "b2 line" >> "$R/gen213.txt"; t213; git -C "$R" commit -qam "b2: edit gen213"
git -C "$R" checkout -q main; echo own > "$R/own213.txt"; git -C "$R" add -A; t213; git -C "$R" commit -qm "main: own"
git -C "$R" merge -q --squash feat > /dev/null 2>&1; t213; git -C "$R" commit -qm "squash feat" > /dev/null
mkdir -p "$R/lib"; git -C "$R" mv gen213.txt lib/gen213.txt; t213; git -C "$R" commit -qm "main: move gen213 to lib"
git -C "$R" checkout -q feat; t213; git -C "$R" merge -q --no-edit main > /dev/null 2>&1
echo "b4 line" >> "$R/gen213.txt"; t213; git -C "$R" commit -qam "b4: edit gen213 at its old path (never landed)"
unset GIT_AUTHOR_DATE GIT_COMMITTER_DATE
OUT213=$(out_of "$R" feat main); RC213=$?
assert_exit "fixture-213 the branch merged main, which moved the file; an edit at the old path never landed -> exit 4 (a move)" 4 "$RC213"
rm -rf "$R"

# 214: found by round 18's verify (devil's advocate). c1 moves x214.txt to y214.txt, c2
# puts the original x214.txt back; main squashes the branch and later edits y214.txt
# (#399's own shape). The weak reading kept x214.txt for the moved file, which history
# puts there and which already had y214.txt: the restored file had no name on main, and
# both commits were listed. A file history puts at a name keeps it only when it has no
# place of its own.
R="$(mk_repo)"; for i in 1 2 3 4 5 6 7 8 9 10; do echo "x line $i"; done > "$R/x214.txt"; git -C "$R" add -A && git -C "$R" commit -qm x214
git -C "$R" checkout -q -b feat
git -C "$R" mv x214.txt y214.txt && git -C "$R" commit -qm "c1: move x214 to y214"
git -C "$R" show HEAD~1:x214.txt > "$R/x214.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c2: restore x214"
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat > /dev/null 2>&1 && git -C "$R" commit -qm "PR (squash)" > /dev/null
sed 's/^x line 3$/x line 3 (main later)/' "$R/y214.txt" > "$R/t" && mv "$R/t" "$R/y214.txt"; git -C "$R" commit -qam "main: later edit"
assert_exit "fixture-214 a move and the original put back, squashed, main's later edit -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 215: found by round 18's verify (logic). The same with the old name recreated byte for
# byte and the moved file then edited; main squashes and edits the moved file later.
R="$(mk_repo)"; for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "X line $i of something unique"; done > "$R/x215.txt"; git -C "$R" add -A && git -C "$R" commit -qm x215
git -C "$R" checkout -q -b feat
git -C "$R" mv x215.txt y215.txt && git -C "$R" commit -qm "c1: move x215 to y215"
cp "$R/y215.txt" "$R/x215.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c2: recreate x215"
echo "feat edit" >> "$R/y215.txt"; git -C "$R" commit -qam "c3: edit y215"
git -C "$R" checkout -q main; echo own > "$R/own215.txt"; git -C "$R" add -A && git -C "$R" commit -qm "main: own"
git -C "$R" merge -q --squash feat > /dev/null 2>&1 && git -C "$R" commit -qm "PR (squash)" > /dev/null
echo "main later" >> "$R/y215.txt"; git -C "$R" commit -qam "main: later edit"
assert_exit "fixture-215 a move and an identical file at the old name, squashed, main's later edit -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 216: found by round 18's verify (requirements). Two files swap names over three commits
# (c0-c2), c3 copies the first to lib/f216.txt and c4 deletes it from g216.txt, c5 adds an
# unrelated file; main squashes picks of c0, c1, c3, c5, so it still has the first file at
# t216.txt, where c2 took it from. That name is in no net change (the branch made it and
# removed it again), the whole branch read as landed at the squash, and c2 was missed (exit
# 0). A name the landing commit (or the tip) gives no file of the head can still hold the
# file a commit took away: such a deletion counts as not landed.
R="$(mk_repo)"; L216=""; M216=""; for i in 0 1 2 3 4 5 6 7; do L216="${L216}base A$i\npad A$i a\npad A$i b\n"; M216="${M216}base B$i\npad B$i a\npad B$i b\n"; done
printf "$L216" > "$R/f216.txt"; printf "$M216" > "$R/g216.txt"; git -C "$R" add -A && git -C "$R" commit -qm fg216
git -C "$R" checkout -q -b feat
git -C "$R" mv f216.txt t216.txt && git -C "$R" commit -qm "c0: f to t"
git -C "$R" mv g216.txt f216.txt && git -C "$R" commit -qm "c1: g to f"
git -C "$R" mv t216.txt g216.txt && git -C "$R" commit -qm "c2: t to g (never landed)"
mkdir -p "$R/lib"; { cat "$R/g216.txt"; echo "C3 copy marker"; } > "$R/lib/f216.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c3: copy to lib"
git -C "$R" rm -q g216.txt && git -C "$R" commit -qm "c4: delete g216 (never landed)"
printf 'u5\n' > "$R/u216.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c5: other"
git -C "$R" checkout -q main; B216="$(git -C "$R" rev-parse HEAD)"
for c in feat~5 feat~4 feat~2 feat; do git -C "$R" cherry-pick "$c" > /dev/null 2>&1; done
git -C "$R" reset -q --soft "$B216" && git -C "$R" commit -qm "PR (picks of c0, c1, c3, c5, squashed)"
OUT216=$(out_of "$R" feat main); RC216=$?
assert_exit "fixture-216 a swap and a copy, the last move never landed, the rest squashed -> exit 4 (a move)" 4 "$RC216"
rm -rf "$R"

# 217: found by round 18's verify (regression). g217.txt copied to zz217.txt (c0) and to
# aa217.txt (c1), deleted (c2, never landed), the first copy edited (c3); main squashes
# c0, c1 and c3. Which copy the deletion was paired with followed awk's hash order, and
# macOS listed c1 too. The newest copy, in a fixed order; and a file the head has at the
# name the reference gives it is that file, not the original history keeps elsewhere.
R="$(mk_repo)"; L217=""; for i in 0 1 2 3 4 5 6 7; do L217="${L217}base $i\npad $i a\npad $i b\n"; done
printf "$L217" > "$R/g217.txt"; git -C "$R" add -A && git -C "$R" commit -qm g217
git -C "$R" checkout -q -b feat
cp "$R/g217.txt" "$R/zz217.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c0: copy to zz217"
cp "$R/g217.txt" "$R/aa217.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1: copy to aa217"
git -C "$R" rm -q g217.txt && git -C "$R" commit -qm "c2: delete g217 (never landed)"
echo "c3 line" >> "$R/zz217.txt"; git -C "$R" commit -qam "c3: edit zz217"
git -C "$R" checkout -q main; echo own > "$R/own217.txt"; git -C "$R" add -A && git -C "$R" commit -qm "main: own"; B217="$(git -C "$R" rev-parse HEAD)"
for c in feat~3 feat~2 feat; do git -C "$R" cherry-pick "$c" > /dev/null 2>&1; done
git -C "$R" reset -q --soft "$B217" && git -C "$R" commit -qm "PR (picks of c0, c1, c3, squashed)"
OUT217=$(out_of "$R" feat main); RC217=$?
assert_exit "fixture-217 two copies, the original's deletion never landed -> flagged" 3 "$RC217"
assert_exit "fixture-217 lists c2 and not c1" 0 "$({ has "$OUT217" 'c2: delete g217'; has "$OUT217" 'c1: copy to aa217'; } | tr -d '\n' | grep -qx 01; echo $?)"
rm -rf "$R"

# 218: found by round 18's verify (security). GIT_CONFIG in the environment points `git
# config` at another file, and the partial clone check read none of the repository's
# configuration: with git 2.44, the blobs would have been fetched.
R="$(mk_repo)"; git -C "$R" checkout -q -b feat; printf 'x\n' > "$R/p218.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1"
git -C "$R" checkout -q main; git -C "$R" config remote.origin.promisor true
B218="$(mktemp -d)"; G218="$(command -v git)"
printf '#!/bin/sh\nif [ "$1" = version ]; then echo "git version 2.44.0"; exit 0; fi\nexec "%s" "$@"\n' "$G218" > "$B218/git"; chmod +x "$B218/git"
E218="$(GIT_CONFIG=/dev/null PATH="$B218:$PATH" "${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main 2>&1 >/dev/null; echo "rc=$?")"
assert_exit "fixture-218 GIT_CONFIG set, a promisor remote, git 2.44 -> exit 4, naming the partial clone" 0 \
  "$(printf '%s\n' "$E218" | grep -q '^rc=4$' && printf '%s\n' "$E218" | grep -q 'partial clone'; echo $?)"
rm -rf "$R" "$B218"

# 219: found by round 18's verify (security). A remote with only a partial clone filter
# (remote.<name>.partialclonefilter), which git treats as a promisor.
R="$(mk_repo)"; git -C "$R" checkout -q -b feat; printf 'x\n' > "$R/p219.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1"
git -C "$R" checkout -q main; git -C "$R" config remote.origin.partialclonefilter blob:none
B219="$(mktemp -d)"; G219="$(command -v git)"
printf '#!/bin/sh\nif [ "$1" = version ]; then echo "git version 2.44.0"; exit 0; fi\nexec "%s" "$@"\n' "$G219" > "$B219/git"; chmod +x "$B219/git"
E219="$(PATH="$B219:$PATH" "${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main 2>&1 >/dev/null; echo "rc=$?")"
assert_exit "fixture-219 a remote with a partial clone filter, git 2.44 -> exit 4" 0 \
  "$(printf '%s\n' "$E219" | grep -q '^rc=4$' && printf '%s\n' "$E219" | grep -q 'partial clone'; echo $?)"
rm -rf "$R" "$B219"

# 220: found by round 18's verify (requirements). c0 edits another file (never landed),
# c1 deletes a line of g220.txt, c2 copies it to t220.txt, c3 deletes g220.txt; main picks
# c2 alone. No prefix landed, so the commits are checked at the tip, where main has the
# line in g220.txt, which c3's deletion never removed, and not in the copy: read at the
# copy alone, c1's deletion read as landed. A line a commit deleted is kept at the tip
# when any name of the file still has it. (When the prefix up to the copy lands, the copy
# carries the deletion and the landing commit reads it there: a known limit, SPEC D1.)
R="$(mk_repo)"; L220=""; for i in 0 1 2 3 4 5 6 7; do L220="${L220}base $i\npad $i a\npad $i b\n"; done
printf "$L220" > "$R/g220.txt"; printf 'o1\no2\n' > "$R/o220.txt"; git -C "$R" add -A && git -C "$R" commit -qm g220
git -C "$R" checkout -q -b feat
printf 'o1\no2 = c0\n' > "$R/o220.txt"; git -C "$R" commit -qam "c0: o2 (never landed)"
sed '/^base 5$/d' "$R/g220.txt" > "$R/t" && mv "$R/t" "$R/g220.txt"; git -C "$R" commit -qam "c1: delete base 5 (never landed)"
{ cat "$R/g220.txt"; echo "C2 copy marker"; } > "$R/t220.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c2: copy to t220"
git -C "$R" rm -q g220.txt && git -C "$R" commit -qm "c3: delete g220 (never landed)"
git -C "$R" checkout -q main; git -C "$R" cherry-pick feat~1 > /dev/null 2>&1
OUT220=$(out_of "$R" feat main); RC220=$?
assert_exit "fixture-220 a copy picked alone, a deletion before it never landed -> flagged" 3 "$RC220"
assert_exit "fixture-220 lists c1 and c3, not c2" 0 \
  "$({ has "$OUT220" 'c1: delete base 5'; has "$OUT220" 'c3: delete g220'; has "$OUT220" 'c2: copy to t220'; } | tr -d '\n' | grep -qx 001; echo $?)"
rm -rf "$R"

# ── Round 20 (the maintainer's decision of 2026-11-01): moves are not judged; a part of the
# branch main received before the branch merged main in is checked where it landed ──

# 221: #399 verify round 19 (devil's advocate). c1 edits line 5; main squashes it (PR1);
# the branch merges main (GitHub's Update branch) and c2 edits line 12; main edits c1's line
# (a follow-up) and squashes the branch again (PR2). After the merge the merge-base holds
# PR1, the whole branch landed at PR2, and c1's line is no longer in place there: every
# round up to 19 and 3.5.0 listed c1. c1 landed at PR1 (SPEC, Definition).
mk221() { # repo -> the shape above, up to the merge and c2
  seq 1 20 > "$1/n221.txt"; git -C "$1" add -A && git -C "$1" commit -qm n221
  git -C "$1" checkout -q -b feat
  sed 's/^5$/five/' "$1/n221.txt" > "$1/t" && mv "$1/t" "$1/n221.txt"; git -C "$1" commit -qam "c1: five"
  git -C "$1" checkout -q main; git -C "$1" merge -q --squash feat > /dev/null 2>&1; git -C "$1" commit -qm "PR1"
  git -C "$1" checkout -q feat; git -C "$1" merge -q --no-edit main > /dev/null 2>&1
  sed 's/^12$/twelve/' "$1/n221.txt" > "$1/t" && mv "$1/t" "$1/n221.txt"; git -C "$1" commit -qam "c2: twelve"
  git -C "$1" checkout -q main
  sed 's/^five$/FIVE/' "$1/n221.txt" > "$1/t" && mv "$1/t" "$1/n221.txt"; git -C "$1" commit -qam "follow-up: FIVE"
}
R="$(mk_repo)"; mk221 "$R"; git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" commit -qm "PR2"
assert_exit "fixture-221a PR1, Update branch, main edits PR1's line, PR2 -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"
R="$(mk_repo)"; mk221 "$R"
OUT221=$(out_of "$R" feat main); RC221=$?
assert_exit "fixture-221b the same with no PR2 -> flagged" 3 "$RC221"
assert_exit "fixture-221b lists c2 only" 0 "$({ has "$OUT221" 'c2: twelve'; has "$OUT221" 'c1: five'; } | tr -d '\n' | grep -qx 01; echo $?)"
rm -rf "$R"
R="$(mk_repo)"; mk221 "$R"; git -C "$R" checkout -q feat
sed 's/^15$/fifteen/' "$R/n221.txt" > "$R/t" && mv "$R/t" "$R/n221.txt"; git -C "$R" commit -qam "c3: fifteen (never landed)"
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat~1 > /dev/null 2>&1; git -C "$R" commit -qm "PR2 without c3"
OUT221=$(out_of "$R" feat main); RC221=$?
assert_exit "fixture-221c PR2 drops c3 -> flagged" 3 "$RC221"
assert_exit "fixture-221c lists c3 only" 0 "$({ has "$OUT221" 'c3: fifteen'; has "$OUT221" 'c1: five'; has "$OUT221" 'c2: twelve'; } | tr -d '\n' | grep -qx 011; echo $?)"
rm -rf "$R"

# 222: main moves the file the branch edits, then squashes the branch (git follows the
# move): the branch's path is not in the landing commit. Not judged; the reason names the
# commit and no file name (file names are repository text).
R="$(mk_repo)"; seq 1 20 > "$R/m222.txt"; git -C "$R" add -A && git -C "$R" commit -qm m222
git -C "$R" checkout -q -b feat; sed 's/^5$/five/' "$R/m222.txt" > "$R/t" && mv "$R/t" "$R/m222.txt"; git -C "$R" commit -qam "c1: five"
git -C "$R" checkout -q main; git -C "$R" mv m222.txt moved222.txt; git -C "$R" commit -qm "main moves m222"
git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" commit -qm "squash"
E222="$("${BASH:-bash}" "$HELPER" --repo "$R" --branch feat --baseline main 2>&1 >/dev/null; echo "rc=$?")"
assert_exit "fixture-222 main moved the branch's file before the squash -> exit 4" 0 \
  "$(printf '%s\n' "$E222" | grep -q '^rc=4$' && printf '%s\n' "$E222" | grep -q 'moved or renamed (in [0-9a-f]*)' \
     && ! printf '%s\n' "$E222" | grep -q 'm222'; echo $?)"
rm -rf "$R"

# 223: the branch renames a file and edits it. Squashed exactly: the tip has the head's
# content at every name involved -> 0 (P0). Then main edits the line: not judged -> exit 4.
R="$(mk_repo)"; seq 1 20 > "$R/r223.txt"; git -C "$R" add -A && git -C "$R" commit -qm r223
git -C "$R" checkout -q -b feat; git -C "$R" mv r223.txt s223.txt; git -C "$R" commit -qm "c1: rename"
sed 's/^5$/five/' "$R/s223.txt" > "$R/t" && mv "$R/t" "$R/s223.txt"; git -C "$R" commit -qam "c2: five"
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" commit -qm "squash"
assert_exit "fixture-223a branch renames and edits, squash -> NOT flagged (P0)" 0 "$(run_helper "$R" feat main)"
sed 's/^five$/FIVE/' "$R/s223.txt" > "$R/t" && mv "$R/t" "$R/s223.txt"; git -C "$R" commit -qam "follow-up"
assert_exit "fixture-223b ... then main edits the renamed file -> exit 4" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 224: a move only on main, after the landing commit, with every candidate checked there
# (two commits, so git cherry matches neither to the squash):
# what main did after landing is out of scope (decision A) -> judged. A squash and a later
# move with an edit -> 0; a dropped commit, checked at the tip -> exit 4 (the tip reads the
# moved names).
R="$(mk_repo)"; seq 1 20 > "$R/a224.txt"; git -C "$R" add -A && git -C "$R" commit -qm a224
git -C "$R" checkout -q -b feat; sed 's/^5$/five/' "$R/a224.txt" > "$R/t" && mv "$R/t" "$R/a224.txt"; git -C "$R" commit -qam "c1: five"
sed 's/^7$/seven/' "$R/a224.txt" > "$R/t" && mv "$R/t" "$R/a224.txt"; git -C "$R" commit -qam "c1b: seven"
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" commit -qm "squash"
mkdir "$R/archive"; git -C "$R" mv a224.txt archive/a224.txt
sed 's/^five$/FIVE/' "$R/archive/a224.txt" > "$R/t" && mv "$R/t" "$R/archive/a224.txt"; git -C "$R" commit -qam "archive"
assert_exit "fixture-224a squash, then main moves the file and edits it -> NOT flagged" 0 "$(run_helper "$R" feat main)"
git -C "$R" checkout -q feat; sed 's/^9$/nine/' "$R/a224.txt" > "$R/t" && mv "$R/t" "$R/a224.txt"; git -C "$R" commit -qam "c2: nine (never landed)"
assert_exit "fixture-224b ... and a later commit that never landed (checked at the tip) -> exit 4" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 225: main renames a file no commit of the branch touched: no move counts -> judged as
# before (a squash with a follow-up -> 0; a dropped commit -> 3).
R="$(mk_repo)"; seq 1 20 > "$R/u225.txt"; echo other > "$R/o225.txt"; git -C "$R" add -A && git -C "$R" commit -qm u225
git -C "$R" checkout -q -b feat; sed 's/^5$/five/' "$R/u225.txt" > "$R/t" && mv "$R/t" "$R/u225.txt"; git -C "$R" commit -qam "c1: five"
sed 's/^9$/nine/' "$R/u225.txt" > "$R/t" && mv "$R/t" "$R/u225.txt"; git -C "$R" commit -qam "c2: nine"
git -C "$R" checkout -q main; git -C "$R" mv o225.txt p225.txt; git -C "$R" commit -qm "main renames o225"
git -C "$R" merge -q --squash feat~1 > /dev/null 2>&1; git -C "$R" commit -qm "squash c1"
OUT225=$(out_of "$R" feat main); RC225=$?
assert_exit "fixture-225 main renames an unrelated file; c2 dropped -> flagged" 3 "$RC225"
assert_exit "fixture-225 lists c2 only" 0 "$({ has "$OUT225" 'c2: nine'; has "$OUT225" 'c1: five'; } | tr -d '\n' | grep -qx 01; echo $?)"
rm -rf "$R"

# 226: #399 verify round 19's CRITICAL. b1 adds gen226.txt, b2 appends a line; main takes b1
# alone and moves the file; the branch merges main. Rounds 18 and 19 read b2 as landed
# (exit 0); with the move it is not judged.
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
seq 1 5 > "$R/gen226.txt"; git -C "$R" add -A && git -C "$R" commit -qm "b1: gen226"
echo "b2 line" >> "$R/gen226.txt"; git -C "$R" commit -qam "b2: b2 line"
git -C "$R" checkout -q main; git -C "$R" cherry-pick feat~1 > /dev/null 2>&1
mkdir "$R/lib"; git -C "$R" mv gen226.txt lib/gen226.txt; git -C "$R" commit -qm "main moves gen226"
git -C "$R" checkout -q feat; git -C "$R" merge -q --no-edit main > /dev/null 2>&1; git -C "$R" checkout -q main
assert_exit "fixture-226 b2 before the merge of main, which moved the file -> exit 4 (not 0)" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 227: the branch moves a file and back, then edits it; main squashes the branch (the squash
# records no move) and edits the line. A move in a commit of the branch counts even when
# main's history has none -> exit 4.
R="$(mk_repo)"; seq 1 20 > "$R/a227.txt"; git -C "$R" add -A && git -C "$R" commit -qm a227
git -C "$R" checkout -q -b feat; git -C "$R" mv a227.txt b227.txt && git -C "$R" commit -qm "c1: move"
git -C "$R" mv b227.txt a227.txt && git -C "$R" commit -qm "c2: move back"
sed 's/^5$/five/' "$R/a227.txt" > "$R/t" && mv "$R/t" "$R/a227.txt"; git -C "$R" commit -qam "c3: five"
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" commit -qm "squash"
sed 's/^five$/FIVE/' "$R/a227.txt" > "$R/t" && mv "$R/t" "$R/a227.txt"; git -C "$R" commit -qam "follow-up"
assert_exit "fixture-227 a move and back on the branch, squash, follow-up -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 228: two merges of main: c1, PR1, the branch merges main, c2, main's unrelated u228, the
# branch merges main again, c3, main edits c1's line, PR2. The whole branch and the part up
# to the second merge both land at PR2; c1 is checked again where the part up to the first
# merge landed (PR1): the oldest merge first.
R="$(mk_repo)"; seq 1 20 > "$R/n228.txt"; git -C "$R" add -A && git -C "$R" commit -qm n228
git -C "$R" checkout -q -b feat
sed 's/^5$/five/' "$R/n228.txt" > "$R/t" && mv "$R/t" "$R/n228.txt"; git -C "$R" commit -qam "c1: five"
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" commit -qm "PR1"
git -C "$R" checkout -q feat; git -C "$R" merge -q --no-edit main > /dev/null 2>&1
sed 's/^12$/twelve/' "$R/n228.txt" > "$R/t" && mv "$R/t" "$R/n228.txt"; git -C "$R" commit -qam "c2: twelve"
git -C "$R" checkout -q main; printf 'u\n' > "$R/u228.txt"; git -C "$R" add -A && git -C "$R" commit -qm "u228"
git -C "$R" checkout -q feat; git -C "$R" merge -q --no-edit main > /dev/null 2>&1
sed 's/^15$/fifteen/' "$R/n228.txt" > "$R/t" && mv "$R/t" "$R/n228.txt"; git -C "$R" commit -qam "c3: fifteen"
git -C "$R" checkout -q main
sed 's/^five$/FIVE/' "$R/n228.txt" > "$R/t" && mv "$R/t" "$R/n228.txt"; git -C "$R" commit -qam "follow-up: FIVE"
git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" commit -qm "PR2"
assert_exit "fixture-228 two merges of main, main edits c1's line, PR2 -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 229: fixture 221a where c1 also adds an empty file, which main deletes before PR2: at PR2
# the file is gone, at PR1 it is there (each landing commit's listing is its own).
R="$(mk_repo)"; seq 1 20 > "$R/n229.txt"; git -C "$R" add -A && git -C "$R" commit -qm n229
git -C "$R" checkout -q -b feat
sed 's/^5$/five/' "$R/n229.txt" > "$R/t" && mv "$R/t" "$R/n229.txt"; : > "$R/e229.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1: five, e229"
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" commit -qm "PR1"
git -C "$R" checkout -q feat; git -C "$R" merge -q --no-edit main > /dev/null 2>&1
sed 's/^12$/twelve/' "$R/n229.txt" > "$R/t" && mv "$R/t" "$R/n229.txt"; git -C "$R" commit -qam "c2: twelve"
git -C "$R" checkout -q main; git -C "$R" rm -q e229.txt; git -C "$R" commit -qm "main drops e229"
git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" commit -qm "PR2"
assert_exit "fixture-229 PR1 adds an empty file main drops before PR2 -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Round 21: the shapes round 20's verify found ──

# (Since 2026-11-02 read by path, whatever "exit 4" below says: rounds 21-22's rule is gone.)
# 230: found by round 20's verify (devil's advocate). c1 deletes `def f7`; in one commit main
# moves the file to lib/ and puts a shim at its old name (git reports an edit of the old name
# and an addition, unless it breaks the rewrite); nothing of the branch landed, and main's
# lib/ file still has the line. Rounds 19 and 20 read the deletion as landed (exit 0). With
# rename detection on rewrites (-B) the move counts -> exit 4.
mk230() { # repo -> base a230.txt with def f1..f20, feat c1 deletes def f7
  local i; for i in $(seq 1 20); do printf 'def f%d():\n    return %d\n' "$i" "$i"; done > "$1/a230.txt"
  git -C "$1" add -A && git -C "$1" commit -qm a230
  git -C "$1" checkout -q -b feat
  grep -v '^def f7():$' "$1/a230.txt" > "$1/t" && mv "$1/t" "$1/a230.txt"; git -C "$1" commit -qam "c1: drop def f7 (never landed)"
  git -C "$1" checkout -q main
}
R="$(mk_repo)"; mk230 "$R"; mkdir "$R/lib"; git -C "$R" mv a230.txt lib/a230.txt
printf 'from lib.a230 import *\n' > "$R/a230.txt"; git -C "$R" add -A && git -C "$R" commit -qm "main: move to lib/, shim at the old name"
assert_exit "fixture-230 known limit: main moves the file and leaves a shim -> read by path, clean" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"
# 230b: the same deletion; main moves the file onto a name that exists (git mv -f)
R="$(mk_repo)"; printf 'other\n' > "$R/b230.txt"; git -C "$R" add -A && git -C "$R" commit -qm b230; mk230 "$R"
git -C "$R" mv -f a230.txt b230.txt && git -C "$R" commit -qm "main: move onto b230.txt"
assert_exit "fixture-230b known limit: main moves the file onto a name that exists -> read by path, clean" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# (Since 2026-11-02 read by path, whatever "exit 4" below says: rounds 21-22's rule is gone.)
# 231: found by round 20's verify (devil's advocate). c1 adds d231/new.txt and c2 edits it;
# main renames the directory d231/ to e231/ and squashes the branch. The squash stops on
# git's file-location conflict (merge.directoryRenames defaults to "conflict"; round 21's
# verify, devil's advocate), and accepting git's suggestion puts the new file at
# e231/new.txt. Read by path the new file never landed (rounds 19 and 20: exit 3). Main's
# move took away a directory (nothing is left in d231/) where the branch added a file -> exit 4.
R="$(mk_repo)"; mkdir "$R/d231"; printf 'old\n' > "$R/d231/old.txt"; git -C "$R" add -A && git -C "$R" commit -qm d231
git -C "$R" checkout -q -b feat
printf 'n1\n' > "$R/d231/new.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1: d231/new.txt"
printf 'n1\nn2\n' > "$R/d231/new.txt"; git -C "$R" commit -qam "c2: n2"
git -C "$R" checkout -q main; git -C "$R" mv d231 e231 && git -C "$R" commit -qm "main: d231 -> e231"
M231="$(LC_ALL=C git -C "$R" merge --squash feat 2>&1)"; RC231=$?
assert_exit "fixture-231 the squash stops on git's file-location conflict" 0 \
  "$([ "$RC231" -ne 0 ] && printf '%s\n' "$M231" | grep -q 'CONFLICT (file location)'; echo $?)"
git -C "$R" add -A > /dev/null 2>&1; git -C "$R" commit -qm "squash" > /dev/null 2>&1
assert_exit "fixture-231 accepting git's suggestion put the new file in the renamed directory" 0 "$([ -f "$R/e231/new.txt" ]; echo $?)"
assert_exit "fixture-231 known limit: main renamed the directory the branch added a file to -> listed by path" 3 "$(rc_why "$R" feat main)"
rm -rf "$R"

# 232: found by round 20's verify (logic, regression). The usual GitHub order: PR1 squashes
# c1, the author pushes c1b, then presses Update branch; c2; main edits c1's line; PR2
# squashes the branch. The part up to the merge (c1 and c1b) landed nowhere as a whole, so
# round 20 listed c1 again. c1 itself is in place in PR1 -> NOT flagged.
R="$(mk_repo)"; seq 1 20 > "$R/n232.txt"; git -C "$R" add -A && git -C "$R" commit -qm n232
git -C "$R" checkout -q -b feat
sed 's/^5$/five/' "$R/n232.txt" > "$R/t" && mv "$R/t" "$R/n232.txt"; git -C "$R" commit -qam "c1: five"
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" commit -qm "PR1"
git -C "$R" checkout -q feat
sed 's/^9$/nine/' "$R/n232.txt" > "$R/t" && mv "$R/t" "$R/n232.txt"; git -C "$R" commit -qam "c1b: nine"
git -C "$R" merge -q --no-edit main > /dev/null 2>&1
sed 's/^12$/twelve/' "$R/n232.txt" > "$R/t" && mv "$R/t" "$R/n232.txt"; git -C "$R" commit -qam "c2: twelve"
git -C "$R" checkout -q main
sed 's/^five$/FIVE/' "$R/n232.txt" > "$R/t" && mv "$R/t" "$R/n232.txt"; git -C "$R" commit -qam "follow-up: FIVE"
git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" commit -qm "PR2"
assert_exit "fixture-232 a commit pushed after PR1 and before Update branch, main's edit, PR2 -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 233: found by round 20's verify (devil's advocate). PR1 squashes c1a and c1b but leaves one
# of c1b's lines out; the branch merges main, main edits c1a's line, PR2 squashes the rest.
# The part up to the merge landed nowhere as a whole; c1a itself is in place in PR1 -> NOT
# flagged.
R="$(mk_repo)"; seq 1 20 > "$R/n233.txt"; git -C "$R" add -A && git -C "$R" commit -qm n233
git -C "$R" checkout -q -b feat
sed 's/^3$/three/' "$R/n233.txt" > "$R/t" && mv "$R/t" "$R/n233.txt"; git -C "$R" commit -qam "c1a: three"
sed -e 's/^7$/seven/' -e 's/^9$/nine/' "$R/n233.txt" > "$R/t" && mv "$R/t" "$R/n233.txt"; git -C "$R" commit -qam "c1b: seven, nine"
git -C "$R" checkout -q main; sed -e 's/^3$/three/' -e 's/^7$/seven/' "$R/n233.txt" > "$R/t" && mv "$R/t" "$R/n233.txt"
git -C "$R" commit -qam "PR1 (left nine out)"
git -C "$R" checkout -q feat; git -C "$R" merge -q --no-edit main > /dev/null 2>&1
sed 's/^12$/twelve/' "$R/n233.txt" > "$R/t" && mv "$R/t" "$R/n233.txt"; git -C "$R" commit -qam "c2: twelve"
git -C "$R" checkout -q main
sed 's/^three$/THREE/' "$R/n233.txt" > "$R/t" && mv "$R/t" "$R/n233.txt"; git -C "$R" commit -qam "follow-up: THREE"
git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" commit -qm "PR2"
assert_exit "fixture-233 PR1 left a line of c1b out, Update branch, main's edit of c1a's line, PR2 -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 234: found by round 20's verify (requirements). The Moves rule's second clause: a move of
# main's own at or before the landing commit. c1 and c2 edit f234.txt; main moves it away and
# back, then squashes the branch, then edits c1's line. The landing commit holds the net
# change by path, but main moved the file before it -> exit 4 (without the clause, 0).
R="$(mk_repo)"; seq 1 20 > "$R/f234.txt"; git -C "$R" add -A && git -C "$R" commit -qm f234
git -C "$R" checkout -q -b feat
sed 's/^5$/five/' "$R/f234.txt" > "$R/t" && mv "$R/t" "$R/f234.txt"; git -C "$R" commit -qam "c1: five"
sed 's/^9$/nine/' "$R/f234.txt" > "$R/t" && mv "$R/t" "$R/f234.txt"; git -C "$R" commit -qam "c2: nine"
git -C "$R" checkout -q main; git -C "$R" mv f234.txt g234.txt && git -C "$R" commit -qm "main: move away"
git -C "$R" mv g234.txt f234.txt && git -C "$R" commit -qm "main: move back"
git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" commit -qm "squash"
sed 's/^five$/FIVE/' "$R/f234.txt" > "$R/t" && mv "$R/t" "$R/f234.txt"; git -C "$R" commit -qam "follow-up"
assert_exit "fixture-234 main moved the file away and back before the squash -> exit 4 (a move)" 4 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 235: the second check goes on past a merged main commit that lacks the commit. c1 edits
# line 5; PR1 leaves it out (takes c0 only); the branch merges main; main then takes c1's
# line in a hotfix of its own; the branch merges main again; main edits c1's line; PR2.
# c1 is not in place at the first merged commit, and is at the second -> NOT flagged.
R="$(mk_repo)"; seq 1 20 > "$R/n235.txt"; git -C "$R" add -A && git -C "$R" commit -qm n235
git -C "$R" checkout -q -b feat
sed 's/^3$/three/' "$R/n235.txt" > "$R/t" && mv "$R/t" "$R/n235.txt"; git -C "$R" commit -qam "c0: three"
sed 's/^5$/five/' "$R/n235.txt" > "$R/t" && mv "$R/t" "$R/n235.txt"; git -C "$R" commit -qam "c1: five"
git -C "$R" checkout -q main; sed 's/^3$/three/' "$R/n235.txt" > "$R/t" && mv "$R/t" "$R/n235.txt"; git -C "$R" commit -qam "PR1 (c0 only)"
git -C "$R" checkout -q feat; git -C "$R" merge -q --no-edit main > /dev/null 2>&1
sed 's/^9$/nine/' "$R/n235.txt" > "$R/t" && mv "$R/t" "$R/n235.txt"; git -C "$R" commit -qam "c2: nine"
git -C "$R" checkout -q main; sed 's/^5$/five/' "$R/n235.txt" > "$R/t" && mv "$R/t" "$R/n235.txt"; git -C "$R" commit -qam "hotfix: five"
git -C "$R" checkout -q feat; git -C "$R" merge -q --no-edit main > /dev/null 2>&1
sed 's/^12$/twelve/' "$R/n235.txt" > "$R/t" && mv "$R/t" "$R/n235.txt"; git -C "$R" commit -qam "c3: twelve"
git -C "$R" checkout -q main; sed 's/^five$/FIVE/' "$R/n235.txt" > "$R/t" && mv "$R/t" "$R/n235.txt"; git -C "$R" commit -qam "follow-up: FIVE"
git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" commit -qm "PR2"
assert_exit "fixture-235 c1 in place only at the second merged main commit -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 236: a move inside one directory does not carry a file the branch added there along: main
# renames d236/old.txt to d236/old2.txt, the branch adds d236/new.txt and edits it twice;
# squash; follow-up. No move counts -> judged (0).
R="$(mk_repo)"; mkdir "$R/d236"; printf 'old\n' > "$R/d236/old.txt"; git -C "$R" add -A && git -C "$R" commit -qm d236
git -C "$R" checkout -q -b feat
printf 'n1\n' > "$R/d236/new.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1: d236/new.txt"
printf 'n1\nn2\n' > "$R/d236/new.txt"; git -C "$R" commit -qam "c2: n2"
git -C "$R" checkout -q main; git -C "$R" mv d236/old.txt d236/old2.txt && git -C "$R" commit -qm "main: old -> old2"
git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" commit -qm "squash"
printf 'n1\nn2 follow-up\n' > "$R/d236/new.txt"; git -C "$R" commit -qam "follow-up"
assert_exit "fixture-236 main renames a file inside the directory the branch added to -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# (Since 2026-11-02 read by path, whatever "exit 4" below says: rounds 21-22's rule is gone.)
# 237: a move counts by its new name too: c1 deletes a237.txt (never landed); main moves
# x237.txt onto a237.txt (git mv -f). Read by path the deletion never landed (exit 3); the
# move's new name is a path the branch touched -> exit 4.
# (files over 400 bytes: git does not break a rewrite of a smaller file, so a move onto a small
# file's name is not seen, SPEC "Moves")
R="$(mk_repo)"; for i in $(seq 1 20); do printf 'def a%d():\n    return %d\n' "$i" "$i"; done > "$R/a237.txt"
for i in $(seq 1 20); do printf 'def x%d():\n    return %d\n' "$i" "$((i + 100))"; done > "$R/x237.txt"; git -C "$R" add -A && git -C "$R" commit -qm a237
git -C "$R" checkout -q -b feat; git -C "$R" rm -q a237.txt && git -C "$R" commit -qm "c1: drop a237 (never landed)"
git -C "$R" checkout -q main; git -C "$R" mv -f x237.txt a237.txt && git -C "$R" commit -qm "main: x237 onto a237"
assert_exit "fixture-237 known limit: another file moved onto a path the branch deleted -> the deletion listed" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Round 22: the shapes round 21's verify found ──

# (Since 2026-11-02 read by path, whatever "exit 4" below says: rounds 21-22's rule is gone.)
# 239: found by round 21's verify (requirements). Fixture 230 with a file under 400 bytes
# (git's -B never breaks so small a rewrite): main moves a239.py to lib239/ and puts a
# one-line shim at its old name. Copy detection pairs the moved file with the file its
# commit changed -> exit 4 (round 21: 0). (b): the moved file is edited in the same commit.
mk239() { # repo -> a239.py with 8 small defs; feat c1 deletes def f7; back on main
  local i; for i in $(seq 1 8); do printf 'def f%d():\n    return %d\n' "$i" "$i"; done > "$1/a239.py"
  git -C "$1" add -A && git -C "$1" commit -qm a239
  git -C "$1" checkout -q -b feat
  grep -vx 'def f7():' "$1/a239.py" > "$1/t" && mv "$1/t" "$1/a239.py"; git -C "$1" commit -qam "c1: drop def f7 (never landed)"
  git -C "$1" checkout -q main; mkdir "$1/lib239"; git -C "$1" mv a239.py lib239/a239.py
  printf 'from lib239.a239 import *\n' > "$1/a239.py"
}
R="$(mk_repo)"; mk239 "$R"; git -C "$R" add -A && git -C "$R" commit -qm "main: move a239 to lib239/, shim at the old name"
assert_exit "fixture-239a known limit: a small file moved, a shim at its old name -> clean" 0 "$(rc_why "$R" feat main)"
rm -rf "$R"
R="$(mk_repo)"; mk239 "$R"; sed 's/return 1$/return 100/' "$R/lib239/a239.py" > "$R/t" && mv "$R/t" "$R/lib239/a239.py"
git -C "$R" add -A && git -C "$R" commit -qm "main: move a239 (edited) to lib239/, shim at the old name"
assert_exit "fixture-239b known limit: the same, the moved file edited -> clean" 0 "$(rc_why "$R" feat main)"
rm -rf "$R"

# (Since 2026-11-02 read by path, whatever "exit 4" below says: rounds 21-22's rule is gone.)
# 240: found by round 21's verify (logic). A small file moved onto a name that exists (git mv
# -f): the commit deletes a240.txt and turns b240.txt into exactly its content. git pairs
# neither, in any mode; the check pairs them by content -> exit 4 (round 21: 0).
R="$(mk_repo)"; seq 1 10 > "$R/a240.txt"; printf 'other\n' > "$R/b240.txt"; git -C "$R" add -A && git -C "$R" commit -qm a240
git -C "$R" checkout -q -b feat; grep -vx 7 "$R/a240.txt" > "$R/t" && mv "$R/t" "$R/a240.txt"; git -C "$R" commit -qam "c1: drop 7 (never landed)"
git -C "$R" checkout -q main; git -C "$R" mv -f a240.txt b240.txt && git -C "$R" commit -qm "main: a240 onto b240"
assert_exit "fixture-240 known limit: a small file moved onto a name that exists -> clean" 0 "$(rc_why "$R" feat main)"
rm -rf "$R"

# 241: found by round 21's verify (logic, requirements, regression). The branch adds a file
# to docs241/; main moves another file from docs241/ to docs241/archive/, and docs241/ stays:
# merge-ort carries nothing, and no move counts. (a) A full squash -> 0. (b) The PR takes c1
# only; c2 edits app241.txt and never lands -> c2 listed. (Round 21: exit 4 for both.)
mk241() { # repo
  mkdir "$1/docs241"; printf 'guide\n' > "$1/docs241/guide.md"; printf 'old\n' > "$1/docs241/old.md"; printf 'app\n' > "$1/app241.txt"
  git -C "$1" add -A && git -C "$1" commit -qm d241
  git -C "$1" checkout -q -b feat; printf 'n1\n' > "$1/docs241/new.md"; git -C "$1" add -A && git -C "$1" commit -qm "c1: docs241/new.md"
}
mvdoc241() { # repo
  git -C "$1" checkout -q main; mkdir "$1/docs241/archive"; git -C "$1" mv docs241/old.md docs241/archive/old.md
  git -C "$1" commit -qm "main: archive old.md"
}
R="$(mk_repo)"; mk241 "$R"; printf 'n1\nn2\n' > "$R/docs241/new.md"; git -C "$R" commit -qam "c2: n2"; mvdoc241 "$R"
git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" commit -qm "squash"
assert_exit "fixture-241a main moved a sibling within a directory that stays, full squash -> NOT flagged" 0 "$(rc_why "$R" feat main)"
rm -rf "$R"
R="$(mk_repo)"; mk241 "$R"; printf 'app 2\n' > "$R/app241.txt"; git -C "$R" commit -qam "c2: app 2"; mvdoc241 "$R"
git -C "$R" checkout -q feat~1 -- docs241/new.md && git -C "$R" commit -qm "PR: c1 only"
OUT241=$(out_of "$R" feat main); RC241=$?
assert_exit "fixture-241b the same, the PR took c1 only -> flagged" 3 "$RC241"
assert_exit "fixture-241b lists c2" 0 "$(has "$OUT241" 'c2: app 2')"
assert_exit "fixture-241b does not list c1" 1 "$(has "$OUT241" 'c1: docs241/new.md')"
rm -rf "$R"

# (Since 2026-11-02 read by path, whatever "exit 4" below says: rounds 21-22's rule is gone.)
# 242: found by round 21's verify (requirements, logic, Codex). The renamed directory holds
# only a subdirectory: `git mv d242 e242` moves d242/a/x.txt to e242/a/x.txt, and the branch
# added d242/new.txt. merge-ort derives d242 -> e242 as well (the paths end alike) and, its
# conflict accepted, puts the new file at e242/new.txt -> exit 4 (rounds 20 and 21: 3).
R="$(mk_repo)"; mkdir -p "$R/d242/a"; printf 'x\n' > "$R/d242/a/x.txt"; git -C "$R" add -A && git -C "$R" commit -qm d242
git -C "$R" checkout -q -b feat; printf 'n1\n' > "$R/d242/new.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1: d242/new.txt"
printf 'n1\nn2\n' > "$R/d242/new.txt"; git -C "$R" commit -qam "c2: n2"
git -C "$R" checkout -q main; git -C "$R" mv d242 e242 && git -C "$R" commit -qm "main: d242 -> e242"
LC_ALL=C git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" add -A > /dev/null 2>&1; git -C "$R" commit -qm "squash" > /dev/null 2>&1
assert_exit "fixture-242 the squash put the new file in the renamed directory" 0 "$([ -f "$R/e242/new.txt" ]; echo $?)"
assert_exit "fixture-242 known limit: main renamed the parent directory -> listed by path" 3 "$(rc_why "$R" feat main)"
rm -rf "$R"

# 243, 244: found by round 21's verify (logic). Update branch after main renamed a directory
# the branch added a file to: the branch merges main and accepts git's suggestion, so the
# merge moves the file; c3 edits app.txt; main takes only c3's line. The new file never
# landed. Rename detection inside the merge sees the branch's file move -> exit 4 (rounds 20
# and 21: 0, through the shortcut, which compared the old name only). 243: the directory
# holds only subdirectories; 244: it holds a file.
upd243() { # repo old-dir new-dir file -> the branch's merge of main, c3, main's app-only commit
  git -C "$1" checkout -q main; git -C "$1" mv "$2" "$3" && git -C "$1" commit -qm "main: $2 -> $3"
  git -C "$1" checkout -q feat; LC_ALL=C git -C "$1" merge -q --no-edit main > /dev/null 2>&1
  git -C "$1" add -A > /dev/null 2>&1; git -C "$1" commit -q --no-edit > /dev/null 2>&1
  printf 'app 2\n' > "$1/app.txt"; git -C "$1" commit -qam "c3: app 2"
  git -C "$1" checkout -q main; printf 'app 2\n' > "$1/app.txt"; git -C "$1" commit -qam "main: app 2 only"
}
R="$(mk_repo)"; mkdir -p "$R/p243/foo/scripts" "$R/p243/foo/skills"; printf 'a\n' > "$R/p243/foo/scripts/a.sh"
printf 's\n' > "$R/p243/foo/skills/s.md"; printf 'app\n' > "$R/app.txt"; git -C "$R" add -A && git -C "$R" commit -qm p243
git -C "$R" checkout -q -b feat; printf 'r1\n' > "$R/p243/foo/README.md"; git -C "$R" add -A && git -C "$R" commit -qm "c1: README"
printf 'r1\nr2\n' > "$R/p243/foo/README.md"; git -C "$R" commit -qam "c2: r2"
upd243 "$R" p243/foo p243/bar README.md
assert_exit "fixture-243 the branch's merge moved its README" 0 "$(git -C "$R" cat-file -e feat:p243/bar/README.md 2>/dev/null; echo $?)"
assert_exit "fixture-243 a merge of main moved the branch's file, the file never landed -> exit 4 (a move)" "4 moved" "$(rc_why "$R" feat main)"
rm -rf "$R"
R="$(mk_repo)"; mkdir "$R/d244"; printf 'old\n' > "$R/d244/old.txt"; printf 'app\n' > "$R/app.txt"; git -C "$R" add -A && git -C "$R" commit -qm d244
git -C "$R" checkout -q -b feat; printf 'n1\n' > "$R/d244/new.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1: new"
printf 'n1\nn2\n' > "$R/d244/new.txt"; git -C "$R" commit -qam "c2: n2"
upd243 "$R" d244 e244 new.txt
assert_exit "fixture-244 the branch's merge moved its new file" 0 "$(git -C "$R" cat-file -e feat:e244/new.txt 2>/dev/null; echo $?)"
assert_exit "fixture-244 the same with a directory that holds a file -> exit 4 (a move)" "4 moved" "$(rc_why "$R" feat main)"
rm -rf "$R"

# 245: found by round 21's verify (logic). c1 changes 5 and 9; PR1 squashes c1; main edits
# c1's nine to NINE; the branch merges main and keeps nine (the conflict resolved to the
# branch); c2; main edits five to FIVE; PR2 squashes the branch. c1 landed in full in PR1:
# in place where the branch up to the merge landed -> NOT flagged (round 21: listed, since
# at the main commit the merge brought in, nine is NINE).
R="$(mk_repo)"; seq 1 20 > "$R/n245.txt"; git -C "$R" add -A && git -C "$R" commit -qm n245
git -C "$R" checkout -q -b feat; sed -e 's/^5$/five/' -e 's/^9$/nine/' "$R/n245.txt" > "$R/t" && mv "$R/t" "$R/n245.txt"; git -C "$R" commit -qam "c1: five, nine"
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" commit -qm "PR1"
sed 's/^nine$/NINE/' "$R/n245.txt" > "$R/t" && mv "$R/t" "$R/n245.txt"; git -C "$R" commit -qam "main: NINE"
git -C "$R" checkout -q feat; git -C "$R" merge -q --no-edit main > /dev/null 2>&1
git -C "$R" checkout -q --ours n245.txt && git -C "$R" add n245.txt && git -C "$R" commit -q --no-edit > /dev/null 2>&1
assert_exit "fixture-245 the merge kept the branch's nine" 0 "$(grep -qx nine "$R/n245.txt"; echo $?)"
sed 's/^12$/twelve/' "$R/n245.txt" > "$R/t" && mv "$R/t" "$R/n245.txt"; git -C "$R" commit -qam "c2: twelve"
git -C "$R" checkout -q main; sed 's/^five$/FIVE/' "$R/n245.txt" > "$R/t" && mv "$R/t" "$R/n245.txt"; git -C "$R" commit -qam "main: FIVE"
git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" commit -qm "PR2"
assert_exit "fixture-245 main edited c1's line before Update branch, the merge kept the branch's side -> NOT flagged" 0 "$(rc_why "$R" feat main)"
rm -rf "$R"

# (Since 2026-11-02 read by path, whatever "exit 4" below says: rounds 21-22's rule is gone.)
# 247: the branch splits a file: c1 copies u247.py to h247.py and turns u247.py into a shim;
# c2 edits h247.py; a full squash, then main edits h247.py. Copy detection pairs the copy
# with the file its commit changed: a file the branch touched was copied -> exit 4 (the
# maintainer's decision of 2026-11-01 does not judge copies; reading by path, round 20, gave
# 0, and the squash did land the split).
R="$(mk_repo)"; for i in $(seq 1 12); do printf 'def u%d():\n    return %d\n' "$i" "$i"; done > "$R/u247.py"; git -C "$R" add -A && git -C "$R" commit -qm u247
git -C "$R" checkout -q -b feat; cp "$R/u247.py" "$R/h247.py"; printf 'from h247 import *\n' > "$R/u247.py"; git -C "$R" add -A && git -C "$R" commit -qm "c1: split"
sed 's/return 3$/return 30/' "$R/h247.py" > "$R/t" && mv "$R/t" "$R/h247.py"; git -C "$R" commit -qam "c2: 30"
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" commit -qm "squash"
sed 's/return 30$/return 300/' "$R/h247.py" > "$R/t" && mv "$R/t" "$R/h247.py"; git -C "$R" commit -qam "follow-up: 300"
assert_exit "fixture-247 the branch copied a file and turned the original into a shim, squashed -> NOT flagged" 0 "$(rc_why "$R" feat main)"
rm -rf "$R"

# 248: the branch's merge of main moves the branch's file (the author renamed it while resolving
# the merge; main moved nothing); the PR then lands whole as a squash, and main edits the moved
# file. The commits are checked at the landing commit, not at the tip; a move the branch's own
# merge made is the branch's -> exit 4 (taken as main's move, it was judged by path, and c1 and
# c2 were listed).
R="$(mk_repo)"; printf 'app\n' > "$R/app248.txt"; git -C "$R" add -A && git -C "$R" commit -qm a248
git -C "$R" checkout -q -b feat; printf 'n1\n' > "$R/f248.txt"; git -C "$R" add -A && git -C "$R" commit -qm "c1: f248"
printf 'n1\nn2\n' > "$R/f248.txt"; git -C "$R" commit -qam "c2: n2"
git -C "$R" checkout -q main; printf 'app 2\n' > "$R/app248.txt"; git -C "$R" commit -qam "main: app 2"
git -C "$R" checkout -q feat; git -C "$R" merge -q --no-commit --no-ff main > /dev/null 2>&1
git -C "$R" mv f248.txt g248.txt && git -C "$R" commit -q --no-edit > /dev/null 2>&1
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat > /dev/null 2>&1; git -C "$R" commit -qm "squash" > /dev/null 2>&1
printf 'n1\nn2\nfollow-up\n' > "$R/g248.txt"; git -C "$R" commit -qam "follow-up"
assert_exit "fixture-248 the merge on the branch moved the file" 0 "$(git -C "$R" cat-file -e feat:g248.txt 2>/dev/null && ! git -C "$R" cat-file -e feat:f248.txt 2>/dev/null; echo $?)"
assert_exit "fixture-248 the branch's merge moved its file, squash, follow-up -> exit 4 (a move)" "4 moved" "$(rc_why "$R" feat main)"
rm -rf "$R"

# 249: found by round 23's verify (devil's advocate). A commit that sets a line back to its
# merge-base value never lands; the branch merges main in between. (a) c0 adds DEBUG, c1 removes
# it; the squash has DEBUG. (b) c0 deletes a line, c1 restores it; the squash deletes it. The merged
# main commit never touched the line, so its state is no evidence -> c1 listed (round 22, 23: 0).
for v249 in a b; do
  R="$(mk_repo)"; seq 1 30 > "$R/n249.txt"; printf 'o\n' > "$R/o249.txt"; git -C "$R" add -A && git -C "$R" commit -qm n249
  git -C "$R" checkout -q -b feat; cp "$R/n249.txt" "$R/base249"
  if [ "$v249" = a ]; then sed 's/^10$/10\nDEBUG/' "$R/base249" > "$R/n249.txt"; else grep -vx 10 "$R/base249" > "$R/n249.txt"; fi
  cp "$R/n249.txt" "$R/mid249"; git -C "$R" add n249.txt; git -C "$R" commit -qm "c0"
  cp "$R/base249" "$R/n249.txt"; git -C "$R" add n249.txt; git -C "$R" commit -qm "c1: back"
  git -C "$R" checkout -q main; printf 'o2\n' > "$R/o249.txt"; git -C "$R" add o249.txt; git -C "$R" commit -qm "main: o"
  git -C "$R" checkout -q feat; git -C "$R" merge -q --no-edit main > /dev/null 2>&1
  sed 's/^25$/twentyfive/' "$R/n249.txt" > "$R/t" && mv "$R/t" "$R/n249.txt"; git -C "$R" add n249.txt; git -C "$R" commit -qm "c2"
  git -C "$R" checkout -q main; sed 's/^25$/twentyfive/' "$R/mid249" > "$R/n249.txt"; git -C "$R" add n249.txt; git -C "$R" commit -qm "squash without c1"
  OUT249=$(out_of "$R" feat main); RC249=$?
  assert_exit "fixture-249$v249 a commit back to the merge-base value never landed, a merge of main -> known limit S1, not listed" 0 "$RC249"
    rm -rf "$R"
done

# 250: found by round 23's verify (Codex). A path with a newline that differs between head and
# tip does not split into a name a candidate touched: P0 still holds -> 0.
R="$(mk_repo)"; seq 1 5 > "$R/f250.txt"; printf 'g\n' > "$R/g250.txt"; git -C "$R" add -A && git -C "$R" commit -qm f250
git -C "$R" checkout -q -b feat; printf 'x\n' >> "$R/f250.txt"; git -C "$R" commit -qam c1; printf 'g2\n' > "$R/g250.txt"; git -C "$R" commit -qam c2
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat > /dev/null 2>&1; printf 'n\n' > "$R/other
f250.txt"; git -C "$R" add -A; git -C "$R" commit -qm squash
assert_exit "fixture-250 an unrelated path with a newline ending in a candidate's name -> P0 still holds" 0 "$(rc_why "$R" feat main)"
rm -rf "$R"

# 251: found by round 24's verify. (a) Fixture 249a with a first PR of an unrelated commit: the
# branch up to the merge landed there, and DEBUG never arrived. (b) A commit mixing the removal
# of DEBUG with a real edit main also made by hotfix. c1 listed in both.
mk251() { R="$(mk_repo)"; seq 1 40 > "$R/n251.txt"; git -C "$R" add -A && git -C "$R" commit -qm n251; git -C "$R" checkout -q -b feat; }
ed251() { sed "$2" "$R/n251.txt" > "$R/t" && mv "$R/t" "$R/n251.txt"; git -C "$R" commit -qam "$1"; }
mk251; ed251 "c00" 's/^3$/three/'; ed251 "c0" 's/^10$/10\nDEBUG/'; ed251 "c1: back" '/^DEBUG$/d'
git -C "$R" checkout -q main; ed251 "PR1" 's/^3$/three/'
git -C "$R" checkout -q feat; git -C "$R" merge -q --no-edit main > /dev/null 2>&1; ed251 "c2" 's/^35$/thirtyfive/'
git -C "$R" checkout -q main; ed251 "PR2 without c1" 's/^10$/10\nDEBUG/;s/^35$/thirtyfive/'
assert_exit "fixture-251a set back after a first PR of another commit -> known limit S1" 0 "$(rc_why "$R" feat main)"; rm -rf "$R"
mk251; ed251 "c0" 's/^10$/10\nDEBUG/'; ed251 "c1: back" '/^DEBUG$/d;s/^30$/thirty/'; ed251 "c1b" 's/^20$/twenty/'
git -C "$R" checkout -q main; ed251 "hotfix" 's/^30$/thirty/'
git -C "$R" checkout -q feat; git -C "$R" merge -q --no-edit main > /dev/null 2>&1; ed251 "c2" 's/^35$/thirtyfive/'
git -C "$R" checkout -q main; ed251 "squash without c1" 's/^10$/10\nDEBUG/;s/^20$/twenty/;s/^35$/thirtyfive/'
assert_exit "fixture-251b a set-back hunk mixed with a real edit -> known limit S1" 0 "$(rc_why "$R" feat main)"; rm -rf "$R"

# 252: found by round 25's verify. (a) Fixture 249a in a non-ASCII file: still listed. (b) A first
# PR's commit that also adds a blank line, Update branch, main's edit, PR2 -> NOT flagged.
R="$(mk_repo)"; seq 1 30 > "$R/中252.txt"; git -C "$R" add -A && git -C "$R" commit -qm n
git -C "$R" checkout -q -b feat; sed 's/^10$/10\nDEBUG/' "$R/中252.txt" > "$R/t" && cp "$R/t" "$R/mid.tmp" && mv "$R/t" "$R/中252.txt"; git -C "$R" add 中252.txt; git -C "$R" commit -qm c0
sed '/^DEBUG$/d' "$R/中252.txt" > "$R/t" && mv "$R/t" "$R/中252.txt"; git -C "$R" add 中252.txt; git -C "$R" commit -qm "c1: back"
git -C "$R" checkout -q main; printf 'o\n' > "$R/o252"; git -C "$R" add o252; git -C "$R" commit -qm o
git -C "$R" checkout -q feat; git -C "$R" merge -q --no-edit main > /dev/null 2>&1; sed 's/^25$/x25/' "$R/中252.txt" > "$R/t" && mv "$R/t" "$R/中252.txt"; git -C "$R" add 中252.txt; git -C "$R" commit -qm c2
git -C "$R" checkout -q main; sed 's/^25$/x25/' "$R/mid.tmp" > "$R/中252.txt"; git -C "$R" add 中252.txt; git -C "$R" commit -qm "squash without c1"
assert_exit "fixture-252a a set-back commit in a non-ASCII file -> known limit S1" 0 "$(rc_why "$R" feat main)"; rm -rf "$R"
R="$(mk_repo)"; { seq 1 15; echo; seq 16 40; } > "$R/b252.txt"; git -C "$R" add -A && git -C "$R" commit -qm b
git -C "$R" checkout -q -b feat; sed -e 's/^3$/three/' -e 's/^30$/30\n/' "$R/b252.txt" > "$R/t" && mv "$R/t" "$R/b252.txt"; git -C "$R" commit -qam c1; sed 's/^20$/twenty/' "$R/b252.txt" > "$R/t" && mv "$R/t" "$R/b252.txt"; git -C "$R" commit -qam c1x
git -C "$R" checkout -q main; git -C "$R" merge -q --squash feat >/dev/null 2>&1; git -C "$R" commit -qm PR1
git -C "$R" checkout -q feat; git -C "$R" merge -q --no-edit main >/dev/null 2>&1; sed 's/^35$/x35/' "$R/b252.txt" > "$R/t" && mv "$R/t" "$R/b252.txt"; git -C "$R" commit -qam c2
git -C "$R" checkout -q main; sed 's/^three$/THREE/' "$R/b252.txt" > "$R/t" && mv "$R/t" "$R/b252.txt"; git -C "$R" commit -qam follow; git -C "$R" merge -q --squash feat >/dev/null 2>&1; git -C "$R" commit -qm PR2
assert_exit "fixture-252b a first PR's commit that also adds a blank line -> NOT flagged" 0 "$(rc_why "$R" feat main)"; rm -rf "$R"

print_summary
