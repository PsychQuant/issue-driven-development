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

rm -rf "$STUB"
print_summary
