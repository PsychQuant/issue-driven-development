#!/usr/bin/env bash
# check-plugin-presence.sh — generic Claude Code plugin presence detector
#
# Usage:
#   check-plugin-presence.sh <marketplace> <plugin-name>
#
# Examples:
#   check-plugin-presence.sh claude-plugins-official ralph-loop
#   check-plugin-presence.sh psychquant-claude-plugins che-word-mcp
#
# Used by:
#   - idd-issue Step 1 Source Type Adapter (#27 fail-fast for .docx / Telegram / Mail / Notes)
#   - scripts/check-ralph-loop.sh (wrapper for backward-compat from #28)
#
# Exit:
#   0 — plugin installed (or IDD_SKIP_PLUGIN_CHECK=1)
#   1 — plugin missing
#   2 — usage error (wrong arg count)
#
# Detect path is hardcoded against Claude Code 2025-Q4 plugin cache schema.
# When schema changes upstream, see #35 (path schema watch-list).
#
# Trust model (#41):
#   This script trusts the filesystem — presence of the plugin.json file
#   inside ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/.claude-plugin/
#   counts as "plugin installed". NO signature/hash/integrity verification.
#
#   Implications:
#   - Single-user dev environments (macOS local install): trust model is fine
#   - Shared dev containers / CI runners / multi-user shared $HOME: a hostile
#     party can plant an empty plugin.json skeleton in the cache path to fake
#     detect → IDD will run --loop / source-type adapter as if plugin present
#   - Caller's responsibility to harden if running in untrusted environment:
#     either pre-validate the plugin install via `claude plugin list` or set
#     IDD_SKIP_PLUGIN_CHECK=1 and accept the bypass cost
#
# Future hardening (#41 reopen criteria): if multi-user / CI deployment becomes
# common, evaluate hash verification step against marketplace-published manifest.

set -u

# Usage check
if [ $# -ne 2 ]; then
  cat >&2 <<EOF
Usage: $(basename "$0") <marketplace> <plugin-name>

Examples:
  $(basename "$0") claude-plugins-official ralph-loop
  $(basename "$0") psychquant-claude-plugins che-word-mcp
EOF
  exit 2
fi

MARKETPLACE="$1"
PLUGIN="$2"

# Escape hatch — let user bypass detect (#28 risk mitigation, #27 inheritance).
# Print stderr warning so this leaves an audit trail.
if [ "${IDD_SKIP_PLUGIN_CHECK:-}" = "1" ]; then
  echo "⚠ IDD_SKIP_PLUGIN_CHECK=1 set — skipping ${MARKETPLACE}/${PLUGIN} detection (advanced override)" >&2
  echo "  Caller will run as if ${PLUGIN} is installed." >&2
  exit 0
fi

# Plugin cache layout (Claude Code 2025-Q4):
#   ~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/.claude-plugin/plugin.json
# Match any installed version under the plugin dir.
#
# Use bash array + nullglob (NOT unquoted `for f in $GLOB`) to handle HOME with
# whitespace correctly (per #28 F3 verify finding).
shopt -s nullglob
files=( "${HOME}/.claude/plugins/cache/${MARKETPLACE}/${PLUGIN}"/*/.claude-plugin/plugin.json )
shopt -u nullglob

if (( ${#files[@]} > 0 )); then
  exit 0
fi

cat >&2 <<EOF
✗ ${PLUGIN} plugin not found.
  Searched: ~/.claude/plugins/cache/${MARKETPLACE}/${PLUGIN}/*/.claude-plugin/plugin.json

  Install:
    claude plugin marketplace add <owner>/${MARKETPLACE}
    claude plugin install ${PLUGIN}@${MARKETPLACE}

  Or bypass this check (advanced): export IDD_SKIP_PLUGIN_CHECK=1
EOF
exit 1
