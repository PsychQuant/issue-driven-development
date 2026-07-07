#!/usr/bin/env bash
# test.sh — drift-guard for the #111 pre-implementation staging hand-off to
# superpowers (change reshape-plan-preimpl-tier, spec superpowers-integration).
#
# WHY A CONTENT DRIFT-GUARD: the hand-off is prose (README stage-mapping table +
# idd-issue / idd-diagnose pointers) plus two mechanical filesystem invariants
# (no self-built staging skill; idd-plan stays superpowers-free). Assertions are
# on canonical tokens + filesystem presence, non-line-bound.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
README="$PLUGIN_ROOT/README.md"
DIAGNOSE="$PLUGIN_ROOT/skills/idd-diagnose/SKILL.md"
ISSUE="$PLUGIN_ROOT/skills/idd-issue/SKILL.md"
PLAN_DIR="$PLUGIN_ROOT/skills/idd-plan"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

assert_file_exists "README.md exists" "$README"
assert_file_exists "idd-diagnose SKILL.md exists" "$DIAGNOSE"
assert_file_exists "idd-issue SKILL.md exists" "$ISSUE"
R="$(cat "$README" 2>/dev/null || echo "")"
D="$(cat "$DIAGNOSE" 2>/dev/null || echo "")"
I="$(cat "$ISSUE" 2>/dev/null || echo "")"

IDD_UNIQUE="IDD 獨有 — 無 superpowers 對應"

# ── Task 4.1 — pre-implementation staging hand-off to superpowers ──
# README carries an IDD↔superpowers stage-mapping table naming superpowers:brainstorming
# and marking the verify ensemble + close audit trail as IDD-unique (no counterpart).
assert_grep "README: stage-mapping table title (#111)"            "IDD ↔ superpowers" "$R"
assert_grep "README: names superpowers:brainstorming as staging dest" "superpowers:brainstorming" "$R"
assert_grep "README: verify ensemble marked IDD-unique"           "$IDD_UNIQUE"        "$R"

# idd-issue (summary step) and idd-diagnose (design-heavy) surface a non-binding
# hand-off pointer naming superpowers:brainstorming.
assert_grep "idd-diagnose: design-heavy hand-off pointer"         "superpowers:brainstorming" "$D"
assert_grep "idd-issue: summary-step hand-off pointer"            "superpowers:brainstorming" "$I"

# No self-built staging skill is added (mechanical filesystem check).
assert_file_absent "no idd-brainstorm skill exists"  "$PLUGIN_ROOT/skills/idd-brainstorm"
assert_file_absent "no idd-write-plan skill exists"  "$PLUGIN_ROOT/skills/idd-write-plan"

# ── Task 4.2 — kept disciplines are excluded from delegation ──
# The planning discipline (idd-plan / Spectra) must NOT delegate to superpowers.
# Mechanical check: grep 'superpowers:' anywhere under idd-plan → zero hits.
# Fail-loud if the dir is missing (a vanished target must not read as "pass" —
# fixes the silent-pass-on-missing-dir flagged in verify round 1).
if [ ! -d "$PLAN_DIR" ]; then
  fail "idd-plan is superpowers-free (mechanical check)" "target dir missing: $PLAN_DIR (cannot verify — not a silent pass)"
elif grep -rqn "superpowers:" "$PLAN_DIR" 2>/dev/null; then
  fail "idd-plan is superpowers-free (mechanical check)" "found a superpowers: reference under $PLAN_DIR"
else
  pass "idd-plan is superpowers-free (mechanical check)"
fi
# Contract text explicitly distinguishes hand-off pointer from delegation.
assert_grep "README: contract states pointer ≠ delegation"  "pointer ≠ delegation" "$R"

print_summary "superpowers-staging"
