#!/usr/bin/env bash
# Test: the actionability gate — does routing know whether an issue can be worked
# on right now? (PsychQuant/issue-driven-development#298)
#
# The incident this fixture reproduces: on 2026-08-10 a real 22-issue backlog was
# routed by /idd-list. Of the 11 diagnosed issues, 8 parked/deferred/blocked ones
# were reported as "Actionable now". Two of them (#131, #200) carried a defer
# ruling the user had personally made on 2026-07-07. The failure was silent — the
# table looked syntactically correct and carried no warning.
#
# Root cause: `### Complexity` never declared a closed value domain and had no
# unparseable contract, so a producer could legally write `Simple when triggered`
# and three consumers each invented an incompatible narrowing:
#   - idd-list      `([A-Za-z-]+)`      → silently truncated to `Simple`
#   - idd-all       `(.+?)` + via-split → non-tier string, matched no dispatch row
#   - idd-implement same                → same
# idd-all's `UNKNOWN → abort` net does NOT catch this: it only fires when the
# regex fails entirely, not when it matches an out-of-domain value.
#
# TWO CONTRACTS under test (design.md → Implementation Contract):
#   idd_parse_complexity <body>
#     stdout : canonical tier — Simple | Plan | Spectra | SDD-warranted
#     exit 0 : in domain (bare tier, or tier + " via <source>")
#     exit 3 : section present, value out of domain → stderr names the raw value
#     exit 4 : no `### Complexity` section at all
#   idd_actionability_verdict --complexity-exit N --parking-label yes|no --blocking-section yes|no
#     stdout : "actionable" | "not-actionable: <reason>[; <reason>...]"
#     exit 0 : actionable      exit 1 : not actionable
#   reason vocabulary is CLOSED (four values):
#     complexity-unparseable | complexity-missing | parking-lot-label | blocking-nonempty
#
# The `- [~]` Strategy skip marker is deliberately NOT a gate input — it is a
# close-time per-item disposition owned by idd-close. Row 905 pins that.
#
# Usage: bash test.sh   (exit 0 = pass, 1 = fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIBDIR="$(cd "$HERE/../../lib" && pwd)"
. "$LIBDIR/assert-helpers.sh"

LIB="$LIBDIR/actionability.sh"
FIXTURE="$HERE/fixtures/parked-routing.json"

command -v jq >/dev/null 2>&1 || { echo "jq is required for this suite" >&2; exit 1; }
[ -f "$FIXTURE" ] || { echo "fixture missing: $FIXTURE" >&2; exit 1; }

HELPER_PRESENT=0
if [ -f "$LIB" ]; then
  # shellcheck disable=SC1090
  . "$LIB"
  HELPER_PRESENT=1
fi

# Build a Diagnosis comment body from a fixture row's complexity value.
# `null` means the row has no `### Complexity` section at all.
synth_body() { # raw_or_NULL
  if [ "$1" = "__NULL__" ]; then
    printf '## Diagnosis\n\n### Type\n\nbug\n\n### Risks\n\n- none\n'
  else
    printf '## Diagnosis\n\n### Type\n\nbug\n\n### Complexity\n\n%s\n\n### Risks\n\n- none\n' "$1"
  fi
}

missing_helper_note="helper not implemented yet: $LIB"

ACTIONABLE_SNAPSHOT=()

