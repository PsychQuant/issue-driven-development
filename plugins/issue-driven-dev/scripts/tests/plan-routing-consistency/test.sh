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

# ── Every file that makes a CLAIM about unattended Plan routing, not just the
# ── ones using the implementation label
#
# `#317`'s criterion (c) asked whether a THIRD place restates this routing. The
# check grepped for `Phase 3p` and reported "no third place" — but
# `docs/workflows.md` stated the OPPOSITE ("Plan gate 仍 trigger…卡住") without
# ever using that token. Grepping the implementation label answers "where is the
# label", not "who makes a claim". The closing summary asserted the latter on the
# strength of the former, and a post-merge ensemble falsified it.
#
# So: scan for the CLAIM's vocabulary — any file pairing unattended-mode words
# with the Plan gate — and require each hit to agree that unattended DOWNGRADES.
ROOT="$(cd "$PLUGIN/../.." && pwd)"
claim_files() {
  grep -rlE --include='*.md' -- 'Plan gate|Plan tier|Plan path' "$ROOT/docs" "$PLUGIN" 2>/dev/null \
    | grep -v '/CHANGELOG.md$'
}
BAD=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  # A file claiming the gate FIRES under unattended contradicts idd-all.
  if grep -qE 'unattended|/loop|autopilot' "$f" 2>/dev/null \
     && grep -qE 'Plan gate 仍 trigger|EnterPlanMode 無人 approve' "$f" 2>/dev/null; then
    BAD="${BAD}\n    ${f}"
  fi
done <<CLAIMS
$(claim_files)
CLAIMS
require "no file claims the Plan gate still fires under unattended mode" \
  bash -c '[ -z "$0" ] || { printf "%b\n" "$0"; exit 1; }' "$BAD"

# Positive control — the scan above must be able to see such a claim.
PC="$ROOT/docs/.plan-claim-canary.$$-${RANDOM}.md"
trap 'rm -f "$PC"' EXIT HUP INT TERM
printf 'unattended: Plan gate 仍 trigger 但 EnterPlanMode 無人 approve\n' > "$PC"
PC_SEEN=0
while IFS= read -r f; do
  case "$f" in *plan-claim-canary*) PC_SEEN=1 ;; esac
done <<CANARY
$(claim_files)
CANARY
rm -f "$PC"
require "positive control: the claim scan detects a planted contradiction" \
  bash -c '[ "$0" = 1 ]' "$PC_SEEN"

print_summary "plan-routing-consistency"
exit $?
