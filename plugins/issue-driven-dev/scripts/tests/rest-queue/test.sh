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
# git in the scenarios reads no configuration of this machine: hooks, signing and templates there cannot change a result
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
  GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
REPO=o/r

git_tree() { # dir → a clone of a bare origin (dir.origin.git) whose main holds a.txt; the run state is ignored
  git init -q --bare -b main "$1.origin.git"
  git init -q -b main "$1"
  printf '.claude/.idd/state/\n' >> "$1/.git/info/exclude"
  printf 'a\n' > "$1/a.txt"
  git -C "$1" add a.txt && git -C "$1" commit -q -m init
  git -C "$1" remote add origin "$1.origin.git" && git -C "$1" push -q -u origin main 2>/dev/null
}
new() { # name issue-spec… → S (scenario dir), G (gh answers), T (working tree, a git clone with an origin)
  S="$WORK/$1"; G="$S/gh"; T="$S/tree"; shift
  mkdir -p "$G"
  git_tree "$T"
  export FAKE_GH_DIR="$G"
  python3 "$HERE/scenario.py" "$G" "$@"
}
settle() { run settle --issue "$1"; }   # the step between two issues
# what idd-diagnose leaves is written by the real writer, with gh and curl replaced on PATH
STUB="$WORK/stub"; mkdir -p "$STUB"
cat > "$STUB/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "${1:-}" in
  issue) case "${GH_STUB_MODE:-empty}" in
           empty)    printf '{"body":"no attachment here","comments":[]}\n' ;;
           with_url) printf '{"body":"spec: https://github.com/user-attachments/files/123/spec.docx ok","comments":[]}\n' ;;
         esac ;;
  auth)  echo stub-token ;;
  *)     echo "gh stub: unhandled: $*" >&2; exit 1 ;;
esac
GHSTUB
cat > "$STUB/curl" <<'CURLSTUB'
#!/usr/bin/env bash
out=""; while [ $# -gt 0 ]; do [ "$1" = "-o" ] && out="$2"; shift; done
[ -n "$out" ] && printf 'attachment bytes\n' > "$out"
CURLSTUB
chmod +x "$STUB/gh" "$STUB/curl"
download() { # issue [dir] [mode] → process-attachments.sh download, run from dir (default: the working tree)
  (cd "${2:-$T}" && PATH="$STUB:$PATH" GH_STUB_MODE="${3:-empty}" IDD_CALLER=idd-diagnose \
     bash "$PLUGIN/scripts/process-attachments.sh" download "$1" --repo "$REPO" > /dev/null 2>&1)
}
reason_shape() { # label file → the reason line fits the limit and says what to do next before any detail
  assert_true "$1: the reason fits the limit for a reason" "[ \"\$(sed 's/^rest-queue: //' '$2' | wc -m | tr -d ' ')\" -le 301 ]"
  assert_grep_re "$1: and says what to do next before git's words or any path" 'then run the same /idd-all command again \(same flags\)( \(.*\))?$' "$(cat "$2")"
}
kept_of() { # issue → the kept entries of that attempt in the run state, as compact JSON
  python3 -c 'import json,sys; a=[x for x in json.load(open(sys.argv[1]))["attempts"] if x["issue"]==int(sys.argv[2])][0]; print(json.dumps(a.get("kept", []), separators=(",",":")))' "$(state_file)" "$1"
}
remote_ahead() { # origin/main gets one commit the working tree does not have
  git clone -q "$T.origin.git" "$S/other" 2>/dev/null && printf 'b\n' > "$S/other/b.txt" \
    && git -C "$S/other" add b.txt && git -C "$S/other" commit -q -m remote && git -C "$S/other" push -q origin main 2>/dev/null
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
stash0() { # key → that key of the first stash in the JSON on standard input
  python3 -c '
import json, sys
s = (json.loads(sys.stdin.read() or "{}").get("stashes") or [{}])[0]
v = s.get(sys.argv[1], "<missing>")
print(v if isinstance(v, str) else json.dumps(v, separators=(",", ":")))' "$1"
}
write_state() { # hours-since-last-activity attempts-json
  mkdir -p "$T/.claude/.idd/state"
  python3 - "$(state_file)" "$1" "$2" <<'PY'
import json, sys, time
path, hours, attempts = sys.argv[1], float(sys.argv[2]), json.loads(sys.argv[3])
stamp = lambda t: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))
at = time.time() - hours * 3600
for a in attempts:
    a.setdefault("handed_at", stamp(at)); a.setdefault("recorded_at", stamp(at)); a.setdefault("reason", "")
    a.setdefault("settled", True)
json.dump({"version": 4, "repo": "o/r", "path": "PR", "default": "main", "review": False, "started_at": stamp(at - 60), "updated_at": stamp(at),
           "attempts": attempts, "stop": None}, open(path, "w"))
PY
}

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
settle 5 > /dev/null
assert_eq "spawn: next is #9" "9" "$(run next | jget next)"
issues 5 12; echo CLOSED > "$G/state-9"     # #9 was closed, #12 was opened during the run
assert_eq "spawn: #9 is recorded as closed" "closed" "$(run record --issue 9 | jget outcome)"
settle 9 > /dev/null
assert_eq "spawn: the new issue #12 is handed out" "12" "$(run next | jget next)"
run record --issue 12 --reason "stopped at the PR" > /dev/null; settle 12 > /dev/null
OUT=$(run next)
assert_eq "spawn: then the run is done" "true" "$(printf '%s' "$OUT" | jget done)"
assert_eq "spawn: and #5 is not handed out again" "null" "$(printf '%s' "$OUT" | jget next)"

# spec-example: idd-all-rest / the in-flight issue is repeated
new inflight 5 9
run start --path PR --review no > /dev/null 2>&1
run next > /dev/null
OUT=$(run next)
assert_eq "in flight: the same issue is repeated, with no branch" '{"next":5,"in_flight":true,"branch":null,"review":"no"}' "$(printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), separators=(",",":")))')"
assert_eq "in flight: the state holds one attempt" "1" "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["attempts"]))' "$(state_file)")"

# spec-example: idd-all-rest / the in-flight issue names its branch
new inflight-branch 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; git -C "$T" branch idd/5-x
assert_eq "in flight: the issue names its local branch" '{"next":5,"in_flight":true,"branch":"idd/5-x","review":"no"}' "$(run next | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin), separators=(",",":")))')"

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
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; run record --issue 5 --reason x > /dev/null; settle 5 > /dev/null
assert_eq "one stopped issue does not end the run" "9" "$(run next | jget next)"
new stop 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; run record --issue 5 --reason x > /dev/null
run stop --reason "default branch could not be fast-forwarded" > /dev/null 2>&1; rc=$?
assert_exit "stop: exits 0" 0 "$rc"
OUT=$(rq next --cwd "$T" --repo "$REPO")
assert_eq "stop: next names the reason and hands out nothing" '{"next":null,"stopped":"default branch could not be fast-forwarded"}' \
  "$(printf '%s' "$OUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(json.dumps({"next": d["next"], "stopped": d["stopped"]}, separators=(",",":")))')"
assert_eq "stop: #9 was not handed out" "1" "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["attempts"]))' "$(state_file)")"

# spec-example: idd-all-rest / resume within 24 hours
new resume 5 9
write_state 2 '[{"issue": 5, "outcome": "stopped", "reason": "verify gate: not_clean"}]'
run start --path PR --review no > "$S/start.out" 2>&1; rc=$?
assert_exit "resume: start exits 0" 0 "$rc"
assert_output_grep "resume: start says the run is resumed" "resumed" "$S/start.out"
assert_output_grep "resume: with one attempt" "1 attempt" "$S/start.out"
assert_output_grep "resume: the list names issue numbers" "#9" "$S/start.out"
refute_output_grep "resume: the list prints no issue title" "SECRET-TITLE-TEXT" "$S/start.out"
refute_output_grep "resume: the list prints no issue text" "SECRET-BODY-TEXT" "$S/start.out"
assert_true "resume: the fixture issues do carry that title" 'grep -q "SECRET-TITLE-TEXT" "$G/issues.json"'
assert_eq "resume: starting counts as activity (updated_at is now, not 2 hours ago)" "fresh" "$(python3 -c 'import calendar,json,sys,time; s=json.load(open(sys.argv[1])); t=calendar.timegm(time.strptime(s["updated_at"], "%Y-%m-%dT%H:%M:%SZ")); print("fresh" if time.time()-t < 300 else "stale")' "$(state_file)")"
assert_eq "resume: next is #9, not #5" "9" "$(run next | jget next)"
run start --path PR --review no > /dev/null 2>&1    # a second start during the run
assert_eq "resume: a second start keeps the attempts" "2" "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["attempts"]))' "$(state_file)")"

# spec-example: idd-all-rest / a state older than 24 hours starts a new run
new expired 5 9
write_state 25 '[{"issue": 5, "outcome": "stopped", "reason": "verify gate: not_clean"}]'
run start --path PR --review no > "$S/start.out" 2>&1
refute_output_grep "expired: start does not resume" "resumed" "$S/start.out"
assert_eq "expired: next is #5 again" "5" "$(run next | jget next)"

# spec-example: idd-all-rest / report with one closed, one stopped and one waiting issue
new report 5 9 14:html=body-two-rows
run start --path PR --review no > /dev/null 2>&1
run next > /dev/null; issues 9 14:html=body-two-rows; echo CLOSED > "$G/state-5"; run record --issue 5 > /dev/null; settle 5 > /dev/null
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
run next > /dev/null; run record --issue 5 --reason "verify gate: not_clean" > /dev/null; settle 5 > /dev/null 2>&1
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
assert_output_grep "report: whose reason names what to look at" "names the pull request or branch to look at" "$S/report.out"

# spec-example: idd-all-rest / a stopped issue carries its open questions
new report-asked 5 14:html=body-two-rows
run start --path PR --review no > /dev/null 2>&1
run next > /dev/null; run record --issue 5 --reason "verify gate: not_clean" > /dev/null; settle 5 > /dev/null 2>&1
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
run next > /dev/null; echo CLOSED > "$G/state-5"; run record --issue 5 > /dev/null; settle 5 > /dev/null 2>&1
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
json.dump({"version": 4, "repo": "o/r", "path": "PR", "default": "main", "review": False, "started_at": stamp(now - 600), "updated_at": stamp(now - 300),
           "attempts": [{"issue": 5, "handed_at": stamp(now - 500), "outcome": "stopped",
                         "reason": "verify gate\nSECOND-LINE of the issue reason", "recorded_at": stamp(now - 400)},
                        {"issue": 6, "handed_at": stamp(now - 450), "outcome": "stopped",
                         "reason": "a\tTAB-FOLLOWS " + "x" * 400, "recorded_at": stamp(now - 350)}],
           "stop": {"reason": "first line\nSECOND-LINE of the stop reason", "at": stamp(now - 300)}}, open(sys.argv[1], "w"))
PY
run start --path PR --review no > "$S/start.out" 2>&1; rc=$?
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
python3 "$S/copy/rest-queue.py" report --cwd "$T" --repo "$REPO" > "$S/report.out" 2>&1; rc=$?
assert_exit "report: an unplanned failure while re-reading the list still exits 0" 0 "$rc"
assert_output_grep "report: the recorded result is still printed after it" "#5 — stopped at the PR" "$S/report.out"
assert_output_grep "report: and it says the list could not be read" "could not be read" "$S/report.out"
assert_file_absent "report: and the run state is deleted" "$(state_file)"

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
run start --path PR --review no > /dev/null 2>&1; rc=$?
assert_exit "start failed on a run it would have resumed: exits 3" 3 "$rc"
require "start failed on a run it would have resumed: the state of that run is untouched" cmp -s "$S/before.json" "$(state_file)"
rm "$G/fail-page"
run start --path PR --review no > "$S/start.out" 2>&1
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
new other-repo-state 5
write_state 1 '[{"issue": 5, "outcome": "stopped", "reason": "x"}]'
rq start --cwd "$T" --repo o/other --path PR --review no > "$S/start.out" 2>&1; rc=$?
assert_exit "start: a run state of another repository does not stop it" 0 "$rc"
assert_output_grep "start: and it says whose it was" "o/r" "$S/start.out"
refute_grep "start: and does not call a state written an hour ago older than 24 hours" "older than 24 hours" "$(cat "$S/start.out")"
for bad in "../x" "o/.." "./r" "o/."; do
  rq list --repo "$bad" > /dev/null 2>&1; assert_exit "usage: --repo $bad exits 2" 2 "$?"
done
rq list --repo "o/.github" > /dev/null 2>&1; assert_exit "usage: a repository name that begins with a dot is fine" 0 "$?"

echo "── between two issues ──"
head_branch() { git -C "$T" symbolic-ref --quiet --short HEAD || echo "<detached>"; }
stopped_block() { awk '/^stopped \(/{f=1; next} f&&/^[^ ]/{exit} f' "$1"; }

# spec-example: idd-all-rest / next waits for settle
new waits 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; run record --issue 5 --reason x > /dev/null
run next > /dev/null 2> "$S/err"; rc=$?
assert_exit "settle: next before settle exits 1" 1 "$rc"
assert_output_grep "settle: and its reason line names the issue to settle" "#5" "$S/err"
settle 5 > /dev/null 2>&1; rc=$?
assert_exit "settle: a clean default branch settles" 0 "$rc"
assert_eq "settle: then next hands out #9" "9" "$(run next | jget next)"

new settle-calls 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
settle 5 > /dev/null 2>&1; assert_exit "settle: the issue in flight exits 1" 1 "$?"
run record --issue 5 --reason x > /dev/null
settle 9 > /dev/null 2>&1; assert_exit "settle: an issue that was not recorded last exits 1" 1 "$?"
run settle --issue 5 --default main > /dev/null 2>&1; assert_exit "settle: --default is not an argument any more" 2 "$?"
run settle --issue 5 --path PR > /dev/null 2>&1; assert_exit "settle: neither is --path" 2 "$?"
mkdir -p "$WORK/no-run"; rq settle --cwd "$WORK/no-run" --repo "$REPO" --issue 5 > /dev/null 2>&1
assert_exit "settle: no run in the working tree exits 1" 1 "$?"

# spec-example: idd-all-rest / leftovers on the issue's own branch are kept there
new kept 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
INIT=$(git -C "$T" rev-parse HEAD)
git -C "$T" checkout -q -b idd/5-x
printf 'changed\n' >> "$T/a.txt"
download 5
assert_eq "kept: the manifest the real writer wrote is untracked" "?? .claude/" "$(git -C "$T" status --porcelain | grep claude)"
remote_ahead
run record --issue 5 --reason x > /dev/null
settle 5 > "$S/out" 2> "$S/err"; rc=$?
assert_exit "kept: settle exits 0" 0 "$rc"
assert_eq "kept: idd/5-x has one new commit" "1" "$(git -C "$T" rev-list --count "$INIT..idd/5-x")"
assert_eq "kept: and it holds a.txt and not the manifest" "a.txt" \
  "$(git -C "$T" show --name-only --format= idd/5-x | sort | tr '\n' ' ' | sed 's/ $//')"
assert_file_absent "kept: the manifest no longer exists" "$T/.claude/.idd/attachments/issue-5/_manifest.json"
assert_eq "kept: settle says what it discarded" '[".claude/.idd/attachments/issue-5/_manifest.json"]' "$(jget discarded < "$S/out")"
assert_eq "kept: the working tree is on main" "main" "$(head_branch)"
assert_eq "kept: clean" "" "$(git -C "$T" status --porcelain)"
assert_eq "kept: at the commit of origin/main" "$(git -C "$S/other" rev-parse HEAD)" "$(git -C "$T" rev-parse HEAD)"
assert_eq "kept: the commit is not pushed" "" "$(git -C "$T" ls-remote origin refs/heads/idd/5-x)"
KEPT=$(git -C "$T" rev-parse --short=7 idd/5-x)
OUT=$(settle 5 2>/dev/null); rc=$?
assert_exit "kept: a second settle for the same issue exits 0" 0 "$rc"
assert_eq "kept: and changes nothing" "$KEPT" "$(git -C "$T" rev-parse --short=7 idd/5-x)"
run report > "$S/report.out" 2>&1
assert_grep "kept: the report names the branch under #5" "idd/5-x" "$(stopped_block "$S/report.out")"
assert_grep "kept: and the commit" "$KEPT" "$(stopped_block "$S/report.out")"
assert_grep "kept: and the path the commit holds" "a.txt" "$(stopped_block "$S/report.out" | grep -F "$KEPT")"
assert_output_grep "kept: and says a later run records it as existing work" "later rest run" "$S/report.out"

# spec-example: idd-all-rest / a leftover on the default branch stops the run
new dirty-default 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; printf 'b\n' > "$T/b.txt"; run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2> "$S/err"; rc=$?
assert_exit "dirty default: settle exits 3" 3 "$rc"
assert_output_grep "dirty default: its reason line names b.txt" "b.txt" "$S/err"
assert_eq "dirty default: with one reason line" "1" "$(wc -l < "$S/err" | tr -d ' ')"
assert_eq "dirty default: no commit was made" "1" "$(git -C "$T" rev-list --count HEAD)"
assert_eq "dirty default: b.txt is left as it was" "?? b.txt" "$(git -C "$T" status --porcelain)"

