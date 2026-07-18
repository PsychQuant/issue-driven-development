#!/usr/bin/env bash
# test.sh — drift-guard for the codex-channel dependency contract (#251 → #264).
#
# CONTRACT (v2 — #264 supersedes the #251 single-pin): IDD's tree contains NO
# vendored codex executable and NO model pin at all. The executable resolves
# from the parallel-ai-agents plugin cache (MIN_PAI ≥ 2.19.0, the
# codexModel/codexEffort contract floor); model/effort/max-time governance
# resolves from codex-pro's profile contract (MIN_CODEX_PRO ≥ 0.7.0,
# defaults.json + two profile.yaml layers) and is passed EXPLICITLY. A stale
# hard-pin, or a re-vendored bin/codex-call, fails here instead of drifting
# silently (the #251 failure class, now guarded one level up).
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
REPO_ROOT="$PLUGIN_ROOT/../.."
VERIFY="$PLUGIN_ROOT/skills/idd-verify/SKILL.md"
DIAGNOSE="$PLUGIN_ROOT/skills/idd-diagnose/SKILL.md"
ROUTE_RECOMMEND="$REPO_ROOT/plugins/idd-route/skills/idd-route-recommend/SKILL.md"
ROUTE_STATS="$REPO_ROOT/plugins/idd-route/skills/idd-route-stats/SKILL.md"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

assert_file_exists "idd-verify SKILL exists" "$VERIFY"
assert_file_exists "idd-diagnose SKILL exists" "$DIAGNOSE"
assert_file_exists "idd-route recommend SKILL exists" "$ROUTE_RECOMMEND"
assert_file_exists "idd-route stats SKILL exists" "$ROUTE_STATS"

# ── #264: no vendored executable — a re-vendor is a regression ──
if [ -e "$PLUGIN_ROOT/bin/codex-call" ]; then
  fail "no vendored codex-call in the tree" "bin/codex-call exists — the #264 dependency contract deletes it (executable belongs to pai)"
else
  pass "no vendored codex-call in the tree"
fi

# ── executable resolution: pai, version-gated at the codexModel contract floor ──
assert_output_grep "skill: pai codex-call resolution var"       'PAI_CODEX_CALL'        "$VERIFY"
assert_output_grep "skill: MIN_PAI gated at 2.19.0"             'MIN_PAI="2.19.0"'      "$VERIFY"

# ── governance resolution: codex-pro contract, fail-fast ──
assert_output_grep "skill: MIN_CODEX_PRO gate"                  'MIN_CODEX_PRO="0.7.0"' "$VERIFY"
assert_output_grep "skill: reads codex-pro defaults.json"       'defaults.json'         "$VERIFY"
assert_output_grep "skill: canonical tier passes codexModel"    'codexModel'            "$VERIFY"
assert_output_grep "skill: one-step install instruction"        'claude plugin install codex-pro@codex-pro' "$VERIFY"

# ── install-time dependency wiring ──
assert_output_grep "plugin.json: codex-pro dependency declared" '"codex-pro"'           "$PLUGIN_JSON"

# ── zero model pins in IDD's tree (generation-neutral prose only) ──
refute_output_grep "idd-verify: no stale gpt-5.5 hard-pin"      "gpt-5.5"          "$VERIFY"
assert_output_grep "idd-verify: prose is generation-neutral"    "gpt-5.x"          "$VERIFY"
refute_output_grep "idd-verify: no hardcoded --model gpt-5 pin" '--model gpt-5'    "$VERIFY"

# ── idd-diagnose: candidate stays generation-neutral ──
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
