#!/usr/bin/env bash
# Test runner for .claude/scripts/idd-edit-helper.sh
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
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
TARGET_SCRIPT="$REPO_ROOT/.claude/scripts/idd-edit-helper.sh"
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

    # Run target script, capture stdout + stderr + exit
    set +e
    actual_stdout=$("$TARGET_SCRIPT" "$subcmd" "${args[@]+"${args[@]}"}" 2>"/tmp/idd-edit-test-stderr-$$")
    actual_exit=$?
    actual_stderr=$(cat "/tmp/idd-edit-test-stderr-$$")
    rm -f "/tmp/idd-edit-test-stderr-$$"
    set -e

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
