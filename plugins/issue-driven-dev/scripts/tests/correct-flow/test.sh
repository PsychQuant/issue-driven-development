#!/usr/bin/env bash
# test.sh — /idd-edit --correct end to end: correct-prepare → (preview) →
# correct-apply / correct-discard against a fake gh, with TMPDIR under /var the
# way macOS has it (#351). Rounds 1–4 of verify kept finding defects in a flow
# that only had static string contracts; this suite runs the flow itself.
#
# Change: openspec/changes/idd-edit-in-place-correction (tasks section 11)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
HELPER="$PLUGIN/scripts/idd-edit-helper.py"

WORK="$(mktemp -d /tmp/idd-cf-XXXXXX)"
cleanup() { chmod -R u+rwx "$WORK" 2>/dev/null; rm -rf "$WORK" "$TMPDIR"; }
trap cleanup EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
# macOS keeps the user's temp dir under /var. A private one per run: counting
# working directories in a shared /var/tmp made two overlapping runs fail
# each other (verify #351 round 6).
export TMPDIR="$(mktemp -d /var/tmp/idd-cf-tmp-XXXXXX)"
export FAKE_GH_STORE="$WORK/store"; mkdir -p "$FAKE_GH_STORE"
mkdir -p "$WORK/bin"
printf '#!/bin/sh\nexec python3 "%s/fake-gh.py" "$@"\n' "$HERE" >"$WORK/bin/gh"; chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"
printf 'kiki830621' >"$FAKE_GH_STORE/user"
REPO="$WORK/repo"; mkdir -p "$REPO"; git -C "$REPO" init -q
ARCH="$REPO/.claude/.idd/archive/edits"

# mkrec <file> <login> <assoc> <body>
mkrec() {
  python3 - "$FAKE_GH_STORE/$1" "$2" "$3" "$4" <<'PY'
import json, sys
path, login, assoc, body = sys.argv[1:]
json.dump({"body": body, "user": {"login": login}, "author_association": assoc,
           "html_url": "https://github.com/o/r/x"}, open(path, "w"))
PY
}
body_of() { python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["body"])' "$FAKE_GH_STORE/$1"; }
val() { sed -n "s/^$1=//p" "$2" | head -1; }
# helper <label> <args...> — run in the clone; stdout/stderr to files, rc in RC
helper() {
  local label="$1"; shift
  (cd "$REPO" && python3 "$HELPER" "$@") >"$WORK/$label.out" 2>"$WORK/$label.err"
  RC=$?
}
printf 'right text\n' >"$WORK/fix.md"
TMPFIX="$(mktemp -d "$TMPDIR/idd-cf-body-XXXXXX")"; printf 'right text\n' >"$TMPFIX/fix.md"
count_work() { find "$TMPDIR" -maxdepth 1 -name 'idd-correct-*' -user "$(id -u)" 2>/dev/null | wc -l | tr -d ' '; }
SECTION_BODY='## Notes
wrong text

## Next
- keep me'

# ── E1. comment section, confirmed ─────────────────────────────────────────
echo "E1. confirmed correction of a comment section"
mkrec comment-100.json kiki830621 MEMBER "$SECTION_BODY"
helper e1p correct-prepare --target comment:100 --repo o/r --section "## Notes" --body-file "$TMPFIX/fix.md" --scrub-attested warn
assert_exit "prepare succeeds with TMPDIR under /var" 0 "$RC"
E1W="$(val WORK "$WORK/e1p.out")"; E1P="$(val PREVIEW "$WORK/e1p.out")"
assert_file_exists "the preview is written" "$E1P"
assert_output_grep "the preview carries the new text" "right text" "$E1P"
assert_output_grep "the preview marks the backup id as pending" "(assigned after confirmation)" "$E1P"
helper e1a correct-apply --work "$E1W" --state "$(val STATE "$WORK/e1p.out")"
assert_exit "apply succeeds" 0 "$RC"
assert_eq "apply reports edited" "edited" "$(val RESULT "$WORK/e1a.out")"
E1ID="$(val BACKUP_ID "$WORK/e1a.out")"
assert_file_exists "the prior text is archived" "$ARCH/$E1ID.md"
body_of comment-100.json >"$WORK/e1.body"
assert_output_grep "the comment holds the corrected text" "right text" "$WORK/e1.body"
refute_output_grep "the wrong text is gone from the comment" "wrong text" "$WORK/e1.body"
assert_output_grep "the marker names the backup id" "backup-id=\"$E1ID\"" "$WORK/e1.body"
assert_output_grep "the rest of the comment is kept" "keep me" "$WORK/e1.body"
refute "the working directory is removed" test -e "$E1W"

