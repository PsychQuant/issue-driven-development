#!/usr/bin/env bash
# rest-queue suite (#478) — scripts/rest-queue.py decides which open issue /idd-all runs next
# when no issue was named, and keeps the state of that run.
#
# gh is replaced by fake-gh.py (answers from a scenario directory, logs every call).
# scenario.py writes the open issues of a scenario; bodies come from fixtures/*.md and
# GitHub's own rendering of them, fixtures/*.html (../verify-gate/render-fixtures.sh <paths>).

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
RQ="$HERE/../../rest-queue.py"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
SKILL="$PLUGIN/skills/idd-all/SKILL.md"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/idd-rest-queue-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
export IDD_CLOSE_STAGE_TEST=1 IDD_GH="$HERE/fake-gh.py"
REPO=o/r

new() { # name issue-spec… → S (scenario dir), G (gh answers), T (working tree)
  S="$WORK/$1"; G="$S/gh"; T="$S/tree"; shift
  mkdir -p "$G" "$T"
  export FAKE_GH_DIR="$G"
  python3 "$HERE/scenario.py" "$G" "$@"
}
issues() { python3 "$HERE/scenario.py" "$G" "$@"; }   # replace the open issues of the current scenario
rq() { python3 "$RQ" "$@"; }
run() { rq "$1" --cwd "$T" --repo "$REPO" "${@:2}"; }
jget() { # dotted.key → the value as compact JSON (strings unquoted); <missing> when absent
  python3 -c '
import json, sys
v = json.loads(sys.stdin.read() or "{}")
for k in sys.argv[1].split("."):
    v = v.get(k, "<missing>") if isinstance(v, dict) else "<missing>"
print(v if isinstance(v, str) else json.dumps(v, separators=(",", ":")))' "$1"
}
state_file() { printf '%s' "$T/.claude/.idd/state/idd-all-rest.json"; }
write_state() { # hours-since-last-activity attempts-json
  mkdir -p "$T/.claude/.idd/state"
  python3 - "$(state_file)" "$1" "$2" <<'PY'
import json, sys, time
path, hours, attempts = sys.argv[1], float(sys.argv[2]), json.loads(sys.argv[3])
stamp = lambda t: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))
at = time.time() - hours * 3600
for a in attempts:
    a.setdefault("handed_at", stamp(at)); a.setdefault("recorded_at", stamp(at)); a.setdefault("reason", "")
json.dump({"version": 1, "repo": "o/r", "started_at": stamp(at - 60), "updated_at": stamp(at),
           "attempts": attempts, "stop": None}, open(path, "w"))
PY
}

echo "── the two tables ──"
# spec-example: idd-all-rest / argument forms
# spec-example: idd-all-rest / class precedence
python3 "$HERE/tables_check.py" > "$WORK/tables.out" 2>&1; rc=$?
assert_exit "tables_check.py passes (argument forms, class precedence, 256 combinations)" 0 "$rc"
[ "$rc" = 0 ] || tail -20 "$WORK/tables.out"

OUT=$(rq args --); rc=$?
assert_exit "args: no argument exits 0" 0 "$rc"
assert_eq "args: no argument is rest" "rest" "$(printf '%s' "$OUT" | jget mode)"
OUT=$(rq args -- rest "#12"); rc=$?
assert_exit "args: rest with another positional exits 1" 1 "$rc"
assert_eq "args: rest with another positional is refused" "refuse" "$(printf '%s' "$OUT" | jget mode)"
assert_true "args: a refusal carries a reason" '[ "$(printf "%s" "$OUT" | jget reason)" != "<missing>" ]'
OUT=$(rq args -- "#12"); rc=$?
assert_exit "args: one issue exits 0" 0 "$rc"
assert_eq "args: one issue is other" "other" "$(printf '%s' "$OUT" | jget mode)"
OUT=$(rq args -- --reveiw); rc=$?
assert_exit "args: an unknown flag exits 1" 1 "$rc"
assert_eq "args: an unknown flag is refused" "refuse" "$(printf '%s' "$OUT" | jget mode)"

echo "── reading and ordering ──"
# spec-example: idd-all-rest / four candidates in run order
new order 9 12:diag=Simple 3 20:diag=Plan
OUT=$(rq list --repo "$REPO" --json); rc=$?
assert_exit "list: exits 0" 0 "$rc"
assert_eq "list: diagnosed candidates first, then by number" "[12,20,3,9]" "$(printf '%s' "$OUT" | jget order)"
assert_eq "list: the open count" "4" "$(printf '%s' "$OUT" | jget open)"

