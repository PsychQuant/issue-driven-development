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

# ── Fixtures 8–11 (#399): a squash keeps the branch's FINAL content, not each commit ──
# A line one branch commit adds and a later one rewrites exists in no final tree,
# so per-commit line presence flags that commit. These fixtures pin the containment
# check: a squash that holds the branch's net change is clean even when (9) the
# baseline gained a follow-up on the same file afterwards, or (10) the branch was
# never rebased and main changed the same file meanwhile. (11) keeps a genuine
# orphan flagged next to that rewrite shape.
mk_rewrite_branch() { # repo -> feat: x added, then rewritten
  printf 'h1\nh2\nh3\n' > "$1/a.py"; git -C "$1" add -A && git -C "$1" commit -qm "a.py"
  git -C "$1" checkout -q -b feat
  printf 'h1\nh2\nh3\nx = 1\n' > "$1/a.py"; git -C "$1" commit -qam "add x"
  printf 'h1\nh2\nh3\nx = 2\n' > "$1/a.py"; git -C "$1" commit -qam "change x"
}

R="$(mk_repo)"; mk_rewrite_branch "$R"
git -C "$R" checkout -q main
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat"
assert_exit "fixture-8 rewritten line, squash -> NOT flagged" 0 "$(run_helper "$R" feat main)"
rm -rf "$R"

R="$(mk_repo)"; mk_rewrite_branch "$R"
git -C "$R" checkout -q main
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat"
printf 'h1\nh2\nh3\nx = 2\ny = 3\n' > "$R/a.py"; git -C "$R" commit -qam "follow-up on the same file"
assert_exit "fixture-9 squash + later follow-up on the same file -> NOT flagged" 0 "$(run_helper "$R" feat main)"
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
assert_exit "fixture-11 rewrite shape + a genuine orphan -> flagged" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

# ── Fixture 12 (#399): the containment walk is capped at 200 baseline commits ──
# Past the cap the helper skips containment and falls back to per-commit line
# presence — today's behaviour, so the rewrite shape is flagged again (rc=3).
# Empty commits via commit-tree keep this fast.
add_empty_commits() { # repo n — append n empty commits on main
  local t p i; t=$(git -C "$1" rev-parse 'main^{tree}'); p=$(git -C "$1" rev-parse main)
  for ((i = 0; i < $2; i++)); do p=$(git -C "$1" commit-tree "$t" -p "$p" -m "noise $i"); done
  git -C "$1" update-ref refs/heads/main "$p"
}
R="$(mk_repo)"; mk_rewrite_branch "$R"
git -C "$R" checkout -q main
git -C "$R" merge -q --squash feat >/dev/null 2>&1 && git -C "$R" commit -qm "squash feat"
add_empty_commits "$R" 199   # merge-base is the a.py commit; squash + 199 = 200 commits after it
assert_exit "fixture-12a 200 baseline commits -> containment still runs" 0 "$(run_helper "$R" feat main)"
add_empty_commits "$R" 1     # 201
assert_exit "fixture-12b 201 baseline commits -> falls back to per-commit check" 3 "$(run_helper "$R" feat main)"
rm -rf "$R"

print_summary
