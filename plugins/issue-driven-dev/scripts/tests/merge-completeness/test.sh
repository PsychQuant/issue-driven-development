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

# ── Fixtures 8–17 (#399): a squash keeps the branch's FINAL content, not each commit ──
# A line one branch commit adds and a later one rewrites exists in no final tree.
# Two mechanisms cover that: (a) the per-commit check skips an added line the
# branch head itself no longer has, and (b) a containment step accepts a squash
# whose content main edited AFTER it landed (#408: a release date changed by a
# follow-up commit). Containment must not accept what never landed or what was
# reverted, and must not let repo merge drivers decide.
#
# Containment needs `git merge-tree --write-tree` and `--attr-source` (git >= 2.40).
# On an older git the helper falls back to the per-commit check; the fixtures that
# only containment can clear expect that fallback instead of failing.
if git merge-tree --write-tree HEAD HEAD >/dev/null 2>&1 \
   && git --attr-source="$(git hash-object -t tree /dev/null)" version >/dev/null 2>&1; then
  CONTAINED_RC=0
else
  CONTAINED_RC=3
  echo "  (git without merge-tree --write-tree / --attr-source: containment fixtures expect the per-commit fallback)"
fi

mk_rewrite_branch() { # repo -> feat: x added, then rewritten
  printf 'h1\nh2\nh3\n' > "$1/a.py"; git -C "$1" add -A && git -C "$1" commit -qm "a.py"
  git -C "$1" checkout -q -b feat
  printf 'h1\nh2\nh3\nx = 1\n' > "$1/a.py"; git -C "$1" commit -qam "add x"
  printf 'h1\nh2\nh3\nx = 2\n' > "$1/a.py"; git -C "$1" commit -qam "change x"
}
squash_feat() { git -C "$1" checkout -q main && git -C "$1" merge -q --squash feat >/dev/null 2>&1 && git -C "$1" commit -qm "squash feat"; }

R="$(mk_repo)"; mk_rewrite_branch "$R"; squash_feat "$R"
assert_exit "fixture-8 rewritten line, squash -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

R="$(mk_repo)"; mk_rewrite_branch "$R"; squash_feat "$R"
printf 'h1\nh2\nh3\nx = 2\ny = 3\n' > "$R/a.py"; git -C "$R" commit -qam "follow-up on the same file"
assert_exit "fixture-9a squash + later follow-up adding to the same file -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

# 9b is the #408 shape: a follow-up edits the very line the branch added. Only
# containment can clear it — the per-commit check sees `x = 2` in the branch head
# and not at the tip.
R="$(mk_repo)"; mk_rewrite_branch "$R"; squash_feat "$R"
printf 'h1\nh2\nh3\nx = 3\n' > "$R/a.py"; git -C "$R" commit -qam "follow-up edits the branch's line"
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
OUT11=$(bash "$HELPER" --repo "$R" --branch feat --baseline main 2>/dev/null); RC11=$?
assert_exit "fixture-11 rewrite shape + a genuine orphan -> flagged" 3 "$RC11"
assert_exit "fixture-11 lists the genuine orphan" 0 "$(printf '%s\n' "$OUT11" | grep -q 'orphan (never landed)'; echo $?)"
assert_exit "fixture-11 does not list the rewritten 'add x'" 1 "$(printf '%s\n' "$OUT11" | grep -q 'add x'; echo $?)"
rm -rf "$R"

