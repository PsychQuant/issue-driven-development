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
# A `## ` line ends the section only outside the block: inside it, it is a comment
# and the patterns after it must still be tested.
EXAMPLE="$(awk '
  /^## \.gitignore guidance[[:space:]]*$/ { sec = 1; next }
  sec && !inblk && /^## / { exit }
  sec && /^```/ { if (inblk) exit; inblk = 1; next }
  inblk && !/^#/ && NF { print }
' "$RULE")"
assert_true "example block found under '## .gitignore guidance'" '[ -n "$EXAMPLE" ]'

# Only the example may decide what is ignored: no user or system git config
# (core.excludesFile, ~/.config/git/ignore) and no repo inherited from the caller
# (GIT_DIR / GIT_INDEX_FILE are set when this runs inside a git hook).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
R="$(mktemp -d)" || { echo "FATAL: mktemp -d failed" >&2; exit 1; }
trap 'rm -rf "$R"' EXIT
git -C "$R" init -q -b main || exit 1
git -C "$R" config user.email t@t.t
git -C "$R" config user.name t
git -C "$R" config core.excludesFile /dev/null
printf '%s\n' "$EXAMPLE" > "$R/.gitignore"
A=".claude/.idd/attachments/issue-7"
mkdir -p "$R/$A/sub"
printf '{"issue": 7, "files": []}\n' > "$R/$A/_manifest.json"
printf 'binary\n' > "$R/$A/1.pdf"
printf 'binary\n' > "$R/$A/photo.jpg"
printf 'binary\n' > "$R/$A/report.docx"
printf 'binary\n' > "$R/$A/.hidden.png"
# GitHub image attachments (user-attachments/assets/<uuid>) have no extension
printf 'binary\n' > "$R/$A/3f2c9a1e-5b7d-4c8e-9a0f-1b2c3d4e5f60"
printf 'binary\n' > "$R/$A/sub/x"

refute  "#432: _manifest.json is not ignored"  git -C "$R" check-ignore -q "$A/_manifest.json"
for f in 1.pdf photo.jpg report.docx .hidden.png 3f2c9a1e-5b7d-4c8e-9a0f-1b2c3d4e5f60 sub/x; do
  require "#432: attachment $f ignored" git -C "$R" check-ignore -q "$A/$f"
done

git -C "$R" add -- "$A" 2>/dev/null
assert_exit "#432: git add of the issue dir succeeds" 0 $?
assert_eq "#432: git add stages only the manifest" "$A/_manifest.json" "$(git -C "$R" diff --cached --name-only)"

print_summary "attachments-gitignore-example"
