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

require "#105 (summary inside IC comment) is under MID-COMMENT"  in_section "MID-COMMENT (unverified)" 105
refute  "#105 is NOT in MISSING (summary exists)"                flagged 105

# D2 — `## Closing Summary (retroactive — …)` satisfies the canonical prefix by
# design (idd-close SKILL.md: remediated issues must not be re-surfaced). It has
# to classify as own-comment, i.e. appear in NO section at all.
refute  "#106 (retroactive heading) is NOT in MISSING"           flagged 106
refute  "#106 (retroactive heading) is NOT in CASING"            in_section "CASING —" 106
refute  "#106 (retroactive heading) is NOT in MID-COMMENT"       in_section "MID-COMMENT (unverified)" 106

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
  "do NOT run --retroactive" "$(section_header 'MID-COMMENT (unverified)')"
refute_grep "CASING header does not invite the destructive path" \
  "remediate: idd-close --retroactive" "$(section_header 'CASING —')"
refute_grep "MID-COMMENT header does not invite the destructive path" \
  "remediate: idd-close --retroactive" "$(section_header 'MID-COMMENT (unverified)')"

# Glyph policy after the #295 verify round: ⚠ marks "a human still has to look",
# which is true of MISSING and of MID-COMMENT (the tool cannot tell a real
# summary from a quoted one there). CASING is the only class the tool has
# actually established, so it is the only one printed without the glyph.
assert_grep "MID-COMMENT entries carry ⚠ (unverified, needs a human)" "⚠ #105" "$OUT"
refute_grep "a CASING entry never carries the warning glyph" "⚠ #104" "$OUT"

# ── #295 R2: a quoted heading is not a summary (the verify round's H1) ──
# Every one of these has NO summary; each was classified as mid-comment by the
# first implementation, printed with "the summary IS there", and thereby
# exonerated. All three must sit in MISSING.

require "#108 (heading only inside a fenced block) is MISSING"     flagged 108
require "#109 (heading only inside an HTML comment) is MISSING"    flagged 109
require "#110 (heading with zero content under it) is MISSING"     flagged 110

# The converse — a genuine summary merged into the IC comment — must survive as
# MID-COMMENT, or the fix has simply collapsed the class into missing.
require "#111 (genuine merged summary) is still MID-COMMENT"       in_section "MID-COMMENT (unverified)" 111
refute  "#111 is NOT in MISSING"                                   flagged 111

# ── #295 R2: the title is untrusted data (the verify round's H2) ──
# `class\t#N  title` is parsed positionally downstream, so an unescaped newline
# in a title forged a whole row — into the one section that invites the
# irreversible --retroactive.

refute_grep "a newline in a title cannot forge a row"  "#9999  FABRICATED ENTRY" "$OUT"
require    "#112 (whose title carries the payload) is itself compliant" \
  bash -c '! printf "%s\n" "$0" | grep -qE -- "(^|[^0-9])#112([^0-9]|$)"' "$OUT"
assert_grep "a tab in a title no longer truncates it" "tab here in title" "$OUT"

# A 4-space-indented heading is an indented code block, not a heading. This
# guards `live_lines`, NOT the `^ {0,3}` cap in `head_re` — acid showed the cap
# is strictly redundant once `live_lines` drops indented lines, so no input can
# distinguish the two and the cap has no test of its own (labelled as such in
# the script).
require "#114 (heading indented 4 spaces) is MISSING, not a heading" flagged 114

# ── #295 R3: what round 2 broke ──
# Round 2 used the live-markdown list to answer BOTH "where is the heading" and
# "is there content under it". The second use was wrong — content inside a fence
# is still content — and an over-broad `<!--` rule deleted whole lines. Both sent
# REAL summaries to MISSING, the one class --retroactive admits.

require "#115 (heading carries an inline HTML marker) is NOT missing" \
  bash -c '! printf "%s\n" "$0" | grep -qE -- "⚠ #115"' "$OUT"
require "#116 (summary body entirely inside a fence) is NOT missing" \
  bash -c '! printf "%s\n" "$0" | grep -qE -- "⚠ #116"' "$OUT"

# The converse of the content rule: an EMPTY summary must not be rescued by an
# unrelated later section. Round 3's first cut widened the check to every raw
# line after the heading, which made exactly that mistake.
require "#117 (empty summary, unrelated later section) is MISSING" flagged 117

# H2 again, one field to the left: `.number` is untrusted too.
refute_grep "a newline in .number cannot forge a row" "#9999  FORGED VIA NUMBER" "$OUT"

# The two HTML mechanisms mask each other under naive mutation — the anchored
# block rule makes the span-strip look redundant, and the span-strip makes
# un-anchoring look harmless. Each fixture below isolates ONE of them, so acid
# on either mechanism turns exactly one assertion red.
require "#119 (line starting with a balanced HTML comment) is NOT missing" \
  bash -c '! printf "%s\n" "$0" | grep -qE -- "⚠ #119"' "$OUT"
# #120's heading sits after a `---`, so it is legitimately `mid-comment` — which
# now carries ⚠. The assertion is therefore "not in MISSING", not "no ⚠": the
# first draft asserted the latter and failed on correct behaviour.
refute "#120 (unbalanced HTML-comment opener mid-line) is NOT missing" flagged 120

# Isolates `strip_html_span`: an IDD marker on its own line immediately above a
# real summary — the exact shape this plugin writes (`<!-- idd:dashboard -->`
# and friends). Without the span-strip the anchored block rule fires on the
# marker line, never finds its `-->` (it was on that same consumed line), and
# swallows the summary into MISSING — a real summary on the destructive path.
refute "#121 (IDD marker line above a real summary) is NOT missing" flagged 121

# The advisory contract's fail-safe direction, for the classification filter
# itself: a jq error must not fall through to "✓ nothing missing". Acid showed
# swallowing the error turned nothing red — the old test only covered the
# malformed-JSON guard, one layer earlier.
BADJQ=$(bash "$HELPER" --json-file "$HERE/fixtures/nonstring-body.json" 2>/dev/null); BJRC=$?
refute_grep "a jq failure does NOT produce a false all-clear" "No closed issue is missing" "$BADJQ"
assert_exit "a jq failure still exits 0 (advisory)" 0 "$BJRC"

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
