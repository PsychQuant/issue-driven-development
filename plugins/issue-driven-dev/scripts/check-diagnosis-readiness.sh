#!/usr/bin/env bash
# check-diagnosis-readiness.sh — classify N issues into ready/not_ready by ## Diagnosis presence
#
# Used by /idd-all-chain Step 0.4 (single-root in v1) and reserved for #46 multi-root chain.
#
# Usage:
#   check-diagnosis-readiness.sh <github-repo> <issue-number> [<issue-number>...]
#
# Stdout (success): JSON {"ready":[N,...],"not_ready":[N,...]}
# Exit:
#   0 — success
#   1 — gh / jq failure (auth, network, non-existent issue)
#   2 — usage error
#
# Detection regex (per PsychQuant/issue-driven-development#53, refined in #64/#65):
#   `test("(?m)^[ ]{0,3}## Diagnosis")` — line-anchored with CommonMark spec's
#   1-3 space leading indent tolerance for ATX headings (#64). 4+ space leading
#   indent is a CommonMark code block (not a heading) — `[ ]{0,3}` correctly
#   excludes that. Tab indent (U+0009) is NOT a valid ATX heading indent.
#
# Known limitations (#65 — acknowledged, not closed):
#   - Detection is line-based; doesn't track fenced code block state. A comment
#     body that quotes `## Diagnosis` INSIDE a fenced code block (```) for
#     documentation / example purposes will false-positive as "diagnosed".
#     Mitigation: chain Phase 0.4 AskUserQuestion lets the user override the
#     auto-detect verdict (run /idd-diagnose first / proceed anyway / cancel).
#   - For a context-aware markdown-state parser (would close this gap fully),
#     see future-work follow-up. Current heuristic accepts the trade-off:
#     simpler regex + user-override safety net > full state machine + edge-case
#     bugs in the parser itself.
#
# See: plugins/issue-driven-dev/references/chain-flow.md for chain-shell context

set -u

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") <github-repo> <issue-number> [<issue-number>...]

Arguments:
  github-repo    GitHub repo in owner/repo form (e.g. PsychQuant/issue-driven-development)
  issue-number   one or more positive integer issue numbers

Stdout (success):
  JSON {"ready":[N,...],"not_ready":[N,...]}

Exit:
  0 — success
  1 — gh / jq failure
  2 — usage error
EOF
  exit 2
}

if [ $# -lt 2 ]; then
  usage
fi

GITHUB_REPO="$1"
shift

# Validate GITHUB_REPO shape
if ! [[ "$GITHUB_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  echo "ERROR: '$GITHUB_REPO' is not in owner/repo form" >&2
  usage
fi

READY=()
NOT_READY=()

for n in "$@"; do
  # Strict positive-integer check: GitHub has no issue #0, so reject "0" too.
  if ! [[ "$n" =~ ^[1-9][0-9]*$ ]]; then
    echo "ERROR: '$n' is not a positive integer issue number" >&2
    usage
  fi

  # v2.68.0+ #64 — CommonMark allows 1-3 space leading indent for ATX headings;
  # widen the anchor from strict ^## to ^[ ]{0,3}## so user-pasted comment bodies
  # with legal indent don't false-negative. (4+ space is a code block per spec —
  # `[ ]{0,3}` correctly excludes that.)
  count=$(gh issue view "$n" -R "$GITHUB_REPO" --json comments 2>/dev/null \
    | jq -r '[.comments[] | select(.body | test("(?m)^[ ]{0,3}## Diagnosis"))] | length' \
    2>/dev/null)

  if ! [[ "$count" =~ ^[0-9]+$ ]]; then
    echo "ERROR: gh/jq failed for issue #$n in $GITHUB_REPO (auth, network, or issue not found)" >&2
    exit 1
  fi

  if [ "$count" = "0" ]; then
    NOT_READY+=("$n")
  else
    READY+=("$n")
  fi
done

# Emit JSON. Use jq -n with empty arrays as sentinels so unset variables don't
# trip set -u when an array has 0 elements.
ready_json=$(printf '%s\n' "${READY[@]+"${READY[@]}"}" | grep -v '^$' | jq -R 'tonumber' | jq -s . 2>/dev/null)
not_ready_json=$(printf '%s\n' "${NOT_READY[@]+"${NOT_READY[@]}"}" | grep -v '^$' | jq -R 'tonumber' | jq -s . 2>/dev/null)
ready_json=${ready_json:-[]}
not_ready_json=${not_ready_json:-[]}

jq -nc \
  --argjson r "$ready_json" \
  --argjson nr "$not_ready_json" \
  '{ready: $r, not_ready: $nr}'
