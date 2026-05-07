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
# Print stderr warning so this leaves an audit trail (per F4 verify finding).
if [ "${IDD_SKIP_RALPH_CHECK:-}" = "1" ]; then
  echo "⚠ IDD_SKIP_RALPH_CHECK=1 set — skipping ralph-loop detection (advanced override)" >&2
  echo "  /idd-verify --loop and /idd-all (PR, unattended) will run as if ralph-loop is installed." >&2
  exit 0
fi

# Plugin cache layout (Claude Code 2025-Q4):
#   ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/.claude-plugin/plugin.json
# Match any installed version under the plugin dir.
#
# F3 fix: use bash array + nullglob, NOT unquoted `for f in $GLOB`. The latter
# word-splits when HOME contains whitespace (macOS display-name accounts,
# iCloud Mobile Documents paths) → false-negative even when ralph-loop is
# installed → silently breaks v2.40.0 backward-compat for /idd-all callers.
shopt -s nullglob
files=( "${HOME}/.claude/plugins/cache/claude-plugins-official/ralph-loop"/*/.claude-plugin/plugin.json )
shopt -u nullglob

if (( ${#files[@]} > 0 )); then
  exit 0
fi

cat >&2 <<EOF
✗ ralph-loop plugin not found.
  Searched: ~/.claude/plugins/cache/claude-plugins-official/ralph-loop/*/.claude-plugin/plugin.json

  Install:
    claude plugin marketplace add anthropics/claude-plugins-official
    claude plugin install ralph-loop@claude-plugins-official

  Or bypass this check (advanced): export IDD_SKIP_RALPH_CHECK=1
EOF
exit 1
