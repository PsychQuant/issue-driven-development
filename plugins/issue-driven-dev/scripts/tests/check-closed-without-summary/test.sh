#!/usr/bin/env bash
# Test: check-closed-without-summary.sh classifies CLOSED issues by what their
# `## Closing Summary` marker looks like — the retroactive safety net for the
# direct-commit auto-close trap (#151), made four-way by #295.
#
# Destinations (#295, as of round 6) — `compliant` prints nowhere:
#   #100 CLOSED + canonical heading leading its comment  → compliant (not listed)
#   #101 CLOSED + no  Closing Summary                    → MISSING
#   #102 OPEN   + no  Closing Summary                    → not listed
#   #103 CLOSED + zero comments                          → MISSING (legacy / UI-close)
#   #104 CLOSED + `## Closing summary`                   → CASING
#   #105 CLOSED + summary inside the IC comment          → PRESENT
#   #106 CLOSED + `## Closing Summary (retro…)`          → compliant (D2)
#   #107 CLOSED + `## closing summary_v2`                → CASING (D3)
#
# Why not two classes (#295): the two-way `startswith` misreported 11 of 43
# closed issues in a real repo (26%), and `/idd-close --retroactive` shares the
# same marker as its precondition — so a false positive there does not merely add
# noise, it posts a duplicate summary onto an issue that already has one. Only
# MISSING may reach that path.
#
# TWO PREDICATES (round 6). Presence is judged permissively (any indentation,
# blockquote prefix, 1-6 hashes, emoji decoration, NBSP) because over-detecting
# withholds the destructive action. Leading is judged strictly (a real ATX
# heading, no blockquote prefix, ≤3 spaces) because over-detecting exonerates an
# issue with a positive claim — round 5 shared one regex between the two and a
# blockquoted quotation was announced as "the summary is there".
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
# to classify as `compliant`, i.e. appear in NO section at all.
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

# Glyph policy: ⚠ marks "a human still has to look", which is true of MISSING and
# of PRESENT (the tool establishes nothing about a heading that does not lead its
# comment). CASING is the only listed class whose position AND content the tool
# has actually established, so it is the only one printed without the glyph.
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
# R6: a bare heading with nothing under it is no longer `compliant`. Reading it
# as compliant made the issue INVISIBLE — printed in no section at all, while
# `--retroactive` also aborts on it, so anyone who can comment could silence a
# closed issue permanently by posting an empty `## Closing Summary`. It now
# lands in PRESENT: visible to a human, authorising nothing.
require "#110 (heading with zero content) is PRESENT, not MISSING and not silent" unverified 110
refute  "#110 is NOT in MISSING"                                                  flagged 110

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
# #120's heading sits after a `---`, so it is legitimately `present` — which
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

# #129 is indented with a space then a TAB, which under CommonMark tab-stop
# rules indents to column 4 — an indented code block, i.e. a quotation, not a
# heading. R6 split the predicates: `lead_re` is strict (a real ATX heading, no
# blockquote prefix, at most three literal spaces), so #129 is no longer CASING.
# It stays out of MISSING via the permissive presence test. R5 asserted CASING
# here; the stricter reading is the correct one.
require "#129 (space+tab indent) is PRESENT, not CASING"  unverified 129
refute  "#129 is NOT in MISSING"                          flagged 129

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

# The widened invisible/bidi set (#295 R6). ZWJ and ZWNJ are deliberately spared
# — they join emoji sequences and Persian/Indic letters and cannot forge a row —
# so this asserts on the dangerous set only.
require "invisible and bidi controls do not survive into the report" \
  python3 -c "
import sys
bad = {0x061C, 0x200B, 0x200E, 0x200F, 0x2028, 0x2029, 0x2060, 0xFEFF}
bad |= set(range(0x202A, 0x202F)) | set(range(0x2066, 0x206A)) | set(range(0xE0000, 0xE0080))
found = sorted({hex(ord(c)) for c in sys.argv[1] if ord(c) in bad})
if found:
    print('unsanitised invisibles reached stdout: %s' % found)
    sys.exit(1)
" "$OUT"
require "#133 (whose title carries them) is itself listed" flagged 133

# The FOURTH mechanism, previously untested (round-5 verify, regression lens):
# the three-way all-clear guard. If it is ever weakened to test only MISSING, a
# repo with casing/present rows gets a green ✓ over a non-empty report.
ALLCLEAR=$(bash "$HELPER" --json-file "$HERE/fixtures/casing-only.json" 2>/dev/null)
refute_grep "a casing-only repo does NOT get a false all-clear" \
  "No closed issue is missing" "$ALLCLEAR"
