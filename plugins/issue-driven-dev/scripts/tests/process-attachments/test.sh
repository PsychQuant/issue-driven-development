#!/usr/bin/env bash
# test.sh — fixtures for process-attachments.sh zero-attachment contract
# (PsychQuant/issue-driven-development#186)
#
# The contract (idd-diagnose SKILL.md Step 1.5): an issue with NO attachment
# URLs → empty `_manifest.json` written + exit 0. The bug: `detect_urls()` is a
# pipeline ending in grep; zero matches → grep exit 1 → pipefail → `set -e`
# kills the script at the `URLS=$(detect_urls)` assignment, silently, before
# the empty-manifest branch. THREE call sites are affected (download's URLS=,
# check's no-manifest URLS=, check's with-manifest CURRENT=), so the fixtures cover all three — plus the
# loud-failure contract: a REAL gh failure must NOT be swallowed into a fake
# "no attachments" empty manifest.
#
# gh is stubbed via PATH prepend; mode controlled by $GH_STUB_MODE
# (empty / with_url / fail). First gh-stub test in this repo.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../process-attachments.sh"
. "$HERE/../../lib/assert-helpers.sh"

# --- gh stub -----------------------------------------------------------------
STUB="$(mktemp -d)"
cat > "$STUB/gh" <<'GHSTUB'
#!/usr/bin/env bash
case "${1:-}" in
  issue)  # gh issue view N --repo R --json body,comments
    case "${GH_STUB_MODE:-empty}" in
      empty)    printf '{"body":"## Problem\\nno attachment urls here","comments":[{"body":"plain comment"}]}\n' ;;
      with_url) printf '{"body":"spec: https://github.com/user-attachments/files/123/spec.docx ok","comments":[]}\n' ;;
      # The three ways a real issue body wraps a URL. Each used to come back
      # with the wrapper glued on, producing a link that 404s — and an
      # attachment that cannot be downloaded is an attachment that gets
      # ignored, which this plugin treats as ignoring the source.
      wrapped)  printf '{"body":"autolink <https://github.com/user-attachments/files/1/a.pdf>\\nhtml <img src=\\"https://github.com/user-attachments/assets/2/b.png\\">\\nsentence see https://github.com/user-attachments/files/3/c.pdf.","comments":[]}\n' ;;
      # one unsafe URL followed by a legitimate one — the ordering matters,
      # because the bug lost everything AFTER the refusal.
      refusable) printf '{"body":"bad https://github.com/user-attachments/files/1/%%2e%%2e%%2fpwned.txt and good https://github.com/user-attachments/files/2/safe.pdf","comments":[]}\n' ;;
      fail)     echo "gh: network error (stub)" >&2; exit 1 ;;
    esac ;;
  auth)   echo "stub-token" ;;
  *)      echo "gh-stub: unhandled: $*" >&2; exit 1 ;;
esac
GHSTUB
chmod +x "$STUB/gh"
export PATH="$STUB:$PATH"

run_pa() { # cmd issue-number  (cwd must be the fixture workdir)
  bash "$SCRIPT" "$1" "$2" --repo stub/repo
}

echo "process-attachments zero-attachment contract"

# ── Fixture 1 (download call site): zero-attachment download → exit 0 + empty manifest ──
W="$(mktemp -d)"; cd "$W"
export GH_STUB_MODE=empty
run_pa download 7 > "$W/out1.txt" 2>&1; RC=$?
assert_exit "f1a download exit 0 on zero attachments" 0 "$RC"
require "f1b empty manifest written"  test -s "$W/.claude/.idd/attachments/issue-7/_manifest.json"
require "f1c manifest has files: []"  bash -c "jq -e '.files == []' '$W/.claude/.idd/attachments/issue-7/_manifest.json' >/dev/null"
require "f1d visible output (not silent)"  grep -q 'no attachments' "$W/out1.txt"

# ── Fixture 2 (check with-manifest call site): zero-attachment check WITH manifest present → exit 0 ──
#    (the third call site — proof that fixing download alone is not enough)
run_pa check 7 >/dev/null 2>&1
assert_exit "f2 check exit 0 (manifest exists, zero attachments — CURRENT= call site)" 0 $?
cd /; rm -rf "$W"