# fake gh self-check: two pages are two requests
new pages 1 2 3
echo 2 > "$G/page-size"
OUT=$(rq list --repo "$REPO" --json); rc=$?
assert_exit "list: three issues over two pages" 0 "$rc"
assert_eq "list: all three issues are read" "[1,2,3]" "$(printf '%s' "$OUT" | jget order)"
assert_eq "list: the query ran once per page" "2" "$(grep -c '"graphql"' "$G/calls.log")"

# spec-example: idd-all-rest / second page fails
new page-fail 1 2 3
echo 2 > "$G/page-size"; echo 2 > "$G/fail-page"
OUT=$(rq list --repo "$REPO" --json 2>"$S/err"); rc=$?
assert_exit "list: a failed page exits 3" 3 "$rc"
assert_eq "list: a failed page prints no list" "" "$OUT"
assert_true "list: a failed page says why on stderr" '[ -s "$S/err" ]'

# spec-example: idd-all-rest / Diagnosis older than the last 100 comments
new long 7:diag=Simple,comments=130 8
OUT=$(rq list --repo "$REPO" --json); rc=$?
assert_exit "list: an issue with 130 comments" 0 "$rc"
assert_eq "list: its old Diagnosis is found (actionable, not undiagnosed)" "[7]" "$(printf '%s' "$OUT" | jget diagnosed)"
assert_eq "list: and it runs before the undiagnosed issue" "[7,8]" "$(printf '%s' "$OUT" | jget order)"
assert_output_grep "list: all comments of #7 were read" "repos/o/r/issues/7/comments" "$G/calls.log"
refute_output_grep "list: comments of #8 were not read again" "repos/o/r/issues/8/comments" "$G/calls.log"

# every class from real inputs (the judgements come from actionability.sh, intent.py and ghread.py)
new classes 1:author=outsider 2:author=botty 3:author=none 4:editor=outsider 5:labels=epic \
  6:html=body-two-rows 7:labels=parking-lot 8:diag=parked 9:blocking=waiting-for-upstream 10:diag=meeting \
  11:html=body-verified 12:html=body-fenced-phase,diag=Plan 13 14:diag=Simple 15:labels=north-star
echo '{"permission": "read", "role_name": "read"}' > "$G/perm-outsider.json"
: > "$G/perm-botty.404"
OUT=$(rq list --repo "$REPO" --json); rc=$?
assert_exit "classes: exits 0" 0 "$rc"
assert_eq "classes: author (no write access, bot account, gone account, outsider edit)" "[1,2,3,4]" "$(printf '%s' "$OUT" | jget classes.author)"
assert_eq "classes: tracker" "[5,15]" "$(printf '%s' "$OUT" | jget classes.tracker)"
assert_eq "classes: needs-person" "[6]" "$(printf '%s' "$OUT" | jget classes.needs-person)"
assert_eq "classes: parked (label, and a deferral in Complexity)" "[7,8]" "$(printf '%s' "$OUT" | jget classes.parked)"
assert_eq "classes: blocked" "[9]" "$(printf '%s' "$OUT" | jget classes.blocked)"
assert_eq "classes: meeting" "[10]" "$(printf '%s' "$OUT" | jget classes.meeting)"
assert_eq "classes: verified" "[11]" "$(printf '%s' "$OUT" | jget classes.verified)"
assert_eq "classes: candidate (a Phase line inside a code block does not count)" "[12,13,14]" "$(printf '%s' "$OUT" | jget classes.candidate)"
assert_eq "classes: run order" "[12,14,13]" "$(printf '%s' "$OUT" | jget order)"
assert_eq "classes: both questions of #6 are listed" "2" "$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["questions"]["6"]))')"
assert_eq "classes: every issue is in exactly one class" "15" "$(printf '%s' "$OUT" | python3 -c 'import json,sys; c=json.load(sys.stdin)["classes"]; a=[n for v in c.values() for n in v]; print(len(a) if len(a)==len(set(a)) else "duplicates")')"

new perm500 1:author=flaky
: > "$G/perm-flaky.500"
OUT=$(rq list --repo "$REPO" --json 2>/dev/null); rc=$?
assert_exit "list: a permission read that fails (not 404) exits 3" 3 "$rc"
assert_eq "list: and prints no list" "" "$OUT"

