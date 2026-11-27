#!/usr/bin/env bash
# Test: stop-mode-log.py records how a /idd-all verify loop with a stop mode ended (#603).
#
# WHY THIS EXISTS
#
# #595 added three stop modes, but a finished run left nothing to measure: the per-round counts live only in the
# run state (local, read for 24 hours, deleted by the next reset of the same issue) and the run report's
# `stop mode:` line is printed to the conversation only. This suite pins the record that makes the modes
# measurable: what `append` writes and when, what `summary` counts, and that the Phase 4 `next` block of
# skills/idd-all/SKILL.md calls it without letting a failed append change the run.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"

CS="$PLUGIN/scripts/close-stage.py"
LOG="$PLUGIN/scripts/stop-mode-log.py"
SKILL="$PLUGIN/skills/idd-all/SKILL.md"
REPO=octo/demo
T=$(mktemp -d "${TMPDIR:-/tmp}/stop-mode-log.XXXXXX")
trap 'rm -rf "$T"' EXIT

# A run state written by the real init, then given the rounds the gate would have recorded.
# usage: run_state <dir> <issue> <stop mode or none> <rounds as "status:blocking:in_scope,...">
run_state() {
  local dir=$1 n=$2 mode=$3 rounds=$4
  mkdir -p "$dir"
  python3 "$CS" init --cwd "$dir" --repo $REPO --issue "$n" --path PR --requested-path PR --interaction unattended \
    --branch "idd/$n-x" --default main --review no --in-chain no --stop "$mode" >/dev/null || return 1
  python3 - "$dir/.claude/.idd/state/idd-all-run-$n.json" "$rounds" <<'PY'
import json, sys
p, spec = sys.argv[1], sys.argv[2]
st = json.load(open(p))
for i, r in enumerate([x for x in spec.split(",") if x], 1):
    status, blocking, in_scope = r.split(":")
    st["rounds"].append({"round": i, "sha": f"{i:040x}", "status": status, "blocking": int(blocking),
                         "in_scope": int(in_scope), "report_id": 1000 + i, "at": st["created_at"]})
json.dump(st, open(p, "w"))
PY
}
lines() { [ -f "$1" ] && wc -l < "$1" | tr -d ' ' || echo 0; }
append() { # <dir> <issue> <answer json> ; record file in $REC
  IDD_STOP_LOG="$REC" python3 "$LOG" append --cwd "$1" --repo $REPO --issue "$2" --answer "$3"
}

echo "── append: what is written and when"
# spec-example: idd-pr-hitl-modes / what append writes
REC="$T/rec-a.jsonl"
run_state "$T/a1" 11 early "clean:0:0"
append "$T/a1" 11 '{"decision": "stop", "merge": true, "mode": "early", "reason": "clean", "decided": true}'
assert_eq "stop mode early, one round, stop with merge → 1 line" 1 "$(lines "$REC")"
run_state "$T/a2" 12 exhaustive-blocking "not_clean:2:3,not_clean:1:1"
append "$T/a2" 12 '{"decision": "stop", "merge": false, "mode": "exhaustive-blocking", "reason": "no progress", "decided": true}'
assert_eq "exhaustive-blocking, two rounds, stop without merge → 1 more line" 2 "$(lines "$REC")"
run_state "$T/a3" 13 exhaustive-blocking "not_clean:2:0"
append "$T/a3" 13 '{"decision": "fix", "merge": false, "mode": "exhaustive-blocking", "reason": "2 to fix", "decided": true}'
assert_eq "exhaustive-blocking, fix → nothing" 2 "$(lines "$REC")"
run_state "$T/a4" 14 none "clean:0:0"
append "$T/a4" 14 '{"decision": "stop", "merge": true, "mode": null, "reason": "clean", "decided": true}'
assert_eq "no stop mode, stop → nothing" 2 "$(lines "$REC")"
mkdir -p "$T/a5"
append "$T/a5" 15 '{"decision": "stop", "merge": false, "mode": null, "rounds": [], "decided": false}'; RC=$?
assert_eq "no run state, stop undecided → nothing" 2 "$(lines "$REC")"
assert_exit "no run state is not an error of append" 0 "$RC"