assert_grep "a casing-only repo still prints its CASING section" \
  "CASING —" "$ALLCLEAR"

# ── #295 R7: the recogniser widening now carries test weight ──
# Round 6 widened the recogniser and verified it with a hand-written probe that
# never entered the suite. Acid then showed the entire widening could be reverted
# to the round-5 form with the suite still fully green — and three lenses found
# real summaries still reaching MISSING. Each shape below is one mechanism of the
# widening; together they are the regression lock that was missing.

for n in 140 141 142 147 148 149 150 151 152 153; do
  refute "#$n (a real summary a reader can see) is NOT in MISSING" flagged "$n"
done

# CRLF is how the GitHub web UI actually submits comment bodies, and every other
# fixture in this file is LF-only — so nothing here could see a CRLF regression.
require "#154 (CRLF body, canonical summary) stays quiet" \
  bash -c '! printf "%s\n" "$0" | grep -qE -- "#154"' "$OUT"

# The mirror direction, and the reason round 6 exists: a comment that merely
# QUOTES the heading must never reach a class that asserts content exists.
# `casing` says "the summary is there"; `present` says nothing was established.
require "#155 (blockquote-led quotation) is PRESENT, never CASING" unverified 155
refute  "#155 is NOT in CASING (it would assert content that is not there)" \
  in_section "CASING —" 155

# The silencing channel, closed properly this time: round 6 required "content"
# but accepted any non-space, so three dots restored the invisibility.
require "#156 (heading + dots only) is PRESENT, not silent" unverified 156

# Acid on round 7 found two mechanisms still carrying no weight, one of them
# added in the same round. Each fixture below is reachable by exactly ONE
# mechanism, so neither can hide behind the other — present_re and bare_re had
# been masking each other, which is the same shape that hid defects in rounds
# 2, 3 and 6.
# NOTE the assertion form: `flagged` is section-scoped. The first cut asserted
# "no ⚠ #157", but PRESENT entries carry ⚠ too, so it failed on correct
# behaviour — the same conflation this suite already recorded once at #120.
refute "#157 (emoji heading, mid-comment, same-line content) is NOT in MISSING" flagged 157
require "#157 is visible in the advisory bucket"                                unverified 157
require "#158 (known-truncated comment set) is PRESENT, never MISSING" unverified 158
refute  "#158 is NOT in MISSING — an incomplete fetch cannot prove absence" flagged 158

# ── post-merge audit (2026-08-15): emphasised headings with a tail ──
# `bare_re`'s trailing `$` anchor is what keeps ordinary prose out of the
# presence test, but it also rejected every emphasised heading carrying a tail,
# sending a real summary to MISSING. `emph_re` covers that shape; these two
# fixtures are its regression lock (acid: removing emph_re turns them red).
refute "#160 (bold heading with a tail) is NOT in MISSING"   flagged 160
refute "#161 (italic heading with a tail) is NOT in MISSING" flagged 161
# The counterpart the loosening must NOT break: prose mentioning the phrase
# still cannot rescue an issue that has no summary.
require "prose mentioning the marker still cannot rescue an issue" \
  bash -c 'printf "%s" "[{\"number\":9001,\"title\":\"p\",\"state\":\"CLOSED\",\"comments\":[{\"body\":\"I forgot the closing summary, sorry\"}]}]" > "$0/p.json";
           bash "$1" --json-file "$0/p.json" | grep -q "9001"' "${TMPDIR:-/tmp}" "$HELPER"

# ── the content test must use the same notion of "visible" as the lead test ──
#
# `lead_line` skips whole-line HTML markers when deciding which line a reader
# sees first — this plugin mandates a machine-locatable marker on line 1, and it
# must not demote a byte-perfect summary. `lead_has_content` did NOT apply the
# same rule to the lines it scans for content, so an HTML comment counted as a
# summary. That reopens, one level down, the silencing channel the content test
# was added to close: `## Closing Summary` + `<!-- TODO -->` read as compliant,
# which prints in NO section at all, and `--retroactive` refuses it too.
#
# Direction note: this whole class sits on the CHEAP side — the wrong answer
# hides an issue rather than authorising a duplicate post. It is fixed anyway
# because a previous round set out to close exactly this channel and left a
# second door open.
require "#162 (canonical heading, only an HTML comment under it) is PRESENT" unverified 162
refute  "#162 is NOT compliant — compliant prints nowhere, i.e. invisible"   in_section "CASING —" 162
refute  "#162 is NOT in MISSING"                                             flagged 162
require "#163 (casing heading, only an HTML comment under it) is PRESENT"    unverified 163
refute  "#163 is NOT in CASING — CASING claims the summary is there"         in_section "CASING —" 163
refute  "#163 is NOT in MISSING"                                             flagged 163

