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
  'git -C "$CWD" merge-base HEAD FETCH_HEAD' \
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
refute_grep "idd-plan does not propose (idd-480-fix7)" 'Skill(skill="spectra-propose"' "$PLAN_TXT"
assert_grep "… it says so where it writes the Spec plan line" "本 skill 不 propose" "$(grep -F '先寫規格（#480' "$PLAN")"
refute_grep "idd-plan has no Step 3.5 (idd-480-fix7)" "### Step 3.5:" "$PLAN_TXT"
refute_grep "… and no read_change_files task" "read_change_files" "$PLAN_TXT"
refute_grep "Step 4 no longer attaches the change's files" "Step 3.5" "$(sed -n '/^### Step 4: /,/^### Step 5: /p' "$PLAN")"
S6P="$(sed -n '/^### Step 6: /,/^### Step 7: /p' "$PLAN")"
assert_grep "idd-plan hands the approved change name to idd-implement" "change 名稱" "$S6P"
assert_grep "… which proposes in the light form" "輕量形式 propose" "$S6P"
assert_grep "the Revised row is back to its wording before #480" '| Revised (with feedback) | 修改 Implementation Plan comment（用 `gh api PATCH` 更新原 comment 而非新 comment 避免散亂），再次 `EnterPlanMode` 呈現新版 |' "$PLAN_TXT"
refute_grep "the Aborted row no longer writes rejected or parks" "spectra park" "$(grep -F '| Aborted |' "$PLAN")"

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
assert_grep "verify builds the spec context only under the code profile" 'if [ "${VERIFY_PROFILE:-code}" = code ]; then' "$SB"
assert_grep "… and under code, a missing range is reported as an error, not skipped" 'BASE_SHA or FROZEN_SHA is empty in this shell' "$SB"
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
pf_rc() { # block perm spectra specdir → PF_RC the block leaves
  local p="$W2/base:/usr/bin:/bin"; [ "$3" = yes ] && p="$W2/withspectra:$p"
  env -i HOME="$HOME" PATH="$p" FAKE_PERM="$2" GITHUB_REPO=o/r CWD="$W2/$4" CLAUDE_PLUGIN_ROOT="$PLUGIN" \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 bash --norc --noprofile -c '. "$1" >/dev/null 2>&1; printf "%s" "${PF_RC:-unset}"' _ "$W2/$1" </dev/null
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
  rc=$(pf_rc contract.sh "$perm" "$2" "$3")
  case "$4" in ready|third-party) want=0 ;; *) want=nonzero ;; esac
  assert_true "… the block sets PF_RC" "[ '$rc' != unset ]"
  [ "$rc" != 0 ] && [ -n "$rc" ] && rc=nonzero
  assert_eq "… the run $( [ "$want" = 0 ] && echo proceeds || echo stops ) (PF_RC)" "$want" "$rc"
  rc2=$(pf_rc all.sh "$perm" "$2" "$3"); [ "$rc2" != 0 ] && [ -n "$rc2" ] && [ "$rc2" != unset ] && rc2=nonzero
  assert_eq "… and the same in idd-all Step 3b.0 (PF_RC)" "$want" "$rc2"
done
assert_grep "the contract stops when preflight prints nothing or not JSON" "沒有輸出" "$REF_TXT"
assert_grep "idd-all Step 3b.0 stops when preflight prints nothing or not JSON" "沒有輸出" "$(sed -n '/^#### Step 3b.0: Spec preflight/,/^#### Step 3b.0.5: /p' "$ALL")"

echo "spec-wrapper-contract: verify round 2 fixes in the text (idd-480-fix2)"
CL="$PLUGIN/skills/idd-close/SKILL.md"
assert_grep "a retroactive close skips Step 1.57" "1.57" "$(grep -F '| Step 0 / 1.5' "$CL")"
assert_grep "the verify spec context runs the two checks only with a git range" '[ -n "${BASE_SHA:-}" ]' "$SB"
assert_grep "the verify spec data sits in a per-run fence" 'SPEC_FENCE' "$SB"
assert_grep "the DA suffix gains the spec checks only when a spec context was built" '[ -n "$SPEC_BLOCK" ]' "$(grep -F 'DA_FOCUS_SUFFIX=' "$VERIFY" | tail -1; grep -F 'DA_FOCUS_SUFFIX="$DA_FOCUS_SUFFIX' "$VERIFY")"
assert_grep "verify-profiles says what of the default profile is unchanged" "lens 組合與輸入偵測" "$(read_file "$PROFILES")"
assert_grep "the diagnose hand-off runs the preflight before /spectra-discuss" "preflight" "$(sed -n '/Spectra tier 的追蹤 hand-off/,/為什麼需要這一行/p' "$PLUGIN/skills/idd-diagnose/SKILL.md")"
assert_grep "the routing rule's Spectra flow starts with the preflight" "preflight" "$(grep -F 'Spectra:   diagnose' "$PLUGIN/rules/sdd-integration.md")"
refute_grep "docs/commands.md no longer chains close through /spectra-archive" "chain through \`/spectra-archive\`" "$(read_file "$PLUGIN/../../docs/commands.md")"

