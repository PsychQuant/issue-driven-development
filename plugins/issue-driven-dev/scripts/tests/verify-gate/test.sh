#!/usr/bin/env bash
# verify-gate suite (#392) — scripts/verify-gate.py reads one verify master
# comment and decides whether /idd-all may merge and close.
#
# Contract (design.md of change idd-all-merge-and-close, Implementation Contract):
#   stdout  one JSON line {status, verdict, blocking, in_scope, follow_up, reason}
#   exit    clean 0 · not_clean 1 · unparseable 2 (also: file unreadable) · usage 64
# The gate fails closed: anything it cannot read, or that contradicts itself,
# is `unparseable`, never `clean`.
#
# Expected values below are literals written from the fixtures, not computed by
# the helper.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
GATE="$HERE/../../verify-gate.py"
FX="$HERE/fixtures"

json_field() { # field — read one field from the JSON on stdin; prints "<missing>" when absent
  python3 -c 'import json,sys
try:
    d=json.loads(sys.stdin.read())
except Exception:
    print("<not-json>"); sys.exit(0)
v=d.get(sys.argv[1],"<missing>")
print("null" if v is None else v)' "$1"
}

run_gate() { # name fixture expected_status expected_exit [blocking in_scope follow_up]
  local name="$1" fixture="$2" want_status="$3" want_exit="$4"
  local out rc
  out=$(python3 "$GATE" --comment-file "$FX/$fixture" 2>/dev/null); rc=$?
  assert_eq "$name: status" "$want_status" "$(printf '%s' "$out" | json_field status)"
  assert_exit "$name: exit" "$want_exit" "$rc"
  if [ $# -ge 7 ]; then
    assert_eq "$name: blocking" "$5" "$(printf '%s' "$out" | json_field blocking)"
    assert_eq "$name: in_scope" "$6" "$(printf '%s' "$out" | json_field in_scope)"
    assert_eq "$name: follow_up" "$7" "$(printf '%s' "$out" | json_field follow_up)"
  fi
  LAST_OUT="$out"
}

reason_has() { # name needle — the last run's reason mentions needle
  assert_grep "$1" "$2" "$(printf '%s' "$LAST_OUT" | json_field reason)"
}

echo "verify-gate:"
[ -f "$GATE" ] || echo "  (helper missing: $GATE — every case below fails)"

# clean
run_gate "PASS, empty findings table" clean-empty.md clean 0 0 0 0
run_gate "PASS, only Follow-up remains" followup-only.md clean 0 0 0 2
run_gate "bold Follow-up is still Follow-up" bold-value.md clean 0 0 0 1
run_gate "a table without an Action column is not a findings table" extra-table.md clean 0 0 0 1
run_gate "bold labels that are not verdicts are ignored" bold-labels.md clean 0 0 0 1

# not_clean
run_gate "Blocking finding" blocking.md not_clean 1 1 0 1
run_gate "In-scope fix findings" inscope.md not_clean 1 0 2 0
run_gate "FAIL verdict without Blocking rows" fail-verdict.md not_clean 1 0 0 1
run_gate "a template inside a code fence is ignored" fenced-template.md not_clean 1 1 0 0

# unparseable
run_gate "no findings table" no-table.md unparseable 2
reason_has "no findings table: reason" "table"
run_gate "no verdict line" no-verdict.md unparseable 2
reason_has "no verdict line: reason" "verdict"
run_gate "Action value outside the three classes" fourth-value.md unparseable 2
reason_has "fourth value: reason names it" "No action"
run_gate "annotated Action value" annotated-value.md unparseable 2
run_gate "empty Action cell" empty-action.md unparseable 2
run_gate "PASS verdict with a Blocking row" pass-with-blocking.md unparseable 2
reason_has "PASS with Blocking: reason" "contradict"
run_gate "two verdict lines" two-verdicts.md unparseable 2
run_gate "unfilled PASS / FAIL template" template-verdict.md unparseable 2
run_gate "CONDITIONAL verdict" conditional.md unparseable 2

# file and usage errors
out=$(python3 "$GATE" --comment-file "$FX/does-not-exist.md" 2>/dev/null); rc=$?
assert_eq "missing file: status" "unparseable" "$(printf '%s' "$out" | json_field status)"
assert_exit "missing file: exit" 2 "$rc"
python3 "$GATE" >/dev/null 2>&1; rc=$?
assert_exit "no arguments: exit" 64 "$rc"
python3 "$GATE" --comment-file >/dev/null 2>&1; rc=$?
assert_exit "--comment-file without a value: exit" 64 "$rc"
python3 "$GATE" --bogus x >/dev/null 2>&1; rc=$?
assert_exit "unknown flag: exit" 64 "$rc"

print_summary
