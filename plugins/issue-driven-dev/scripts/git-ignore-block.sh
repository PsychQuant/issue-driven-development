#!/usr/bin/env bash
# git-ignore-block.sh — idempotent, marker-delimited git ignore-block writer.
#
# Shared primitive for:
#   - idd-issue Step 0.5.E third-party clone setup (#192) — direction=exclude,
#     target .git/info/exclude (keep IDD config out of an upstream you don't own)
#   - idd-issue Stage 4.5 jsonl carve-out (#55) — direction=re-include,
#     target .gitignore (re-include a run-log path whose parent dir is excluded)
#
# See: openspec change add-third-party-clone-setup design.md D4.
#
# Usage:
#   git-ignore-block.sh --target <file> --marker <marker-line> \
#                       --direction <exclude|re-include> [--] PATH_OR_PATTERN...
#
#   direction=exclude    : args written verbatim as ignore patterns.
#   direction=re-include : each arg is a path; expanded to the parent-dir
#                          carve-out chain (!a / a/* / !a/b / a/b/* / !a/b/c)
#                          so the path is trackable even when an ancestor is
#                          excluded (git "cannot re-include a file if a parent
#                          directory of that file is excluded" rule).
#
# Idempotent: same marker + body → no-op; same marker, different body → replace
# the block in place; surrounding user content preserved. The block is bracketed
# by BEGIN/END sentinels derived from the marker, so replacement is exact (no
# fragile pattern state-machine).
#
# Exit: 0 written or no-op, 2 usage error.

set -u

TARGET="" MARKER="" DIRECTION=""
PATTERNS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --target)    TARGET="${2:-}"; shift 2 ;;
    --marker)    MARKER="${2:-}"; shift 2 ;;
    --direction) DIRECTION="${2:-}"; shift 2 ;;
    --)          shift; while [ $# -gt 0 ]; do PATTERNS+=("$1"); shift; done ;;
    -*)          echo "✗ git-ignore-block: unknown option: $1" >&2; exit 2 ;;
    *)           PATTERNS+=("$1"); shift ;;
  esac
done

[ -n "$TARGET" ] || { echo "✗ git-ignore-block: --target required" >&2; exit 2; }
[ -n "$MARKER" ] || { echo "✗ git-ignore-block: --marker required" >&2; exit 2; }
[ ${#PATTERNS[@]} -gt 0 ] || { echo "✗ git-ignore-block: at least one pattern/path required" >&2; exit 2; }
case "$DIRECTION" in
  exclude|re-include) ;;
  *) echo "✗ git-ignore-block: --direction must be exclude|re-include (got '${DIRECTION}')" >&2; exit 2 ;;
esac

# --- Build block body ---------------------------------------------------------
BODY=()
if [ "$DIRECTION" = "exclude" ]; then
  for p in "${PATTERNS[@]}"; do BODY+=("$p"); done
else
  # re-include: expand each path into the parent-dir carve-out chain.
  for path in "${PATTERNS[@]}"; do
    path="${path#/}"; path="${path%/}"
    IFS='/' read -ra comps <<< "$path"
    prefix=""
    n=${#comps[@]}
    for ((i=0; i<n; i++)); do
      if [ -z "$prefix" ]; then prefix="${comps[i]}"; else prefix="$prefix/${comps[i]}"; fi
      BODY+=("!$prefix")
      if [ $((i+1)) -lt "$n" ]; then BODY+=("$prefix/*"); fi
    done
  done
fi

BEGIN="# >>> ${MARKER} >>>"
END="# <<< ${MARKER} <<<"

new_block() {
  printf '%s\n' "$BEGIN"
  printf '%s\n' "${BODY[@]}"
  printf '%s\n' "$END"
}

mkdir -p "$(dirname "$TARGET")"
touch "$TARGET"

# --- Idempotent write ---------------------------------------------------------
if grep -qF "$BEGIN" "$TARGET"; then
  existing="$(awk -v b="$BEGIN" -v e="$END" '$0==b{f=1} f{print} $0==e{f=0}' "$TARGET")"
  desired="$(new_block)"
  if [ "$existing" = "$desired" ]; then
    exit 0   # same marker + same body → no-op
  fi
  # Remove stale block (BEGIN..END inclusive), preserving everything else.
  awk -v b="$BEGIN" -v e="$END" '
    $0==b{skip=1}
    !skip{print}
    $0==e{skip=0}
  ' "$TARGET" > "$TARGET.tmp"
  mv "$TARGET.tmp" "$TARGET"
fi

# Append fresh block, with a blank-line separator when the file already has
# content (and does not already end in a blank line).
if [ -s "$TARGET" ] && [ -n "$(tail -c1 "$TARGET")" ]; then
  printf '\n' >> "$TARGET"
elif [ -s "$TARGET" ]; then
  : # already ends in newline; add one more blank for readability is optional — skip
fi
new_block >> "$TARGET"
exit 0
