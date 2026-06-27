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

new_repo() {
  local d
  d="$(mktemp -d)"
  git -C "$d" init -b main -q
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name t
  git -C "$d" rev-parse --show-toplevel
}

TMPDIRS=()
mk() { local r; r="$(new_repo)"; TMPDIRS+=("$r"); printf '%s' "$r"; }
cleanup() { for d in "${TMPDIRS[@]:-}"; do [ -n "${d:-}" ] && rm -rf "$d"; done; }
trap cleanup EXIT

MARKER="IDD test block (#192)"
BEGINLINE="# >>> ${MARKER} >>>"

# --- Test 1: exclude direction → .git/info/exclude ignores the path ---------
R="$(mk)"
bash "$SCRIPT" --target "$R/.git/info/exclude" --marker "$MARKER" --direction exclude ".claude/.idd/"
assert_exit "exclude exits 0" 0 $?
require "exclude: .claude/.idd/local.json now ignored" git -C "$R" check-ignore -q .claude/.idd/local.json
refute  "exclude: unrelated path not ignored"          git -C "$R" check-ignore -q src/main.py

# --- Test 2: idempotent re-run (same marker+body) → one block ---------------
R="$(mk)"
bash "$SCRIPT" --target "$R/.git/info/exclude" --marker "$MARKER" --direction exclude ".claude/.idd/"
bash "$SCRIPT" --target "$R/.git/info/exclude" --marker "$MARKER" --direction exclude ".claude/.idd/"
CNT=$(grep -cF "$BEGINLINE" "$R/.git/info/exclude")
assert_eq "idempotent: block begin-sentinel appears once" "1" "$CNT"

# --- Test 3: stale block upgrade-in-place (same marker, different body) ------
R="$(mk)"
bash "$SCRIPT" --target "$R/.git/info/exclude" --marker "$MARKER" --direction exclude ".claude/old/"
bash "$SCRIPT" --target "$R/.git/info/exclude" --marker "$MARKER" --direction exclude ".claude/.idd/"
MCNT=$(grep -cF "$BEGINLINE" "$R/.git/info/exclude")
assert_eq "stale: begin-sentinel still once after upgrade" "1" "$MCNT"
require "stale: new pattern ignored" git -C "$R" check-ignore -q .claude/.idd/x
refute  "stale: old pattern gone"    git -C "$R" check-ignore -q .claude/old/x

# --- Test 4: adjacent user content preserved --------------------------------
R="$(mk)"
printf '# user header\n*.log\n' > "$R/.git/info/exclude"
bash "$SCRIPT" --target "$R/.git/info/exclude" --marker "$MARKER" --direction exclude ".claude/.idd/"
assert_grep "preserve: user header kept" "# user header" "$(cat "$R/.git/info/exclude")"
require "preserve: user *.log still effective" git -C "$R" check-ignore -q debug.log
require "preserve: new exclude effective"      git -C "$R" check-ignore -q .claude/.idd/y

# --- Test 5: re-include direction → parent-dir-excluded carve-out trackable --
R="$(mk)"
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
R="$(mk)"
EXC="$R/.git/info/exclude"
mkdir -p "$(dirname "$EXC")"
printf '# >>> %s >>>\n.claude/old/\n# user line AFTER a corrupted (END-less) block\nsecrets/\n' "$MARKER" > "$EXC"
bash "$SCRIPT" --target "$EXC" --marker "$MARKER" --direction exclude ".claude/.idd/" 2>/dev/null
assert_exit "missing-END corruption → exit 2 (no delete-to-EOF)" 2 $?
assert_grep "missing-END: trailing user line preserved" "user line AFTER" "$(cat "$EXC")"
assert_grep "missing-END: secrets/ line preserved" "secrets/" "$(cat "$EXC")"

# --- Test 8: re-include idempotency (run twice → one block) -------------------
R="$(mk)"
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
RA="$(mk)"
bash "$SCRIPT" --target "$RA/.gitignore" --marker "$MARKER" --direction exclude ".claude/.idd/"
assert_exit "#194: .gitignore basename allowed → exit 0" 0 $?
bash "$SCRIPT" --target "$RA/.git/info/exclude" --marker "$MARKER" --direction exclude ".claude/.idd/"
assert_exit "#194: exclude basename allowed → exit 0" 0 $?

print_summary "git-ignore-block"
