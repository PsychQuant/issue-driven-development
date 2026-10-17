#!/usr/bin/env bash
# test.sh — one /idd-edit run, all four modes, the way an agent runs it (#351).
#
# Verify rounds 6 and 7 found the same defect twice: the skill was written as
# one bash script spanning the user's confirmation, but the preview and the
# write are separate tool calls, so shell variables, arrays, `continue` and the
# run's exit code did not survive. The run's state now lives in the helper
# (run-start → prepare → apply | discard → finish). Part A tests the helper
# against a fake gh; part B runs the SKILL's own step blocks — every mode
# confirmed, plus a decline, a refusal, a half-done batch and a PICK — one
# fresh shell per block, with ${CLAUDE_PLUGIN_ROOT} substituted the way Claude
# Code does, an environment holding no IDD variable, and only the documented
# values pasted in, under zsh (the agent's Bash tool) and bash.
#
# Change: openspec/changes/idd-edit-in-place-correction (tasks section 14)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
HELPER="$PLUGIN/scripts/idd-edit-helper.py"
SKILL="$PLUGIN/skills/idd-edit/SKILL.md"
FAKE="$HERE/../correct-flow/fake-gh.py"

WORK="$(mktemp -d /tmp/idd-er-XXXXXX)"
export TMPDIR="$(mktemp -d /var/tmp/idd-er-tmp-XXXXXX)"
cleanup() { chmod -R u+rwx "$WORK" "$TMPDIR" 2>/dev/null; rm -rf "$WORK" "$TMPDIR"; }
trap cleanup EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export FAKE_GH_STORE="$WORK/store"; mkdir -p "$FAKE_GH_STORE"
mkdir -p "$WORK/bin"
printf '#!/bin/sh\nexec python3 "%s" "$@"\n' "$FAKE" >"$WORK/bin/gh"; chmod +x "$WORK/bin/gh"
export PATH="$WORK/bin:$PATH"
printf 'kiki830621' >"$FAKE_GH_STORE/user"
printf '{"viewerPermission": "ADMIN", "isPrivate": false}' >"$FAKE_GH_STORE/repo.json"
REPO="$WORK/repo"; mkdir -p "$REPO"; git -C "$REPO" init -q

# mkrec <file> <login> <assoc> <body>
mkrec() {
  python3 - "$FAKE_GH_STORE/$1" "$2" "$3" "$4" <<'PY'
import json, sys
path, login, assoc, body = sys.argv[1:]
json.dump({"body": body, "user": {"login": login}, "author_association": assoc,
           "html_url": "https://github.com/o/r/x"}, open(path, "w"))
PY
}
body_of() { python3 -c 'import json,sys;sys.stdout.write(json.load(open(sys.argv[1]))["body"])' "$FAKE_GH_STORE/$1"; }
val() { sed -n "s/^$1=//p" "$2" | head -1; }
vals() { sed -n "s/^$1=//p" "$2"; }
# h <label> <args...> — the helper, run in the clone
h() {
  local label="$1"; shift
  (cd "$REPO" && python3 "$HELPER" "$@") >"$WORK/$label.out" 2>"$WORK/$label.err"
  RC=$?
}
count_runs() { find "$TMPDIR" -maxdepth 1 -name 'idd-run-*' | wc -l | tr -d ' '; }
SECTION_BODY='## Notes
wrong text

## Next
- keep me'
printf 'right text\n' >"$WORK/fix.md"

# ═══ Part A — the helper ════════════════════════════════════════════════════
echo "A1. run-start"
h a1 run-start --default-repo o/r -- comment:100 --append --body-file "$WORK/fix.md" --reason "add a note"
assert_exit "run-start succeeds" 0 "$RC"
RUN="$(val RUN "$WORK/a1.out")"
require "it prints RUN=" test -d "$RUN"
assert_eq "it prints the repository" "o/r" "$(val REPO "$WORK/a1.out")"
assert_eq "it resolves the privacy tier (admin, public → warn)" "warn" "$(val SCRUB "$WORK/a1.out")"
assert_eq "it prints the target" "comment:100" "$(val TARGET "$WORK/a1.out")"
h a1b run-start --default-repo o/r -- comment:100 --replace --body-file "$WORK/fix.md"
assert_exit "R4 still refuses --replace without a scope (exit 3)" 3 "$RC"
h a1c run-start -- comment:100 --append --body-file "$WORK/fix.md"
assert_exit "no repository is a usage error" 2 "$RC"
printf '100\n101\n102\n' >"$FAKE_GH_STORE/issue-7-comment-ids"
h a1d run-start --default-repo o/r -- '#7' --last --append --body-file "$WORK/fix.md" --reason x
assert_eq "--last resolves to the newest comment" "comment:102" "$(val TARGET "$WORK/a1d.out")"
h a1e run-start --default-repo o/r -- '#7' --append --body-file "$WORK/fix.md" --reason x
assert_eq "#N without --last asks the agent to pick" "#7" "$(val PICK "$WORK/a1e.out")"
printf '{"viewerPermission": "READ", "isPrivate": false}' >"$FAKE_GH_STORE/repo.json"
h a1f run-start --default-repo o/r -- comment:100 --append --body-file "$WORK/fix.md" --reason x
assert_eq "a read-only repository is enforce" "enforce" "$(val SCRUB "$WORK/a1f.out")"
printf '{"viewerPermission": "WRITE", "isPrivate": true}' >"$FAKE_GH_STORE/repo.json"
h a1g run-start --default-repo o/r -- comment:100 --append --body-file "$WORK/fix.md" --reason x
assert_eq "a private repository you can write is light" "light" "$(val SCRUB "$WORK/a1g.out")"
printf '{"viewerPermission": "ADMIN", "isPrivate": false}' >"$FAKE_GH_STORE/repo.json"
for f in a1 a1d a1e a1f a1g; do h "x-$f" finish --run "$(val RUN "$WORK/$f.out")"; done

# start <label> <args...> — run-start, RUN and SCRUB into variables
start() { local l="$1"; shift; h "$l" run-start --default-repo o/r -- "$@"; RUN="$(val RUN "$WORK/$l.out")"; SCRUB="$(val SCRUB "$WORK/$l.out")"; }

