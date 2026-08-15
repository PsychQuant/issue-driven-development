#!/usr/bin/env bash
# Test: the `Question for you` column contains QUESTIONS (#294).
#
# WHY THIS EXISTS
#
# #294 changed that column from descriptive analysis to a question, on the
# user's own instruction ("iddclarify我覺得你可以直接放對使用者的問題"). The
# reason is who reads it: the person making the call. Analysis makes them
# reconstruct the question before they can answer it.
#
# What shipped was the RULE, an ❌/✅ contrast table demonstrating the rule —
# and, forty lines further down, a worked example whose third column was still
# analysis (`分群變數 / distinguishing variable (per K-means context…)`). A
# reader following the example gets the old behaviour; a reader following the
# rule gets the new one. The example is the part people copy.
#
# Same class as #288's scratch paths: a document that states a rule and then
# violates it in its own example is worse than one that states nothing.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"

# Every example row with status `surfaced` must ask something. Placeholder rows
# (`...`), `passed` rows and `deferred` rows are exempt: the first are not
# examples of wording, and the last two have nothing to ask.
bad_rows() {
  grep -rhE --include='*.md' '^\| (terminology|ambiguity|missing-context) \|' "$PLUGIN/skills" 2>/dev/null \
    | grep -E '\| surfaced \|' \
    | awk -F'|' '{q=$4; gsub(/^[ \t]+|[ \t]+$/,"",q); if (q != "..." && q !~ /[?？]/) print}'
}

HITS=$(bad_rows || true)
require "every surfaced example row asks a question, not states an analysis" \
  bash -c '[ -z "$0" ] || { printf "%s\n" "$0"; exit 1; }' "$HITS"

# Positive control: plant a row in the old analysis style and prove the scan
# sees it. Unique name + trap — the canary is written into the repo.
CANARY="$PLUGIN/skills/idd-clarify/.question-canary.$$-${RANDOM}.md"
trap 'rm -f "$CANARY"' EXIT HUP INT TERM
printf '| terminology | "x" | 語義邊界未定義 | surfaced |\n' > "$CANARY"
SEEN=$(bad_rows | grep -c '語義邊界未定義' || true)
rm -f "$CANARY"
require "positive control: the scan detects an analysis-style row" \
  bash -c '[ "$0" -ge 1 ]' "$SEEN"

# And the rule itself must still be stated — the examples above conform to it,
# but conformance without the rule written down is one edit away from drifting
# back, and nothing here would notice.
CLARIFY=$(cat "$PLUGIN/skills/idd-clarify/SKILL.md")
assert_grep "the question-not-analysis rule is stated" "第三欄寫「問句」，不是分析" "$CLARIFY"
assert_grep "...and requires a one-sentence answer" "可以用一句話回答" "$CLARIFY"

print_summary "clarify-question-column"
exit $?
