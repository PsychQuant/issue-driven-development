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

echo "spectra-verify findings before archiving (2026-11-11)"
assert_eq "no skill, rule or reference still says close triggers archive" 0 "$(grep -rlF 'Close triggers archive' "$PLUGIN/skills" "$PLUGIN/rules" "$PLUGIN/references" "$PLUGIN/CLAUDE.md" 2>/dev/null | wc -l | tr -d ' ')"
refute_grep "idd-all's report no longer asks for an archive on the default branch" 'Next: run /spectra-archive' "$ALL_TXT"
HANDOFF="$(sed -n '/Spectra tier 的追蹤 hand-off/,/為什麼需要這一行/p' "$PLUGIN/skills/idd-diagnose/SKILL.md")"
assert_grep "the diagnose hand-off points at the contract's close-out" "spec-wrapper.md" "$HANDOFF"
assert_grep "… and at the archived tasks path" "changes/archive/" "$HANDOFF"
refute_grep "… not at the open change's tasks path" '--tasks-file openspec/changes/<change-name>/tasks.md' "$HANDOFF"
S5A="$(sed -n '/^\*\*Step 5a: Checklist Sync\*\*/,/^\*\*Step 5b/p' "$IMPL")"
assert_grep "idd-implement Step 5a fills the checklist from tasks.md when the issue has a change" "tasks.md" "$S5A"
refute_grep "the Implementation Complete template no longer names TaskList as the only source" '### Checklist (synced from TaskList)' "$IMPL_TXT"
SB="$(sed -n '/規格對照（#480）/,/^DA_FOCUS_SUFFIX=/p' "$VERIFY")"
assert_grep "verify builds the spec context only under the code profile, with a git range" 'if [ "${VERIFY_PROFILE:-code}" = code ] && [ -n "${BASE_SHA:-}" ] && [ -n "${FROZEN_SHA:-}" ]; then' "$SB"
assert_grep "a failed comment fetch is detected on the fetch itself" 'SPEC_FETCH_OK=no' "$SB"
assert_grep "… and reported as unreadable, not read as legacy" '"form":"unreadable"' "$SB"
assert_grep "the DA focus carries the spec check results" '${SPEC_DA' "$(grep -F 'DA_FOCUS_SUFFIX=' "$VERIFY")"
assert_grep "Step 3 blocks on any result other than ok and pass" '`ok`' "$(sed -n '/^### Step 3: /,/^### Step 3.5: /p' "$VERIFY")"
B3P="$(sed -n '/^### Phase 3b: /,/^#### Step 3b.1: /p' "$ALL")"
assert_grep "the Spectra tier runs the spec preflight before discuss" 'spec-change.py" preflight' "$B3P"
assert_grep "… and hands a third-party clone to idd-implement" "third-party" "$B3P"
assert_grep "the contract: a fix change is named exactly idd-<N>-fix<k>" "不加 slug" "$REF_TXT"
assert_grep "the contract: after the archive, a requirement fix goes through step 7, archive/ is not edited" '不改 `archive/`' "$REF_TXT"
assert_grep "the contract: the Spec line holds the declaration only" "只寫宣告" "$REF_TXT"
assert_grep "the README states the linked-worktree limit" "linked worktree" "$(read_file "$PLUGIN/README.md")"

echo "spec-wrapper-contract: verify round 1 fixes (idd-480-fix1)"
SB="$(sed -n '/規格對照（#480）/,/^DA_FOCUS_SUFFIX=/p' "$VERIFY")"
assert_grep "verify chooses the comment with spec-change.py ic" 'spec-change.py" ic --comments' "$SB"
refute_grep "… and has no selection of its own" 'author_association ==' "$SB"
assert_grep "reviewers judge No executable check reasons" 'No executable check:' "$(printf '%s' "$SB" | grep -F 'Every reviewer')"
B3P="$(sed -n '/^### Phase 3b: /,/^#### Step 3b.1: /p' "$ALL")"
assert_true "Phase 3b runs the preflight before it checks for Spectra" \
  "[ $(printf '%s\n' "$B3P" | grep -nF 'spec-change.py" preflight' | head -1 | cut -d: -f1) -lt $(printf '%s\n' "$B3P" | grep -nF 'command -v spectra' | head -1 | cut -d: -f1) ]"
