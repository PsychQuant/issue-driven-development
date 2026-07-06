#!/usr/bin/env bash
# test.sh — regression lock for the repo line-ending policy (#216)
#
# Locks the two load-bearing facts of .gitattributes:
#   1. The deliberate CRLF fixture keeps its CRLF bytes (the -text exemption is
#      present AND effective). Without this lock, deleting the -text line would
#      silently degrade fixture 19-section-replace-crlf from a CRLF test into an
#      LF test with no failing test anywhere (#216 verify, devils-advocate finding).
#   2. The global `* text=auto eol=lf` policy line exists, so newly added CRLF
#      text files normalize to LF in the index.
#
# Read-only: no index/working-tree mutation (safe to run with staged changes).

set -u

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../.." && pwd)"
FIXTURE="plugins/issue-driven-dev/scripts/tests/idd-edit/fixtures/19-section-replace-crlf/input.md"
PASS=0
FAIL=0

check() { # <label> <cmd...>
  local label="$1"; shift
  if "$@" > /dev/null 2>&1; then
    echo "  ✓ $label"; PASS=$((PASS + 1))
  else
    echo "  ✗ $label"; FAIL=$((FAIL + 1))
  fi
}

cd "$REPO_ROOT" || { echo "✗ cannot cd to repo root"; exit 1; }

# 1a. .gitattributes exists with the global LF policy line
check "policy: .gitattributes has global '* text=auto eol=lf'" \
  grep -qE '^\* text=auto eol=lf$' .gitattributes

# 1b. the CRLF fixture has an explicit -text exemption line
check "policy: fixture has -text exemption line" \
  grep -qF "$FIXTURE -text" .gitattributes

# 2. attribute resolution: text must be UNSET for the fixture (exemption effective)
TEXT_ATTR="$(git check-attr text -- "$FIXTURE" | awk -F': ' '{print $NF}')"
check "check-attr: fixture 'text' resolves to unset (got: $TEXT_ATTR)" \
  test "$TEXT_ATTR" = "unset"

# 3. index state: fixture is stored with CRLF (i/crlf)
INDEX_EOL="$(git ls-files --eol -- "$FIXTURE" | awk '{print $1}')"
check "index: fixture stored as i/crlf (got: $INDEX_EOL)" \
  test "$INDEX_EOL" = "i/crlf"

# 4. working copy bytes: fixture actually contains CRLF sequences
check "worktree: fixture bytes contain CRLF" \
  grep -q $'\r' "$FIXTURE"

echo "================================"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
