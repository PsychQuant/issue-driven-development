#!/usr/bin/env bash
# Test: check-closed-without-summary.sh classifies CLOSED issues by what their
# `## Closing Summary` marker looks like — the retroactive safety net for the
# direct-commit auto-close trap (#151), made four-way by #295.
#
# Fixture `mixed.json`:
#   #100 CLOSED + canonical heading, own comment → own-comment (not listed)
#   #101 CLOSED + no  Closing Summary            → MISSING
#   #102 OPEN   + no  Closing Summary            → not listed (only closed audited)
#   #103 CLOSED + zero comments                  → MISSING (legacy / UI-close)
#   #104 CLOSED + `## Closing summary`           → CASING       (#295)
#   #105 CLOSED + summary inside the IC comment  → MID-COMMENT  (#295)
#   #106 CLOSED + `## Closing Summary (retro…)`  → own-comment  (#295 D2)
#   #107 CLOSED + `## closing summary_v2`        → CASING       (#295 D3)
#
# Why four classes and not two (#295): the two-way `startswith` misreported 11
# of 43 closed issues in a real repo (26%), and `/idd-close --retroactive`
# shares the same marker as its precondition — so a false positive there does
# not merely add noise, it posts a duplicate summary onto an issue that already
# has one. Only MISSING may reach that path.
#
# Usage: bash test.sh   (exit 0 = pass, 1 = fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$(cd "$HERE/../.." && pwd)/check-closed-without-summary.sh"   # scripts/check-closed-without-summary.sh
FIXTURE="$HERE/fixtures/mixed.json"

# Shared assertion helpers (#156) — require/refute/assert_grep bake in the `--`
# end-of-options separator, so a needle like '--state closed' is matched as data.
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"

if [ ! -f "$HELPER" ]; then
  echo "  ✗ helper not found: $HELPER"
  echo "FAIL: helper missing"
  exit 1
fi

OUT=$(bash "$HELPER" --json-file "$FIXTURE" 2>/dev/null)
RC=$?

# Section extractor (#295): headers are non-indented and carry the class name;
# entries are indented. A section ends at the next non-indented line.
section_body() { # $1 = anchor substring of the section header
  printf '%s\n' "$OUT" | awk -v a="$1" '
    index($0, a) { insec = 1; next }
    insec && /^[^ ]/ { insec = 0 }
    insec { print }
  '
}

# Domain predicate: is issue #$2 listed under the section anchored by $1?
# (#$2 is always a digit run, so the composed pattern can never start with `--`;
# `--` added anyway for uniform discipline.)
in_section() { section_body "$1" | grep -qE -- "(^|[^0-9])#$2([^0-9]|$)"; }

# `flagged` keeps its original meaning — "would be sent to --retroactive" —
# which after #295 is exactly the MISSING class. The four assertions below are
# unchanged from the two-way era on purpose: they are the regression lock that
# proves widening the classifier did not weaken the safety net.
flagged() { in_section "MISSING —" "$1"; }

require "#101 (closed, no summary) is flagged"        flagged 101
require "#103 (closed, zero comments) is flagged"     flagged 103
refute  "#100 (closed WITH summary) is NOT flagged"   flagged 100
refute  "#102 (open) is NOT flagged"                  flagged 102
assert_exit "advisory exit 0 on mixed fixture" 0 "$RC"

# ── #295: the three classes that are NOT missing work ──
# Each must stay out of MISSING (that is the destructive path) AND land in its
# own section (that is the information the two-way marker threw away).

require "#104 (lowercase heading) is listed under CASING"        in_section "CASING —" 104
refute  "#104 is NOT in MISSING (summary exists)"                flagged 104

require "#105 (summary inside IC comment) is under MID-COMMENT"  in_section "MID-COMMENT —" 105
refute  "#105 is NOT in MISSING (summary exists)"                flagged 105

# D2 — `## Closing Summary (retroactive — …)` satisfies the canonical prefix by
# design (idd-close SKILL.md: remediated issues must not be re-surfaced). It has
# to classify as own-comment, i.e. appear in NO section at all.
refute  "#106 (retroactive heading) is NOT in MISSING"           flagged 106
refute  "#106 (retroactive heading) is NOT in CASING"            in_section "CASING —" 106
refute  "#106 (retroactive heading) is NOT in MID-COMMENT"       in_section "MID-COMMENT —" 106

# D3 — no `\b` after `summary`: `_` is a word character, so a trailing word
# boundary would refuse `summary_v2` and misfile a present summary as MISSING.
require "#107 (summary_v2 heading) is listed under CASING"             in_section "CASING —" 107
refute  "#107 (summary_v2 heading) is NOT in MISSING"                  flagged 107

# The non-MISSING sections must never invite the destructive remediation.
# Scoped per section, not grepped over the whole output: an acid run showed a
# whole-output grep stays green when ONE section loses the warning, because the
# other still carries it — the assertion was satisfied from somewhere it was
# not meant to guard.
section_header() { printf '%s\n' "$OUT" | grep -F -- "$1" | head -1; }

assert_grep "MISSING header is the one that invites --retroactive" \
  "idd-close --retroactive" "$(section_header 'MISSING —')"
assert_grep "CASING header warns off --retroactive" \
  "do NOT run --retroactive" "$(section_header 'CASING —')"
assert_grep "MID-COMMENT header warns off --retroactive" \
  "do NOT run --retroactive" "$(section_header 'MID-COMMENT —')"
refute_grep "CASING header does not invite the destructive path" \
  "remediate: idd-close --retroactive" "$(section_header 'CASING —')"
refute_grep "MID-COMMENT header does not invite the destructive path" \
  "remediate: idd-close --retroactive" "$(section_header 'MID-COMMENT —')"

# Only MISSING entries carry the warning glyph.
refute_grep "a CASING entry never carries the MISSING warning glyph" "⚠ #104" "$OUT"
refute_grep "a MID-COMMENT entry never carries the MISSING warning glyph" "⚠ #105" "$OUT"

# --dry-run: assert the live-gh branch composes the right gh invocation, with NO
# network (closes the untested-executable-seam gap, #151 verify DA/logic LOW).
DRY=$(bash "$HELPER" --repo foo/bar --since 2026-01-01 --limit 5 --dry-run 2>/dev/null)
assert_grep    "--dry-run gh args have '--state closed'" "--state closed"      "$DRY"
assert_grep    "--dry-run gh args have '--repo foo/bar'" "--repo foo/bar"      "$DRY"
assert_grep    "--dry-run gh args have '--limit 5'"      "--limit 5"           "$DRY"
assert_grep    "--dry-run composes '--since' search"     "closed:>=2026-01-01" "$DRY"

# Malformed JSON must NOT yield a false "all-clear" (safety-net direction, #151 verify logic LOW).
MAL=$(bash "$HELPER" --json-file "$HERE/fixtures/malformed.json" 2>/dev/null); MRC=$?
refute_grep "malformed JSON does NOT produce a FALSE all-clear" "No closed issue is missing" "$MAL"
assert_exit "malformed JSON: advisory exit 0" 0 "$MRC"

print_summary "check-closed-without-summary"
exit $?
