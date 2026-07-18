#!/usr/bin/env bash
# test.sh — drift-guard for the docs catalog completeness (#267, mechanizing #122).
#
# ROOT CAUSE THIS GUARDS: the path/skill catalogs (docs/workflows.md +
# docs/skill-dimensions.md) had no forcing function — every release wave that
# shipped a new skill without backfilling the docs drifted silently until a
# human noticed (#122 fixed the content, this suite fixes the mechanism).
# Contract: EVERY directory under plugins/issue-driven-dev/skills/ must be
# mentioned by name in at least one of the two catalog docs. The guard asserts
# MENTION, not quality — prose depth stays human judgment.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
REPO_ROOT="$PLUGIN_ROOT/../.."
WORKFLOWS="$REPO_ROOT/docs/workflows.md"
DIMENSIONS="$REPO_ROOT/docs/skill-dimensions.md"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

assert_file_exists "docs/workflows.md exists" "$WORKFLOWS"
assert_file_exists "docs/skill-dimensions.md exists" "$DIMENSIONS"

for d in "$PLUGIN_ROOT"/skills/*/; do
  n=$(basename "$d")
  if grep -qF -- "$n" "$WORKFLOWS" || grep -qF -- "$n" "$DIMENSIONS"; then
    pass "catalog mentions skill: $n"
  else
    fail "catalog mentions skill: $n" "neither docs/workflows.md nor docs/skill-dimensions.md mentions '$n' — backfill the catalog (the #122/#267 drift class)"
  fi
done

print_summary "docs-catalog-sync"
