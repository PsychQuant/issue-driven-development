#!/usr/bin/env bash
# Test: check-closed-without-summary.sh flags CLOSED issues that lack a
# `## Closing Summary` comment — the retroactive safety net for the
# direct-commit auto-close trap (#151).
#
# Fixture `mixed.json`:
#   #100 CLOSED + has Closing Summary  → must NOT flag
#   #101 CLOSED + no  Closing Summary  → must flag
#   #102 OPEN   + no  Closing Summary  → must NOT flag (only closed issues audited)
#   #103 CLOSED + zero comments        → must flag (legacy / UI-close)
#
# Usage: bash test.sh   (exit 0 = pass, 1 = fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$(cd "$HERE/../.." && pwd)/check-closed-without-summary.sh"   # scripts/check-closed-without-summary.sh
FIXTURE="$HERE/fixtures/mixed.json"

# Shared assertion helpers (#156) — require/refute/assert_grep bake in the `--`
# end-of-options separator, so a needle like '--state closed' is matched as data.
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"

if [ ! -f "$HELPER" ]; then
  echo "  ✗ helper not found: $HELPER"
  echo "FAIL: helper missing"
  exit 1
fi

OUT=$(bash "$HELPER" --json-file "$FIXTURE" 2>/dev/null)
RC=$?

# Domain predicate: was issue #$1 flagged in the helper output? (#$1 is always a
# digit run, so the composed pattern can never start with `--`; `--` added anyway
# for uniform discipline.)
flagged() { printf '%s\n' "$OUT" | grep -qE -- "(^|[^0-9])#$1([^0-9]|$)"; }

require "#101 (closed, no summary) is flagged"        flagged 101
require "#103 (closed, zero comments) is flagged"     flagged 103
refute  "#100 (closed WITH summary) is NOT flagged"   flagged 100
refute  "#102 (open) is NOT flagged"                  flagged 102
assert_exit "advisory exit 0 on mixed fixture" 0 "$RC"

# --dry-run: assert the live-gh branch composes the right gh invocation, with NO
# network (closes the untested-executable-seam gap, #151 verify DA/logic LOW).
DRY=$(bash "$HELPER" --repo foo/bar --since 2026-01-01 --limit 5 --dry-run 2>/dev/null)
assert_grep    "--dry-run gh args have '--state closed'" "--state closed"      "$DRY"
assert_grep    "--dry-run gh args have '--repo foo/bar'" "--repo foo/bar"      "$DRY"
assert_grep    "--dry-run gh args have '--limit 5'"      "--limit 5"           "$DRY"
assert_grep    "--dry-run composes '--since' search"     "closed:>=2026-01-01" "$DRY"

# Malformed JSON must NOT yield a false "all-clear" (safety-net direction, #151 verify logic LOW).
MAL=$(bash "$HELPER" --json-file "$HERE/fixtures/malformed.json" 2>/dev/null); MRC=$?
refute_grep "malformed JSON does NOT produce a FALSE all-clear" "No closed issue is missing" "$MAL"
assert_exit "malformed JSON: advisory exit 0" 0 "$MRC"

print_summary "check-closed-without-summary"
exit $?
