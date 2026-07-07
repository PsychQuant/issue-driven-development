#!/usr/bin/env bash
# test.sh — drift-guard for the #57 first-class `meeting` issue type
# (change reshape-plan-preimpl-tier, spec meeting-issue-type).
#
# WHY A CONTENT DRIFT-GUARD: the meeting behaviors live in prose SKILL.md files
# (idd-issue taxonomy, idd-diagnose Strategy branch, idd-plan skip-chain, idd-close
# semantics) — AI prompts, not executable code. The falsifiable equivalent is
# asserting each SKILL's prose encodes the meeting contract. Assertions are on
# canonical tokens, non-line-bound.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
ISSUE="$PLUGIN_ROOT/skills/idd-issue/SKILL.md"
DIAGNOSE="$PLUGIN_ROOT/skills/idd-diagnose/SKILL.md"
PLAN="$PLUGIN_ROOT/skills/idd-plan/SKILL.md"
CLOSE="$PLUGIN_ROOT/skills/idd-close/SKILL.md"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

assert_file_exists "idd-issue SKILL.md exists" "$ISSUE"
I="$(cat "$ISSUE" 2>/dev/null || echo "")"

# ── Task 2.1 — meeting is a first-class issue type ──
# The taxonomy value set expands from {bug, feature, refactor, docs} to include
# `meeting`. idd-issue accepts meeting without falling back to feature / rejecting.
assert_grep "idd-issue: taxonomy lists meeting as a peer type" "bug / feature / refactor / docs / meeting" "$I"

# ── Task 2.2 — diagnose emits a deliberation Strategy for meeting issues ──
# type=meeting → Phase A/B/C deliberation template (agenda / decision points /
# action items), NOT the code-centric Files & Changes Strategy. The meeting branch
# is evaluated BEFORE complexity scoring (so no hard-gate / Layer P verdict).
assert_file_exists "idd-diagnose SKILL.md exists" "$DIAGNOSE"
D="$(cat "$DIAGNOSE" 2>/dev/null || echo "")"
assert_grep "diagnose: has a type=meeting branch"                 "type=meeting" "$D"
assert_grep "diagnose: meeting Strategy Phase A (議程/agenda)"     "Phase A（議程）"   "$D"
assert_grep "diagnose: meeting Strategy Phase B (決策點/decisions)" "Phase B（決策點）" "$D"
assert_grep "diagnose: meeting Strategy Phase C (行動項/actions)"   "Phase C（行動項）" "$D"
assert_grep "diagnose: meeting Strategy replaces code-centric Files & Changes" "而非 code-centric 的 Files & Changes" "$D"
assert_grep "diagnose: meeting branch splits before complexity scoring" "複雜度評估前分流" "$D"
# HIGH-5: Step 1 type RECOGNITION must list meeting (else meeting never reaches the branch).
assert_grep "diagnose: Step 1 type recognition includes meeting" "bug / feature / refactor / docs / meeting" "$D"
# MED-req: the verdict Next Step table must route meeting → /idd-plan (meeting-adapted).
assert_grep "diagnose: Next Step table has a meeting → /idd-plan row" "meeting-adapted plan" "$D"

# ── Task 2.3 — plan for meeting issues skips the implement chain ──
# idd-plan for type=meeting uses a meeting-adapted Plan body schema and does NOT
# chain to /idd-implement (meeting is deliberation, not a TDD loop).
assert_file_exists "idd-plan SKILL.md exists" "$PLAN"
PN="$(cat "$PLAN" 2>/dev/null || echo "")"
assert_grep "plan: has a type=meeting branch"               "type=meeting"              "$PN"
assert_grep "plan: meeting-adapted Plan body schema"        "meeting-adapted Plan body" "$PN"
assert_grep "plan: meeting skips chain to /idd-implement"   "不 chain 到 /idd-implement" "$PN"