# ── Fixture 3 (check no-manifest call site): zero-attachment check with NO manifest → exit 0 ──
W="$(mktemp -d)"; cd "$W"
run_pa check 8 > "$W/out3.txt" 2>&1; RC=$?
assert_exit "f3a check exit 0 (no manifest, zero attachments — no-manifest call site)" 0 "$RC"
require "f3b says no manifest needed"  grep -q 'no attachments' "$W/out3.txt"
cd /; rm -rf "$W"

# ── Fixture 4 (regression guard): with-attachment behavior unchanged ──
W="$(mktemp -d)"; cd "$W"
export GH_STUB_MODE=with_url
run_pa check 9 > "$W/out4.txt" 2>&1; RC=$?
assert_exit "f4a check exit 1 when attachments exist but manifest missing" 1 "$RC"
# NB file+require (no eval): the warning contains a literal $CLAUDE_PLUGIN_ROOT,
# which assert_true's eval would re-expand under set -u -> false FAIL (#154 class)
require "f4b warning mentions manifest missing"  grep -q 'manifest missing' "$W/out4.txt"
cd /; rm -rf "$W"

# ── Fixture 5 (loud-failure contract): gh failure must NOT become an empty manifest ──
W="$(mktemp -d)"; cd "$W"
export GH_STUB_MODE=fail
run_pa download 10 >/dev/null 2>&1
RC=$?
refute  "f5a gh failure → download exits non-zero (loud)"  test "$RC" -eq 0
refute  "f5b gh failure → NO manifest written (not swallowed as 'no attachments')"  test -e "$W/.claude/.idd/attachments/issue-10/_manifest.json"
cd /; rm -rf "$W"

# ── Fixture 6 (#189): corrupt manifest → check loud-fails (NOT false "up-to-date") ──
#    jq parse error was swallowed (2>/dev/null + || true) → empty KNOWN → false PASS.
W="$(mktemp -d)"; cd "$W"; mkdir -p .claude/.idd/attachments/issue-11
export GH_STUB_MODE=empty
printf '{ broken json <<<<<<< HEAD\n' > .claude/.idd/attachments/issue-11/_manifest.json
run_pa check 11 > "$W/out6.txt" 2>&1; RC6=$?
refute  "f6a corrupt manifest → check exits non-zero (not false up-to-date)"  test "$RC6" -eq 0
require "f6b check says manifest corrupt (loud)"  grep -qi 'corrupt' "$W/out6.txt"
cd /; rm -rf "$W"

# ── Fixture 7 (#189): corrupt manifest → verify loud-fails (verify IS idd-close Step 1.4 gate) ──
#    process-substitution `< <(jq ... 2>/dev/null)` never propagated jq exit → MISSING=0 → false PASS.
#    Realistic corruption: git merge-conflict markers (manifest is git-tracked).
W="$(mktemp -d)"; cd "$W"; mkdir -p .claude/.idd/attachments/issue-12
printf '{\n  "issue": 12,\n<<<<<<< HEAD\n  "files": []\n=======\n  "files": [{"filename":"a.png"}]\n>>>>>>> branch\n}\n' \
  > .claude/.idd/attachments/issue-12/_manifest.json
run_pa verify 12 > "$W/out7.txt" 2>&1; RC7=$?
refute  "f7a corrupt manifest → verify exits non-zero (not false 'all present')"  test "$RC7" -eq 0
require "f7b verify says manifest corrupt (loud)"  grep -qi 'corrupt' "$W/out7.txt"
cd /; rm -rf "$W"

