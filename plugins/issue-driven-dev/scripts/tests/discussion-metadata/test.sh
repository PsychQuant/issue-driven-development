#!/usr/bin/env bash
# test.sh — drift-guard for the discussion-type metadata helper in idd-issue
# (PsychQuant/issue-driven-development#141 feature + #142 bug-prevention safeguards).
#
# SCOPE (artifact-level, like session-start-commit-rule/test.sh): this fixture
# asserts the SHIPPED SKILL.md PROSE that describes Step 3.5. It does NOT execute
# the AskUserQuestion helper (that is a Claude-runtime tool contract, unrunnable
# in a shell harness). What it locks is that the helper's contract — the
# `--discussion` trigger, the four advisory sub-steps, #142's 3 non-negotiable
# label safeguards, and the disclosed native-relationship deferral — cannot be
# silently deleted or reworded out of existence without turning this suite RED.
#
# LEAN-V1 (per feedback_lead_minimal): detection collapses to the `--discussion`
# flag + a config opt-in for the body heuristic (design Q1's own recommended
# default); the native-relationship GraphQL picker is DEFERRED (highest risk,
# reuses a not-yet-generalized code path) and disclosed as such. The fixture
# asserts the deferral is DOCUMENTED, not that the picker exists — a deferred
# item that vanishes from the prose is drift too.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL="$HERE/../../../skills/idd-issue/SKILL.md"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

echo "discussion-metadata helper drift-guard (#141 + #142)"

assert_file_exists "idd-issue SKILL.md exists" "$SKILL"

# ── #141: detection contract ────────────────────────────────────────────────
# --discussion is the PRIMARY (lean-v1 only) trigger; the body heuristic is
# opt-in behind a config key so a standard bug/feature issue never gets the
# 4-prompt ceremony (design Q1).
assert_output_grep "141 detection: --discussion flag documented"          "--discussion"                    "$SKILL"
assert_output_grep "141 detection: body heuristic is config opt-in"        "discussion_metadata_heuristic"   "$SKILL"

# ── #141: the helper section itself ─────────────────────────────────────────
assert_output_grep "141 helper: Step 3.5 section header present"           "Step 3.5: Discussion Metadata Helper" "$SKILL"
assert_output_grep "141 helper: bootstrap stage task named"                "discussion_metadata_helper"      "$SKILL"

# ── #141: advisory sub-steps (surface-only, never auto-set) ──────────────────
# (a) assignee reused from the tagging-collaborators-verified @login set.
assert_output_grep "141 (a) assignee: --add-assignee path documented"      "--add-assignee"                  "$SKILL"
# (b) label default is config-overridable (design Q2/Q3 + #142 Q3).
assert_output_grep "141 (b) label: config-overridable discussion_label"    "discussion_label"                "$SKILL"
# (c) milestone only on a time-bound signal — reuses Step 4.5 machinery.
assert_output_grep "141 (c) milestone: time-bound gate documented"         "time-bound"                      "$SKILL"
# (d) native relationship DEFERRED (lean cut) — deferral must be DISCLOSED.
assert_output_grep "141 (d) native relationship deferral disclosed"        "Native relationship suggestion (deferred" "$SKILL"

# ── #142: three non-negotiable label safeguards baked into Step 3.5 ──────────
# S1: never trust `gh label create`'s silent success — verify by reading back.
assert_output_grep "142 S1: verify-by-read after label create"             "VERIFY by reading back"          "$SKILL"
# S2: pre-add existence check for the --add-label path.
assert_output_grep "142 S2: pre-add label existence check"                 "Pre-add existence check"         "$SKILL"
# S3: UI cache-sync hint — the exact confusing string + the remedy.
assert_output_grep "142 S3: cache-lag hint names the 'Invalid value' string" "Invalid value"                 "$SKILL"
assert_output_grep "142 S3: cache-lag hint gives hard-refresh remedy"       "hard refresh"                    "$SKILL"

print_summary "discussion-metadata (#141 + #142)"