# ── Task 2.4 — meeting closing maps decisions to actions without a TDD verify pass ──
# Closing a type=meeting issue uses a decision→action mapping as the closing summary
# and does NOT require an /idd-verify TDD pass as a precondition.
assert_file_exists "idd-close SKILL.md exists" "$CLOSE"
C="$(cat "$CLOSE" 2>/dev/null || echo "")"
assert_grep "close: has a type=meeting branch"                    "type=meeting"        "$C"
assert_grep "close: decision→action mapping summary"              "decision→action"     "$C"
assert_grep "close: meeting close needs no /idd-verify TDD pass"  "無 /idd-verify TDD pass" "$C"
# HIGH-3: the OPERATIVE path must branch, not just a declarative paragraph. The
# draft_closing_comment TaskCreate must itself branch on type=meeting (per the
# skill's own 'behavior not in TaskCreate = a bug' rule).
assert_grep "close: draft_closing_comment TaskCreate branches on meeting" "\`type=meeting\` 用 decision→action" "$C"
# Round-2 HIGH (codex): meeting Phase C action items are `- [ ]` boxes with no
# downstream step to check them off (plan skips implement), yet the checklist gate
# blocks close on any `- [ ]`. Deadlock. The close section must resolve each action
# item to a disposition marker so the gate is satisfiable.
assert_grep "close: meeting action items get [x]/[~]/[-] disposition markers (deadlock fix)" "\`- [~] — tracked in #NNN\`" "$C"
# Round-5 HIGH fixes: the meeting gate source resolution is mechanically defined
# (recency + heading-prefix, NOT an unimplemented 'approved' check), with a
# no-deliverable BLOCK (no vacuous pass), and dispositions decided BEFORE the gate.
assert_grep "close: meeting gate blocks when no deliverable exists (no vacuous pass)" "兩者皆無 → 擋 close" "$C"
assert_grep "close: meeting gate decides disposition before blocking check" "先決定 disposition 再跑 blocking check" "$C"
refute_grep "close: meeting source no longer relies on unimplemented 'approved' check" "approved \`## Meeting Plan\` 的 Phase C 行動項為 canonical" "$C"
# Round-4 CRITICAL fix: meeting is NO LONGER bolted onto the generic whitelist /
# authoritative_source machinery (that had no meeting branch → deadlock or silent
# bypass). It now has its OWN self-contained gate. Assert the mechanism, not a string.
assert_grep "close: type=meeting routes to a meeting-specific gate" "meeting-specific gate" "$C"
assert_grep "close: meeting gate is self-contained (no authoritative_source entanglement)" "self-contained" "$C"
refute_grep "close: reverted the round-3 whitelist bolt-on row" "\`Meeting Plan\` → \`Phase C\` | ✅" "$C"
# Round-3 MEDIUM: diagnose_by_type Step-0 TaskCreate must cover meeting (TaskCreate-
# completeness 鐵律 — every emitted step must be in the bootstrap list).
assert_grep "diagnose: diagnose_by_type TaskCreate covers meeting" "meeting→Phase A/B/C" "$D"
# Round-4 HIGH: the meeting BYPASS lists (what meeting skips) must also name Spectra
# — round-3 only fixed the routing *sequences*, missed the *bypass* variant.
assert_grep "diagnose: meeting bypass list (Step 3.5) names Spectra" "不進 Layer 1 / Layer V / Spectra（Layer 2+3）/ 硬閘 / Layer P" "$D"
# Round-5 HIGH: the 'type is a deterministic field' premise needs an actual
# resolution order (label vs body heading), else it's an unbacked claim.
assert_grep "diagnose: Step 1 type resolution order is defined (label > body > infer)" "Type 解析順序" "$D"
# Round-4 HIGH: CLAUDE.md whitelist copy must stay in sync — it now carries the
# meeting exception note (not a diverging whitelist row).
CLAUDE_MD="$PLUGIN_ROOT/CLAUDE.md"
assert_file_exists "plugin CLAUDE.md exists" "$CLAUDE_MD"
CM="$(cat "$CLAUDE_MD" 2>/dev/null || echo "")"
assert_grep "CLAUDE.md: checklist conventions carry the meeting exception" "meeting-specific gate" "$CM"
refute_grep "CLAUDE.md: reverted the diverging Meeting Plan whitelist row" "\`Meeting Plan\` → \`Phase C\` | ✅（#57" "$CM"

# ── Round-2 systemic guard: the meeting spec Requirement must encode the FULL bypass
# (Layer 1 + Layer V), not just hard-gate + Layer P — the round-1 HIGH-2 mechanism
# was never written into the normative spec. Dev-only artifact → assert when present.
CHANGE_DIR="$PLUGIN_ROOT/../../openspec/changes/reshape-plan-preimpl-tier"
if [ -d "$CHANGE_DIR" ]; then
  MTS="$(cat "$CHANGE_DIR/specs/meeting-issue-type/spec.md" 2>/dev/null || echo "")"
  assert_grep "spec: meeting bypass names the Layer 1 disqualifier" "before the Layer 1 disqualifier" "$MTS"
  assert_grep "spec: meeting bypass names Layer V" "Layer V" "$MTS"
  # Round-3 HIGH: the bypass list must also name Spectra (Layer 2+3) — else the spec
  # letter permits a meeting issue to get a Spectra verdict.
  assert_grep "spec: meeting bypass names Spectra (Layer 2+3)" "before the Spectra (Layer 2+3) evaluation" "$MTS"
  # Round-4: spec must encode the meeting-specific close gate (not just the bypass).
  assert_grep "spec: meeting-specific close gate is a Requirement" "meeting-specific" "$MTS"
else
  pass "change artifacts absent (downstream/post-archive) — meeting spec guard skipped"
fi

print_summary "meeting-issue-type"
