#!/usr/bin/env bash
# test.sh — drift-guard for the Path Map wiki pipeline (#276 Phase 2).
#
# CONTRACT: docs/workflows.md is the single source (its `## Path Flowchart`
# mermaid block + the `#### P-` catalog); scripts/generate-path-map.py renders
# the committed wiki-source page docs/wiki/Path-Map.md deterministically; the
# wiki sync copies that file verbatim. Three invariants keep the navigation
# map from silently rotting (the #122/#267 drift class, third instance):
#   1. FRESHNESS — regenerating must reproduce the committed page byte-for-byte
#   2. COVERAGE  — every P- name in the catalog appears in the mermaid block
#                  AND in the generated page (a new path that skips the map
#                  goes red here, not unnoticed)
#   3. DISCOVERY — README points at the wiki page
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
REPO_ROOT="$PLUGIN_ROOT/../.."
WORKFLOWS="$REPO_ROOT/docs/workflows.md"
GEN="$REPO_ROOT/scripts/generate-path-map.py"
PAGE="$REPO_ROOT/docs/wiki/Path-Map.md"
README="$PLUGIN_ROOT/README.md"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

assert_file_exists "docs/workflows.md exists" "$WORKFLOWS"
assert_file_exists "generator exists" "$GEN"
assert_file_exists "committed wiki-source page exists" "$PAGE"

# ── source section present ──
assert_output_grep "workflows.md has the Path Flowchart section" "## Path Flowchart" "$WORKFLOWS"
assert_output_grep "flowchart section carries a mermaid fence"   '```mermaid'         "$WORKFLOWS"

# ── invariant 1: freshness (generator --check diffs against committed page) ──
OUT=$(python3 "$GEN" --check 2>&1); RC=$?
if [ "$RC" -eq 0 ]; then
  pass "Path-Map.md is fresh (generator --check clean)"
else
  fail "Path-Map.md is fresh (generator --check clean)" "$OUT"
fi

# ── invariant 2: coverage — every catalog P- name in mermaid block AND page ──
MERMAID=$(awk '/^## Path Flowchart/{f=1} f && /^```mermaid/{m=1; next} m && /^```/{exit} m' "$WORKFLOWS")
MISS_M=""; MISS_P=""
while IFS= read -r NAME; do
  case "$MERMAID" in *"$NAME"*) : ;; *) MISS_M="$MISS_M $NAME" ;; esac
  grep -qF -- "$NAME" "$PAGE" || MISS_P="$MISS_P $NAME"
done < <(grep -oE '^#### (P-[a-z0-9-]+)' "$WORKFLOWS" | sed 's/^#### //' | sort -u)
if [ -z "$MISS_M" ]; then
  pass "every catalog path appears in the mermaid flowchart"
else
  fail "every catalog path appears in the mermaid flowchart" "missing:$MISS_M"
fi
if [ -z "$MISS_P" ]; then
  pass "every catalog path appears in Path-Map.md"
else
  fail "every catalog path appears in Path-Map.md" "missing:$MISS_P"
fi

# ── invariant 3: discovery ──
assert_output_grep "README links to the wiki Path Map" "wiki/Path-Map" "$README"

print_summary "path-map-sync"
