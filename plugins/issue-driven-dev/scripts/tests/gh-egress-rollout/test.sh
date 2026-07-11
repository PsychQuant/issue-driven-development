#!/usr/bin/env bash
# test.sh — drift-guard for the #226 gh-egress wider rollout (Phase 2 of #202).
#
# Phase 1 wired only idd-issue; every other skill's comment/edit egress went
# raw `gh issue comment|edit` — no attestation gate, no privacy/mention nets,
# leaving #117's headline scenario (comment @mention) mechanically unenforced.
# This suite locks the Phase-2 wiring: each rolled-out SKILL routes its
# executable comment/edit call sites through scripts/gh-egress.sh with a
# --scrub-attested level, and the exact pre-rollout raw call lines are GONE
# (refuted verbatim, so a revert or a copy-paste regression turns RED).
#
# Whitelist (deliberately NOT wired / not egress):
#   - `gh issue close`            — not a content egress verb (wrapper scope is
#                                   create|comment|edit per #202 D2)
#   - `gh api ... PATCH comments` — idd-edit / audit-block PATCH surgery goes
#                                   through gh api (comment-id scoped), tracked
#                                   separately; wrapper wraps `gh issue` verbs
#   - prose/table MENTIONS of `gh issue comment` (rules text, rationale) — only
#     executable call lines were wired
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
SK="$PLUGIN_ROOT/skills"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

# ── every rolled-out skill routes egress through the wrapper ──
for sk in idd-comment idd-diagnose idd-implement idd-verify idd-close idd-update; do
  assert_output_grep "$sk: routes egress via gh-egress.sh" "gh-egress.sh" "$SK/$sk/SKILL.md"
  assert_output_grep "$sk: carries a scrub attestation"    "--scrub-attested" "$SK/$sk/SKILL.md"
done

# ── the exact pre-rollout raw call lines are gone (verbatim refutes) ──
refute_output_grep "idd-comment: raw body-file comment gone" \
  'gh issue comment $NUMBER --repo $GITHUB_REPO --body-file /tmp/idd-comment-$$.md' \
  "$SK/idd-comment/SKILL.md"
refute_output_grep "idd-diagnose: raw diagnosis-report comment gone" \
  'gh issue comment $NUMBER --repo $GITHUB_REPO --body "$DIAGNOSIS_REPORT"' \
  "$SK/idd-diagnose/SKILL.md"
refute_output_grep "idd-implement: raw implementation-plan comment gone" \
  'gh issue comment $NUMBER --repo $GITHUB_REPO --body "$IMPLEMENTATION_PLAN"' \
  "$SK/idd-implement/SKILL.md"
refute_output_grep "idd-verify: raw merged-findings comment gone" \
  'gh issue comment $NUMBER --repo $GITHUB_REPO --body "$MERGED_FINDINGS"' \
  "$SK/idd-verify/SKILL.md"
refute_output_grep "idd-close: raw closing-comment capture gone" \
  'CLOSING_COMMENT_URL=$(gh issue comment $NUMBER --repo $GITHUB_REPO --body "$CLOSING_COMMENT")' \
  "$SK/idd-close/SKILL.md"
refute_output_grep "idd-update: raw body edit gone" \
  'gh issue edit $NUMBER --repo $GITHUB_REPO --body "$UPDATED_BODY"' \
  "$SK/idd-update/SKILL.md"

# ── level resolution is cited, not re-invented per skill ──
for sk in idd-comment idd-diagnose idd-implement idd-verify idd-close idd-update; do
  assert_output_grep "$sk: cites privacy-scrubbing rule for \$SCRUB_LEVEL" "privacy-scrubbing" "$SK/$sk/SKILL.md"
done

print_summary "gh-egress-rollout (#226)"
