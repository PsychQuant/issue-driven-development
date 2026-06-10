#!/usr/bin/env bash
# test.sh — fixtures for process-attachments.sh zero-attachment contract
# (PsychQuant/issue-driven-development#186)
#
# The contract (idd-diagnose SKILL.md Step 1.5): an issue with NO attachment
# URLs → empty `_manifest.json` written + exit 0. The bug: `detect_urls()` is a
# pipeline ending in grep; zero matches → grep exit 1 → pipefail → `set -e`
# kills the script at the `URLS=$(detect_urls)` assignment, silently, before
# the empty-manifest branch. THREE call sites are affected (download L130,
# check L178, check L188), so the fixtures cover all three — plus the
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

# ── Fixture 1 (L130): zero-attachment download → exit 0 + empty manifest ──
W="$(mktemp -d)"; cd "$W"
export GH_STUB_MODE=empty
run_pa download 7 > "$W/out1.txt" 2>&1; RC=$?
assert_exit "f1a download exit 0 on zero attachments" 0 "$RC"
require "f1b empty manifest written"  test -s "$W/.claude/.idd/attachments/issue-7/_manifest.json"
require "f1c manifest has files: []"  bash -c "jq -e '.files == []' '$W/.claude/.idd/attachments/issue-7/_manifest.json' >/dev/null"
require "f1d visible output (not silent)"  grep -q 'no attachments' "$W/out1.txt"

# ── Fixture 2 (L188): zero-attachment check WITH manifest present → exit 0 ──
#    (the third call site — proof that fixing download alone is not enough)
run_pa check 7 >/dev/null 2>&1
assert_exit "f2 check exit 0 (manifest exists, zero attachments — L188 call site)" 0 $?
cd /; rm -rf "$W"

# ── Fixture 3 (L178): zero-attachment check with NO manifest → exit 0 ──
W="$(mktemp -d)"; cd "$W"
run_pa check 8 > "$W/out3.txt" 2>&1; RC=$?
assert_exit "f3a check exit 0 (no manifest, zero attachments — L178 call site)" 0 "$RC"
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

rm -rf "$STUB"
print_summary
