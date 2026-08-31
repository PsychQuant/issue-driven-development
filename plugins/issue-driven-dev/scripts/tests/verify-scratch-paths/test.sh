#!/usr/bin/env bash
# Test: no skill may name a FIXED scratch path under /tmp (#288).
#
# WHY THIS EXISTS
#
# #288 was closed with a summary stating that every scratch path now hung off
# `mktemp -d`. What actually shipped was a NOTE saying so, followed by twenty-
# three paragraphs that went on MUSTing `/tmp/verify_${NUMBER}_*` — including
# the OUTPUT instructions handed to the reviewer agents, i.e. the paths that
# decide where findings actually land. The rule and its violations lived four
# lines apart for two releases.
#
# A fixed name under /tmp carries no repo identity. Two sessions verifying the
# SAME issue number in DIFFERENT repos share filenames, and a leftover file from
# the earlier run is read as this run's findings — silently, and in the worst
# direction: another repo's verdict merged into this PR's report.
#
# So the rule is mechanised rather than restated. Prose cannot drift from a
# grep.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"

# A fixed scratch path = /tmp (or ${TMPDIR:-/tmp}) followed by a literal name.
# `mktemp` lines are exempt: that is the sanctioned way to obtain one, and the
# template it takes necessarily contains /tmp.
#
# SCOPE IS A CRITERION, NOT A LIST (rewritten round 12).
#
# It used to name three files, then say "Still NOT covered, and deliberately:
# idd-edit" -- which READS as a closed enumeration while being an open one. A
# scan of the whole plugin found three more files nobody had looked at, and the
# sharpest was `idd-close`'s `/tmp/distribution_sync_patch.json`: a fixed name
# with NO per-run component at all, holding the full body about to be PATCHed
# into someone's issue comment. Two concurrent /idd-close runs overwrite each
# other's payload and the PATCH still succeeds -- with the other run's text.
# That file met every stated inclusion criterion; it was simply outside the
# sentence. So #288's own story -- "the rule and its largest violation shipped
# in the same release" -- repeated inside the fix for it.
#
# The criterion: a fixed path is forbidden anywhere it becomes (a) an EGRESS
# BODY -- text that gets posted, PATCHed or handed to a reviewer -- or (b) a
# GATE'S DECISION INPUT. Both fail silently and in the publishing direction.
# Rather than enumerate where that happens, the scan now covers skills/, rules/
# and references/ wholesale, and exceptions live in an explicit allowlist below
# with a reason each. An exception you have to write down is one the next reader
# can find; a sentence they have to re-derive is not.
#
# ALLOWLIST (path fragment -> why). Keep it short; each entry is a promise that
# the path is neither an egress body nor a gate input.
#   skills/idd-edit/         /tmp/idd-edit-backup/ is a documented recovery
#                            location users are told to `ls`; moving it is a
#                            behaviour change, and its collision consequence is
#                            a visible clash, not a wrong comment.
#   idd-issue-attachments    a staging directory for downloads; the files are
#                            read back by the same run and never posted.
SCAN_ROOTS="$PLUGIN/skills $PLUGIN/rules $PLUGIN/references"
ALLOW_PATHS='skills/idd-edit/|idd-issue-attachments'
scan_fixed_tmp() {
  # The mktemp CALL is REMOVED from the line, then whatever remains is scanned.
  # Two weaker forms preceded this, each exempting more than it meant to:
  #   1. drop every line containing the idiom `${TMPDIR:-/tmp}` -- so a FIXED
  #      name written that way sailed through the check that forbids it;
  #   2. drop every line containing the word `mktemp` -- so a fixed path merely
  #      SHARING a line with a sanctioned call was excused too.
  # Excusing the sanctioned construct is right. Excusing whatever sits beside it
  # is how an exemption becomes a hiding place.
  # TWO shapes, because they do not look alike to a regex: a bare `/tmp/name`,
  # and the idiom `${TMPDIR:-/tmp}/name` where `/tmp` is followed by `}`. The
  # first cut wrote only the first alternative and then `grep -v`-ed the idiom
  # wholesale, so the idiom form was doubly invisible.
  grep -rnE --include='*.md' -- '(^|[^A-Za-z0-9_])/tmp/[A-Za-z0-9_.-]|\$\{TMPDIR:-/tmp\}/[A-Za-z0-9_.-]' \
    $SCAN_ROOTS 2>/dev/null \
    | grep -vE "$ALLOW_PATHS" \
    | sed -E 's/mktemp( -d)?[ \t]+\\?"?[$]\{TMPDIR:-\/tmp\}\/[A-Za-z0-9_.${}-]*X{3,}\\?"?//g' \
    | grep -E '(^|[^A-Za-z0-9_])/tmp/[A-Za-z0-9_.-]|[$]\{TMPDIR:-/tmp\}/[A-Za-z0-9_.-]'
}

