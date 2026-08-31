#!/usr/bin/env bash
# Test: idd-plan's account of idd-all's Plan routing matches idd-all (#317).
#
# WHY THIS EXISTS
#
# #292 moved Plan-tier routing so that ATTENDED /idd-all calls /idd-plan (the
# EnterPlanMode gate lives there, not in /idd-implement). idd-all was updated;
# idd-plan's "與 idd-all 的整合" section was not, and it stated the old rule as
# a UNIVERSAL: "idd-all 不該走 Plan path". Its unattended half was right — the
# error was writing one branch's conclusion without its condition. A reader
# taking idd-plan as the source concluded the opposite of what runs.
#
# Same failure the repo's own doctrine warns about: a blanket judgement plus
# examples is two specifications that will not be edited together. Enumerate.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"

PLAN=$(cat "$PLUGIN/skills/idd-plan/SKILL.md")
ALL=$(cat "$PLUGIN/skills/idd-all/SKILL.md")

# The normative side first. If idd-all ever stops routing attended Plan to
# /idd-plan, the reader-side assertions below are pinning fiction — so they are
# asserted against the source, not assumed.
assert_grep "idd-all routes attended Plan tier to /idd-plan" \
  'attended → Phase 3p: `/idd-plan`' "$ALL"
assert_grep "idd-all downgrades Plan tier only under unattended" \
  'unattended → Phase 3a: idd-implement' "$ALL"

# The reader side.
refute_grep "idd-plan no longer states the blanket 'idd-all must not take the Plan path'" \
  "idd-all 不該走 Plan path**。Plan tier 的核心價值" "$PLAN"
assert_grep "idd-plan splits the two interaction modes" "attended | unattended" "$PLAN"
assert_grep "idd-plan says the downgrade is unattended-only" "降級只發生在 unattended" "$PLAN"
assert_grep "idd-plan defers to idd-all as the normative source" \
  "normative source 是" "$PLAN"

# ── One fact, one place: restating idd-all's Plan routing is the violation ──
#
# #317 (c) asks 「檢查是否還有第三處複述 idd-all 的 Plan routing」. It has now been
# answered wrongly TWICE, each time by grepping for a string:
#
#   round 1: grepped `Phase 3p` — the implementation LABEL. docs/workflows.md
#            stated the opposite CLAIM without ever using the token.
#   round 2: grepped the two literal Chinese phrases from THAT violation. A live
#            spec (openspec/specs/idd-pr-hitl-modes/spec.md) said the opposite in
#            ENGLISH, and two more files inside the scanned dirs were cleared
#            solely because they used different words.
#
# Both answer "where is this string", not "who makes this claim" — and the second
# was worse than the first, because it looked specific. So the rule is no longer
# about wording at all:
#
#   A file that pairs Plan tier with a mode word AND a routing-mechanism token is
#   making a routing claim. It must either BE the normative source, or defer to
#   it. Restating the mechanism — correctly or not — is what the criterion
#   forbids, because a correct copy is one edit away from a wrong one.
#
# That is checkable without remembering any previous violation, and it catches a
# restatement written in a language nobody anticipated.
# Exempt: CHANGELOG (a log of what was true then) and archived change proposals
# (snapshots of a past decision). Rewriting either to match today would falsify a
# record. A LIVE spec is NOT in that category — openspec/specs/ is current, and
# that is exactly where round 2's surviving violation sat.
# Exempt: CHANGELOG (a log of what was true then) and archived change proposals
# (snapshots of a past decision). Rewriting either to match today would falsify a
# record. A LIVE spec is NOT in that category — openspec/specs/ is current, and
# that is exactly where round 2's surviving violation sat.
NORMATIVE='skills/idd-all/SKILL.md'
# ROUTING tokens only. Bare skill names (`idd-implement`, `/idd-plan`) are not in
# the set: they appear in ordinary prose everywhere, and a file that merely names
# both skills is not restating routing. The first cut included them and flagged a
# path catalogue and a design-rationale note — false positives that would have
# taught the next reader to widen the exemption list instead of the rule.
# ALL FOUR vocabularies are matched lowercased below, so they are written
# lowercase here. The previous cut folded case for the Plan token only, while
# the commit message claimed the detector was case-insensitive -- and three of
# the four kept matching literally. `Hybrid`, `Attended`, `EnterPlanMode` in a
# heading: each escaped a different one of them.
MECHANISM='enterplanmode|phase 3a|phase 3p'
# `noninteractive` / `headless` / `without a user` are the same claim in other
# words; leaving them out is the round-2 mistake (grep the wording you remember)
# in miniature. `hybrid` is here because docs/workflows.md:106 used it as its
# mode word and sailed through four rounds of this detector: it is the repo's
# own name for "attended for Plan tier, unattended otherwise", i.e. precisely a
# routing claim that depends on the interaction axis.
MODE_WORD='unattended|attended|hybrid|/loop|autopilot|noninteractive|non-interactive|headless|without a user|no user'
DEFER='dispatch table|normative source|不複述|見 .skills/idd-all'
# A deference pointer that DENIES being one is not a pointer. `defer` is a plain
# substring test, so the sentence "this is not the normative source" exempted
# every claim within ten lines of it -- an escape hatch made of the exact words
# the rule asks for. Any line matching DEFER is discarded if it also matches
# this.
DEFER_NEG='not the normative|不是 normative|非 normative|is not a dispatch table'

