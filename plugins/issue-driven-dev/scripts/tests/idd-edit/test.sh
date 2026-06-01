#!/usr/bin/env bash
# Test runner for plugins/issue-driven-dev/scripts/idd-edit-helper.sh
#
# Each fixture in fixtures/<NN-name>/ provides:
#   - subcmd.txt         — subcommand to run (parse-args / validate-target / section-replace)
#   - args.txt           — args to pass (one per line; supports __FIXTURE_PATH__ placeholder)
#   - expected_exit.txt  — expected exit code
#   - expected_stderr_contains.txt  (optional) — substrings that MUST appear in stderr
#   - expected_stdout.txt           (optional) — exact stdout match (only for section-replace)
#   - expected_stdout_contains.txt  (optional) — substrings that MUST appear in stdout
#
# Exit 0 if all tests pass; 1 otherwise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Path: plugins/issue-driven-dev/scripts/tests/idd-edit/ → 5 levels deep
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
TARGET_SCRIPT="$REPO_ROOT/plugins/issue-driven-dev/scripts/idd-edit-helper.py"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

if [ ! -f "$TARGET_SCRIPT" ]; then
    echo "ERROR: target script not found: $TARGET_SCRIPT" >&2
    exit 1
fi

# Fixture 23 (--body-file escape-hatch on an allowed /tmp path) references a
# safe file that must exist and be readable at runtime. Create it as test
# setup (not comparison logic) and clean it up on exit.
FIXTURE23_FILE="/tmp/idd-edit-fixture-23-safe.md"
printf 'safe content' > "$FIXTURE23_FILE"
trap 'rm -f "$FIXTURE23_FILE"' EXIT

PASS=0
FAIL=0
FAILED_TESTS=()

for fixture in "$FIXTURES_DIR"/*/; do
    name=$(basename "$fixture")
    fixture_abs=$(cd "$fixture" && pwd)

    if [ ! -f "$fixture/subcmd.txt" ] || [ ! -f "$fixture/args.txt" ] || [ ! -f "$fixture/expected_exit.txt" ]; then
        echo "SKIP   $name (missing subcmd.txt/args.txt/expected_exit.txt)"
        continue
    fi

    subcmd=$(cat "$fixture/subcmd.txt")
    expected_exit=$(cat "$fixture/expected_exit.txt" | tr -d '[:space:]')

    # Build args array — read one line per arg, substitute placeholder
    args=()
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line//__FIXTURE_PATH__/$fixture_abs}"
        args+=("$line")
    done < "$fixture/args.txt"

    # Auto-discover mock_*.json file for validate-target fixtures (closes #154 H3).
    # When fixture dir contains a mock_*.json, run target with
    # IDD_EDIT_HELPER_GH_MOCK pointing at it (helper reads mock instead of gh api).
    # Use shell glob (with nullglob via set + array) rather than `ls | head` pipe
    # (pipefail makes ls-no-match abort the script).
    #
    # R2 H8 fix: also set IDD_EDIT_HELPER_TEST_MODE=1 — helper gates mock var
    # behind test-mode to prevent production R5 bypass via attacker-crafted env.
    # Exception: fixture 21 deliberately omits TEST_MODE to verify the gate refuses.
    mock_env=""
    for cand in "$fixture"/mock_*.json; do
        if [ -f "$cand" ]; then
            if [ -f "$fixture/no_test_mode_flag" ]; then
                # Test-the-gate fixtures (e.g. 21) — set mock but NOT test-mode
                mock_env="IDD_EDIT_HELPER_GH_MOCK=$cand"
            else
                mock_env="IDD_EDIT_HELPER_GH_MOCK=$cand IDD_EDIT_HELPER_TEST_MODE=1"
            fi
            break
        fi
    done

    # Run target script, capture stdout + stderr + exit.
    # Script-level: `set -uo pipefail` only (NO `set -e`) — fixtures testing
    # refuse paths expect non-zero exit codes; $? captures regardless.
    actual_stdout=$(env $mock_env python3 "$TARGET_SCRIPT" "$subcmd" "${args[@]+"${args[@]}"}" 2>"/tmp/idd-edit-test-stderr-$$")
    actual_exit=$?
    actual_stderr=$(cat "/tmp/idd-edit-test-stderr-$$")
    rm -f "/tmp/idd-edit-test-stderr-$$"

    # Assertions
    local_pass=true
    failure_reasons=()

    # Exit code
    if [ "$actual_exit" != "$expected_exit" ]; then
        local_pass=false
        failure_reasons+=("exit code: expected=$expected_exit actual=$actual_exit")
    fi

    # Stderr contains (use -- to handle needles starting with --)
    if [ -f "$fixture/expected_stderr_contains.txt" ]; then
        while IFS= read -r needle || [ -n "$needle" ]; do
            [ -z "$needle" ] && continue
            if ! echo "$actual_stderr" | grep -qF -- "$needle"; then
                local_pass=false
                failure_reasons+=("stderr missing: $needle")
            fi
        done < "$fixture/expected_stderr_contains.txt"
    fi

    # Stdout exact
    if [ -f "$fixture/expected_stdout.txt" ]; then
        expected_stdout=$(cat "$fixture/expected_stdout.txt")
        if [ "$actual_stdout" != "$expected_stdout" ]; then
            local_pass=false
            failure_reasons+=("stdout mismatch (see diff below)")
        fi
    fi

    # Stdout contains (use -- to handle needles starting with --)
    if [ -f "$fixture/expected_stdout_contains.txt" ]; then
        while IFS= read -r needle || [ -n "$needle" ]; do
            [ -z "$needle" ] && continue
            if ! echo "$actual_stdout" | grep -qF -- "$needle"; then
                local_pass=false
                failure_reasons+=("stdout missing: $needle")
            fi
        done < "$fixture/expected_stdout_contains.txt"
    fi

    if [ "$local_pass" = "true" ]; then
        echo "PASS   $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL   $name"
        for r in "${failure_reasons[@]}"; do
            echo "       → $r"
        done
        # Diff for visibility on stdout mismatch
        if [ -f "$fixture/expected_stdout.txt" ] && [ "$actual_stdout" != "$(cat "$fixture/expected_stdout.txt")" ]; then
            echo "       expected stdout:"
            sed 's/^/         /' "$fixture/expected_stdout.txt"
            echo "       actual stdout:"
            echo "$actual_stdout" | sed 's/^/         /'
        fi
        echo "       stderr:"
        echo "$actual_stderr" | sed 's/^/         /'
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$name")
    fi
done

echo ""
echo "================================"
echo "Results: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
    echo "Failed tests:"
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t"
    done
    exit 1
fi
exit 0
