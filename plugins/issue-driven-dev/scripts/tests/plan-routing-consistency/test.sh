#!/usr/bin/env bash
# Test: idd-plan's account of idd-all's Plan routing matches idd-all (#317).
#
# WHY THIS EXISTS
#
# #292 moved Plan-tier routing so that ATTENDED /idd-all calls /idd-plan (the
# EnterPlanMode gate lives there, not in /idd-implement). idd-all was updated;
# idd-plan's "與 idd-all 的整合" section was not, and it stated the old rule as
# a UNIVERSAL: "idd-all 不該走 Plan path". Its unattended half was right — the
# error was writing one branch's conclusion without its condition. A reader
# taking idd-plan as the source concluded the opposite of what runs.
#
# Same failure the repo's own doctrine warns about: a blanket judgement plus
# examples is two specifications that will not be edited together. Enumerate.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"

PLAN=$(cat "$PLUGIN/skills/idd-plan/SKILL.md")
ALL=$(cat "$PLUGIN/skills/idd-all/SKILL.md")

# The normative side first. If idd-all ever stops routing attended Plan to
# /idd-plan, the reader-side assertions below are pinning fiction — so they are
# asserted against the source, not assumed.
assert_grep "idd-all routes attended Plan tier to /idd-plan" \
  'attended → Phase 3p: `/idd-plan`' "$ALL"
assert_grep "idd-all downgrades Plan tier only under unattended" \
  'unattended → Phase 3a: idd-implement' "$ALL"

# The reader side.
refute_grep "idd-plan no longer states the blanket 'idd-all must not take the Plan path'" \
  "idd-all 不該走 Plan path**。Plan tier 的核心價值" "$PLAN"
assert_grep "idd-plan splits the two interaction modes" "attended | unattended" "$PLAN"
assert_grep "idd-plan says the downgrade is unattended-only" "降級只發生在 unattended" "$PLAN"
assert_grep "idd-plan defers to idd-all as the normative source" \
  "normative source 是" "$PLAN"

print_summary "plan-routing-consistency"
exit $?
