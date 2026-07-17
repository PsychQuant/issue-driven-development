#!/usr/bin/env bash
# test.sh — drift-guard for #251 model-generation sync.
#
# CONTRACT: the codex model generation is pinned in EXACTLY ONE place —
# bin/codex-call's default. Every other site is generation-neutral: SKILL
# prose says gpt-5.x, codex invocations inherit the default (no explicit
# --model gpt-5.*), and the idd-route candidate is `codex-xhigh`. When the
# next generation ships, the bump touches codex-call + this suite's pin
# needle; any stale hard-pin elsewhere fails here instead of drifting silently
# (the #251 failure class: docs said gpt-5.5 long after the default moved).
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
REPO_ROOT="$PLUGIN_ROOT/../.."
CODEX_CALL="$PLUGIN_ROOT/bin/codex-call"
VERIFY="$PLUGIN_ROOT/skills/idd-verify/SKILL.md"
DIAGNOSE="$PLUGIN_ROOT/skills/idd-diagnose/SKILL.md"
ROUTE_RECOMMEND="$REPO_ROOT/plugins/idd-route/skills/idd-route-recommend/SKILL.md"
ROUTE_STATS="$REPO_ROOT/plugins/idd-route/skills/idd-route-stats/SKILL.md"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

assert_file_exists "codex-call exists" "$CODEX_CALL"
assert_file_exists "idd-verify SKILL exists" "$VERIFY"
assert_file_exists "idd-diagnose SKILL exists" "$DIAGNOSE"
assert_file_exists "idd-route recommend SKILL exists" "$ROUTE_RECOMMEND"
assert_file_exists "idd-route stats SKILL exists" "$ROUTE_STATS"

# ── single pin point: codex-call default (bump this needle with the next generation) ──
assert_output_grep "codex-call: default pinned to gpt-5.6-sol"  'var model: String = "gpt-5.6-sol"' "$CODEX_CALL"

# ── idd-verify: generation-neutral prose, invocations inherit the default ──
refute_output_grep "idd-verify: no stale gpt-5.5 hard-pin"      "gpt-5.5"          "$VERIFY"
assert_output_grep "idd-verify: prose is generation-neutral"    "gpt-5.x"          "$VERIFY"
refute_output_grep "idd-verify: codex invocation inherits default (no explicit --model gpt-5)" "--model gpt-5" "$VERIFY"

# ── idd-diagnose: candidate renamed to generation-neutral ──
refute_output_grep "idd-diagnose: old candidate name gone"      "codex-gpt-5.5-xhigh" "$DIAGNOSE"
assert_output_grep "idd-diagnose: codex-xhigh candidate"        "codex-xhigh"      "$DIAGNOSE"

# ── references: same neutrality contract ──
AGENT_ROUTING="$PLUGIN_ROOT/references/agent-routing.md"
EXT_DELEG="$PLUGIN_ROOT/references/external-agent-delegation.md"
assert_file_exists "agent-routing.md exists" "$AGENT_ROUTING"
assert_file_exists "external-agent-delegation.md exists" "$EXT_DELEG"
refute_output_grep "agent-routing: old candidate name gone"     "codex-gpt-5.5-xhigh" "$AGENT_ROUTING"
refute_output_grep "external-agent-delegation: no stale gpt-5.5" "gpt-5.5"         "$EXT_DELEG"

# ── idd-route: candidate renamed + migration note preserves history ──
refute_output_grep "idd-route recommend: old candidate gone"    "codex-gpt-5.5-xhigh" "$ROUTE_RECOMMEND"
assert_output_grep "idd-route recommend: codex-xhigh in defaults" "codex-xhigh"    "$ROUTE_RECOMMEND"
assert_output_grep "idd-route stats: migration note exists"     "Candidate 命名遷移" "$ROUTE_STATS"
assert_output_grep "idd-route stats: old records kept as history" "保留為歷史"       "$ROUTE_STATS"

print_summary "model-generation-sync"
