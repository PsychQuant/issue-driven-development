#!/usr/bin/env bash
# test.sh — drift lock for spectra-bridge state path (#199)
# idd-comment must READ new-path-first (legacy fallback allowed) and WRITE the
# new path ONLY. rules/spectra-bridge.md L116 is the contract.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$HERE/../../../skills/idd-comment/SKILL.md"
PASS=0; FAIL=0
ok(){ echo "  ✓ $1"; PASS=$((PASS+1)); }
no(){ echo "  ✗ $1"; FAIL=$((FAIL+1)); }

# 1. write path: mkdir/cat must target .claude/.idd/state/, never .claude/state/
if grep -qE 'cat > \.claude/state/idd-bridge\.json|mkdir -p \.claude/state' "$SKILL"; then
  no "no legacy-path WRITE in idd-comment SKILL.md"
else ok "no legacy-path WRITE in idd-comment SKILL.md"; fi
# 2. new path present as primary read + write
grep -q '\.claude/\.idd/state/bridge\.json' "$SKILL" && ok "new path referenced" || no "new path referenced"
# 3. legacy path may appear ONLY as documented fallback (with the word fallback/legacy nearby)
LEGACY_LINES=$(grep -n '\.claude/state/idd-bridge\.json' "$SKILL" | grep -viE 'fallback|legacy' | wc -l | tr -d ' ')
[ "$LEGACY_LINES" = "0" ] && ok "legacy path only in fallback context" || no "legacy path only in fallback context ($LEGACY_LINES bare refs)"

echo "================================"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
