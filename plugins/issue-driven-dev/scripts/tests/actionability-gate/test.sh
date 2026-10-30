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
. "$HERE/../../lib/git-fixture-helpers.sh"
git_fixture_setup

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
  # A full stop is NOT a terminator (round 5 reverted round 4's `\.|。`): it had
  # no corpus need (0/55 rows) and turned `- None. Waiting on X` — placeholder
  # token, full stop, real blocker clause — into "no blocker" (fail-open). The
  # bare `- None.` therefore reads as a blocker: fail-closed, visible, and not
  # a shape the corpus contains. Do not re-add the terminator by analogy; a
  # reader-rule change must flip a measured row or be a revert.
  assert_eq "blocking: '- None. Waiting on X' is a BLOCKER (full stop is not a terminator)" "- None. Waiting on X" \
    "$(idd_blocking_section $'### Blocking\n- None. Waiting on X\n')"
  assert_eq "blocking: '- 無。等 #99 merge' is a BLOCKER (CJK full stop is not a terminator)" "- 無。等 #99 merge" \
    "$(idd_blocking_section $'### Blocking\n- 無。等 #99 merge\n')"
  assert_eq "blocking: bare '- None.' reads as a BLOCKER (documented fail-closed)" "- None." "$(idd_blocking_section $'### Blocking\n- None.\n')"
  assert_eq "blocking: decoration inside the parens is empty" "" "$(idd_blocking_section $'### Blocking\n- (**none**)\n')"
  # locale independence: the rule must not flip under LC_ALL=C (bracket
  # expressions split multibyte characters into bytes there)
  assert_eq "blocking: LC_ALL=C — kana after the token is still a blocker" "- none ぁ x" \
    "$(LC_ALL=C bash -c '. "$1"; idd_blocking_section "$2"' _ "$LIB" $'### Blocking\n- none ぁ x\n')"
  assert_eq "blocking: LC_ALL=C — CJK placeholder is still empty" "" \
    "$(LC_ALL=C bash -c '. "$1"; idd_blocking_section "$2"' _ "$LIB" $'### Blocking\n（無）\n')"
  # The PLACEHOLDER-TOKEN rule must not depend on the process locale, nor on a shell function that
  # shadows `grep` (spec R9, round 6). Round 5's assertion compared C with C.UTF-8 for EQUALITY, so
  # pinning to C.UTF-8 — both sides empty, the fail-open direction — still passed; the VALUE is
  # asserted now. And production is not BSD grep: skills `.`-source the helper in Claude Code's zsh,
  # where the shell snapshot defines `grep` as a ugrep function that ignores LC_ALL. The function
  # used below emulates that (it forces a UTF-8 grep whatever LC_ALL says); the helper must bypass it.
  u3000=$'### Blocking\n- none　\n'
  # precondition: C.UTF-8 really classifies U+3000 as blank here — otherwise the two-locale
  # assertions compare two identical environments and prove nothing
  assert_true "precondition: C.UTF-8 classifies U+3000 as [[:space:]] (else the locale assertions are vacuous)" \
    "printf '　\n' | LC_ALL=C.UTF-8 command grep -qE '^[[:space:]]\$'"
  for loc in C C.UTF-8; do
    assert_eq "blocking: under LC_ALL=$loc, '- none<U+3000>' reads as a BLOCKER (withholding side, pinned by value)" "- none　" \
      "$(LC_ALL=$loc bash -c '. "$1"; idd_blocking_section "$2"' _ "$LIB" "$u3000")"
  done
  shadowed() { LC_ALL=C bash -c 'grep() { LC_ALL=C.UTF-8 command grep "$@"; }; . "$1"; idd_blocking_section "$2"' _ "$LIB" "$1"; }
  assert_eq "blocking: with grep shadowed by a locale-ignoring function (the zsh/ugrep shape), '- none<U+3000>' still reads as a BLOCKER" "- none　" "$(shadowed "$u3000")"
  assert_eq "blocking: with grep shadowed, a plain '- (none)' is still empty" "" "$(shadowed $'### Blocking\n- (none)\n')"
  # The SECOND placeholder grep (a bullet holding only blanks or decoration) is pinned too (round 7):
  # a whitespace-only bullet written with U+3000 reads as a blocker in both locales and under the
  # locale-ignoring shadow; and under a FAILING shadow (every grep "matches") both placeholder greps
  # must still be the real one — round 5 prescribed this shadow, round 6 shipped only the other one.
  ws=$'### Blocking\n-　\n'
  for loc in C C.UTF-8; do
    assert_eq "blocking: under LC_ALL=$loc, '-<U+3000>' (whitespace-only bullet) reads as a BLOCKER" "-　" \
      "$(LC_ALL=$loc bash -c '. "$1"; idd_blocking_section "$2"' _ "$LIB" "$ws")"
  done
  assert_eq "blocking: with grep shadowed by a locale-ignoring function, '-<U+3000>' still reads as a BLOCKER" "-　" "$(shadowed "$ws")"
  failing() { LC_ALL=C bash -c 'grep() { return 0; }; . "$1"; idd_blocking_section "$2"' _ "$LIB" "$1"; }
  assert_eq "blocking: with grep shadowed by an always-matching function, both placeholder greps still decide (a real blocker after '- (none)' is read)" "- 等 #99 merge" \
    "$(failing $'### Blocking\n- (none)\n- 等 #99 merge\n')"
  # DIRECTION PINS for the matchers that are deliberately NOT locale-pinned (round 6, DA-H1).
  # "Remove the locale dependence" has no direction-free answer: pinning the deferral grep or the
  # bullet detector to C turns these two inputs fail-open — a human deferral becomes routable
  # (#298's incident) and a real blocker after a placeholder disappears — with every other
  # assertion green and no corpus row changed. In the reference environment (UTF-8, also what the
  # production ugrep does) both sit on the withholding side; these pins make the suite refuse
  # either change. The remaining environment dependence is listed in the helper and handed to #336.
  utf8_cexit() { LC_ALL=C.UTF-8 bash -c '. "$1"; idd_parse_complexity "$2" >/dev/null 2>&1; echo $?' _ "$LIB" "$1"; }
  utf8_block() { LC_ALL=C.UTF-8 bash -c '. "$1"; idd_blocking_section "$2"' _ "$LIB" "$1"; }
  # The pins use U+3000, which both macOS's libc and glibc classify as blank under a UTF-8 locale
  # (round 7, measured: macOS bash + BSD grep + the production zsh; Ubuntu 24.04 + GNU grep 3.11).
  # NBSP is NOT portable: glibc does not classify it as blank, so on Linux the NBSP forms already
  # take the C-locale path. Round 6 pinned the NBSP forms and CI (ubuntu-latest) failed — on every
  # commit since c006c8b, unnoticed by the round-6 verify, which ran on macOS only.
  assert_eq "direction pin (deferral grep): 'Simple when<U+3000>triggered' is withheld (exit 5), never routable" "5" \
    "$(utf8_cexit $'### Complexity\n\nSimple when　triggered\n')"
  assert_eq "direction pin (bullet detector): a real blocker '-<U+3000>…' after a placeholder is read" "-　等 #99 merge" \
    "$(utf8_block $'### Blocking\n- (none)\n-　等 #99 merge\n')"
  # Environment RECORD (not an approval): the NBSP forms, with the value this platform's libc gives.
  nbsp_grep=$(printf ' \n' | LC_ALL=C.UTF-8 command grep -cE '^[[:space:]]$')
  if [ "$nbsp_grep" = 1 ]; then exp_def=5; exp_bul="- 等 #99 merge"; plat="libc classifies NBSP as blank (macOS)"; else exp_def=0; exp_bul=""; plat="libc does not classify NBSP as blank (glibc): the C-locale path"; fi
  assert_eq "environment record ($plat): 'Plan when<NBSP>triggered' exit under UTF-8" "$exp_def" \
    "$(utf8_cexit $'### Complexity\n\nPlan when triggered\n')"
  assert_eq "environment record ($plat): '-<NBSP>…' after a placeholder under UTF-8" "$exp_bul" \
    "$(utf8_block $'### Blocking\n- (none)\n- 等 #99 merge\n')"
  # C0 / DEL scrubbed at the helper's outputs (TAB and LF kept)
  assert_eq "blocking: mid-line CR and ESC are scrubbed" "- 等 #99 fake[31mX" "$(idd_blocking_section $'### Blocking\n- 等 #99\r fake\033[31mX\n')"
  err=$(idd_parse_complexity $'### Complexity\n\nSimple\033[2K when triggered\n' 2>&1 >/dev/null)
  refute_grep "complexity: ESC scrubbed from the surfaced raw line" $'\033' "$err"
  err=$(idd_parse_complexity $'### Complexity\n\nBogus\033[31m tier\n' 2>&1 >/dev/null)
  refute_grep "complexity: ESC scrubbed from the unparseable-complexity raw line" $'\033' "$err"
  err=$(idd_actionability_group $'bogus\033[31m' 2>&1 >/dev/null)
  refute_grep "group: ESC scrubbed from the misuse message" $'\033' "$err"
  err=$(idd_actionability_verdict --complexity-exit $'9\033[31m' --parking-label no --blocking-section no 2>&1 >/dev/null)
  refute_grep "verdict: ESC scrubbed from the --complexity-exit misuse message" $'\033' "$err"
  err=$(idd_actionability_verdict --complexity-exit 0 --parking-label $'x\033[31m' --blocking-section no 2>&1 >/dev/null)
  refute_grep "verdict: ESC scrubbed from the --parking-label misuse message" $'\033' "$err"
  err=$(idd_actionability_verdict --complexity-exit 0 --parking-label no --blocking-section $'x\033[31m' 2>&1 >/dev/null)
  refute_grep "verdict: ESC scrubbed from the --blocking-section misuse message" $'\033' "$err"
  err=$(idd_actionability_verdict $'--bogus\033[2K' 2>&1 >/dev/null)
  refute_grep "verdict: ESC scrubbed from the unknown-argument misuse message" $'\033' "$err"
  err=$(idd_actionability_verdict --complexity-exit 0 --parking-label no --blocking-section no --diagnosis-type $'x\033[31m' 2>&1 >/dev/null)
  refute_grep "verdict: ESC scrubbed from the --diagnosis-type misuse message" $'\033' "$err"
  assert_grep "verdict: the --diagnosis-type misuse message names the flag" 'diagnosis-type must be' "$err"
  # ── fences follow CommonMark, which is what GitHub renders (round 5) ────────
  # Round 4 disabled fence tracking for a body whose marker count was odd, so
  # that a section below an UNCLOSED fence would be read. Measured: the only
  # live instance (#290) gets the same gate verdict either way; the heuristic
  # exposed FENCED TEMPLATES as real sections (shapes A and B below); and the
  # state-machine variant ("disable if still open at EOF") failed shape B the
  # same way. The reader's fence semantics therefore equal the CommonMark
  # render: an unclosed fence runs to the end of the body and hides everything
  # below it (a producer defect to surface, #336), and a balanced fenced
  # example is never a section. Any "detect imbalance → stop tracking" rule is
  # a one-key switch and must not come back.
  # A: a CLOSED ``` block whose content has a `~~~` line and a template — three
  #    marker lines, balanced. The real sections after it win.
  shapeA=$'### Notes\n```\nfence syntax:\n~~~\n### Complexity\n\nSimple\n\n### Blocking\n- (none)\n```\n\n### Complexity\n\nPlan when triggered\n\n### Blocking\n- 等 #99 merge\n'
  idd_parse_complexity "$shapeA" >/dev/null 2>&1
  assert_exit "fence A: closed block containing ~~~ — real Complexity (deferral) wins, not the fenced Simple" "5" "$?"
  assert_eq   "fence A: closed block containing ~~~ — real blocker is read, not the fenced (none)" "- 等 #99 merge" "$(idd_blocking_section "$shapeA")"
  # B: a closed fenced example, the real sections, then a stray opener at the
  #    end (odd count; open at EOF). Neither the count nor the EOF state may
  #    turn the fenced example into the section.
  shapeB=$'### Notes\n```\n### Complexity\n\nSimple\n\n### Blocking\n- (none)\n```\n\n### Complexity\n\nPlan when triggered\n\n### Blocking\n- 等 #99 merge\n\n### Later\n```\n'
  idd_parse_complexity "$shapeB" >/dev/null 2>&1
  assert_exit "fence B: fenced example + trailing stray opener — real Complexity (deferral) wins" "5" "$?"
  assert_eq   "fence B: fenced example + trailing stray opener — real blocker is read" "- 等 #99 merge" "$(idd_blocking_section "$shapeB")"
  # C: the #290 shape — one unclosed fence above the sections. CommonMark (and
  #    GitHub) render everything below it as code; so does the reader.
  shapeC=$'### Notes\n```\nexample\n\n### Complexity\n\nPlan\n\n### Blocking\n- 等 #99 merge\n'
  idd_parse_complexity "$shapeC" >/dev/null 2>&1
  assert_exit "fence C: unclosed fence runs to EOF — Complexity below it is not a section (CommonMark)" "4" "$?"
  assert_eq   "fence C: unclosed fence runs to EOF — Blocking below it is not read (CommonMark)" "" "$(idd_blocking_section "$shapeC")"
  # The reader is line-based: it follows CommonMark on the two rules above and departs from it in
  # the KNOWN ways below — known, not exhaustive. Each pinned shape is measured against markdown_it;
  # on the live snapshot (243 issue bodies + 164 Diagnosis comments, 2026-09-08) the reader and
  # CommonMark agree on section presence, content and verdict for all 217 sections. The pins make a
  # change deliberate, not forbidden: converging a shape on the markdown_it render is allowed by the
  # change gate and flips its pin in the same commit. The full list, with directions, is in the
  # helper; whether this field should be regex-read at all is #336.
  # D1: fence LENGTH is not compared — a ```` opener is closed by the first ``` line, so a nested
  #     example's content is read as outside the fence. Direction: either (the template's text).
  assert_eq "DOCUMENTED DIVERGENCE D1 (fence length): a nested example inside a 4-backtick fence is read" "- FAKE-NESTED" \
    "$(idd_blocking_section $'### Notes\n````md\n```bash\n### Blocking\n- FAKE-NESTED\n```\n````\n\n### Blocking\n- (none)\n')"
  # D2: INDENTATION is not checked — a ``` line indented 4+ spaces (CommonMark: indented code, not a
  #     fence) opens a fence here and, left open, hides the real section. Direction: fail-open.
  assert_eq "DOCUMENTED DIVERGENCE D2 (indentation): a 4-space-indented \`\`\` hides the real blocker below" "" \
    "$(idd_blocking_section $'### Notes\n\n    ```\n    example\n\n### Blocking\n- 等 #99 merge\n')"
  # D3: a ``` line WITH TRAILING TEXT closes a fence here (CommonMark: a closer carries no info
  #     string, so it does not close). Direction: either (the template's text).
  assert_eq "DOCUMENTED DIVERGENCE D3 (closer with text): a fenced template after '\`\`\` text' is read" "- FAKE-2" \
    "$(idd_blocking_section $'### Notes\n```\n### Blocking\n- FAKE-CLOSER\n``` not a closer\n### Blocking\n- FAKE-2\n```\n\n### Blocking\n- (none)\n')"
  # D4: an opener whose INFO STRING contains a backtick (e.g. a paragraph line that starts with an
  #     inline span written with three backticks) is not a fence in CommonMark but opens one here
  #     that never closes. Direction: fail-open. Flips on convergence.
  assert_eq "DOCUMENTED DIVERGENCE D4 (backtick in the info string): a real blocker below is hidden" "" \
    "$(idd_blocking_section $'### Notes\n```x``` is inline code\n\n### Blocking\n- 等 #99 merge\n')"
  # D2 also covers a TAB-indented opener (CommonMark: indented code). Direction: fail-open.
  assert_eq "DOCUMENTED DIVERGENCE D2 (tab): a tab-indented \`\`\` hides the real blocker below" "" \
    "$(idd_blocking_section $'### Notes\n\n\t```\n\texample\n\n### Blocking\n- 等 #99 merge\n')"
  # D5: a closer indented 4+ spaces INSIDE a fence closes it here (CommonMark: content, the fence
  #     continues). Direction: either (the template's text) — here a fenced fake blocker is read.
  assert_eq "DOCUMENTED DIVERGENCE D5 (indented closer): a fenced template after an indented \`\`\` is read" "- FAKE-2" \
    "$(idd_blocking_section $'### Notes\n```\n### Blocking\n- FAKE\n    ```\n### Blocking\n- FAKE-2\n```\n\n### Blocking\n- (none)\n')"
  # D6: a fence opened on a LIST-ITEM line (`- \`\`\``) is not seen here; its indented closer is then
  #     taken as an opener that runs to the end of the body. Direction: fail-open. (A fence inside a
  #     blockquote is not a divergence: neither the reader nor CommonMark reads its contents.)
  assert_eq "DOCUMENTED DIVERGENCE D6 (list-item fence): the real blocker below is hidden" "" \
    "$(idd_blocking_section $'### Notes\n- ```\n  example\n  ```\n\n### Blocking\n- 等 #99 merge\n')"
  assert_eq "not a divergence: a fence inside a blockquote hides nothing and reads no fake" "" \
    "$(idd_blocking_section $'### Notes\n> ```\n> ### Blocking\n> - FAKE\n> ```\n\n### Blocking\n- (none)\n')"
  # D7: an HTML comment holding a fake `### Blocking` is hidden by GitHub but read here (the first
  #     matching heading wins). Direction: either — here the fake placeholder hides the real blocker.
  assert_eq "DOCUMENTED DIVERGENCE D7 (HTML comment): a fake section inside <!-- --> is read first" "" \
    "$(idd_blocking_section $'<!--\n### Blocking\n- (none)\n-->\n\n### Blocking\n- 等 #99 merge\n')"
  # D8–D12 (round 7) — measured against markdown-it AND pandoc's CommonMark reader, pinned under
  # LC_ALL=C.UTF-8 (the production shell's locale; the awk extractor follows the locale, so these
  # are environment-dependent where NBSP is involved). They record today's behaviour, not an
  # approval: changing any of them is a structural change, frozen until a requirement names its
  # oracle (#336). The awk C pin moves D8, D9 and D10 in mixed directions — these pins catch it.
  # Which awk this is decides D8–D10 (round 7, measured): macOS's awk treats NBSP as blank under
  # C.UTF-8 and U+3000 not; gawk + glibc the reverse; mawk neither. The expected value of each pin
  # follows this platform's classification, so a change that makes the helper's awk disagree with
  # the platform awk (a C-locale pin, a different regex) fails on macOS and under gawk alike.
  awk_nbsp=$(printf ' x\n' | LC_ALL=C.UTF-8 awk '/^[[:space:]]x/' | wc -l | tr -d ' ')
  awk_u3000=$(printf '　x\n' | LC_ALL=C.UTF-8 awk '/^[[:space:]]x/' | wc -l | tr -d ' ')
  echo "  note: this awk under C.UTF-8 — NBSP blank=$awk_nbsp, U+3000 blank=$awk_u3000"
  if [ "$awk_nbsp" = 1 ]; then d8="" d9a="- 等 #99 merge" d9b="" d10="- 等 #99 merge"; else d8="- 等 #99 merge" d9a="" d9b="- 等 #99 merge" d10=""; fi
  if [ "$awk_u3000" = 1 ]; then d10u="- 等 #99 merge"; else d10u=""; fi
  # D8: an NBSP-indented ``` opens a fence here; both oracles read paragraph text. Fail-open.
  assert_eq "DOCUMENTED DIVERGENCE D8 (NBSP-indented opener, UTF-8; NBSP blank=$awk_nbsp): hidden where NBSP is blank" "$d8" \
    "$(utf8_block $'### Notes\n ```\nx\n\n### Blocking\n- 等 #99 merge\n')"
  # D9: `###<NBSP>X` / `##<NBSP>X` count as headings here; neither oracle treats them as headings.
  assert_eq "DOCUMENTED DIVERGENCE D9 (###<NBSP>Blocking, UTF-8; NBSP blank=$awk_nbsp): read as the section where NBSP is blank" "$d9a" \
    "$(utf8_block $'### Blocking\n- 等 #99 merge\n')"
  assert_eq "DOCUMENTED DIVERGENCE D9 (##<NBSP>Next, UTF-8; NBSP blank=$awk_nbsp): ends the section early where NBSP is blank" "$d9b" \
    "$(utf8_block $'### Blocking\n- (none)\n## Next\n- 等 #99 merge\n')"
  # D10: trailing whitespace other than space/tab after the heading text. The oracles disagree:
  #      markdown-it strips it (heading "Blocking"); pandoc's CommonMark keeps it ("Blocking\160").
  assert_eq "DOCUMENTED DIVERGENCE D10 (### Blocking<NBSP>, UTF-8; NBSP blank=$awk_nbsp): read where NBSP is blank (= markdown-it; CommonMark: no such heading)" "$d10" \
    "$(utf8_block $'### Blocking \n- 等 #99 merge\n')"
  assert_eq "DOCUMENTED DIVERGENCE D10 (### Blocking<U+3000>, UTF-8; U+3000 blank=$awk_u3000): read only where this awk treats U+3000 as blank (gawk)" "$d10u" \
    "$(utf8_block $'### Blocking　\n- 等 #99 merge\n')"
  # D11 / D12: an ATX heading indented 1–3 spaces, or with a closing sequence, is not read here;
  #      both oracles read it. Fail-open.
  assert_eq "DOCUMENTED DIVERGENCE D11 (ATX heading indented 3 spaces): not read" "" "$(idd_blocking_section $'   ### Blocking\n- 等 #99 merge\n')"
  assert_eq "DOCUMENTED DIVERGENCE D12 (### Blocking ### closing sequence): not read" "" "$(idd_blocking_section $'### Blocking ###\n- 等 #99 merge\n')"
  # Complexity's ltrim/rtrim parameter expansions follow the shell locale too (an environment
  # dependence round 6 left off its list). Recorded in both environments.
  nbsp_bash=$(LC_ALL=C.UTF-8 bash -c 'x=$1a; y=${x#"${x%%[![:space:]]*}"}; [ "$y" = a ] && echo 1 || echo 0' _ $' ')
  if [ "$nbsp_bash" = 1 ]; then exp_trim=0; else exp_trim=3; fi
  assert_eq "environment dependence (Complexity trim; bash NBSP blank=$nbsp_bash): '<NBSP>Plan' under UTF-8 exits $exp_trim" "$exp_trim" "$(utf8_cexit $'### Complexity\n\n Plan\n')"
  assert_eq "environment dependence (Complexity trim): '<NBSP>Plan' is unparseable under C (exit 3)" "3" \
    "$(LC_ALL=C bash -c '. "$1"; idd_parse_complexity "$2" >/dev/null 2>&1; echo $?' _ "$LIB" $'### Complexity\n\n Plan\n')"
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
  #    `### Blocking` section in this repo (55 rows; 54 sections under CommonMark — #290's heading
  #    sits below an unclosed fence). Hand review: 48 semantically empty / 7 real blockers
  #    (`semantic_empty`); the rule's expectation is 47 / 8 (`expect_empty`, row #1 is the accepted
  #    false positive). Round 2 withheld 30 of the 48 when it read the original bodies. ──
  BCORPUS="$HERE/fixtures/corpus-blocking.json"
  if [ -f "$BCORPUS" ]; then
    b_ok=0; b_total=0; b_empty=0; b_block=0
    s_empty=0; s_block=0; s_closed=0; s_disagree=""; s_secmatch=0
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
      # The claims the reference makes about this corpus, pinned as data rather
      # than prose (verify #318 round 4, codex): the SEMANTIC hand review is
      # carried per row, the rule–review disagreement set is exactly {#1}, 54 of
      # the 55 issues are CLOSED, and the frozen `.section` is what the shared
      # extractor returns for the original body (so `.section` cannot drift from
      # what the reader actually judges).
      sem=$(jq -r '.semantic_empty' <<<"$row")
      case "$sem" in true) s_empty=$((s_empty + 1)) ;; false) s_block=$((s_block + 1)) ;; *) fail "blocking corpus #$num" "row has no boolean semantic_empty" ;; esac
      [ "$sem" = "$exp_empty" ] || s_disagree="${s_disagree:+$s_disagree }$num"
      [ "$(jq -r '.state' <<<"$row")" = "CLOSED" ] && s_closed=$((s_closed + 1))
      if [ "$(jq -r '.section | join("\n")' <<<"$row")" = "$(_idd_section_lines "$body" Blocking)" ]; then s_secmatch=$((s_secmatch + 1)); else fail "blocking corpus #$num" "frozen .section differs from what the extractor returns for the original body"; fi
    done < <(jq -c '.rows[]' "$BCORPUS")
    assert_eq "blocking corpus: every section judged as reviewed ($b_ok/$b_total)" "$b_total" "$b_ok"
    assert_eq "blocking corpus: 55 rows, 47 empty / 8 non-empty by the rule (hand review is 48/7; #1 is the accepted FP)" "55/47/8" "$b_total/$b_empty/$b_block"
    assert_eq "blocking corpus: semantic hand review is 48 empty / 7 real blockers"  "48/7" "$s_empty/$s_block"
    assert_eq "blocking corpus: rule disagrees with the hand review on exactly #1"   "1"    "$s_disagree"
    assert_eq "blocking corpus: 54 of the 55 issues are CLOSED"                      "54"   "$s_closed"
    assert_eq "blocking corpus: frozen .section == extractor output for all 55 bodies" "$b_total" "$s_secmatch"
    # #290's body has an UNCLOSED fence above `### Blocking`. Under CommonMark
    # everything below it is code, and the reader agrees: the section is not
    # read and the gate outcome is "no blocker" — the same outcome round 4's
    # heuristic produced (its `- (none) — 已結案。` was a placeholder anyway).
    # Pin the GATE OUTCOME, not an intermediate value: round 4 pinned the
    # intermediate and called a no-op a fix.
    b290=$(jq -r '.rows[] | select(.number == 290) | .body' "$BCORPUS")
    assert_eq "blocking corpus: #290 (unclosed fence) — gate outcome is no blocker, section below the fence is not read" "" "$(idd_blocking_section "$b290")"
    assert_eq "blocking corpus: #290 (unclosed fence) — the reader does not surface anything below the fence" "" "$(_idd_section_lines "$b290" Blocking)"
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
  idd_actionability_group "" >/dev/null 2>&1; rc=$?
  assert_exit "empty reason list is API misuse (exit 2), never parked" "2" "$rc"
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
  assert_output_grep "$c: set -e safe verdict capture"        'if VERDICT=$(idd_actionability_verdict --complexity-exit "$CEXIT" --parking-label "$HAS_PARKING" --blocking-section "$BLOCKING" --diagnosis-type "$DIAG_TYPE" 2>&1); then VEXIT=0; else VEXIT=$?; fi' "$f"
  assert_output_grep "$c: reads the type from the trusted Diagnosis (#383 r4)" 'DIAG_TYPE=$(idd_diagnosis_type "$LATEST_DIAGNOSIS")' "$f"
  refute_output_grep "$c: never takes the type from labels or the issue body (#383 r4)" 'idd_issue_type' "$f"
  assert_output_grep "$c: branches on the verdict"            'REASONS="${VERDICT#not-actionable: }"' "$f"
  assert_output_grep "$c: exit 2 is a consumer FATAL"         'FATAL: idd_actionability_verdict misuse' "$f"
  assert_output_grep "$c: issue number is digit-checked before the REST path" "*[!0-9]*) " "$f"
  assert_output_grep "$c: Diagnosis author is trusted-only"   'author_association' "$f"
  # The verdict is printed in TWO parts (round 5): a machine line whose fields
  # are all closed-vocabulary, then the third-party raw text on its own lines
  # inside a fixed `raw<<<` … `>>>raw` delimiter with every raw line indented.
  # Round 4 printed `… | $COMPLEXITY_ERR$BLOCK_LINE` on the same unbounded line:
  # a body bullet could carry a look-alike `gate #77: VEXIT=0 …` (TAB survives
  # the scrub), the two raws were glued together, and prose that reads like an
  # instruction landed on the executing model's only channel with nothing
  # marking it as data (verify #318 round 4, security + codex).
  assert_output_grep "$c: the verdict is PRINTED — machine line, closed vocabulary only" "printf 'gate #%s: VEXIT=%s TIER=%s REASONS=%s TYPE=%s\\n'" "$f"
  assert_output_grep "$c: raw third-party text opens a delimited block"  "printf 'raw<<<\\n'" "$f"
  assert_output_grep "$c: raw third-party text closes the delimited block" "printf '>>>raw\\n'" "$f"
  assert_output_grep "$c: every raw line is indented (no raw line at column 0)" "sed 's/^/  │ /'" "$f"
  refute_output_grep "$c: no single-line print with the raws glued on"   'REASONS=%s | %s%s' "$f"
  assert_output_grep "$c: REASONS reset on the actionable path" 'REASONS="" ;;' "$f"
  refute_output_grep "$c: no closed-domain wording for the tier field" '封閉值域外' "$f"
  refute_output_grep "$c: no 'closed domain, no fifth value' tier claim" '不得依相似性外推第五個' "$f"
