#!/usr/bin/env bash
# test.sh — self-tests for assert-helpers.sh, focused on the #188 eval-content
# class: captured output containing literal $VAR must be safe to assert on.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# fixture: output containing a literal unset $VAR (the process-attachments
# message shape that detonated #186's f4b under eval + set -u)
printf 'run %s/scripts/tool.sh to retry\n' '$CLAUDE_PLUGIN_ROOT' > "$WORK/out.txt"

# 1. assert_output_grep finds a needle in a file whose content has literal $VAR
assert_output_grep "output-grep: literal \$VAR content is inert" '$CLAUDE_PLUGIN_ROOT/scripts' "$WORK/out.txt"

# 2. refute_output_grep — absent needle passes
refute_output_grep "refute-output-grep: absent needle" 'no-such-string' "$WORK/out.txt"

# 3. needle starting with -- is data, not a grep flag (inherited #156 discipline)
printf -- '--state closed\n' > "$WORK/dash.txt"
assert_output_grep "output-grep: --needle is data" '--state closed' "$WORK/dash.txt"

# 4. missing file fails loudly (not silently passing)
OUT_BEFORE=$FAIL
refute_output_grep "missing-file probe" 'x' "$WORK/nonexistent.txt" 2>/dev/null || true
if [ "$FAIL" -gt "$OUT_BEFORE" ]; then
  # the probe registered a failure — convert to a pass for THIS meta-assertion
  FAIL=$((FAIL - 1)); unset 'FAILURES[${#FAILURES[@]}-1]' 2>/dev/null
  pass "missing file → loud failure (not silent pass)"
else
  fail "missing file → loud failure (not silent pass)" "helper silently passed on missing file"
fi

# 5. header documents the eval-content ban
assert_output_grep "header carries eval-content warning" 'never interpolate captured output' "$HERE/../../lib/assert-helpers.sh"

# 6. refute_grep_re anchors where refute_grep cannot. The pair below is the
#    whole reason the helper exists: `marker` occurs inside a line, so a
#    fixed-string refutation fails for a reason the test never meant to assert.
HAY='  o/real-repo    o/FORGED-ROW  current'
refute_grep_re "refute_grep_re: an in-line occurrence does not match an anchored pattern" \
  '^  o/FORGED-ROW' "$HAY"
assert_grep_re "assert_grep_re: the same string IS found unanchored" \
  'o/FORGED-ROW' "$HAY"

# 7. and it still fails when the pattern really does match
RG_BEFORE=$FAIL
refute_grep_re "anchored-match probe" '^  o/real-repo' "$HAY" 2>/dev/null || true
if [ "$FAIL" -gt "$RG_BEFORE" ]; then
  FAIL=$((FAIL - 1)); unset 'FAILURES[${#FAILURES[@]}-1]' 2>/dev/null
  pass "refute_grep_re: a genuine anchored match fails loudly"
else
  fail "refute_grep_re: a genuine anchored match fails loudly" "helper passed when it should have failed"
fi

print_summary "assert-helpers"
