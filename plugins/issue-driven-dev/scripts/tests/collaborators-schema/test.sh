#!/usr/bin/env bash
# test.sh — schema-consistency drift guard for the collaborators[] identity
# registry (PsychQuant/issue-driven-development#86).
#
# #86 adds an OPTIONAL `collaborators[]` config array so IDD can resolve a
# person's alias / email / display-name → their GitHub @login WITHOUT guessing
# (feeds rules/tagging-collaborators.md Step 2-3 as a resolution accelerator).
# The schema is documented across THREE files that MUST agree:
#   - references/config-protocol.md   (schema source of truth + PII boundary)
#   - rules/tagging-collaborators.md  (consumer: table-lookup then verify)
#   - skills/idd-config/SKILL.md       (validate: schema checks)
#
# This is a C_shared_module_coord change, so the real failure mode is DRIFT:
# rename a field in one file, forget the other two, and the tagging protocol
# resolves against a stale schema. There is deliberately no behavioral test —
# the resolution itself is LLM-executed prose (consistent with the whole rules/
# corpus), so there is no resolver binary to unit-test. What IS mechanically
# checkable, and what breaks in practice, is that all three files still describe
# the same distinctive field set + the PII boundary. The needles below are
# 0-occurrence in all three files BEFORE #86 (verified), so each is a genuine
# drift signal, not a token that happens to pre-exist for another reason
# (`role`, e.g., pre-exists via groups[].repos[].role — deliberately not tested).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
ROOT="$(cd "$HERE/../../.." && pwd)"     # → plugins/issue-driven-dev

PROTOCOL="$ROOT/references/config-protocol.md"
TAGGING="$ROOT/rules/tagging-collaborators.md"
IDDCONFIG="$ROOT/skills/idd-config/SKILL.md"

echo "collaborators-schema (3-file drift guard, #86)"

# ── config-protocol.md — the schema source of truth ──
assert_output_grep "protocol declares the collaborators[] field"   "collaborators[" "$PROTOCOL"
assert_output_grep "protocol: github_login (required @-handle)"    "github_login"   "$PROTOCOL"
assert_output_grep "protocol: display_name (required real name)"   "display_name"   "$PROTOCOL"
assert_output_grep "protocol: aliases (optional fuzzy-match keys)" "aliases"        "$PROTOCOL"
assert_output_grep "protocol: PII boundary documented"             "PII"            "$PROTOCOL"

# ── tagging-collaborators.md — consumes the registry as a lookup accelerator ──
assert_output_grep "tagging references the collaborators[] registry" "collaborators[" "$TAGGING"
assert_output_grep "tagging resolves to github_login"                "github_login"   "$TAGGING"
# regression lock: a table HIT must STILL existence-verify (table can be stale).
assert_output_grep "tagging keeps the gh api users/ existence-verify" "users/"        "$TAGGING"

# ── skills/idd-config/SKILL.md — validate schema-checks the registry ──
assert_output_grep "idd-config validate covers collaborators[]"    "collaborators[" "$IDDCONFIG"
assert_output_grep "idd-config validate checks github_login format" "github_login"  "$IDDCONFIG"
assert_output_grep "idd-config validate checks aliases uniqueness"  "aliases"       "$IDDCONFIG"
# the PII-reminder contract lives in idd-config too — keep it anchored so it
# can't be dropped from validate while config-protocol.md still advertises it.
assert_output_grep "idd-config validate carries the PII reminder"   "PII"           "$IDDCONFIG"

print_summary