done
for c in idd-list idd-all idd-implement idd-plan; do
  f="$SKILLS/$c/SKILL.md"
  assert_output_grep "$c: allowed-tools pre-approves jq"      'Bash(jq:*)' "$f"
  assert_output_grep "$c: allowed-tools pre-approves python3" 'Bash(python3:*)' "$f"
done
# No consumer may fetch comments through `gh issue view --json …comments` — that connection returns only
# the OLDEST 100 comments, so on a long issue the latest Diagnosis is the one dropped. Command lines only
# (not `#` notes, not `>` prose), comments in ANY --json field position. Round 4's guard
# (`--json[^ ]*comments`) could not cross the space after `--json` and matched nothing; its first
# replacement needed a leading comma and missed `--json comments,…` (verify #318 round 4, logic L2).
# One pattern, self-tested on the exact string the loop below uses.
# A `#` may be crossed only when glued to a non-blank character (`"#$N"`); a blank-led `# …` is a shell
# comment and ends the command, so a note that mentions `--json comments` is not a fetch.
COMMENTS_GUARD_RE='^[^#>]*gh issue view([^|#]|[^|#[:space:]]#)*--json([[:space:]]+|=)[^[:space:]|#]*comments'
join_cont() { sed -e ':a' -e '/\\$/N' -e 's/\\\n//' -e 'ta'; }   # a `\`-continued command becomes one line before matching
# Joining alone can HIDE a fetch: a previous line that ends in `2>/dev/null \\` puts a `>` before
# `gh` on the joined line (verify #318 round 6, logic L-2). Each consumer is checked raw AND joined.
two_lines=$(printf '%s\n' 'OUT=$(gh api x 2>/dev/null \' '  || gh issue view "$N" --json title,comments)')
refute_grep_re "drift guard self-test: the joined form alone misses a fetch after '2>/dev/null \\' (why raw is checked too)" "$COMMENTS_GUARD_RE" "$(printf '%s\n' "$two_lines" | join_cont)"
assert_grep_re "drift guard self-test: …and the raw form catches it" "$COMMENTS_GUARD_RE" "$two_lines"
assert_grep_re "drift guard self-test: '--json=' is caught" \
  "$COMMENTS_GUARD_RE" 'X=$(gh issue view "$N" --repo "$R" --json=title,comments)'