echo "A2. --append, confirmed"
mkrec comment-200.json kiki830621 MEMBER "first line"
start a2 comment:200 --append --body-file "$WORK/fix.md" --reason "add a note"
h a2p prepare --run "$RUN" --target comment:200
assert_exit "prepare succeeds" 0 "$RC"
assert_output_grep "the preview carries the appended text" "right text" "$(val PREVIEW "$WORK/a2p.out")"
assert_output_grep "the diff shows the added lines" "+right text" "$(val DIFF "$WORK/a2p.out")"
A2B="$(val BACKUP "$WORK/a2p.out")"
assert_eq "the backup holds the old body exactly" "first line" "$(cat "$A2B")"
require "backups live in the user's temp dir, under idd-edit-backup" test "$(dirname "$A2B")" = "$(cd "$TMPDIR" && pwd -P)/idd-edit-backup"
h a2a apply --run "$RUN" --target comment:200 --scrub-attested "$SCRUB"
assert_exit "apply succeeds" 0 "$RC"
assert_eq "it reports edited" "edited" "$(val RESULT "$WORK/a2a.out")"
assert_output_grep "the comment holds the appended text" "right text" <(body_of comment-200.json)
assert_output_grep "and the edit marker" 'idd:edit mode="append"' <(body_of comment-200.json)
h a2f finish --run "$RUN"
assert_exit "finish exits 0" 0 "$RC"
assert_output_grep "the report counts one edit" "edited: 1 / refused: 0" "$WORK/a2f.out"
refute "finish removes the run directory" test -d "$RUN"

echo "A3. --replace --section and --scope whole-comment, --prepend-note"
mkrec comment-201.json kiki830621 MEMBER "$SECTION_BODY"
start a3 comment:201 --replace --section "## Notes" --body-file "$WORK/fix.md" --reason r
h a3p prepare --run "$RUN" --target comment:201
h a3a apply --run "$RUN" --target comment:201 --scrub-attested "$SCRUB"
assert_eq "section replace is edited" "edited" "$(val RESULT "$WORK/a3a.out")"
assert_output_grep "the section holds the new text" "right text" <(body_of comment-201.json)
assert_output_grep "the next section is kept" "- keep me" <(body_of comment-201.json)
refute_output_grep "the old text is gone" "wrong text" <(body_of comment-201.json)
h a3f finish --run "$RUN"
mkrec comment-202.json kiki830621 MEMBER "old whole"
start a3w comment:202 --replace --scope whole-comment --body-file "$WORK/fix.md" --reason r
h a3wp prepare --run "$RUN" --target comment:202
h a3wa apply --run "$RUN" --target comment:202 --scrub-attested "$SCRUB"
assert_output_grep "whole-comment replace writes the new text" "right text" <(body_of comment-202.json)
refute_output_grep "and drops the old one" "old whole" <(body_of comment-202.json)
h a3wf finish --run "$RUN"
mkrec comment-203.json kiki830621 MEMBER "stale analysis"
start a3n comment:203 --prepend-note --reason "superseded by a later run"
h a3np prepare --run "$RUN" --target comment:203
h a3na apply --run "$RUN" --target comment:203 --scrub-attested "$SCRUB"
assert_eq "the note is the first line" "> ⚠️ **Edit $(date +%Y-%m-%d)**: superseded by a later run" "$(body_of comment-203.json | head -1)"
h a3nf finish --run "$RUN"

echo "A4. R5 and override"
mkrec comment-204.json collaborator MEMBER "their words"
start a4 comment:204 --append --body-file "$WORK/fix.md" --reason r
h a4p prepare --run "$RUN" --target comment:204
assert_eq "someone else's comment is refused" "R5" "$(val REASON "$WORK/a4p.out")"
h a4f finish --run "$RUN"
assert_exit "a refusal makes the run exit 4" 4 "$RC"
assert_output_grep "the report names it" "✗ REFUSED(R5) comment:204" "$WORK/a4f.out"
assert_output_grep "and gives the override hint outside --correct" "override: --override-user-content" "$WORK/a4f.out"
start a4o comment:204 --append --body-file "$WORK/fix.md" --override-user-content --reason "agreed with them"
h a4op prepare --run "$RUN" --target comment:204
h a4oa apply --run "$RUN" --target comment:204 --scrub-attested "$SCRUB"
assert_output_grep "an override writes its own marker" "override-user-content" <(body_of comment-204.json)
h a4of finish --run "$RUN"
assert_exit "the overridden run exits 0" 0 "$RC"

echo "A5. declined, mixed batch, never applied"
mkrec comment-205.json kiki830621 MEMBER "a"
mkrec comment-206.json collaborator MEMBER "b"
start a5 comment:205 comment:206 --append --body-file "$WORK/fix.md" --reason r
assert_eq "both targets are listed" "comment:205 comment:206" "$(vals TARGET "$WORK/a5.out" | tr '\n' ' ' | sed 's/ $//')"
h a5p prepare --run "$RUN" --target comment:205
h a5p2 prepare --run "$RUN" --target comment:206
h a5d discard --run "$RUN" --target comment:205
h a5f finish --run "$RUN"
assert_exit "refused beats declined (exit 4)" 4 "$RC"
assert_output_grep "the decline is reported" "DECLINED comment:205" "$WORK/a5f.out"
assert_eq "the declined comment is unchanged" "a" "$(body_of comment-205.json)"
mkrec comment-207.json kiki830621 MEMBER "c"
start a5b comment:207 --append --body-file "$WORK/fix.md" --reason r
h a5bp prepare --run "$RUN" --target comment:207
h a5bd discard --run "$RUN" --target comment:207
h a5bf finish --run "$RUN"
assert_exit "a run whose only target was declined exits 9" 9 "$RC"
mkrec comment-208.json kiki830621 MEMBER "d"
start a5c comment:208 --append --body-file "$WORK/fix.md" --reason r
h a5cp prepare --run "$RUN" --target comment:208
h a5cf finish --run "$RUN"
assert_exit "a prepared target that was never applied exits 4" 4 "$RC"
assert_output_grep "and is reported as not applied" "REFUSED(not-applied) comment:208" "$WORK/a5cf.out"