assert_grep "Phase 3b reads the permission strictly" 'READ|TRIAGE|NONE) CAN_WRITE=no' "$B3P"
assert_grep "the Spectra tier's propose args ask for Examples and markers" 'spec-example:' "$(sed -n '/^#### Step 3b.3: /,/^#### Step 3b.4: /p' "$ALL")"
assert_grep "idd-all's fix rule covers a rejected exemption" "verify 否決" "$(sed -n '/^\*\*修正也留下規格（#480）\*\*/,/^\*\*乾淨的定義/p' "$ALL")"
assert_grep "the contract reads the permission strictly" 'READ|TRIAGE|NONE) CAN_WRITE=no' "$REF_TXT"
refute_grep "… and no longer defaults an unreadable permission to no" "讀不到權限時是 \`no\`" "$REF_TXT"
assert_grep "the contract's step 7 covers a rejected exemption" "verify 否決" "$(sed -n '/^## 7\. /,$p' "$REF")"
refute_grep "idd-implement no longer says exempt issues are unaffected by the worktree stop" "不受影響" "$(sed -n '/^### Step 0.4: /,/^### Step 0.5: /p' "$IMPL")"
assert_grep "idd-all's batch mode warns that worktrees stop issues that write a spec" "#488" "$(sed -n '/idd-worktree.sh create <N>/p' "$ALL")"

SBQ="$(sed -n '/^  SPEC_BLOCK="SPEC CONTEXT/,/^else$/p' "$VERIFY")"
assert_true "the SPEC_BLOCK string exists" "[ -n \"\$SBQ\" ]"
refute_grep "SPEC_BLOCK is a double-quoted string: a backtick in it runs a command (a fix-round slip)" '`' "$SBQ"

echo "spec-wrapper-contract: spectra-verify findings on idd-480-fix1"
assert_grep "an unreadable permission sets PF to an error the status table catches (contract)" 'PF=' "$(grep -F 'cannot read this account' "$REF")"
assert_grep "… (idd-all Phase 3b)" 'PF=' "$(grep -F 'cannot read this account' "$ALL")"
refute_grep "idd-all no longer says Phase 3b aborts without Spectra" "Phase 3b will abort" "$ALL_TXT"
refute_grep "the verify comment no longer describes the jq selection" "jq 照樣對空輸入" "$V_TXT"
assert_grep "a third-party Spectra-tier issue rerouted to idd-implement keeps a TaskList" "third-party" "$(grep -F '`Spectra`' "$IMPL" | grep -F '跳過本 step')"

echo "spec-wrapper-contract: the preflight call, run (idd-480-fix2)"
# spec-example: spec-on-every-issue / the preflight call routes by permission and Spectra
# The bash of contract step 1 and of idd-all Step 3b.0 is run as written, with a stand-in gh that reports
# $FAKE_PERM and a PATH that has or lacks a stand-in spectra. Both copies must give the same status.
W2=$(mktemp -d "${TMPDIR:-/tmp}/idd-swc.XXXXXX"); trap 'rm -rf "$W2"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$W2/base" "$W2/withspectra"
for tool in python3 git jq; do ln -s "$(command -v "$tool")" "$W2/base/$tool"; done
printf '#!/bin/sh\ncase "$1 $2" in "repo view") [ -n "$FAKE_PERM" ] || exit 1; echo "$FAKE_PERM" ;; *) exit 1 ;; esac\n' > "$W2/base/gh"
printf '#!/bin/sh\nexit 0\n' > "$W2/withspectra/spectra"
chmod +x "$W2/base/gh" "$W2/withspectra/spectra"
git init -q "$W2/present"; mkdir -p "$W2/present/openspec/specs"
git init -q "$W2/absent"
awk '/^## 1\. /{f=1} f && /^```bash$/{b=1; next} b && /^```$/{exit} b' "$REF" > "$W2/contract.sh"
awk '/^#### Step 3b.0: Spec preflight/{f=1} f && /^```bash$/{b=1; next} b && /^```$/{exit} b' "$ALL" > "$W2/all.sh"
pf_status() { # block perm spectra(yes|no) specdir(present|absent) → printed status
  local p="$W2/base:/usr/bin:/bin"; [ "$3" = yes ] && p="$W2/withspectra:$p"
  env -i HOME="$HOME" PATH="$p" FAKE_PERM="$2" GITHUB_REPO=o/r CWD="$W2/$4" CLAUDE_PLUGIN_ROOT="$PLUGIN" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 bash --norc --noprofile -c '. "$1" >/dev/null 2>&1; printf "%s" "$PF" | python3 -c "import json,sys; print(json.loads(sys.stdin.read() or \"{}\").get(\"status\", \"none\"))"' _ "$W2/$1" </dev/null
}
for row in "WRITE yes present ready" "ADMIN no present install-spectra" "READ no absent third-party" \
           "TRIAGE yes present third-party" "- yes present error" "SOMETHING_ELSE yes present error"; do
  set -- $row; perm=$1; [ "$perm" = - ] && perm=""
  if [ "$2" = no ]; then
    # /bin/bash 3.2 reads ~/.bashrc in -c mode when it thinks a remote shell started it (stdin a socket), and
    # a ~/.bashrc that adds ~/.local/bin put a real spectra on the "clean" PATH: one run in ten failed on
    # 2026-11-11. Every nested bash here runs with --norc --noprofile and stdin from /dev/null.
    seen=$(env -i HOME="$HOME" PATH="$W2/base:/usr/bin:/bin" bash --norc --noprofile -c 'command -v spectra || true' </dev/null)
    assert_eq "… the restricted PATH really has no spectra (row ${perm:-none})" "" "$seen"
  fi
  a=$(pf_status contract.sh "$perm" "$2" "$3"); b=$(pf_status all.sh "$perm" "$2" "$3")
  assert_eq "preflight call: permission '${perm:-none}', spectra $2, spec dir $3 → $4 (contract)" "$4" "$a"
  assert_eq "… the same in idd-all Step 3b.0" "$a" "$b"
