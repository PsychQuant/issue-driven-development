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
. "$HERE/lib.sh"   # RQ, PLUGIN, SKILL, WORK, the scenario helpers and the states of a directory

echo "── the two tables ──"
# spec-example: idd-all-rest / argument forms
# spec-example: idd-all-rest / class precedence
python3 "$HERE/tables_check.py" > "$WORK/tables.out" 2>&1; rc=$?
assert_exit "tables_check.py passes (argument forms, class precedence, 1024 combinations)" 0 "$rc"
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
OUT=$(rq args -- last); rc=$?
assert_exit "args: the word last exits 1" 1 "$rc"
assert_grep "args: and the reason names rest" "rest" "$(printf '%s' "$OUT" | jget reason)"
OUT=$(rq args -- ''); rc=$?
assert_exit "args: an empty argument exits 1" 1 "$rc"

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
  11:html=body-verified 12:html=body-fenced-phase,diag=Plan 13 14:diag=Simple 15:labels=north-star \
  16:commenter=outsider 17:bot=helper-bot 18:commenter=outsider,comments=130
: > "$G/perm-helper-bot.500"     # a bot's permission is never read: it would end the command here
echo '{"permission": "read", "role_name": "read"}' > "$G/perm-outsider.json"
: > "$G/perm-botty.404"
OUT=$(rq list --repo "$REPO" --json); rc=$?
assert_exit "classes: exits 0" 0 "$rc"
assert_eq "classes: outsider (author without write access, app account, gone account, outside edit, outside comment, an old outside comment)" "[1,2,3,4,16,18]" "$(printf '%s' "$OUT" | jget classes.outsider)"
assert_eq "classes: tracker" "[5,15]" "$(printf '%s' "$OUT" | jget classes.tracker)"
assert_eq "classes: needs-person" "[6]" "$(printf '%s' "$OUT" | jget classes.needs-person)"
assert_eq "classes: parked (label, and a deferral in Complexity)" "[7,8]" "$(printf '%s' "$OUT" | jget classes.parked)"
assert_eq "classes: blocked" "[9]" "$(printf '%s' "$OUT" | jget classes.blocked)"
assert_eq "classes: meeting" "[10]" "$(printf '%s' "$OUT" | jget classes.meeting)"
assert_eq "classes: verified" "[11]" "$(printf '%s' "$OUT" | jget classes.verified)"
assert_eq "classes: candidate (a Phase line inside a code block does not count; a bot comment does not hold an issue back)" "[12,13,14,17]" "$(printf '%s' "$OUT" | jget classes.candidate)"
assert_eq "classes: run order" "[12,14,13,17]" "$(printf '%s' "$OUT" | jget order)"
assert_eq "classes: both questions of #6 are listed" "2" "$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["questions"]["6"]))')"
assert_eq "classes: every issue is in exactly one class" "18" "$(printf '%s' "$OUT" | python3 -c 'import json,sys; c=json.load(sys.stdin)["classes"]; a=[n for v in c.values() for n in v]; print(len(a) if len(a)==len(set(a)) else "duplicates")')"

# spec-example: idd-all-rest / edited by an account that cannot be read
new edited 5 6:editor=me 7:edited=yes
OUT=$(rq list --repo "$REPO" --json); rc=$?
assert_exit "edited: exits 0" 0 "$rc"
assert_eq "edited: never edited, and edited by an account with write access, are candidates" "[5,6]" "$(printf '%s' "$OUT" | jget order)"
assert_eq "edited: edited by an account GitHub does not return is an outsider issue" "[7]" "$(printf '%s' "$OUT" | jget classes.outsider)"
python3 -c 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); del d[0]["lastEditedAt"]; json.dump(d, open(p,"w"))' "$G/issues.json"
OUT=$(rq list --repo "$REPO" --json 2>/dev/null); rc=$?
assert_exit "edited: a node without the time of the last edit exits 3" 3 "$rc"

# spec-example: idd-all-rest / a body GitHub renders as nothing
new unreadable 5 6:html=body-comment-only 7:html=body-comment-only,author=outsider
echo '{"permission": "read", "role_name": "read"}' > "$G/perm-outsider.json"
assert_true "unreadable: the fixture has text and GitHub's rendering of it is empty" '[ -s "$HERE/fixtures/body-comment-only.md" ] && [ ! -s "$HERE/fixtures/body-comment-only.html" ]'
OUT=$(rq list --repo "$REPO" --json 2>"$S/err"); rc=$?
assert_exit "unreadable: one issue without a rendering does not fail the command" 0 "$rc"
assert_eq "unreadable: that issue has its own class" "[6]" "$(printf '%s' "$OUT" | jget classes.unreadable)"
assert_eq "unreadable: by an account without write access it is an outsider issue" "[7]" "$(printf '%s' "$OUT" | jget classes.outsider)"
assert_eq "unreadable: the run order holds the other candidate" "[5]" "$(printf '%s' "$OUT" | jget order)"
rq list --repo "$REPO" > "$S/list.out" 2>&1
assert_true "unreadable: the plain list names the class and the issue" 'grep -E "no rendering.*\(1\): #6$" "$S/list.out" >/dev/null'
refute_output_grep "list: prints no issue title" "SECRET-TITLE-TEXT" "$S/list.out"

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

# a gate that cannot be evaluated ends the command: a copy of the helper without lib/actionability.sh
new gate-missing 1:diag=Simple
mkdir -p "$S/copy/lib"
cp "$RQ" "$S/copy/rest-queue.py"
cp "$PLUGIN/scripts/lib/ghread.py" "$PLUGIN/scripts/lib/intent.py" "$PLUGIN/scripts/lib/rendered.py" "$PLUGIN/scripts/lib/reststate.py" "$S/copy/lib/"
OUT=$(python3 "$S/copy/rest-queue.py" list --repo "$REPO" --json 2>"$S/err"); rc=$?
assert_exit "list: a gate that cannot be evaluated exits 3" 3 "$rc"
assert_eq "list: and prints no list" "" "$OUT"
assert_eq "list: the reason is one line" "1" "$(wc -l < "$S/err" | tr -d ' ')"

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
run start --path PR --review no > "$S/start.out" 2>&1; rc=$?
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
run start --path PR --review no > /dev/null 2>&1
run next > /dev/null
OUT=$(run next)
assert_eq "in flight: the same issue is repeated, with its directory and no branch" "5|true|$(dir_of 5)|null|no" "$(for k in next in_flight dir branch review; do printf '%s' "$OUT" | jget $k; done | paste -sd'|' -)"
assert_eq "in flight: the state holds one attempt" "1" "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["attempts"]))' "$(state_file)")"

# spec-example: idd-all-rest / the in-flight issue names its branch
new inflight-branch 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null 2>&1; git -C "$(dir_of 5)" checkout -q -b idd/5-x
OUT=$(run next 2> /dev/null)
assert_eq "in flight: the issue names the branch its directory is on" "5|true|idd/5-x" "$(printf '%s' "$OUT" | jget next)|$(printf '%s' "$OUT" | jget in_flight)|$(printf '%s' "$OUT" | jget branch)"
git -C "$(dir_of 5)" checkout -q -b other
assert_eq "in flight: a branch that is not one of the issue is not named" "null" "$(run next 2> /dev/null | jget branch)"

# spec-example: idd-all-rest / outcomes by issue state
new out-closed 5
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; echo CLOSED > "$G/state-5"
OUT=$(run record --issue 5)
assert_eq "outcome: CLOSED without a reason" "closed|" "$(printf '%s' "$OUT" | jget outcome)|$(printf '%s' "$OUT" | jget reason)"
new out-open-reason 5
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
OUT=$(run record --issue 5 --reason "verify gate: not_clean")
assert_eq "outcome: OPEN with a reason" "stopped|verify gate: not_clean" "$(printf '%s' "$OUT" | jget outcome)|$(printf '%s' "$OUT" | jget reason)"
new out-open-none 5
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
OUT=$(run record --issue 5)
assert_eq "outcome: OPEN without a reason" "stopped|no reason given" "$(printf '%s' "$OUT" | jget outcome)|$(printf '%s' "$OUT" | jget reason)"
new out-claimed 5
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
OUT=$(run record --issue 5 --reason "merged and closed")
assert_eq "outcome: an open issue is stopped whatever the caller says" "stopped" "$(printf '%s' "$OUT" | jget outcome)"
new out-wrong 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
cp "$(state_file)" "$S/before.json"
run record --issue 9 > /dev/null 2>&1; rc=$?
assert_exit "record: an issue that is not in flight exits 1" 1 "$rc"
require "record: and the state is unchanged" cmp -s "$S/before.json" "$(state_file)"

# spec-example: idd-all-rest / stop ends the run
new cont 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; run record --issue 5 --reason x > /dev/null
assert_eq "one stopped issue does not end the run" "9" "$(run next | jget next)"
new stop 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; run record --issue 5 --reason x > /dev/null
run stop --reason "default branch could not be fast-forwarded" > /dev/null 2>&1; rc=$?
assert_exit "stop: exits 0" 0 "$rc"
OUT=$(run next)
assert_eq "stop: next names the reason and hands out nothing" '{"next":null,"stopped":"default branch could not be fast-forwarded"}' \
  "$(printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps({"next": d["next"], "stopped": d["stopped"]}, separators=(",",":")))')"
assert_eq "stop: #9 was not handed out" "1" "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["attempts"]))' "$(state_file)")"

# spec-example: idd-all-rest / resume within 24 hours
new resume 5 9
write_state 2 '[{"issue": 5, "outcome": "stopped", "reason": "verify gate: not_clean"}]'
run start --path PR --review no --take-over > "$S/start.out" 2>&1; rc=$?
assert_exit "resume: start --take-over exits 0" 0 "$rc"
assert_output_grep "resume: start says the run is resumed" "resumed" "$S/start.out"
assert_output_grep "resume: with one attempt" "1 attempt" "$S/start.out"
assert_output_grep "resume: the list names issue numbers" "#9" "$S/start.out"
refute_output_grep "resume: the list prints no issue title" "SECRET-TITLE-TEXT" "$S/start.out"
refute_output_grep "resume: the list prints no issue text" "SECRET-BODY-TEXT" "$S/start.out"
assert_true "resume: the fixture issues do carry that title" 'grep -q "SECRET-TITLE-TEXT" "$G/issues.json"'
assert_eq "resume: starting counts as activity (updated_at is now, not 2 hours ago)" "fresh" "$(python3 -c 'import calendar,json,sys,time; s=json.load(open(sys.argv[1])); t=calendar.timegm(time.strptime(s["updated_at"], "%Y-%m-%dT%H:%M:%SZ")); print("fresh" if time.time()-t < 300 else "stale")' "$(state_file)")"
assert_eq "resume: next is #9, not #5" "9" "$(run next | jget next)"
run start --path PR --review no --take-over > /dev/null 2>&1    # a start that takes the run over
assert_eq "resume: a start --take-over keeps the attempts" "2" "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["attempts"]))' "$(state_file)")"

# spec-example: idd-all-rest / a state older than 24 hours starts a new run
new expired 5 9
write_state 25 '[{"issue": 5, "outcome": "stopped", "reason": "verify gate: not_clean"}]'
run start --path PR --review no > "$S/start.out" 2>&1
refute_output_grep "expired: start does not resume" "resumed" "$S/start.out"
assert_eq "expired: next is #5 again" "5" "$(run next | jget next)"

# spec-example: idd-all-rest / report with one closed, one stopped and one waiting issue
new report 5 9 14:html=body-two-rows
run start --path PR --review no > /dev/null 2>&1
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

refute_output_grep "report: prints no issue title" "SECRET-TITLE-TEXT" "$S/report.out"

# spec-example: idd-all-rest / an attempted issue is not listed as not run
new report-attempted 5 8:html=body-verified
run start --path PR --review no > /dev/null 2>&1
run next > /dev/null; run record --issue 5 --reason "verify gate: not_clean" > /dev/null
issues 5:html=body-verified 8:html=body-verified      # by the time of the report #5 shows the phase verified too
run report > "$S/report.out" 2>&1; rc=$?
assert_exit "report (attempted): exits 0" 0 "$rc"
VLINE=$(grep -E '^not run — already verified' "$S/report.out")
assert_grep "report (attempted): the verified line names #8" "#8" "$VLINE"
refute_grep "report (attempted): and does not name #5" "#5" "$VLINE"
assert_output_grep "report (attempted): #5 is under stopped" "#5 — verify gate: not_clean" "$S/report.out"
assert_grep "report (attempted): a verified issue continues when it is named" "/idd-all #N" "$VLINE"
new report-existing 5
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; run record --issue 5 --reason "existing work: PR #77" > /dev/null
run report > "$S/report.out" 2>&1
assert_output_grep "report: an issue with existing work is left for a person" "existing work is left for a person" "$S/report.out"
assert_output_grep "report: whose reason names what to look at" "names the pull request, the branch or the directory to look at" "$S/report.out"

# spec-example: idd-all-rest / a stopped issue carries its open questions
new report-asked 5 14:html=body-two-rows
run start --path PR --review no > /dev/null 2>&1
run next > /dev/null; run record --issue 5 --reason "verify gate: not_clean" > /dev/null
issues 5:html=body-three-rows 14:html=body-two-rows      # by the time of the report #5 shows two open rows
run report > "$S/report.out" 2>&1; rc=$?
assert_exit "report (asked): exits 0" 0 "$rc"
assert_eq "report (asked): #5 is named once" "1" "$(grep -c '#5\b' "$S/report.out")"
STOPPED_BLOCK=$(awk '/^stopped \(/{f=1; next} f&&/^[^ ]/{exit} f' "$S/report.out")
assert_grep "report (asked): under stopped, with its reason" "#5 — verify gate: not_clean" "$STOPPED_BLOCK"
assert_eq "report (asked): followed by its two open rows" "2" "$(printf '%s\n' "$STOPPED_BLOCK" | grep -c '^    - ')"
assert_grep "report (asked): the first row of #5" "first thing" "$STOPPED_BLOCK"
WAITING_BLOCK=$(awk '/^waiting for a person \(/{f=1; print; next} f&&/^[^ ]/{exit} f' "$S/report.out")
assert_grep_re "report (asked): one issue waits for a person" '^waiting for a person \(1\):' "$WAITING_BLOCK"
assert_grep "report (asked): it is #14" "#14" "$WAITING_BLOCK"
refute_grep "report (asked): and not #5" "#5" "$WAITING_BLOCK"
new report-flight 5
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
issues 5:html=body-two-rows
run report > "$S/report.out" 2>&1
assert_output_grep "report: an issue in flight keeps its open questions too" "Does alpha include beta?" "$S/report.out"
assert_true "report: and it is not listed as waiting" 'grep -E "^waiting for a person \(0\)" "$S/report.out" >/dev/null'

# spec-example: idd-all-rest / a closed issue that was reopened carries its open questions
new report-reopened 5 9
run start --path PR --review no > /dev/null 2>&1
run next > /dev/null; echo CLOSED > "$G/state-5"; run record --issue 5 > /dev/null
issues 5:html=body-two-rows 9      # #5 is open again, with two open clarity rows
run report > "$S/report.out" 2>&1; rc=$?
assert_exit "report (reopened): exits 0" 0 "$rc"
CLOSED_BLOCK=$(awk '/^closed \(/{f=1; print; next} f&&/^[^ ]/{exit} f' "$S/report.out")
assert_grep_re "report (reopened): #5 is under closed" '^closed \(1\): #5$' "$CLOSED_BLOCK"
assert_grep "report (reopened): with a note that it is open again" "#5 — open again" "$CLOSED_BLOCK"
assert_eq "report (reopened): followed by its two open rows" "2" "$(printf '%s\n' "$CLOSED_BLOCK" | grep -c '^    - ')"
WAITING_BLOCK=$(awk '/^waiting for a person \(/{f=1; print; next} f&&/^[^ ]/{exit} f' "$S/report.out")
refute_grep "report (reopened): and #5 is not listed as waiting" "#5" "$WAITING_BLOCK"
assert_eq "report (reopened): #5 is named nowhere outside the closed part" "0" "$(awk '/^closed \(/{f=1; next} f&&/^[^ ]/{f=0} !f' "$S/report.out" | grep -c '#5\b')"

# spec-example: idd-all-rest / a reason with a line break is printed on one line
new one-line 5 9
mkdir -p "$T/.claude/.idd/state"
python3 - "$(state_file)" <<'PY'
import json, sys, time
stamp = lambda t: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))
now = time.time()
json.dump({"version": 6, "repo": "o/r", "path": "PR", "default": "main", "review": False, "started_at": stamp(now - 600), "updated_at": stamp(now - 300),
           "token_digest": __import__("hashlib").sha256(b"00112233445566778899aabb").hexdigest(),
           "attempts": [{"issue": 5, "handed_at": stamp(now - 500), "outcome": "stopped",
                         "reason": "verify gate\nSECOND-LINE of the issue reason", "recorded_at": stamp(now - 400)},
                        {"issue": 6, "handed_at": stamp(now - 450), "outcome": "stopped",
                         "reason": "a\tTAB-FOLLOWS " + "x" * 400, "recorded_at": stamp(now - 350)}],
           "stop": {"reason": "first line\nSECOND-LINE of the stop reason", "at": stamp(now - 300)}}, open(sys.argv[1], "w"))
