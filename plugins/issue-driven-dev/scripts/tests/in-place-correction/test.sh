#!/usr/bin/env bash
# test.sh — /idd-edit --correct: parsing, protected regions, marker shape and
# placement, and the doc contracts of the skills that route to it (#351).
#
# Change: openspec/changes/idd-edit-in-place-correction
#   specs/in-place-correction/spec.md, specs/append-vs-modify-discipline/spec.md
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"

PLUGIN="$(cd "$HERE/../../.." && pwd)"
HELPER="$PLUGIN/scripts/idd-edit-helper.py"
RULE="$PLUGIN/rules/append-vs-modify.md"
SKILLS="$PLUGIN/skills"

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# run_helper <label> <args...> — stdout/stderr land in $WORK/<label>.{out,err},
# exit code in RC. Output is asserted from files, never re-expanded (#188).
run_helper() {
  local label="$1"; shift
  python3 "$HELPER" "$@" >"$WORK/$label.out" 2>"$WORK/$label.err"
  RC=$?
}

# ── A. parse-args ──────────────────────────────────────────────────────────
echo "A. parse-args --correct"

run_helper a1 parse-args comment:1 --correct --scope whole-comment --body x --reason r
assert_exit "comment target + whole-comment scope is accepted" 0 "$RC"
assert_output_grep "MODE carries the --correct flag" "MODE=--correct" "$WORK/a1.out"

run_helper a2 parse-args issue:351 --correct --section "## Expected" --body x --reason r
assert_exit "issue target + --section is accepted" 0 "$RC"
assert_output_grep "issue:<N> target is passed through" "issue:351" "$WORK/a2.out"

run_helper a3 parse-args issue:351 --correct --scope whole-comment --body x --reason r
assert_exit "issue target + whole scope is refused with exit 3" 3 "$RC"
assert_output_grep "refusal names --section" "--section" "$WORK/a3.err"

run_helper a4 parse-args comment:1 --correct --body x --reason r
assert_exit "--correct without scope or section is refused with exit 3" 3 "$RC"

run_helper a5 parse-args comment:1 --correct --scope whole-comment --body x --reason r --override-user-content
assert_exit "--correct + --override-user-content is refused with exit 2" 2 "$RC"
assert_output_grep "refusal says --correct cannot override" "cannot override" "$WORK/a5.err"

run_helper a6 parse-args issue:351 --replace --section "## Expected" --body x --reason r
assert_exit "issue target with a mode other than --correct is refused with exit 2" 2 "$RC"
assert_output_grep "refusal points to #347" "#347" "$WORK/a6.err"

run_helper a7 parse-args issue:abc --correct --section "## Expected" --body x --reason r
assert_exit "non-numeric issue target is refused with exit 2" 2 "$RC"
assert_output_grep "refusal says the issue number must be numeric" "numeric" "$WORK/a7.err"

# ── B. check-correction ────────────────────────────────────────────────────
echo "B. check-correction"

cat >"$WORK/body.md" <<'EOF'
## Problem

> **Original text**:
> 「the quoted source」
> — Source: a conversation

Interpretation A.

## Expected
- old expectation

## Related
- #347

### Clarity Surface(idd-clarify run 2026-09-24T00:00:00Z)

| Type | Source | Question for you | Status |
|---|---|---|---|

---

## Current Status

**Phase**: diagnosed

### Key Decisions
- a decision
EOF

QUOTE='> **Original text**:
> 「the quoted source」
> — Source: a conversation'

# Spec example table, row by row.
printf '\n%s\n\nInterpretation B.\n\n' "$QUOTE" >"$WORK/r1.md"
run_helper b1 check-correction "$WORK/body.md" "## Problem" "$WORK/r1.md"
assert_exit "row 1: same blockquote + new paragraph → accepted" 0 "$RC"

printf '\n%s\n\nInterpretation A.\n\n' "$(printf '%s' "$QUOTE" | sed 's/quoted/Quoted/')" >"$WORK/r2.md"
run_helper b2 check-correction "$WORK/body.md" "## Problem" "$WORK/r2.md"
assert_exit "row 2: blockquote with one character changed → exit 6" 6 "$RC"

