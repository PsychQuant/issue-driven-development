#!/usr/bin/env bash
# test.sh — aggregator self-tests (#217): pass / fail / timeout branches.
# NOTE: lives OUTSIDE the aggregator's default sweep only logically — the
# aggregator WILL run this suite too; the fixtures below use IDD_TESTS_DIR to
# point the aggregator at a sandbox, so no recursion occurs.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGG="$HERE/../../run-all-tests.sh"
. "$HERE/../../lib/assert-helpers.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

mk_suite() { # name body
  mkdir -p "$W/tests/$1"
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$W/tests/$1/test.sh"
}

# all-pass → exit 0
mk_suite ok 'exit 0'
IDD_TESTS_DIR="$W/tests" bash "$AGG" > "$W/out1" 2>&1
assert_exit "all-pass → 0" 0 $?
assert_grep "summary lists suite" "ok" "$(cat "$W/out1")"

# one failing → exit 1 + tail surfaced
mk_suite bad 'echo boom-detail; exit 1'
IDD_TESTS_DIR="$W/tests" bash "$AGG" > "$W/out2" 2>&1
assert_exit "any-fail → 1" 1 $?
assert_grep "failing tail surfaced" "boom-detail" "$(cat "$W/out2")"

# hung suite → timeout branch, aggregator still completes
rm -rf "$W/tests/bad"
mk_suite hang 'sleep 30'
IDD_TESTS_DIR="$W/tests" IDD_SUITE_TIMEOUT=2 bash "$AGG" > "$W/out3" 2>&1
assert_exit "hung suite → 1 (timeout)" 1 $?
assert_grep "timeout verdict shown" "TIMEOUT" "$(cat "$W/out3")"

# a suite's own `timeout` file raises its limit above the global one (#399)
rm -rf "$W/tests/hang"
mk_suite slow 'sleep 3'
printf '20\n' > "$W/tests/slow/timeout"
IDD_TESTS_DIR="$W/tests" IDD_SUITE_TIMEOUT=1 bash "$AGG" > "$W/out5" 2>&1
assert_exit "suite timeout file raises the limit → 0" 0 $?
# ...and never lowers it below the global one
printf '1\n' > "$W/tests/slow/timeout"
IDD_TESTS_DIR="$W/tests" IDD_SUITE_TIMEOUT=20 bash "$AGG" > "$W/out6" 2>&1
assert_exit "suite timeout file never lowers the limit → 0" 0 $?

# empty dir → non-zero (zero suites must not read as success)
mkdir -p "$W/empty"
IDD_TESTS_DIR="$W/empty" bash "$AGG" > "$W/out4" 2>&1
assert_exit "zero suites → non-zero" 1 $?

print_summary "run-all-tests-self"