# #603 r1: a run another /idd-all replaced (#602) no longer owns the run state; nothing is written for it
run_state "$T/a6" 16 early "clean:0:0"
append "$T/a6" 16 '{"decision": "stop", "merge": false, "mode": "exhaustive-blocking", "reason": "x", "decided": false, "replaced": true}'; RC=$?
assert_eq "a replaced next answer → nothing" 2 "$(lines "$REC")"
assert_exit "… and it is not an error" 0 "$RC"
IDD_STOP_LOG="$REC" python3 "$LOG" append --cwd "$T/a6" --repo $REPO --issue 16 \
  --answer '{"decision": "stop", "merge": false, "mode": "early", "reason": "no round yet", "decided": false}' \
  --gate '{"status": "unparseable", "replaced": true}'; RC=$?
assert_eq "a replaced gate → nothing, even when next's answer has no flag" 2 "$(lines "$REC")"
assert_exit "… and it is not an error" 0 "$RC"
# #603 r2: an empty --gate means the gate's answer was lost (another Bash call); it fails closed
ERR=$(IDD_STOP_LOG="$REC" python3 "$LOG" append --cwd "$T/a6" --repo $REPO --issue 16 \
  --answer '{"decision": "stop", "merge": false, "mode": "early", "reason": "no round yet", "decided": false}' --gate '' 2>&1); RC=$?
assert_eq "an empty --gate → nothing" 2 "$(lines "$REC")"
assert_exit "… exit 0" 0 "$RC"
assert_grep "… and says why" "gate's answer" "$ERR"
# #603 r3: a gate answer that is not a JSON object, or is from another round, fails closed the same way
for G in 'garbage' '"replaced"' '[{"replaced": true}]' '{"status": "unparseable", "replaced": true' 'null'; do
  ERR=$(IDD_STOP_LOG="$REC" python3 "$LOG" append --cwd "$T/a6" --repo $REPO --issue 16 \
    --answer '{"decision": "stop", "merge": false, "mode": "early", "reason": "x", "decided": false}' --gate "$G" 2>&1)
  assert_eq "a gate answer that is not an object ($G) → nothing" 2 "$(lines "$REC")"
  assert_grep "… and says why ($G)" "gate's answer" "$ERR"
done
ERR=$(IDD_STOP_LOG="$REC" python3 "$LOG" append --cwd "$T/a6" --repo $REPO --issue 16 \
  --answer '{"decision": "stop", "merge": true, "mode": "early", "reason": "clean", "decided": true, "round": 2}' \
  --gate '{"status": "clean", "round": 1}' 2>&1)
assert_eq "a gate answer from another round → nothing" 2 "$(lines "$REC")"
assert_grep "… and says why" "round" "$ERR"
# … but only where a line would have been written: a fix answer or a run with no stop mode says nothing
ERR=$(IDD_STOP_LOG="$REC" python3 "$LOG" append --cwd "$T/a3" --repo $REPO --issue 13 \
  --answer '{"decision": "fix", "merge": false, "mode": "exhaustive-blocking", "reason": "2 to fix", "decided": true}' --gate '' 2>&1)
assert_eq "a fix answer with an empty gate prints nothing" "" "$ERR"
ERR=$(IDD_STOP_LOG="$REC" python3 "$LOG" append --cwd "$T/a4" --repo $REPO --issue 14 \
  --answer '{"decision": "stop", "merge": true, "mode": null, "reason": "clean", "decided": true}' --gate '' 2>&1)
assert_eq "a run with no stop mode and an empty gate prints nothing" "" "$ERR"

L2=$(sed -n 2p "$REC" 2>/dev/null)
assert_grep "the line names the repo" '"repo": "octo/demo"' "$L2"
assert_grep "… the issue" '"issue": 12' "$L2"
assert_grep "… the mode" '"mode": "exhaustive-blocking"' "$L2"
assert_grep "… the decision" '"decision": "stop"' "$L2"
assert_grep "… next's merge answer" '"next_merge": false' "$L2"
assert_grep "… decided" '"decided": true' "$L2"
assert_grep "… the reason" '"reason": "no progress"' "$L2"
assert_grep "… each round's report id" '"report_id": 1002' "$L2"
assert_grep "… each round's Blocking count" '"blocking": 1' "$L2"
assert_grep "… the run's created_at" '"created_at": "' "$L2"