# ── E2. declined ───────────────────────────────────────────────────────────
echo "E2. declined preview"
mkrec comment-101.json kiki830621 MEMBER "$SECTION_BODY"
helper e2p correct-prepare --target comment:101 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
E2W="$(val WORK "$WORK/e2p.out")"
helper e2d correct-discard --work "$E2W"
assert_exit "discard succeeds" 0 "$RC"
refute "the working directory is removed" test -e "$E2W"
assert_eq "the comment is unchanged" "$SECTION_BODY" "$(body_of comment-101.json)"
refute "nothing is archived" sh -c "ls '$ARCH' 2>/dev/null | grep -q comment-101"

# ── E3. changed since preview ──────────────────────────────────────────────
echo "E3. target changed after the preview"
mkrec comment-102.json kiki830621 MEMBER "$SECTION_BODY"
helper e3p correct-prepare --target comment:102 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
E3W="$(val WORK "$WORK/e3p.out")"
mkrec comment-102.json kiki830621 MEMBER "$SECTION_BODY
someone added this"
helper e3a correct-apply --work "$E3W" --state "$(val STATE "$WORK/e3p.out")"
assert_exit "apply refuses" 4 "$RC"
assert_eq "reason is changed-since-preview" "changed-since-preview" "$(val REASON "$WORK/e3a.out")"
refute "nothing is archived" sh -c "ls '$ARCH' 2>/dev/null | grep -q comment-102"
refute "the working directory is removed after a refusal" test -e "$E3W"

# ── E4. egress refusal happens before anything is archived ────────────────
echo "E4. egress gates before the archive"
mkrec comment-103.json kiki830621 MEMBER "## Notes
Thanks @alice, but this is wrong

## Next
- keep me"
printf 'Thanks @alice, fixed\n' >"$WORK/fix-mention-kept.md"
helper e4a correct-prepare --target comment:103 --repo o/r --section "## Notes" --body-file "$WORK/fix-mention-kept.md" --scrub-attested warn
assert_exit "an existing mention is attested" 0 "$RC"
helper e4a2 correct-discard --work "$(val WORK "$WORK/e4a.out")"
printf 'fixed, cc @bob\n' >"$WORK/fix-mention-new.md"
E4_BEFORE="$(count_work)"
helper e4b correct-prepare --target comment:103 --repo o/r --section "## Notes" --body-file "$WORK/fix-mention-new.md" --scrub-attested warn
assert_exit "a new mention is refused at prepare" 4 "$RC"
assert_eq "reason is egress" "egress" "$(val REASON "$WORK/e4b.out")"
refute "the refusal prints no working directory" test -n "$(val WORK "$WORK/e4b.out")"
assert_eq "and leaves none on disk" "$E4_BEFORE" "$(count_work)"

# ── E5. gh fails the write ─────────────────────────────────────────────────
echo "E5. failed write"
mkrec comment-104.json kiki830621 MEMBER "$SECTION_BODY"
helper e5p correct-prepare --target comment:104 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
: >"$FAKE_GH_STORE/fail-patch"
helper e5a correct-apply --work "$(val WORK "$WORK/e5p.out")" --state "$(val STATE "$WORK/e5p.out")"
rm -f "$FAKE_GH_STORE/fail-patch"
assert_exit "a failed write is not success" 4 "$RC"
assert_eq "result is write-failed" "write-failed" "$(val RESULT "$WORK/e5a.out")"
assert_eq "the comment is unchanged" "$SECTION_BODY" "$(body_of comment-104.json)"

# ── E6. read-back differs ──────────────────────────────────────────────────
echo "E6. unverified write"
mkrec comment-105.json kiki830621 MEMBER "$SECTION_BODY"
helper e6p correct-prepare --target comment:105 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
: >"$FAKE_GH_STORE/mangle-read"
helper e6a correct-apply --work "$(val WORK "$WORK/e6p.out")" --state "$(val STATE "$WORK/e6p.out")"
rm -f "$FAKE_GH_STORE/mangle-read"
assert_exit "a read-back that differs exits 7" 7 "$RC"
assert_eq "result is unverified" "unverified" "$(val RESULT "$WORK/e6a.out")"

