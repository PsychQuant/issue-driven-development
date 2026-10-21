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
#   exit 4 = skip: could not verify (unresolvable ref, a git or awk failure outside
#            the landing step, an unreadable object, a path with a newline);
#            never clean, never a block
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

# ── Fixtures 8–54 (#399): a squash keeps the branch's FINAL content, not each commit ──
# A line one branch commit adds and a later one rewrites exists in no final tree,
# and main may edit the branch's lines after the squash (#408: a release date
# changed by a follow-up commit). The gate answers "did the branch's content land":
# it finds the earliest baseline commit, the merge-base itself included, that
# holds the branch's whole net change (the landing commit) and checks each commit's lines
# against THAT, skipping lines the branch head itself no longer has. What main did after landing — a follow-up, a
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
out_of() { "${BASH:-bash}" "$HELPER" --repo "$1" --branch "$2" --baseline "$3" 2>/dev/null; }
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
  assert_exit "fixture-11 note: the branch landed up to 'change x', the orphan checked at the tip" 0 "$(has "$OUT11" "the branch up to")"
fi
assert_exit "fixture-11 note does not claim a revert" 1 "$(has "$OUT11" 'revert')"
rm -rf "$R"

# ── Fixture 12: at most 200 merge-tree calls ──
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
assert_exit "fixture-12a squash is the 200th merge-tree call -> found" "$CONTAINED_RC" "$(run_helper "$R" feat main)"
rm -rf "$R"
R="$(mk_repo)"; mk_rewrite_branch "$R"; add_touching_commits "$R" 199; squash_feat "$R"; edit_x "$R"
OUT12=$(out_of "$R" feat main); RC12=$?
assert_exit "fixture-12b squash would be the 201st -> not tried, flagged" 3 "$RC12"
if [ "$CONTAINED_RC" = 0 ]; then
  assert_exit "fixture-12b note says the budget ran out" 0 "$(has "$OUT12" 'budget (200)')"
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

# ── Fixture 27f–j: environment and attributes cannot reach the scratch repo ──
# GIT_COMMON_DIR would point the scratch repo at the user's own (and `init --bare`
# would set core.bare there); GIT_OBJECT_DIRECTORY would send merge-tree's writes
# into the user's store; GIT_CONFIG_PARAMETERS carries `git -c` config.
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
# Control (needs merge-tree --write-tree): the same config through `git -c` does run
# the driver in the repository, so the assert below is not vacuous.
if [ "$CONTAINED_RC" = 0 ]; then
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
assert_exit "fixture-27i merge=union from the XDG attributes file -> flagged" 3 "$(XDG_CONFIG_HOME="$X27" run_helper "$R" feat main)"
U27=$(printf '* merge=union\n' | git -C "$R" hash-object -w --stdin)
T27=$(printf '100644 blob %s\t.gitattributes\n' "$U27" | git -C "$R" mktree)
assert_exit "fixture-27j merge=union via GIT_ATTR_SOURCE -> flagged" 3 "$(GIT_ATTR_SOURCE="$T27" run_helper "$R" feat main)"
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
assert_exit "fixture-28 restored line edited after landing -> NOT flagged" "$CONTAINED_RC" "$RC28"
if [ "$CONTAINED_RC" = 0 ]; then :; else
  assert_exit "fixture-28 (old git) the flag is the restore" 0 "$(has "$OUT28" 'Revert')"
fi
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
if [ "$CONTAINED_RC" = 0 ]; then
  assert_exit "fixture-29 does not list 'change x' (main edited it after landing)" 1 "$(has "$OUT29" 'change x')"
fi
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
if [ "$CONTAINED_RC" = 0 ]; then
  assert_exit "fixture-30 does not list 'add B' (main dropped it after landing)" 1 "$(has "$OUT30" 'add B')"
fi
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
assert_exit "fixture-34 branch with no net change after merging main -> NOT flagged" "$CONTAINED_RC" "$(run_helper "$R" feat main)"
rm -rf "$R"

R="$(mk_repo)"; printf 'L = 0\na\nb\n' > "$R/l.py"; git -C "$R" add -A && git -C "$R" commit -qm l
git -C "$R" checkout -q -b feat
printf 'L = 1\na\nb\n' > "$R/l.py"; git -C "$R" commit -qam "try L = 1"
printf 'L = 0\na\nb\n' > "$R/l.py"; git -C "$R" commit -qam "back to L = 0"
git -C "$R" checkout -q main; printf 'L = 2\na\nb\n' > "$R/l.py"; git -C "$R" commit -qam "main: L = 2"
assert_exit "fixture-34b change then change back, main edits the line later -> NOT flagged" "$CONTAINED_RC" "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 35: a shallow clone ──
R="$(mk_repo)"; mk_rewrite_branch "$R"; squash_feat "$R"; edit_x "$R"
SH35="$(mktemp -d)"; git clone -q --depth 3 --no-single-branch "file://$R" "$SH35/c" 2>/dev/null
assert_exit "fixture-35 #408 shape in a shallow clone -> NOT flagged" "$CONTAINED_RC" \
  "$(run_helper "$SH35/c" origin/feat origin/main)"