printf '\nInterpretation B.\n\n' >"$WORK/r3.md"
run_helper b3 check-correction "$WORK/body.md" "## Problem" "$WORK/r3.md"
assert_exit "row 3: paragraph only, blockquote dropped → exit 6" 6 "$RC"
assert_output_grep "row 3: message says the verbatim block must be preserved" "Original text" "$WORK/b3.err"

cat >"$WORK/body-noquote.md" <<'EOF'
## Problem

> a side note that is not a source quotation

Interpretation A.

## Expected
- x
EOF
run_helper b4 check-correction "$WORK/body-noquote.md" "## Problem" "$WORK/r3.md"
assert_exit "row 4: blockquote without 'Original text' may be dropped → accepted" 0 "$RC"

printf -- '- new expectation\n\n' >"$WORK/r-exp.md"
run_helper b5 check-correction "$WORK/body.md" "## Expected" "$WORK/r-exp.md"
assert_exit "ordinary section is accepted" 0 "$RC"

run_helper b6 check-correction "$WORK/body.md" "## Current Status" "$WORK/r-exp.md"
assert_exit "## Current Status is refused with exit 6" 6 "$RC"
assert_output_grep "Current Status refusal names idd-update" "idd-update" "$WORK/b6.err"

run_helper b7 check-correction "$WORK/body.md" "### Key Decisions" "$WORK/r-exp.md"
assert_exit "heading nested inside Current Status is refused with exit 6" 6 "$RC"
assert_output_grep "nested refusal names idd-update" "idd-update" "$WORK/b7.err"

run_helper b8 check-correction "$WORK/body.md" "## Related" "$WORK/r-exp.md"
assert_exit "section that contains ### Clarity Surface is refused with exit 6" 6 "$RC"
assert_output_grep "containment refusal names idd-clarify" "idd-clarify" "$WORK/b8.err"

run_helper b9 check-correction "$WORK/body.md" "### Clarity Surface(idd-clarify run 2026-09-24T00:00:00Z)" "$WORK/r-exp.md"
assert_exit "### Clarity Surface section is refused with exit 6" 6 "$RC"
assert_output_grep "Clarity Surface refusal names idd-clarify" "idd-clarify" "$WORK/b9.err"

run_helper b10 check-correction "$WORK/body.md" "## Nowhere" "$WORK/r-exp.md"
assert_exit "missing section → exit 1 (same as section-replace)" 1 "$RC"

printf '%s\n\nold comment text\n' "$QUOTE" >"$WORK/comment.md"
printf 'new comment text\n' >"$WORK/comment-new-bad.md"
printf '%s\n\nnew comment text\n' "$QUOTE" >"$WORK/comment-new-ok.md"
run_helper b11 check-correction "$WORK/comment.md" - "$WORK/comment-new-bad.md"
assert_exit "whole comment that drops its Original text block → exit 6" 6 "$RC"
run_helper b12 check-correction "$WORK/comment.md" - "$WORK/comment-new-ok.md"
assert_exit "whole comment that keeps its Original text block → accepted" 0 "$RC"

run_helper b13 check-correction "$WORK/missing.md" - "$WORK/comment-new-ok.md"
assert_exit "unreadable old file → exit 5" 5 "$RC"

# ── C. marker ──────────────────────────────────────────────────────────────
echo "C. correction marker"

run_helper c1 emit-audit-marker edit mode=correct backup-id=comment-5805214375-20261009T100000Z
assert_exit "marker with a valid backup-id is emitted" 0 "$RC"
MARKER="$(cat "$WORK/c1.out")"
assert_grep_re "marker has the documented shape" \
  '^<!-- idd:edit mode="correct" backup-id="(comment|issue)-[0-9]+(-body)?-[0-9]{8}T[0-9]{6}Z(-[0-9]+)?" date="[0-9]{4}-[0-9]{2}-[0-9]{2}" -->$' "$MARKER"
