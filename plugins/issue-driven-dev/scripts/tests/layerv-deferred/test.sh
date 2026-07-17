#!/usr/bin/env bash
# test.sh — drift-guard for the #120 Layer V unattended deferred-record.
#
# WHY A CONTENT DRIFT-GUARD (not an execution harness): the mechanism is prose
# across three sites — the reason-pattern registry (append-vs-modify.md), the
# originating writer (idd-diagnose Step 3.4 F), and the aggregating reader
# (idd-all Phase 6 Action items). The falsifiable equivalent of "unattended
# Layer V trigger leaves a recoverable record" is asserting the registered
# literal `unattended-auto-Step-3.4-layerV-deferred` appears VERBATIM at all
# three sites (the #137 typo-drift lesson: one drifted citation silently breaks
# the Phase 6 aggregation grep), plus the structured-record fields the reader
# depends on. Mirrors the #137 mechanism this one is isomorphic to.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
REGISTRY="$PLUGIN_ROOT/rules/append-vs-modify.md"
DIAGNOSE="$PLUGIN_ROOT/skills/idd-diagnose/SKILL.md"
ALL="$PLUGIN_ROOT/skills/idd-all/SKILL.md"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

assert_file_exists "append-vs-modify.md exists" "$REGISTRY"
assert_file_exists "idd-diagnose SKILL.md exists" "$DIAGNOSE"
assert_file_exists "idd-all SKILL.md exists" "$ALL"

LIT="unattended-auto-Step-3.4-layerV-deferred"

# ── literal registered + cited verbatim at all three sites (#137 lesson) ──
assert_output_grep "registry: literal registered as source of truth"   "$LIT" "$REGISTRY"
assert_output_grep "diagnose: Step 3.4 F writes the literal"           "$LIT" "$DIAGNOSE"
assert_output_grep "idd-all: Phase 6 scan recognizes the literal"      "$LIT" "$ALL"

# registry row names the originating action and the recognizing reader
assert_output_grep "registry: originating action is Step 3.4 F"        "Step 3.4 F" "$REGISTRY"
assert_output_grep "registry: recognized by idd-all Phase 6"           "Phase 6"    "$REGISTRY"

# ── structured deferred record (writer side) ──
# Attended behavior is untouched; the unattended branch upgrades its one-line
# audit note into a recoverable record: scores + the literal + the catch-up command.
assert_output_grep "diagnose: record is structured (deferred-record heading)"  "#### Layer V Deferred Record" "$DIAGNOSE"
assert_output_grep "diagnose: record carries V1/V4 scores"                     "**V1**: \$V1"                 "$DIAGNOSE"
assert_output_grep "diagnose: record names the catch-up command"               "/idd-clarify #\$NUMBER"       "$DIAGNOSE"
assert_output_grep "diagnose: attended path is explicitly unchanged"           "attended 行為零改動"           "$DIAGNOSE"

# ── aggregation (reader side) ──
# Phase 6 grep must match the new literal with a dot-escaped regex (same
# discipline as the Step-4.6 literal), and surface rows under Action items.
assert_output_grep "idd-all: dot-escaped regex for the new literal"    'unattended-auto-Step-3\.4-layerV-deferred' "$ALL"
assert_output_grep "idd-all: Layer V rows land in Action items"        "Layer V deferred" "$ALL"

print_summary "layerv-deferred"
