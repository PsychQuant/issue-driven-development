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

WORK="$(mktemp -d /tmp/idd-ipc-XXXXXX)"; trap 'rm -rf "$WORK"' EXIT

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
assert_exit "## Related above a nested ### Clarity Surface is correctable (the managed heading ends it)" 0 "$RC"
run_helper b8b section-replace "$WORK/body.md" "## Related" "$WORK/r-exp.md" --stop-at-rule
assert_output_grep "Clarity Surface block survives the correction of ## Related" "### Clarity Surface(idd-clarify run 2026-09-24T00:00:00Z)" "$WORK/b8b.out"
refute_output_grep "old ## Related content is replaced" "- #347" "$WORK/b8b.out"

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

# ── E. round 2 (verify #351 round 1) ──────────────────────────────────────
echo "E. round 2"

# E1. multi-line --body-file survives eval and executes nothing
cat >"$WORK/ml.md" <<'EOF'
## Strategy
- uses `.claude` dir and $(touch PWNED_MARKER)
second line with 'quotes' and "double"
EOF
run_helper e1 parse-args comment:1 --correct --scope whole-comment --body-file "$WORK/ml.md" --reason r
assert_exit "multi-line body-file parses" 0 "$RC"
( cd "$WORK" && eval "$(cat "$WORK/e1.out")" 2>/dev/null; printf '%s' "$BODY_INPUT" >"$WORK/e1.body" )
require "BODY_INPUT after eval equals the file byte for byte" cmp -s "$WORK/ml.md" "$WORK/e1.body"
refute "eval executed nothing from the body" test -e "$WORK/PWNED_MARKER"

# E2. target and flag combinations
run_helper e2a parse-args issue:351 comment:5 --correct --section "## X" --body x --reason r
assert_exit "issue + comment targets → exit 2" 2 "$RC"
run_helper e2b parse-args issue:351 issue:352 --correct --section "## X" --body x --reason r
assert_exit "two issue targets → exit 2" 2 "$RC"
run_helper e2c parse-args comment:1 --correct --scope whole-comment --section "## X" --body x --reason r
assert_exit "--scope and --section together → exit 3" 3 "$RC"

# E3. author gate: own login passes regardless of association; outside issue author refused
export IDD_EDIT_HELPER_TEST_MODE=1 IDD_EDIT_HELPER_GH_USER=kiki830621
printf '{"login":"kiki830621","assoc":"MEMBER"}' >"$WORK/m-member.json"
printf '{"login":"outsider","assoc":"NONE"}' >"$WORK/m-out.json"
IDD_EDIT_HELPER_GH_MOCK="$WORK/m-member.json" run_helper e3a validate-target 5805214375 o/r false
assert_exit "MEMBER comment by the authenticated user passes" 0 "$RC"
export IDD_EDIT_HELPER_GH_MOCK="$WORK/m-out.json"
run_helper e3b validate-target issue:42 o/r false
assert_exit "issue opened by an outside reporter → exit 4" 4 "$RC"
export IDD_EDIT_HELPER_GH_MOCK="$WORK/m-member.json"
run_helper e3c validate-target issue:42 o/r false
assert_exit "issue opened by the authenticated user passes" 0 "$RC"
unset IDD_EDIT_HELPER_GH_MOCK IDD_EDIT_HELPER_GH_USER

# E4. `---` ends a corrected section; replacement may not introduce managed headings
cat >"$WORK/sep.md" <<'EOF'
## Related
- #347

---

### Linked-Context Siblings Filed
- none

---

## Current Status

**Phase**: x
EOF
printf -- '- #348\n' >"$WORK/r-rel.md"
run_helper e4a check-correction "$WORK/sep.md" "## Related" "$WORK/r-rel.md"
assert_exit "## Related with a separator below is accepted" 0 "$RC"
run_helper e4b section-replace "$WORK/sep.md" "## Related" "$WORK/r-rel.md" --stop-at-rule
assert_exit "section-replace --stop-at-rule succeeds" 0 "$RC"
assert_output_grep "audit block below the separator survives" "### Linked-Context Siblings Filed" "$WORK/e4b.out"
assert_eq "both separators survive" "2" "$(grep -c '^---$' "$WORK/e4b.out")"
printf -- '- x\n\n## Current Status\n' >"$WORK/r-mg.md"
run_helper e4c check-correction "$WORK/body.md" "## Expected" "$WORK/r-mg.md"
assert_exit "replacement that introduces ## Current Status → exit 6" 6 "$RC"