# spec-example: idd-all-rest / a file IDD keeps out of git is never committed
new keep-out 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
INIT=$(git -C "$T" rev-parse HEAD)
git -C "$T" checkout -q -b idd/5-x; printf 'changed\n' >> "$T/a.txt"
mkdir -p "$T/.claude/.idd"; printf 'pid\n' > "$T/.claude/.idd/tree-lock"
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2> "$S/err"; rc=$?
assert_exit "keep out: settle exits 3" 3 "$rc"
assert_output_grep "keep out: its reason line names the file" ".claude/.idd/tree-lock" "$S/err"
assert_output_grep "keep out: and the issue" "#5" "$S/err"
assert_true "keep out: what to do comes before the path" '[ "$(grep -o "have git ignore.*" "$S/err" | grep -c "tree-lock")" = 1 ]'
reason_shape "keep out" "$S/err"
assert_eq "keep out: idd/5-x has no new commit" "$INIT" "$(git -C "$T" rev-parse idd/5-x)"
assert_eq "keep out: and the working tree stays on it" "idd/5-x" "$(head_branch)"
new keep-out-many 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
git -C "$T" checkout -q -b idd/5-x; mkdir -p "$T/.claude/worktrees"
for i in 1 2 3 4 5; do printf 'x\n' > "$T/.claude/worktrees/a-very-long-file-name-that-fills-the-line-and-then-some-more-of-it-number-$i.txt"; done
download 5   # the manifest would be discarded, were the run not stopping
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2> "$S/err"; assert_exit "keep out: five long paths exit 3" 3 "$?"
reason_shape "keep out, many" "$S/err"
assert_output_grep "keep out: the number of the other paths is not cut off" "and 2 more)" "$S/err"
assert_true "keep out: nothing was discarded before it stopped" '[ -f "$T/.claude/.idd/attachments/issue-5/_manifest.json" ]'
for p in ".claude/.idd/state/x.json" ".claude/.idd/tree-lock.reclaim" ".claude/worktrees/w/a"; do
  new "keep-out-$(printf '%s' "$p" | tr -c 'a-z0-9' '-')" 5 9
  printf '.claude/.idd/state/idd-all-rest.json\n.claude/.idd/state/unattended.json\n' > "$T/.git/info/exclude"   # two named files, not the folder
  run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; run record --issue 5 --reason x > /dev/null
  git -C "$T" checkout -q -b idd/5-x; mkdir -p "$T/$(dirname "$p")"; printf 'x\n' > "$T/$p"
  settle 5 > /dev/null 2> "$S/err"; rc=$?
  assert_exit "keep out: $p is never committed (exit 3)" 3 "$rc"
  assert_output_grep "keep out: and is named" "$p" "$S/err"
done
for p in ".claude/.idd/issue-runs/run.jsonl" ".claude/.idd/routing-stats.jsonl" ".claude/.idd/attachments/issue-5/sub/_manifest.json" \
         ".claude/.idd/attachments/issue-5/screenshot.png" ".claude/.idd/attachments/issue-6/_manifest.json"; do   # a file no manifest vouches for, and another issue's folder
  new "commit-ok-$(printf '%s' "$p" | tr -c 'a-z0-9' '-')" 5 9
  run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; run record --issue 5 --reason x > /dev/null
  git -C "$T" checkout -q -b idd/5-x; mkdir -p "$T/$(dirname "$p")"; printf 'x\n' > "$T/$p"
  settle 5 > /dev/null 2>&1; assert_exit "commit: $p is committed on the issue's own branch" 0 "$?"
  assert_eq "commit: $p is in that commit" "$p" "$(git -C "$T" show --name-only --format= idd/5-x)"
done

# spec-example: idd-all-rest / a local default branch with commits of its own does not stop the run
new main-ahead 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
printf 'c\n' > "$T/c.txt"; git -C "$T" add c.txt; git -C "$T" commit -q -m "not of any issue"
git -C "$T" checkout -q --no-track -b idd/5-x origin/main
printf 'w\n' > "$T/w.txt"; git -C "$T" add w.txt; git -C "$T" commit -q -m "work of #5"
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2> "$S/err"; rc=$?
assert_exit "main ahead: settle exits 0" 0 "$rc"
assert_eq "main ahead: the working tree is on main" "main" "$(head_branch)"
assert_eq "main ahead: and main still has its own commit" "1" "$(git -C "$T" rev-list --count origin/main..main)"
new main-diverged 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
printf 'c\n' > "$T/c.txt"; git -C "$T" add c.txt; git -C "$T" commit -q -m "not of any issue"; remote_ahead
git -C "$T" fetch -q origin main; git -C "$T" checkout -q --no-track -b idd/5-x origin/main
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2>&1; assert_exit "main diverged: settle exits 0 and leaves main as it is" 0 "$?"
assert_true "main diverged: the empty branch is deleted all the same (its commits are on origin/main)" '! git -C "$T" show-ref --verify --quiet refs/heads/idd/5-x'
new main-behind 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; run record --issue 5 --reason x > /dev/null; remote_ahead
settle 5 > /dev/null 2>&1; assert_exit "main behind: settle exits 0" 0 "$?"
assert_eq "main behind: and main is fast-forwarded" "$(git -C "$S/other" rev-parse HEAD)" "$(git -C "$T" rev-parse HEAD)"
run settle --issue 5 direct-commit > /dev/null 2>&1; assert_exit "settle: a positional argument is a usage error" 2 "$?"

# spec-example: idd-all-rest / a shared log is committed and named as such
new shared-log 5 9
mkdir -p "$T/.claude/.idd"; printf '{"issue":1}\n' > "$T/.claude/.idd/routing-stats.jsonl"
git -C "$T" add .claude/.idd/routing-stats.jsonl; git -C "$T" commit -q -m "stats"; git -C "$T" push -q origin main
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
git -C "$T" checkout -q --no-track -b idd/5-x origin/main
printf 'w\n' > "$T/w.txt"; git -C "$T" add w.txt; git -C "$T" commit -q -m "work of #5"; git -C "$T" push -q -u origin idd/5-x
printf '{"issue":5}\n' >> "$T/.claude/.idd/routing-stats.jsonl"
echo CLOSED > "$G/state-5"; run record --issue 5 > /dev/null
settle 5 > /dev/null 2>&1; rc=$?
assert_exit "shared log: settle exits 0" 0 "$rc"
assert_eq "shared log: the new commit holds the log" ".claude/.idd/routing-stats.jsonl" "$(git -C "$T" show --name-only --format= idd/5-x)"
assert_eq "shared log: and is not pushed" "1" "$(git -C "$T" rev-list --count origin/idd/5-x..idd/5-x)"
KEPT=$(git -C "$T" rev-parse --short=7 idd/5-x)
run report > "$S/report.out" 2>&1
LINE=$(grep -F "#5 — what the run left is kept on idd/5-x (commit $KEPT)" "$S/report.out")
assert_grep "shared log: the report names the branch, the commit and the path under #5" ".claude/.idd/routing-stats.jsonl" "$LINE"
assert_grep "shared log: and says that it is a log shared by all issues" "log shared by all issues" "$LINE"
refute_output_grep "shared log: no line about starting a closed issue over" "later rest run" "$S/report.out"

# spec-example: idd-all-rest / an interrupted settle keeps its commit
new interrupted 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'changed\n' >> "$T/a.txt"
run record --issue 5 --reason x > /dev/null
git -C "$T" remote set-url origin "$S/nowhere.git"
settle 5 > /dev/null 2> "$S/err"; rc=$?
assert_exit "interrupted: the first settle exits 3 when origin cannot be reached" 3 "$rc"
assert_output_grep "interrupted: its reason names the issue" "#5" "$S/err"
assert_output_grep "interrupted: and where the working tree is now" "working tree on main" "$S/err"
reason_shape "interrupted" "$S/err"
assert_eq "interrupted: the reason names the default branch once" "1" "$(sed 's/ (same flags) (.*$//' "$S/err" | grep -o 'main' | wc -l | tr -d ' ')"
FIRST=$(git -C "$T" rev-parse idd/5-x)
assert_eq "interrupted: after it committed a.txt on idd/5-x" "a.txt" "$(git -C "$T" show --name-only --format= idd/5-x)"
run next > /dev/null 2>&1; assert_exit "interrupted: next still waits for settle" 1 "$?"
git -C "$T" remote set-url origin "$T.origin.git"
settle 5 > /dev/null 2>&1; rc=$?
assert_exit "interrupted: the second settle exits 0" 0 "$rc"
assert_eq "interrupted: the run state keeps the commit of the first call and its path" \
  "[{\"branch\":\"idd/5-x\",\"commit\":\"$FIRST\",\"paths\":[\"a.txt\"],\"more\":0,\"shared\":[],\"upstream\":false}]" "$(kept_of 5)"
# spec-example: idd-all-rest / a commit the run state missed is found again
new missed 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'changed\n' >> "$T/a.txt"
run record --issue 5 --reason x > /dev/null
git -C "$T" remote set-url origin "$S/nowhere.git"
settle 5 > /dev/null 2>&1; FIRST=$(git -C "$T" rev-parse idd/5-x)
python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); s["attempts"][-1].pop("kept"); json.dump(s, open(p,"w"))' "$(state_file)"
assert_eq "missed: the record of the kept commit is gone from the state" "[]" "$(kept_of 5)"
git -C "$T" remote set-url origin "$T.origin.git"
settle 5 > /dev/null 2>&1; assert_exit "missed: settle exits 0" 0 "$?"
assert_eq "missed: and finds the commit and its path again" \
  "[{\"branch\":\"idd/5-x\",\"commit\":\"$FIRST\",\"paths\":[\"a.txt\"],\"more\":0,\"shared\":[],\"upstream\":false}]" "$(kept_of 5)"

# spec-example: idd-all-rest / commit hooks that reject the leftovers are skipped for that commit
hook() { printf '%s\n' "$3" > "$1/.git/hooks/$2"; chmod +x "$1/.git/hooks/$2"; }
# hooks that come from git's configuration (hook.<name>.event): only where this git knows them
CONFIG_HOOKS=""
git init -q "$WORK/hookprobe" && git -C "$WORK/hookprobe" config hook.probe.event pre-commit && git -C "$WORK/hookprobe" config hook.probe.command true \
  && git -C "$WORK/hookprobe" hook list pre-commit 2>/dev/null | grep -qx probe && CONFIG_HOOKS="config-pre-commit config-prepare-commit-msg config-and-file config-odd-name config-odd-prepare"
[ -n "$CONFIG_HOOKS" ] || echo "  (this git has no hooks from configuration: five rows of the hook Example are not run)"
for kind in pre-commit prepare-commit-msg formatter $CONFIG_HOOKS; do
  new "hook-$kind" 5 9
  run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
  git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'changed\n' >> "$T/a.txt"
  run record --issue 5 --reason x > /dev/null
  case "$kind" in
    formatter) hook "$T" pre-commit '#!/bin/sh
printf "formatted\n" > a.txt
exit 1' ;;
    config-odd-name) git -C "$T" config "hook.my lint.event" pre-commit; git -C "$T" config "hook.my lint.command" "exit 1" ;;   # a name that cannot be switched off by -c
    config-odd-prepare) git -C "$T" config "hook.my lint.event" prepare-commit-msg; git -C "$T" config "hook.my lint.command" "exit 1" ;;   # --no-verify does not reach this one
    config-and-file) git -C "$T" config hook.lint.event pre-commit; git -C "$T" config hook.lint.command "exit 1"
               hook "$T" pre-commit '#!/bin/sh
exit 1' ;;
    config-*)  git -C "$T" config hook.lint.event "${kind#config-}"; git -C "$T" config hook.lint.command "exit 1" ;;
    *)         hook "$T" "$kind" '#!/bin/sh
exit 1' ;;
  esac
  settle 5 > "$S/out" 2> "$S/err"; rc=$?
  assert_exit "hook $kind: settle exits 0" 0 "$rc"
  assert_eq "hook $kind: idd/5-x has one new commit that holds a.txt" "a.txt" "$(git -C "$T" show --name-only --format= idd/5-x)"
  assert_eq "hook $kind: the commit is the one the helper finds again by its subject" "chore: keep what the run of #5 left (#5)" "$(git -C "$T" log -1 --format=%s idd/5-x)"
  assert_grep "hook $kind: the body of its message says the hooks were skipped" "hooks were skipped" "$(git -C "$T" log -1 --format=%b idd/5-x)"
  [ "$kind" = formatter ] && assert_eq "hook formatter: the commit holds what the hook wrote" "formatted" "$(git -C "$T" show idd/5-x:a.txt)"
  assert_eq "hook $kind: the working tree is on main and clean" "main|" "$(head_branch)|$(git -C "$T" status --porcelain)"
  assert_eq "hook $kind: the run state says so" "skipped" "$(kept_of 5 | python3 -c 'import json,sys; print(json.load(sys.stdin)[0].get("hooks"))')"
  run report > "$S/report.out" 2>&1
  assert_grep "hook $kind: the report says the commit was made without the commit hooks" "without the repository's commit hooks" "$(stopped_block "$S/report.out")"
done
# Scenario: commit hooks that accept the leftovers run
new hook-accepts 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'changed\n' >> "$T/a.txt"
run record --issue 5 --reason x > /dev/null
hook "$T" pre-commit '#!/bin/sh
: > "$(git rev-parse --git-dir)/hook-ran"'
settle 5 > /dev/null 2>&1; assert_exit "hook accepts: settle exits 0" 0 "$?"
assert_true "hook accepts: the hook has run" '[ -f "$T/.git/hook-ran" ]'
refute_grep "hook accepts: the commit message does not say hooks were skipped" "skipped" "$(git -C "$T" log -1 --format=%B idd/5-x)"
assert_eq "hook accepts: neither does the run state" "None" "$(kept_of 5 | python3 -c 'import json,sys; print(json.load(sys.stdin)[0].get("hooks"))')"
# Scenario: a hook that fails after the checkout
new hook-post-checkout 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
git -C "$T" checkout -q --no-track -b idd/5-x origin/main
printf 'w\n' > "$T/w.txt"; git -C "$T" add w.txt; git -C "$T" commit -q -m "work of #5"
run record --issue 5 --reason x > /dev/null
hook "$T" post-checkout '#!/bin/sh
exit 1'
settle 5 > /dev/null 2> "$S/err"; assert_exit "post-checkout hook: settle exits 0" 0 "$?"
assert_eq "post-checkout hook: the working tree is on main" "main" "$(head_branch)"

# spec-example: idd-all-rest / files that only the issue's branch ignores are stashed
new branch-ignores 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
git -C "$T" checkout -q --no-track -b idd/5-x origin/main
printf 'coverage/\n' > "$T/.gitignore"; git -C "$T" add .gitignore; git -C "$T" commit -q -m "ignore coverage (#5)"
mkdir -p "$T/coverage"; printf 'the report\n' > "$T/coverage/report.txt"
run record --issue 5 --reason x > /dev/null
settle 5 > "$S/out" 2> "$S/err"; rc=$?
assert_exit "branch ignores: settle exits 0" 0 "$rc"
assert_eq "branch ignores: the working tree is on main and git status prints nothing" "main|" "$(head_branch)|$(git -C "$T" status --porcelain)"
assert_eq "branch ignores: one stash entry has the message" "1" "$(git -C "$T" stash list --format=%gs | grep -c 'idd rest: files of #5 that only idd/5-x ignores$')"
STASH=$(git -C "$T" rev-parse refs/stash)
run report > "$S/report.out" 2>&1
assert_grep "branch ignores: the report names the stash commit and how to get the files back" "git stash apply $STASH on that branch" "$(stopped_block "$S/report.out")"
assert_grep "branch ignores: and the path" "coverage/" "$(stopped_block "$S/report.out" | grep -F 'stash')"
git -C "$T" checkout -q idd/5-x; git -C "$T" stash apply -q "$STASH"
assert_eq "branch ignores: applied on the branch, the file is there again with its content" "the report" "$(cat "$T/coverage/report.txt" 2>/dev/null)"
new branch-ignores-and-more 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
git -C "$T" checkout -q --no-track -b idd/5-x origin/main
printf 'coverage/\n' > "$T/.gitignore"; git -C "$T" add .gitignore; git -C "$T" commit -q -m "ignore coverage (#5)"
mkdir -p "$T/coverage"; printf 'r\n' > "$T/coverage/report.txt"
run record --issue 5 --reason x > /dev/null
hook "$T" post-checkout '#!/bin/sh
printf "stray\n" > stray.txt'
settle 5 > /dev/null 2> "$S/err"; assert_exit "branch ignores: a file that was not ignored on the branch still stops (exit 3)" 3 "$?"
assert_eq "branch ignores: and nothing was stashed" "" "$(git -C "$T" stash list)"
assert_output_grep "branch ignores: the reason names the working tree's branch once" "working tree on main" "$S/err"

