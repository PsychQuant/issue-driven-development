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
ci() { git -C "$R" add -A; git -C "$R" -c user.name=t -c user.email=t@t commit -qm "$1"; SHA=$(git -C "$R" rev-parse HEAD); }
repo() { # new clone with one commit; config ignored unless told otherwise
  n=$((n+1)); R="$W/r$n"; mkdir -p "$R"
  git -C "$R" -c init.defaultBranch=main init -q
  printf '.claude/.idd/\n' > "$R/.gitignore"
  mkdir -p "$R/scripts"; printf 'echo shipped > "$MARK"\n' > "$R/scripts/ci.sh"
  ci init
}
cfg() { mkdir -p "$R/.claude/.idd"; printf '%s' "$1" > "$R/.claude/.idd/local.json"; }
run() { OUT=$(bash "$GATE" run --commit "${1:-$SHA}" --cwd "$R" 2>"$W/err"); RC=$?; }
field() { printf '%s\n' "$OUT" | sed -n "s/^$1=//p"; }
expect() { # name rc result
  if [ "$RC" = "$2" ] && [ "$(field RESULT)" = "$3" ]; then ok; else bad "$1: rc=$RC result=$(field RESULT) want $2/$3; $(cat "$W/err")"; fi
}
export MARK="$W/mark"
MARKCMD='{"ci":{"command":"touch \"$MARK\""}}'
notrun() { [ -e "$MARK" ] && bad "$1: the command ran" || ok; rm -f "$MARK"; }

# Local mode is the default
repo; run; expect "no config" 3 not-configured
repo; cfg '{"ci":{"mode":"remote","command":"touch \"$MARK\""}}'; run; expect "remote" 10 remote; notrun "remote"
repo; cfg '{"ci":{"mode":"cloud"}}'; run; expect "bad mode" 4 error
repo; cfg '{"ci":{"command":"true"}}'; run; expect "mode absent is local" 0 pass

# The command comes only from untracked local configuration
repo; run; expect "shipped script not run" 3 not-configured; notrun "scripts/ci.sh"
repo; printf '' > "$R/.gitignore"; cfg "$MARKCMD"; ci cfg; run; expect "tracked config" 4 error; notrun "tracked config"
repo; cfg '{not json'; run; expect "unparsable config" 4 error
repo; cfg '{"ci":{"command":""}}'; run; expect "empty command" 4 error
repo; cfg '{"ci":{"command":["true"]}}'; run; expect "non-string command" 4 error

# A bare repository planted in the config directory must not answer the tracked check
repo; printf '' > "$R/.gitignore"; cfg "$MARKCMD"; ci cfg
git -c init.defaultBranch=main init -q --bare "$W/bare$n"; for e in HEAD objects refs config; do cp -pR "$W/bare$n/$e" "$R/.claude/.idd/$e"; done
run; expect "tracked config with planted bare repo" 4 error; notrun "planted bare repo"
# A config tracked under another case must not run, whichever way the filesystem resolves it
repo; printf '' > "$R/.gitignore"; mkdir -p "$R/.claude/.idd"; printf '%s' "$MARKCMD" > "$R/.claude/.idd/LOCAL.JSON"; ci cfg
run; { [ "$RC" = 4 ] || [ "$RC" = 3 ]; } && ok || bad "case variant: rc=$RC"; notrun "case-variant tracked config"
# Links
repo; mkdir -p "$W/elsewhere" "$R/.claude/.idd"; printf '%s' "$MARKCMD" > "$W/elsewhere/c.json"; ln -s "$W/elsewhere/c.json" "$R/.claude/.idd/local.json"
run; expect "linked config" 4 error; notrun "linked config"
repo; mkdir -p "$W/else2/.idd"; printf '%s' "$MARKCMD" > "$W/else2/.idd/local.json"; ln -s "$W/else2" "$R/.claude"
run; expect "linked .claude" 4 error; notrun "linked .claude"
# Permissions
repo; cfg "$MARKCMD"; chmod g+w "$R/.claude/.idd/local.json"; run; expect "group-writable config" 4 error; notrun "group-writable config"
repo; cfg "$MARKCMD"; chmod o+w "$R/.claude/.idd"; run; expect "world-writable directory" 4 error; notrun "world-writable directory"
# No walking above the repository
n=$((n+1)); O="$W/o$n"; mkdir -p "$O/.claude/.idd"; printf '%s' "$MARKCMD" > "$O/.claude/.idd/local.json"
R="$O/inner"; mkdir -p "$R"; git -C "$R" -c init.defaultBranch=main init -q; echo x > "$R/f"; ci i
run; expect "config above the repository" 3 not-configured; notrun "config above the repository"
# A linked worktree uses the main worktree's config
repo; cfg '{"ci":{"command":"true"}}'; git -C "$R" worktree add -q --detach "$W/lw$n" "$SHA"
OUT=$(bash "$GATE" run --commit "$SHA" --cwd "$W/lw$n" 2>"$W/err"); RC=$?; expect "linked worktree" 0 pass