# an undecided stop of a run whose state is readable is recorded with decided false
run_state "$T/a7" 17 early "unparseable:0:0"
REC="$T/rec-und.jsonl" append "$T/a7" 17 '{"decision": "stop", "merge": false, "mode": "early", "reason": "gate unparseable", "decided": false}'
assert_grep "an undecided stop is recorded with decided false" '"decided": false' "$(cat "$T/rec-und.jsonl" 2>/dev/null)"

echo "── summary: the last line per run"
# A run asked twice is one run
append "$T/a2" 12 '{"decision": "stop", "merge": false, "mode": "exhaustive-blocking", "reason": "no progress", "decided": true}'
assert_eq "the same run appended again → 3 lines" 3 "$(lines "$REC")"
SUM=$(IDD_STOP_LOG="$REC" python3 "$LOG" summary --json); RC=$?
assert_exit "summary exits 0" 0 "$RC"
assert_eq "summary: exhaustive-blocking has one run" 1 "$(printf '%s' "$SUM" | jq -r '.modes["exhaustive-blocking"].runs')"
assert_eq "summary: … with to-fix 5 → 2" "5 → 2" "$(printf '%s' "$SUM" | jq -r '.modes["exhaustive-blocking"].to_fix[0]')"
assert_eq "summary: … and no merge answer" 0 "$(printf '%s' "$SUM" | jq -r '.modes["exhaustive-blocking"].next_merge')"
assert_eq "summary: early has one merge answer" 1 "$(printf '%s' "$SUM" | jq -r '.modes.early.next_merge')"
assert_eq "summary: the JSON has no merged count" null "$(printf '%s' "$SUM" | jq -r '.modes.early.merged')"
TXT=$(IDD_STOP_LOG="$REC" python3 "$LOG" summary)
assert_grep "summary text names each mode" "exhaustive-blocking" "$TXT"
assert_grep "summary text says next answered merge" "next answered merge in 1" "$TXT"
refute_grep "summary text does not claim a merge" " merged" "$TXT"
EMPTY=$(IDD_STOP_LOG="$T/none.jsonl" python3 "$LOG" summary --json); RC=$?
assert_exit "summary of a missing record exits 0" 0 "$RC"
assert_eq "… and counts no run" 0 "$(printf '%s' "$EMPTY" | jq -r '[.modes[].runs] | add // 0')"

echo "── the record file and odd lines"
# #603 r1: the record is the user's own: 0600, and a symbolic link at its path is not followed
REC="$T/rec-m.jsonl"
run_state "$T/m1" 31 early "clean:0:0"
append "$T/m1" 31 '{"decision": "stop", "merge": true, "mode": "early", "reason": "clean", "decided": true}'
# python reads the mode the same on GNU and BSD (`stat -f` means something else on GNU, #603 r2)
assert_eq "a new record file is 0600" 600 "$(python3 -c 'import os,sys; print(format(os.stat(sys.argv[1]).st_mode & 0o777, "o"))' "$REC")"
echo target > "$T/target.txt"; ln -s "$T/target.txt" "$T/rec-link.jsonl"
REC="$T/rec-link.jsonl" append "$T/m1" 31 '{"decision": "stop", "merge": true, "mode": "early", "reason": "clean", "decided": true}' 2>/dev/null; RC=$?
assert_exit "a symbolic link at the record path is refused" 1 "$RC"
assert_eq "… and its target is untouched" target "$(cat "$T/target.txt")"
# lines that parse as JSON but have the wrong shape are counted as unreadable, not a crash
REC="$T/rec-odd.jsonl"
cp "$T/rec-m.jsonl" "$REC"
printf '%s\n' '{"repo": "x", "issue": 1, "created_at": "t"}' '{"repo": "x", "issue": 2, "created_at": "t", "mode": "early", "rounds": {"a": 1}}' \
  '{"repo": ["x"], "issue": 3, "created_at": "t", "mode": "early", "rounds": []}' \
  '{"repo": "x", "issue": 4, "created_at": "t", "mode": "early", "rounds": [], "reason": {"a": 1}}' \
  '{"repo": "x", "issue": 6, "created_at": "t", "mode": "early", "rounds": [1, "x"]}' >> "$REC"
