#!/usr/bin/env bash
# Test: the actionability gate — does routing know whether an issue can be worked
# on right now? (PsychQuant/issue-driven-development#298 → #316)
#
# The incident this fixture reproduces: on 2026-08-10 a real 22-issue backlog was
# routed by /idd-list. Of the 11 diagnosed issues, 8 parked/deferred/blocked ones
# were reported as "Actionable now". Two of them (#131, #200) carried a defer
# ruling the user had personally made on 2026-07-07. The failure was silent — the
# table looked syntactically correct and carried no warning.
#
# Round 1 (PR #318) framed the fix as a CLOSED value domain for `### Complexity`.
# /idd-verify falsified that with the real corpus: 93% of the 159 diagnoses in
# this repo write the tier followed by same-line rationale, so a closed domain
# would have rejected 42% of them. Round 2 (/idd-diagnose #316, corpus 159/159,
# 0 false positives) replaced it with the rule under test here:
#
#   idd_parse_complexity <body>
#     strip markdown decoration → value must BEGIN WITH one of
#       Simple | Plan | Spectra | SDD-warranted   (longest match first)
#     then scan the ENTIRE value for deferral vocabulary
#       when triggered | parking lot | deferred | 暫緩   (case-insensitive)
#     stdout : the leading tier (exit 0 only)
#     exit 0 : routable
#     exit 3 : section present, value does not begin with a tier
#              → stderr "unparseable-complexity: <raw>"
#     exit 4 : no `### Complexity` section (code fences are NOT sections)
#              → stderr "missing-complexity"
#     exit 5 : tier is valid but deferral vocabulary is present
#              → stderr "deferral-marker: <raw>"
#   idd_actionability_verdict --complexity-exit N --parking-label yes|no --blocking-section yes|no
#     stdout : "actionable" | "not-actionable: <reason>[; <reason>...]"
#     exit 0 : actionable      exit 1 : not actionable      exit 2 : bad usage
#   reason vocabulary is CLOSED (five values):
#     complexity-unparseable | complexity-missing | complexity-deferral-marker
#     parking-lot-label | blocking-nonempty
#
# The `- [~]` Strategy skip marker is deliberately NOT a gate input — it is a
# close-time per-item disposition owned by idd-close. Row 905 pins that.
#
# Round 3 (verify #318 round 2) adds: per-bullet `### Blocking` reader with a
# leading-token placeholder rule frozen against corpus-blocking.json, CRLF
# handling, the `undiagnosed` display group, and drift guards that pin the
# consumers' verdict capture shape, branch/egress ordering and input hygiene.
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

# Run a function with a wall-clock bound, bash-only (no coreutils `timeout`).
# A hung call is killed and reports 143, which reads as a plain assertion
# failure instead of wedging the whole suite. Needed because verify #318 H1
# found the verdict arg loop spins forever on a value-less flag.
run_bounded() { # secs fn args...
  local secs="$1"; shift
  ( "$@" ) & local pid=$!
  ( sleep "$secs"; kill "$pid" 2>/dev/null ) 2>/dev/null & local killer=$!
  wait "$pid" 2>/dev/null; local rc=$?
  kill "$killer" 2>/dev/null; wait "$killer" 2>/dev/null
  return "$rc"
}

# Build a Diagnosis comment body from a fixture row.
#   __NULL__  → no `### Complexity` section at all
#   fenced=1  → no real section either, but a fenced example of the template
#               sits in prose (a non-fence-aware extractor would grab it)
synth_body() { # raw_or_NULL fenced [strategy-line]
  local raw="$1" fenced="${2:-0}" strategy="${3:-}"
  { synth_body_core "$raw" "$fenced"
    [ -n "$strategy" ] && printf '\n### Strategy\n\n- [x] done item\n%s\n- [ ] open item\n' "$strategy"; }
}
synth_body_core() { # raw_or_NULL fenced
  local raw="$1" fenced="${2:-0}"
  if [ "$fenced" = "1" ]; then
    printf '## Diagnosis\n\n### Type\n\nbug\n\n### Notes\n\nThe template looks like this:\n\n```markdown\n### Complexity\n\nSimple\n```\n\nand also:\n\n~~~\n### Complexity\n\nPlan when triggered\n~~~\n\n### Risks\n\n- none\n'
  elif [ "$raw" = "__NULL__" ]; then
    printf '## Diagnosis\n\n### Type\n\nbug\n\n### Risks\n\n- none\n'
  else
    printf '## Diagnosis\n\n### Type\n\nbug\n\n### Complexity\n\n%s\n\n### Risks\n\n- none\n' "$raw"
  fi
}