# ── HTML-flavoured headings a reader sees but the recogniser did not (#320) ──
#
# The recogniser demanded a hash (or an emphasis run, or a bare title line) at
# the start of the line. GitHub renders all four shapes below as visible
# headings, so a human reading the comment sees a closing summary — and the
# classifier said `missing`, which since the gate landed no longer merely
# under-reports: it AUTHORISES the duplicate post, while idd-close explicitly
# forbids the agent from second-guessing the exit code by reading the prose.
#
# #170 is the sharp one. The fixtures already had the marker AFTER the heading
# (#115) and on its OWN line (#121). Marker BEFORE the heading, same line, is
# the third arrangement of the same three tokens — the one nobody enumerated.
refute "#170 (idd marker before the heading) is NOT in MISSING"   flagged 170
refute "#171 (anchor tag before the heading) is NOT in MISSING"   flagged 171
# Not merely "not missing" — these two LEAD with a heading once the invisible
# prefix is accounted for, so they belong in CASING, whose advice (normalise the
# heading, e.g. put the marker on its own line as #121 does) is actionable.
# Asserting only "not missing" left the strict predicate with no individual
# weight: an acid run showed html_pfx could be dropped from lead_re alone and
# the suite stayed green, because present_re caught them one class down.
# CORRECTED (round 11): these two were pinned to CASING, which asserts "the
# summary is there". But `<!-- x --> ## Closing Summary` and
# `<a name="cs"></a>## Closing Summary` are NOT CommonMark headings — an ATX
# heading must begin the line, so both render as PARAGRAPHS. Verified with
# markdown-it rather than reasoned about. The previous round widened the STRICT
# predicate to accept them and then wrote a test fixing that behaviour in place —
# pinning a non-heading as a positive claim, one round after writing down that
# widening the strict half is how round 5 broke.
require "#170 (marker before hashes — NOT a CommonMark heading) is advisory only" unverified 170
refute  "#170 is NOT promoted to CASING"                                 in_section "CASING —" 170
require "#171 (anchor before hashes — NOT a heading either) is advisory only"     unverified 171
refute  "#171 is NOT promoted to CASING"                                 in_section "CASING —" 171
refute "#172 (raw <h2> heading) is NOT in MISSING"                flagged 172
refute "#173 (details/summary disclosure) is NOT in MISSING"      flagged 173
# ...and none of them may be silently swallowed either: each must still show up
# somewhere a human reads.
require "#172 (raw <h2>) is visible in the advisory bucket"       unverified 172
require "#173 (details/summary) is visible in the advisory bucket" in_section "MENTIONED" 173
# The widening must not exonerate a QUOTATION: a blockquoted HTML heading is
# still only `present`, never `casing`/`compliant`.
require "a blockquoted HTML heading stays in the advisory bucket, not CASING" \
  bash -c 'printf "%s" "[{\"number\":9100,\"title\":\"q\",\"state\":\"CLOSED\",\"comments\":[{\"body\":\"> <h2>Closing Summary</h2>\\n> quoted, not mine\"}]}]" > "$0/q.json";
           [ "$(bash "$1" --json-file "$0/q.json" --issue 9100 2>/dev/null | jq -r .class)" = "present" ]' \
  "${TMPDIR:-/tmp}" "$HELPER"

# ── round 10: absence is judged on NORMALISED text, not on heading shape ──
#
# Ten rounds ended the same way — a real summary the recogniser could not follow
# reached `missing`, and since the gate landed that no longer under-reports, it
# AUTHORISES the irreversible post. The seven shapes below were all reproduced
# returning `class=missing, rc=0`, and every one renders on GitHub as a visible
# "Closing Summary" heading.
#
# The lesson is not "we forgot some shapes". "Would a reader see a heading?" is a
# question about RENDERED OUTPUT; matching source bytes cannot answer it, because
# the rendering function is many-to-one with an unbounded preimage. So the
# destructive class now turns on whether the two words are present at all in
# renderer-flattened text. To be wrongly authorised, a real summary would have to
# contain neither word adjacent anywhere — which a template summary cannot.
refute "#180 (emphasis inside the phrase) is NOT in MISSING"        flagged 180
refute "#181 (CJK prefix before the words) is NOT in MISSING"       flagged 181
refute "#182 (the entity form of the gap) is NOT in MISSING"        flagged 182
refute "#183 (HTML bold, twin of the markdown form) is NOT in MISSING" flagged 183
refute "#184 (h2 attributes wrapped across lines) is NOT in MISSING" flagged 184
refute "#185 (close bracket inside an attribute) is NOT in MISSING"  flagged 185