PY
run start --path PR --review no --take-over > "$S/start.out" 2>&1; rc=$?
assert_exit "one line: start exits 0" 0 "$rc"
assert_true "one line: no line of start begins with the second line" '! grep -E "^SECOND-LINE" "$S/start.out" >/dev/null'
assert_true "one line: start holds both parts of the stop reason on one line" 'grep -E "first line SECOND-LINE of the stop reason" "$S/start.out" >/dev/null'
OUT=$(run next)
assert_eq "one line: next gives the stop reason on one line" "first line SECOND-LINE of the stop reason" "$(printf '%s' "$OUT" | jget stopped)"
run report > "$S/report.out" 2>&1; rc=$?
assert_exit "one line: report exits 0" 0 "$rc"
assert_true "one line: no line of report begins with the second line" '! grep -E "^SECOND-LINE" "$S/report.out" >/dev/null'
assert_true "one line: report holds both parts of the stop reason on one line" 'grep -E "first line SECOND-LINE of the stop reason" "$S/report.out" >/dev/null'
assert_true "one line: and the issue reason on one line" 'grep -E "#5 — verify gate SECOND-LINE of the issue reason" "$S/report.out" >/dev/null'
L6=$(grep -F '#6 — ' "$S/report.out")
assert_true "one line: a tab in a reason is not printed" "! printf '%s' \"\$L6\" | grep -q \"\$(printf '\\t')\""
assert_true "one line: and a long reason is cut to the limit" '[ "$(printf "%s" "$L6" | sed "s/^  #6 — //" | wc -m)" -le 301 ]'

# spec-example: idd-all-rest / a long clarity row is printed in full
new report-long 5 14:html=body-long-row
assert_true "long row: the open row of the fixture is longer than 300 characters" '[ "$(grep -c "END-OF-QUESTION" "$HERE/fixtures/body-long-row.md")" = 1 ] && [ "$(grep "END-OF-QUESTION" "$HERE/fixtures/body-long-row.md" | wc -m)" -gt 300 ]'
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; run record --issue 5 --reason x > /dev/null
run report > "$S/report.out" 2>&1; rc=$?
assert_exit "report (long row): exits 0" 0 "$rc"
assert_true "report (long row): the row is printed up to its last words" 'grep -E "^    - .*END-OF-QUESTION" "$S/report.out" >/dev/null'
assert_eq "report (long row): on one line" "1" "$(grep -c "END-OF-QUESTION" "$S/report.out")"

new report-unreadable 5
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; run record --issue 5 --reason "stopped at the PR" > /dev/null
echo 1 > "$G/fail-page"
run report > "$S/report.out" 2>&1; rc=$?
assert_exit "report: still exits 0 when the list cannot be re-read" 0 "$rc"
assert_output_grep "report: the recorded result is still printed" "#5 — stopped at the PR" "$S/report.out"
assert_output_grep "report: and it says the list could not be read" "could not be read" "$S/report.out"
assert_file_absent "report: the run state is deleted" "$(state_file)"

new report-crash 5
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; run record --issue 5 --reason "stopped at the PR" > /dev/null
mkdir -p "$S/copy"; cp "$RQ" "$S/copy/rest-queue.py"; cp -R "$PLUGIN/scripts/lib" "$S/copy/lib"
printf '\n\ndef latest_diagnosis(comments):\n    raise RuntimeError("a failure nobody planned for")\n' >> "$S/copy/lib/ghread.py"
python3 "$S/copy/rest-queue.py" report --cwd "$T" --repo "$REPO" --token "$(run_token)" > "$S/report.out" 2>&1; rc=$?
assert_exit "report: an unplanned failure while re-reading the list still exits 0" 0 "$rc"
assert_output_grep "report: the recorded result is still printed after it" "#5 — stopped at the PR" "$S/report.out"
assert_output_grep "report: and it says the list could not be read" "could not be read" "$S/report.out"
assert_file_absent "report: and the run state is deleted" "$(state_file)"

echo "── refusals ──"
new norun 5
for sub in next where record stop report; do
  case "$sub" in record) extra=(--issue 5) ;; stop) extra=(--reason x) ;; *) extra=() ;; esac
  if [ "$sub" = stop ]; then rq stop --cwd "$T" --token "$NO_TOKEN_YET" "${extra[@]}" > /dev/null 2>&1; rc=$?
  else run "$sub" ${extra[@]+"${extra[@]}"} > /dev/null 2>&1; rc=$?; fi
  assert_exit "no run: $sub exits 1" 1 "$rc"
done
rq next > /dev/null 2>&1; assert_exit "usage: next without arguments exits 2" 2 "$?"
rq bogus > /dev/null 2>&1; assert_exit "usage: an unknown subcommand exits 2" 2 "$?"
rq next --cwd "$T" --repo "not a repo" > /dev/null 2>&1; assert_exit "usage: a malformed repo exits 2" 2 "$?"
new symlink 5
mkdir -p "$S/elsewhere"; ln -s "$S/elsewhere" "$T/.claude"
run start --path PR --review no > /dev/null 2>&1; rc=$?
assert_exit "start: refuses a state directory behind a symlink (exit 3)" 3 "$rc"
assert_true "start: and writes nothing through it" '[ -z "$(ls -A "$S/elsewhere")" ]'
new start-fail 5
echo 1 > "$G/fail-page"
run start --path PR --review no > /dev/null 2>&1; rc=$?
assert_exit "start: exits 3 when the issues cannot be read" 3 "$rc"
assert_file_absent "start: and leaves no run state" "$(state_file)"
run stop --reason "the open issues could not be read" > /dev/null 2>&1; rc=$?
assert_exit "start failed: there is no run, so stop exits 1" 1 "$rc"
run report > /dev/null 2>&1; rc=$?
assert_exit "start failed: and report exits 1" 1 "$rc"
new start-fail-resume 5 9
write_state 2 '[{"issue": 5, "outcome": "stopped", "reason": "verify gate: not_clean"}]'
cp "$(state_file)" "$S/before.json"; echo 1 > "$G/fail-page"
run start --path PR --review no --take-over > /dev/null 2>&1; rc=$?
assert_exit "start failed on a run it would have resumed: exits 3" 3 "$rc"
require "start failed on a run it would have resumed: the state of that run is untouched" cmp -s "$S/before.json" "$(state_file)"
rm "$G/fail-page"
run start --path PR --review no --take-over > "$S/start.out" 2>&1
assert_output_grep "start failed on a run it would have resumed: a later start resumes it" "resumed" "$S/start.out"
assert_eq "start failed on a run it would have resumed: and #5 is not handed out again" "9" "$(run next | jget next)"

echo "── failures of the helper itself ──"
new unwritable 5
mkdir -p "$T/.claude/.idd"; : > "$T/.claude/.idd/state"      # the state directory cannot be created: a file is in the way
run start --path PR --review no > "$S/out" 2> "$S/err"; rc=$?
assert_exit "start: a run state that cannot be written exits 3" 3 "$rc"
assert_eq "start: with one reason line" "1" "$(wc -l < "$S/err" | tr -d ' ')"
refute_output_grep "start: and no traceback" "Traceback" "$S/err"
new empty-reason 5
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
OUT=$(run record --issue 5 --reason ""); rc=$?
assert_exit "record: an empty reason is accepted" 0 "$rc"
assert_eq "record: and reads as no reason" "stopped|no reason given" "$(printf '%s' "$OUT" | jget outcome)|$(printf '%s' "$OUT" | jget reason)"
new broken-state 5
mkdir -p "$T/.claude/.idd/state"; printf '{"version": 1, "repo"' > "$(state_file)"
run start --path PR --review no > "$S/start.out" 2>&1; rc=$?
assert_exit "start: a run state that cannot be used and was written just now stops it" 3 "$rc"
assert_output_grep "start: and it says so" "cannot be used" "$S/start.out"
new null-reason 5
write_state 1 '[{"issue": 5, "outcome": "stopped", "reason": null}]'
run start --path PR --review no > "$S/start.out" 2>&1; rc=$?
assert_exit "start: an attempt without a usable reason makes the state unusable: start stops (exit 3)" 3 "$rc"
assert_output_grep "start: and it says so" "cannot be used" "$S/start.out"
# spec-example: idd-all-rest / a run for another repository is not replaced without --take-over
new other-repo-case 5
write_state 1 '[]'; python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); s["repo"]="O/R"; json.dump(s, open(p,"w"))' "$(state_file)"
cp "$(state_file)" "$S/before.json"
run start --path PR --review no > /dev/null 2>&1; assert_exit "another repository (O/R, the same one): start exits 4" 4 "$?"
require "another repository (O/R): the state file is as it was" cmp -s "$S/before.json" "$(state_file)"
run start --path PR --review no --take-over > "$S/start.out" 2>&1; assert_exit "another repository (O/R): start --take-over exits 0" 0 "$?"
assert_output_grep "another repository (O/R): and resumes that run" "resumed" "$S/start.out"
new other-repo-state 5
mkdir -p "$(dir_of 5)"; printf 'x\n' > "$(dir_of 5)/a.txt"
write_state 1 '[{"issue": 5, "outcome": null, "reason": "", "dir": "'"$(dir_of 5)"'", "made": true}]'
python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); s["repo"]="o/other"; json.dump(s, open(p,"w"))' "$(state_file)"
cp "$(state_file)" "$S/before.json"
run start --path PR --review no > /dev/null 2> "$S/err"; rc=$?
assert_exit "another repository (o/other): start exits 4" 4 "$rc"
assert_output_grep "another repository (o/other): and its reason line names it" "o/other" "$S/err"
require "another repository (o/other): the state file is as it was" cmp -s "$S/before.json" "$(state_file)"
run start --path PR --review no --take-over > "$S/start.out" 2>&1; rc=$?
assert_exit "another repository (o/other): start --take-over begins a new run" 0 "$rc"
assert_output_grep "another repository (o/other): and says whose it was" "o/other" "$S/start.out"
assert_grep "another repository (o/other): and before the list prints the directory of #5" "$(dir_of 5)" "$(awk '/never ended with its report/{f=1; next} /^open issues:/{f=0} f' "$S/start.out")"
refute_grep "another repository (o/other): and does not call a state written an hour ago older than 24 hours" "older than 24 hours" "$(cat "$S/start.out")"
rq next --cwd "$T" --repo o/other --token "$TEST_TOKEN" > /dev/null 2>&1; assert_exit "another repository (o/other): a next of the run that was replaced exits 4" 4 "$?"
for bad in "../x" "o/.." "./r" "o/."; do
  rq list --repo "$bad" > /dev/null 2>&1; assert_exit "usage: --repo $bad exits 2" 2 "$?"
done
rq list --repo "o/.github" > /dev/null 2>&1; assert_exit "usage: a repository name that begins with a dot is fine" 0 "$?"

echo "── the directory of an issue ──"
stopped_block() { awk '/^stopped \(/{f=1; next} f&&/^[^ ]/{exit} f' "$1"; }
python3 "$HERE/treecheck.py" --self-test > "$WORK/treecheck.out" 2>&1; assert_exit "treecheck: the listing of a repository passes its own test" 0 "$?"

# Scenario: an issue is handed out with its directory
# spec-example: idd-all-rest / the directory is a repository of its own
new dir-own 5
remote_ahead
git -C "$T" config user.name "Local Name"
printf '#!/bin/sh\nexit 0\n' > "$T/.git/hooks/pre-commit"; /bin/chmod u+x "$T/.git/hooks/pre-commit"
run start --path PR --review no > /dev/null 2>&1; OUT=$(run next 2> /dev/null); D=$(dir_of 5)
assert_eq "directory: next prints it as dir, and the directory the run was started in as root" "$D|$T" "$(printf '%s' "$OUT" | jget dir)|$(printf '%s' "$OUT" | jget root)"
assert_eq "directory: next prints no token" "<missing>" "$(printf '%s' "$OUT" | jget token)"
assert_true "directory: no file below T or its origin holds the token of the run" '! grep -rqF "$(run_token)" "$T" "$T.origin.git"'
assert_true "directory: it holds a git directory of its own" '[ -d "$D/.git" ] && [ ! -L "$D/.git" ]'
assert_eq "directory: it is on main, at the commit origin has" "main|$(git -C "$T.origin.git" rev-parse main)" "$(git -C "$D" symbolic-ref --short HEAD)|$(git -C "$D" rev-parse HEAD)"
assert_true "directory: which the repository the run was started in does not have checked out" '[ "$(git -C "$T" rev-parse HEAD)" != "$(git -C "$D" rev-parse HEAD)" ]'
assert_eq "directory: it is not a linked worktree of that repository" "1" "$(git -C "$T" worktree list | grep -c .)"
assert_eq "directory: its origin is the origin of that repository" "$(git -C "$T" remote get-url origin)" "$(git -C "$D" remote get-url origin)"
assert_eq "directory: user.name is carried over" "Local Name" "$(git -C "$D" config --local user.name)"
assert_true "directory: the hook is not" '[ ! -e "$D/.git/hooks/pre-commit" ]'
assert_true "directory: it borrows no objects once it is made" '[ ! -e "$D/.git/objects/info/alternates" ]'
assert_eq "directory: git ignores the plugin's own places in it" "3" "$(cd "$D" && git check-ignore .claude/.idd/state/x .claude/worktrees/x .claude/.idd/tree-lock.reclaim | grep -c .)"
assert_eq "directory: the helper wrote no file into the clone (git status is empty, and so is its state folder)" "|0" "$(git -C "$D" status --porcelain --untracked-files=all --ignored)|$(ls -A "$D/.claude/.idd/state" 2>/dev/null | grep -c .)"
assert_eq "directory: its git directory holds the mark stored with the issue" "$(attempt 5 mark)" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["mark"])' "$D/.git/idd-rest-mark" 2>/dev/null)"
assert_true "directory: the mark is a value of its own" '[ "$(attempt 5 mark | wc -c)" -gt 16 ]'
assert_eq "directory: the URL it was cloned from is stored with the issue" "$(git -C "$T" remote get-url origin)" "$(attempt 5 origin)"
assert_eq "directory: no temporary folder is left once it is made" "0" "$(ls -A "$T/.claude/worktrees" | grep -c '^\.rest-')"
here_in "$D" 5 > /dev/null 2>&1; assert_exit "directory: here exits 0 for it, the issue and the token of the run, run there" 0 "$?"

# spec-example: idd-all-rest / the working tree the run was started in is not needed clean
new not-clean-a 5
run start --path PR --review no > /dev/null 2>&1; assert_exit "not clean (on main, clean): start exits 0" 0 "$?"
assert_eq "not clean (on main, clean): next hands out #5" "5" "$(run next 2> /dev/null | jget next)"
new not-clean-b 5
git -C "$T" checkout -q -b wip; printf 'changed\n' >> "$T/a.txt"; printf 'b\n' > "$T/b.txt"
BEFORE="$(git -C "$T" symbolic-ref --short HEAD)|$(git -C "$T" status --porcelain -- a.txt b.txt)|$(cat "$T/a.txt" "$T/b.txt")"
run start --path PR --review no > /dev/null 2> "$S/err"; assert_exit "not clean (on wip, with changes): start exits 0" 0 "$?"
assert_eq "not clean (on wip, with changes): next hands out #5" "5" "$(run next 2> /dev/null | jget next)"
assert_eq "not clean: the working tree is on the same branch with the same files" "$BEFORE" "$(git -C "$T" symbolic-ref --short HEAD)|$(git -C "$T" status --porcelain -- a.txt b.txt)|$(cat "$T/a.txt" "$T/b.txt")"
assert_eq "not clean: the directory of #5 is on main" "main" "$(git -C "$(dir_of 5)" symbolic-ref --short HEAD)"

# spec-example: idd-all-rest / a directory that was not finished
unmade() { python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); s["attempts"][0]["made"]=False; json.dump(s, open(p,"w"))' "$(state_file)"; }
new dir-unfinished-empty 5 9
begin; D=$(dir_of 5); unmade; rm -rf "$D"
OUT=$(run next 2> /dev/null); rc=$?
assert_exit "unfinished directory (nothing at its place): next exits 0" 0 "$rc"
assert_eq "unfinished directory (nothing at its place): it prints #5 in flight with the same dir" "5|true|$D" "$(printf '%s' "$OUT" | jget next)|$(printf '%s' "$OUT" | jget in_flight)|$(printf '%s' "$OUT" | jget dir)"
assert_true "unfinished directory (nothing at its place): the directory is a repository of its own" '[ -d "$D/.git" ] && git --git-dir "$D/.git" rev-parse --git-dir > /dev/null 2>&1'
new dir-unfinished-taken 5 9
begin; D=$(dir_of 5); unmade; rm -rf "$D"; mkdir -p "$D"; printf 'half\n' > "$D/partial.txt"   # what a next that was ended during the clone leaves
OUT=$(run next 2> /dev/null); rc=$?
assert_exit "unfinished directory (a folder at its place): next exits 0" 0 "$rc"
assert_eq "unfinished directory (a folder at its place): it hands out #9" "9" "$(printf '%s' "$OUT" | jget next)"
assert_eq "unfinished directory (a folder at its place): #5 is recorded as stopped" "stopped" "$(attempt 5 outcome)"
assert_grep "unfinished directory (a folder at its place): and its reason names the place" "$D" "$(attempt 5 reason)"
assert_eq "unfinished directory (a folder at its place): partial.txt is still there" "half" "$(cat "$D/partial.txt" 2>/dev/null)"
new dir-unfinished-moved 5 9
begin; D=$(dir_of 5); unmade; printf 'keep\n' > "$D/keep.txt"   # the clone the earlier next moved there, before it said so
OUT=$(run next 2> /dev/null); rc=$?
assert_exit "unfinished directory (the clone the earlier next moved there): next exits 0" 0 "$rc"
assert_eq "unfinished directory (the clone the earlier next moved there): it prints #5 in flight with the same dir" "5|true|$D" "$(printf '%s' "$OUT" | jget next)|$(printf '%s' "$OUT" | jget in_flight)|$(printf '%s' "$OUT" | jget dir)"
assert_eq "unfinished directory (the clone the earlier next moved there): and it is the one that was there" "keep" "$(cat "$D/keep.txt" 2>/dev/null)"
new dir-unfinished-other 5 9
begin; D=$(dir_of 5); unmade; rm -rf "$D"; git clone -q "$T.origin.git" "$D" 2> /dev/null   # another clone of the same origin, without the mark
python3 "$HERE/treecheck.py" whole "$D" > "$S/other-before.txt"
OUT=$(run next 2> /dev/null)
assert_eq "unfinished directory (another clone without the mark): it hands out #9" "9" "$(printf '%s' "$OUT" | jget next)"
assert_eq "unfinished directory (another clone without the mark): #5 is recorded as stopped" "stopped" "$(attempt 5 outcome)"
assert_grep "unfinished directory (another clone without the mark): and its reason names the place" "$D" "$(attempt 5 reason)"
python3 "$HERE/treecheck.py" whole "$D" > "$S/other-after.txt"
require "unfinished directory (another clone without the mark): that clone is as it was" cmp -s "$S/other-before.txt" "$S/other-after.txt"