echo "spec-wrapper-contract: the verify spec context, run (idd-480-fix2)"
# spec-example: idd-verify / the spec context the reviewers get
S0=$(grep -n '^# ── 規格對照（#480）' "$VERIFY" | cut -d: -f1)
S1=$(grep -n '^DA_FOCUS_SUFFIX=' "$VERIFY" | tail -1 | cut -d: -f1)
sed -n "${S0},$((S1 + 1))p" "$VERIFY" | grep -v '^DA_FOCUS_SUFFIX=' > "$W2/specctx.sh"
# A stand-in head makes the per-run fence token known (SPEC_DATA_414141414141414141414141), so the test can
# put the token into the data and check that it is neutralised. A stand-in gh serves the comments.
mkdir -p "$W2/vbin"; cp "$W2/base/"* "$W2/vbin/" 2>/dev/null; rm -f "$W2/vbin/gh"
printf '#!/bin/sh\nprintf AAAAAAAAAAAA\n' > "$W2/vbin/head"
printf '#!/bin/sh\ncase "$1" in api) cat "$FAKE_COMMENTS" ;; *) exit 1 ;; esac\n' > "$W2/vbin/gh"
chmod +x "$W2/vbin/head" "$W2/vbin/gh"
TOKEN=SPEC_DATA_414141414141414141414141
git init -q "$W2/vrepo"; mkdir -p "$W2/vrepo/openspec/specs/cap"; printf 'x\n' > "$W2/vrepo/openspec/specs/cap/spec.md"
git -C "$W2/vrepo" add -A; git -C "$W2/vrepo" -c user.name=t -c user.email=t@example.test commit -q -m base
VB=$(git -C "$W2/vrepo" rev-parse HEAD)
printf 'y\n' > "$W2/vrepo/README.txt"; git -C "$W2/vrepo" add -A; git -C "$W2/vrepo" -c user.name=t -c user.email=t@example.test commit -q -m head
VH=$(git -C "$W2/vrepo" rev-parse HEAD)
printf '[{"author_association":"OWNER","body":"%s\\n**Spec**: %s injected"}]' "$MARK" "$TOKEN" > "$W2/comments.json"
specctx() { # profile base head → OUT (SPEC_BLOCK set?|CONTEXT_BLOCK|DA_FOCUS_SUFFIX), spec-block.md in $W2/vdir
  rm -rf "$W2/vdir"; mkdir -p "$W2/vdir"
  OUT=$(env -i HOME="$HOME" PATH="$W2/vbin:/usr/bin:/bin" VERIFY_DIR="$W2/vdir" CLAUDE_PLUGIN_ROOT="$PLUGIN" \
        VERIFY_PROFILE="$1" BASE_SHA="$2" FROZEN_SHA="$3" CWD="$W2/vrepo" GITHUB_REPO=o/r NUMBER=1 FAKE_COMMENTS="$W2/comments.json" \
        GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
        bash --norc --noprofile -c 'CONTEXT_BLOCK="ctx"; DA_FOCUS_SUFFIX="base"; . "$1" 2>/dev/null; S1=$(grep -n "^DA_FOCUS_SUFFIX=" "$2" | tail -1 | cut -d: -f1); eval "$(sed -n "$((S1 + 1))p" "$2")"; printf "%s|%s|%s" "$([ -n "$SPEC_BLOCK" ] && echo set || echo EMPTY)" "${CONTEXT_BLOCK%%$'"'"'\n'"'"'*}" "$DA_FOCUS_SUFFIX"' _ "$W2/specctx.sh" "$VERIFY" </dev/null)
}
specctx prose "" ""
assert_eq "prose profile: no spec block, context and DA focus unchanged" "EMPTY|ctx|base" "$OUT"
assert_grep "… spec-block.md says it is not used" "not used" "$(cat "$W2/vdir/spec-block.md" 2>/dev/null)"
specctx code "" ""
SBN="$(cat "$W2/vdir/spec-block.md")"
assert_grep "code profile with no range in this shell: the link check reads error (fails closed)" 'Link check (spec-change.py links): {"status": "error"' "$SBN"
assert_grep "… and so does the archive check" 'Archive check at the reviewed head (spec-change.py archived): {"status": "error"' "$SBN"
assert_grep "… and the DA focus gains the spec checks" "Spec checks (#480)" "$OUT"
specctx code "$VB" "$VH"
SBF="$(cat "$W2/vdir/spec-block.md")"
assert_eq "code profile with a range: the token appears only in the header and the two fence lines" 3 "$(printf '%s\n' "$SBF" | grep -o "$TOKEN" | wc -l | tr -d ' ')"
assert_grep "… the token inside the data is neutralised" "[fence]" "$SBF"
assert_true "… the review rules come after the closing fence" \
  "[ $(printf '%s\n' "$SBF" | grep -n "^${TOKEN}>>>\$" | cut -d: -f1) -lt $(printf '%s\n' "$SBF" | grep -n '^Review rules' | cut -d: -f1) ]"
assert_grep "… and the DA focus gains the spec checks" "Spec checks (#480)" "$OUT"

echo "spec-wrapper-contract: verify round 3 fixes in the text (idd-480-fix3)"
S157="$(sed -n '/^### Step 1.57: /,/^### Step 1.6: /p' "$PLUGIN/skills/idd-close/SKILL.md")"
assert_grep "Step 1.57 checks the commit the fetch returned" "FETCH_HEAD" "$S157"
refute_grep "Step 1.57 does not need jq to choose the branch" "jq -r '.form" "$S157"
assert_grep "Step 1.57's result table stops on no output" "沒有輸出" "$S157"
assert_grep "the contract's link check stops when SPEC_BASE is empty" '[ -n "$SPEC_BASE" ]' "$REF_TXT"
refute_grep "the contract no longer explains the merge-base against origin/<default>" 'merge-base HEAD "origin/$DEFAULT_BRANCH"' "$REF_TXT"
refute_grep "idd-all no longer restates the old merge-base" 'merge-base HEAD origin/<default>' "$ALL_TXT"
refute_grep "the verify comment no longer claims the spec block holds no third-party prose" "不含別人的散文" "$V_TXT"
assert_grep "SPEC_FILES lists main specs only, not change deltas" "grep -v '/changes/'" "$SB"

