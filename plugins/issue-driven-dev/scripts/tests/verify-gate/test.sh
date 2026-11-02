#!/usr/bin/env bash
# verify-gate suite (#392) — scripts/verify-gate.py reads one verify master
# comment AS GITHUB RENDERS IT and decides whether /idd-all may merge and close.
#
# Inputs: fixtures/*.md are the comments as written; fixtures/*.html are
# GitHub's rendering of them (render-fixtures.sh, committed). The gate reads
# only the .html, the way close-stage.py hands it a comment's body_html.
#
# Contract (design.md of change idd-all-merge-and-close, Implementation Contract):
#   stdout  one JSON line {status, verdict, blocking, in_scope, follow_up, rejected, reason}
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
  out=$(python3 "$GATE" --html-file "$FX/${fixture%.md}.html" 2>/dev/null); rc=$?
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
# #392 verify r1 (logic #40): FAIL with only Follow-up rows contradicts itself, like PASS with a Blocking row
run_gate "FAIL verdict with only Follow-up rows" fail-verdict.md unparseable 2
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
reason_has "PASS with Blocking: reason" "blocking"
run_gate "PASS whose own line admits a Blocking row" pass-with-blocking-stated.md unparseable 2
reason_has "PASS admitting Blocking: reason" "contradict"
run_gate "two verdict lines" two-verdicts.md unparseable 2
run_gate "unfilled PASS / FAIL template" template-verdict.md unparseable 2
run_gate "CONDITIONAL verdict" conditional.md unparseable 2

# round 1 of #392's verify: layouts that used to read as clean
run_gate "a findings row after a blank line is outside the table" interrupted-table.md unparseable 2
reason_has "interrupted table: reason" "outside"
run_gate "a GFM row without a leading pipe still counts" no-leading-pipe.md not_clean 1 0 1 1
run_gate "a four-backtick fence is not closed by three backticks (GitHub draws the Blocking table after it)" fence-length.md unparseable 2
run_gate "a tilde line inside a backtick fence does not close it" fence-tilde-inside.md not_clean 1 0 1 0
# An unclosed fence runs to the end of the comment: GitHub shows the rest as code, and so does the gate.
run_gate "an unclosed fence after an empty findings table" unclosed-fence.md clean 0 0 0 0
run_gate "an Action header with decoration" action-header-variant.md unparseable 2
run_gate "a one-dash GFM divider" short-divider.md not_clean 1 0 1 0
run_gate "FAIL with no Blocking and no In-scope fix row" fail-no-findings.md unparseable 2
reason_has "FAIL without findings: reason" "contradict"

# --expect-sha: the report must name the commit it reviewed
SHA=78e32898e75243a3b6895568adff8b1ae7949824
run_gate_x() { # name fixture status exit args...
  local name="$1" fixture="$2" want_status="$3" want_exit="$4"; shift 4
  local out rc
  out=$(python3 "$GATE" --html-file "$FX/${fixture%.md}.html" "$@" 2>/dev/null); rc=$?
  assert_eq "$name: status" "$want_status" "$(printf '%s' "$out" | json_field status)"
  assert_exit "$name: exit" "$want_exit" "$rc"
  LAST_OUT="$out"
}
run_gate_x "Reviewed line equals the expected commit" reviewed-ok.md clean 0 --expect-sha "$SHA"
# #392 verify r2 (security #58): the contract asks for the full commit, so a prefix no longer passes
run_gate_x "a 7-character Reviewed prefix is not enough" reviewed-short.md unparseable 2 --expect-sha "$SHA"
run_gate_x "Reviewed names another commit" reviewed-other.md unparseable 2 --expect-sha "$SHA"
reason_has "another commit: reason" "Reviewed"
run_gate_x "two Reviewed lines" reviewed-twice.md unparseable 2 --expect-sha "$SHA"
run_gate_x "no Reviewed line while a commit is expected" clean-empty.md unparseable 2 --expect-sha "$SHA"
run_gate_x "without --expect-sha the Reviewed line is not required" clean-empty.md clean 0
# #392 verify r2: the verdict line's own count, tables where Action is not last, the reviewed range
run_gate "the verdict line says 1 blocking but the table has none" verdict-count-mismatch.md unparseable 2
reason_has "verdict count: reason" "blocking"
run_gate "a verdict line without a blocking count" verdict-no-count.md unparseable 2
run_gate "a table whose Action column is not last" action-not-last.md unparseable 2
run_gate "a table with a column after Action" action-then-owner.md unparseable 2
BASE=4fbc947aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
run_gate_x "a Reviewed range whose head and base match" reviewed-range.md clean 0 --expect-sha "$SHA" --expect-base "$BASE"
run_gate_x "a Reviewed range is accepted without --expect-base" reviewed-range.md clean 0 --expect-sha "$SHA"
run_gate_x "a Reviewed range with another base" reviewed-range-otherbase.md unparseable 2 --expect-sha "$SHA" --expect-base "$BASE"
reason_has "another base: reason" "range"
run_gate_x "a single Reviewed commit when a base is expected" reviewed-ok.md unparseable 2 --expect-sha "$SHA" --expect-base "$BASE"
python3 "$GATE" --html-file "$FX/reviewed-ok.html" --expect-base "$BASE" >/dev/null 2>&1; rc=$?
assert_exit "--expect-base without --expect-sha: exit" 64 "$rc"
# #392 verify r3/r4: what GitHub draws is what counts — HTML blocks, fences, comments
run_gate "a Blocking table GitHub draws after an HTML block" html-details.md unparseable 2
reason_has "HTML block: reason" "blocking"
run_gate "a multi-line HTML comment is hidden by GitHub" html-comment-multiline.md clean 0 0 0 0
run_gate "a one-line HTML comment is fine" html-comment-oneline.md clean 0 0 0 0
run_gate "the verdict line states the blocking count twice" verdict-duplicate-count.md unparseable 2
run_gate "the three-bucket verdict line" verdict-three-buckets.md not_clean 1 0 2 1
python3 "$GATE" --html-file "$FX/reviewed-ok.html" --expect-sha not-a-sha >/dev/null 2>&1; rc=$?
assert_exit "--expect-sha that is not hex: exit" 64 "$rc"

