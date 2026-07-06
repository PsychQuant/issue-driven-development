#!/usr/bin/env bash
# test.sh — unattended-state helper contract (#123/#222)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
. "$HERE/../../lib/unattended-state.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

# default: attended
( unset IDD_ALL_UNATTENDED; is_unattended "$W" ); refute "clean root → attended" test $? -eq 0

# mark → active
mark_unattended "$W" "idd-all"
( unset IDD_ALL_UNATTENDED; is_unattended "$W" ); require "marked → unattended" test $? -eq 0
assert_grep "flag records writer" '"by":"idd-all"' "$(cat "$W/.claude/.idd/state/unattended.json")"

# clear → attended
clear_unattended "$W"
( unset IDD_ALL_UNATTENDED; is_unattended "$W" ); refute "cleared → attended" test $? -eq 0

# env var compat layer wins without file
( export IDD_ALL_UNATTENDED=1; is_unattended "$W" ); require "env var compat layer → unattended" test $? -eq 0

# stale (>24h) → warn + auto-clear + attended
mkdir -p "$W/.claude/.idd/state"
printf '{"active":true,"by":"idd-all","started_at":"2020-01-01T00:00:00Z"}\n' > "$W/.claude/.idd/state/unattended.json"
( unset IDD_ALL_UNATTENDED; is_unattended "$W" 2>"$W/stale-err" ); refute "stale flag → attended" test $? -eq 0
assert_grep "stale warning surfaced" "stale" "$(cat "$W/stale-err")"
assert_file_absent "stale flag auto-cleared" "$W/.claude/.idd/state/unattended.json"

# corrupt json → treated stale
printf 'not-json' > "$W/.claude/.idd/state/unattended.json" 2>/dev/null || true
mkdir -p "$W/.claude/.idd/state"; printf 'not-json' > "$W/.claude/.idd/state/unattended.json"
( unset IDD_ALL_UNATTENDED; is_unattended "$W" 2>/dev/null ); refute "corrupt flag → attended" test $? -eq 0

print_summary "unattended-state"