HITS=$(scan_fixed_tmp || true)
require "no skill names a fixed scratch path under /tmp" \
  bash -c '[ -z "$0" ] || { printf "%s\n" "$0"; exit 1; }' "$HITS"

# Positive control. Without it, a scan broken by a bad flag or a wrong path
# (all of which have happened in this repo) reads as a clean tree. Unique name
# + trap, because the canary is written INTO the repo and an interrupted run
# would otherwise leave it there as a permanent red.
CANARY="$PLUGIN/skills/idd-verify/.tmp-path-canary.$$-${RANDOM}.md"
trap 'rm -f "$CANARY"' EXIT HUP INT TERM
printf 'canary: write findings to /tmp/verify_${NUMBER}_findings_logic.md\n' > "$CANARY"
SEEN=$(scan_fixed_tmp | grep -c 'tmp-path-canary' || true)
rm -f "$CANARY"
require "positive control: the scan actually detects a planted fixed path" \
  bash -c '[ "$0" -ge 1 ]' "$SEEN"

# Second control, for the exemption itself: a FIXED name written with the
# ${TMPDIR:-/tmp} idiom must still be caught. Under the old blanket `grep -v`
# this exact line was invisible.
CANARY2="$PLUGIN/skills/idd-verify/.tmp-idiom-canary.$$-${RANDOM}.md"
trap 'rm -f "$CANARY" "$CANARY2"' EXIT HUP INT TERM
printf 'body-file ${TMPDIR:-/tmp}/pointer.md\n' > "$CANARY2"
SEEN2=$(scan_fixed_tmp | grep -c 'tmp-idiom-canary' || true)
rm -f "$CANARY2"
require "positive control: the TMPDIR idiom does not grant blanket exemption" \
  bash -c '[ "$0" -ge 1 ]' "$SEEN2"

# Third control: a fixed path that merely SHARES A LINE with a sanctioned
# mktemp call. Under `grep -v mktemp` this whole line was excused, so a fixed
# egress body could hide simply by sitting next to a legitimate call.
CANARY3="$PLUGIN/skills/idd-verify/.tmp-beside-mktemp-canary.$$-${RANDOM}.md"
trap 'rm -f "$CANARY" "$CANARY2" "$CANARY3"' EXIT HUP INT TERM
printf 'D=$(mktemp -d "${TMPDIR:-/tmp}/ok-XXXXXX"); cp "$D/x" /tmp/pointer.md\n' > "$CANARY3"
SEEN3=$(scan_fixed_tmp | grep -c 'tmp-beside-mktemp-canary' || true)
rm -f "$CANARY3"
require "positive control: a fixed path beside a sanctioned mktemp call is still caught" \
  bash -c '[ "$0" -ge 1 ]' "$SEEN3"

# The sanctioned replacement must be present and resolved BEFORE anything is
# written — a run directory created after the first write is not a run
# directory, it is a rename.
VERIFY_MD=$(cat "$PLUGIN/skills/idd-verify/SKILL.md")
assert_grep "idd-verify resolves a per-run scratch dir with mktemp -d" \
  'VERIFY_DIR=$(mktemp -d' "$VERIFY_MD"
assert_grep "...as a Step 0 task, before any spawn or write" \
  'TaskCreate(name="resolve_scratch_dir"' "$VERIFY_MD"
assert_grep "reviewer OUTPUT instructions use it" \
  '$VERIFY_DIR/findings_' "$VERIFY_MD"

# ── the tagging protocol's scratch dir must FAIL CLOSED ──
#
# `idd-verify` mandates this protocol, and the mention gate decides who gets
# notified by reading files in that directory. `mktemp -d` without `|| exit` left
# TAG_DIR empty on a full or read-only /tmp; the paths became `/collaborators.json`
# etc.; the verification loop then read a file that does not exist, `grep`
# produced nothing, the `for handle in ...` body ran ZERO times — and the gate
# passed silently. A gate that cannot read its own inputs must refuse.
#
# The same silent-zero-iterations failure had a second cause: nothing created
# `comment-body.md`, the file the loop scans. The consumer was repointed at the
# new directory and no producer was ever written.
TAG_MD=$(cat "$PLUGIN/rules/tagging-collaborators.md")
assert_grep "the tagging scratch dir fails closed" \
  'TAG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/idd-tagging-XXXXXX") || {' "$TAG_MD"
