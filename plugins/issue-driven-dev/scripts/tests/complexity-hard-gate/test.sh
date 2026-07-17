#!/usr/bin/env bash
# test.sh — drift-guard for the #129 MUST-trigger complexity hard gate
# (change reshape-plan-preimpl-tier, spec complexity-hard-gate).
#
# WHY A CONTENT DRIFT-GUARD (not an execution harness): `/idd-diagnose` is a
# prose SKILL.md — an AI prompt, not executable code. "Feed a ≥5-file issue →
# assert Complexity=Plan" cannot be run. The falsifiable equivalent is asserting
# the prompt text (idd-diagnose Step 3.5) AND the canonical rule (Layer P section
# of sdd-integration.md) both encode the hard-gate routing contract. Assertions
# are on canonical tokens, non-line-bound (design acceptance: "不綁定 source line
# number"). Token alignment across BOTH files mirrors the session-start-commit-
# rule suite: the executor (SKILL.md) and the canonical rule must not drift apart.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
DIAGNOSE="$PLUGIN_ROOT/skills/idd-diagnose/SKILL.md"
SDD="$PLUGIN_ROOT/rules/sdd-integration.md"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

assert_file_exists "idd-diagnose SKILL.md exists" "$DIAGNOSE"
assert_file_exists "sdd-integration.md exists" "$SDD"
D="$(cat "$DIAGNOSE" 2>/dev/null || echo "")"
S="$(cat "$SDD" 2>/dev/null || echo "")"

# ── Task 1.1 — hard-gate verdict mapping (design: 硬閘疊加於 Layer P 之上，不反轉 Simple 預設) ──
# Three verdict cases from spec "MUST-trigger complexity hard gate layered above
# Layer P": (a) estimated ≥ 5 files → Plan; (b) shared abstraction (≥ 2 cross-file
# callers) → Plan; (c) escalate-only — the gate does NOT invert the Simple default,
# and a non-firing gate falls through to Layer P with Simple preserved.

# (mechanism exists — MUST-trigger hard gate, in both the executor and the rule)
assert_grep "diagnose: names the 硬閘 (hard gate) mechanism"            "硬閘"          "$D"
assert_grep "diagnose: hard gate is MUST-trigger"                       "MUST-trigger" "$D"
assert_grep "sdd: names the hard gate mechanism"                        "hard gate"    "$S"
assert_grep "sdd: hard gate is MUST-trigger"                            "MUST-trigger" "$S"

# (a) estimated ≥ 5 files OF ONE INTERDEPENDENT CONCEPT → Plan (P3: the trigger is
#     scattered-single-concept, NOT genuinely-independent multi-file, which Layer 1
#     keeps Simple — resolves the HIGH-7 contradiction with Layer 1).
assert_grep "diagnose: ≥ 5 檔 file-count trigger"                       "≥ 5 檔"       "$D"
assert_grep "sdd: ≥ 5 files file-count trigger"                         "≥ 5 files"    "$S"
assert_grep "diagnose: ≥5 trigger qualified to one interdependent concept" "單一概念散佈" "$D"
assert_grep "sdd: ≥5 trigger qualified to one interdependent concept"    "one interdependent concept" "$S"

# (b) shared-abstraction predicate = referenced by ≥ 2 other files
assert_grep "diagnose: shared-abstraction predicate (≥ 2 個其他檔案)"    "≥ 2 個其他檔案" "$D"
assert_grep "sdd: shared-abstraction predicate (≥ 2 other files)"       "≥ 2 other files" "$S"

# (c) escalate-only — does NOT invert the Simple default; non-firing falls through
assert_grep "diagnose: escalate-only, 不反轉 Simple 預設"               "不反轉"       "$D"
assert_grep "diagnose: non-firing gate 落回 Layer P"                    "落回 Layer P" "$D"
assert_grep "sdd: escalate-only — does not invert the Simple default"   "does not invert" "$S"
assert_grep "sdd: non-firing gate falls through to Layer P"             "falls through to Layer P" "$S"

# N = 5 is the one tunable knob (design Open Question; ratified default)
assert_grep "diagnose: N = 5 knob documented"                          "N = 5"        "$D"
assert_grep "sdd: N = 5 knob documented"                               "N = 5"        "$S"

# Simple-default preserved: the isolated single-file anchor must survive the gate
# insertion (spec scenario "Small isolated change preserves the Simple default").
assert_grep "diagnose: 單檔案 → Simple anchor intact"                   "單檔案"       "$D"
assert_grep "sdd: single-file → Simple anchor intact"                  "Single-file change" "$S"

