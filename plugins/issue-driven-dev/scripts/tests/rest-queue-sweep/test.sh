#!/usr/bin/env bash
# rest-queue-sweep suite (#478) — the checks of rest-queue.py that run it many hundred times:
#   - `record`, ended after each of its steps and run again, comes to the end an undisturbed record comes to, for
#     every state the directory of an issue can be in (../rest-queue/lib.sh), and leaves that directory as it was;
#   - `next`, ended after each of its steps and run again, hands out the same issue in a directory of its own, or
#     records it as stopped when the end came after it took the place of the directory and before it moved the clone
#     there; it leaves the working tree it was started in as it was, and every temporary folder it leaves is recorded.
# The points are between the commands and the writes of the helper (step() in rest-queue.py): a clone is ended after
# git has returned, not while it runs. What a clone that fails while it runs does is in the rest-queue suite
# (example "a clone that fails touches only its temporary folder").
# It is a suite of its own so that the rest-queue suite stays within a few minutes.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
. "$HERE/../rest-queue/lib.sh"   # RQ, WORK, the scenario helpers and the states of a directory

outcome() { # → what a record comes to: the directory, the attempt (without its times), the routing log and the listing of T
  printf 'directory: %s\n' "$([ -e "$D" ] && echo there || echo gone)"
  python3 -c '
import json, sys
a = [x for x in json.load(open(sys.argv[1]))["attempts"] if x["issue"] == 5][0]
for k in ("handed_at", "recorded_at", "at"):
    a.pop(k, None)
print("attempt:", json.dumps(a, sort_keys=True, ensure_ascii=False))' "$(state_file)"
  printf 'routing: %s\n' "$(cat "$T/$ROUTING" 2>/dev/null | paste -sd'|' -)"
  if [ -d "$D/.git" ]; then echo "the directory:"; python3 "$RQT/treecheck.py" whole "$D"; fi   # every file, .git included, refs and stash
  python3 "$RQT/treecheck.py" list "$T"
}

sweep_record() { # name → every point of record, for the state of the directory that s_<name> makes
  local name="$1" steps k bad=0
  new "sw-$name" 5 9; begin; D=$(dir_of 5); "s_$name"
  snap "sw-$name"
  IDD_REST_COUNT_STEPS="$S/steps" run record --issue 5 --reason x > /dev/null 2>&1
  outcome > "$WORK/want-$name.txt"; steps=$(cat "$S/steps")
  for k in $(seq 1 "$steps"); do
    restore "sw-$name"
    IDD_REST_STOP_AFTER_STEP=$k run record --issue 5 --reason x > /dev/null 2>&1
    [ "$?" = 99 ] || { bad=$((bad + 1)); echo "    $name: point $k: the first record was not ended there"; continue; }
    run record --issue 5 --reason x > /dev/null 2>&1 || { bad=$((bad + 1)); echo "    $name: point $k: the second record failed"; continue; }
    outcome > "$WORK/got-$name.txt"
    if ! cmp -s "$WORK/want-$name.txt" "$WORK/got-$name.txt"; then
      bad=$((bad + 1)); echo "    $name: point $k:"; diff "$WORK/want-$name.txt" "$WORK/got-$name.txt" | sed -n 1,6p
    fi
  done
  assert_eq "record ($name): at each of its $steps points, ended there and run again, it comes to the same end" "0" "$bad"
  assert_true "record ($name): it has at least three points" "[ $steps -ge 3 ]"
  POINTS=$((POINTS + steps))
}
POINTS=0
for name in $LEAVE_NAMES; do sweep_record "$name"; done
assert_true "record: over more than 60 points in all" "[ $POINTS -gt 60 ]"

# next, ended after each of its steps and run again
new sw-next 5 9; run start --path PR --review no > /dev/null 2>&1; D=$(dir_of 5)
python3 "$RQT/treecheck.py" list "$T" > "$WORK/next-before.txt"
snap sw-next
IDD_REST_COUNT_STEPS="$S/steps" run next > /dev/null 2>&1; STEPS=$(cat "$S/steps"); bad=0; LEFT_SEEN=0; TMP_SEEN=0
for k in $(seq 1 "$STEPS"); do
  restore sw-next
  IDD_REST_STOP_AFTER_STEP=$k run next > /dev/null 2>&1
  [ "$?" = 99 ] || { bad=$((bad + 1)); echo "    next: point $k: the first next was not ended there"; continue; }
  OUT=$(run next 2> /dev/null)
  python3 "$RQT/treecheck.py" list "$T" > "$WORK/next-after.txt"
  # the two outcomes of the example "a directory that was not finished": nothing was at the place, so #5 is made
  # again; or the clone was ended part of the way, so #5 is recorded as stopped, its folder is left, and #9 is handed out
  got="$(printf '%s' "$OUT" | jget next)|$(printf '%s' "$OUT" | jget dir)|$(attempt 5 made)|$(git -C "$D" symbolic-ref --short HEAD 2>/dev/null)"
  here=$(cd "$D" 2>/dev/null && python3 "$RQ" here --cwd "$D" --repo "$REPO" --issue 5 --token "$(token_of 5)" > /dev/null 2>&1; echo $?)
  D9=$(dir_of 9)
  here9=$(cd "$D9" 2>/dev/null && python3 "$RQ" here --cwd "$D9" --repo "$REPO" --issue 9 --token "$(token_of 9)" > /dev/null 2>&1; echo $?)
  made="5|$D|true|main|0"
  left="9|$D9|stopped|$D|0"
  [ "$got|$here" = "$made" ] && outcome="$made" || outcome="$(printf '%s' "$OUT" | jget next)|$(printf '%s' "$OUT" | jget dir)|$(attempt 5 outcome)|$([ -e "$D" ] && printf '%s' "$D")|$here9"
  if { [ "$outcome" != "$made" ] && [ "$outcome" != "$left" ]; } || ! python3 "$RQT/treecheck.py" same "$WORK/next-before.txt" "$WORK/next-after.txt"; then
    bad=$((bad + 1)); echo "    next: point $k: $outcome"
  fi
  [ "$outcome" = "$left" ] && LEFT_SEEN=$((LEFT_SEEN + 1))
  # every temporary folder that is still there is recorded with #5, so that the report names it
  unrecorded=$(python3 - "$(state_file)" "$T/.claude/worktrees" <<'SWEEP_PY'
import json, os, sys
a = [x for x in json.load(open(sys.argv[1]))["attempts"] if x["issue"] == 5][0]
left = [os.path.join(sys.argv[2], n) for n in os.listdir(sys.argv[2]) if n.startswith(".rest-5-")]
print(len(left), sum(1 for p in left if p not in a.get("tmps", [])))
SWEEP_PY
)
  [ "${unrecorded#* }" = 0 ] || { bad=$((bad + 1)); echo "    next: point $k: a temporary folder that is not recorded"; }
  [ "${unrecorded% *}" -gt 0 ] && TMP_SEEN=$((TMP_SEEN + 1))
done
# spec-example: idd-all-rest / a directory that was not finished
assert_eq "next: at each of its $STEPS points, ended there and run again, it makes #5 again or leaves the place it took and hands out #9, leaves T as it was, and records every temporary folder it leaves" "0" "$bad"
assert_true "next: some points end after it took the place and before it moved the clone there, and there the place is left" "[ $LEFT_SEEN -gt 0 ]"
assert_true "next: some points leave a temporary folder, which is recorded" "[ $TMP_SEEN -gt 0 ]"
assert_true "next: it has more than five points" "[ $STEPS -gt 5 ]"

print_summary "rest-queue-sweep"