# THE MIRROR, which the same round broke: `html_pfx` accepted ANY tag as an
# invisible prefix, so an HTML blockquote and a CommonMark autolink — both
# VISIBLE — were treated as blank and the quotation behind them was promoted to
# `casing`, a positive claim. Round 5 restored, in the strict predicate.
refute  "#186 (HTML-blockquoted quotation) is NOT promoted to CASING" in_section "CASING —" 186
require "#186 stays in the advisory bucket"                          in_section "MENTIONED" 186
# The line BEFORE the heading is what decides which line leads, and #186 only
# ever tested a blockquote sitting on the heading's own line. `invisible_line`
# skipped any line matching `^[ \t]*<!--.*-->[ \t]*$`, and `.*` is greedy: on
# `<!-- a --> <blockquote><!-- b -->` it runs from the FIRST `<!--` to the LAST
# `-->`, swallowing the visible element between them. The quotation`s opening
# tag was therefore invisible, the heading became the lead line, and a pure
# quotation read as `compliant` -- the class that reports nothing at all.
#
# Non-greedy is NOT the fix, and that is worth writing down because it is the
# obvious one: `<!--.*?-->[ \t]*$` still matches, because the `$` forces the
# lazy quantifier to keep extending until the tail is whitespace. The fix has to
# say what the line may CONTAIN -- comments and blanks, nothing else.
# `compliant` prints in NO section, so "is not compliant" is asserted the way
# #112 does it: the number must appear SOMEWHERE in the report. Numbers 190-192
# and not 187-189 because 187 was already taken -- the first cut of these
# fixtures collided with the existing `#187 autolink then hash`, and both of my
# refutations passed against THAT issue while mine went unexamined. Same shape
# as every vacuous guard this file records: an assertion satisfied by a
# neighbour.
require "#190 (blockquote opened beside HTML comments) is NOT compliant" \
  bash -c 'printf "%s\n" "$0" | grep -qE -- "(^|[^0-9])#190([^0-9]|$)"' "$OUT"
require "#190 stays in the advisory bucket"                          unverified 190
# #191 is the BOUNDARY, not a second repro: `<!-- x --> <blockquote>` does not
# end in `-->`, so even the greedy pattern never matched it. Kept because the
# boundary is where a future "simplification" of the pattern would land, and
# because saying which of two neighbouring fixtures actually reproduced the bug
# is the difference between a regression lock and decoration.
require "#191 (one comment, then a visible blockquote) is NOT compliant" \
  bash -c 'printf "%s\n" "$0" | grep -qE -- "(^|[^0-9])#191([^0-9]|$)"' "$OUT"
require "#191 stays in the advisory bucket"                          unverified 191
# CONTROL for the fix: a line that really IS only HTML comments must still be
# skipped, or the fix would buy its correctness by disabling the feature. That
# means #192 must be compliant, i.e. appear nowhere.
require "#192 (genuine comments-only line) is still compliant, i.e. unlisted" \
  bash -c '! printf "%s\n" "$0" | grep -qE -- "(^|[^0-9])#192([^0-9]|$)"' "$OUT"
refute  "#187 (autolink is visible, not a blank prefix) is NOT CASING" in_section "CASING —" 187

# And the cheap direction must still work: something with no marker at all is
# still the only thing that reaches the destructive class.
require "#101 (no marker anywhere) still reaches MISSING"  flagged 101
require "#103 (zero comments) still reaches MISSING"       flagged 103

