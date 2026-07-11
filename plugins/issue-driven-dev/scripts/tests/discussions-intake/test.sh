#!/usr/bin/env bash
# test.sh — drift-guard for the #221 Discussions intake bridge
# (change discussions-intake-bridge, spec discussions-intake).
#
# The bridge spans TWO prose SKILLs + ONE shared reference that MUST agree:
#   - references/discussions-intake.md  (contract source of truth + GraphQL)
#   - skills/idd-list/SKILL.md          (--discussions surfacing, Step 2.7)
#   - skills/idd-issue/SKILL.md         (--from-discussion seeding + reply)
# The real failure mode is DRIFT (change the contract in one file, forget the
# others) plus EROSION of the three normative constraints — especially
# no-auto-file, whose violation recreates the exact noise the motivating
# case (che-ical-mcp discussion 105) proved harmful.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
REF="$PLUGIN_ROOT/references/discussions-intake.md"
LIST="$PLUGIN_ROOT/skills/idd-list/SKILL.md"
ISSUE="$PLUGIN_ROOT/skills/idd-issue/SKILL.md"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

# ── reference: the contract + all three queries live here, once ──
assert_file_exists "shared reference exists" "$REF"
assert_output_grep "ref: no-auto-file constraint"            "no-auto-file"            "$REF"
assert_output_grep "ref: dedup constraint"                   "dedup"                   "$REF"
assert_output_grep "ref: resolution-detection constraint"    "resolution-detection"    "$REF"
assert_output_grep "ref: answerChosenAt mechanical boundary" "answerChosenAt"          "$REF"
assert_output_grep "ref: hasDiscussionsEnabled probe query"  "hasDiscussionsEnabled"   "$REF"
assert_output_grep "ref: list query (first 50)"              "discussions(first:50"    "$REF"
assert_output_grep "ref: single-discussion fetch query"      "discussion(number:"      "$REF"
assert_output_grep "ref: reply mutation (confirm-gated)"     "addDiscussionComment"    "$REF"
assert_output_grep "ref: schema assumption note dated"       "Schema 假設"              "$REF"
assert_output_grep "ref: unattended draft-only boundary"     "draft-only 絕不 post"     "$REF"

# ── idd-list: opt-in surfacing (Step 2.7) ──
assert_output_grep "idd-list: --discussions flag documented" "--discussions"           "$LIST"
assert_output_grep "idd-list: Step 2.7 section present"      "Step 2.7"                "$LIST"
assert_output_grep "idd-list: disabled-repo graceful skip"   "hasDiscussionsEnabled"   "$LIST"
assert_output_grep "idd-list: category filter (Q&A/Ideas)"   "Q&A"                     "$LIST"
assert_output_grep "idd-list: unanswered signal"             "answerChosenAt"          "$LIST"
assert_output_grep "idd-list: dedup against issue refs"      "dedup"                   "$LIST"
assert_output_grep "idd-list: dedicated actionable block"    "Discussions (actionable)" "$LIST"
assert_output_grep "idd-list: suggested next → from-discussion" "idd-issue --from-discussion" "$LIST"
assert_output_grep "idd-list: bootstrap task fetch_discussions" "fetch_discussions"    "$LIST"
assert_output_grep "idd-list: cites the shared reference"    "discussions-intake"      "$LIST"

# ── idd-issue: --from-discussion seeding + confirm-gated reply ──
assert_output_grep "idd-issue: --from-discussion flag"       "--from-discussion"       "$ISSUE"
assert_output_grep "idd-issue: Provenance section seeded"    "## Provenance"           "$ISSUE"
assert_output_grep "idd-issue: verbatim blockquote of opening post" "verbatim blockquote" "$ISSUE"
assert_output_grep "idd-issue: reply is draft-and-confirm"   "draft-and-confirm"       "$ISSUE"
assert_output_grep "idd-issue: unattended never posts reply" "suggested reply (not posted)" "$ISSUE"
assert_output_grep "idd-issue: bootstrap task seed_from_discussion" "seed_from_discussion" "$ISSUE"
assert_output_grep "idd-issue: cites the shared reference"   "discussions-intake"      "$ISSUE"

# ── the cardinal rule survives in BOTH consumer skills ──
assert_output_grep "idd-list: never auto-files"              "絕不自動建 issue"          "$LIST"
assert_output_grep "idd-issue: never auto-posts the reply"   "絕不 auto-post"           "$ISSUE"

print_summary "discussions-intake (#221)"
