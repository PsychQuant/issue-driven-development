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
assert_eq "the file is not JSON → error" error "$ST"
assert_exit "… exit 2" 2 "$RC"

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

print_summary spec-archive-local