# ── E7. target cannot be read ──────────────────────────────────────────────
echo "E7. fetch failure"
helper e7 correct-prepare --target comment:999 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
assert_exit "prepare refuses" 4 "$RC"
assert_eq "reason is fetch-failed" "fetch-failed" "$(val REASON "$WORK/e7.out")"

# ── E8. issue body ─────────────────────────────────────────────────────────
echo "E8. issue body section"
mkrec issue-351.json kiki830621 OWNER "## Problem
x

## Related
- #347 — wrong claim

---

## Current Status

**Phase**: diagnosed"
printf -- '- #347 — the right claim\n' >"$WORK/fix-related.md"
helper e8p correct-prepare --target issue:351 --repo o/r --section "## Related" --body-file "$WORK/fix-related.md" --scrub-attested warn
assert_exit "prepare succeeds for an issue body" 0 "$RC"
helper e8a correct-apply --work "$(val WORK "$WORK/e8p.out")" --state "$(val STATE "$WORK/e8p.out")"
assert_exit "apply succeeds for an issue body" 0 "$RC"
body_of issue-351.json >"$WORK/e8.body"
assert_output_grep "the issue body is corrected" "the right claim" "$WORK/e8.body"
assert_output_grep "Current Status is untouched" "**Phase**: diagnosed" "$WORK/e8.body"
assert_output_grep "the issue body is written through gh issue edit" "issue edit 351" "$FAKE_GH_STORE/calls.log"

# ── E9. a bot's comment ────────────────────────────────────────────────────
echo "E9. bot author"
mkrec comment-106.json "coderabbitai[bot]" NONE "$SECTION_BODY"
helper e9 correct-prepare --target comment:106 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
assert_exit "prepare refuses a bot's comment" 4 "$RC"
assert_eq "reason is R5" "R5" "$(val REASON "$WORK/e9.out")"

# ── E10. the working directory was changed after the preview ──────────────
echo "E10. tampered preview"
mkrec comment-107.json kiki830621 MEMBER "$SECTION_BODY"
helper e10p correct-prepare --target comment:107 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
printf 'something else\n' >>"$(val PREVIEW "$WORK/e10p.out")"
helper e10a correct-apply --work "$(val WORK "$WORK/e10p.out")" --state "$(val STATE "$WORK/e10p.out")"
assert_exit "apply refuses a changed preview" 4 "$RC"
assert_eq "reason is differs-from-preview" "differs-from-preview" "$(val REASON "$WORK/e10a.out")"
assert_eq "the comment is unchanged" "$SECTION_BODY" "$(body_of comment-107.json)"

# ── E11. protected region ──────────────────────────────────────────────────
echo "E11. managed section"
helper e11 correct-prepare --target issue:351 --repo o/r --section "## Current Status" --body-file "$WORK/fix.md" --scrub-attested warn
assert_exit "prepare refuses ## Current Status" 4 "$RC"
assert_eq "reason is protected" "protected" "$(val REASON "$WORK/e11.out")"

# ── E12. apply only accepts a directory prepare made ──────────────────────
echo "E12. foreign working directory"
mkdir -p "$WORK/foreign"
helper e12 correct-apply --work "$WORK/foreign"
assert_exit "apply refuses a directory it did not create" 2 "$RC"

# ── R6. round 6 (verify #351 round 5) ─────────────────────────────────────
echo "R6. round 6"
BEFORE="$(count_work)"

# R6.1 a heading that occurs twice is ambiguous
mkrec comment-200.json kiki830621 MEMBER "## Notes
fine text

## Notes
wrong text"
helper r1 correct-prepare --target comment:200 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
assert_exit "a repeated heading is refused" 4 "$RC"
assert_eq "reason is section-ambiguous" "section-ambiguous" "$(val REASON "$WORK/r1.out")"

