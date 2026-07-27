#!/usr/bin/env bash
# test.sh — drift-guard for the skill frontmatter description contract (#276).
#
# ROOT CAUSE THIS GUARDS: a skill's frontmatter `description` is the ONLY surface
# an AI reads when deciding which skill to invoke. Everything else — SKILL.md body,
# docs/workflows.md path catalog, README — is either loaded too late (after the
# skill was already chosen) or never auto-loaded at all. In #276 an AI advised a
# user to skip `/idd-diagnose` and run `/idd-plan` directly; that inference was
# CORRECT on the information visible to it, because idd-plan's description named
# no precondition. The routing error was structural, not incidental.
#
# Contract, per skill under plugins/issue-driven-dev/skills/:
#   A1  frontmatter exists and carries a non-empty `description`
#   A2  the description states WHEN to reach for the skill      (`Use when`)
#   A3  the description states WHAT FAILURE it prevents         (`防止的失敗`)
#   A4  skills in DIAGNOSIS_DEPENDENT name the diagnosis precondition (`diagnos`)
#
# The guard asserts PRESENCE of these signals at a predictable position, NOT their
# quality — someone can still satisfy A2 with "Use when: 需要時". Prose quality stays
# human judgment at review. Same self-declared stance as scripts/tests/docs-catalog-sync
# ("asserts MENTION, not quality"): a mechanical guard buys consistency of surface,
# never depth of content.
#
# WHY A4 IS AN EXPLICIT ALLOWLIST AND NOT DERIVED: the obvious derivation —
# "any skill whose body tells the user to run /idd-diagnose first" — was tried and
# rejected. `grep -l '先跑 `/idd-diagnose'` also matches skills/idd-close/SKILL.md,
# where the string sits in a meeting-deliverable fallback ("neither deliverable
# present → send them back to diagnose"), NOT as idd-close's own precondition
# (close is gated on verify). A derived rule would force idd-close to advertise a
# precondition it does not have. The IDD lifecycle graph is small and stable, so
# an explicit list costs less to maintain than a misfiring inference costs to debug.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
SKILLS_DIR="$PLUGIN_ROOT/skills"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

# Skills whose description MUST name the diagnosis precondition. See header for
# why this is enumerated rather than inferred.
DIAGNOSIS_DEPENDENT=(idd-plan idd-implement)

# Emit the `description` field's full value (block scalar or single line):
# everything from the `description:` line until the next top-level frontmatter key.
extract_description() { # file
  awk '
    /^---[[:space:]]*$/ { fence++; if (fence >= 2) exit; next }
    fence != 1          { next }
    /^description:/     { indesc = 1; print; next }
    indesc && /^[A-Za-z_][A-Za-z0-9_-]*:/ { indesc = 0 }
    indesc              { print }
  ' "$1"
}

in_allowlist() { # name
  local n="$1" s
  for s in "${DIAGNOSIS_DEPENDENT[@]}"; do [ "$s" = "$n" ] && return 0; done
  return 1
}

assert_file_exists "skills/ directory exists" "$SKILLS_DIR"

for d in "$SKILLS_DIR"/*/; do
  n=$(basename "$d")
  f="$d/SKILL.md"

  if [ ! -f "$f" ]; then
    fail "A1 $n: SKILL.md exists" "no SKILL.md under skills/$n/"
    continue
  fi

  desc=$(extract_description "$f")

  # A1 — the field itself.
  if printf '%s\n' "$desc" | grep -qE '^description:[[:space:]]*\S'; then
    pass "A1 $n: frontmatter has a description"
  else
    fail "A1 $n: frontmatter has a description" \
         "skills/$n/SKILL.md has no non-empty 'description:' in its YAML frontmatter"
  fi

  # A2 — when to reach for it.
  assert_grep "A2 $n: description says 'Use when'" "Use when" "$desc"

  # A3 — what failure it prevents.
  assert_grep "A3 $n: description says '防止的失敗'" "防止的失敗" "$desc"

  # A4 — diagnosis precondition, allowlisted skills only.
  if in_allowlist "$n"; then
    assert_grep_re "A4 $n: description names the diagnosis precondition" "diagnos" "$desc"
  fi
done

# Placebo guard on the allowlist itself: a renamed or deleted skill must not let
# A4 silently stop asserting anything (the #119 placebo-gate failure class).
for s in "${DIAGNOSIS_DEPENDENT[@]}"; do
  assert_file_exists "A4 allowlist entry resolves to a real skill: $s" "$SKILLS_DIR/$s/SKILL.md"
done

print_summary "skill-description-contract"