echo "A6. failed and unverified writes, egress, the attested tier"
mkrec comment-209.json kiki830621 MEMBER "e"
start a6 comment:209 --append --body-file "$WORK/fix.md" --reason r
h a6p prepare --run "$RUN" --target comment:209
h a6x apply --run "$RUN" --target comment:209 --scrub-attested light
assert_exit "a tier looser than the run's is a usage error" 2 "$RC"
: >"$FAKE_GH_STORE/fail-patch"
h a6a apply --run "$RUN" --target comment:209 --scrub-attested "$SCRUB"
rm -f "$FAKE_GH_STORE/fail-patch"
assert_eq "gh failing the write, target unchanged → write-failed" "write-failed" "$(val RESULT "$WORK/a6a.out")"
h a6f finish --run "$RUN"
assert_exit "a failed write exits 4" 4 "$RC"
mkrec comment-210.json kiki830621 MEMBER "f"
start a6b comment:210 --append --body-file "$WORK/fix.md" --reason r
h a6bp prepare --run "$RUN" --target comment:210
: >"$FAKE_GH_STORE/fail-after-patch"
h a6ba apply --run "$RUN" --target comment:210 --scrub-attested "$SCRUB"
rm -f "$FAKE_GH_STORE/fail-after-patch"
assert_eq "a write that landed before gh erred → unverified" "unverified" "$(val RESULT "$WORK/a6ba.out")"
h a6bf finish --run "$RUN"
assert_exit "an unverified write exits 7" 7 "$RC"
mkrec comment-211.json kiki830621 MEMBER "g"
printf 'cc @newperson\n' >"$WORK/fix-mention.md"
start a6c comment:211 --append --body-file "$WORK/fix-mention.md" --reason r
h a6cp prepare --run "$RUN" --target comment:211
assert_eq "a mention the edit adds is refused before the preview" "egress" "$(val REASON "$WORK/a6cp.out")"
h a6cf finish --run "$RUN"

echo "A6b. apply checks again what prepare checked"
mkrec comment-216.json kiki830621 MEMBER "before"
start a6d comment:216 --append --body-file "$WORK/fix.md" --reason r
h a6dp prepare --run "$RUN" --target comment:216
mkrec comment-216.json kiki830621 MEMBER "someone edited it after the preview"
h a6da apply --run "$RUN" --target comment:216 --scrub-attested "$SCRUB"
assert_eq "a comment changed after the preview is not overwritten" "changed-since-preview" "$(val REASON "$WORK/a6da.out")"
assert_eq "the newer text survives" "someone edited it after the preview" "$(body_of comment-216.json)"
h a6df finish --run "$RUN"
mkrec comment-217.json kiki830621 MEMBER "mine"
start a6e comment:217 --replace --scope whole-comment --body-file "$WORK/fix.md" --reason r
h a6ep prepare --run "$RUN" --target comment:217
printf 'someone-else' >"$FAKE_GH_STORE/user"
h a6ea apply --run "$RUN" --target comment:217 --scrub-attested "$SCRUB"
printf 'kiki830621' >"$FAKE_GH_STORE/user"
assert_eq "apply runs the author gate again" "R5" "$(val REASON "$WORK/a6ea.out")"
assert_eq "the comment is unchanged" "mine" "$(body_of comment-217.json)"
h a6ef finish --run "$RUN"

echo "A7. --correct through the run"
mkrec comment-212.json kiki830621 MEMBER "$SECTION_BODY"
start a7 comment:212 --correct --section "## Notes" --body-file "$WORK/fix.md" --reason r
h a7p prepare --run "$RUN" --target comment:212
assert_exit "correct prepare succeeds" 0 "$RC"
require "it prints STATE=" test -n "$(val STATE "$WORK/a7p.out")"
assert_output_grep "its diff shows the removed line" "-wrong text" "$(val DIFF "$WORK/a7p.out")"
h a7a apply --run "$RUN" --target comment:212 --scrub-attested "$SCRUB" --state "$(val STATE "$WORK/a7p.out")"
assert_eq "correct apply is edited" "edited" "$(val RESULT "$WORK/a7a.out")"
h a7f finish --run "$RUN"
assert_exit "a corrected run exits 0" 0 "$RC"
mkrec comment-213.json kiki830621 MEMBER "$SECTION_BODY"
start a7d comment:213 --correct --section "## Notes" --body-file "$WORK/fix.md" --reason r
h a7dp prepare --run "$RUN" --target comment:213
A7W="$(val WORK "$WORK/a7dp.out")"
h a7dd discard --run "$RUN" --target comment:213
refute "a declined correction removes its working copy" test -d "$A7W"
h a7df finish --run "$RUN"
assert_exit "a declined correction exits 9" 9 "$RC"
mkrec comment-214.json repo-owner OWNER "$SECTION_BODY"
start a7r comment:214 --correct --section "## Notes" --body-file "$WORK/fix.md" --reason r
h a7rp prepare --run "$RUN" --target comment:214
h a7rf finish --run "$RUN"
assert_exit "a refused correction exits 4" 4 "$RC"
mkrec comment-215.json kiki830621 MEMBER "$SECTION_BODY"
start a7n comment:215 --correct --section "## Notes" --body-file "$WORK/fix.md" --reason r
h a7np prepare --run "$RUN" --target comment:215
A7NW="$(val WORK "$WORK/a7np.out")"
h a7nf finish --run "$RUN"
assert_exit "a correction never applied exits 4" 4 "$RC"
refute "finish removes its working copy (it holds the wrong text)" test -d "$A7NW"
assert_eq "no run directory is left" "0" "$(count_runs)"