# R6.2 a replacement that starts with the target heading is accepted
mkrec comment-201.json kiki830621 MEMBER "$SECTION_BODY"
printf '## Notes\nright text\n' >"$WORK/fix-heading.md"
helper r2p correct-prepare --target comment:201 --repo o/r --section "## Notes" --body-file "$WORK/fix-heading.md" --scrub-attested warn
assert_exit "prepare accepts a replacement that repeats the target heading" 0 "$RC"
helper r2a correct-apply --work "$(val WORK "$WORK/r2p.out")" --state "$(val STATE "$WORK/r2p.out")"
assert_eq "the correction is applied" "edited" "$(val RESULT "$WORK/r2a.out")"
assert_eq "it holds the new text" "right text" "$(body_of comment-201.json | sed -n 2p)"
assert_eq "the heading appears once" "1" "$(body_of comment-201.json | grep -c '^## Notes$')"

# R6.3 the archive is the exact prior text (no added newline)
mkrec comment-202.json kiki830621 MEMBER "## Notes
wrong text, no newline at the end"
helper r3p correct-prepare --target comment:202 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
helper r3a correct-apply --work "$(val WORK "$WORK/r3p.out")" --state "$(val STATE "$WORK/r3p.out")"
R3ID="$(val BACKUP_ID "$WORK/r3a.out")"
chmod u+r "$ARCH/$R3ID.md"
assert_eq "the archive holds the body byte for byte" "$(printf '## Notes\nwrong text, no newline at the end' | od -c)" "$(od -c <"$ARCH/$R3ID.md")"
chmod 000 "$ARCH/$R3ID.md"

# R6.4 a changed state.json does not redirect the write
mkrec comment-203.json kiki830621 MEMBER "$SECTION_BODY"
mkrec comment-204.json kiki830621 MEMBER "$SECTION_BODY"
helper r4p correct-prepare --target comment:203 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
R4W="$(val WORK "$WORK/r4p.out")"
python3 - "$R4W/state.json" <<'PYS'
import json, sys
s = json.load(open(sys.argv[1])); s["target"] = "comment:204"; s["num"] = "204"
json.dump(s, open(sys.argv[1], "w"))
PYS
helper r4a correct-apply --work "$R4W" --state "$(val STATE "$WORK/r4p.out")"
assert_exit "apply refuses a state that no longer matches what was prepared" 4 "$RC"
assert_eq "the other comment is untouched" "$SECTION_BODY" "$(body_of comment-204.json)"

# R6.5 archive preconditions are checked before the preview
NG="$WORK/not-git"; mkdir -p "$NG"
mkrec comment-205.json kiki830621 MEMBER "$SECTION_BODY"
(cd "$NG" && python3 "$HELPER" correct-prepare --target comment:205 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn) >"$WORK/r5.out" 2>"$WORK/r5.err"
assert_exit "outside a git work tree prepare refuses" 4 "$?"
assert_eq "reason is archive" "archive" "$(val REASON "$WORK/r5.out")"

# R6.6 a setext heading inside the corrected range is refused
mkrec comment-206.json kiki830621 MEMBER "### Root Cause
the bug is in a.py
see line 3
---
follow-up"
helper r6 correct-prepare --target comment:206 --repo o/r --section "### Root Cause" --body-file "$WORK/fix.md" --scrub-attested warn
assert_exit "a setext heading in the range is refused" 4 "$RC"
assert_eq "reason is setext, not protected" "setext" "$(val REASON "$WORK/r6.out")"

# R6.7 whole-comment correction of a dashboard comment, end to end
mkrec comment-207.json kiki830621 MEMBER "<!-- idd:dashboard -->
## For Reviewer
wrong"
printf '<!-- idd:dashboard -->\n## For Reviewer\nright\n' >"$WORK/fix-dash.md"
helper r7p correct-prepare --target comment:207 --repo o/r --scope whole-comment --body-file "$WORK/fix-dash.md" --scrub-attested warn
assert_exit "whole-comment prepare succeeds" 0 "$RC"
helper r7a correct-apply --work "$(val WORK "$WORK/r7p.out")" --state "$(val STATE "$WORK/r7p.out")"
assert_exit "whole-comment apply succeeds" 0 "$RC"
assert_eq "the dashboard marker is line 1, once" "<!-- idd:dashboard -->" "$(body_of comment-207.json | head -1)"
assert_eq "the dashboard marker is not repeated" "1" "$(body_of comment-207.json | grep -c 'idd:dashboard')"