new missing-field 1
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); del d[0]["bodyHTML"]; json.dump(d, open(p,"w"))' "$G/issues.json"
OUT=$(rq list --repo "$REPO" --json 2>/dev/null); rc=$?
assert_exit "list: a node without an expected field exits 3" 3 "$rc"
assert_eq "list: and prints no list" "" "$OUT"

echo "── open clarity rows ──"
# spec-example: idd-all-rest / two open rows and one resolved row
ROWS=$(python3 - "$PLUGIN/scripts/lib" "$HERE/fixtures" <<'PY'
import json, sys
sys.path.insert(0, sys.argv[1])
import intent
fx = sys.argv[2]
read = lambda n, e: open(f"{fx}/{n}.{e}", encoding="utf-8").read()
issue = {"body": read("body-three-rows", "md"), "body_html": read("body-three-rows", "html")}
rows = intent.open_clarity_rows(issue)
plain = {"body": read("body-verified", "md"), "body_html": read("body-verified", "html")}
print(json.dumps({"count": len(rows), "first": "first thing" in rows[0] if rows else False,
                  "second": "third thing" in rows[1] if len(rows) > 1 else False,
                  "single": intent.open_clarity_row(issue) == (rows[0] if rows else None),
                  "none": intent.open_clarity_rows(plain) == [] and intent.open_clarity_row(plain) is None}))
PY
)
assert_eq "clarity: two open rows, in document order, and the single-row function returns the first" \
  '{"count":2,"first":true,"second":true,"single":true,"none":true}' "$(printf '%s' "$ROWS" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), separators=(",",":")))')"

echo "── the run ──"
# spec-example: idd-all-rest / a spawned issue is picked up
new spawn 5 9
run start > "$S/start.out" 2>&1; rc=$?
assert_exit "spawn: start exits 0" 0 "$rc"
assert_eq "spawn: first next is #5" "5" "$(run next | jget next)"
assert_eq "spawn: #5 is recorded as stopped" "stopped" "$(run record --issue 5 --reason 'verify gate: not_clean' | jget outcome)"
assert_eq "spawn: next is #9" "9" "$(run next | jget next)"
issues 5 12; echo CLOSED > "$G/state-9"     # #9 was closed, #12 was opened during the run
assert_eq "spawn: #9 is recorded as closed" "closed" "$(run record --issue 9 | jget outcome)"
assert_eq "spawn: the new issue #12 is handed out" "12" "$(run next | jget next)"
run record --issue 12 --reason "stopped at the PR" > /dev/null
OUT=$(run next)
assert_eq "spawn: then the run is done" "true" "$(printf '%s' "$OUT" | jget done)"
assert_eq "spawn: and #5 is not handed out again" "null" "$(printf '%s' "$OUT" | jget next)"

# spec-example: idd-all-rest / the in-flight issue is repeated
new inflight 5 9
run start > /dev/null 2>&1
run next > /dev/null
OUT=$(run next)
assert_eq "in flight: the same issue is repeated" '{"next":5,"in_flight":true}' "$(printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps({"next": d["next"], "in_flight": d["in_flight"]}, separators=(",",":")))')"
assert_eq "in flight: the state holds one attempt" "1" "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["attempts"]))' "$(state_file)")"

# spec-example: idd-all-rest / outcomes by issue state
new out-closed 5
run start > /dev/null 2>&1; run next > /dev/null; echo CLOSED > "$G/state-5"
OUT=$(run record --issue 5)
assert_eq "outcome: CLOSED without a reason" "closed|" "$(printf '%s' "$OUT" | jget outcome)|$(printf '%s' "$OUT" | jget reason)"
new out-open-reason 5
run start > /dev/null 2>&1; run next > /dev/null
OUT=$(run record --issue 5 --reason "verify gate: not_clean")
assert_eq "outcome: OPEN with a reason" "stopped|verify gate: not_clean" "$(printf '%s' "$OUT" | jget outcome)|$(printf '%s' "$OUT" | jget reason)"
new out-open-none 5
run start > /dev/null 2>&1; run next > /dev/null
OUT=$(run record --issue 5)
assert_eq "outcome: OPEN without a reason" "stopped|no reason given" "$(printf '%s' "$OUT" | jget outcome)|$(printf '%s' "$OUT" | jget reason)"
new out-claimed 5
run start > /dev/null 2>&1; run next > /dev/null
OUT=$(run record --issue 5 --reason "merged and closed")
assert_eq "outcome: an open issue is stopped whatever the caller says" "stopped" "$(printf '%s' "$OUT" | jget outcome)"
new out-wrong 5 9
run start > /dev/null 2>&1; run next > /dev/null
cp "$(state_file)" "$S/before.json"
run record --issue 9 > /dev/null 2>&1; rc=$?
assert_exit "record: an issue that is not in flight exits 1" 1 "$rc"
require "record: and the state is unchanged" cmp -s "$S/before.json" "$(state_file)"