# spec-example: idd-all-rest / a long branch name does not cut off the next step
new long-branch 5 9
LONG="idd/5-$(printf 'a%.0s' 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40)"
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
git -C "$T" checkout -q --no-track -b "$LONG" origin/main; mkdir -p "$T/.claude/worktrees" "$T/.claude/.idd"
printf 'pid\n' > "$T/.claude/.idd/tree-lock"
for i in 1 2 3 4 5; do printf 'x\n' > "$T/.claude/worktrees/a-very-long-file-name-that-fills-the-line-and-then-some-more-of-it-number-$i.txt"; done
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2> "$S/err"; assert_exit "long branch: settle exits 3" 3 "$?"
reason_shape "long branch" "$S/err"
assert_eq "long branch: the branch name appears once" "1" "$(grep -o "$LONG" "$S/err" | wc -l | tr -d ' ')"
assert_grep_re "long branch: the line ends with the number of the paths it did not name" 'and [0-9]+ more\)$|[0-9]+ path\(s\)\)$' "$(cat "$S/err")"
# every git step of settle, failed once and run again: the commit recorded first is still the one recorded
SHAPE=$(python3 - "$RQ" <<'SHAPE_PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("rq", sys.argv[1]); rq = importlib.util.module_from_spec(spec); spec.loader.exec_module(rq)
todo = "do the one thing that puts it right, " + rq.AGAIN
line = str(rq.SettleStop(5, "idd/5-" + "a" * 40, "what is wrong, said at great length " * 12, todo, "git's own words " * 30))
print(len(line) <= rq.REASON_MAX, todo in line, line.count("idd/5-"), "what is wrong" in line, line.endswith(")"))
SHAPE_PY
)
TIGHT=$(python3 - "$RQ" <<'TIGHT_PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("rq", sys.argv[1]); rq = importlib.util.module_from_spec(spec); spec.loader.exec_module(rq)
todo = "s" * 163 + ", " + rq.AGAIN   # a next step so long that a 60-character branch name does not fit beside it
line = str(rq.SettleStop(5, "b" * 60, "what is wrong", todo))
print(len(line) <= rq.REASON_MAX, todo in line, rq.ON_MIN <= line.count("b") < 60)
TIGHT_PY
)
assert_eq "reason: beside a very long next step the branch name is shortened, never below its least, and the step stays whole" "True True True" "$TIGHT"
assert_eq "reason: a long problem is cut first, the next step stays whole, the line fits and still carries the detail" "True True 1 True True" "$SHAPE"
# every stop of settle, with names as long as a reason line shows them: the next step is whole and the line fits
new longest 5 9
NAME40=$(python3 -c 'print("d" * 40)'); LONG5="idd/5-$(python3 -c 'print("b" * 54)')"   # 40 and 60 characters
git -C "$T" branch -q -m main "$NAME40"; git -C "$T" push -q origin "$NAME40" 2>/dev/null; printf '%s\n' "$NAME40" > "$G/default-branch"
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
git -C "$T" checkout -q --no-track -b "$LONG5" "origin/$NAME40"; mkdir -p "$T/.claude/.idd"; printf 'pid\n' > "$T/.claude/.idd/tree-lock"
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2> "$S/err"; assert_exit "longest: settle exits 3" 3 "$?"
reason_shape "longest" "$S/err"
assert_output_grep "longest: the checkout command is whole, with the whole name" "then git checkout --no-overwrite-ignore $NAME40, then run the same /idd-all command again (same flags)" "$S/err"
# a default branch whose name a shell would not read as one word is not put into a command
for name in 'ma;in' 'a$(touch${IFS}made-by-the-name)' "$(python3 -c 'print("d" * 41)')"; do
  new "odd-default" 5 9; rm -rf "$S/made"; mkdir -p "$S/made"
  git -C "$T" branch -q -m main "$name"; git -C "$T" push -q origin "$name" 2>/dev/null; printf '%s\n' "$name" > "$G/default-branch"
  run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
  git -C "$T" checkout -q --no-track -b idd/5-x "origin/$name"; mkdir -p "$T/.claude/.idd"; printf 'pid\n' > "$T/.claude/.idd/tree-lock"
  run record --issue 5 --reason x > /dev/null
  settle 5 > /dev/null 2> "$S/err"; assert_exit "odd default branch: settle exits 3" 3 "$?"
  assert_output_grep "odd default branch: the command holds a placeholder" "then git checkout --no-overwrite-ignore <the default branch>, then run the same /idd-all command again (same flags)" "$S/err"
  refute_grep "odd default branch: and not the name" "$name" "$(cat "$S/err")"
  rm -rf "$WORK/odd-default"
done
new discard-order 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; download 5 "$T" with_url
run record --issue 5 --reason x > /dev/null
OUT=$(settle 5 2>/dev/null)
assert_eq "discard: the manifest and the file it vouches for are discarded, the manifest last" \
  '[".claude/.idd/attachments/issue-5/spec.docx",".claude/.idd/attachments/issue-5/_manifest.json"]' "$(printf '%s' "$OUT" | jget discarded)"
assert_eq "discard: a second settle prints the same records" "$(printf '%s' "$OUT" | jget discarded)" "$(settle 5 2>/dev/null | jget discarded)"

for step in checkout; do   # the fast-forward has a check of its own below: settle now moves the default branch before the checkout
  new "fail-$step" 5 9
  run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
  git -C "$T" checkout -q --no-track -b idd/5-x "$(git -C "$T" rev-parse main)"; printf 'changed\n' >> "$T/a.txt"
  run record --issue 5 --reason x > /dev/null
  case "$step" in
    checkout) hook "$T" post-commit '#!/bin/sh
: > "$(git rev-parse --git-dir)/index.lock"' ;;
    merge)    hook "$T" post-checkout '#!/bin/sh
: > "$(git rev-parse --git-dir)/index.lock"' ;;
  esac
  settle 5 > /dev/null 2> "$S/err"; rc=$?
  assert_exit "fail $step: settle exits 3" 3 "$rc"
  assert_eq "fail $step: with one reason line" "1" "$(wc -l < "$S/err" | tr -d ' ')"
  assert_output_grep "fail $step: that names the issue" "#5" "$S/err"
  reason_shape "fail $step" "$S/err"
  rm -f "$T/.git/hooks/post-commit" "$T/.git/hooks/post-checkout" "$T/.git/index.lock"
  FIRST=$(kept_of 5 | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["commit"])')
  settle 5 > /dev/null 2>&1; rc=$?
  assert_exit "fail $step: the second settle exits 0" 0 "$rc"
  assert_eq "fail $step: the branch holds the leftover" "a.txt" "$(git -C "$T" show --name-only --format= idd/5-x)"
  assert_eq "fail $step: the run state still records the first commit, the tip of the branch" "$FIRST|$(git -C "$T" rev-parse idd/5-x)" \
    "$(kept_of 5 | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["commit"])')|$FIRST"
  assert_eq "fail $step: the working tree is clean on main" "main|" "$(head_branch)|$(git -C "$T" status --porcelain)"
done

# the fast-forward fails where the working tree was on the default branch all along; a second settle finishes it
new fail-merge 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; remote_ahead
run record --issue 5 --reason x > /dev/null
: > "$T/.git/index.lock"
settle 5 > /dev/null 2> "$S/err"; rc=$?
assert_exit "fail merge: settle exits 3" 3 "$rc"
assert_eq "fail merge: with one reason line" "1" "$(wc -l < "$S/err" | tr -d ' ')"
assert_output_grep "fail merge: that names the issue" "#5" "$S/err"
reason_shape "fail merge" "$S/err"
rm -f "$T/.git/index.lock"
settle 5 > /dev/null 2>&1; assert_exit "fail merge: the second settle exits 0" 0 "$?"
assert_eq "fail merge: main is at origin/main and clean" "$(git -C "$T" rev-parse origin/main)|" "$(git -C "$T" rev-parse HEAD)|$(git -C "$T" status --porcelain)"

echo "── what a stop tells a person to do ──"
ended() { # what idd-all does after settle stopped the run: stop with that reason, then the report, which ends the run
  sed 's/^rest-queue: //' "$S/err" | run stop --reason-stdin > /dev/null 2>&1; run report > "$S/report.out" 2>&1
}
accepts() { run start --path PR --review no > /dev/null 2> "$S/start.err"; assert_exit "$1" 0 "$?"; }
begin() { run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; }   # a new run, #5 handed out
before_detail() { sed 's/ (same flags) (.*$/ (same flags)/' "$1"; }                    # the reason without git's words

# a repository with a person's own ignored files: tools/.gitignore ignores .env, and tools/.env is there before the run
with_tools() {
  mkdir -p "$T/tools"; printf '#!/bin/sh\n' > "$T/tools/run.sh"; printf '.env\n' > "$T/tools/.gitignore"
  git -C "$T" add tools; git -C "$T" commit -q -m "tools"; git -C "$T" push -q origin main 2>/dev/null
  printf 'TOKEN=ghp_secret\n' > "$T/tools/.env"
}
squash5() { # GitHub squash-merged the pull request of idd/5-x and closed #5; #9 is the only open issue
  C=$(git -C "$T.origin.git" commit-tree "$(git -C "$T.origin.git" rev-parse 'idd/5-x^{tree}')" -p main -m "squash (#5)")
  git -C "$T.origin.git" update-ref refs/heads/main "$C"; echo CLOSED > "$G/state-5"; issues 9
}
python3 "$HERE/treecheck.py" --self-test > "$WORK/treecheck.out" 2>&1; assert_exit "treecheck: the file-system check passes its own test" 0 "$?"

# spec-example: idd-all-rest / a file that was there before the run is left where it is
new before-run 5 9
with_tools
hook "$T" pre-commit '#!/bin/sh
if git diff --cached | grep -q ghp_; then echo "secret scan: a token is staged" >&2; exit 1; fi
: > "$(git rev-parse --git-dir)/scan-ran"'
begin
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; git -C "$T" rm -q -r tools; git -C "$T" commit -q -m "remove tools (#5)"
rm -f "$T/.git/scan-ran"; printf 'changed\n' >> "$T/a.txt"
run record --issue 5 --reason x > /dev/null
settle 5 > "$S/out" 2> "$S/err"; assert_exit "before the run: settle exits 0" 0 "$?"
assert_eq "before the run: the new commit on idd/5-x holds a.txt and not tools/.env" "a.txt" "$(git -C "$T" show --name-only --format= idd/5-x)"
assert_true "before the run: the hook has run and accepted that commit" '[ -f "$T/.git/scan-ran" ]'
refute_grep "before the run: the commit message does not say hooks were skipped" "skipped" "$(git -C "$T" log -1 --format=%B idd/5-x)"
assert_eq "before the run: tools/.env is in the working tree with its content" "TOKEN=ghp_secret" "$(cat "$T/tools/.env" 2>/dev/null)"
assert_eq "before the run: the working tree is on main and git status prints nothing" "main|" "$(head_branch)|$(git -C "$T" status --porcelain)"
run report > "$S/report.out" 2>&1
refute_output_grep "before the run: the report does not name tools/.env" "tools/.env" "$S/report.out"

# spec-example: idd-all-rest / a path the default branch no longer ignores goes into the local exclude file
new exclude 5 9
with_tools
begin
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; git -C "$T" rm -q -r tools; git -C "$T" commit -q -m "remove tools (#5)"
git -C "$T" push -q -u origin idd/5-x 2>/dev/null; squash5
run record --issue 5 > /dev/null
settle 5 > "$S/out" 2> "$S/err"; assert_exit "exclude: settle exits 0" 0 "$?"
assert_eq "exclude: settle prints tools/.env as excluded" '["tools/.env"]' "$(jget excluded < "$S/out")"
assert_true "exclude: .git/info/exclude holds the line /tools/.env" 'grep -qx "/tools/.env" "$T/.git/info/exclude"'
assert_grep "exclude: under a comment line that names #5" "#5" "$(grep -B1 -x '/tools/.env' "$T/.git/info/exclude" | sed -n 1p)"
assert_eq "exclude: tools/.env still holds its content" "TOKEN=ghp_secret" "$(cat "$T/tools/.env" 2>/dev/null)"
assert_eq "exclude: main is at origin/main and git status prints nothing" "$(git -C "$T" rev-parse origin/main)|" "$(git -C "$T" rev-parse HEAD)|$(git -C "$T" status --porcelain)"
assert_eq "exclude: a second settle prints the same path" '["tools/.env"]' "$(settle 5 2>/dev/null | jget excluded)"
assert_eq "exclude: next hands out #9" "9" "$(run next | jget next)"
run report > "$S/report.out" 2>&1
LINE=$(grep -F 'tools/.env' "$S/report.out")
assert_grep "exclude: the report says the path was there before the run" "before the run" "$LINE"
assert_grep "exclude: and that it was added to .git/info/exclude" ".git/info/exclude" "$LINE"

# spec-example: idd-all-rest / a file the issue stopped tracking does not stop the run
for how in stopped merged; do
  new "untrack-$how" 5 9
  begin
  git -C "$T" checkout -q --no-track -b idd/5-x origin/main
  git -C "$T" rm -q --cached a.txt; printf 'a.txt\n' > "$T/.gitignore"; git -C "$T" add .gitignore; git -C "$T" commit -q -m "stop tracking a.txt (#5)"
  if [ "$how" = stopped ]; then
    printf 'the run wrote this\n' > "$T/a.txt"; run record --issue 5 --reason x > /dev/null
  else
    git -C "$T" push -q -u origin idd/5-x 2>/dev/null; squash5; run record --issue 5 > /dev/null
  fi
  settle 5 > "$S/out" 2> "$S/err"; assert_exit "untrack, $how: settle exits 0" 0 "$?"
  assert_eq "untrack, $how: the working tree is on main and git status prints nothing" "main|" "$(head_branch)|$(git -C "$T" status --porcelain)"
  if [ "$how" = stopped ]; then
    assert_eq "untrack, stopped: one stash entry has the message" "1" \
      "$(git -C "$T" stash list --format=%gs | grep -c 'idd rest: files of #5 that idd/5-x ignores and the default branch tracks$')"
    assert_eq "untrack, stopped: and holds a.txt" '["a.txt"]' "$(stash0 paths < "$S/out")"
    assert_eq "untrack, stopped: a.txt on main holds what main has" "a" "$(cat "$T/a.txt")"
    STASH=$(stash0 commit < "$S/out")
    assert_eq "untrack, stopped: next hands out #9" "9" "$(run next | jget next)"
    run report > "$S/report.out" 2>&1
    assert_output_grep "untrack, stopped: the report names the stash commit and where to apply it" "git stash apply $STASH on that branch" "$S/report.out"
    git -C "$T" checkout -q --no-overwrite-ignore idd/5-x; git -C "$T" stash apply -q "$STASH"
    assert_eq "untrack, stopped: applied on idd/5-x, a.txt holds what the run wrote" "the run wrote this" "$(cat "$T/a.txt")"
  else
    assert_eq "untrack, merged: no stash entry" "" "$(git -C "$T" stash list)"
    assert_eq "untrack, merged: main is at origin/main" "$(git -C "$T" rev-parse origin/main)" "$(git -C "$T" rev-parse main)"
    assert_eq "untrack, merged: a.txt is there with the content it had" "a" "$(cat "$T/a.txt")"
    assert_eq "untrack, merged: next hands out #9" "9" "$(run next | jget next)"
  fi
done

# spec-example: idd-all-rest / what a rejecting hook wrote is looked at again
for wrote in lint.log tree-lock; do
  new "hook-wrote-$wrote" 5 9
  begin
  git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'changed\n' >> "$T/a.txt"
  run record --issue 5 --reason x > /dev/null
  case "$wrote" in
    lint.log)  hook "$T" pre-commit '#!/bin/sh
printf "lint\n" > lint.log
exit 1' ;;
    tree-lock) hook "$T" pre-commit '#!/bin/sh
mkdir -p .claude/.idd; printf "pid\n" > .claude/.idd/tree-lock
exit 1' ;;
  esac
  settle 5 > "$S/out" 2> "$S/err"; rc=$?
  if [ "$wrote" = lint.log ]; then
    assert_exit "hook wrote lint.log: settle exits 0" 0 "$rc"
    assert_eq "hook wrote lint.log: the commit made without the hooks holds a.txt and lint.log" "a.txt lint.log" "$(git -C "$T" show --name-only --format= idd/5-x | sort | tr '\n' ' ' | sed 's/ $//')"
    assert_eq "hook wrote lint.log: and the run state names both" '["a.txt","lint.log"]' "$(kept_of 5 | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)[0]["paths"], separators=(",",":")))')"
  else
    assert_exit "hook wrote the tree lock: settle exits 3" 3 "$rc"
    assert_output_grep "hook wrote the tree lock: the reason names the path" ".claude/.idd/tree-lock" "$S/err"
    assert_eq "hook wrote the tree lock: idd/5-x has no new commit" "$(git -C "$T" rev-parse origin/main)" "$(git -C "$T" rev-parse idd/5-x)"
  fi
done

# spec-example: idd-all-rest / a settle that stopped gives no delete step for a pushed branch
new stopped-pushed 5 9
begin
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'w\n' > "$T/w.txt"; git -C "$T" add w.txt; git -C "$T" commit -q -m "work (#5)"
git -C "$T" push -q -u origin idd/5-x 2>/dev/null; git -C "$T" branch -q --no-track idd/5-y origin/main
printf 'changed\n' >> "$T/a.txt"
hook "$T" post-checkout '#!/bin/sh
printf "stray\n" > stray.txt'
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2> "$S/err"; assert_exit "stopped, pushed: settle exits 3" 3 "$?"
assert_eq "stopped, pushed: after it committed a.txt on idd/5-x" "a.txt" "$(git -C "$T" show --name-only --format= idd/5-x)"
ended
LINE=$(grep -F 'branch idd/5-x is kept' "$S/report.out")
assert_grep "stopped, pushed: the report names idd/5-x with what its commit holds" "a.txt" "$LINE"
refute_grep "stopped, pushed: and gives no delete step for it" "deleting it" "$LINE"
assert_grep "stopped, pushed: the report names idd/5-y as a branch of #5 without a commit of its own" "idd/5-y" "$(grep -F 'no commit of its own' "$S/report.out")"

# spec-example: idd-all-rest / a settle that stopped gives the delete step only where the record says no upstream
for record in none dropped; do
  new "stopped-$record" 5 9
  begin
  git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'w\n' > "$T/w.txt"; git -C "$T" add w.txt; git -C "$T" commit -q -m "work (#5)"
  printf 'changed\n' >> "$T/a.txt"
  hook "$T" post-checkout '#!/bin/sh
