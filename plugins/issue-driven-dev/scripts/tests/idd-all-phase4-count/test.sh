#!/usr/bin/env bash
# Test: the Phase 4 round count of /idd-all when next cannot decide, and the stop on a replaced run (#602 verify r1).
#
# WHY THIS EXISTS
#
# Phase 4's fix loop is prose that the model runs, so no suite exercised it. Round 1 of #602's verify found three
# defects in it that the close-stage suite could not see: when the first gate could not write the record, Phase 4
# counted that round itself, then took next's count back on the following round (next counts only recorded
# rounds). A write that kept failing looped without a limit; a write that failed once gave a third verify round
# that could merge. And a run whose state another /idd-all replaced took the same fallback and went on fixing.
#
# The two blocks of skills/idd-all/SKILL.md between `# >>> phase4-replaced` / `# <<< phase4-replaced` and
# `# >>> phase4-count` / `# <<< phase4-count` are run here as Python, round by round, with next's answers given.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"
SKILL="${PHASE4_SKILL:-$PLUGIN/skills/idd-all/SKILL.md}"   # override only to check the test against another text

run() { # scenario-name → prints one line per round: decision,round,merge — or ABORT
  python3 - "$SKILL" "$1" <<'PY'
import re, sys, textwrap
skill, name = sys.argv[1:]
text = open(skill, encoding="utf-8").read()
def block(tag):
    m = re.search(rf"^[ \t]*# >>> {tag}\n(.*?)^[ \t]*# <<< {tag}\n", text, re.S | re.M)
    if not m:
        sys.exit(f"no {tag} block")
    return textwrap.dedent(m.group(1))
replaced, count = block("phase4-replaced"), block("phase4-count")
undecided = {"decision": "stop", "merge": False, "round": 0, "limit": 2, "decided": False}
scenarios = {
    # the gate can never write the record: next stays at round 0, undecided
    "always-undecided": [(dict(undecided), {})] * 5,
    # round 1 unrecorded, rounds 2 and 3 recorded (3 would be clean)
    "once-undecided": [(dict(undecided), {}),
                       ({"decision": "fix", "merge": False, "round": 1, "limit": 2, "decided": True}, {}),
                       ({"decision": "stop", "merge": True, "round": 2, "limit": 2, "decided": True}, {})],
    # round 1 unrecorded, round 2 recorded and clean
    "once-undecided-then-clean": [(dict(undecided), {}),
                                  ({"decision": "stop", "merge": True, "round": 1, "limit": 2, "decided": True}, {})],
    # every round recorded: Phase 4 takes next's answer as it is
    "recorded": [({"decision": "fix", "merge": False, "round": 1, "limit": 2, "decided": True}, {}),
                 ({"decision": "stop", "merge": True, "round": 2, "limit": 2, "decided": True}, {})],
    # the gate says the run state was replaced
    "replaced-gate": [(dict(undecided), {"replaced": True})],
    # next says the run state was replaced
    "replaced-next": [(dict(undecided, replaced=True), {})],
}
class Abort(Exception):
    pass
def abort_with_message(msg):
    raise Abort(msg)
env = {"ROUND": 0, "FALLBACK": False, "INTERACTION": "unattended", "abort_with_message": abort_with_message}
for nxt, gate in scenarios[name]:
    env["nxt"], env["gate"] = nxt, gate
    try:
        exec(replaced, env)
    except Abort:
        print("ABORT"); break
    exec(count, env)
    n = env["nxt"]
    print(f"{n['decision']},{n['round']},{n.get('merge')}")
    if n["decision"] != "fix":
        break
PY
}

# spec-example: idd-pr-hitl-modes / rounds after an undecided next
echo "── an undecided next: Phase 4 keeps its own count"
assert_eq "a write that keeps failing stops at round 2" "$(printf 'fix,1,False\nstop,2,False')" "$(run always-undecided)"
assert_eq "one unrecorded round: round 2 is the last, and it does not merge" "$(printf 'fix,1,False\nstop,2,False')" "$(run once-undecided)"
assert_eq "one unrecorded round, round 2 clean: a stop that merges at round 2" "$(printf 'fix,1,False\nstop,2,True')" "$(run once-undecided-then-clean)"
echo "── every round recorded: next's answer as it is"
assert_eq "recorded rounds follow next" "$(printf 'fix,1,False\nstop,2,True')" "$(run recorded)"
echo "── a replaced run stops"
assert_eq "gate replaced → abort" "ABORT" "$(run replaced-gate)"
assert_eq "next replaced → abort" "ABORT" "$(run replaced-next)"

print_summary
