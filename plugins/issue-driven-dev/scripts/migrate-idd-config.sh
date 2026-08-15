#!/usr/bin/env bash
# migrate-idd-config.sh — move legacy IDD config to the current path (#303).
#
# #195 moved the WRITE-BACK side to `.claude/.idd/local.json`. It did not move
# anything that already existed, so both layouts have coexisted since, with no
# migration and no deprecation statement — the worst of the three possible
# states, because a consumer cannot tell whether the legacy form is supported
# forever or about to disappear.
#
#   legacy:  <repo>/.claude/issue-driven-dev.local.json
#   current: <repo>/.claude/.idd/local.json
#
# Measured on one real machine (two work roots, maxdepth 8, excluding
# node_modules/.git/.build): 32 repos still on the legacy path. Every new tool
# that scans config has to parse both, and each one gets its own chance to miss
# a format — #302's repo-map scanner already listed that as a HIGH risk, where
# missing a config means "this layer does not exist" and triggers the wrong
# upward resolution.
#
# Usage:
#   migrate-idd-config.sh --scan [root ...]     # report only, no writes (default)
#   migrate-idd-config.sh --apply [root ...]    # move + leave a pointer behind
#
# Defaults to scanning ~/Developer if no root is given.
# ALWAYS exits 0 on scan; --apply exits non-zero only if a move failed.

set -u

MODE="scan"
ROOTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --scan)  MODE="scan";  shift ;;
    --apply) MODE="apply"; shift ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *) ROOTS+=("$1"); shift ;;
  esac
done
[ ${#ROOTS[@]} -eq 0 ] && ROOTS=("$HOME/Developer")

LEGACY_NAME="issue-driven-dev.local.json"
found=0
migrated=0
skipped=0
failed=0

for root in "${ROOTS[@]}"; do
  [ -d "$root" ] || { echo "note: not a directory, skipping: $root" >&2; continue; }
  # -prune the heavy directories rather than filtering after the fact.
  # -print0 / read -d "" is not stylistic. With -print, a directory name that
  # contains a NEWLINE splits one entry into two, and the second fragment is a
  # RELATIVE path that `dirname`/`mv` then resolve against the CALLER's cwd.
  # Reproduced: with a victim at caller/.claude/.claude/local config and a
  # newline-named repo inside the scan root, `--apply ../scan` relocated the
  # victim -- a file outside the scanned tree entirely -- and reported
  # "✓ migrated: .claude  migrated: 1".
  while IFS= read -r -d '' legacy; do
    found=$((found + 1))
    # Belt and braces: even with -print0, never act on a path that is not an
    # absolute path inside the root we were told to scan.
    case "$legacy" in
      "$root"/*) : ;;
      *) echo "  ✗ refusing a path outside the scan root: $legacy" >&2; failed=$((failed + 1)); continue ;;
    esac
    dir=$(dirname "$legacy")              # .../.claude
    current="$dir/.idd/local.json"
    repo=$(dirname "$dir")

    if [ -f "$current" ]; then
      # Both exist. The reader already prefers the current path, so moving would
      # change nothing and could destroy a hand-edited legacy file. Report, do
      # not touch.
      echo "  = both present, current wins (left alone): $repo"
      skipped=$((skipped + 1))
      continue
    fi

    if [ "$MODE" = "scan" ]; then
      echo "  → would migrate: $repo"
      continue
    fi

    if ! mkdir -p "$dir/.idd" 2>/dev/null; then
      echo "  ✗ cannot create $dir/.idd" >&2; failed=$((failed + 1)); continue
    fi
    if ! mv "$legacy" "$current" 2>/dev/null; then
      echo "  ✗ move failed: $legacy" >&2; failed=$((failed + 1)); continue
    fi
    # Leave a breadcrumb: a repo whose config silently relocated is confusing to
    # anyone who bookmarked the old path or greps for it.
    # Never truncate an existing file: the breadcrumb is a courtesy, not a
    # reason to destroy something a user put there.
    if [ -e "$legacy.moved" ]; then
      echo "  note: $legacy.moved already exists — breadcrumb not written" >&2
    else
      printf '%s\n' \
        "This file moved to .claude/.idd/local.json (#303, $(date +%Y-%m-%d))." \
        "The old path is no longer written by any IDD skill." \
        > "$legacy.moved"
    fi
    echo "  ✓ migrated: $repo"
    migrated=$((migrated + 1))
  done < <(find "$root" \
             \( -name node_modules -o -name .git -o -name .build -o -name .venv \
                -o -name archive -o -name archived -o -path '*/.claude/worktrees' \) -prune -o \
             -type f -name "$LEGACY_NAME" -print0 2>/dev/null)
done

echo ""
echo "legacy configs found: $found"
if [ "$MODE" = "scan" ]; then
  echo "(scan only — re-run with --apply to migrate)"
  exit 0
fi
echo "migrated: $migrated   left alone (both present): $skipped   failed: $failed"
[ "$failed" -eq 0 ] || exit 1
exit 0