printf "stray\n" > stray.txt'
  run record --issue 5 --reason x > /dev/null
  settle 5 > /dev/null 2> "$S/err"; assert_exit "stopped, upstream $record: settle exits 3" 3 "$?"
  if [ "$record" = dropped ]; then   # a record that does not say whether the branch has an upstream
    python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); [k.pop("upstream", None) for k in s["attempts"][0]["kept"]]; json.dump(s, open(p,"w"))' "$(state_file)"
  fi
  ended
  LINE=$(grep -F 'branch idd/5-x is kept' "$S/report.out")
  assert_grep "stopped, upstream $record: the report names idd/5-x with what its commit holds" "a.txt" "$LINE"
  if [ "$record" = none ]; then
    assert_grep "stopped, upstream none: and gives the delete step for it" "it has no upstream: deleting it" "$LINE"
  else
    refute_grep "stopped, upstream dropped from the record: and gives no delete step for it" "deleting it" "$LINE"
  fi
done

# spec-example: idd-all-rest / a file the default branch tracks is not overwritten
ignore_local() { printf 'local/\n' > "$T/.gitignore"; git -C "$T" add .gitignore; git -C "$T" commit -q -m "ignore local"; git -C "$T" push -q origin main 2>/dev/null; mkdir -p "$T/local"; }
tracked_elsewhere() { # someone else commits the same paths on origin/main
  git clone -q "$T.origin.git" "$S/other" 2>/dev/null; mkdir -p "$S/other/local"
  for f in "$@"; do printf 'theirs\n' > "$S/other/local/$f"; done
  git -C "$S/other" add -f local; git -C "$S/other" commit -q -m "track local"; git -C "$S/other" push -q origin main 2>/dev/null
}
new overwrite 5 9
ignore_local; printf 'mine\n' > "$T/local/settings.json"
begin
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'w\n' > "$T/w.txt"; git -C "$T" add w.txt; git -C "$T" commit -q -m "work (#5)"
tracked_elsewhere settings.json
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2> "$S/err"; rc=$?
assert_exit "overwrite: settle exits 3" 3 "$rc"
assert_eq "overwrite: the file still holds what it held, and the working tree is on the issue's branch" \
  "idd/5-x|mine" "$(head_branch)|$(cat "$T/local/settings.json")"
assert_eq "overwrite: no stash was made" "" "$(git -C "$T" stash list)"
reason_shape "overwrite" "$S/err"
assert_output_grep "overwrite: the reason gives the checkout that does not overwrite" "run git checkout --no-overwrite-ignore main and move away each file it names until it succeeds" "$S/err"
ended
git -C "$T" checkout -q --no-overwrite-ignore main 2> "$S/git.err"; assert_exit "overwrite: that checkout fails while the file is in the way" 1 "$?"
assert_output_grep "overwrite: and names the file" "local/settings.json" "$S/git.err"
mv "$T/local" "$S/local.kept"; git -C "$T" checkout -q --no-overwrite-ignore main
accepts "overwrite: with the file moved away and that checkout done, a new run starts"
# the same with names too long for a reason line: the steps still lose nothing
new overwrite-long 5 9
LONGNAME="settings-for-the-local-development-environment-of-this-repository-number"
ignore_local; for i in 1 2 3 4; do printf 'mine\n' > "$T/local/$LONGNAME-$i.json"; done
begin
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'w\n' > "$T/w.txt"; git -C "$T" add w.txt; git -C "$T" commit -q -m "work (#5)"
tracked_elsewhere "$LONGNAME-1.json" "$LONGNAME-2.json" "$LONGNAME-3.json" "$LONGNAME-4.json"
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2> "$S/err"; assert_exit "overwrite, long names: settle exits 3" 3 "$?"
reason_shape "overwrite, long names" "$S/err"
ended
git -C "$T" checkout -q --no-overwrite-ignore main 2> "$S/git.err"; assert_exit "overwrite, long names: the checkout the reason gives fails" 1 "$?"
assert_eq "overwrite, long names: and names all four files in full" "4" "$(grep -c "$LONGNAME" "$S/git.err")"
mv "$T/local" "$S/local.kept"; git -C "$T" checkout -q --no-overwrite-ignore main
assert_eq "overwrite, long names: every file still holds what it held" "4" "$(grep -l 'mine' "$S"/local.kept/*.json | wc -l | tr -d ' ')"
accepts "overwrite, long names: and a new run starts"

# ── files from before the run that the issue's branch tracks, or that a hook stages ──
lockfile() { # the rule `package-lock.json`, and the file, there before the run
  printf 'package-lock.json\n' > "$T/.gitignore"; git -C "$T" add .gitignore; git -C "$T" commit -q -m "ignore the lockfile"; git -C "$T" push -q origin main 2>/dev/null
  printf '{"lock": "MINE"}\n' > "$T/package-lock.json"
}
tracks_lockfile() { # #5 handed out; its branch drops the rule and commits the file
  begin
  git -C "$T" checkout -q --no-track -b idd/5-x origin/main; : > "$T/.gitignore"
  git -C "$T" add -- .gitignore package-lock.json; git -C "$T" commit -q -m "track the lockfile (#5)"
}
set_aside() { # what a settle leaves that was killed after it had set the file aside
  H="$T/.claude/.idd/state/rest-held-5"; mkdir -p "$H"; printf '[{"path": "%s", "name": "0"}]' "${1:-package-lock.json}" > "$H/held.json"
  mv "$T/package-lock.json" "$H/0"
}
state_list() { # key → that list of the first attempt in the run state, as compact JSON
  python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["attempts"][0].get(sys.argv[2], "<missing>"), separators=(",",":")))' "$(state_file)" "$1"
}

# spec-example: idd-all-rest / a path whose rule someone else removed goes into the local exclude file and not into a stash
new exclude-elsewhere 5 9
lockfile
begin
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'w\n' > "$T/w.txt"; git -C "$T" add w.txt; git -C "$T" commit -q -m "work (#5)"
git clone -q "$T.origin.git" "$S/other" 2>/dev/null; : > "$S/other/.gitignore"
git -C "$S/other" commit -q -a -m "drop the rule"; git -C "$S/other" push -q origin main 2>/dev/null
run record --issue 5 --reason x > /dev/null
settle 5 > "$S/out" 2> "$S/err"; assert_exit "exclude, rule removed elsewhere: settle exits 0" 0 "$?"
assert_eq "exclude, rule removed elsewhere: the file is in the working tree as it was" '{"lock": "MINE"}' "$(cat "$T/package-lock.json" 2>/dev/null)"
assert_eq "exclude, rule removed elsewhere: it is recorded as excluded, and no stash was made" '["package-lock.json"]|[]|' "$(jget excluded < "$S/out")|$(jget stashes < "$S/out")|$(git -C "$T" stash list)"
assert_eq "exclude, rule removed elsewhere: the working tree is on main and git status prints nothing" "main|" "$(head_branch)|$(git -C "$T" status --porcelain)"

# ── fix round 7: one reader of the working tree, one check of every kept commit ──
# spec-example: idd-all-rest / what git shows by default does not change what is handed out
new hidden-untracked-start 5 9
git -C "$T" config status.showUntrackedFiles no; printf 'notes\n' > "$T/local-notes.txt"
run start --path PR --review no > /dev/null 2> "$S/err"; assert_exit "hidden untracked file: start exits 3" 3 "$?"
assert_output_grep "hidden untracked file: start names the file" "local-notes.txt" "$S/err"
new hidden-untracked-next 5 9
run start --path PR --review no > /dev/null 2>&1
git -C "$T" config status.showUntrackedFiles no; printf 'notes\n' > "$T/local-notes.txt"
run next > "$S/out" 2> "$S/err"; assert_exit "hidden untracked file: next exits 3" 3 "$?"
assert_output_grep "hidden untracked file: next names the file" "local-notes.txt" "$S/err"
assert_eq "hidden untracked file: and the run state holds no attempt" "0" "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["attempts"]))' "$(state_file)")"
assert_eq "hidden untracked file: the file is untouched" "notes" "$(cat "$T/local-notes.txt")"

# spec-example: idd-all-rest / a hook that lets the commit through cannot add a file that is never committed
new hook-adds-keep-out 5 9
begin
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'changed\n' >> "$T/a.txt"
hook "$T" pre-commit '#!/bin/sh
mkdir -p .claude/worktrees && printf "x\n" > .claude/worktrees/from-the-hook.txt
git add -A'
TIP=$(git -C "$T" rev-parse idd/5-x)
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2> "$S/err"; assert_exit "hook adds a file that is never committed: settle exits 3" 3 "$?"
assert_eq "hook adds a file that is never committed: idd/5-x has no new commit" "$TIP" "$(git -C "$T" rev-parse idd/5-x)"
assert_output_grep "hook adds a file that is never committed: the reason names the file" ".claude/worktrees/from-the-hook.txt" "$S/err"
assert_eq "hook adds a file that is never committed: the change of a.txt is still in the working tree" "changed" "$(tail -1 "$T/a.txt")"
assert_eq "hook adds a file that is never committed: the working tree stays on the issue's branch" "idd/5-x" "$(head_branch)"
assert_output_grep "hook adds a file that is never committed: the reason says so" "it holds files that are never committed" "$S/err"
reason_shape "hook adds a file that is never committed" "$S/err"

# spec-example: idd-all-rest / a record a rejecting hook wrote is discarded, not committed
new hook-writes-record 5 9
begin
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'changed\n' >> "$T/a.txt"
hook "$T" pre-commit '#!/bin/sh
mkdir -p .claude/.idd/attachments/issue-5 && printf "{\"issue\": 5, \"files\": []}" > .claude/.idd/attachments/issue-5/_manifest.json
git add -A
exit 1'
run record --issue 5 --reason x > /dev/null
settle 5 > "$S/out" 2> "$S/err"; assert_exit "hook writes a record and rejects: settle exits 0" 0 "$?"
assert_eq "hook writes a record and rejects: the new commit holds a.txt only" "a.txt" "$(git -C "$T" show --name-only --format= idd/5-x)"
assert_eq "hook writes a record and rejects: the record is among the discarded" '[".claude/.idd/attachments/issue-5/_manifest.json"]' "$(jget discarded < "$S/out")"

# spec-example: idd-all-rest / a kept commit that holds a file from before the run stops settle on the default branch
new kept-commit-bad 5 9
with_tools
begin
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'changed\n' >> "$T/a.txt"
git -C "$T" add -f -- a.txt tools/.env; git -C "$T" commit -q -m "chore: keep what the run of #5 left (#5)"
BAD=$(git -C "$T" rev-parse --short=7 idd/5-x)
cp "$T/tools/.env" "$S/env.kept"; git -C "$T" checkout -q main; cp "$S/env.kept" "$T/tools/.env"   # the checkout takes the file out: it is put back by hand
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2> "$S/err"; assert_exit "a kept commit with a file from before: settle exits 3" 3 "$?"
assert_output_grep "a kept commit with a file from before: the reason names the commit" "$BAD" "$S/err"
assert_output_grep "a kept commit with a file from before: and the file" "tools/.env" "$S/err"
assert_eq "a kept commit with a file from before: the file is in the working tree" "TOKEN=ghp_secret" "$(cat "$T/tools/.env" 2>/dev/null)"
reason_shape "a kept commit with a file from before" "$S/err"

# spec-example: idd-all-rest / a rule of the default branch that un-ignores the file stops settle
new exclude-negated 5 9
lockfile
begin
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'w\n' > "$T/w.txt"; git -C "$T" add w.txt; git -C "$T" commit -q -m "work (#5)"
git clone -q "$T.origin.git" "$S/other" 2>/dev/null; printf '!package-lock.json\n' > "$S/other/.gitignore"
git -C "$S/other" commit -q -a -m "never ignore the lockfile"; git -C "$S/other" push -q origin main 2>/dev/null
run record --issue 5 --reason x > /dev/null
settle 5 > "$S/out" 2> "$S/err"; assert_exit "a rule un-ignores the file: settle exits 3" 3 "$?"
assert_eq "a rule un-ignores the file: the file is in the working tree as it was" '{"lock": "MINE"}' "$(cat "$T/package-lock.json" 2>/dev/null)"
assert_eq "a rule un-ignores the file: the run state does not say it was excluded" "[]" "$(state_list excluded | sed 's/"<missing>"/[]/')"
assert_eq "a rule un-ignores the file: the local exclude file has no line for it" "0" "$(grep -c 'package-lock' "$T/.git/info/exclude")"
assert_eq "a rule un-ignores the file: and no comment line of settle is left behind" "0" "$(grep -c 'idd rest' "$T/.git/info/exclude")"
assert_output_grep "a rule un-ignores the file: the reason names it" "package-lock.json" "$S/err"
assert_output_grep "a rule un-ignores the file: and says the local exclude file cannot hide it" "local exclude file cannot hide" "$S/err"
reason_shape "a rule un-ignores the file" "$S/err"

# spec-example: idd-all-rest / what git is configured to print does not change what settle compares
new relative-diff 5 9
mkdir -p "$T/sub"; printf 's\n' > "$T/sub/s.txt"; printf 'local.cfg\n' > "$T/.gitignore"
git -C "$T" add sub/s.txt .gitignore; git -C "$T" commit -q -m sub; git -C "$T" push -q origin main 2>/dev/null
printf 'sub/.claude/.idd/state/\n' >> "$T/.git/info/exclude"
git -C "$T" config diff.relative true; git -C "$T" config log.showSignature true
printf 'MINE\n' > "$T/local.cfg"
rq start --cwd "$T/sub" --repo "$REPO" --path PR --review no > /dev/null 2>&1; rq next --cwd "$T/sub" --repo "$REPO" > /dev/null
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; : > "$T/.gitignore"
git -C "$T" add -- .gitignore local.cfg; git -C "$T" commit -q -m "track the settings (#5)"
git clone -q "$T.origin.git" "$S/other" 2>/dev/null; printf 'THEIRS\n' > "$S/other/local.cfg"
git -C "$S/other" add -f local.cfg; git -C "$S/other" commit -q -m "settings of the team"; git -C "$S/other" push -q origin main 2>/dev/null
rq record --cwd "$T/sub" --repo "$REPO" --issue 5 --reason x > /dev/null
rq settle --cwd "$T/sub" --repo "$REPO" --issue 5 > /dev/null 2> "$S/err"; assert_exit "relative diff, below the top: settle exits 3" 3 "$?"
assert_eq "relative diff, below the top: the file holds what it held" "MINE" "$(cat "$T/local.cfg" 2>/dev/null)"
assert_output_grep "relative diff, below the top: the reason names the file" "local.cfg" "$S/err"

# spec-example: idd-all-rest / a carriage return in a file name
new odd-name 5 9
printf 'odd*\n' > "$T/.gitignore"; git -C "$T" add .gitignore; git -C "$T" commit -q -m "ignore odd"; git -C "$T" push -q origin main 2>/dev/null
ODD="$T/$(printf 'odd\rname.txt')"
if printf 'MINE\n' > "$ODD" 2>/dev/null && [ -f "$ODD" ]; then
  begin
  git -C "$T" checkout -q --no-track -b idd/5-x origin/main; : > "$T/.gitignore"
  git -C "$T" add -A; git -C "$T" commit -q -m "track the odd file (#5)"
  run record --issue 5 --reason x > /dev/null
  settle 5 > "$S/out" 2> "$S/err"; assert_exit "a carriage return in a name: settle exits 0" 0 "$?"
  assert_eq "a carriage return in a name: the file is in the working tree as it was" "MINE" "$(cat "$ODD" 2>/dev/null)"
  assert_eq "a carriage return in a name: nothing is recorded as missing" "[]" "$(jget missing < "$S/out")"
  assert_eq "a carriage return in a name: the working tree is on main and git status prints nothing" "main|" "$(head_branch)|$(git -C "$T" status --porcelain)"
else
  echo "  (skipped: this file system does not take a carriage return in a file name)"
fi

# spec-example: idd-all-rest / a file that origin puts where an ignored folder stands
new folder-in-the-way 5 9
printf 'build/\n' > "$T/.gitignore"; git -C "$T" add .gitignore; git -C "$T" commit -q -m "ignore build"; git -C "$T" push -q origin main 2>/dev/null
mkdir -p "$T/x/build"; printf 'notes\n' > "$T/x/build/notes.txt"
begin
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'x/\n' >> "$T/.gitignore"
git -C "$T" add .gitignore; git -C "$T" commit -q -m "ignore x (#5)"
git clone -q "$T.origin.git" "$S/other" 2>/dev/null; mkdir -p "$S/other/x"; printf 'a file\n' > "$S/other/x/build"
git -C "$S/other" add -f x/build; git -C "$S/other" commit -q -m "a file named build"; git -C "$S/other" push -q origin main 2>/dev/null
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2> "$S/err"; assert_exit "a file where an ignored folder stands: settle exits 3" 3 "$?"
assert_eq "a file where an ignored folder stands: the file in the folder holds what it held" "notes" "$(cat "$T/x/build/notes.txt" 2>/dev/null)"
assert_eq "a file where an ignored folder stands: no stash was made" "" "$(git -C "$T" stash list)"

# spec-example: idd-all-rest / a line of the local exclude file that settle did not add stays
new exclude-own-line 5 9
printf '/package-lock.json\n' >> "$T/.git/info/exclude"; printf '{"lock": "MINE"}\n' > "$T/package-lock.json"
begin
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'w\n' > "$T/w.txt"; git -C "$T" add w.txt; git -C "$T" commit -q -m "work (#5)"
git clone -q "$T.origin.git" "$S/other" 2>/dev/null; printf '!package-lock.json\n' > "$S/other/.gitignore"
git -C "$S/other" add .gitignore; git -C "$S/other" commit -q -m "never ignore the lockfile"; git -C "$S/other" push -q origin main 2>/dev/null
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2> "$S/err"; assert_exit "the person's own exclude line: settle exits 3" 3 "$?"
assert_eq "the person's own exclude line: it is still in the file, once" "1" "$(grep -cx '/package-lock.json' "$T/.git/info/exclude")"
assert_eq "the person's own exclude line: and settle left no comment line of its own" "0" "$(grep -c 'idd rest' "$T/.git/info/exclude")"

