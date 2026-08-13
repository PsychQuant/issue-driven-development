#!/usr/bin/env bash
# Test: the prose readers of the `## Closing Summary` marker must not contradict
# its normative source (#295).
#
# WHY THIS TEST EXISTS
#
# The marker has one normative source — `scripts/check-closed-without-summary.sh`
# — and several prose readers: idd-list, idd-close, idd-find, idd-update,
# CLAUDE.md. Across SIX verify rounds on PR #297 the same defect recurred every
# time: the classifier was fixed and the prose was updated only where a reviewer
# had cited it. Round 5 rewrote `CLAUDE.md:487` while line 485 one line above
# still invited `--retroactive` unconditionally. Round 6 built the first version
# of this test — and then shipped a CRITICAL anyway, because both destructive-
# gate readers still printed the round-5 regex verbatim and the test's phrase
# list did not know about it.
#
# That failure is the reason for the design below. A hand-maintained list of
# banned phrases only knows what its author remembered to add, which is exactly
# the faculty that had already failed five times. So the primary check is now
# MECHANICAL and needs no memory:
#
#   RULE 1 (no copies): prose must not quote a regex literal for this marker at
#   all. One definition, in one file. A copy cannot drift if it does not exist.
#
#   RULE 2 (phrase list): a small residue of superseded WORDING that rule 1
#   cannot catch, e.g. class names. Kept, but no longer load-bearing.
#
#   RULE 3 (positive control): every check above must be shown to fail when the
#   thing it guards is broken. Round 6's version passed vacuously under four
#   independent no-op mutations; a test that cannot fail is not a test.
#
# Usage: bash test.sh   (exit 0 = pass, 1 = fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
SCRIPT="$PLUGIN/scripts/check-closed-without-summary.sh"
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"

# ── Rule 1: no regex literal for this marker may appear in any prose file ──
#
# The signature of such a literal is a line-anchored pattern mentioning the
# marker words. Matching on the SHAPE rather than on a remembered string is what
# makes this check survive rewordings the author did not anticipate.
scan_prose_regex() {
  grep -rnE --include='*.md' -- '\^[^`]*closing[^`]*summary' "$PLUGIN" 2>/dev/null \
    | grep -v '/CHANGELOG.md:'
}

HITS=$(scan_prose_regex || true)
require "no prose file quotes a regex literal for the closing-summary marker" \
  bash -c '[ -z "$0" ] || { printf "%s\n" "$0"; exit 1; }' "$HITS"

# ── Rule 3a: positive control for rule 1 ──
# Plant a regex literal in a scratch .md inside the plugin, prove the scan sees
# it, then remove it. Without this, a broken scan (bad flag, wrong path, a `--`
# swallowing --include — all three happened while writing this file) reads as a
# clean repo.
CANARY="$PLUGIN/.drift-canary.md"
printf 'canary: `^ {0,3}#{1,2} closing summary`\n' > "$CANARY"
CANARY_SEEN=$(scan_prose_regex | grep -c 'drift-canary' || true)
rm -f "$CANARY"
require "positive control: the regex scan actually detects a planted literal" \
  bash -c '[ "$0" -ge 1 ]' "$CANARY_SEEN"

# ── Rule 2: residual superseded wording ──
STALE=$(cat <<'EOF'
own-comment	class renamed; the compliant class is now called `compliant`
mid-comment	class renamed; the unverified class is now called `present`
MID-COMMENT	class renamed; the unverified class is now called `present`
只看活的 markdown	round 5 stopped distinguishing live markdown from quoted markdown
unreachable by construction	round 5 claim, retracted in round 6 — four shapes still reached missing
CLOSED 但無	binary phrasing of the rule, replaced by the four destinations
the summary IS there	round-1 wording; only `casing` may claim content, and it says so differently
EOF
)

# `--include` MUST precede `--`: `--` ends option parsing, so an --include after
# it is taken as a FILE OPERAND and silently ignored. That exact bug shipped in
# round 6 and made this scan cover every file type, including itself.
HISTORICAL='round [1-6]|rounds [1-6]|早期版本|舊判定|superseded|已被取代|retracted|複述'

hits=0
report=""
while IFS=$'\t' read -r phrase why; do
  [ -z "$phrase" ] && continue
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    text=${line#*:*:}
    printf '%s' "$text" | grep -qE -- "$HISTORICAL" && continue
    hits=$((hits + 1))
    report="${report}
    ${line%%:*} — ${phrase}  (${why})"
  done <<EOF2
$(grep -rn --include='*.md' -- "$phrase" "$PLUGIN" 2>/dev/null | grep -v '/CHANGELOG.md:')
EOF2
done <<EOF3
$STALE
EOF3

require "no prose file states a superseded classification rule" \
  bash -c '[ "$0" -eq 0 ] || { printf "%s\n" "$1"; exit 1; }' "$hits" "$report"

# ── Rule 3b: positive control for rule 2 ──
CANARY2="$PLUGIN/.drift-canary2.md"
printf 'canary: the class is called own-comment here\n' > "$CANARY2"
SEEN2=$(grep -rn --include='*.md' -- "own-comment" "$PLUGIN" 2>/dev/null | grep -c 'drift-canary2' || true)
rm -f "$CANARY2"
require "positive control: the phrase scan actually detects a planted phrase" \
  bash -c '[ "$0" -ge 1 ]' "$SEEN2"

# ── The readers must defer to the normative source, not restate it ──
for reader in skills/idd-list/SKILL.md skills/idd-close/SKILL.md; do
  assert_grep "$reader points at the normative source" \
    "check-closed-without-summary.sh" "$(cat "$PLUGIN/$reader")"
done

# ── The predicate names the prose defers TO must actually exist ──
# Otherwise "see `def present_re`" is a dangling pointer, which is the same
# drift one level down.
for def in present_re bare_re lead_re; do
  assert_grep "the normative source really defines $def" \
    "def $def:" "$(cat "$SCRIPT")"
done

print_summary "closing-summary-prose-drift"
exit $?
