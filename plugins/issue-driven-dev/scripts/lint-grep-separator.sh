#!/usr/bin/env bash
# lint-grep-separator.sh — flag grep calls whose needle is a bare "$var" but that
# omit the `--` end-of-options separator (PsychQuant/issue-driven-development#156).
#
# Why: a needle that starts with `--` (e.g. "--state closed") is misparsed by grep
# as an unknown option instead of a search pattern — a silent test failure / warning.
# This is the #154 / #160 bug class. The structural fix is `assert_grep` (in
# lib/assert-helpers.sh), which bakes in `--`; this lint is the tripwire for any
# raw grep that bypasses it.
#
# Heuristic: a `grep <flags> "$..."` where the bare var is in NEEDLE position
# (immediately after the options) and the line has no `--` separator. A var in
# FILE position (`grep "pattern" "$file"`) is not matched (the literal pattern
# comes first). False positive anyway? append  # lint-ok: grep-sep  to the line.
#
# Usage: bash lint-grep-separator.sh   (exit 0 = clean, 1 = violations)

set -u

# Two-statement form on purpose: `A || cd X && pwd` parses as `(A || cd X) && pwd`,
# so `pwd` would run even when git succeeds — appending a second line to ROOT and
# corrupting every `git -C "$ROOT"` downstream (the lint then scans nothing and is
# silently always-green). Caught by the falsifiable planted-violation test.
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[ -n "$ROOT" ] || ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"

# Needle-position bare-var grep, no `--`, no opt-out marker.
NEEDLE_VAR='grep( +-[A-Za-z]+)* +"\$[A-Za-z_{(]'

viol=0
while IFS= read -r f; do
  case "$f" in
    # The lib defines assert_grep (`grep ... -- "$2"`); this linter quotes the
    # pattern it hunts for. Both would self-match — skip them.
    */lib/assert-helpers.sh | */lint-grep-separator.sh) continue ;;
  esac
  matches=$(grep -nE -- "$NEEDLE_VAR" "$ROOT/$f" 2>/dev/null \
            | grep -vE -- ' -- |lint-ok: grep-sep' || true)
  if [ -n "$matches" ]; then
    printf '%s:\n%s\n' "$f" "$matches"
    viol=$((viol + 1))
  fi
done < <(git -C "$ROOT" ls-files '*.sh' 2>/dev/null)

if [ "$viol" -gt 0 ]; then
  echo ""
  echo "FAIL: $viol file(s) have a grep var-needle missing the -- separator (#156)."
  echo "  Fix: use assert_grep (plugins/issue-driven-dev/scripts/lib/assert-helpers.sh),"
  echo "       or add -- before the needle: grep -qF -- \"\$needle\"."
  echo "  False positive (the var is a FILE arg, not the pattern)? append  # lint-ok: grep-sep"
  exit 1
fi
echo "PASS: no grep var-needle missing the -- separator."
exit 0