# The claim has to actually be MADE, not merely have its vocabulary scattered
# across a long document: a routing-mechanism line with a mode word near it.
# File-level pairing was too coarse (a catalogue describing many paths mentions
# `unattended` for a different one); same-line everywhere was too tight (the
# violation that started this had `**Mode**:Unattended` two lines above).
#
# A TABLE ROW is self-contained, so for `|`-rows the mode word must be on that
# same row: adjacent rows are unrelated topics, and the ±5 window read a skill
# catalogue's neighbouring entry as context for this one.
ROOT="$(cd "$PLUGIN/../.." && pwd)"
restating_files() {   # $1 = tree to scan
  # -i on the OUTER enumeration too. Lowercasing inside the awk was not enough:
  # this grep decides which files reach it at all, and it was case-sensitive, so
  # `PLAN TIER` never got that far. Two places had to agree and only one was
  # changed — which is exactly the shape of defect this suite exists to catch.
  grep -rliE --include='*.md' -- 'Plan[ -]tier|Plan path' "$1" 2>/dev/null \
    | grep -v '/CHANGELOG.md$' \
    | grep -v '/openspec/changes/archive/' \
    | while IFS= read -r f; do
        case "$f" in *"$NORMATIVE") continue ;; esac        # the source may state it
        # Deference is checked PER CLAIM, in the same window as the claim --
        # NOT per file. A file-level `grep && continue` is a blanket amnesty:
        # adding one deference pointer anywhere exempts every other restatement
        # in the same document. That is not hypothetical -- it happened here.
        # docs/workflows.md:570 restates the routing and says the OPPOSITE of
        # line 407, which this same round had just fixed; the detector FOUND it
        # and the file-level exemption threw it away, because 407 now carries a
        # pointer. The fix created the amnesty that hid the violation.
        awk -v mech="$MECHANISM" -v mode="$MODE_WORD" -v defer="$DEFER" \
            -v deferneg="$DEFER_NEG" -v f="$f" '
          { line[NR] = $0 }
          END {
            for (n = 1; n <= NR; n++) {
              # The Plan token and the mechanism token do NOT have to share a
              # line. Requiring that missed every claim spread over a short
              # paragraph -- and a paragraph is how prose actually states this.
              # Case-insensitive too: `Plan Tier` and `PLAN TIER` escaped a
              # case-sensitive match.
              if (tolower(line[n]) !~ /plan[ -]tier|plan path/) continue
              plo = (n - 5 < 1 ? 1 : n - 5); phi = (n + 5 > NR ? NR : n + 5)
              has_mech = 0
              for (m = plo; m <= phi; m++) if (tolower(line[m]) ~ mech) has_mech = 1
              if (!has_mech) continue
              # A version-history row (first cell is a version) is a release
              # log embedded in a table -- same category as CHANGELOG.md, and
              # exempt for the same reason: it records what was true then, and
              # editing it to match today would falsify the record.
              if (line[n] ~ /^[ \t]*\|[ \t]*v[0-9]/) continue
              if (line[n] ~ /^[ \t]*\|/) { lo = n; hi = n }        # table row: same row only
              else { lo = (n - 5 < 1 ? 1 : n - 5); hi = (n + 5 > NR ? NR : n + 5) }
              # The DEFERENCE window is wider than the CLAIM window, on purpose.
              # A claim is made on a line (or a table row); a deference pointer
              # legitimately introduces a whole block -- a table caption covers
              # its rows. Same-row deference would force the pointer into every
              # row. Still per-claim, not per-file: ten lines, not the document.
              dlo = (n - 10 < 1 ? 1 : n - 10); dhi = (n + 10 > NR ? NR : n + 10)
              deferred = 0
              for (m = dlo; m <= dhi; m++)
                if (tolower(line[m]) ~ defer && tolower(line[m]) !~ deferneg) deferred = 1
              if (deferred) continue
              for (m = lo; m <= hi; m++)
                if (tolower(line[m]) ~ mode) { print f ":" n; exit }
            }
          }' "$f"
      done
}

