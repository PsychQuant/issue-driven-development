#!/usr/bin/env bash
# test.sh — drift-guard for #133 dashboard comment contract (+ #134 rollup, same suite).
#
# WHY A CONTENT DRIFT-GUARD: the dashboard is a prose contract executed by four
# lifecycle SKILLs. The falsifiable equivalent of "humans get one stable
# narrative surface per issue" is asserting (a) the canonical contract file
# carries the marker + template + phase-transition-only update table (the #116
# anti-fatigue lock), and (b) all four lifecycle SKILLs cite the contract at
# their wiring point — a missing citation is exactly how one skill's phase
# transition would silently stop updating the dashboard.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
REF="$PLUGIN_ROOT/references/dashboard-comment.md"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

# ── contract file: marker + template + update-point table + division of labor ──
assert_file_exists "references/dashboard-comment.md exists" "$REF"
assert_output_grep "ref: HTML marker for machine location"      "<!-- idd:dashboard -->"          "$REF"
assert_output_grep "ref: human-facing heading"                  "## 📊 For Reviewer / Collaborator" "$REF"
assert_output_grep "ref: update points bound to phase transitions ONLY" "只綁 phase 轉換"          "$REF"
assert_output_grep "ref: anti-fatigue rationale cites the #116 class"   "notification fatigue"    "$REF"
assert_output_grep "ref: last-updated provenance field"         "last-updated by"                 "$REF"
assert_output_grep "ref: division of labor vs body Current Status"      "narrative for humans"    "$REF"
assert_output_grep "ref: update mechanics via marker surgery"   "marker 定位"                      "$REF"

# ── four lifecycle SKILLs wired (each cites the contract at its transition point) ──
for skill in idd-diagnose idd-implement idd-verify idd-close; do
  S="$PLUGIN_ROOT/skills/$skill/SKILL.md"
  assert_file_exists "$skill SKILL.md exists" "$S"
  assert_output_grep "$skill: cites dashboard contract"  "references/dashboard-comment.md" "$S"
  assert_output_grep "$skill: names the marker"          "idd:dashboard"                   "$S"
done

# ── #134 rollup mode (idd-report consumes the same contract) ──
REPORT="$PLUGIN_ROOT/skills/idd-report/SKILL.md"
assert_file_exists "idd-report SKILL.md exists" "$REPORT"
assert_output_grep "report: rollup mode exists"                 "--rollup"            "$REPORT"
assert_output_grep "report: consumes the dashboard marker"      "idd:dashboard"       "$REPORT"
assert_output_grep "report: grouping — need attention"          "need attention"      "$REPORT"
assert_output_grep "report: grouping — stalled"                 "stalled"             "$REPORT"
assert_output_grep "report: grouping — recently closed"         "recently closed"     "$REPORT"
assert_output_grep "report: snapshot-only invariant (no write-back)" "snapshot-only"  "$REPORT"
assert_output_grep "report: registry-based owner mapping (#86)" "collaborators"       "$REPORT"

print_summary "dashboard-comment"
