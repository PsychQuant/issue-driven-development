#!/usr/bin/env bash
# Test: migrate-idd-config.sh moves legacy config without destroying anything (#303).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$(cd "$HERE/../.." && pwd)/migrate-idd-config.sh"
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"

S=$(mktemp -d)
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/a/.claude" "$S/b/.claude/.idd" "$S/n/node_modules/x/.claude"
echo '{"github_repo":"o/a"}'        > "$S/a/.claude/issue-driven-dev.local.json"
echo '{"github_repo":"o/b-legacy"}' > "$S/b/.claude/issue-driven-dev.local.json"
echo '{"github_repo":"o/b-cur"}'    > "$S/b/.claude/.idd/local.json"
echo '{"github_repo":"o/noise"}'    > "$S/n/node_modules/x/.claude/issue-driven-dev.local.json"

SCAN=$(bash "$SCRIPT" --scan "$S" 2>&1); SRC=$?
assert_exit "scan exits 0" 0 "$SRC"
assert_grep    "scan reports the migratable repo"        "would migrate" "$SCAN"
refute_grep    "scan does not write anything"            "✓ migrated"    "$SCAN"
refute_grep    "node_modules is pruned, not reported"    "noise"         "$SCAN"
require "scan left the legacy file in place" \
  test -f "$S/a/.claude/issue-driven-dev.local.json"

OUT=$(bash "$SCRIPT" --apply "$S" 2>&1); ARC=$?
assert_exit "apply exits 0 when nothing failed" 0 "$ARC"
require "legacy file moved to the current path" test -f "$S/a/.claude/.idd/local.json"
refute  "legacy file no longer at the old path" test -f "$S/a/.claude/issue-driven-dev.local.json"
require "a breadcrumb is left behind"           test -f "$S/a/.claude/issue-driven-dev.local.json.moved"

# The destructive case this script must never do: clobber an existing current
# config with a stale legacy one. Both present -> leave both alone.
assert_grep "both-present is reported, not migrated" "both present" "$OUT"
require "existing current config is untouched" \
  bash -c 'grep -q "b-cur" "$0/b/.claude/.idd/local.json"' "$S"
require "its legacy sibling is also left in place" \
  test -f "$S/b/.claude/issue-driven-dev.local.json"

# node_modules must stay pruned even on apply
require "node_modules config was not touched" \
  test -f "$S/n/node_modules/x/.claude/issue-driven-dev.local.json"

print_summary "migrate-idd-config"
exit $?
