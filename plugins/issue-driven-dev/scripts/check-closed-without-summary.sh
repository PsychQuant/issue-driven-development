#!/usr/bin/env bash
# check-closed-without-summary.sh — retroactive audit for the direct-commit
# auto-close trap (#151). Lists CLOSED issues whose comments contain NO
# `## Closing Summary` heading — i.e. issues that may have been auto-closed by a
# commit / PR-body close keyword, bypassing the /idd-close gate (checklist /
# semantic / sister-sweep / residue / distribution-sync).
#
# Advisory only — ALWAYS exits 0. Output: one line per flagged issue.
#
# Usage:
#   check-closed-without-summary.sh [--repo owner/repo] [--limit N] [--since YYYY-MM-DD]
#   check-closed-without-summary.sh --json-file <path>     # test / offline mode
#
# Consumed by idd-list `--audit-closes`. The `## Closing Summary` heading is the
# same marker idd-list Step 3 keys on for phase inference.

set -u

JSON_FILE=""
REPO=""
LIMIT=50
SINCE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --json-file) JSON_FILE="${2:-}"; shift 2 ;;
    --repo)      REPO="${2:-}"; shift 2 ;;
    --limit)     LIMIT="${2:-50}"; shift 2 ;;
    --since)     SINCE="${2:-}"; shift 2 ;;
    -h|--help)   sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           echo "unknown arg: $1" >&2; shift ;;
  esac
done

# ── Acquire issue JSON ──
if [ -n "$JSON_FILE" ]; then
  [ -f "$JSON_FILE" ] || { echo "✗ --json-file not found: $JSON_FILE" >&2; exit 0; }
  ISSUES_JSON=$(cat "$JSON_FILE")
else
  # Resolve repo: --repo flag → walk-up .claude/.idd config → gh default repo.
  if [ -z "$REPO" ]; then
    dir="$PWD"
    while [ "$dir" != "/" ]; do
      for cfg in "$dir/.claude/.idd/local.json" "$dir/.claude/issue-driven-dev.local.json"; do
        if [ -f "$cfg" ]; then
          REPO=$(jq -r '.github_repo // empty' "$cfg" 2>/dev/null)
          [ -n "$REPO" ] && break
        fi
      done
      [ -n "$REPO" ] && break
      [ "$dir" = "$HOME" ] && break
      dir=$(dirname "$dir")
    done
  fi
  GH_ARGS=(issue list --state closed --json number,title,state,comments --limit "$LIMIT")
  [ -n "$REPO" ]  && GH_ARGS+=(--repo "$REPO")
  [ -n "$SINCE" ] && GH_ARGS+=(--search "closed:>=$SINCE")
  if ! ISSUES_JSON=$(gh "${GH_ARGS[@]}" 2>/dev/null); then
    echo "note: 'gh issue list' failed (auth / network / old gh CLI) — audit skipped." >&2
    exit 0
  fi
fi

# ── Filter: CLOSED issues with NO `## Closing Summary` comment ──
# `select(... any | not)` keeps issues where NONE of the comment bodies start
# with the heading. Empty-comments issues yield `[] | any == false → not == true`
# → flagged (the legacy / GitHub-UI-close case).
FLAGGED=$(printf '%s' "$ISSUES_JSON" | jq -r '
  .[]
  | select((.state // "CLOSED") | ascii_upcase == "CLOSED")
  | select([.comments[]?.body // "" | startswith("## Closing Summary")] | any | not)
  | "⚠ #\(.number)  \(.title)"
' 2>/dev/null)

if [ -z "$FLAGGED" ]; then
  echo "✓ No closed issue is missing a ## Closing Summary (within the scanned window)."
  exit 0
fi

echo "Closed issues with NO ## Closing Summary (possible auto-close-trap bypass —"
echo "consider retroactive /idd-close remediation):"
printf '%s\n' "$FLAGGED"
echo ""
echo "(advisory — legacy / pre-IDD / GitHub-UI-closed issues are expected here; narrow with --since / --limit)"
exit 0
