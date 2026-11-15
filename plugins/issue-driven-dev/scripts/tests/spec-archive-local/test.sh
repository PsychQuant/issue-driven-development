#!/usr/bin/env bash
# spec-archive-local suite (#547) — a repository without a remote can opt into its local
# default branch: `spec-change.py archive-ref` decides which branch the spec checks read,
# `spec-change.py link-base` gives the base of the link check in that mode.
#
# spec-example: spec-on-every-issue / how a spec_archive entry resolves
# spec-example: spec-on-every-issue / where the local link check starts
# spec-example: spec-on-every-issue / a top level whose name ends in whitespace
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
assert_grep "… not a branch name (idd-547-fix4)" "is not a branch name" "$(printf '%s' "$OUT" | field reason)"
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
assert_grep "… more than one entry (idd-547-fix3)" "more than one entry" "$(printf '%s' "$OUT" | field reason)"
mkrepo "$WORK/c3/sub"; conf "$WORK/c3" "{\"spec_archive\": {\"sub\": $OPT}}"; git -C "$WORK/c3/sub" config remote.origin.pushurl "$WORK/nowhere.git"
ar "$WORK/c3/sub"
assert_eq "a remote with only a pushurl counts → error" error "$ST"
assert_grep "… naming it" "origin" "$(printf '%s' "$OUT" | field reason)"
mkrepo "$WORK/c4/sub"; conf "$WORK/c4" "{\"spec_archive\": {\"sub\": $OPT}}"; mkdir -p "$WORK/c4/sub/.git/remotes"
printf 'URL: %s\n' "$WORK/nowhere.git" > "$WORK/c4/sub/.git/remotes/origin"
ar "$WORK/c4/sub"
assert_eq "a legacy remotes/origin file counts → error" error "$ST"
assert_grep "… naming the remote (idd-547-fix3)" "origin" "$(printf '%s' "$OUT" | field reason)"
mkdir -p "$WORK/c5" "$WORK/c5gd"; conf "$WORK/c5" "{\"spec_archive\": {\"sub\": $OPT}}"
git init -q -b master --separate-git-dir "$WORK/c5gd/.git" "$WORK/c5/sub"; git -C "$WORK/c5/sub" commit -q --allow-empty -m base
ar "$WORK/c5/sub"
assert_eq "a repository made with --separate-git-dir is keyed by its top level → local" local "$ST"
assert_eq "… with the key sub (idd-547-fix3)" sub "$(printf '%s' "$OUT" | field key)"
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

