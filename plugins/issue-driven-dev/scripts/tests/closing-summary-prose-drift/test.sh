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

# ── the PRICE has to be true in the prose, not merely stated in it ──
#
# The three assertions above check that sentences EXIST. The claim they stand in
# for is "`--retroactive` has no unattended path", and a sentence saying so
# survives every edit that reintroduces one. Deleting the operative confirmation
# step while keeping its description, or adding an unattended branch beside it,
# leaves all three green — and the round-12 price is then false in the shipped
# skill while its own test reports otherwise. That is the exact shape this file
# exists to catch, one level up from where it was looking.
#
# So: no escape hatch may exist, and the confirmation must come BEFORE the post.
for HATCH in -- '--yes' '--no-confirm' '--force-confirm' 'skip-confirm' 'AUTO_CONFIRM'; do
  [ "$HATCH" = "--" ] && continue
  refute_grep "no '$HATCH' escape hatch around the retroactive confirmation" \
    "$HATCH" "$CLOSE_MD"
done
# Unattended-mode words may APPEAR (the file explains why there is no such path);
# what must not exist is one of them promising `--retroactive` a way through.
require "no unattended/loop/cron branch offers --retroactive a way past the human" \
  bash -c '
    bad=$(printf "%s\n" "$0" \
      | grep -nE "unattended|/loop|cron|autopilot|noninteractive" \
      | grep -iE "retroactive" \
      | grep -vE "不再有無人值守|無無人值守|no unattended|沒有無人值守|除外|不得省略")
    [ -z "$bad" ] || { printf "%s\n" "$bad"; exit 1; }' "$CLOSE_MD"
# ORDER: the confirmation step must be described before the publish step. A
# mandate that lands after the post is not a gate.
require "the confirmation is documented BEFORE the publish step" \
  bash -c '
    C=$(printf "%s\n" "$0" | grep -n "拿到人的確認才 post" | head -1 | cut -d: -f1)
    P=$(printf "%s\n" "$0" | grep -n "^### Step 4: Post\|publish_and_close" | head -1 | cut -d: -f1)
    [ -n "$C" ] && [ -n "$P" ] && [ "$C" -lt "$P" ]' "$CLOSE_MD"

# `GATE_RC` must be the helper`s exit status, not a number set nearby. The two
# assertions above check two disconnected strings, so `bash "$HELPER" …` followed
# by an unrelated `GATE_RC=10` passes both.
require "GATE_RC is captured from the helper invocation itself" \
  bash -c 'printf "%s\n" "$0" | grep -q "VERDICT=\$(bash \"\$HELPER\".*); GATE_RC=\$?"' "$CLOSE_MD"
# ...and the helper path must be ABSOLUTE. `${CLAUDE_PLUGIN_ROOT:?}` only
# requires non-empty: set it to a relative path and the gate resolves against
# $PWD, which is the audited repo — the hole the `:?` was added to close, one
# character short.
assert_grep "the gate helper path is required to be absolute" \
  '必須是絕對路徑' "$CLOSE_MD"
require "...checked with a leading-slash case, not merely described" \
  bash -c 'printf "%s\n" "$0" | grep -A1 "case .\${CLAUDE_PLUGIN_ROOT" | grep -qE "^ +/\*\)"' "$CLOSE_MD"
refute_grep "idd-close no longer tells anyone that exit 0 may proceed" \
  '只有 `rc == 0` 放行' "$CLOSE_MD"

# ── the human permit must not be optional ANYWHERE in this file ──
#
# Round 12 removed the helper's power to authorise, leaving exactly one thing
# between `rc == 10` and an irreversible duplicate summary: a person. The table
# row and the new section both say that confirmation cannot be disabled.
#
# The Step 0.5 bootstrap list said otherwise, and it is the list an executing
# agent actually follows -- twelve lines below it the file declares
# `TaskCreate 清單 = 真實的步驟清單`. Its `review_with_user` entry carried
# `(若已明確 /idd-close 可省略此步)`, and `--retroactive` IS an explicit
# `/idd-close` invocation, so the carve-out covered precisely the one case that
# must never take it. Eight commits of round-12 work touched 65 lines of this
# file and none of them touched that one.
#
# Three places have to agree, so all three are asserted: the table row, the task
# list, and the Step 3 body. The previous round asserted the first two and the
# defect lived in the third form of the same sentence.
refute_grep "the task list does not license skipping confirmation for an explicit close" \
  '(若已明確 /idd-close 可省略此步)' "$CLOSE_MD"
assert_grep "...it scopes the omission away from --retroactive instead" \
  '--retroactive 不得省略' "$CLOSE_MD"
assert_grep "the Step 3 BODY carries the mandate too, not just the retroactive table" \
  '`--retroactive` 時這一步不可省略' "$CLOSE_MD"
# And the property behind all three, checked without depending on any single
# wording: no line in this file may pair "省略/skip" with the confirmation step
# unless it also names the retroactive exception.
require "no line lets the confirmation step be skipped unconditionally" \
  bash -c '
    bad=$(printf "%s\n" "$0" \
      | grep -nE "省略|skip" \
      | grep -E "確認|confirm|review_with_user" \
      | grep -vE "retroactive")
    [ -z "$bad" ] || { printf "%s\n" "$bad"; exit 1; }' "$CLOSE_MD"
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
# a flag that does not exist fails open in the worst possible way: an unknown or
# malformed flag used to be warned about and IGNORED, so the run continued into
# audit mode -- and audit always exits 0. The comment that used to sit here said
# exactly that ("would put the audit's always-exit-0 contract on the destructive
# path") and was left as a description of a live defect rather than a test of it.
# Reproduced later by an outside reviewer: `--issue=101` and `--repo --issue 101`
# both exited 0.
#
# Asserted BEHAVIOURALLY now. The old form grepped for the literal source line
# `--issue)     GATE_SEEN=1; GATE_ISSUE=` -- which pinned the whitespace of an
# implementation rather than the property, and went red the moment the parser
# was rewritten to close the hole it was supposedly guarding.
SRC=$(cat "$SCRIPT")
PD_FIX=$(mktemp "${TMPDIR:-/tmp}/prose-drift-args-XXXXXX") || PD_FIX=""
require "an argument fixture could be created" bash -c '[ -n "$0" ]' "$PD_FIX"
printf '%s' '[{"number":1,"title":"t","state":"CLOSED","url":"u","closedAt":"2026-01-01T00:00:00Z","comments":[{"body":"nothing marker-like"}]}]' > "$PD_FIX"
for FORM in "--issue 1" "--issue=1"; do
  # shellcheck disable=SC2086
  bash "$SCRIPT" --json-file "$PD_FIX" $FORM >/dev/null 2>&1
  RC=$?
  assert_eq "the helper really implements --issue ($FORM), and it is not audit mode" \
    "10" "$RC"
done
bash "$SCRIPT" --json-file "$PD_FIX" --repo --issue 1 >/dev/null 2>&1
assert_eq "a flag that swallows the next flag is refused, not run as an audit" "2" "$?"
bash "$SCRIPT" --json-file "$PD_FIX" --no-such-flag >/dev/null 2>&1
assert_eq "an unknown flag is fatal, so it cannot become an audit-mode 0" "2" "$?"
rm -f "$PD_FIX"
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