BAD=$(restating_files "$ROOT" || true)
require "no file restates idd-all's Plan routing without deferring to it" \
  bash -c '[ -z "$0" ] || { printf "%s\n" "$0"; exit 1; }' "$BAD"

# ── Positive control, over THE DETECTOR ──
#
# The previous control planted a canary and then checked that the ENUMERATION
# listed the file. It never ran the detector, so when the detector's needle was
# replaced with a string that matches nothing, the suite stayed green — proven by
# mutation. A control that exercises a different function than the assertion is
# not a control. This one plants a restatement and requires the DETECTOR to name
# it, and plants a deferring file and requires the detector to stay silent.
PC_DIR=$(mktemp -d); trap 'rm -rf "$PC_DIR"' EXIT HUP INT TERM
cat > "$PC_DIR/restates.md" <<'CANARY'
Under unattended mode a Plan tier issue still reaches EnterPlanMode via Phase 3a.
CANARY
# SPREAD ACROSS LINES, because that is how prose states it and because a
# single-line control cannot tell whether the window works at all. Every control
# here previously put Plan, mode and mechanism on one line, so shrinking the
# window to zero would have left them all green -- the guard had no test weight
# with respect to its own window parameter.
cat > "$PC_DIR/restates-spread.md" <<'CANARY'
Plan tier behaviour:

When no user is present, the run is noninteractive.

Phase 3a invokes idd-implement directly, so EnterPlanMode never fires.
CANARY
cat > "$PC_DIR/defers.md" <<'CANARY'
Plan tier routing under unattended mode: see the dispatch table in skills/idd-all/SKILL.md.
CANARY
# A restatement inside an ordinary table row must still be caught -- the
# version-history exemption above is narrow, and this proves it did not widen
# into "tables are exempt".
cat > "$PC_DIR/restates-table.md" <<'CANARY'
| mode | behaviour |
|---|---|
| unattended | Plan tier still reaches EnterPlanMode via Phase 3a |
CANARY
SEEN_TABLE=$(restating_files "$PC_DIR" | grep -c 'restates-table.md' || true)
# Case. A case-sensitive `Plan tier` match let `Plan Tier` and `PLAN TIER`
# through, and no control used either spelling, so lowering the token had no
# test weight — the parameter was unguarded by its own controls.
cat > "$PC_DIR/restates-case.md" <<'CANARY'
PLAN TIER, unattended: EnterPlanMode still fires via Phase 3a.
CANARY
SEEN_CASE=$(restating_files "$PC_DIR" | grep -c 'restates-case.md' || true)
SEEN_SPREAD=$(restating_files "$PC_DIR" | grep -c 'restates-spread.md' || true)
SEEN=$(restating_files "$PC_DIR" | grep -c 'restates.md' || true)
QUIET=$(restating_files "$PC_DIR" | grep -c 'defers.md' || true)
require "positive control: the detector names a planted restatement" \
  bash -c '[ "$0" -ge 1 ]' "$SEEN"
require "negative control: the detector stays silent on a file that defers" \
  bash -c '[ "$0" -eq 0 ]' "$QUIET"
require "positive control: an upper-case Plan token is caught" \
  bash -c '[ "$0" -ge 1 ]' "$SEEN_CASE"
require "positive control: a claim SPREAD over several lines is caught" \
  bash -c '[ "$0" -ge 1 ]' "$SEEN_SPREAD"
require "positive control: a restatement in an ordinary table row is still caught" \
  bash -c '[ "$0" -ge 1 ]' "$SEEN_TABLE"

