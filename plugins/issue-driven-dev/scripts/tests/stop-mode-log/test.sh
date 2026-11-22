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

L2=$(sed -n 2p "$REC" 2>/dev/null)
assert_grep "the line names the repo" '"repo": "octo/demo"' "$L2"
assert_grep "… the issue" '"issue": 12' "$L2"
assert_grep "… the mode" '"mode": "exhaustive-blocking"' "$L2"
assert_grep "… the decision and next's merge answer" '"next_merge": false' "$L2"
assert_grep "… the reason" '"reason": "no progress"' "$L2"
assert_grep "… each round's report id" '"report_id": 1002' "$L2"
assert_grep "… each round's Blocking count" '"blocking": 1' "$L2"
assert_grep "… the run's created_at" '"created_at": "' "$L2"

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

echo "── the Phase 4 next block of idd-all"
# The fenced bash block that runs `next` (not the --read-only one of Phase 5c).
BLOCK="$T/next-block.sh"
awk '/^```bash$/{inb=1; buf=""; next} /^```$/ && inb {inb=0; if (buf ~ /NEXT_JSON=\$\(python3/) {printf "%s", buf; exit} next} inb {buf = buf $0 "\n"}' \
  "$SKILL" > "$BLOCK"
assert_grep "the next block was found" 'close-stage.py" next' "$(cat "$BLOCK")"
assert_grep "the next block calls stop-mode-log append" 'stop-mode-log.py" append' "$(cat "$BLOCK")"

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
  ( cd "$T" && CLAUDE_PLUGIN_ROOT="$ROOT" REAL_CS="$CS" IDD_STOP_LOG="$3" CWD="$1" GITHUB_REPO=$REPO N="$2" \
      bash -c "$(cat "$BLOCK")"'
      echo "RC=$? NEXT_RC=$NEXT_RC NEXT_JSON=$NEXT_JSON"' 2>&1 )
}
run_state "$T/b1" 21 exhaustive-blocking "not_clean:0:1"
ANS='{"decision": "stop", "merge": false, "mode": "exhaustive-blocking", "reason": "coverage", "decided": true}'
OUT=$(FAKE_ANSWER="$ANS" run_block "$T/b1" 21 "$T/rec-b.jsonl")
assert_eq "the block writes the record" 1 "$(lines "$T/rec-b.jsonl")"
assert_grep "the block keeps next's answer" "NEXT_RC=0 NEXT_JSON=$ANS" "$OUT"
# spec scenario: A failed append does not change the run
mkdir -p "$T/ro"; chmod 500 "$T/ro"
OUT=$(FAKE_ANSWER="$ANS" run_block "$T/b1" 21 "$T/ro/sub/rec.jsonl")
assert_grep "a failed append prints a warning" "stop-mode record was not written" "$OUT"
assert_grep "… and leaves NEXT_JSON and NEXT_RC as next answered" "NEXT_RC=0 NEXT_JSON=$ANS" "$OUT"
assert_grep "… and the block ends as before" "RC=0 " "$OUT"
chmod 700 "$T/ro"
UND='{"decision": "stop", "merge": false, "mode": "exhaustive-blocking", "reason": "x", "decided": false}'
OUT=$(FAKE_ANSWER="$UND" FAKE_RC=3 run_block "$T/b1" 21 "$T/rec-c.jsonl")
assert_grep "an undecided next keeps NEXT_RC 3" "NEXT_RC=3 " "$OUT"

print_summary
