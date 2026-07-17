#!/usr/bin/env bash
# test.sh — drift-guard for #139 /idd-find (surfacing-only semantic lookup).
#
# WHY A CONTENT DRIFT-GUARD: the skill is prose. The falsifiable equivalent of
# "find stays a surfacing-only primitive with an honest v1 boundary" is
# asserting the SKILL carries the read-only prohibition, the open+closed
# corpus + relevance backend, the IDD overlay, the embedding-residue
# disclosure, and the idd-list division-of-labor redirect — plus the two doc
# surfaces (plugin CLAUDE.md table, usecase-routing) that make it discoverable.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
SKILL="$PLUGIN_ROOT/skills/idd-find/SKILL.md"
PCLAUDE="$PLUGIN_ROOT/CLAUDE.md"
ROUTING="$PLUGIN_ROOT/references/usecase-routing.md"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

# ── skill exists with the surfacing-only contract ──
assert_file_exists "idd-find SKILL.md exists" "$SKILL"
assert_output_grep "skill: surfacing-only prohibition (no state mutation)" "不 mutate 任何 state" "$SKILL"
assert_output_grep "skill: full corpus (open+closed)"          "open+closed"           "$SKILL"
assert_output_grep "skill: GitHub relevance backend"           "gh search issues"      "$SKILL"
assert_output_grep "skill: fallback search path"               "gh issue list --search" "$SKILL"
assert_output_grep "skill: phase overlay on open hits"         "**Phase**:"            "$SKILL"
assert_output_grep "skill: PR overlay marker"                  "→ PR #"                "$SKILL"
assert_output_grep "skill: honest boundary — embedding residue" "embedding"            "$SKILL"
assert_output_grep "skill: cross-phrasing limitation disclosed" "跨措辭"                "$SKILL"
assert_output_grep "skill: division of labor redirects to idd-list" "idd-list"         "$SKILL"
assert_output_grep "skill: filter flags rejected"              "--state"               "$SKILL"
assert_output_grep "skill: empty result degrades honestly"     "放寬"                   "$SKILL"
assert_output_grep "skill: family membership (surfacing-only primitive)" "surfacing-only" "$SKILL"

# ── discoverability surfaces ──
assert_output_grep "plugin CLAUDE.md lists idd-find"           "idd-find"              "$PCLAUDE"
assert_output_grep "usecase-routing has a find scenario"       "idd-find"              "$ROUTING"

# ── #140: surfacing-only primitive family doc (D12 axis) ──
FAMILY="$PLUGIN_ROOT/references/surfacing-primitives.md"
assert_file_exists "references/surfacing-primitives.md exists" "$FAMILY"
assert_output_grep "family: D12 axis named"                    "D12"                   "$FAMILY"
assert_output_grep "family: Surfacing vs Lifecycle axis"       "Surfacing vs Lifecycle" "$FAMILY"
assert_output_grep "family: member idd-list"                   "idd-list"              "$FAMILY"
assert_output_grep "family: member idd-clarify"                "idd-clarify"           "$FAMILY"
assert_output_grep "family: member idd-find"                   "idd-find"              "$FAMILY"
assert_output_grep "family: state-mutation prohibition"        "no \`gh issue create\`" "$FAMILY"
assert_output_grep "family: 4th-member review criteria"        "第 4 員"                "$FAMILY"
assert_output_grep "family: boilerplate checklist"             "Family boilerplate"    "$FAMILY"

print_summary "idd-find"