# ── `--issue N`: the single-issue VETO (#307; re-contracted round 12) ──────────
# Audit mode reports to a human and always exits 0. This mode guards an
# IRREVERSIBLE action, so the whole point is the exit code: the caller must not
# have to read prose to find out whether posting is refused.
#
#   1  a marker WAS recognised            -> refuse
#   2  nothing could be determined        -> refuse
#   10 no marker was recognised           -> the veto did not fire. NOT a permit.
#
# The asymmetry is the contract, and it is the whole of round 12. Twelve rounds
# of this classifier failed in ONE direction: a real closing summary whose shape
# the recogniser could not follow was called `missing`, and `missing` authorised
# a duplicate post. That direction cannot be fixed by a better recogniser --
# "would a reader see a heading?" is a question about RENDERED output, and the
# rendering function is many-to-one with unbounded preimage, so no source-byte
# matcher can ever answer it in the negative.
#
# But it can answer in the POSITIVE. "I found the marker" is an observation;
# "the marker is not there" is an inference from a failure to recognise. So the
# power is split along the direction that is sound: this script may VETO, and
# may never PERMIT. What supplies the permit is the thing that can actually
# answer the question -- a reader (see idd-close --retroactive).
#
# 10, not 0, on purpose. Any caller still reading "rc == 0 means go" now breaks
# loudly instead of silently keeping the behaviour this change exists to remove.
gate() { bash "$HELPER" --json-file "$FIXTURE" --issue "$1" 2>/dev/null; }
gate_rc() { gate "$1" >/dev/null 2>&1; echo $?; }
# `tostring`, NOT `// "null"`: in jq the alternative operator treats `false` as
# empty, so `.comments_complete // "null"` reports a genuine `false` as "null"
# — which would have made the truncation assertion below unable to fail.
gate_field() { gate "$1" | jq -r ".$2 | tostring"; }

assert_eq "veto: an unrecognised-marker issue exits 10, not 0" "10" "$(gate_rc 101)"
assert_eq "veto: ...and names the class for what it is -- unrecognised, not missing" \
  "unrecognised" "$(gate_field 101 class)"
assert_eq "veto: ...and states in the payload that it authorises nothing" \
  "false" "$(gate_field 101 authorises)"
assert_eq "veto: ...and asserts the comment set was complete"  "true" "$(gate_field 101 comments_complete)"
assert_eq "veto: a zero-comment closed issue also exits 10"    "10" "$(gate_rc 103)"

# The property, swept rather than enumerated: there is no input -- fixture, live,
# malformed, hostile -- for which this script exits 0 in gate mode.
#
# What this sweep does NOT pin, stated because the distinction is the kind that
# quietly rots: two independent mechanisms hold the property (the verdict emits
# 10, and gate_out refuses to exit 0 at all), so the sweep goes red only when
# BOTH are broken. Mutating the verdict back to 0 leaves it green -- the guard
# converts the 0 to a 2. The assertion that pins the verdict code is the
# `exits 10, not 0` one above; this one pins the property they jointly hold.
# Verified by mutation both ways, round 12.
require "veto: NO input makes this script exit 0 in gate mode" \
  bash -c '
    rcs=""
    for n in $(jq -r ".[].number" "$1") 9999 abc "" 0 -1; do
      bash "$0" --json-file "$1" --issue "$n" >/dev/null 2>&1
      rc=$?
      [ "$rc" = 0 ] && rcs="$rcs $n"
    done
    [ -z "$rcs" ] || { echo "exited 0 for:$rcs"; exit 1; }' \
  "$HELPER" "$FIXTURE"

# The sweep above swept VALUES. It never swept the SPELLING of the flag, and
# that is where the hole was: `--issue=101` did not match the `--issue)` arm,
# fell through to `*)`, and the run continued into AUDIT mode -- which always
# exits 0. So the assertion whose name is "NO input makes this script exit 0"
# was defeated by an equals sign. Same for `--repo --issue 101`, where `--repo`
# swallows `--issue` as its own value and the number then falls through.
#
# Both are MALFORMED invocations, which is exactly the case that must not
# silently become the advisory mode: a caller that wrote `--issue` meant to ask
# the gate a question, and audit's 0 answers a different question.
require "veto: the EQUALS spelling still enters gate mode, never audit" \
  bash -c '
    bad=""
    for form in "--issue=101" "--issue=abc" "--issue="; do
      bash "$0" --json-file "$1" "$form" >/dev/null 2>&1
      rc=$?
      [ "$rc" = 0 ] && bad="$bad [$form -> 0]"
    done
    [ -z "$bad" ] || { echo "audit-mode 0 for:$bad"; exit 1; }' \
  "$HELPER" "$FIXTURE"
# WHICH of these two pins the equals form, stated because the answer is not the
# obvious one. Removing the `--*=*` split leaves the assertion ABOVE green: the
# unknown-argument arm then refuses `--issue=101` with exit 2, which is still
# "not 0", so the refusal guard masks the parsing guard. The assertion that
# actually pins the equals spelling is this one -- it requires the two spellings
# to reach the same VERDICT, which only parsing can deliver. Verified by
# mutation both ways. (Same shape as the exit-0 sweep note above: two mechanisms
# holding one property, and only one assertion able to tell them apart.)
assert_eq "veto: --issue=101 gives the same verdict as --issue 101" \
  "$(bash "$HELPER" --json-file "$FIXTURE" --issue 101 2>/dev/null | jq -r .class)" \
  "$(bash "$HELPER" --json-file "$FIXTURE" --issue=101 2>/dev/null | jq -r .class)"
