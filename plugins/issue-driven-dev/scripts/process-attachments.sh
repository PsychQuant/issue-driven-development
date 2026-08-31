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
#   IDD_CALLER — name of calling skill (recorded in manifest fetched_by);
#                allowed values + semantics: references/idd-caller-registry.md (#161)
#
# Exit codes:
#   0 — success / no attachments / up-to-date
#   1 — manifest missing / new attachments detected / files missing on disk
#   2 — usage error / cannot resolve repo / attachment-list fetch failure
#       (gh/jq — network, auth, malformed JSON; detect_urls returns 2, #186)
#       / corrupt or malformed _manifest.json (not a JSON object with a 'files'
#       array — incl. 0-byte/truncated; check/verify, #189)

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
  # (private-)user-images.githubusercontent.com/, and RELEASE ASSETS (#284):
  # github.com/{owner}/{repo}/releases/download/{tag}/{file}
  #
  # The release-asset form is not an exotic case — it is what THIS PLUGIN itself
  # produces. `idd-issue` Step 4 uploads attachments to an `attachments` release
  # and writes the release-download URL into the issue body; `idd-diagnose`
  # Step 1.5 then called this function, matched nothing, and reported
  # "Issue #N has no attachments (empty manifest written)". The write side and
  # the read side of the same plugin disagreed about the URL shape, and the
  # disagreement was silent: an empty manifest is indistinguishable from an issue
  # that genuinely has no attachments, so a diagnosis proceeded without the
  # evidence it was supposed to read.
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
  # The character class excluded `)` and whitespace only, which covers a
  # markdown link and nothing else. Real issue bodies wrap URLs three more ways,
  # and each one used to come back with the wrapper glued on:
  #
  #   <https://…/a.pdf>          autolink        -> trailing `>`
  #   <img src="https://…/b.png"> HTML attribute -> trailing `">`
  #   see https://…/c.pdf.       end of sentence -> trailing `.`
  #
  # All three download as 404, and an attachment that cannot be downloaded is a
  # source that gets ignored — which this plugin treats as a rule violation, not
  # a nuisance. `<`, `>`, `"` and `'` can never appear unencoded in a URL, so
  # excluding them is free.
  local u='[^)<>"'"'"'[:space:]]'
  # Trailing sentence punctuation is stripped afterwards rather than excluded,
  # because `.` is legal mid-URL and every one of these ends in a file
  # extension. Exactly one character, so `…/c.pdf..` would still keep a dot —
  # accepted: the wrong direction here is a loud 404, not a silent wrong file.
  printf '%s\n' "$content" \
    | grep -oE "https://(github\.com/(user-attachments/(files|assets)/$u+|[^/]+/[^/]+/files/[0-9]+/$u+|[^/]+/[^/]+/releases/download/[^/)<>\"'[:space:]]+/$u+)|(private-)?user-images\.githubusercontent\.com/$u+)" \
    | sed 's/[.,;:!?]$//' \
    | sort -u || true
}

assert_manifest_valid() {
  # $1 = manifest path. Loud-fail (exit 2) on a corrupt OR malformed manifest. A
  # manifest that can't be read must NEVER be treated as "0 files / all present"
  # (silent PASS, #189): `check` swallowed the jq error (2>/dev/null + || true) and
  # `verify` read it through a process-substitution whose exit never propagated, so
  # both reported a false success — and `verify` is idd-close's Step 1.4 gate.
  #
  # The shape check is `type=="object" and (.files|type)=="array"`, NOT bare
  # `jq empty` (#189 verify): `jq empty` only checks PARSEABILITY, so a 0-byte file
  # (truncated/interrupted write), whitespace, `null`, `[1,2,3]`, or `{"foo":1}`
  # all slip past it and then re-trigger the very swallowers above on `.files[]` —
  # the same false-PASS class, one rung down. This guard fires on anything that
  # isn't a JSON object carrying a `files` array (exactly what `download`'s `jq -n`
  # always builds, even for zero attachments → no regression). It deliberately does
  # NOT validate per-file fields (that deeper schema check is the deferred residue).
  # Same exit-2 = data-layer-failure semantics as the fetch-failure guard (#186).
  if ! jq -e 'type=="object" and (.files|type)=="array"' "$1" >/dev/null 2>&1; then
    echo "✗ Manifest is corrupt or malformed (not a JSON object with a 'files' array): $1" >&2
    echo "   Re-fetch to rebuild it: bash \$CLAUDE_PLUGIN_ROOT/scripts/process-attachments.sh download $NUMBER" >&2
    exit 2
  fi
}