# idd-547-fix3 rows — how a spec_archive entry resolves
mkdir -p "$WORK/d1" "$WORK/d1gd"; conf "$WORK/d1" "{\"spec_archive\": {\"sub\": $OPT}}"
git init -q -b master --separate-git-dir "$WORK/d1gd/meta.git" "$WORK/d1/sub"; git -C "$WORK/d1/sub" commit -q --allow-empty -m base
git -C "$WORK/d1/sub" worktree add -q "$WORK/d1/wt" -b wt 2>/dev/null
ar "$WORK/d1/wt"
assert_eq "a linked worktree of a --separate-git-dir main tree → remote (no key is guessed)" remote "$ST"
assert_eq "… has_remote false (callers stop)" False "$(printf '%s' "$OUT" | field has_remote)"
assert_grep "… saying the main working tree is not recorded" "main working tree" "$(printf '%s' "$OUT" | field reason)"
# its own path is never used as the key: an entry under that name is not read
conf "$WORK/d1" "{\"spec_archive\": {\"wt\": $OPT}}"
ar "$WORK/d1/wt"
assert_eq "… even when an entry names the linked worktree's own path → remote" remote "$ST"
assert_eq "… has_remote false (idd-547-fix4)" False "$(printf '%s' "$OUT" | field has_remote)"
assert_grep "… saying the main working tree is not recorded (idd-547-fix4)" "main working tree" "$(printf '%s' "$OUT" | field reason)"
ar "$WORK/d1/sub"
assert_eq "the --separate-git-dir main working tree itself, no entry for sub → remote" remote "$ST"
mkrepo "$WORK/d2/sub"; mkdir -p "$WORK/d2/.claude/.idd"
printf '{"spec_archive": {"sub": %s}, "spec_archive": {"sub": %s}}\n' "$OPT" "$OPT" > "$WORK/d2/.claude/.idd/local.json"
ar "$WORK/d2/sub"
assert_eq "spec_archive written twice at the top level → error" error "$ST"
assert_grep "… more than one entry" "more than one entry" "$(printf '%s' "$OUT" | field reason)"
mkrepo "$WORK/d3/sub"; mkdir -p "$WORK/d3/.claude/.idd"
printf '{"spec_archive": {"sub": {"ref": "local", "branch": "master", "branch": "master"}}}\n' > "$WORK/d3/.claude/.idd/local.json"
ar "$WORK/d3/sub"
assert_eq "a key written twice inside the entry → error" error "$ST"
assert_grep "… more than one entry (idd-547-fix4)" "more than one entry" "$(printf '%s' "$OUT" | field reason)"
mkrepo "$WORK/d4/sub"; mkdir -p "$WORK/d4/.claude/.idd"
printf '{"spec_archive": {"sub": %s, "\\u0000duplicate-keys": ["sub"]}, "\\u0000duplicate-keys": ["spec_archive"]}\n' "$OPT" > "$WORK/d4/.claude/.idd/local.json"
ar "$WORK/d4/sub"
assert_eq "a key that looks like an internal marker does not imitate a duplicate → local" local "$ST"
mkrepo "$WORK/d5/sub"; conf "$WORK/d5" '{"spec_archive": null}'; git -C "$WORK/d5/sub" remote add origin "$WORK/nowhere.git"
ar "$WORK/d5/sub"
assert_eq "spec_archive null → remote" remote "$ST"
assert_eq "… has_remote true" True "$(printf '%s' "$OUT" | field has_remote)"
mkrepo "$WORK/d6/sub"; conf "$WORK/d6" "{\"spec_archive\": {\"sub\": $OPT}}"; git -C "$WORK/d6/sub" config remote.origin.vcs hg
ar "$WORK/d6/sub"
assert_eq "a remote with only a vcs counts → error" error "$ST"
assert_grep "… naming it" "origin" "$(printf '%s' "$OUT" | field reason)"
ar "$WORK/none/sub"
assert_eq "no configuration, no remote → has_remote false" False "$(printf '%s' "$OUT" | field has_remote)"

# idd-547-fix3 rows — where the local link check starts
B="$WORK/le1/repo"; mkrepo "$B"; conf "$WORK/le1" "{\"spec_archive\": {\"repo\": $OPT}}"; BASE=$(git -C "$B" rev-parse HEAD)
git -C "$B" commit -q --allow-empty -m "a (#14)"; git -C "$B" config i18n.logOutputEncoding UTF-16
lb "$B" 14
assert_eq "i18n.logOutputEncoding UTF-16 → still the commit before a (#14)" "$BASE" "$(printf '%s' "$OUT" | field base)"