# ── Fixture 12: containment walks the OLDEST 200 baseline commits after the merge-base ──
# The squash is normally among the first; past 200 the rest are not tried.
add_empty_commits() { # repo n — append n empty commits on main
  local t p i; t=$(git -C "$1" rev-parse 'main^{tree}'); p=$(git -C "$1" rev-parse main)
  for ((i = 0; i < $2; i++)); do p=$(git -C "$1" commit-tree "$t" -p "$p" -m "noise $i"); done
  git -C "$1" update-ref refs/heads/main "$p"
}
edit_x() { printf 'h1\nh2\nh3\nx = 3\n' > "$1/a.py"; git -C "$1" commit -qam "follow-up edits the branch's line"; }
R="$(mk_repo)"; mk_rewrite_branch "$R"; squash_feat "$R"; edit_x "$R"
add_empty_commits "$R" 199   # squash is commit 1 of 201 after the merge-base
assert_exit "fixture-12a squash within the oldest 200 -> found" "$CONTAINED_RC" "$(run_helper "$R" feat main)"
rm -rf "$R"
R="$(mk_repo)"; mk_rewrite_branch "$R"; git -C "$R" checkout -q main
add_empty_commits "$R" 200; git -C "$R" checkout -q main
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat"; edit_x "$R"
assert_exit "fixture-12b squash is commit 201 -> not walked, per-commit check flags" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 13: a squash that main reverted wholesale is NOT landed ──
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'f1\n' > "$R/f.txt"; git -C "$R" add -A && git -C "$R" commit -qm "add f"
printf 'f1\nf2\n' > "$R/f.txt"; git -C "$R" commit -qam "extend f"
squash_feat "$R"; git -C "$R" revert --no-edit HEAD >/dev/null 2>&1
assert_exit "fixture-13 squash then revert -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 14: a baseline commit that is not a descendant of the merge-base ──
# feat forks from a side branch, undoes it (v=1) and adds w.txt; main had a
# parallel commit that added the same w.txt before merging side. That parallel
# commit is reachable from main but not from the merge-base, and measured against
# its own (older) merge-base the branch's net change — w.txt only — is already in
# it. The restore of v=1 never landed. (w.txt keeps the wholesale-revert check
# from deciding first, so this pins --ancestry-path itself.)
R="$(mk_repo)"
printf 'v = 1\n' > "$R/v.txt"; git -C "$R" add -A && git -C "$R" commit -qm "v=1"
git -C "$R" checkout -q -b side; printf 'v = 2\n' > "$R/v.txt"; git -C "$R" commit -qam "side: v=2"
git -C "$R" checkout -q -b feat; printf 'v = 1\n' > "$R/v.txt"; printf 'w\n' > "$R/w.txt"
git -C "$R" add -A && git -C "$R" commit -qm "restore v=1 + add w (restore never landed)"
git -C "$R" checkout -q main; printf 'w\n' > "$R/w.txt"; git -C "$R" add -A && git -C "$R" commit -qm "parallel main commit adds w"
git -C "$R" merge -q --no-ff -m "merge side" side
assert_exit "fixture-14 non-descendant baseline commit does not count -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 15: a repo merge driver must not decide containment ──
# `merge=keepours` resolves every conflict to main's version, which would make a
# branch change that never landed look contained.
R="$(mk_repo)"
printf 'a.py merge=keepours\n' > "$R/.gitattributes"; printf 'v = 1\n' > "$R/a.py"
git -C "$R" add -A && git -C "$R" commit -qm "attrs + a.py"
git -C "$R" config merge.keepours.driver true
git -C "$R" checkout -q -b feat; printf 'v = 2\n' > "$R/a.py"; git -C "$R" commit -qam "fix: v=2 (never landed)"
git -C "$R" checkout -q main; printf 'v = 9\n' > "$R/a.py"; git -C "$R" commit -qam "main: v=9"
assert_exit "fixture-15 keep-ours merge driver ignored -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 16 (documented limit): main overwrote PART of a landed squash ──
# The branch's change is not wholly undone at the tip, so containment still
# accepts the squash commit. A later edit and a partial revert cannot be told
# apart; this pins the accepted trade-off rather than leaving it unstated.
R="$(mk_repo)"; git -C "$R" checkout -q -b feat
printf 'A\n' > "$R/g.txt"; git -C "$R" add -A && git -C "$R" commit -qm "add A"
printf 'A\nB\n' > "$R/g.txt"; git -C "$R" commit -qam "add B"
squash_feat "$R"; printf 'A\n' > "$R/g.txt"; git -C "$R" commit -qam "later edit drops B"
assert_exit "fixture-16 partial overwrite after landing -> NOT flagged (documented limit)" "$CONTAINED_RC" "$(run_helper "$R" feat main)"
rm -rf "$R"

print_summary