# spec-example: idd-all-rest / stop ends the run
new cont 5 9
run start > /dev/null 2>&1; run next > /dev/null; run record --issue 5 --reason x > /dev/null
assert_eq "one stopped issue does not end the run" "9" "$(run next | jget next)"
new stop 5 9
run start > /dev/null 2>&1; run next > /dev/null; run record --issue 5 --reason x > /dev/null
run stop --reason "default branch could not be fast-forwarded" > /dev/null 2>&1; rc=$?
assert_exit "stop: exits 0" 0 "$rc"
OUT=$(rq next --cwd "$T" --repo "$REPO")
assert_eq "stop: next names the reason and hands out nothing" '{"next":null,"stopped":"default branch could not be fast-forwarded"}' \
  "$(printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps({"next": d["next"], "stopped": d["stopped"]}, separators=(",",":")))')"
assert_eq "stop: #9 was not handed out" "1" "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["attempts"]))' "$(state_file)")"

# spec-example: idd-all-rest / resume within 24 hours
new resume 5 9
write_state 2 '[{"issue": 5, "outcome": "stopped", "reason": "verify gate: not_clean"}]'
run start > "$S/start.out" 2>&1; rc=$?
assert_exit "resume: start exits 0" 0 "$rc"
assert_output_grep "resume: start says the run is resumed" "resumed" "$S/start.out"
assert_output_grep "resume: with one attempt" "1 attempt" "$S/start.out"
assert_output_grep "resume: the list names issue numbers" "#9" "$S/start.out"
refute_output_grep "resume: the list prints no issue text" "SECRET-TITLE-TEXT" "$S/start.out"
assert_eq "resume: starting counts as activity (updated_at is now, not 2 hours ago)" "fresh" "$(python3 -c 'import calendar,json,sys,time; s=json.load(open(sys.argv[1])); t=calendar.timegm(time.strptime(s["updated_at"], "%Y-%m-%dT%H:%M:%SZ")); print("fresh" if time.time()-t < 300 else "stale")' "$(state_file)")"
assert_eq "resume: next is #9, not #5" "9" "$(run next | jget next)"
run start > /dev/null 2>&1    # a second start during the run
assert_eq "resume: a second start keeps the attempts" "2" "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["attempts"]))' "$(state_file)")"

# spec-example: idd-all-rest / a state older than 24 hours starts a new run
new expired 5 9
write_state 25 '[{"issue": 5, "outcome": "stopped", "reason": "verify gate: not_clean"}]'
run start > "$S/start.out" 2>&1
refute_output_grep "expired: start does not resume" "resumed" "$S/start.out"
assert_eq "expired: next is #5 again" "5" "$(run next | jget next)"

# spec-example: idd-all-rest / report with one closed, one stopped and one waiting issue
new report 5 9 14:html=body-two-rows
run start > /dev/null 2>&1
run next > /dev/null; issues 9 14:html=body-two-rows; echo CLOSED > "$G/state-5"; run record --issue 5 > /dev/null
run next > /dev/null; run record --issue 9 --reason "verify gate: not_clean" > /dev/null
run report > "$S/report.out" 2>&1; rc=$?
assert_exit "report: exits 0" 0 "$rc"
assert_true "report: #5 is under closed" 'grep -E "^closed \(1\): #5$" "$S/report.out" >/dev/null'
assert_output_grep "report: #9 with its reason" "#9 — verify gate: not_clean" "$S/report.out"
assert_output_grep "report: the first question of #14" "Does alpha include beta?" "$S/report.out"
assert_output_grep "report: the second question of #14" "Which file holds gamma?" "$S/report.out"
assert_file_absent "report: the run state is deleted" "$(state_file)"
run next > /dev/null 2>&1; rc=$?
assert_exit "report: a later next exits 1" 1 "$rc"

