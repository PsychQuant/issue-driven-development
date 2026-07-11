#!/usr/bin/env bash
# test.sh — drift-guard for the #161 IDD_CALLER registry.
#
# #161: the IDD_CALLER env-var convention spans 5+ SKILL.md emitters and the
# process-attachments.sh reader (manifest `fetched_by`) with no central
# registry — new values get added silently (PR #159 added the 6th with zero
# review surface). The registry (references/idd-caller-registry.md) is the
# review surface; THIS suite is the anti-drift lock: any IDD_CALLER=<value>
# in the tree MUST appear in the registry, so a future silent addition turns
# this suite RED instead of drifting.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
REGISTRY="$PLUGIN_ROOT/references/idd-caller-registry.md"
READER="$PLUGIN_ROOT/scripts/process-attachments.sh"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

assert_file_exists "registry exists" "$REGISTRY"

# ── ANTI-DRIFT CORE: every IDD_CALLER=<value> in the tree is registered ──
# Dynamic sweep (not a static list) so a silently-added 7th value fails here.
TREE_VALUES=$(grep -rhoE 'IDD_CALLER=[a-z][a-z-]*' "$PLUGIN_ROOT/skills" "$PLUGIN_ROOT/scripts" 2>/dev/null \
  | sed 's/^IDD_CALLER=//' | sort -u)
if [ -z "$TREE_VALUES" ]; then
  fail "tree sweep found no IDD_CALLER values" "grep returned empty — sweep broken?"
else
  for v in $TREE_VALUES; do
    if grep -qF "\`$v\`" "$REGISTRY" 2>/dev/null; then
      pass "registry covers tree value: $v"
    else
      fail "registry missing tree value: $v" "add a row to $REGISTRY (this is the #161 review surface)"
    fi
  done
fi

# ── registry documents the reader contract ──
assert_output_grep "registry names the reader (process-attachments.sh)" "process-attachments.sh" "$REGISTRY"
assert_output_grep "registry documents manifest fetched_by field"       "fetched_by"             "$REGISTRY"
assert_output_grep "registry documents the unset default"              "idd-skill"              "$REGISTRY"
assert_output_grep "registry states the semantic intent (audit trail)" "audit trail"            "$REGISTRY"

# ── cross-links: reader script points back at the registry ──
assert_output_grep "reader script cross-links the registry" "idd-caller-registry" "$READER"

print_summary "idd-caller-registry (#161)"
