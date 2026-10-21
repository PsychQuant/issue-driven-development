#!/usr/bin/env bash
# test.sh — fixtures for check-merge-completeness.sh (PsychQuant/issue-driven-development#184)
#
# The gate detects commits on an issue's branch whose CONTENT did not land in
# the baseline (origin/<default>). The hard part is the squash-merge false
# positive: after a squash, every branch commit's patch-id differs from the
# squashed commit, so `git cherry` alone flags everything — the content-verify
# step must filter those out. These 3 fixtures ARE the spec for that step.
#
#   exit 0 = clean (no genuine orphan)
#   exit 3 = genuine orphan(s) found
#   exit 4 = skip (branch/baseline unresolvable)
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
  bash "$HELPER" --repo "$1" --branch "$2" --baseline "$3" >/dev/null 2>&1
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

# ── Fixtures 8–27 (#399): a squash keeps the branch's FINAL content, not each commit ──
# A line one branch commit adds and a later one rewrites exists in no final tree,
# and main may edit the branch's lines after the squash (#408: a release date
# changed by a follow-up commit). The gate answers "did the branch's content land":
# it finds the newest baseline commit holding the branch's whole net change (the
# landing commit) and checks each commit's lines against THAT, skipping lines the
# branch head itself no longer has. What main did after landing — a follow-up, a
# revert — is out of scope. Finding the landing commit must not accept what never
# landed, and no merge driver, diff driver or color setting may decide.
#
# The landing step needs `git merge-tree --write-tree` (git >= 2.38). On an older
# git the helper checks against the tip; the fixtures that only the landing step
# can clear expect that fallback instead of failing. The probe runs in a scratch
# repo, not the caller's cwd.
PROBE="$(mk_repo)"
if git -C "$PROBE" merge-tree --write-tree HEAD HEAD >/dev/null 2>&1; then
  CONTAINED_RC=0
else
  CONTAINED_RC=3
  echo "  (git without merge-tree --write-tree: landing fixtures expect the tip fallback)"
fi
rm -rf "$PROBE"

mk_rewrite_branch() { # repo -> feat: x added, then rewritten
  printf 'h1\nh2\nh3\n' > "$1/a.py"; git -C "$1" add -A && git -C "$1" commit -qm "a.py"
  git -C "$1" checkout -q -b feat
  printf 'h1\nh2\nh3\nx = 1\n' > "$1/a.py"; git -C "$1" commit -qam "add x"
  printf 'h1\nh2\nh3\nx = 2\n' > "$1/a.py"; git -C "$1" commit -qam "change x"
}
squash_feat() { git -C "$1" checkout -q main && git -C "$1" merge -q --squash feat >/dev/null 2>&1 && git -C "$1" commit -qm "squash feat"; }
edit_x() { printf 'h1\nh2\nh3\nx = 3\n' > "$1/a.py"; git -C "$1" commit -qam "follow-up edits the branch's line"; }
out_of() { bash "$HELPER" --repo "$1" --branch "$2" --baseline "$3" 2>/dev/null; }
has() { printf '%s\n' "$1" | grep -qF -- "$2"; echo $?; }   # 0 = present

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
assert_exit "fixture-9b squash + follow-up editing the branch's line -> NOT flagged" "$CONTAINED_RC" "$(run_helper "$R" feat main)"
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
if [ "$CONTAINED_RC" = 0 ]; then
  assert_exit "fixture-11 note: no landing commit, checked against the tip" 0 "$(has "$OUT11" "no baseline commit after the merge-base holds the branch's net change")"
fi
assert_exit "fixture-11 note does not claim a revert" 1 "$(has "$OUT11" 'revert')"
rm -rf "$R"

# ── Fixture 12: the landing walk tries the NEWEST 200 commits after the merge-base ──
# idd-close runs right after the merge, so the squash sits near the tip.
add_empty_commits() { # repo n — append n empty commits on main
  local t p i; t=$(git -C "$1" rev-parse 'main^{tree}'); p=$(git -C "$1" rev-parse main)
  for ((i = 0; i < $2; i++)); do p=$(git -C "$1" commit-tree "$t" -p "$p" -m "noise $i"); done
  git -C "$1" update-ref refs/heads/main "$p"
}
R="$(mk_repo)"; mk_rewrite_branch "$R"; squash_feat "$R"; edit_x "$R"
add_empty_commits "$R" 198   # squash is the 200th commit back from the tip
assert_exit "fixture-12a squash within the newest 200 -> found" "$CONTAINED_RC" "$(run_helper "$R" feat main)"
rm -rf "$R"
R="$(mk_repo)"; mk_rewrite_branch "$R"; squash_feat "$R"; edit_x "$R"
add_empty_commits "$R" 199   # squash is the 201st
OUT12=$(out_of "$R" feat main); RC12=$?
assert_exit "fixture-12b squash is the 201st back -> not walked, flagged" 3 "$RC12"
if [ "$CONTAINED_RC" = 0 ]; then
  assert_exit "fixture-12b note says the walk stopped at 200" 0 "$(has "$OUT12" 'newest 200')"
fi
rm -rf "$R"

# ── Fixture 13: a revert after landing is main's own history — out of scope ──
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'f1\n' > "$R/f.txt"; git -C "$R" add -A && git -C "$R" commit -qm "add f"
printf 'f1\nf2\n' > "$R/f.txt"; git -C "$R" commit -qam "extend f"
squash_feat "$R"; git -C "$R" revert --no-edit HEAD >/dev/null 2>&1
assert_exit "fixture-13 squash then revert -> NOT flagged (landed; revert out of scope)" "$CONTAINED_RC" "$(run_helper "$R" feat main)"
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
assert_exit "fixture-16 partial overwrite after landing -> NOT flagged (out of scope)" "$CONTAINED_RC" "$(run_helper "$R" feat main)"
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
if [ "$CONTAINED_RC" = 0 ]; then
  assert_exit "fixture-19 note names the landing commit" 0 "$(has "$OUT19" "landed in")"
  assert_exit "fixture-19 note names its subject" 0 "$(has "$OUT19" "land P only")"
fi
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

# ── Fixture 22: a conflicted merge-tree never counts as landing ──
# feat deletes d.txt and adds L to e.txt. Main's C1 modified d.txt and has L;
# C2 changed L. At C1 merge-tree hits a modify/delete conflict, yet the tree it
# writes keeps C1's d.txt and equals C1's tree — only its exit status says no.
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
assert_exit "fixture-23 stacked branch squash + follow-up -> NOT flagged" "$CONTAINED_RC" "$(run_helper "$R" feat main)"
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

# ── Fixture 27: merge-tree runs where no merge driver is defined and nothing is written ──
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

print_summary