echo "spec-wrapper-contract: contract steps 3 and 4, run (idd-480-fix4)"
# spec-example: spec-on-every-issue / contract steps 3 and 4 run as written
awk '/^## 3\. /{f=1} /^## 4\. /{f=0} f && /^```bash$/{b=1; buf=""; next} b && /^```$/{b=0; if (buf ~ /is_unattended/) {printf "%s", buf; exit} next} b {buf = buf $0 "\n"}' "$REF" > "$W2/step3.sh"
awk '/^## 4\. /{f=1} f && /^```bash$/{b=1; next} b && /^```$/{exit} b' "$REF" | sed 's/^CHANGE="<change 名稱>"$/CHANGE="idd-7-x"/' > "$W2/step4.sh"
mkdir -p "$W2/sbin" "$W2/s3cwd"
printf '#!/bin/sh\ncase "$1 $2" in\n  "list --parked") printf "{\\"parked\\": [%%s]}" "$FAKE_PARKED" ;;\n  "unpark "*) echo "$2" >> "$UNPARK_LOG" ;;\n  *) exit 1 ;;\nesac\n' > "$W2/sbin/spectra"
chmod +x "$W2/sbin/spectra"
step34() { # unattended(1|-) parked-json-items → S3 printed word, S4 unparked names
  rm -f "$W2/unpark.log"; : > "$W2/unpark.log"
  local ua=(); [ "$1" = 1 ] && ua=(IDD_ALL_UNATTENDED=1)
  S3=$(env -i HOME="$HOME" PATH="$W2/base:/usr/bin:/bin" "${ua[@]}" CWD="$W2/s3cwd" CLAUDE_PLUGIN_ROOT="$PLUGIN" \
       bash --norc --noprofile -c '. "$1" 2>/dev/null' _ "$W2/step3.sh" </dev/null | sed -n 's/^→ spec wrapper: //p')
  env -i HOME="$HOME" PATH="$W2/sbin:$W2/base:/usr/bin:/bin" FAKE_PARKED="$2" UNPARK_LOG="$W2/unpark.log" \
       bash --norc --noprofile -c '. "$1" >/dev/null 2>&1' _ "$W2/step4.sh" </dev/null
  S4=$(tr '\n' ' ' < "$W2/unpark.log" | sed 's/ $//'); [ -n "$S4" ] || S4=nothing
}
step34 1 '{"name": "idd-7-x"}'
assert_eq "steps 3-4: unattended, idd-7-x parked → prints unattended" unattended "$S3"
assert_eq "… unparks idd-7-x" idd-7-x "$S4"
step34 - '{"name": "idd-7-x"}'
assert_eq "steps 3-4: attended, idd-7-x parked → prints attended" attended "$S3"
assert_eq "… unparks idd-7-x" idd-7-x "$S4"
step34 - '{"name": "idd-8-y"}'
assert_eq "steps 3-4: only another change parked → prints attended" attended "$S3"
assert_eq "steps 3-4: only another change parked → unparks nothing" nothing "$S4"
step34 - ''
assert_eq "steps 3-4: nothing parked → prints attended" attended "$S3"
assert_eq "steps 3-4: nothing parked → unparks nothing" nothing "$S4"

echo "spec-wrapper-contract: verify round 4 fixes in the text (idd-480-fix4)"
S25="$(sed -n '/^### Step 2.5: /,/^### Step 3: /p' "$IMPL")"
refute_grep "Step 2.5 no longer skips the whole step when there is a change" "有 change 時跳過這一步" "$S25"
assert_grep "… a change skips only the TaskList; the routing table still applies" "只略過 TaskList" "$S25"
refute_grep "the contract no longer has the rejected form (idd-480-fix7)" '**Spec plan**: rejected' "$REF_TXT"
refute_grep "… nor a rejected branch in step 3" "proposed|rejected)" "$REF_TXT"
refute_grep "… nor says idd-plan creates the change first" "（\`idd-plan\` 會先建好）" "$REF_TXT"
assert_grep "the contract applies an existing change only when the newest plan names it" '`**Spec plan**: change <名稱>`' "$REF_TXT"
refute_grep "idd-plan no longer writes a rejected line on abort" '**Spec plan**: rejected' "$(grep -F '| Aborted |' "$PLAN")"
assert_grep "verify reads changed spec paths unquoted" 'core.quotePath=false' "$SB"

