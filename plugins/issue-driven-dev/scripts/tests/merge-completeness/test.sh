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

print_summary