# spec-example: idd-all-rest / a clone that fails touches only its temporary folder
wait_tmp() { # issue → returns once next has made the temporary folder of its clone (it then waits before the clone)
  local i; for i in $(seq 1 150); do ls -A "$T/.claude/worktrees" 2> /dev/null | grep -q "^\.rest-$1-" && return 0; sleep 0.1; done; return 1
}
new clone-fails 5 9
run start --path PR --review no > /dev/null 2>&1
python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); s["default"]="nosuch"; json.dump(s, open(p,"w"))' "$(state_file)"   # a branch origin does not have: the clone fails
D=$(dir_of 5)
IDD_REST_SLEEP_BEFORE_CLONE=4 run next > "$S/next.out" 2> "$S/next.err" & P=$!
wait_tmp 5; mkdir -p "$D"; printf 'mine\n' > "$D/mine.txt"
wait "$P"; rc=$?
assert_exit "a clone that fails: next exits 3" 3 "$rc"
assert_eq "a clone that fails: mine.txt at the place is there with its content" "mine" "$(cat "$D/mine.txt" 2>/dev/null)"
assert_eq "a clone that fails: the place holds nothing else" "mine.txt" "$(ls -A "$D" | tr '\n' ' ' | sed 's/ $//')"
new clone-place-taken 5 9
run start --path PR --review no > /dev/null 2>&1
D=$(dir_of 5)
IDD_REST_SLEEP_BEFORE_CLONE=4 run next > "$S/next.out" 2> "$S/next.err" & P=$!
wait_tmp 5; mkdir -p "$D"; printf 'mine\n' > "$D/mine.txt"
wait "$P"; rc=$?
assert_exit "a place taken during the clone: next exits 0" 0 "$rc"
assert_eq "a place taken during the clone: it hands out #9" "9" "$(jget next < "$S/next.out")"
assert_eq "a place taken during the clone: #5 is recorded as stopped" "stopped" "$(attempt 5 outcome)"
assert_grep "a place taken during the clone: and its reason names the place" "$D" "$(attempt 5 reason)"
assert_eq "a place taken during the clone: mine.txt is there with its content" "mine|mine.txt" "$(cat "$D/mine.txt" 2>/dev/null)|$(ls -A "$D" | tr '\n' ' ' | sed 's/ $//')"
TMP5=$(python3 -c 'import json,sys; a=[x for x in json.load(open(sys.argv[1]))["attempts"] if x["issue"]==5][0]; print((a.get("tmps") or [""])[0])' "$(state_file)")
assert_true "a place taken during the clone: the temporary folder of #5 is recorded and holds the clone" '[ -n "$TMP5" ] && [ -d "$TMP5/.git" ] && git --git-dir "$TMP5/.git" rev-parse --git-dir > /dev/null 2>&1'
assert_true "a place taken during the clone: its name is not the name of a directory" 'case "$(basename "$TMP5")" in .rest-5-*) true ;; *) false ;; esac'
new clone-place-empty 5 9
run start --path PR --review no > /dev/null 2>&1
D=$(dir_of 5)
IDD_REST_SLEEP_BEFORE_CLONE=4 run next > "$S/next.out" 2> "$S/next.err" & P=$!
wait_tmp 5; mkdir -p "$D"   # an empty folder: a rename onto it would replace it
wait "$P"; rc=$?
assert_exit "an empty folder put at the place during the clone: next exits 0" 0 "$rc"
assert_eq "an empty folder put at the place during the clone: it hands out #9 and records #5 as stopped" "9|stopped" "$(jget next < "$S/next.out")|$(attempt 5 outcome)"
assert_true "an empty folder put at the place during the clone: the folder is there and empty" '[ -d "$D" ] && [ -z "$(ls -A "$D")" ]'
TMP5=$(python3 -c 'import json,sys; a=[x for x in json.load(open(sys.argv[1]))["attempts"] if x["issue"]==5][0]; print((a.get("tmps") or [""])[0])' "$(state_file)")
assert_true "an empty folder put at the place during the clone: the temporary folder of #5 holds the clone" '[ -n "$TMP5" ] && [ -d "$TMP5/.git" ]'

# spec-example: idd-all-rest / a directory is not removed because of its name
new dir-name 5 9
mkdir -p "$T/.claude/worktrees/rest-5"; printf 'mine\n' > "$T/.claude/worktrees/rest-5/mine.txt"
run start --path PR --review no > "$S/start.out" 2>&1
assert_output_grep "a directory at the place: start lists #5 apart" "candidates with a local branch or a directory an earlier run kept, recorded as existing work when their turn comes (1): #5" "$S/start.out"
assert_eq "a directory at the place: next hands out #9" "9" "$(run next 2> /dev/null | jget next)"
assert_grep_re "a directory at the place: #5 is recorded as existing work" '^stopped\|existing work: directory ' "$(attempt 5 outcome)|$(attempt 5 reason)"
assert_grep "a directory at the place: the reason names it and says rest mode removes no directory" "$T/.claude/worktrees/rest-5 — rest mode removes no directory: look at it and delete it" "$(attempt 5 reason)"
assert_eq "a directory at the place: the file in it is still there" "mine" "$(cat "$T/.claude/worktrees/rest-5/mine.txt" 2>/dev/null)"

# spec-example: idd-all-rest / here names the directory an issue runs in
new here 5 9
begin; D=$(dir_of 5); K=$(run_token)
here() { (cd "${3:-$1}" && python3 "$RQ" here --cwd "$1" --repo "$REPO" --issue "$2" --token "${4:-$K}") 2> "$S/err"; }   # dir issue [the process's directory] [token]
here "$D" 5 > /dev/null; assert_exit "here: the directory of #5, issue 5, its token: exit 0" 0 "$?"
here "$T" 5 > /dev/null; assert_exit "here: the directory the run was started in, issue 5: exit 1" 1 "$?"
assert_output_grep "here: and the reason says T is not the directory of #5" "is not the directory of #5" "$S/err"
here "$D" 9 > /dev/null; assert_exit "here: the directory of #5, issue 9: exit 1" 1 "$?"
assert_output_grep "here: and the reason says it is not the directory of #9" "is not the directory of #9" "$S/err"
here "$D" 5 "$D" "$NO_TOKEN_YET" > /dev/null; assert_exit "here: another token: exit 4" 4 "$?"
assert_output_grep "here: and the reason says the token is not the one of this rest run" "the token is not the one of this rest run" "$S/err"
mv "$D" "$S/orig"; git clone -q "$T.origin.git" "$D" 2> /dev/null   # another clone of the same origin at the place
here "$D" 5 > /dev/null; assert_exit "here: another clone of the same origin at its place: exit 1" 1 "$?"
assert_output_grep "here: and the reason says the directory is not bound to #5" "is not bound to #5" "$S/err"
rm -rf "$D"; mv "$S/orig" "$D"
URL=$(git -C "$D" remote get-url origin); git -C "$D" remote set-url origin "$S/elsewhere.git"
here "$D" 5 > /dev/null; assert_exit "here: its origin set to another URL: exit 1" 1 "$?"
assert_output_grep "here: and the reason says the directory is not bound to #5" "is not bound to #5" "$S/err"
git -C "$D" remote set-url origin "$URL"
here "$D" 5 > /dev/null; assert_exit "here: back as it was: exit 0" 0 "$?"
mkdir -p "$S/nowhere"; git init -q "$S/nowhere"
here "$S/nowhere" 5 > /dev/null; assert_exit "here: a directory that is not below a working tree with a run: exit 1" 1 "$?"
assert_output_grep "here: and the reason says no rest run has #5 in flight there" "no rest run has #5 in flight" "$S/err"
here "$D" 5 "$T" > /dev/null; assert_exit "here: the directory of #5 with the process in T: exit 1" 1 "$?"
assert_output_grep "here: and the reason says the current directory is not the directory of #5" "current directory" "$S/err"
mv "$D" "$S/moved"; ln -s "$S/moved" "$D"
here "$S/moved" 5 > /dev/null; assert_exit "here: a moved clone, given where it is now: exit 1" 1 "$?"
assert_output_grep "here: and the reason says no rest run has #5 in flight there" "no rest run has #5 in flight" "$S/err"
here "$D" 5 > /dev/null; assert_exit "here: a moved clone, given as the place of the link: exit 1" 1 "$?"
assert_output_grep "here: and the reason says a symbolic link is on the way" "symbolic link" "$S/err"
rm "$D"; mv "$S/moved" "$D"

# spec-example: idd-all-rest / the token belongs to the run
new token 5 9
begin; K=$(run_token); D=$(dir_of 5)
run start --path PR --review no --take-over > "$S/start.out" 2>&1; L=$(run_token)
assert_true "token: start --take-over prints a new token" '[ -n "$L" ] && [ "$L" != "$K" ]'
assert_output_grep "token: and says the run is taken over" "taken over" "$S/start.out"
for sub in here where record; do
  case "$sub" in
    here) here_in "$D" 5 "$K" > /dev/null 2> "$S/err" ;;
    where) run where --token "$K" > /dev/null 2> "$S/err" ;;
    record) run record --issue 5 --reason x --token "$K" > /dev/null 2> "$S/err" ;;
  esac
  rc=$?
  assert_exit "token: $sub with the earlier token exits 4" 4 "$rc"
  assert_output_grep "token: and says the token is not the one of this rest run" "the token is not the one of this rest run" "$S/err"
  assert_output_grep "token: and that the invocation is to end" "end this invocation" "$S/err"
done
assert_eq "token: the outcome of #5 is not recorded" "null" "$(attempt 5 outcome)"
OUT=$(run next 2> /dev/null)
assert_eq "token: next with the new token prints #5 in flight, and no token" "5|true|<missing>" "$(printf '%s' "$OUT" | jget next)|$(printf '%s' "$OUT" | jget in_flight)|$(printf '%s' "$OUT" | jget token)"
here_in "$D" 5 "$L" > /dev/null 2>&1; assert_exit "token: here with the new token exits 0" 0 "$?"
assert_eq "token: where with the new token prints the directory of #5" "$D" "$(run where 2> /dev/null)"

# spec-example: idd-all-rest / an unfinished run is taken over only with --take-over
new take-over 5 9
begin; K=$(run_token); cp "$(state_file)" "$S/before.json"
run start --path PR --review no > "$S/out" 2> "$S/err"; rc=$?
assert_exit "take over: start without --take-over on an unfinished run exits 4" 4 "$rc"
assert_output_grep "take over: and says an unfinished rest run is in this working tree" "an unfinished rest run is in this working tree" "$S/err"
assert_output_grep "take over: and names start --take-over" "start --take-over" "$S/err"
require "take over: the run state is as it was" cmp -s "$S/before.json" "$(state_file)"
assert_eq "take over: and the token is still the one it was" "$K" "$(run_token)"
run start --path PR --review no --take-over > /dev/null 2>&1; rc=$?; L=$(run_token)
assert_exit "take over: start --take-over exits 0" 0 "$rc"
assert_true "take over: and prints a token that is not the earlier one" '[ "$L" != "$K" ]'
run next --token "$K" > /dev/null 2>&1; assert_exit "take over: next with the earlier token exits 4" 4 "$?"
assert_eq "take over: next with the new token prints #5 in flight" "5|true" "$(run next | jget next)|$(run next | jget in_flight)"
assert_true "take over: no file below T holds either token" '! grep -rqF -e "$K" -e "$L" "$T"'

# spec-example: idd-all-rest / start runs only at the top of a repository
new top-only 5
mkdir -p "$T/sub"
rq start --cwd "$T/sub" --repo "$REPO" --path PR --review no > /dev/null 2> "$S/err"; rc=$?
assert_exit "top only (a folder below the top): start exits 3" 3 "$rc"
assert_output_grep "top only (a folder below the top): its reason line names the top" "$T," "$S/err"
assert_true "top only (a folder below the top): no .claude folder below it and no run state at the top" '[ ! -e "$T/sub/.claude" ] && [ ! -e "$(state_file)" ]'
rq next --cwd "$T/sub" --repo "$REPO" --token "$NO_TOKEN_YET" > /dev/null 2>&1; assert_exit "top only (a folder below the top): next exits 3" 3 "$?"
run start --path PR --review no > /dev/null 2>&1; assert_exit "top only (the top): start exits 0" 0 "$?"
assert_true "top only (the top): a run state below it" '[ -f "$(state_file)" ]'
NL="$WORK/line"$'\n'"feed"; mkdir -p "$NL"; git_tree "$NL/tree"
rq start --cwd "$NL/tree" --repo "$REPO" --path PR --review no > /dev/null 2>&1; assert_exit "top only (a path with a line feed): start exits 3" 3 "$?"
assert_true "top only (a path with a line feed): no run state below it" '[ ! -e "$NL/tree/.claude/.idd/state/idd-all-rest.json" ]'
rq next --cwd "$NL/tree" --repo "$REPO" --token "$NO_TOKEN_YET" > /dev/null 2>&1; assert_exit "top only (a path with a line feed): next exits 3" 3 "$?"

# spec-example: idd-all-rest / existing work on GitHub is found by next
PR12='[{"number": 12, "body": "Refs #5", "headRefName": "feature-x", "headRefOid": "1111111111111111111111111111111111111111", "createdAt": "2021-01-01T00:00:00Z", "url": "https://example.invalid/pull/12"}]'
new ew-clear 5 9
run start --path PR --review no > /dev/null 2>&1
assert_eq "existing work (nothing): next hands out #5" "5" "$(run next 2> /dev/null | jget next)"
new ew-pr 5 9
printf '%s' "$PR12" > "$G/prs-open.json"
run start --path PR --review no > /dev/null 2>&1
assert_eq "existing work (an open pull request declares #5): next hands out #9" "9" "$(run next 2> /dev/null | jget next)"
assert_grep_re "existing work (pull request): the reason begins with existing work and names pull request #12" '^existing work: .*#12' "$(attempt 5 reason)"
assert_true "existing work (pull request): no directory was made for #5" '[ ! -e "$(dir_of 5)" ]'
new ew-branch 5 9
git clone -q "$T.origin.git" "$S/other" 2>/dev/null; git -C "$S/other" checkout -q -b idd/5-x; printf 'w\n' > "$S/other/w.txt"
git -C "$S/other" add w.txt; git -C "$S/other" commit -q -m "work (#5)"; git -C "$S/other" push -q origin idd/5-x 2>/dev/null
run start --path PR --review no > /dev/null 2>&1
assert_eq "existing work (a branch of #5 on origin): next hands out #9" "9" "$(run next 2> /dev/null | jget next)"
assert_grep_re "existing work (branch): the reason begins with existing work and names the branch" '^existing work: .*idd/5-x' "$(attempt 5 reason)"
assert_true "existing work (branch): no directory was made for #5" '[ ! -e "$(dir_of 5)" ]'
new ew-unknown 5 9
: > "$G/prs-open.fail"
run start --path PR --review no > /dev/null 2>&1
assert_eq "existing work (the pull requests cannot be read): next hands out neither #5 nor #9" "null" "$(run next 2> /dev/null | jget next)"
assert_grep_re "existing work (not determined): the reason says so" '^existing work: could not be determined' "$(attempt 5 reason)"
assert_true "existing work (not determined): no directory was made for #5" '[ ! -e "$(dir_of 5)" ]'
assert_grep_re "existing work (not determined): #9 is recorded for the same reason" '^existing work: could not be determined' "$(attempt 9 reason)"

new ew-crash 5 9
mkdir -p "$S/copy/lib"; cp "$RQ" "$S/copy/rest-queue.py"; cp -R "$PLUGIN/scripts/lib/." "$S/copy/lib/"
printf '#!/bin/sh\necho "check: crashed" >&2\nexit 1\n' > "$S/copy/check-existing-work.sh"
printf '.claude/worktrees/\n' >> "$T/.git/info/exclude"   # the copy has no writer for that rule beside it
TOKC=$(python3 "$S/copy/rest-queue.py" start --cwd "$T" --repo "$REPO" --path PR --review no 2> /dev/null | sed -n 's/^token: //p')
OUT=$(python3 "$S/copy/rest-queue.py" next --cwd "$T" --repo "$REPO" --token "$TOKC" 2> /dev/null)
assert_eq "existing work (the check itself fails): nothing is handed out" "null" "$(printf '%s' "$OUT" | jget next)"
assert_grep_re "existing work (the check itself fails): the reason says it could not be determined" '^existing work: could not be determined' "$(attempt 5 reason)"

# spec-example: idd-all-rest / record leaves every directory as it was
# Scenario: a merged issue keeps its directory
leave_rows
new whole-listing 5 9
begin; D=$(dir_of 5)
python3 "$HERE/treecheck.py" whole "$D" > "$S/w1.txt"
mkdir -p "$D/.claude/.idd"; printf '{"n":1}\n' > "$D/$ROUTING"
python3 "$HERE/treecheck.py" whole "$D" > "$S/w2.txt"
assert_true "listing of a directory: a routing log written in it shows" '! cmp -s "$S/w1.txt" "$S/w2.txt"'
printf 'x\n' >> "$D/.git/description"
python3 "$HERE/treecheck.py" whole "$D" > "$S/w3.txt"
assert_true "listing of a directory: a changed file of its git directory shows" '! cmp -s "$S/w2.txt" "$S/w3.txt"'
new record-leaves-merged 5 9
begin; D=$(dir_of 5); pushed; python3 "$HERE/treecheck.py" whole "$D" > "$S/dir-before.txt"; echo CLOSED > "$G/state-5"
OUT=$(run record --issue 5 2> /dev/null)
assert_eq "record (a merged and closed issue): the outcome is closed and the directory is printed" "closed|$D" "$(printf '%s' "$OUT" | jget outcome)|$(printf '%s' "$OUT" | jget dir)"
python3 "$HERE/treecheck.py" whole "$D" > "$S/dir-after.txt"
require "record (a merged and closed issue): the directory is there, as it was" cmp -s "$S/dir-before.txt" "$S/dir-after.txt"

