#!/usr/bin/env bash
# assert-helpers.sh — shared assertion helpers for IDD test runners.
# (PsychQuant/issue-driven-development#156)
#
# Source this from a test runner:
#   . "$(dirname "${BASH_SOURCE[0]}")/../../lib/assert-helpers.sh"
# then use the assert_* / require / refute helpers, and call print_summary at
# the end (its exit code is the suite's pass/fail).
#
# Two assertion families, because the runners legitimately use both shapes:
#   - value-comparison : assert_eq / assert_exit         (idd-worktree style)
#   - command-success  : require / refute / assert_true  (check-closed style)
# plus the class-closing grep helpers (assert_grep / refute_grep) which bake in
# the `--` end-of-options separator so a `--`-prefixed needle can never be
# misparsed as a grep flag — the #154/#160 bug class, made unrepresentable.
#
# EVAL-CONTENT BAN (#188, detonated in #186 f4b): with the eval family
# (assert_true), never interpolate captured output into the eval string —
# output containing a literal $VAR (e.g. a script printing
# "$CLAUDE_PLUGIN_ROOT/...") gets RE-EXPANDED by eval and explodes under the
# runner's `set -u` (unbound variable → the assertion false-FAILs). Safe forms:
#   - write output to a file, then assert_output_grep / refute_output_grep
#   - or assert_grep "name" "$needle" "$captured"   (string haystack, no eval)
# assert_true is for command CONDITIONS you author, never for data you captured.
#
# Counters are module-level (PASS / FAIL / FAILURES); the sourcing runner does
# not declare them. `set -u`-safe.

PASS=0
FAIL=0
FAILURES=()

pass() { PASS=$((PASS + 1)); printf '  ✓ %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); FAILURES+=("$1"); printf '  ✗ %s\n     %s\n' "$1" "${2:-}"; }

# ── value-comparison family ──
assert_eq() { # name expected actual
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected [$2] got [$3]"; fi
}
assert_exit() { # name expected_code actual_code
  if [ "$2" = "$3" ]; then pass "$1"; else fail "$1" "expected exit $2 got $3"; fi
}

# ── command-success family ──
# require: the command MUST succeed (exit 0). refute: it MUST fail (non-zero).
# assert_true is kept as a backward-compatible alias of require (idd-worktree).
require()     { local n="$1"; shift; if "$@";      then pass "$n"; else fail "$n" "expected success: $*"; fi; }
refute()      { local n="$1"; shift; if "$@";      then fail "$n" "expected failure: $*"; else pass "$n"; fi; }
assert_true() { local n="$1"; shift; if eval "$@"; then pass "$n"; else fail "$n" "condition false: $*"; fi; }

# ── grep family (`--`-safe by construction — #156 closes the #154/#160 class) ──
# assert_grep   : haystack MUST contain needle (fixed-string).  refute_grep: MUST NOT.
# The `-- "$needle"` is the whole point: a needle like "--state closed" is matched
# as data, never parsed as an option. Pass the haystack as $3 (a string) — it is
# fed to grep on stdin, so no needle/haystack ever reaches the shell as an argv flag.
assert_grep() { # name needle haystack
  if printf '%s\n' "$3" | grep -qF -- "$2"; then pass "$1"; else fail "$1" "needle not found: [$2]"; fi
}
refute_grep() { # name needle haystack
  if printf '%s\n' "$3" | grep -qF -- "$2"; then fail "$1" "needle unexpectedly found: [$2]"; else pass "$1"; fi
}
# Regex variant when the needle is an ERE pattern (still `--`-safe for the pattern).
assert_grep_re() { # name ere_pattern haystack
  if printf '%s\n' "$3" | grep -qE -- "$2"; then pass "$1"; else fail "$1" "pattern not matched: [$2]"; fi
}

# ── output-file grep family (#188 — the safe form for captured output) ──
# assert_output_grep : file MUST contain needle (fixed-string, `--`-safe).
# refute_output_grep : file MUST NOT contain needle.
# Reading via grep FILE (no eval, no interpolation) keeps literal $VAR content
# in the output inert. A missing/unreadable file FAILS loudly on both helpers —
# an unreadable capture is a broken test, never a silent pass.
assert_output_grep() { # name needle file
  if [ ! -r "$3" ]; then fail "$1" "output file missing/unreadable: $3"; return; fi
  if grep -qF -- "$2" "$3"; then pass "$1"; else fail "$1" "needle not found in $3: [$2]"; fi
}
refute_output_grep() { # name needle file
  if [ ! -r "$3" ]; then fail "$1" "output file missing/unreadable: $3"; return; fi
  if grep -qF -- "$2" "$3"; then fail "$1" "needle unexpectedly found in $3: [$2]"; else pass "$1"; fi
}

# ── filesystem family ──
assert_file_exists() { # name path
  if [ -e "$2" ]; then pass "$1"; else fail "$1" "missing: $2"; fi
}
assert_file_absent() { # name path
  if [ ! -e "$2" ]; then pass "$1"; else fail "$1" "should not exist: $2"; fi
}

# ── summary ── call at end of suite; exit code = 0 iff all passed.
print_summary() { # [suite-label]
  printf '\n─── %s ───\n' "${1:-Summary}"
  printf 'PASS: %s\nFAIL: %s\n' "$PASS" "$FAIL"
  if [ "$FAIL" -gt 0 ]; then
    printf 'Failed: %s\n' "${FAILURES[*]}"
    return 1
  fi
  return 0
}