# R6.8 an existing mention survives apply (attested at the write too)
mkrec comment-208.json kiki830621 MEMBER "## Notes
Thanks @alice, but this is wrong

## Next
- keep me"
helper r8p correct-prepare --target comment:208 --repo o/r --section "## Notes" --body-file "$WORK/fix-mention-kept.md" --scrub-attested warn
helper r8a correct-apply --work "$(val WORK "$WORK/r8p.out")" --state "$(val STATE "$WORK/r8p.out")"
assert_exit "apply writes a body that keeps an existing mention" 0 "$RC"

# R6.9 a failed write is re-read before it is called unchanged
mkrec comment-209.json kiki830621 MEMBER "$SECTION_BODY"
helper r9p correct-prepare --target comment:209 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
: >"$FAKE_GH_STORE/fail-patch"
helper r9a correct-apply --work "$(val WORK "$WORK/r9p.out")" --state "$(val STATE "$WORK/r9p.out")"
rm -f "$FAKE_GH_STORE/fail-patch"
assert_output_grep "a write failure still reports the backup id" "BACKUP_ID=" "$WORK/r9a.out"
require "the target was re-read after the failed write" \
  awk '/comments\/209/ && /PATCH/ {p=1; next} p && /^api repos\/o\/r\/issues\/comments\/209/ && !/PATCH/ {f=1} END {exit !f}' "$FAKE_GH_STORE/calls.log"

# ── R8. round 8 (verify #351 round 6) ─────────────────────────────────────
echo "R8. round 8"

# R8.1 (the SKILL's own Step 1.6 in two shells) moved to scripts/tests/edit-run
# part B in round 9: it seeded variables, a loop and bash where an agent has
# none of them and runs zsh (verify #351 round 7).

# R8.2 apply runs the author gate again: the gh user changed after the preview
mkrec comment-402.json kiki830621 MEMBER "$SECTION_BODY"
helper r82p correct-prepare --target comment:402 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
printf 'someone-else' >"$FAKE_GH_STORE/user"
helper r82a correct-apply --work "$(val WORK "$WORK/r82p.out")" --state "$(val STATE "$WORK/r82p.out")"
printf 'kiki830621' >"$FAKE_GH_STORE/user"
assert_eq "apply re-runs the author gate" "R5" "$(val REASON "$WORK/r82a.out")"
assert_eq "the target is unchanged" "$SECTION_BODY" "$(body_of comment-402.json)"

# restate <work> <python statement on s> — rewrite state.json, print its new digest
restate() {
  python3 - "$1/state.json" "$2" <<'PYX'
import hashlib, json, sys
path, stmt = sys.argv[1:]
s = json.load(open(path)); exec(stmt)
data = json.dumps(s).encode(); open(path, "wb").write(data)
print(hashlib.sha256(data).hexdigest())
PYX
}
# R8.3 apply runs the protected-region check again, before comparing the preview
mkrec comment-403.json kiki830621 MEMBER "## Notes
wrong text

## Current Status
- managed"
helper r83p correct-prepare --target comment:403 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
R83W="$(val WORK "$WORK/r83p.out")"
helper r83a correct-apply --work "$R83W" --state "$(restate "$R83W" 's["heading"] = "## Current Status"')"
assert_eq "a state naming a managed section is refused as protected" "protected" "$(val REASON "$WORK/r83a.out")"

# R8.4 a malformed field is refused even when the caller's digest matches it
mkrec comment-404.json kiki830621 MEMBER "$SECTION_BODY"
helper r84p correct-prepare --target comment:404 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
R84W="$(val WORK "$WORK/r84p.out")"
ARCH_N="$(ls "$ARCH" 2>/dev/null | wc -l | tr -d ' ')"
helper r84a correct-apply --work "$R84W" --state "$(restate "$R84W" 's["scrub"] = "none"')"
assert_eq "a malformed state field is refused" "differs-from-preview" "$(val REASON "$WORK/r84a.out")"
assert_eq "nothing is archived" "$ARCH_N" "$(ls "$ARCH" 2>/dev/null | wc -l | tr -d ' ')"