# spec-example: idd-all-rest / the starting working tree is the same after every ending
# Scenario: a run changes nothing in the working tree it was started in
tree_row() { # name → the state s_<name> of the directory, in a repository a person is working in: its listing before start and after report
  new "tree-$1" 5 9; person_tree
  python3 "$HERE/treecheck.py" list "$T" > "$S/before.txt"
  begin; D=$(dir_of 5); "s_$1"
  run record --issue 5 --reason x > /dev/null 2>&1; run next > /dev/null 2>&1; run record --issue 9 --reason y > /dev/null 2>&1
  run report > "$S/report.out" 2>&1
  python3 "$HERE/treecheck.py" list "$T" > "$S/after.txt"
  assert_true "starting working tree ($1): the same before start and after report (a fetch may bring tags of origin)" 'python3 "$HERE/treecheck.py" same "$S/before.txt" "$S/after.txt"'
  python3 "$HERE/treecheck.py" same "$S/before.txt" "$S/after.txt" || diff "$S/before.txt" "$S/after.txt" | sed -n 1,8p
  assert_output_grep "starting working tree ($1): the run ended with its report" "rest run report" "$S/report.out"
}
for name in $LEAVE_NAMES; do tree_row "$name"; done

# spec-example: idd-all-rest / reading the starting working tree does not write its index
new index-bytes 5 9
printf 'd\n' > "$T/d.txt"; git -C "$T" add d.txt; git -C "$T" commit -q -m d; touch -t 202001010000 "$T/d.txt"
IDX=$(git -C "$T" rev-parse --git-path index); case "$IDX" in /*) ;; *) IDX="$T/$IDX" ;; esac
BEFORE=$(shasum "$IDX" | cut -d' ' -f1)
begin; run record --issue 5 --reason x > /dev/null 2>&1
assert_eq "the index of the starting working tree: its bytes are those before start" "$BEFORE" "$(shasum "$IDX" | cut -d' ' -f1)"

# spec-example: idd-all-rest / a change of the starting working tree is reported
# a run whose starting directory is given through a symbolic link (a synced folder, /tmp on macOS): every command
# resolves --cwd, next prints the directory below the real path, and here and init agree with it
new root-link 5 9
ln -s "$T" "$S/link"
K=$(rq start --cwd "$S/link" --repo "$REPO" --path PR --review no 2> /dev/null | sed -n 's/^token: //p'); assert_true "root through a link: start exits 0 and prints a token" '[ -n "$K" ]'
OUT=$(rq next --cwd "$S/link" --repo "$REPO" --token "$K" 2> /dev/null)
assert_eq "root through a link: next prints the directory below the real path" "$T/.claude/worktrees/rest-5" "$(printf '%s' "$OUT" | jget dir)"
D=$(printf '%s' "$OUT" | jget dir)
(cd "$D" && python3 "$RQ" here --cwd "$D" --repo "$REPO" --issue 5 --token "$K") > /dev/null 2>&1; assert_exit "root through a link: here exits 0 at the directory next printed" 0 "$?"
(cd "$S/link/.claude/worktrees/rest-5" && python3 "$RQ" here --cwd "$S/link/.claude/worktrees/rest-5" --repo "$REPO" --issue 5 --token "$K") > /dev/null 2>&1; assert_exit "root through a link: here exits 1 for the directory named through the link" 1 "$?"
python3 "$PLUGIN/scripts/close-stage.py" init --cwd "$D" --repo "$REPO" --issue 5 --path PR --requested-path PR --interaction unattended --branch idd/5-x --default main --review no --in-chain no --rest-root "$S/link" --rest-token "$K" > /dev/null 2>&1; assert_exit "root through a link: init takes the rest root through the link" 0 "$?"
rq record --cwd "$S/link" --repo "$REPO" --issue 5 --token "$K" --reason x > /dev/null 2>&1; assert_exit "root through a link: record exits 0" 0 "$?"

new root-same 5 9
begin; run record --issue 5 --reason x > /dev/null 2>&1; rc=$?; run report > "$S/report.out" 2>&1
assert_exit "starting working tree (nothing happens): record exits 0" 0 "$rc"
refute_output_grep "starting working tree (nothing happens): the report says nothing about it" "this working tree changed" "$S/report.out"
new root-file 5 9
begin; printf 'edited\n' >> "$T/a.txt"; run record --issue 5 --reason x > /dev/null 2>&1; rc=$?; run report > "$S/report.out" 2>&1
assert_exit "starting working tree (a file is changed): record exits 0" 0 "$rc"
assert_output_grep "starting working tree (a file is changed): the report says the files changed while #5 ran" "while it ran, this working tree changed (the files)" "$S/report.out"
assert_output_grep "starting working tree (a file is changed): and that rest mode does not write there" "rest mode does not write there" "$S/report.out"
new root-commit 5 9
begin; printf 'c\n' > "$T/c.txt"; git -C "$T" add c.txt; git -C "$T" commit -q -m "by a person"; run record --issue 5 --reason x > /dev/null 2>&1; run report > "$S/report.out" 2>&1
assert_output_grep "starting working tree (a commit is made): the report says the checked-out commit changed" "this working tree changed (the checked-out commit)" "$S/report.out"
new root-again 5 9
printf 'changed\n' >> "$T/a.txt"   # already listed as changed when #5 is handed out
begin; printf 'once more\n' >> "$T/a.txt"; run record --issue 5 --reason x > /dev/null 2>&1; rc=$?; run report > "$S/report.out" 2>&1
assert_exit "starting working tree (a file already changed is changed once more): record exits 0" 0 "$rc"
refute_output_grep "starting working tree (a file already changed is changed once more): the report says nothing about it, as git lists the same" "this working tree changed" "$S/report.out"
new root-stash 5 9
begin; printf 'edited\n' >> "$T/a.txt"; git -C "$T" stash -q; run record --issue 5 --reason x > /dev/null 2>&1; run report > "$S/report.out" 2>&1
assert_output_grep "starting working tree (a stash is made): the report says the stash changed" "this working tree changed (the stash)" "$S/report.out"

# spec-example: idd-all-rest / the existing-work check removes no tag
new prune-tags 5
git -C "$T" config fetch.pruneTags true; git -C "$T" config remote.origin.pruneTags true
git -C "$T" tag mytag; TAGSHA=$(git -C "$T" rev-parse mytag)
run start --path PR --review no > /dev/null 2>&1
assert_eq "no tag pruned: next hands out #5" "5" "$(run next 2> /dev/null | jget next)"
assert_eq "no tag pruned: mytag is still there at the same commit" "$TAGSHA" "$(git -C "$T" rev-parse -q --verify refs/tags/mytag)"

# spec-example: idd-all-rest / the folder of the directories is ignored before a run starts
new ignore-dirs 5
assert_eq "folder of the directories: no rule covers it before the run" "1" "$(git -C "$T" check-ignore -q .claude/worktrees/rest-0/x; echo $?)"
run start --path PR --review no > /dev/null 2>&1; assert_exit "folder of the directories: start exits 0" 0 "$?"
run next > /dev/null 2>&1
assert_eq "folder of the directories: git status lists nothing below it after next" "0" "$(git -C "$T" status --porcelain --untracked-files=all | grep -c 'claude/worktrees')"
assert_true "folder of the directories: the rule is in the local exclude file" 'grep -q "^\.claude/worktrees/$" "$T/.git/info/exclude"'
assert_eq "folder of the directories: and no tracked file was changed" "" "$(git -C "$T" status --porcelain --untracked-files=no)"

# spec-example: idd-all-rest / the report names the directory of every issue
new report-dirs 5 9
begin; D=$(dir_of 5); printf 'changed\n' >> "$D/a.txt"; run record --issue 5 --reason "verify gate: not_clean" > /dev/null 2>&1
run next > /dev/null 2>&1; echo CLOSED > "$G/state-9"; D9=$(dir_of 9); run record --issue 9 > /dev/null 2>&1
issues 5; run report > "$S/report.out" 2>&1
assert_grep "report (every directory): the entry of #5 names its directory" "its directory: $D" "$(awk '/^  #5 /{f=1; next} f&&/^    /{print; next} f{exit}' "$S/report.out")"
assert_grep "report (every directory): the entry of #9 names its directory" "its directory: $D9" "$(awk '/^  #9($| )/{f=1; next} f&&/^    /{print; next} f{exit}' "$S/report.out")"
assert_output_grep "report (every directory): one line says rest mode removes no directory" "rest mode removes no directory" "$S/report.out"
assert_output_grep "report (every directory): and that a person looks at it and deletes it" "Look at a directory and delete it" "$S/report.out"
assert_eq "report (every directory): the directory of #5 still holds the changed a.txt" "changed" "$(tail -1 "$D/a.txt")"
assert_eq "report (every directory): no line under a stopped issue names /idd-all" "0" "$(stopped_block "$S/report.out" | grep -c '/idd-all')"
rm -rf "$D"   # the step the report names
run start --path PR --review no > /dev/null 2>&1
assert_eq "report (every directory): once it is deleted, a new run hands #5 out again" "5" "$(run next 2> /dev/null | jget next)"

# spec-example: idd-all-rest / the report names the directory of an issue in flight
new report-flight-dir 5
begin; run report > "$S/report.out" 2>&1
assert_output_grep "report (in flight): #5 is named as handed out without a recorded outcome" "handed out, no outcome recorded (1): #5" "$S/report.out"
assert_true "report (in flight): a line under it names its directory" 'grep -Fx "    its directory: $(dir_of 5)" "$S/report.out" > /dev/null'

# spec-example: idd-all-rest / the report prints a path as it is
LONG="report  path/$(printf 'y%.0s' $(seq 1 150))/$(printf 'z%.0s' $(seq 1 160))"
new "$LONG" 5 9
assert_true "report (a path as it is): the path of T holds two spaces in a row and is longer than 300 characters" 'case "$T" in *"  "*) [ "${#T}" -gt 300 ] ;; *) false ;; esac'
begin; run record --issue 5 --reason x > /dev/null 2>&1; run report > "$S/report.out" 2>&1
assert_true "report (a path as it is): a line is four spaces, a label and the path of the directory exactly" 'grep -Fx "    its directory: $(dir_of 5)" "$S/report.out" > /dev/null'

# spec-example: idd-all-rest / the report names a temporary folder that is left
new report-tmp 5 9
begin; D=$(dir_of 5); unmade; rm -rf "$D"
LEFT="$T/.claude/worktrees/.rest-5-left"; mkdir -p "$LEFT"; printf 'half\n' > "$LEFT/partial.txt"   # what a next that was ended during the clone left
python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); s["attempts"][0]["tmps"]=[sys.argv[2]]; json.dump(s, open(p,"w"))' "$(state_file)" "$LEFT"
OUT=$(run next 2> /dev/null)
assert_eq "report (a temporary folder): the next after it hands out #5 again, made in a new folder" "5|true" "$(printf '%s' "$OUT" | jget next)|$(printf '%s' "$OUT" | jget in_flight)"
run record --issue 5 --reason x > /dev/null 2>&1; run report > "$S/report.out" 2>&1
UNDER5=$(awk '/^  #5 /{f=1; next} f&&/^    /{print; next} f{exit}' "$S/report.out")
assert_grep "report (a temporary folder): under #5 it names the directory" "its directory: $D" "$UNDER5"
assert_grep "report (a temporary folder): and the folder that was left" "$LEFT" "$UNDER5"
assert_eq "report (a temporary folder): which is still there" "half" "$(cat "$LEFT/partial.txt" 2>/dev/null)"

echo "── start, next and the branch step ──"
# spec-example: idd-all-rest / fewer comments than the issue has
new comments-short 5:diag=Simple,comments=130
printf '[{"assoc": "MEMBER", "body": "one", "login": "me", "type": "User"}]' > "$G/comments-5.json"
rq list --repo "$REPO" --json > "$S/out" 2> "$S/err"; rc=$?
assert_true "fewer comments than the issue has: list does not exit 0" "[ $rc != 0 ]"
assert_eq "fewer comments than the issue has: and prints no list" "" "$(cat "$S/out")"
assert_output_grep "fewer comments than the issue has: the reason says the comments were not read completely" "comments of #5" "$S/err"

# spec-example: idd-all-rest / the step that creates the branch does not overwrite a file git ignores
new step05 5
printf '.vscode/\n' >> "$T/.git/info/exclude"; mkdir -p "$T/.vscode"; printf 'MINE\n' > "$T/.vscode/settings.json"
git clone -q "$T.origin.git" "$S/other" 2>/dev/null; mkdir -p "$S/other/.vscode"; printf 'TEAM\n' > "$S/other/.vscode/settings.json"
git -C "$S/other" add .vscode; git -C "$S/other" commit -q -m "team settings"; git -C "$S/other" push -q origin main 2>/dev/null
CREATE=$(grep -F -- '--no-track -b "$BRANCH" "origin/$DEFAULT"' "$SKILL" | grep -F 'git -C')
assert_eq "skill: one line of Step 0.5 creates the branch from the remote default branch" "1" "$(printf '%s\n' "$CREATE" | grep -c .)"
assert_grep "skill: it checks out in the way that does not overwrite a file git ignores" "--no-overwrite-ignore" "$CREATE"
assert_grep "skill: and so does the line that takes up a branch on the remote" "--no-overwrite-ignore" "$(grep -F 'git -C' "$SKILL" | grep -F -- '-b "$BRANCH" "origin/$BRANCH"')"
git -C "$T" fetch -q origin main
(CWD="$T"; BRANCH=idd/5-x; DEFAULT=main; eval "$(printf '%s\n' "$CREATE" | sed 's/ *|| abort.*$//; s/ *#.*$//')") > /dev/null 2> "$S/git.err"; rc=$?
assert_true "step 0.5: that line, run as it is written, fails while the file is in the way" "[ $rc != 0 ]"
assert_eq "step 0.5: and the file still holds what it held" "MINE" "$(cat "$T/.vscode/settings.json")"
assert_output_grep "step 0.5: git names the file" ".vscode/settings.json" "$S/git.err"

# spec-example: idd-all-rest / an issue with a local branch is recorded, not handed out
new local-branch 5 9
git -C "$T" branch idd/5-old
run start --path PR --review no > "$S/start.out" 2>&1
assert_output_grep "start: says a candidate with a pull request or branch is recorded as existing work" "recorded as existing work when its turn comes" "$S/start.out"
refute_output_grep "start: says nothing about attachment files" "attachment files" "$S/start.out"

# spec-example: idd-all-rest / candidates with a local branch are listed apart
assert_output_grep "start: the run order names #9 and not #5" "to run (1): #9" "$S/start.out"
assert_output_grep "start: and #5 is on a line of its own, as a candidate with a local branch" "candidates with a local branch or a directory an earlier run kept, recorded as existing work when their turn comes (1): #5" "$S/start.out"
assert_eq "local branch: next hands out #9" "9" "$(run next | jget next)"
assert_eq "local branch: #5 is recorded as stopped with the branch" "stopped|existing work: local branch idd/5-old" \
  "$(python3 -c 'import json,sys; a=json.load(open(sys.argv[1]))["attempts"][0]; print(a["outcome"] + "|" + a["reason"]) if a["issue"] == 5 else print("not #5")' "$(state_file)")"
new local-branch-other 5 9
git -C "$T" branch idd/50-x; git -C "$T" branch idd/5x
assert_eq "local branch: a branch of another issue does not count" "5" "$(run start --path PR --review no > /dev/null 2>&1; run next | jget next)"
new local-branch-all 5
git -C "$T" branch idd/5
assert_eq "local branch: when every candidate has one, the run is done" "true" "$(run start --path PR --review no > /dev/null 2>&1; run next | jget done)"

# spec-example: idd-all-rest / a run state that git would track
new tracked 5
: > "$T/.git/info/exclude"
run start --path PR --review no > "$S/out" 2> "$S/err"; rc=$?
assert_exit "tracked state: start exits 3" 3 "$rc"
assert_output_grep "tracked state: its reason line names the folder" ".claude/.idd/state/" "$S/err"
assert_output_grep "tracked state: and says how to ignore it" "info/exclude" "$S/err"
assert_file_absent "tracked state: no run state file exists" "$(state_file)"
assert_true "tracked state: nothing was written in the tree" '[ -z "$(git -C "$T" status --porcelain)" ]'
new nogit 5
rm -rf "$T/.git"
run start --path PR --review no > /dev/null 2>&1; assert_exit "start: a folder that is not a git working tree exits 3" 3 "$?"
new one-file 5
printf '.claude/.idd/state/idd-all-rest.json\n' > "$T/.git/info/exclude"
run start --path PR --review no > /dev/null 2> "$S/err"; assert_exit "start: ignoring only the run state file is not enough (the folder holds other state)" 3 "$?"
assert_output_grep "start: and the reason names the folder" ".claude/.idd/state/" "$S/err"

# spec-example: idd-all-rest / a run that is not on the PR path is refused
new not-pr 5
rq start --cwd "$T" --repo "$REPO" --path direct-commit --review no > "$S/out" 2> "$S/err"; rc=$?
assert_exit "not PR: start exits 3" 3 "$rc"
assert_output_grep "not PR: its reason line names --pr" "--pr" "$S/err"
assert_output_grep "not PR: and the path it was given" "direct-commit" "$S/err"
assert_output_grep "not PR: it says that --pr takes the place of --no-pr" "in place of --no-pr" "$S/err"
assert_file_absent "not PR: no run state file exists" "$(state_file)"
assert_file_absent "not PR: gh was not called" "$G/calls.log"
refute_grep_re "not PR: the reason holds no /idd-all command line to copy" '/idd-all +--' "$(cat "$S/err")"
rq start --cwd "$T" --repo "$REPO" --review no > /dev/null 2>&1; assert_exit "start: the path is required (usage)" 2 "$?"
rq start --cwd "$T" --repo "$REPO" --path PR > /dev/null 2>&1; assert_exit "start: the review flag is required (usage)" 2 "$?"
rq start --cwd "$T" --repo "$REPO" --path PR --review maybe > /dev/null 2>&1; assert_exit "start: the review flag is yes or no (usage)" 2 "$?"

# spec-example: idd-all-rest / start stores the default branch
new default-branch 5
echo trunk > "$G/default-branch"; git -C "$T" branch -q -m trunk
run start --path PR --review no > /dev/null 2>&1; rc=$?
assert_exit "default branch: start exits 0" 0 "$rc"
assert_eq "default branch: the run state holds the path and the default branch" "PR|trunk" \
  "$(python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print(s["path"] + "|" + s["default"])' "$(state_file)")"
echo other > "$G/default-branch"; run start --path PR --review no > /dev/null 2>&1
assert_eq "default branch: a resumed run keeps the one it stored" "trunk" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["default"])' "$(state_file)")"
new default-bad 5
printf -- '--evil\n' > "$G/default-branch"
run start --path PR --review no > /dev/null 2> "$S/err"; assert_exit "default branch: a name that is not a branch name exits 3" 3 "$?"
assert_file_absent "default branch: and no run state file exists" "$(state_file)"

# spec-example: idd-all-rest / an account without write access cannot start a run
new no-write 5:author=alice
: > "$G/perm-alice.403"
run start --path PR --review no > /dev/null 2> "$S/err"; rc=$?
assert_exit "no write access: start exits 3" 3 "$rc"
assert_output_grep "no write access: its reason says rest mode needs an account with write access" "needs an account with write access" "$S/err"
assert_file_absent "no write access: no run state file exists" "$(state_file)"
new branches-unreadable 5 9
run start --path PR --review no > /dev/null 2>&1; rm -rf "$T/.git"
run next > /dev/null 2> "$S/err"; assert_exit "next: git that cannot list the local branches exits 3" 3 "$?"
assert_eq "next: with one reason line" "1" "$(wc -l < "$S/err" | tr -d ' ')"

echo "── the lock of a run ──"
# spec-example: idd-all-rest / two sessions at the same run
# Scenario: a second command waits for the first
new lock-next 5 9
run start --path PR --review no > /dev/null 2>&1
IDD_REST_SLEEP_BEFORE_MAKE=3 run next > "$S/first.out" 2>&1 &
FIRST=$!; sleep 1
OUT=$(IDD_REST_LOCK_WAIT=20 run next 2> /dev/null)
[ -d "$(dir_of 5)" ] && printf 'mine\n' > "$(dir_of 5)/notes.txt"
wait "$FIRST"
assert_eq "lock (next and next): the second prints #5 in flight" "5|true" "$(printf '%s' "$OUT" | jget next)|$(printf '%s' "$OUT" | jget in_flight)"
assert_eq "lock (next and next): notes.txt in the directory of #5 is still there" "mine" "$(cat "$(dir_of 5)/notes.txt" 2>/dev/null)"
new lock-record 5 9
begin
IDD_REST_SLEEP_AFTER_READ=2 run record --issue 5 --reason x > /dev/null 2>&1 &
FIRST=$!; sleep 0.5
IDD_REST_LOCK_WAIT=20 run start --path PR --review yes --take-over > /dev/null 2>&1
wait "$FIRST"
assert_eq "lock (record and start --review yes): the run state has review on" "true" "$(python3 -c 'import json,sys; print(str(json.load(open(sys.argv[1]))["review"]).lower())' "$(state_file)")"
new lock-held 5 9
run start --path PR --review no > /dev/null 2>&1; cp "$(state_file)" "$S/before.json"
python3 -c 'import fcntl,sys,time; f=open(sys.argv[1],"a"); fcntl.flock(f, fcntl.LOCK_EX); time.sleep(4)' "$T/.claude/.idd/state/idd-all-rest.lock" &
HOLD=$!; sleep 0.5
IDD_REST_LOCK_WAIT=1 run next > /dev/null 2> "$S/err"; rc=$?
wait "$HOLD"
assert_exit "lock (held longer than the wait): next exits 4" 4 "$rc"
assert_output_grep "lock (held longer than the wait): its reason says another rest command is going on" "another rest command for this run is going on" "$S/err"
require "lock (held longer than the wait): the run state is unchanged" cmp -s "$S/before.json" "$(state_file)"

echo "── record and the token ──"
new record-done 5 9
begin; D=$(dir_of 5); pushed
FIRST=$(run record --issue 5 --reason x 2> /dev/null)
OUT=$(run record --issue 5 --reason y 2> /dev/null); assert_exit "record: called again for the issue recorded last, with its token, it exits 0" 0 "$?"
assert_eq "record: and prints what it recorded" "$FIRST" "$OUT"
rq record --cwd "$T" --repo "$REPO" --issue 5 --token "$NO_TOKEN_YET" > /dev/null 2>&1; assert_exit "record: called again with another token, it exits 4" 4 "$?"
rq record --cwd "$T" --repo "$REPO" --issue 5 --token wrong > /dev/null 2>&1; assert_exit "record: a token that is not of the form start prints is a usage error (exit 2)" 2 "$?"
run next > /dev/null 2>&1
run record --issue 5 > /dev/null 2>&1; assert_exit "record: once the next issue is handed out, #5 is refused (exit 1)" 1 "$?"
new record-no-token 5 9
begin
rq record --cwd "$T" --repo "$REPO" --issue 5 > /dev/null 2>&1; assert_exit "record: without a token it is a usage error (exit 2)" 2 "$?"

echo "── the run state ──"
new state-no-reason 5
mkdir -p "$T/.claude/.idd/state"
python3 - "$(state_file)" <<'PY'
import json, sys, time
s = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
json.dump({"version": 6, "repo": "o/r", "path": "PR", "default": "main", "review": False, "started_at": s, "updated_at": s, "stop": None,
           "token_digest": __import__("hashlib").sha256(b"00112233445566778899aabb").hexdigest(),
           "attempts": [{"issue": 5, "outcome": "stopped", "handed_at": s, "recorded_at": s}]}, open(sys.argv[1], "w"))
PY
run start --path PR --review no > "$S/start.out" 2>&1; rc=$?
assert_exit "state: an attempt without a reason is not used: start stops (exit 3)" 3 "$rc"
assert_output_grep "state: and start says so" "cannot be used" "$S/start.out"
new state-bad-time 5
write_state 1 '[]'
python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); s["started_at"]="yesterday\nFORGED"; json.dump(s, open(p,"w"))' "$(state_file)"
run start --path PR --review no > "$S/start.out" 2>&1
assert_output_grep "state: a start time that is not a time is not used" "cannot be used" "$S/start.out"
refute_output_grep "state: and is not printed" "FORGED" "$S/start.out"
new state-bad-kept 5
write_state 1 '[{"issue": 5, "outcome": "stopped", "reason": "x", "left": "kept", "dir": "/x/rest-5", "why": [5]}]'
run start --path PR --review no > "$S/start.out" 2>&1
assert_output_grep "state: a reason for keeping a directory that is not text is not used" "cannot be used" "$S/start.out"
new state-bad-path 5
write_state 1 '[{"issue": 5, "outcome": "stopped", "reason": "x", "dir": "/x/rest\u0007-5", "made": true}]'
run start --path PR --review no > "$S/start.out" 2>&1
assert_output_grep "state: a directory whose path cannot be printed as it is is not used" "cannot be used" "$S/start.out"
new state-bad-dir 5
write_state 1 '[{"issue": 5, "outcome": null, "reason": "", "dir": "rest-5"}]'
run start --path PR --review no > "$S/start.out" 2>&1
assert_output_grep "state: a directory that is not an absolute path is not used" "cannot be used" "$S/start.out"

for field in path default review token_digest; do
  new "state-no-$field" 5
  write_state 1 '[{"issue": 5, "outcome": "stopped", "reason": "x"}]'
  python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); del s[sys.argv[2]]; json.dump(s, open(p,"w"))' "$(state_file)" "$field"
  run start --path PR --review no > "$S/start.out" 2>&1
  assert_output_grep "state: a state without a stored $field is not used" "cannot be used" "$S/start.out"
done
new state-other-path 5
write_state 1 '[{"issue": 5, "outcome": "stopped", "reason": "x"}]'
python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); s["path"]="direct-commit"; json.dump(s, open(p,"w"))' "$(state_file)"
run start --path PR --review no > "$S/start.out" 2>&1
assert_output_grep "state: a state of a run on another path is not used" "cannot be used" "$S/start.out"
# spec-example: idd-all-rest / a state that cannot be used
age() { python3 -c 'import os,sys,time; t=time.time()-float(sys.argv[2])*3600; os.utime(sys.argv[1], (t, t))' "$1" "$2"; }
new unusable-now 5
mkdir -p "$T/.claude/.idd/state"; printf '{"review": tr' > "$(state_file)"
run start --path PR --review no > /dev/null 2> "$S/err"; assert_exit "unusable state: text that is not JSON, written now, stops start (exit 3)" 3 "$?"
assert_output_grep "unusable state: the reason names the file" "idd-all-rest.json" "$S/err"
assert_eq "unusable state: and the file is unchanged" '{"review": tr' "$(cat "$(state_file)")"
new unusable-v5 5
write_state 1 '[{"issue": 5, "outcome": null, "reason": "", "token": "t"}]'
python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); s["version"]=5; s["review"]=True; s.pop("token_digest"); json.dump(s, open(p,"w"))' "$(state_file)"
BEFORE=$(cat "$(state_file)")
run start --path PR --review no > /dev/null 2> "$S/err"; assert_exit "unusable state: a state of the previous version, an hour old, stops start (exit 3)" 3 "$?"
assert_eq "unusable state: and the file is unchanged" "$BEFORE" "$(cat "$(state_file)")"
new unusable-old 5
mkdir -p "$T/.claude/.idd/state"; printf '{"review": tr' > "$(state_file)"; age "$(state_file)" 25
run start --path PR --review no > "$S/start.out" 2>&1; assert_exit "unusable state: the same text written 25 hours ago is replaced by a new run (exit 0)" 0 "$?"
assert_output_grep "unusable state: and start says that it replaced a file it could not use" "cannot be used" "$S/start.out"
for hours in 1 25; do
  new "state-link-$hours" 5
  write_state "$hours" '[]'; mv "$(state_file)" "$S/real.json"; ln -s "$S/real.json" "$(state_file)"
  python3 -c 'import os,sys,time; t=time.time()-float(sys.argv[2])*3600; os.utime(sys.argv[1], (t, t), follow_symlinks=False)' "$(state_file)" "$hours"
  REAL=$(cat "$S/real.json")
  run start --path PR --review no > "$S/start.out" 2>&1; rc=$?
  if [ "$hours" = 1 ]; then
    assert_exit "a state file that is a link, 1 hour old: start exits 3" 3 "$rc"
    assert_output_grep "a state file that is a link, 1 hour old: and names the file" "idd-all-rest.json" "$S/start.out"
    assert_true "a state file that is a link, 1 hour old: the link is unchanged" '[ -L "$(state_file)" ]'
  else
    assert_exit "a state file that is a link, 25 hours old: start exits 0" 0 "$rc"
    assert_true "a state file that is a link, 25 hours old: the link is replaced by a file" '[ -f "$(state_file)" ] && [ ! -L "$(state_file)" ]'
  fi
  assert_eq "a state file that is a link ($hours h): the file it pointed at is unchanged" "$REAL" "$(cat "$S/real.json")"
done

# spec-example: idd-all-rest / a run that was never reported is not forgotten
forgotten_row() { # name attempt-json → start after a run of 25 hours ago with that attempt; OLD is what it printed of it
  new "forgotten-$1" 9
  write_state 25 "$2"
  run start --path PR --review no > "$S/start.out" 2>&1; assert_exit "forgotten ($1): start exits 0 and begins a new run" 0 "$?"
  OLD=$(awk '/never ended with its report/{f=1; next} /^open issues:/{f=0} f' "$S/start.out")
}
OLDDIR="$WORK/old-run/.claude/worktrees/rest-5"; mkdir -p "$OLDDIR"; printf 'x\n' > "$OLDDIR/a.txt"
forgotten_row made '[{"issue": 5, "outcome": "stopped", "reason": "x", "dir": "'"$OLDDIR"'", "made": true, "left": "left"}]'
assert_grep "forgotten (stopped, made): before the list it names the directory, as it is" "    its directory: $OLDDIR" "$OLD"
assert_grep "forgotten (stopped, made): and the outcome of that issue" "stopped" "$OLD"
OLDHALF="$WORK/old-half/.claude/worktrees/rest-5"; mkdir -p "$OLDHALF"; printf 'half\n' > "$OLDHALF/partial.txt"
forgotten_row half '[{"issue": 5, "outcome": null, "reason": "", "dir": "'"$OLDHALF"'", "made": false}]'
assert_grep "forgotten (in flight, not made): it names the folder at the place" "$OLDHALF" "$OLD"
OLDTMP="$WORK/old-tmp/.claude/worktrees/.rest-5-abc"; mkdir -p "$OLDTMP"
forgotten_row tmp '[{"issue": 5, "outcome": null, "reason": "", "dir": "'"$WORK/old-tmp/.claude/worktrees/rest-5"'", "made": false, "tmps": ["'"$OLDTMP"'"]}]'
assert_grep "forgotten (a temporary folder recorded): it names the temporary folder" "$OLDTMP" "$OLD"
refute_grep "forgotten (a temporary folder recorded): and not the directory, at whose place nothing is" "rest-5$" "$OLD"
echo "── the review flag ──"
# spec-example: idd-all-rest / the review flag across a resumed run
for row in "yes yes yes no" "yes no yes yes" "no yes yes yes" "no no no no"; do
  set -- $row
  new "review-$1-$2" 5
  run start --path PR --review "$1" > /dev/null 2>&1
  run start --path PR --review "$2" --take-over > "$S/start.out" 2>&1; assert_exit "review $1 then $2: start --take-over exits 0" 0 "$?"
  assert_eq "review $1 then $2: next prints review $3" "$3" "$(run next | jget review)"
  assert_eq "review $1 then $2: start says the flag differs: $4" "$4" "$(grep -q 'review flag differs' "$S/start.out" && echo yes || echo no)"
done
# Scenario: the flag is printed for an issue in flight
new review-inflight 5
run start --path PR --review yes > /dev/null 2>&1; run next > /dev/null
assert_eq "review: an issue in flight carries the flag" "true|yes" "$(run next | jget in_flight)|$(run next | jget review)"
# spec-example: idd-all-rest / the close stage cannot be told that review is off
CS="$PLUGIN/scripts/close-stage.py"
init() { # review [directory] [rest root] [token] → close-stage.py init for #5 there (default: the directory of #5,
        # --rest-root T, and the token of the run when the rest root is not none)
  local rr="${3:-$T}" tk="${4:-}"
  [ -n "$tk" ] || { [ "$rr" = none ] && tk=none || tk=$(run_token); }
  python3 "$CS" init --cwd "${2:-$(dir_of 5)}" --repo "$REPO" --issue 5 --path PR --requested-path PR --interaction unattended --branch idd/5-x --default main --review "$1" --in-chain no --rest-root "$rr" --rest-token "$tk"
}
runstate() { [ -f "${1:-$(dir_of 5)}/.claude/.idd/state/idd-all-run-5.json" ] && echo yes || echo no; }
# the rest run (its review, the issue in flight) | where init runs | --rest-root | --review | exit | a run state for #5 exists there
for row in "yes 5 dir T no 64 no" "yes 5 dir T yes 0 yes" "no 5 dir T no 0 yes" "no 5 dir none no 64 no" "no 5 root none no 64 no" "yes 5 root none yes 64 no" "yes 9 root none no 0 yes" "none - root none no 0 yes" "none - root T no 64 no"; do
  set -- $row
  new "init-$1-$2-$3-$4-$5" 5 9
  if [ "$1" != none ]; then
    run start --path PR --review "$1" > /dev/null 2>&1
    [ "$2" = 9 ] && { issues 9; }   # only #9 is a candidate, so it is the one in flight
    run next > /dev/null 2>&1
  fi
  if [ "$3" = dir ]; then AT=$(dir_of 5); else AT="$T"; fi
  if [ "$4" = T ]; then RR="$T"; else RR=none; fi
  init "$5" "$AT" "$RR" > /dev/null 2> "$S/err"; rc=$?
  assert_exit "init: rest review $1, #$2 in flight, run in the $3, --rest-root $4, --review $5 exits $6" "$6" "$rc"
  assert_eq "init: and a run state for #5 exists there: $7" "$7" "$(runstate "$AT")"
  if [ "$4" = none ] && [ "$2" = 5 ]; then
    assert_output_grep "init: with none and #5 in flight, the message names the directory of #5" "$(dir_of 5)" "$S/err"
  fi
done
new init-ways-out 5 9
run start --path PR --review yes > /dev/null 2>&1; run next > /dev/null 2>&1
init no > /dev/null 2> "$S/err"
assert_output_grep "init: its message names the other way out, ending the rest run" "end the rest run" "$S/err"
new init-stale 5
write_state 25 '[{"issue": 5, "outcome": null}]'
python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); s["review"]=True; json.dump(s, open(p,"w"))' "$(state_file)"
init no "$T" none > /dev/null 2>&1; assert_exit "init: a rest state older than 24 hours changes nothing" 0 "$?"
new init-unreadable 5
mkdir -p "$T/.claude/.idd/state"; printf '{"review": tr' > "$(state_file)"
init no "$T" none > /dev/null 2>&1; assert_exit "init: a rest state that cannot be read changes nothing" 0 "$?"

# spec-example: idd-all-rest / init binds the issue to its directory
rec_root() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("rest_root"))' "$(dir_of 5)/.claude/.idd/state/idd-all-run-5.json" 2> /dev/null || echo none; }
bind_row() { # name what-happened init-args exit the-run-of-#5-afterwards
  new "bind-$1" 5 9; begin; D=$(dir_of 5)
  eval "$2"
  eval "init no $3" > /dev/null 2> "$S/err"; rc=$?
  assert_exit "init binds ($1): exits $4" "$4" "$rc"
  local want="$5"; [ "$want" = T ] && want="$T"   # T of this scenario, which new has just made
  assert_eq "init binds ($1): the run of #5 there afterwards" "$want" "$(rec_root)"
}
bind_row token ':' '' 0 T
bind_row other-token ':' '"" "$T" "$NO_TOKEN_YET"' 4 none
bind_row swapped 'mv "$D" "$S/orig"; git clone -q "$T.origin.git" "$D" 2> /dev/null' '' 64 none
bind_row origin 'git -C "$D" remote set-url origin "$S/elsewhere.git"' '' 64 none
bind_row other-root 'mkdir -p "$S/U"' '"" "$S/U"' 64 none
bind_row none-after 'init no > /dev/null 2>&1' '"" none' 64 T

# spec-example: idd-all-rest / review added while an issue is in flight
crun() { python3 "$CS" run --cwd "$(dir_of 5)" --repo "$REPO" --issue 5 --rest-token "${1:-$(run_token)}" 2>/dev/null; }
for added in yes no; do
  new "review-added-$added" 5 9
  run start --path PR --review no > /dev/null 2>&1; run next > /dev/null 2>&1
  init no > /dev/null 2>&1; assert_exit "review added ($added): init records review off while the run has none" 0 "$?"
  run start --path PR --review "$added" --take-over > "$S/start.out" 2>&1
  [ "$added" = yes ] && assert_output_grep "review added (yes): start says a close stage that is already running is not stopped by it" "already running" "$S/start.out"
  OUT=$(crun); rc=$?
  [ "$added" = yes ] && assert_exit "review added (yes): the close stage stops (exit 3)" 3 "$rc"
  assert_eq "review added ($added): the reason is the review flag of the rest run: $added" "$added" \
    "$(printf '%s' "$OUT" | jget reason | grep -q 'the rest run has --review' && echo yes || echo no)"
done
# Scenario: a rest run state that cannot be read stops the close stage
new review-state-unreadable 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null 2>&1; init no > /dev/null 2>&1
printf '{"review": tr' > "$(state_file)"
OUT=$(crun); assert_exit "review: a rest state that cannot be read stops the close stage (exit 3)" 3 "$?"
assert_grep "review: and the reason says its review flag is unknown" "review flag is unknown" "$(printf '%s' "$OUT" | jget reason)"
# spec-example: idd-all-rest / a run that is gone stops the close stage of a rest issue
for gone in no resumed replaced; do
  new "run-gone-$gone" 5 9
  run start --path PR --review no > /dev/null 2>&1; run next > /dev/null 2>&1; init no > /dev/null 2>&1
  case "$gone" in
    resumed) run start --path PR --review yes --take-over > /dev/null 2>&1; run report > /dev/null 2>&1 ;;
    replaced) run report > /dev/null 2>&1; issues 9; run start --path PR --review no > /dev/null 2>&1; run next > /dev/null 2>&1 ;;
  esac
  OUT=$(crun); rc=$?
  if [ "$gone" = no ]; then
    refute_grep "run gone (no): the close stage does not give that reason" "cannot be found" "$(printf '%s' "$OUT" | jget reason)"
  else
    assert_exit "run gone ($gone): the close stage stops (exit 3)" 3 "$rc"
    assert_grep "run gone ($gone): and its reason says the rest run of the issue cannot be found" "cannot be found" "$(printf '%s' "$OUT" | jget reason)"
  fi
done
# spec-example: idd-all-rest / the close stage of a session that was taken over (the rows that stop before the merge
# are here; the two that need a pull request ready to merge are in the close-stage suite)
new taken-over-cs 5 9
begin; init no > /dev/null 2>&1; K=$(run_token)
OUT=$(crun); refute_grep "close stage (with the token of the run): gives no reason of the other rows" "token" "$(printf '%s' "$OUT" | jget reason)"
OUT=$(python3 "$CS" run --cwd "$(dir_of 5)" --repo "$REPO" --issue 5 2> /dev/null); rc=$?
assert_exit "close stage (without --rest-token): exits 3" 3 "$rc"
assert_grep "close stage (without --rest-token): its reason says no token of the rest run was given" "no token of the rest run was given" "$(printf '%s' "$OUT" | jget reason)"
run start --path PR --review no --take-over > /dev/null 2>&1
OUT=$(crun "$K"); rc=$?
assert_exit "close stage (with the token of a start that was taken over): exits 3" 3 "$rc"
assert_grep "close stage (with the token of a start that was taken over): another session has taken the rest run over" "another session has taken the rest run over" "$(printf '%s' "$OUT" | jget reason)"
# spec-example: idd-all-rest / every command of a run takes its token
new token-table 5 9
begin; D=$(dir_of 5); cp "$(state_file)" "$S/before.json"
CMDS=$(python3 - "$RQ" <<'TABLE_PY'
import runpy, sys
g = runpy.run_path(sys.argv[1], run_name="probe")
print(" ".join(sorted(g["COMMANDS"])) + "|" + " ".join(g["NO_TOKEN"]))
TABLE_PY
)
EXEMPT=${CMDS#*|}
assert_eq "token table: the commands of rest-queue.py that take no token are args, list and start" "args list start" "$EXEMPT"
for sub in ${CMDS%%|*}; do
  case " $EXEMPT " in *" $sub "*) continue ;; esac
  case "$sub" in
    next|where|report|here) args=() ;;
    record) args=(--issue 5 --reason x) ;;
    stop) args=(--reason x) ;;
    *) assert_true "token table: the command $sub has a row in this table" false; continue ;;
  esac
  if [ "$sub" = here ]; then
    here_in "$D" 5 "$NO_TOKEN_YET" > /dev/null 2>&1; rc=$?
    (cd "$D" && python3 "$RQ" here --cwd "$D" --repo "$REPO" --issue 5) > /dev/null 2>&1; rc2=$?
  else
    rq "$sub" --cwd "$T" --repo "$REPO" ${args[@]+"${args[@]}"} --token "$NO_TOKEN_YET" > /dev/null 2>&1; rc=$?
    rq "$sub" --cwd "$T" --repo "$REPO" ${args[@]+"${args[@]}"} > /dev/null 2>&1; rc2=$?
  fi
  assert_exit "token table: $sub with a token that is not the run's exits 4" 4 "$rc"
  assert_exit "token table: $sub without a token is a usage error" 2 "$rc2"
  require "token table: the run state is as it was after $sub" cmp -s "$S/before.json" "$(state_file)"
done
init no "" "$T" "$NO_TOKEN_YET" > /dev/null 2>&1; assert_exit "token table: close-stage.py init with a rest root and a token that is not the run's exits 4" 4 "$?"
assert_eq "token table: and writes no run state" "no" "$(runstate)"
python3 "$CS" init --cwd "$D" --repo "$REPO" --issue 5 --path PR --requested-path PR --interaction unattended --branch b --default main --review no --in-chain no --rest-root "$T" > /dev/null 2>&1
assert_exit "token table: close-stage.py init with a rest root and no --rest-token is a usage error" 64 "$?"
require "token table: the run state is as it was after close-stage.py init" cmp -s "$S/before.json" "$(state_file)"
CSCMDS=$(python3 - "$CS" <<'TABLE_PY'
import runpy, sys
g = runpy.run_path(sys.argv[1], run_name="probe")
print(" ".join(sorted(g["HANDLERS"])) + "|" + " ".join(g["REST_TOKEN"]))
TABLE_PY
)
assert_eq "token table: the commands of close-stage.py that take the token of a rest run are init, run and reset" "init run reset" "${CSCMDS#*|}"
python3 "$CS" reset --cwd "$D" --issue 5 --rest-token "$NO_TOKEN_YET" > /dev/null 2>&1; assert_exit "token table: close-stage.py reset in the directory of #5 with a token that is not the run's exits 4" 4 "$?"
python3 "$CS" reset --cwd "$D" --issue 5 > /dev/null 2>&1; assert_exit "token table: and without one" 4 "$?"
for sub in ${CSCMDS%%|*}; do   # every other one is known not to read a rest run's state as its own (rest-review reads it and takes no token)
  case "$sub" in init|run|rest-review|reset|gate|pr-check|confirm-close) ;; *) assert_true "token table: close-stage.py $sub is in neither list" false ;; esac
done
# spec-example: idd-all-rest / a session that was taken over writes nothing for its issue
new displaced-writes 5 9
begin; init no > /dev/null 2>&1; K=$(run_token); D=$(dir_of 5); SD="$D/.claude/.idd/state"
printf '{"status": "stopped", "reason": "earlier"}\n' > "$SD/idd-all-result-5.json"
cp "$SD/idd-all-run-5.json" "$S/run-before.json"; cp "$SD/idd-all-result-5.json" "$S/result-before.json"
run start --path PR --review no --take-over > /dev/null 2>&1
python3 "$CS" reset --cwd "$D" --issue 5 --rest-token "$K" > /dev/null 2> "$S/err"; assert_exit "taken over: reset with the earlier token exits 4" 4 "$?"
python3 "$CS" reset --cwd "$D" --issue 5 > /dev/null 2>&1; assert_exit "taken over: reset without a token exits 4" 4 "$?"
OUT=$(crun "$K"); rc=$?
assert_exit "taken over: run with the earlier token exits 3" 3 "$rc"
assert_grep "taken over: and says another session has taken the rest run over" "another session has taken the rest run over" "$(printf '%s' "$OUT" | jget reason)"
require "taken over: the run state of #5 is as it was" cmp -s "$S/run-before.json" "$SD/idd-all-run-5.json"
require "taken over: the result file of #5 is as it was" cmp -s "$S/result-before.json" "$SD/idd-all-result-5.json"
python3 "$CS" reset --cwd "$D" --issue 5 --rest-token "$(run_token)" > /dev/null 2>&1; assert_exit "taken over: reset with the token of the run exits 0" 0 "$?"

# spec-example: idd-all-rest / here refuses an earlier token first
new here-first 5 9
begin; K=$(run_token); run start --path PR --review no --take-over > /dev/null 2>&1
run record --issue 5 --reason x > /dev/null 2>&1; run next > /dev/null 2>&1
assert_eq "here first: the run has handed out #9" "9" "$(run next 2> /dev/null | jget next)"
here_in "$(dir_of 5)" 5 "$K" > /dev/null 2> "$S/err"; assert_exit "here first: here for #5 with the earlier token exits 4" 4 "$?"
assert_output_grep "here first: and says the token is not the one of this rest run" "the token is not the one of this rest run" "$S/err"

# spec-example: idd-all-rest / an issue of a rest run runs on the PR path only
new rest-pr-only 5 9
begin
python3 "$CS" init --cwd "$(dir_of 5)" --repo "$REPO" --issue 5 --path direct-commit --requested-path direct-commit --interaction unattended --branch main --default main --review no --in-chain no --rest-root "$T" --rest-token "$(run_token)" > /dev/null 2>&1
assert_exit "PR path only: init with a rest root and the direct-commit path exits 64" 64 "$?"
assert_eq "PR path only: and writes no run state" "no" "$(runstate)"
new review-elsewhere 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null 2>&1; init no > /dev/null 2>&1
python3 -c 'import json,sys; r=json.load(open(sys.argv[1])); r["rest_root"]="none"; json.dump(r, open(sys.argv[2],"w"))' "$(dir_of 5)/.claude/.idd/state/idd-all-run-5.json" "$T/.claude/.idd/state/idd-all-run-5.json"   # as if the issue had been recorded where the run was started
OUT=$(python3 "$CS" run --cwd "$T" --repo "$REPO" --issue 5 2>/dev/null); assert_exit "review: the close stage of an issue that runs elsewhere stops (exit 3)" 3 "$?"
assert_grep "review: and the reason says the issue runs in a directory of its own" "in a directory of its own" "$(printf '%s' "$OUT" | jget reason)"

echo "── reasons ──"
# spec-example: idd-all-rest / outcomes by issue state
new closed-reason 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; echo CLOSED > "$G/state-5"
OUT=$(run record --issue 5 --reason 'Stopped: /idd-close did not finish')
assert_eq "record: a closed issue keeps the reason its run reported" "closed|Stopped: /idd-close did not finish" "$(printf '%s' "$OUT" | jget outcome)|$(printf '%s' "$OUT" | jget reason)"
# spec-example: idd-all-rest / a closed issue whose run reported a stop
run report > "$S/report.out" 2>&1
assert_grep_re "report: the closed issue is listed under closed" '^closed \(1\): #5$' "$(cat "$S/report.out")"
assert_output_grep "report: followed by what its run reported" "#5 — its run reported: Stopped: /idd-close did not finish" "$S/report.out"
# spec-example: idd-all-rest / a reason on standard input is taken as it is
new stdin-reason 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
OUT=$(cd "$S" && printf '%s' 'it'"'"'s `whoami` and $(touch made-by-the-reason)' | rq record --cwd "$T" --repo "$REPO" --issue 5 --token "$(token_of 5)" --reason-stdin)
assert_eq "stdin reason: the recorded reason is that text" 'it'"'"'s `whoami` and $(touch made-by-the-reason)' "$(printf '%s' "$OUT" | jget reason)"
assert_file_absent "stdin reason: nothing in it was run" "$S/made-by-the-reason"
printf 'x' | run record --issue 5 --reason y --reason-stdin > /dev/null 2>&1; assert_exit "record: both forms of the reason are a usage error" 2 "$?"
run stop > /dev/null 2>&1; assert_exit "stop: a reason is required (usage)" 2 "$?"
# spec-example: idd-all-rest / a reason copied from the helper keeps its end
new stop-prefix 5
run start --path PR --review no > /dev/null 2>&1
LINE=$(python3 -c 'print("x" * 289 + "and 2 more)")')
printf 'rest-queue: %s' "$LINE" | run stop --reason-stdin > /dev/null 2>&1; assert_exit "stop: a reason on standard input exits 0" 0 "$?"
assert_grep_re "stop: next prints a stop reason that ends with the number of the other paths" 'and 2 more\)$' "$(run next | jget stopped)"
run report > "$S/report.out" 2>&1
assert_grep_re "stop: and so does the report" '^run stopped: x+and 2 more\)$' "$(cat "$S/report.out")"

echo "── the inventory of writers ──"
echo "── the inventory of writers ──"
INVENTORY="$PLUGIN/references/working-tree-writers.md"
assert_true "inventory: the file is there" '[ -f "$INVENTORY" ]'
python3 - "$PLUGIN" "$INVENTORY" > "$WORK/inventory.out" 2>&1 <<'PY'
import os, re, sys
plugin, inventory = sys.argv[1], sys.argv[2]
named = open(inventory, encoding="utf-8").read() if os.path.isfile(inventory) else ""
found = {}
for sub in ("skills", "scripts"):
    for base, dirs, files in os.walk(os.path.join(plugin, sub)):
        dirs[:] = [d for d in dirs if d != "tests"]
        for name in files:
            path = os.path.join(base, name)
            try:
                text = open(path, encoding="utf-8").read()
            except (OSError, UnicodeDecodeError):
                continue
            for m in re.finditer(r"\.claude/(\.idd/)?([A-Za-z0-9_][A-Za-z0-9_.-]*)", text):
                if m.group(2) == ".idd":
                    continue
                found.setdefault(".claude/" + (m.group(1) or "") + m.group(2).rstrip("."), os.path.relpath(path, plugin))
missing = sorted(loc for loc in found if loc not in named)
for loc in missing:
    print(f"not in the inventory: {loc} (named in {found[loc]})")
print(f"inventory: {len(found)} locations, {len(missing)} missing")
PY
assert_output_grep "inventory: every location the skills and scripts name is in it" " 0 missing" "$WORK/inventory.out"
grep -q ' 0 missing' "$WORK/inventory.out" || sed -n '1,30p' "$WORK/inventory.out"

new render-crash 5 9
mkdir -p "$S/copy"; cp "$RQ" "$S/copy/rest-queue.py"; cp -R "$PLUGIN/scripts/lib" "$S/copy/lib"
printf '\n\ndef open_clarity_rows(issue):\n    raise RuntimeError("a failure nobody planned for")\n' >> "$S/copy/lib/intent.py"
OUT=$(python3 "$S/copy/rest-queue.py" list --repo "$REPO" --json 2> "$S/err"); rc=$?
assert_exit "rendering: an unplanned failure reading one rendering does not fail the list" 0 "$rc"
assert_eq "rendering: the issues it hit are unreadable" "[5,9]" "$(printf '%s' "$OUT" | jget classes.unreadable)"

echo "── the skill ──"
# spec-example: idd-all-rest / the skill names the loop commands in order
STEP01=$(awk '/^#### Step 0\.1/{f=1} f&&/^#### Step 0\.2/{exit} f' "$SKILL")
REST=$(awk '/^## Rest mode/{f=1; print; next} f&&/^## /{exit} f' "$SKILL")
assert_grep "skill: Step 0.1 runs the argument classification" 'rest-queue.py" args' "$STEP01"
assert_grep_re "skill: Step 0.1 has a row for no positional argument" '^\| `/idd-all`[^|]*\| rest ' "$STEP01"
assert_grep_re "skill: Step 0.1 has a row for the word rest" '^\| `/idd-all rest`[^|]*\| rest ' "$STEP01"
refute_grep "skill: the two-way question is gone" "建新 issue 還是用既有 issue" "$(cat "$SKILL")"
assert_grep "skill: Step 0.1 says an unquoted description is one argument" "整段算一個引數" "$STEP01"
# spec-example: idd-existing-work-lookup / rest mode records existing work instead of acting on it
assert_grep "skill: the rest section does not take over existing work" 'existing work: ' "$REST"
assert_grep_re "skill: and every verdict other than clear is recorded so" '`verdict=clear` 以外的任何結果' "$REST"
assert_grep "skill: without a question" "不提問" "$(printf '%s\n' "$REST" | grep -F 'verdict=clear')"
STEP051=$(awk '/^#### Step 0\.5\.1/{f=1} f&&/^#### Step 0\.6/{exit} f' "$SKILL")
assert_grep "skill: Step 0.5.1 points at the rest rule" '## Rest mode' "$STEP051"
STOPS=$(printf '%s\n' "$REST" | awk '/^### 整個 run 停下/{f=1; next} f&&/^### /{exit} f' | grep -E '^\| ' | sed -n '2,$p')   # the header row is dropped; the |---| line never matches
assert_eq "skill: the whole-run stop table has five rows" "5" "$(printf '%s\n' "$STOPS" | grep -c '^| ')"
# spec-example: idd-all-rest / the skill handles a busy run
BUSY=$(printf '%s\n' "$STOPS" | grep -E '以 4 結束')
assert_eq "skill: one row is about a command that exits 4" "1" "$(printf '%s\n' "$BUSY" | grep -c '^| ')"
assert_grep "skill: that row ends the invocation without stop or report" '不呼叫 `stop` 也不呼叫 `report`' "$BUSY"
assert_grep "skill: that row names the lock" "鎖" "$(printf '%s\n' "$BUSY" | cut -d'|' -f2)"
assert_grep "skill: and the token that is not the run's" "token 不是這個 run 的" "$(printf '%s\n' "$BUSY" | cut -d'|' -f2)"
assert_grep "skill: and a start without --take-over that finds an unfinished run" '`start` 沒帶 `--take-over`' "$(printf '%s\n' "$BUSY" | cut -d'|' -f2)"
assert_grep "skill: and an init of the close stage that exits 4" '`close-stage.py init`' "$(printf '%s\n' "$BUSY" | cut -d'|' -f2)"
assert_grep "skill: that row says not to call next again" '不再呼叫 `next`' "$BUSY"
assert_grep "skill: nor to take the run back" '不用 `start --take-over` 把它搶回來' "$BUSY"
assert_grep "skill: the here step says exit code 4 ends the invocation" "這一次的呼叫就此結束" "$(printf '%s\n' "$REST" | grep -F '它以 4 結束')"
assert_eq "skill: no sentence about a refused token sends the session back to step 3" "0" "$(printf '%s\n' "$REST" | tr '。；' '\n\n' | grep -F 'token 不是' | grep -c '回第 3 步')"
assert_grep "skill: a refused token is not a lost token" '不可以用 `--take-over` 搶回來' "$REST"
# spec-example: idd-all-rest / the skill ends when the report itself fails
FAILED_REPORT=$(printf '%s\n' "$STOPS" | grep -E '^\| [^|]*`report`[^|]*以 1 或 3 結束')
assert_eq "skill: one row is about the report that fails" "1" "$(printf '%s\n' "$FAILED_REPORT" | grep -c '^| ')"
assert_grep "skill: that row says to pass on what was printed" "已經印出" "$FAILED_REPORT"
assert_grep_re "skill: and to call neither stop nor report again" '不再呼叫 `stop` 或 `report`' "$FAILED_REPORT"
assert_grep "skill: the stop list says five cases" "只有這五種" "$REST"
# spec-example: idd-all-rest / the skill reports a failed start directly
# spec-example: idd-all-rest / the skill ends a refused run
FAILED_START=$(printf '%s\n' "$STOPS" | grep -E '^\| [^|]*`start`[^|]*以 3 結束')
assert_eq "skill: one row is about the start that fails before a run exists" "1" "$(printf '%s\n' "$FAILED_START" | grep -c '^| ')"
assert_grep "skill: that row says no run exists yet" "還沒有 run" "$FAILED_START"
assert_grep_re "skill: and to call neither stop nor report" '不呼叫 `stop` 與 `report`' "$FAILED_START"
assert_grep "skill: and to tell the user the reason" "告訴使用者" "$FAILED_START"
assert_grep "skill: a path that is not PR is among its causes" "path 不是 \`PR\`" "$FAILED_START"
refute_grep "skill: and a working tree that is not clean is not" "乾淨" "$FAILED_START"
# spec-example: idd-all-rest / the skill goes on to the report when stop fails
STOP3=$(printf '%s\n' "$STOPS" | grep -E '^\| `next` 或 `record` 以 3 結束')
assert_eq "skill: one row is about next or record exiting 3" "1" "$(printf '%s\n' "$STOP3" | grep -c '^| ')"
assert_grep "skill: that row calls stop with the reason line" "照抄" "$STOP3"
assert_grep "skill: and goes on to the end when stop itself fails" '`stop` 自己也失敗時直接做「結束」一節' "$STOP3"
assert_grep "skill: gh authentication is part of that row" "gh" "$STOP3"
assert_grep_re "skill: stop case — the user interrupts, and nothing is recorded" '^\| 使用者中斷 \| 不必做任何事' "$STOPS"
refute_grep "skill: the old step 5 prose is gone" 'pull --ff-only -q' "$REST"
# spec-example: idd-all-rest / the skill runs the preflight steps once
FLOW=$(printf '%s\n' "$REST" | awk '/^### 流程/{f=1; next} f&&/^### /{exit} f')
L_STARTCMD=$(printf '%s\n' "$FLOW" | grep -n -F 'rest-queue.py" start' | head -1 | cut -d: -f1)
K=$(printf '%s\n' "$FLOW" | sed -n "1,${L_STARTCMD:-1}p" | grep -E '^[0-9]+\. ' | tail -1 | sed -E 's/^([0-9]+)\..*/\1/')   # the numbered step that calls start
STEP1=$(printf '%s\n' "$FLOW" | awk -v a="$((K - 1))" -v b="$K" '$0 ~ "^" a "\\. " {f=1} f && $0 ~ "^" b "\\. " {exit} f')   # the one before it
assert_true "skill: there is a numbered step before the one that calls start" '[ "${K:-0}" -ge 2 ] && [ -n "$STEP1" ]'
for step in '0\.2' '0\.3' '0\.35' '0\.5' '0\.6'; do
  assert_grep_re "skill: that step names Step $step" "Step $step([^0-9.]|\$)" "$STEP1"