missing_helper_note="helper not implemented yet: $LIB"

ACTIONABLE_SNAPSHOT=()

ROWS=$(jq -c '.[]' "$FIXTURE")
while IFS= read -r row; do
  num=$(jq -r '.number' <<<"$row")
  snapshot=$(jq -r '.snapshot' <<<"$row")
  raw=$(jq -r 'if .complexity_raw == null then "__NULL__" else .complexity_raw end' <<<"$row")
  fenced=$(jq -r 'if .fenced_example == true then "1" else "0" end' <<<"$row")
  strategy=$(jq -r '.strategy // ""' <<<"$row")
  exp_exit=$(jq -r '.expect_parse_exit' <<<"$row")
  exp_tier=$(jq -r 'if .expect_tier == null then "" else .expect_tier end' <<<"$row")
  exp_verdict=$(jq -r '.expect_verdict' <<<"$row")
  exp_reasons=$(jq -r '.expect_reasons | sort | join(";")' <<<"$row")
  has_label=$(jq -r 'if (.labels | index("parking-lot")) then "yes" else "no" end' <<<"$row")
  blocking_src=$(jq -r '.blocking // "- (none)"' <<<"$row")

  body=$(synth_body "$raw" "$fenced" "$strategy")

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

  err=$(idd_parse_complexity "$body" 2>&1 >/dev/null)
  case "$exp_exit" in
    0)
      assert_eq "#$num leading tier" "$exp_tier" "$tier"
      ;;
    3)
      assert_eq   "#$num no tier emitted"          "" "$tier"
      assert_grep "#$num stderr says unparseable"  "unparseable-complexity" "$err"
      assert_grep "#$num stderr surfaces raw value" "$raw" "$err"
      ;;
    4)
      assert_eq   "#$num no tier emitted"          "" "$tier"
      assert_grep "#$num stderr names missing section" "missing-complexity" "$err"
      ;;
    5)
      # The tier prefix is well-formed here; the ONLY reason it is withheld is
      # deferral vocabulary. Emitting the tier would let a consumer route on it.
      assert_eq   "#$num no tier emitted"          "" "$tier"
      assert_grep "#$num stderr says deferral"     "deferral-marker" "$err"
      assert_grep "#$num stderr surfaces raw value" "$raw" "$err"
      ;;
  esac

  # ── contract 3: the Blocking signal is read through the helper, never by
  #    a private awk — a missing section and idd-update's `- (none)` placeholder
  #    are both "no" ──
  issue_body=$(printf '## Current Status\n\n### Phase\n\ndiagnosed\n\n### Blocking\n%s\n\n### Tasks\n\n- [ ] x\n' "$blocking_src")
  block_line=$(idd_blocking_section "$issue_body")
  if [ -n "$block_line" ]; then has_blocking=yes; else has_blocking=no; fi

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