printf '\377\376 not utf-8\n' >> "$REC"
SUM=$(IDD_STOP_LOG="$REC" python3 "$LOG" summary --json); RC=$?
assert_exit "summary --json survives odd lines" 0 "$RC"
assert_eq "… and counts them as unreadable (wrong shape, rounds of non-objects, not UTF-8)" 6 "$(printf '%s' "$SUM" | jq -r '.unreadable_lines')"
IDD_STOP_LOG="$REC" python3 "$LOG" summary >/dev/null; RC=$?
assert_exit "summary text survives odd lines" 0 "$RC"
# a reason with a terminal control sequence is printed escaped
REC="$T/rec-esc.jsonl"
printf '%s\n' '{"repo": "x", "issue": 5, "created_at": "t", "mode": "early\u001b[31m", "rounds": [{"to_fix": "\u001b]0;t\u0007"}], "reason": "a\u001b[2Jb\u009bc"}' > "$REC"
TXT=$(IDD_STOP_LOG="$REC" python3 "$LOG" summary)
assert_eq "no ESC byte reaches the terminal (reason, mode, to-fix)" 0 "$(printf '%s' "$TXT" | LC_ALL=C grep -c $'\x1b')"
assert_eq "… nor a C1 control (U+009B)" 0 "$(printf '%s' "$TXT" | LC_ALL=C grep -c $'\xc2\x9b')"
assert_grep "the mode is printed, escaped" 'early\x1b[31m' "$TXT"
assert_grep "the to-fix sequence is printed, escaped" 'to-fix \x1b]0;t\x07' "$TXT"
assert_grep "the reason is printed, escaped" 'a\x1b[2Jb\x9bc' "$TXT"
# a last line without its newline does not swallow the next line appended
REC="$T/rec-nl.jsonl"
printf '%s' '{"repo": "x", "issue": 7, "created_at": "t", "mode": "early", "rounds": []}' > "$REC"
append "$T/m1" 31 '{"decision": "stop", "merge": true, "mode": "early", "reason": "clean", "decided": true}'
SUM=$(IDD_STOP_LOG="$REC" python3 "$LOG" summary --json)
assert_eq "both lines are read" "0 2" "$(printf '%s' "$SUM" | jq -r '"\(.unreadable_lines) \(.modes.early.runs)"')"
# the default record path, when IDD_STOP_LOG is not set
DH="$T/home"; mkdir -p "$DH"
env -u IDD_STOP_LOG HOME="$DH" python3 "$LOG" append --cwd "$T/m1" --repo $REPO --issue 31 \
  --answer '{"decision": "stop", "merge": true, "mode": "early", "reason": "clean", "decided": true}' --gate '{"status": "clean"}'
assert_eq "without IDD_STOP_LOG the record is ~/.claude/.idd/stop-mode-runs.jsonl" 1 "$(lines "$DH/.claude/.idd/stop-mode-runs.jsonl")"
# append writes no bytecode into the plugin directory
NB="$T/nobyte"; mkdir -p "$NB/scripts"; cp "$LOG" "$CS" "$NB/scripts/"; cp -R "$PLUGIN/scripts/lib" "$NB/scripts/lib"
find "$NB" -name __pycache__ -prune -exec rm -rf {} +
IDD_STOP_LOG="$T/rec-nb.jsonl" python3 "$NB/scripts/stop-mode-log.py" append --cwd "$T/m1" --repo $REPO --issue 31 \
  --answer '{"decision": "stop", "merge": true, "mode": "early", "reason": "clean", "decided": true}'
assert_eq "append leaves no __pycache__" 0 "$(find "$NB" -name __pycache__ | wc -l | tr -d ' ')"

echo "── the Phase 4 next block of idd-all"
# The fenced bash block that runs `next` (not the --read-only one of Phase 5c).
BLOCK="$T/next-block.sh"
awk '/^```bash$/{inb=1; buf=""; next} /^```$/ && inb {inb=0; if (buf ~ /NEXT_JSON=\$\(python3/) {printf "%s", buf; exit} next} inb {buf = buf $0 "\n"}' \
  "$SKILL" > "$BLOCK"