new report-unreadable 5
run start > /dev/null 2>&1; run next > /dev/null; run record --issue 5 --reason "stopped at the PR" > /dev/null
echo 1 > "$G/fail-page"
run report > "$S/report.out" 2>&1; rc=$?
assert_exit "report: still exits 0 when the list cannot be re-read" 0 "$rc"
assert_output_grep "report: the recorded result is still printed" "#5 — stopped at the PR" "$S/report.out"
assert_output_grep "report: and it says the list could not be read" "could not be read" "$S/report.out"
assert_file_absent "report: the run state is deleted" "$(state_file)"

echo "── refusals ──"
new norun 5
for sub in next record stop report; do
  case "$sub" in record) extra=(--issue 5) ;; stop) extra=(--reason x) ;; *) extra=() ;; esac
  if [ "$sub" = stop ]; then rq stop --cwd "$T" "${extra[@]}" > /dev/null 2>&1; rc=$?
  else run "$sub" ${extra[@]+"${extra[@]}"} > /dev/null 2>&1; rc=$?; fi
  assert_exit "no run: $sub exits 1" 1 "$rc"
done
rq next > /dev/null 2>&1; assert_exit "usage: next without arguments exits 2" 2 "$?"
rq bogus > /dev/null 2>&1; assert_exit "usage: an unknown subcommand exits 2" 2 "$?"
rq next --cwd "$T" --repo "not a repo" > /dev/null 2>&1; assert_exit "usage: a malformed repo exits 2" 2 "$?"
new symlink 5
mkdir -p "$S/elsewhere"; ln -s "$S/elsewhere" "$T/.claude"
run start > /dev/null 2>&1; rc=$?
assert_exit "start: refuses a state directory behind a symlink (exit 3)" 3 "$rc"
assert_true "start: and writes nothing through it" '[ -z "$(ls -A "$S/elsewhere")" ]'
new start-fail 5
echo 1 > "$G/fail-page"
run start > /dev/null 2>&1; rc=$?
assert_exit "start: exits 3 when the issues cannot be read" 3 "$rc"
assert_file_absent "start: and leaves no run state" "$(state_file)"

echo "── the skill ──"
# spec-example: idd-all-rest / the skill names the loop commands in order
STEP01=$(awk '/^#### Step 0\.1/{f=1} f&&/^#### Step 0\.2/{exit} f' "$SKILL")
REST=$(awk '/^## Rest mode/{f=1; print; next} f&&/^## /{exit} f' "$SKILL")
assert_grep "skill: Step 0.1 runs the argument classification" 'rest-queue.py" args' "$STEP01"
assert_grep_re "skill: Step 0.1 has a row for no positional argument" '^\| `/idd-all`[^|]*\| rest ' "$STEP01"
assert_grep_re "skill: Step 0.1 has a row for the word rest" '^\| `/idd-all rest`[^|]*\| rest ' "$STEP01"
refute_grep "skill: the two-way question is gone" "建新 issue 還是用既有 issue" "$(cat "$SKILL")"
assert_grep "skill: Step 0.1 says an unquoted description is one argument" "整段算一個引數" "$STEP01"
line_of() { printf '%s\n' "$REST" | grep -n -F -- "$1" | head -1 | cut -d: -f1; }
for sub in start next record stop report; do
  assert_true "skill: the rest section calls $sub" "[ -n \"\$(line_of 'rest-queue.py\" $sub')\" ]"
done
L_START=$(line_of 'rest-queue.py" start'); L_NEXT=$(line_of 'rest-queue.py" next')
L_RECORD=$(line_of 'rest-queue.py" record'); L_REPORT=$(line_of 'rest-queue.py" report')
L_STOP=$(line_of 'rest-queue.py" stop')
assert_true "skill: start comes before next" "[ ${L_START:-0} -gt 0 ] && [ ${L_START:-0} -lt ${L_NEXT:-0} ]"
assert_true "skill: next comes before record" "[ ${L_NEXT:-0} -gt 0 ] && [ ${L_NEXT:-0} -lt ${L_RECORD:-0} ]"
assert_true "skill: report comes last" "[ ${L_REPORT:-0} -gt ${L_RECORD:-0} ] && [ ${L_REPORT:-0} -gt ${L_STOP:-0} ]"

print_summary "rest-queue"