# R8.5 a write that lands before gh reports an error is unverified, not failed
mkrec comment-405.json kiki830621 MEMBER "$SECTION_BODY"
helper r85p correct-prepare --target comment:405 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
: >"$FAKE_GH_STORE/fail-after-patch"
helper r85a correct-apply --work "$(val WORK "$WORK/r85p.out")" --state "$(val STATE "$WORK/r85p.out")"
rm -f "$FAKE_GH_STORE/fail-after-patch"
assert_exit "a landed write with a gh error exits 7" 7 "$RC"
assert_eq "it is reported unverified" "unverified" "$(val RESULT "$WORK/r85a.out")"

# R8.6 a working directory left for more than a day is removed by the next prepare
STALE="$(mktemp -d "$TMPDIR/idd-correct-XXXXXX")"; : >"$STALE/state.json"; touch -t 202001010000 "$STALE"
FRESH="$(mktemp -d "$TMPDIR/idd-correct-XXXXXX")"; : >"$FRESH/state.json"
helper r86 correct-prepare --target comment:9999 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
refute "the stale working directory is removed" test -d "$STALE"
require "a recent one is kept" test -d "$FRESH"
rm -rf "$FRESH"

# R8.7 a target in another repository is not read (the fake routes by owner/repo)
helper r87 correct-prepare --target comment:100 --repo o/other --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
assert_eq "another repository's comment is not this one" "fetch-failed" "$(val REASON "$WORK/r87.out")"

# R8.8 CRLF and a missing final newline outside the section stay byte for byte
python3 - "$FAKE_GH_STORE/comment-406.json" <<'PYX'
import json, sys
json.dump({"body": "## Notes\r\nwrong text\r\n\r\n## Next\r\n- keep me", "user": {"login": "kiki830621"},
           "author_association": "MEMBER", "html_url": "https://github.com/o/r/x"}, open(sys.argv[1], "w"))
PYX
helper r88p correct-prepare --target comment:406 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
helper r88a correct-apply --work "$(val WORK "$WORK/r88p.out")" --state "$(val STATE "$WORK/r88p.out")"
assert_eq "the CRLF original is corrected and reads back exactly" "edited" "$(val RESULT "$WORK/r88a.out")"
r88() { python3 -c 'import json,sys;b=json.load(open(sys.argv[1]))["body"];print(eval(sys.argv[2]))' "$FAKE_GH_STORE/comment-406.json" "$1"; }
assert_eq "the heading keeps its CRLF" "True" "$(r88 'b.startswith("## Notes\r\nright text\n")')"
assert_eq "the next section keeps its CRLF and no final newline" "True" "$(r88 'b.endswith("\n\n## Next\r\n- keep me")')"

# R8.9 a read-back with one extra newline is not what was sent
mkrec comment-407.json kiki830621 MEMBER "$SECTION_BODY"
helper r89p correct-prepare --target comment:407 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
: >"$FAKE_GH_STORE/pad-read"
helper r89a correct-apply --work "$(val WORK "$WORK/r89p.out")" --state "$(val STATE "$WORK/r89p.out")"
rm -f "$FAKE_GH_STORE/pad-read"
assert_eq "an extra newline on read-back is unverified" "unverified" "$(val RESULT "$WORK/r89a.out")"

# R8.10 the dashboard marker stays on line 1 when the replacement moves it
mkrec comment-408.json kiki830621 MEMBER "<!-- idd:dashboard -->
## For Reviewer
wrong"
printf '## For Reviewer\nright\n\n<!-- idd:dashboard -->\n' >"$WORK/fix-dash-end.md"
helper r810p correct-prepare --target comment:408 --repo o/r --scope whole-comment --body-file "$WORK/fix-dash-end.md" --scrub-attested warn
helper r810a correct-apply --work "$(val WORK "$WORK/r810p.out")" --state "$(val STATE "$WORK/r810p.out")"
assert_eq "the correction is applied" "edited" "$(val RESULT "$WORK/r810a.out")"
assert_eq "the marker is line 1" "<!-- idd:dashboard -->" "$(body_of comment-408.json | head -1)"
assert_eq "the marker appears once" "1" "$(body_of comment-408.json | grep -c 'idd:dashboard')"

# R8.11 a null comment body is a failed read
python3 - "$FAKE_GH_STORE/comment-409.json" <<'PYX'
import json, sys
json.dump({"body": None, "user": {"login": "kiki830621"}, "author_association": "MEMBER",
           "html_url": "https://github.com/o/r/x"}, open(sys.argv[1], "w"))