# ── Fixture 8 (regression guard): VALID manifest → check + verify behavior unchanged ──
W="$(mktemp -d)"; cd "$W"; mkdir -p .claude/.idd/attachments/issue-13
printf 'content' > .claude/.idd/attachments/issue-13/a.png
cat > .claude/.idd/attachments/issue-13/_manifest.json <<'JSON'
{"issue":13,"fetched_at":"x","fetched_by":"test","files":[{"filename":"a.png","url":"https://github.com/user-attachments/files/1/a.png","sha256":"x","size_bytes":7}]}
JSON
export GH_STUB_MODE=empty
run_pa verify 13 >/dev/null 2>&1; assert_exit "f8a valid manifest + file present → verify exit 0 (unchanged)" 0 $?
run_pa check  13 >/dev/null 2>&1; assert_exit "f8b valid manifest → check exit 0 (unchanged)"               0 $?
cd /; rm -rf "$W"

# ── Fixture 9 (#189 verify): 0-byte manifest (truncated/interrupted write) → loud-fail ──
#    Parses past `jq empty` but is NOT a manifest — verify (idd-close's gate) must not false-PASS.
W="$(mktemp -d)"; cd "$W"; mkdir -p .claude/.idd/attachments/issue-14
: > .claude/.idd/attachments/issue-14/_manifest.json            # 0 bytes
run_pa verify 14 > "$W/out9.txt" 2>&1; RC9=$?
refute  "f9a 0-byte manifest → verify exits non-zero"  test "$RC9" -eq 0
require "f9b 0-byte manifest → verify says corrupt/malformed (loud)"  grep -qiE 'corrupt|malformed' "$W/out9.txt"
cd /; rm -rf "$W"

# ── Fixture 10 (#189 verify): valid JSON but not a manifest (no .files) → loud-fail ──
W="$(mktemp -d)"; cd "$W"; mkdir -p .claude/.idd/attachments/issue-15
printf '{"foo":1}\n' > .claude/.idd/attachments/issue-15/_manifest.json
export GH_STUB_MODE=empty
run_pa check 15 > "$W/out10.txt" 2>&1; RC10=$?
refute  "f10a schemaless manifest ({\"foo\":1}) → check exits non-zero"  test "$RC10" -eq 0
require "f10b schemaless manifest → check says corrupt/malformed (loud)"  grep -qiE 'corrupt|malformed' "$W/out10.txt"
cd /; rm -rf "$W"

# ── Fixture 11 (post-merge audit): URLs wrapped the way real issue bodies wrap
# them. The extractor's character class excluded `)` and whitespace only, so an
# autolink kept its `>`, an HTML attribute kept its `">`, and a URL at the end
# of a sentence kept the full stop. Each of those downloads 404s, and a file
# that cannot be downloaded is a source that gets ignored — the one thing the
# attachment rule says must never happen quietly.
W="$(mktemp -d)"; cd "$W"
export GH_STUB_MODE=wrapped
run_pa download 21 > "$W/out11.txt" 2>&1
MAN11=".claude/.idd/attachments/issue-21/_manifest.json"
require "f11a wrapped-URL run still writes a manifest" test -f "$MAN11"
URLS11=$(jq -r '.files[].url, (.errors[]?.url // empty)' "$MAN11" 2>/dev/null; jq -r '.[]?.url // empty' "$MAN11" 2>/dev/null)
# Whatever the manifest ends up recording, no recorded URL may carry a wrapper.
refute_grep_re "f11b no extracted URL keeps an autolink '>'"      '>' "$URLS11"
refute_grep_re "f11c no extracted URL keeps an HTML quote"        '"' "$URLS11"
refute_grep_re "f11d no extracted URL keeps a sentence full stop" '\.$' "$URLS11"
assert_eq "f11e all three URLs were extracted" "3" "$(printf '%s\n' "$URLS11" | grep -c 'github.com')"
cd /; rm -rf "$W"

# ── Fixture 12 (#320 verify, security HIGH): percent-encoded path traversal ──
#
# `decode_filename` took `basename` FIRST and URL-decoded AFTER. basename cannot
# see a separator that is still percent-encoded, so a URL ending in
# `%2e%2e%2f%2e%2e%2fpwned.txt` passed through basename intact and only became
# `../../pwned.txt` afterwards — after which it was joined onto the attachments
# directory and resolved to `.claude/.idd/pwned.txt`, two levels up. The URL
# comes out of an issue body, so it is attacker-supplied on any repo that takes
# outside reports.
#
# The function is sourced directly: the traversal is in the NAME DERIVATION, and
# routing it through a download would test the network stub instead.
eval "$(sed -n '/^decode_filename()/,/^}/p' "$SCRIPT")"