done
assert_grep "skill: and says it runs once" "只做一次" "$(printf '%s\n' "$STEP1" | sed -n '1p')"
assert_grep "skill: the start invocation passes the path it resolved" '--path "$PATH_AXIS"' "$(printf '%s\n' "$REST" | grep -F 'rest-queue.py" start')"
assert_grep "skill: and the review flag of the invocation" '--review "$REVIEW_YN"' "$(printf '%s\n' "$REST" | grep -F 'rest-queue.py" start')"
# spec-example: idd-all-rest / the skill takes the review flag from next
RUN_STEP=$(printf '%s\n' "$FLOW" | awk '/^4\. /{f=1} f&&/^5\. /{exit} f')
assert_grep_re "skill: the review flag of an issue is the one next printed" '`REVIEW_YN`[^。]*`next` 印出的 `review`' "$RUN_STEP"
assert_grep "skill: and not a remembered one" "不從記憶" "$RUN_STEP"
# spec-example: idd-all-rest / the skill passes reasons on standard input
assert_grep "skill: record takes its reason on standard input" "--reason-stdin" "$(printf '%s\n' "$REST" | grep -F 'rest-queue.py" record')"
assert_grep "skill: and so does stop" "--reason-stdin" "$(printf '%s\n' "$REST" | grep -F 'rest-queue.py" stop')"
refute_grep "skill: no reason is passed as a shell argument in the rest section" "--reason '" "$REST"
# spec-example: idd-all-rest / Step 0.5 and Step 0.6 point at the rest rule
first_para() { awk -v h="$1" 'index($0, h) == 1 {f=1; next} f && NF {p=1; print; next} f && p {exit}' "$SKILL"; }
for step in "#### Step 0.5:" "#### Step 0.6:"; do
  assert_grep "skill: the first paragraph of $step names the rest section" '## Rest mode' "$(first_para "$step")"
  assert_grep "skill: and says a rest run does not resolve the path again" "不再重新解析" "$(first_para "$step")"
