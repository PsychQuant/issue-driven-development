# lib.sh — what the suites of rest-queue.py share (#478): a scenario (a repository with an origin, and GitHub's
# answers), the helper's commands, and the states the directory of an issue can be in. Sourced after
# ../../lib/assert-helpers.sh; fake-gh.py and scenario.py are beside this file.
RQT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RQ="$RQT/../../rest-queue.py"
PLUGIN="$(cd "$RQT/../../.." && pwd)"
SKILL="$PLUGIN/skills/idd-all/SKILL.md"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/idd-rest-queue-test.XXXXXX")
trap '/bin/chmod -R u+rwX "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT   # a test may leave a folder that cannot be listed
export IDD_CLOSE_STAGE_TEST=1 IDD_GH="$RQT/fake-gh.py"
# git in the scenarios reads no configuration of this machine: hooks, signing and templates there cannot change a result
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0 \
  GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
REPO=o/r
SHIM="$WORK/shim"; mkdir -p "$SHIM"
printf '#!/bin/sh\nexec python3 "%s" "$@"\n' "$RQT/fake-gh.py" > "$SHIM/gh"
/bin/chmod u+x "$SHIM/gh"
export PATH="$SHIM:$PATH"   # scripts/check-existing-work.sh, which next asks, calls gh by name
WORK=$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$WORK")   # the paths next prints are real paths

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
  python3 "$RQT/scenario.py" "$G" "$@"
}
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
issues() { python3 "$RQT/scenario.py" "$G" "$@"; }   # replace the open issues of the current scenario
rq() { python3 "$RQ" "$@"; }
NO_TOKEN_YET=000000000000000000000000   # a well-formed token that is no run's: what a command gets before any start
TEST_TOKEN=00112233445566778899aabb      # the token of a state that write_state writes by hand
run_token() { # → the token the last start of this scenario printed (or write_state stored)
  cat "$S/token" 2> /dev/null || printf '%s' "$NO_TOKEN_YET"
}
token_of() { run_token; }   # one token per run: every issue of a run has the run's
run() { # subcommand args… → rest-queue.py at T; start keeps the token it prints, and every command that takes one is
        # given it unless the call names one
  local sub="$1" out rc tok; shift
  case "$sub" in
    start)
      out=$(rq start --cwd "$T" --repo "$REPO" "$@"); rc=$?
      tok=$(printf '%s\n' "$out" | sed -n 's/^token: \([0-9a-f]\{24\}\)$/\1/p' | head -1)
      [ -n "$tok" ] && printf '%s' "$tok" > "$S/token"
      [ -n "$out" ] && printf '%s\n' "$out"
      return "$rc" ;;
    next|where|record|stop|report)
      case " $* " in *" --token "*) ;; *) set -- "$@" --token "$(run_token)" ;; esac ;;
  esac
  rq "$sub" --cwd "$T" --repo "$REPO" "$@"
}
here_in() { # directory issue [token] → here, run in that directory
  (cd "$1" && python3 "$RQ" here --cwd "$1" --repo "$REPO" --issue "$2" --token "${3:-$(run_token)}")
}
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
import hashlib, json, sys, time
path, hours, attempts = sys.argv[1], float(sys.argv[2]), json.loads(sys.argv[3])
stamp = lambda t: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(t))
at = time.time() - hours * 3600
for a in attempts:
    a.setdefault("handed_at", stamp(at)); a.setdefault("recorded_at", stamp(at)); a.setdefault("reason", "")
    a.setdefault("dir", None); a.setdefault("made", False); a.setdefault("left", "none" if a["outcome"] else None)
json.dump({"version": 6, "repo": "o/r", "path": "PR", "default": "main", "review": False, "started_at": stamp(at - 60), "updated_at": stamp(at),
           "token_digest": hashlib.sha256(b"00112233445566778899aabb").hexdigest(), "attempts": attempts, "stop": None}, open(path, "w"))
