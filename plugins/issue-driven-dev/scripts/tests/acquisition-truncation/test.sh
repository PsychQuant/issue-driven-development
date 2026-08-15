#!/usr/bin/env bash
# Test: the >100-comment acquisition repair in check-closed-without-summary.sh.
#
# WHY THIS SUITE EXISTS
#
# `gh issue list --json comments` resolves the nested connection as
# `comments(first: 100)` and returns the OLDEST 100. A closing summary is by
# construction the NEWEST comment, so on any issue past 100 comments it is
# exactly the element dropped — and the classifier then says `missing`, the one
# class that invites the irreversible `--retroactive`.
#
# The repair for that lives in the live-`gh` branch, which every other suite
# skips because `--json-file` short-circuits it. The result: a post-merge audit
# deleted all nineteen lines of the repair and 46/46 suites stayed green. This
# suite closes that hole by stubbing `gh` on PATH, so the real code runs.
#
# Usage: bash test.sh   (exit 0 = pass, 1 = fail)

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$(cd "$HERE/../.." && pwd)/check-closed-without-summary.sh"
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"

STUB=$(mktemp -d); trap 'rm -rf "$STUB"' EXIT

# `gh` stub: `issue list` returns one closed issue whose comment array is capped
# at 100 with NO heading (exactly what the real API does); `api .../comments`
# paginates, emitting ONE ARRAY PER PAGE like the real `--paginate --jq`, with
# the closing summary in the final page.
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
case "$1 $2" in
  "issue list")
    python3 -c '
import json
print(json.dumps([{"number":4242,"title":"long issue, summary past the cap",
 "state":"CLOSED","comments":[{"body":"c%d"%i} for i in range(100)]}]))'
    ;;
  "api "*|"repo view")
    if [ "$1" = "repo view" ] || [ "$2" = "view" ]; then echo "o/r"; exit 0; fi
    # two pages, each its own JSON array — the shape that broke --argjson
    python3 -c '
import json
print(json.dumps([{"body":"c%d"%i} for i in range(100)]))
print(json.dumps([{"body":"## Closing Summary\n\n### Problem\nreal"}]))'
    ;;
  *) echo "[]" ;;
esac
STUBEOF
chmod +x "$STUB/gh"

OUT=$(PATH="$STUB:$PATH" bash "$HELPER" --repo o/r 2>&1); RC=$?

assert_exit "advisory exit 0 even on the live-gh path" 0 "$RC"

# THE assertion: the summary lives past the cap, so a working repair finds it and
# the issue stays quiet. A broken repair (or none) reports it MISSING and invites
# the duplicate post.
# NOT "absent from MISSING" — that is also satisfied by a repair which merely
# FAILED SAFELY (the issue then lands in PRESENT). The assertion must separate
# "the summary was recovered" from "we gave up without doing damage", so it
# demands the issue be QUIET: recovered, compliant, printed in no section at
# all. The first cut asserted the weaker thing, and reverting the pagination fix
# left it green — a test that could not see the bug it was written for.
refute_grep "an issue whose summary is past the cap is RECOVERED (quiet, not merely non-missing)" \
  "4242" "$OUT"
# CANARY. "4242 is absent" is ALSO satisfied by the audit dying before it prints
# anything — and reverting the pagination fix does exactly that (the merge fails,
# the guard aborts). Without this line the suite stayed green on that mutation:
# the assertion could not tell "recovered" from "never ran".
assert_grep "…and the audit actually completed rather than aborting" \
  "No closed issue is missing" "$OUT"
refute_grep "…with no skip notice" "audit skipped" "$OUT"

# The fail-safe half: when the re-fetch cannot be completed, the issue must fall
# to PRESENT, never to MISSING. Stub a failing api call.
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
case "$1 $2" in
  "issue list")
    python3 -c '
import json
print(json.dumps([{"number":4243,"title":"refetch fails","state":"CLOSED",
 "comments":[{"body":"c%d"%i} for i in range(100)]}]))'
    ;;
  "repo view") echo "o/r" ;;
  *) exit 1 ;;
esac
STUBEOF
chmod +x "$STUB/gh"
OUT2=$(PATH="$STUB:$PATH" bash "$HELPER" --repo o/r 2>&1); RC2=$?
assert_exit "advisory exit 0 when the re-fetch fails" 0 "$RC2"
refute_grep "a failed re-fetch never reaches MISSING" \
  "4243" "$(printf '%s\n' "$OUT2" | sed -n '/^MISSING/,/^$/p')"

# The shrink guard: a re-fetch that returns FEWER comments than we already had
# is a partial page. Swapping it in would delete evidence and could route a real
# summary to MISSING, so it must be refused and the issue marked instead.
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
case "$1 $2" in
  "issue list")
    python3 -c '
import json
print(json.dumps([{"number":4244,"title":"refetch returns fewer","state":"CLOSED",
 "comments":[{"body":"## Closing Summary\n\n### Problem\nreal"}] + [{"body":"c%d"%i} for i in range(99)]}]))'
    ;;
  "repo view") echo "o/r" ;;
  *) python3 -c 'import json; print(json.dumps([{"body":"only one comment came back"}]))' ;;
esac
STUBEOF
chmod +x "$STUB/gh"
OUT3=$(PATH="$STUB:$PATH" bash "$HELPER" --repo o/r 2>&1); RC3=$?
assert_exit "advisory exit 0 when the re-fetch shrinks the set" 0 "$RC3"
refute_grep "a shrinking re-fetch must not delete the evidence we already had" \
  "4244" "$(printf '%s\n' "$OUT3" | sed -n '/^MISSING/,/^$/p')"
assert_grep "…and that run completed too" "closed issue" "$OUT3"

# `.number` is fetched data and gets interpolated into a `gh api` path, so it is
# validated as an integer first. Without a case that exercises it, the guard was
# just an untested line.
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
case "$1 $2" in
  "issue list")
    python3 -c '
import json
print(json.dumps([{"number":"4245 --hostname evil.example","title":"non-numeric id",
 "state":"CLOSED","comments":[{"body":"c%d"%i} for i in range(100)]}]))'
    ;;
  "repo view") echo "o/r" ;;
  *) echo "SHOULD-NOT-BE-CALLED-WITH-A-NON-NUMERIC-ID" ;;
esac
STUBEOF
chmod +x "$STUB/gh"
OUT4=$(PATH="$STUB:$PATH" bash "$HELPER" --repo o/r 2>&1); RC4=$?
assert_exit "advisory exit 0 on a non-numeric issue id" 0 "$RC4"
assert_grep "a non-numeric id is refused before it reaches the api path" \
  "skipping non-numeric issue id" "$OUT4"
refute_grep "…and the api call is never made with it" \
  "SHOULD-NOT-BE-CALLED" "$OUT4"

print_summary "acquisition-truncation"
exit $?
