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
  # -i is not optional: the marker is canonically CAPITALISED (`## Closing
  # Summary`), so a case-sensitive scan cannot fire on the realistic literal.
  # It shipped case-sensitive, and its positive control planted the LOWERCASE
  # form — so the control passed while the check was blind to every regex a
  # reader would actually quote. A positive control that certifies a capability
  # the check does not have is worse than none.
  grep -rniE --include='*.md' -- '\^[^`]*closing[^`]*summary' "$PLUGIN" 2>/dev/null \
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
# The canary is a file written INTO THE REPO. Two consequences the first cut
# ignored: an interrupted run (Ctrl-C, a failing assertion under `set -e`, a
# killed CI job) leaves it behind, where it is both a permanent red for every
# later run and something a careless `git add -A` will commit; and a fixed name
# means two concurrent runs delete each other's canary and each reads the other's
# removal as "the scan cannot see a planted literal". Unique name + trap.
CANARY_SUFFIX="$$-${RANDOM}"
CANARY="$PLUGIN/.drift-canary.$CANARY_SUFFIX.md"
CANARY2="$PLUGIN/.drift-canary2.$CANARY_SUFFIX.md"
trap 'rm -f "$CANARY" "$CANARY2"' EXIT HUP INT TERM
# The canary plants the CANONICAL CAPITALISATION — the form the check must be
# able to see. Planting the lowercase form is what let a case-sensitive scan
# pass its own control.
printf 'canary: `^ {0,3}#{1,2} Closing Summary`\n' > "$CANARY"
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

# ── The destructive gate must be EXECUTED, not merely deferred to ──
#
# Pointing at the normative source is what the two readers already did while the
# gate stayed advisory for seven rounds: idd-close described the classification
# faithfully and then judged it itself. Deference is not enforcement. What makes
# it a gate is that the skill runs the helper and obeys its exit code, so that
# is what gets asserted — the invocation, and the fail-closed rule beside it.
CLOSE_MD=$(cat "$PLUGIN/skills/idd-close/SKILL.md")
assert_grep "idd-close resolves the gate helper by path" \
  '/scripts/check-closed-without-summary.sh"' "$CLOSE_MD"
assert_grep "idd-close INVOKES it in single-issue mode" \
  'bash "$HELPER" --issue "$NUMBER"' "$CLOSE_MD"
assert_grep "idd-close branches on the helper exit code" \
  'GATE_RC" -ne 0' "$CLOSE_MD"
# The gate's IDENTITY must come from the install location, never from the tree
# being audited. `${CLAUDE_PLUGIN_ROOT:-plugins/issue-driven-dev}` resolved the
# executable relative to $PWD, and /idd-close runs inside the user's repo — so a
# cloned repo shipping that path got arbitrary code execution plus an
# unconditional pass. Closing the "helper absent" hole opened the "helper
# substituted" one; both halves are asserted here.
refute_grep "idd-close does not fall back to a CWD-relative gate path" \
  'CLAUDE_PLUGIN_ROOT:-plugins/issue-driven-dev' "$CLOSE_MD"
assert_grep "idd-close requires CLAUDE_PLUGIN_ROOT to be set" \
  'CLAUDE_PLUGIN_ROOT:?' "$CLOSE_MD"
assert_grep "idd-close states that only exit 0 may proceed" \
  '只有 `rc == 0` 放行' "$CLOSE_MD"
refute_grep "idd-close no longer describes its own gate as prose-only" \
  "本 skill 並未呼叫它" "$CLOSE_MD"

# ── Permissive matching may not back a POSITIVE claim ──
#
# The two-predicate split is not local to the classifier: it is a rule about
# which question is being asked. `present_re` (permissive) answers "could a
# reader see one?", where over-detecting is safe. `lead_re` (strict) answers
# "does this comment lead with one?", where over-detecting states something
# false. Two prose readers were on the wrong side of it — idd-find labelled a
# quotation as an archaeological record, and idd-update pushed an OPEN issue's
# phase to `closed` on a quoted heading.
UPDATE_MD=$(cat "$PLUGIN/skills/idd-update/SKILL.md")
FIND_MD=$(cat "$PLUGIN/skills/idd-find/SKILL.md")
assert_grep "idd-update requires the heading to LEAD the comment (phase is a positive claim)" \
  "必須是那則 comment 的首行" "$UPDATE_MD"
refute_grep "idd-update no longer allows a blockquote prefix for phase inference" \
  "允許任意縮排與 blockquote 前綴" "$UPDATE_MD"
refute_grep "idd-find no longer calls a permissive match an archaeological record" \
  "標 \`📜 closing summary\`（可考古的結案紀錄）" "$FIND_MD"

# ...and the helper must really have the mode the skill invokes. A skill calling
# a flag that does not exist fails open in the worst possible way: `gh`-less
# environments aside, an unknown flag here is warned about and ignored, which
# would put the audit's always-exit-0 contract on the destructive path.
SRC=$(cat "$SCRIPT")
assert_grep "the helper really implements --issue" '--issue)     GATE_SEEN=1; GATE_ISSUE=' "$SRC"
assert_grep "the helper documents the gate exit codes" \
  '0  class == missing, comment set known complete' "$SRC"

print_summary "closing-summary-prose-drift"
exit $?