# spec-example: idd-all-rest / the report says which files in sight are not what the run left
new shown-before 5 9
with_tools
begin
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; git -C "$T" rm -q -r tools; git -C "$T" commit -q -m "remove tools (#5)"
mkdir -p "$T/.claude/.idd"; printf 'pid\n' > "$T/.claude/.idd/tree-lock"; printf 'changed\n' >> "$T/a.txt"
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2> "$S/err"; assert_exit "files from before in sight: settle exits 3" 3 "$?"
assert_output_grep "files from before in sight: the reason sends the person to the report before the checkout" "then (see the report first) git checkout --no-overwrite-ignore main" "$S/err"
reason_shape "files from before in sight" "$S/err"
ended
assert_grep "files from before in sight: the report names the file and says to leave it" "tools/.env" "$(grep -F 'do not commit them and do not remove them' "$S/report.out")"

# spec-example: idd-all-rest / fewer comments than the issue has
new comments-short 5:diag=Simple,comments=130
printf '[{"assoc": "MEMBER", "body": "one", "login": "me", "type": "User"}]' > "$G/comments-5.json"
rq list --repo "$REPO" --json > "$S/out" 2> "$S/err"; rc=$?
assert_true "fewer comments than the issue has: list does not exit 0" "[ $rc != 0 ]"
assert_eq "fewer comments than the issue has: and prints no list" "" "$(cat "$S/out")"
assert_output_grep "fewer comments than the issue has: the reason says the comments were not read completely" "comments of #5" "$S/err"

# spec-example: idd-all-rest / a file from before that the issue starts to track is put back
for how in committed changed; do
  new "tracks-$how" 5 9
  lockfile; tracks_lockfile
  WANT='{"lock": "MINE"}'
  [ "$how" = changed ] && { WANT='{"lock": "MINE, edited"}'; printf '%s\n' "$WANT" > "$T/package-lock.json"; }
  run record --issue 5 --reason x > /dev/null
  settle 5 > "$S/out" 2> "$S/err"; assert_exit "tracks ($how): settle exits 0" 0 "$?"
  assert_eq "tracks ($how): the file is in the working tree as it was" "$WANT" "$(cat "$T/package-lock.json" 2>/dev/null)"
  assert_eq "tracks ($how): the working tree is on main and git status prints nothing" "main|" "$(head_branch)|$(git -C "$T" status --porcelain)"
  assert_eq "tracks ($how): settle prints the path as returned" '["package-lock.json"]' "$(jget returned < "$S/out")"
  assert_true "tracks ($how): nothing is left set aside" '[ ! -e "$T/.claude/.idd/state/rest-held-5" ]'
  assert_eq "tracks ($how): settle made no commit" "track the lockfile (#5)" "$(git -C "$T" log -1 --format=%s idd/5-x)"
  run report > "$S/report.out" 2>&1
  assert_grep "tracks ($how): the report says settle put the file back" "put them back" "$(grep -F 'package-lock.json' "$S/report.out")"
  git -C "$T" branch -q -D idd/5-x
  assert_eq "tracks ($how): and it is still there after the kept branch is deleted" "$WANT" "$(cat "$T/package-lock.json" 2>/dev/null)"
done

# spec-example: idd-all-rest / a file set aside is put back when the checkout fails
new tracks-refused 5 9
ignore_local; printf 'mine\n' > "$T/local/settings.json"; printf 'notes\n' > "$T/local/notes.txt"
begin
git -C "$T" checkout -q --no-track -b idd/5-x origin/main
git -C "$T" add -f -- local/notes.txt; git -C "$T" commit -q -m "track the notes (#5)"
printf 'notes, edited\n' > "$T/local/notes.txt"
tracked_elsewhere settings.json
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2> "$S/err"; assert_exit "tracks, refused: settle exits 3" 3 "$?"
assert_eq "tracks, refused: both files hold what they held" "notes, edited|mine" "$(cat "$T/local/notes.txt" 2>/dev/null)|$(cat "$T/local/settings.json" 2>/dev/null)"
assert_eq "tracks, refused: the working tree is on the issue's branch with the change it had" "idd/5-x| M local/notes.txt" "$(head_branch)|$(git -C "$T" status --porcelain)"
assert_true "tracks, refused: nothing is left set aside" '[ ! -e "$T/.claude/.idd/state/rest-held-5" ]'
reason_shape "tracks, refused" "$S/err"
# spec-example: idd-all-rest / the report says what to copy before a checkout by hand
assert_output_grep "tracks, refused: the reason sends the person to the report before the checkout" "(see the report first) git checkout --no-overwrite-ignore main" "$S/err"
ended
assert_grep "tracks, refused: the report names the file the branch tracks and says to copy it before the checkout" "local/notes.txt" "$(grep -F 'Copy them elsewhere before that checkout' "$S/report.out")"

# spec-example: idd-all-rest / a file put back that the default branch does not ignore goes into the local exclude file
new tracks-unignored 5 9
lockfile
begin
git -C "$T" checkout -q --no-track -b idd/5-x origin/main
git -C "$T" add -f -- package-lock.json; git -C "$T" commit -q -m "track the lockfile (#5)"
git clone -q "$T.origin.git" "$S/other" 2>/dev/null; : > "$S/other/.gitignore"
git -C "$S/other" commit -q -a -m "drop the rule"; git -C "$S/other" push -q origin main 2>/dev/null
run record --issue 5 --reason x > /dev/null
settle 5 > "$S/out" 2> "$S/err"; assert_exit "tracks, not ignored: settle exits 0" 0 "$?"
assert_eq "tracks, not ignored: the file is in the working tree as it was" '{"lock": "MINE"}' "$(cat "$T/package-lock.json" 2>/dev/null)"
assert_eq "tracks, not ignored: the working tree is on main and git status prints nothing" "main|" "$(head_branch)|$(git -C "$T" status --porcelain)"
assert_eq "tracks, not ignored: the path is recorded as returned and as excluded" '["package-lock.json"]|["package-lock.json"]' "$(state_list returned)|$(state_list excluded)"
assert_grep "tracks, not ignored: and it is a line of the local exclude file" "/package-lock.json" "$(cat "$T/.git/info/exclude")"

# spec-example: idd-all-rest / a changed file from before that the merged issue tracks stays as it is
new tracks-merged-edited 5 9
lockfile; tracks_lockfile
git -C "$T" push -q -u origin idd/5-x 2>/dev/null; squash5
printf '{"lock": "MINE, edited"}\n' > "$T/package-lock.json"
run record --issue 5 > /dev/null
settle 5 > /dev/null 2> "$S/err"; assert_exit "tracks, merged, changed: settle exits 3" 3 "$?"
assert_eq "tracks, merged, changed: the file is where it was with the change" '{"lock": "MINE, edited"}' "$(cat "$T/package-lock.json" 2>/dev/null)"
assert_eq "tracks, merged, changed: the working tree is on main, where git shows the change" "main| M package-lock.json" "$(head_branch)|$(git -C "$T" status --porcelain)"
assert_true "tracks, merged, changed: nothing is left set aside" '[ ! -e "$T/.claude/.idd/state/rest-held-5" ]'
reason_shape "tracks, merged, changed" "$S/err"

# spec-example: idd-all-rest / a file from before that both branches track with different content stops the run
new tracks-clash 5 9
lockfile; tracks_lockfile
git clone -q "$T.origin.git" "$S/other" 2>/dev/null; printf 'THEIRS\n' > "$S/other/package-lock.json"
git -C "$S/other" add -f package-lock.json; git -C "$S/other" commit -q -m "a lockfile of the team"; git -C "$S/other" push -q origin main 2>/dev/null
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2> "$S/err"; assert_exit "tracks, both: settle exits 3" 3 "$?"
assert_eq "tracks, both: the file holds what it held" '{"lock": "MINE"}' "$(cat "$T/package-lock.json" 2>/dev/null)"
assert_eq "tracks, both: the working tree is on the issue's branch, unchanged" "idd/5-x|" "$(head_branch)|$(git -C "$T" status --porcelain)"
assert_output_grep "tracks, both: the reason says to move the file away and gives the checkout" "move those files away, then git checkout --no-overwrite-ignore main, then" "$S/err"
assert_output_grep "tracks, both: and names the file" "package-lock.json" "$S/err"
reason_shape "tracks, both" "$S/err"
ended
mv "$T/package-lock.json" "$S/lock.kept"; git -C "$T" checkout -q --no-overwrite-ignore main
assert_eq "tracks, both: with the file moved away, that checkout brings the version of the default branch" "THEIRS" "$(cat "$T/package-lock.json" 2>/dev/null)"
accepts "tracks, both: and a new run starts"

# spec-example: idd-all-rest / a hook that stages everything does not put a file from before into the commit
for hook_exit in 0 1; do
  new "hook-stages-all-$hook_exit" 5 9
  with_tools
  begin
  git -C "$T" checkout -q --no-track -b idd/5-x origin/main; git -C "$T" rm -q -r tools; git -C "$T" commit -q -m "remove tools (#5)"
  printf 'changed\n' >> "$T/a.txt"
  hook "$T" pre-commit "#!/bin/sh
git add -A
exit $hook_exit"
  run record --issue 5 --reason x > /dev/null
  settle 5 > "$S/out" 2> "$S/err"; assert_exit "hook stages all, exits $hook_exit: settle exits 0" 0 "$?"
  assert_eq "hook stages all, exits $hook_exit: the new commit holds a.txt and not tools/.env" "a.txt" "$(git -C "$T" show --name-only --format= idd/5-x)"
  assert_grep "hook stages all, exits $hook_exit: its message says a hook staged files from before the run" "staged files that were in the working tree before the run" "$(git -C "$T" log -1 --format=%b idd/5-x)"
  assert_eq "hook stages all, exits $hook_exit: the run state says the hooks were skipped" "skipped" "$(kept_of 5 | python3 -c 'import json,sys; print(json.load(sys.stdin)[0].get("hooks"))')"
  assert_eq "hook stages all, exits $hook_exit: tools/.env is in the working tree with its content" "TOKEN=ghp_secret" "$(cat "$T/tools/.env" 2>/dev/null)"
  assert_eq "hook stages all, exits $hook_exit: no commit of idd/5-x holds tools/.env" "" "$(git -C "$T" log --format=%h origin/main..idd/5-x -- tools/.env)"
  assert_eq "hook stages all, exits $hook_exit: the working tree is on main and git status prints nothing" "main|" "$(head_branch)|$(git -C "$T" status --porcelain)"
done

# spec-example: idd-all-rest / a file from before that the run removed is named in the report
new run-removed 5 9
with_tools
begin
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; rm -rf "$T/tools"
run record --issue 5 --reason x > /dev/null
settle 5 > "$S/out" 2> "$S/err"
assert_eq "run removed: settle prints tools/.env as missing" '["tools/.env"]' "$(jget missing < "$S/out")"
run report > "$S/report.out" 2>&1
assert_grep "run removed: the report names the file as gone when the run ended" "tools/.env" "$(grep -F 'gone when its run ended' "$S/report.out")"

# spec-example: idd-all-rest / a settle that was killed with a file set aside
for at in idd/5-x main; do
  new "held-killed-${at%%/*}" 5 9
  lockfile; tracks_lockfile
  run record --issue 5 --reason x > /dev/null
  set_aside
  [ "$at" = main ] && git -C "$T" checkout -q main
  settle 5 > "$S/out" 2> "$S/err"; assert_exit "set aside, on $at: the next settle exits 0" 0 "$?"
  assert_eq "set aside, on $at: the file is where it was, as it was" '{"lock": "MINE"}' "$(cat "$T/package-lock.json" 2>/dev/null)"
  assert_eq "set aside, on $at: it is recorded as returned" '["package-lock.json"]' "$(state_list returned)"
  assert_true "set aside, on $at: the folder is gone" '[ ! -e "$H" ]'
  assert_eq "set aside, on $at: the working tree is on main and git status prints nothing" "main|" "$(head_branch)|$(git -C "$T" status --porcelain)"
done
new held-orphan 5 9
lockfile; tracks_lockfile
run record --issue 5 --reason x > /dev/null
set_aside
run report > "$S/report.out" 2>&1
assert_output_grep "set aside, never settled: the report names the folder" "are still set aside in .claude/.idd/state/rest-held-5" "$S/report.out"
git -C "$T" checkout -q main
run start --path PR --review no > /dev/null 2> "$S/start.err"; assert_exit "set aside, never settled: a new run does not start" 3 "$?"
assert_output_grep "set aside, never settled: and says where the files are" "still set aside in .claude/.idd/state/rest-held-5" "$S/start.err"
assert_eq "set aside, never settled: the file is still in the folder" '{"lock": "MINE"}' "$(cat "$H/0" 2>/dev/null)"
mv "$H/0" "$T/package-lock.json"; rm -r "$H"
accepts "set aside, never settled: with the file moved back and the folder removed, a new run starts"
for same in yes no; do
  new "held-taken-$same" 5 9
  lockfile; tracks_lockfile
  run record --issue 5 --reason x > /dev/null
  set_aside; git -C "$T" checkout -q main
  if [ "$same" = yes ]; then printf '{"lock": "MINE"}\n' > "$T/package-lock.json"; else printf 'OTHER\n' > "$T/package-lock.json"; fi
  settle 5 > "$S/out" 2> "$S/err"; rc=$?
  if [ "$same" = yes ]; then
    assert_exit "place taken by the same content: settle exits 0" 0 "$rc"
    assert_true "place taken by the same content: the copy and its folder are gone" '[ ! -e "$H" ]'
  else
    assert_exit "place taken by other content: settle exits 3" 3 "$rc"
    assert_eq "place taken by other content: neither file is touched" 'OTHER|{"lock": "MINE"}' "$(cat "$T/package-lock.json")|$(cat "$H/0" 2>/dev/null)"
    assert_output_grep "place taken by other content: the reason names the folder" ".claude/.idd/state/rest-held-5" "$S/err"
    reason_shape "place taken by other content" "$S/err"
  fi
done
new held-tampered 5 9
lockfile; tracks_lockfile
run record --issue 5 --reason x > /dev/null
set_aside "../escaped.txt"; git -C "$T" checkout -q main
settle 5 > "$S/out" 2> "$S/err"; assert_exit "a list that settle did not write: settle exits 3" 3 "$?"
assert_true "a list that settle did not write: nothing is written outside the working tree" '[ ! -e "$S/escaped.txt" ] && [ -f "$H/0" ]'
new held-not-recorded 5 9
lockfile; tracks_lockfile
run record --issue 5 --reason x > /dev/null
set_aside "a-path-nobody-recorded.txt"; git -C "$T" checkout -q main
settle 5 > "$S/out" 2> "$S/err"; assert_exit "a list with a path that was not recorded at hand-out: settle exits 3" 3 "$?"
assert_true "a list with a path that was not recorded at hand-out: nothing is written" '[ ! -e "$T/a-path-nobody-recorded.txt" ] && [ -f "$H/0" ]'
new held-behind-a-link 5 9
ignore_local; printf 'mine\n' > "$T/local/settings.json"
begin
git -C "$T" checkout -q --no-track -b idd/5-x origin/main
git -C "$T" add -f -- local/settings.json; git -C "$T" commit -q -m "track the settings (#5)"
run record --issue 5 --reason x > /dev/null
H="$T/.claude/.idd/state/rest-held-5"; mkdir -p "$H" "$S/outside"; printf '[{"path": "local/settings.json", "name": "0"}]' > "$H/held.json"
mv "$T/local/settings.json" "$H/0"; git -C "$T" checkout -q main; rm -rf "$T/local"; ln -s "$S/outside" "$T/local"
settle 5 > "$S/out" 2> "$S/err"; assert_exit "the place is below a folder that is a link: settle exits 3" 3 "$?"
assert_true "the place is below a folder that is a link: nothing is written where the link points" '[ ! -e "$S/outside/settings.json" ] && [ -f "$H/0" ]'
assert_output_grep "the place is below a folder that is a link: the reason names the folder" ".claude/.idd/state/rest-held-5" "$S/err"

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

# spec-example: idd-all-rest / the steps a stop names lead to a run that starts
for stop in lock other-branch default merge merge-default unmerged unclean state fetch fast-forward; do
  new "follow-$stop" 5 9
  if [ "$stop" = fast-forward ]; then   # origin/main gets a commit that tracks build.log
    git clone -q "$T.origin.git" "$S/other" 2>/dev/null; printf 'from origin\n' > "$S/other/build.log"
    git -C "$S/other" add build.log; git -C "$S/other" commit -q -m "track build.log"; git -C "$S/other" push -q origin main 2>/dev/null
    printf 'build.log\n' >> "$T/.git/info/exclude"; printf 'local, ignored\n' > "$T/build.log"   # there before the run, and ignored
  fi
  begin
  case "$stop" in
    lock)   git -C "$T" checkout -q --no-track -b idd/5-x origin/main; mkdir -p "$T/.claude/.idd"
            printf 'pid\n' > "$T/.claude/.idd/tree-lock"; printf 'changed\n' >> "$T/a.txt" ;;
    other-branch) git -C "$T" checkout -q -b wip; printf 'changed\n' >> "$T/a.txt" ;;
    default) printf 'b\n' > "$T/b.txt" ;;
    merge)  git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'one\n' > "$T/a.txt"; git -C "$T" commit -q -am "one (#5)"
            git -C "$T" checkout -q -b side main; printf 'two\n' > "$T/a.txt"; git -C "$T" commit -q -am two
            git -C "$T" checkout -q idd/5-x; git -C "$T" merge -q side > /dev/null 2>&1 ;;
    merge-default) git -C "$T" checkout -q -b side main; printf 'two\n' > "$T/a.txt"; git -C "$T" commit -q -am two
            git -C "$T" checkout -q main; printf 'one\n' > "$T/a.txt"; git -C "$T" commit -q -am "a commit only this clone has"
            git -C "$T" merge -q side > /dev/null 2>&1 ;;
    unmerged) git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'stashed\n' > "$T/a.txt"; git -C "$T" stash -q
            printf 'one\n' > "$T/a.txt"; git -C "$T" commit -q -am "one (#5)"; git -C "$T" stash pop -q > /dev/null 2>&1 ;;
    unclean) git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'w\n' > "$T/w.txt"; git -C "$T" add w.txt
            git -C "$T" commit -q -m "work (#5)"; hook "$T" post-checkout '#!/bin/sh
