#!/usr/bin/env bash
# Unit-test runner for spectra-archive-post-ic.sh
#
# Each fixture in fixtures/<NN-name>/ provides:
#   - archive/proposal.md (+ design.md / tasks.md as needed)
#   - args.txt        — args to pass (with __FIXTURE_PATH__ placeholder)
#   - expected_stdout.txt
#   - expected_exit.txt
#   - post_assert.txt (optional) — additional assertions after run
#
# Each test run:
#   1. Substitute __FIXTURE_PATH__ in args.txt → actual fixture path
#   2. Invoke script with those args
#   3. Compare actual stdout + exit code against expected
#   4. Apply post_assert (must_not_exist <path> currently supported)
#
# Exit 0 if all tests pass; exit 1 otherwise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
TARGET_SCRIPT="$REPO_ROOT/.claude/scripts/spectra-archive-post-ic.sh"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

if [ ! -x "$TARGET_SCRIPT" ]; then
  echo "ERROR: target script not executable: $TARGET_SCRIPT" >&2
  exit 1
fi

PASS=0
FAIL=0
FAILED_TESTS=()

for fixture in "$FIXTURES_DIR"/*/; do
  name=$(basename "$fixture")
  fixture_abs=$(cd "$fixture" && pwd)

  # Skip if missing required files
  if [ ! -f "$fixture/args.txt" ] || [ ! -f "$fixture/expected_stdout.txt" ] || [ ! -f "$fixture/expected_exit.txt" ]; then
    echo "SKIP   $name (missing args.txt / expected_stdout.txt / expected_exit.txt)"
    continue
  fi

  # Build args (substitute __FIXTURE_PATH__)
  raw_args=$(cat "$fixture/args.txt")
  args="${raw_args//__FIXTURE_PATH__/$fixture_abs}"

  # Clean any leftover artifacts from prior runs
  rm -f /tmp/spectra-archive-candidates.txt /tmp/spectra-archive-ic-dryrun-body.md /tmp/pwn-fixture-05

  # Run script from /tmp (non-git cwd) so script's git log Fallback 3 can't find
  # commits referencing the fixtures themselves. Fixtures use absolute paths via
  # __FIXTURE_PATH__ substitution, so cwd change is safe.
  #
  # Parse args via array splitting (NOT eval) so malicious args.txt content cannot
  # achieve RCE on the test machine (R3-S1 finding from /idd-verify #56 R3 verify
  # report). `read -ra` populates the array using bash's standard word-splitting
  # rules + respects single-quoted segments, e.g. 'evil$(echo)' stays literal
  # (verified by fixture 07).
  read -ra args_array <<<"$args"
  actual_stdout=$(cd /tmp && bash "$TARGET_SCRIPT" "${args_array[@]}" 2>/dev/null)
  actual_exit=$?

  # Expected values
  expected_stdout=$(cat "$fixture/expected_stdout.txt")
  expected_exit=$(cat "$fixture/expected_exit.txt")

  # Compare
  PASS_STDOUT=0
  PASS_EXIT=0
  PASS_POST=1

  if [ "$actual_stdout" = "$expected_stdout" ]; then
    PASS_STDOUT=1
  fi

  if [ "$actual_exit" = "$expected_exit" ]; then
    PASS_EXIT=1
  fi

  # Apply post-assertions (e.g., "must_not_exist /tmp/pwn-fixture-05")
  if [ -f "$fixture/post_assert.txt" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      cmd=$(echo "$line" | awk '{print $1}')
      target=$(echo "$line" | awk '{print $2}')
      case "$cmd" in
        must_not_exist)
          if [ -e "$target" ]; then
            PASS_POST=0
            echo "         post_assert FAIL: $target should not exist"
          fi
          ;;
        must_exist)
          if [ ! -e "$target" ]; then
            PASS_POST=0
            echo "         post_assert FAIL: $target should exist"
          fi
          ;;
        *)
          echo "         post_assert UNKNOWN command: $cmd"
          PASS_POST=0
          ;;
      esac
    done < "$fixture/post_assert.txt"
  fi

  if [ "$PASS_STDOUT" = "1" ] && [ "$PASS_EXIT" = "1" ] && [ "$PASS_POST" = "1" ]; then
    echo "PASS   $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL   $name"
    if [ "$PASS_STDOUT" = "0" ]; then
      echo "         stdout expected: $expected_stdout"
      echo "         stdout actual:   $actual_stdout"
    fi
    if [ "$PASS_EXIT" = "0" ]; then
      echo "         exit expected: $expected_exit"
      echo "         exit actual:   $actual_exit"
    fi
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$name")
  fi
done

echo ""
echo "─── Summary ───"
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed tests: ${FAILED_TESTS[*]}"
  exit 1
fi
exit 0