echo "spec-wrapper-contract: an existing change is checked against the Spec plan line, run (idd-480-fix4)"
awk '/^## 3\. /{f=1} /^## 4\. /{f=0} f && /^```bash$/{b=1; buf=""; next} b && /^```$/{b=0; if (buf ~ /spec-change.py" plan/) {printf "%s", buf; exit} next} b {buf = buf $0 "\n"}' "$REF" > "$W2/exist.sh"
assert_true "contract step 3 has a bash block that runs spec-change.py plan" "[ -s '$W2/exist.sh' ]"
# spec-example: spec-on-every-issue / an open change is checked against the newest plan
mkdir -p "$W2/ebin"
printf '#!/bin/sh\n[ "${FAKE_LIST:-x}" = fail ] && { echo "Not initialized" >&2; exit 1; }\n[ "${FAKE_LIST:-x}" = garbage ] && { echo "not json"; exit 0; }\ncase "$1 $2" in\n  "list --json") if [ "${FAKE_LIST:-x}" = none ]; then printf "{\\"changes\\": []}"; else printf "{\\"changes\\": [{\\"name\\": \\"idd-7-x\\"}]}"; fi ;;\n  "list --parked") printf "{\\"parked\\": []}" ;;\n  *) exit 1 ;;\nesac\n' > "$W2/ebin/spectra"
printf '#!/bin/sh\ncase "$1" in api) cat "$FAKE_COMMENTS" ;; *) exit 1 ;; esac\n' > "$W2/ebin/gh"
chmod +x "$W2/ebin/spectra" "$W2/ebin/gh"
exist_run() { # list-mode(x|none|fail|garbage) comments-json → the "→ spec step 3:" verdict
  printf '%s' "$2" > "$W2/ec.json"
  env -i HOME="$HOME" PATH="$W2/ebin:$W2/base:/usr/bin:/bin" FAKE_LIST="$1" FAKE_COMMENTS="$W2/ec.json" GITHUB_REPO=o/r NUMBER=7 CLAUDE_PLUGIN_ROOT="$PLUGIN" \
    bash --norc --noprofile -c '. "$1" 2>/dev/null' _ "$W2/exist.sh" </dev/null | sed -n 's/^→ spec step 3: //p'
}
pl() { printf '[{"author_association":"OWNER","body":"## Implementation Plan (Plan tier)\\n\\n**Spec plan**: %s"}]' "$1"; }
assert_eq "step 3: no open change → propose" propose "$(exist_run none "$(pl 'change idd-7-x')")"
assert_eq "step 3: idd-7-x and a plan naming it → go on" "go on with idd-7-x" "$(exist_run x "$(pl 'change idd-7-x')")"
v=$(exist_run x "$(pl 'proposed (change idd-7-x)')"); assert_grep "step 3: proposed → a stop" "stop:" "$v"; assert_grep "… that names /idd-plan" "/idd-plan" "$v"
v=$(exist_run x "$(pl 'change idd-7-y')"); assert_grep "step 3: a plan naming another change → a stop" "stop:" "$v"; assert_grep "… that names /idd-plan (spectra-verify on idd-480-fix5)" "/idd-plan" "$v"
assert_grep "step 3: no plan comment → a stop" "stop:" "$(exist_run x '[]')"
assert_grep "step 3: the change list cannot be read → a stop, not propose" "stop:" "$(exist_run fail "$(pl 'change idd-7-x')")"
assert_grep "step 3: the change list is not JSON → a stop, not propose (spectra-verify on idd-480-fix5)" "stop:" "$(exist_run garbage "$(pl 'change idd-7-x')")"
S06="$(sed -n '/^### Step 0.6: /,/^### Step 1: /p' "$IMPL")"
assert_grep "idd-implement checks an existing change with spec-change.py plan" 'spec-change.py" plan' "$S06"
assert_grep "… before Step 2 posts anything" "Step 2 貼" "$S06"
refute_grep "… and no longer names the rejected form" "rejected" "$S06"
assert_grep "idd-implement offers /idd-plan for a Plan-tier issue before it proposes" "/idd-plan" "$S06"
assert_grep "idd-plan writes the Spec plan line for an exemption too" '**Spec plan**: no behaviour change' "$(read_file "$PLAN")"
assert_grep "idd-plan writes the third-party form" '**Spec plan**: third-party clone' "$(read_file "$PLAN")"

echo "spec-wrapper-contract: verify round 5 fixes in the text (idd-480-fix5)"
assert_grep "idd-plan writes proposed before plan mode" '**Spec plan**: proposed (change' "$(read_file "$PLAN")"
assert_grep "… and changes it to change once approved" "核准後" "$(grep -F '**Spec plan**: proposed' "$PLAN" | head -1)"
assert_grep "idd-implement posts its plan line before it proposes" "先貼下面的 Implementation Plan" "$(sed -n '/^### Step 2: /,/^### Step 3/p' "$IMPL")"
assert_grep "a fix round posts its plan line before it proposes the fix change" '**Spec plan**: change idd-<N>-fix<k>' "$(sed -n '/^## 7\. /,$p' "$REF")"
C25="$(grep -F '若使用者直接呼叫 `/idd-implement` 而 Complexi' "$IMPL")"
assert_grep "Step 2.5 no longer asks the Plan question a second time" "已在 Step 0.6、propose 之前問過" "$C25"
refute_grep "… and no longer gives the instruction it cancels" "AskUserQuestion 確認 continue/abort" "$C25"
refute_grep "… nor keeps the exemption-only wording" "宣告豁免的 issue 照這一列問" "$C25"
assert_grep "verify lists changed spec paths NUL-separated" 'diff -z' "$SB"

echo "spec-wrapper-contract: spectra-verify warnings on idd-480-fix5"
refute_grep "the contract no longer claims every plan line comes before the propose" "plan 行一律在 propose 之前貼出" "$(read_file "$REF")"
assert_grep "… and says the Plan tier proposes only after approval" "核准之後才由 \`idd-implement\` propose" "$(read_file "$REF")"
assert_grep "idd-implement sends a proposed change to /idd-plan too" '`proposed`' "$(sed -n '/^### Step 0.6: /,/^### Step 1: /p' "$IMPL")"
assert_grep "idd-all's fix-round note posts the plan line first" '**Spec plan**: change idd-<N>-fix<k>' "$(grep -F '**修正也留下規格（#480）**' "$ALL")"