decode_filename() {
  # ORDER, and why each step is where it is. The input is a URL, not a filename.
  #
  #   1. strip trailing markdown punctuation
  #   2. take the last path segment of the URL — split on REAL `/`, while a
  #      percent-encoded one is still just three characters
  #   3. decode
  #   4. REFUSE anything that is not a plain filename
  #
  # The original ran basename(2) and decoded (3) in the other order, so
  # `basename` could not see a separator that was still percent-encoded:
  # `…/%2e%2e%2f%2e%2e%2fpwned.txt` survived intact and only became
  # `../../pwned.txt` afterwards, joined onto the attachments directory and
  # resolving two levels up. The URL comes from an issue body, so it is
  # attacker-supplied wherever outside reports are accepted.
  #
  # The first fix decoded first and then FLATTENED with basename. That closed
  # the traversal but opened a collision: `%2e%2e%2ftrusted.pdf` and
  # `trusted.pdf` produced the SAME name, so a traversal-shaped URL on the same
  # issue could overwrite a real attachment — and the tests asserted the
  # flattened output, pinning "accept and flatten" while the comment beside them
  # said "refuse". Refusing is what was claimed, and it is what is safe: the
  # caller records a manifest error, which this plugin requires to be loud.
  # WHERE the validation runs matters as much as what it checks. The control
  # character test used to live in the shell, AFTER `dec=$(... python3 ...)` —
  # and command substitution strips NUL bytes and trailing newlines before the
  # value is assigned. So `*[[:cntrl:]]*` was written for precisely the two
  # inputs it could never see: `trusted.pdf%00` and `trusted.pdf%0A` both
  # arrived as `trusted.pdf`, colliding with a legitimate attachment of that
  # name — the collision the refuse-don`t-flatten change exists to prevent,
  # walking in through the guard meant to stop it. A guard placed downstream of
  # a lossy boundary is not a guard.
  #
  # It is now decided in python, on BYTES, before anything crosses that
  # boundary: `errors="strict"` so invalid UTF-8 is refused instead of being
  # folded to U+FFFD (which mapped `%FF.txt` and `%FE.txt` onto one name), and
  # an explicit reject list for NUL and every other control character. The shell
  # sees only an accepted name or a non-zero status.
  local seg dec
  seg=$(printf '%s' "$1" | sed 's/[)>"].*$//')
  seg=${seg##*/}
  dec=$(printf '%s' "$seg" | python3 -c '
import sys, urllib.parse
raw = sys.stdin.buffer.read().strip()
try:
    name = urllib.parse.unquote_to_bytes(raw).decode("utf-8", errors="strict")
except UnicodeDecodeError:
    sys.exit(1)                      # invalid UTF-8 — two of these fold to one name
if any(ord(c) < 32 or ord(c) == 127 for c in name):
    sys.exit(1)                      # NUL, LF, TAB, DEL — none survive the shell intact
sys.stdout.write(name)
') || return 1
  case "$dec" in
    ''|.|..)  return 1 ;;
    */*)      return 1 ;;   # a separator that was hiding inside an escape
    -*)       return 1 ;;   # a name that could be read as an option
  esac
  printf '%s\n' "$dec"
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
      # An explicit refusal must be recorded and skipped, not left to errexit.
      # `filename=$(decode_filename ...)` propagates the non-zero status, and
      # under `set -e` that aborted the WHOLE download — every attachment after
      # the refused one lost, with a partial manifest. Refusing one unsafe name
      # is not a reason to stop collecting the rest.
      if ! filename=$(decode_filename "$url"); then
        echo "⚠ refusing an unsafe attachment filename derived from: $url" >&2
        FILES_JSON=$(printf '%s' "$FILES_JSON" | jq \
          --arg url "$url" '. += [{filename: null, url: $url, error: "unsafe_filename"}]')
        continue
      fi
      # The name comes from the URL's LAST SEGMENT, which is not unique: two
      # perfectly legitimate attachments on one issue can both be `report.pdf`
      # from different repos. `curl -o` then wrote the second over the first,
      # the manifest kept BOTH rows (same filename, different url, different
      # sha256), and `verify` — which only checks that the path exists — passed
      # over an attachment that was irrecoverably gone.
      #
      # Disambiguated deterministically rather than refused: both files are
      # legitimate and the caller asked for both. The suffix is derived from the
      # URL, so re-running produces the same name, and it is inserted before the
      # extension so the file still opens with the right application.
      if [ -e "$ATTACH_DIR/$filename" ] \
         && [ "$(printf '%s' "$FILES_JSON" | jq -r --arg f "$filename" --arg u "$url" \
                  '[.[] | select(.filename == $f and .url != $u)] | length')" != "0" ]; then
        sfx=$(printf '%s' "$url" | shasum -a 256 | cut -c1-8)
        case "$filename" in
          *.*) filename="${filename%.*}-${sfx}.${filename##*.}" ;;
          *)   filename="${filename}-${sfx}" ;;
        esac
        echo "ℹ two attachments share the basename — the second is stored as $filename" >&2
      fi
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

    # A refused entry keeps its URL, so it counts as KNOWN and `check` used to
    # print a bare "up-to-date" over an attachment that is not on disk and never
    # will be. It IS known — re-running download reproduces the same refusal —
    # so it must not be reported as drift; but it must not be silent either.
    REFUSED=$(jq '[.files[] | select(.error == "unsafe_filename")] | length' "$MANIFEST" 2>/dev/null || echo 0)
    echo "✓ Manifest up-to-date for #$NUMBER ($(jq '.files | length' "$MANIFEST") files)"
    if [ "${REFUSED:-0}" -gt 0 ]; then
      echo "⚠ $REFUSED attachment(s) refused for an unsafe filename — permanently unavailable, not re-fetchable." >&2
      jq -r '.files[] | select(.error == "unsafe_filename") | "   refused: \(.url)"' "$MANIFEST" >&2
    fi
    ;;

  verify)
    if [ ! -f "$MANIFEST" ]; then
      echo "ℹ No manifest for #$NUMBER (skipping verify)."
      exit 0
    fi

    assert_manifest_valid "$MANIFEST"   # #189 — corrupt manifest must loud-fail, not false "all present"
    # `select(.filename != null)`, and the reason is the difference between the
    # two ways an entry can lack a file on disk:
    #
    #   download_failed   keeps a real filename, and is TRANSIENT. Re-fetching
    #                     clears it, which is exactly what this gate should
    #                     force. Still blocks.
    #   unsafe_filename   has filename == null, and is DETERMINISTIC. Re-fetching
    #                     reproduces the same refusal.
    #
    # Without the select, `jq -r` printed the literal string `null`, `[ -z ]` was
    # false, and the loop tested `-f "$ATTACH_DIR/null"` — so one attacker-shaped
    # (or merely dash-leading) attachment URL made this exit 1 forever, and this
    # is idd-close Step 1.4. A gate with no remediation path does not gate, it
    # bricks. So a refusal is reported and does not block; only drift blocks.
    MISSING=0
    while IFS= read -r filename; do
      [ -z "$filename" ] && continue
      if [ ! -f "$ATTACH_DIR/$filename" ]; then
        echo "⚠ Manifest references $filename but file missing on disk." >&2
        MISSING=$((MISSING + 1))
      fi
    done < <(jq -r '.files[] | select(.filename != null) | .filename' "$MANIFEST" 2>/dev/null)

    REFUSED=$(jq '[.files[] | select(.error == "unsafe_filename")] | length' "$MANIFEST" 2>/dev/null || echo 0)
    if [ "${REFUSED:-0}" -gt 0 ]; then
      echo "⚠ $REFUSED attachment(s) were refused at download time for an unsafe filename." >&2
      jq -r '.files[] | select(.error == "unsafe_filename") | "   refused: \(.url)"' "$MANIFEST" >&2
      echo "   They are permanently unavailable — do NOT reference them in the closing comment." >&2
    fi

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