assert_grep "the next block was found" 'close-stage.py" next' "$(cat "$BLOCK")"
assert_grep "the next block calls stop-mode-log append" 'stop-mode-log.py" append' "$(cat "$BLOCK")"
assert_grep "… with the gate file" '--gate-file "$CWD/.claude/.idd/state/idd-all-gate-$N.json"' "$(cat "$BLOCK")"
# #603 r3: the gate block keeps its answer in a file, which survives the Bash call (a variable does not)
GBLOCK=$(awk '/^```bash$/{inb=1; buf=""; next} /^```$/ && inb {inb=0; if (buf ~ /GATE_JSON=\$\(python3/) {printf "%s", buf; exit} next} inb {buf = buf $0 "\n"}' "$SKILL")
# spec-example: idd-pr-hitl-modes / the gate block has the gate write its answer
# #623: the gate writes the file itself, through close-stage's guards; the block has no shell redirect to it
assert_grep "the gate block asks the gate to write its answer" 'gate --cwd "$CWD" --repo "$GITHUB_REPO" --issue "$N" --sha "$HEAD_SHA" "${GATE_BASE[@]}" --write-answer yes' "$GBLOCK"
assert_eq "… and does not redirect into the gate file" 0 "$(printf '%s' "$GBLOCK" | grep -c '> *"$CWD/.claude/.idd/state/idd-all-gate')"

# spec-example: idd-pr-hitl-modes / append reads only this issue's gate file and never through a symbolic link
run_state "$T/g1" 41 exhaustive-blocking "not_clean:0:1"
GA='{"decision": "stop", "merge": false, "mode": "exhaustive-blocking", "reason": "x", "decided": true}'
GD="$T/g1/.claude/.idd/state"
printf '%s\n' '{"status": "not_clean", "blocking": 0}' > "$T/planted.json"
ln -sf "$T/planted.json" "$GD/idd-all-gate-41.json"
OUT=$(IDD_STOP_LOG="$T/rec-g1.jsonl" python3 "$LOG" append --cwd "$T/g1" --repo $REPO --issue 41 --answer "$GA" \
  --gate-file "$GD/idd-all-gate-41.json" 2>&1)
assert_eq "a gate file that is a symbolic link: no record" 0 "$(lines "$T/rec-g1.jsonl")"
assert_grep "… and append says it cannot be read" "cannot be read" "$OUT"
rm -f "$GD/idd-all-gate-41.json"
OUT=$(IDD_STOP_LOG="$T/rec-g1.jsonl" python3 "$LOG" append --cwd "$T/g1" --repo $REPO --issue 41 --answer "$GA" \
  --gate-file "$T/planted.json" 2>&1)
assert_eq "a gate file outside the state directory: no record" 0 "$(lines "$T/rec-g1.jsonl")"
assert_grep "… and append says it is not this issue's gate file" "is not this issue's gate file" "$OUT"
printf '%s\n' '{"status": "not_clean", "blocking": 0}' > "$GD/idd-all-gate-42.json"
OUT=$(IDD_STOP_LOG="$T/rec-g1.jsonl" python3 "$LOG" append --cwd "$T/g1" --repo $REPO --issue 41 --answer "$GA" \
  --gate-file "$GD/idd-all-gate-42.json" 2>&1)
assert_eq "another issue's gate file: no record" 0 "$(lines "$T/rec-g1.jsonl")"
mkdir "$GD/idd-all-gate-41.json"
OUT=$(IDD_STOP_LOG="$T/rec-g1.jsonl" python3 "$LOG" append --cwd "$T/g1" --repo $REPO --issue 41 --answer "$GA" \
  --gate-file "$GD/idd-all-gate-41.json" 2>&1)
assert_eq "a directory at the gate file: no record" 0 "$(lines "$T/rec-g1.jsonl")"
rmdir "$GD/idd-all-gate-41.json"
printf '%s\n' '{"status": "not_clean", "blocking": 0}' > "$GD/idd-all-gate-41.json"
OUT=$(IDD_STOP_LOG="$T/rec-g1.jsonl" python3 "$LOG" append --cwd "$T/g1" --repo $REPO --issue 41 --answer "$GA" \
  --gate-file "$GD/idd-all-gate-41.json" 2>&1)
assert_eq "this issue's regular gate file: the record is written" 1 "$(lines "$T/rec-g1.jsonl")"

