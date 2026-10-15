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
cleanup() { chmod -R u+rwx "$WORK" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export TMPDIR=/var/tmp            # macOS keeps the user's temp dir under /var
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
SECTION_BODY='## Notes
wrong text

## Next
- keep me'

# ── E1. comment section, confirmed ─────────────────────────────────────────
echo "E1. confirmed correction of a comment section"
mkrec comment-100.json kiki830621 MEMBER "$SECTION_BODY"
helper e1p correct-prepare --target comment:100 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
assert_exit "prepare succeeds with TMPDIR under /var" 0 "$RC"
E1W="$(val WORK "$WORK/e1p.out")"; E1P="$(val PREVIEW "$WORK/e1p.out")"
assert_file_exists "the preview is written" "$E1P"
assert_output_grep "the preview carries the new text" "right text" "$E1P"
assert_output_grep "the preview marks the backup id as pending" "(assigned after confirmation)" "$E1P"
helper e1a correct-apply --work "$E1W"
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
helper e3a correct-apply --work "$E3W"
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
helper e4b correct-prepare --target comment:103 --repo o/r --section "## Notes" --body-file "$WORK/fix-mention-new.md" --scrub-attested warn
assert_exit "a new mention is refused at prepare" 4 "$RC"
assert_eq "reason is egress" "egress" "$(val REASON "$WORK/e4b.out")"
refute "no working directory is left" test -n "$(val WORK "$WORK/e4b.out")"

# ── E5. gh fails the write ─────────────────────────────────────────────────
echo "E5. failed write"
mkrec comment-104.json kiki830621 MEMBER "$SECTION_BODY"
helper e5p correct-prepare --target comment:104 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
: >"$FAKE_GH_STORE/fail-patch"
helper e5a correct-apply --work "$(val WORK "$WORK/e5p.out")"
rm -f "$FAKE_GH_STORE/fail-patch"
assert_exit "a failed write is not success" 4 "$RC"
assert_eq "result is write-failed" "write-failed" "$(val RESULT "$WORK/e5a.out")"
assert_eq "the comment is unchanged" "$SECTION_BODY" "$(body_of comment-104.json)"

# ── E6. read-back differs ──────────────────────────────────────────────────
echo "E6. unverified write"
mkrec comment-105.json kiki830621 MEMBER "$SECTION_BODY"
helper e6p correct-prepare --target comment:105 --repo o/r --section "## Notes" --body-file "$WORK/fix.md" --scrub-attested warn
: >"$FAKE_GH_STORE/mangle-read"
helper e6a correct-apply --work "$(val WORK "$WORK/e6p.out")"
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
helper e8a correct-apply --work "$(val WORK "$WORK/e8p.out")"
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
helper e10a correct-apply --work "$(val WORK "$WORK/e10p.out")"
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

print_summary "correct-flow"
