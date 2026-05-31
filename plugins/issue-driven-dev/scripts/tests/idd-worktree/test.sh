#!/usr/bin/env bash
# test.sh — fixture-dir tests for idd-worktree.sh (PsychQuant/issue-driven-development#167)
#
# Each test spins up a throwaway git repo in a temp dir, runs the helper, and
# asserts behavior + exit code. Self-contained — no live GitHub / network.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../idd-worktree.sh"

PASS=0
FAIL=0
FAILURES=()

# --- assertion helpers --------------------------------------------------------

pass() { PASS=$((PASS + 1)); printf '  ✓ %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); FAILURES+=("$1"); printf '  ✗ %s\n     %s\n' "$1" "${2:-}"; }

assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected [$2] got [$3]"; fi
}
assert_exit() { # name expected_code actual_code
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected exit $2 got $3"; fi
}
assert_true() { # name condition-cmd... (eval)
  local name="$1"; shift
  if eval "$@"; then pass "$name"; else fail "$name" "condition false: $*"; fi
}

# Build a throwaway git repo with one commit on branch main; echo its path.
new_repo() {
  local d
  d="$(mktemp -d)"
  git -C "$d" init -b main -q
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name t
  echo seed > "$d/seed.txt"
  git -C "$d" add seed.txt
  git -C "$d" commit -qm seed
  # Canonicalize: on macOS mktemp returns /var/... but git resolves the symlink
  # to /private/var/... — the helper returns the git-resolved path, so the test
  # must compare against the same canonical root.
  git -C "$d" rev-parse --show-toplevel
}

TMPDIRS=()
track() { TMPDIRS+=("$1"); }
cleanup_all() { for d in "${TMPDIRS[@]:-}"; do [ -n "$d" ] && rm -rf "$d"; done; }
trap cleanup_all EXIT

# ------------------------------------------------------------------------------
echo "== create =="

# 1. create fresh
R="$(new_repo)"; track "$R"
OUT="$("$SCRIPT" create 167 --slug parallel-iso --repo-root "$R" 2>/dev/null)"; RC=$?
assert_exit "create fresh exits 0" 0 "$RC"
assert_true "create fresh makes worktree dir" "[ -d '$R/.claude/worktrees/idd-167' ]"
assert_eq "create fresh stdout = abs worktree path" "$R/.claude/worktrees/idd-167" "$OUT"
assert_true "create fresh makes branch idd/167-parallel-iso" \
  "git -C '$R' show-ref --verify --quiet refs/heads/idd/167-parallel-iso"
assert_true "create fresh gitignores .claude/worktrees/" \
  "grep -qxF '.claude/worktrees/' '$R/.gitignore'"

# 2. create idempotent re-run
OUT2="$("$SCRIPT" create 167 --slug different-slug --repo-root "$R" 2>/dev/null)"; RC=$?
assert_exit "create idempotent exits 0" 0 "$RC"
assert_eq "create idempotent prints same path" "$R/.claude/worktrees/idd-167" "$OUT2"
WT_COUNT="$(git -C "$R" worktree list | grep -c 'idd-167')"
assert_eq "create idempotent makes no 2nd worktree" "1" "$WT_COUNT"

# 3. gitignore idempotent (no duplicate line)
GI_COUNT="$(grep -cxF '.claude/worktrees/' "$R/.gitignore")"
assert_eq "gitignore line appears exactly once" "1" "$GI_COUNT"

# 4. create not-a-git-repo
PLAIN="$(mktemp -d)"; track "$PLAIN"
"$SCRIPT" create 5 --slug x --repo-root "$PLAIN" >/dev/null 2>&1; RC=$?
assert_exit "create non-git repo exits 3" 3 "$RC"

# 5. create bad / missing N (usage)
"$SCRIPT" create abc --repo-root "$R" >/dev/null 2>&1; RC=$?
assert_exit "create non-numeric N exits 2" 2 "$RC"
"$SCRIPT" create --repo-root "$R" >/dev/null 2>&1; RC=$?
assert_exit "create missing N exits 2" 2 "$RC"

# 6. branch conflict — issue checked out at a DIFFERENT path
RC2="$(new_repo)"; track "$RC2"
OTHER="$(mktemp -d)/elsewhere"; track "$(dirname "$OTHER")"
git -C "$RC2" worktree add -q -b idd/167-foo "$OTHER" main
"$SCRIPT" create 167 --slug bar --repo-root "$RC2" >/dev/null 2>&1; RC=$?
assert_exit "create conflict (idd/167-* checked out elsewhere) exits 4" 4 "$RC"

# 7. bare fallback when no --slug and gh disabled
RB="$(new_repo)"; track "$RB"
IDD_WORKTREE_NO_GH=1 "$SCRIPT" create 200 --repo-root "$RB" >/dev/null 2>&1; RC=$?
assert_exit "create bare (no slug, no gh) exits 0" 0 "$RC"
assert_true "create bare makes branch idd/200" \
  "git -C '$RB' show-ref --verify --quiet refs/heads/idd/200"