# E5. verbatim blocks compared as multisets; **Original** label also protected
printf '\n%s (paraphrased)\n\nInterpretation A.\n' "$QUOTE" >"$WORK/v1.md"
run_helper e5a check-correction "$WORK/body.md" "## Problem" "$WORK/v1.md"
assert_exit "text appended to the quote's last line → exit 6" 6 "$RC"
printf '\n%s\n> 「並且要求自動改」\n\nInterpretation A.\n' "$QUOTE" >"$WORK/v2.md"
run_helper e5b check-correction "$WORK/body.md" "## Problem" "$WORK/v2.md"
assert_exit "quote line appended to the block → exit 6" 6 "$RC"
printf '\nsee: %s\n\nInterpretation A.\n' "$QUOTE" >"$WORK/v3.md"
run_helper e5c check-correction "$WORK/body.md" "## Problem" "$WORK/v3.md"
assert_exit "quote turned into a non-blockquote → exit 6" 6 "$RC"
printf '> **Original** (2026-09-24)：\n> 「先不要做 X」\n\nnote\n' >"$WORK/dec.md"
printf '> **Original** (2026-09-24)：\n> 「直接做 X」\n\nnote\n' >"$WORK/dec-new.md"
run_helper e5d check-correction "$WORK/dec.md" - "$WORK/dec-new.md"
assert_exit "decision-template **Original** quote is protected → exit 6" 6 "$RC"

# E6. marker: date comes from the backup id (UTC day)
run_helper e6 emit-audit-marker edit mode=correct backup-id=comment-1-20261009T230000Z
assert_output_grep "marker date is the backup id's UTC day" 'date="2026-10-09"' "$WORK/e6.out"

# E7. doc contracts for round 2
UPD="$SKILLS/idd-update/SKILL.md"
refute_output_grep "idd-update no longer says Key Decisions are append-only" "Key Decisions 只加不刪" "$UPD"
assert_output_grep "idd-update rebuilds Key Decisions from current comments" "每次重建" "$UPD"
for s in idd-verify idd-diagnose idd-reorganize; do
  assert_output_grep "$s stores replacement files under ~/.cache/idd/corrections" ".cache/idd/corrections" "$SKILLS/$s/SKILL.md"
done
assert_output_grep "idd-edit re-reads the target after confirmation" "changed since preview" "$SKILLS/idd-edit/SKILL.md"
refute_output_grep "idd-edit has no global ISSUE_BODY_TARGET routing" "ISSUE_BODY_TARGET" "$SKILLS/idd-edit/SKILL.md"
assert_output_grep "idd-comment errata self path takes --correction-file" "--correction-file" "$SKILLS/idd-comment/SKILL.md"
refute_output_grep "idd-comment does not declare the in-place-correction category" "(category: in-place-correction)" "$SKILLS/idd-comment/SKILL.md"
assert_output_grep "MANIFESTO lists the 8th category" "in-place-correction" "$PLUGIN/MANIFESTO.md"

# ── F. round 3 (verify #351 round 2) ──────────────────────────────────────
echo "F. round 3"

# F1. a whole-comment correction may not drop a managed region either
printf '## Notes\nwrong\n\n### Clarity Surface(idd-clarify run 2026-10-01T00:00:00Z)\n\n| Type | Source |\n|---|---|\n' >"$WORK/managed-comment.md"
run_helper f1 check-correction "$WORK/managed-comment.md" - "$WORK/r-exp.md"
assert_exit "whole-comment correction that drops managed sections → exit 6" 6 "$RC"
assert_output_grep "whole-comment refusal names the managing skill" "idd-" "$WORK/f1.err"

# F4. a fenced code block does not end a section
cat >"$WORK/fenced.md" <<'EOF'
## Notes
wrong intro

```bash
# a shell comment, not a heading
---
## Current Status
```

wrong tail

