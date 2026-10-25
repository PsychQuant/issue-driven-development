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
# skips because `--json-file` short-circuits it. (Since #416 the acquisition reads
# through gh-rest, which pages comments in full; the repair is now a safety net.) The result: a post-merge audit
# deleted all nineteen lines of the repair and 46/46 suites stayed green. This
# suite closes that hole by stubbing `gh` on PATH, so the real code runs.
#
# Usage: bash test.sh   (exit 0 = pass, 1 = fail)

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$(cd "$HERE/../.." && pwd)/check-closed-without-summary.sh"
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"

STUB=$(mktemp -d); trap 'rm -rf "$STUB"' EXIT

# #416: the acquisition now reads through lib/gh-rest.sh (REST), which pages the
# comments in full, so the 100-comment cap no longer happens at acquisition. The
# repair loop stays as a safety net and is still exercised: every issue below
# reaches it with >= 100 comments. The stubs answer REST paths only:
#   repos/o/r/issues?state=closed&per_page=100&page=1     the closed-issue list
#   repos/o/r/issues/N/comments?per_page=100&page=K       gh-rest's comment pages
#   repos/o/r/issues/N/comments  (+ --paginate --jq)      the repair's re-fetch,
#                                                         ONE ARRAY PER PAGE
list_row() { printf '[{"number":%s,"title":"%s","state":"closed","closed_at":"2026-02-01T00:00:00Z"}]\n' "$1" "$2"; }
export -f list_row

# 1. The summary sits past the first 100 comments: it must be found, the issue quiet.
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
[ "$1" = "api" ] || { echo "unexpected porcelain gh $*" >&2; exit 1; }
case "$2" in
  'repos/o/r/issues?state=closed&per_page=100&page=1') list_row 4242 "long issue, summary past the cap" ;;
  'repos/o/r/issues/4242/comments?per_page=100&page=1') python3 -c 'import json; print(json.dumps([{"body":"c%d"%i} for i in range(100)]))' ;;
  'repos/o/r/issues/4242/comments?per_page=100&page=2') python3 -c 'import json; print(json.dumps([{"body":"## Closing Summary\n\n### Problem\nreal"}]))' ;;
  repos/o/r/issues/4242/comments)
    python3 -c '
import json
print(json.dumps([{"body":"c%d"%i} for i in range(100)]))
print(json.dumps([{"body":"## Closing Summary\n\n### Problem\nreal"}]))' ;;
  *) echo "[]" ;;
esac
STUBEOF
chmod +x "$STUB/gh"; export STUB_LOG="$STUB/calls.log"

OUT=$(PATH="$STUB:$PATH" bash "$HELPER" --repo o/r 2>&1); RC=$?

assert_exit "advisory exit 0 even on the live-gh path" 0 "$RC"

# THE assertion: the summary lives past the first 100 comments, so a complete read
# finds it and the issue stays quiet. NOT "absent from MISSING" — that is also
# satisfied by a read which merely FAILED SAFELY (the issue then lands in
# PRESENT). The assertion demands the issue be QUIET: recovered, compliant,
# printed in no section at all.
refute_grep "an issue whose summary is past the cap is RECOVERED (quiet, not merely non-missing)" \
  "4242" "$OUT"
# CANARY. "4242 is absent" is ALSO satisfied by the audit dying before it prints
# anything. Without this line the suite cannot tell "recovered" from "never ran".
assert_grep "…and the audit actually completed rather than aborting" \
  "No closed issue is missing" "$OUT"
refute_grep "…with no skip notice" "audit skipped" "$OUT"