printf "stray\n" > stray.txt' ;;
    state)  git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'changed\n' >> "$T/a.txt" ;;
    fetch)  git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'changed\n' >> "$T/a.txt"
            git -C "$T" remote set-url origin "$S/nowhere.git" ;;
    fast-forward) : ;;   # the issue ended on main, which is behind origin/main
  esac
  run record --issue 5 --reason x > /dev/null
  [ "$stop" = state ] && python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); s["default"]="not a branch name"; json.dump(s, open(p,"w"))' "$(state_file)"
  settle 5 > /dev/null 2> "$S/err"; assert_exit "follow $stop: settle exits 3" 3 "$?"
  reason_shape "follow $stop" "$S/err"
  ended
  case "$stop" in   # the steps the reason names, taken as they are written
    lock)   assert_output_grep "follow lock: the reason names every step" "have git ignore them, commit or remove what else is left, then git checkout --no-overwrite-ignore main, then" "$S/err"
            printf '.claude/.idd/tree-lock\n' >> "$T/.git/info/exclude"; git -C "$T" add -A; git -C "$T" commit -q -m "what was left"; git -C "$T" checkout -q --no-overwrite-ignore main ;;
    other-branch) assert_output_grep "follow other-branch: the reason names every step" "commit or remove what is left there, then git checkout --no-overwrite-ignore main, then" "$S/err"
            git -C "$T" add -A; git -C "$T" commit -q -m "what was left"; git -C "$T" checkout -q --no-overwrite-ignore main ;;
    merge-default) assert_output_grep "follow merge-default: on the default branch nothing is to be committed there" "finish or abort it, commit what is left elsewhere or move it away, then" "$S/err"
            git -C "$T" merge --abort ;;
    unmerged) assert_output_grep "follow unmerged: the reason says the paths are unmerged, not that a merge is unfinished" "git reports unmerged paths — resolve them, commit or remove what is left, then git checkout --no-overwrite-ignore main, then" "$S/err"
            git -C "$T" add a.txt; git -C "$T" commit -q -m "resolved"; git -C "$T" stash drop -q; git -C "$T" checkout -q --no-overwrite-ignore main ;;
    unclean) assert_output_grep "follow unclean: the reason names the step" "the working tree is not clean — commit what is there elsewhere or move it away, then" "$S/err"
            mv "$T/stray.txt" "$S/stray.txt.kept" ;;
    state)  assert_output_grep "follow state: the reason names every step" "commit or remove what is left, then git checkout --no-overwrite-ignore <the default branch> (the default branch of the repository), then" "$S/err"
            git -C "$T" commit -q -am "what was left"; git -C "$T" checkout -q --no-overwrite-ignore main ;;
    default) assert_output_grep "follow default: the reason names every step" "commit them elsewhere or move them away, then" "$S/err"
            assert_eq "follow default: and names the default branch once" "1" "$(before_detail "$S/err" | grep -o 'main' | wc -l | tr -d ' ')"
            mv "$T/b.txt" "$S/b.txt.kept" ;;
    merge)  assert_output_grep "follow merge: the reason names every step" "finish or abort it, commit or remove what is left, then git checkout --no-overwrite-ignore main, then" "$S/err"
            git -C "$T" merge --abort; git -C "$T" checkout -q --no-overwrite-ignore main ;;
    fetch)  assert_output_grep "follow fetch: the reason names the step" "check that origin can be reached, then" "$S/err"
            assert_eq "follow fetch: and names the default branch once" "1" "$(before_detail "$S/err" | grep -o 'main' | wc -l | tr -d ' ')"
            git -C "$T" remote set-url origin "$T.origin.git" ;;
    fast-forward) assert_eq "follow fast-forward: the ignored file in the way was not overwritten" "local, ignored" "$(cat "$T/build.log")"
            assert_output_grep "follow fast-forward: the reason gives the fast-forward that does not overwrite" "run git merge --ff-only --no-overwrite-ignore origin/main and move away each file it names until it succeeds, then" "$S/err"
            git -C "$T" merge -q --ff-only --no-overwrite-ignore origin/main 2> "$S/git.err"; assert_exit "follow fast-forward: that command fails while the file is in the way" 1 "$?"
            assert_output_grep "follow fast-forward: and names the file" "build.log" "$S/git.err"
            mv "$T/build.log" "$S/build.log.kept"; git -C "$T" merge -q --ff-only --no-overwrite-ignore origin/main ;;
  esac
  accepts "follow $stop: after those steps a new run starts"
done

# spec-example: idd-all-rest / a commit that fails without a commit hook is not made again
SHIM="$WORK/shim"; mkdir -p "$SHIM"
cat > "$SHIM/git" <<'GITSHIM'
#!/bin/sh
# the first `git … commit` fails, for a reason that is no hook's; everything else is the real git
case " $* " in *" commit "*) if [ ! -f "$SHIM_MARK" ]; then : > "$SHIM_MARK"; echo "fatal: the commit fails once" >&2; exit 1; fi ;; esac
exec "$REAL_GIT" "$@"
GITSHIM
chmod +x "$SHIM/git"
REAL_GIT=$(command -v git)
for hooks in none accepting; do
  new "commit-fails-$hooks" 5 9
  begin
  git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'changed\n' >> "$T/a.txt"
  run record --issue 5 --reason x > /dev/null
  [ "$hooks" = accepting ] && hook "$T" pre-commit '#!/bin/sh
exit 0'
  PATH="$SHIM:$PATH" SHIM_MARK="$S/shim-mark" REAL_GIT="$REAL_GIT" python3 "$RQ" settle --cwd "$T" --repo "$REPO" --issue 5 > /dev/null 2> "$S/err"; rc=$?
  if [ "$hooks" = none ]; then
    assert_exit "commit fails, no commit hook: settle exits 3" 3 "$rc"
    assert_output_grep "commit fails, no commit hook: the reason says the commit could not be made" "could not commit what the run left" "$S/err"
    assert_eq "commit fails, no commit hook: no commit was made on the branch" "$(git -C "$T" rev-parse origin/main)" "$(git -C "$T" rev-parse idd/5-x)"
    reason_shape "commit fails, no commit hook" "$S/err"
  else
    assert_exit "commit fails, a commit hook is there: settle exits 0" 0 "$rc"
    assert_grep "commit fails, a commit hook is there: the commit says the hooks were skipped" "hooks were skipped" "$(git -C "$T" log -1 --format=%b idd/5-x)"
  fi
done

# spec-example: idd-all-rest / a second keep commit keeps the first
new second-keep 5 9
begin
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'changed\n' >> "$T/a.txt"
run record --issue 5 --reason x > /dev/null
hook "$T" post-commit '#!/bin/sh
: > "$(git rev-parse --git-dir)/index.lock"'
settle 5 > /dev/null 2>&1; assert_exit "second keep: the first settle stops after its commit (exit 3)" 3 "$?"
rm -f "$T/.git/hooks/post-commit" "$T/.git/index.lock"
FIRST=$(git -C "$T" rev-parse idd/5-x); printf 'b\n' > "$T/b.txt"
settle 5 > /dev/null 2>&1; assert_exit "second keep: the second settle exits 0" 0 "$?"
SECOND=$(git -C "$T" rev-parse idd/5-x)
assert_eq "second keep: the run state names the newest commit, the paths of both and the earlier commit" \
  "$SECOND|[\"a.txt\",\"b.txt\"]|[\"$FIRST\"]" \
  "$(kept_of 5 | python3 -c 'import json,sys; k=json.load(sys.stdin)[0]; d=lambda v: json.dumps(v, separators=(",",":")); print(k["commit"], d(k["paths"]), d(k.get("earlier")), sep="|")')"
run report > "$S/report.out" 2>&1
LINE=$(grep -F 'branch idd/5-x is kept' "$S/report.out")
assert_grep "second keep: the report names the newest commit" "$(printf '%s' "$SECOND" | cut -c1-7)" "$LINE"
assert_grep "second keep: and the earlier one" "$(printf '%s' "$FIRST" | cut -c1-7)" "$LINE"

new second-keep-missed 5 9
begin
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'changed\n' >> "$T/a.txt"
run record --issue 5 --reason x > /dev/null
hook "$T" post-commit '#!/bin/sh
: > "$(git rev-parse --git-dir)/index.lock"'
settle 5 > /dev/null 2>&1; rm -f "$T/.git/hooks/post-commit" "$T/.git/index.lock"
FIRST=$(git -C "$T" rev-parse idd/5-x); printf 'b\n' > "$T/b.txt"
python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); s["attempts"][-1].pop("kept"); json.dump(s, open(p,"w"))' "$(state_file)"
settle 5 > /dev/null 2>&1; assert_exit "second keep, first record lost: settle exits 0" 0 "$?"
assert_eq "second keep, first record lost: the earlier commit and the paths of both are still named" "[\"a.txt\",\"b.txt\"]|[\"$FIRST\"]" \
  "$(kept_of 5 | python3 -c 'import json,sys; k=json.load(sys.stdin)[0]; d=lambda v: json.dumps(v, separators=(",",":")); print(d(k["paths"]), d(k.get("earlier")), sep="|")')"

# spec-example: idd-all-rest / a stash whose branch was deleted
new stash-gone 5 9
git clone -q "$T.origin.git" "$S/other" 2>/dev/null; printf 'coverage/\n' > "$S/other/.gitignore"
git -C "$S/other" add .gitignore; git -C "$S/other" commit -q -m "ignore coverage"; git -C "$S/other" push -q origin main 2>/dev/null
printf 'l\n' > "$T/local.txt"; git -C "$T" add local.txt; git -C "$T" commit -q -m "a commit only this clone has"
begin
git -C "$T" fetch -q origin main; git -C "$T" checkout -q --no-track -b idd/5-x origin/main   # as Step 0.5 creates it
mkdir -p "$T/coverage"; printf 'the report\n' > "$T/coverage/report.txt"
run record --issue 5 --reason x > /dev/null
settle 5 > "$S/out" 2> "$S/err"; assert_exit "stash gone: settle exits 0" 0 "$?"
assert_eq "stash gone: the branch held no commit of its own and is deleted" "" "$(git -C "$T" branch --list 'idd/5*')"
STASH=$(git -C "$T" rev-parse -q --verify refs/stash)
assert_eq "stash gone: settle prints that the branch of the stash was not kept" "$STASH|false" "$(stash0 commit < "$S/out")|$(stash0 kept < "$S/out")"
run report > "$S/report.out" 2>&1
LINE=$(grep -F "git stash apply $STASH" "$S/report.out")
assert_grep "stash gone: the report says that branch is deleted" "is deleted" "$LINE"
refute_grep "stash gone: and does not say to apply the stash on that branch" "on that branch" "$LINE"
git -C "$T" stash apply -q "$STASH" 2>/dev/null
assert_eq "stash gone: applied in the working tree, the file is there again" "the report" "$(cat "$T/coverage/report.txt" 2>/dev/null)"
assert_grep "stash gone: the report says to move the files out again before the next run" "move them out of the working tree again before the next run" "$LINE"
mv "$T/coverage" "$S/coverage.kept"
accepts "stash gone: with the files moved out, a new run starts"

# spec-example: idd-all-rest / a stash the run state missed is found again
new stash-missed 5 9
begin
git -C "$T" checkout -q --no-track -b idd/5-x origin/main
printf 'coverage/\n' > "$T/.gitignore"; git -C "$T" add .gitignore; git -C "$T" commit -q -m "ignore coverage (#5)"
mkdir -p "$T/coverage/html"; printf 'the report\n' > "$T/coverage/report.txt"; printf '<p>\n' > "$T/coverage/html/index.html"
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2>&1; STASH=$(git -C "$T" rev-parse -q --verify refs/stash)
python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); a=s["attempts"][-1]; a.pop("stashes"); a["settled"]=False; json.dump(s, open(p,"w"))' "$(state_file)"
settle 5 > "$S/out" 2>&1; assert_exit "stash missed: settle exits 0" 0 "$?"
assert_eq "stash missed: and finds the stash and the files it holds again" "$STASH|[\"coverage/html/index.html\",\"coverage/report.txt\"]|true" "$(stash0 commit < "$S/out")|$(stash0 paths < "$S/out")|$(stash0 kept < "$S/out")"
assert_eq "stash missed: a settle after that prints what was recorded" "$STASH" "$(settle 5 2>/dev/null | stash0 commit)"

# spec-example: idd-all-rest / the working tree below the top of the repository
new below-top 5 9
mkdir -p "$T/sub"; printf 's\n' > "$T/sub/s.txt"; git -C "$T" add sub/s.txt; git -C "$T" commit -q -m sub; git -C "$T" push -q origin main
printf 'sub/.claude/.idd/state/\n' >> "$T/.git/info/exclude"
rq start --cwd "$T/sub" --repo "$REPO" --path PR --review no > /dev/null 2>&1; rq next --cwd "$T/sub" --repo "$REPO" > /dev/null
git -C "$T" checkout -q --no-track -b idd/5-x origin/main
download 5 "$T/sub"
assert_eq "below top: the manifest is the only leftover" "?? sub/.claude/" "$(git -C "$T" status --porcelain)"
rq record --cwd "$T/sub" --repo "$REPO" --issue 5 --reason x > /dev/null
rq settle --cwd "$T/sub" --repo "$REPO" --issue 5 > /dev/null 2> "$S/err"; rc=$?
assert_exit "below top: settle exits 0" 0 "$rc"
assert_file_absent "below top: the manifest no longer exists" "$T/sub/.claude/.idd/attachments/issue-5/_manifest.json"
assert_true "below top: and the branch no longer exists" '! git -C "$T" show-ref --verify --quiet refs/heads/idd/5-x'
new below-top-state 5 9
mkdir -p "$T/sub"; printf 's\n' > "$T/sub/s.txt"; git -C "$T" add sub/s.txt; git -C "$T" commit -q -m sub; git -C "$T" push -q origin main
printf 'sub/.claude/.idd/state/idd-all-rest.json\nsub/.claude/.idd/state/unattended.json\n' >> "$T/.git/info/exclude"
rq start --cwd "$T/sub" --repo "$REPO" --path PR --review no > /dev/null 2>&1; rq next --cwd "$T/sub" --repo "$REPO" > /dev/null
git -C "$T" checkout -q --no-track -b idd/5-x origin/main
printf 'x\n' > "$T/sub/.claude/.idd/state/x.json"; rq record --cwd "$T/sub" --repo "$REPO" --issue 5 --reason x > /dev/null
rq settle --cwd "$T/sub" --repo "$REPO" --issue 5 > /dev/null 2>&1
assert_exit "below top: a state file below --cwd is never committed (exit 3)" 3 "$?"
# spec-example: idd-all-rest / a worktree folder at the top is never committed from below
new below-top-worktree 5 9
mkdir -p "$T/sub"; printf 's\n' > "$T/sub/s.txt"; git -C "$T" add sub/s.txt; git -C "$T" commit -q -m sub; git -C "$T" push -q origin main
printf 'sub/.claude/.idd/state/\n' >> "$T/.git/info/exclude"
rq start --cwd "$T/sub" --repo "$REPO" --path PR --review no > /dev/null 2>&1; rq next --cwd "$T/sub" --repo "$REPO" > /dev/null
git -C "$T" checkout -q --no-track -b idd/5-x origin/main
mkdir -p "$T/.claude/worktrees/w"; printf 'x\n' > "$T/.claude/worktrees/w/a"
rq record --cwd "$T/sub" --repo "$REPO" --issue 5 --reason x > /dev/null
rq settle --cwd "$T/sub" --repo "$REPO" --issue 5 > /dev/null 2> "$S/err"
assert_exit "below top: a worktree folder at the top is never committed (exit 3)" 3 "$?"
assert_output_grep "below top: and the reason names it" ".claude/worktrees/w/a" "$S/err"

# Scenario: a branch with an upstream is kept
new upstream 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; git -C "$T" push -q -u origin idd/5-x
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2>&1; assert_exit "upstream: settle exits 0" 0 "$?"
assert_eq "upstream: the branch without a commit of its own is kept, with an upstream" '[{"branch":"idd/5-x","commit":"","upstream":true}]' "$(kept_of 5)"
# Scenario: two branches of one issue
new two-branches 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
git -C "$T" branch idd/5-y; git -C "$T" checkout -q --no-track -b idd/5-x origin/main
printf 'w\n' > "$T/w.txt"; git -C "$T" add w.txt; git -C "$T" commit -q -m "work of #5"
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2>&1; assert_exit "two branches: settle exits 0" 0 "$?"
assert_true "two branches: the empty one is deleted" '! git -C "$T" show-ref --verify --quiet refs/heads/idd/5-y'
assert_eq "two branches: the one with work is kept" '[{"branch":"idd/5-x","commit":"","upstream":false}]' "$(kept_of 5)"

# spec-example: idd-all-rest / endings of the single-issue pipeline
python3 "$HERE/endings.py" "$RQ" "$PLUGIN/scripts/process-attachments.sh" > "$WORK/endings.out" 2>&1; rc=$?
assert_exit "endings: every row of the table holds" 0 "$rc"
[ "$rc" = 0 ] || sed -n "1,40p" "$WORK/endings.out"
assert_output_grep "endings: and it ran all of them" "29 rows, 0 failure(s)" "$WORK/endings.out"