echo "A8. round 10 (verify #351 round 8)"
# a 0755 backup directory left by 3.4.0 is tightened, not refused
BK="$(cd "$TMPDIR" && pwd -P)/idd-edit-backup"
chmod 755 "$BK"
mkrec comment-230.json kiki830621 MEMBER "x"
start a8a comment:230 --append --body-file "$WORK/fix.md" --reason r
h a8ap prepare --run "$RUN" --target comment:230
assert_exit "an upgraded 0755 backup directory still takes the backup" 0 "$RC"
assert_eq "and is now private" "700" "$(python3 -c 'import os,sys; print(format(os.stat(sys.argv[1]).st_mode & 0o777, "o"))' "$BK")"
# a stricter tier than the run's is accepted; the write goes out at that tier
h a8aa apply --run "$RUN" --target comment:230 --scrub-attested enforce
assert_eq "a stricter attested tier is accepted" "edited" "$(val RESULT "$WORK/a8aa.out")"
h a8af finish --run "$RUN"
# a mistyped STATE can be retried
mkrec comment-231.json kiki830621 MEMBER "$SECTION_BODY"
start a8b comment:231 --correct --section "## Notes" --body-file "$WORK/fix.md" --reason r
h a8bp prepare --run "$RUN" --target comment:231
h a8bx apply --run "$RUN" --target comment:231 --scrub-attested "$SCRUB" --state "0000000000000000000000000000000000000000000000000000000000000000"
assert_exit "a wrong STATE is a usage error" 2 "$RC"
h a8ba apply --run "$RUN" --target comment:231 --scrub-attested "$SCRUB" --state "$(val STATE "$WORK/a8bp.out")"
assert_eq "and the right one still applies" "edited" "$(val RESULT "$WORK/a8ba.out")"
h a8bf finish --run "$RUN"
# a mode is required; a target named twice is edited once; --last on no comments
h a8c run-start --default-repo o/r -- comment:230 --scope whole-comment --body-file "$WORK/fix.md"
assert_exit "no mode is a usage error, not a silent --replace" 2 "$RC"
start a8d comment:230 comment:230 --append --body-file "$WORK/fix.md" --reason r
assert_eq "a target named twice is listed once" "1" "$(vals TARGET "$WORK/a8d.out" | wc -l | tr -d ' ')"
h a8df finish --run "$RUN"
: >"$FAKE_GH_STORE/issue-11-comment-ids"
h a8e run-start --default-repo o/r -- '#11' --last --append --body-file "$WORK/fix.md" --reason r
assert_exit "--last on an issue with no comments is exit 2" 2 "$RC"
assert_output_grep "and says so" "has no comments" "$WORK/a8e.err"
# a --correct body that is only the target heading is refused at run-start
printf '## Notes\n' >"$WORK/only-heading.md"
h a8f run-start --default-repo o/r -- comment:231 --correct --section "## Notes" --body-file "$WORK/only-heading.md" --reason r
assert_exit "a heading-only --correct body is exit 2 at run-start" 2 "$RC"
# someone else's issue body: the refusal points to --type correction
python3 - "$FAKE_GH_STORE/issue-12.json" <<'PY'
import json, sys
json.dump({"body": "## Expected\nwrong", "user": {"login": "reporter"}, "author_association": "NONE",
           "html_url": "https://github.com/o/r/issues/12"}, open(sys.argv[1], "w"))
PY
start a8g issue:12 --correct --section "## Expected" --body-file "$WORK/fix.md" --reason r
h a8gp prepare --run "$RUN" --target issue:12
assert_output_grep "an issue body's refusal names --type correction" "--type correction" "$WORK/a8gp.err"
h a8gf finish --run "$RUN"