require "veto: a value-taking flag REFUSES to swallow the next flag" \
  bash -c '
    bash "$0" --json-file "$1" --repo --issue 101 >/dev/null 2>&1
    rc=$?
    [ "$rc" != 0 ] || { echo "--repo swallowed --issue and the run exited 0"; exit 1; }' \
  "$HELPER" "$FIXTURE"
require "veto: ...and says which flag was missing its value" \
  bash -c 'bash "$0" --json-file "$1" --repo --issue 101 2>&1 | grep -q -- "--repo"' \
  "$HELPER" "$FIXTURE"

require "veto: ...and every gate reply carries authorises:false" \
  bash -c '
    bad=""
    for n in $(jq -r ".[].number" "$1"); do
      a=$(bash "$0" --json-file "$1" --issue "$n" 2>/dev/null | jq -r ".authorises | tostring")
      [ "$a" = "false" ] || bad="$bad $n=$a"
    done
    [ -z "$bad" ] || { echo "not false for:$bad"; exit 1; }' \
  "$HELPER" "$FIXTURE"

assert_eq "gate: a compliant issue REFUSES (exit 1)"           "1" "$(gate_rc 100)"
assert_eq "gate: a casing issue REFUSES — the summary is there, only misspelt" \
  "1" "$(gate_rc 104)"
assert_eq "gate: a PRESENT issue REFUSES — nothing was established about it" \
  "1" "$(gate_rc 110)"
# #155 is a pure QUOTATION. It is the shape the audit deliberately under-reports
# on, and the gate must inherit that: refusing here costs a missed remediation,
# allowing here costs a duplicate post onto someone else's issue.
assert_eq "gate: a quotation-only issue REFUSES rather than authorising a post" \
  "1" "$(gate_rc 155)"

assert_eq "gate: an OPEN issue exits 2 — not a retroactive case at all" \
  "2" "$(gate_rc 102)"
assert_eq "gate: a truncated comment set exits 2, never 0" "2" "$(gate_rc 158)"
assert_eq "gate: ...and reports the comment set as incomplete" \
  "false" "$(gate_field 158 comments_complete)"
assert_eq "gate: an issue absent from the payload exits 2"  "2" "$(gate_rc 9999)"
assert_eq "gate: a non-numeric --issue exits 2"             "2" "$(gate_rc abc)"
# ...and exits 2 because the VALIDATOR fired, not because jq happened to choke
# downstream. Deleting the validation leaves the exit code at 2 (the offline
# path dies on --argjson instead), so the code alone cannot tell the two apart —
# and the reason the validation exists is the LIVE path, where the number is
# interpolated into an API URL and no jq stands between it and the request.
assert_grep "gate: ...because the integer check fired, not because jq crashed" \
  "expects an integer" "$(gate_field abc error)"
assert_eq "gate: a malformed payload exits 2, not 0" "2" \
  "$(bash "$HELPER" --json-file "$HERE/fixtures/malformed.json" --issue 101 >/dev/null 2>&1; echo $?)"

# The output must be a single JSON object on stdout for EVERY path, including
# the failures — a caller that has to distinguish "JSON" from "a sentence" will
# eventually get it wrong.
for n in 101 100 102 158 9999 abc; do
  require "gate: --issue $n emits one parseable JSON object" \
    bash -c 'bash "$0" --json-file "$1" --issue "$2" 2>/dev/null | jq -e "type == \"object\"" >/dev/null' \
    "$HELPER" "$FIXTURE" "$n"
done

# Audit mode must be UNAFFECTED: it still always exits 0, gate or no gate.
assert_eq "audit mode still exits 0 (advisory contract intact)" "0" \
  "$(bash "$HELPER" --json-file "$FIXTURE" >/dev/null 2>&1; echo $?)"

# ── an EMPTY summary must not be exonerated by an empty HTML tag (round 12) ──
#
# `lead_has_content` tests `[\p{L}\p{N}]` on the RAW line, and `invisible_line`
# only recognises a line made entirely of HTML comments. So `<span></span>` under
# a heading counts as content -- because the tag NAME has letters in it. The
# result is a positive claim (`compliant` / `casing`) about a comment that
# renders to a heading and nothing else. The channel the bare-heading fix closed
# one layer up, re-opened one layer down; the existing fixture only tried
# `<!-- TODO -->`, which `invisible_line` does catch.
require "#193 (heading + empty <span>) is NOT compliant — it renders to nothing" \
  bash -c 'printf "%s\n" "$0" | grep -qE -- "(^|[^0-9])#193([^0-9]|$)"' "$OUT"
