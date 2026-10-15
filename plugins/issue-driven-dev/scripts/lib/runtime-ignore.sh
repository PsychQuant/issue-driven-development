#!/usr/bin/env bash
# Local session state belongs in the clone's shared excludes, never .gitignore.
# Reuse the canonical marker writer; linked worktrees share this common git dir.
idd_ignore_runtime_paths() {
  local repo="$1" common target scripts
  common="$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null)" || return 1
  case "$common" in /*) ;; *) common="$repo/$common" ;; esac
  target="$common/info/exclude"
  if [ -L "$target" ] || [ -L "$common/info" ]; then
    echo "⚠ refusing symlinked runtime exclude target: $target" >&2
    return 1
  fi
  scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || return 1
  bash -e "$scripts/git-ignore-block.sh" --target "$target" \
    --marker 'IDD local runtime state' --direction exclude -- \
    '.claude/worktrees/' '.claude/.idd/tree-lock'
}