echo "A9. round 11 (verify #351 round 9)"
# mkrec_in <file> <login> <issue number> <body> — a comment that belongs to an issue
mkrec_in() {
  python3 - "$FAKE_GH_STORE/$1" "$2" "$3" "$4" <<'PY'
import json, sys
path, login, issue, body = sys.argv[1:]
json.dump({"body": body, "user": {"login": login}, "author_association": "MEMBER",
           "html_url": "https://github.com/o/r/x", "issue_url": f"https://api.github.com/repos/o/r/issues/{issue}"},
          open(path, "w"))
PY
}
# a --correct written at the stricter tier the review attested
mkrec comment-240.json kiki830621 MEMBER "$SECTION_BODY"
start a9a comment:240 --correct --section "## Notes" --body-file "$WORK/fix.md" --reason r
h a9ap prepare --run "$RUN" --target comment:240
h a9aa apply --run "$RUN" --target comment:240 --scrub-attested enforce --state "$(val STATE "$WORK/a9ap.out")"
assert_eq "--correct writes at the stricter attested tier" "enforce" "$(val SCRUB "$WORK/a9aa.out")"
h a9af finish --run "$RUN"
# a target the run did not list is not prepared
mkrec comment-241.json kiki830621 MEMBER "listed"
mkrec comment-242.json kiki830621 MEMBER "not listed"
start a9b comment:241 --append --body-file "$WORK/fix.md" --reason r
h a9bp prepare --run "$RUN" --target comment:242
assert_exit "a target outside the run is a usage error" 2 "$RC"
h a9bf finish --run "$RUN"
# PICKs are settled one by one: the comment must belong to that issue
mkrec_in comment-243.json kiki830621 20 "from twenty"
mkrec_in comment-244.json kiki830621 21 "from twenty-one"
start a9c '#20' '#21' '#20' --append --body-file "$WORK/fix.md" --reason r
assert_eq "a PICK named twice is listed once" "2" "$(vals PICK "$WORK/a9c.out" | wc -l | tr -d ' ')"
h a9cw prepare --run "$RUN" --target comment:244 --pick 20
assert_eq "a comment from another issue does not resolve the PICK" "not-in-pick" "$(val REASON "$WORK/a9cw.out")"
h a9cp prepare --run "$RUN" --target comment:244 --pick 21
h a9ca apply --run "$RUN" --target comment:244 --scrub-attested "$SCRUB"
h a9cf finish --run "$RUN"
assert_exit "one PICK left unresolved exits 4" 4 "$RC"
assert_output_grep "the report names #20, the one that was refused" "REFUSED(not-in-pick) #20" "$WORK/a9cf.out"
refute_output_grep "and not #21, which was edited" "not-picked) #21" "$WORK/a9cf.out"
# a PICK that resolves to a target already in the run is settled, not refused
mkrec_in comment-245.json kiki830621 22 "both"
start a9d comment:245 '#22' --append --body-file "$WORK/fix.md" --reason r
h a9dp prepare --run "$RUN" --target comment:245
h a9da apply --run "$RUN" --target comment:245 --scrub-attested "$SCRUB"
h a9dk prepare --run "$RUN" --target comment:245 --pick 22
assert_exit "a PICK naming a target already in the run is accepted" 0 "$RC"
h a9df finish --run "$RUN"
assert_exit "and the run exits 0" 0 "$RC"
# a --correct run moves between temp dirs (sandboxed and unsandboxed calls)
mkrec comment-246.json kiki830621 MEMBER "$SECTION_BODY"
OTHER_TMP="$(mktemp -d /var/tmp/idd-er-other-XXXXXX)"
start a9e comment:246 --correct --section "## Notes" --body-file "$WORK/fix.md" --reason r
(cd "$REPO" && TMPDIR="$OTHER_TMP" python3 "$HELPER" prepare --run "$RUN" --target comment:246) >"$WORK/a9ep.out" 2>"$WORK/a9ep.err"
assert_exit "prepare under another TMPDIR accepts the run's own body" 0 "$?"
(cd "$REPO" && TMPDIR="$OTHER_TMP" python3 "$HELPER" apply --run "$RUN" --target comment:246 --scrub-attested "$SCRUB" --state "$(val STATE "$WORK/a9ep.out")") >"$WORK/a9ea.out" 2>"$WORK/a9ea.err"
assert_eq "and apply there writes it" "edited" "$(val RESULT "$WORK/a9ea.out")"
h a9ef finish --run "$RUN"
rm -rf "$OTHER_TMP"
# a run directory whose run.json run-start could not have written is refused
EVIL="$WORK/elsewhere/idd-run-evil"; mkdir -p "$EVIL"; chmod 700 "$EVIL"
printf '{"mode": "--append", "override": "true", "reason": "", "scrub": "light", "repo": "o/r", "targets": ["comment:241"], "picks": []}' >"$EVIL/run.json"
ln -s /etc/hosts "$EVIL/body.md"
h a9f prepare --run "$EVIL" --target comment:241
assert_exit "a run.json with an override and no reason is not a run" 2 "$RC"
printf '{"mode": "--append", "override": "false", "reason": "r", "scrub": "warn", "repo": "o/r", "targets": ["comment:241"], "picks": []}' >"$EVIL/run.json"
h a9f2 prepare --run "$EVIL" --target comment:241
assert_exit "a symlinked body.md is not a run's body" 2 "$RC"
# the diff marks a last line without a newline
mkrec comment-247.json kiki830621 MEMBER "no newline at the end"
start a9g comment:247 --append --body-file "$WORK/fix.md" --reason r
h a9gp prepare --run "$RUN" --target comment:247
assert_output_grep "the diff says the old text had no final newline" '\ No newline at end of file' "$(val DIFF "$WORK/a9gp.out")"
refute_output_grep "and does not glue two lines together" "-no newline at the end+" "$(val DIFF "$WORK/a9gp.out")"
h a9gf finish --run "$RUN"
# $HOME//x is still under the home directory
mkdir -p "$WORK/home2"; printf 'from home\n' >"$WORK/home2/h.md"
mkrec comment-248.json kiki830621 MEMBER "h"
(cd "$REPO" && HOME="$WORK/home2" python3 "$HELPER" run-start --default-repo o/r -- comment:248 --append --body-file '$HOME//h.md' --reason r) >"$WORK/a9h.out" 2>"$WORK/a9h.err"
assert_exit "\$HOME//file is read from the home directory" 0 "$?"
h a9hf finish --run "$(val RUN "$WORK/a9h.out")"
# gh's own token store is a credential path
mkdir -p "$WORK/home3/.config/gh"; printf 'oauth_token: x\n' >"$WORK/home3/.config/gh/hosts.yml"
(HOME="$WORK/home3" python3 "$HELPER" run-start --default-repo o/r -- comment:248 --append --body-file "$WORK/home3/.config/gh/hosts.yml" --reason r) >"$WORK/a9t.out" 2>"$WORK/a9t.err"
assert_exit "gh's hosts.yml is refused as a body file" 5 "$?"
# a bot-opened issue body: the refusal names --type correction
python3 - "$FAKE_GH_STORE/issue-25.json" <<'PY'
import json, sys
json.dump({"body": "## Expected\nwrong", "user": {"login": "renovate[bot]"}, "author_association": "NONE",
           "html_url": "https://github.com/o/r/issues/25"}, open(sys.argv[1], "w"))
PY
start a9i issue:25 --correct --section "## Expected" --body-file "$WORK/fix.md" --reason r
h a9ip prepare --run "$RUN" --target issue:25
assert_output_grep "a bot's issue body points to --type correction" "--type correction" "$WORK/a9ip.err"
h a9if finish --run "$RUN"