# .claude as a submodule shows only as a gitlink
n=$((n+1)); SUB="$W/sub$n"; mkdir -p "$SUB/.idd"; git -C "$SUB" -c init.defaultBranch=main init -q; printf '%s' "$MARKCMD" > "$SUB/.idd/local.json"
git -C "$SUB" add -A; git -C "$SUB" -c user.name=t -c user.email=t@t commit -qm s
repo; git -C "$R" -c protocol.file.allow=always submodule add -q "$SUB" .claude; ci sub
run; expect "submodule at .claude" 4 error; notrun "submodule at .claude"
# A planted git directory in a tracked subdirectory
repo; S="$R/sub"; mkdir -p "$S/objects" "$S/refs" "$S/.claude/.idd"; printf 'ref: refs/heads/main\n' > "$S/HEAD"; touch "$S/objects/k" "$S/refs/k"
printf '[core]\n\trepositoryformatversion = 0\n\tbare = false\n\tworktree = .\n' > "$S/config"; printf '%s' "$MARKCMD" > "$S/.claude/.idd/local.json"; ci planted
OUT=$(bash "$GATE" run --commit "$SHA" --cwd "$S" 2>"$W/err"); RC=$?; [ "$RC" != 0 ] && ok || bad "planted git dir: rc=$RC"; notrun "planted git dir in a subdirectory"
# Repository hooks stay out of the gate's own git calls
repo; cfg '{"ci":{"command":"true"}}'; mkdir -p "$R/.githooks"; printf '#!/bin/sh\ntouch "$MARK"\n' > "$R/.githooks/post-checkout"; python3 -c 'import os,sys; os.chmod(sys.argv[1],0o755)' "$R/.githooks/post-checkout"; ci hook; git -C "$R" config core.hooksPath .githooks
run; expect "repository hook" 0 pass; notrun "repository hook"
# A leaked GIT_INDEX_FILE does not make a tracked config look untracked
repo; printf '' > "$R/.gitignore"; cfg "$MARKCMD"; ci cfg
OUT=$(GIT_INDEX_FILE="$W/none" bash "$GATE" run --commit "$SHA" --cwd "$R" 2>"$W/err"); RC=$?; expect "GIT_INDEX_FILE" 4 error; notrun "GIT_INDEX_FILE"
# A command that rewrites its own config
repo; printf '#!/bin/sh\nprintf x >> "$1"\n' > "$W/rw$n.sh"; cfg "{\"ci\":{\"command\":\"sh $W/rw$n.sh $R/.claude/.idd/local.json\"}}"; run; expect "config rewritten during the run" 4 error
# Every field is validated, whatever the mode
repo; cfg '{"ci":{"mode":"remote","timeout_seconds":"abc"}}'; run; expect "bad field under remote" 4 error
repo; cfg '{"ci":{"post_output_tail":"yes"}}'; run; expect "bad field without command" 4 error
# A linked worktree ignores its own config
repo; cfg '{"ci":{"command":"false"}}'; git -C "$R" worktree add -q --detach "$W/lx$n" "$SHA"; mkdir -p "$W/lx$n/.claude/.idd"; printf '{"ci":{"command":"true"}}' > "$W/lx$n/.claude/.idd/local.json"
OUT=$(bash "$GATE" run --commit "$SHA" --cwd "$W/lx$n" 2>"$W/err"); RC=$?; expect "linked worktree's own config" 1 fail

# A tracked Python file must not shadow the gate's own imports, from inside the clone
repo; for m in json tempfile hashlib; do printf 'import os\nopen(os.environ["MARK"],"w").write("x")\nraise SystemExit(0)\n' > "$R/$m.py"; done; ci shadow
OUT=$(cd "$R" && bash "$GATE" run --commit "$SHA" 2>"$W/err"); RC=$?; expect "shadowed stdlib from the clone" 3 not-configured; notrun "shadowed stdlib"
# A filter configured in the repository does not run during the checkout
repo; cfg '{"ci":{"command":"true"}}'; printf 'f filter=evil\n' > "$R/.gitattributes"; echo x > "$R/f"; ci attrs; git -C "$R" config filter.evil.smudge 'touch "$MARK"; cat'
run; expect "local filter refused" 4 error; notrun "local filter"
# Another worktree's record survives a run
repo; cfg '{"ci":{"command":"true"}}'; git -C "$R" worktree add -q --detach "$W/mv$n" "$SHA"; mv "$W/mv$n" "$W/mv$n.moved"
run; expect "with a moved worktree" 0 pass
[ -d "$R/.git/worktrees" ] && ok || bad "the gate pruned another worktree's record"
# An output that is not a path (old git echoes an unknown flag) is not used
repo; cfg '{"ci":{"command":"true"}}'; mkdir -p "$W/oldgit$n"; printf '#!/bin/sh\nfor a; do [ "$a" = --path-format=absolute ] && { echo --path-format=absolute; echo .git; exit 0; }; done\nexec %s "$@"\n' "$(command -v git)" > "$W/oldgit$n/git"; python3 -c 'import os,sys; os.chmod(sys.argv[1],0o755)' "$W/oldgit$n/git"
OUT=$(PATH="$W/oldgit$n:$PATH" bash "$GATE" run --commit "$SHA" --cwd "$R" 2>"$W/err"); RC=$?; expect "git without --path-format" 4 error

