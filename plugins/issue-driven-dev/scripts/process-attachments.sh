#!/usr/bin/env bash
# process-attachments.sh — IDD attachment download/check/verify helper
#
# Mechanical work for attachment processing:
#   - download: fetch all attachment URLs in issue body/comments to .claude/.idd/attachments/issue-NNN/
#   - check:    verify manifest covers current issue attachment list (downstream skills)
#   - verify:   confirm manifest-listed files still exist on disk (idd-close)
#
# Parsing (docx -> text, pdf -> text) is NOT this script's job — Claude uses
# MCP tools (che-word-mcp, che-pdf-mcp) or Read tool on the downloaded files.
#
# Usage:
#   process-attachments.sh download <issue-number> [--repo owner/repo]
#   process-attachments.sh check    <issue-number> [--repo owner/repo]
#   process-attachments.sh verify   <issue-number> [--repo owner/repo]
#
# Env:
#   IDD_CALLER — name of calling skill (recorded in manifest fetched_by)
#
# Exit codes:
#   0 — success / no attachments / up-to-date
#   1 — manifest missing / new attachments detected / files missing on disk
#   2 — usage error / cannot resolve repo / attachment-list fetch failure
#       (gh/jq — network, auth, malformed JSON; detect_urls returns 2, #186)
#       / corrupt _manifest.json (unparseable JSON; check/verify, #189)

set -euo pipefail

CMD="${1:-}"
NUMBER="${2:-}"
REPO=""

# Shift positional args, then parse flags
if [ $# -ge 2 ]; then shift 2; fi
while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 2 ;;
  esac
done

if [ -z "$CMD" ] || [ -z "$NUMBER" ]; then
  cat >&2 <<EOF
Usage: $0 {download|check|verify} <issue-number> [--repo owner/repo]

  download  Fetch attachments from issue body/comments to .claude/.idd/attachments/issue-N/
  check     Verify manifest covers current issue attachment list (downstream skills)
  verify    Confirm manifest-listed files still exist on disk (idd-close)
EOF
  exit 2
fi

# --- helpers ----------------------------------------------------------------

parse_md_frontmatter() {
  # Extract github_repo from YAML frontmatter (legacy .local.md format)
  python3 - "$1" <<'PY' 2>/dev/null || true
import sys, re
with open(sys.argv[1]) as f:
    text = f.read()
m = re.match(r'^---\n(.*?)\n---', text, re.DOTALL)
if not m:
    sys.exit(1)
for line in m.group(1).splitlines():
    if ':' in line:
        key, val = line.split(':', 1)
        if key.strip() == 'github_repo':
            print(val.strip().strip('"').strip("'"))
            sys.exit(0)
sys.exit(1)
PY
}

resolve_repo() {
  if [ -n "$REPO" ]; then echo "$REPO"; return 0; fi
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    # Path precedence: new (.idd/local.json) > legacy json > legacy md frontmatter
    for cfg in "$dir/.claude/.idd/local.json" "$dir/.claude/issue-driven-dev.local.json"; do
      if [ -f "$cfg" ]; then
        local r
        r=$(jq -r '.github_repo // empty' "$cfg" 2>/dev/null || true)
        if [ -n "$r" ]; then echo "$r"; return 0; fi
      fi
    done
    if [ -f "$dir/.claude/issue-driven-dev.local.md" ]; then
      local r
      r=$(parse_md_frontmatter "$dir/.claude/issue-driven-dev.local.md")
      if [ -n "$r" ]; then echo "$r"; return 0; fi
    fi
    [ "$dir" = "$HOME" ] && break
    dir=$(dirname "$dir")
  done
  return 1
}

detect_urls() {
  # Patterns: github.com/user-attachments/{files,assets}/, github.com/{owner}/{repo}/files/N/,
  # (private-)user-images.githubusercontent.com/
  #
  # Fetch and filter are deliberately SPLIT (#186): a zero-attachment issue makes
  # grep exit 1, and under `set -euo pipefail` a single fetch|filter pipeline dies
  # at the caller's `URLS=$(detect_urls)` assignment — silently, before the
  # empty-manifest branch (all three call sites: download + both check paths).
  # The asymmetry is the contract: a FETCH failure (gh/jq — network, auth, bad
  # JSON) must stay LOUD (return non-zero -> the caller's assignment fails ->
  # top-level set -e aborts, no manifest written; never swallowed into a fake
  # "no attachments"), while a FILTER zero-match is a legitimate empty result.
  #
  # Failure propagation is EXPLICIT (`|| return 2`), not errexit-reliant: this
  # function runs inside `$(...)` whose subshell does NOT inherit errexit by
  # default (bash `inherit_errexit` is opt-in since 4.4) — relying on set -e
  # here silently downgrades a gh outage into "no attachments".
  local raw content
  raw=$(gh issue view "$NUMBER" --repo "$REPO" --json body,comments) || return 2
  content=$(printf '%s\n' "$raw" | jq -r '.body, .comments[].body') || return 2
  printf '%s\n' "$content" \
    | grep -oE 'https://(github\.com/(user-attachments/(files|assets)/[^)]+|[^/]+/[^/]+/files/[0-9]+/[^)]+)|(private-)?user-images\.githubusercontent\.com/[^)]+)' \
    | sort -u || true
}

assert_manifest_valid() {
  # $1 = manifest path. Loud-fail (exit 2) on unparseable JSON. A corrupt
  # manifest must NEVER be read as "0 files / all present" (silent PASS, #189):
  # `check` swallowed the jq error (2>/dev/null + || true) and `verify` read it
  # through a process-substitution whose exit never propagated, so both reported
  # a false success — and `verify` is idd-close's Step 1.4 gate. `jq empty`
  # parses without emitting the document, exit 0 only on valid JSON. Same
  # exit-2 = data-layer-failure semantics as the fetch-failure guard (#186).
  if ! jq empty "$1" 2>/dev/null; then
    echo "✗ Manifest is corrupt (not valid JSON): $1" >&2
    echo "   Re-fetch to rebuild it: bash \$CLAUDE_PLUGIN_ROOT/scripts/process-attachments.sh download $NUMBER" >&2
    exit 2
  fi
}

decode_filename() {
  # URL-decode the basename, strip trailing markdown punctuation
  basename "$1" | sed 's/[)>"].*$//' | python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.stdin.read().strip()))'
}

