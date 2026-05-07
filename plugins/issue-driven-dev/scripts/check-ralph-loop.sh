#!/usr/bin/env bash
# check-ralph-loop.sh — detect ralph-loop plugin presence
#
# Used by:
#   - idd-verify --loop (Step 0a fail-fast)
#   - idd-all Phase 0.6 (graceful degrade gate)
#
# Exit:
#   0 — ralph-loop installed (or IDD_SKIP_RALPH_CHECK=1)
#   1 — ralph-loop missing
#
# Detect path is hardcoded against Claude Code 2025-Q4 plugin cache schema.
# When schema changes upstream, see #35 (path schema watch-list).
# Source plugin lives at anthropics/claude-plugins-official.

set -u

# Escape hatch — let user bypass detect (#28 risk mitigation).
if [ "${IDD_SKIP_RALPH_CHECK:-}" = "1" ]; then
  exit 0
fi

# Plugin cache layout (Claude Code 2025-Q4):
#   ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/.claude-plugin/plugin.json
# Match any installed version under the plugin dir.
DETECT_GLOB="${HOME}/.claude/plugins/cache/claude-plugins-official/ralph-loop/*/.claude-plugin/plugin.json"

# shellcheck disable=SC2086  # intentional glob expansion
for f in $DETECT_GLOB; do
  if [ -f "$f" ]; then
    exit 0
  fi
done

cat >&2 <<EOF
✗ ralph-loop plugin not found.
  Searched: ~/.claude/plugins/cache/claude-plugins-official/ralph-loop/*/.claude-plugin/plugin.json

  Install:
    claude plugin marketplace add anthropics/claude-plugins-official
    claude plugin install ralph-loop@claude-plugins-official

  Or bypass this check (advanced): export IDD_SKIP_RALPH_CHECK=1
EOF
exit 1