if [ "$HELPER_PRESENT" -eq 1 ]; then
  # ── section extraction: fences and heading levels ──────────────────────────
  # A real section followed by a fenced copy of the template: the real one wins,
  # and the deferral vocabulary inside the fence must not leak into the scan.
  body=$'## Diagnosis\n\n### Complexity\n\nPlan\n\n### Notes\n\n```\n### Complexity\n\nSimple when triggered\n```\n'
  tier=$(idd_parse_complexity "$body" 2>/dev/null); rc=$?
  assert_exit "real section beats fenced copy (exit)" "0" "$rc"
  assert_eq   "real section beats fenced copy (tier)" "Plan" "$tier"

  # A higher-level heading ends the section, so deferral text in the NEXT
  # section is not attributed to Complexity.
  body=$'## Diagnosis\n\n### Complexity\n\nSpectra\n\n## Next steps\n\nRevisit when triggered.\n'
  tier=$(idd_parse_complexity "$body" 2>/dev/null); rc=$?
  assert_exit "higher heading ends section (exit)" "0" "$rc"
  assert_eq   "higher heading ends section (tier)" "Spectra" "$tier"

  # Longest match first: `SDD-warranted` must not be read as a non-tier because
  # no shorter tier is its prefix — and `Simple` must not match `Simpler`.
  body=$'### Complexity\n\nSDD-warranted（legacy alias）\n'
  tier=$(idd_parse_complexity "$body" 2>/dev/null); rc=$?
  assert_exit "legacy alias with rationale (exit)" "0" "$rc"
  assert_eq   "legacy alias with rationale (tier)" "SDD-warranted" "$tier"

  body=$'### Complexity\n\nSimpler than it looks\n'
  idd_parse_complexity "$body" 2>/dev/null >/dev/null
  assert_exit "tier must be a whole word (Simpler ≠ Simple)" "3" "$?"

  # Deferral scan is case-insensitive and tolerant of `parking-lot` / `Parking Lot`.
  body=$'### Complexity\n\nPlan — Parking-Lot until #310 lands\n'
  idd_parse_complexity "$body" 2>/dev/null >/dev/null
  assert_exit "deferral vocab is case/hyphen-insensitive" "5" "$?"

  body=$'### Complexity\n\nSimple（暫緩：等 #86）\n'
  idd_parse_complexity "$body" 2>/dev/null >/dev/null
  assert_exit "CJK deferral marker detected" "5" "$?"

  # ── contract 3: ### Blocking reader (per bullet, leading-token placeholder) ──
  assert_eq "blocking: real blocker → first line" "- 等 /spectra-discuss 對齊 acceptance metric proxy" \
    "$(idd_blocking_section $'## Current Status\n\n### Blocking\n- 等 /spectra-discuss 對齊 acceptance metric proxy\n- second line\n\n### Tasks\n- [ ] x')"
  assert_eq "blocking: idd-update placeholder is empty"   "" "$(idd_blocking_section $'### Blocking\n- (none)\n')"
  assert_eq "blocking: annotated placeholder is empty (#316's own body)" "" "$(idd_blocking_section $'### Blocking\n- (none — 可動)\n')"
  assert_eq "blocking: placeholder + dash annotation is empty" "" "$(idd_blocking_section $'### Blocking\n- (none) — diagnosed, awaiting pickup\n')"
  assert_eq "blocking: bare (none) is empty"             "" "$(idd_blocking_section $'### Blocking\n\n(none)\n')"
  assert_eq "blocking: CJK placeholder is empty"         "" "$(idd_blocking_section $'### Blocking\n（無）\n')"
  assert_eq "blocking: decorated none is empty"          "" "$(idd_blocking_section $'### Blocking\n_none_\n')"
  assert_eq "blocking: N/A is empty"                     "" "$(idd_blocking_section $'### Blocking\nN/A\n')"
  assert_eq "blocking: bare bullet is empty"             "" "$(idd_blocking_section $'### Blocking\n-\n')"
  assert_eq "blocking: absent section is empty"          "" "$(idd_blocking_section $'### Type\nbug\n')"
  assert_eq "blocking: fenced copy is not a section"     "" "$(idd_blocking_section $'### Notes\n```\n### Blocking\n- real\n```\n')"
  assert_eq "blocking: higher heading ends section"      "" "$(idd_blocking_section $'### Blocking\n\n## Next\n- not a blocker\n')"
  # per-bullet: a placeholder does not short-circuit the bullets after it
  assert_eq "blocking: placeholder then real bullet → the real bullet" "- 等 upstream #310 merge" \
    "$(idd_blocking_section $'### Blocking\n- (none)\n- 等 upstream #310 merge\n')"
  assert_eq "blocking: annotated placeholder then real bullet → the real bullet" "- 等 collaborator 回信" \
    "$(idd_blocking_section $'### Blocking\n- (none — closed)\n- 等 collaborator 回信\n')"
  assert_eq "blocking: continuation line under a placeholder is not a bullet" "" \
    "$(idd_blocking_section $'### Blocking\n- (none — closed)\n  see the closing summary for details\n')"
  assert_eq "blocking: continuation line under a blocker keeps the blocker" "- 等 re-park trigger 之一成立：" \
    "$(idd_blocking_section $'### Blocking\n- 等 re-park trigger 之一成立：\n  (1) #298 落地後 triage 準確率可接受\n')"
  # token followed by a WORD is a blocker, not a placeholder
  assert_eq "blocking: 'none' inside a real blocker is kept" "- none of the reviewers replied yet" \
    "$(idd_blocking_section $'### Blocking\n- none of the reviewers replied yet\n')"
  assert_eq "blocking: 'None yet, but …' is kept" "- None yet, but waiting on X" \
    "$(idd_blocking_section $'### Blocking\n- None yet, but waiting on X\n')"
  # documented accepted misses: the leading token wins over a trailing clause
  assert_eq "blocking: DOCUMENTED MISS — '(none) but actually blocked by' reads empty" "" \
    "$(idd_blocking_section $'### Blocking\n- (none) but actually blocked by #86\n')"
  assert_eq "blocking: '- None.' with a full stop is empty" "" "$(idd_blocking_section $'### Blocking\n- None.\n')"
  assert_eq "blocking: decoration inside the parens is empty" "" "$(idd_blocking_section $'### Blocking\n- (**none**)\n')"
  # locale independence: the rule must not flip under LC_ALL=C (bracket
  # expressions split multibyte characters into bytes there)
  assert_eq "blocking: LC_ALL=C — kana after the token is still a blocker" "- none ぁ x" \
    "$(LC_ALL=C bash -c '. "$1"; idd_blocking_section "$2"' _ "$LIB" $'### Blocking\n- none ぁ x\n')"
  assert_eq "blocking: LC_ALL=C — CJK placeholder is still empty" "" \
    "$(LC_ALL=C bash -c '. "$1"; idd_blocking_section "$2"' _ "$LIB" $'### Blocking\n（無）\n')"
  # C0 / DEL scrubbed at the helper's outputs (TAB and LF kept)
  assert_eq "blocking: mid-line CR and ESC are scrubbed" "- 等 #99 fake[31mX" "$(idd_blocking_section $'### Blocking\n- 等 #99\r fake\033[31mX\n')"
  err=$(idd_parse_complexity $'### Complexity\n\nSimple\033[2K when triggered\n' 2>&1 >/dev/null)
  refute_grep "complexity: ESC scrubbed from the surfaced raw line" $'\033' "$err"
  # unbalanced fence → fence tracking disabled for that body (live #290 shape)
  assert_eq "blocking: real blocker below an UNCLOSED fence is found" "- 等 #99 merge" \
    "$(idd_blocking_section $'### Notes\n```\nexample\n\n### Blocking\n- 等 #99 merge\n')"
  tier=$(idd_parse_complexity $'### Notes\n```\nexample\n\n### Complexity\n\nPlan\n' 2>/dev/null); rc=$?
  assert_exit "complexity: section below an UNCLOSED fence is found (exit)" "0" "$rc"
  assert_eq   "complexity: section below an UNCLOSED fence is found (tier)" "Plan" "$tier"
  # CRLF (GitHub web textarea): both directions
  assert_eq "blocking: CRLF real blocker is kept"       "- 等 upstream #310" "$(idd_blocking_section $'### Blocking\r\n\r\n- 等 upstream #310\r\n')"
  assert_eq "blocking: CRLF placeholder is empty"       "" "$(idd_blocking_section $'### Blocking\r\n- (none)\r\n')"
  tier=$(idd_parse_complexity $'### Complexity\r\n\r\nSimple\r\n' 2>/dev/null); rc=$?
  assert_exit "complexity: CRLF bare tier routes (exit)" "0" "$rc"
  assert_eq   "complexity: CRLF bare tier routes (tier)" "Simple" "$tier"
  idd_parse_complexity $'### Complexity\r\n\r\nSimple when triggered\r\n' 2>/dev/null >/dev/null
  assert_exit "complexity: CRLF deferral is exit 5, not 3" "5" "$?"
  # deeper heading inside the section is skipped, never taken as the value
  tier=$(idd_parse_complexity $'### Complexity\n#### tier\nPlan\n' 2>/dev/null); rc=$?
  assert_exit "complexity: #### line is skipped (exit)" "0" "$rc"
  assert_eq   "complexity: #### line is skipped (tier)" "Plan" "$tier"

  # ── corpus regression for signal 3 (verify #318 round-2 CRITICAL): every real
  #    `### Blocking` section in this repo, hand-reviewed. 47 empty / 8 non-empty.
  #    Round 2 withheld 31 of the 47. ──
  BCORPUS="$HERE/fixtures/corpus-blocking.json"
  if [ -f "$BCORPUS" ]; then
    b_ok=0; b_total=0; b_empty=0; b_block=0
    while IFS= read -r row; do
      b_total=$((b_total + 1))
      num=$(jq -r '.number' <<<"$row")
      exp_empty=$(jq -r '.expect_empty' <<<"$row")
      exp_first=$(jq -r '.expect_first_blocker // ""' <<<"$row")
      # the ORIGINAL body, so fences / headings / CR go through the shared extractor
      # (round 3 synthesised a clean body from .section and never exercised it)
      body=$(jq -r '.body // empty' <<<"$row")
      if [ -z "$body" ]; then fail "blocking corpus #$num" "row has no body — fixture must carry the original issue body"; continue; fi
      got=$(idd_blocking_section "$body")
      if [ "$exp_empty" = "true" ]; then
        b_empty=$((b_empty + 1))
        if [ -z "$got" ]; then b_ok=$((b_ok + 1)); else fail "blocking corpus #$num" "expected empty, got: $got"; fi
      else
        b_block=$((b_block + 1))
        if [ "$got" = "$exp_first" ]; then b_ok=$((b_ok + 1)); else fail "blocking corpus #$num" "expected '$exp_first', got '$got'"; fi
      fi
    done < <(jq -c '.rows[]' "$BCORPUS")
    assert_eq "blocking corpus: every section judged as reviewed ($b_ok/$b_total)" "$b_total" "$b_ok"
    assert_eq "blocking corpus: 55 sections, 47 empty / 8 non-empty (rule; hand review is 48/7, #1 is the accepted FP)" "55/47/8" "$b_total/$b_empty/$b_block"
    # #290's body has an UNCLOSED fence: the extractor must still find its section
    b290=$(jq -r '.rows[] | select(.number == 290) | .body' "$BCORPUS")
    assert_eq "blocking corpus: #290 section survives an unclosed fence" "- (none) — 已結案。" "$(_idd_section_lines "$b290" Blocking)"
  else
    fail "blocking corpus" "fixture missing: $BCORPUS"
  fi

  # ── audit discipline: the cheap path must not be the unsafe one ────────────
  # A gate that treated an unanswered signal as "clear" would re-open the hole
  # #298 closed, so every malformed invocation fails loud (exit 2) instead of
  # defaulting to actionable.
  idd_actionability_verdict --complexity-exit 0 --parking-label no 2>/dev/null
  assert_exit "missing --blocking-section fails loud" "2" "$?"

  idd_actionability_verdict --complexity-exit "" --parking-label no --blocking-section no 2>/dev/null
  assert_exit "empty --complexity-exit fails loud" "2" "$?"

  idd_actionability_verdict --complexity-exit 0 --parking-label maybe --blocking-section no 2>/dev/null
  assert_exit "non-boolean --parking-label fails loud" "2" "$?"

  idd_actionability_verdict --complexity-exit 9 --parking-label no --blocking-section no 2>/dev/null
  assert_exit "out-of-range --complexity-exit fails loud" "2" "$?"

  idd_actionability_verdict --complexity-exit 5 --parking-label no --blocking-section no >/dev/null 2>&1
  assert_exit "exit 5 is an accepted --complexity-exit" "1" "$?"

  idd_actionability_verdict --bogus-flag yes 2>/dev/null
  assert_exit "unknown flag fails loud" "2" "$?"

  # verify #318 H1: a flag with no value must be a named exit-2 error, not an
  # infinite loop. Each call is wall-clock bounded; a hang reports 143.
  run_bounded 5 idd_actionability_verdict --parking-label no --blocking-section no --complexity-exit 2>/dev/null
  assert_exit "value-less --complexity-exit fails loud (no hang)" "2" "$?"
  run_bounded 5 idd_actionability_verdict --complexity-exit 0 --blocking-section no --parking-label 2>/dev/null
  assert_exit "value-less --parking-label fails loud (no hang)" "2" "$?"
  run_bounded 5 idd_actionability_verdict --complexity-exit 0 --parking-label no --blocking-section 2>/dev/null
  assert_exit "value-less --blocking-section fails loud (no hang)" "2" "$?"
  err=$(run_bounded 5 idd_actionability_verdict --complexity-exit 0 --parking-label no --blocking-section 2>&1 >/dev/null)
  assert_grep "value-less flag error names the flag" "blocking-section" "$err"

  # display grouping: blocking-only keeps the #84 blocked group; anything else parks
  assert_eq "blocking-only → blocked group"      "blocked" "$(idd_actionability_group 'blocking-nonempty')"
  assert_eq "parking label → parked group"       "parked"  "$(idd_actionability_group 'parking-lot-label')"
  assert_eq "unparseable → parked group"         "parked"  "$(idd_actionability_group 'complexity-unparseable')"
  assert_eq "missing alone → undiagnosed group"  "undiagnosed" "$(idd_actionability_group 'complexity-missing')"
  assert_eq "missing + blocking → blocked group"  "blocked" "$(idd_actionability_group 'complexity-missing; blocking-nonempty')"
  assert_eq "deferral + blocking → parked group"  "parked"  "$(idd_actionability_group 'complexity-deferral-marker; blocking-nonempty')"
  idd_actionability_group "" >/dev/null 2>&1
  assert_exit "empty reason list is API misuse (exit 2), never parked" "2" "$?"
  assert_eq "deferral marker → parked group"     "parked"  "$(idd_actionability_group 'complexity-deferral-marker')"
  assert_eq "mixed reasons → parked group"       "parked"  "$(idd_actionability_group 'complexity-unparseable; blocking-nonempty')"

  # ── task 6.4: the documented call shape survives `set -euo pipefail` ───────
  # Consumers run under strict mode. A bare `TIER=$(idd_parse_complexity …)`
  # would abort the whole listing on the first non-routable issue; the
  # conditional-capture shape must instead yield the exit code as data.
  strict_out=$(bash -euo pipefail -c '
    . "$1"
    body=$(printf "### Complexity\n\nSimple when triggered\n")
    if TIER=$(idd_parse_complexity "$body" 2>/dev/null); then CEXIT=0; else CEXIT=$?; fi
    if VERDICT=$(idd_actionability_verdict --complexity-exit "$CEXIT" --parking-label no --blocking-section no 2>/dev/null); then VEXIT=0; else VEXIT=$?; fi
    printf "%s|%s|%s|%s\n" "$CEXIT" "${TIER:-}" "$VEXIT" "$VERDICT"
    echo still-running
  ' _ "$LIB" 2>/dev/null); strict_rc=$?
  assert_exit "strict-mode caller is not aborted" "0" "$strict_rc"
  assert_eq   "strict-mode capture yields exit 5 as data" "5||1|not-actionable: complexity-deferral-marker" "$(printf '%s' "$strict_out" | head -1)"
  assert_grep "strict-mode caller continues past the gate" "still-running" "$strict_out"
fi

# ── consumer wiring drift guard (tasks 6.4 / 7.1 / 7.2 / 9.1 / 9.2) ─────────
# Round 1 shipped a green gate that no consumer called. These greps pin the
# canonical call shape into the four SKILL.md files so it cannot silently
# regress, and pin the #84 display strings idd-list must keep verbatim.
SKILLS="$HERE/../../../skills"
REF="$HERE/../../../references/actionability-gate.md"
for c in idd-list idd-all idd-implement idd-plan; do
  f="$SKILLS/$c/SKILL.md"
  assert_output_grep "$c: sources the shared helper"           'scripts/lib/actionability.sh' "$f"
  assert_output_grep "$c: fails loud when helper is missing"   'FATAL: missing $CLAUDE_PLUGIN_ROOT/scripts/lib/actionability.sh' "$f"
  assert_output_grep "$c: actually calls the verdict"          'idd_actionability_verdict --complexity-exit "$CEXIT" --parking-label "$HAS_PARKING" --blocking-section "$BLOCKING"' "$f"
  assert_output_grep "$c: reads ### Blocking through the helper" 'idd_blocking_section' "$f"
  assert_output_grep "$c: set -e safe conditional capture"     'if TIER=$(idd_parse_complexity "$LATEST_DIAGNOSIS" 2>/dev/null); then CEXIT=0; else CEXIT=$?; fi' "$f"
  assert_output_grep "$c: paginates the comments fetch"        '/comments" --paginate --jq' "$f"
  refute_output_grep "$c: no truncating --json comments fetch for the diagnosis" 'LATEST_DIAGNOSIS=$(gh issue view' "$f"
  refute_grep_re     "$c: no oldest-100 --json comments connection anywhere" '=\$\(gh issue view[^)]*--json comments' "$(cat "$f")"
  assert_output_grep "$c: set -e safe verdict capture"        'if VERDICT=$(idd_actionability_verdict --complexity-exit "$CEXIT" --parking-label "$HAS_PARKING" --blocking-section "$BLOCKING" 2>&1); then VEXIT=0; else VEXIT=$?; fi' "$f"
  assert_output_grep "$c: branches on the verdict"            'REASONS="${VERDICT#not-actionable: }"' "$f"
  assert_output_grep "$c: exit 2 is a consumer FATAL"         'FATAL: idd_actionability_verdict misuse' "$f"
  assert_output_grep "$c: issue number is digit-checked before the REST path" "*[!0-9]*) " "$f"
  assert_output_grep "$c: Diagnosis author is trusted-only"   'author_association' "$f"
  assert_output_grep "$c: the verdict is PRINTED, not only assigned" "printf 'gate #%s: VEXIT=%s" "$f"
  assert_output_grep "$c: REASONS reset on the actionable path" 'REASONS="" ;;' "$f"
  # command lines only (not `#` comments or `>` prose), and `comments` must be inside the --json field list
  refute_grep_re     "$c: no bare gh issue view --json …comments left" '^[^#>]*gh issue view[^\n]*--json[^ ]*comments' "$(cat "$f")"
  refute_output_grep "$c: no closed-domain wording for the tier field" '封閉值域外' "$f"
  refute_output_grep "$c: no 'closed domain, no fifth value' tier claim" '不得依相似性外推第五個' "$f"
done
for c in idd-list idd-all idd-implement idd-plan; do
  f="$SKILLS/$c/SKILL.md"
  assert_output_grep "$c: allowed-tools pre-approves jq"      'Bash(jq:*)' "$f"
  assert_output_grep "$c: allowed-tools pre-approves python3" 'Bash(python3:*)' "$f"
done
# gate SHALL precede any egress or branch creation (verify #318 round-2 HIGH: idd-implement)
IMPL="$SKILLS/idd-implement/SKILL.md"
gate_ln=$(grep -n 'if VERDICT=$(idd_actionability_verdict' "$IMPL" | head -1 | cut -d: -f1)
branch_ln=$(grep -nE '^[[:space:]]*git checkout -b' "$IMPL" | head -1 | cut -d: -f1)   # the command line, not a prose mention
egress_ln=$(grep -n 'gh-egress.sh" comment' "$IMPL" | head -1 | cut -d: -f1)
assert_true "idd-implement: gate precedes branch creation (gate@${gate_ln:-?} < branch@${branch_ln:-?})" "[ -n '$gate_ln' ] && [ -n '$branch_ln' ] && [ '$gate_ln' -lt '$branch_ln' ]"
assert_true "idd-implement: gate precedes first egress (gate@${gate_ln:-?} < egress@${egress_ln:-?})"  "[ -n '$gate_ln' ] && [ -n '$egress_ln' ] && [ '$gate_ln' -lt '$egress_ln' ]"
# #84 surface preserved verbatim (spec R6)
L="$SKILLS/idd-list/SKILL.md"
assert_output_grep "idd-list: #84 blocked group heading verbatim"  'Blocked (waiting on external):' "$L"
assert_output_grep "idd-list: #84 all-blocked banner verbatim"     '✋ 所有可控事項已完成 — N 個 open issue 全部等待外部回應（詳見上表 blocker）。' "$L"
assert_output_grep "idd-list: #84 footer count verbatim"           '`X actionable, Y blocked`' "$L"
assert_output_grep "idd-list: parked group present"                'Parked (not routable now):' "$L"
assert_output_grep "idd-list: undiagnosed group present"           'Needs diagnosis (' "$L"
assert_output_grep "idd-list: undiagnosed rows keep the diagnose command" '→ /idd-diagnose #' "$L"
assert_output_grep "idd-list: per-ISSUE state guard before the gate"  '.state // ""' "$L"
refute_output_grep "idd-list: no listing-flag state guard"          '[ "$STATE" = "open" ]' "$L"
assert_output_grep "idd-list: skipped rows have a display rule"     'group=skipped' "$L"
IA="$SKILLS/idd-all/SKILL.md"
assert_grep_re "idd-all: Layer-V sub-issue scan filters author"     'issues/\$sub_n/comments" --paginate --jq .\[\.\[\] \| select\(\.author_association' "$(cat "$IA")"
assert_output_grep "idd-all: sub-issue number digit-checked"        'case "$sub_n" in' "$IA"
IM="$SKILLS/idd-implement/SKILL.md"
assert_output_grep "idd-implement: Step 2.5 re-runs the gate when the variables did not survive" '[ -n "${VEXIT:-}" ] ||' "$IM"
assert_output_grep "idd-list: groups via the helper"               'idd_actionability_group "$REASONS"' "$L"
# reference + producer (9.1 / 9.2)
assert_output_grep "reference: cites the 159-diagnosis corpus"     '159' "$REF"
assert_output_grep "reference: five-value reason vocabulary"       'complexity-deferral-marker' "$REF"
assert_output_grep "reference: exit 5 documented"                  'deferral-marker: <raw' "$REF"
refute_output_grep "reference: no closed tier domain claim"        'The legal values are exactly these four' "$REF"
D="$SKILLS/idd-diagnose/SKILL.md"
refute_output_grep "idd-diagnose: no closed-enumeration tier claim" '只得是下列四個值之一' "$D"
assert_output_grep "idd-diagnose: tier-prefix rule stated"         '必須以四個 tier 之一開頭' "$D"
assert_output_grep "idd-diagnose: producer never derives the label — scoped to the issue under diagnosis" 'SHALL NOT 對**正在診斷的該 issue**貼、移除或推導 `parking-lot` label' "$D"
refute_output_grep "idd-issue: no blocker:* label mandate left" 'blocker:infeasible' "$SKILLS/idd-issue/SKILL.md"
refute_output_grep "sdd-integration: no parallel Complexity parse narrative" '→ parse as `Simple`' "$HERE/../../../rules/sdd-integration.md"
assert_output_grep "reference: signal-3 risk posture present"     'Signal 3 (`### Blocking`)' "$REF"
refute_output_grep "reference: no 'parked group == --parked set' claim" 'exactly the set `idd-list --parked` reviews' "$REF"
assert_output_grep "reference: corpus scope stated (54 of 55 CLOSED)" '54 of the 55' "$REF"
assert_output_grep "reference: cluster-path coverage gap stated"    'cluster' "$REF"
assert_output_grep "reference: undiagnosed group documented"      'undiagnosed' "$REF"

# ── task 8.2 / spec R8: full-corpus regression. Every diagnosed issue in this
#    repo (159, frozen 2026-08-15) must route exactly as hand-reviewed:
#    149 routable / 0 unparseable / 1 missing / 9 deferral. "Zero migration" is
#    a claim about the real corpus; this block is what makes it falsifiable. ──
CORPUS="$HERE/fixtures/corpus-complexity.json"
if [ "$HELPER_PRESENT" -eq 1 ] && [ -f "$CORPUS" ]; then
  c_ok=0; c_total=0; c0=0; c3=0; c4=0; c5=0
  while IFS= read -r row; do
    c_total=$((c_total + 1))
    num=$(jq -r '.number' <<<"$row")
    raw=$(jq -r 'if .complexity_raw == null then "__NULL__" else .complexity_raw end' <<<"$row")
    exp_exit=$(jq -r '.expect_parse_exit' <<<"$row")
    exp_tier=$(jq -r '.expect_tier // ""' <<<"$row")
    body=$(synth_body "$raw" 0)
    tier=$(idd_parse_complexity "$body" 2>/dev/null); rc=$?
    case "$rc" in 0) c0=$((c0 + 1)) ;; 3) c3=$((c3 + 1)) ;; 4) c4=$((c4 + 1)) ;; 5) c5=$((c5 + 1)) ;; esac
    if [ "$rc" = "$exp_exit" ] && [ "$tier" = "$exp_tier" ]; then
      c_ok=$((c_ok + 1))
    else
      fail "corpus #$num" "expected exit $exp_exit tier '$exp_tier'; got exit $rc tier '$tier' — raw: $raw"
    fi
  done < <(jq -c '.rows[]' "$CORPUS")
  assert_eq "corpus: every diagnosis routes as reviewed ($c_ok/$c_total)" "$c_total" "$c_ok"
  assert_eq "corpus: 159 diagnoses in the frozen snapshot" "159" "$c_total"
  assert_eq "corpus: exit distribution routable/unparseable/missing/deferral" "149/0/1/9" "$c0/$c3/$c4/$c5"
