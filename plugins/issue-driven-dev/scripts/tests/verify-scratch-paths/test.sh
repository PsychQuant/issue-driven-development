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
#   idd-edit-backup          a documented recovery location users are told to
#                            `ls`; moving it is a behaviour change, and its
#                            collision consequence is a visible clash, not a
#                            wrong comment.
#   idd-edit-parse-err       a parse-error scratch file, PID-suffixed, read back
#                            by the same run and never posted.
#   idd-issue-attachments    a staging directory for downloads; the files are
#                            read back by the same run and never posted.
#
# The entries name PATHS, not DIRECTORIES, and that distinction is the whole of
# this fix. The first cut wrote `skills/idd-edit/` — a whole directory exempted
# on the strength of a reason that named one path inside it. Two egress bodies
# inherited it: the replacement text and the new comment body, both written to
# a fixed name and handed straight to `gh-egress edit-comment`, i.e. PATCHed
# into someone else`s comment. An exemption is a promise about a path; writing
# it as a directory promises for files nobody looked at.
SCAN_ROOTS="$PLUGIN/skills $PLUGIN/rules $PLUGIN/references"
ALLOW_PATHS='idd-edit-backup|idd-edit-parse-err|idd-issue-attachments'
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
  # ONLY inside fenced code blocks. The rule is about paths a skill USES, and a
  # skill executes what is in its fences; a path named in prose is an example, a
  # past attack vector being discussed, or a `--body-file=` illustration for the
  # reader. Scanning prose made the widened scope report four such lines in
  # idd-edit and nothing about them was wrong.
  #
  # This is a property, not a wording heuristic: fenced or not fenced.
  for _f in $(find $SCAN_ROOTS -name '*.md' 2>/dev/null); do
    awk -v F="$_f" '
      /^[[:space:]]*```/ { infence = !infence; next }
      infence { print F ":" NR ":" $0 }
    ' "$_f"
  done 2>/dev/null \
    | grep -vE '^[^:]*:[0-9]+:[[:space:]]*#' \
    | grep -E -- '(^|[^A-Za-z0-9_])/tmp/[A-Za-z0-9_.-]|\$\{TMPDIR:-/tmp\}/[A-Za-z0-9_.-]' \
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
printf '```bash\ncanary: write findings to /tmp/verify_${NUMBER}_findings_logic.md\n```\n' > "$CANARY"
SEEN=$(scan_fixed_tmp | grep -c 'tmp-path-canary' || true)
rm -f "$CANARY"
require "positive control: the scan actually detects a planted fixed path" \
  bash -c '[ "$0" -ge 1 ]' "$SEEN"

# Second control, for the exemption itself: a FIXED name written with the
# ${TMPDIR:-/tmp} idiom must still be caught. Under the old blanket `grep -v`
# this exact line was invisible.
CANARY2="$PLUGIN/skills/idd-verify/.tmp-idiom-canary.$$-${RANDOM}.md"
trap 'rm -f "$CANARY" "$CANARY2"' EXIT HUP INT TERM
printf '```bash\nbody-file ${TMPDIR:-/tmp}/pointer.md\n```\n' > "$CANARY2"
SEEN2=$(scan_fixed_tmp | grep -c 'tmp-idiom-canary' || true)
rm -f "$CANARY2"
require "positive control: the TMPDIR idiom does not grant blanket exemption" \
  bash -c '[ "$0" -ge 1 ]' "$SEEN2"

# Third control: a fixed path that merely SHARES A LINE with a sanctioned
# mktemp call. Under `grep -v mktemp` this whole line was excused, so a fixed
# egress body could hide simply by sitting next to a legitimate call.
CANARY3="$PLUGIN/skills/idd-verify/.tmp-beside-mktemp-canary.$$-${RANDOM}.md"
trap 'rm -f "$CANARY" "$CANARY2" "$CANARY3"' EXIT HUP INT TERM
printf '```bash\nD=$(mktemp -d "${TMPDIR:-/tmp}/ok-XXXXXX"); cp "$D/x" /tmp/pointer.md\n```\n' > "$CANARY3"
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

# ── a cleanup trap must not swallow the signal that fired it ──
#
# `trap 'rm -rf "$TAG_DIR"' EXIT HUP INT TERM` does two things at once, and the
# second is not wanted. On HUP or TERM it deletes the directory AND replaces the
# default termination semantics with "run this and carry on" -- so a caller
# without `set -e` continues into the verification loop, `grep` finds no file,
# the loop runs zero times, and the mention gate passes silently.
#
# That is the same silent-zero-iterations failure this file already records
# twice (a missing file, then a missing VALUE), arriving a third time through
# the signal path. Each fix closed the layer it was looking at.
#
# The shape that works: EXIT does cleanup; each signal runs cleanup, restores
# the default disposition, and re-raises itself, so the process dies the way the
# sender asked. Checked per implementation rather than per file, since the same
# protocol is inlined in three places.
TRAP_FILES=$(grep -rlE --include='*.md' -- 'TAG_DIR=\$\(mktemp' \
  "$PLUGIN/skills" "$PLUGIN/rules" 2>/dev/null)
require "at least one TAG_DIR implementation was found (guards a vacuous sweep)" \
  bash -c '[ -n "$0" ]' "$TRAP_FILES"
while IFS= read -r tf; do
  [ -z "$tf" ] && continue
  rel="${tf#$PLUGIN/}"
  BODY=$(cat "$tf")
  if printf '%s\n' "$BODY" | grep -qE "^trap '[^']*' EXIT HUP INT TERM"; then
    fail "$rel: the cleanup trap does not swallow HUP/TERM" \
         "one trap for EXIT and the signals means a signal is handled and then ignored"
  else
    pass "$rel: the cleanup trap does not swallow HUP/TERM"
  fi
  case "$BODY" in
    *'kill -s "$sig" $$'*) pass "$rel: ...and the signal is re-raised after cleanup" ;;
    *) fail "$rel: ...and the signal is re-raised after cleanup" \
            "no re-raise — the process survives a termination request" ;;
  esac
  # Defence in depth, and the part that does not depend on signals at all: the
  # loop must refuse when its input is not there, whatever removed it. Scoped to
  # files that actually RUN the gate — `idd-issue` creates a TAG_DIR and then
  # delegates the verification to `rules/tagging-collaborators.md`, so requiring
  # a staging guard there would be demanding a guard for a loop it does not have.
  # (The first cut of this assertion was scoped to "makes a TAG_DIR" and failed
  # idd-issue for exactly that reason: a red that named a real file and a real
  # line, and was still wrong about what the file does.)
  if printf '%s\n' "$BODY" | grep -q "grep -oE '@\[A-Za-z0-9-\]"; then
    case "$BODY" in
      *'[ -s "$TAG_DIR/comment-body.md" ] || {'*)
        pass "$rel: the gate refuses when its input file is absent or empty" ;;
      *) fail "$rel: the gate refuses when its input file is absent or empty" \
              "a missing body still yields zero iterations and a silent pass" ;;
    esac
  fi
done <<TRAP_FILE_LIST
$TRAP_FILES
TRAP_FILE_LIST

# ── the mention gate must actually be able to VERIFY a collaborator ──
#
# `gh api ... --jq ".[] | {login, name}"` emits a STREAM of objects, one per
# collaborator, not an array. The consumer then runs
# `jq -e ".[] | select(.login == …)"` over that file, so `.[]` iterates the
# FIELDS of each object and `select` asks a string for `.login`:
#
#   jq: error: Cannot index string with string ("login")      rc=5
#
# Every legitimate @mention is therefore refused, and the `MENTION_ATTESTED`
# path added this round cannot work for anyone. Two independent Codex legs found
# it in two different files.
#
# Checked by RUNNING both halves against a sample, not by grepping the shape:
# the failure is a type error at the seam between two commands, and only
# executing the seam can see it.
COLLAB_SRC=$(mktemp "${TMPDIR:-/tmp}/collab-src-XXXXXX") || COLLAB_SRC=""
COLLAB_OUT=$(mktemp "${TMPDIR:-/tmp}/collab-out-XXXXXX") || COLLAB_OUT=""
require "the collaborator-shape fixtures could be created" \
  bash -c '[ -n "$0" ] && [ -n "$1" ]' "$COLLAB_SRC" "$COLLAB_OUT"
printf '%s' '[{"login":"alice","name":"A"},{"login":"bob","name":"B"}]' > "$COLLAB_SRC"

while IFS= read -r gf; do
  [ -z "$gf" ] && continue
  rel="${gf#$PLUGIN/}"
  # the producer jq program, taken from the file under test
  PROD=$(grep -oE -- "--jq '\[?\.\[\][^']*'" "$gf" | head -1 | sed "s/^--jq '//; s/'$//")
  if [ -z "$PROD" ]; then
    pass "$rel: no collaborator producer here (nothing to check)"
    continue
  fi
  jq -r "$PROD" "$COLLAB_SRC" > "$COLLAB_OUT" 2>/dev/null
  if jq -e '.[] | select(.login == "alice")' "$COLLAB_OUT" >/dev/null 2>&1; then
    pass "$rel: a real collaborator VERIFIES against the file this produces"
  else
    fail "$rel: a real collaborator VERIFIES against the file this produces" \
         "producer emits [$PROD] — the consumer's .[] cannot read it, so every mention is refused"
  fi
  # Page 2 exists on real repos. Without --paginate every collaborator past the
  # first page is treated as unverified and the gate aborts the post.
  if grep -q 'repos/\$OWNER/\$REPO/collaborators' "$gf"; then
    if grep -E 'repos/\$OWNER/\$REPO/collaborators' "$gf" | grep -q -- '--paginate'; then
      pass "$rel: the collaborator fetch is paginated"
    else
      fail "$rel: the collaborator fetch is paginated" \
           "page 2+ collaborators are refused as unverified"
    fi
  fi
done <<COLLAB_FILE_LIST
$(grep -rlE --include='*.md' -- 'repos/\$OWNER/\$REPO/collaborators' "$PLUGIN/skills" "$PLUGIN/rules" 2>/dev/null)
COLLAB_FILE_LIST
# The org-member half of the union must have a consumer. The protocol fetches
# `org-members.json` and declared "the combined set is the only source of truth",
# while the verification loop read `collaborators.json` alone — a produced-but-
# unread allowlist, i.e. a spec and an implementation disagreeing inside one file.
# An org member who is not a direct collaborator was refused as unverified.
TAG_MD_SRC=$(cat "$PLUGIN/rules/tagging-collaborators.md")
assert_grep "the verification loop consults org-members too, not just collaborators" \
  'org-members.json' "$TAG_MD_SRC"
# The needle is the QUERY, not the filename. The first cut compared the last
# line mentioning `org-members.json` against the ERROR line — and the prose
# explaining WHY the fallback exists mentions the filename too, so deleting the
# fallback left the comment to satisfy the assertion. Fourth instance of a needle
# met by a neighbour in this work; the fix is always to name the mechanism.
require "...as a QUERY inside the verify loop, not merely fetched or mentioned" \
  bash -c '
    P=$(printf "%s\n" "$0" | grep -n "jq -e --arg l .*org-members.json\|org-members.json. > /dev/null" | tail -1 | cut -d: -f1)
    L=$(printf "%s\n" "$0" | grep -n "ERROR: @\$login" | head -1 | cut -d: -f1)
    [ -n "$P" ] && [ -n "$L" ] && [ "$P" -lt "$L" ]' "$TAG_MD_SRC"
# ...and the reason commit-authors.txt is NOT in the union has to be written
# down, or the next reader adds it and starts matching logins against emails.
assert_grep "the exclusion of commit-authors from the union is explained" \
  'not logins' "$TAG_MD_SRC"
rm -f "$COLLAB_SRC" "$COLLAB_OUT"

# ── the widened SCOPE has to have weight ──
#
# Round 12 widened this scan from `skills/idd-verify` to skills/ + rules/ +
# references/ and made that widening the headline of the change. Measured
# afterwards by an outside reviewer: narrowing `SCAN_ROOTS` back to `$PLUGIN`,
# or all the way back to `$PLUGIN/skills/idd-verify`, left the suite 20/0 GREEN.
# All three positive controls plant their canary in `skills/idd-verify` — the
# old scope — so every one of them tests the grep flags and the sed exemption,
# and none tests where the scan looks.
#
# What makes this worth more than the fix: in the SAME round, in the sibling
# suite `plan-routing-consistency`, the identical lesson was written down --
# "a scope with no control is a scope that will be narrowed by the next person
# who finds it noisy" -- and canaries were added there for docs/ and
# openspec/specs/. Diagnosed in one suite, shipped unfixed in the other, by the
# same hand on the same day. Writing a lesson down is not the same as applying
# it, and the gap is invisible from inside the file where it was written.
for SCOPE_ROOT in "$PLUGIN/rules" "$PLUGIN/references"; do
  if [ ! -d "$SCOPE_ROOT" ]; then
    fail "scope control: $SCOPE_ROOT exists" "the scan claims to cover it"
    continue
  fi
  SC="$SCOPE_ROOT/.tmp-scope-canary.$$-${RANDOM}.md"
  printf '```bash\ncp "$D/x" /tmp/scope-canary-pointer.md\n```\n' > "$SC"
  if scan_fixed_tmp | grep -q 'tmp-scope-canary'; then
    pass "scope control: a fixed path planted in ${SCOPE_ROOT#$PLUGIN/} is detected"
  else
    fail "scope control: a fixed path planted in ${SCOPE_ROOT#$PLUGIN/} is detected" \
         "the scan does not actually reach ${SCOPE_ROOT#$PLUGIN/}"
  fi
  rm -f "$SC"
done

# ── the pointer-publishing loop must not report success over a wrong post ──
#
# `references/external-agent-delegation.md` is already in this suite's scope
# because its egress bodies are why the scope was widened. Three fail-open
# shapes lived in six lines of it, each publishing something wrong while
# reporting success:
#
#   MASTER_URL=$(gh ... 2>&1 | tail -1)   a failed `gh` still gives `tail` a
#                                         zero exit, so the LAST LINE OF THE
#                                         ERROR became the URL in every pointer
#   one shared pointer.md                 rewritten in the loop while background
#                                         `gh` processes were reading it
#   a bare `wait`                         returns 0 and hides child failures
#
# Asserted on the shipped text: this is prose the executing model follows, and
# there is no binary to run.
EAD=$(cat "$PLUGIN/references/external-agent-delegation.md")
refute_grep "the master-comment capture no longer folds stderr into the pipe" \
  'gh pr comment "$PR" --repo "$REPO" --body-file "$VERIFY_DIR/master.md" 2>&1 | tail -1' "$EAD"
assert_grep "...it checks the command status instead" \
  'if ! MASTER_URL=$(gh pr comment' "$EAD"
assert_grep "...and refuses anything that is not a URL" \
  'the master comment did not return a URL' "$EAD"
assert_grep "each issue gets its OWN pointer body file" \
  'pointer-$I.md' "$EAD"
refute_grep "...so the shared one is gone" \
  '> "$VERIFY_DIR/pointer.md"' "$EAD"
require "the pointer posts are waited on INDIVIDUALLY, not with a bare wait" \
  bash -c '
    printf "%s\n" "$0" | grep -q "wait \"\$pid\" || PTR_FAILED=" || exit 1
    printf "%s\n" "$0" | grep -qE "^wait$" && exit 1
    exit 0' "$EAD"
assert_grep "...and a failed pointer makes the run refuse, not report done" \
  'the external audit trail is INCOMPLETE' "$EAD"

print_summary "verify-scratch-paths"
exit $?
