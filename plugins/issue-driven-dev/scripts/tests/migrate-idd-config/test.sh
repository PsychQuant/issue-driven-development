#!/usr/bin/env bash
# Test: migrate-idd-config.sh moves legacy config without destroying anything (#303).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$(cd "$HERE/../.." && pwd)/migrate-idd-config.sh"
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"

S=$(mktemp -d)
trap 'rm -rf "$S"' EXIT
mkdir -p "$S/a/.claude" "$S/b/.claude/.idd" "$S/n/node_modules/x/.claude"
echo '{"github_repo":"o/a"}'        > "$S/a/.claude/issue-driven-dev.local.json"
echo '{"github_repo":"o/b-legacy"}' > "$S/b/.claude/issue-driven-dev.local.json"
echo '{"github_repo":"o/b-cur"}'    > "$S/b/.claude/.idd/local.json"
echo '{"github_repo":"o/noise"}'    > "$S/n/node_modules/x/.claude/issue-driven-dev.local.json"

SCAN=$(bash "$SCRIPT" --scan "$S" 2>&1); SRC=$?
assert_exit "scan exits 0" 0 "$SRC"
assert_grep    "scan reports the migratable repo"        "would migrate" "$SCAN"
refute_grep    "scan does not write anything"            "✓ migrated"    "$SCAN"
refute_grep    "node_modules is pruned, not reported"    "noise"         "$SCAN"
require "scan left the legacy file in place" \
  test -f "$S/a/.claude/issue-driven-dev.local.json"

OUT=$(bash "$SCRIPT" --apply "$S" 2>&1); ARC=$?
assert_exit "apply exits 0 when nothing failed" 0 "$ARC"
require "legacy file moved to the current path" test -f "$S/a/.claude/.idd/local.json"
refute  "legacy file no longer at the old path" test -f "$S/a/.claude/issue-driven-dev.local.json"
require "a breadcrumb is left behind"           test -f "$S/a/.claude/issue-driven-dev.local.json.moved"

# The destructive case this script must never do: clobber an existing current
# config with a stale legacy one. Both present -> leave both alone.
assert_grep "both-present is reported, not migrated" "both present" "$OUT"
require "existing current config is untouched" \
  bash -c 'grep -q "b-cur" "$0/b/.claude/.idd/local.json"' "$S"
require "its legacy sibling is also left in place" \
  test -f "$S/b/.claude/issue-driven-dev.local.json"

# node_modules must stay pruned even on apply
require "node_modules config was not touched" \
  test -f "$S/n/node_modules/x/.claude/issue-driven-dev.local.json"

# ─────────────────────────────────────────────────────────────────────────────
# Hostile tree. Everything below is a shape the script must REFUSE rather than
# handle: the destination or the breadcrumb path is not the ordinary regular
# file the happy path assumes. These live in their own root and get their own
# --apply run, because a refusal is a failure (exit 1) and mixing them into the
# tree above would make the "apply exits 0" assertion vacuous.
#
# Every case here is a real filesystem shape an attacker (or a careless symlink
# farm) can plant inside a repo you scan. `--apply` defaults to walking ALL of
# ~/Developer, so "a repo I cloned" is inside the threat model.
# ─────────────────────────────────────────────────────────────────────────────
H=$(mktemp -d); OUTSIDE=$(mktemp -d)
trap 'rm -rf "$S" "$H" "$OUTSIDE"' EXIT
L="issue-driven-dev.local.json"

# H1 — .idd is a symlink to a directory outside the repo. `mkdir -p` accepts an
# existing symlink-to-dir silently, so the move follows it and the config lands
# outside the tree the user was told it would stay in.
mkdir -p "$H/h1/.claude" "$OUTSIDE/exfil"
echo '{"github_repo":"o/h1"}' > "$H/h1/.claude/$L"
ln -s "$OUTSIDE/exfil" "$H/h1/.claude/.idd"

# H2 — the breadcrumb path is a symlink to a file the user cares about. `>` and
# `>>` both follow symlinks, so writing the breadcrumb truncates the target.
mkdir -p "$H/h2/.claude"
echo '{"github_repo":"o/h2"}' > "$H/h2/.claude/$L"
printf 'precious\n' > "$OUTSIDE/victim.txt"
ln -s "$OUTSIDE/victim.txt" "$H/h2/.claude/$L.moved"

