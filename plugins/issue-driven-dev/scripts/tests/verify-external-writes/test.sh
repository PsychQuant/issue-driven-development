#!/usr/bin/env bash
# Test: the ensemble is told about writes that happen OUTSIDE the diff (#315).
#
# WHY THIS EXISTS
#
# `idd-verify`'s scope is a diff. `idd-implement`'s sister sweep and
# cross-reference notes write to surfaces that are NOT in it — comments on other
# issues, issues filed in other repos. In the recorded case (macdoc#143) a
# factual error in an implementation note was propagated verbatim into another
# issue's cross-reference note; four lenses reviewed only the wording inside the
# diff, and the devil's advocate caught it by stepping outside its brief.
#
# WHAT THE FIRST IMPLEMENTATION GOT WRONG (post-merge ensemble, #320 verify)
#
# Every one of these was live, and the suite was green over all of them:
#   - the fetch used `$N`, undefined in that scope
#   - it used `gh issue view --json comments` — the OLDEST-100 connection this
#     same file deliberately routes the gate away from
#   - it sat inside a block labelled "Tier 1 專用", so manual fan-out got
#     "(none recorded)" every run
#   - three of its four section names are written by no skill at all
#   - `^` was applied to the whole comment string, not per line
#   - cluster verify loops every ref'd issue; the fetch read one
#   - the untrusted comment text went verbatim into five prompts with no guard
#
# And the assertion meant to prove parity — annotated == prompt count — LOCKED
# THE GAP IN: adding the context to the codex leg would have made it FAIL. An
# equality that is satisfied by two things being equally incomplete is not a
# parity check. This file now enumerates the reviewers by name instead.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"

MD=$(cat "$PLUGIN/skills/idd-verify/SKILL.md")

echo "── acquisition ──"
assert_grep "the external-writes list is collected as a Step 0 task" \
  'TaskCreate(name="collect_external_writes"' "$MD"
# The oldest-100 nested connection is the seven-round root cause. Using it to
# find the NEWEST audit-trail comment repeats it one surface over.
refute_grep "the fetch does NOT use the oldest-100 nested comments connection" \
  'gh issue view "$N" --repo "$GITHUB_REPO" --json comments' "$MD"
assert_grep "the fetch uses paginated REST, like the gate does" \
  'gh api "repos/$GITHUB_REPO/issues/$1/comments" --paginate' "$MD"
assert_grep "a failed fetch is distinguishable from an empty one" 'EW_OK=0' "$MD"
refute_grep "no undefined \$N in the collector" 'gh issue view "$N"' "$MD"
assert_grep "cluster: every ref'd issue is collected, not just one" \
  'for I in ${REFD_ISSUES:-$NUMBER}' "$MD"

echo "── the sections scanned must be sections something WRITES ──"
# Verified against the writers, not remembered. Each name below must appear in
# the collector AND be produced by some skill; a name in the collector that
# nothing emits guarantees a permanent UNKNOWN for that class.
for sec in "Sister Bugs Filed" "Sister Concerns Filed" "Follow-up Findings Filed" \
           "Closing Follow-ups Filed" "Tangential Observations"; do
  assert_grep "collector scans '$sec'" "$sec" "$(printf '%s' "$MD" | grep -A2 '^EW_SECTIONS=')"
  # `--include` MUST precede `--`: after it, grep takes the flag as a FILE
  # OPERAND and ignores it. The first cut had it after, printed
  # "grep: --include=*.md: No such file or directory" to stderr, and PASSED
  # anyway. Same bug the prose-drift suite documents in its own header.
  require "...and some skill actually writes '$sec'" \
    bash -c 'grep -rqF --include="*.md" -- "### $1" "$0"/skills' "$PLUGIN" "$sec"
done
# The three names the first version invented, which nothing emits.
for ghost in "Blast Radius" "External writes"; do
  refute_grep "collector does not scan the invented section '$ghost'" \
    "$ghost" "$(printf '%s' "$MD" | grep -A2 '^EW_SECTIONS=')"
done

echo "── who actually receives it ──"
# Named reviewers, not a count. The pai DA is asserted as a KNOWN GAP rather
# than quietly omitted — engine `daPrompt` takes no contextBlock, so IDD cannot
# reach it through the documented contract.
assert_grep "Tier 1 receives it through CONTEXT_BLOCK" 'CONTEXT_BLOCK="${CONTEXT_BLOCK}' "$MD"
assert_grep "the manual codex leg receives it too" '--instructions "You are verifying' "$MD"
require "the manual codex --instructions carries the block" \
  bash -c 'printf "%s" "$0" | grep -A3 -- "--instructions \"You are verifying" | grep -q "EW_BLOCK"' "$MD"
assert_grep "the pai DA gap is stated, with the engine line" 'daPrompt' "$MD"
assert_grep "...and named as an upstream limitation, not a claim of parity" \
  '上游限制' "$MD"
refute_grep "no unqualified 'both backends' claim survives" \
  '兩個 backend 都給' "$MD"

# Every manual-fan-out lens prompt must carry it. Counting prompts is still
# useful — but as a FLOOR (all five), never as an equality against however many
# happen to be annotated.
PROMPTS=$(printf '%s\n' "$MD" | grep -c 'Diff path: \$VERIFY_DIR/diff\.patch')
ANNOTATED=$(printf '%s\n' "$MD" | grep -c '^\${EW_BLOCK}$')
require "all five manual lens prompts carry the block (floor, not equality)" \
  bash -c '[ "$0" -ge 5 ] && [ "$1" -ge "$0" ]' "$PROMPTS" "$ANNOTATED"

echo "── the absent case, and untrusted content ──"
assert_grep "an empty record is reported as UNKNOWN, not 'nothing happened'" \
  'the blast radius is UNKNOWN' "$MD"
assert_grep "the untrusted comment text carries its own data guard" \
  'UNTRUSTED issue-comment content' "$MD"
assert_grep "...and is delimited so injected text cannot pass as instruction" \
  '<<<EXTERNAL_WRITES' "$MD"

print_summary "verify-external-writes"
exit $?