assert_grep_re "drift guard self-test: a '#'-quoted issue number before --json is caught" \
  "$COMMENTS_GUARD_RE" 'gh issue view "#$N" --repo "$R" --json comments'
assert_grep_re "drift guard self-test: a backslash-continued --json comments is caught after joining" \
  "$COMMENTS_GUARD_RE" "$(printf '%s\n' 'X=$(gh issue view "$N" --repo "$R" \' '    --json title,comments)' | join_cont)"
assert_grep_re "drift guard self-test: comments as the FIRST --json field is caught too" \
  "$COMMENTS_GUARD_RE" 'gh issue view $NUMBER --repo $GITHUB_REPO --json comments,title'
assert_grep_re "drift guard self-test: comments as the last --json field is caught" \
  "$COMMENTS_GUARD_RE" 'gh issue view $NUMBER --repo $GITHUB_REPO --json title,body,labels,comments'
assert_grep_re "drift guard self-test: the round-3 quoted assignment form is caught" \
  "$COMMENTS_GUARD_RE" 'ISSUE_JSON=$(gh issue view "$NUMBER" --repo "$GITHUB_REPO" --json title,body,labels,comments)'
refute_grep_re "drift guard self-test: a fetch without comments is not flagged" \
  "$COMMENTS_GUARD_RE" 'ISSUE_JSON=$(gh issue view "$NUMBER" --repo "$GITHUB_REPO" --json title,body,labels)'
refute_grep_re "drift guard self-test: a trailing '# comments …' note is not a comments fetch" \
  "$COMMENTS_GUARD_RE" 'gh issue view $NUMBER --repo $GITHUB_REPO --json title,body,labels   # comments 由下方 gate 區塊分頁抓'
for c in idd-list idd-all idd-implement idd-plan; do
  refute_grep_re "$c: no gh issue view fetches comments through --json (raw lines)" "$COMMENTS_GUARD_RE" "$(cat "$SKILLS/$c/SKILL.md")"
  refute_grep_re "$c: no gh issue view fetches comments through --json (continuation lines joined)" "$COMMENTS_GUARD_RE" "$(join_cont < "$SKILLS/$c/SKILL.md")"
done
# The canonical shape in the reference prints the same two-part verdict.
assert_output_grep "reference: canonical shape prints the machine line"      "printf 'gate #%s: VEXIT=%s TIER=%s REASONS=%s TYPE=%s\\n'" "$REF"
assert_output_grep "reference: canonical shape reads the type from the trusted Diagnosis (#383 r4)" 'DIAG_TYPE=$(idd_diagnosis_type "$LATEST_DIAGNOSIS")' "$REF"
assert_output_grep "reference: canonical shape delimits the raw block"       "printf 'raw<<<\\n'" "$REF"
refute_output_grep "reference: no single-line print with the raws glued on"  'REASONS=%s | %s%s' "$REF"
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
# Step 5's closed enumeration must name `skipped` too — Step 3.7 produces it for every non-OPEN
# row under `--state all` / `--state closed`, and a rule that is only claimed in Step 3.7 prose is
# not a rule (common-spec-prose-enumeration; verify #318 round 4, regression R4-M1).
assert_output_grep "idd-list: Step 5 enumeration names all five non-actionable groups" '`group=blocked` / `parked` / `undiagnosed` / `error` / `skipped`' "$L"
refute_output_grep "idd-list: no 'closed list of four values' that omits undiagnosed" '（四個值）' "$L"
# Every error exit in Step 3.7 prints why (the model's only channel), and the helper's new exit 2
# cannot take the listing down (verify #318 round 4: five silent `GROUP=error; continue`, one
# unguarded `$(idd_actionability_group …)` under `set -e`).
assert_output_grep "idd-list: group call is guarded against exit 2"  'GROUP=$(idd_actionability_group "$REASONS") || GROUP=error' "$L"
assert_true "idd-list: every Step 3.7 error exit says so on stderr (≥ 7 'gate not evaluated')" "[ $(grep -c 'gate not evaluated' "$L") -ge 7 ]"
assert_output_grep "idd-list: body is extracted under its own guard before the helper" 'BODY=$(jq -r '"'"'.body // ""'"'"' <<<"$ISSUE_JSON")' "$L"
refute_output_grep "idd-list: no nested jq inside the helper call (its failure was swallowed)" 'idd_blocking_section "$(jq -r' "$L"
refute_output_grep "idd-list: no blanket 'helper scrubs everything' delegation claim" '本 skill 不再自行處理' "$L"
assert_output_grep "idd-list: label names are named as NOT passing through the helper" 'label 名不經 helper' "$L"
refute_output_grep "idd-list: no claim that the skill scrubs label names itself (no code did)" '由本 skill 自行' "$L"
IA="$SKILLS/idd-all/SKILL.md"
assert_grep_re "idd-all: Layer-V sub-issue scan filters author"     'issues/\$sub_n/comments" --paginate --jq .\[\.\[\] \| select\(\.author_association' "$(cat "$IA")"
assert_output_grep "idd-all: sub-issue number digit-checked"        'case "$sub_n" in' "$IA"
# …and digit-checked BEFORE the first use of $sub_n, not between two uses (verify #318 round 4, regression R4-M4)
subcase_ln=$(grep -n 'case "$sub_n" in' "$IA" | head -1 | cut -d: -f1)
subview_ln=$(grep -n 'SUB_BODY=$(gh issue view "$sub_n"' "$IA" | head -1 | cut -d: -f1)
assert_true "idd-all: sub-issue digit check precedes its first gh call (case@${subcase_ln:-?} < view@${subview_ln:-?})" "[ -n '$subcase_ln' ] && [ -n '$subview_ln' ] && [ '$subcase_ln' -lt '$subview_ln' ]"
subnorm_ln=$(grep -nF 'sub_n=${sub_n#\#}' "$IA" | head -1 | cut -d: -f1)
assert_true "idd-all: a '#'-prefixed sub-issue is normalised before the digit check (norm@${subnorm_ln:-?} < case@${subcase_ln:-?})" "[ -n '$subnorm_ln' ] && [ '$subnorm_ln' -lt '$subcase_ln' ]"
assert_output_grep "idd-all: a skipped non-numeric sub-issue is reported, not silent" 'skipping non-numeric sub-issue' "$IA"
# …through printf + scrub, not echo: zsh's echo interprets backslash escapes in the model-filled
# value (`\n` forges a column-0 line, `\c` silences the rest), and the value is not scrubbed.
refute_output_grep "idd-all: the skip line does not echo the untrusted value" 'echo "⚠ skipping non-numeric sub-issue' "$IA"
assert_output_grep "idd-all: the skip line prints through printf and strips C0/DEL" "printf '⚠ skipping non-numeric sub-issue: %s" "$IA"
refute_output_grep "idd-list: one display rule for group=error (no second '⚠ gate error' form)" '⚠ gate error' "$L"
refute_output_grep "idd-list: group=error is not described as API misuse only" 'gate API 誤用' "$L"
IM="$SKILLS/idd-implement/SKILL.md"
# Step 2.5 must actually RE-RUN the gate, not print that it is re-running: the verdict call and the
# printed machine line appear twice in idd-implement (Step 0.35 and Step 2.5). Round 4 pinned the
# `${VEXIT:-}` guard string and called an echo a re-run (verify #318 round 4, four lenses + codex).
# B1 (round 6): the gate block is repeated — idd-implement Step 0.35 and Step 2.5, idd-plan Step 1,
# idd-all Phase 2 — and routing in idd-implement reads the Step 2.5 copy. Round 5 guarded the copies
# with two occurrence counts; six edits to Step 2.5 alone (dropping the author filter, the digit
# check, the raw-block sed, hard-coding a signal) left the suite green. The copies are now compared
# byte for byte; idd-all's copy differs only by its issue variable (`$N`). The reference and
# idd-list are documentation / a documented variant and are not compared. Structural fix: #370.
gate_blocks() {   # every fenced bash block that calls the verdict, each terminated by \036
  awk '/^```bash[[:space:]]*$/ { inb = 1; buf = ""; next }
       inb && /^```[[:space:]]*$/ { inb = 0; if (index(buf, "if VERDICT=$(idd_actionability_verdict --complexity-exit")) printf "%s\036", buf; next }
       inb { buf = buf $0 "\n" }' "$1"
}
impl_blocks=$(gate_blocks "$IM")
assert_eq "idd-implement carries exactly two gate blocks (Step 0.35, Step 2.5)" "2" "$(printf '%s' "$impl_blocks" | tr -cd '\036' | wc -c | tr -d ' ')"
gb_035=${impl_blocks%%$'\036'*}; gb_rest=${impl_blocks#*$'\036'}; gb_25=${gb_rest%%$'\036'*}
assert_eq "idd-implement: the Step 2.5 gate block is byte-identical to Step 0.35" "$gb_035" "$gb_25"
gb_plan=$(gate_blocks "$SKILLS/idd-plan/SKILL.md"); gb_plan=${gb_plan%%$'\036'*}
assert_eq "idd-plan: the gate block is byte-identical to idd-implement's" "$gb_035" "$gb_plan"
gb_all=$(gate_blocks "$IA"); gb_all=${gb_all%%$'\036'*}
gb_all=$(printf '%s' "$gb_all" | sed -E 's/\$N([^A-Za-z0-9_]|$)/$NUMBER\1/g')
assert_eq "idd-all: the gate block is byte-identical to idd-implement's after \$N→\$NUMBER" "$(printf '%s' "$gb_035")" "$gb_all"
assert_grep "gate block: the comment fetch is captured under its own guard (a failed fetch is not 'no diagnosis')" 'comment fetch failed' "$gb_035"
# Round 7 — what the byte compare could not see (verify #318 round 6: security S2, logic L-3/L-4/L-5).
# (a) every verdict call in the file, in ANY fence or none, is inside a compared block;
# (b) idd-plan and idd-all carry exactly one block;
# (c) no other fenced code in these files assigns a gate variable or prints a verdict line;
# (d) idd-all's own block never says $NUMBER (the $N→$NUMBER rewrite would hide it);
# (e) the guards are exercised, not just present: the extracted block runs against a stub gh.
for c in idd-implement:2 idd-plan:1 idd-all:1; do
  f="$SKILLS/${c%%:*}/SKILL.md"; want=${c##*:}
  assert_eq "${c%%:*}: verdict calls anywhere in the file = $want (no copy outside a compared block)" "$want" \
    "$(command grep -c 'VERDICT=$(idd_actionability_verdict --complexity-exit' "$f" | tr -d ' ')"
  assert_eq "${c%%:*}: exactly $want gate block(s) extracted" "$want" "$(gate_blocks "$f" | tr -cd '\036' | wc -c | tr -d ' ')"
  outside=$(awk '/^[[:space:]]*(```|~~~)/ { if (inb) { inb = 0; if (!index(buf, "VERDICT=$(idd_actionability_verdict --complexity-exit")) printf "%s", buf } else { inb = 1; buf = "" } next }
                 inb { buf = buf $0 "\n" }' "$f")
  refute_grep_re "${c%%:*}: no fenced code outside the gate blocks assigns a gate variable or prints a verdict line" \
    '(^|[^A-Za-z_])(VEXIT|TIER|REASONS|CEXIT|BLOCKING|HAS_PARKING|LATEST_DIAGNOSIS|BLOCK_LINE)=|gate #' "$outside"
