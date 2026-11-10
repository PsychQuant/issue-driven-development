#!/usr/bin/env bash
# spec-wrapper-contract suite (#480) — the wrappers that make every implemented
# issue leave a spec change (Spectra change spec-on-every-issue, group 3).
#
# The wrappers are SKILL.md text carried out by a model, so this suite pins the
# parts a reader would otherwise drift on: the shared contract exists and names
# each step, and the three skills call the steps in the right order and post the
# declaration line that scripts/spec-change.py reads.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
REF="$PLUGIN/references/spec-wrapper.md"
IMPL="$PLUGIN/skills/idd-implement/SKILL.md"
PLAN="$PLUGIN/skills/idd-plan/SKILL.md"
ALL="$PLUGIN/skills/idd-all/SKILL.md"
read_file() { [ -f "$1" ] && cat "$1" || printf ''; }
line_of() { # file needle — first line number, or 999999 when absent
  local n; n=$(grep -nF -- "$2" "$1" 2>/dev/null | head -1 | cut -d: -f1); printf '%s' "${n:-999999}"
}
MARK='<!-- idd:comment type=implementation-complete -->'

echo "spec-wrapper-contract: the shared contract"
REF_TXT="$(read_file "$REF")"
assert_true "references/spec-wrapper.md exists" "[ -s '$REF' ]"
for needle in \
  'spec-change.py" preflight' \
  'idd-<N>-<slug>' \
  'spectra-propose' \
  'spectra-apply' \
  'spectra-verify' \
  'spectra archive' \
  'spec-change.py" archived' \
  'spec-change.py" links --base' \
  'git merge-base HEAD "origin/$DEFAULT_BRANCH"' \
  'spec-example: <capability> / <Example title>' \
  "$MARK" \
  '**Spec**: change' \
  '**Spec**: no behaviour change' \
  '**Spec**: third-party clone' \
  'idd-<N>-fix<k>'; do
  assert_grep "contract names: $needle" "$needle" "$REF_TXT"
done
assert_grep "the light form has no discuss and no design" "不做 discuss、不寫 design" "$REF_TXT"
assert_grep "the four exemption cases are a closed list" "只有這四種" "$REF_TXT"
assert_grep "refactor is the fourth case" "(d)" "$REF_TXT"
assert_grep "a linked worktree stops" "linked-worktree" "$REF_TXT"
assert_grep "close-out runs in a fixed order" "順序固定" "$REF_TXT"

echo "spec-wrapper-contract: idd-implement is the Simple wrapper"
IMPL_TXT="$(read_file "$IMPL")"
assert_grep "idd-implement cites the contract" "references/spec-wrapper.md" "$IMPL_TXT"
assert_grep "idd-implement runs the spec preflight" 'spec-change.py" preflight' "$IMPL_TXT"
assert_true "the spec preflight comes before Step 1 (before any artifact or commit)" \
  "[ $(line_of "$IMPL" '### Step 0.6: Spec preflight') -lt $(line_of "$IMPL" '### Step 1: ') ]"
assert_true "the spec preflight comes after the path is resolved" \
  "[ $(line_of "$IMPL" '### Step 0.5: ') -lt $(line_of "$IMPL" '### Step 0.6: Spec preflight') ]"
assert_grep "idd-implement proposes through spectra-propose" 'Skill(skill="spectra-propose"' "$IMPL_TXT"
assert_grep "idd-implement applies through spectra-apply" 'Skill(skill="spectra-apply"' "$IMPL_TXT"
assert_grep "idd-implement does not propose again when idd-plan already did" "不再 propose" "$IMPL_TXT"
assert_true "the spec close-out comes before the Implementation Complete comment" \
  "[ $(line_of "$IMPL" '### Step 4.5: Spec close-out') -lt $(line_of "$IMPL" '### Step 5: ') ]"
assert_grep "the Implementation Complete template carries the marker" "$MARK" "$IMPL_TXT"
assert_grep "the Implementation Complete template carries the Spec line" '**Spec**: {' "$IMPL_TXT"
assert_grep "the tree-lock step says a linked worktree cannot write a spec change" "linked worktree" "$(sed -n '/^### Step 0.4: /,/^### Step 0.5: /p' "$IMPL")"
assert_grep "the stage task list has the spec preflight" 'name="spec_preflight"' "$IMPL_TXT"
assert_grep "the stage task list has the spec close-out" 'name="spec_closeout"' "$IMPL_TXT"

echo "spec-wrapper-contract: idd-plan is the Plan wrapper"
PLAN_TXT="$(read_file "$PLAN")"
assert_grep "idd-plan cites the contract" "references/spec-wrapper.md" "$PLAN_TXT"
assert_grep "idd-plan proposes through spectra-propose" 'Skill(skill="spectra-propose"' "$PLAN_TXT"
assert_grep "idd-plan presents the proposal and the tasks for approval" "proposal 與 tasks" "$(sed -n '/^### Step 4: /,/^### Step 5: /p' "$PLAN")"
assert_grep "idd-plan hands the approved change to idd-implement" "change 名稱" "$(sed -n '/^### Step 6: /,/^### Step 7: /p' "$PLAN")"

echo "spec-wrapper-contract: idd-all closes out the Spectra tier"
ALL_TXT="$(read_file "$ALL")"
assert_grep "idd-all cites the contract" "references/spec-wrapper.md" "$ALL_TXT"
B3="$(sed -n '/^### Phase 3b: /,/^### Phase 4: /p' "$ALL")"
assert_grep "Phase 3b runs the close-out after apply" "Spec close-out" "$B3"
assert_grep "Phase 3b posts the Implementation Complete with the marker" "$MARK" "$B3"
assert_grep "Phase 3b's comment has no Checklist section" "沒有 \`### Checklist\`" "$B3"

print_summary spec-wrapper-contract
