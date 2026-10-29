#!/usr/bin/env bash
# test.sh — the .gitignore example in rules/process-attachments.md keeps
# _manifest.json trackable (PsychQuant/issue-driven-development#432)
#
# The example is copied by users into their own .gitignore, so it is tested as
# written: the fenced block under `## .gitignore guidance` is extracted from the
# rule file and applied to a throwaway repo. An `attachments/**` pattern excludes
# the issue-N/ directory itself, and git cannot re-include a file whose parent
# directory is excluded — the manifest was ignored along with the binaries.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RULE="$HERE/../../../rules/process-attachments.md"

. "$HERE/../../lib/assert-helpers.sh"

# First fenced block after the `## .gitignore guidance` heading, comment lines dropped.
EXAMPLE="$(awk '
  /^## \.gitignore guidance[[:space:]]*$/ { sec = 1; next }
  sec && /^## / { exit }
  sec && /^```/ { if (inblk) exit; inblk = 1; next }
  inblk && !/^#/ && NF { print }
' "$RULE")"
assert_true "example block found under '## .gitignore guidance'" '[ -n "$EXAMPLE" ]'

R="$(mktemp -d)"
trap 'rm -rf "$R"' EXIT
git -C "$R" init -q -b main
git -C "$R" config user.email t@t.t
git -C "$R" config user.name t
printf '%s\n' "$EXAMPLE" > "$R/.gitignore"
A=".claude/.idd/attachments/issue-7"
mkdir -p "$R/$A"
printf '{"issue": 7, "files": []}\n' > "$R/$A/_manifest.json"
printf 'binary\n' > "$R/$A/1.pdf"
printf 'binary\n' > "$R/$A/photo.jpg"

refute  "#432: _manifest.json is not ignored"  git -C "$R" check-ignore -q "$A/_manifest.json"
require "#432: attachment binary (.pdf) ignored" git -C "$R" check-ignore -q "$A/1.pdf"
require "#432: attachment binary (.jpg) ignored" git -C "$R" check-ignore -q "$A/photo.jpg"

git -C "$R" add -- "$A" 2>/dev/null
assert_exit "#432: git add of the issue dir succeeds" 0 $?
assert_eq "#432: git add stages only the manifest" "$A/_manifest.json" "$(git -C "$R" diff --cached --name-only)"

print_summary "attachments-gitignore-example"
