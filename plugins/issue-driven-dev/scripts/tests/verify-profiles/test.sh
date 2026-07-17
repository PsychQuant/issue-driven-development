#!/usr/bin/env bash
# test.sh — drift-guard for #258 composable verification profiles
# (change verify-profiles, spec idd-verify ADDED requirements).
#
# WHY A CONTENT DRIFT-GUARD (not an execution harness): idd-verify is a prose
# SKILL.md. "Run --profile prose --file X → assert prose lenses dispatched"
# cannot be executed here. The falsifiable equivalent is asserting the profile
# contract exists verbatim at its three sites: the canonical reference (single
# source for the four-tuple), the SKILL (flags + input resolution + freshness
# mirror), and config-protocol (custom-profile schema + collision rule). The
# code-default-unchanged sentence is the backward-compat lock.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
REF="$PLUGIN_ROOT/references/verify-profiles.md"
VERIFY="$PLUGIN_ROOT/skills/idd-verify/SKILL.md"
PROTO="$PLUGIN_ROOT/references/config-protocol.md"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

# ── canonical reference: single source for the profile four-tuple ──
assert_file_exists "references/verify-profiles.md exists" "$REF"
assert_output_grep "ref: built-in code profile section"        "## Profile: code"     "$REF"
assert_output_grep "ref: built-in prose profile section"       "## Profile: prose"    "$REF"
assert_output_grep "ref: built-in academic profile section"    "## Profile: academic" "$REF"
assert_output_grep "ref: prose lens — factual accuracy"        "factual-accuracy-vs-source" "$REF"
assert_output_grep "ref: prose lens — PII/PHI leak"            "pii-phi-leak"         "$REF"
assert_output_grep "ref: prose lens — citation support"        "citation-support"     "$REF"
assert_output_grep "ref: file freshness contract (SHA-256)"    "SHA-256"              "$REF"

# ── SKILL: flags, input resolution, backward-compat lock, freshness mirror ──
assert_output_grep "skill: --profile flag documented"          "--profile"            "$VERIFY"
assert_output_grep "skill: --file input source"                "--file <path>"        "$VERIFY"
assert_output_grep "skill: --dir input source"                 "--dir <path>"         "$VERIFY"
assert_output_grep "skill: mutual exclusion with git sources"  "互斥"                  "$VERIFY"
assert_output_grep "skill: code default unchanged (verbatim lock)" "（預設）＝今日行為，逐 byte 不變" "$VERIFY"
assert_output_grep "skill: unknown profile fails loud"         "可用 profile 清單"     "$VERIFY"
assert_output_grep "skill: file freshness gate mirror"         "FROZEN_HASHES"        "$VERIFY"
assert_output_grep "skill: cites the canonical reference"      "references/verify-profiles.md" "$VERIFY"

# ── config-protocol: custom profiles + collision rule ──
assert_output_grep "config: verify_profiles field"             "### \`verify_profiles\` field" "$PROTO"
assert_output_grep "config: built-in wins on collision"        "內建勝"                "$PROTO"

print_summary "verify-profiles"