# ── Task 1.3 — hard-gate estimate disclosed in the audit trail ──
# diagnose emits a single audit line `Hard-gate: <triggered|not triggered> — <reason
# with anchors>` into the Diagnosis comment (alongside Layer V's audit trail). When
# signal is insufficient the gate does NOT fire (fail-open to Layer P) and the line
# reads `insufficient signal`. Three scenarios each assert their audit-line string.
assert_grep "diagnose: audit-line format template"      "Hard-gate: <triggered|not triggered>" "$D"
assert_grep "diagnose: triggered audit line literal"    "Hard-gate: triggered"      "$D"
assert_grep "diagnose: not-triggered audit line literal" "Hard-gate: not triggered" "$D"
assert_grep "diagnose: insufficient-signal fail-open"   "insufficient signal"       "$D"

# ── Task 1.4 — shared-abstraction trigger forces family-wide Plan scope ──
# When the gate fires on a shared abstraction, the resulting Plan must enumerate
# ALL known call sites / family members as in-scope, not just the file named in
# the issue title (spec: "Plan enumerates family members"; #44 lesson). The Plan
# body carries a named `Family-wide scope` section; diagnose cross-references it.
PLAN="$PLUGIN_ROOT/skills/idd-plan/SKILL.md"
assert_file_exists "idd-plan SKILL.md exists" "$PLAN"
PN="$(cat "$PLAN" 2>/dev/null || echo "")"
assert_grep "plan: Family-wide scope section in Plan body"     "Family-wide scope"   "$PN"
assert_grep "plan: enumerates all known call sites"            "所有已知 call site"  "$PN"
assert_grep "plan: family members are in-scope"                "family member"       "$PN"
assert_grep "diagnose: shared-abstraction → family-wide Plan"  "Family-wide scope"   "$D"

# ── Task 3.1 — unified Step 3.5 routing order (resolves #129 × #57 coupling) ──
# Canonical MEETING-FIRST routing, faithful 7-step (P2 decision; HIGH-2 + round-3
# HIGH fix — no lossy "5-stage" that drops Spectra): (1) type=meeting → (2) Layer 1
# → (3) Layer V → (4) Spectra (Layer 2+3) → (5) #129 hard gate → (6) Layer P →
# (7) Simple default. meeting is checked FIRST (deterministic type field) so
# Layer 1's narrative disqualifier can't swallow a meeting's deliberation content.
# Round-2 HIGH-5 fix: the summary must FAITHFULLY enumerate every gate (no lossy
# "5-stage" label that silently drops Spectra/Layer 2+3). Summary now == the
# operational 7-step list, so a reader can't be left guessing which stage absorbs
# Spectra.
SEQ="(1) type=meeting → (2) Layer 1 → (3) Layer V → (4) Spectra（Layer 2+3）→ (5) #129 硬閘 → (6) Layer P → (7) Simple 預設"
assert_grep "diagnose: canonical routing sequence (meeting-first, faithful 7-step)"  "$SEQ"     "$D"
assert_grep "diagnose: meeting is an explicit early step in the order" "→ 走 meeting Strategy" "$D"
# Round-2 HIGH (codex): meeting-first is only real if Step 3.4 (Layer V) — which runs
# BEFORE Step 3.5 — short-circuits for type=meeting. Assert that short-circuit exists.
assert_grep "diagnose: Step 3.4 short-circuits Layer V for type=meeting" "跳過整個 Layer V" "$D"

# ── P1/P2 systemic drift-guard (HIGH-1/HIGH-4/HIGH-6): the canonical rule file
# (sdd-integration.md) must not drift from the executor. The prior string-only
# guards were green while sdd-integration was internally stale — these assert the
# structural facts the DA proved were missing. ──
# sdd-integration must actually carry the meeting branch (it was entirely absent).
assert_grep "sdd: ordered list carries the type=meeting branch"          "type=meeting"  "$S"
# sdd stale '5-layer replaces 4-layer' prose must be gone (list is now 7 steps).
refute_grep "sdd: no stale '5-layer evaluation replaces' prose"          "5-layer evaluation replaces" "$S"
# sdd truth table must have a Hard-gate column (was missing → wrong Simple verdict).
assert_grep "sdd: truth table has a Hard gate column"                    "Hard gate hit" "$S"
# Round-4 HIGH: the sdd ordered-list meeting bypass must name Spectra (Layer 2+3).
assert_grep "sdd: meeting bypass names Spectra (Layer 2+3)" "NOT scored by Layer 1 / Layer V / Spectra (Layer 2+3)" "$S"
# Round-4 HIGH: sdd '## Rules' item 7 must be meeting-first, not the stale
# 'Disqualifiers are evaluated first' (which contradicts the file's own order).
assert_grep "sdd: Rules item 7 is meeting-first" "is evaluated first, then Layer 1 disqualifiers" "$S"
refute_grep "sdd: Rules item 7 dropped stale 'Disqualifiers are evaluated first'" "**Disqualifiers are evaluated first**" "$S"