done
refute_grep "idd-all: its gate block never says \$NUMBER (idd-all defines only \$N)" '$NUMBER' "$(gate_blocks "$IA")"
GB_RUN=$(git_fixture_mktemp) || exit 1; printf '%s' "$gb_035" > "$GB_RUN/block.sh"
gb_stub='gh() { case "$1" in api) [ "$STUB" = commentfail ] && return 1; case "$STUB" in meetingdiag) echo "[{\"body\":\"## Diagnosis\\n\\n### Type\\nmeeting\\n\"}]" ;; bodyflip) echo "[{\"body\":\"## Diagnosis\\n\\n### Type\\nbug\\n\\n### Complexity\\n\\nSimple when triggered\\n\"}]" ;; *) echo "[]" ;; esac ;; issue) [ "$STUB" = issuefail ] && return 1; case "$STUB" in meeting|meetingdiag) echo "{\"labels\":[{\"name\":\"meeting\"}],\"body\":\"\"}" ;; bodyflip) echo "{\"labels\":[],\"body\":\"## Type\\nmeeting\\n\"}" ;; *) echo "{\"labels\":[],\"body\":\"\"}" ;; esac ;; esac; }'
run_block() { ( cd "$GB_RUN" && STUB="$1" NUMBER=316 GITHUB_REPO=o/r CLAUDE_PLUGIN_ROOT="$HERE/../../.." bash -c "$gb_stub"$'\n'"$(cat block.sh)" 2>&1 ); }
out=$(run_block commentfail); rc=$?
assert_eq "gate block (run): a failed comment fetch exits 1" "1" "$rc"
assert_grep "gate block (run): a failed comment fetch says so" 'comment fetch failed' "$out"
out=$(run_block issuefail); rc=$?
assert_eq "gate block (run): a failed issue fetch exits 1" "1" "$rc"
assert_grep "gate block (run): a failed issue fetch says so" 'issue fetch failed' "$out"
out=$(run_block ok); rc=$?
assert_eq "gate block (run): with both fetches ok it exits 0" "0" "$rc"
assert_grep_re "gate block (run): no diagnosis prints the complexity-missing verdict" '^gate #316: VEXIT=1 TIER= REASONS=complexity-missing TYPE=none$' "$out"
# A meeting issue with NO Diagnosis comment is still undiagnosed: the meeting
# exemption covers a Diagnosis without a tier, never a missing Diagnosis
# (verify #383 r1, findings 1-4 — the first cut pinned the opposite here).
out=$(run_block meeting); rc=$?
assert_eq "gate block (run): a meeting issue with no Diagnosis comment exits 0 (block ran)" "0" "$rc"
assert_grep_re "gate block (run): a meeting-labelled issue with no Diagnosis comment stays complexity-missing (#383 r1, r4)" '^gate #316: VEXIT=1 TIER= REASONS=complexity-missing TYPE=none$' "$out"
out=$(run_block meetingdiag); rc=$?
assert_eq "gate block (run): a diagnosed meeting issue exits 0 (#383)" "0" "$rc"
assert_grep_re "gate block (run): a diagnosed meeting issue is actionable and says TYPE=meeting (#383)" '^gate #316: VEXIT=0 TIER= REASONS= TYPE=meeting$' "$out"
# r4 #19: the issue author rewrites the body to `meeting` after a bug Diagnosis
# with a deferral — the gate still reads `bug` from the trusted Diagnosis.
out=$(run_block bodyflip); rc=$?
assert_eq "gate block (run): a body flipped to meeting exits 0 (block ran)" "0" "$rc"
assert_grep_re "gate block (run): the body cannot release the gate — TYPE comes from the Diagnosis (#383 r4)" '^gate #316: VEXIT=1 TIER= REASONS=complexity-deferral-marker TYPE=bug$' "$out"
rm -rf "$GB_RUN"
assert_output_grep "reference: canonical shape guards the comment fetch" 'comment fetch failed' "$REF"
refute_output_grep "idd-implement: Step 2.5 prose no longer describes the superseded occurrence-count guard" 'drift guard 斷言兩處都含 verdict 呼叫與機器行' "$IM"
assert_output_grep "idd-implement: Step 2.5 prose names the byte compare" '逐位元組' "$IM"
refute_output_grep "idd-implement: no prose-as-code re-run (echo only)" 're-running the Step 0.35 block (same helper, same shape)" >&2; }' "$IM"
P="$SKILLS/idd-plan/SKILL.md"
refute_output_grep "idd-plan: no 2-key routing row under the 3-key header" '| `0` · `Simple` |' "$P"
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

# Round-5 claims refuted by the round-5 verify must not come back (round 6). Empirical statements
# about the outside world are "known, not exhaustive"; the change gate is two direction properties.
ROOT="$HERE/../../../../.."
# After `spectra archive` (2026-10-07) the requirements live in the main spec; the change's design and
# tasks live in its archive directory. A test that kept reading the old change path would fail open
# (a missing file refutes nothing), so the paths are asserted to exist below.
SPEC="$ROOT/openspec/specs/actionability-gate/spec.md"
ARCHIVED="$ROOT/openspec/changes/archive/2026-10-07-add-actionability-gate"
refute_output_grep "spec.md: no 'one of exactly three forms' change gate" 'one of exactly three forms' "$SPEC"
for f in "$LIB" "$REF" "$SPEC"; do
  n=$(basename "$f")
  # ("exactly three" itself stays legal in the spec: three signals, three display groups)
  [ "$f" = "$SPEC" ] || refute_output_grep "$n: no 'exactly three' divergence claim" 'exactly three' "$f"
  # ("a closed list" stays legal for the REASON vocabulary, which is one; only the helper's fence list was wrongly so called)
  [ "$f" = "$LIB" ] && refute_output_grep "$n: no 'closed list' for the fence divergences" 'a closed list' "$f"
  refute_output_grep "$n: no 'a function of the input alone' claim"        'a function of the input alone' "$f"
  refute_output_grep "$n: no 'the change gate keeps' lock-in of a fail-open" 'change gate keeps' "$f"
  refute_output_grep "$n: no three-form change gate"                       'one of three forms' "$f"
done
assert_output_grep "helper: divergences are stated as known, not exhaustive" 'not exhaustive' "$LIB"
assert_output_grep "spec: the gate's vocabulary property moves only toward withholding" 'toward withholding' "$SPEC"
assert_output_grep "spec: structural rules are frozen until a requirement names their oracle" 'frozen' "$SPEC"
assert_output_grep "spec: control characters narrowed to C0 and DEL" 'C0 control characters and DEL' "$SPEC"
# Round-6 claims refuted by the round-6 verify must not come back (round 7).
for f in "$LIB" "$REF" "$SPEC"; do
  n=$(basename "$f")
  refute_output_grep "$n: no 'the gate admits' the awk C pin"                   'gate admits' "$f"
  refute_output_grep "$n: no 'not a fail-open' verdict on the awk C pin"         'not a fail-open' "$f"
  refute_output_grep "$n: no 'never contains an adversarial or edge shape'"      'never contains an adversarial' "$f"
  refute_output_grep "$n: no 'converging … is allowed' (structure is frozen)"    'ALLOWED by the change' "$f"
  refute_output_grep "$n: no 'is allowed by the change gate'"                     'allowed by the change gate' "$f"
  refute_output_grep "$n: no 'stays on the withholding side' universal title"    'stays on the withholding side' "$f"
  refute_output_grep "$n: no 'author who can write any of these' framing"        'author who can write any of these' "$f"
  refute_output_grep "$n: no 'every misuse message — each pinned' claim"         'every misuse message — each pinned' "$f"
done
refute_output_grep "spec.md: the convergence scenario is gone (structure is frozen)" 'A listed divergence may converge' "$SPEC"
refute_output_grep "spec.md: no 'Convergence that clears a blocker is refused' scenario" 'Convergence that clears a blocker is refused' "$SPEC"
refute_output_grep "spec.md: no undefined 'reference environment'" 'reference environment' "$SPEC"
# History documents keep withdrawn claims, each marked where it stands (round 7, verify #318 round 6).
bullet_marked() {   # file pattern marker — every bullet / paragraph holding PATTERN also holds MARKER
  awk -v pat="$2" -v mk="$3" 'function flush() { if (buf != "" && index(buf, pat) && !index(buf, mk)) bad++; buf = "" }
    /^- / || /^#/ || /^[[:space:]]*$/ { flush() } { buf = buf "\n" $0 } END { flush(); exit (bad > 0) }' "$1"
}
DESIGN="$ARCHIVED/design.md"; TASKS="$ARCHIVED/tasks.md"
for f_ in "$SPEC" "$DESIGN" "$TASKS"; do assert_true "spec artifact present: ${f_#"$ROOT/"}" "[ -s '$f_' ]"; done
CL="$ROOT/plugins/issue-driven-dev/CHANGELOG.md"
for spec_ in "$DESIGN|三處已知分歧|勘誤" "$DESIGN|三種合法形態|勘誤" "$DESIGN|不是** fail-open|勘誤" "$DESIGN|永遠不會出現在裡面|勘誤" \
             "$TASKS|封閉三形態|勘誤" "$TASKS|awk 的 C 釘選未被擋|勘誤" \
             "$CL|converges on CommonMark instead|Errata" "$CL|contains an edge shape|Errata" "$CL|may not move the corpus, the live snapshot or a|Errata"; do
  IFS='|' read -r f_ pat_ mk_ <<<"$spec_"
  assert_true "$(basename "$f_"): the withdrawn claim '$pat_' carries an errata marker" "bullet_marked '$f_' '$pat_' '$mk_'"
done
# B5: what plugin users read must not claim a repair round 5 reverted
PJ="$ROOT/plugins/issue-driven-dev/.claude-plugin/plugin.json"; MJ="$ROOT/.claude-plugin/marketplace.json"
pj_desc=$(jq -r '.description' "$PJ"); mj_desc=$(jq -r '.plugins[] | select(.name == "issue-driven-dev") | .description' "$MJ")
for d in "plugin.json:$pj_desc" "marketplace.json:$mj_desc"; do
  refute_grep "${d%%:*}: does not claim the reverted unclosed-fence repair" 'unclosed-fence fail-open' "${d#*:}"
  assert_grep "${d%%:*}: states the CommonMark fence rule shipped in round 5" 'CommonMark' "${d#*:}"
  refute_grep "${d%%:*}: no 'structure only toward the markdown_it render' (under it the bullet-detector pin would pass)" 'structure only toward the markdown_it render' "${d#*:}"
  assert_grep "${d%%:*}: states that structural rules are frozen" 'frozen' "${d#*:}"
  refute_grep "${d%%:*}: no '55 real sections' (55 rows, 54 sections under CommonMark)" '55 real sections' "${d#*:}"
done