## Next
- keep me
EOF
printf 'right text\n' >"$WORK/r-fix.md"
run_helper f4a section-replace "$WORK/fenced.md" "## Notes" "$WORK/r-fix.md" --stop-at-rule
assert_exit "section-replace across a fence succeeds" 0 "$RC"
refute_output_grep "text after the fence is replaced too" "wrong tail" "$WORK/f4a.out"
refute_output_grep "fenced lines are replaced with the section" "a shell comment" "$WORK/f4a.out"
assert_output_grep "the next real heading survives" "## Next" "$WORK/f4a.out"
run_helper f4b check-correction "$WORK/fenced.md" "## Notes" "$WORK/r-fix.md"
# Round 4 reversed this: idd-update finds '## Current Status' by exact line
# match, fenced or not, so the protection scan reads lines the same way.
assert_exit "a '## Current Status' line inside the target is refused even when fenced" 6 "$RC"

# F4 + F7 + F8. compose-correction builds the full new body for preview and write
MARK='<!-- idd:edit mode="correct" backup-id="comment-1-20261016T000000Z" date="2026-10-16" -->'
run_helper f4c compose-correction "$WORK/fenced.md" "## Notes" "$WORK/r-fix.md" "$MARK"
assert_exit "compose-correction succeeds" 0 "$RC"
assert_output_grep "composed body keeps the heading" "## Notes" "$WORK/f4c.out"
assert_output_grep "composed body carries the new text" "right text" "$WORK/f4c.out"
assert_output_grep "composed body ends the section with the marker" "comment-1-20261016T000000Z" "$WORK/f4c.out"
assert_output_grep "composed body keeps the rest of the target" "keep me" "$WORK/f4c.out"

printf '## Notes\nright text\n' >"$WORK/r-dup.md"
run_helper f7a compose-correction "$WORK/fenced.md" "## Notes" "$WORK/r-dup.md" "$MARK"
assert_eq "a replacement that repeats the heading does not duplicate it" "1" "$(grep -c '^## Notes$' "$WORK/f7a.out")"

run_helper f7b parse-args comment:1 --correct --section "Expected" --body x --reason r
assert_exit "--section that is not a heading → exit 2" 2 "$RC"
run_helper f7c parse-args comment:1 --correct --section "##Expected" --body x --reason r
assert_exit "--section without a space after the hashes → exit 2" 2 "$RC"
run_helper f7d parse-args comment:1 --replace --section "Expected" --body x --reason r
assert_exit "--replace --section that is not a heading → exit 2" 2 "$RC"

OLDMARK='<!-- idd:edit mode="correct" backup-id="comment-1-20261001T000000Z" date="2026-10-01" -->'
printf '## Notes\nfirst fix\n\n%s\n\n## Next\n- keep me\n' "$OLDMARK" >"$WORK/recorrected.md"
run_helper f8 compose-correction "$WORK/recorrected.md" "## Notes" "$WORK/r-fix.md" "$MARK"
assert_output_grep "re-correcting keeps the earlier marker" "comment-1-20261001T000000Z" "$WORK/f8.out"
assert_output_grep "re-correcting adds the new marker" "comment-1-20261016T000000Z" "$WORK/f8.out"
assert_eq "the new marker is the last line of the section" "$MARK" \
  "$(awk '/^## Next/{exit} NF{last=$0} END{print last}' "$WORK/f8.out")"
printf 'whole\n\n%s\n' "$OLDMARK" >"$WORK/whole-old.md"
run_helper f8b compose-correction "$WORK/whole-old.md" - "$WORK/r-fix.md" "$MARK"
assert_output_grep "whole-comment re-correction keeps the earlier marker" "comment-1-20261001T000000Z" "$WORK/f8b.out"

# F6. --correct refuses a bot's comment; other modes keep the bot pass
printf '%s' '{"login":"coderabbitai[bot]","assoc":"NONE"}' >"$WORK/m-bot.json"
export IDD_EDIT_HELPER_TEST_MODE=1 IDD_EDIT_HELPER_GH_USER=kiki830621 IDD_EDIT_HELPER_GH_MOCK="$WORK/m-bot.json"
run_helper f6a validate-target 900 o/r false --correct
assert_exit "--correct on a bot comment → exit 4" 4 "$RC"
assert_output_grep "bot refusal says to propose an errata comment" "errata" "$WORK/f6a.err"
run_helper f6b validate-target 900 o/r false
assert_exit "--replace on a bot comment still passes" 0 "$RC"
printf '%s' '{"login":"someone-else","assoc":"CONTRIBUTOR"}' >"$WORK/m-other.json"
IDD_EDIT_HELPER_GH_MOCK="$WORK/m-other.json" run_helper f6c validate-target 902 o/r false --correct
assert_exit "--correct on another user's comment → exit 4" 4 "$RC"
refute_output_grep "a --correct refusal does not suggest the override it rejects" "override-user-content" "$WORK/f6c.err"
assert_output_grep "a --correct refusal points to errata" "errata" "$WORK/f6c.err"
unset IDD_EDIT_HELPER_GH_MOCK IDD_EDIT_HELPER_GH_USER

