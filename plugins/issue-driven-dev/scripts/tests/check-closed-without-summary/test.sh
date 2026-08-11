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
# The advisory bucket: a heading exists somewhere, nothing was established.
unverified() { in_section "PRESENT (unverified)" "$1"; }

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

require "#105 (summary inside IC comment) is under PRESENT"      unverified 105
refute  "#105 is NOT in MISSING (summary exists)"                flagged 105

# D2 — `## Closing Summary (retroactive — …)` satisfies the canonical prefix by
# design (idd-close SKILL.md: remediated issues must not be re-surfaced). It has
# to classify as own-comment, i.e. appear in NO section at all.
refute  "#106 (retroactive heading) is NOT in MISSING"           flagged 106
refute  "#106 (retroactive heading) is NOT in CASING"            in_section "CASING —" 106
refute  "#106 (retroactive heading) is NOT in PRESENT"           unverified 106

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
assert_grep "PRESENT header warns off --retroactive" \
  "do NOT run --retroactive" "$(section_header 'PRESENT (unverified)')"
refute_grep "CASING header does not invite the destructive path" \
  "remediate: idd-close --retroactive" "$(section_header 'CASING —')"
refute_grep "PRESENT header does not invite the destructive path" \
  "remediate: idd-close --retroactive" "$(section_header 'PRESENT (unverified)')"

# Glyph policy after the #295 verify round: ⚠ marks "a human still has to look",
# which is true of MISSING and of MID-COMMENT (the tool cannot tell a real
# summary from a quoted one there). CASING is the only class the tool has
# actually established, so it is the only one printed without the glyph.
assert_grep "PRESENT entries carry ⚠ (unverified, needs a human)" "⚠ #105" "$OUT"
refute_grep "a CASING entry never carries the warning glyph" "⚠ #104" "$OUT"

# ── #295 R5: the destructive gate turns on ABSENCE alone ──
# DELIBERATE DIRECTION CHANGE, decided by the maintainer after round 4 failed:
# rounds 1-4 tried to tell a real summary from a quoted one by parsing markdown
# in jq, and every mechanism added (fence toggle, HTML span, section bound,
# indent cap, content requirement) grew its own one-way failure that routed a
# REAL summary into MISSING — the only class that authorises the irreversible
# `--retroactive`. The parser is gone. A quoted heading now counts the same as a
# real one, so these four — which have NO summary, only a quotation or an empty
# heading — are no longer reported as MISSING. They land in PRESENT instead:
# still visible to a human, but unable to trigger the destructive path.
#
# That is a MISSED DETECTION and it is the accepted price. Do not "fix" these by
# reintroducing a quoting rule without re-reading rounds 1-4 on PR #297 first.

require "#108 (heading only inside a fenced block) is PRESENT, not MISSING"  unverified 108
refute  "#108 is NOT in MISSING (accepted under-report)"                     flagged 108
require "#109 (heading only inside an HTML comment) is PRESENT"              unverified 109
refute  "#109 is NOT in MISSING (accepted under-report)"                     flagged 109
require "#110 (heading with zero content under it) is CASING-or-quiet, not MISSING" \
  bash -c '! printf "%s\n" "$0" | grep -qE -- "⚠ #110"' "$OUT"

# The converse — a genuine summary merged into the IC comment — must stay in the
# advisory bucket, or the rewrite has simply collapsed everything into missing.
require "#111 (genuine merged summary) is PRESENT"                 unverified 111
refute  "#111 is NOT in MISSING"                                   flagged 111

# ── #295 R2: the title is untrusted data (the verify round's H2) ──
# `class\t#N  title` is parsed positionally downstream, so an unescaped newline
# in a title forged a whole row — into the one section that invites the
# irreversible --retroactive.

# Assert on the SHAPE of a forged row, not on a literal payload string. The
# first version grepped for "#9999  FABRICATED ENTRY" with two spaces — and the
# whitespace-collapsing half of `sanitize` survives any mutation of the
# control-character half, so the needle never matched and the assertion stayed
# green while forging actually succeeded. Acid on `sanitize` exposed it: the
# mutation turned only the tab assertion red.
require "no forged row can appear in any section (title channel)" \
  bash -c '! printf "%s\n" "$0" | grep -qE -- "^ +(⚠ )?#9999"' "$OUT"
require    "#112 (whose title carries the payload) is itself compliant" \
  bash -c '! printf "%s\n" "$0" | grep -qE -- "(^|[^0-9])#112([^0-9]|$)"' "$OUT"
assert_grep "a tab in a title no longer truncates it" "tab here in title" "$OUT"

# A 4-space-indented heading renders as code, so it is a quotation — and under
# the R5 rule a quotation counts as presence. It must therefore NOT be MISSING.
# (Rounds 1-4 asserted the opposite here; the earlier claim in this file that
# the `^ {0,3}` cap was "strictly redundant, no input can distinguish the two"
# was itself wrong — a space+tab indent distinguished them, see #129 — and both
# the cap and the claim are now gone with the parser.)
refute  "#114 (heading indented 4 spaces) is NOT in MISSING"         flagged 114
require "#114 is visible in the advisory bucket instead"             unverified 114