# ── #383: Diagnosis type — a diagnosed meeting issue skips the Complexity signal ─
# The meeting type (#57) deliberately writes no tier, so the Complexity signal
# would always read unparseable (exit 3) or missing (exit 4). The gate learns the
# type from the latest TRUSTED Diagnosis (its `### Type`), never from labels or
# the issue body, which the issue author can edit (verify r4, maintainer
# decision 2026-10-14). Each fixture row builds a Diagnosis with that type and
# runs it through idd_diagnosis_type, the path a consumer takes.
MFIX="$HERE/fixtures/meeting-routing.json"
assert_true "meeting fixture present" "[ -s '$MFIX' ]"
cs_body() { printf '## Current Status\n\n### Phase\n\ndiagnosed\n\n### Blocking\n%s\n\n### Tasks\n\n- [ ] x\n' "$1"; }
typed_diag() { # dtype raw_or_NULL — a Diagnosis whose ### Type is dtype
  if [ "$2" = "__NULL__" ]; then printf '## Diagnosis\n\n### Type\n\n%s\n\n### Risks\n\n- none\n' "$1"
  else printf '## Diagnosis\n\n### Type\n\n%s\n\n### Complexity\n\n%s\n\n### Risks\n\n- none\n' "$1" "$2"; fi
}
while IFS= read -r row; do
  name=$(jq -r '.name' <<<"$row")
  raw=$(jq -r 'if .complexity_raw == null then "__NULL__" else .complexity_raw end' <<<"$row")
  exp_pexit=$(jq -r '.expect_parse_exit' <<<"$row")
  exp_verdict=$(jq -r '.expect_verdict' <<<"$row")
  exp_reasons=$(jq -r '.expect_reasons | sort | join(";")' <<<"$row")
  has_label=$(jq -r 'if (.labels | index("parking-lot")) then "yes" else "no" end' <<<"$row")
  if [ -n "$(idd_blocking_section "$(cs_body "$(jq -r '.blocking' <<<"$row")")")" ]; then hb=yes; else hb=no; fi
  dtype=$(jq -r '.diagnosis_type' <<<"$row")
  # No trusted Diagnosis comment means an EMPTY LATEST_DIAGNOSIS.
  if [ "$dtype" = none ]; then diag=""; else diag=$(typed_diag "$dtype" "$raw"); fi
  dt=$(idd_diagnosis_type "$diag" 2>/dev/null)
  assert_eq "meeting [$name]: Diagnosis type read from the Diagnosis" "$dtype" "$dt"
  idd_parse_complexity "$diag" >/dev/null 2>&1; pexit=$?
  assert_eq "meeting [$name]: parse exit" "$exp_pexit" "$pexit"
  out=$(idd_actionability_verdict --complexity-exit "$pexit" --parking-label "$has_label" \
          --blocking-section "$hb" --diagnosis-type "$dt" 2>/dev/null); vexit=$?
  verdict="${out%%:*}"; verdict="${verdict// /}"
  assert_eq "meeting [$name]: verdict" "$exp_verdict" "$verdict"
  if [ "$exp_verdict" = "not-actionable" ]; then
    got=$(printf '%s' "${out#*: }" | tr ';' '\n' | sed 's/^ *//; s/ *$//' | sort | paste -sd';' -)
    assert_eq "meeting [$name]: reasons" "$exp_reasons" "$got"
    assert_eq "meeting [$name]: exit 1" "1" "$vexit"
    exp_group=$(jq -r '.expect_group // ""' <<<"$row")
    [ -n "$exp_group" ] && assert_eq "meeting [$name]: display group" "$exp_group" "$(idd_actionability_group "${out#*: }" 2>/dev/null)"
  else
    assert_eq "meeting [$name]: exit 0" "0" "$vexit"
  fi
done < <(jq -c '.[]' "$MFIX")

idd_actionability_verdict --complexity-exit 0 --parking-label no --blocking-section no --diagnosis-type nonsense >/dev/null 2>&1
assert_eq "--diagnosis-type: a value outside the seven is misuse (exit 2)" "2" "$?"
run_bounded 5 idd_actionability_verdict --complexity-exit 0 --parking-label no --blocking-section no --diagnosis-type >/dev/null 2>&1
assert_eq "--diagnosis-type: a value-less flag is misuse (exit 2), not a hang" "2" "$?"
idd_actionability_verdict --complexity-exit 0 --parking-label no --blocking-section no --diagnosis-type "" >/dev/null 2>&1
assert_eq "--diagnosis-type: passed but empty is misuse (exit 2), not 'no type given'" "2" "$?"
for old_ in "--issue-type meeting" "--diagnosis-present yes"; do
  idd_actionability_verdict --complexity-exit 4 --parking-label no --blocking-section no $old_ >/dev/null 2>&1
  assert_eq "verdict: the withdrawn flag '${old_%% *}' is an unknown argument (exit 2)" "2" "$?"
done

# Omitted Diagnosis type preserves the existing verdict, and so does every value
# other than meeting: re-run each parked-routing row with each of them.
while IFS= read -r row; do
  num=$(jq -r '.number' <<<"$row")
  raw=$(jq -r 'if .complexity_raw == null then "__NULL__" else .complexity_raw end' <<<"$row")
  fenced=$(jq -r 'if .fenced_example == true then "1" else "0" end' <<<"$row")
  strategy=$(jq -r '.strategy // ""' <<<"$row")
  has_label=$(jq -r 'if (.labels | index("parking-lot")) then "yes" else "no" end' <<<"$row")
  if [ -n "$(idd_blocking_section "$(cs_body "$(jq -r '.blocking // "- (none)"' <<<"$row")")")" ]; then hb=yes; else hb=no; fi
  idd_parse_complexity "$(synth_body "$raw" "$fenced" "$strategy")" >/dev/null 2>&1; pexit=$?
  base=$(idd_actionability_verdict --complexity-exit "$pexit" --parking-label "$has_label" --blocking-section "$hb" 2>/dev/null)
  for t_ in bug feature refactor docs unknown none; do
    got=$(idd_actionability_verdict --complexity-exit "$pexit" --parking-label "$has_label" \
            --blocking-section "$hb" --diagnosis-type "$t_" 2>/dev/null)
    assert_eq "#$num: --diagnosis-type $t_ leaves the verdict unchanged" "$base" "$got"
  done
done < <(jq -c '.[]' "$FIXTURE")
# The other two frozen corpora too (verify #383 r1, finding 36 — task 1.3 named
# all three, the first cut ran one). Counted, not asserted per row, to keep the
# output readable; any mismatch is reported by number.
reg_ok=0; reg_total=0
while IFS= read -r row; do
  num=$(jq -r '.number' <<<"$row")
  raw=$(jq -r 'if .complexity_raw == null then "__NULL__" else .complexity_raw end' <<<"$row")
  idd_parse_complexity "$(synth_body "$raw" 0)" >/dev/null 2>&1; pexit=$?
  base=$(idd_actionability_verdict --complexity-exit "$pexit" --parking-label no --blocking-section no 2>/dev/null)
  for t_ in bug feature refactor docs unknown none; do
    reg_total=$((reg_total + 1))
    got=$(idd_actionability_verdict --complexity-exit "$pexit" --parking-label no --blocking-section no --diagnosis-type "$t_" 2>/dev/null)
    if [ "$got" = "$base" ]; then reg_ok=$((reg_ok + 1)); else fail "corpus-complexity #$num" "--diagnosis-type $t_ changed '$base' to '$got'"; fi
  done
done < <(jq -c '.rows[]' "$CORPUS")
while IFS= read -r row; do
  num=$(jq -r '.number' <<<"$row")
  if [ -n "$(idd_blocking_section "$(jq -r '.body' <<<"$row")")" ]; then hb=yes; else hb=no; fi
  base=$(idd_actionability_verdict --complexity-exit 0 --parking-label no --blocking-section "$hb" 2>/dev/null)
  for t_ in bug feature refactor docs unknown none; do
    reg_total=$((reg_total + 1))
    got=$(idd_actionability_verdict --complexity-exit 0 --parking-label no --blocking-section "$hb" --diagnosis-type "$t_" 2>/dev/null)
    if [ "$got" = "$base" ]; then reg_ok=$((reg_ok + 1)); else fail "corpus-blocking #$num" "--diagnosis-type $t_ changed '$base' to '$got'"; fi
  done
done < <(jq -c '.rows[]' "$HERE/fixtures/corpus-blocking.json")
assert_eq "regression: corpus-complexity + corpus-blocking unchanged under every non-meeting type ($reg_ok/$reg_total)" "$reg_total" "$reg_ok"
assert_eq "regression: (159 + 55) rows × 6 non-meeting Diagnosis types" "1284" "$reg_total"

# ── #383 r4: idd_diagnosis_type — the type recorded in the trusted Diagnosis ──
# Values from the spec's Diagnosis type table. The input is the latest trusted
# Diagnosis (author-filtered by every consumer), so this is not an adversarial
# reader: it uses the same section reader as ### Complexity.
dt_() { idd_diagnosis_type "$1" 2>/dev/null; }
td_() { printf '## Diagnosis\n\n### Type\n%s\n\n### Complexity\n\nSimple\n' "$1"; }
assert_eq "diagnosis type: ### Type meeting → meeting"                 "meeting" "$(dt_ "$(td_ meeting)")"
assert_eq "diagnosis type: meeting with a parenthetical note → meeting" "meeting" "$(dt_ "$(td_ 'meeting（本文 ## Type；label 不是 IDD 類型）')")"
assert_eq "diagnosis type: **meeting** → meeting"                      "meeting" "$(dt_ "$(td_ '**meeting**')")"
assert_eq "diagnosis type: Meeting (ASCII case) → meeting"             "meeting" "$(dt_ "$(td_ 'Meeting')")"
assert_eq "diagnosis type: bug → bug"                                  "bug"     "$(dt_ "$(td_ bug)")"
assert_eq "diagnosis type: docs → docs"                                "docs"    "$(dt_ "$(td_ docs)")"
assert_eq "diagnosis type: meeting-notes is not meeting → unknown"     "unknown" "$(dt_ "$(td_ 'meeting-notes')")"
# r5 #32: the spec's five-step boundary, row by row (the spec example table)
assert_eq "diagnosis type: meeting（…） → meeting (step 4: a full-width bracket may follow)" "meeting" "$(dt_ "$(td_ 'meeting（本文 ## Type）')")"
assert_eq "diagnosis type: meeting_ → meeting (step 3 strips a trailing _)"                "meeting" "$(dt_ "$(td_ 'meeting_')")"
assert_eq "diagnosis type: - meeting → unknown (step 1 does not strip a list bullet)"      "unknown" "$(dt_ "$(td_ '- meeting')")"
assert_eq "diagnosis type: type=meeting → unknown (step 2 takes the word type, which step 5 rejects)"      "unknown" "$(dt_ "$(td_ 'type=meeting')")"
assert_eq "diagnosis type: meeting2 is not meeting → unknown"          "unknown" "$(dt_ "$(td_ 'meeting2')")"
assert_eq "diagnosis type: a non-type word → unknown"                  "unknown" "$(dt_ "$(td_ 'deliberation')")"
assert_eq "diagnosis type: no ### Type heading → unknown"              "unknown" "$(dt_ $'## Diagnosis\n\n### Complexity\n\nSimple\n')"
assert_eq "diagnosis type: a fenced example ### Type is not read → bug" "bug" \
  "$(dt_ $'## Diagnosis\n\n```\n### Type\nmeeting\n```\n\n### Type\nbug\n')"
assert_eq "diagnosis type: an empty Diagnosis (none trusted) → none"   "none"    "$(dt_ '')"
idd_diagnosis_type >/dev/null 2>&1
assert_eq "diagnosis type: no argument is misuse (exit 2)" "2" "$?"
idd_diagnosis_type a b >/dev/null 2>&1
assert_eq "diagnosis type: two arguments is misuse (exit 2)" "2" "$?"
# The type input is gone from the issue side: no label or body reader remains.
refute_output_grep "helper: idd_issue_type was removed (r4 — the body is author-editable)" 'idd_issue_type()' "$LIB"
# A large Diagnosis under set -euo pipefail is not killed by SIGPIPE.
big_=$(printf '## Diagnosis\n\n### Type\nmeeting\n\n'; for i in $(seq 1 20000); do printf 'line %s padding padding padding\n' "$i"; done)
( set -euo pipefail; t_=$(idd_diagnosis_type "$big_"); [ "$t_" = meeting ] ); rc_=$?
assert_eq "diagnosis type: a large Diagnosis under set -euo pipefail returns meeting (no SIGPIPE)" "0" "$rc_"

# ── #383: consumers route on the type before any tier (meeting-issue-type spec
#    "Routing consumers honour the meeting type" / "Meeting Plan advances the
#    phase to planning") ──
IA_="$SKILLS/idd-all/SKILL.md"; IP_="$SKILLS/idd-plan/SKILL.md"; IM_="$SKILLS/idd-implement/SKILL.md"
IL_="$SKILLS/idd-list/SKILL.md"; IU_="$SKILLS/idd-update/SKILL.md"
assert_output_grep "idd-all: a meeting dispatch row comes before the tier rows"   '| `TYPE=meeting` · `VEXIT=0` |' "$IA_"
# verify #383 r1 (#16): a Meeting Plan is optional — the item names both next steps
assert_output_grep "idd-all: unattended meeting action item names /idd-plan or /idd-close" 'NEXT="next: attended /idd-plan #${RN} for a Meeting Plan, or /idd-close #${RN}' "$IA_"
assert_output_grep "idd-all: the stopped-at-diagnosed item carries that next step" 'stopped at diagnosed (unattended); ${NEXT}' "$IA_"
refute_output_grep "idd-all: no action item calls the plan a requirement"         'needs an attended /idd-plan' "$IA_"
assert_output_grep "idd-all: Phase 4 verify is skipped for meeting"               '`TYPE=meeting` → 跳過 Phase 4' "$IA_"
assert_output_grep "idd-all: Phase 5 push / PR is skipped for meeting"            '`TYPE=meeting` → 跳過 push 與 PR' "$IA_"
# r1 (#9, #15): the Action item is rebuilt in Phase 6, not carried in shell state
refute_output_grep "idd-all: no MEETING_ITEMS shell variable carried across phases" 'MEETING_ITEMS' "$IA_"
assert_output_grep "idd-all: Phase 6 re-resolves the type from the trusted Diagnosis" 'MT_PAGES=$(gh api "repos/$GITHUB_REPO/issues/$RN/comments"' "$IA_"
# r1 (#30): Phase 5 has a code guard, not only prose
assert_output_grep "idd-all: Phase 5 bash stops a mid-run meeting in code (r5 #11)" 'FATAL: Phase 5: the latest trusted Diagnosis of #$N now records meeting' "$IA_"
# r1 (#7, #23): the Phase 0.5 branch is unwound for a meeting issue in PR mode
assert_output_grep "idd-all: meeting dispatch unwinds the empty Phase 0.5 branch" 'removed the empty Phase 0.5 branch' "$IA_"
# ── verify #383 r2 (#4, #6, #12/C2): BEHAVIOUR, not prose. The meeting unwind
#    and the Phase 5 guard are extracted from idd-all and run in a scratch repo
#    with a stubbed `gh`. Round 1 pinned only their strings; round 2 then showed
#    the unwind deleted the branch of a NON-meeting run, and that a guard in its
#    own fence cannot stop the push in the next one. ──
ia_block_after() { awk -v h="$1" 'index($0, h) == 1 { f = 1; next } f && /^```bash$/ { inb = 1; next } inb && /^```$/ { exit } inb { print }' "$IA_"; }
UW_SRC=$(ia_block_after '#### meeting 分派前的 branch unwind')
assert_true "idd-all: the meeting unwind block is extractable" "[ -n \"\$UW_SRC\" ]"
uw_repo() {   # $1 = scratch dir; leaves a repo on branch idd/7-x with no commits ahead of main
  git_fixture_init "$1" -b main && git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init \
    && git -C "$1" checkout -q -b idd/7-x
}
uw_stub='gh() { case "$1" in repo) echo main ;; api) echo "[\"## Diagnosis\\n\\n### Type\\n$UW_TYPE\\n\"]" ;; issue) echo "{\"labels\":[],\"body\":\"## Type\\nmeeting\\n\"}" ;; esac; }'
uw_run() {   # $1 repo, $2 type
  ( cd "$1" && UW_TYPE="$2" N=7 GITHUB_REPO=o/r CWD="$1" PATH_AXIS=PR BRANCH=idd/7-x CLAUDE_PLUGIN_ROOT="$HERE/../../.." \
      GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
      bash -c "$uw_stub"$'\n'"$UW_SRC" 2>&1 )
}
UWD=$(git_fixture_mktemp) || exit 1
mkdir "$UWD/a" && uw_repo "$UWD/a" && out=$(uw_run "$UWD/a" bug); rc=$?
assert_eq "unwind (run): a non-meeting PR run exits 0" "0" "$rc"
assert_eq "unwind (run): a non-meeting PR run stays on its feature branch (r2 #4)" "idd/7-x" "$(git -C "$UWD/a" branch --show-current)"
assert_true "unwind (run): a non-meeting PR run keeps its feature branch" "git -C '$UWD/a' show-ref --verify --quiet refs/heads/idd/7-x"
mkdir "$UWD/b" && uw_repo "$UWD/b" && mkdir -p "$UWD/b/.claude/.idd/attachments/issue-7" \
  && printf '{"files": []}\n' > "$UWD/b/.claude/.idd/attachments/issue-7/_manifest.json" && out=$(uw_run "$UWD/b" meeting); rc=$?
assert_eq "unwind (run): a meeting run with a diagnose manifest exits 0" "0" "$rc"
assert_eq "unwind (run): it returns to the default branch" "main" "$(git -C "$UWD/b" branch --show-current)"
assert_eq "unwind (run): the working tree is clean afterwards, so the next PR-mode Phase 0.5 can start (r2 #6)" "" "$(git -C "$UWD/b" status --porcelain)"
assert_true "unwind (run): the manifest is kept, committed on the feature branch" "git -C '$UWD/b' cat-file -e idd/7-x:.claude/.idd/attachments/issue-7/_manifest.json"
assert_grep "unwind (run): it says the branch was kept and not pushed" 'not pushed' "$out"
mkdir "$UWD/c" && uw_repo "$UWD/c" && out=$(uw_run "$UWD/c" meeting); rc=$?
assert_eq "unwind (run): a meeting run with nothing to keep exits 0" "0" "$rc"
assert_eq "unwind (run): it returns to the default branch (empty case)" "main" "$(git -C "$UWD/c" branch --show-current)"
refute_grep "unwind (run): the empty branch is gone" 'idd/7-x' "$(git -C "$UWD/c" branch --list)"
assert_grep "unwind (run): it reports the removal only after it happened" 'removed the empty Phase 0.5 branch' "$out"
# r3 #2: lost shell state is a loud failure, not "no branch to unwind"
mkdir "$UWD/d" && uw_repo "$UWD/d" && mkdir -p "$UWD/d/.claude/.idd/attachments/issue-7" \
  && printf '{"files": []}\n' > "$UWD/d/.claude/.idd/attachments/issue-7/_manifest.json"
out=$( cd "$UWD/d" && UW_TYPE=meeting N=7 GITHUB_REPO=o/r CWD="$UWD/d" CLAUDE_PLUGIN_ROOT="$HERE/../../.." bash -c "$uw_stub"$'\n'"$UW_SRC" 2>&1 ); rc=$?
assert_eq "unwind (run): an unset PATH_AXIS is a loud failure (r3 #2)" "1" "$rc"
assert_grep "unwind (run): ... naming the lost shell state" 'PATH_AXIS' "$out"
assert_eq "unwind (run): ... and the branch is left as is" "idd/7-x" "$(git -C "$UWD/d" branch --show-current)"
# r4 #3/#8: a NON-meeting run with PATH_AXIS lost must not abort at the unwind
mkdir "$UWD/h" && uw_repo "$UWD/h"
out=$( cd "$UWD/h" && UW_TYPE=bug N=7 GITHUB_REPO=o/r CWD="$UWD/h" CLAUDE_PLUGIN_ROOT="$HERE/../../.." bash -c "$uw_stub"$'\n'"$UW_SRC" 2>&1 ); rc=$?
assert_eq "unwind (run): a non-meeting run with PATH_AXIS unset exits 0 (r4 #3)" "0" "$rc"
assert_eq "unwind (run): ... and keeps its branch" "idd/7-x" "$(git -C "$UWD/h" branch --show-current)"
# r4 #19: the issue body says meeting but the trusted Diagnosis says bug → no unwind
mkdir "$UWD/i" && uw_repo "$UWD/i" && out=$(uw_run "$UWD/i" bug)
assert_eq "unwind (run): a body that says meeting does not trigger the unwind (the Diagnosis says bug)" "idd/7-x" "$(git -C "$UWD/i" branch --show-current)"
# r3 #10: HEAD on the default branch → nothing to unwind, nothing committed to main
mkdir "$UWD/e" && uw_repo "$UWD/e" && git -C "$UWD/e" checkout -q main && mkdir -p "$UWD/e/.claude/.idd/attachments/issue-7" \
  && printf '{"files": []}\n' > "$UWD/e/.claude/.idd/attachments/issue-7/_manifest.json" && out=$(uw_run "$UWD/e" meeting); rc=$?
assert_eq "unwind (run): on the default branch it exits 0" "0" "$rc"
assert_eq "unwind (run): ... and commits nothing to main (r3 #10)" "1" "$(git -C "$UWD/e" rev-list --count main)"
# r3 #23: direct-commit makes no issue fetch (gh fails here and must not be reached)
mkdir "$UWD/f" && uw_repo "$UWD/f"
out=$( cd "$UWD/f" && N=7 GITHUB_REPO=o/r CWD="$UWD/f" PATH_AXIS=direct-commit CLAUDE_PLUGIN_ROOT="$HERE/../../.." bash -c 'gh() { echo GH-CALLED; return 1; }'$'\n'"$UW_SRC" 2>&1 ); rc=$?
assert_eq "unwind (run): direct-commit exits 0 without touching gh (r3 #23)" "0" "$rc"
refute_grep "unwind (run): ... no gh call on direct-commit" 'GH-CALLED' "$out"
# r3 #3/#6: the kept branch says how to get the manifest back
mkdir "$UWD/g" && uw_repo "$UWD/g" && mkdir -p "$UWD/g/.claude/.idd/attachments/issue-7" \
  && printf '{"files": []}\n' > "$UWD/g/.claude/.idd/attachments/issue-7/_manifest.json" && out=$(uw_run "$UWD/g" meeting)
assert_grep "unwind (run): the kept-branch line says what to do with it (r3 #3)" 'push it with a later PR' "$out"
# r5 #10: a lost CWD is loud for a meeting run, and harmless for a non-meeting one
mkdir "$UWD/j" && uw_repo "$UWD/j"
out=$( cd "$UWD/j" && UW_TYPE=meeting N=7 GITHUB_REPO=o/r CWD= PATH_AXIS=PR CLAUDE_PLUGIN_ROOT="$HERE/../../.." bash -c "$uw_stub"$'\n'"$UW_SRC" 2>&1 ); rc=$?
assert_eq "unwind (run): a meeting run with CWD lost is a loud failure (r5 #10)" "1" "$rc"
assert_grep "unwind (run): ... naming CWD" 'CWD is empty' "$out"
assert_eq "unwind (run): ... and the branch is left as is" "idd/7-x" "$(git -C "$UWD/j" branch --show-current)"
out=$( cd "$UWD/j" && UW_TYPE=bug N=7 GITHUB_REPO=o/r CWD= PATH_AXIS=PR CLAUDE_PLUGIN_ROOT="$HERE/../../.." bash -c "$uw_stub"$'\n'"$UW_SRC" 2>&1 ); rc=$?
assert_eq "unwind (run): a non-meeting run with CWD lost exits 0 (r5 #10)" "0" "$rc"
# r5 #14: a failed comment fetch leaves the branch and does not abort the run
mkdir "$UWD/k" && uw_repo "$UWD/k"
out=$( cd "$UWD/k" && N=7 GITHUB_REPO=o/r CWD="$UWD/k" PATH_AXIS=PR CLAUDE_PLUGIN_ROOT="$HERE/../../.." bash -c 'gh() { case "$1" in api) return 1 ;; repo) echo main ;; esac; }'$'\n'"$UW_SRC" 2>&1 ); rc=$?
assert_eq "unwind (run): a failed comment fetch does not abort the run (r5 #14)" "0" "$rc"
assert_grep "unwind (run): ... it says the type is unknown and how to unwind by hand" 'could not read the Diagnosis type of #7' "$out"
assert_eq "unwind (run): ... and the branch is left as is" "idd/7-x" "$(git -C "$UWD/k" branch --show-current)"
rm -rf "$UWD"
# r5 #11/#12: Phase 4 has a guard in code. A meeting run never reaches Phase 4
# (Phase 2 sends it to Phase 6), so a meeting Diagnosis here means the type
# changed after Phase 2 routed the issue as code work: stop, do not verify.
P4_SRC=$(ia_block_after '> **`TYPE=meeting` → 跳過 Phase 4')
assert_true "idd-all: the Phase 4 guard is extractable" "[ -n \"\$P4_SRC\" ]"
p4_run() {   # $1 = Diagnosis type (FAIL = the comment fetch fails), $2 = N
  ( P4T="$1" N="${2-7}" GITHUB_REPO=o/r CLAUDE_PLUGIN_ROOT="$HERE/../../.." \
      bash -c 'gh() { echo GH-CALLED >&2; [ "$P4T" = FAIL ] && return 1; echo "[\"## Diagnosis\\n\\n### Type\\n$P4T\\n\"]"; }'$'\n'"$P4_SRC" 2>&1 )
}
out=$(p4_run meeting); rc=$?
assert_eq "phase 4 (run): a meeting Diagnosis after implement stops the run (r5 #11)" "1" "$rc"
assert_grep "phase 4 (run): ... saying verify was not run and why" 'now records meeting, but Phase 2 routed this run as code work' "$out"
out=$(p4_run bug); rc=$?
assert_eq "phase 4 (run): a non-meeting run passes the guard" "0" "$rc"
refute_grep "phase 4 (run): ... silently" 'FATAL' "$out"
out=$(p4_run FAIL); rc=$?
assert_eq "phase 4 (run): a failed comment fetch does not stop a code run (r6 #2)" "0" "$rc"
assert_grep "phase 4 (run): ... it warns and continues into verify" 'comment fetch failed — cannot re-read the Diagnosis type of #7; continuing into verify' "$out"
out=$( P4T=bug N=7 GITHUB_REPO= CLAUDE_PLUGIN_ROOT="$HERE/../../.." bash -c 'gh() { echo GH-CALLED >&2; }'$'\n'"$P4_SRC" 2>&1 ); rc=$?
assert_eq "phase 4 (run): a lost GITHUB_REPO does not stop a code run (r6 #14)" "0" "$rc"
assert_grep "phase 4 (run): ... it names the lost shell state" 'GITHUB_REPO is empty (shell state lost)' "$out"
refute_grep "phase 4 (run): ... and makes no gh call" 'GH-CALLED' "$out"
out=$( N=7 GITHUB_REPO=o/r CLAUDE_PLUGIN_ROOT="$HERE/../../.." bash -c 'gh() { echo "not json"; }'$'\n'"$P4_SRC" 2>&1 ); rc=$?
assert_eq "phase 4 (run): an unreadable comment list does not fail open into a silent pass, nor stop (r6 #12)" "0" "$rc"
assert_grep "phase 4 (run): ... it warns that the list is not readable" 'is not readable — cannot re-read the Diagnosis type' "$out"
out=$(p4_run bug '7/../x'); rc=$?
assert_eq "phase 4 (run): a non-numeric issue number is fatal (r5 #12)" "1" "$rc"
refute_grep "phase 4 (run): ... before any gh call" 'GH-CALLED' "$out"
assert_output_grep "idd-all: the abort table lists the Phase 4 guard (r5 #11)" '| Phase 4 type guard:' "$IA_"
# Phase 5: the guard lives in the same shell as the push, on the PR path only.
P5_SRC=$(ia_block_after '**Conditional push + PR creation**')
assert_true "idd-all: the Phase 5 block is extractable" "[ -n \"\$P5_SRC\" ]"
p5_stub='git() { case "$*" in *push*) echo "PUSH-CALLED"; return 0 ;; esac; command git "$@"; }; gh() { case "$1" in api) if [ "$UW_TYPE" = meeting ]; then echo "[\"## Diagnosis\\n\\n### Type\\nmeeting\\n\"]"; else return 1; fi ;; pr) echo "PR-CALLED" ;; esac; }'
p5_run() { ( UW_TYPE="$1" N=7 GITHUB_REPO=o/r CWD=/nonexistent PATH_AXIS="$2" IN_CHAIN="${3:-}" BRANCH=idd/7-x CLAUDE_PLUGIN_ROOT="$HERE/../../.." bash -c "$p5_stub"$'\n'"$P5_SRC" 2>&1 ); }
out=$(p5_run meeting PR); rc=$?
assert_eq "phase 5 (run): a meeting Diagnosis at Phase 5 fails closed (r5 #11)" "1" "$rc"
assert_grep "phase 5 (run): ... saying the type changed after Phase 2 routed it" 'now records meeting, but Phase 2 routed this run as code work' "$out"
refute_grep "phase 5 (run): a meeting issue never reaches git push (r2 #12, C2)" 'PUSH-CALLED' "$out"
refute_grep "phase 5 (run): a meeting issue never opens a PR" 'PR-CALLED' "$out"
# r3 #27: positive control — a non-meeting PR run still reaches git push
# r4 #35: the issue body says meeting (as if the author rewrote it after implement); the trusted Diagnosis says bug
p5ok_stub='git() { case "$*" in *push*) echo "PUSH-CALLED"; return 0 ;; esac; return 0; }; gh() { case "$1" in api) echo "[\"## Diagnosis\\n\\n### Type\\nbug\\n\"]" ;; issue) echo "{\"labels\":[],\"body\":\"## Type\\nmeeting\\n\"}" ;; pr) echo "PR-CALLED" ;; *) return 0 ;; esac; }'
out=$( UW_TYPE=bug N=7 GITHUB_REPO=o/r CWD=/nonexistent PATH_AXIS=PR IN_CHAIN= BRANCH=idd/7-x CLAUDE_PLUGIN_ROOT="$HERE/../../.." bash -c "$p5ok_stub"$'\n'"$P5_SRC" 2>&1 )
assert_grep "phase 5 (run): a non-meeting PR run does call git push (positive control)" 'PUSH-CALLED' "$out"
assert_grep "phase 5 (run): ... even when the issue body was rewritten to meeting after implement (r4 #35)" 'PR-CALLED' "$out"
out=$( UW_TYPE=bug N='7/../x' GITHUB_REPO=o/r CWD=/nonexistent PATH_AXIS=PR IN_CHAIN= BRANCH=idd/7-x CLAUDE_PLUGIN_ROOT="$HERE/../../.." bash -c "$p5ok_stub"$'\n'"$P5_SRC" 2>&1 ); rc=$?
assert_eq "phase 5 (run): a non-numeric issue number stops before any fetch (r5 #12)" "1" "$rc"
refute_grep "phase 5 (run): ... and never pushes" 'PUSH-CALLED' "$out"
out=$(p5_run bug direct-commit); rc=$?
assert_eq "phase 5 (run): direct-commit makes no issue fetch, so a failing gh cannot abort it (r2 #5)" "0" "$rc"
out=$(p5_run bug PR "" ); rc=$?
assert_eq "phase 5 (run): a failed comment fetch on the PR path stops before pushing" "1" "$rc"
refute_grep "phase 5 (run): ... and never pushes" 'PUSH-CALLED' "$out"
out=$( UW_TYPE=bug N=7 GITHUB_REPO= CWD=/nonexistent PATH_AXIS=PR IN_CHAIN= BRANCH=idd/7-x CLAUDE_PLUGIN_ROOT="$HERE/../../.." bash -c "$p5ok_stub"$'\n'"$P5_SRC" 2>&1 ); rc=$?
assert_eq "phase 5 (run): a lost GITHUB_REPO stops before pushing (r6 #14)" "1" "$rc"
refute_grep "phase 5 (run): ... and never pushes" 'PUSH-CALLED' "$out"
out=$( N=7 GITHUB_REPO=o/r CWD=/nonexistent PATH_AXIS=PR IN_CHAIN= BRANCH=idd/7-x CLAUDE_PLUGIN_ROOT="$HERE/../../.." bash -c 'git() { case "$*" in *push*) echo PUSH-CALLED ;; esac; return 0; }; gh() { case "$1" in api) echo "not json" ;; pr) echo PR-CALLED ;; esac; }'$'\n'"$P5_SRC" 2>&1 ); rc=$?
assert_eq "phase 5 (run): an unreadable comment list stops before pushing (r6 #12)" "1" "$rc"
refute_grep "phase 5 (run): ... and never pushes" 'PUSH-CALLED' "$out"
# r2 (#9): the meeting report carries the #123 cleanup and names the Action-items section
assert_output_grep "idd-all: the meeting report clears the unattended flag (#123)" 'meeting report 印出後同樣 `clear_unattended "$CWD"`' "$IA_"
assert_output_grep "idd-all: the meeting report names the Action-items section" '「Phase 6 Action items surface」那一節' "$IA_"
# r2 (#14, #28, C3): the meeting Action item is for the root this run gated, never spawned issues;
# no Meeting Plan comment suppresses it; a failed re-resolve is itself an item
assert_output_grep "idd-all: the meeting Action item is computed for the root only" 'RN="${ROOT_N:-$N}"' "$IA_"
refute_output_grep "idd-all: no Meeting Plan comment suppresses the Action item" "grep -q '^## Meeting Plan'" "$IA_"
assert_output_grep "idd-all: a failed type re-resolve is surfaced, not skipped" 'could not re-resolve the issue type' "$IA_"
# r2 (#20, #5): the abort table carries the meeting exception and the Phase 5 FATALs
assert_output_grep "idd-all: the cexit=4 abort row names its meeting exception" '非 meeting;meeting 只在完全沒有受信任的 Diagnosis 時才 abort' "$IA_"
assert_output_grep "idd-all: the abort table lists the Phase 5 type-guard FATALs" 'Phase 5 type guard 失敗(PR 路徑)' "$IA_"
# r3 #4/#21: the Phase 6 Action-items block, run. ROOT_N is never assigned in
# idd-all; the meeting item must come from $N, appear only for a meeting whose
# body phase is diagnosed, and a non-meeting unattended run must print nothing.
P6_SRC=$(ia_block_after '#### Phase 6 Action items surface')
assert_true "idd-all: the Phase 6 Action-items block is extractable" "[ -n \"\$P6_SRC\" ]"
p6_run() {   # $1 = Diagnosis type, $2 = issue body (\n escapes), $3 = gh mode, $4 = EXISTING_WORK_ITEMS, $5 = INTERACTION, $6 = N, $7 = CWD
  ( N="${6-7}" INTERACTION="${5-unattended}" IDD_ALL_UNATTENDED= GITHUB_REPO=o/r CWD="${7-/nonexistent}" CLAUDE_PLUGIN_ROOT="$HERE/../../.." P6D="$1" P6B="$2" P6M="${3:-ok}" EXISTING_WORK_ITEMS="${4:-}" \
      bash -c 'gh() { [ "$P6M" = fail ] && return 1; case "$1" in issue) [ -z "$3" ] && return 1; printf "%b\n" "$P6B" ;; api) case "$2" in *"/issues//"*) return 1 ;; esac; echo "[\"## Diagnosis\\n\\n### Type\\n$P6D\\n\"]" ;; esac; }; git() { return 0; }'$'\n'"$P6_SRC" 2>&1 )
}
out=$(p6_run bug '## Problem\n\n---\n\n## Current Status\n\n**Phase**: diagnosed\n')
assert_eq "phase 6 (run): a non-meeting unattended run prints no Action items (r3 #4)" "" "$out"
out=$(p6_run meeting '## Problem\n\n---\n\n## Current Status\n\n**Phase**: diagnosed\n')
assert_grep "phase 6 (run): a diagnosed meeting root gets its item, numbered from \$N" '#7: type=meeting — stopped at diagnosed' "$out"
assert_grep "phase 6 (run): ... naming both next steps" 'next: attended /idd-plan #7 for a Meeting Plan, or /idd-close #7' "$out"
out=$(p6_run meeting '## Problem\n\n---\n\n## Current Status\n\n**Phase**: created\n')
refute_grep "phase 6 (run): a meeting root that never reached diagnosed gets no stopped-at-diagnosed item (r3 #21)" 'stopped at diagnosed' "$out"
assert_grep "phase 6 (run): ... but it is told that the body is not at diagnosed (r4 #16)" 'does not show phase diagnosed' "$out"
out=$(p6_run '' '' fail)
assert_grep "phase 6 (run): a failed re-resolve is itself an item" 'could not re-resolve the issue type' "$out"
out=$(p6_run meeting '## Problem\n\n---\n\n## Current Status\n\n**Phase**: diagnosed\n' ok $'\n- #7: existing-work lookup unknown (gh api timeout) — check by hand')
assert_grep "phase 6 (run): an unknown existing-work line does not suppress the meeting item (r4 #4)" '#7: type=meeting — stopped at diagnosed' "$out"
out=$(p6_run meeting '## Problem\n\n---\n\n## Current Status\n\n**Phase**: diagnosed\n' ok $'\n- #7: existing PR #12 declares it — not started; review it (/idd-verify #7 --pr 12) or run /idd-all #7 interactively')
refute_grep "phase 6 (run): an issue Step 0.5.1 blocked gets no stopped-at-diagnosed item (r3 #21)" 'type=meeting — stopped at diagnosed' "$out"
out=$(p6_run meeting '## Problem\n\n---\n\n## Current Status\n\n**Phase**: diagnosed\n' ok '' '')
assert_grep "phase 6 (run): a lost interaction mode is itself an item (r4 #12)" 'interaction mode of this run was lost' "$out"
# r5 #2: lost shell state adds nothing to a NON-meeting run
out=$(p6_run bug '## Problem\n\n---\n\n## Current Status\n\n**Phase**: diagnosed\n' ok '' '')
assert_eq "phase 6 (run): a non-meeting run with INTERACTION lost prints nothing (r5 #2)" "" "$out"
out=$(p6_run bug '## Problem\n\n---\n\n## Current Status\n\n**Phase**: diagnosed\n' ok '' '' '')
assert_eq "phase 6 (run): a run with both N and INTERACTION lost prints nothing (r5 #2)" "" "$out"
out=$(p6_run bug '' ok '' unattended '')
assert_grep "phase 6 (run): an unattended run that lost N says so" 'issue number of this run was lost' "$out"
# r5 #13: attended runs make no lookup; non-meeting runs never fetch the body
out=$(p6_run meeting '' fail '' attended)
assert_eq "phase 6 (run): an attended run makes no type lookup (r5 #13)" "" "$out"
out=$( N=7 INTERACTION=unattended IDD_ALL_UNATTENDED= GITHUB_REPO=o/r CWD=/nonexistent CLAUDE_PLUGIN_ROOT="$HERE/../../.." \
  bash -c 'gh() { case "$1" in issue) echo BODY-FETCHED >&2 ;; api) echo "[\"## Diagnosis\\n\\n### Type\\nbug\\n\"]" ;; esac; }; git() { return 0; }'$'\n'"$P6_SRC" 2>&1 )
assert_eq "phase 6 (run): a non-meeting unattended run does not fetch the issue body (r5 #13)" "" "$out"
# INTERACTION lost but the unattended state file is still there → treated as unattended
P6S=$(git_fixture_mktemp) || exit 1
mkdir -p "$P6S/.claude/.idd/state" \
  && printf '{"active":true,"by":"idd-all","started_at":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$P6S/.claude/.idd/state/unattended.json"
out=$(p6_run meeting '## Problem\n\n---\n\n## Current Status\n\n**Phase**: diagnosed\n' ok '' '' 7 "$P6S")
assert_grep "phase 6 (run): a lost INTERACTION is recovered from the unattended state file" '#7: type=meeting — stopped at diagnosed' "$out"
rm -rf "$P6S"
# r5 #28: the phase is read from ## Current Status only, not from author-written lines
out=$(p6_run meeting '## Problem\n\n**Phase**: diagnosed\n')
refute_grep "phase 6 (run): a **Phase** line outside ## Current Status does not count (r5 #28)" 'stopped at diagnosed' "$out"
assert_grep "phase 6 (run): ... the item says the body does not show the phase" 'does not show phase diagnosed' "$out"
# r6 #14/#23: a type lookup that cannot run adds an item only when the run is known to be unattended
out=$(p6_run meeting '' fail '' '')
assert_eq "phase 6 (run): a failed lookup with INTERACTION lost prints nothing (r6 #14)" "" "$out"
out=$( N=7 INTERACTION=unattended IDD_ALL_UNATTENDED= GITHUB_REPO= CWD=/nonexistent CLAUDE_PLUGIN_ROOT="$HERE/../../.." bash -c 'gh() { echo GH-CALLED >&2; }; git() { return 0; }'$'\n'"$P6_SRC" 2>&1 )
assert_grep "phase 6 (run): an unattended run that lost GITHUB_REPO says the type could not be re-resolved" 'could not re-resolve the issue type' "$out"
refute_grep "phase 6 (run): ... without a gh call" 'GH-CALLED' "$out"

# ── verify #383 r6 (#3): the author filter itself. Every stub above returns an
#    already-filtered list, so deleting the four `select(.author_association …)`
#    filters left the suite green. This stub runs the caller's own --jq against a
#    raw comment list whose LATEST Diagnosis is a meeting posted by an outside
#    author (NONE); the trusted Diagnosis before it says bug. ──
RAW_UNTRUSTED='[{"author_association":"OWNER","body":"## Diagnosis\n\n### Type\nbug\n"},{"author_association":"NONE","body":"## Diagnosis\n\n### Type\nmeeting\n"}]'
RAW_TRUSTED='[{"author_association":"OWNER","body":"## Diagnosis\n\n### Type\nbug\n"},{"author_association":"MEMBER","body":"## Diagnosis\n\n### Type\nmeeting\n"}]'
RAWC_STUB=$(cat <<'EOS'
gh() {
  case "$1" in
    api) local f=""; shift
         while [ $# -gt 0 ]; do if [ "$1" = --jq ]; then f="$2"; shift; fi; shift; done
         [ -n "$f" ] || return 1
         printf '%s' "$RAWC" | jq -c "$f" ;;
    pr) echo PR-CALLED ;;
    repo) echo main ;;
    issue) printf '%b\n' "${P6B:-}" ;;
    *) return 0 ;;
  esac
}
EOS
)
raw_env() { env RAWC="$1" N=7 GITHUB_REPO=o/r IDD_ALL_UNATTENDED= CLAUDE_PLUGIN_ROOT="$HERE/../../.." "${@:2}"; }
out=$(raw_env "$RAW_UNTRUSTED" bash -c "$RAWC_STUB"$'\n'"$P4_SRC" 2>&1); rc=$?
assert_eq "author filter (run): Phase 4 ignores an outside author's meeting Diagnosis (r6 #3)" "0" "$rc"
out=$(raw_env "$RAW_TRUSTED" bash -c "$RAWC_STUB"$'\n'"$P4_SRC" 2>&1); rc=$?
assert_eq "author filter (run): ... positive control: a MEMBER's meeting Diagnosis stops Phase 4" "1" "$rc"
out=$(raw_env "$RAW_UNTRUSTED" CWD=/nonexistent PATH_AXIS=PR IN_CHAIN= BRANCH=idd/7-x bash -c 'git() { case "$*" in *push*) echo PUSH-CALLED ;; esac; return 0; }'$'\n'"$RAWC_STUB"$'\n'"$P5_SRC" 2>&1)
assert_grep "author filter (run): Phase 5 ignores an outside author's meeting Diagnosis and pushes (r6 #3)" 'PUSH-CALLED' "$out"
out=$(raw_env "$RAW_TRUSTED" CWD=/nonexistent PATH_AXIS=PR IN_CHAIN= BRANCH=idd/7-x bash -c 'git() { case "$*" in *push*) echo PUSH-CALLED ;; esac; return 0; }'$'\n'"$RAWC_STUB"$'\n'"$P5_SRC" 2>&1)
refute_grep "author filter (run): ... positive control: a MEMBER's meeting Diagnosis stops the push" 'PUSH-CALLED' "$out"
CS6='## Problem\n\n---\n\n## Current Status\n\n**Phase**: diagnosed\n'
out=$(raw_env "$RAW_UNTRUSTED" INTERACTION=unattended CWD=/nonexistent P6B="$CS6" bash -c 'git() { return 0; }'$'\n'"$RAWC_STUB"$'\n'"$P6_SRC" 2>&1)
assert_eq "author filter (run): Phase 6 ignores an outside author's meeting Diagnosis (r6 #3)" "" "$out"
out=$(raw_env "$RAW_TRUSTED" INTERACTION=unattended CWD=/nonexistent P6B="$CS6" bash -c 'git() { return 0; }'$'\n'"$RAWC_STUB"$'\n'"$P6_SRC" 2>&1)
assert_grep "author filter (run): ... positive control: a MEMBER's meeting Diagnosis gets the item" '#7: type=meeting — stopped at diagnosed' "$out"
RWD=$(git_fixture_mktemp) || exit 1
mkdir "$RWD/a" && uw_repo "$RWD/a" && out=$( cd "$RWD/a" && raw_env "$RAW_UNTRUSTED" CWD="$RWD/a" PATH_AXIS=PR GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t bash -c "$RAWC_STUB"$'\n'"$UW_SRC" 2>&1 )
assert_eq "author filter (run): the unwind ignores an outside author's meeting Diagnosis (r6 #3)" "idd/7-x" "$(git -C "$RWD/a" branch --show-current)"
mkdir "$RWD/b" && uw_repo "$RWD/b" && out=$( cd "$RWD/b" && raw_env "$RAW_TRUSTED" CWD="$RWD/b" PATH_AXIS=PR GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t bash -c "$RAWC_STUB"$'\n'"$UW_SRC" 2>&1 )
assert_eq "author filter (run): ... positive control: a MEMBER's meeting Diagnosis is unwound" "main" "$(git -C "$RWD/b" branch --show-current)"
# r6 #14 / #12 in the unwind: lost GITHUB_REPO is loud; an unreadable list only warns
mkdir "$RWD/c" && uw_repo "$RWD/c" && out=$( cd "$RWD/c" && N=7 GITHUB_REPO= CWD="$RWD/c" PATH_AXIS=PR CLAUDE_PLUGIN_ROOT="$HERE/../../.." bash -c 'gh() { echo GH-CALLED; }'$'\n'"$UW_SRC" 2>&1 ); rc=$?
assert_eq "unwind (run): a lost GITHUB_REPO does not abort the run (PR #398 review; r4 #3)" "0" "$rc"
assert_grep "unwind (run): ... it names the lost shell state" 'GITHUB_REPO is empty (shell state lost)' "$out"
refute_grep "unwind (run): ... before any gh call" 'GH-CALLED' "$out"
assert_eq "unwind (run): ... and the branch is left as is" "idd/7-x" "$(git -C "$RWD/c" branch --show-current)"
mkdir "$RWD/d" && uw_repo "$RWD/d" && out=$( cd "$RWD/d" && N=7 GITHUB_REPO=o/r CWD="$RWD/d" PATH_AXIS=PR CLAUDE_PLUGIN_ROOT="$HERE/../../.." bash -c 'gh() { echo "not json"; }'$'\n'"$UW_SRC" 2>&1 ); rc=$?
assert_eq "unwind (run): an unreadable comment list only warns (r6 #12)" "0" "$rc"
assert_grep "unwind (run): ... saying so" 'comment list of #7 is not readable' "$out"
assert_eq "unwind (run): ... and the branch is left as is" "idd/7-x" "$(git -C "$RWD/d" branch --show-current)"
rm -rf "$RWD"
# r6 #1/#8: the report follows the route this run took; Action items run before the cleanup
assert_output_grep "idd-all: the report template follows the route this run took (r6 #1)" '選樣板看本次**實際走的路線**,不看重讀的 type' "$IA_"
assert_output_grep "idd-all: a type change during the run is a warning line, not a template swap" '⚠ type changed during this run' "$IA_"
assert_output_grep "idd-all: Action items run before clear_unattended (r6 #8)" '**順序:先跑 Action items 區塊,再清理**' "$IA_"
# r1 (#6, #8, #14): Phase 6 has a meeting report that claims no verify / PR
assert_output_grep "idd-all: Phase 6 has a meeting report"                        '✓ idd-all stopped (type=meeting)' "$IA_"
assert_output_grep "idd-all: the terminal-phase rule names its meeting exception" 'Verify is the terminal phase regardless of mode**（meeting issue 例外' "$IA_"
n_tier_=$(grep -n '^| `0` · `0` · `Simple` |' "$IA_" | head -1 | cut -d: -f1)
n_meet_=$(grep -n -F '| `TYPE=meeting` · `VEXIT=0` |' "$IA_" | head -1 | cut -d: -f1)
assert_true "idd-all: the meeting row precedes the first tier row (meeting@${n_meet_:-?} < Simple@${n_tier_:-?})" "[ -n '$n_meet_' ] && [ -n '$n_tier_' ] && [ '$n_meet_' -lt '$n_tier_' ]"
assert_output_grep "idd-plan: a meeting row in the Step 1 gate table"             '| `TYPE=meeting` · `VEXIT=0` |' "$IP_"
assert_output_grep "idd-implement: refuses meeting with its own message"          'meeting 不走 implement' "$IM_"
meet_row_=$(grep -F '| `TYPE=meeting` · `VEXIT=0` |' "$IM_")
assert_true "idd-implement: the meeting row exists and is keyed on VEXIT=0 (r1 #19)" "[ -n \"\$meet_row_\" ]"
refute_grep_re "idd-implement: the meeting row never asks to fix the Diagnosis (any wording, r1 #32)" '(修正|修) *Diagnosis|fix the Diagnosis' "$meet_row_"
assert_output_grep "idd-list: meeting next action is /idd-plan while diagnosed"   '`TYPE=meeting` 且 phase `diagnosed` → `/idd-plan #N`' "$IL_"
assert_output_grep "idd-list: meeting next action is /idd-close in phase planning (r1 #20)" '`TYPE=meeting` 且 phase `planning` → `/idd-close #N`' "$IL_"
assert_output_grep "idd-list: the Step 3 heading fallback reads ## Meeting Plan as planning" '`## Meeting Plan` → `planning`（#383）' "$IL_"
assert_output_grep "idd-list: the meeting rows say their enumeration covers every other phase (r2 #16)" '第二列涵蓋 `planning` 以外的**所有** phase' "$IL_"
refute_output_grep "idd-list: no claim that the heading fallback covers a stale body (r2 #10)" 'body 還沒 sync 時由 Step 3 的 heading fallback 讀到' "$IL_"
assert_output_grep "idd-plan: the aborted row has a meeting variant without Complexity (r2 #23)" 'Meeting Plan 中止：{reason}' "$IP_"
assert_output_grep "idd-list: an undiagnosed meeting stays in the undiagnosed group" '歸 **undiagnosed** 組，下一步是 `/idd-diagnose #N`' "$IL_"
assert_output_grep "idd-update: Meeting Plan is a planning row in the phase table" '| Meeting Plan | `planning` |' "$IU_"
assert_output_grep "idd-update: the heading list names ## Meeting Plan"          '`## Meeting Plan`' "$IU_"
# reference (task 5.1): the meeting section, its spec citation, and the sentinel rejection
assert_output_grep "reference: a section on the issue type input (#383)"        '### The Diagnosis type — a diagnosed meeting drops the Complexity signal only' "$REF"
assert_output_grep "reference: cites the meeting-issue-type spec"                'openspec/specs/meeting-issue-type/spec.md' "$REF"
assert_output_grep "reference: states why there is no meeting sentinel in Complexity" 'no `meeting` sentinel' "$REF"
assert_output_grep "reference: the non-routable default names its meeting exception" 'except for a diagnosed `meeting` issue' "$REF"
assert_output_grep "reference: the trust claim names the producer rule (r5 #3/#27)" 'never to infer meeting from content' "$REF"
assert_output_grep "reference: the trust claim states its limits (r6 #15/#33)" 'the rule is an instruction the model follows, not a code check' "$REF"
assert_output_grep "reference: TYPE is one of seven Diagnosis types (r5 #6)"    'one of seven Diagnosis types' "$REF"