require "#193 lands in the advisory bucket instead"          unverified 193
refute  "#194 (lower-case heading + empty <a>) is NOT promoted to CASING" \
  in_section "CASING —" 194
require "#194 lands in the advisory bucket too"              unverified 194

# ── a prose MENTION is not a marker, and must not be reported as one ──
#
# The round-10 backstop demotes anything containing the two adjacent words, which
# is right for the veto direction but wrong about WHY. Reported as `present`, the
# audit says "a closing-summary heading exists but no comment leads with one" and
# the gate says "this issue already carries a closing-summary marker". Neither is
# true of `I forgot the closing summary, sorry`: there is no heading and no
# marker, only prose. And the file's own comment above `bare_re` still asserts
# the opposite invariant -- that such prose stays flagged -- measured on 5 of 9
# real issues. Code and stated requirement contradicted each other 165 lines
# apart in one file.
#
# So the mention backstop gets its own class. It still refuses (the cheap
# direction: a missed remediation beats a duplicate post), but it refuses while
# saying what it actually found.
require "#195 (prose mention only) is classified `mentioned`, not `present`" \
  in_section "MENTIONED" 195
refute  "#195 is NOT reported as carrying a heading"         in_section "PRESENT (unverified)" 195
require "#196 (Chinese prose mention) lands there too"       in_section "MENTIONED" 196
assert_grep "the MENTIONED section says no heading was RECOGNISED" \
  "no closing-summary heading was RECOGNISED" "$OUT"
# ...and does not overstate it. Two different situations land in this class and
# the tool cannot tell them apart, so the line must not assert either one. The
# first cut said "the phrase appears only in ordinary prose", which is false for
# #173 (a real summary in a <details> disclosure) -- the same over-claim, in the
# same file, that this whole class was split out to stop making.
assert_grep "...and admits it does not tell prose from an unparsed heading" \
  "does not tell them apart" "$OUT"
GATE_195=$(gate_field 195 error)
assert_grep "...and the gate stops claiming a marker exists" \
  "no closing-summary heading was RECOGNISED" "$GATE_195"
refute_grep "...the false 'already carries a marker' wording is gone from it" \
  "already carries a closing-summary marker" "$GATE_195"

# ── the recogniser sees a heading split inside a word ──
#
# `normalise` replaces a tag with a SPACE while a renderer concatenates, so
# `Clos<b>ing</b>` normalises to `clos ing` and the two-token test misses it.
# That was the round-12 CRITICAL. It no longer authorises anything (the gate
# cannot authorise at all now), but it still costs a wasted human read, and the
# de-spaced companion below is one line. It can only move issues TOWARD the
# veto, which is the sound direction.
require "#197 (heading split inside a word) is recognised, not left unseen" \
  bash -c 'printf "%s\n" "$0" | grep -qE -- "(^|[^0-9])#197([^0-9]|$)"' "$OUT"
refute  "#197 is NOT in MISSING"                             flagged 197
assert_eq "...and the gate refuses rather than clearing the veto" "1" "$(gate_rc 197)"

# ── stage 1 in isolation: the SHAPE recognisers, with the backstop switched off ──
#
# The round-10 mention backstop catches almost everything the shape recognisers
# catch, so it MASKS them. Measured, not guessed: emptying `html_pfx` (the whole
# round-9 inline-tag whitelist) left the suite fully green before the `mentioned`
# class existed, and replacing all four recognisers with `false` turned only two
# assertions red. Round 9`s forty-five lines of reasoning about which tags may
# count as an invisible prefix -- why `<blockquote>` must NOT, why an autolink is
# visible -- had nothing holding them.
#
# Splitting `mentioned` out restored a lot of that weight (all-four-off is now 21
# red), but `html_pfx` itself still only moves two. So stage 1 is exercised on
# its own: a COPY of the shipped script with the backstop branch disabled, run
# over the same fixtures. No test-only switch is added to the production script
# — an env var that changes how a safety classifier decides is exactly the kind
# of thing that gets found in the wild by someone who is not testing.
STAGE1=$(mktemp "${TMPDIR:-/tmp}/csw-stage1-XXXXXX") || STAGE1=""
require "a stage-1 copy could be created" bash -c '[ -n "$0" ]' "$STAGE1"
trap 'rm -f "$STAGE1"' EXIT HUP INT TERM
sed 's/elif ($bodies | any(mentions_marker))/elif (false)/' "$HELPER" > "$STAGE1"
require "the backstop is actually disabled in the copy" \
  bash -c '! grep -q "any(mentions_marker)" "$0" && grep -q "elif (false)" "$0"' "$STAGE1"