echo "spec-wrapper-contract: idd-480-fix6 checks that remain after fix7"
refute_grep "idd-implement's note no longer asks the Plan question as before" "照舊先問要不要改走" "$(read_file "$IMPL")"
v=$(exist_run x "$(pl 'proposed (change idd-7-y)')"); assert_grep "step 3: a proposed plan naming another change → the stop names it" "idd-7-y" "$v"; assert_grep "… and the open change" "idd-7-x" "$v"

refute_grep "nor does idd-diagnose's route table" "審查 proposal 與 tasks" "$(read_file "$PLUGIN/skills/idd-diagnose/SKILL.md")"

echo "spec-wrapper-contract: the attended Plan tier approves the Implementation Plan (idd-480-fix7)"
S2I="$(sed -n '/^### Step 2: /,/^### Step 3/p' "$IMPL")"
assert_grep "idd-implement from idd-plan proposes with the approved name" "從 \`idd-plan\` 來" "$S2I"
assert_grep "… in the light form" "輕量形式" "$S2I"
refute_grep "idd-implement no longer says idd-plan approved the change" "（\`idd-plan\` 核准過的）" "$(read_file "$IMPL")"
refute_grep "spec-change.py has no rejected form" "REJECTED_RE" "$(read_file "$PLUGIN/scripts/spec-change.py")"
SDD="$(read_file "$PLUGIN/rules/sdd-integration.md")"
refute_grep "sdd-integration's Plan flow no longer approves the proposal" "user approves proposal + tasks" "$SDD"
assert_grep "… it approves the Implementation Plan and proposes in idd-implement" "user approves the Implementation Plan" "$SDD"
DG="$(read_file "$PLUGIN/skills/idd-diagnose/SKILL.md")"
refute_grep "idd-diagnose's route table no longer has the plan mode review the proposal" "審查 proposal、spec delta 與 tasks" "$DG"
assert_grep "… it reviews the Implementation Plan" "EnterPlanMode 審查 Implementation Plan" "$DG"
refute_grep "the CHANGELOG no longer says idd-plan presents the proposal" "presents the proposal, the spec delta and the tasks" "$(read_file "$PLUGIN/CHANGELOG.md")"
refute_grep "idd-plan no longer says the Plan tier produces no spec artifacts" "Plan tier 不會產出 spec/proposal/tasks artifacts" "$(read_file "$PLAN")"

echo "spec-wrapper-contract: spectra-verify warnings on idd-480-fix7"
assert_eq "the contract test is one file, not two pasted together" 1 "$(grep -c '^#!' "$HERE/test.sh")"
refute_grep "the README no longer says idd-plan presents the proposal" "the Spectra proposal and tasks" "$(read_file "$PLUGIN/README.md")"
P139="$(grep -F '先寫規格（#480' "$PLAN")"
# Since #499 the lookup is a bash block of Step 2; the note above it only names the line the block prints.
awk '/^### Step 2: /{f=1} /^### Step 2\.5: /{f=0} f && /^```bash$/{b=1; buf=""; next} b && /^```$/{b=0; if (buf ~ /idd-plan change lookup/) {printf "%s", buf; exit} next} b {buf = buf $0 "\n"}' "$PLAN" > "$W2/plookup.sh"
assert_grep "idd-plan looks up the issue's open change in the change list" "spectra list --parked --json" "$(cat "$W2/plookup.sh")"
assert_grep "… and its Step 2 note names the line the block prints" "→ idd-plan change lookup:" "$P139"
assert_grep "… and may run spectra" "Bash(spectra:*)" "$(sed -n '1,20p' "$PLAN")"
refute_grep "the Aborted row no longer claims there is no change yet" "這時還沒有 change" "$(grep -F '| Aborted |' "$PLAN")"
S6P="$(sed -n '/^### Step 6: /,/^### Step 7: /p' "$PLAN")"
assert_grep "the chain example passes the change name" '--spec-change' "$(grep -F 'Skill(skill="issue-driven-dev:idd-implement"' "$PLAN")"
# Until #499 this refuted the literal "Step 2: SKIP", which the file no longer held, so it could not fail while two
# other lines said the same thing in other words. The property: no line of idd-plan says that a Step 2 is skipped
# (Step 2.5 skipping its TaskList, and a meeting issue skipping Step 6, are other statements).
step2_skipped() { # files → file:line: text, for each line with a claim that a Step 2 is skipped
  # "Step 2 is not skipped" states the opposite, but only for its own skip word: the negation has to stand
  # right before it. A negated clause elsewhere on the line does not excuse a claim (#499, verify round 1).
  python3 - "$@" <<'PY'
import re, sys
SKIPW = r"(跳過|略過|不跑|[Ss]kips?|skipped|SKIP)"
claims = [re.compile(SKIPW + r"[^|]{0,15}Step 2([^.0-9]|$)"), re.compile(r"Step 2[^|.0-9]{0,6}(SKIP|[Ss]kip)")]
negated = re.compile(r"(不|沒有|未|not |never |n.t )(會|被)*$")
for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            if any(not negated.search(line[: m.start(1)]) for c in claims for m in c.finditer(line)):
                print(f"{path}:{n}: {line.strip()[:100]}")
PY
}
assert_eq "no line of idd-plan says a Step 2 is skipped" "" "$(step2_skipped "$PLAN")"
assert_grep "… it says idd-implement proposes in its Step 2" "在它的 Step 2" "$S6P"

