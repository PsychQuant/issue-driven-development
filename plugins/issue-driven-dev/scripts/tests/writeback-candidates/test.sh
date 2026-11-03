#!/usr/bin/env bash
# test.sh — scripts/writeback-candidates.py (#424, spec issue-write-back,
# "Write-back SHALL be triggered by session discussion and by trusted comments").
# Runs the script against a stand-in for gh: who counts as trusted, whose comments
# are listed, the cutoff, a closed issue, and a failed read.
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
comments() { cat >"$WORK/comments"; }
run() { python3 "$S" "$@" >"$WORK/out" 2>"$WORK/err"; RC=$?; }

echo "A. classification"
issue open "## Problem"
comments <<'J'
[{"id":1,"user":{"login":"me"},"author_association":"OWNER","created_at":"2026-11-04T01:00:00Z","updated_at":"2026-11-04T01:00:00Z","body":"note"},
 {"id":2,"user":{"login":"amy"},"author_association":"COLLABORATOR","created_at":"2026-11-04T01:00:00Z","updated_at":"2026-11-04T01:00:00Z","body":"x"},
 {"id":3,"user":{"login":"bob"},"author_association":"MEMBER","created_at":"2026-11-04T01:00:00Z","updated_at":"2026-11-04T01:00:00Z","body":"x"},
 {"id":4,"user":{"login":"own"},"author_association":"OWNER","created_at":"2026-11-04T01:00:00Z","updated_at":"2026-11-04T01:00:00Z","body":"x"},
 {"id":5,"user":{"login":"eve"},"author_association":"NONE","created_at":"2026-11-04T01:00:00Z","updated_at":"2026-11-04T01:00:00Z","body":"x"},
 {"id":6,"user":{"login":"pat"},"author_association":"CONTRIBUTOR","created_at":"2026-11-04T01:00:00Z","updated_at":"2026-11-04T01:00:00Z","body":"x"},
 {"id":7,"user":{"login":"ci[bot]"},"author_association":"NONE","created_at":"2026-11-04T01:00:00Z","updated_at":"2026-11-04T01:00:00Z","body":"x"},
 {"id":8,"user":null,"author_association":"NONE","created_at":"2026-11-04T01:00:00Z","updated_at":"2026-11-04T01:00:00Z","body":"x"},
 {"id":9,"user":{"login":"deps[bot]","type":"Bot"},"author_association":"MEMBER","created_at":"2026-11-04T01:00:00Z","updated_at":"2026-11-04T01:00:00Z","body":"x"},
 {"id":19,"user":{"login":"app","type":"Bot"},"author_association":"COLLABORATOR","created_at":"2026-11-04T01:00:00Z","updated_at":"2026-11-04T01:00:00Z","body":"x"}]
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
assert_grep "a bot is not, even as a member" "UNTRUSTED 9 deps[bot] MEMBER" "$OUT"
assert_grep "a bot account without the suffix is not either" "UNTRUSTED 19 app COLLABORATOR" "$OUT"

echo "B. no time cutoff"
comments <<'J'
[{"id":1,"user":{"login":"me"},"author_association":"OWNER","created_at":"2026-10-01T00:00:00Z","updated_at":"2026-11-03T12:00:00Z","body":"## Diagnosis\n..."},
 {"id":10,"user":{"login":"amy"},"author_association":"MEMBER","created_at":"2020-01-01T00:00:00Z","updated_at":"2020-01-01T00:00:00Z","body":"x"},
 {"id":11,"user":{"login":"amy"},"author_association":"MEMBER","body":"no dates"}]
J
issue open "**Last updated**: 2099-01-01 by idd-update"
run --repo o/r --issue 7
OUT="$(cat "$WORK/out")"
assert_grep "an old comment is still listed after your Diagnosis was edited" "TRUSTED 10 " "$OUT"
assert_grep "a comment without dates is listed" "TRUSTED 11 " "$OUT"

echo "C. nothing to do, closed issue, failures"
issue closed "x"
run --repo o/r --issue 7
assert_exit "a closed issue exits 0" 0 "$RC"
assert_eq "and lists nothing" "" "$(cat "$WORK/out")"
assert_output_grep "and says why" "closed" "$WORK/err"
issue open "x"
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
issue open "x"

echo "D. arguments reach no command line unchecked"
run --repo 'o/r;touch x' --issue 7
assert_exit "a malformed repo exits 2" 2 "$RC"
run --repo o/r --issue '7/../../x'
assert_exit "a malformed issue number exits 2" 2 "$RC"
run --repo o/r
assert_exit "a missing issue number exits 2" 2 "$RC"

print_summary "writeback-candidates"
