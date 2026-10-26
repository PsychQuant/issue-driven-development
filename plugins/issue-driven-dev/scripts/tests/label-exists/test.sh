#!/usr/bin/env bash
# Test: idd-issue's label_exists() answers by an exact REST lookup (#411).
#
# The old probe was `gh label list --search "$1" … | grep -qx "$1"`. Three things
# made it answer "missing" for labels that exist:
#   - `--search` is a best-match search capped at 30 results, so an existing label
#     can be absent from what it returns (P0 was, in the report);
#   - `gh label list` is GraphQL, which Claude Code cloud sessions block;
#   - `grep -qx "$1"` reads the name as a pattern, so `[RFC]` or `-wip` never match.
# It also ran against `$REPO`, which Step 2.6 sets to the bare repo name.
#
# The function is RUN out of SKILL.md against a stub `gh` whose `label list`
# returns nothing (as the search did for P0) and whose REST label endpoint knows the
# repo's labels. A control runs the old function against the same stub and must get
# the old wrong answer, so the stub really reproduces the bug.
#
# Usage: bash test.sh   (exit 0 = pass, 1 = fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
SKILL="$PLUGIN/skills/idd-issue/SKILL.md"
. "$PLUGIN/scripts/lib/assert-helpers.sh"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/label-exists-XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

FN="$(awk '/^label_exists\(\) \{/{f=1} f{print} f&&/^\}/{exit}' "$SKILL")"
assert_true "label_exists() is extractable from SKILL.md" '[ -n "$FN" ]'

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case "$1 $2" in
  "label list") exit 0 ;;   # the search found nothing — what it did for P0
esac
[ "$1" = api ] || { echo "unexpected gh $*" >&2; exit 1; }
case "$2" in
  repos/o/r/labels/netfail) echo "gh: HTTP 502: Bad Gateway" >&2; exit 1 ;;
  repos/o/r/labels/*)
    name=$(python3 -c 'import sys, urllib.parse; print(urllib.parse.unquote(sys.argv[1]))' "${2#repos/o/r/labels/}")
    for l in bug P0 "good first issue" "[RFC]" "-wip"; do
      [ "$(printf '%s' "$l" | tr A-Z a-z)" = "$(printf '%s' "$name" | tr A-Z a-z)" ] && exit 0
    done
    echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;;
  *) echo "unexpected api $2" >&2; exit 1 ;;
esac
STUB
chmod +x "$TMP/bin/gh"
export GH_LOG="$TMP/gh.log"
probe() { # $1 function source, $2 label → stderr on stdout; returns the function's code
  PATH="$TMP/bin:$PATH" GITHUB_REPO=o/r REPO=r bash -c "$1"$'\n''label_exists "$0"' "$2" 2>&1
}

for l in P0 "good first issue" "[RFC]" "-wip" "Bug"; do
  : > "$GH_LOG"; probe "$FN" "$l" >/dev/null; RC=$?
  assert_exit "an existing label is found: '$l'" 0 "$RC"
  refute_grep "…without gh label list (best-match search, GraphQL)" "label list" "$(cat "$GH_LOG")"
  assert_grep "…on the full OWNER/REPO, not the bare repo name" "api repos/o/r/labels/" "$(cat "$GH_LOG")"
done
: > "$GH_LOG"; probe "$FN" "good first issue" >/dev/null
assert_grep "the name is URL-encoded in the path" "repos/o/r/labels/good%20first%20issue" "$(cat "$GH_LOG")"
: > "$GH_LOG"; probe "$FN" "nothere" >/dev/null; RC=$?
assert_exit "a missing label is reported missing (exit 1)" 1 "$RC"
for l in . .. "" ./bug bug/. a/../bug; do
  : > "$GH_LOG"; probe "$FN" "$l" >/dev/null; RC=$?
  refute "'$l' is never reported as existing" test "$RC" -eq 0
  assert_eq "…and makes no request (labels/. would read the label list)" "" "$(cat "$GH_LOG")"
done
: > "$GH_LOG"; OUT="$(probe "$FN" netfail)"; RC=$?
assert_exit "a failed lookup is not 'missing': exit 2" 2 "$RC"
assert_grep "…and gh's message is shown" "HTTP 502" "$OUT"

# control: the old probe against the same stub gives the old wrong answer
OLD='label_exists() {
  gh label list --repo "$REPO" --search "$1" --json name --jq '"'"'.[].name'"'"' | grep -qx "$1"
}'
probe "$OLD" P0 >/dev/null; RC=$?
assert_exit "control: the old --search probe misses the existing P0 on this stub" 1 "$RC"

refute_output_grep "SKILL.md no longer probes with --search" '--search "$1"' "$SKILL"
print_summary "label-exists (#411)"