PY
  printf '%s' "$TEST_TOKEN" > "$S/token"
}

# ── the directory of an issue ──
dir_of() { printf '%s' "$T/.claude/worktrees/rest-$1"; }
EDITS=".claude/.idd/$(printf 'arch%s' ive)"   # where idd-edit-helper.py keeps earlier versions of corrected GitHub text
ROUTING=".claude/.idd/routing-stats.jsonl"
begin() { run start --path PR --review no > /dev/null 2>&1; run next > /dev/null 2>&1; }   # a new run, the first candidate handed out
attempt() { # issue key → that key of the attempt in the run state (strings as they are, the rest as compact JSON)
  python3 -c '
import json, sys
a = [x for x in json.load(open(sys.argv[1]))["attempts"] if x["issue"] == int(sys.argv[2])][0]
v = a.get(sys.argv[3], "<missing>")
print(v if isinstance(v, str) else json.dumps(v, separators=(",", ":"), ensure_ascii=False))' "$(state_file)" "$1" "$2"
}
pushed() { # the directory of #5 on its branch idd/5-x with one commit, pushed
  local d; d=$(dir_of 5)
  git -C "$d" checkout -q -b idd/5-x && printf 'w\n' > "$d/w.txt" && git -C "$d" add w.txt \
    && git -C "$d" commit -q -m "work (#5)" && git -C "$d" push -q -u origin idd/5-x 2>/dev/null
}
snap() { tar -C "$WORK" -cf "$WORK/$1.tar" "$1"; }                          # a scenario as it is now …
restore() { rm -rf "${WORK:?}/$1"; tar -C "$WORK" -xf "$WORK/$1.tar"; }     # … and brought back to that, at the same place

# The rows of the example "what becomes of a directory": one function per row, run with D set to the directory of #5.
s_pushed()     { pushed; }
s_manifest()   { pushed; mkdir -p "$D/.claude/.idd/attachments/issue-5"; printf '{"t":1}\n' > "$D/.claude/.idd/attachments/issue-5/_manifest.json"
                 git -C "$D" add -f .claude/.idd/attachments; git -C "$D" commit -q -m "manifest (#5)"; git -C "$D" push -q origin idd/5-x 2>/dev/null
                 printf '{"t":2}\n' > "$D/.claude/.idd/attachments/issue-5/_manifest.json"; }
s_attachment() { pushed; mkdir -p "$D/.claude/.idd/attachments/issue-5"; printf 'bytes\n' > "$D/.claude/.idd/attachments/issue-5/spec.docx"; }
s_ignored()    { pushed; printf 'build/\n' >> "$D/.git/info/exclude"; mkdir -p "$D/build"; printf 'bin\n' > "$D/build/out.bin"; }
s_nothing()    { :; }
s_unpushed()   { git -C "$D" checkout -q -b idd/5-x; printf 'w\n' > "$D/w.txt"; git -C "$D" add w.txt; git -C "$D" commit -q -m "work (#5)"; }
s_changed()    { pushed; printf 'changed\n' >> "$D/a.txt"; }
s_untracked()  { pushed; printf 'n\n' > "$D/notes.txt"; }
s_stash()      { pushed; printf 'changed\n' >> "$D/a.txt"; git -C "$D" stash -q; }
s_tag_local()  { pushed; git -C "$D" tag idd-5-verified; }
s_tag_pushed() { pushed; git -C "$D" tag idd-5-verified; git -C "$D" push -q origin idd-5-verified 2>/dev/null; }
s_tag_moved()  { pushed; git -C "$D" tag idd-5-verified main; git -C "$D" push -q origin idd-5-verified 2>/dev/null
                 git -C "$D" tag -f idd-5-verified idd/5-x > /dev/null; }   # origin has the tag at another commit
