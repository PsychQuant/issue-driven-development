#!/usr/bin/env bash
# test.sh — SKILL.md↔helper integration contract layer for /idd-edit (#163).
#
# THE GAP THIS CLOSES: /idd-edit's 23 fixtures all invoke the helper directly,
# bypassing the SKILL.md orchestration layer — so "SKILL references a variable
# the helper never emits" bugs (R1 B1 $APPEND_BODY, R1 B2 $GITHUB_REPO) shipped
# with green tests. Shape (c) per the #163 ruling: a STATIC contract check —
# every uppercase $VAR consumed in a SKILL fenced-bash block must have a
# provenance (assigned in some SKILL block, emitted by the helper, or on the
# documented env allowlist). The helper source is the single source of truth
# for the emit surface (no third variable list to drift).
#
# Scan boundary (documented in the SKILL's Contract section): fenced ```bash
# blocks only, heredocs included (B1 lived in one); single-quote non-expansion
# false positives are absorbed by the allowlist. The structural bug class
# (R2 H7 loop closure) is NOT this layer — fixture 14 prose contracts cover it.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$HERE/../../.."
HELPER="$PLUGIN_ROOT/scripts/idd-edit-helper.py"
SKILL="$PLUGIN_ROOT/skills/idd-edit/SKILL.md"

HELPERS="$HERE/../../lib/assert-helpers.sh"
[ -f "$HELPERS" ] || { echo "✗ missing $HELPERS — cannot run suite" >&2; exit 1; }
. "$HELPERS"

assert_file_exists "idd-edit-helper.py exists" "$HELPER"
assert_file_exists "idd-edit SKILL.md exists" "$SKILL"

CHECKER="$HERE/.contract-checker.py"
cat > "$CHECKER" <<'PYEOF'
import re, sys

def emitted_names(helper_src):
    names = set(re.findall(r'emit_assignment\(\s*"([A-Z_]+)"', helper_src))
    if re.search(r'print\(f?"TARGETS=\(', helper_src):
        names.add("TARGETS")
    return names

FENCE_RE = re.compile(r'```bash\n(.*?)```', re.DOTALL)
# provenance-granting forms inside SKILL blocks
ASSIGN_RE = re.compile(r'^\s*(?:local\s+|export\s+)?([A-Z_][A-Z0-9_]*)\+?=', re.MULTILINE)
FOR_RE    = re.compile(r'\bfor\s+([A-Z_][A-Z0-9_]*)\s+in\b')
READ_RE   = re.compile(r'\bread\s+(?:-r\s+)?([A-Z_][A-Z0-9_]*)\b')
USE_RE    = re.compile(r'\$\{?([A-Z_][A-Z0-9_]*)\b')

# environment / harness-provided (NOT helper contract — a name here is
# deliberately exempt; GITHUB_REPO must never be added, that was bug B2)
# IDD_CALLER: cross-skill invocation env contract (#161), consumed with a
# ${VAR:-} safe default — provided by the calling skill's environment.
ALLOWLIST = {"CLAUDE_PLUGIN_ROOT", "HOME", "PWD", "PATH", "ARGUMENTS", "EOF", "IDD_CALLER"}

def violations(skill_md, helper_src):
    blocks = FENCE_RE.findall(skill_md)
    defined, consumed = set(), set()
    for b in blocks:
        defined |= set(ASSIGN_RE.findall(b))
        defined |= set(FOR_RE.findall(b))
        defined |= set(READ_RE.findall(b))
        consumed |= set(USE_RE.findall(b))
    return sorted(consumed - defined - emitted_names(helper_src) - ALLOWLIST)

if __name__ == "__main__":
    mode = sys.argv[1]
    if mode == "check":
        skill = open(sys.argv[2]).read()
        helper = open(sys.argv[3]).read()
        v = violations(skill, helper)
        if v:
            print("VIOLATIONS: " + " ".join(v))
            sys.exit(1)
        print("OK")
    elif mode == "selftest":
        # seeded violation: SKILL block consumes $UNDEFINED_VAR (and the two
        # historical bug names) with a helper that emits only BODY_INPUT/REPO.
        bad_skill = "```bash\necho \"$UNDEFINED_VAR\"\ncat <<X\n$APPEND_BODY in heredoc\nX\ngh api -R \"$GITHUB_REPO\" x\nLOCAL_OK=1\necho \"$LOCAL_OK $BODY_INPUT $REPO\"\n```\n"
        fake_helper = 'emit_assignment("BODY_INPUT", x)\nemit_assignment("REPO", x)\n'
        v = violations(bad_skill, fake_helper)
        expect = {"UNDEFINED_VAR", "APPEND_BODY", "GITHUB_REPO"}
        if set(v) == expect:
            print("SELFTEST-OK")
        else:
            print(f"SELFTEST-FAIL: got {v}, expected {sorted(expect)}")
            sys.exit(1)
PYEOF

# ── 1) checker efficacy self-test (the RED-equivalent: detection power is non-empty) ──
OUT=$(python3 "$CHECKER" selftest 2>&1)
if [ "$OUT" = "SELFTEST-OK" ]; then
  pass "checker self-test: seeded B1/B2-class violations are detected"
else
  fail "checker self-test: seeded B1/B2-class violations are detected" "$OUT"
fi

# ── 2) the real contract: every SKILL-consumed var has a provenance ──
OUT=$(python3 "$CHECKER" check "$SKILL" "$HELPER" 2>&1); RC=$?
if [ "$RC" -eq 0 ]; then
  pass "SKILL↔helper contract: no unsourced variable references"
else
  fail "SKILL↔helper contract: no unsourced variable references" "$OUT"
fi

# ── 3) emit-surface freeze: deleting an emit breaks SKILL consumers → red here first ──
for NAME in MODE SCOPE_FLAG SECTION_FLAG REASON BODY_INPUT BODY_FILE REPO CWD LAST OVERRIDE_USER_CONTENT; do
  assert_output_grep "helper emits $NAME" "emit_assignment(\"$NAME\"" "$HELPER"
done
assert_output_grep "helper emits TARGETS array" 'TARGETS=(' "$HELPER"

# ── 4) SKILL documents the contract mechanism ──
assert_output_grep "SKILL has the Contract section"        "## SKILL↔helper Contract" "$SKILL"
assert_output_grep "SKILL documents the scan boundary"     "fenced bash"              "$SKILL"

rm -f "$CHECKER"
print_summary "idd-edit-contract"
