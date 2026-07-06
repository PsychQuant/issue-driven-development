#!/usr/bin/env bash
# test.sh — fixtures for idd-tree-lock.sh (PsychQuant/issue-driven-development#183)
#
# Cross-terminal scope (#183 verify rescope): the lock records a PERSISTENT
# process pid (the harness shell, `$PPID`) — NOT the ephemeral helper `$$`. A
# separate `claude` instance has a different live pid; when its instance exits,
# that pid dies and the lock is reclaimed. The lock answers "is the holder's
# session process still LIVE?" (kill -0), never "is the holder done?".
#
# These fixtures deliberately use REAL background processes as holders (whose
# life the test controls), so an alive/dead holder is a genuine separate
# process — not the always-alive test runner `$$`, which was the false-assurance
# that hid the original no-op (verify B1/M3).
#
#   acquire → 0 acquired / 3 held-by-live-other / 4 lock infra unwritable / 2 usage
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$HERE/../../idd-tree-lock.sh"
. "$HERE/../../lib/assert-helpers.sh"

mk_repo() { mktemp -d; }
acq()  { bash "$HELPER" acquire --repo "$1" --id "$2" --pid "$3"; }   # repo id pid
rel()  { bash "$HELPER" release --repo "$1" --id "$2"; }
lockpid()        { sed -n 's/^pid=//p'    "$1/.claude/.idd/tree-lock" | head -1; }
lockpid_holder() { sed -n 's/^holder=//p' "$1/.claude/.idd/tree-lock" | head -1; }

echo "idd-tree-lock (cross-terminal, $PPID-keyed)"

# ── Fixture 1 (Example): acquire / held / release / re-acquire over a LIVE holder ──
R="$(mk_repo)"; sleep 60 & HOLD=$!     # a real, controllable "session" process
acq "$R" A "$HOLD" >/dev/null 2>&1; assert_exit "f1a A acquires (live holder pid)"     0 $?
acq "$R" B "$HOLD" >/dev/null 2>&1; assert_exit "f1b B sees live holder -> held"        3 $?
rel "$R" A         >/dev/null 2>&1; assert_exit "f1c A releases"                        0 $?
acq "$R" B "$HOLD" >/dev/null 2>&1; assert_exit "f1d B re-acquires after release"       0 $?
kill "$HOLD" 2>/dev/null; wait "$HOLD" 2>/dev/null; rm -rf "$R"

# ── Fixture 2: holder process EXITS (instance closed) -> reclaim ──
R="$(mk_repo)"; sleep 60 & HOLD=$!
acq "$R" A "$HOLD" >/dev/null 2>&1; assert_exit "f2a A acquires (live holder)"          0 $?
kill "$HOLD" 2>/dev/null; wait "$HOLD" 2>/dev/null    # holder's instance exits → pid dead
acq "$R" B "$$"    >/dev/null 2>&1; assert_exit "f2b dead holder -> reclaimed"          0 $?
rm -rf "$R"

# ── Fixture 3: live holder -> NOT reclaimed (the real isolation guarantee) ──
R="$(mk_repo)"; sleep 60 & HOLD=$!
acq "$R" A "$HOLD" >/dev/null 2>&1; assert_exit "f3a A acquires (live)"                 0 $?
acq "$R" B "$$"    >/dev/null 2>&1; assert_exit "f3b live holder -> held, not stolen"   3 $?
kill "$HOLD" 2>/dev/null; wait "$HOLD" 2>/dev/null; rm -rf "$R"

# ── Fixture 4 (B1 REGRESSION): default acquire records a PERSISTENT pid, not the
#    ephemeral helper $$. This is the fixture that would have caught the no-op:
#    after the acquire subprocess exits, the recorded pid MUST still be alive. ──
R="$(mk_repo)"
bash "$HELPER" acquire --repo "$R" --id A >/dev/null 2>&1   # NO --pid → default $PPID (this test shell)
REC="$(lockpid "$R")"
require "f4a default-pid acquire recorded a numeric pid"  bash -c "printf '%s' '$REC' | grep -qE '^[0-9]+$'"
require "f4b recorded pid is still ALIVE after helper exited (not ephemeral \$\$)"  kill -0 "$REC"
# The helper defaults pid to its OWN $PPID = the invoking shell = this test script ($$).
# In production that invoker is the persistent harness shell (stable across Bash calls).
assert_eq "f4c recorded pid == invoking persistent shell (helper's \$PPID)" "$$" "$REC"
rm -rf "$R"

# ── Fixture 5: unwritable lock location -> exit 4 (caller fails open) ──
R="$(mk_repo)"; chmod 000 "$R"
bash "$HELPER" acquire --repo "$R" --id A --pid "$$" >/dev/null 2>&1; rc=$?
chmod 755 "$R"; rm -rf "$R"
assert_exit "f5 unwritable lock dir -> exit 4 (fail-open signal)" 4 "$rc"