# ── verify #383 r5 (#3): the PRODUCER. idd-all re-runs idd-diagnose on every run,
#    so a body `## Type: meeting` copied from an outside author would produce a
#    trusted meeting Diagnosis and switch the Complexity signal off. The block
#    that decides whether a body meeting may be adopted is extracted and run. ──
ID_="$SKILLS/idd-diagnose/SKILL.md"
block_after_in() { awk -v h="$1" 'index($0, h) == 1 { f = 1; next } f && /^```bash$/ { inb = 1; next } inb && /^```$/ { exit } inb { print }' "$2"; }
DG_SRC=$(block_after_in '**本文 meeting 的採信條件' "$ID_")
assert_true "idd-diagnose: the body-meeting trust block is extractable" "[ -n \"\$DG_SRC\" ]"
dg_run() {   # $1 = issue number, $2 = author_association the stubbed gh returns (FAIL = the lookup fails)
  ( NUMBER="$1" GITHUB_REPO=o/r DGA="$2" bash -c 'gh() { [ "$DGA" = FAIL ] && return 1; echo "$DGA"; }'$'\n'"$DG_SRC" 2>&1 )
}
for a_ in OWNER MEMBER COLLABORATOR; do
  assert_grep "idd-diagnose (run): a $a_ author's body meeting is adoptable" 'BODY_MEETING_TRUSTED=yes' "$(dg_run 7 "$a_")"