assert_grep "...and is cleaned up" 'trap ' "$TAG_MD"
assert_grep "the file the mention gate reads is actually written" \
  '> "$TAG_DIR/comment-body.md"' "$TAG_MD"
require "...by a producer that appears BEFORE the consumer that greps it" \
  bash -c 'P=$(printf "%s\n" "$0" | grep -n ">[ ]*\"[$]TAG_DIR/comment-body.md\"" | head -1 | cut -d: -f1);
           C=$(printf "%s\n" "$0" | grep -n "grep -oE .@\[A-Za-z0-9-\]" | head -1 | cut -d: -f1);
           [ -n "$P" ] && [ -n "$C" ] && [ "$P" -lt "$C" ]' "$TAG_MD"

# ── the mention gate, in EVERY file that implements it ──
#
# The previous round added "the producer appears before the consumer" and bound
# it to $TAG_MD alone -- the one file that had just been fixed. One directory
# over, `idd-comment` had its own inline copy of the same protocol, broken worse:
# the gate read a file no step ever wrote (the real body was written under a
# DIFFERENT name, in a later step), so it scanned a missing file, found no
# mentions, and passed. An assertion scoped to the fixed instance certifies the
# fix, not the property.
#
# So the check enumerates implementations by finding them: any file that greps
# for @-handles as a mention gate must (a) stage the body itself, (b) refuse an
# unset or empty body, and (c) do both BEFORE the grep.
GATE_FILES=$(grep -rlE --include='*.md' -- "grep -oE '@\[A-Za-z0-9-\]" \
  "$PLUGIN/skills" "$PLUGIN/rules" 2>/dev/null)
require "at least one mention-gate implementation was found (guards a vacuous sweep)" \
  bash -c '[ -n "$0" ]' "$GATE_FILES"

while IFS= read -r gf; do
  [ -z "$gf" ] && continue
  rel="${gf#$PLUGIN/}"
  BODY=$(cat "$gf")
  # (b) an unset/empty draft body must refuse. `printf '%s' "" > f` SUCCEEDS,
  # writes 0 bytes, and the loop then certifies "no mentions" about text it was
  # never given -- the same silent-zero-iterations failure as a missing file,
  # one layer down on a missing VALUE.
  case "$BODY" in
    *'${COMMENT_BODY:?'*) pass "$rel: refuses an unset draft body" ;;
    *) fail "$rel: refuses an unset draft body" \
            "no \${COMMENT_BODY:?...} guard — an unset body yields a 0-byte file and a silent pass" ;;
  esac
  case "$BODY" in
    *'-s "$TAG_DIR/comment-body.md"'*) pass "$rel: refuses an EMPTY staged body" ;;
    *) fail "$rel: refuses an EMPTY staged body" \
            "COMMENT_BODY=\"\" passes :? and still stages nothing" ;;
  esac
  # (a)+(c) producer before consumer, in this file.
  P=$(printf '%s\n' "$BODY" | grep -n '> "\$TAG_DIR/comment-body.md"' | head -1 | cut -d: -f1)
  C=$(printf '%s\n' "$BODY" | grep -n "grep -oE '@\[A-Za-z0-9-\]" | head -1 | cut -d: -f1)
  if [ -n "$P" ] && [ -n "$C" ] && [ "$P" -lt "$C" ]; then
    pass "$rel: the body is staged BEFORE the gate reads it"
  else
    fail "$rel: the body is staged BEFORE the gate reads it" \
         "producer=${P:-none} consumer=${C:-none}"
  fi
done <<GATE_FILE_LIST
$GATE_FILES
GATE_FILE_LIST

# `MENTION_ATTESTED` has to be produced by whoever runs the gate. idd-comment
# read it in the egress call and assigned it nowhere, so the flag was always
# omitted -- and gh-egress's mention net then REFUSES every legitimate @mention.
# Both ends of the documented flow were broken at once: the gate could not fire,
# and the net blocked unconditionally.
while IFS= read -r gf; do
  [ -z "$gf" ] && continue
  rel="${gf#$PLUGIN/}"
  BODY=$(cat "$gf")
  case "$BODY" in
    *'${MENTION_ATTESTED:+'*)
      case "$BODY" in
        *'MENTION_ATTESTED='*) pass "$rel: sets MENTION_ATTESTED before consuming it" ;;
        *) fail "$rel: sets MENTION_ATTESTED before consuming it" \
                "the flag is read but never assigned — gh-egress refuses every mention" ;;
      esac ;;
  esac
done <<ATTEST_FILE_LIST
$(grep -rlE --include='*.md' -- 'MENTION_ATTESTED:\+' "$PLUGIN/skills" 2>/dev/null)
ATTEST_FILE_LIST

print_summary "verify-scratch-paths"
exit $?