# ── Fixture 6: release is holder-scoped — B cannot release A's live lock ──
R="$(mk_repo)"; sleep 60 & HOLD=$!
acq "$R" A "$HOLD" >/dev/null 2>&1
rel "$R" B         >/dev/null 2>&1               # B is not the holder → must not remove A's lock
acq "$R" C "$$"    >/dev/null 2>&1; assert_exit "f6 non-holder release leaves lock held" 3 $?
kill "$HOLD" 2>/dev/null; wait "$HOLD" 2>/dev/null; rm -rf "$R"

# ── Fixture 7 (S-1): a planted pid=0 must NOT wedge the lock (kill -0 0 is special) ──
R="$(mk_repo)"; mkdir -p "$R/.claude/.idd"
printf 'holder=X\npid=0\nheartbeat=z\nepoch=100\n' > "$R/.claude/.idd/tree-lock"   # old/stale epoch
acq "$R" A "$$"    >/dev/null 2>&1; assert_exit "f7 planted pid=0 + stale -> reclaimable" 0 $?
rm -rf "$R"

# ── Fixture 8 (B2): a half-written / unreadable-pid lock that is FRESH is treated
#    as held (mid-acquire), not stolen — closes the create/write window. ──
R="$(mk_repo)"; mkdir -p "$R/.claude/.idd"
: > "$R/.claude/.idd/tree-lock"                   # empty (fresh mtime) = mid-acquire window
acq "$R" A "$$"    >/dev/null 2>&1; assert_exit "f8 fresh unreadable lock -> held (not stolen)" 3 $?
rm -rf "$R"

# ── Fixture 9 (R2 F1): same-id re-acquire (aborted issue, sequential same instance)
#    must RE-OWN the lock, not see its own live pid as a "live other" and escalate. ──
R="$(mk_repo)"; sleep 60 & HOLD=$!
acq "$R" same "$HOLD" >/dev/null 2>&1; assert_exit "f9a acquires (id=same)"                        0 $?
acq "$R" same "$HOLD" >/dev/null 2>&1; assert_exit "f9b re-acquire same id (no release) -> re-own" 0 $?
kill "$HOLD" 2>/dev/null; wait "$HOLD" 2>/dev/null; rm -rf "$R"

# ── Fixture 10 (R2-1): reclaiming a stale lock leaves exactly ONE valid lock and no
#    orphan reclaim-mutex dir (the mkdir-mutex critical section cleans up). ──
R="$(mk_repo)"; mkdir -p "$R/.claude/.idd"
printf 'holder=ghost\npid=999999\nheartbeat=z\nepoch=100\n' > "$R/.claude/.idd/tree-lock"   # dead + stale
acq "$R" new "$$" >/dev/null 2>&1; assert_exit "f10a stale lock reclaimed"                  0 $?
assert_eq "f10b exactly one holder after reclaim" "new" "$(lockpid_holder "$R")"
require   "f10c no orphan reclaim mutex left"  bash -c "[ ! -d '$R/.claude/.idd/tree-lock.reclaim' ]"
rm -rf "$R"

# ── Fixture 11 (#245 REGRESSION): file_mtime() must resolve mtime under GNU stat
#    semantics. `stat -f %m` is BSD "format"; on GNU/Linux `-f` = --file-system, so
#    a BSD-first chain leaks a multi-line filesystem block into holder_is_live()'s
#    freshness arithmetic — a FRESH empty lock is then wrongly reclaimed (f8 passes
#    on macOS, fails on the Linux CI runner). We shim a GNU-semantics `stat` onto
#    PATH so the Linux-only failure reproduces on ANY host: RED while file_mtime
#    tries `-f` first, GREEN once it tries `-c %Y` first. ──
R="$(mk_repo)"; mkdir -p "$R/.claude/.idd"
: > "$R/.claude/.idd/tree-lock"                   # empty + fresh = mid-acquire window (as f8)
SHIMDIR="$(mktemp -d)"
cat > "$SHIMDIR/stat" <<'SHIM'
#!/bin/sh
# GNU-coreutils `stat` semantics, for the #245 regression only:
#   -f  → --file-system (NOT BSD's "format"); handed a bogus %m operand it prints a
#         multi-line fs block for the real file and exits nonzero.
#   -c  → format string ($2=%Y = mtime); prints a bare epoch integer, exit 0.
case "$1" in
  -f) printf 'File: "%s"\nID: 0 Namelen: 255 Type: apfs\nBlock size: 4096\n' "${3:-$2}"; exit 1 ;;
  -c) date +%s; exit 0 ;;
  *)  exit 1 ;;
esac
SHIM
chmod +x "$SHIMDIR/stat"
( export PATH="$SHIMDIR:$PATH"; bash "$HELPER" acquire --repo "$R" --id A --pid "$$" ) >/dev/null 2>&1
assert_exit "f11 GNU-stat shim: fresh empty lock still held (BSD-first file_mtime regression #245)" 3 $?
rm -rf "$R" "$SHIMDIR"

print_summary