# spec-example: idd-all-rest / an empty issue branch is deleted
new empty-branch 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; git -C "$T" checkout -q -b idd/5-x; run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2>&1; rc=$?
assert_exit "empty branch: settle exits 0" 0 "$rc"
assert_true "empty branch: idd/5-x no longer exists" '! git -C "$T" show-ref --verify --quiet refs/heads/idd/5-x'
assert_eq "empty branch: the working tree is on main" "main" "$(head_branch)"
run report > "$S/report.out" 2>&1
refute_grep "empty branch: the report names no branch under #5" "idd/" "$(stopped_block "$S/report.out")"
refute_output_grep "empty branch: and says nothing about kept branches" "later rest run" "$S/report.out"

# Scenario: an issue branch with work and nothing left over
new work-branch 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; git -C "$T" checkout -q -b idd/5-x
printf 'w\n' > "$T/w.txt"; git -C "$T" add w.txt; git -C "$T" commit -q -m "work of #5"; WORK5=$(git -C "$T" rev-parse HEAD)
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2>&1; assert_exit "work branch: settle exits 0" 0 "$?"
assert_eq "work branch: no commit was added" "$WORK5" "$(git -C "$T" rev-parse idd/5-x)"
assert_eq "work branch: the working tree is on main" "main" "$(head_branch)"
run report > "$S/report.out" 2>&1
assert_grep "work branch: the report names the kept branch under #5" "idd/5-x" "$(stopped_block "$S/report.out")"
refute_grep "work branch: with no settle commit" "commit" "$(stopped_block "$S/report.out" | grep 'idd/5-x')"
new closed-branch 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; git -C "$T" checkout -q -b idd/5-x
printf 'w\n' > "$T/w.txt"; git -C "$T" add w.txt; git -C "$T" commit -q -m "work of #5"
echo CLOSED > "$G/state-5"; run record --issue 5 > /dev/null; settle 5 > /dev/null 2>&1
run report > "$S/report.out" 2>&1
refute_output_grep "closed: a merged branch without a settle commit is not named" "idd/5-x" "$S/report.out"

# Scenario: the working tree is on a branch of another issue
new other-branch 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; git -C "$T" checkout -q -b idd/7-y; run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2> "$S/err"; assert_exit "other branch: settle exits 3" 3 "$?"
assert_eq "other branch: and leaves the working tree there" "idd/7-y" "$(head_branch)"
assert_output_grep "other branch: its reason line names the branch" "idd/7-y" "$S/err"
new detached 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; git -C "$T" checkout -q --detach; run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2>&1; assert_exit "detached: settle exits 3" 3 "$?"
new merging 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
git -C "$T" checkout -q -b side; printf 'side\n' > "$T/a.txt"; git -C "$T" commit -q -am side
git -C "$T" checkout -q main; git -C "$T" checkout -q -b idd/5-x; printf 'mine\n' > "$T/a.txt"; git -C "$T" commit -q -am mine
git -C "$T" merge -q side > /dev/null 2>&1
MINE=$(git -C "$T" rev-parse HEAD)
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2> "$S/err"; assert_exit "merging: an unfinished merge exits 3" 3 "$?"
assert_true "merging: and is left unfinished" 'git -C "$T" rev-parse -q --verify MERGE_HEAD >/dev/null'
assert_eq "merging: no commit was made" "$MINE" "$(git -C "$T" rev-parse HEAD)"

new picking 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
git -C "$T" checkout -q -b side; printf 'side\n' > "$T/a.txt"; git -C "$T" commit -q -am side; SIDE=$(git -C "$T" rev-parse HEAD)
git -C "$T" checkout -q main; git -C "$T" checkout -q -b idd/5-x; printf 'mine\n' > "$T/a.txt"; git -C "$T" commit -q -am mine
git -C "$T" cherry-pick "$SIDE" > /dev/null 2>&1
run record --issue 5 --reason x > /dev/null
settle 5 > /dev/null 2> "$S/err"; assert_exit "picking: an unfinished cherry-pick exits 3" 3 "$?"
assert_output_grep "picking: and the reason names it" "cherry-pick" "$S/err"
new closed-kept 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; git -C "$T" checkout -q -b idd/5-x
mkdir -p "$T/.claude/.idd"; printf '{}\n' > "$T/.claude/.idd/routing-stats.jsonl"
echo CLOSED > "$G/state-5"; run record --issue 5 > /dev/null; settle 5 > /dev/null 2>&1
KEPT=$(git -C "$T" rev-parse --short=7 idd/5-x)
run report > "$S/report.out" 2>&1
assert_output_grep "closed: a branch to which settle added a commit is named, with the path" "#5 — what the run left is kept on idd/5-x (commit $KEPT): .claude/.idd/routing-stats.jsonl" "$S/report.out"

# spec-example: idd-all-rest / an issue with a local branch is recorded, not handed out
new local-branch 5 9
git -C "$T" branch idd/5-old
run start --path PR --review no > "$S/start.out" 2>&1
assert_output_grep "start: says a candidate with a pull request or branch is recorded as existing work" "recorded as existing work when its turn comes" "$S/start.out"
refute_output_grep "start: says nothing about attachment files" "attachment files" "$S/start.out"
# spec-example: idd-all-rest / candidates with a local branch are listed apart
assert_output_grep "start: the run order names #9 and not #5" "to run (1): #9" "$S/start.out"
assert_output_grep "start: and #5 is on a line of its own, as a candidate with a local branch" "candidates with a local branch, recorded as existing work when their turn comes (1): #5" "$S/start.out"
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

echo "── the run state ──"
new state-no-reason 5
mkdir -p "$T/.claude/.idd/state"
python3 - "$(state_file)" <<'PY'
import json, sys, time
s = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
json.dump({"version": 4, "repo": "o/r", "path": "PR", "default": "main", "review": False, "started_at": s, "updated_at": s, "stop": None,
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
write_state 1 '[{"issue": 5, "outcome": "stopped", "reason": "x", "settled": true, "kept": [{"branch": 5}]}]'
run start --path PR --review no > "$S/start.out" 2>&1
assert_output_grep "state: a kept branch that is not a name is not used" "cannot be used" "$S/start.out"

for field in path default review; do
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
new unusable-v3 5
write_state 1 '[]'
python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); s["version"]=3; s["review"]=True; json.dump(s, open(p,"w"))' "$(state_file)"
BEFORE=$(cat "$(state_file)")
run start --path PR --review no > /dev/null 2> "$S/err"; assert_exit "unusable state: a state of the previous version, an hour old, stops start (exit 3)" 3 "$?"
assert_eq "unusable state: and the file is unchanged" "$BEFORE" "$(cat "$(state_file)")"
new unusable-old 5
mkdir -p "$T/.claude/.idd/state"; printf '{"review": tr' > "$(state_file)"; age "$(state_file)" 25
run start --path PR --review no > "$S/start.out" 2>&1; assert_exit "unusable state: the same text written 25 hours ago is replaced by a new run (exit 0)" 0 "$?"
assert_output_grep "unusable state: and start says that it replaced a file it could not use" "cannot be used" "$S/start.out"
# spec-example: idd-all-rest / a run that was never reported is not forgotten
new forgotten 9
KEEP=$(python3 -c 'print("a" * 40)'); STSH=$(python3 -c 'print("b" * 40)')
write_state 25 '[{"issue": 5, "outcome": "stopped", "reason": "x", "settled": true, "kept": [{"branch": "idd/5-x", "commit": "'"$KEEP"'", "paths": ["a.txt"], "more": 0, "shared": [], "hooks": "skipped", "upstream": false}], "stashes": [{"commit": "'"$STSH"'", "branch": "idd/5-x", "paths": ["coverage/"], "more": 0, "kind": "only", "kept": true}]}]'
run start --path PR --review no > "$S/start.out" 2>&1; assert_exit "forgotten: start exits 0 and begins a new run" 0 "$?"
OLD=$(grep -F 'idd/5-x' "$S/start.out")
assert_grep "forgotten: before the list it names the kept branch with its commit" "aaaaaaa" "$OLD"
assert_grep "forgotten: says that the commit was made without the hooks" "without the repository's commit hooks" "$OLD"
assert_output_grep "forgotten: and names the commit of the stash" "$STSH" "$S/start.out"
# spec-example: idd-all-rest / a new run does not start in a working tree an earlier run left
new fresh-clean 5
run start --path PR --review no > /dev/null 2>&1; assert_exit "new run: a clean main starts" 0 "$?"
new fresh-other-branch 5
git -C "$T" checkout -q -b idd/7-y
run start --path PR --review no > /dev/null 2> "$S/err"; assert_exit "new run: a working tree on another branch exits 3" 3 "$?"
assert_output_grep "new run: the reason names the branch" "idd/7-y" "$S/err"
assert_output_grep "new run: and that an earlier run may have left it" "earlier run" "$S/err"
assert_file_absent "new run: no run state file exists" "$(state_file)"
assert_output_grep "new run: the reason names every step" "commit or remove what is left there, run git checkout --no-overwrite-ignore main, then" "$S/err"
git -C "$T" checkout -q --no-overwrite-ignore main
run start --path PR --review no > /dev/null 2>&1; assert_exit "new run: after those steps it starts" 0 "$?"
new fresh-dirty 5
printf 'b\n' > "$T/b.txt"
run start --path PR --review no > /dev/null 2> "$S/err"; assert_exit "new run: an untracked file on main exits 3" 3 "$?"
assert_output_grep "new run: the reason names the file" "b.txt" "$S/err"
assert_output_grep "new run: and says to commit them elsewhere or move them away" "commit them elsewhere or move them away, then" "$S/err"
assert_file_absent "new run: no run state file exists" "$(state_file)"
new resumed-dirty 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; git -C "$T" checkout -q -b idd/5-x; printf 'w\n' > "$T/w.txt"
run start --path PR --review no > /dev/null 2>&1; assert_exit "resumed run: its issue in flight may be on its own branch" 0 "$?"

echo "── handing out ──"
# spec-example: idd-all-rest / a new issue is handed out only on a clean default branch
for where in clean wip dirty; do
  new "handout-$where" 5
  printf 'local/\n' > "$T/.gitignore"; git -C "$T" add .gitignore; git -C "$T" commit -q -m "ignore local"; git -C "$T" push -q origin main 2>/dev/null
  mkdir -p "$T/local"; printf 'mine\n' > "$T/local/s.json"
  run start --path PR --review no > /dev/null 2>&1
  case "$where" in wip) git -C "$T" checkout -q -b wip ;; dirty) printf 'b\n' > "$T/b.txt" ;; esac
  OUT=$(run next 2> "$S/err"); rc=$?
  ATTEMPTS=$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["attempts"]))' "$(state_file)")
  case "$where" in
    clean) assert_eq "hand-out, clean main: next hands out #5" "0|5" "$rc|$(printf '%s' "$OUT" | jget next)"
           assert_grep "hand-out, clean main: the run state holds local/ among the paths recorded for #5" '"local/"' \
             "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["attempts"][0].get("before")))' "$(state_file)")"
           refute_grep "hand-out, clean main: and not .claude/, which only holds the ignored state folder" '".claude/"' \
             "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["attempts"][0].get("before")))' "$(state_file)")" ;;
    wip)   assert_eq "hand-out, on wip: next exits 3 and the run state holds no attempt" "3|0" "$rc|$ATTEMPTS"
           assert_output_grep "hand-out, on wip: the reason names the branch" "wip" "$S/err" ;;
    dirty) assert_eq "hand-out, an untracked file on main: next exits 3 and the run state holds no attempt" "3|0" "$rc|$ATTEMPTS"
           assert_output_grep "hand-out, an untracked file on main: the reason names the file" "b.txt" "$S/err" ;;
  esac
done
# Scenario: an issue in flight is handed out again wherever the working tree is
new handout-flight 5
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
FIRST=$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["attempts"][0].get("before")))' "$(state_file)")
git -C "$T" checkout -q -b idd/5-x; printf 'changed\n' >> "$T/a.txt"; mkdir -p "$T/local2"; printf 'x\n' > "$T/local2/x"
assert_eq "hand-out: an issue in flight is handed out again on its own branch with a changed file" "5|true" "$(run next | jget next)|$(run next | jget in_flight)"
assert_eq "hand-out: and what was recorded for it at its first hand-out stays" "$FIRST" \
  "$(python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1]))["attempts"][0].get("before")))' "$(state_file)")"
new no-run 5
run next > /dev/null 2> "$S/err"
assert_output_grep "no run: the reason names the --cwd as a cause, not only a missing start" "--cwd" "$S/err"

echo "── the review flag ──"
# spec-example: idd-all-rest / the review flag across a resumed run
for row in "yes yes yes no" "yes no yes yes" "no yes yes yes" "no no no no"; do
  set -- $row
  new "review-$1-$2" 5
  run start --path PR --review "$1" > /dev/null 2>&1
  run start --path PR --review "$2" > "$S/start.out" 2>&1; assert_exit "review $1 then $2: start exits 0" 0 "$?"
  assert_eq "review $1 then $2: next prints review $3" "$3" "$(run next | jget review)"
  assert_eq "review $1 then $2: start says the flag differs: $4" "$4" "$(grep -q 'review flag differs' "$S/start.out" && echo yes || echo no)"
done
# Scenario: the flag is printed for an issue in flight
new review-inflight 5
run start --path PR --review yes > /dev/null 2>&1; run next > /dev/null
assert_eq "review: an issue in flight carries the flag" "true|yes" "$(run next | jget in_flight)|$(run next | jget review)"
# spec-example: idd-all-rest / the close stage cannot be told that review is off
CS="$PLUGIN/scripts/close-stage.py"
init() { python3 "$CS" init --cwd "$T" --repo "$REPO" --issue 5 --path PR --requested-path PR --interaction unattended --branch idd/5-x --default main --review "$1" --in-chain no; }
runstate() { [ -f "$T/.claude/.idd/state/idd-all-run-5.json" ] && echo yes || echo no; }
for row in "yes 5 no 64 no" "yes 5 yes 0 yes" "no 5 no 0 yes" "yes 9 no 0 yes" "none - no 0 yes"; do
  set -- $row
  new "init-$1-$2-$3" 5 9
  if [ "$1" != none ]; then
    run start --path PR --review "$1" > /dev/null 2>&1
    [ "$2" = 9 ] && { issues 9; }   # only #9 is a candidate, so it is the one in flight
    run next > /dev/null
  fi
  init "$3" > /dev/null 2> "$S/err"; rc=$?
  assert_exit "init: rest review $1, #$2 in flight, --review $3 exits $4" "$4" "$rc"
  assert_eq "init: and a run state for #5 exists: $5" "$5" "$(runstate)"
done
new init-ways-out 5 9
run start --path PR --review yes > /dev/null 2>&1; run next > /dev/null
init no > /dev/null 2> "$S/err"
assert_output_grep "init: its message names the other way out, ending the rest run" "end the rest run" "$S/err"
new init-stale 5
write_state 25 '[{"issue": 5, "outcome": null}]'
python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); s["review"]=True; json.dump(s, open(p,"w"))' "$(state_file)"
init no > /dev/null 2>&1; assert_exit "init: a rest state older than 24 hours changes nothing" 0 "$?"
new init-unreadable 5
mkdir -p "$T/.claude/.idd/state"; printf '{"review": tr' > "$(state_file)"
init no > /dev/null 2>&1; assert_exit "init: a rest state that cannot be read changes nothing" 0 "$?"

# spec-example: idd-all-rest / review added while an issue is in flight
crun() { python3 "$CS" run --cwd "$T" --repo "$REPO" --issue 5 2>/dev/null; }
for added in yes no; do
  new "review-added-$added" 5 9
  run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
  init no > /dev/null 2>&1; assert_exit "review added ($added): init records review off while the run has none" 0 "$?"
  run start --path PR --review "$added" > "$S/start.out" 2>&1
  [ "$added" = yes ] && assert_output_grep "review added (yes): start says a close stage that is already running is not stopped by it" "already running" "$S/start.out"
  OUT=$(crun); rc=$?
  [ "$added" = yes ] && assert_exit "review added (yes): the close stage stops (exit 3)" 3 "$rc"
  assert_eq "review added ($added): the reason is the review flag of the rest run: $added" "$added" \
    "$(printf '%s' "$OUT" | jget reason | grep -q 'the rest run at this --cwd has --review' && echo yes || echo no)"
done
new review-state-unreadable 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; init no > /dev/null 2>&1
printf '{"review": tr' > "$(state_file)"
OUT=$(crun); assert_exit "review: a rest state that cannot be read stops the close stage (exit 3)" 3 "$?"
assert_grep "review: and the reason says its review flag is unknown" "review flag is unknown" "$(printf '%s' "$OUT" | jget reason)"

echo "── reasons ──"
# spec-example: idd-all-rest / outcomes by issue state
new closed-reason 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null; echo CLOSED > "$G/state-5"
OUT=$(run record --issue 5 --reason 'Stopped: /idd-close did not finish')
assert_eq "record: a closed issue keeps the reason its run reported" "closed|Stopped: /idd-close did not finish" "$(printf '%s' "$OUT" | jget outcome)|$(printf '%s' "$OUT" | jget reason)"
# spec-example: idd-all-rest / a closed issue whose run reported a stop
settle 5 > /dev/null 2>&1; run report > "$S/report.out" 2>&1
assert_grep_re "report: the closed issue is listed under closed" '^closed \(1\): #5$' "$(cat "$S/report.out")"
assert_output_grep "report: followed by what its run reported" "#5 — its run reported: Stopped: /idd-close did not finish" "$S/report.out"
# spec-example: idd-all-rest / a reason on standard input is taken as it is
new stdin-reason 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
OUT=$(cd "$S" && printf '%s' 'it'"'"'s `whoami` and $(touch made-by-the-reason)' | rq record --cwd "$T" --repo "$REPO" --issue 5 --reason-stdin)
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

