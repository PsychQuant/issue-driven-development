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

# #351 round 11: idd-edit's --reason is prose; a reason that mentions the archive (round 18: fail-closed — such cases are denied now)
# (the correction of #351's own Expected would) does not read it
expect_deny  edit-reason '{"tool_name":"Bash","tool_input":{"command":"python3 /p/scripts/idd-edit-helper.py run-start --default-repo o/r -- issue:351 --correct --section \u0027## Expected\u0027 --body-file /t/x.md --reason \u0027the backups live in .claude/.idd/archive/edits, not in git\u0027"}}'
expect_deny  edit-reason-subst '{"tool_name":"Bash","tool_input":{"command":"python3 /p/scripts/idd-edit-helper.py run-start -- comment:1 --append --reason \"$(cat .claude/.idd/archive/edits/a.md)\""}}'
# #351 round 12: a heredoc commit message that mentions the archive is still (round 18: fail-closed — such cases are denied now)
# denied (the shell runs $(...)), but the reason says how to pass the text
expect_deny  heredoc '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"$(cat <<'EOF'\nkeep .claude/.idd/archive/ out of git\nEOF\n)\""}}'
assert_output_grep "the denial points to a message file" "--body-file" "$WORK/hook-heredoc.out"
# #351 round 13: -m is skipped as a message only when its value is prose (round 18: fail-closed — such cases are denied now)
# (whitespace); `git diff -m` takes no value, so the path after it is read
expect_deny  diff-m '{"tool_name":"Bash","tool_input":{"command":"git diff --no-index -m .claude/.idd/archive/edits/a.md /dev/null"}}'
assert_output_grep "the denial says any command naming the path is denied" "Any command that names this path is denied" "$WORK/hook-diff-m.out"
# #351 round 14: -m is a message only for message-taking subcommands, and a (round 18: fail-closed — such cases are denied now)
# newline or a glued &&, ||, | ends a command
expect_deny  diff-m-sp '{"tool_name":"Bash","tool_input":{"command":"git diff --no-index -m \u0027/x/My Repo/.claude/.idd/archive/edits/a.md\u0027 /dev/null"}}'
expect_deny  glued-and '{"tool_name":"Bash","tool_input":{"command":"git status&&bash -c -m \u0027cat .claude/.idd/archive/edits/x.md\u0027"}}'
expect_deny  glued-or  '{"tool_name":"Bash","tool_input":{"command":"git status||sh -c -m \u0027cat .claude/.idd/archive/edits/x.md\u0027"}}'
expect_deny  newline   '{"tool_name":"Bash","tool_input":{"command":"git status\nbash -c -m \u0027cat .claude/.idd/archive/edits/x.md\u0027"}}'
expect_deny  git-C     '{"tool_name":"Bash","tool_input":{"command":"git -C repo commit -m \u0027see .claude/.idd/archive/ docs\u0027"}}'
expect_deny  multiline '{"tool_name":"Bash","tool_input":{"command":"git commit -m \u0027first line\nkeep .claude/.idd/archive/ out of git\u0027"}}'
expect_deny  gh-pr     '{"tool_name":"Bash","tool_input":{"command":"gh pr create --title t --body \u0027archive under .claude/.idd/archive/edits\u0027"}}'
# #351 round 15: shlex must not read # as a comment (the rest of the command, (round 18: fail-closed — such cases are denied now)
# later lines and a chmod -R hid behind it); `--` ends options; |& separates
expect_deny  hash-line '{"tool_name":"Bash","tool_input":{"command":"# look at the old version\ncat .claude/.idd/archive/edits/a.md"}}'
expect_deny  hash-tail '{"tool_name":"Bash","tool_input":{"command":"git status  # check first\ncat .claude/.idd/archive/edits/a.md"}}'
expect_deny  hash-mid  '{"tool_name":"Bash","tool_input":{"command":"cat foo#bar .claude/.idd/archive/edits/a.md"}}'
expect_deny  hash-grep '{"tool_name":"Bash","tool_input":{"command":"git log --oneline --grep=#351; cat .claude/.idd/archive/edits/a.md"}}'
expect_deny  hash-chmod "{\"tool_name\":\"Bash\",\"cwd\":\"$REPO\",\"tool_input\":{\"command\":\"# fix perms\nchmod -R u+r .claude\"}}"
expect_deny  dashdash '{"tool_name":"Bash","tool_input":{"command":"git commit -- -m .claude/.idd/archive/edits/a.md"}}'
expect_deny  pipe-amp  '{"tool_name":"Bash","tool_input":{"command":"git commit -m \u0027a b\u0027 |& sort -m \u0027/x/My Repo/.claude/.idd/archive/edits/a.md\u0027"}}'
# round 16: combined short flags are not read as -m (git reads -Fm as -F m)
expect_deny  commit-am '{"tool_name":"Bash","tool_input":{"command":"git commit -am \u0027see .claude/.idd/archive/ docs\u0027"}}'
expect_deny  contline  '{"tool_name":"Bash","tool_input":{"command":"git \\\n commit -m \u0027see .claude/.idd/archive/ docs\u0027"}}'
expect_deny  env-py    '{"tool_name":"Bash","tool_input":{"command":"env A=1 python3 /p/scripts/idd-edit-helper.py run-start --reason \u0027see .claude/.idd/archive/ x\u0027"}}'
expect_deny  hg-repo   '{"tool_name":"Bash","tool_input":{"command":"hg --repository r commit -m \u0027see .claude/.idd/archive/ x\u0027"}}'
# #351 round 16: a shell comment runs to the end of the line and its quotes
# are text; -Fm is not -m; IDD's own '\'' idiom parses as the shell reads it
expect_deny  fm-path   '{"tool_name":"Bash","tool_input":{"command":"git commit -Fm \u0027/repo with spaces/.claude/.idd/archive/edits/a.md\u0027"}}'
expect_deny  c-apos1   "{\"tool_name\":\"Bash\",\"cwd\":\"$REPO\",\"tool_input\":{\"command\":\"# Let\u0027s make it readable\nchmod -R u+r \u0027.claude\u0027\"}}"
expect_deny  c-apos2   "{\"tool_name\":\"Bash\",\"cwd\":\"$REPO\",\"tool_input\":{\"command\":\"chmod -R u+r \u0027.claude/.idd\u0027  # it\u0027s needed\"}}"
expect_deny  c-apos3   "{\"tool_name\":\"Bash\",\"cwd\":\"$REPO\",\"tool_input\":{\"command\":\"chmod -R u+r .claude/.idd;ls  # don\u0027t\"}}"
expect_deny  c-apos4   "{\"tool_name\":\"Bash\",\"cwd\":\"$REPO\",\"tool_input\":{\"command\":\"# Let\u0027s fix the permissions\nchmod -R u+rw .\n# Now let\u0027s retry\ngrep -rn wrong .\"}}"
expect_deny  c-msg     '{"tool_name":"Bash","tool_input":{"command":"git commit -m #x\u0027\ncat .claude/.idd/archive/edits/a.md #\u0027"}}'
expect_deny  c-ls      '{"tool_name":"Bash","tool_input":{"command":"ls # ; git commit -m \u0027\ncat .claude/.idd/archive/edits/a.md #\u0027"}}'
expect_deny  idiom     '{"tool_name":"Bash","tool_input":{"command":"python3 /p/scripts/idd-edit-helper.py run-start -- comment:1 --append --reason \u0027it\u0027\\\u0027\u0027s in .claude/.idd/archive/ now\u0027"}}'
expect_deny  idiom-ch  "{\"tool_name\":\"Bash\",\"cwd\":\"$REPO\",\"tool_input\":{\"command\":\"git commit -m \u0027it\u0027\\\u0027\u0027s\u0027; chmod -R u+r .claude\"}}"
expect_deny  redir     '{"tool_name":"Bash","tool_input":{"command":"git commit -m \u0027see .claude/.idd/archive/ docs\u0027 2>&1"}}'
expect_allow hash-var  '{"tool_name":"Bash","tool_input":{"command":"echo ${#arr[@]} $# foo#bar"}}'
# #351 round 17: comment text and heredoc bodies are scanned, only their quotes
# are ignored; PowerShell backslashes are separators before anything else
expect_deny  subst-hash "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "echo $(true)# note; chmod -R u+r .claude"}}' | sed "s|__REPO__|$REPO|")"
expect_deny  esc-hash   '{"tool_name": "Bash", "tool_input": {"command": "cat foo\\ #x .claude/.idd/archive/edits/a.md"}}'
expect_deny  esc-semi   '{"tool_name": "Bash", "tool_input": {"command": "cat a\\;#b .claude/.idd/archive/edits/a.md"}}'
expect_deny  hd-issue   '{"tool_name": "Bash", "tool_input": {"command": "cat <<EOF\nIssue #351 $(cat .claude/.idd/archive/edits/a.md)\nEOF"}}'
expect_deny  hd-hashln  '{"tool_name": "Bash", "tool_input": {"command": "cat <<EOF\n# Summary: $(cat .claude/.idd/archive/edits/a.md)\nEOF"}}'
expect_deny  hd-prbody  '{"tool_name": "Bash", "tool_input": {"command": "PR_BODY=$(cat <<EOF\nRefs #351 - prior wording: $(head -1 .claude/.idd/archive/edits/a.md)\nEOF\n)"}}'
expect_deny  hd-parity  "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "cat > /tmp/notes.md <<EOF\n## Why it'\''s wrong\nIt'\''s the archive mode.\nEOF\nchmod -R u+rw .claude/.idd\n# Let'\''s check again\nls -la .claude/.idd"}}' | sed "s|__REPO__|$REPO|")"
expect_deny  hd-two     "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "cat > a.txt <<'\''EOF'\''\nWe don'\''t need it.\nEOF\nchmod -R u+r .claude\ncat > b.txt <<'\''EOF'\''\nIt won'\''t matter.\nEOF"}}' | sed "s|__REPO__|$REPO|")"
expect_deny  ps-trail   '{"tool_name": "PowerShell", "tool_input": {"command": "git -C \"C:\\repo\\\" commit -m \"fix #351\"; Get-Content .claude\\.idd\\archive\\edits\\a.md"}}'
expect_deny  paren-cont "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "x=( a b )\\\nchmod -R u+r .claude"}}' | sed "s|__REPO__|$REPO|")"
expect_deny  noclobber  '{"tool_name": "Bash", "tool_input": {"command": "sort >| git commit -m '\''/x/My Repo/.claude/.idd/archive/edits/a.md'\''"}}'
expect_deny  step-cmt   '{"tool_name": "Bash", "tool_input": {"command": "# step: commit\ngit commit -m '\''mention .claude/.idd/archive/ path here'\''"}}'
expect_allow hd-plain   '{"tool_name": "Bash", "tool_input": {"command": "gh pr create --title t --body \"$(cat <<'\''EOF'\''\nRefs #351, it'\''s done\nEOF\n)\""}}'
# #351 round 18 (fail-closed, user decision 2026-10-18): any command that
# names the path is denied, messages included; escapes and quotes are
# resolved before matching, and a chmod -R is found anywhere in the command
expect_deny  esc-arch   '{"tool_name": "Bash", "tool_input": {"command": "cat <<EOF\n$(cat .claude/.idd/arch\\ive/edits/a.md)\nEOF"}}'
expect_deny  dq-arch    '{"tool_name": "Bash", "tool_input": {"command": "cat .claude/.idd/arch\"\"ive/edits/a.md"}}'
expect_deny  sq-arch    '{"tool_name": "Bash", "tool_input": {"command": "cat .claude/.idd/'\''arch'\''ive/edits/a.md"}}'
expect_deny  ln2-cmt    "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "echo start\n# Let'\''s go\nchmod -R u+r .claude\n# That'\''s it"}}' | sed "s|__REPO__|$REPO|")"
expect_deny  hd-cmt     "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "cat > /tmp/n.md <<'\''EOF'\''\nnotes\nEOF\n# Let'\''s fix perms\nchmod -R u+r .claude\n# that'\''s all"}}' | sed "s|__REPO__|$REPO|")"
expect_deny  herestr    "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "cat <<< '\''x'\''\n# it'\''s\nchmod -R u+r .claude\n# it'\''s"}}' | sed "s|__REPO__|$REPO|")"
expect_deny  find-chmod "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "find . -type f -exec chmod u+r {} +"}}' | sed "s|__REPO__|$REPO|")"
expect_deny  glued-par  "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "(cd sub)&&chmod -R u+r .claude"}}' | sed "s|__REPO__|$REPO|")"
expect_allow plain-cmt  '{"tool_name": "Bash", "tool_input": {"command": "git status\n# Let'\''s commit the read guard fix\ngit commit -m '\''fix the read guard'\''"}}'
expect_deny  chmod-ok   "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "chmod -R u+x scripts"}}' | sed "s|__REPO__|$REPO|")"
# #351 round 19: a line continuation joins a path or a command name; a
# chmod -R target is also read as the shell's whole word (spaces kept)
SPACE="$WORK/My Repo"; mkdir -p "$SPACE/.claude/.idd/archive/edits" "$SPACE/sub"
expect_deny  cont-path  '{"tool_name": "Bash", "tool_input": {"command": "cat .claude/.idd/arch\\\nive/edits/a.md"}}'
expect_deny  cont-cmd   "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "chm\\\nod -R u+r .claude"}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g")"
expect_deny  sp-quoted  "$(printf %s '{"tool_name": "Bash", "cwd": "__SPACE__/sub", "tool_input": {"command": "chmod -R u+r \"__SPACE__\""}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g")"
hook_case sp-esc "$(python3 -c 'import json,sys; s=sys.argv[1]; print(json.dumps({"tool_name": "Bash", "cwd": s + "/sub", "tool_input": {"command": "chmod -R u+r " + s.replace(" ", "\\ ")}}))' "$SPACE")"
assert_output_grep "an escaped space in a chmod -R target is one word" '"permissionDecision": "deny"' "$WORK/hook-sp-esc.out"
expect_deny  sp-rel     "$(printf %s '{"tool_name": "Bash", "cwd": "__SPACE__/sub", "tool_input": {"command": "chmod -R u+rw \"../.claude\""}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g")"
expect_deny  nested-bs  '{"tool_name": "Bash", "tool_input": {"command": "bash -c \"cat .claude\\\\/.idd/archive/edits/a.md\""}}'
expect_deny  ansi-c     '{"tool_name": "Bash", "tool_input": {"command": "cat .claude/.idd/$'\''arch'\''ive/edits/a.md"}}'
expect_deny  ps-tick    '{"tool_name": "PowerShell", "tool_input": {"command": "Get-Content .claude/.idd/arch`ive/edits/a.md"}}'
expect_deny  pwd-var    "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "chmod -R u+r \"$PWD\""}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g")"
expect_deny  toplevel   "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "chmod -R u+r \"$(git rev-parse --show-toplevel)\""}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g")"
expect_deny  rec-abbr   "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "chmod --recurs u+r .claude"}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g")"
expect_deny  grep-chmod "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "grep -R chmod ."}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g")"
expect_deny  monitor    '{"tool_name": "Monitor", "tool_input": {"command": "tail -f .claude/.idd/archive/edits/a.md", "description": "x", "timeout_ms": 1000}}'
expect_allow chmod-file "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "chmod u+x scripts/run.sh"}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g")"
# #351 round 20: inside a repository that holds the archive every recursive
# permission change is refused (chmod-ok and grep-chmod above are denied now);
# elsewhere every word counts as a target and an unresolvable one refuses
PLAIN="$WORK/plain"; mkdir -p "$PLAIN/scripts"
expect_deny  glued-semi "$(printf %s '{"tool_name": "Bash", "cwd": "__SPACE__/sub", "tool_input": {"command": "true;chmod -R u+r \"__SPACE__\""}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g; s|__PLAIN__|$PLAIN|g")"
expect_deny  apos-cmt   "$(printf %s '{"tool_name": "Bash", "cwd": "__SPACE__", "tool_input": {"command": "chmod -R u+r \"__SPACE__\" # it'\''s done"}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g; s|__PLAIN__|$PLAIN|g")"
expect_deny  cd-rel     "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "cd .claude && chmod -R u+rw .idd"}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g; s|__PLAIN__|$PLAIN|g")"
expect_deny  pushd-rel  "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "pushd .claude >/dev/null; chmod -R u+r .idd"}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g; s|__PLAIN__|$PLAIN|g")"
expect_deny  dot-glob   "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "chmod -R u+rw .*"}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g; s|__PLAIN__|$PLAIN|g")"
expect_deny  ps-recurse "$(printf %s '{"tool_name": "PowerShell", "cwd": "__REPO__", "tool_input": {"command": "Get-ChildItem -Recurse | ForEach-Object { chmod u+r $_ }"}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g; s|__PLAIN__|$PLAIN|g")"
expect_deny  out-space  "$(printf %s '{"tool_name": "Bash", "cwd": "__PLAIN__", "tool_input": {"command": "chmod -R u+r \"__SPACE__\""}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g; s|__PLAIN__|$PLAIN|g")"
expect_deny  out-glued  "$(printf %s '{"tool_name": "Bash", "cwd": "__PLAIN__", "tool_input": {"command": "true&&chmod -R u+r \"__SPACE__\""}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g; s|__PLAIN__|$PLAIN|g")"
expect_deny  out-cd     "$(printf %s '{"tool_name": "Bash", "cwd": "__PLAIN__", "tool_input": {"command": "cd \"__SPACE__\" && chmod -R u+r ."}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g; s|__PLAIN__|$PLAIN|g")"
expect_deny  out-var    "$(printf %s '{"tool_name": "Bash", "cwd": "__PLAIN__", "tool_input": {"command": "chmod -R u+r \"$TARGET\""}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g; s|__PLAIN__|$PLAIN|g")"
expect_allow out-plain  "$(printf %s '{"tool_name": "Bash", "cwd": "__PLAIN__", "tool_input": {"command": "chmod -R u+x scripts"}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g; s|__PLAIN__|$PLAIN|g")"
expect_allow out-search "$(printf %s '{"tool_name": "Bash", "cwd": "__PLAIN__", "tool_input": {"command": "grep -R chmod ."}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g; s|__PLAIN__|$PLAIN|g")"
expect_allow in-nonrec  "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "chmod u+x scripts/run.sh"}}' | sed "s|__REPO__|$REPO|g; s|__SPACE__|$SPACE|g; s|__PLAIN__|$PLAIN|g")"
# round 20: a lowercase r flag is not recursive; a folder that holds a
# repository with an archive counts as a directory above it
expect_allow lrt-flag   "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "ls -lrt && chmod u+x scripts/run.sh"}}' | sed "s|__REPO__|$REPO|g; s|__PLAIN__|$PLAIN|g")"
expect_deny  sibling-up "$(printf %s '{"tool_name": "Bash", "cwd": "__PLAIN__", "tool_input": {"command": "chmod -R u+r .."}}' | sed "s|__REPO__|$REPO|g; s|__PLAIN__|$PLAIN|g")"
expect_deny  folder-dot "$(printf %s '{"tool_name": "Bash", "cwd": "__PLAIN__/..", "tool_input": {"command": "chmod -R u+r ."}}' | sed "s|__REPO__|$REPO|g; s|__PLAIN__|$PLAIN|g")"
hook_case permreason "$(printf %s '{"tool_name": "Bash", "cwd": "__REPO__", "tool_input": {"command": "chmod -R u+r ."}}' | sed "s|__REPO__|$REPO|g")"
assert_output_grep "a recursive permission change gets its own reason" "recursive permission change" "$WORK/hook-permreason.out"
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
ok = any(e.get("matcher") == "Read|Grep|Glob|Edit|Write|NotebookEdit|Bash|PowerShell|Monitor"
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

# F5. hook: path-segment matching, dot-dot, prefix, unlock flag (round 18: every word is scanned, messages included)
expect_deny  commit   '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"keep .claude/.idd/archive/ out of git\""}}'
expect_deny  ghbody   '{"tool_name":"Bash","tool_input":{"command":"gh issue comment 351 --body \"archive lives in .claude/.idd/archive/edits\""}}'
expect_deny  dotdot   '{"tool_name":"Bash","tool_input":{"command":"cat .claude/x/../.idd/archive/edits/a.md"}}'
expect_deny  dblslash '{"tool_name":"Bash","tool_input":{"command":"cat .claude//.idd/archive/edits/a.md"}}'
expect_allow prefix   '{"tool_name":"Read","tool_input":{"file_path":"/r/.claude/.idd/archive-notes.md"}}'
expect_deny  shc      '{"tool_name":"Bash","tool_input":{"command":"sh -c \"cat .claude/.idd/archive/edits/a.md\""}}'
expect_deny  pyc      '{"tool_name":"Bash","tool_input":{"command":"python3 -c \"print(open(\u0027.claude/.idd/archive/edits/a.md\u0027).read())\""}}'
expect_deny  quoted   '{"tool_name":"Bash","tool_input":{"command":"cat \".claude/.idd/archive/edits/a b.md\""}}'
expect_deny  commitF  '{"tool_name":"Bash","tool_input":{"command":"git commit --message=\"see .claude/.idd/archive/ docs\""}}'
expect_deny  subst    '{"tool_name":"Bash","tool_input":{"command":"gh issue comment 1 --body \"$(cat .claude/.idd/archive/edits/a.md)\""}}'
expect_deny  backtick '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"`cat .claude/.idd/archive/edits/a.md`\""}}'
expect_deny  procsub  '{"tool_name":"Bash","tool_input":{"command":"gh issue comment 1 --body-file <(cat .claude/.idd/archive/edits/a.md)"}}'
mkdir -p "$WORK/fakehome/.cache/idd"; : >"$WORK/fakehome/.cache/idd/archive-read-guard.disabled"
printf '%s' '{"tool_name":"Read","tool_input":{"file_path":"/r/.claude/.idd/archive/edits/a.md"}}' \
  | HOME="$WORK/fakehome" python3 "$HOOK" >"$WORK/hook-unlock.out" 2>/dev/null
refute_output_grep "unlock flag allows the call" "deny" "$WORK/hook-unlock.out"

# ── G. round 3 (verify #351 round 2) ──────────────────────────────────────
echo "G. round 3"

# G1. restore refuses when any directory on the archive path is a symlink
for link_at in edits archive; do
  SL="$WORK/sl-$link_at"; mkdir -p "$SL"; git -C "$SL" init -q
  ELSE="$WORK/elsewhere-$link_at"; mkdir -p "$ELSE/edits"
  printf 'x' >"$ELSE/edits/comment-9-20261009T100000Z.md"
  printf 'o/r' >"$ELSE/edits/comment-9-20261009T100000Z.repo"
  if [ "$link_at" = edits ]; then
    mkdir -p "$SL/.claude/.idd/archive"; ln -s "$ELSE/edits" "$SL/.claude/.idd/archive/edits"
  else
    mkdir -p "$SL/.claude/.idd"; ln -s "$ELSE" "$SL/.claude/.idd/archive"
  fi
  rm -f "$WORK/gh_args"
  run_in "$SL" "g1-$link_at" restore comment-9-20261009T100000Z --repo o/r
  assert_exit "restore through a symlinked '$link_at' directory → exit 2" 2 "$RC"
  refute "gh not called when '$link_at' is a symlink" test -e "$WORK/gh_args"
done

# G2. archive refuses to write through a symlinked directory
SW="$WORK/sl-write"; mkdir -p "$SW/.claude/.idd"; git -C "$SW" init -q
mkdir -p "$WORK/write-elsewhere"; ln -s "$WORK/write-elsewhere" "$SW/.claude/.idd/archive"
run_in "$SW" g2 archive comment 10 --from-file "$WORK/old.md" --repo o/r
assert_exit "archive through a symlinked directory → exit 7" 7 "$RC"
refute "nothing written behind the symlink" test -e "$WORK/write-elsewhere/edits"

# ── H. round 4 (verify #351 round 3) ──────────────────────────────────────
echo "H. round 4"

# H1. the sidecar is created exclusively: an orphan or a symlinked .repo is never written through
OR="$WORK/orphan"; mkdir -p "$OR"; git -C "$OR" init -q
mkdir -p "$OR/.claude/.idd/archive/edits"
printf 'someone/else' >"$OR/.claude/.idd/archive/edits/comment-11-20261009T100000Z.repo"
printf 'victim' >"$WORK/victim.txt"
ln -s "$WORK/victim.txt" "$OR/.claude/.idd/archive/edits/comment-12-20261009T100000Z.repo"
run_in "$OR" h1a archive comment 11 --from-file "$WORK/old.md" --repo o/r
assert_eq "an orphan sidecar pushes the id to -2" "comment-11-20261009T100000Z-2" "$(cat "$WORK/h1a.out")"
assert_eq "the orphan sidecar is untouched" "someone/else" "$(cat "$OR/.claude/.idd/archive/edits/comment-11-20261009T100000Z.repo")"
run_in "$OR" h1b archive comment 12 --from-file "$WORK/old.md" --repo o/r
assert_eq "a symlinked sidecar is not written through" "victim" "$(cat "$WORK/victim.txt")"

# H2. a nested repository (submodule) under the archive path is refused
NR="$WORK/nested"; mkdir -p "$NR"; git -C "$NR" init -q
mkdir -p "$NR/.claude/.idd/archive/edits"; git -C "$NR/.claude" init -q
printf 'x' >"$NR/.claude/.idd/archive/edits/comment-13-20261009T100000Z.md"
printf 'o/r' >"$NR/.claude/.idd/archive/edits/comment-13-20261009T100000Z.repo"
git -C "$NR/.claude" add -f . >/dev/null 2>&1
rm -f "$WORK/gh_args"
run_in "$NR" h2 restore comment-13-20261009T100000Z --repo o/r
assert_exit "an entry inside a nested repository → exit 2" 2 "$RC"
refute "gh not called for a nested-repository entry" test -e "$WORK/gh_args"

# H3. on a case-insensitive filesystem, a tracked .CLAUDE/... entry is still refused
CS="$WORK/case"; mkdir -p "$CS/.CLAUDE/.IDD/ARCHIVE/EDITS"; git -C "$CS" init -q
if [ -d "$CS/.claude/.idd/archive/edits" ]; then
  printf 'x' >"$CS/.CLAUDE/.IDD/ARCHIVE/EDITS/comment-14-20261009T100000Z.md"
  printf 'o/r' >"$CS/.CLAUDE/.IDD/ARCHIVE/EDITS/comment-14-20261009T100000Z.repo"
  git -C "$CS" add -f . >/dev/null 2>&1
  rm -f "$WORK/gh_args"
  run_in "$CS" h3 restore comment-14-20261009T100000Z --repo o/r
  assert_exit "a tracked entry under a case variant → exit 2" 2 "$RC"
  refute "gh not called for the case variant" test -e "$WORK/gh_args"
fi

# H4. hook: a recursive chmod above the archive is denied; -m is prose only for message-taking commands (round 18: fail-closed — such cases are denied now)
expect_deny  chmodR   "{\"tool_name\":\"Bash\",\"cwd\":\"$REPO\",\"tool_input\":{\"command\":\"chmod -R u+r .claude\"}}"
expect_deny  chmodRd  "{\"tool_name\":\"Bash\",\"cwd\":\"$REPO\",\"tool_input\":{\"command\":\"chmod -R u+rw .\"}}"
expect_allow chmodOk  "{\"tool_name\":\"Bash\",\"cwd\":\"$REPO\",\"tool_input\":{\"command\":\"chmod u+x scripts/run.sh\"}}"
expect_deny  sortm    '{"tool_name":"Bash","tool_input":{"command":"sort -m .claude/.idd/archive/edits/a.md"}}'
# round 15: a message value is skipped only when it is prose in a message-taking (round 18: fail-closed — such cases are denied now)
# subcommand (whitespace and subcommand both), so a one-word -m value is scanned
expect_deny  gitm     '{"tool_name":"Bash","tool_input":{"command":"git commit -m .claude/.idd/archive/edits"}}'

# ── I. round 5 (verify #351 round 4) ──────────────────────────────────────
echo "I. round 5"

# I1. a recursive permission change above the repository root
mkdir -p "$REPO/sub"
expect_deny  chmodUp  "{\"tool_name\":\"Bash\",\"cwd\":\"$REPO/sub\",\"tool_input\":{\"command\":\"chmod -R u+r ../..\"}}"
# I2. IDD's own posts and env-prefixed commands keep the message exemption (round 18: fail-closed — such cases are denied now)
expect_deny  egressBody '{"tool_name":"Bash","tool_input":{"command":"bash plugins/issue-driven-dev/scripts/gh-egress.sh comment 1 --body \"the archive lives in .claude/.idd/archive/edits\""}}'
expect_deny  envGh      '{"tool_name":"Bash","tool_input":{"command":"GH_PAGER=cat gh issue comment 1 --body \"see .claude/.idd/archive/edits\""}}'
expect_deny  envGit     '{"tool_name":"Bash","tool_input":{"command":"GIT_EDITOR=true git commit -m \"keep .claude/.idd/archive out\""}}'
# I3. a redirection in a message value is not prose (round 18: fail-closed — such cases are denied now)
expect_deny  msgRedir   '{"tool_name":"Bash","tool_input":{"command":"git commit -m <.claude/.idd/archive/edits/a.md"}}'

# I4. archive refuses a repository that tracks anything under the archive path
TA="$WORK/tracks"; mkdir -p "$TA/.claude/.idd/archive/edits"; git -C "$TA" init -q
printf 'x' >"$TA/.claude/.idd/archive/edits/planted.md"
git -C "$TA" add -f .claude >/dev/null 2>&1
run_in "$TA" i4 archive comment 21 --from-file "$WORK/old.md" --repo o/r
assert_exit "archive in a repository that tracks the archive path → exit 7" 7 "$RC"

print_summary "correction-archive"