# A relative PATH entry or BASH_ENV must not let a tracked file decide the result
repo; cfg '{"ci":{"command":"false"}}'; mkdir -p "$R/bin"; printf '#!/bin/sh\nexit 0\n' > "$R/bin/bash"; python3 -c 'import os,sys; os.chmod(sys.argv[1],0o755)' "$R/bin/bash"; printf 'exit 0\n' > "$R/env0.sh"; ci tools
OUT=$(PATH="bin:$PATH" bash "$GATE" run --commit "$SHA" --cwd "$R" 2>"$W/err"); RC=$?; expect "relative PATH" 1 fail
OUT=$(BASH_ENV=env0.sh bash "$GATE" run --commit "$SHA" --cwd "$R" 2>"$W/err"); RC=$?; expect "relative BASH_ENV" 1 fail
# A filter reached through an include
repo; cfg '{"ci":{"command":"true"}}'; printf '[filter "x"]\n\tsmudge = touch "$MARK"; cat\n' > "$W/inc$n"; printf 'f filter=x\n' > "$R/.gitattributes"; echo x > "$R/f"; ci attrs; git -C "$R" config include.path "$W/inc$n"
run; expect "filter through include" 4 error; notrun "filter through include"

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

# Records hold no output and no command by default
repo; cfg '{"ci":{"command":"printf secret-; printf output"}}'; run; expect "pass record" 0 pass
REC=$(field RECORD); grep -q "$SHA" "$REC" && ok || bad "record lacks commit"
grep -q 'secret-output' "$REC" && bad "pass record has output" || ok
grep -q 'secret-output' "$(field LOG)" && ok || bad "log lacks output"
grep -Eq '[0-9]T[0-9:]+[+-][0-9]{2}:[0-9]{2}' "$REC" && ok || bad "record times lack offset"
repo; cfg '{"ci":{"command":"echo tok3n-value; SECRET=hunter2 false"}}'; run; expect "default fail record" 1 fail
REC=$(field RECORD); grep -q 'tok3n-value' "$REC" && bad "default record has output" || ok
grep -q 'hunter2' "$REC" && bad "record has the command" || ok
grep -q 'tok3n-value' "$(field LOG)" && ok || bad "local log lost the output"
repo; cfg '{"ci":{"command":"true","post_output_tail":"yes"}}'; run; expect "non-boolean post_output_tail" 4 error

# The opt-in tail
repo; cfg "{\"ci\":{\"post_output_tail\":true,\"command\":\"echo \$HOME/x; pwd; seq 1 60; false\"}}"; run; expect "fail record" 1 fail
REC=$(field RECORD)
grep -q "$HOME" "$REC" && bad "record has home dir" || ok
grep -q '~/x' "$REC" && bad "tail beyond 40 lines kept" || ok
grep -q '^60$' "$REC" && ok || bad "record lacks last line"
[ "$(grep -c '^[0-9][0-9]*$' "$REC")" = 40 ] && ok || bad "tail is not 40 lines"
repo; cfg "{\"ci\":{\"post_output_tail\":true,\"command\":\"echo \$HOME/x; pwd; false\"}}"; run; expect "fail paths" 1 fail
REC=$(field RECORD); grep -q '~/x' "$REC" && ok || bad "home not replaced"
grep -q '<checkout>' "$REC" && ok || bad "checkout not replaced"
# It cannot close its fence, and control characters are removed
repo; cfg '{"ci":{"post_output_tail":true,"command":"printf \"\\x60\\x60\\x60\\x60\\x60\\x60\\x60\\x60\\x60\\x60\\n## forged\\n\\033[31mred\\n\"; false"}}'; run; expect "fence record" 1 fail
python3 - "$(field RECORD)" <<'CHECK' && ok || bad "fence escape or control character"
import re, sys
t = open(sys.argv[1], encoding="utf-8").read()
fences = re.findall(r"^(`{3,})$", t, re.M)
assert fences[0] == fences[-1] and all(len(f) < len(fences[0]) for f in fences[1:-1]), fences
assert "\x1b" not in t
CHECK

# usage
OUT=$(bash "$GATE" run 2>/dev/null); RC=$?; expect "missing --commit" 4 error

echo "idd-ci-gate: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
