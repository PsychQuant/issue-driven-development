#!/usr/bin/env bash
# test.sh — drift-guard for #269 idd-comment --type=reply (change
# add-idd-comment-reply-type, spec idd-comment-reply ADDED requirements).
#
# WHY A CONTENT DRIFT-GUARD (not an execution harness): idd-comment is a prose
# SKILL.md. "Invoke --type=reply without --points-from → assert refusal" cannot
# be executed here. The falsifiable equivalent is asserting the reply-type
# contract exists verbatim at its SKILL sites: the type table + Step 2
# required-field row (validation), the reply template (per-point structure +
# metadata marker), the points-source three-layer chain + verbatim ban, the
# verify-before-claim gate, the perspective-writer soft-integration step
# (presence-check coordinates + the two degrade install literals + no
# install-time dependency), and the anchoring-precedes-calibration invariant.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
SKILL="$PLUGIN_ROOT/skills/idd-comment/SKILL.md"
COMMANDS_DOC="$PLUGIN_ROOT/../../docs/commands.md"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

# ── type registration + required-field validation (spec: Reply comment type) ──
assert_output_grep "skill: reply listed in type table"          "| \`reply\` |"                    "$SKILL"
assert_output_grep "skill: Step 2 requires --points-from"       "reply | \`--points-from\` 必存在"  "$SKILL"

# ── reply template: per-point structure + metadata marker ──
assert_output_grep "skill: reply template section"              "#### Template: \`reply\`"          "$SKILL"
assert_output_grep "skill: metadata marker records type"        "idd:comment type=reply"           "$SKILL"
assert_output_grep "skill: marker records calibration outcome"  "calibrated={yes|no}"              "$SKILL"

# ── points-source three-layer chain + verbatim ban (spec: Points-source resolution) ──
assert_output_grep "skill: issue-body source literal"           "\`issue-body\`"                   "$SKILL"
assert_output_grep "skill: default = Original text blockquote"  "Original text" "$SKILL"
assert_output_grep "skill: verbatim ban on counterpart's words" "禁止 paraphrase 對方原文"           "$SKILL"

# ── verify-before-claim gate (spec: Verify-before-claim gate) ──
assert_output_grep "skill: evidence check before claiming"      "git log --grep" "$SKILL"
assert_output_grep "skill: unevidenced points stay honest"      "無證據的點必須寫 open / pending"     "$SKILL"

# ── perspective-writer soft integration (spec: soft integration with graceful degrade) ──
assert_output_grep "skill: presence-check coordinates"          "check-plugin-presence.sh perspective-writer perspective-writer" "$SKILL"
assert_output_grep "skill: degrade install literal (marketplace)" "claude plugin marketplace add PsychQuant/perspective-writer"   "$SKILL"
assert_output_grep "skill: degrade install literal (install)"   "claude plugin install perspective-writer@perspective-writer"    "$SKILL"
assert_output_grep "skill: calibration via skill invocation"    "perspective-writer:perspective-writer" "$SKILL"
assert_output_grep "skill: no install-time dependency"          "不新增 install-time \`dependencies\` 條目" "$SKILL"

# ── ordering invariant (spec: Anchoring precedes calibration) ──
assert_output_grep "skill: anchoring precedes calibration"      "錨定完成後才進 calibration"          "$SKILL"
assert_output_grep "skill: calibration must not alter anchors"  "calibration 不得改動錨定事實"        "$SKILL"

# ── additive audit posture (spec: Additive audit posture and egress discipline) ──
assert_output_grep "skill: reply is additive to closing summary" "closing summary 的加項"            "$SKILL"

# ── docs catalog: commands.md lists the new type ──
assert_output_grep "docs: commands.md type enumeration has reply" "reply" "$COMMANDS_DOC"

print_summary "idd-comment-reply"