PYX
helper r811 correct-prepare --target comment:409 --repo o/r --scope whole-comment --body-file "$WORK/fix.md" --scrub-attested warn
assert_eq "a null comment body is fetch-failed" "fetch-failed" "$(val REASON "$WORK/r811.out")"

# R8.12 a replacement that is only the target heading is empty
mkrec comment-410.json kiki830621 MEMBER "$SECTION_BODY"
printf '## Notes\n' >"$WORK/fix-only-heading.md"
helper r812 correct-prepare --target comment:410 --repo o/r --section "## Notes" --body-file "$WORK/fix-only-heading.md" --scrub-attested warn
assert_exit "only the heading is refused as empty" 2 "$RC"

# R8.13 a replacement may not add a setext heading
printf 'right text\nmore\n---\n' >"$WORK/fix-setext.md"
helper r813 correct-prepare --target comment:410 --repo o/r --section "## Notes" --body-file "$WORK/fix-setext.md" --scrub-attested warn
assert_eq "an added setext heading is refused" "setext" "$(val REASON "$WORK/r813.out")"

# R8.14 the archive directory must be creatable before the preview
OBST="$WORK/obstructed"; mkdir -p "$OBST/.claude"; git -C "$OBST" init -q; : >"$OBST/.claude/.idd"
(cd "$OBST" && python3 "$HELPER" correct-prepare --target comment:410 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn) >"$WORK/r814.out" 2>"$WORK/r814.err"
assert_eq "a file where the archive directory goes is refused at prepare" "archive" "$(val REASON "$WORK/r814.out")"

# R8.15 the privacy attestation is the caller's, never defaulted
helper r815 correct-prepare --target comment:410 --repo o/r --section "## Notes" --body-file "$WORK/fix.md"
assert_exit "prepare without --scrub-attested is a usage error" 2 "$RC"

# R8.16 only your own content is corrected: the OWNER's words, when you are not
# the OWNER, are theirs (user decision 2026-10-17, verify #351 round 6)
mkrec comment-411.json repo-owner OWNER "$SECTION_BODY"
helper r816 correct-prepare --target comment:411 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
assert_eq "an OWNER comment by someone else is refused" "R5" "$(val REASON "$WORK/r816.out")"
printf 'repo-owner' >"$FAKE_GH_STORE/user"
helper r816b correct-prepare --target comment:411 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
printf 'kiki830621' >"$FAKE_GH_STORE/user"
assert_exit "the OWNER's own comment, corrected by the OWNER, is prepared" 0 "$RC"
helper r816c correct-discard --work "$(val WORK "$WORK/r816b.out")"

# ── R9. round 9 (verify #351 round 7) ─────────────────────────────────────
echo "R9. round 9"
# R9.1 a reply's quotation of a reviewer is verbatim-preserve
mkrec comment-420.json kiki830621 MEMBER "## 🧑‍🏫 Reply

> **Point 1**（review 2026-10-01）：
> 「The bound in Lemma 2 is wrong for n < 3.」

