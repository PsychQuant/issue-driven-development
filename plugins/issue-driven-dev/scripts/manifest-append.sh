#!/usr/bin/env bash
# manifest-append.sh — append a spawn entry to chain-spawned-issues.json
#
# Used by 4 spawning sub-skills (idd-implement / idd-verify / idd-plan / idd-diagnose)
# under chain context (when /idd-all-chain has initialized the manifest file).
#
# Usage:
#   manifest-append.sh <repo-root> <issue-number> <spawned-by> <spawn-step> \
#                      <spawn-kind> <same-file> <same-skill> <title>
#
# Exit:
#   0 — entry appended, or manifest absent (chain context inactive — silent skip)
#   1 — schema version mismatch, manifest corrupt, or write failed
#   2 — usage error / invalid argument
#
# See: plugins/issue-driven-dev/references/spawn-manifest.md

set -u

EXPECTED_SCHEMA_VERSION=1

usage() {
  cat >&2 <<EOF
Usage: $(basename "$0") <repo-root> <issue-number> <spawned-by> <spawn-step> <spawn-kind> <same-file> <same-skill> <title>

Arguments:
  repo-root      absolute path to repo root (where .claude/.idd/state/ lives)
  issue-number   GitHub issue number (positive integer)
  spawned-by     one of: idd-implement | idd-verify | idd-plan | idd-diagnose
  spawn-step     human-readable step identifier (e.g. "Step 5.7 sister bug sweep")
  spawn-kind     one of: sister-bug | follow-up-finding | tangential | sister-concern | upstream-tracking
  same-file      true | false (does spawn target same source files as root?)
  same-skill     true | false (does spawn target same skill / module as root?)
  title          spawned issue title (raw)

If the manifest file does not exist, the script exits 0 silently
(chain context not active, sub-skill should continue baseline behavior).
EOF
  exit 2
}

if [ $# -ne 8 ]; then
  usage
fi

REPO_ROOT="$1"
ISSUE_NUMBER="$2"
SPAWNED_BY="$3"
SPAWN_STEP="$4"
SPAWN_KIND="$5"
SAME_FILE="$6"
SAME_SKILL="$7"
TITLE="$8"

# Validate enums
case "$SPAWNED_BY" in
  idd-implement|idd-verify|idd-plan|idd-diagnose) ;;
  *) echo "✗ invalid spawned-by: '$SPAWNED_BY'" >&2; exit 2 ;;
esac
case "$SPAWN_KIND" in
  sister-bug|follow-up-finding|tangential|sister-concern|upstream-tracking) ;;
  *) echo "✗ invalid spawn-kind: '$SPAWN_KIND'" >&2; exit 2 ;;
esac
case "$SAME_FILE" in
  true|false) ;;
  *) echo "✗ same-file must be 'true' or 'false', got: '$SAME_FILE'" >&2; exit 2 ;;
esac
case "$SAME_SKILL" in
  true|false) ;;
  *) echo "✗ same-skill must be 'true' or 'false', got: '$SAME_SKILL'" >&2; exit 2 ;;
esac
if ! [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]] || [ "$ISSUE_NUMBER" -le 0 ]; then
  echo "✗ issue-number must be a positive integer, got: '$ISSUE_NUMBER'" >&2
  exit 2
fi

MANIFEST="${REPO_ROOT}/.claude/.idd/state/chain-spawned-issues.json"

# Chain context detection:if manifest absent, silent skip (exit 0)
if [ ! -f "$MANIFEST" ]; then
  exit 0
fi

# Schema version check (per "Each spawned issue SHALL produce one append-only entry" requirement)
ACTUAL_VERSION=$(jq -r '.schema_version // empty' "$MANIFEST" 2>/dev/null)
if [ "$ACTUAL_VERSION" != "$EXPECTED_SCHEMA_VERSION" ]; then
  cat >&2 <<EOF
✗ Manifest schema version mismatch.
  File: $MANIFEST
  Expected: $EXPECTED_SCHEMA_VERSION
  Actual: ${ACTUAL_VERSION:-(missing)}

  This sub-skill was built against schema_version=${EXPECTED_SCHEMA_VERSION}.
  If the manifest is from a newer chain shell, update sub-skill scripts.
EOF
  exit 1
fi

# Build entry as JSON object via jq (handles escaping correctly)
FILED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

NEW_ENTRY=$(jq -n \
  --argjson issue_number "$ISSUE_NUMBER" \
  --arg spawned_by "$SPAWNED_BY" \
  --arg spawn_step "$SPAWN_STEP" \
  --arg spawn_kind "$SPAWN_KIND" \
  --argjson same_file "$SAME_FILE" \
  --argjson same_skill "$SAME_SKILL" \
  --arg filed_at "$FILED_AT" \
  --arg title "$TITLE" \
  '{
    issue_number: $issue_number,
    spawned_by: $spawned_by,
    spawn_step: $spawn_step,
    spawn_kind: $spawn_kind,
    same_file_as_root: $same_file,
    same_skill_as_root: $same_skill,
    filed_at: $filed_at,
    title: $title
  }')

# Atomic temp-file rename (per "Manifest writes SHALL be atomic via temp-file rename" requirement)
TEMP="${MANIFEST}.tmp.$$"
trap 'rm -f "$TEMP"' EXIT

if ! jq --argjson entry "$NEW_ENTRY" '.spawned += [$entry]' "$MANIFEST" > "$TEMP"; then
  echo "✗ jq failed to update manifest" >&2
  exit 1
fi

# Validate temp file is valid JSON before rename
if ! jq -e . "$TEMP" >/dev/null 2>&1; then
  echo "✗ temp file is not valid JSON, refusing to rename" >&2
  exit 1
fi

mv "$TEMP" "$MANIFEST"
trap - EXIT

echo "✓ appended #${ISSUE_NUMBER} to manifest" >&2
exit 0
