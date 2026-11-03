#!/usr/bin/env bash
# test.sh — fixture-dir tests for git-ignore-block.sh (PsychQuant/issue-driven-development#192)
#
# Each test spins up a throwaway git repo in a temp dir, runs the helper against
# .git/info/exclude or .gitignore, and asserts behavior via `git check-ignore`.
# Self-contained — no live GitHub / network.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../git-ignore-block.sh"

. "$HERE/../../lib/assert-helpers.sh"

# Every throwaway repo lives under one root, so the EXIT trap removes all of them
# (a list appended inside "$(mk)" was lost with the subshell). A repo that cannot
# be created stops the run: with R="" every "$R/..." below is a path at the
# filesystem root (#431 verify).
TROOT="$(mktemp -d)" || { echo "FATAL: mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$TROOT"' EXIT
new_repo() {
  local d
  d="$(mktemp -d "$TROOT/repo.XXXXXX")" || return 1
  git -C "$d" init -b main -q || return 1
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name t
  git -C "$d" rev-parse --show-toplevel
}
mk() {
  local r
  r="$(new_repo)" && [ -n "$r" ] || { echo "FATAL: could not create a test repo under $TROOT" >&2; return 1; }
  printf '%s' "$r"
}

MARKER="IDD test block (#192)"
BEGINLINE="# >>> ${MARKER} >>>"

# --- Test 1: exclude direction → .git/info/exclude ignores the path ---------
R="$(mk)" || exit 1
bash "$SCRIPT" --target "$R/.git/info/exclude" --marker "$MARKER" --direction exclude ".claude/.idd/"
assert_exit "exclude exits 0" 0 $?
require "exclude: .claude/.idd/local.json now ignored" git -C "$R" check-ignore -q .claude/.idd/local.json
refute  "exclude: unrelated path not ignored"          git -C "$R" check-ignore -q src/main.py

# --- Test 2: idempotent re-run (same marker+body) → one block ---------------
R="$(mk)" || exit 1
bash "$SCRIPT" --target "$R/.git/info/exclude" --marker "$MARKER" --direction exclude ".claude/.idd/"
bash "$SCRIPT" --target "$R/.git/info/exclude" --marker "$MARKER" --direction exclude ".claude/.idd/"
CNT=$(grep -cF "$BEGINLINE" "$R/.git/info/exclude")
assert_eq "idempotent: block begin-sentinel appears once" "1" "$CNT"

# --- Test 3: stale block upgrade-in-place (same marker, different body) ------
R="$(mk)" || exit 1
bash "$SCRIPT" --target "$R/.git/info/exclude" --marker "$MARKER" --direction exclude ".claude/old/"
bash "$SCRIPT" --target "$R/.git/info/exclude" --marker "$MARKER" --direction exclude ".claude/.idd/"
MCNT=$(grep -cF "$BEGINLINE" "$R/.git/info/exclude")
assert_eq "stale: begin-sentinel still once after upgrade" "1" "$MCNT"
require "stale: new pattern ignored" git -C "$R" check-ignore -q .claude/.idd/x
refute  "stale: old pattern gone"    git -C "$R" check-ignore -q .claude/old/x

# --- Test 4: adjacent user content preserved --------------------------------
R="$(mk)" || exit 1
printf '# user header\n*.log\n' > "$R/.git/info/exclude"
bash "$SCRIPT" --target "$R/.git/info/exclude" --marker "$MARKER" --direction exclude ".claude/.idd/"
assert_grep "preserve: user header kept" "# user header" "$(cat "$R/.git/info/exclude")"
require "preserve: user *.log still effective" git -C "$R" check-ignore -q debug.log
require "preserve: new exclude effective"      git -C "$R" check-ignore -q .claude/.idd/y

# --- Test 5: re-include direction → parent-dir-excluded carve-out trackable --
R="$(mk)" || exit 1
printf '.claude/\n' > "$R/.gitignore"
require "re-include precheck: path ignored before carve-out" git -C "$R" check-ignore -q .claude/.idd/issue-runs/x.jsonl
bash "$SCRIPT" --target "$R/.gitignore" --marker "$MARKER" --direction re-include ".claude/.idd/issue-runs"
refute  "re-include: issue-runs now trackable"          git -C "$R" check-ignore -q .claude/.idd/issue-runs/x.jsonl
require "re-include: sibling .claude/other still ignored" git -C "$R" check-ignore -q .claude/other/y

# --- Test 6: usage errors -----------------------------------------------------
bash "$SCRIPT" --target /tmp/x --marker m --direction bogus foo 2>/dev/null
assert_exit "bad direction exits 2" 2 $?
bash "$SCRIPT" --marker m --direction exclude foo 2>/dev/null
assert_exit "missing --target exits 2" 2 $?
bash "$SCRIPT" --target /tmp/x --direction exclude 2>/dev/null
assert_exit "missing pattern exits 2" 2 $?
bash "$SCRIPT" --target 2>/dev/null   # valueless option must not hang/loop
assert_exit "valueless --target exits 2 (no infinite loop)" 2 $?

# --- Test 7: missing-END corruption → abort, surrounding content preserved ----
R="$(mk)" || exit 1
EXC="$R/.git/info/exclude"
mkdir -p "$(dirname "$EXC")"
printf '# >>> %s >>>\n.claude/old/\n# user line AFTER a corrupted (END-less) block\nsecrets/\n' "$MARKER" > "$EXC"
bash "$SCRIPT" --target "$EXC" --marker "$MARKER" --direction exclude ".claude/.idd/" 2>/dev/null
assert_exit "missing-END corruption → exit 2 (no delete-to-EOF)" 2 $?
assert_grep "missing-END: trailing user line preserved" "user line AFTER" "$(cat "$EXC")"
assert_grep "missing-END: secrets/ line preserved" "secrets/" "$(cat "$EXC")"

# --- Test 8: re-include idempotency (run twice → one block) -------------------
R="$(mk)" || exit 1
printf '.claude/\n' > "$R/.gitignore"
bash "$SCRIPT" --target "$R/.gitignore" --marker "$MARKER" --direction re-include ".claude/.idd/issue-runs"
bash "$SCRIPT" --target "$R/.gitignore" --marker "$MARKER" --direction re-include ".claude/.idd/issue-runs"
RCNT=$(grep -cF "$BEGINLINE" "$R/.gitignore")
assert_eq "re-include idempotent: begin-sentinel once" "1" "$RCNT"
refute "re-include idempotent: still trackable" git -C "$R" check-ignore -q .claude/.idd/issue-runs/x.jsonl

# --- Test 9: target allowlist (#194) — reject non-ignore-file targets ---------
bash "$SCRIPT" --target /tmp/idd-hax/.git/hooks/pre-commit --marker m --direction exclude ".x" 2>/dev/null
assert_exit "#194: .git/hooks/pre-commit target rejected → exit 2" 2 $?
bash "$SCRIPT" --target /tmp/idd-hax/random.txt --marker m --direction exclude ".x" 2>/dev/null
assert_exit "#194: arbitrary basename rejected → exit 2" 2 $?
# allowed basenames still work
RA="$(mk)" || exit 1
bash "$SCRIPT" --target "$RA/.gitignore" --marker "$MARKER" --direction exclude ".claude/.idd/"
assert_exit "#194: .gitignore basename allowed → exit 0" 0 $?
bash "$SCRIPT" --target "$RA/.git/info/exclude" --marker "$MARKER" --direction exclude ".claude/.idd/"
assert_exit "#194: exclude basename allowed → exit 0" 0 $?

# --- Test 10: an `exclude` target must be <git-dir>/info/exclude of a real repo (#431)
# Outside a work tree `git rev-parse --git-dir` prints nothing, so the callers'
# "$(git rev-parse --git-dir)/info/exclude" becomes /info/exclude. That case runs
# only where /info does not exist; a helper that still writes it fails here and
# leaves /info/exclude for the person running the tests to remove. If the file
# there holds exactly this test's own block (an earlier run of a broken helper
# wrote it), the case still runs — it cannot touch anything else — and the file
# must come out unchanged. Any other /info is reported, not silently dropped.
if [ ! -e /info ]; then
  bash "$SCRIPT" --target "/info/exclude" --marker m --direction exclude ".x" 2>/dev/null
  assert_exit "#431: empty git-dir (/info/exclude) rejected → exit 2" 2 $?
  assert_file_absent "#431: /info/exclude not created" /info/exclude
elif [ "$(cat /info/exclude 2>/dev/null)" = "$(printf '# >>> m >>>\n.x\n# <<< m <<<')" ]; then
  BEFORE="$(cksum < /info/exclude)"
  bash "$SCRIPT" --target "/info/exclude" --marker m --direction exclude ".x" 2>/dev/null
  assert_exit "#431: empty git-dir (/info/exclude) rejected → exit 2" 2 $?
  assert_eq "#431: leftover /info/exclude unchanged" "$BEFORE" "$(cksum < /info/exclude)"
else
  echo "  SKIP #431: empty git-dir (/info/exclude) — /info exists on this host"
fi
# A trailing newline in a path component is stripped by $(dirname …), so the
# probe would check a real git dir while the write lands next to it.
RN="$(mk)" || exit 1
bash "$SCRIPT" --target "$RN/.git"$'\n'"/info/exclude" --marker m --direction exclude ".x" 2>/dev/null
assert_exit "#431: newline in the git-dir component rejected → exit 2" 2 $?
assert_file_absent "#431: no '.git<newline>' dir created" "$RN/.git"$'\n'
bash "$SCRIPT" --target "$RN/.git/info/exclude"$'\n' --marker m --direction exclude ".x" 2>/dev/null
assert_exit "#431: trailing newline on the target rejected → exit 2" 2 $?
assert_file_absent "#431: no 'exclude<newline>' file created" "$RN/.git/info/exclude"$'\n'
# A .git FILE (linked worktree, submodule) passes `git --git-dir`, which follows
# its gitdir: line, but it is not a directory the helper can write under.
RW="$(mk)" || exit 1
git -C "$RW" commit -q --allow-empty -m init
git -C "$RW" worktree add -q "$TROOT/wt-gitfile" 2>/dev/null
bash "$SCRIPT" --target "$TROOT/wt-gitfile/.git/info/exclude" --marker m --direction exclude ".x" 2>/dev/null
assert_exit "#431: a .git file (gitfile) as the git dir rejected → exit 2" 2 $?
NG="$(mktemp -d "$TROOT/nongit.XXXXXX")" || exit 1
bash "$SCRIPT" --target "$NG/info/exclude" --marker m --direction exclude ".x" 2>/dev/null
assert_exit "#431: info/exclude under a non-git dir rejected → exit 2" 2 $?
assert_file_absent "#431: non-git info/ not created" "$NG/info"
RB="$(mk)" || exit 1
bash "$SCRIPT" --target "$RB/.git/hooks/exclude" --marker m --direction exclude ".x" 2>/dev/null
assert_exit "#431: <git-dir>/hooks/exclude (not info/) rejected → exit 2" 2 $?
assert_file_absent "#431: hooks/exclude not created" "$RB/.git/hooks/exclude"
bash "$SCRIPT" --target "$NG/some/where/exclude" --marker m --direction exclude ".x" 2>/dev/null
assert_exit "#431: arbitrary <dir>/exclude rejected → exit 2" 2 $?
assert_file_absent "#431: arbitrary parent dir not created" "$NG/some"
# the form the callers pass from a repo's top level is relative: .git/info/exclude
RR="$(mk)" || exit 1
( cd "$RR" && bash "$SCRIPT" --target "$(git rev-parse --git-dir)/info/exclude" --marker "$MARKER" --direction exclude ".claude/.idd/" )
assert_exit "#431: relative .git/info/exclude from the top level → exit 0" 0 $?
require "#431: relative target is effective" git -C "$RR" check-ignore -q .claude/.idd/local.json

print_summary "git-ignore-block"