done
# spec-example: idd-all-rest / the skill's record command works as written
new skill-block 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
python3 - "$SKILL" > "$S/blocks.txt" <<'BLOCKS_PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
rest = text.split("\n## Rest mode", 1)[1].split("\n## ", 1)[0]
for fence in re.findall(r"^[ \t]*```bash\n(.*?)^[ \t]*```", rest, flags=re.S | re.M):
    if "--reason-stdin" in fence:
        print(fence, end="")
        print("#-- next block --")
BLOCKS_PY
awk '/^#-- next block --$/{n++; next} n==0' "$S/blocks.txt" | sed 's/<Stopped: 那一行>/Stopped: the price is $5 and `date` is not run/' > "$S/record.sh"
awk '/^#-- next block --$/{n++; next} n==1' "$S/blocks.txt" | sed 's/<原因>/the helper stopped/' > "$S/stop.sh"
OUT=$(cd "$S" && CLAUDE_PLUGIN_ROOT="$PLUGIN" REST_ROOT="$T" CWD="$(dir_of 5)" GITHUB_REPO="$REPO" N=5 TOKEN="$(token_of 5)" bash "$S/record.sh" 2>/dev/null)
assert_eq "skill: the record block, run as it is written, records exactly that line" 'Stopped: the price is $5 and `date` is not run' "$(printf '%s' "$OUT" | jget reason)"

