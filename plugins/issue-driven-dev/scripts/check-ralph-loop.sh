#!/usr/bin/env bash
# check-ralph-loop.sh — backward-compat wrapper around check-plugin-presence.sh
#
# v2.54+ (#34 refactor): the actual detection logic moved to
# scripts/check-plugin-presence.sh which accepts <marketplace> <plugin>.
# This wrapper is preserved so #28's existing callers continue to work:
#   - idd-verify --loop Step 0a fail-fast
#   - idd-all Phase 0.6 graceful degrade gate
#
# Both `IDD_SKIP_RALPH_CHECK=1` and `IDD_SKIP_PLUGIN_CHECK=1` are honored
# (legacy + new env var name).
#
# Exit codes inherited from check-plugin-presence.sh:
#   0 — installed
#   1 — missing

# Honor legacy env var name from #28 v2.53.
if [ "${IDD_SKIP_RALPH_CHECK:-}" = "1" ]; then
  export IDD_SKIP_PLUGIN_CHECK=1
fi

exec "$(dirname "$0")/check-plugin-presence.sh" claude-plugins-official ralph-loop