# ── #295 R3/R5: real summaries that earlier rounds routed to MISSING ──
# Each of these is a REAL summary that one of rounds 2-4 sent to the destructive
# class. They are the regression lock on the direction: whatever the classifier
# becomes, none of them may ever reach MISSING again.

require "#115 (heading carries an inline HTML marker) is NOT missing" \
  bash -c '! printf "%s\n" "$0" | grep -qE -- "⚠ #115"' "$OUT"
require "#116 (summary body entirely inside a fence) is NOT missing" \
  bash -c '! printf "%s\n" "$0" | grep -qE -- "⚠ #116"' "$OUT"

# #117 (`## Closing Summary` then an unrelated `## Next Steps`) has no summary,
# but it is structurally IDENTICAL to #122 — a real summary whose subsections are
# h2 — and nothing syntactic separates them. Round 3 resolved that ambiguity
# toward MISSING, i.e. toward the irreversible action; R5 resolves it away from
# MISSING and lets a human read both.
refute  "#117 (empty summary, unrelated later section) is NOT in MISSING" flagged 117

# H2 again, one field to the left: `.number` is untrusted too. Same shape-based
# assertion as the title channel, for the same reason.
require "no forged row can appear in any section (number channel)" \
  bash -c '! printf "%s\n" "$0" | grep -qE -- "FORGED VIA NUMBER"' "$OUT"

# The non-Cc forging channel (#295 R4 self-probe): U+2028/U+2029 are line and
# paragraph separators and the bidi overrides reorder a rendered line, but none
# of them is [[:cntrl:]] — so the round-2 fix closed the channel for \n and left
# it open one codepoint over. Asserted on the sanitised OUTPUT, since whether a
# given renderer breaks on U+2028 is not something this test can observe.
require "U+2028 / U+2029 / bidi overrides do not survive into the report" \
  python3 -c "
import sys
bad = {0x2028, 0x2029, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E,
       0x2066, 0x2067, 0x2068, 0x2069}
found = sorted({hex(ord(c)) for c in sys.argv[1] if ord(c) in bad})
if found:
    print('unsanitised separators reached stdout: %s' % found)
    sys.exit(1)
" "$OUT"

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
require "#121 is QUIET — a leading marker line must not demote a canonical summary" \
  bash -c '! printf "%s\n" "$0" | grep -qE -- "#121"' "$OUT"

# ── #295 R4: every shape the fourth verify round found ──
# All nine were REAL summaries that HEAD-at-round-4 classified as MISSING and
# printed under "remediate: idd-close --retroactive". Each one is its own
# mechanism, so each gets its own assertion: this block is the reason the parser
# was removed rather than patched a fifth time.

refute "#122 (h2 subsections, not h3) is NOT missing"                flagged 122
refute "#123 (empty decoy heading before the real one) is NOT missing" flagged 123
refute "#124 (one-line summary on the heading line) is NOT missing"  flagged 124
refute "#125 (a tilde fence line inside a backtick block) is NOT missing" flagged 125
refute "#126 (3 backticks inside a 4-backtick block) is NOT missing" flagged 126
refute "#127 (unclosed fence earlier in the comment) is NOT missing" flagged 127
refute "#128 (unclosed HTML comment) is NOT missing"                 flagged 128
refute "#129 (heading indented with space+tab) is NOT missing"       flagged 129
refute "#131 (cluster-close preamble above the summary) is NOT missing" flagged 131

# The four whose heading leads its comment must be QUIET, not merely non-missing
# — a compliant repo has to stay silent or the audit becomes noise.
for n in 122 123 124 130; do
  require "#$n is quiet (canonical heading leads its comment)" \
    bash -c '! printf "%s\n" "$1" | grep -qE -- "#$0"' "$n" "$OUT"
done

# #129 leads with the heading but indented: CASING, and CASING carries no ⚠.
require "#129 is listed under CASING"                    in_section "CASING —" 129
refute_grep "#129 carries no warning glyph"              "⚠ #129" "$OUT"

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

# ── The helper must be plain text (#295 R4) ──
# Two NUL bytes reached this script inside a comment that was *explaining* why
# control characters must be neutralised — the escapes were pasted as the bytes
# themselves. They survived three verify rounds because every symptom was
# silence: `grep -r` printed nothing instead of erroring, `gh pr diff` inherited
# the bytes so grep went blind on the patch too, and GitHub served the file as a
# binary blob — the whole +199/-19 of the NORMATIVE SOURCE rendered as "Binary
# file not shown", unreviewable and un-commentable. git itself still diffed it as
# text (its detector only reads the first 8000 bytes), which is what hid it.
require "the helper contains no control bytes other than TAB and LF" \
  python3 -c "
import sys
d = open(sys.argv[1], 'rb').read()
bad = sorted({b for b in d if b < 32 and b not in (9, 10)})
if bad:
    print('stray control bytes: %s' % [hex(b) for b in bad])
    sys.exit(1)
" "$HELPER"

print_summary "check-closed-without-summary"
exit $?
