#!/usr/bin/env bash
# spec-archive-local suite (#547) — a repository without a remote can opt into its local
# default branch: `spec-change.py archive-ref` decides which branch the spec checks read,
# `spec-change.py link-base` gives the base of the link check in that mode.
#
# spec-example: spec-on-every-issue / how a spec_archive entry resolves
# spec-example: spec-on-every-issue / where the local link check starts
#
# Real git repositories under a temporary HOME, so the walk up for the IDD configuration
# stops inside the fixture and never reads the developer's own files.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
SC="$PLUGIN/scripts/spec-change.py"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/idd-spec-archive-local.XXXXXX")
WORK=$(cd "$WORK" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
field() { python3 -c 'import json,sys; d=json.loads(sys.stdin.read() or "{}"); print(d.get(sys.argv[1], "<missing>"))' "$1"; }

mkrepo() { # dir → a repository with one commit on master
  mkdir -p "$1"; git init -q -b master "$1"
  git -C "$1" commit -q --allow-empty -m base
}
conf() { # parent-dir json → writes <parent>/.claude/.idd/local.json
  mkdir -p "$1/.claude/.idd"; printf '%s\n' "$2" > "$1/.claude/.idd/local.json"
}
ar() { OUT=$(python3 "$SC" archive-ref --cwd "$1" 2>/dev/null); RC=$?; ST=$(printf '%s' "$OUT" | field status); }
OPT='{"ref": "local", "branch": "master"}'

echo "spec-archive-local: how a spec_archive entry resolves"
mkrepo "$WORK/none/sub"
ar "$WORK/none/sub"
assert_eq "no configuration found → remote" remote "$ST"
assert_exit "… exit 0" 0 "$RC"

mkrepo "$WORK/a2/sub"; conf "$WORK/a2" '{"github_repo": "o/r"}'
ar "$WORK/a2/sub"
assert_eq "a file without spec_archive → remote" remote "$ST"

mkrepo "$WORK/a3/sub"; conf "$WORK/a3" "{\"spec_archive\": {\"other\": $OPT}}"
ar "$WORK/a3/sub"
assert_eq "spec_archive names another path only → remote" remote "$ST"

mkrepo "$WORK/a4/sub"; conf "$WORK/a4" "{\"spec_archive\": {\"sub\": $OPT}}"
ar "$WORK/a4/sub"
assert_eq "spec_archive names this path → local" local "$ST"
assert_exit "… exit 0" 0 "$RC"
assert_eq "… branch master" master "$(printf '%s' "$OUT" | field branch)"
assert_eq "… and its commit" "$(git -C "$WORK/a4/sub" rev-parse master)" "$(printf '%s' "$OUT" | field ref)"
assert_eq "… key is the path relative to the configuration" sub "$(printf '%s' "$OUT" | field key)"
mkdir -p "$WORK/a4/sub/deeper"
ar "$WORK/a4/sub/deeper"
assert_eq "… also from a directory inside the repository" local "$ST"

mkrepo "$WORK/a5/sub"; conf "$WORK/a5" "{\"spec_archive\": {\"./sub/\": $OPT}}"
ar "$WORK/a5/sub"
assert_eq "the path written as ./sub/ → local" local "$ST"

mkrepo "$WORK/a6/sub"; conf "$WORK/a6" "{\"spec_archive\": {\"sub\": $OPT}}"
git -C "$WORK/a6/sub" remote add origin "$WORK/nowhere.git"
ar "$WORK/a6/sub"
assert_eq "the repository has a remote → error" error "$ST"
assert_exit "… exit 2" 2 "$RC"
assert_grep "… naming the remote" "origin" "$(printf '%s' "$OUT" | field reason)"

mkrepo "$WORK/a7/sub"; conf "$WORK/a7" '{"spec_archive": {"sub": {"ref": "local", "branch": "trunk"}}}'
ar "$WORK/a7/sub"
assert_eq "the branch does not exist → error" error "$ST"

mkrepo "$WORK/a8/sub"; conf "$WORK/a8" '{"spec_archive": {"sub": {"ref": "remote", "branch": "master"}}}'
ar "$WORK/a8/sub"
assert_eq "ref is not local → error" error "$ST"

mkrepo "$WORK/a9/sub"; conf "$WORK/a9" '{"spec_archive": {"sub": {"ref": "local"}}}'
ar "$WORK/a9/sub"
assert_eq "no branch → error" error "$ST"

mkrepo "$WORK/a10/sub"; conf "$WORK/a10" '{"spec_archive": ["sub"]}'
ar "$WORK/a10/sub"
assert_eq "spec_archive is a list → error" error "$ST"

mkrepo "$WORK/a11/sub"; conf "$WORK/a11" '{"spec_archive": '
ar "$WORK/a11/sub"
assert_eq "the file is not JSON → remote (idd-547-fix1)" remote "$ST"
assert_exit "… exit 0" 0 "$RC"
assert_grep "… saying the file could not be read" "not readable" "$(printf '%s' "$OUT" | field reason)"

# idd-547-fix1 rows
mkrepo "$WORK/b1/sub"; mkdir -p "$WORK/b1/.claude/.idd"; : > "$WORK/b1/.claude/.idd/local.json"
ar "$WORK/b1/sub"
assert_eq "an empty configuration file → remote" remote "$ST"
mkrepo "$WORK/b2/sub"; conf "$WORK/b2" 'null'
ar "$WORK/b2/sub"
assert_eq "a configuration holding null → remote" remote "$ST"
mkrepo "$WORK/b3/sub"; mkdir -p "$WORK/b3/.claude/.idd"
printf '\357\273\277%s\n' "{\"spec_archive\": {\"sub\": $OPT}}" > "$WORK/b3/.claude/.idd/local.json"
ar "$WORK/b3/sub"
assert_eq "a UTF-8 byte order mark → read as usual, local" local "$ST"
mkrepo "$WORK/b4/sub"; mkdir -p "$WORK/b4/.claude/.idd"; printf '{"a": "\377"}\n' > "$WORK/b4/.claude/.idd/local.json"
ar "$WORK/b4/sub"
assert_eq "a file that is not valid UTF-8 → remote" remote "$ST"
mkrepo "$WORK/b5/sub"; mkdir -p "$WORK/b5/.claude/.idd"
python3 -c 'print("[" * 100000 + "]" * 100000)' > "$WORK/b5/.claude/.idd/local.json"
ar "$WORK/b5/sub"
assert_eq "a file nested too deeply → remote, not a traceback" remote "$ST"
mkrepo "$WORK/b6/sub"; conf "$WORK/b6" "{\"spec_archive\": {\"sub\": $OPT, \"./sub/\": $OPT}}"
ar "$WORK/b6/sub"
assert_eq "two keys naming the same path → error" error "$ST"
assert_grep "… more than one entry" "more than one entry" "$(printf '%s' "$OUT" | field reason)"
mkrepo "$WORK/b7/sub"; conf "$WORK/b7" '{"spec_archive": {"sub": {"ref": "local", "branch": "master~1"}}}'
git -C "$WORK/b7/sub" commit -q --allow-empty -m second
ar "$WORK/b7/sub"
assert_eq "branch master~1 (revision syntax) → error" error "$ST"
mkrepo "$WORK/b8/sub"; conf "$WORK/b8" '{"spec_archive": {"sub": {"ref": "local", "branch": "master@{0}"}}}'
ar "$WORK/b8/sub"
assert_eq "branch master@{0} → error" error "$ST"
mkrepo "$WORK/b9/sub"; conf "$WORK/b9" "{\"spec_archive\": {\" sub\": $OPT, \"\": $OPT}}"
ar "$WORK/b9/sub"
assert_eq "keys with surrounding whitespace or empty match nothing → remote" remote "$ST"
mkrepo "$WORK/b10/sub"; conf "$WORK/b10" "{\"spec_archive\": {\"sub\": $OPT}}"
printf '[remote "origin"]\n\tprune = true\n' > "$WORK/gitconfig-prune"
OUT=$(GIT_CONFIG_GLOBAL="$WORK/gitconfig-prune" python3 "$SC" archive-ref --cwd "$WORK/b10/sub" 2>/dev/null); ST=$(printf '%s' "$OUT" | field status)
assert_eq "a global remote section without a URL is not a remote → local" local "$ST"
mkrepo "$WORK/b11/sub"; conf "$WORK/b11" "{\"spec_archive\": {\"sub\": $OPT}}"
git -C "$WORK/b11/sub" worktree add -q "$WORK/b11/sub/.claude/worktrees/wt" -b wt 2>/dev/null
ar "$WORK/b11/sub/.claude/worktrees/wt"
assert_eq "asked from a linked worktree of the opted-in repository → local" local "$ST"
assert_eq "… with the main working tree's key" sub "$(printf '%s' "$OUT" | field key)"
mkrepo "$WORK/b12/sub"; conf "$WORK/b12" '{"github_repo": "o/r"}'
printf '%s\n' "{\"spec_archive\": {\"sub\": $OPT}}" > "$WORK/b12/.claude/issue-driven-dev.local.json"
ar "$WORK/b12/sub"
assert_eq "the new file wins over the legacy file at the same level → remote" remote "$ST"
mkdir -p "$WORK/abovehome/.claude/.idd"; printf '%s\n' "{\"spec_archive\": {\"home/sub\": $OPT}}" > "$WORK/abovehome/.claude/.idd/local.json"
mkrepo "$WORK/abovehome/home/sub"
OUT=$(HOME="$WORK/abovehome/home" python3 "$SC" archive-ref --cwd "$WORK/abovehome/home/sub" 2>/dev/null); ST=$(printf '%s' "$OUT" | field status)
assert_eq "a configuration above the home directory is not read → remote" remote "$ST"

# The legacy file name is read too, after the new one at the same level.
mkrepo "$WORK/a12/sub"; mkdir -p "$WORK/a12/.claude"
printf '%s\n' "{\"spec_archive\": {\"sub\": $OPT}}" > "$WORK/a12/.claude/issue-driven-dev.local.json"
ar "$WORK/a12/sub"
assert_eq "the legacy configuration file → local" local "$ST"

# The repository's own configuration, key "."
mkrepo "$WORK/a13"; conf "$WORK/a13" "{\"spec_archive\": {\".\": $OPT}}"
ar "$WORK/a13"
assert_eq "the repository's own configuration, key . → local" local "$ST"

ar "$WORK"
assert_eq "not inside a git repository → error" error "$ST"

echo "spec-archive-local: where the local link check starts"
lb() { OUT=$(cd "$1" && python3 "$SC" link-base --cwd "$1" --issue "$2" 2>/dev/null); RC=$?; ST=$(printf '%s' "$OUT" | field status); }
B="$WORK/lb1/repo"; mkrepo "$B"; conf "$WORK/lb1" "{\"spec_archive\": {\"repo\": $OPT}}"
git -C "$B" commit -q --allow-empty -m "tagged"; git -C "$B" tag idd-14-baseline
TAGGED=$(git -C "$B" rev-parse HEAD)
git -C "$B" commit -q --allow-empty -m "a (#14)"
lb "$B" 14
assert_eq "tag on an ancestor of HEAD → ok" ok "$ST"
assert_eq "… the tag's commit" "$TAGGED" "$(printf '%s' "$OUT" | field base)"
assert_eq "… from baseline-tag" baseline-tag "$(printf '%s' "$OUT" | field from)"

B="$WORK/lb2/repo"; mkrepo "$B"; conf "$WORK/lb2" "{\"spec_archive\": {\"repo\": $OPT}}"
BASE=$(git -C "$B" rev-parse HEAD)
git -C "$B" commit -q --allow-empty -m "a (#14)"; git -C "$B" commit -q --allow-empty -m $'b\n\nRefs #14'
lb "$B" 14
assert_eq "no tag; the parent of the first commit naming #14 → ok" ok "$ST"
assert_eq "… the commit before it" "$BASE" "$(printf '%s' "$OUT" | field base)"
assert_eq "… from first-commit" first-commit "$(printf '%s' "$OUT" | field from)"

B="$WORK/lb3/repo"; mkrepo "$B"; conf "$WORK/lb3" "{\"spec_archive\": {\"repo\": $OPT}}"
git -C "$B" commit -q --allow-empty -m "a (#142)"
lb "$B" 14
assert_eq "only #142 names a 14 → error" error "$ST"
assert_exit "… exit 2" 2 "$RC"

B="$WORK/lb4/repo"; mkdir -p "$B"; git init -q -b master "$B"; conf "$WORK/lb4" "{\"spec_archive\": {\"repo\": $OPT}}"
git -C "$B" commit -q --allow-empty -m "start (#14)"
lb "$B" 14
assert_eq "the first commit with #14 is the root commit → error" error "$ST"

B="$WORK/lb5/repo"; mkrepo "$B"
git -C "$B" commit -q --allow-empty -m "a (#14)"
lb "$B" 14
assert_eq "not opted in → remote" remote "$ST"
assert_exit "… exit 0" 0 "$RC"

lb "$WORK/lb2/repo" 14x
assert_eq "an issue number that is not digits → error" error "$ST"
assert_exit "… exit 2" 2 "$RC"

# idd-547-fix1 rows
lb "$WORK/lb5/repo" abc
assert_eq "not opted in, --issue abc → remote (the issue is not read)" remote "$ST"
assert_exit "… exit 0" 0 "$RC"

B="$WORK/lb6/repo"; mkrepo "$B"; conf "$WORK/lb6" "{\"spec_archive\": {\"repo\": $OPT}}"
git -C "$B" commit -q --allow-empty -m "see o/r#14"; git -C "$B" commit -q --allow-empty -m "x#14"
BEFORE=$(git -C "$B" rev-parse HEAD); git -C "$B" commit -q --allow-empty -m "fix (#14)"
lb "$B" 14
assert_eq "o/r#14 and x#14 do not count; the parent of 'fix (#14)'" "$BEFORE" "$(printf '%s' "$OUT" | field base)"

B="$WORK/lb7/repo"; mkrepo "$B"; conf "$WORK/lb7" "{\"spec_archive\": {\"repo\": $OPT}}"
BASE=$(git -C "$B" rev-parse HEAD)
git -C "$B" checkout -q -b side; git -C "$B" commit -q --allow-empty -m side; git -C "$B" tag idd-14-baseline; git -C "$B" checkout -q master
git -C "$B" commit -q --allow-empty -m "a (#14)"
lb "$B" 14
assert_eq "a baseline tag that is not an ancestor of HEAD → falls back to the first commit" "$BASE" "$(printf '%s' "$OUT" | field base)"
assert_eq "… from first-commit" first-commit "$(printf '%s' "$OUT" | field from)"

B="$WORK/lb8/repo"; mkrepo "$B"; conf "$WORK/lb8" "{\"auto_tag\": {\"baseline_format\": \"start-{N}\"}, \"spec_archive\": {\"repo\": $OPT}}"
git -C "$B" commit -q --allow-empty -m "tagged"; git -C "$B" tag start-14; T=$(git -C "$B" rev-parse HEAD)
git -C "$B" commit -q --allow-empty -m "a (#14)"
lb "$B" 14
assert_eq "auto_tag.baseline_format start-{N} → that tag" "$T" "$(printf '%s' "$OUT" | field base)"
assert_eq "… from baseline-tag" baseline-tag "$(printf '%s' "$OUT" | field from)"

B="$WORK/lb9/repo"; mkrepo "$B"; conf "$WORK/lb9" "{\"spec_archive\": {\"repo\": $OPT}}"
git -C "$B" commit -q --allow-empty -m "$(printf 'odd \036 byte')"; BEFORE=$(git -C "$B" rev-parse HEAD)
git -C "$B" commit -q --allow-empty -m "a (#14)"
lb "$B" 14
assert_eq "a 0x1e byte in an earlier message does not hide a commit" "$BEFORE" "$(printf '%s' "$OUT" | field base)"

# archive-ref reports the configured branch, not HEAD (idd-547-fix1)
git -C "$WORK/a4/sub" checkout -q -b elsewhere; git -C "$WORK/a4/sub" commit -q --allow-empty -m elsewhere
ar "$WORK/a4/sub"
assert_eq "HEAD on another branch → ref is still master's commit" "$(git -C "$WORK/a4/sub" rev-parse master)" "$(printf '%s' "$OUT" | field ref)"
git -C "$WORK/a4/sub" checkout -q master

# idd-547-fix2 rows — how a spec_archive entry resolves
mkdir -p "$WORK/c1"; conf "$WORK/c1" "{\"spec_archive\": {\".\": $OPT}}"; git init -q -b master "$WORK/c1"; git -C "$WORK/c1" commit -q --allow-empty -m base
mkrepo "$WORK/c1/odd "
ar "$WORK/c1/odd "
assert_eq "a repository whose path cannot be a key does not fall back to . → remote" remote "$ST"
mkrepo "$WORK/c2/sub"; mkdir -p "$WORK/c2/.claude/.idd"
printf '{"spec_archive": {"sub": %s, "sub": %s}}\n' "$OPT" "$OPT" > "$WORK/c2/.claude/.idd/local.json"
ar "$WORK/c2/sub"
assert_eq "the same key written twice in the file → error" error "$ST"
mkrepo "$WORK/c3/sub"; conf "$WORK/c3" "{\"spec_archive\": {\"sub\": $OPT}}"; git -C "$WORK/c3/sub" config remote.origin.pushurl "$WORK/nowhere.git"
ar "$WORK/c3/sub"
assert_eq "a remote with only a pushurl counts → error" error "$ST"
assert_grep "… naming it" "origin" "$(printf '%s' "$OUT" | field reason)"
mkrepo "$WORK/c4/sub"; conf "$WORK/c4" "{\"spec_archive\": {\"sub\": $OPT}}"; mkdir -p "$WORK/c4/sub/.git/remotes"
printf 'URL: %s\n' "$WORK/nowhere.git" > "$WORK/c4/sub/.git/remotes/origin"
ar "$WORK/c4/sub"
assert_eq "a legacy remotes/origin file counts → error" error "$ST"
mkdir -p "$WORK/c5" "$WORK/c5gd"; conf "$WORK/c5" "{\"spec_archive\": {\"sub\": $OPT}}"
git init -q -b master --separate-git-dir "$WORK/c5gd/.git" "$WORK/c5/sub"; git -C "$WORK/c5/sub" commit -q --allow-empty -m base
ar "$WORK/c5/sub"
assert_eq "a repository made with --separate-git-dir is keyed by its top level → local" local "$ST"
OUT=$(python3 "$SC" archive-ref --cwd "$WORK/a3/sub" 2>/dev/null)
refute_grep "reasons do not carry the configuration's absolute path" "$WORK/a3/.claude" "$(printf '%s' "$OUT" | field reason)"

# idd-547-fix2 rows — where the local link check starts
B="$WORK/ld1/repo"; mkrepo "$B"; conf "$WORK/ld1" "{\"github_repo\": \"o/issues\", \"spec_archive\": {\"repo\": $OPT}}"
git -C "$B" commit -q --allow-empty -m "see other/r#14"; BEFORE=$(git -C "$B" rev-parse HEAD)
git -C "$B" commit -q --allow-empty -m "fix (O/ISSUES#14)"
lb "$B" 14
assert_eq "github_repo o/issues: O/ISSUES#14 counts, other/r#14 does not" "$BEFORE" "$(printf '%s' "$OUT" | field base)"
B="$WORK/ld2/repo"; mkrepo "$B"; conf "$WORK/ld2" "{\"spec_archive\": {\"repo\": $OPT}}"; BASE=$(git -C "$B" rev-parse HEAD)
git -C "$B" commit -q --allow-empty -m "a (#14)"; git -C "$B" tag idd-14-baseline
lb "$B" 14
assert_eq "a baseline tag on HEAD itself → falls back to the first commit" "$BASE" "$(printf '%s' "$OUT" | field base)"
assert_eq "… from first-commit" first-commit "$(printf '%s' "$OUT" | field from)"
B="$WORK/ld3/repo"; mkrepo "$B"; conf "$WORK/ld3" "{\"spec_archive\": {\"repo\": $OPT}}"
# A commit carrying a (fake) signature, and log.showSignature pointing at a program that leaves a sentinel
# (the pattern of merge-completeness fixture 40b). Without --no-show-signature git log runs it and prints its text.
mkdir -p "$WORK/fakegpg"; printf '#!/bin/sh\ntouch "%s/ran"\necho "gpg: Signature made by fake"\nexit 1\n' "$WORK/fakegpg" > "$WORK/fakegpg/gpg"
python3 -c 'import os,sys; os.chmod(sys.argv[1], 0o755)' "$WORK/fakegpg/gpg"
git -C "$B" commit -q --allow-empty -m signed
SIGNED=$(git -C "$B" cat-file commit HEAD | awk 'NR == 1 { print; next } !done && /^committer / { print; print "gpgsig -----BEGIN PGP SIGNATURE-----"; print " Zm9v"; print " -----END PGP SIGNATURE-----"; done = 1; next } { print }' \
  | git -C "$B" hash-object -t commit -w --stdin)
git -C "$B" update-ref refs/heads/master "$SIGNED"
git -C "$B" config log.showSignature true; git -C "$B" config gpg.program "$WORK/fakegpg/gpg"
BEFORE=$(git -C "$B" rev-parse HEAD); git -C "$B" commit -q --allow-empty -m "a (#14)"
lb "$B" 14
assert_eq "log.showSignature on, a signed commit before → still the parent of a (#14)" "$BEFORE" "$(printf '%s' "$OUT" | field base)"
assert_exit "… and gpg.program is not run" 1 "$([ -e "$WORK/fakegpg/ran" ]; echo $?)"
B="$WORK/ld4/repo"; mkrepo "$B"; conf "$WORK/ld4" "{\"spec_archive\": {\"repo\": $OPT}}"; BASE=$(git -C "$B" rev-parse HEAD)
echo x > "$B/HEAD"; git -C "$B" add HEAD; git -C "$B" commit -q -m "a (#14)"
lb "$B" 14
assert_eq "a file named HEAD at the top level → still ok" "$BASE" "$(printf '%s' "$OUT" | field base)"

echo "spec-archive-local: the wrapper and idd-all text"
WRAP="$PLUGIN/references/spec-wrapper.md"
STEP5=$(sed -n '/^## 5\. Close-out/,/^## 6\./p' "$WRAP")
assert_grep "spec-wrapper step 5 asks link-base" 'spec-change.py" link-base' "$STEP5"
assert_grep "… with the issue number from NUMBER or N" '${NUMBER:-${N:-}}' "$STEP5"
refute_grep "step 5's JSON readers run isolated: no python3 -c without -I (idd-547-fix2)" "python3 -c 'import json" "$STEP5"
# idd-547-fix2: run the step-5 block as written. In local mode a link-base error stops with its reason and
# does not go on to print the failed-fetch message.
printf '%s\n' "$STEP5" | awk '/^```bash$/{b=1; next} b && /^```$/{exit} b' > "$WORK/step5.sh"
S5OUT=$(cd "$WORK/lb3/repo" && env HOME="$WORK" CWD="$WORK/lb3/repo" NUMBER=14 GITHUB_REPO=o/r CLAUDE_PLUGIN_ROOT="$PLUGIN" \
  bash --norc --noprofile "$WORK/step5.sh" 2>&1 </dev/null)
assert_grep "step 5, local mode, no base found → stops with the archive-ref reason" "archive-ref:" "$S5OUT"
refute_grep "… without the failed-fetch message" "cannot find where this branch left" "$S5OUT"
S5OK=$(cd "$WORK/lb2/repo" && env HOME="$WORK" CWD="$WORK/lb2/repo" NUMBER=14 GITHUB_REPO=o/r CLAUDE_PLUGIN_ROOT="$PLUGIN" \
  bash --norc --noprofile "$WORK/step5.sh" 2>&1 </dev/null)
assert_grep "step 5, local mode with a base → runs the link check from it" "link check from" "$S5OK"
assert_grep "idd-all Step 3b.6 names link-base for the local mode" "link-base" "$(sed -n '/^#### Step 3b.6/,/^---/p' "$PLUGIN/skills/idd-all/SKILL.md")"

print_summary spec-archive-local