echo "── what the report tells a person to do ──"
# spec-example: idd-all-rest / the report says what to do with a kept branch
new advice 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'w\n' > "$T/w.txt"; git -C "$T" add w.txt; git -C "$T" commit -q -m "work of #5"
run record --issue 5 --reason x > /dev/null; settle 5 > /dev/null 2>&1
run next > /dev/null
git -C "$T" checkout -q --no-track -b idd/9-y origin/main; printf 'v\n' > "$T/v.txt"; git -C "$T" add v.txt; git -C "$T" commit -q -m "work of #9"
git -C "$T" push -q -u origin idd/9-y 2>/dev/null
run record --issue 9 --reason x > /dev/null; settle 9 > /dev/null 2>&1
run report > "$S/report.out" 2>&1
assert_grep "advice: the line of the branch without an upstream says deleting it lets a later run start the issue over" "deleting it lets a later rest run start the issue over" "$(grep -F 'branch idd/5-x is kept' "$S/report.out")"
refute_grep "advice: the line of the branch with an upstream does not" "deleting it" "$(grep -F 'branch idd/9-y is kept' "$S/report.out")"
assert_eq "advice: one line says that going on with kept work is for a person" "1" "$(grep -c 'going on with such work is for a person' "$S/report.out")"
refute_grep "advice: no line under a stopped issue names /idd-all" "/idd-all" "$(stopped_block "$S/report.out")"
git -C "$T" branch -q -D idd/5-x
run start --path PR --review no > /dev/null 2>&1
assert_eq "advice: with the branch deleted as the report says, a new run hands out #5" "5" "$(run next | jget next)"
# spec-example: idd-all-rest / the report says where the working tree may be
# spec-example: idd-all-rest / the step for a working tree that was not settled
new loose 5
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
git -C "$T" checkout -q --no-track -b idd/5-x origin/main; printf 'changed\n' >> "$T/a.txt"
run report > "$S/report.out" 2>&1
assert_grep "report: and says to commit or remove what is left there first" "commit or remove what is left there, then run git checkout --no-overwrite-ignore main" "$(grep -F 'may still be on a branch' "$S/report.out")"
git -C "$T" commit -q -am "what was left"; git -C "$T" checkout -q --no-overwrite-ignore main
run start --path PR --review no > /dev/null 2>&1; assert_exit "report: after those steps a new run starts" 0 "$?"
assert_output_grep "report: says the working tree may still be on a branch of the issue in flight" "the working tree may still be on a branch of #5" "$S/report.out"
assert_grep "report: and names the default branch" "main" "$(grep -F 'may still be on a branch' "$S/report.out")"

echo "── the inventory of writers ──"
# spec-example: idd-all-rest / every location the plugin names is in the inventory
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

new state-kept-paths 5
write_state 1 '[{"issue": 5, "outcome": "stopped", "reason": "x", "settled": true, "kept": [{"branch": "idd/5-x", "commit": "", "paths": [5]}]}]'
run start --path PR --review no > "$S/start.out" 2>&1
assert_output_grep "state: kept paths that are not names are not used" "cannot be used" "$S/start.out"

new render-crash 5 9
mkdir -p "$S/copy"; cp "$RQ" "$S/copy/rest-queue.py"; cp -R "$PLUGIN/scripts/lib" "$S/copy/lib"
printf '\n\ndef open_clarity_rows(issue):\n    raise RuntimeError("a failure nobody planned for")\n' >> "$S/copy/lib/intent.py"
OUT=$(python3 "$S/copy/rest-queue.py" list --repo "$REPO" --json 2> "$S/err"); rc=$?
assert_exit "rendering: an unplanned failure reading one rendering does not fail the list" 0 "$rc"
assert_eq "rendering: the issues it hit are unreadable" "[5,9]" "$(printf '%s' "$OUT" | jget classes.unreadable)"

python3 "$HERE/settle_matrix.py" "$RQ" > "$WORK/matrix.out" 2>&1; rc=$?
assert_exit "settle matrix: every combination matches the table" 0 "$rc"
[ "$rc" = 0 ] || sed -n "1,40p" "$WORK/matrix.out"
assert_output_grep "settle matrix: and it ran all of them" "288 cases, 0 mismatch(es)" "$WORK/matrix.out"

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
assert_grep_re "skill: and names both verdicts" 'verdict=resume.*verdict=blocked' "$REST"
assert_grep "skill: and records them without a question" "不提問" "$(printf '%s\n' "$REST" | grep -F 'verdict=resume')"
STEP051=$(awk '/^#### Step 0\.5\.1/{f=1} f&&/^#### Step 0\.6/{exit} f' "$SKILL")
assert_grep "skill: Step 0.5.1 points at the rest rule" '## Rest mode' "$STEP051"
STOPS=$(printf '%s\n' "$REST" | awk '/^### 整個 run 停下/{f=1; next} f&&/^### /{exit} f' | grep -E '^\| ' | sed -n '2,$p')   # the header row is dropped; the |---| line never matches
assert_eq "skill: the whole-run stop table has four rows" "4" "$(printf '%s\n' "$STOPS" | grep -c '^| ')"
# spec-example: idd-all-rest / the skill ends when the report itself fails
FAILED_REPORT=$(printf '%s\n' "$STOPS" | grep -E '^\| [^|]*`report`[^|]*以 1 或 3 結束')
assert_eq "skill: one row is about the report that fails" "1" "$(printf '%s\n' "$FAILED_REPORT" | grep -c '^| ')"
assert_grep "skill: that row says to pass on what was printed" "已經印出" "$FAILED_REPORT"
assert_grep_re "skill: and to call neither stop nor report again" '不再呼叫 `stop` 或 `report`' "$FAILED_REPORT"
assert_grep "skill: and still to clear the unattended marker" 'clear_unattended "$CWD"' "$FAILED_REPORT"
assert_grep "skill: the stop list says four cases" "只有這四種" "$REST"
# spec-example: idd-all-rest / the skill reports a failed start directly
FAILED_START=$(printf '%s\n' "$STOPS" | grep -E '^\| [^|]*`start`[^|]*以 3 結束')
assert_eq "skill: one row is about the start that fails before a run exists" "1" "$(printf '%s\n' "$FAILED_START" | grep -c '^| ')"
assert_grep "skill: that row says no run exists yet" "還沒有 run" "$FAILED_START"
assert_grep_re "skill: and to call neither stop nor report" '不呼叫 `stop` 與 `report`' "$FAILED_START"
assert_grep "skill: and to tell the user the reason" "告訴使用者" "$FAILED_START"
# spec-example: idd-all-rest / the skill goes on to the report when stop fails
STOP3=$(printf '%s\n' "$STOPS" | grep -E '^\| `next`、`record` 或 `settle` 以 3 結束')
assert_eq "skill: one row is about next, record or settle exiting 3" "1" "$(printf '%s\n' "$STOP3" | grep -c '^| ')"
assert_grep "skill: that row calls stop with the reason line" "照抄" "$STOP3"
assert_grep "skill: and goes on to the end when stop itself fails" '`stop` 自己也失敗時直接做「結束」一節' "$STOP3"
assert_grep "skill: gh authentication is part of that row" "gh" "$STOP3"
assert_grep_re "skill: stop case — the user interrupts, and nothing is recorded" '^\| 使用者中斷 \| 不必做任何事' "$STOPS"
refute_grep "skill: the old step 5 prose is gone" 'pull --ff-only -q' "$REST"
# spec-example: idd-all-rest / the skill ends a refused run without a marker
assert_grep "skill: a path that is not PR is one cause of a start that exits 3" 'path 不是 `PR`' "$FAILED_START"
assert_grep "skill: and that row clears the unattended marker" 'clear_unattended "$CWD"' "$FAILED_START"
refute_grep "skill: the rest section no longer describes a direct-commit run" "direct-commit 下，一張停下" "$REST"
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
OUT=$(cd "$S" && CLAUDE_PLUGIN_ROOT="$PLUGIN" CWD="$T" GITHUB_REPO="$REPO" N=5 bash "$S/record.sh" 2>/dev/null)
assert_eq "skill: the record block, run as it is written, records exactly that line" 'Stopped: the price is $5 and `date` is not run' "$(printf '%s' "$OUT" | jget reason)"
settle 5 > /dev/null 2>&1
OUT=$(cd "$S" && CLAUDE_PLUGIN_ROOT="$PLUGIN" CWD="$T" GITHUB_REPO="$REPO" bash "$S/stop.sh" 2>/dev/null)
assert_eq "skill: and so does the stop block" "the helper stopped" "$(printf '%s' "$OUT" | jget stopped)"
# spec-example: idd-all-rest / the skill takes both review values from next
assert_grep_re "skill: REVIEW_FLAG of an issue follows the review next printed" '`REVIEW_FLAG`[^。]*`next`' "$RUN_STEP"
assert_grep "skill: the block that prepares the pull request text asks the close stage for the review flag of the rest run" 'rest-review' "$(grep -F 'REST_REVIEW=' "$SKILL")"
assert_grep "skill: Step 0.7 says a rest run does not go back to the original arguments" "rest mode 例外" "$(awk '/^#### Step 0.7:/{f=1} f&&/^#### Step 0.8|^### Phase 1/{exit} f' "$SKILL" | grep -F '原始引數')"
# spec-example: idd-all-rest / the skill says the flags are to be the same
RESUME_ROWS=$(printf '%s\n' "$STOPS" | grep -F '會接續')
assert_eq "skill: two rows of the stop table say a later command resumes the run" "2" "$(printf '%s\n' "$RESUME_ROWS" | grep -c '^| ')"
assert_eq "skill: and both say the flags are to be the same" "2" "$(printf '%s\n' "$RESUME_ROWS" | grep -c '旗標相同')"
assert_eq "skill: every line that says a later command within 24 hours resumes the run says the flags are to be the same" "0" \
  "$(grep -F '24 小時內再下' "$SKILL" | grep -vc '旗標相同')"
assert_eq "skill: every line of the rest section about resuming within 24 hours says the flags are to be the same" "0" \
  "$(printf '%s\n' "$REST" | grep -F '24 小時內' | grep -F '接續' | grep -vc '旗標')"
# spec-example: idd-all-rest / the skill says to leave the working tree alone
assert_grep "skill: the rest section says nothing else is to work in the same working tree while a rest run goes" "不要在同一個工作樹" "$REST"
SETTLE_LINE=$(printf '%s\n' "$REST" | grep -F 'rest-queue.py" settle')
assert_eq "skill: there is one settle invocation" "1" "$(printf '%s\n' "$SETTLE_LINE" | grep -c .)"
refute_grep "skill: and it passes no default branch" "--default" "$SETTLE_LINE"
refute_grep "skill: and no path" "--path" "$SETTLE_LINE"
# spec-example: idd-all-rest / the skill continues an issue in flight
FLIGHT=$(printf '%s\n' "$REST" | grep -F '"in_flight": true')
assert_eq "skill: one row is about an issue in flight" "1" "$(printf '%s\n' "$FLIGHT" | grep -c .)"
assert_grep "skill: an issue in flight with a Phase 6 result goes to record" "直接做第 5 步" "$FLIGHT"
assert_grep_re "skill: without a branch it starts again from Step 0.4" '`branch` 是 `null` 時[^。]*從 Step 0\.4 重新開始' "$FLIGHT"
assert_grep "skill: otherwise its interrupted phase is continued" "從中斷的那個 phase 接著做完" "$FLIGHT"
assert_grep "skill: and Step 0.5.1 is not run again" "不重跑 Step 0.5.1" "$FLIGHT"
RECORD_STEP=$(printf '%s\n' "$FLOW" | grep -n -F 'rest-queue.py" record' | head -1 | cut -d: -f1)
assert_grep_re "skill: step 5 is the one that records" '^5\. 記下這一張的結果' "$(printf '%s\n' "$FLOW" | sed -n "1,${RECORD_STEP:-1}p" | grep -E '^[0-9]+\. ' | tail -1)"
# spec-example: idd-all-rest / the skill clears the unattended marker
NOTAKE=$(printf '%s\n' "$REST" | grep -F 'verdict=resume')
assert_grep_re "skill: an issue rest does not take over is cleaned up before it is recorded" 'clear_unattended "\$CWD"`[^。]*再做第 5 步' "$NOTAKE"
ENDING=$(printf '%s\n' "$REST" | awk '/^### 結束/{f=1; next} f&&/^### /{exit} f')
assert_grep "skill: the end of the run clears the unattended marker" 'clear_unattended "$CWD"' "$ENDING"
L_REP=$(printf '%s\n' "$ENDING" | grep -n -F 'rest-queue.py" report' | head -1 | cut -d: -f1)
L_CLR=$(printf '%s\n' "$ENDING" | grep -n -F 'clear_unattended "$CWD"' | tail -1 | cut -d: -f1)
assert_true "skill: and it does so after the report" "[ ${L_REP:-0} -gt 0 ] && [ ${L_CLR:-0} -gt ${L_REP:-0} ]"
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
for sub in start next record settle stop report; do
  assert_true "skill: the rest section calls $sub" "[ -n \"\$(line_of 'rest-queue.py\" $sub')\" ]"
done
L_START=$(line_of 'rest-queue.py" start'); L_NEXT=$(line_of 'rest-queue.py" next')
L_RECORD=$(line_of 'rest-queue.py" record'); L_REPORT=$(line_of 'rest-queue.py" report')
L_STOP=$(line_of 'rest-queue.py" stop'); L_SETTLE=$(line_of 'rest-queue.py" settle')
assert_true "skill: start comes before next" "[ ${L_START:-0} -gt 0 ] && [ ${L_START:-0} -lt ${L_NEXT:-0} ]"
assert_true "skill: next comes before record" "[ ${L_NEXT:-0} -gt 0 ] && [ ${L_NEXT:-0} -lt ${L_RECORD:-0} ]"
assert_true "skill: settle comes after record" "[ ${L_SETTLE:-0} -gt ${L_RECORD:-0} ]"
assert_true "skill: report comes last" "[ ${L_REPORT:-0} -gt ${L_SETTLE:-0} ] && [ ${L_REPORT:-0} -gt ${L_STOP:-0} ]"

# ── fix round 7: one reading of the rest run's state ──
# spec-example: idd-all-rest / the review flag of a rest run has one reader
rest_review() { python3 "$CS" rest-review --cwd "$T" --repo "$REPO" --issue 5 2> /dev/null; }
new rr-none 5 9
assert_eq "rest-review: no rest run: off" "off" "$(rest_review)"
for flag in yes no; do
  new "rr-$flag" 5 9
  run start --path PR --review "$flag" > /dev/null 2>&1; run next > /dev/null
  [ "$flag" = yes ] && WANT=on || WANT=off
  assert_eq "rest-review: review $flag, #5 in flight: $WANT" "$WANT" "$(rest_review)"
done
new rr-old 5 9
write_state 25 '[{"issue": 5, "outcome": null}]'
python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); s["review"]=True; json.dump(s, open(p,"w"))' "$(state_file)"
assert_eq "rest-review: a run older than 24 hours: off" "off" "$(rest_review)"
for lacks in version path default; do
  new "rr-lacks-$lacks" 5 9
  write_state 1 '[{"issue": 5, "outcome": null}]'
  python3 -c 'import json,sys; p=sys.argv[1]; s=json.load(open(p)); s.pop(sys.argv[2]); json.dump(s, open(p,"w"))' "$(state_file)" "$lacks"
  assert_eq "rest-review: a recent state without $lacks, review false: unreadable" "unreadable" "$(rest_review)"
  run start --path PR --review no > /dev/null 2>&1; assert_exit "rest-review: and start stops on the same file" 3 "$?"
  init no > /dev/null 2>&1
  python3 "$CS" run --cwd "$T" --repo "$REPO" --issue 5 > "$S/run.out" 2>&1
  assert_output_grep "rest-review: and the close stage stays at verified for it" "review flag is unknown" "$S/run.out"
done
new rr-not-json 5 9
mkdir -p "$T/.claude/.idd/state"; printf '{"review": fal' > "$(state_file)"
assert_eq "rest-review: a recent file that is not JSON: unreadable" "unreadable" "$(rest_review)"
phase5() { # the two lines of Phase 5 that take the review of the rest run, run as they are written → RUN_REVIEW
  (CLAUDE_PLUGIN_ROOT="$PLUGIN"; CWD="$T"; GITHUB_REPO="$REPO"; N=5; RUN_REVIEW=no
   eval "$(grep -F -A1 'REST_REVIEW=$(python3' "$SKILL")"; printf '%s' "$RUN_REVIEW")
}
assert_eq "skill: the two lines of Phase 5 are the call and the line that uses its answer" "2" "$(grep -F -A1 'REST_REVIEW=$(python3' "$SKILL" | grep -c 'REST_REVIEW')"
new p5-none 5 9
assert_eq "phase 5: no rest run leaves the review of the issue as it is" "no" "$(phase5)"
new p5-on 5 9
run start --path PR --review yes > /dev/null 2>&1; run next > /dev/null
assert_eq "phase 5: a rest run with review that has the issue in flight makes it a review" "yes" "$(phase5)"
new p5-off 5 9
run start --path PR --review no > /dev/null 2>&1; run next > /dev/null
assert_eq "phase 5: a rest run without review leaves it as it is" "no" "$(phase5)"
new p5-unreadable 5 9
mkdir -p "$T/.claude/.idd/state"; printf '{"review": fal' > "$(state_file)"
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