# CORRECTED (round 11): these asserted the FLATTENED output — `pwned.txt` — which
# pinned "must accept and flatten" while the comment beside the code said
# "refuse anything that is not a plain filename". The test fixed the opposite of
# the stated requirement in place. Flattening is also unsafe on its own terms:
# `%2e%2e%2ftrusted.pdf` and `trusted.pdf` flatten to the SAME name, so a
# traversal-shaped URL on one issue can collide with, and overwrite, a real
# attachment.
refute "f12a a percent-encoded traversal is REFUSED, not flattened" \
  decode_filename 'https://github.com/user-attachments/files/1/%2e%2e%2f%2e%2e%2fpwned.txt'
# A LITERAL traversal needs no refusal: taking the URL's last path segment
# already yields a plain name, and the `..` segments never reach the filesystem.
# Refusing it would have been the wrong requirement — asserted here as the safe
# OUTCOME rather than as a rejection, so the distinction is recorded rather than
# rediscovered.
assert_eq "f12b a literal traversal yields a plain name, no escape" \
  "pwned.txt" \
  "$(decode_filename 'https://github.com/user-attachments/files/1/../../pwned.txt')"
# The collision this prevents, asserted directly rather than implied.
if decode_filename 'https://x/%2e%2e%2ftrusted.pdf' >/dev/null 2>&1; then
  fail "f12c a traversal-shaped URL cannot collide with a real attachment name" \
       "it produced a name instead of being refused"
else
  pass "f12c a traversal-shaped URL cannot collide with a real attachment name"
fi
assert_eq "f12d ...while the real attachment keeps its name" \
  "trusted.pdf" "$(decode_filename 'https://x/trusted.pdf')"
# A leading dash could be read as an option by anything downstream. The previous
# guard was a no-op: it prepended `./` and stripped it again, so `%2d%2drf` still
# came out as `--rf`. Nothing asserted it, so nothing noticed.
refute "f12e a name that decodes to a leading dash is refused" \
  decode_filename 'https://x/%2d%2drf'
# The legitimate cases must survive — CJK and spaces are ordinary here, and
# mangling them would break the manifest-to-disk correspondence.
assert_eq "f12f percent-encoded spaces and CJK still decode" \
  "報告 final.pdf" \
  "$(decode_filename 'https://github.com/user-attachments/files/2/%E5%A0%B1%E5%91%8A%20final.pdf')"
assert_eq "f12g trailing markdown punctuation is still stripped" \
  "normal.png" \
  "$(decode_filename 'https://github.com/user-attachments/files/3/normal.png)')"
refute "f12h a name that decodes to '..' is refused outright" \
  decode_filename 'https://x/%2e%2e'

# ── Fixture 13: a refused filename must SKIP that URL, not kill the run ──
#
# `filename=$(decode_filename "$url")` propagates the refusal, and under
# `set -euo pipefail` that aborted the whole download — every attachment after
# the unsafe one lost, with a partial manifest written or none at all. The
# refusal was correct; leaving it to errexit was not.
W="$(mktemp -d)"; cd "$W"
export GH_STUB_MODE=refusable
run_pa download 22 > "$W/out13.txt" 2>&1; RC13=$?
MAN13=".claude/.idd/attachments/issue-22/_manifest.json"
require "f13a a refused name does not abort the run" test -f "$MAN13"
require "f13b the refusal is recorded, not silently dropped" \
  bash -c 'jq -e ".files[] | select(.error == \"unsafe_filename\")" "$0" >/dev/null' "$MAN13"
require "f13c the SAFE attachment beside it is still collected" \
  bash -c 'jq -e ".files[] | select(.filename == \"safe.pdf\")" "$0" >/dev/null' "$MAN13"
require "f13d and the refusal is visible on stderr" grep -q 'refusing an unsafe' "$W/out13.txt"
cd /; rm -rf "$W"

rm -rf "$STUB"
print_summary