# H2b — the same, but DANGLING. `[ -e ]` is false for a broken link, so the
# existing "already exists" guard does not fire and `>` CREATES the target.
mkdir -p "$H/h2b/.claude"
echo '{"github_repo":"o/h2b"}' > "$H/h2b/.claude/$L"
ln -s "$OUTSIDE/planted.txt" "$H/h2b/.claude/$L.moved"

# H3 — the destination exists as a DIRECTORY. `[ -f ]` is false for it, so the
# both-present branch is skipped and `mv` moves the file INSIDE it, producing
# .idd/local.json/issue-driven-dev.local.json while reporting "✓ migrated".
mkdir -p "$H/h3/.claude/.idd/local.json"
echo '{"github_repo":"o/h3"}' > "$H/h3/.claude/$L"

# H4 — the destination is a DANGLING symlink. `[ -f ]` is false (it resolves to
# nothing), so nothing warns; rename() then replaces the link itself.
mkdir -p "$H/h4/.claude/.idd"
echo '{"github_repo":"o/h4"}' > "$H/h4/.claude/$L"
ln -s "$OUTSIDE/does-not-exist" "$H/h4/.claude/.idd/local.json"

# H4b — the destination is a symlink to an existing regular file elsewhere.
# `-f` FOLLOWS it, so without an -L test this reports "both present, current
# wins" — an audit line that says the config is in the repo when it is not.
mkdir -p "$H/h4b/.claude/.idd"
echo '{"github_repo":"o/h4b"}' > "$H/h4b/.claude/$L"
echo '{"github_repo":"o/elsewhere"}' > "$OUTSIDE/other-config.json"
ln -s "$OUTSIDE/other-config.json" "$H/h4b/.claude/.idd/local.json"

# H5 — a file with the legacy NAME that is not in a `.claude/` directory at all.
# It is not IDD config; migrating it invents a `.idd` directory in someone
# else's tree. The find predicate is name-only, so it matches.
mkdir -p "$H/h5/docs/examples"
echo '{"github_repo":"o/h5-doc-sample"}' > "$H/h5/docs/examples/$L"

# H6 — the legacy path is itself a symlink. Regression lock, not a new guard:
# `find -type f` uses lstat, so a symlink is already excluded. Pinned because
# the guard is invisible (it lives in a flag, not in a line of code) and a
# future switch to `find -L` would silently start following it.
mkdir -p "$H/h6/.claude"
echo 'secret' > "$OUTSIDE/linked-config.json"
ln -s "$OUTSIDE/linked-config.json" "$H/h6/.claude/$L"

HOUT=$(bash "$SCRIPT" --apply "$H" 2>&1); HRC=$?

assert_exit "hostile apply exits non-zero (refusals are failures)" 1 "$HRC"

require "H1 .idd symlink: legacy config stays put" test -f "$H/h1/.claude/$L"
refute  "H1 .idd symlink: nothing was written through the link" \
  test -e "$OUTSIDE/exfil/local.json"
assert_grep "H1 .idd symlink: refusal is reported" "not a directory" "$HOUT"

assert_eq "H2 breadcrumb symlink: victim file is not truncated" \
  "precious" "$(cat "$OUTSIDE/victim.txt")"

refute "H2b dangling breadcrumb symlink: nothing was created through it" \
  test -e "$OUTSIDE/planted.txt"

require "H3 destination is a directory: legacy config stays put" test -f "$H/h3/.claude/$L"
refute  "H3 destination is a directory: nothing was moved inside it" \
  test -e "$H/h3/.claude/.idd/local.json/$L"

require "H4 dangling destination symlink: legacy config stays put" test -f "$H/h4/.claude/$L"
require "H4 dangling destination symlink: the link itself is untouched" \
  test -L "$H/h4/.claude/.idd/local.json"

require "H4b symlinked destination: legacy config stays put" test -f "$H/h4b/.claude/$L"
assert_grep "H4b symlinked destination: refused, NOT called 'both present'" \
  ".idd/local.json is a symlink" "$HOUT"
refute_grep "H4b symlinked destination: no misleading both-present line" \
  "both present, current wins (left alone): $H/h4b" "$HOUT"

require "H5 legacy name outside .claude/ is not migrated" test -f "$H/h5/docs/examples/$L"
refute  "H5 no .idd directory was invented next to it" test -e "$H/h5/docs/examples/.idd"

require "H6 symlinked legacy path is not followed" test -L "$H/h6/.claude/$L"
assert_eq "H6 its target is unchanged" "secret" "$(cat "$OUTSIDE/linked-config.json")"

print_summary "migrate-idd-config"
exit $?