OUT=$(cd "$S" && CLAUDE_PLUGIN_ROOT="$PLUGIN" REST_ROOT="$T" CWD="$(dir_of 5)" GITHUB_REPO="$REPO" TOKEN="$(run_token)" bash "$S/stop.sh" 2>/dev/null)
assert_eq "skill: and so does the stop block" "the helper stopped" "$(printf '%s' "$OUT" | jget stopped)"
# spec-example: idd-all-rest / the skill takes both review values from next
assert_grep_re "skill: REVIEW_FLAG of an issue follows the review next printed" '`REVIEW_FLAG`[^。]*`next`' "$RUN_STEP"
assert_grep "skill: the block that prepares the pull request text asks the close stage for the review flag of the rest run" 'rest-review' "$(grep -F 'REST_REVIEW=' "$SKILL")"
assert_grep "skill: Step 0.7 says a rest run does not go back to the original arguments" "rest mode 例外" "$(awk '/^#### Step 0.7:/{f=1} f&&/^#### Step 0.8|^### Phase 1/{exit} f' "$SKILL" | grep -F '原始引數')"
# spec-example: idd-all-rest / the skill says the flags are to be the same
RESUME_ROWS=$(printf '%s\n' "$STOPS" | grep -F '會接續')
assert_eq "skill: two rows of the stop table say a later command resumes the run" "2" "$(printf '%s\n' "$RESUME_ROWS" | grep -c '^| ')"
assert_eq "skill: and both say the flags are to be the same" "2" "$(printf '%s\n' "$RESUME_ROWS" | grep -c '旗標相同')"
assert_eq "skill: and both name --take-over" "2" "$(printf '%s\n' "$RESUME_ROWS" | grep -c -- '--take-over')"
assert_eq "skill: every line that says a later command within 24 hours resumes the run names --take-over" "0" \
  "$(grep -F '24 小時內' "$SKILL" | grep -F '接續' | grep -vc -- '--take-over')"
assert_eq "skill: every line that says a later command within 24 hours resumes the run says the flags are to be the same" "0" \
  "$(grep -F '24 小時內再下' "$SKILL" | grep -vc '旗標相同')"
assert_eq "skill: every line of the rest section about resuming within 24 hours says the flags are to be the same" "0" \
  "$(printf '%s\n' "$REST" | grep -F '24 小時內' | grep -F '接續' | grep -vc '旗標')"
# spec-example: idd-all-rest / the skill continues an issue in flight
FLIGHT=$(printf '%s\n' "$REST" | grep -F '"in_flight": true')
assert_eq "skill: one row is about an issue in flight" "1" "$(printf '%s\n' "$FLIGHT" | grep -c .)"
assert_grep "skill: an issue in flight with a Phase 6 result goes to record" "直接做第 5 步" "$FLIGHT"
assert_grep "skill: and it is continued in the dir that was printed" "在印出的 \`dir\` 裡接著做" "$FLIGHT"
assert_grep_re "skill: without a branch it starts again from Step 0.4" '`branch` 是 `null` 時[^。]*從 Step 0\.4 重新開始' "$FLIGHT"
assert_grep "skill: otherwise its interrupted phase is continued" "從中斷的那個 phase 接著做完" "$FLIGHT"
assert_grep "skill: and Step 0.5.1 is not run again" "不重跑 Step 0.5.1" "$FLIGHT"
RECORD_STEP=$(printf '%s\n' "$FLOW" | grep -n -F 'rest-queue.py" record' | head -1 | cut -d: -f1)
assert_grep_re "skill: step 5 is the one that records" '^5\. 記下這一張的結果' "$(printf '%s\n' "$FLOW" | sed -n "1,${RECORD_STEP:-1}p" | grep -E '^[0-9]+\. ' | tail -1)"
# spec-example: idd-all-rest / the skill clears the unattended marker
RECORD5=$(printf '%s\n' "$FLOW" | awk '/^5\. /{f=1} f')
L_CLR=$(printf '%s\n' "$RECORD5" | grep -n -F 'clear_unattended "$CWD"' | head -1 | cut -d: -f1)
L_BACK=$(printf '%s\n' "$RECORD5" | grep -n -F 'cd "$REST_ROOT"' | head -1 | cut -d: -f1)
L_REC=$(printf '%s\n' "$RECORD5" | grep -n -F 'rest-queue.py" record' | head -1 | cut -d: -f1)
assert_true "skill: the step that records clears the marker of the issue's directory, then goes back, then records" \
  "[ ${L_CLR:-0} -gt 0 ] && [ ${L_CLR:-0} -lt ${L_BACK:-0} ] && [ ${L_BACK:-0} -lt ${L_REC:-0} ]"
assert_eq "skill: no line of the rest section clears a marker where the run was started" "0" "$(printf '%s\n' "$REST" | grep -c 'clear_unattended "$REST_ROOT"')"
assert_grep "skill: the rest section names where the takeover went" "#566" "$REST"
assert_grep "skill: the description says once per run" "每張在一次 run 裡只試一次" "$(sed -n '1,12p' "$SKILL")"
assert_grep "skill: a run that names an issue does not create rest_run" "指名 issue 的 run 不建 \`rest_run\`" "$(cat "$SKILL")"
assert_grep "skill: and the task line itself says so" "指名 issue 的 run 不建這一項" "$(grep -F 'TaskCreate(name="rest_run"' "$SKILL")"
assert_grep "skill: Step 0.1 names the word last" '`last`' "$STEP01"
for f in "$PLUGIN/MANIFESTO.md" "$PLUGIN/README.md" "$PLUGIN/skills/idd-issue/SKILL.md"; do
  refute_grep_re "docs: no bare /idd-all with only a flag as an example of one issue in $(basename "$(dirname "$f")")/$(basename "$f")" 'idd-all --(pr|no-pr)' "$(cat "$f")"
done
assert_grep "skill: outside text is not put into a shell argument" "不放進 shell 的引數" "$REST"
refute_grep_re "skill: no reason template in double quotes" '--reason "<' "$REST"
CLASSROWS=$(printf '%s\n' "$REST" | grep -E '^\| `(outsider|tracker|unreadable|needs-person|parked|blocked|meeting|verified|candidate)` ')
assert_eq "skill: the class table has the nine classes" "9" "$(printf '%s\n' "$CLASSROWS" | grep -c '^| ')"
assert_eq "skill: in the order of the decision table" "outsider tracker unreadable needs-person parked blocked meeting verified candidate" "$(printf '%s\n' "$CLASSROWS" | sed -E 's/^\| `([a-z-]+)`.*/\1/' | tr '\n' ' ' | sed 's/ $//')"
assert_grep "skill: the mode is resolved once" '只問一次' "$REST"
PHASE6=$(awk '/^### Phase 6/{f=1} f&&/^#### /{exit} f' "$SKILL")
assert_grep "skill: Phase 6 sends a rest run back to the rest section" '## Rest mode' "$PHASE6"
line_of() { printf '%s\n' "$REST" | grep -n -F -- "$1" | head -1 | cut -d: -f1; }
for sub in start next where here record stop report; do
  assert_true "skill: the rest section calls $sub" "[ -n \"\$(line_of 'rest-queue.py\" $sub')\" ]"