# F13. test mode never calls the real gh for the current user
FAKEBIN="$WORK/fakebin"; mkdir -p "$FAKEBIN"
printf '#!/bin/sh\necho called >"%s/gh-called"\necho kiki830621\n' "$WORK" >"$FAKEBIN/gh"; chmod +x "$FAKEBIN/gh"
printf '%s' '{"login":"kiki830621","assoc":"MEMBER"}' >"$WORK/m-me.json"
IDD_EDIT_HELPER_GH_MOCK="$WORK/m-me.json" PATH="$FAKEBIN:$PATH" run_helper f13 validate-target 901 o/r false
refute "test mode without IDD_EDIT_HELPER_GH_USER does not run gh" test -e "$WORK/gh-called"
assert_exit "unknown current user in test mode → not treated as own content" 4 "$RC"
unset IDD_EDIT_HELPER_TEST_MODE

# F14. a value starting with '=' survives eval under zsh
run_helper f14 parse-args comment:1 --correct --scope whole-comment --body x --reason "=echo"
assert_output_grep "a leading '=' is escaped" 'REASON=\=echo' "$WORK/f14.out"
if command -v zsh >/dev/null 2>&1; then
  assert_eq "zsh eval keeps the literal value" "=echo" \
    "$(zsh -c 'eval "$(cat "$1")"; print -r -- "$REASON"' _ "$WORK/f14.out" 2>/dev/null)"
fi

# F2 + F11. skill contract: fetch failures and declines have their own buckets
EDIT_SKILL="$SKILLS/idd-edit/SKILL.md"
require "both gh fetches check the exit code (Step 2 and the re-read)" \
  test "$(grep -c 'REFUSED_TARGETS+=("$TARGET fetch-failed")' "$EDIT_SKILL")" -ge 2
assert_output_grep "a missing section has its own refusal reason" "section-not-found" "$EDIT_SKILL"
assert_output_grep "a declined preview cleans up and is reported" "declined" "$EDIT_SKILL"
assert_output_grep "the preview shows the composed full text" "compose-correction" "$EDIT_SKILL"
assert_output_grep "validate-target receives the mode" 'validate-target "$VALIDATE_ARG" "$REPO" "$OVERRIDE_USER_CONTENT" "$MODE"' "$EDIT_SKILL"

# F5 / F9 / F10 / F12. doc contracts
assert_output_grep "idd-comment errata routing asks with --correct, so a bot goes to errata" \
  'validate-target "$TARGET_COMMENT" "$GITHUB_REPO" false --correct' "$SKILLS/idd-comment/SKILL.md"
refute_output_grep "no skill still says OWNER, a bot, or you are correctable" "OWNER、bot" "$SKILLS/idd-comment/SKILL.md"
assert_output_grep "idd-edit says the archive lives in one clone" "那份 clone" "$EDIT_SKILL"
assert_output_grep "idd-edit says to chmod the archive back" "chmod 000" "$EDIT_SKILL"
assert_output_grep "idd-issue multi-finding routes wrong body content to --correct" "--correct --section" "$SKILLS/idd-issue/SKILL.md"
assert_output_grep "README lists the archive read guard hook" "archive-read-guard" "$PLUGIN/README.md"
assert_output_grep "idd-update leaves out decisions an errata overturned" "type=errata" "$SKILLS/idd-update/SKILL.md"
assert_output_grep "idd-reorganize separates superseded judgments from wrong statements" "判斷被後來的資訊推翻" "$SKILLS/idd-reorganize/SKILL.md"

# ── G. round 4 (verify #351 round 3) ──────────────────────────────────────
echo "G. round 4"

