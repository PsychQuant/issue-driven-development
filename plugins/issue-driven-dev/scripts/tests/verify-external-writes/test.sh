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
#
# PARSED FROM THE SKILL, not hardcoded. The first cut iterated its own list of
# five names and asserted each was real — which says nothing about what the
# collector actually scans. Mutation-proven: prepending a sixth invented section
# to `EW_SECTIONS` left the suite 28/0 green. A gate that cannot see the thing it
# constrains is decoration.
#
# The stated guarantee is: "a name in the collector that nothing emits guarantees
# a permanent UNKNOWN for that class". Enforce exactly that, over whatever the
# collector currently lists.
EW_LINE=$(printf '%s\n' "$MD" | grep '^EW_SECTIONS=' | head -1)
require "the collector's section list is parseable" \
  bash -c '[ -n "$0" ]' "$EW_LINE"
EW_LIST=$(printf '%s' "$EW_LINE" | sed "s/^EW_SECTIONS='//; s/'\$//" | tr '|' '\n')
require "...and non-empty" bash -c '[ -n "$0" ]' "$EW_LIST"

# A section counts as EMITTED when some skill declares it an `**Audit trail
# target**` — that is how all six writers state it. Keying on the declaration
# rather than on a bare mention is what separates a writer from the collector's
# own comment table; the first cut excluded `idd-verify/SKILL.md` wholesale
# instead, which also excluded a GENUINE writer (idd-verify emits
# `### Follow-up Findings Filed` into its own report) and failed on it.
writers_of() {  # $1 = section name
  grep -rl --include='*.md' -- "Audit trail target" "$PLUGIN/skills" 2>/dev/null \
    | while IFS= read -r f; do
        grep -qE -- '\*\*Audit trail target\*\*:?[^`]*`### '"$(printf '%s' "$1" | sed 's/[][\.*^$/]/\\&/g')" "$f" \
          && printf '%s\n' "$f"
      done
}
# Evaluated in THIS shell. `bash -c` spawns one without the function, so
# `writers_of` would be "command not found", `$(...)` empty, and the assertion
# would report on nothing. That is the same mistake this round already fixed
# twice in the attachments suite — writing it a third time is the reason the
# rule is stated here rather than remembered.
while IFS= read -r sec; do
  [ -z "$sec" ] && continue
  if [ -n "$(writers_of "$sec")" ]; then
    pass "collector scans '$sec' — and some OTHER skill actually writes it"
  else
    fail "collector scans '$sec' — and some OTHER skill actually writes it" \
         "nothing outside idd-verify emits '### $sec'; that class can only ever report UNKNOWN"
  fi
done <<EW_SECTIONS_LIST
$EW_LIST
EW_SECTIONS_LIST

# THE CONVERSE, which is the direction that actually finds things: every section
# some skill DECLARES must appear in the collector. Without it the test only
# ratifies today's list — and it immediately found a sixth,
# `### Linked-Context Siblings Filed` (idd-issue), which the collector did not
# scan, so that whole class of external write could only ever report UNKNOWN.
DECLARED=$(grep -rhoE '\*\*Audit trail target\*\*:?[^`]*`### [^(`]+' "$PLUGIN/skills" 2>/dev/null \
           | sed 's/.*### //; s/ *$//' | sort -u)
require "at least one audit-trail target is declared (guards a vacuous pass)" \
  bash -c '[ -n "$0" ]' "$DECLARED"
while IFS= read -r decl; do
  [ -z "$decl" ] && continue
  case "$EW_LIST" in
    *"$decl"*) pass "declared target '$decl' is in the collector's scan list" ;;
    *)         fail "declared target '$decl' is in the collector's scan list" \
                    "a skill writes it, the collector does not look for it — permanent UNKNOWN" ;;
  esac
done <<DECLARED_LIST
$DECLARED
DECLARED_LIST

# Positive control: a name nothing emits must be caught. Without it the loop
# above is only as good as the list it read, and an empty list would pass
# vacuously.
if [ -z "$(writers_of "Ghost Radius Log")" ]; then
  pass "positive control: an invented section name has no writer"
else
  fail "positive control: an invented section name has no writer" "the writer search matches anything"
fi

echo "── who actually receives it ──"
# Named reviewers, not a count. The pai DA is asserted as a KNOWN GAP rather
# than quietly omitted — engine `daPrompt` takes no contextBlock, so IDD cannot
# reach it through the documented contract.
assert_grep "Tier 1 receives it through CONTEXT_BLOCK" 'CONTEXT_BLOCK="${CONTEXT_BLOCK}' "$MD"
assert_grep "the manual codex leg receives it too" '--instructions "You are verifying' "$MD"
require "the manual codex --instructions carries the block" \
  bash -c 'printf "%s" "$0" | grep -A3 -- "--instructions \"You are verifying" | grep -q "EW_BLOCK"' "$MD"
assert_grep "the pai DA gap is stated, with the engine line" 'daPrompt' "$MD"
# The DA IS reachable — `daPrompt` interpolates `A.daFocus`, a documented caller
# arg this skill already passes. The previous text called it an upstream
# limitation that could not be worked around; that was wrong, and the honest
# version is a trade-off: `contextBlock` is sentinel-wrapped by pai, `daFocus` is
# raw, so only a STRUCTURAL digest goes that way.
refute_grep "the DA gap is no longer described as un-sendable" '無法從 documented contract 送進去' "$MD"
assert_grep "...it is stated as a trade-off with a named reason" 'trade-off' "$MD"
assert_grep "the DA receives a structural digest through daFocus" 'DA_FOCUS_SUFFIX' "$MD"
assert_grep "...and the digest carries no verbatim comment text" 'EW_DIGEST=' "$MD"
assert_grep "...and an absent record still reads UNKNOWN there too" \
  'treat the blast radius as UNKNOWN' "$MD"
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
