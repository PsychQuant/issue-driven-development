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
# Detection regex (per PsychQuant/issue-driven-development#53):
#   `test("(?m)^## Diagnosis")` — line-anchored, avoids quoted-history false-positives.
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

  count=$(gh issue view "$n" -R "$GITHUB_REPO" --json comments 2>/dev/null \
    | jq -r '[.comments[] | select(.body | test("(?m)^## Diagnosis"))] | length' \
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