done
assert_grep "the contract stops when preflight prints nothing or not JSON" "沒有輸出" "$REF_TXT"
assert_grep "idd-all Step 3b.0 stops when preflight prints nothing or not JSON" "沒有輸出" "$(sed -n '/^#### Step 3b.0: Spec preflight/,/^#### Step 3b.0.5: /p' "$ALL")"

echo "spec-wrapper-contract: verify round 2 fixes in the text (idd-480-fix2)"
CL="$PLUGIN/skills/idd-close/SKILL.md"
assert_grep "a retroactive close skips Step 1.57" "1.57" "$(grep -F '| Step 0 / 1.5' "$CL")"
assert_grep "the verify spec context runs only with a git range" '[ -n "${BASE_SHA:-}" ]' "$SB"
assert_grep "the verify spec data sits in a per-run fence" 'SPEC_FENCE' "$SB"
assert_grep "the DA suffix gains the spec checks only when a spec context was built" '[ -n "$SPEC_BLOCK" ]' "$(grep -F 'DA_FOCUS_SUFFIX=' "$VERIFY" | tail -1; grep -F 'DA_FOCUS_SUFFIX="$DA_FOCUS_SUFFIX' "$VERIFY")"
assert_grep "verify-profiles says what of the default profile is unchanged" "lens 組合與輸入偵測" "$(read_file "$PROFILES")"
assert_grep "the diagnose hand-off runs the preflight before /spectra-discuss" "preflight" "$(sed -n '/Spectra tier 的追蹤 hand-off/,/為什麼需要這一行/p' "$PLUGIN/skills/idd-diagnose/SKILL.md")"
assert_grep "the routing rule's Spectra flow starts with the preflight" "preflight" "$(grep -F 'Spectra:   diagnose' "$PLUGIN/rules/sdd-integration.md")"
refute_grep "docs/commands.md no longer chains close through /spectra-archive" "chain through \`/spectra-archive\`" "$(read_file "$PLUGIN/../../docs/commands.md")"

echo "spec-wrapper-contract: the verify spec context without a git range, run (idd-480-fix2)"
S0=$(grep -n '^# ── 規格對照（#480）' "$VERIFY" | cut -d: -f1)
S1=$(grep -n '^DA_FOCUS_SUFFIX=' "$VERIFY" | tail -1 | cut -d: -f1)
sed -n "${S0},$((S1 + 1))p" "$VERIFY" | grep -v '^DA_FOCUS_SUFFIX=' > "$W2/specctx.sh"
mkdir -p "$W2/vdir"
out=$(env -i HOME="$HOME" PATH="$W2/base:/usr/bin:/bin" VERIFY_DIR="$W2/vdir" CLAUDE_PLUGIN_ROOT="$PLUGIN" \
      bash --norc --noprofile -c 'BASE_SHA=""; FROZEN_SHA=""; CONTEXT_BLOCK="ctx"; DA_FOCUS_SUFFIX="base"; . "$1" 2>/dev/null; printf "%s|%s|%s" "${SPEC_BLOCK:-EMPTY}" "$CONTEXT_BLOCK" "$DA_FOCUS_SUFFIX"' _ "$W2/specctx.sh" </dev/null)
assert_eq "no git range (prose / academic): no spec block, context and DA focus unchanged" "EMPTY|ctx|base" "$out"
assert_grep "… and spec-block.md says it is not used" "not used" "$(cat "$W2/vdir/spec-block.md" 2>/dev/null)"

print_summary spec-wrapper-contract