# ── Round-2 systemic guard (HIGH-6/9/12): lock the NORMATIVE change artifacts, not
# just the executor prose. Round 1 fixed the SKILL/rule prose but left tasks.md +
# specs/*/spec.md encoding the DISPROVEN pre-fix rules (order + unqualified ≥5-file),
# and those spec.md files become canonical on archive. These artifacts live in the
# dev repo's openspec change dir (NOT distributed with the plugin), so assert only
# when present; skip gracefully for downstream consumers / post-archive. ──
CHANGE_DIR="$PLUGIN_ROOT/../../openspec/changes/reshape-plan-preimpl-tier"
if [ -d "$CHANGE_DIR" ]; then
  HGS="$(cat "$CHANGE_DIR/specs/complexity-hard-gate/spec.md" 2>/dev/null || echo "")"
  TKS="$(cat "$CHANGE_DIR/tasks.md" 2>/dev/null || echo "")"
  DGN="$(cat "$CHANGE_DIR/design.md" 2>/dev/null || echo "")"
  # spec Requirement must carry the interdependent-concept qualifier (P3), and the
  # worked Example must document that independent multi-file stays Simple via Layer 1.
  assert_grep "spec: hard-gate qualified to one interdependent concept" "one interdependent concept" "$HGS"
  assert_grep "spec: Example documents independent-files → Simple (Layer 1)" "Simple (Layer 1 disqualifier)" "$HGS"
  # tasks.md Task 3.1 order must be meeting-FIRST (the round-2 CRITICAL miss); the
  # stale Layer-1-first order must be gone.
  assert_grep "tasks.md: Task 3.1 routing order is meeting-first" "(1) \`type=meeting\` 分支" "$TKS"
  refute_grep "tasks.md: Task 3.1 has no stale Layer-1-first order" "(1) Layer 1 disqualifier" "$TKS"
  # Round-3 HIGH: design.md Decisions section (the guard previously never read
  # design.md) must carry the faithful 7-step seq with Spectra at step 4, not the
  # disproven 5-step that dropped Spectra.
  assert_grep "design.md: Decisions routing seq includes Spectra at step 4" "(4) Spectra（Layer 2+3" "$DGN"
  refute_grep "design.md: no stale 5-step tail (Layer P as step 5)" "(5) Layer P any-match + Simple 預設" "$DGN"
else
  pass "change artifacts absent (downstream/post-archive) — spec/tasks guards skipped"
fi

# ── #252 sdd_bias switch: hard-gate exit is config-sensitive ─────────────────
# Opt-in `sdd_bias: high` escalates a hard-gate hit to Spectra (spec records)
# instead of Plan; default/absent/invalid = Plan, byte-identical to pre-#252.
SDDI="$PLUGIN_ROOT/rules/sdd-integration.md"
PROTO="$PLUGIN_ROOT/references/config-protocol.md"
assert_output_grep "sdd-integration: sdd_bias switch documented"       "sdd_bias"                          "$SDDI"
assert_output_grep "sdd-integration: high-bias Spectra exit verbatim"  "Spectra via hard-gate (sdd_bias)"  "$SDDI"
assert_output_grep "sdd-integration: anti-pattern scoped to default"   "sdd_bias: default"                 "$SDDI"
assert_output_grep "diagnose: Step 3.5 mirrors the switch"             "Spectra via hard-gate (sdd_bias)"  "$DIAGNOSE"
assert_output_grep "diagnose: invalid value degrades to default"       "視同 \`default\`"                   "$DIAGNOSE"
assert_output_grep "config-protocol: sdd_bias field documented"        "### \`sdd_bias\` field"            "$PROTO"
assert_output_grep "config-protocol: trade-off note (chain weight)"    "流程重量"                            "$PROTO"

print_summary "complexity-hard-gate"
