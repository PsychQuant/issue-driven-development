#!/usr/bin/env bash
# test.sh — cloud-session runtime contract (#416, change cloud-session-idd-all).
#
#   lib      scripts/lib/cloud-session.sh — CLAUDE_CODE_REMOTE / CLAUDE_CODE_SESSION_ATTENDED are
#            read as exact literals; anything else is "not cloud" / "unattended".
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
LIB="$HERE/../../lib/cloud-session.sh"

# ── lib: detection ──────────────────────────────────────────────────────────
is_cloud() { env -u CLAUDE_CODE_REMOTE ${1:+CLAUDE_CODE_REMOTE="$1"} bash -c '. "$0"; idd_is_cloud_session' "$LIB"; }
interaction() { env -u CLAUDE_CODE_SESSION_ATTENDED ${1:+CLAUDE_CODE_SESSION_ATTENDED="$1"} bash -c '. "$0"; idd_cloud_interaction' "$LIB"; }

is_cloud true;  require "CLAUDE_CODE_REMOTE=true → cloud" test $? -eq 0
is_cloud "";    refute  "CLAUDE_CODE_REMOTE unset → not cloud" test $? -eq 0
is_cloud 1;     refute  "CLAUDE_CODE_REMOTE=1 → not cloud (literal true only)" test $? -eq 0
is_cloud TRUE;  refute  "CLAUDE_CODE_REMOTE=TRUE → not cloud (case-sensitive)" test $? -eq 0
is_cloud false; refute  "CLAUDE_CODE_REMOTE=false → not cloud" test $? -eq 0
( export CLAUDE_CODE_REMOTE=""; bash -c '. "$0"; idd_is_cloud_session' "$LIB" ); refute "CLAUDE_CODE_REMOTE empty → not cloud" test $? -eq 0

assert_eq "attended signal 1 → attended"           "attended"   "$(interaction 1)"
assert_eq "attended signal unset → unattended"     "unattended" "$(interaction "")"
assert_eq "attended signal 0 → unattended"         "unattended" "$(interaction 0)"
assert_eq "attended signal true → unattended (literal 1 only)" "unattended" "$(interaction true)"

# sourcing must not leak set -e / set -u changes or print anything
OUT="$(bash -c 'set +u; . "$0"; echo "u=$-"' "$LIB")"
refute_grep "sourcing does not turn on nounset" "u" "${OUT#u=}"
assert_eq "sourcing prints nothing" "" "$(bash -c '. "$0"' "$LIB")"

print_summary "cloud-session (#416)"