refute_grep "marker contains no '/'" "/" "$MARKER"

run_helper c2 emit-audit-marker edit mode=correct backup-id=../../etc/passwd
assert_exit "backup-id that is not an id is refused with exit 2" 2 "$RC"

run_helper c3 emit-audit-marker edit mode=correct backup-id=issue-351-body-20261009T100000Z-2
assert_exit "issue-body backup-id with a collision suffix is accepted" 0 "$RC"

# Placement: the marker is appended to the replacement, so it ends the section.
printf -- '- new expectation\n\n%s\n\n' "$MARKER" >"$WORK/r-marked.md"
run_helper c4 section-replace "$WORK/body.md" "## Expected" "$WORK/r-marked.md"
assert_exit "section-replace with the marked replacement succeeds" 0 "$RC"
BEFORE_NEXT="$(awk '/^## Related$/{print last; exit} NF{last=$0}' "$WORK/c4.out")"
assert_eq "marker is the last non-empty line before the next heading" "$MARKER" "$BEFORE_NEXT"
STATUS_ZONE="$(awk '/^## Current Status$/{f=1} f' "$WORK/c4.out")"
refute_grep "marker is not inside ## Current Status" "idd:edit" "$STATUS_ZONE"

# ── D. doc contracts ───────────────────────────────────────────────────────
echo "D. rule and skill contracts"

CATS="$(grep -cE '^### [0-9]+\. `' "$RULE")"
assert_eq "rule file lists exactly 8 categories" "8" "$CATS"
assert_output_grep "rule file has category 8 in-place-correction" '### 8. `in-place-correction`' "$RULE"
refute_output_grep "rule file no longer says 7-category" "7-category" "$RULE"
INPLACE="$(awk '/^### 8\. `in-place-correction`/{f=1;next} f&&/^##/{exit} f' "$RULE")"
EX_COUNT="$(printf '%s\n' "$INPLACE" | awk '/^\*\*Examples\*\*/{f=1;next} f&&/^- /{n++} END{print n+0}')"
require "in-place-correction lists at least 2 examples" test "$EX_COUNT" -ge 2
VERBATIM="$(awk '/^### 5\. `verbatim-preserve`/{f=1;next} f&&/^### /{exit} f' "$RULE")"
assert_grep "verbatim-preserve names Original text quotations" "Original text" "$VERBATIM"
refute_grep "verbatim-preserve no longer claims the whole body above ---" "Issue body above the \`---\` separator" "$VERBATIM"

assert_output_grep "idd-edit declares the category" "(category: in-place-correction)" "$SKILLS/idd-edit/SKILL.md"
assert_output_grep "idd-edit lists the check_correction task" "check_correction" "$SKILLS/idd-edit/SKILL.md"
assert_output_grep "idd-edit lists the archive_before_patch task" "archive_before_patch" "$SKILLS/idd-edit/SKILL.md"

ERRATA="$(awk '/^#### Template: `errata`/{f=1} f&&/^#### Template: /&&!/errata/{exit} f' "$SKILLS/idd-comment/SKILL.md")"
assert_grep "errata routes OWNER/bot targets to idd-edit --correct" "--correct" "$ERRATA"
assert_grep "errata routing names the OWNER check" "OWNER" "$ERRATA"
refute_output_grep "errata no longer auto-prepends a warning" 'prepend-note --reason="See errata' "$SKILLS/idd-comment/SKILL.md"

for s in idd-verify idd-diagnose idd-reorganize; do
  F="$SKILLS/$s/SKILL.md"
  assert_output_grep "$s has a Proposed Corrections block" "### Proposed Corrections" "$F"
  assert_output_grep "$s proposes /idd-edit --correct" "--correct" "$F"
  assert_output_grep "$s lists only, under unattended (只列不做)" "只列不做" "$F"
  refute_output_grep "$s never calls the archive subcommand" "idd-edit-helper.py\" archive" "$F"
done

print_summary "in-place-correction"