# #392 verify r4: layouts GitHub draws as a Blocking table that a markdown parser missed
run_gate "a CommonMark type-4 HTML block toggles no fence (r4 #11)" html-type4.md unparseable 2
reason_has "type-4 HTML block: reason" "blocking"
run_gate "a fence inside a list item ends with the item (r4 #12)" list-fence.md unparseable 2
run_gate "a raw table on a one-line comment line (r4 #14)" oneline-comment-table.md unparseable 2
run_gate "a continuation row and an annotated Blocking row (r4 #21)" continuation-row.md unparseable 2
run_gate "a Blocking table inside a collapsed details block" details-blocking.md unparseable 2
run_gate "the verdict line inside a quote" verdict-in-quote.md unparseable 2
reason_has "quoted verdict: reason" "quote"
# Proposed Corrections keep their <details> replacement text (r4 #17)
run_gate "Proposed Corrections with a details block" corrections-details.md clean 0 0 0 1
# Rejected findings stay in the table and are counted (r4 #7)
run_gate "a Rejected row, stated in the verdict line" rejected.md clean 0 0 0 1
assert_eq "Rejected row: rejected count" "1" "$(printf '%s' "$LAST_OUT" | json_field rejected)"
run_gate "a Rejected row the verdict line does not state" rejected-unstated.md unparseable 2
reason_has "unstated rejected: reason" "rejected"
# The coverage line
run_gate "PASS with 3 / 5 requirements addressed" coverage-short.md unparseable 2
run_gate "PASS with 5 / 5 requirements addressed" coverage-full.md clean 0 0 0 0

# #392 verify r5: rows and verdicts GitHub shows outside a paragraph; signals the close stage stops on
run_gate "a findings row in a tight list item (r5 #3)" list-orphan-row.md unparseable 2
reason_has "list row: reason" "outside a findings table"
run_gate "a findings row as raw text in a details block (r5 #3)" details-raw-row.md unparseable 2
run_gate "a second verdict in a list item (r5 #10)" verdict-in-list.md unparseable 2
run_gate "a HIGH finding filed as Follow-up is reported (r5 #4)" high-followup.md clean 0 0 0 2
assert_eq "HIGH Follow-up: high_follow_up count" "1" "$(printf '%s' "$LAST_OUT" | json_field high_follow_up)"
run_gate "a Process Gaps section is reported (r5 #22)" process-gaps.md clean 0 0 0 0
assert_eq "Process Gaps: flag" "True" "$(printf '%s' "$LAST_OUT" | json_field process_gaps)"
run_gate "a clean report without a coverage line (r5 #41)" coverage-missing.md unparseable 2
reason_has "missing coverage: reason" "coverage"

run_gate "a Blocking heading outside a table (r6 #17)" heading-blocking.md unparseable 2
run_gate "a findings table without Severity (r6 #11)" no-severity.md unparseable 2

# every .md fixture has its rendering committed
for md in "$FX"/*.md; do
  assert_file_exists "rendered: $(basename "$md")" "${md%.md}.html"
done

# file and usage errors
out=$(python3 "$GATE" --html-file "$FX/does-not-exist.html" 2>/dev/null); rc=$?
assert_eq "missing file: status" "unparseable" "$(printf '%s' "$out" | json_field status)"
assert_exit "missing file: exit" 2 "$rc"
python3 "$GATE" >/dev/null 2>&1; rc=$?
assert_exit "no arguments: exit" 64 "$rc"
python3 "$GATE" --html-file >/dev/null 2>&1; rc=$?
assert_exit "--html-file without a value: exit" 64 "$rc"
python3 "$GATE" --comment-file "$FX/clean-empty.md" >/dev/null 2>&1; rc=$?
assert_exit "the markdown input flag is gone: exit" 64 "$rc"
python3 "$GATE" --bogus x >/dev/null 2>&1; rc=$?
assert_exit "unknown flag: exit" 64 "$rc"

print_summary
