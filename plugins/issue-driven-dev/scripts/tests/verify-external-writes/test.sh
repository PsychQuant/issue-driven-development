#!/usr/bin/env bash
# Test: the ensemble is told about writes that happen OUTSIDE the diff (#315).
#
# WHY THIS EXISTS
#
# `idd-verify`'s scope is a diff. But `idd-implement`'s sister sweep and
# cross-reference notes write to surfaces that are NOT in it — comments on other
# issues, issues filed in other repos. No lens can see them.
#
# The recorded case (macdoc#143): a factual error in an implementation note was
# propagated verbatim into a cross-reference note on another issue. Four lenses
# reviewed only the wording inside the diff; the devil's advocate caught it by
# stepping OUTSIDE its scope to read the Implementation Complete comment's blast
# radius. One reviewer improvising past its brief is not a mechanism.
#
# #315 offered three options. This is option 1 — put the implementation's own
# record of external writes into the reviewer context, so they at least know the
# surfaces exist and are asked to check them. Option 2 (a machine-readable
# manifest written by idd-implement and content-checked by idd-verify) is a NEW
# CONTRACT BETWEEN TWO SKILLS, and this session's whole finding is that new
# contracts shipped without their own review are where the defects live. Not
# done here; the residue is recorded in the CHANGELOG.
#
# BOTH BACKENDS, or the context is a coin flip: the same run reviewed through
# pai gets the blast radius and through the manual fan-out does not, which makes
# a finding depend on which backend resolved. The skill's own contract promises
# the two are interchangeable after Step 3.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"

MD=$(cat "$PLUGIN/skills/idd-verify/SKILL.md")

assert_grep "the external-writes list is collected as a Step 0 task" \
  'TaskCreate(name="collect_external_writes"' "$MD"
assert_grep "it is read from the Implementation Complete comment" \
  'Implementation Complete' "$MD"
assert_grep "Tier 1 (pai) receives it through CONTEXT_BLOCK" \
  'WRITES OUTSIDE THIS DIFF' "$MD"

# Every manual-fan-out prompt must carry it too. Counting is the point: the
# first attempt at this edit keyed on a line only ONE of the five prompts has,
# so four kept the old context and nothing said so.
PROMPTS=$(printf '%s\n' "$MD" | grep -c 'Diff path: \$VERIFY_DIR/diff\.patch')
ANNOTATED=$(printf '%s\n' "$MD" | grep -c 'Writes OUTSIDE this diff')
assert_eq "every manual-fan-out lens prompt carries the external-writes context" \
  "$PROMPTS" "$ANNOTATED"
require "...and there is more than one of them (guards against a vacuous 0 == 0)" \
  bash -c '[ "$0" -ge 4 ]' "$PROMPTS"

# The absence case is the one that matters. "No section" means the blast radius
# is UNKNOWN, not that it was empty — an absent record is exactly what a missing
# sister-sweep looks like.
assert_grep "an empty record is reported as UNKNOWN, not as 'nothing happened'" \
  "blast radius as UNKNOWN rather than" "$MD"
assert_grep "...and the pai-side wording says the same" \
  "is simply unknown" "$MD"

print_summary "verify-external-writes"
exit $?
