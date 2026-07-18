#!/usr/bin/env bash
# test.sh — drift-guard for #72 /idd-ask (grounded QA over the issue corpus).
#
# WHY A CONTENT DRIFT-GUARD: the skill is prose. The falsifiable equivalent of
# "answers stay grounded and the skill stays a surfacing primitive" is
# asserting the SKILL carries the grounding contract verbatim (blockquote the
# question, cite every claim, source priority, Referenced Issues, honest
# silence), the family obligations (read-only, no-diagnose-trigger, bounded
# top-N, idd-find backend delegation — never a diverging retrieval copy), and
# the three discoverability surfaces. A missing citation-contract line is
# exactly how grounded QA silently degrades into hallucinated summaries.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
SKILL="$PLUGIN_ROOT/skills/idd-ask/SKILL.md"
FAMILY="$PLUGIN_ROOT/references/surfacing-primitives.md"
PCLAUDE="$PLUGIN_ROOT/CLAUDE.md"
ROUTING="$PLUGIN_ROOT/references/usecase-routing.md"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

# ── skill exists with the grounding contract ──
assert_file_exists "idd-ask SKILL.md exists" "$SKILL"
assert_output_grep "skill: blockquote the user's question"      "blockquote 引用使用者原問題" "$SKILL"
assert_output_grep "skill: every claim carries a citation"      "claim 必附引用"        "$SKILL"
assert_output_grep "skill: source priority order"               "closed-with-PR > open > orphaned comment" "$SKILL"
assert_output_grep "skill: Referenced Issues section"           "### Referenced Issues" "$SKILL"
assert_output_grep "skill: honest silence on corpus miss"       "查無"                  "$SKILL"
assert_output_grep "skill: conflicts surfaced not resolved"     "分歧"                  "$SKILL"

# ── family obligations ──
assert_output_grep "skill: read-only prohibition"               "不 mutate 任何 state"   "$SKILL"
assert_output_grep "skill: bug-shaped question never triggers diagnose" "不觸發"        "$SKILL"
assert_output_grep "skill: bounded top-N"                       "top-N"                 "$SKILL"
assert_output_grep "skill: delegates idd-find backend (no diverging copy)" '`idd-find` 的 search backend' "$SKILL"
assert_output_grep "skill: family membership"                   "surfacing-only"        "$SKILL"
assert_output_grep "skill: cites family canonical"              "references/surfacing-primitives.md" "$SKILL"

# ── family canonical registers the 4th member ──
assert_output_grep "family: member table lists idd-ask"         "idd-ask"               "$FAMILY"
assert_output_grep "family: ask's distinct I/O shape recorded"  "合成答案"               "$FAMILY"

# ── discoverability ──
assert_output_grep "plugin CLAUDE.md lists idd-ask"             "idd-ask"               "$PCLAUDE"
assert_output_grep "usecase-routing has an ask scenario"        "idd-ask"               "$ROUTING"

print_summary "idd-ask"
