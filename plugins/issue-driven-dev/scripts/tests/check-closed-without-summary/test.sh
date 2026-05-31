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

if [ ! -f "$HELPER" ]; then
  echo "  ✗ helper not found: $HELPER"
  echo "FAIL: helper missing"
  exit 1
fi

OUT=$(bash "$HELPER" --json-file "$FIXTURE" 2>/dev/null)
RC=$?

fail=0
flagged() { printf '%s\n' "$OUT" | grep -qE "(^|[^0-9])#$1([^0-9]|$)"; }

flagged 101 || { echo "  ✗ #101 (closed, no summary) should be flagged"; fail=1; }
flagged 103 || { echo "  ✗ #103 (closed, zero comments) should be flagged"; fail=1; }
flagged 100 && { echo "  ✗ #100 (closed WITH summary) must NOT be flagged"; fail=1; }
flagged 102 && { echo "  ✗ #102 (open) must NOT be flagged — only closed issues are audited"; fail=1; }
[ "$RC" -eq 0 ] || { echo "  ✗ expected exit 0 (advisory), got $RC"; fail=1; }

# --dry-run: assert the live-gh branch composes the right gh invocation, with NO
# network (closes the untested-executable-seam gap, #151 verify DA/logic LOW).
DRY=$(bash "$HELPER" --repo foo/bar --since 2026-01-01 --limit 5 --dry-run 2>/dev/null)
echo "$DRY" | grep -q -- '--state closed'        || { echo "  ✗ --dry-run: gh args missing '--state closed'"; fail=1; }
echo "$DRY" | grep -q -- '--repo foo/bar'         || { echo "  ✗ --dry-run: gh args missing '--repo foo/bar'"; fail=1; }
echo "$DRY" | grep -q -- '--limit 5'              || { echo "  ✗ --dry-run: gh args missing '--limit 5'"; fail=1; }
echo "$DRY" | grep -q 'closed:>=2026-01-01'       || { echo "  ✗ --dry-run: gh args missing '--since' search composition"; fail=1; }

# Malformed JSON must NOT yield a false "all-clear" (safety-net direction, #151 verify logic LOW).
MAL=$(bash "$HELPER" --json-file "$HERE/fixtures/malformed.json" 2>/dev/null); MRC=$?
echo "$MAL" | grep -q 'No closed issue is missing' && { echo "  ✗ malformed JSON produced a FALSE all-clear"; fail=1; }
[ "$MRC" -eq 0 ] || { echo "  ✗ malformed JSON: expected advisory exit 0, got $MRC"; fail=1; }

if [ "$fail" -eq 0 ]; then
  echo "PASS: flags only #101 + #103 (closed without Closing Summary); #100 + #102 excluded."
  exit 0
fi
echo ""
echo "FAIL: check-closed-without-summary did not flag the expected set."
echo "--- helper output ---"
printf '%s\n' "$OUT"
exit 1
