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
  'GATE_RC" -ne 10' "$CLOSE_MD"
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
assert_grep "idd-close states that anything but the veto-clear code aborts" \
  '`rc != 10` 一律 abort' "$CLOSE_MD"
# The half that round 12 added, and the half that is easiest to lose again: the
# veto-clear code is not permission. If this sentence goes, the skill reads
# exactly like the twelve rounds that preceded it.
assert_grep "idd-close states that the veto-clear code authorises nothing" \
  '`rc == 10` 什麼都沒放行' "$CLOSE_MD"
# Anchored at the HEADING, not anywhere in the file. The first cut of this
# assertion grepped the bare phrase, and the phrase also appears in the
# Precondition table as a cross-reference ("見下方「許可由讀者供給」") -- so
# deleting the entire section left it green, satisfied by the pointer to the
# thing it was supposed to be checking. Caught by mutating the heading away.
assert_grep_re "...and routes the decision to a reader instead" \
  '^#### 許可由讀者供給' "$CLOSE_MD"
# ...and the section's operative content, not just its title. A heading with the
# body deleted is the same failure one level down.
assert_grep "...stating the reader must read the whole comment set" \
  '讀完該 issue 的全部 comment' "$CLOSE_MD"
assert_grep "...and must write the basis into the draft" \
  '在 draft 裡明寫依據' "$CLOSE_MD"
assert_grep "...and makes the human confirmation non-optional" \
  '強制，無無人值守路徑' "$CLOSE_MD"
refute_grep "idd-close no longer tells anyone that exit 0 may proceed" \
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
# The positive claim `phase = closed` is gated on GitHub's own `state`, not on
# how strict the heading match is. Requiring a LEADING heading (the first fix)
# blocked quotations but also blocked #295's own measured case — a real summary
# merged into the Implementation Complete comment — leaving phase stuck at the
# old value, which is the failure this step exists to prevent. Both directions
# are pinned so neither over-correction can come back.
# Needles are SINGLE-quoted and backtick-free. The first cut used double quotes
# around a needle containing backticks — the shell ran them as command
# substitution and the file stopped parsing at "unexpected EOF". Eighth broken
# probe of this round; caught only because the suite refused to run at all.
assert_grep "idd-update gates phase=closed on the real GitHub state" \
  '額外要求 issue 的 GitHub' "$UPDATE_MD"
assert_grep "...and says why an authoritative field beats a stricter regex" \
  '無法被 comment 內容偽造' "$UPDATE_MD"
refute_grep "idd-update does not re-impose the lead-line requirement on phase inference" \
  '但該 heading 必須是那則 comment 的首行' "$UPDATE_MD"
refute_grep "idd-find no longer calls a permissive match an archaeological record" \
  "標 \`📜 closing summary\`（可考古的結案紀錄）" "$FIND_MD"

# ...and the helper must really have the mode the skill invokes. A skill calling
# a flag that does not exist fails open in the worst possible way: `gh`-less
# environments aside, an unknown flag here is warned about and ignored, which
# would put the audit's always-exit-0 contract on the destructive path.
SRC=$(cat "$SCRIPT")
assert_grep "the helper really implements --issue" '--issue)     GATE_SEEN=1; GATE_ISSUE=' "$SRC"
# This used to grep the header for a literal line of its own documentation --
# prose checked against prose, which cannot notice the code changing underneath.
# Now the observed exit code is produced by RUNNING the helper, and the header is
# required to document that number. Change the verdict without changing the doc
# (or the reverse) and this fires.
GATE_FIXTURE=$(mktemp "${TMPDIR:-/tmp}/prose-drift-XXXXXX") || GATE_FIXTURE=""
require "a gate fixture could be created" bash -c '[ -n "$0" ]' "$GATE_FIXTURE"
trap 'rm -f "$CANARY" "$GATE_FIXTURE"' EXIT HUP INT TERM
printf '%s' '[{"number":1,"title":"t","state":"CLOSED","url":"u","closedAt":"2026-01-01T00:00:00Z","comments":[{"body":"nothing marker-like here","createdAt":"2026-01-01T00:00:00Z"}]}]' > "$GATE_FIXTURE"
bash "$SCRIPT" --issue 1 --json-file "$GATE_FIXTURE" >/dev/null 2>&1
OBSERVED_RC=$?
assert_eq "the helper's veto-clear path is the code the header documents" \
  "10" "$OBSERVED_RC"
assert_grep "...and the header documents that same code" \
  "  $OBSERVED_RC  no marker was recognised" "$SRC"
refute_grep "the header no longer documents an exit-0 pass" \
  '0  class == missing, comment set known complete' "$SRC"
# The asymmetry itself, in the file that is normative for it.
assert_grep "the header states the veto/permit asymmetry" \
  'MAY VETO. IT MAY NOT PERMIT' "$SRC"

print_summary "closing-summary-prose-drift"
exit $?
