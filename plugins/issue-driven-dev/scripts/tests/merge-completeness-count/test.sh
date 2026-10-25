#!/usr/bin/env bash
# test.sh — the merge-completeness suite again, as git 2.38 and 2.39 run it (#399).
#
# At a landing commit check-merge-completeness.sh checks each commit in its own place
# with `git merge-tree --merge-base` (git 2.40). Git 2.38 and 2.39 have --write-tree
# but not --merge-base, and there the helper counts lines instead. On a newer git the
# merge-completeness fixtures never reach that count, so this suite runs them again
# under a shim that refuses --merge-base, which keeps the count's rules pinned
# wherever the suites run. A separate suite, not a second pass inside the first, so
# each stays within run-all-tests' per-suite timeout.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUITE="$HERE/../merge-completeness/test.sh"

PROBE="$(mktemp -d "${TMPDIR:-/tmp}/mc-count-probe-XXXXXX")" || { echo "cannot create a probe dir" >&2; exit 1; }
git -C "$PROBE" init -q && git -C "$PROBE" -c user.email=t@t.t -c user.name=t commit -q --allow-empty -m p
if ! git -C "$PROBE" merge-tree --write-tree HEAD HEAD >/dev/null 2>&1; then
  rm -rf "$PROBE"
  echo "  (git without merge-tree --write-tree: no landing step to count at; nothing to run)"
  echo "PASS: 0"; echo "FAIL: 0"
  exit 0
fi
rm -rf "$PROBE"

SHIM="$(mktemp -d "${TMPDIR:-/tmp}/mc-count-shim-XXXXXX")" || { echo "cannot create a shim dir" >&2; exit 1; }
trap 'rm -rf "$SHIM"' EXIT
REALGIT="$(command -v git)"
printf '#!/bin/sh\n# Simulates git 2.38-2.39: merge-tree has --write-tree but no --merge-base.\nfor a in "$@"; do case "$a" in --merge-base|--merge-base=*) echo "error: unknown option" >&2; exit 129 ;; esac; done\nexec "%s" "$@"\n' "$REALGIT" > "$SHIM/git"
chmod +x "$SHIM/git"
PATH="$SHIM:$PATH" "${BASH:-bash}" "$SUITE"
