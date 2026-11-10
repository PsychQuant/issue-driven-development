#!/usr/bin/env bash
# Regenerate fixtures/*.html from fixtures/*.md with GitHub's own renderer (#392).
#
# verify-gate.py reads a comment the way GitHub renders it (body_html), so the
# suite's inputs are GitHub's output, not HTML written by hand. Run this after
# adding or editing a .md fixture (needs network and `gh auth`); commit both
# files. The suite itself (test.sh) reads only the committed .html and runs
# offline.
#
#   render-fixtures.sh            render every fixture
#   render-fixtures.sh NAME.md…   render the named ones
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FX="$HERE/fixtures"
CONTEXT=PsychQuant/issue-driven-development   # gfm mode needs a repo context, as a comment has
if [ $# -gt 0 ]; then files=("$@"); else files=("$FX"/*.md); fi
for md in "${files[@]}"; do
  case "$md" in /*) ;; *) md="$FX/$md" ;; esac
  out="${md%.md}.html"
  gh api markdown -f mode=gfm -f context="$CONTEXT" -F text=@"$md" > "$out.tmp"
  mv "$out.tmp" "$out"
  echo "rendered $(basename "$out")"
done