# G1. an unclosed fence: in the original target, or opened by the replacement
cat >"$WORK/unclosed.md" <<'EOF'
## Expected
wrong text
```bash
echo oops

---

## Current Status

**Phase**: diagnosed
EOF
run_helper g1a check-correction "$WORK/unclosed.md" "## Expected" "$WORK/r-fix.md"
assert_exit "an unclosed fence that swallows ## Current Status → exit 6" 6 "$RC"

printf '## Expected\nwrong\n\n## Actual\nx\n\n---\n\n## Current Status\n\n**Phase**: diagnosed\n' >"$WORK/plain.md"
printf 'fixed:\n```bash\necho hi\n' >"$WORK/r-open.md"
run_helper g1b compose-correction "$WORK/plain.md" "## Expected" "$WORK/r-open.md" "$MARK"
assert_exit "a replacement that leaves a fence open → exit 6" 6 "$RC"
assert_output_grep "the refusal says the block is left open" "open" "$WORK/g1b.err"

printf '## Notes\nwrong\n<!--\n## hidden\n-->\nmore wrong\n\n## Next\n- keep me\n' >"$WORK/htmlc.md"
run_helper g1c section-replace "$WORK/htmlc.md" "## Notes" "$WORK/r-fix.md" --stop-at-rule
refute_output_grep "a heading inside an HTML comment does not end the section" "more wrong" "$WORK/g1c.out"
assert_output_grep "the real next heading survives" "## Next" "$WORK/g1c.out"
refute_output_grep "no orphan comment terminator is left" "-->" "$WORK/g1c.out"

printf '## Notes\nwrong\n\nSub title\n---\nkeep sub\n\n## Next\n' >"$WORK/setext.md"
run_helper g1d section-replace "$WORK/setext.md" "## Notes" "$WORK/r-fix.md" --stop-at-rule
assert_output_grep "a setext H2 ends the section" "Sub title" "$WORK/g1d.out"
assert_output_grep "the setext section's body stays" "keep sub" "$WORK/g1d.out"
refute_output_grep "the corrected text is gone" "wrong" "$WORK/g1d.out"

# G2. NUL and control characters never reach eval unquoted
printf 'x\000;touch %s/PWNED' "$WORK" >"$WORK/nul.md"
run_helper g2a parse-args comment:1 --correct --scope whole-comment --body-file "$WORK/nul.md" --reason r
assert_exit "a body file with a NUL byte → exit 5" 5 "$RC"
run_helper g2b parse-args comment:1 --correct --scope whole-comment --body "$(printf 'a\001b')" --reason r
assert_output_grep "a control character goes through ANSI-C quoting" "BODY_INPUT=\$'a\\x01b'" "$WORK/g2b.out"

# G3. every '=' is escaped (zsh expands '=cmd' after ':' too)
run_helper g3 parse-args comment:1 --correct --scope whole-comment --body 'a:=ls' --reason r
assert_output_grep "an '=' after ':' is escaped" 'BODY_INPUT=a:\=ls' "$WORK/g3.out"
if command -v zsh >/dev/null 2>&1; then
  assert_eq "zsh eval keeps 'a:=ls'" "a:=ls" \
    "$(zsh -c 'eval "$(cat "$1")"; print -r -- "$BODY_INPUT"' _ "$WORK/g3.out" 2>/dev/null)"
fi

# G4. a subsection of Clarity Surface is managed too
printf '## Related\n- #1\n\n### Clarity Surface(idd-clarify run 2026-10-01T00:00:00Z)\n\n#### Pending\n- a question\n' >"$WORK/nested-cs.md"
run_helper g4 check-correction "$WORK/nested-cs.md" "#### Pending" "$WORK/r-fix.md"
assert_exit "a heading nested under Clarity Surface → exit 6" 6 "$RC"
assert_output_grep "the refusal names idd-clarify" "idd-clarify" "$WORK/g4.err"

# G5. a line right after the Original text quotation would join it (lazy continuation)
printf '%s\nnew interpretation\n' "$QUOTE" >"$WORK/r-lazy.md"
run_helper g5 check-correction "$WORK/body.md" "## Problem" "$WORK/r-lazy.md"
assert_exit "text glued to the quotation → exit 6" 6 "$RC"

# G6. --correct needs replacement text
run_helper g6 parse-args comment:1 --correct --scope whole-comment --reason r
assert_exit "--correct without --body or --body-file → exit 2" 2 "$RC"

