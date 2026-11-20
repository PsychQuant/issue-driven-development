#!/usr/bin/env bash
# rest-queue-sweep suite (#478) — the checks of rest-queue.py that run it many hundred times:
#   - `record`, ended after each of its steps and run again, comes to the end an undisturbed record comes to, for
#     every state the directory of an issue can be in (the rows of ../rest-queue/lib.sh) and for the routing log;
#   - `next`, ended after each of its steps and run again, hands out the same issue in a directory of its own, and
#     leaves the working tree it was started in as it was.
# It is a suite of its own so that the rest-queue suite stays within a few minutes.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
. "$HERE/../rest-queue/lib.sh"   # RQ, WORK, the scenario helpers and the states of a directory

outcome() { # → what a record comes to: the directory, the attempt (without its times), the routing log and the listing of T
  printf 'directory: %s\n' "$([ -e "$D" ] && echo there || echo gone)"
  printf 'pointer: %s\n' "$([ -e "$D/$POINTER" ] && echo there || echo gone)"
  python3 -c '
import json, sys
a = [x for x in json.load(open(sys.argv[1]))["attempts"] if x["issue"] == 5][0]
for k in ("handed_at", "recorded_at", "at"):
    a.pop(k, None)
print("attempt:", json.dumps(a, sort_keys=True, ensure_ascii=False))' "$(state_file)"
  printf 'routing: %s\n' "$(cat "$T/$ROUTING" 2>/dev/null | paste -sd'|' -)"
  python3 "$RQT/treecheck.py" list "$T"
}

# spec-example: idd-all-rest / record ended part of the way comes to the same end
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
  assert_true "record ($name): it has more than five points" "[ $steps -gt 5 ]"
  POINTS=$((POINTS + steps))
}
POINTS=0
while IFS='|' read -r name want needle; do sweep_record "$name"; done <<< "$LEAVE_ROWS"
sweep_record routing
assert_true "record: over more than 150 points in all" "[ $POINTS -gt 150 ]"

# next, ended after each of its steps and run again
new sw-next 5 9; run start --path PR --review no > /dev/null 2>&1; D=$(dir_of 5)
python3 "$RQT/treecheck.py" list "$T" > "$WORK/next-before.txt"
snap sw-next
IDD_REST_COUNT_STEPS="$S/steps" run next > /dev/null 2>&1; STEPS=$(cat "$S/steps"); bad=0
for k in $(seq 1 "$STEPS"); do
  restore sw-next
  IDD_REST_STOP_AFTER_STEP=$k run next > /dev/null 2>&1
  [ "$?" = 99 ] || { bad=$((bad + 1)); echo "    next: point $k: the first next was not ended there"; continue; }
  OUT=$(run next 2> /dev/null)
  python3 "$RQT/treecheck.py" list "$T" > "$WORK/next-after.txt"
  got="$(printf '%s' "$OUT" | jget next)|$(printf '%s' "$OUT" | jget dir)|$(attempt 5 made)|$(git -C "$D" symbolic-ref --short HEAD 2>/dev/null)"
  here=$(python3 "$RQ" here --cwd "$D" --repo "$REPO" --issue 5 > /dev/null 2>&1; echo $?)
  if [ "$got|$here" != "5|$D|true|main|0" ] || ! python3 "$RQT/treecheck.py" same "$WORK/next-before.txt" "$WORK/next-after.txt"; then
    bad=$((bad + 1)); echo "    next: point $k: $got|here $here"
  fi
done
assert_eq "next: at each of its $STEPS points, ended there and run again, it hands out #5 in a directory of its own and leaves T as it was" "0" "$bad"
assert_true "next: it has more than five points" "[ $STEPS -gt 5 ]"

print_summary "rest-queue-sweep"
