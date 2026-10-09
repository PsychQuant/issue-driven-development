#!/usr/bin/env bash
# test.sh — correction archive: write-once storage, never tracked, unreadable at
# rest, restore without display, and the PreToolUse read guard (#351).
#
# Change: openspec/changes/idd-edit-in-place-correction
#   specs/correction-archive/spec.md
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"

PLUGIN="$(cd "$HERE/../../.." && pwd)"
HELPER="$PLUGIN/scripts/idd-edit-helper.py"
HOOK="$PLUGIN/hooks/archive-read-guard.py"
HOOKS_JSON="$PLUGIN/hooks/hooks.json"
EDIT_SKILL="$PLUGIN/skills/idd-edit/SKILL.md"

WORK="$(mktemp -d /tmp/idd-ca-XXXXXX)"
cleanup() { chmod -R u+rwx "$WORK" 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

export IDD_EDIT_HELPER_TEST_MODE=1
export IDD_EDIT_HELPER_NOW=2026-10-09T10:00:00Z
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

mode_of() { python3 -c 'import os,stat,sys;print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$1"; }

# run_in <dir> <label> <helper args...> — runs the helper with <dir> as cwd.
run_in() {
  local dir="$1" label="$2"; shift 2
  (cd "$dir" && python3 "$HELPER" "$@") >"$WORK/$label.out" 2>"$WORK/$label.err"
  RC=$?
}

SECRET="WRONG-CONTENT-ALPHA"
printf '%s first line\nsecond line\n' "$SECRET" >"$WORK/old.md"

REPO="$WORK/repo"; mkdir -p "$REPO"; git -C "$REPO" init -q
ARCH="$REPO/.claude/.idd/archive/edits"
ID1="comment-5805214375-20261009T100000Z"

# ── A. write once under a fixed local path ─────────────────────────────────
echo "A. archive write"

run_in "$REPO" a1 archive comment 5805214375 --from-file "$WORK/old.md" --repo o/r
assert_exit "archive succeeds in a git work tree" 0 "$RC"
assert_eq "stdout is exactly the backup id" "$ID1" "$(cat "$WORK/a1.out")"
assert_file_exists "archive file is at the fixed path" "$ARCH/$ID1.md"
refute_output_grep "stdout never carries archived content" "$SECRET" "$WORK/a1.out"
refute_output_grep "stderr never carries archived content" "$SECRET" "$WORK/a1.err"

chmod u+r "$ARCH/$ID1.md"
require "archive is byte-identical to the previewed original" cmp -s "$WORK/old.md" "$ARCH/$ID1.md"
chmod 000 "$ARCH/$ID1.md"

run_in "$REPO" a2 archive comment 5805214375 --from-file "$WORK/old.md" --repo o/r
assert_exit "same-second second archive succeeds" 0 "$RC"
assert_eq "collision gets a -2 suffix" "$ID1-2" "$(cat "$WORK/a2.out")"
chmod u+r "$ARCH/$ID1.md"
require "existing archive file is untouched by the collision" cmp -s "$WORK/old.md" "$ARCH/$ID1.md"
chmod 000 "$ARCH/$ID1.md"

run_in "$REPO" a3 archive issue 351 --from-file "$WORK/old.md" --repo o/r
assert_eq "issue body backup id" "issue-351-body-20261009T100000Z" "$(cat "$WORK/a3.out")"

run_in "$REPO" a4 archive comment 5805214375 --from-file "$WORK/nope.md" --repo o/r
assert_exit "unreadable --from-file → exit 5" 5 "$RC"
run_in "$REPO" a5 archive gist 1 --from-file "$WORK/old.md" --repo o/r
assert_exit "unknown target kind → exit 2" 2 "$RC"
run_in "$REPO" a6 archive comment 12ab --from-file "$WORK/old.md" --repo o/r
assert_exit "non-numeric id → exit 2" 2 "$RC"
run_in "$REPO" a7 archive comment 1 --from-file "$WORK/old.md"
assert_exit "missing --repo → exit 2" 2 "$RC"

# ── B. never tracked by git ────────────────────────────────────────────────
echo "B. never tracked"

EXCLUDE="$(git -C "$REPO" rev-parse --git-path info/exclude)"
case "$EXCLUDE" in /*) ;; *) EXCLUDE="$REPO/$EXCLUDE" ;; esac
assert_output_grep "archive dir is listed in .git/info/exclude" ".claude/.idd/archive/" "$EXCLUDE"
require "git check-ignore reports the archive file as ignored" git -C "$REPO" check-ignore -q ".claude/.idd/archive/edits/$ID1.md"
refute_grep "git status does not list the archive" ".claude" "$(git -C "$REPO" status --porcelain --untracked-files=all)"

run_in "$REPO" b1 archive comment 5805214375 --from-file "$WORK/old.md" --repo o/r
EXCL_LINES="$(grep -c 'claude/.idd/archive' "$EXCLUDE")"
assert_eq "exclude block is written once (idempotent)" "1" "$EXCL_LINES"

REINC="$WORK/reinc"; mkdir -p "$REINC"; git -C "$REINC" init -q
printf '!.claude/.idd/archive/\n!.claude/.idd/archive/**\n' >"$REINC/.gitignore"
run_in "$REINC" b2 archive comment 5805214375 --from-file "$WORK/old.md" --repo o/r
assert_exit "re-include rule → exit 7" 7 "$RC"
assert_output_grep "refusal names the archive path" ".claude/.idd/archive" "$WORK/b2.err"
refute "no archive file is left behind" test -e "$REINC/.claude/.idd/archive/edits/$ID1.md"

NOGIT="$WORK/nogit"; mkdir -p "$NOGIT"
run_in "$NOGIT" b3 archive comment 5805214375 --from-file "$WORK/old.md" --repo o/r
assert_exit "outside a git work tree → exit 7" 7 "$RC"
refute "no archive dir is created outside git" test -e "$NOGIT/.claude"

# ── C. unreadable at rest ──────────────────────────────────────────────────
echo "C. unreadable at rest"

assert_eq "archive file mode is 0000" "0o0" "$(mode_of "$ARCH/$ID1.md")"
if [ "$(id -u)" = "0" ]; then
  pass "recursive grep check skipped: running as root, mode bits do not apply"
else
  GREP_OUT="$(cd "$REPO" && grep -r "$SECRET" . 2>/dev/null)"
  refute_grep "grep -r from the repo root does not surface archived content" "$SECRET" "$GREP_OUT"
fi

# ── D. restore ─────────────────────────────────────────────────────────────
echo "D. restore"

mkdir -p "$WORK/bin"
cat >"$WORK/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$STUB_DIR/gh_args"
cat >"$STUB_DIR/gh_stdin"
[ "${STUB_GH_FAIL:-0}" = "1" ] && { echo "stub failure" >&2; exit 1; }
echo "https://github.com/o/r/issues/1#issuecomment-5805214375"
EOF
chmod +x "$WORK/bin/gh"
export STUB_DIR="$WORK"
PATH="$WORK/bin:$PATH"; export PATH

rm -f "$WORK/gh_args"
run_in "$REPO" d1 restore ../../etc/passwd --repo o/r
assert_exit "path-traversal backup id → exit 2" 2 "$RC"
refute "gh is not called for an invalid id" test -e "$WORK/gh_args"

run_in "$REPO" d2 restore "$ID1" --repo 'o/r;rm'
assert_exit "malformed repo → exit 2" 2 "$RC"

run_in "$REPO" d3 restore comment-999-20261009T100000Z --repo o/r
assert_exit "unknown backup id → exit 5" 5 "$RC"

run_in "$REPO" d4 restore "$ID1" --repo o/r
assert_exit "restore succeeds" 0 "$RC"
require "gh received the archived bytes on stdin" cmp -s "$WORK/old.md" "$WORK/gh_stdin"
assert_output_grep "gh targets the comment endpoint" "repos/o/r/issues/comments/5805214375" "$WORK/gh_args"
assert_output_grep "stdout names the target URL" "https://github.com/o/r/issues/1#issuecomment-5805214375" "$WORK/d4.out"
assert_output_grep "stdout reports a byte count" "bytes" "$WORK/d4.out"
refute_output_grep "stdout never carries archived content" "$SECRET" "$WORK/d4.out"
refute_output_grep "stderr never carries archived content" "$SECRET" "$WORK/d4.err"
assert_eq "mode is back to 0000 after restore" "0o0" "$(mode_of "$ARCH/$ID1.md")"

run_in "$REPO" d5 restore issue-351-body-20261009T100000Z --repo o/r
assert_output_grep "issue body restore targets the issue endpoint" "repos/o/r/issues/351" "$WORK/gh_args"
refute_output_grep "issue body restore is not sent to the comments endpoint" "issues/comments" "$WORK/gh_args"

export STUB_GH_FAIL=1
run_in "$REPO" d6 restore "$ID1" --repo o/r
unset STUB_GH_FAIL
refute "failed PATCH → non-zero exit" test "$RC" -eq 0
assert_eq "mode is back to 0000 after a failed restore" "0o0" "$(mode_of "$ARCH/$ID1.md")"

# ── E. PreToolUse read guard ───────────────────────────────────────────────
echo "E. read guard hook"

# hook_case <label> <json> — stdout in $WORK/hook-<label>.out, exit in RC.
hook_case() {
  printf '%s' "$2" | python3 "$HOOK" >"$WORK/hook-$1.out" 2>"$WORK/hook-$1.err"
  RC=$?
}
expect_deny() {
  hook_case "$1" "$2"
  assert_exit "$1: hook exits 0" 0 "$RC"
  assert_output_grep "$1: denied" '"permissionDecision": "deny"' "$WORK/hook-$1.out"
}
expect_allow() {
  hook_case "$1" "$2"
  assert_exit "$1: hook exits 0" 0 "$RC"
  refute_output_grep "$1: allowed" "deny" "$WORK/hook-$1.out"
}

expect_deny read      '{"tool_name":"Read","tool_input":{"file_path":"/x/.claude/.idd/archive/edits/a.md"}}'
expect_deny read-var  '{"tool_name":"Read","tool_input":{"file_path":".Claude/./.IDD/Archive/edits/x.md"}}'
expect_deny grep-path '{"tool_name":"Grep","tool_input":{"pattern":"x","path":".claude/.idd/archive"}}'
expect_deny grep-glob '{"tool_name":"Grep","tool_input":{"pattern":"x","path":".claude/.idd","glob":"archive/**"}}'
expect_deny glob-pat  '{"tool_name":"Glob","tool_input":{"pattern":".claude/.idd/archive/**/*.md"}}'
expect_deny glob-join '{"tool_name":"Glob","tool_input":{"pattern":"archive/**","path":".claude/.idd"}}'
expect_deny edit      '{"tool_name":"Edit","tool_input":{"file_path":"/r/.claude/.idd/archive/edits/a.md","old_string":"a","new_string":"b"}}'
expect_deny write     '{"tool_name":"Write","tool_input":{"file_path":"/r/.claude/.idd/archive/edits/a.md","content":"x"}}'
expect_deny notebook  '{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"/r/.claude/.idd/archive/n.ipynb"}}'
expect_deny bash      '{"tool_name":"Bash","tool_input":{"command":"cat .claude/.idd/archive/edits/x.md"}}'
expect_deny pwsh      '{"tool_name":"PowerShell","tool_input":{"command":"Get-Content .claude\\.idd\\archive\\edits\\x.md"}}'
assert_output_grep "deny reason points to restore" "restore" "$WORK/hook-read.out"

expect_allow helper   '{"tool_name":"Bash","tool_input":{"command":"python3 \"$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py\" archive comment 5805214375 --from-file \"$BACKUP_FILE\" --repo \"$REPO\""}}'
expect_allow skill    '{"tool_name":"Read","tool_input":{"file_path":"plugins/issue-driven-dev/skills/idd-edit/SKILL.md"}}'
expect_allow grep-re  '{"tool_name":"Grep","tool_input":{"pattern":".claude/.idd/archive","path":"plugins"}}'
expect_allow echo     '{"tool_name":"Bash","tool_input":{"command":"echo hi"}}'
expect_allow other    '{"tool_name":"WebFetch","tool_input":{"url":"https://x/.claude/.idd/archive"}}'
expect_allow garbage  'not json at all'

require "hooks.json registers the guard with the exact matcher and keeps SessionStart" python3 - "$HOOKS_JSON" <<'EOF'
import json, sys
h = json.load(open(sys.argv[1]))["hooks"]
pre = h.get("PreToolUse", [])
ok = any(e.get("matcher") == "Read|Grep|Glob|Edit|Write|NotebookEdit|Bash|PowerShell"
         and any("archive-read-guard.py" in x.get("command", "") for x in e.get("hooks", []))
         for e in pre)
sys.exit(0 if ok and h.get("SessionStart") else 1)
EOF

FENCED="$(awk '/^```bash/{f=1;next} /^```/{f=0} f' "$EDIT_SKILL")"
refute_grep "idd-edit executed bash never spells the archive path" ".idd/archive" "$FENCED"

# ── F. round 2 (verify #351 round 1) ──────────────────────────────────────
echo "F. round 2"

# F1. sidecar repo binding + restore refusals
run_in "$REPO" f1 archive comment 777 --from-file "$WORK/old.md" --repo o/r
F1ID="$(cat "$WORK/f1.out")"
assert_file_exists "sidecar records the repo" "$ARCH/$F1ID.repo"
assert_eq "sidecar content" "o/r" "$(cat "$ARCH/$F1ID.repo")"
rm -f "$WORK/gh_args"
run_in "$REPO" f1b restore "$F1ID" --repo c/d
assert_exit "restore to a different repo → exit 2" 2 "$RC"
refute "gh not called on repo mismatch" test -e "$WORK/gh_args"

ln -s "$WORK/old.md" "$ARCH/comment-888-20261009T100000Z.md"
printf 'o/r' >"$ARCH/comment-888-20261009T100000Z.repo"
run_in "$REPO" f1c restore comment-888-20261009T100000Z --repo o/r
assert_exit "symlinked archive entry → exit 2" 2 "$RC"

TR="$WORK/tracked"; mkdir -p "$TR/.claude/.idd/archive/edits"; git -C "$TR" init -q
printf 'x' >"$TR/.claude/.idd/archive/edits/comment-9-20261009T100000Z.md"
printf 'o/r' >"$TR/.claude/.idd/archive/edits/comment-9-20261009T100000Z.repo"
git -C "$TR" add -f .claude >/dev/null 2>&1
run_in "$TR" f1d restore comment-9-20261009T100000Z --repo o/r
assert_exit "tracked archive entry → exit 2" 2 "$RC"

# F2. --from-file sensitive path gate
mkdir -p "$WORK/home/.ssh"; printf 'KEY' >"$WORK/home/.ssh/id_rsa"
export HOME_SAVE="$HOME" HOME="$WORK/home"
run_in "$REPO" f2 archive comment 1 --from-file "$WORK/home/.ssh/id_rsa" --repo o/r
export HOME="$HOME_SAVE"
assert_exit "--from-file under .ssh → exit 5" 5 "$RC"

# F3. linked worktree archives into the main worktree
git -C "$REPO" commit -q --allow-empty -m init
git -C "$REPO" worktree add -q "$WORK/wt" 2>/dev/null
run_in "$WORK/wt" f3 archive comment 4242 --from-file "$WORK/old.md" --repo o/r
F3ID="$(cat "$WORK/f3.out")"
assert_file_exists "archive written under the main worktree" "$ARCH/$F3ID.md"
git -C "$REPO" worktree remove "$WORK/wt" >/dev/null 2>&1
assert_file_exists "archive survives git worktree remove" "$ARCH/$F3ID.md"

# F4. collision filename is checked against ignore rules
CI="$WORK/coll"; mkdir -p "$CI"; git -C "$CI" init -q
printf '!.claude/.idd/archive/\n.claude/.idd/archive/edits/*\n!.claude/.idd/archive/edits/comment-5-20261009T100000Z-2.md\n' >"$CI/.gitignore"
run_in "$CI" f4a archive comment 5 --from-file "$WORK/old.md" --repo o/r
run_in "$CI" f4b archive comment 5 --from-file "$WORK/old.md" --repo o/r
assert_exit "collision name that is not ignored → exit 7" 7 "$RC"
refute "no -2 file written" test -e "$CI/.claude/.idd/archive/edits/comment-5-20261009T100000Z-2.md"

# F5. hook: word-level matching, dot-dot, prefix, unlock flag
expect_allow commit   '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"keep .claude/.idd/archive/ out of git\""}}'
expect_allow ghbody   '{"tool_name":"Bash","tool_input":{"command":"gh issue comment 351 --body \"archive lives in .claude/.idd/archive/edits\""}}'
expect_deny  dotdot   '{"tool_name":"Bash","tool_input":{"command":"cat .claude/x/../.idd/archive/edits/a.md"}}'
expect_deny  dblslash '{"tool_name":"Bash","tool_input":{"command":"cat .claude//.idd/archive/edits/a.md"}}'
expect_allow prefix   '{"tool_name":"Read","tool_input":{"file_path":"/r/.claude/.idd/archive-notes.md"}}'
mkdir -p "$WORK/fakehome/.cache/idd"; : >"$WORK/fakehome/.cache/idd/archive-read-guard.disabled"
printf '%s' '{"tool_name":"Read","tool_input":{"file_path":"/r/.claude/.idd/archive/edits/a.md"}}' \
  | HOME="$WORK/fakehome" python3 "$HOOK" >"$WORK/hook-unlock.out" 2>/dev/null
refute_output_grep "unlock flag allows the call" "deny" "$WORK/hook-unlock.out"

print_summary "correction-archive"