echo "== cleanup =="

# 8. cleanup clean → worktree gone, branch kept
RCl="$(new_repo)"; track "$RCl"
"$SCRIPT" create 12 --slug a --repo-root "$RCl" >/dev/null 2>&1
"$SCRIPT" cleanup 12 --repo-root "$RCl" >/dev/null 2>&1; RC=$?
assert_exit "cleanup clean exits 0" 0 "$RC"
assert_true "cleanup clean removes worktree dir" "[ ! -d '$RCl/.claude/worktrees/idd-12' ]"
assert_true "cleanup clean keeps branch idd/12-a" \
  "git -C '$RCl' show-ref --verify --quiet refs/heads/idd/12-a"

# 9. cleanup dirty without --force → refuse exit 5, worktree intact
RD="$(new_repo)"; track "$RD"
"$SCRIPT" create 13 --slug b --repo-root "$RD" >/dev/null 2>&1
echo dirty > "$RD/.claude/worktrees/idd-13/uncommitted.txt"
"$SCRIPT" cleanup 13 --repo-root "$RD" >/dev/null 2>&1; RC=$?
assert_exit "cleanup dirty without --force exits 5" 5 "$RC"
assert_true "cleanup dirty refuse keeps worktree" "[ -d '$RD/.claude/worktrees/idd-13' ]"

# 10. cleanup dirty WITH --force → removed
"$SCRIPT" cleanup 13 --force --repo-root "$RD" >/dev/null 2>&1; RC=$?
assert_exit "cleanup dirty --force exits 0" 0 "$RC"
assert_true "cleanup --force removes worktree" "[ ! -d '$RD/.claude/worktrees/idd-13' ]"

# 11. cleanup missing → no-op exit 0
"$SCRIPT" cleanup 999 --repo-root "$RD" >/dev/null 2>&1; RC=$?
assert_exit "cleanup missing worktree exits 0 (no-op)" 0 "$RC"

echo "== list =="

# 12. list shows each IDD worktree with N / branch / path
RL="$(new_repo)"; track "$RL"
"$SCRIPT" create 12 --slug a --repo-root "$RL" >/dev/null 2>&1
"$SCRIPT" create 34 --slug b --repo-root "$RL" >/dev/null 2>&1
LIST="$("$SCRIPT" list --repo-root "$RL" 2>/dev/null)"; RC=$?
assert_exit "list exits 0" 0 "$RC"
assert_true "list mentions issue 12" "printf '%s' \"\$LIST\" | grep -q '12'"
assert_true "list mentions issue 34" "printf '%s' \"\$LIST\" | grep -q '34'"
assert_true "list mentions branch idd/12-a" "printf '%s' \"\$LIST\" | grep -q 'idd/12-a'"
assert_true "list mentions worktree path" "printf '%s' \"\$LIST\" | grep -q '.claude/worktrees/idd-34'"

# empty list → nothing + exit 0
REmpty="$(new_repo)"; track "$REmpty"
LIST2="$("$SCRIPT" list --repo-root "$REmpty" 2>/dev/null)"; RC=$?
assert_exit "list empty exits 0" 0 "$RC"
assert_eq "list empty prints nothing" "" "$LIST2"

echo "== verify-round fixes (#167 P2) =="

# FIX-2: canonical idd-<N>/ path registered on a WRONG branch → create exits 4
# (not silent exit 0 that misleads the caller into a wrong-issue branch).
RWB="$(new_repo)"; track "$RWB"
git -C "$RWB" worktree add -q -b idd/999-other "$RWB/.claude/worktrees/idd-50" main
"$SCRIPT" create 50 --slug x --repo-root "$RWB" >/dev/null 2>&1; RC=$?
assert_exit "create on canonical path with wrong branch exits 4 (not 0)" 4 "$RC"

# FIX-1: cleanup invoked with --repo-root pointing at a LINKED worktree still
# removes the main-tree worktree — helper anchors on the main worktree, not the
# linked one it was handed (the idd-close GC-from-worktree scenario).
RA="$(new_repo)"; track "$RA"
WT60="$("$SCRIPT" create 60 --slug a --repo-root "$RA" 2>/dev/null)"
SIDE="$("$SCRIPT" create 61 --slug b --repo-root "$RA" 2>/dev/null)"
"$SCRIPT" cleanup 60 --repo-root "$SIDE" >/dev/null 2>&1; RC=$?
assert_exit "cleanup --repo-root <linked worktree> exits 0" 0 "$RC"
assert_true "cleanup anchored on main removes target worktree idd-60" "[ ! -d '$WT60' ]"
assert_true "cleanup did not touch unrelated worktree idd-61" "[ -d '$SIDE' ]"

# ------------------------------------------------------------------------------
echo ""
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED:\n'; printf '  - %s\n' "${FAILURES[@]}"
  exit 1
fi
echo "ALL GREEN"
exit 0