s_worktree()   { pushed; git -C "$D" worktree add -q "$S/second" -b side 2>/dev/null; }
s_edits()      { pushed; printf '%s/\n' "$EDITS" >> "$D/.git/info/exclude"; mkdir -p "$D/$EDITS/edits"; printf 'old text\n' > "$D/$EDITS/edits/c1.md"; }
s_parked()     { pushed; mkdir -p "$D/.git/spectra-app/changes/x"; printf 'p\n' > "$D/.git/spectra-app/changes/x/proposal.md"; }
s_deleted()    { pushed; git -C "$T.origin.git" branch -q -D idd/5-x; }   # pushed, then deleted on origin (as after a squash merge)
s_assume()     { pushed; git -C "$D" update-index --assume-unchanged a.txt; printf 'hidden\n' >> "$D/a.txt"; }
s_skip()       { pushed; git -C "$D" update-index --skip-worktree a.txt; printf 'hidden\n' >> "$D/a.txt"; }
s_index()      { pushed; printf 'not an index' > "$D/.git/index"; }
s_detached()   { git -C "$D" checkout -q --detach; printf 'w\n' > "$D/w.txt"; git -C "$D" add w.txt; git -C "$D" commit -q -m "no branch (#5)"; }
s_routing()    { pushed; mkdir -p "$D/.claude/.idd"; printf '{"n":2}\n{"n":3}\n' > "$D/$ROUTING"; }   # a routing log stays in the directory
# the states of the directory of #5 that the tests make (record leaves each of them as it is)
LEAVE_NAMES="pushed manifest attachment ignored nothing unpushed changed untracked stash tag_local tag_pushed tag_moved worktree edits parked detached deleted assume skip index routing"

leave_row() { # name → record leaves the directory in the state s_<name> as it is, and the run goes on
  local name="$1" OUT rc
  new "leave-$name" 5 9; begin; D=$(dir_of 5); "s_$name"
  python3 "$RQT/treecheck.py" whole "$D" > "$S/dir-before.txt"
  OUT=$(run record --issue 5 --reason x 2> "$S/err"); rc=$?
  assert_exit "record leaves the directory ($name): record exits 0" 0 "$rc"
  python3 "$RQT/treecheck.py" whole "$D" > "$S/dir-after.txt"
  require "record leaves the directory ($name): its files, index, branches, tags and stash are as they were" cmp -s "$S/dir-before.txt" "$S/dir-after.txt"
  assert_eq "record leaves the directory ($name): record prints it" "$D" "$(printf '%s' "$OUT" | jget dir)"
  assert_true "record leaves the directory ($name): no routing log reached the working tree the run was started in" '[ ! -e "$T/$ROUTING" ]'
  assert_eq "record leaves the directory ($name): the following next hands out the next candidate" "9" "$(run next 2> /dev/null | jget next)"
}
leave_rows() { local name; for name in $LEAVE_NAMES; do leave_row "$name"; done; }
person_tree() { # T as a person left it: on wip, with a staged and an unstaged change, an untracked and an ignored file, a stash and a branch
  printf 'local/\n' > "$T/.gitignore"; printf 'c\n' > "$T/c.txt"; git -C "$T" add .gitignore c.txt
  git -C "$T" commit -q -m "more"; git -C "$T" push -q origin main 2>/dev/null
  git -C "$T" branch side; git -C "$T" checkout -q -b wip
  printf 'd\n' > "$T/d.txt"; git -C "$T" add d.txt; git -C "$T" commit -q -m "d"
  printf 'stashed\n' >> "$T/a.txt"; git -C "$T" stash -q
  printf 'staged\n' >> "$T/a.txt"; git -C "$T" add a.txt; printf 'changed\n' >> "$T/c.txt"; printf 'b\n' > "$T/b.txt"
  mkdir -p "$T/local"; printf 'mine\n' > "$T/local/notes.txt"
  touch -t 202001010000 "$T/d.txt"   # the stat of d.txt no longer matches the index: a git status that may write would refresh it
}
