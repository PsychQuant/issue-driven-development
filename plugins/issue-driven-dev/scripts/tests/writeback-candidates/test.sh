#!/usr/bin/env bash
# test.sh — scripts/writeback-candidates.py (#424, spec issue-write-back,
# "Write-back SHALL be triggered by session discussion and by trusted comments").
# Runs the script against a stand-in for gh: who counts as trusted, whose comments
# are listed, the date cutoff, a closed issue, and a failed read.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
S="$PLUGIN/scripts/writeback-candidates.py"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/idd-wbc-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'GH'
#!/usr/bin/env python3
import os, sys
store = os.environ["FAKE_STORE"]
args = sys.argv[1:]
open(os.path.join(store, "calls.log"), "a").write(" ".join(args) + "\n")
def out(name):
    path = os.path.join(store, name)
    if not os.path.exists(path):
        sys.exit(1)
    sys.stdout.write(open(path).read())
if args[:2] == ["api", "user"]:
    out("user")
elif args[0] == "api" and "/comments" in args[1]:
    out("comments")
elif args[0] == "api":
    out("issue")
else:
    sys.exit(1)
GH
chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH" FAKE_STORE="$WORK"
printf '{"login":"me"}' >"$WORK/user"

issue() { python3 -c 'import json,sys;json.dump({"state":sys.argv[1],"body":sys.argv[2]},open(sys.argv[3],"w"))' "$1" "$2" "$WORK/issue"; }
BODY='## Current Status

**Phase**: diagnosed
**Last updated**: 2026-11-03 by idd-update
'
comments() { cat >"$WORK/comments"; }
run() { python3 "$S" "$@" >"$WORK/out" 2>"$WORK/err"; RC=$?; }

echo "A. classification"
issue open "$BODY"
comments <<'J'
[{"id":1,"user":{"login":"me"},"author_association":"OWNER","created_at":"2026-11-04T01:00:00Z"},
 {"id":2,"user":{"login":"amy"},"author_association":"COLLABORATOR","created_at":"2026-11-04T01:00:00Z"},
 {"id":3,"user":{"login":"bob"},"author_association":"MEMBER","created_at":"2026-11-04T01:00:00Z"},
 {"id":4,"user":{"login":"own"},"author_association":"OWNER","created_at":"2026-11-04T01:00:00Z"},
 {"id":5,"user":{"login":"eve"},"author_association":"NONE","created_at":"2026-11-04T01:00:00Z"},
 {"id":6,"user":{"login":"pat"},"author_association":"CONTRIBUTOR","created_at":"2026-11-04T01:00:00Z"},
 {"id":7,"user":{"login":"ci[bot]"},"author_association":"NONE","created_at":"2026-11-04T01:00:00Z"},
 {"id":8,"user":null,"author_association":"NONE","created_at":"2026-11-04T01:00:00Z"}]
J
run --repo o/r --issue 7
assert_exit "exits 0" 0 "$RC"
OUT="$(cat "$WORK/out")"
refute_grep "your own comment is not a candidate" " 1 " "$OUT"
assert_grep "a collaborator is trusted" "TRUSTED 2 amy COLLABORATOR" "$OUT"
assert_grep "a member is trusted" "TRUSTED 3 bob MEMBER" "$OUT"
assert_grep "the owner is trusted when it is not you" "TRUSTED 4 own OWNER" "$OUT"
assert_grep "an outsider is not" "UNTRUSTED 5 eve NONE" "$OUT"
assert_grep "a past contributor is not" "UNTRUSTED 6 pat CONTRIBUTOR" "$OUT"
assert_grep "a bot is not" "UNTRUSTED 7 ci[bot] NONE" "$OUT"
assert_grep "a deleted account is not" "UNTRUSTED 8 (unknown) NONE" "$OUT"

echo "B. the date cutoff"
comments <<'J'
[{"id":10,"user":{"login":"amy"},"author_association":"MEMBER","created_at":"2026-11-01T23:59:59Z"},
 {"id":11,"user":{"login":"amy"},"author_association":"MEMBER","created_at":"2026-11-02T00:00:00Z"},
 {"id":12,"user":{"login":"amy"},"author_association":"MEMBER","created_at":"2026-11-03T12:00:00Z"}]
J
run --repo o/r --issue 7
OUT="$(cat "$WORK/out")"
refute_grep "older than a day before Last updated is skipped" "TRUSTED 10 " "$OUT"
assert_grep "a day before Last updated still counts (time zones)" "TRUSTED 11 " "$OUT"
assert_grep "the same day counts" "TRUSTED 12 " "$OUT"
issue open "no status block yet"
run --repo o/r --issue 7
assert_grep "without a Last updated line every comment counts" "TRUSTED 10 " "$(cat "$WORK/out")"
issue open "**Last updated**: not a date by someone
"
run --repo o/r --issue 7
assert_grep "an unreadable date counts every comment" "TRUSTED 10 " "$(cat "$WORK/out")"

echo "C. nothing to do, closed issue, failures"
issue closed "$BODY"
run --repo o/r --issue 7
assert_exit "a closed issue exits 0" 0 "$RC"
assert_eq "and lists nothing" "" "$(cat "$WORK/out")"
assert_output_grep "and says why" "closed" "$WORK/err"
issue open "$BODY"
printf '[]' >"$WORK/comments"
run --repo o/r --issue 7
assert_exit "no comments exits 0" 0 "$RC"
assert_eq "and lists nothing" "" "$(cat "$WORK/out")"
rm -f "$WORK/comments"
run --repo o/r --issue 7
assert_exit "a failed comment read exits 1" 1 "$RC"
printf 'not json' >"$WORK/comments"
run --repo o/r --issue 7
assert_exit "a malformed answer exits 1" 1 "$RC"
printf '[]' >"$WORK/comments"
rm -f "$WORK/user"
run --repo o/r --issue 7
assert_exit "an unknown gh user exits 1, not everyone is someone else" 1 "$RC"
printf '{"login":"me"}' >"$WORK/user"
rm -f "$WORK/issue"
run --repo o/r --issue 7
assert_exit "a failed issue read exits 1" 1 "$RC"
issue open "$BODY"

echo "D. arguments reach no command line unchecked"
run --repo 'o/r;touch x' --issue 7
assert_exit "a malformed repo exits 2" 2 "$RC"
run --repo o/r --issue '7/../../x'
assert_exit "a malformed issue number exits 2" 2 "$RC"
run --repo o/r
assert_exit "a missing issue number exits 2" 2 "$RC"

print_summary "writeback-candidates"