# idd-547-fix3 — a top level whose name ends in a space
mkdir -p "$WORK/sp"; git init -q -b main "$WORK/sp/odd "; git init -q -b main "$WORK/sp/odd"
for r in "$WORK/sp/odd " "$WORK/sp/odd"; do mkdir -p "$r/openspec/specs"; echo x > "$r/openspec/specs/.keep"; git -C "$r" add -A; git -C "$r" commit -q -m base; done
mkdir -p "$WORK/sp/odd /openspec/changes/archive/2026-11-14-idd-9-c1"; echo p > "$WORK/sp/odd /openspec/changes/archive/2026-11-14-idd-9-c1/proposal.md"
git -C "$WORK/sp/odd " add -A; git -C "$WORK/sp/odd " commit -q -m "archive c1"
mkdir -p "$WORK/sp/odd/openspec/changes/idd-9-c1"; echo p > "$WORK/sp/odd/openspec/changes/idd-9-c1/proposal.md"; git -C "$WORK/sp/odd" add -A; git -C "$WORK/sp/odd" commit -q -m "open c1"
printf '%s\n' '<!-- idd:comment type=implementation-complete -->' '**Spec**: change idd-9-c1' > "$WORK/sp/ic.md"
OUT=$(python3 "$SC" archived --file "$WORK/sp/ic.md" --cwd "$WORK/sp/odd " --ref HEAD 2>/dev/null)
assert_eq "archived on 'odd ' with a sibling 'odd' → reads 'odd ' (pass)" pass "$(printf '%s' "$OUT" | field status)"
mv "$WORK/sp/odd" "$WORK/sp/away"
OUT=$(python3 "$SC" archived --file "$WORK/sp/ic.md" --cwd "$WORK/sp/odd " --ref HEAD 2>/dev/null)
assert_eq "archived on 'odd ' alone → pass" pass "$(printf '%s' "$OUT" | field status)"
mv "$WORK/sp/away" "$WORK/sp/odd"
SPB=$(git -C "$WORK/sp/odd " rev-parse HEAD); git -C "$WORK/sp/odd " checkout -q -b feat
mkdir -p "$WORK/sp/odd /openspec/specs/cap"; printf '## Purpose\n\nx\n\n## Requirements\n\n### Requirement: Something new\n\nIt SHALL do it.\n' > "$WORK/sp/odd /openspec/specs/cap/spec.md"
git -C "$WORK/sp/odd " add -A; git -C "$WORK/sp/odd " commit -q -m "add a spec"
OUT=$(python3 "$SC" links --base "$SPB" --cwd "$WORK/sp/odd " 2>/dev/null)
assert_eq "links on 'odd ' with a sibling 'odd' → missing (reads 'odd ')" missing "$(printf '%s' "$OUT" | field status)"
# idd-547-fix4: a top level whose name ends in a newline, with a sibling without it
NL="$WORK/sp/nl"$'\n'
git init -q -b main "$NL"; mkdir -p "$NL/openspec/specs"; echo x > "$NL/openspec/specs/.keep"; git -C "$NL" add -A; git -C "$NL" commit -q -m base
mkdir -p "$NL/openspec/changes/archive/2026-11-14-idd-9-c1"; echo p > "$NL/openspec/changes/archive/2026-11-14-idd-9-c1/proposal.md"
git -C "$NL" add -A; git -C "$NL" commit -q -m "archive c1"
git init -q -b main "$WORK/sp/nl"; mkdir -p "$WORK/sp/nl/openspec/changes/idd-9-c1"; echo p > "$WORK/sp/nl/openspec/changes/idd-9-c1/proposal.md"
git -C "$WORK/sp/nl" add -A; git -C "$WORK/sp/nl" commit -q -m "open c1"
OUT=$(python3 "$SC" archived --file "$WORK/sp/ic.md" --cwd "$NL" --ref HEAD 2>/dev/null)
assert_eq "archived on a top level ending in a newline, with a sibling without it → reads itself (pass)" pass "$(printf '%s' "$OUT" | field status)"
# preflight, too (round 4 pre-check): 'pf ' has openspec/, its sibling 'pf' does not; a stub spectra on PATH
mkdir -p "$WORK/stubsp"; printf '#!/bin/sh\nexit 0\n' > "$WORK/stubsp/spectra"; python3 -c 'import os,sys; os.chmod(sys.argv[1], 0o755)' "$WORK/stubsp/spectra"
git init -q -b main "$WORK/sp/pf "; git -C "$WORK/sp/pf " commit -q --allow-empty -m base; mkdir -p "$WORK/sp/pf /openspec/specs"
git init -q -b main "$WORK/sp/pf"; git -C "$WORK/sp/pf" commit -q --allow-empty -m base
OUT=$(PATH="$WORK/stubsp:$PATH" python3 "$SC" preflight --cwd "$WORK/sp/pf " --can-write yes 2>/dev/null)
assert_eq "preflight on 'pf ' with a sibling 'pf' → reads 'pf ' (ready)" ready "$(printf '%s' "$OUT" | field status)"
mv "$WORK/sp/pf" "$WORK/sp/pf-away"
OUT=$(PATH="$WORK/stubsp:$PATH" python3 "$SC" preflight --cwd "$WORK/sp/pf " --can-write yes 2>/dev/null)
assert_eq "preflight on 'pf ' alone → ready" ready "$(printf '%s' "$OUT" | field status)"