# 2. The fail-safe half: when the re-fetch cannot be completed, the issue must fall
# to PRESENT, never to MISSING.
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
[ "$1" = "api" ] || { echo "unexpected porcelain gh $*" >&2; exit 1; }
case "$2" in
  'repos/o/r/issues?state=closed&per_page=100&page=1') list_row 4243 "refetch fails" ;;
  'repos/o/r/issues/4243/comments?per_page=100&page=1') python3 -c 'import json; print(json.dumps([{"body":"c%d"%i} for i in range(100)]))' ;;
  'repos/o/r/issues/4243/comments?per_page=100&page=2') echo '[]' ;;
  *) exit 1 ;;
esac
STUBEOF
chmod +x "$STUB/gh"
OUT2=$(PATH="$STUB:$PATH" bash "$HELPER" --repo o/r 2>&1); RC2=$?
assert_exit "advisory exit 0 when the re-fetch fails" 0 "$RC2"
refute_grep "a failed re-fetch never reaches MISSING" \
  "4243" "$(printf '%s\n' "$OUT2" | sed -n '/^MISSING/,/^$/p')"
assert_grep "…and that run completed (the issue was read)" "closed issue" "$OUT2"

# 3. The shrink guard: a re-fetch that returns FEWER comments than we already had
# is a partial page. Swapping it in would delete evidence and could route a real
# summary to MISSING, so it must be refused and the issue marked instead.
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
[ "$1" = "api" ] || { echo "unexpected porcelain gh $*" >&2; exit 1; }
case "$2" in
  'repos/o/r/issues?state=closed&per_page=100&page=1') list_row 4244 "refetch returns fewer" ;;
  'repos/o/r/issues/4244/comments?per_page=100&page=1')
    python3 -c 'import json; print(json.dumps([{"body":"## Closing Summary\n\n### Problem\nreal"}] + [{"body":"c%d"%i} for i in range(99)]))' ;;
  'repos/o/r/issues/4244/comments?per_page=100&page=2') echo '[]' ;;
  *) python3 -c 'import json; print(json.dumps([{"body":"only one comment came back"}]))' ;;
esac
STUBEOF
chmod +x "$STUB/gh"
OUT3=$(PATH="$STUB:$PATH" bash "$HELPER" --repo o/r 2>&1); RC3=$?
assert_exit "advisory exit 0 when the re-fetch shrinks the set" 0 "$RC3"
refute_grep "a shrinking re-fetch must not delete the evidence we already had" \
  "4244" "$(printf '%s\n' "$OUT3" | sed -n '/^MISSING/,/^$/p')"
assert_grep "…and that run completed too" "closed issue" "$OUT3"

# 4. `.number` is fetched data and gets interpolated into an API path, so it is
# validated as an integer first. gh-rest refuses the whole read (exit 1) rather
# than return a row without comments — a closed issue with no comments would be
# classified MISSING, the one class that invites a duplicate post. The audit is
# then skipped, and the id never reaches a request.
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$STUB_LOG"
[ "$1" = "api" ] || { echo "unexpected porcelain gh $*" >&2; exit 1; }
case "$2" in
  'repos/o/r/issues?state=closed&per_page=100&page=1')
    echo '[{"number":"4245 --hostname evil.example","title":"non-numeric id","state":"closed","closed_at":"2026-02-01T00:00:00Z"}]' ;;
  *) echo "SHOULD-NOT-BE-CALLED-WITH-A-NON-NUMERIC-ID" ;;
esac
STUBEOF
chmod +x "$STUB/gh"; : > "$STUB_LOG"
OUT4=$(PATH="$STUB:$PATH" bash "$HELPER" --repo o/r 2>&1); RC4=$?
assert_exit "advisory exit 0 on a non-numeric issue id" 0 "$RC4"
assert_grep "a non-numeric id stops the read (fail-safe: audit skipped, nothing classified)" \
  "audit skipped" "$OUT4"
refute_grep "…and the api call is never made with it" \
  "4245" "$(grep -v 'state=closed' "$STUB_LOG")"
refute_grep "…and nothing answered for it" \
  "SHOULD-NOT-BE-CALLED" "$OUT4"

print_summary "acquisition-truncation"
exit $?