S1_OUT=$(bash "$STAGE1" --json-file "$FIXTURE" 2>&1)
# CONTROL: with the backstop off, a PROSE-only mention must fall to MISSING.
# Without this the disabling might have silently failed and stage 1 would be
# grading the same masked run again.
require "stage1 control: a prose-only mention now falls to MISSING" \
  bash -c 'printf "%s\n" "$0" | awk "/^MISSING/,/^\$/" | grep -qE -- "(^|[^0-9])#195([^0-9]|$)"' "$S1_OUT"

# Now the claims round 9 actually made, each answerable by the recognisers alone.
# WHAT STAGE 1 ACTUALLY COVERS — measured, and it is not what round 9 claimed.
#
# Running the fixtures with the backstop off gives a clean answer:
#
#   #170 #171 #172   present        -> the shape recognisers really do see these
#   #173 #183 #184   unrecognised   -> NOTHING in stage 1 sees them
#   #185 #186        unrecognised      the mention backstop is their only cover
#
# So five of the seven "reader sees it, the recogniser does not" fixtures that
# round 9 added are not recognised by round 9's regexes at all. Their assertions
# (`is NOT in MISSING`) have been passing on the strength of round 10's
# backstop, a mechanism written a round later. The fixture tested the OUTCOME
# and the assertion text implied the MECHANISM; nothing connected them.
#
# The reasons are structural rather than oversights, which is why this is
# recorded instead of patched:
#   #184  the scan splits on newlines, so a tag whose attributes wrap across
#         lines cannot be matched by any single-line regex.
#   #183  `<b>` is not in `html_re` (which takes h1-h6 and summary), and
#         `emph_re` is about markdown emphasis, not HTML bold.
#   #173  `<details>` is not in the `html_pfx` whitelist — correctly: it RENDERS
#         a disclosure triangle, and round 9's own criterion is that only
#         invisible prefixes may be skipped. Adding it to buy a green line would
#         break the rule the whitelist exists to state.
#   #186  a heading inside `<blockquote>` — `<blockquote>` is deliberately
#         excluded for the same reason.
#
# Widening the recognisers to cover them is the enumeration treadmill round 10
# replaced. What was missing is not coverage, it is an honest statement of which
# layer covers what — so that is what these assertions are.
s1_seen() {     # $1 = issue, $2 = label — stage 1 recognises it
  if printf '%s\n' "$S1_OUT" | awk '/^MISSING/,/^$/' | grep -qE -- "(^|[^0-9])#$1([^0-9]|$)"; then
    fail "stage1 sees it: $2" "#$1 fell to MISSING — a shape recogniser regressed"
  else
    pass "stage1 sees it: $2"
  fi
}
s1_backstop_only() {  # $1 = issue, $2 = label — ONLY the backstop covers it
  if printf '%s\n' "$S1_OUT" | awk '/^MISSING/,/^$/' | grep -qE -- "(^|[^0-9])#$1([^0-9]|$)"; then
    pass "backstop-only, as recorded: $2"
  else
    fail "backstop-only, as recorded: $2" \
         "#$1 is now recognised by stage 1 — good news, but the note above is stale: move it to s1_seen"
  fi
}
s1_seen 172 "a raw <h2> heading (html_re)"
s1_backstop_only 173 "<details><summary> — <details> is a VISIBLE element"
s1_backstop_only 183 "HTML bold pseudo-heading — <b> is not in html_re"
s1_backstop_only 184 "<h2> attributes wrapped across lines — the scan is line-split"
s1_backstop_only 185 "close bracket inside an attribute"
s1_backstop_only 186 "heading inside an HTML blockquote — deliberately excluded"
# The NEGATIVE half of round 9, and the half `html_pfx` actually earns its keep
# on: a marker or an anchor before the hashes is NOT a CommonMark heading, so it
# must not be promoted to `casing`. If `html_pfx` ever widens to admit a visible
# prefix, these fire — with the backstop off, nothing else can mask it.
for n in 170 171; do
  if printf '%s\n' "$S1_OUT" | awk '/^CASING/,/^$/' | grep -qE -- "(^|[^0-9])#$n([^0-9]|$)"; then
    fail "stage1: #$n (not a CommonMark heading) stays out of CASING" \
         "html_pfx admitted a visible prefix"
  else
    pass "stage1: #$n (not a CommonMark heading) stays out of CASING"
  fi
done

print_summary "check-closed-without-summary"
exit $?