echo "spec-wrapper-contract: idd-plan's lookup of an open change, run (#499)"
# spec-example: spec-on-every-issue / idd-plan looks up the open change of the issue
# The block extracted above ($W2/plookup.sh) is run as written. A stand-in spectra serves $FAKE_ACTIVE and
# $FAKE_PARKED (JSON items), fails the call named by $FAKE_FAIL, prints $FAKE_RAW or $FAKE_RAW_PARKED in place of
# the active or the parked list, and logs every call; a stand-in gh only logs.
assert_true "idd-plan Step 2 has a bash block that prints the lookup line" "[ -s '$W2/plookup.sh' ]"
mkdir -p "$W2/lbin"
printf '#!/bin/sh\necho "spectra $*" >> "$CALL_LOG"\ncase "$1 $2" in\n  "list --json") [ "${FAKE_FAIL:-}" = list ] && { echo "Not initialized" >&2; exit 1; }\n    if [ "${FAKE_RAW+set}" = set ]; then printf "%%s" "$FAKE_RAW"; else printf "{\\"changes\\": [%%s]}" "${FAKE_ACTIVE:-}"; fi ;;\n  "list --parked") [ "${FAKE_FAIL:-}" = parked ] && { echo "boom" >&2; exit 1; }\n    if [ "${FAKE_RAW_PARKED+set}" = set ]; then printf "%%s" "$FAKE_RAW_PARKED"; else printf "{\\"parked\\": [%%s]}" "${FAKE_PARKED:-}"; fi ;;\n  *) exit 1 ;;\nesac\n' > "$W2/lbin/spectra"
printf '#!/bin/sh\necho "gh $*" >> "$CALL_LOG"\nexit 1\n' > "$W2/lbin/gh"
chmod +x "$W2/lbin/spectra" "$W2/lbin/gh"
plook() { # issue-number [VAR=value …] → what the block prints after the prefix; its output is left in plook.out, its calls in plook.log
  local n="$1"; shift; : > "$W2/plook.log"
  env -i HOME="$HOME" PATH="$W2/lbin:$W2/base:/usr/bin:/bin" CALL_LOG="$W2/plook.log" NUMBER="$n" "$@" \
    bash --norc --noprofile -c '. "$1" 2>/dev/null' _ "$W2/plookup.sh" </dev/null > "$W2/plook.out"
  sed -n 's/^→ idd-plan change lookup: //p' "$W2/plook.out"
}
assert_eq "lookup: issue 7, idd-7-x active → its name" "idd-7-x" "$(plook 7 FAKE_ACTIVE='{"name": "idd-7-x"}')"
assert_eq "lookup: issue 7, idd-7-x parked → its name" "idd-7-x" "$(plook 7 FAKE_PARKED='{"name": "idd-7-x"}')"
assert_eq "lookup: issue 7, nothing open → new" "new" "$(plook 7)"
assert_eq "lookup: issue 7, idd-7-a active and idd-7-b parked → the active one" "idd-7-a" "$(plook 7 FAKE_ACTIVE='{"name": "idd-7-a"}' FAKE_PARKED='{"name": "idd-7-b"}')"
assert_eq "… on one line: the parked one is not printed after it" 1 "$(wc -l < "$W2/plook.out" | tr -d ' ')"
assert_eq "lookup: issue 7, only idd-70-x open → new" "new" "$(plook 7 FAKE_ACTIVE='{"name": "idd-70-x"}')"
assert_eq "lookup: issue 70, only idd-7-x open → new" "new" "$(plook 70 FAKE_ACTIVE='{"name": "idd-7-x"}')"
v=$(plook 7 FAKE_FAIL=list); assert_eq "lookup: the list command fails → a stop" "stop:" "${v%% *}"
v=$(plook 7 FAKE_FAIL=parked); assert_eq "lookup: the parked list command fails → a stop" "stop:" "${v%% *}"
v=$(plook 7 FAKE_RAW='not json'); assert_eq "lookup: the list is text that is not JSON → a stop" "stop:" "${v%% *}"
v=$(plook 7 FAKE_RAW_PARKED='not json'); assert_eq "lookup: the parked list is text that is not JSON → a stop" "stop:" "${v%% *}"
# a boundary the table does not list: an open change must not be named when the other list cannot be read
v=$(plook 7 FAKE_FAIL=parked FAKE_ACTIVE='{"name": "idd-7-x"}'); assert_eq "lookup: idd-7-x active but the parked list fails → a stop, not the name" "stop:" "${v%% *}"
plook 7 FAKE_ACTIVE='{"name": "idd-7-x"}' >/dev/null
assert_eq "lookup: the block prints exactly one line" 1 "$(wc -l < "$W2/plook.out" | tr -d ' ')"
assert_eq "lookup: it runs the two list commands and nothing else (no gh, no plan check)" "spectra list --json|spectra list --parked --json" "$(paste -s -d '|' "$W2/plook.log")"
refute_grep "idd-plan's block does not run the plan check" 'spec-change.py" plan' "$(cat "$W2/plookup.sh")"
# The last six rows of the Example (#499, verify round 1): NUMBER is what the block filters the names with, and each
# Bash call starts a new shell. Without it the filter matches nothing and the block would report `new`; with `.*` it
# would name another issue's change. The block has to stop, and to look nothing up.
plook_env() { # [VAR=value …] → like plook, but NUMBER is only what the caller passes; calls are appended to plook.all
  : > "$W2/plook.log"
  env -i HOME="$HOME" PATH="$W2/lbin:$W2/base:/usr/bin:/bin" CALL_LOG="$W2/plook.log" "$@" \
    bash --norc --noprofile -c '. "$1" 2>/dev/null' _ "$W2/plookup.sh" </dev/null > "$W2/plook.out"
  cat "$W2/plook.log" >> "$W2/plook.all"
  sed -n 's/^→ idd-plan change lookup: //p' "$W2/plook.out"
}
: > "$W2/plook.all"
v=$(plook_env FAKE_ACTIVE='{"name": "idd-7-x"}'); assert_eq "lookup: NUMBER not set, idd-7-x open → a stop, not new" "stop:" "${v%% *}"
assert_eq "… on exactly one line" 1 "$(wc -l < "$W2/plook.out" | tr -d ' ')"
v=$(plook_env NUMBER= FAKE_ACTIVE='{"name": "idd-7-x"}'); assert_eq "lookup: NUMBER empty, idd-7-x open → a stop" "stop:" "${v%% *}"
v=$(plook_env NUMBER=abc FAKE_ACTIVE='{"name": "idd-7-x"}'); assert_eq "lookup: NUMBER is abc → a stop" "stop:" "${v%% *}"
v=$(plook_env 'NUMBER=#7' FAKE_ACTIVE='{"name": "idd-7-x"}'); assert_eq "lookup: NUMBER is #7 → a stop" "stop:" "${v%% *}"
v=$(plook_env 'NUMBER=.*' FAKE_ACTIVE='{"name": "idd-7-x"}'); assert_eq "lookup: NUMBER is .* → a stop, not another issue's change" "stop:" "${v%% *}"
v=$(plook_env NUMBER=07 FAKE_ACTIVE='{"name": "idd-7-x"}'); assert_eq "lookup: NUMBER is 07 → a stop, not new (idd-07- matches nothing)" "stop:" "${v%% *}"
assert_eq "lookup: in those six cases no list command runs" "" "$(cat "$W2/plook.all")"
# The same lookup lives in the contract's step 3 (run by idd-implement). The two copies are compared line for line,
# so a change to one that is not made to the other fails here (one implementation for both is a follow-up of #499).
lookup_lines() { # file → from the line that lists the changes to the line that sets EXISTING
  awk '/^if A=\$\(spectra list --json/{f=1} f {print} f && /^  EXISTING=\$\(/{exit}' "$1"
}
awk '/^## 3\. /{f=1} /^## 4\. /{f=0} f' "$REF" > "$W2/step3.md"
assert_eq "the contract's step 3 lookup is three lines" 3 "$(lookup_lines "$W2/step3.md" | wc -l | tr -d ' ')"
assert_eq "idd-plan's lookup lines are those of the contract's step 3" "$(lookup_lines "$W2/step3.md")" "$(lookup_lines "$W2/plookup.sh")"
STOP_REF="$(grep -o 'stop: the change list could not be read[^"]*' "$W2/step3.md" | sed -n '1p')"
assert_true "the contract's step 3 has the stop reason" "[ -n '$STOP_REF' ]"
assert_eq "… and idd-plan's block gives the same reason" "$STOP_REF" "$(grep -o 'stop: the change list could not be read[^"]*' "$W2/plookup.sh" | sed -n '1p')"