# idd-547-fix4 rows — how a spec_archive entry resolves
for U in " " ""; do
  R="$WORK/u$([ -z "$U" ] && echo e || echo s)"; mkrepo "$R/sub"; conf "$R" "{\"spec_archive\": {\"sub\": $OPT}}"
  git -C "$R/sub" config remote.origin.url "$U"
  ar "$R/sub"
  assert_eq "a remote whose url is '$U' counts → error" error "$ST"
  assert_grep "… naming it" "origin" "$(printf '%s' "$OUT" | field reason)"
done
# a bare main repository: its linked worktree is keyed by its own path
mkdir -p "$WORK/bare"; git init -q --bare -b master "$WORK/bare/main.git"
git clone -q "$WORK/bare/main.git" "$WORK/bare/seed" 2>/dev/null; git -C "$WORK/bare/seed" commit -q --allow-empty -m base
git -C "$WORK/bare/seed" push -q origin HEAD:master 2>/dev/null
git -C "$WORK/bare/main.git" worktree add -q "$WORK/bare/wt" master 2>/dev/null
conf "$WORK/bare" "{\"spec_archive\": {\"wt\": $OPT}}"
ar "$WORK/bare/wt"
assert_eq "a linked worktree of a bare repository → local" local "$ST"
assert_eq "… keyed by its own path" wt "$(printf '%s' "$OUT" | field key)"
# --separate-git-dir <dir>/.git: git reports <dir> as the main working tree, and that path is the key
mkdir -p "$WORK/sg/store" "$WORK/sg/iss"; conf "$WORK/sg" "{\"spec_archive\": {\"store\": $OPT}}"
git init -q -b master --separate-git-dir "$WORK/sg/store/.git" "$WORK/sg/iss/sub"; git -C "$WORK/sg/iss/sub" commit -q --allow-empty -m base
git -C "$WORK/sg/iss/sub" worktree add -q "$WORK/sg/wt" -b wt 2>/dev/null
ar "$WORK/sg/wt"
assert_eq "a linked worktree of a --separate-git-dir <dir>/.git repository → keyed by <dir>" store "$(printf '%s' "$OUT" | field key)"
assert_eq "… local, the same repository's master" "$(git -C "$WORK/sg/iss/sub" rev-parse master)" "$(printf '%s' "$OUT" | field ref)"

echo "spec-archive-local: the wrapper and idd-all text"
WRAP="$PLUGIN/references/spec-wrapper.md"
STEP5=$(sed -n '/^## 5\. Close-out/,/^## 6\./p' "$WRAP")
assert_grep "spec-wrapper step 5 asks link-base" 'spec-change.py" link-base' "$STEP5"
assert_grep "… with the issue number from NUMBER or N" '${NUMBER:-${N:-}}' "$STEP5"
refute_grep "step 5's JSON readers run isolated: no python3 -c without -I (idd-547-fix2)" "python3 -c 'import json" "$STEP5"
# idd-547-fix2: run the step-5 block as written. In local mode a link-base error stops with its reason and
# does not go on to print the failed-fetch message.
mkdir -p "$WORK/ghok"; printf '#!/bin/sh\ncase "$1 $2" in "repo view") echo main ;; *) exit 1 ;; esac\n' > "$WORK/ghok/gh"
python3 -c 'import os,sys; os.chmod(sys.argv[1], 0o755)' "$WORK/ghok/gh"
printf '%s\n' "$STEP5" | awk '/^```bash$/{b=1; next} b && /^```$/{exit} b' > "$WORK/step5.sh"
S5OUT=$(cd "$WORK/lb3/repo" && env HOME="$WORK" CWD="$WORK/lb3/repo" NUMBER=14 GITHUB_REPO=o/r CLAUDE_PLUGIN_ROOT="$PLUGIN" \
  bash --norc --noprofile "$WORK/step5.sh" 2>&1 </dev/null)