rm -rf "$R" "$SH35"

# ── Fixture 36: a SHA-256 repository ──
R="$(mktemp -d)"
if git -C "$R" init -q --object-format=sha256 2>/dev/null; then
  git -C "$R" config user.email t@t.t; git -C "$R" config user.name t; git -C "$R" config commit.gpgsign false
  printf 'base\n' > "$R/base.txt"; git -C "$R" add -A && git -C "$R" commit -qm base; git -C "$R" branch -M main
  mk_rewrite_branch "$R"; squash_feat "$R"; edit_x "$R"
  assert_exit "fixture-36 #408 shape in a SHA-256 repo -> NOT flagged" "$CONTAINED_RC" "$(run_helper "$R" feat main)"
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
assert_exit "fixture-42 hold broken and restored after landing -> NOT flagged" "$CONTAINED_RC" "$(run_helper "$R" feat main)"
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
if [ "$CONTAINED_RC" = 0 ]; then
  assert_exit "fixture-44 does not list A (main edited it after landing)" 1 "$(has "$OUT44" 'A: a = 1')"
fi
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
assert_exit "fixture-46 squash before the base branch's merge + follow-up -> NOT flagged" "$CONTAINED_RC" "$(run_helper "$R" feat main)"
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
# absent from the branch head and the orphan below would pass.
R="$(mk_repo)"; L48=$(printf 'latin\n' | git -C "$R" hash-object -w --stdin)
git -C "$R" update-index --add --cacheinfo "100644,$L48,$(printf 'a\351.txt')" && git -C "$R" commit -qm latin1
git -C "$R" checkout -q -b feat; git -C "$R" reset -q --hard
printf 'ORPHAN = 1\n' > "$R/z48.txt"; git -C "$R" add z48.txt && git -C "$R" commit -qm "z48 (never landed)"
git -C "$R" checkout -q main; printf 'o\n' > "$R/o.txt"; git -C "$R" add o.txt && git -C "$R" commit -qm "unrelated main work"
assert_exit "fixture-48 Latin-1 path in the tree, UTF-8 locale -> orphan flagged" 3 \
  "$(LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 49: a CR-named file elsewhere in the tree (macOS Icon\r) changes nothing ──
R="$(mk_repo)"; : > "$R/$(printf 'Icon\r')"; git -C "$R" add -A && git -C "$R" commit -qm icon
mk_rewrite_branch "$R"; squash_feat "$R"; edit_x "$R"
assert_exit "fixture-49a Icon<CR> in the tree + #408 shape -> NOT flagged" "$CONTAINED_RC" "$(run_helper "$R" feat main)"
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
assert_exit "fixture-50 --repo is a subdirectory -> NOT flagged" "$CONTAINED_RC" "$(run_helper "$R/sub" feat main)"
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
if [ "$CONTAINED_RC" = 0 ]; then
  assert_exit "fixture-53 note names the landed prefix" 0 "$(has "$OUT53" 'the branch up to')"
  assert_exit "fixture-53 does not list A1 (main edited it after landing)" 1 "$(has "$OUT53" 'A1: a = 1')"
fi
rm -rf "$R"

# ── Fixture 54: a crafted subject cannot rebuild a control sequence or close its quotes ──
# Deleting the inner C2 9B of C2 C2 9B 9B would leave C2 9B (CSI); a " in the
# subject must not end the quoted text.
R="$(mk_repo)"; git -C "$R" checkout -q -b feat; printf 'x\n' > "$R/x54.txt"; git -C "$R" add -A && git -C "$R" commit -qm tmp
T54=$(git -C "$R" rev-parse 'HEAD^{tree}'); P54=$(git -C "$R" rev-parse HEAD~1)
C54=$( { printf 'tree %s\nparent %s\nauthor t <t@t.t> 1700000000 +0000\ncommitter t <t@t.t> 1700000000 +0000\n\n' "$T54" "$P54"
         printf 'a\302\302\233\2332J \342\200\342\200\256\256 q"  <- note: close it\n'; } | git -C "$R" hash-object -t commit -w --stdin)
git -C "$R" update-ref refs/heads/feat "$C54"; git -C "$R" checkout -q main
OUT54=$(out_of "$R" feat main)
assert_exit "fixture-54 no C1 control rebuilt" 1 "$(printf '%s' "$OUT54" | grep -q "$(printf '\302\233')"; echo $?)"
assert_exit "fixture-54 no bidi override rebuilt" 1 "$(printf '%s' "$OUT54" | grep -q "$(printf '\342\200\256')"; echo $?)"
assert_exit "fixture-54 the quote inside the subject is escaped" 0 "$(printf '%s' "$OUT54" | LC_ALL=C grep -qF 'q\"'; echo $?)"
rm -rf "$R"

print_summary