Fixed in a1b2c3."
printf '## 🧑‍🏫 Reply\n\n> **Point 1**（review 2026-10-01）：\n> 「The reviewer thinks Lemma 2 is slightly loose.」\n\nFixed in a1b2c3.\n' >"$WORK/fix-reply.md"
helper r91 correct-prepare --target comment:420 --repo o/r --scope whole-comment --body-file "$WORK/fix-reply.md" --scrub-attested warn
assert_eq "a rewritten reviewer quotation is refused" "protected" "$(val REASON "$WORK/r91.out")"
# R9.2 a setext heading is matched whole: a changed underline is a new one
mkrec comment-421.json kiki830621 MEMBER "Summary
-------
wrong"
printf 'Summary\n=======\nright\n' >"$WORK/fix-underline.md"
helper r92 correct-prepare --target comment:421 --repo o/r --scope whole-comment --body-file "$WORK/fix-underline.md" --scrub-attested warn
assert_eq "a changed setext underline is refused" "setext" "$(val REASON "$WORK/r92.out")"
printf 'Summary\n-------\nright\n\nSummary\n-------\nagain\n' >"$WORK/fix-twice.md"
helper r92b correct-prepare --target comment:421 --repo o/r --scope whole-comment --body-file "$WORK/fix-twice.md" --scrub-attested warn
assert_eq "a second copy of a setext heading is refused" "setext" "$(val REASON "$WORK/r92b.out")"
# R9.3 a replacement that is only the dashboard marker is empty
mkrec comment-422.json kiki830621 MEMBER "<!-- idd:dashboard -->
## For Reviewer
wrong"
printf '<!-- idd:dashboard -->\n' >"$WORK/fix-marker-only.md"
helper r93 correct-prepare --target comment:422 --repo o/r --scope whole-comment --body-file "$WORK/fix-marker-only.md" --scrub-attested warn
assert_eq "only the marker is refused as empty" "empty" "$(val REASON "$WORK/r93.out")"
# R9.4 an unclosed fence has its own reason
mkrec comment-423.json kiki830621 MEMBER "$SECTION_BODY"
printf 'right\n```\nnever closed\n' >"$WORK/fix-fence.md"
helper r94 correct-prepare --target comment:423 --repo o/r --section "## Notes" --body-file "$WORK/fix-fence.md" --scrub-attested warn
assert_eq "an unclosed fence is unclosed-block, not protected" "unclosed-block" "$(val REASON "$WORK/r94.out")"
# R9.5 a state without its file hashes is refused, even with a matching digest
mkrec comment-424.json kiki830621 MEMBER "$SECTION_BODY"
helper r95p correct-prepare --target comment:424 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
R95W="$(val WORK "$WORK/r95p.out")"
helper r95a correct-apply --work "$R95W" --state "$(restate "$R95W" 'del s["sha"]')"
assert_eq "a state without sha is refused with a reason" "differs-from-preview" "$(val REASON "$WORK/r95a.out")"
# R9.6 an abandoned run directory is removed too
STALE_RUN="$(mktemp -d "$TMPDIR/idd-run-XXXXXX")"; : >"$STALE_RUN/run.json"; touch -t 202001010000 "$STALE_RUN"
helper r96 correct-prepare --target comment:9999 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
refute "a stale run directory is removed" test -d "$STALE_RUN"
# R9.7 a target refused at the author gate writes nothing into the repository
NG9="$WORK/fresh-repo"; mkdir -p "$NG9"; git -C "$NG9" init -q
mkrec comment-425.json someone-else MEMBER "$SECTION_BODY"
(cd "$NG9" && python3 "$HELPER" correct-prepare --target comment:425 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn) >"$WORK/r97.out" 2>"$WORK/r97.err"
assert_eq "it is refused as R5" "R5" "$(val REASON "$WORK/r97.out")"
refute_output_grep "the exclude block is not written for it" "idd" "$NG9/.git/info/exclude"
assert_output_grep "the refusal points to another account" "gh auth switch" "$WORK/r97.err"
# R9.8 validate-target refuses a malformed repository
helper r98 validate-target 1 "../x" false --correct
assert_exit "a malformed repo is a usage error" 2 "$RC"

# R9.9 restore reads the marker itself: no GitHub value is pasted into a command
mkrec comment-430.json kiki830621 MEMBER "$SECTION_BODY"
helper r99p correct-prepare --target comment:430 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
helper r99a correct-apply --work "$(val WORK "$WORK/r99p.out")" --state "$(val STATE "$WORK/r99p.out")"
helper r99r restore --target comment:430 --repo o/r
assert_exit "restore --target finds the one archived correction" 0 "$RC"
assert_eq "and puts the old text back" "$SECTION_BODY" "$(body_of comment-430.json)"
mkrec comment-431.json kiki830621 MEMBER "## Notes
x
<!-- idd:edit mode=\"correct\" backup-id=\"x'\$(touch $WORK/PWNED)'\" date=\"2026-10-17\" -->"
helper r99f restore --target comment:431 --repo o/r
assert_exit "a marker whose id is not an id restores nothing" 2 "$RC"
refute "and runs nothing" test -e "$WORK/PWNED"

# no refusal or apply leaves a working directory behind
assert_eq "no working directory outlives prepare refusals or apply" "$BEFORE" "$(count_work)"
rm -rf "$TMPFIX"

print_summary "correct-flow"
