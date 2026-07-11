#!/usr/bin/env bash
# test.sh — drift-guard for the #228 idd-verify diff-freshness gate.
#
# #228 (from cluster-verify DA-CRIT-1, 2026-07-06 live incident): idd-verify
# freezes the diff to /tmp at Step 1; if the branch gets another commit while
# the ensemble is reviewing, the frozen diff silently diverges from shipping
# HEAD and an aggregate PASS gets transferred onto code nobody reviewed.
# The gate: record FROZEN_SHA at freeze time, compare before merge/aggregate,
# mismatch → refuse aggregate + require re-freeze / delta round. Plus the
# discipline sentence: the orchestrator must not commit mid-verify (fixes
# accumulate to round end — the DA-CRIT-1 handling, now normative).
#
# WHY A CONTENT DRIFT-GUARD: idd-verify is prose (an AI prompt); the
# falsifiable equivalent is asserting the SKILL encodes the gate mechanism.
# Needles are distinctive to #228 (0-occurrence before the change).
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
VERIFY="$PLUGIN_ROOT/skills/idd-verify/SKILL.md"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

assert_file_exists "idd-verify SKILL.md exists" "$VERIFY"

# ── freeze-time: HEAD sha recorded alongside the frozen diff ──
assert_output_grep "freeze records FROZEN_SHA"                    "FROZEN_SHA"        "$VERIFY"
assert_output_grep "get_diff bootstrap task mentions frozen sha"  "記 FROZEN_SHA"      "$VERIFY"

# ── gate: bootstrap task exists + runs BEFORE merge/aggregate ──
assert_output_grep "freshness_gate bootstrap step exists"         "freshness_gate"    "$VERIFY"
assert_output_grep "gate is a named Step (diff-freshness)"        "Diff-freshness gate" "$VERIFY"

# ── mismatch behavior: refuse aggregate, require re-freeze (option a) ──
assert_output_grep "mismatch refuses the aggregate"               "拒絕 aggregate"     "$VERIFY"
assert_output_grep "remedy is re-freeze + delta review"           "re-freeze"         "$VERIFY"

# ── discipline sentence: no mid-verify commits by the orchestrator ──
assert_output_grep "in-flight no-commit discipline present"       "verify in-flight 期間不得 commit" "$VERIFY"
assert_output_grep "fixes accumulate to round end"                "累積到 round 結束"   "$VERIFY"

# ── provenance: the gate cites its motivating incident ──
assert_output_grep "gate cites DA-CRIT-1 incident (#228)"         "DA-CRIT-1"         "$VERIFY"

print_summary "verify-diff-freshness (#228)"
