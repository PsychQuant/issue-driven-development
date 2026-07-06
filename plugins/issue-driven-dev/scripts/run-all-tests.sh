#!/usr/bin/env bash
# run-all-tests.sh — aggregate entry for every fixture suite under
# scripts/tests/*/test.sh (#217). This is the missing enforcement link for the
# repo's drift-guard hard locks: suites existed but nothing ran them
# automatically (#214 R2 DA finding 15).
#
# Behavior:
#   - runs EVERY suite (no fail-fast) and prints a per-suite summary table
#   - per-suite timeout (default 180s, IDD_SUITE_TIMEOUT to override) so a
#     hung suite (FIFO writer class, #117 incident) cannot wedge CI
#   - exit 0 iff every suite passed; 1 otherwise
#
# Env:
#   IDD_TESTS_DIR      override the suites dir (aggregator self-tests use this)
#   IDD_SUITE_TIMEOUT  per-suite seconds (default 180)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="${IDD_TESTS_DIR:-$HERE/tests}"
SUITE_TIMEOUT="${IDD_SUITE_TIMEOUT:-180}"

if [ ! -d "$TESTS_DIR" ]; then
  echo "✗ tests dir not found: $TESTS_DIR" >&2
  exit 2
fi

run_with_timeout() { # seconds cmd... — portable watchdog (macOS has no coreutils timeout)
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
    return $?
  fi
  "$@" &
  local pid=$!
  ( sleep "$secs"; kill -TERM "$pid" 2>/dev/null ) &
  local wd=$!
  wait "$pid" 2>/dev/null
  local rc=$?
  kill -TERM "$wd" 2>/dev/null; wait "$wd" 2>/dev/null
  return $rc
}

TOTAL=0; FAILED=0
declare -a ROWS=()
shopt -s nullglob
for t in "$TESTS_DIR"/*/test.sh; do
  name="$(basename "$(dirname "$t")")"
  TOTAL=$((TOTAL + 1))
  start=$(date +%s)
  if run_with_timeout "$SUITE_TIMEOUT" bash "$t" > /tmp/idd-suite-"$name".log 2>&1; then
    rc=0; verdict="PASS"
  else
    rc=$?; FAILED=$((FAILED + 1))
    if [ "$rc" -ge 124 ]; then verdict="TIMEOUT(${SUITE_TIMEOUT}s)"; else verdict="FAIL(rc=$rc)"; fi
  fi
  dur=$(( $(date +%s) - start ))
  ROWS+=("$(printf '%-32s %-14s %3ss' "$name" "$verdict" "$dur")")
  # surface the tail of failing suites immediately (CI log ergonomics)
  [ "$rc" -ne 0 ] && { echo "── $name output tail ──"; tail -15 /tmp/idd-suite-"$name".log; echo; }
done
shopt -u nullglob

echo "══════ run-all-tests summary ══════"
printf '%s\n' "${ROWS[@]:-"(no suites found)"}"
echo "───────────────────────────────────"
echo "suites: $TOTAL, failed: $FAILED"
[ "$TOTAL" -gt 0 ] && [ "$FAILED" -eq 0 ]