# G7. identity markers other skills look for survive a whole-comment correction
printf '## Diagnosis\n### Root Cause\nwrong\n\n<!-- idd:comment type=errata date=2026-10-01 target-comment=99 -->\n' >"$WORK/diag.md"
run_helper g7a check-correction "$WORK/diag.md" - "$WORK/r-fix.md"
assert_exit "dropping the comment's ## Diagnosis heading → exit 6" 6 "$RC"
printf '## Diagnosis\n### Root Cause\nright\n' >"$WORK/r-diag.md"
run_helper g7b check-correction "$WORK/diag.md" - "$WORK/r-diag.md"
assert_exit "keeping the heading passes" 0 "$RC"
run_helper g7c compose-correction "$WORK/diag.md" - "$WORK/r-diag.md" "$MARK"
assert_output_grep "the idd:comment marker is carried forward" "target-comment=99" "$WORK/g7c.out"

# G8. markers are not duplicated, and every idd:edit marker is kept
printf 'fixed\n\n%s\n' "$OLDMARK" >"$WORK/r-withmark.md"
run_helper g8 compose-correction "$WORK/recorrected.md" "## Notes" "$WORK/r-withmark.md" "$MARK"
assert_eq "an earlier marker copied into the replacement appears once" "1" "$(grep -c 'comment-1-20261001T000000Z' "$WORK/g8.out")"
printf '## Notes\nold\n\n<!-- idd:edit mode="replace" section="## Notes" date="2026-09-01" -->\n\n## Next\n' >"$WORK/replaced.md"
run_helper g8b compose-correction "$WORK/replaced.md" "## Notes" "$WORK/r-fix.md" "$MARK"
assert_output_grep "an earlier replace marker is kept" 'mode="replace"' "$WORK/g8b.out"

# G9. a missing or different Markdown parser has its own exit code
mkdir -p "$WORK/fakemd/markdown_it"
printf '__version__ = "0.0.1"\nclass MarkdownIt:\n    pass\n' >"$WORK/fakemd/markdown_it/__init__.py"
PYTHONPATH="$WORK/fakemd" run_helper g9 section-replace "$WORK/body.md" "## Expected" "$WORK/r-fix.md"
assert_exit "a different markdown-it-py version → exit 8" 8 "$RC"

# G10. validate-target: --correct ignores override; an unknown gh user is not a verdict
printf '%s' '{"login":"someone-else","assoc":"CONTRIBUTOR"}' >"$WORK/m-other2.json"
export IDD_EDIT_HELPER_TEST_MODE=1 IDD_EDIT_HELPER_GH_MOCK="$WORK/m-other2.json" IDD_EDIT_HELPER_GH_USER=kiki830621
run_helper g10a validate-target 903 o/r true --correct
assert_exit "--correct with override true still refuses another user's comment" 4 "$RC"
unset IDD_EDIT_HELPER_GH_USER
run_helper g10b validate-target 903 o/r false --correct
assert_exit "--correct when the gh user cannot be determined → exit 1" 1 "$RC"
assert_output_grep "the error says the gh user is unknown" "gh user" "$WORK/g10b.err"
unset IDD_EDIT_HELPER_TEST_MODE IDD_EDIT_HELPER_GH_MOCK

# G11. existing-mentions lists the logins the target already mentions
printf 'Thanks @alice and `@bob`, mail user@host.\n' >"$WORK/mentions.md"
run_helper g11 existing-mentions "$WORK/mentions.md"
assert_eq "only the live mention is listed" "alice" "$(cat "$WORK/g11.out")"

# G12. skill contracts
assert_output_grep "egress is checked before anything is archived" 'gh-egress.sh" check' "$EDIT_SKILL"
assert_output_grep "existing mentions are attested" "existing-mentions" "$EDIT_SKILL"
assert_output_grep "--replace checks section-replace's exit code" 'section-replace "$BACKUP_FILE" "$SECTION_FLAG" "$REPL_FILE") || {' "$EDIT_SKILL"
assert_output_grep "a staging failure is recorded, not fatal" "stage-failed" "$EDIT_SKILL"
assert_output_grep "working copies live in a private per-run directory" 'WORK_DIR=$(mktemp -d' "$EDIT_SKILL"
assert_output_grep "the written body is compared with the preview" "differs-from-preview" "$EDIT_SKILL"
assert_output_grep "a run where something was declined exits 5" '[ "${#DECLINED_TARGETS[@]}" -gt 0 ] && exit 5' "$EDIT_SKILL"
assert_output_grep "a failed eval stops the run" 'eval "$PARSE_OUT" ||' "$EDIT_SKILL"
assert_output_grep "idd-comment falls back to an errata comment when idd-edit refuses" "改貼 errata" "$SKILLS/idd-comment/SKILL.md"

print_summary "in-place-correction"