done
for a_ in NONE CONTRIBUTOR FIRST_TIME_CONTRIBUTOR FIRST_TIMER MANNEQUIN ''; do
  assert_grep "idd-diagnose (run): a '${a_:-empty}' author's body meeting is not adopted" 'BODY_MEETING_TRUSTED=no' "$(dg_run 7 "$a_")"
done
out=$(dg_run 7 FAIL); rc=$?
assert_eq "idd-diagnose (run): a failed association lookup does not stop diagnosis" "0" "$rc"
assert_grep "idd-diagnose (run): ... and is not trusted (fail-safe)" 'unknown → BODY_MEETING_TRUSTED=no' "$out"
out=$( NUMBER='7/../x' GITHUB_REPO=o/r bash -c 'gh() { echo GH-CALLED; echo OWNER; }'$'\n'"$DG_SRC" 2>&1 ); rc=$?
assert_eq "idd-diagnose (run): a non-numeric issue number does not stop diagnosis (r6 #18)" "0" "$rc"
assert_grep "idd-diagnose (run): ... it is not trusted" 'BODY_MEETING_TRUSTED=no' "$out"
refute_grep "idd-diagnose (run): ... and no gh call is made" 'GH-CALLED' "$out"
assert_eq "idd-diagnose (run): the trust line names its issue (r6 #22)" "#7 issue author association: OWNER → BODY_MEETING_TRUSTED=yes" "$(dg_run 7 OWNER)"
assert_eq "idd-diagnose (run): an issue number written as #7 is still looked up (PR #398 review)" "#7 issue author association: OWNER → BODY_MEETING_TRUSTED=yes" "$(dg_run '#7' OWNER)"
assert_output_grep "idd-diagnose: a body meeting needs BODY_MEETING_TRUSTED=yes" '只有下方採信判斷印出 `BODY_MEETING_TRUSTED=yes` 才採用' "$ID_"
assert_output_grep "idd-diagnose: inference never yields meeting"               '推斷永遠不得產生 `meeting`' "$ID_"
refute_output_grep "idd-diagnose: no bare 'default non-meeting' that inference could override" '依內容推斷，**預設非 meeting**' "$ID_"
assert_output_grep "idd-diagnose: the ### Type line never starts with a rejected declaration (r6 #19)" '**`### Type` 那一行只寫採用的值**' "$ID_"
assert_output_grep "idd-diagnose: two or more IDD type labels count as none (r6 #21)" '**兩個以上**（例如維護者在既有的 `bug` 上又加了 `meeting`）視同沒有 type label' "$ID_"
assert_output_grep "idd-diagnose: a failed lookup gets its own sentence (r6 #4)" '本文宣告 meeting，但查不到 issue 作者的 association' "$ID_"

print_summary "actionability-gate"
