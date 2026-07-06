#!/usr/bin/env bash
# test.sh — fixtures for resolve-submodule-route.sh (#162)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
. "$HERE/../../lib/resolve-submodule-route.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

mkrepo() { git -C "$1" init -q; git -C "$1" config user.email t@t.t; git -C "$1" config user.name t; git -C "$1" config commit.gpgsign false; git -C "$1" config protocol.file.allow always; }

# fixture: parent repo with a submodule that has its own origin
mkdir -p "$W/subsrc"; mkrepo "$W/subsrc"
printf 'x\n' > "$W/subsrc/f"; git -C "$W/subsrc" add -A; git -C "$W/subsrc" commit -qm sub
git -C "$W/subsrc" remote add origin git@github.com:acme/sub-repo.git

mkdir -p "$W/parent"; mkrepo "$W/parent"
printf 'p\n' > "$W/parent/p"; git -C "$W/parent" add -A; git -C "$W/parent" commit -qm parent
git -C "$W/parent" -c protocol.file.allow=always submodule add -q "$W/subsrc" themodule 2>/dev/null
git -C "$W/parent" commit -qm addsub
# submodule clone keeps file:// origin — override to a github-shaped one
git -C "$W/parent/themodule" remote set-url origin git@github.com:acme/sub-repo.git

# 1. inside submodule + auto → sub repo on stdout + surface line
OUT=$(cd "$W/parent/themodule" && resolve_submodule_route auto 2>"$W/err1")
assert_eq "auto: routes to submodule origin" "acme/sub-repo" "$OUT"
assert_grep "auto: surface line printed" "submodule detected" "$(cat "$W/err1")"

# 2. inside submodule + off → empty stdout + surface line (never silent)
OUT=$(cd "$W/parent/themodule" && resolve_submodule_route off 2>"$W/err2")
assert_eq "off: stays with parent (empty stdout)" "" "$OUT"
assert_grep "off: surface line still printed" "submodules: off" "$(cat "$W/err2")"

# 3. not in a submodule → empty + silent
OUT=$(cd "$W/parent" && resolve_submodule_route auto 2>"$W/err3")
assert_eq "non-submodule: empty stdout" "" "$OUT"
assert_eq "non-submodule: silent stderr" "" "$(cat "$W/err3")"

# 4. submodule without origin → empty + warning fallback
git -C "$W/parent/themodule" remote remove origin
OUT=$(cd "$W/parent/themodule" && resolve_submodule_route auto 2>"$W/err4")
assert_eq "no-origin: empty stdout (parent fallback)" "" "$OUT"
assert_grep "no-origin: warning surfaced" "no 'origin' remote" "$(cat "$W/err4")"

print_summary "submodule-routing"
