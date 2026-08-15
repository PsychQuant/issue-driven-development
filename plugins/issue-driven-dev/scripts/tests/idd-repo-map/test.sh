#!/usr/bin/env bash
# Test: idd-repo-map.sh derives the layer map both formats and all (#302).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$(cd "$HERE/../.." && pwd)/idd-repo-map.sh"
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"

S=$(mktemp -d); trap 'rm -rf "$S"' EXIT
mkdir -p "$S/p1/.claude/.idd" "$S/p2/.claude" "$S/p3/.claude/.idd" "$S/n/node_modules/x/.claude/.idd"
echo '{"github_repo":"o/p1"}'    > "$S/p1/.claude/.idd/local.json"
echo '{"github_repo":"o/p2"}'    > "$S/p2/.claude/issue-driven-dev.local.json"
echo '{}'                        > "$S/p3/.claude/.idd/local.json"
echo '{"github_repo":"o/noise"}' > "$S/n/node_modules/x/.claude/.idd/local.json"

OUT=$(bash "$SCRIPT" "$S" 2>&1); RC=$?
assert_exit "always exits 0" 0 "$RC"

# The whole point of the map: BOTH formats must be seen. Missing one does not
# mean "one fewer row" — an unseen config reads as "this layer does not exist"
# and triggers the wrong upward resolution (#303 measured 17 legacy repos).
assert_grep "current-format repo is mapped" "o/p1"   "$OUT"
assert_grep "legacy-format repo is mapped"  "o/p2"   "$OUT"
assert_grep "format is reported per row"    "legacy" "$OUT"
refute_grep "node_modules is pruned"        "noise"  "$OUT"

# A config that exists but names no repo is NOT a resolved layer. Letting the
# empty string through would make it look like a match.
assert_grep "config without github_repo is called out, not silently empty" \
  "(no github_repo)" "$OUT"

JSON=$(bash "$SCRIPT" --json "$S" 2>/dev/null)
require "--json emits parseable JSON" bash -c 'printf "%s" "$0" | jq -e . >/dev/null' "$JSON"
require "--json reports three repos" \
  bash -c '[ "$(printf "%s" "$0" | jq ".repos | length")" = "3" ]' "$JSON"
require "--json states whether a global layer exists" \
  bash -c 'printf "%s" "$0" | jq -e "has(\"global_present\")" >/dev/null' "$JSON"

OUT2=$(bash "$SCRIPT" "$S/does-not-exist" 2>&1)
assert_grep "a missing root yields an explicit no-repo line, not silence" \
  "no IDD-configured repo found" "$OUT2"

# ─────────────────────────────────────────────────────────────────────────────
# Backslashes. The row buffer used `\t` / `\n` as two-character escapes and was
# rendered with `printf '%b'`, which expands escapes in the DATA too — so a
# backslash in a directory name or a github_repo value was executed rather than
# printed. The sanitiser strips control characters and bidi marks; it never
# touched backslashes, because at the time nothing downstream interpreted them.
# ─────────────────────────────────────────────────────────────────────────────
B=$(mktemp -d); trap 'rm -rf "$S" "$B"' EXIT

# The payloads must reach the row buffer as LITERAL backslashes, so the JSON on
# disk carries `\\`. Written via a quoted heredoc: an earlier version of this
# test used printf and produced `\c` in the file, which is not a legal JSON
# escape — jq rejected it, the value never reached the row buffer, and the probe
# passed while testing nothing.
mk() { mkdir -p "$B/$1/.claude/.idd"; cat > "$B/$1/.claude/.idd/local.json"; }

# `\c` is the dangerous one: %b stops ALL output at it. Everything after this
# row — every other repo, the totals line — silently disappears, and a map that
# lost half its rows reads exactly like a machine with half as many repos.
mk z-tail  <<'EOF'
{"github_repo":"o/tail-marker"}
EOF
mk a-trunc <<'EOF'
{"github_repo":"o/x\\ceaten"}
EOF
# `\n` forges a standalone row; `\t` shifts the columns of the row it is in.
mk b-forge <<'EOF'
{"github_repo":"o/y\\no/FORGED-ROW"}
EOF
mk c-tab   <<'EOF'
{"github_repo":"o/z\\tINJECTED"}
EOF

require "the backslash payload survived as JSON (probe self-check)" \
  bash -c 'jq -e -r ".github_repo" "$0" | grep -q "x.ceaten"' "$B/a-trunc/.claude/.idd/local.json"

BOUT=$(bash "$SCRIPT" "$B" 2>/dev/null)
assert_grep "a backslash-c value does not truncate the rest of the map" \
  "tail-marker" "$BOUT"
assert_grep "totals line still printed after a backslash-c value" "total:" "$BOUT"
# Precise, not incidental: `o/FORGED-ROW` legitimately appears INSIDE the row it
# was written into. What must never happen is it becoming a row of its own, i.e.
# occupying the first column. Grepping for the bare string tests neither.
refute_grep_re "a backslash-n value does not forge a standalone row" \
  '^  o/FORGED-ROW' "$BOUT"
assert_eq "row count is unchanged by backslash payloads" \
  "4" "$(printf '%s' "$BOUT" | grep -c '^  ')"

BJSON=$(bash "$SCRIPT" --json "$B" 2>/dev/null)
require "--json stays parseable with backslash payloads" \
  bash -c 'printf "%s" "$0" | jq -e . >/dev/null' "$BJSON"
require "--json reports exactly the four real repos" \
  bash -c '[ "$(printf "%s" "$0" | jq ".repos | length")" = "4" ]' "$BJSON"

# An unreadable directory must not read as "no config here" — that is the exact
# failure the map exists to prevent (an absent layer resolves upward, wrongly).
U=$(mktemp -d); mkdir -p "$U/locked/deep"
chmod 000 "$U/locked"
UOUT=$(bash "$SCRIPT" "$U" 2>&1); URC=$?
chmod 755 "$U/locked"; rm -rf "$U"
assert_exit "an unreadable subtree still exits 0 (advisory contract)" 0 "$URC"
assert_grep "an unreadable subtree is reported, not silently mapped as empty" \
  "could not be read" "$UOUT"

print_summary "idd-repo-map"
exit $?
