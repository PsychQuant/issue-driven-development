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
require "hooks.json is valid JSON" python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$HOOKS_JSON"
if [ -f "$HOOKS_JSON" ]; then
  # Exact wiring lock (#214 R1 HIGH): substring match let `echo session-start-commit-rule.sh`
  # pass. Assert the SINGLE canonical form: SessionStart → one entry → one hook →
  # type=="command", command == the exact quoted ${CLAUDE_PLUGIN_ROOT} invocation,
  # and NO matcher (deliberate: fire on startup/resume/clear/compact so the rule
  # survives compaction — R1 finding 8 documented decision).
  WIRED=$(python3 - "$HOOKS_JSON" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1]))
entries = d.get("hooks", {}).get("SessionStart", [])
ok = (
    isinstance(entries, list) and len(entries) == 1
    and "matcher" not in entries[0]
    and len(entries[0].get("hooks", [])) == 1
    and entries[0]["hooks"][0].get("type") == "command"
    and entries[0]["hooks"][0].get("command")
        == '"${CLAUDE_PLUGIN_ROOT}/hooks/session-start-commit-rule.sh"'
)
print("yes" if ok else "no")
PYEOF
)
  assert_eq "SessionStart wiring is the exact canonical form (single entry, no matcher, quoted CLAUDE_PLUGIN_ROOT command)" "yes" "${WIRED:-no}"
else
  fail "SessionStart wiring is the exact canonical form (single entry, no matcher, quoted CLAUDE_PLUGIN_ROOT command)" "hooks.json missing"
fi

# --- script executability + output ceiling -----------------------------------
assert_file_exists "hook script exists" "$HOOK_SCRIPT"
if [ -f "$HOOK_SCRIPT" ]; then
  # Direct execution (#214 R1 finding 2): `bash script` masks a lost executable
  # bit — the hook runner execs the file directly, so the test must too.
  assert_true "hook script is executable" "[ -x '$HOOK_SCRIPT' ]"
  # Raw-stdout line count (#214 R1 finding 3): command substitution strips
  # trailing newlines, so count lines from a temp file capture instead.
  HOOK_TMP=$(mktemp)
  "$HOOK_SCRIPT" >"$HOOK_TMP" 2>&1; RC=$?
  assert_exit "hook script exits 0" 0 $RC
  OUT=$(cat "$HOOK_TMP")
  LINES=$(grep -c '' "$HOOK_TMP")   # counts every line incl. an unterminated last line
  rm -f "$HOOK_TMP"
  assert_true "output ≤ 5 lines (got $LINES)" "[ $LINES -le 5 ]"
else
  OUT=""
  fail "hook script is executable" "script missing"
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
# Adjacency-warning semantics (#214 R1 finding 4): keywords alone are not the
# warning — require the 鄰接 verb AND the #-digit object token in BOTH files
# (canonical writes `#<數字>`, hook writes `#數字` — regex covers both forms).
assert_grep_re "hook output warns about close/fix/resolve" 'close.*fix.*resolve|close / fix / resolve|close/fix/resolve' "$OUT"
assert_grep_re "rules file warns about close/fix/resolve" 'close.*fix.*resolve|close / fix / resolve|close/fix/resolve' "$RULES"
assert_grep "hook output carries the adjacency verb (鄰接)" "鄰接" "$OUT"
assert_grep "rules file carries the adjacency verb (鄰接)" "鄰接" "$RULES"
assert_grep_re "hook output names the #-digit object" '#<?數字>?' "$OUT"
assert_grep_re "rules file names the #-digit object" '#<?數字>?' "$RULES"

print_summary "session-start-commit-rule"