# A plugin root whose close-stage.py prints a fixed answer when run, and is the real module when imported.
ROOT="$T/root"; mkdir -p "$ROOT/scripts"
cp "$LOG" "$ROOT/scripts/stop-mode-log.py"
cp -R "$PLUGIN/scripts/lib" "$ROOT/scripts/lib"          # stop-mode-log reads stopmode from its own lib/
cat > "$ROOT/scripts/close-stage.py" <<'PY'
import importlib.util, os, sys
_spec = importlib.util.spec_from_file_location("real_close_stage", os.environ["REAL_CS"])
_m = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(_m)
globals().update({k: v for k, v in vars(_m).items() if not k.startswith("__")})
if __name__ == "__main__":
    print(os.environ["FAKE_ANSWER"]); sys.exit(int(os.environ.get("FAKE_RC", "0")))
PY
run_block() { # <cwd> <issue> <record path> ; prints the block's output then "RC=<rc> NEXT_RC=<rc> NEXT_JSON=<json>"
  # the gate block's file: GATE_FILE_JSON's value when it is set, no file when it is not
  local gf="$1/.claude/.idd/state/idd-all-gate-$2.json"
  if [ "${GATE_FILE_JSON+x}" ]; then printf '%s\n' "$GATE_FILE_JSON" > "$gf"; else rm -f "$gf"; fi
  ( cd "$T" && CLAUDE_PLUGIN_ROOT="$ROOT" REAL_CS="$CS" IDD_STOP_LOG="$3" CWD="$1" GITHUB_REPO=$REPO N="$2" \
      bash -c "$(cat "$BLOCK")"'
      echo "RC=$? NEXT_RC=$NEXT_RC NEXT_JSON=$NEXT_JSON"' 2>&1 )
}
run_state "$T/b1" 21 exhaustive-blocking "not_clean:0:1"
ANS='{"decision": "stop", "merge": false, "mode": "exhaustive-blocking", "reason": "coverage", "decided": true}'
GOK='{"status": "not_clean", "blocking": 0}'        # the gate's answer, as the gate block leaves it
OUT=$(GATE_FILE_JSON="$GOK" FAKE_ANSWER="$ANS" run_block "$T/b1" 21 "$T/rec-b.jsonl")
assert_eq "the block writes the record" 1 "$(lines "$T/rec-b.jsonl")"
assert_grep "the block keeps next's answer" "NEXT_RC=0 NEXT_JSON=$ANS" "$OUT"
# spec scenario: A failed append does not change the run
mkdir -p "$T/ro"; chmod 500 "$T/ro"
OUT=$(GATE_FILE_JSON="$GOK" FAKE_ANSWER="$ANS" run_block "$T/b1" 21 "$T/ro/sub/rec.jsonl")
assert_grep "a failed append prints a warning" "stop-mode record was not written" "$OUT"
assert_grep "… and leaves NEXT_JSON and NEXT_RC as next answered" "NEXT_RC=0 NEXT_JSON=$ANS" "$OUT"
assert_grep "… and the block ends as before" "RC=0 " "$OUT"
chmod 700 "$T/ro"
# #603 r3: the block with no gate file writes nothing and says so; a shell that lost GATE_JSON does not matter
OUT=$(GATE_JSON= FAKE_ANSWER="$ANS" run_block "$T/b1" 21 "$T/rec-lost.jsonl")
assert_eq "no gate file: the block writes no record" 0 "$(lines "$T/rec-lost.jsonl")"
assert_grep "… says the gate's answer is missing" "gate's answer" "$OUT"
assert_grep "… and keeps next's answer" "NEXT_RC=0 NEXT_JSON=$ANS" "$OUT"
# #603 r1: the block hands the gate's answer to append, so a replaced gate writes nothing
OUT=$(GATE_FILE_JSON='{"status": "unparseable", "replaced": true}' FAKE_ANSWER="$ANS" run_block "$T/b1" 21 "$T/rec-g.jsonl")
assert_eq "a replaced gate: the block writes no record" 0 "$(lines "$T/rec-g.jsonl")"
assert_grep "… and keeps next's answer" "NEXT_RC=0 NEXT_JSON=$ANS" "$OUT"
UND='{"decision": "stop", "merge": false, "mode": "exhaustive-blocking", "reason": "x", "decided": false}'
OUT=$(FAKE_ANSWER="$UND" FAKE_RC=3 run_block "$T/b1" 21 "$T/rec-c.jsonl")
assert_grep "an undecided next keeps NEXT_RC 3" "NEXT_RC=3 " "$OUT"

print_summary