done
L_START=$(line_of 'rest-queue.py" start'); L_NEXT=$(line_of 'rest-queue.py" next')
L_RECORD=$(line_of 'rest-queue.py" record'); L_REPORT=$(line_of 'rest-queue.py" report')
L_STOP=$(line_of 'rest-queue.py" stop'); L_HERE=$(line_of 'rest-queue.py" here'); L_WHERE=$(line_of 'rest-queue.py" where')
assert_true "skill: start comes before next" "[ ${L_START:-0} -gt 0 ] && [ ${L_START:-0} -lt ${L_NEXT:-0} ]"
assert_true "skill: next comes before where" "[ ${L_NEXT:-0} -gt 0 ] && [ ${L_NEXT:-0} -lt ${L_WHERE:-0} ]"
assert_true "skill: where comes before here" "[ ${L_WHERE:-0} -gt 0 ] && [ ${L_WHERE:-0} -lt ${L_HERE:-0} ]"
assert_true "skill: here comes before record" "[ ${L_HERE:-0} -gt 0 ] && [ ${L_HERE:-0} -lt ${L_RECORD:-0} ]"
assert_true "skill: report comes last" "[ ${L_REPORT:-0} -gt ${L_RECORD:-0} ] && [ ${L_REPORT:-0} -gt ${L_STOP:-0} ]"
assert_eq "skill: no line of the skill calls settle" "0" "$(grep -c 'rest-queue.py" settle' "$SKILL")"
# spec-example: idd-all-rest / the skill runs each issue in its directory
RUN4=$(printf '%s\n' "$FLOW" | awk '/^4\. /{f=1} f&&/^5\. /{exit} f')
FENCES4=$(python3 - "$SKILL" <<'FENCES_PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
rest = text.split("\n## Rest mode", 1)[1].split("\n## ", 1)[0]
step = rest.split("\n4. ", 1)[1].split("\n5. ", 1)[0]
for i, fence in enumerate(re.findall(r"^[ \t]*```bash\n(.*?)^[ \t]*```", step, flags=re.S | re.M)):
    print(f"#-- block {i} --"); print(fence, end="")
FENCES_PY
)
CDBLOCK=$(printf '%s\n' "$FENCES4" | awk '/^#-- block 0 --$/{f=1; next} /^#-- block /{f=0} f')
HEREBLOCK=$(printf '%s\n' "$FENCES4" | awk '/^#-- block 1 --$/{f=1; next} /^#-- block /{f=0} f')
assert_grep "skill: the first block of step 4 sets CWD from the output of where" 'CWD="$(python3 "${CLAUDE_PLUGIN_ROOT}/scripts/rest-queue.py" where' "$CDBLOCK"
assert_eq "skill: no line of the rest section sets CWD to a value written between angle brackets" "0" "$(printf '%s\n' "$REST" | grep -cE 'CWD="?<')"
assert_grep "skill: and changes to it, ending the command when that fails" 'cd "$CWD" ||' "$CDBLOCK"
refute_grep "skill: and does not run here in the same block" 'rest-queue.py" here' "$CDBLOCK"
assert_grep "skill: the next block runs here with the token" '--token "$TOKEN"' "$HEREBLOCK"
assert_grep "skill: and the directory of the issue" '--cwd "$CWD"' "$HEREBLOCK"
refute_grep "skill: and does not change the directory" 'cd ' "$HEREBLOCK"
assert_grep_re "skill: step 4 says to run here again before Phase 2, Phase 3, Phase 4, Phase 5 and Phase 6" 'Phase 2[^。]*Phase 3[^。]*Phase 4[^。]*Phase 5[^。]*Phase 6[^。]*here' "$RUN4"
assert_grep "skill: the step that records runs here first and ends the invocation on 4" "再跑一次第 4 步的 \`here\`：以 4 結束" "$(printf '%s\n' "$FLOW" | awk '/^5\. /{f=1} f' | sed -n '1p')"
assert_grep "skill: and that a here that fails on the current directory stops the whole run" "整個 run 停下" "$(printf '%s\n' "$RUN4" | grep -F '目前的目錄')"
for sub in start next where record stop report; do
  assert_grep "skill: the $sub invocation is given the directory the run was started in" '--cwd "$REST_ROOT"' "$(printf '%s\n' "$REST" | grep -F "rest-queue.py\" $sub")"
done
for sub in next where here record stop report; do
  assert_grep "skill: the $sub invocation carries the token of the run" '--token "$TOKEN"' "$(printf '%s\n' "$REST" | grep -F "rest-queue.py\" $sub")"
done
# spec-example: idd-all-rest / the skill keeps the token of the run
STEP2=$(printf '%s\n' "$FLOW" | awk '/^2\. /{f=1} f&&/^3\. /{exit} f')
assert_grep "skill: the step that calls start sets REST_ROOT to the top of the repository" 'REST_ROOT="$(git -C "$CWD" rev-parse --show-toplevel)"' "$STEP2"
assert_grep "skill: and says to keep the token: line in the task list of the run" '`token: ` 那一行' "$STEP2"
assert_grep "skill: in the task description" "task 描述" "$STEP2"
assert_grep "skill: a start that exits 4 ends the invocation" "這一次的呼叫就此結束" "$(printf '%s\n' "$STEP2" | grep -F '以 4 結束')"
assert_grep "skill: start --take-over is for a user who asks for the run to be taken over" "使用者在這次對話裡說要接手" "$STEP2"
assert_grep "skill: a lost token is told to the user" "告訴使用者" "$(printf '%s\n' "$RUN4" | grep -F 'token 弄丟了')"
assert_grep "skill: and taken over only when the user asks" '使用者說要接手時，才' "$(printf '%s\n' "$RUN4" | grep -F 'token 弄丟了')"
refute_grep "skill: no permission to take a run over because this invocation lost its token" "後來把 token 弄丟了" "$(cat "$SKILL")"
STEP07=$(awk '/^#### Step 0.7:/{f=1} f&&/^#### Step 0.8|^### Phase 1/{exit} f' "$SKILL")
assert_grep "skill: Step 0.7 ends the invocation when init exits 4" '[ "$rc" != 4 ] || {' "$STEP07"
assert_grep "skill: and its reset is given the token of a rest run" '"${REST_TOKEN_ARG[@]}"' "$(printf '%s\n' "$STEP07" | grep -F 'close-stage.py" reset')"
assert_eq "skill: every close-stage.py reset of the skill names the token of a rest run" "0" "$(grep -F 'close-stage.py' "$SKILL" | grep -F ' reset --cwd' | grep -vc -e '--rest-token' -e 'REST_TOKEN_ARG')"
assert_eq "skill: no line of the skill holds next --take-over" "0" "$(grep -c 'next --take-over' "$SKILL")"
assert_grep "skill: Step 0.7 gives init the token of a rest run" '--rest-token "$REST_TOKEN_OR_NONE"' "$(awk '/^#### Step 0.7:/{f=1} f&&/^#### Step 0.8|^### Phase 1/{exit} f' "$SKILL")"
assert_grep "skill: Phase 5c gives run the token of a rest run" 'REST_TOKEN_ARG=(--rest-token' "$(grep -F 'REST_TOKEN_ARG=' "$SKILL")"
assert_grep "skill: and passes it to run" '"${REST_TOKEN_ARG[@]}"' "$(grep -F 'close-stage.py" run --cwd' "$SKILL")"

# spec-example: idd-all-rest / the skill takes the directory from where
new 'where-$(touch made-by-the-path)' 5 9
begin
printf '%s\n' "$CDBLOCK" > "$S/cd.sh"; printf 'pwd -P\n' >> "$S/cd.sh"
OUT=$(cd "$S" && CLAUDE_PLUGIN_ROOT="$PLUGIN" REST_ROOT="$T" GITHUB_REPO="$REPO" N=5 TOKEN="$(run_token)" bash "$S/cd.sh" 2> "$S/cd.err" | tail -1)
assert_eq "skill: the cd block, run as it is written in a run whose path holds a command, ends in the directory of #5" "$(dir_of 5)" "$OUT"
assert_true "skill: and nothing in the path was run" '[ -z "$(find "$WORK" -name made-by-the-path 2> /dev/null)" ]'
assert_grep "skill: step 4 says the sub-skills are still given --cwd" '子 skill 照樣帶 `--cwd "$CWD"`' "$RUN4"
# spec-example: idd-all-rest / no text describes the removed step between two issues
for f in "$SKILL" "$PLUGIN/CLAUDE.md" "$PLUGIN/references/parallel-orchestration.md" "$PLUGIN/references/working-tree-writers.md" "$PLUGIN/../../docs/commands.md"; do
  name=$(basename "$f")
  assert_eq "docs ($name): no rest-queue.py settle and no \`settle\`" "0" "$(grep -c -e 'rest-queue.py" settle' -e 'rest-queue.py settle' -e '`settle`' "$f")"
  assert_eq "docs ($name): no sentence about rest mode speaks of between two issues" "0" "$(grep -i 'rest' "$f" | grep -ci 'between two issues\|兩張之間')"
  assert_eq "docs ($name): no pointer file" "0" "$(grep -ci 'pointer file\|idd-all-rest-run' "$f")"
done
assert_eq "docs (CHANGELOG.md): no pointer file" "0" "$(grep -ci 'pointer file\|idd-all-rest-run' "$PLUGIN/CHANGELOG.md")"
CMDS="$PLUGIN/../../docs/commands.md"
refute_grep "docs (commands.md): a rest run does not need a clean working tree" "needs the working tree clean" "$(cat "$CMDS")"
refute_grep "docs (commands.md): and nothing says not to work in it" "Do not work in the same working tree" "$(cat "$CMDS")"
# spec-example: idd-all-rest / the skill says that the starting working tree is not used
assert_grep "skill: a rest run does not work in the working tree it was started in" "rest 不在啟動它的那個工作樹裡做事" "$REST"
assert_grep "skill: and a person may go on working there" "人或別的 session 也可以繼續在那裡工作" "$REST"

# ── one reading of the rest run's state ──
# spec-example: idd-all-rest / the review flag of a rest run has one reader
rest_review() { python3 "$CS" rest-review --cwd "${1:-$(dir_of 5)}" --repo "$REPO" --issue 5 2> /dev/null; }
set_state() { # a statement over s, the run state → the state file rewritten
  python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); exec(sys.argv[2]); json.dump(s, open(p,"w"))' "$(state_file)" "$1"
}
flight5() { new "$1" 5 9; run start --path PR --review "$2" > /dev/null 2>&1; run next > /dev/null 2>&1; D=$(dir_of 5); [ "${3:-}" = bare ] || init no > /dev/null 2>&1; }   # #5 in flight, its run recorded with --rest-root T
new rr-none 5 9
assert_eq "rest-review: no rest run and no record: off" "off" "$(rest_review "$T")"
flight5 rr-yes yes bare; init yes > /dev/null 2>&1
assert_eq "rest-review: review yes, #5 in flight, recorded with the rest root: on" "on" "$(rest_review)"
assert_eq "rest-review: the same run asked where it was started: elsewhere" "elsewhere" "$(rest_review "$T")"
flight5 rr-no no
assert_eq "rest-review: review no, #5 in flight, recorded with the rest root: off" "off" "$(rest_review)"
assert_eq "rest-review: the same run asked where it was started: elsewhere" "elsewhere" "$(rest_review "$T")"
flight5 rr-norecord no bare
assert_eq "rest-review: #5 in flight and no record in its directory: elsewhere" "elsewhere" "$(rest_review)"
flight5 rr-old yes bare; init yes > /dev/null 2>&1
set_state 's["updated_at"] = "2020-01-01T00:00:00Z"'; age "$(state_file)" 25
assert_eq "rest-review: the named run wrote nothing for 25 hours: unreadable" "unreadable" "$(rest_review)"
for lacks in version path default; do
  flight5 "rr-lacks-$lacks" no
  set_state "s.pop('$lacks')"
  assert_eq "rest-review: a recent state without $lacks, review false: unreadable" "unreadable" "$(rest_review)"
  run start --path PR --review no > /dev/null 2>&1; assert_exit "rest-review: and start stops on the same file" 3 "$?"
  python3 "$CS" run --cwd "$D" --repo "$REPO" --issue 5 > "$S/run.out" 2>&1
  assert_output_grep "rest-review: and the close stage stays at verified for it" "review flag is unknown" "$S/run.out"
done
flight5 rr-not-json no
printf '{"review": fal' > "$(state_file)"
assert_eq "rest-review: a recent file that is not JSON: unreadable" "unreadable" "$(rest_review)"
flight5 rr-link no
mv "$(state_file)" "$S/real.json"; ln -s "$S/real.json" "$(state_file)"
assert_eq "rest-review: a state file that is a symbolic link to a usable state with review off: unreadable" "unreadable" "$(rest_review)"
run start --path PR --review no > /dev/null 2>&1; assert_exit "rest-review: and start stops on that link too" 3 "$?"
flight5 rr-reported no
run report > /dev/null 2>&1
assert_eq "rest-review: the run was ended by report after the issue was recorded: unreadable" "unreadable" "$(rest_review)"
flight5 rr-moved no
mv "$D" "$S/moved"; ln -s "$S/moved" "$D"
assert_eq "rest-review: the directory moved to U with a link at its place, asked in U: unreadable" "unreadable" "$(rest_review "$S/moved")"
rm "$D"; mv "$S/moved" "$D"
# spec-example: idd-all-rest / the close stage sees a rest run from anywhere in its working tree
new anywhere 3 5
run start --path PR --review yes > /dev/null 2>&1; run next > /dev/null 2>&1; run record --issue 3 --reason x > /dev/null 2>&1; run next > /dev/null 2>&1
assert_eq "anywhere: #5 is in flight, after #3 was recorded" "5" "$(run next 2> /dev/null | jget next)"
mkdir -p "$T/sub" "$(dir_of 5)/sub"
ANY=("$T/sub" "$(dir_of 5)/sub" "$(dir_of 3)")
UPPER="$(dirname "$T")/TREE"   # T is …/tree: the same folder on a file system that does not tell letter case apart
if [ -d "$UPPER" ] && [ "$(cd "$UPPER" && pwd -P)" != "$T" ] && [ "$(ls -di "$UPPER" | cut -d' ' -f1)" = "$(ls -di "$T" | cut -d' ' -f1)" ]; then ANY+=("$UPPER"); fi
for at in "${ANY[@]}"; do
  init no "$at" none > /dev/null 2>&1; rc=$?
  assert_exit "anywhere ($(basename "$at")): init --rest-root none exits 64" 64 "$rc"
  assert_eq "anywhere ($(basename "$at")): and writes no run state there" "no" "$(runstate "$at")"
  assert_eq "anywhere ($(basename "$at")): rest-review prints elsewhere" "elsewhere" "$(rest_review "$at")"
done
new rr-fifo 5 9
mkdir -p "$T/.claude/.idd/state"; mkfifo "$(state_file)"
# the reader runs as a direct child with its output in a file, so a reader that waits on the FIFO is ended after
# 5 seconds and the test fails; it does not wait with it (a command substitution would wait for the reader's pipe)
python3 "$CS" rest-review --cwd "$T" --repo "$REPO" --issue 5 > "$S/fifo.out" 2> /dev/null & P=$!
( sleep 5; kill "$P" 2> /dev/null ) > /dev/null 2>&1 & W=$!
wait "$P" 2> /dev/null; kill "$W" 2> /dev/null
OUT=$(cat "$S/fifo.out")
assert_eq "rest-review: a FIFO at the place of the state: unreadable, without waiting" "unreadable" "$OUT"
phase5() { # [directory] → the two lines of Phase 5 that take the review of the rest run, run as they are written → RUN_REVIEW
  (CLAUDE_PLUGIN_ROOT="$PLUGIN"; CWD="${1:-$(dir_of 5)}"; GITHUB_REPO="$REPO"; N=5; RUN_REVIEW=no
   eval "$(grep -F -A1 'REST_REVIEW=$(python3' "$SKILL")"; printf '%s' "$RUN_REVIEW")
}
assert_eq "skill: the two lines of Phase 5 are the call and the line that uses its answer" "2" "$(grep -F -A1 'REST_REVIEW=$(python3' "$SKILL" | grep -c 'REST_REVIEW')"
new p5-none 5 9
assert_eq "phase 5: no rest run leaves the review of the issue as it is" "no" "$(phase5 "$T")"
flight5 p5-on yes bare; init yes > /dev/null 2>&1
assert_eq "phase 5 (on): the close stage reads on" "on" "$(rest_review)"
assert_eq "phase 5: a rest run with review that has the issue in flight makes it a review" "yes" "$(phase5)"
flight5 p5-off no
assert_eq "phase 5: a rest run without review leaves it as it is" "no" "$(phase5)"
assert_eq "phase 5: the same run, with the pipeline in the wrong place, makes it a review" "yes" "$(phase5 "$T")"
flight5 p5-unreadable no
printf '{"review": fal' > "$(state_file)"
assert_eq "phase 5: a recent state that cannot be used makes it a review" "yes" "$(phase5)"
PHASE5=$(grep -F 'REST_REVIEW=' "$SKILL")
assert_grep "skill: Phase 5 asks the close stage what the rest run says" 'close-stage.py" rest-review' "$PHASE5"
assert_eq "skill: and no line of the skill reads the rest run's state file with jq" "0" "$(grep -F 'idd-all-rest.json' "$SKILL" | grep -c 'jq ')"

# ── two requirements of other capabilities that #478 touched (each to point at idd-all-rest) ──
# spec-example: idd-all-chain / DFS vs BFS queue order with a single spawn
CHAIN="$PLUGIN/skills/idd-all-chain/SKILL.md"
POP=$(grep -F 'QUEUE=("${QUEUE[@]:1}")' "$CHAIN" | sed 's/ *#.*$//')
PUSH=$(awk '/# Push semantics dispatch/{f=1; next} f{print} f&&/^ *fi$/{exit}' "$CHAIN")
assert_eq "chain: one line of the skill pops the front of the queue" "1" "$(printf '%s\n' "$POP" | grep -c .)"
assert_eq "chain: the skill's push block is the five lines after its comment" "5" "$(printf '%s\n' "$PUSH" | grep -c .)"
queue_after() { # dfs|bfs → "the issue popped|the queue after the spawn X was added|the next one"
  TRAVERSAL=$1 SPAWN_NUM=X POP="$POP" PUSH="$PUSH" bash -c 'QUEUE=(44 45 50); CURRENT="${QUEUE[0]}"; eval "$POP"; eval "$PUSH"; printf "%s|%s|%s" "$CURRENT" "${QUEUE[*]}" "${QUEUE[0]}"' 2>&1
}
assert_eq "chain, DFS: #44 is popped, the spawn goes to the front and is next" "44|X 45 50|X" "$(queue_after dfs)"
assert_eq "chain, BFS: #44 is popped, the spawn goes to the back and #45 is next" "44|45 50 X|45" "$(queue_after bfs)"

# spec-example: idd-pr-hitl-modes / the skill asks once in rest mode and offers only the PR path
PRE=$(grep -F 'Step 0.5 只做解析' "$SKILL")
assert_grep "skill: in rest mode pr_policy: ask is asked once, in the preflight step" '`pr_policy: ask` 在這裡只問一次' "$PRE"
assert_grep "skill: the question is whether to start the run on the PR path" "要不要以 PR path 開始這次 run" "$PRE"
assert_grep "skill: and direct-commit is not offered" "不提供 direct-commit" "$PRE"
assert_grep "skill: Step 0.5 says rest does not resolve the path again for each issue" "不再重新解析 path 與 interaction" "$(grep -F '**rest mode（`## Rest mode`）**' "$SKILL")"

print_summary "rest-queue"
