#!/usr/bin/env bash
# Test: idd-repo-map.sh derives the layer map both formats and all (#302).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$(cd "$HERE/../.." && pwd)/idd-repo-map.sh"
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"

S=$(mktemp -d); trap 'rm -rf "$S"' EXIT
mkdir -p "$S/p1/.claude/.idd" "$S/p2/.claude" "$S/p3/.claude/.idd" "$S/n/node_modules/x/.claude/.idd"
echo '{"github_repo":"o/p1"}'    > "$S/p1/.claude/.idd/local.json"
echo '{"github_repo":"o/p2"}'    > "$S/p2/.claude/issue-driven-dev.local.json"
echo '{}'                        > "$S/p3/.claude/.idd/local.json"
echo '{"github_repo":"o/noise"}' > "$S/n/node_modules/x/.claude/.idd/local.json"

OUT=$(bash "$SCRIPT" "$S" 2>&1); RC=$?
assert_exit "always exits 0" 0 "$RC"

# The whole point of the map: BOTH formats must be seen. Missing one does not
# mean "one fewer row" — an unseen config reads as "this layer does not exist"
# and triggers the wrong upward resolution (#303 measured 17 legacy repos).
assert_grep "current-format repo is mapped" "o/p1"   "$OUT"
assert_grep "legacy-format repo is mapped"  "o/p2"   "$OUT"
assert_grep "format is reported per row"    "legacy" "$OUT"
refute_grep "node_modules is pruned"        "noise"  "$OUT"

# A config that exists but names no repo is NOT a resolved layer. Letting the
# empty string through would make it look like a match.
assert_grep "config without github_repo is called out, not silently empty" \
  "(no github_repo)" "$OUT"

JSON=$(bash "$SCRIPT" --json "$S" 2>/dev/null)
require "--json emits parseable JSON" bash -c 'printf "%s" "$0" | jq -e . >/dev/null' "$JSON"
require "--json reports three repos" \
  bash -c '[ "$(printf "%s" "$0" | jq ".repos | length")" = "3" ]' "$JSON"
require "--json states whether a global layer exists" \
  bash -c 'printf "%s" "$0" | jq -e "has(\"global_present\")" >/dev/null' "$JSON"

OUT2=$(bash "$SCRIPT" "$S/does-not-exist" 2>&1)
assert_grep "a missing root yields an explicit no-repo line, not silence" \
  "no IDD-configured repo found" "$OUT2"

print_summary "idd-repo-map"
exit $?