assert_grep "step 5, local mode, no base found → stops with the link-base reason" "link-base:" "$S5OUT"
refute_grep "… without the failed-fetch message" "cannot find where this branch left" "$S5OUT"
S5OK=$(cd "$WORK/lb2/repo" && env HOME="$WORK" CWD="$WORK/lb2/repo" NUMBER=14 GITHUB_REPO=o/r CLAUDE_PLUGIN_ROOT="$PLUGIN" \
  bash --norc --noprofile "$WORK/step5.sh" 2>&1 </dev/null)
assert_grep "step 5, local mode with a base → runs the link check from it" "link check from" "$S5OK"
# idd-547-fix4: step 5 on a repository with a fetchable origin and no entry → the fetch, merge-base and links path
RM="$WORK/rm"; git init -q --bare -b main "$RM/o.git"; git clone -q "$RM/o.git" "$RM/c" 2>/dev/null
git -C "$RM/c" checkout -q -B main; mkdir -p "$RM/c/openspec/specs"; echo x > "$RM/c/openspec/specs/.keep"
git -C "$RM/c" add -A; git -C "$RM/c" commit -q -m base; git -C "$RM/c" push -q origin main 2>/dev/null
git -C "$RM/c" checkout -q -b feat; git -C "$RM/c" commit -q --allow-empty -m "work (#14)"
S5RM=$(cd "$RM/c" && env HOME="$WORK" CWD="$RM/c" NUMBER=14 GITHUB_REPO=o/r CLAUDE_PLUGIN_ROOT="$PLUGIN" \
  PATH="$WORK/ghok:$PATH" bash --norc --noprofile "$WORK/step5.sh" 2>&1 </dev/null)
assert_grep "step 5, a remote and no entry → runs links from the merge-base with the fetched default branch" '"status": "ok"' "$S5RM"
refute_grep "… without saying the repository has no remote" "has no remote" "$S5RM"
assert_eq "… the default branch was fetched" "$(git -C "$RM/o.git" rev-parse main)" "$(git -C "$RM/c" rev-parse -q --verify FETCH_HEAD 2>/dev/null)"
git -C "$RM/c" remote set-url origin "$RM/nowhere.git"
S5RF=$(cd "$RM/c" && env HOME="$WORK" CWD="$RM/c" NUMBER=14 GITHUB_REPO=o/r CLAUDE_PLUGIN_ROOT="$PLUGIN" \
  PATH="$WORK/ghok:$PATH" bash --norc --noprofile "$WORK/step5.sh" 2>&1 </dev/null)
assert_grep "step 5, the fetch fails → stops with the failed-fetch message" "cannot find where this branch left" "$S5RF"
assert_grep "… and link-base's reason" "link-base:" "$S5RF"
# idd-547-fix3: no entry and no remote, a repository named origin inside it → no fetch, stops saying why
git clone -q --bare "$WORK/none/sub" "$WORK/none/sub/origin" 2>/dev/null
git -C "$WORK/none/sub/origin" branch -q main master   # fetchable: only has_remote keeps the fetch from running
S5NR=$(cd "$WORK/none/sub" && env HOME="$WORK" CWD="$WORK/none/sub" NUMBER=14 GITHUB_REPO=o/r CLAUDE_PLUGIN_ROOT="$PLUGIN" \
  PATH="$WORK/ghok:$PATH" bash --norc --noprofile "$WORK/step5.sh" 2>&1 </dev/null)
assert_grep "step 5, no remote and no entry → stops saying the repository has no remote" "has no remote" "$S5NR"
assert_grep "… with the link-base label" "link-base:" "$S5NR"
refute_grep "… and runs no link check" "link check from" "$S5NR"
assert_eq "… and fetched nothing" "" "$(git -C "$WORK/none/sub" rev-parse -q --verify FETCH_HEAD 2>/dev/null)"
assert_grep "idd-all Step 3b.6 names link-base for the local mode" "link-base" "$(sed -n '/^#### Step 3b.6/,/^---/p' "$PLUGIN/skills/idd-all/SKILL.md")"

print_summary spec-archive-local
