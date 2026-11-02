#!/usr/bin/env bash
# test.sh — fixture suite for idd-ci-gate.sh (#465, spec local-ci-gate). Real git; no network.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GATE="$HERE/../../idd-ci-gate.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
W="$(cd "$W" && pwd -P)"
export TMPDIR="$W/tmp"; mkdir -p "$TMPDIR"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }
n=0
repo() { # new clone with one commit; config ignored unless told otherwise
  n=$((n+1)); R="$W/r$n"; mkdir -p "$R"
  git -C "$R" -c init.defaultBranch=main init -q
  printf '.claude/.idd/\n' > "$R/.gitignore"
  mkdir -p "$R/scripts"; printf 'echo shipped > "$MARK"\n' > "$R/scripts/ci.sh"
  git -C "$R" add -A; git -C "$R" -c user.name=t -c user.email=t@t commit -qm init
  SHA=$(git -C "$R" rev-parse HEAD)
}
cfg() { mkdir -p "$R/.claude/.idd"; printf '%s' "$1" > "$R/.claude/.idd/local.json"; }
run() { OUT=$(bash "$GATE" run --commit "${1:-$SHA}" --cwd "$R" 2>"$W/err"); RC=$?; }
field() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p"; }
expect() { # name rc result
  if [ "$RC" = "$2" ] && [ "$(field RESULT)" = "$3" ]; then ok; else bad "$1: rc=$RC result=$(field RESULT) want $2/$3; $(cat "$W/err")"; fi
}
export MARK="$W/mark"

# Local mode is the default
repo; run; expect "no config" 3 not-configured
repo; cfg '{"ci":{"mode":"remote","command":"touch \"$MARK\""}}'; run; expect "remote" 10 remote
[ -e "$MARK" ] && bad "remote ran the command" || ok
repo; cfg '{"ci":{"mode":"cloud"}}'; run; expect "bad mode" 4 error
repo; cfg '{"ci":{"command":"true"}}'; run; expect "mode absent is local" 0 pass

# The command comes only from untracked local configuration
repo; rm -f "$MARK"; run; expect "shipped script not run" 3 not-configured
[ -e "$MARK" ] && bad "scripts/ci.sh executed" || ok
repo; printf '' > "$R/.gitignore"; cfg '{"ci":{"command":"touch \"$MARK\""}}'
git -C "$R" add -A; git -C "$R" -c user.name=t -c user.email=t@t commit -qm cfg; SHA=$(git -C "$R" rev-parse HEAD)
rm -f "$MARK"; run; expect "tracked config" 4 error
[ -e "$MARK" ] && bad "tracked config ran" || ok
repo; cfg '{not json'; run; expect "unparsable config" 4 error
repo; cfg '{"ci":{"command":""}}'; run; expect "empty command" 4 error
repo; cfg '{"ci":{"command":["true"]}}'; run; expect "non-string command" 4 error

# Clean checkout
repo; echo x > "$R/dirty.txt"; cfg '{"ci":{"command":"test ! -e dirty.txt && test -e scripts/ci.sh"}}'; run; expect "uncommitted stays out" 0 pass
repo; cfg '{"ci":{"command":"false"}}'; run; expect "failure" 1 fail
if git -C "$R" worktree list | grep -q idd-ci-gate; then bad "worktree left behind"; else ok; fi
repo; cfg '{"ci":{"command":"true"}}'; run 0000000000000000000000000000000000000000; expect "missing commit" 4 error
repo; cfg '{"ci":{"command":"true"}}'; run --upload-pack=x; expect "option-shaped commit" 4 error

# Exit codes
repo; cfg '{"ci":{"command":"sleep 5","timeout_seconds":1}}'; run; expect "timeout" 2 timeout
if git -C "$R" worktree list | grep -q idd-ci-gate; then bad "worktree left after timeout"; else ok; fi
repo; cfg '{"ci":{"command":"true","timeout_seconds":"abc"}}'; run; expect "bad timeout" 4 error
repo; cfg '{"ci":{"command":"true","timeout_seconds":0}}'; run; expect "zero timeout" 4 error
repo; cfg '{"ci":{"command":"true","timeout_seconds":true}}'; run; expect "bool timeout" 4 error
repo; rm -f "$W/child"; cfg "{\"ci\":{\"command\":\"(sleep 3; touch $W/child) & sleep 30\",\"timeout_seconds\":1}}"; run; expect "timeout with child" 2 timeout
/bin/sleep 3; [ -e "$W/child" ] && bad "background child survived" || ok

# Records
repo; cfg '{"ci":{"command":"printf secret-; printf output"}}'; run; expect "pass record" 0 pass
REC=$(field RECORD); grep -q "$SHA" "$REC" && ok || bad "record lacks commit"
grep -q 'secret-output' "$REC" && bad "pass record has output" || ok
grep -q 'secret-output' "$(field LOG)" && ok || bad "log lacks output"
grep -Eq '[0-9]T[0-9:]+[+-][0-9]{2}:[0-9]{2}' "$REC" && ok || bad "record times lack offset"
repo; cfg "{\"ci\":{\"command\":\"echo \$HOME/x; pwd; seq 1 60; false\"}}"; run; expect "fail record" 1 fail
REC=$(field RECORD)
grep -q "$HOME" "$REC" && bad "record has home dir" || ok
grep -q '~/x' "$REC" && bad "tail beyond 40 lines kept" || ok
grep -q '^60$' "$REC" && ok || bad "record lacks last line"
[ "$(grep -c '^[0-9][0-9]*$' "$REC")" = 40 ] && ok || bad "tail is not 40 lines"
repo; cfg "{\"ci\":{\"command\":\"echo \$HOME/x; pwd; false\"}}"; run; expect "fail paths" 1 fail
REC=$(field RECORD); grep -q '~/x' "$REC" && ok || bad "home not replaced"
grep -q '<checkout>' "$REC" && ok || bad "checkout not replaced"

# usage
OUT=$(bash "$GATE" run 2>/dev/null); RC=$?; expect "missing --commit" 4 error

echo "idd-ci-gate: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
