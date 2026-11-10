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

echo "spec-wrapper-contract: unattended runs do not stop on Spectra's questions"
assert_grep "the contract detects unattended runs through the unattended contract" 'is_unattended "$CWD"' "$REF_TXT"
assert_grep "… and adds the UNATTENDED MODE note to the args" "UNATTENDED MODE" "$REF_TXT"
assert_grep "the wrapper unparks the change itself before apply" 'spectra unpark "$CHANGE"' "$REF_TXT"
assert_true "… before it calls spectra-apply" \
  "[ $(line_of "$REF" 'spectra unpark "$CHANGE"') -lt $(line_of "$REF" 'Skill(skill="spectra-apply"') ]"
refute_grep "the contract no longer leaves the unpark to spectra-apply" "會自己 unpark" "$REF_TXT"
assert_grep "the unattended contract lists the spec wrapper as a detector" "spec-wrapper" "$(read_file "$PLUGIN/references/unattended-contract.md")"

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
assert_grep "idd-implement's apply goes through contract step 4 (unpark first)" "契約第 4 步" "$(grep -F 'Skill(skill="spectra-apply"' "$IMPL")"
assert_grep "idd-implement's propose carries the unattended note when unattended" "無人值守" "$(grep -F 'Skill(skill="spectra-propose"' "$IMPL")"
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

echo "spec-wrapper-contract: idd-verify checks behaviour against the specs (task 4.1)"
VERIFY="$PLUGIN/skills/idd-verify/SKILL.md"; PROFILES="$PLUGIN/references/verify-profiles.md"
V_TXT="$(read_file "$VERIFY")"
assert_grep "verify runs the link check on the reviewed range" 'links --base "$BASE_SHA" --head "$FROZEN_SHA"' "$V_TXT"
assert_grep "verify runs the archive check at the reviewed head" '--ref "$FROZEN_SHA"' "$V_TXT"
assert_grep "verify reads the declaration line" 'spec-change.py" declared' "$V_TXT"
assert_grep "verify stages the spec context to a file" '"$VERIFY_DIR/spec-block.md"' "$V_TXT"
assert_grep "the spec context joins the shared context block" '${SPEC_BLOCK}' "$V_TXT"
assert_true "the spec context is built after the external-writes block is staged" \
  "[ $(line_of "$VERIFY" '> "$VERIFY_DIR/ew-block.md"') -lt $(line_of "$VERIFY" '> "$VERIFY_DIR/spec-block.md"') ]"
assert_eq "every manual reviewer prompt is told to read the spec context" \
  "$(grep -cF 'External-writes context: $VERIFY_DIR/ew-block.md' "$VERIFY")" "$(grep -cF 'Spec context: $VERIFY_DIR/spec-block.md' "$VERIFY")"
assert_grep "the regression rule: behaviour no requirement states is HIGH" "no requirement" "$V_TXT"
assert_grep "the regression rule: a false no-behaviour-change declaration is HIGH" "no-behaviour-change" "$V_TXT"
assert_grep "the test rule: a marked test that does not check its Example is MEDIUM or above" "MEDIUM or above" "$V_TXT"
assert_grep "Step 3 turns the two checks into Blocking rows" "spec-block.md" "$(sed -n '/^### Step 3: /,/^### Step 3.5: /p' "$VERIFY")"
assert_grep "the spec context is the code profile's only" "code profile" "$(sed -n '/SPEC CONTEXT/,/spec-block.md/p' "$VERIFY")"
assert_grep "verify-profiles says the code profile carries the spec context" "spec-block" "$(read_file "$PROFILES")"

echo "spec-wrapper-contract: fixes after a verify round (task 4.2)"
FIX="$(sed -n '/^\*\*Auto-fix 策略\*\*/,/^### Phase 4.5/p' "$ALL")"
assert_grep "idd-all's auto-fix creates idd-<N>-fix<k> when a fix adds or changes a requirement" 'idd-<N>-fix<k>' "$FIX"
assert_grep "… through contract step 7" "第 7 步" "$FIX"
assert_grep "… archived before the next verify round" "下一輪 verify 之前" "$FIX"
assert_grep "… and a new Implementation Complete lists every change" "所有 change" "$FIX"
assert_grep "a Blocking fix leaves a test that fails before the fix" "修正前會失敗" "$FIX"
assert_grep "idd-implement routes a post-verify fix to step 7" 'idd-<N>-fix<k>' "$(sed -n '/^### Step 0.6: /,/^### Step 1: /p' "$IMPL")"

print_summary spec-wrapper-contract