ROWS=$(jq -c '.[]' "$FIXTURE")
while IFS= read -r row; do
  num=$(jq -r '.number' <<<"$row")
  snapshot=$(jq -r '.snapshot' <<<"$row")
  raw=$(jq -r 'if .complexity_raw == null then "__NULL__" else .complexity_raw end' <<<"$row")
  exp_exit=$(jq -r '.expect_parse_exit' <<<"$row")
  exp_tier=$(jq -r 'if .expect_tier == null then "" else .expect_tier end' <<<"$row")
  exp_verdict=$(jq -r '.expect_verdict' <<<"$row")
  exp_reasons=$(jq -r '.expect_reasons | sort | join(";")' <<<"$row")
  has_label=$(jq -r 'if (.labels | index("parking-lot")) then "yes" else "no" end' <<<"$row")
  has_blocking=$(jq -r 'if (.blocking // "") == "" then "no" else "yes" end' <<<"$row")

  body=$(synth_body "$raw")

  if [ "$HELPER_PRESENT" -eq 0 ]; then
    fail "#$num parse exit"     "$missing_helper_note"
    fail "#$num verdict"        "$missing_helper_note"
    fail "#$num reasons"        "$missing_helper_note"
    [ "$exp_verdict" = "actionable" ] && [ "$snapshot" = "true" ] && ACTIONABLE_SNAPSHOT+=("$num")
    continue
  fi

  # ── contract 1: parse ──
  tier=$(idd_parse_complexity "$body" 2>/dev/null); act_exit=$?
  assert_eq "#$num parse exit" "$exp_exit" "$act_exit"

  if [ "$exp_exit" = "0" ]; then
    assert_eq "#$num canonical tier" "$exp_tier" "$tier"
  else
    # out-of-domain / missing MUST surface the raw value on stderr, never a tier
    err=$(idd_parse_complexity "$body" 2>&1 >/dev/null)
    if [ "$raw" = "__NULL__" ]; then
      assert_grep "#$num stderr names missing section" "missing-complexity" "$err"
    else
      assert_grep "#$num stderr surfaces raw value" "$raw" "$err"
    fi
  fi

  # ── contract 2: verdict ──
  out=$(idd_actionability_verdict \
          --complexity-exit "$act_exit" \
          --parking-label "$has_label" \
          --blocking-section "$has_blocking" 2>/dev/null)
  verdict="${out%%:*}"
  verdict="${verdict// /}"
  assert_eq "#$num verdict" "$exp_verdict" "$verdict"

  if [ "$exp_verdict" = "not-actionable" ]; then
    got_reasons=$(printf '%s' "${out#*: }" | tr ';' '\n' | sed 's/^ *//; s/ *$//' | sort | paste -sd';' -)
    assert_eq "#$num reasons" "$exp_reasons" "$got_reasons"
  fi

  [ "$exp_verdict" = "actionable" ] && [ "$snapshot" = "true" ] && ACTIONABLE_SNAPSHOT+=("$num")
done <<<"$ROWS"

# ── audit discipline: the cheap path must not be the unsafe one ──────────────
# A gate that treated an unanswered signal as "clear" would re-open the hole
# #298 closed, so every malformed invocation fails loud (exit 2) instead of
# defaulting to actionable.
if [ "$HELPER_PRESENT" -eq 1 ]; then
  idd_actionability_verdict --complexity-exit 0 --parking-label no 2>/dev/null
  assert_exit "missing --blocking-section fails loud" "2" "$?"

  idd_actionability_verdict --complexity-exit "" --parking-label no --blocking-section no 2>/dev/null
  assert_exit "empty --complexity-exit fails loud" "2" "$?"

  idd_actionability_verdict --complexity-exit 0 --parking-label maybe --blocking-section no 2>/dev/null
  assert_exit "non-boolean --parking-label fails loud" "2" "$?"

  idd_actionability_verdict --complexity-exit 9 --parking-label no --blocking-section no 2>/dev/null
  assert_exit "out-of-range --complexity-exit fails loud" "2" "$?"

  idd_actionability_verdict --bogus-flag yes 2>/dev/null
  assert_exit "unknown flag fails loud" "2" "$?"

  # display grouping: blocking-only keeps the #84 blocked group; anything else parks
  assert_eq "blocking-only → blocked group" "blocked" "$(idd_actionability_group 'blocking-nonempty')"
  assert_eq "parking label → parked group"  "parked"  "$(idd_actionability_group 'parking-lot-label')"
  assert_eq "unparseable → parked group"    "parked"  "$(idd_actionability_group 'complexity-unparseable')"
  assert_eq "mixed reasons → parked group"  "parked"  "$(idd_actionability_group 'complexity-unparseable; blocking-nonempty')"
fi

# ── acceptance criterion (design.md): among the nine 2026-08-10 snapshot rows,
#    exactly #37 is actionable. This is the regression of the actual incident. ──
snap_count=$(jq '[.[] | select(.snapshot)] | length' "$FIXTURE")
assert_eq "fixture carries the 9 snapshot rows" "9" "$snap_count"
assert_eq "only #37 actionable among snapshot" "37" "$(printf '%s' "${ACTIONABLE_SNAPSHOT[*]:-}")"

print_summary "actionability-gate"