# THE CONTROL FOR PER-CLAIM DEFERENCE. Without it this mechanism has no test
# weight: reverting to a file-level `grep && continue` leaves the suite green,
# because the violation it used to hide was fixed in the same commit. That is
# the shape this whole round keeps producing — a guard whose subject was
# removed, so nothing proves the guard works.
#
# The planted file DEFERS in one place and RESTATES in another, far apart. A
# file-level exemption clears it; a per-claim one must not. This is exactly what
# happened to docs/workflows.md: line 407 gained a pointer, and line 570 kept
# saying the opposite, hidden by the amnesty.
{
  printf 'Plan tier routing: see the dispatch table in skills/idd-all/SKILL.md.\n'
  for i in $(seq 1 40); do printf 'filler line %s\n' "$i"; done
  printf 'Under unattended mode a Plan tier issue still reaches EnterPlanMode via Phase 3a.\n'
} > "$PC_DIR/defers-then-restates.md"
SEEN_FAR=$(restating_files "$PC_DIR" | grep -c 'defers-then-restates.md' || true)
require "positive control: a deference elsewhere in the file does NOT amnesty a distant restatement" \
  bash -c '[ "$0" -ge 1 ]' "$SEEN_FAR"

# ── the exempted source must not contradict ITSELF ──
#
# `$NORMATIVE` is skipped above, and rightly: the source is entitled to state
# its own routing. But "skip the file" and "the file is correct" are different
# claims, and the detector was making the second one on the strength of the
# first. Inside that file, L578 says the attended Plan gate is
# `idd-implement`'s native behaviour, while L547 of the SAME file records that
# the gate is NOT in idd-implement -- it lives in `/idd-plan` -- and the
# dispatch table routes attended Plan to Phase 3p. That is the #292/#317 claim
# verbatim, surviving inside the one file nothing was allowed to look at.
#
# So the source gets its own, narrower rule: it may say anything about routing,
# except attribute EnterPlanMode to idd-implement. That is not a style
# preference -- the file itself documents why the attribution is false.
NORMATIVE_FILE="$PLUGIN/skills/idd-all/SKILL.md"
require "the normative source exists where the exemption expects it" \
  test -f "$NORMATIVE_FILE"
# The pattern is the ATTRIBUTION, not co-occurrence. Several lines legitimately
# name both tokens while saying the correct thing ("Plan -> /idd-plan, which owns
# the gate and then chains to idd-implement"); a co-occurrence test flags all of
# them, and a rule that cries wolf on the correct lines gets deleted.
#
# Scope, stated rather than implied: this pins ONE false attribution -- the one
# that actually survived three rounds inside the exempted file. It is not a
# proof that the file is internally consistent, and no grep over prose could be.
# Written down so the next reader does not mistake a green run for that.
SELF_CONTRA=$(awk '
  { l = tolower($0) }
  # the refuted claim being QUOTED in a correction note is not the claim
  l ~ /修正紀錄|推翻|原本|過去把|not in .idd-implement|不在 .idd-implement/ { next }
  l ~ /enterplanmode/ && l ~ /idd-implement.{0,40}(native|的[^。]{0,20}閘門|自然 fire)/ {
    print FILENAME ":" NR ": " $0
  }
' "$NORMATIVE_FILE" || true)
require "the normative source never attributes EnterPlanMode to idd-implement" \
  bash -c '[ -z "$0" ] || { printf "%s\n" "$0"; exit 1; }' "$SELF_CONTRA"

# ── the scan SCOPE has to have weight ──
#
# `ROOT` is the repo root so that `docs/` and `openspec/` are covered -- and
# reverting it to `$PLUGIN` (which drops both) turned NOTHING red, because every
# planted control lived under the plugin. Round 2's surviving violation was in
# `openspec/specs/`; round 12's was in `docs/`. A scope with no control is a
# scope that will be narrowed by the next person who finds it noisy.
for SCOPE_DIR in "$ROOT/docs" "$ROOT/openspec/specs"; do
  if [ ! -d "$SCOPE_DIR" ]; then
    fail "scope control: $SCOPE_DIR exists" "the scan claims to cover it"
    continue
  fi
  SC="$SCOPE_DIR/.plan-routing-scope-canary.$$-${RANDOM}.md"
  printf '%s\n' \
    '# canary' \
    '- **Mode**: Unattended' \
    '- Plan tier routes through EnterPlanMode' > "$SC"
  if restating_files "$ROOT" | grep -q 'plan-routing-scope-canary'; then
    pass "scope control: a restatement planted in ${SCOPE_DIR#$ROOT/} is detected"
  else
    fail "scope control: a restatement planted in ${SCOPE_DIR#$ROOT/} is detected" \
         "the scan does not actually reach ${SCOPE_DIR#$ROOT/}"
  fi
  rm -f "$SC"
done

print_summary "plan-routing-consistency"
exit $?
