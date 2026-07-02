#!/usr/bin/env bash
# test.sh — drift-guard tests for the SessionStart commit-rule hook
# (PsychQuant/issue-driven-development#214, spec user-rule-injection).
#
# Asserts: hooks.json validity + wiring, script executability, ≤5-line output
# ceiling (every user pays this context tax each session — hard-locked here),
# and token alignment between hook output and the canonical rules file.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
HOOKS_JSON="$PLUGIN_ROOT/hooks/hooks.json"
HOOK_SCRIPT="$PLUGIN_ROOT/hooks/session-start-commit-rule.sh"
RULES_FILE="$PLUGIN_ROOT/rules/commit-issue-reference.md"

. "$HERE/../../lib/assert-helpers.sh"

# --- hooks.json validity + wiring -------------------------------------------
assert_file_exists "hooks.json exists" "$HOOKS_JSON"
require "hooks.json is valid JSON" python3 -m json.tool "$HOOKS_JSON"
if [ -f "$HOOKS_JSON" ]; then
  WIRED=$(python3 -c "
import json
d = json.load(open('$HOOKS_JSON'))
entries = d.get('hooks', {}).get('SessionStart', [])
cmds = [h.get('command','') for e in entries for h in e.get('hooks', [])]
print('yes' if any('session-start-commit-rule.sh' in c for c in cmds) else 'no')
" 2>/dev/null)
  assert_eq "SessionStart entry wires the commit-rule script" "yes" "${WIRED:-no}"
else
  fail "SessionStart entry wires the commit-rule script" "hooks.json missing"
fi

# --- script executability + output ceiling -----------------------------------
assert_file_exists "hook script exists" "$HOOK_SCRIPT"
if [ -f "$HOOK_SCRIPT" ]; then
  OUT=$(bash "$HOOK_SCRIPT" 2>&1); RC=$?
  assert_exit "hook script exits 0" 0 $RC
  LINES=$(printf '%s\n' "$OUT" | grep -c '')
  assert_true "output ≤ 5 lines (got $LINES)" "[ $LINES -le 5 ]"
else
  OUT=""
  fail "hook script exits 0" "script missing"
  fail "output ≤ 5 lines" "script missing"
fi

# --- token alignment: hook output ↔ canonical rules file ----------------------
assert_file_exists "canonical rules file exists" "$RULES_FILE"
RULES=$(cat "$RULES_FILE" 2>/dev/null || echo "")
for tok in "(#N)" "Refs #N" "/idd-close" "rules/commit-issue-reference.md"; do
  assert_grep "hook output contains token: $tok" "$tok" "$OUT"
  assert_grep "rules file contains token: $tok" "$tok" "$RULES"
done
# close-keyword warning present in both (word-level, not the trap form itself)
assert_grep_re "hook output warns about close/fix/resolve" 'close.*fix.*resolve|close / fix / resolve|close/fix/resolve' "$OUT"
assert_grep_re "rules file warns about close/fix/resolve" 'close.*fix.*resolve|close / fix / resolve|close/fix/resolve' "$RULES"

print_summary "session-start-commit-rule"