echo "spec-wrapper-contract: round-8 wording (#499)"
# (a) A `proposed` plan line stops idd-implement only when the issue has an open change. No sentence may say that
#     idd-implement will not propose or apply on seeing `proposed` without that condition in the same sentence.
unconditional_proposed() { # files → file:line: sentence, for each sentence that makes the unconditional claim
  python3 - "$@" <<'PY'
import re, sys
neg = re.compile(r"(不會|不再|不)\s*(propose|apply)|(will not|does not|never|neither)[^.]{0,40}(propose|apply)", re.I)
cond = re.compile(r"(?<!沒)有開著的|\bopen change\b")
for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            for s in re.split(r"[。；;|]|(?<=[.!?])\s+", line):
                if re.search(r"\bproposed\b", s) and "idd-implement" in s and neg.search(s) and not cond.search(s):
                    print(f"{path}:{n}: {s.strip()[:100]}")
PY
}
assert_eq "no sentence says idd-implement will not propose on seeing proposed, whatever the open changes" "" "$(unconditional_proposed "$PLAN" "$IMPL" "$REF" "$PLUGIN/README.md")"
ABR="$(grep -F '| Aborted |' "$PLAN")"
assert_grep "the Aborted row says what an open change does" "開著的" "$ABR"
assert_grep "… points at the contract's step 3" "契約第 3 步" "$ABR"
assert_grep "… and says where the missing guard is tracked" "#496" "$ABR"
# (b) "the change is proposed only after approval" holds for the run that goes through idd-plan; a sentence that
#     says it has to carry that limit, whether or not it names a tier (the contract's plan-line sentence does
#     not). A sentence about a run that was NOT approved does not carry it. The spec's own sentence is changed
#     by the change's delta, not checked here.
unlimited_only_after() { # files → file:line: sentence
  python3 - "$@" <<'PY'
import re, sys
only_after = re.compile(r"only after|核准之後才|核准後才|核准之後\s*propose", re.I)
limit = re.compile(r"through `idd-plan`|經 `idd-plan`|(?<!沒)有核准")
for path in sys.argv[1:]:
    with open(path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            for s in re.split(r"[。；;|]|(?<=[.!?])\s+", line):
                if re.search(r"propos", s, re.I) and only_after.search(s) and not limit.search(s):
                    print(f"{path}:{n}: {s.strip()[:100]}")
PY
}
assert_eq "every 'proposed only after approval' sentence names the run it holds for" "" "$(unlimited_only_after "$REF" "$PLAN" "$IMPL")"
# The checks above are checked with sentences they have to catch (#499, verify round 1): a check that has never
# been shown a failing sentence may pass for a reason other than the one it names.
caught() { [ -n "$1" ] && echo caught || echo missed; }
printf '%s\n' 'Plan tier 沒有核准的 run 也在核准之後才 propose。' > "$W2/fx-b1.md"
assert_eq "check (b) catches a sentence that says the run was NOT approved" caught "$(caught "$(unlimited_only_after "$W2/fx-b1.md")")"
printf '%s\n' '`idd-implement` 與修正輪在 propose 之前貼 plan 行；plan 行由 `idd-plan` 在核准時寫成 `change <名稱>`，核准之後才由 `idd-implement` propose。' > "$W2/fx-b2.md"
assert_eq "check (b) catches the contract's plan-line sentence once its limit is taken out" caught "$(caught "$(unlimited_only_after "$W2/fx-b2.md")")"
printf '%s\n' '`idd-implement` 與修正輪在 propose 之前貼 plan 行；經 `idd-plan` 的 run，plan 行由 `idd-plan` 在核准時寫成 `change <名稱>`，核准之後才由 `idd-implement` propose。' > "$W2/fx-b3.md"
assert_eq "… and lets it through with the limit" missed "$(caught "$(unlimited_only_after "$W2/fx-b3.md")")"
printf '%s\n' '| x | Step 2.5 不會跳過；`idd-implement` 跳過 Step 2 |' > "$W2/fx-s1.md"
assert_eq "the Step 2 check catches a skip claim that shares its line with a negated clause" caught "$(caught "$(step2_skipped "$W2/fx-s1.md")")"
printf '%s\n' '這一句不會漏掉別的，但 `idd-implement` 跳過 Step 2。' > "$W2/fx-s3.md"
assert_eq "… and one whose sentence negates something else" caught "$(caught "$(step2_skipped "$W2/fx-s3.md")")"
printf '%s\n' '帶 `--spec-change` 時 `idd-implement` 沒有跳過 Step 2。' > "$W2/fx-s2.md"
assert_eq "… and lets a plain 'Step 2 is not skipped' through" missed "$(caught "$(step2_skipped "$W2/fx-s2.md")")"
assert_grep "the contract says the approved plan is not edited and the tasks go to a separate comment" '## Spec tasks (change <名稱>)' "$REF_TXT"
# (c) idd-implement Step 2: where the tasks go is decided by the heading of the newest plan, not by "its own comment"
#     (idd-plan and idd-implement post from one account).
S2I="$(sed -n '/^### Step 2: /,/^### Step 3/p' "$IMPL")"
assert_grep "Step 2 decides by the Plan-tier heading" '## Implementation Plan (Plan tier)' "$S2I"
assert_grep "… names the heading of the separate comment" '## Spec tasks (change <名稱>)' "$S2I"
assert_grep "… whose task lines carry no checkbox" "不帶 checkbox" "$S2I"
assert_grep "… and which is posted once" "就不再貼" "$S2I"
assert_eq "the list is replaced only in the plan this skill posted itself" "" "$(printf '%s\n' "$S2I" | grep -F '清單改成' | grep -vF '自己貼的')"
refute_grep "Step 2 does not add a second Spec plan line to a plan that has one" '並加一行 `**Spec plan**: change' "$S2I"
# (c2) Which comments count (#499, verify round 1): the plan whose heading decides, and a Spec tasks comment that is
#      already there, are comments by accounts with write access — the selection of spec-change.py plan.
assert_grep "Step 2 decides by the newest plan" '最新那則 plan' "$S2I"
assert_eq "every line of Step 2 that picks the newest plan names accounts with write access" "" "$(printf '%s\n' "$S2I" | grep -F '最新那則 plan' | grep -vF '有寫入權')"
S2L="$(printf '%s\n' "$S2I" | grep -F '最新那則 plan')"
assert_grep "… and names the command that makes the same selection" 'spec-change.py plan' "$S2L"
lacking() { # needle required file… → file:line: sentence, for each sentence that has the needle without the required words
  python3 - "$@" <<'PY'
import re, sys
needle, required = sys.argv[1], sys.argv[2]
for path in sys.argv[3:]:
    with open(path, encoding="utf-8") as fh:
        for n, line in enumerate(fh, 1):
            for s in re.split(r"[。；;|]|(?<=[.!?])\s+", line):
                if needle in s and required not in s:
                    print(f"{path}:{n}: {s.strip()[:100]}")
PY
}
printf '%s\n' "$S2I" > "$W2/step2.md"
assert_eq "every sentence of Step 2 that says the comment is not posted again names accounts with write access" "" "$(lacking '就不再貼' '有寫入權' "$W2/step2.md")"
assert_eq "… and so does every such sentence of the contract" "" "$(lacking '就不再貼' '有寫入權' "$REF")"
printf '%s\n' '另貼一則 `## Spec tasks` 留言，已經有就不再貼；`spec-change.py plan` 讀的是有寫入權的帳號貼的留言。' > "$W2/fx-a1.md"
assert_eq "… a sentence without them is caught even when the same line names them later" caught "$(caught "$(lacking '就不再貼' '有寫入權' "$W2/fx-a1.md")")"
refute_grep "Step 2 does not say that the author of a comment is ignored" '不看留言是誰貼的' "$S2I"
# (e) idd-plan's hand-over says the same
assert_grep "idd-plan Step 6 says the tasks go to a separate Spec tasks comment" '## Spec tasks (change <名稱>)' "$S6P"

print_summary spec-wrapper-contract