echo "A10. round 12 (verify #351 round 10)"
# a run idle for days is not swept by its own prepare (the sweep keeps the live run)
mkrec comment-250.json kiki830621 MEMBER "$SECTION_BODY"
mkrec comment-251.json kiki830621 MEMBER "$SECTION_BODY"
start a10a comment:250 comment:251 --correct --section "## Notes" --body-file "$WORK/fix.md"
h a10ap prepare --run "$RUN" --target comment:250
h a10ad discard --run "$RUN" --target comment:250
touch -t 202610010000 "$RUN"
h a10aq prepare --run "$RUN" --target comment:251
assert_exit "a run idle for days is prepared again, not swept" 0 "$RC"
require "the run directory is still there" test -d "$RUN"
h a10ar discard --run "$RUN" --target comment:251
h a10af finish --run "$RUN"
assert_exit "and finish still reads it (both declined → 9)" 9 "$RC"
# --scope is checked at start in every mode
h a10b run-start --default-repo o/r -- comment:100 --append --scope bogus --body-file "$WORK/fix.md" --reason r
assert_exit "--append with a --scope other than whole-comment is refused at start (exit 3)" 3 "$RC"
h a10b2 run-start --default-repo o/r -- comment:100 --prepend-note --scope section --reason r
assert_exit "--prepend-note too" 3 "$RC"
# a reply comment quoting user-pasted points, in a private repo (light): the
# #272 floor raises the check and the write to warn instead of refusing them
printf '{"viewerPermission": "WRITE", "isPrivate": true}' >"$FAKE_GH_STORE/repo.json"
REPLY_BODY='## Reply
**Point 1**: a quoted point
done in abc123
<!-- idd:comment type=reply date=2026-10-01 points-from=user-pasted calibrated=no -->'
mkrec comment-252.json kiki830621 MEMBER "$REPLY_BODY"
start a10c comment:252 --append --body-file "$WORK/fix.md" --reason r
assert_eq "the run's tier is light" "light" "$SCRUB"
h a10cp prepare --run "$RUN" --target comment:252
assert_exit "--append on a user-pasted reply is prepared at the floor" 0 "$RC"
h a10ca apply --run "$RUN" --target comment:252 --scrub-attested "$SCRUB"
assert_eq "and written at warn" "edited warn" "$(val RESULT "$WORK/a10ca.out") $(val SCRUB "$WORK/a10ca.out")"
h a10cf finish --run "$RUN"
mkrec comment-253.json kiki830621 MEMBER "$REPLY_BODY"
printf '## Reply\n**Point 1**: a quoted point\nnot done yet\n' >"$WORK/reply-fix.md"
start a10c2 comment:253 --correct --scope whole-comment --body-file "$WORK/reply-fix.md"
h a10c2p prepare --run "$RUN" --target comment:253
assert_exit "--correct on a user-pasted reply is prepared at the floor" 0 "$RC"
h a10c2a apply --run "$RUN" --target comment:253 --scrub-attested "$SCRUB" --state "$(val STATE "$WORK/a10c2p.out")"
assert_eq "and written" "edited" "$(val RESULT "$WORK/a10c2a.out")"
h a10c2f finish --run "$RUN"
printf '{"viewerPermission": "ADMIN", "isPrivate": false}' >"$FAKE_GH_STORE/repo.json"
# a PICK whose comment cannot be read stays open: fetch-failed, retry allowed
mkrec_in comment-254.json kiki830621 23 "x"
start a10d '#23' --append --body-file "$WORK/fix.md" --reason r
h a10dw prepare --run "$RUN" --target comment:299 --pick 23
assert_eq "an unreadable comment is fetch-failed, not not-in-pick" "fetch-failed" "$(val REASON "$WORK/a10dw.out")"
h a10dp prepare --run "$RUN" --target comment:254 --pick 23
assert_exit "the PICK is still open for a retry" 0 "$RC"
h a10da apply --run "$RUN" --target comment:254 --scrub-attested "$SCRUB"
h a10df finish --run "$RUN"
assert_exit "and the run exits 0" 0 "$RC"
# issue numbers are numbers: #007 is #7
start a10e '#007' '#7' --append --body-file "$WORK/fix.md" --reason r
assert_eq "#007 and #7 are one PICK, #7" "#7" "$(vals PICK "$WORK/a10e.out" | tr '\n' ' ' | sed 's/ $//')"
h a10ef finish --run "$RUN"
# the diff marks only the true last line, not a line broken at \x0c
python3 - "$FAKE_GH_STORE/comment-255.json" <<'PY'
import json, sys
json.dump({"body": "line one\x0cstill one\nlast", "user": {"login": "kiki830621"}, "author_association": "MEMBER",
           "html_url": "https://github.com/o/r/x"}, open(sys.argv[1], "w"))
PY
start a10f comment:255 --append --body-file "$WORK/fix.md" --reason r
h a10fp prepare --run "$RUN" --target comment:255
assert_eq "one no-newline mark, for the last line" "1" "$(grep -c '^\\ No newline at end of file$' "$(val DIFF "$WORK/a10fp.out")")"
h a10ff finish --run "$RUN"
# the --correct marker's date is the local date, like the other modes'
mkrec comment-256.json kiki830621 MEMBER "$SECTION_BODY"
export TZ=Etc/GMT-14
start a10g comment:256 --correct --section "## Notes" --body-file "$WORK/fix.md"
h a10gp prepare --run "$RUN" --target comment:256
h a10ga apply --run "$RUN" --target comment:256 --scrub-attested "$SCRUB" --state "$(val STATE "$WORK/a10gp.out")"
assert_output_grep "the marker's date is the local date" "date=\"$(date +%Y-%m-%d)\"" <(body_of comment-256.json)
h a10gf finish --run "$RUN"
unset TZ
# credential paths: case variants (APFS is case-insensitive) and gh's other
# config locations (GH_CONFIG_DIR, then XDG_CONFIG_HOME/gh) are refused too
H4="$WORK/home4"; mkdir -p "$H4/.ssh" "$H4/.config/gh" "$H4/xdg/gh" "$H4/ghc"
for f in .ssh/id .config/gh/hosts.yml xdg/gh/hosts.yml ghc/hosts.yml; do printf 'secret\n' >"$H4/$f"; done
for f in .SSH/id .CONFIG/gh/hosts.yml .config/GH/hosts.yml xdg/gh/hosts.yml ghc/hosts.yml; do
  (HOME="$H4" XDG_CONFIG_HOME="$H4/xdg" GH_CONFIG_DIR="$H4/ghc" python3 "$HELPER" run-start --default-repo o/r -- comment:100 --append --body-file "$H4/$f" --reason r) >"$WORK/a10h.out" 2>"$WORK/a10h.err"
  assert_output_grep "$f is refused as a credential path" "refuses credential path" "$WORK/a10h.err"
done

# ═══ Part B — the SKILL's own blocks, one fresh shell each ═════════════════
# What an agent gets: Claude Code substitutes ${CLAUDE_PLUGIN_ROOT} when it
# loads a plugin skill (only the braced form — verify #351 round 8), and the
# Bash tool has no IDD variables at all. So the blocks are taken from the
# SKILL, ${CLAUDE_PLUGIN_ROOT} replaced by the plugin path, the placeholders
# replaced by the values earlier blocks printed, and each run in an empty
# environment under zsh (the Bash tool's shell) and bash.
python3 - "$SKILL" "$WORK/blk" "$PLUGIN" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
blocks = {}
for body in re.findall(r"```bash\n(.*?)```", text, re.S):
    m = re.match(r"# step: ([a-z-]+)", body)
    if m:
        blocks.setdefault(m.group(1), []).append(body)
for name in ("start", "prepare", "apply", "discard", "finish"):
    assert len(blocks.get(name, [])) == 1, (name, len(blocks.get(name, [])))
    open(f"{sys.argv[2]}-{name}.raw", "w", encoding="utf-8").write(blocks[name][0])
    open(f"{sys.argv[2]}-{name}.sh", "w", encoding="utf-8").write(blocks[name][0].replace("${CLAUDE_PLUGIN_ROOT}", sys.argv[3]))