elif [ "$HELPER_PRESENT" -eq 1 ]; then
  fail "corpus regression" "fixture missing: $CORPUS"
fi

# ── acceptance criterion (design.md): among the nine 2026-08-10 snapshot rows,
#    #37 is actionable — and so is #128, whose deferral lived only in Strategy
#    prose (no marker, no label, no Blocking). #128 is the DESIGNED miss: the
#    gate does not parse prose, and the parking-lot label is the human backstop.
#    Pinning it here keeps the fixture honest instead of hypothesis-confirming. ──
snap_count=$(jq '[.[] | select(.snapshot)] | length' "$FIXTURE")
assert_eq "fixture carries the 9 snapshot rows" "9" "$snap_count"
assert_eq "snapshot actionable = #37 + #128 (documented prose-deferral miss)" "37 128" "$(printf '%s' "${ACTIONABLE_SNAPSHOT[*]:-}")"

# spec R8 scenario: the fixture reflects real shapes, ≥3 each. Shape is judged
# on the raw value; deferral rows are counted by expected exit.
n_bare=$(jq '[.[] | select(.number < 900) | select(.complexity_raw != null) | select(.complexity_raw | test("^(Simple|Plan|Spectra|SDD-warranted)$"))] | length' "$FIXTURE")
n_deco=$(jq '[.[] | select(.number < 900) | select(.complexity_raw != null) | select(.complexity_raw | test("^[*`_]"))] | length' "$FIXTURE")
n_rat=$(jq  '[.[] | select(.number < 900) | select(.complexity_raw != null) | select(.expect_parse_exit == 0) | select(.complexity_raw | test("^(Simple|Plan|Spectra|SDD-warranted)$") | not) | select(.complexity_raw | test("^[*`_]") | not)] | length' "$FIXTURE")
n_def=$(jq  '[.[] | select(.number < 900) | select(.expect_parse_exit == 5)] | length' "$FIXTURE")
assert_true "≥3 REAL bare-tier rows ($n_bare)"                 "[ $n_bare -ge 3 ]"
assert_true "≥3 decorated-tier rows ($n_deco)"            "[ $n_deco -ge 3 ]"
assert_true "≥3 tier+rationale rows ($n_rat)"             "[ $n_rat -ge 3 ]"
assert_true "≥3 deferral-vocabulary rows ($n_def)"        "[ $n_def -ge 3 ]"

print_summary "actionability-gate"