file_size() {
  # Cross-platform stat
  if stat -f%z "$1" >/dev/null 2>&1; then stat -f%z "$1"; else stat -c%s "$1"; fi
}

# --- resolve repo -----------------------------------------------------------

if ! REPO=$(resolve_repo); then
  echo "✗ Cannot resolve target repo. Pass --repo owner/repo or run from inside an idd-config'd repo." >&2
  exit 2
fi

ATTACH_DIR=".claude/.idd/attachments/issue-${NUMBER}"
MANIFEST="$ATTACH_DIR/_manifest.json"

# --- commands ---------------------------------------------------------------

case "$CMD" in

  download)
    mkdir -p "$ATTACH_DIR"
    URLS=$(detect_urls)

    TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    BY="${IDD_CALLER:-idd-skill}"

    if [ -z "$URLS" ]; then
      jq -n --argjson n "$NUMBER" --arg ts "$TS" --arg by "$BY" \
        '{issue: $n, fetched_at: $ts, fetched_by: $by, files: []}' > "$MANIFEST"
      echo "ℹ Issue #$NUMBER has no attachments. (empty manifest written)"
      exit 0
    fi

    TOKEN=$(gh auth token)
    FILES_JSON="[]"

    while IFS= read -r url; do
      [ -z "$url" ] && continue
      filename=$(decode_filename "$url")
      target="$ATTACH_DIR/$filename"

      if curl -sLf -H "Authorization: token $TOKEN" -o "$target" "$url"; then
        sha=$(shasum -a 256 "$target" | cut -d' ' -f1)
        size=$(file_size "$target")
        FILES_JSON=$(echo "$FILES_JSON" | jq \
          --arg fn "$filename" --arg url "$url" --arg sha "$sha" --argjson size "$size" \
          '. += [{filename: $fn, url: $url, sha256: $sha, size_bytes: $size}]')
        echo "✓ $filename ($size bytes)"
      else
        echo "⚠ Failed to download $url" >&2
        FILES_JSON=$(echo "$FILES_JSON" | jq \
          --arg fn "$filename" --arg url "$url" \
          '. += [{filename: $fn, url: $url, error: "download_failed"}]')
      fi
    done <<< "$URLS"

    jq -n \
      --argjson n "$NUMBER" \
      --arg ts "$TS" \
      --arg by "$BY" \
      --argjson files "$FILES_JSON" \
      '{issue: $n, fetched_at: $ts, fetched_by: $by, files: $files}' \
      > "$MANIFEST"

    echo "✓ Manifest: $MANIFEST"
    ;;

  check)
    if [ ! -f "$MANIFEST" ]; then
      URLS=$(detect_urls)
      if [ -n "$URLS" ]; then
        echo "⚠ Issue #$NUMBER has attachments but manifest missing: $MANIFEST" >&2
        echo "   Run: bash \$CLAUDE_PLUGIN_ROOT/scripts/process-attachments.sh download $NUMBER" >&2
        exit 1
      fi
      echo "ℹ Issue #$NUMBER has no attachments (no manifest needed)."
      exit 0
    fi

    assert_manifest_valid "$MANIFEST"   # #189 — corrupt manifest must loud-fail, not false "up-to-date"
    CURRENT=$(detect_urls)
    KNOWN=$(jq -r '.files[].url' "$MANIFEST" 2>/dev/null | sort -u || true)
    NEW=$(comm -23 <(echo "$CURRENT") <(echo "$KNOWN") | grep -v '^$' || true)

    if [ -n "$NEW" ]; then
      echo "⚠ Issue #$NUMBER has new attachments since manifest:" >&2
      echo "$NEW" | sed 's/^/   /' >&2
      echo "   Run: bash \$CLAUDE_PLUGIN_ROOT/scripts/process-attachments.sh download $NUMBER" >&2
      exit 1
    fi

    echo "✓ Manifest up-to-date for #$NUMBER ($(jq '.files | length' "$MANIFEST") files)"
    ;;

  verify)
    if [ ! -f "$MANIFEST" ]; then
      echo "ℹ No manifest for #$NUMBER (skipping verify)."
      exit 0
    fi

    assert_manifest_valid "$MANIFEST"   # #189 — corrupt manifest must loud-fail, not false "all present"
    MISSING=0
    while IFS= read -r filename; do
      [ -z "$filename" ] && continue
      if [ ! -f "$ATTACH_DIR/$filename" ]; then
        echo "⚠ Manifest references $filename but file missing on disk." >&2
        MISSING=$((MISSING + 1))
      fi
    done < <(jq -r '.files[].filename' "$MANIFEST" 2>/dev/null)

    if [ "$MISSING" -gt 0 ]; then
      echo "⚠ $MISSING attachment(s) missing — closing comment may have broken references." >&2
      exit 1
    fi

    echo "✓ All attachments present for #$NUMBER"
    ;;

  *)
    echo "Unknown command: $CMD" >&2
    echo "Usage: $0 {download|check|verify} <issue-number> [--repo owner/repo]" >&2
    exit 2
    ;;
esac
