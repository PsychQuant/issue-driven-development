#!/usr/bin/env bash
# test.sh — drift-guard for selective git auto-tag (#85).
#
# #85 adds selective git-tag automation at two IDD milestones:
#   - idd-issue creates `idd-{N}-baseline` (main HEAD at issue-open = rollback anchor)
#   - idd-verify creates `idd-{N}-verified` on Aggregate PASS (review snapshot)
# opt-out via config `auto_tag.enabled`, idempotent, graceful-skip on push failure.
#
# WHY A CONTENT DRIFT-GUARD: the tag behaviors live in prose SKILL.md files
# (idd-issue Step 0/creation, idd-verify Aggregate-PASS branch) + a config schema
# (config-protocol.md) — AI prompts, not executable code. The falsifiable
# equivalent is asserting each file encodes the tag contract. The schema is
# documented across files that MUST agree; the failure mode is DRIFT (rename a
# format key in the schema, forget the SKILL that references it). Needles below
# are distinctive to #85 (0-occurrence before the change), so each is a genuine
# drift signal.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
PROTOCOL="$PLUGIN_ROOT/references/config-protocol.md"
ISSUE="$PLUGIN_ROOT/skills/idd-issue/SKILL.md"
VERIFY="$PLUGIN_ROOT/skills/idd-verify/SKILL.md"
README="$PLUGIN_ROOT/README.md"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

assert_file_exists "config-protocol.md exists" "$PROTOCOL"
assert_file_exists "idd-issue SKILL.md exists" "$ISSUE"
assert_file_exists "idd-verify SKILL.md exists" "$VERIFY"
assert_file_exists "plugin README.md exists" "$README"

# ── config-protocol.md: the auto_tag schema (source of truth) ──
assert_output_grep "protocol: declares the auto_tag field section" "### \`auto_tag\` field" "$PROTOCOL"
assert_output_grep "protocol: auto_tag config key"                 "auto_tag"               "$PROTOCOL"
assert_output_grep "protocol: enabled key (default-on / opt-out)"  "enabled"                "$PROTOCOL"
assert_output_grep "protocol: baseline_format key"                 "baseline_format"        "$PROTOCOL"
assert_output_grep "protocol: verified_format key"                 "verified_format"        "$PROTOCOL"
assert_output_grep "protocol: push_remote key"                     "push_remote"            "$PROTOCOL"
assert_output_grep "protocol: baseline tag naming default"         "idd-{N}-baseline"       "$PROTOCOL"
assert_output_grep "protocol: verified tag naming default"         "idd-{N}-verified"       "$PROTOCOL"
# default-ON must be explicit + opt-out documented (user decision 2026-07-09)
assert_output_grep "protocol: default-on documented"               "default"                "$PROTOCOL"
assert_output_grep "protocol: opt-out documented"                  "enabled: false"         "$PROTOCOL"
# tag push is a repo-wide side effect — must be surfaced so default-on isn't a surprise
assert_output_grep "protocol: push side-effect surfaced"           "side effect"            "$PROTOCOL"

# ── idd-issue: baseline tag after issue creation ──
assert_output_grep "idd-issue: tag_baseline bootstrap step"        "tag_baseline"           "$ISSUE"
assert_output_grep "idd-issue: baseline tag naming"                "idd-{N}-baseline"       "$ISSUE"
assert_output_grep "idd-issue: gated on auto_tag config"           "auto_tag"               "$ISSUE"
assert_output_grep "idd-issue: idempotent (tag exists → skip)"     "idempotent"             "$ISSUE"
assert_output_grep "idd-issue: graceful-skip on push failure"      "graceful-skip"          "$ISSUE"
# never abort the workflow on tag failure (warn-continue discipline)
assert_output_grep "idd-issue: tag failure never aborts"           "never abort"            "$ISSUE"

# ── idd-verify: verified tag on Aggregate PASS ──
assert_output_grep "idd-verify: tag_verified bootstrap step"       "tag_verified"           "$VERIFY"
assert_output_grep "idd-verify: verified tag naming"               "idd-{N}-verified"       "$VERIFY"
assert_output_grep "idd-verify: gated on auto_tag config"          "auto_tag"               "$VERIFY"
assert_output_grep "idd-verify: fires on Aggregate PASS"           "Aggregate PASS"         "$VERIFY"

# ── README: discoverability note ──
assert_output_grep "README: auto-tag convention documented"        "auto_tag"               "$README"
assert_output_grep "README: baseline/verified naming shown"        "idd-{N}-baseline"       "$README"

print_summary "auto-tag (#85)"