PY
assert_exit "the SKILL has exactly one block per step (start, prepare, apply, discard, finish)" 0 "$?"
for s in start prepare apply discard finish; do
  refute_output_grep "step $s needs no loop" "continue" "$WORK/blk-$s.sh"
  refute_grep_re "step $s names the plugin root the way Claude Code substitutes it (braced)" '\$CLAUDE_PLUGIN_ROOT' "$(cat "$WORK/blk-$s.raw")"
  refute_grep_re "step $s reads no shell variable" '\$\{?[A-Za-z_]' "$(cat "$WORK/blk-$s.sh")"
done
# Every bash block of the SKILL, not only the five steps part B runs, reads no
# shell variable: a later edit cannot bring back a value an earlier block set
# (the round 6-7 class), and GitHub text never reaches a command through one.
python3 - "$SKILL" >"$WORK/all-blocks.txt" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
for body in re.findall(r"```bash\n(.*?)```", text, re.S):
    sys.stdout.write(body.replace("${CLAUDE_PLUGIN_ROOT}", "/plugin") + "\n")
PY
refute_grep_re "no bash block in the SKILL reads a shell variable" '\$\{?[A-Za-z_]' "$(cat "$WORK/all-blocks.txt")"
# Placeholders are single-quoted: a value pasted inside double quotes would
# run its $(...) before the helper checks it (verify #351 round 10).
refute_grep_re "no placeholder in a bash block is double-quoted" '"<[A-Z_]+>"' "$(cat "$WORK/all-blocks.txt")"
assert_output_grep "the PICK listing prints each body as JSON, so a newline cannot forge a row" '@json' "$SKILL"
mkdir -p "$WORK/home"
PYUSERBASE="$(python3 -m site --user-base)"
# step <shell> <label> <name> <key=value>... — the block with its placeholders
# filled, run alone in an empty environment
step() {
  local sh="$1" label="$2" name="$3"; shift 3
  python3 - "$WORK/blk-$name.sh" "$@" >"$WORK/$label.sh" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
for kv in sys.argv[2:]:
    key, _, value = kv.partition("=")
    text = text.replace(f"<{key}>", value)
left = re.findall(r"<[A-Z][A-Za-z /-]*>", text)
assert not left, left
sys.stdout.write(text)
PY
  # zsh -f: no ~/.zshenv, which may put the real gh ahead of the fake on PATH
  local flags=""; [ "$sh" = zsh ] && flags="-f"
  # HOME is a test home (for the ~ and $HOME body-file cases); Python keeps
  # finding the user's site-packages (markdown-it-py) through PYTHONUSERBASE
  (cd "$REPO" && env -i PATH="$PATH" HOME="$WORK/home" TMPDIR="$TMPDIR" PYTHONUSERBASE="$PYUSERBASE" \
     FAKE_GH_STORE="$FAKE_GH_STORE" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
     "$sh" $flags -c "$(cat "$WORK/$label.sh")") >"$WORK/$label.out" 2>"$WORK/$label.err"
  RC=$?
}
# confirmed <shell> <label> <targets> <args> — start, prepare and apply every
# target, finish; START_RC, APPLY_RCS (one digit per target), RC = finish's
confirmed() {
  local sh="$1" l="$2" targets="$3" args="$4" tg r s
  step "$sh" "$l-s" start "REPO=o/r" "ARGS=$args"
  START_RC=$RC
  r="$(val RUN "$WORK/$l-s.out")"; s="$(val SCRUB "$WORK/$l-s.out")"
  APPLY_RCS=""
  for tg in $targets; do
    step "$sh" "$l-p-${tg#*:}" prepare "RUN=$r" "TARGET=$tg" "PICK="
    step "$sh" "$l-a-${tg#*:}" apply "RUN=$r" "TARGET=$tg" "SCRUB=$s" "STATE=$(val STATE "$WORK/$l-p-${tg#*:}.out")"
    APPLY_RCS="$APPLY_RCS$RC"
  done
  step "$sh" "$l-f" finish "RUN=$r"
}
SHELLS="bash"; command -v zsh >/dev/null 2>&1 && SHELLS="zsh bash"
[ -n "${CI:-}" ] && ! command -v zsh >/dev/null 2>&1 && fail "zsh is installed on CI" "the agent's Bash tool runs zsh"
n=300
for SH in $SHELLS; do
  echo "B. $SH: every mode, confirmed, through the SKILL's own blocks"
  n=$((n + 1)); mkrec "comment-$n.json" kiki830621 MEMBER "$SECTION_BODY"
  printf '## Notes\nright text\n' >"$WORK/b-fix.md"
  confirmed "$SH" "b$n" "comment:$n" "comment:$n --correct --section '## Notes' --body-file '$WORK/b-fix.md' --reason fixed"
  assert_eq "$SH: --correct — start, apply and finish exit 0" "0 0 0" "$START_RC $APPLY_RCS $RC"
  assert_eq "$SH: --correct writes the new text" "right text" "$(body_of "comment-$n.json" | sed -n 2p)"
  n=$((n + 1)); mkrec "comment-$n.json" kiki830621 MEMBER "first"
  confirmed "$SH" "b$n" "comment:$n" "comment:$n --append --body-file '$WORK/fix.md' --reason 'it'\\''s a note'"
  assert_eq "$SH: --append (a reason with a quote) — start, apply and finish exit 0" "0 0 0" "$START_RC $APPLY_RCS $RC"
  assert_output_grep "$SH: --append writes the reason intact" "**: it's a note" <(body_of "comment-$n.json")
  n=$((n + 1)); mkrec "comment-$n.json" kiki830621 MEMBER "$SECTION_BODY"
  confirmed "$SH" "b$n" "comment:$n" "comment:$n --replace --section '## Notes' --body-file '$WORK/fix.md' --reason r"
  assert_eq "$SH: --replace --section — exits 0 0 0" "0 0 0" "$START_RC $APPLY_RCS $RC"
  refute_output_grep "$SH: --replace --section removes the old text" "wrong text" <(body_of "comment-$n.json")
  n=$((n + 1)); mkrec "comment-$n.json" kiki830621 MEMBER "old whole"
  printf 'whole new\n' >"$WORK/home/new-whole.md"
  confirmed "$SH" "b$n" "comment:$n" "comment:$n --replace --scope whole-comment --body-file '\$HOME/new-whole.md' --reason r"
  assert_eq "$SH: --replace whole, body file as \$HOME/… in single quotes — exits 0 0 0" "0 0 0" "$START_RC $APPLY_RCS $RC"
  assert_output_grep "$SH: the \$HOME path was read" "whole new" <(body_of "comment-$n.json")
  refute_output_grep "$SH: the marker names no local path" "$TMPDIR" <(body_of "comment-$n.json")
  n=$((n + 1)); mkrec "comment-$n.json" kiki830621 MEMBER "stale"
  confirmed "$SH" "b$n" "comment:$n" "comment:$n --prepend-note --reason superseded"
  assert_eq "$SH: --prepend-note — exits 0 0 0" "0 0 0" "$START_RC $APPLY_RCS $RC"
  n=$((n + 1)); a=$n; mkrec "comment-$n.json" kiki830621 MEMBER "one"
  n=$((n + 1)); b=$n; mkrec "comment-$n.json" kiki830621 MEMBER "two"
  printf 'more\n' >"$WORK/home/more.md"
  confirmed "$SH" "b$n" "comment:$a comment:$b" "comment:$a comment:$b --append --body-file '~/more.md' --reason r"
  assert_eq "$SH: a batch of two, body file as ~/… — exits 0 00 0" "0 00 0" "$START_RC $APPLY_RCS $RC"
  assert_output_grep "$SH: the batch report counts two edits" "edited: 2 / refused: 0" "$WORK/b$n-f.out"

  echo "B. $SH: declined, refused, half a batch, PICK"
  n=$((n + 1)); mkrec "comment-$n.json" kiki830621 MEMBER "$SECTION_BODY"
  step "$SH" "b$n-s" start "REPO=o/r" "ARGS=comment:$n --replace --section '## Notes' --body-file '$WORK/fix.md' --reason r"
  R="$(val RUN "$WORK/b$n-s.out")"
  step "$SH" "b$n-p" prepare "RUN=$R" "TARGET=comment:$n" "PICK="
  step "$SH" "b$n-d" discard "RUN=$R" "TARGET=comment:$n"
  step "$SH" "b$n-f" finish "RUN=$R"
  assert_exit "$SH: a declined run exits 9 — what idd-comment routes on" 9 "$RC"
  assert_eq "$SH: the declined comment is unchanged" "$SECTION_BODY" "$(body_of "comment-$n.json")"
  n=$((n + 1)); mkrec "comment-$n.json" collaborator MEMBER "theirs"
  step "$SH" "b$n-s" start "REPO=o/r" "ARGS=comment:$n --append --body-file '$WORK/fix.md' --reason r"
  R="$(val RUN "$WORK/b$n-s.out")"
  step "$SH" "b$n-p" prepare "RUN=$R" "TARGET=comment:$n" "PICK="
  step "$SH" "b$n-f" finish "RUN=$R"
  assert_exit "$SH: a refused run exits 4, not 0" 4 "$RC"
  n=$((n + 1)); a=$n; mkrec "comment-$n.json" kiki830621 MEMBER "one"
  n=$((n + 1)); b=$n; mkrec "comment-$n.json" kiki830621 MEMBER "two"
  step "$SH" "b$n-s" start "REPO=o/r" "ARGS=comment:$a comment:$b --append --body-file '$WORK/fix.md' --reason r"
  R="$(val RUN "$WORK/b$n-s.out")"; S="$(val SCRUB "$WORK/b$n-s.out")"
  step "$SH" "b$n-p" prepare "RUN=$R" "TARGET=comment:$a" "PICK="
  step "$SH" "b$n-a" apply "RUN=$R" "TARGET=comment:$a" "SCRUB=$S" "STATE="
  step "$SH" "b$n-f" finish "RUN=$R"
  assert_exit "$SH: a batch whose second target was never prepared exits 4" 4 "$RC"
  assert_output_grep "$SH: and names it" "REFUSED(not-prepared) comment:$b" "$WORK/b$n-f.out"
  n=$((n + 1)); mkrec_in "comment-$n.json" kiki830621 9 "picked"
  printf '%s\n' 5 "$n" >"$FAKE_GH_STORE/issue-9-comment-ids"
  step "$SH" "b$n-s" start "REPO=o/r" "ARGS='#9' --append --body-file '$WORK/fix.md' --reason r"
  assert_eq "$SH: #N without --last asks to pick" "#9" "$(val PICK "$WORK/b$n-s.out")"
  R="$(val RUN "$WORK/b$n-s.out")"; S="$(val SCRUB "$WORK/b$n-s.out")"
  step "$SH" "b$n-p" prepare "RUN=$R" "TARGET=comment:$n" "PICK=9"
  step "$SH" "b$n-a" apply "RUN=$R" "TARGET=comment:$n" "SCRUB=$S" "STATE="
  step "$SH" "b$n-f" finish "RUN=$R"
  assert_exit "$SH: the picked comment is edited and the run exits 0" 0 "$RC"
  n=$((n + 1))
  step "$SH" "b$n-s" start "REPO=o/r" "ARGS='#9' --append --body-file '$WORK/fix.md' --reason r"
  step "$SH" "b$n-f" finish "RUN=$(val RUN "$WORK/b$n-s.out")"
  assert_exit "$SH: a PICK nobody resolved exits 4" 4 "$RC"
  n=$((n + 1)); mkrec "comment-$n.json" kiki830621 MEMBER "x"
  step "$SH" "b$n-s" start "REPO=o/r" "ARGS=comment:$n --append --body-file '$WORK/fix.md' --reason r"
  R="$(val RUN "$WORK/b$n-s.out")"
  step "$SH" "b$n-x" prepare "RUN=$R" "TARGET=comment:$n\$(touch $WORK/PWNED-$SH)" "PICK="
  refute "$SH: a forged TARGET pasted into the prepare block runs nothing" test -e "$WORK/PWNED-$SH"
  step "$SH" "b$n-d" finish "RUN=$R"
done
assert_eq "no run directory is left after part B" "0" "$(count_runs)"

print_summary "edit-run"
