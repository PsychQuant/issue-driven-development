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
assert_grep "idd-plan proposes through spectra-propose" 'Skill(skill="spectra-propose"' "$PLAN_TXT"
assert_grep "idd-plan presents the proposal, the spec delta and the tasks for approval" "proposal、spec delta、tasks" "$(sed -n '/^### Step 4: /,/^### Step 5: /p' "$PLAN")"
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
assert_grep "the contract states the Spec plan line and its rejected form" '**Spec plan**: rejected' "$REF_TXT"
assert_grep "the contract applies an existing change only when the newest plan names it" '`**Spec plan**: change <名稱>`' "$REF_TXT"
assert_grep "idd-plan marks an aborted plan's change as rejected" '**Spec plan**: rejected' "$(grep -F '| Aborted |' "$PLAN")"
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
v=$(exist_run x "$(pl 'rejected (change idd-7-x left parked)')"); assert_grep "step 3: rejected → a stop" "stop:" "$v"; assert_grep "… that names /idd-plan" "/idd-plan" "$v"
v=$(exist_run x "$(pl 'change idd-7-y')"); assert_grep "step 3: a plan naming another change → a stop" "stop:" "$v"; assert_grep "… that names /idd-plan (spectra-verify on idd-480-fix5)" "/idd-plan" "$v"
assert_grep "step 3: no plan comment → a stop" "stop:" "$(exist_run x '[]')"
assert_grep "step 3: the change list cannot be read → a stop, not propose" "stop:" "$(exist_run fail "$(pl 'change idd-7-x')")"
assert_grep "step 3: the change list is not JSON → a stop, not propose (spectra-verify on idd-480-fix5)" "stop:" "$(exist_run garbage "$(pl 'change idd-7-x')")"
S06="$(sed -n '/^### Step 0.6: /,/^### Step 1: /p' "$IMPL")"
assert_grep "idd-implement checks an existing change with spec-change.py plan" 'spec-change.py" plan' "$S06"
assert_grep "… before Step 2 posts anything" "Step 2 貼" "$S06"
assert_grep "… and stops on a rejected one" "rejected" "$S06"
assert_grep "idd-implement offers /idd-plan for a Plan-tier issue before it proposes" "/idd-plan" "$S06"
assert_grep "idd-plan writes the Spec plan line for an exemption too" '**Spec plan**: no behaviour change' "$(read_file "$PLAN")"
assert_grep "idd-plan writes the third-party form" '**Spec plan**: third-party clone' "$(read_file "$PLAN")"
assert_grep "idd-plan re-presents a rejected change for approval" "再呈現" "$(read_file "$PLAN")"

echo "spec-wrapper-contract: verify round 5 fixes in the text (idd-480-fix5)"
assert_grep "idd-plan writes proposed before plan mode" '**Spec plan**: proposed (change' "$(read_file "$PLAN")"
assert_grep "… and changes it to change once approved" "核准後" "$(grep -F '**Spec plan**: proposed' "$PLAN" | head -1)"
assert_grep "idd-implement posts its plan line before it proposes" "先貼下面的 Implementation Plan" "$(sed -n '/^### Step 2: /,/^### Step 3/p' "$IMPL")"
assert_grep "a fix round posts its plan line before it proposes the fix change" '**Spec plan**: change idd-<N>-fix<k>' "$(sed -n '/^## 7\. /,$p' "$REF")"
C25="$(grep -F '若使用者直接呼叫 `/idd-implement` 而 Complexi' "$IMPL")"
assert_grep "Step 2.5 no longer asks the Plan question a second time" "已在 Step 0.6、propose 之前問過" "$C25"
refute_grep "… and no longer gives the instruction it cancels" "AskUserQuestion 確認 continue/abort" "$C25"
refute_grep "… nor keeps the exemption-only wording" "宣告豁免的 issue 照這一列問" "$C25"
refute_grep "the Abort comment no longer suggests re-diagnosing" "建議重新 \`/idd-diagnose" "$(grep -F '| Aborted |' "$PLAN")"
assert_grep "verify lists changed spec paths NUL-separated" 'diff -z' "$SB"

echo "spec-wrapper-contract: spectra-verify warnings on idd-480-fix5"
P139="$(grep -F '先寫規格（#480' "$PLAN")"
assert_grep "idd-plan presents a proposed change again (not only a rejected one)" '`proposed`' "$P139"
assert_grep "… and an open change that no plan names" "沒有 plan 點名它" "$P139"
assert_grep "… as the only approval path for an open change" "唯一的核准路徑" "$P139"
refute_grep "the contract no longer claims every plan line comes before the propose" "plan 行一律在 propose 之前貼出" "$(read_file "$REF")"
assert_grep "… and says idd-plan posts its plan after the propose" '`idd-plan` 在 propose 之後才貼' "$(read_file "$REF")"
assert_grep "idd-implement sends a proposed change to /idd-plan too" '`proposed`' "$(sed -n '/^### Step 0.6: /,/^### Step 1: /p' "$IMPL")"
assert_grep "idd-all's fix-round note posts the plan line first" '**Spec plan**: change idd-<N>-fix<k>' "$(grep -F '**修正也留下規格（#480）**' "$ALL")"

echo "spec-wrapper-contract: Plan-tier approval covers the change as it will be applied, run (idd-480-fix6)"
awk '/^### Step 3\.5: /{f=1} /^### Step 4: /{f=0} f && /^```bash$/{b=1; buf=""; next} b && /^```$/{b=0; if (buf ~ /spectra instructions apply/) {printf "%s", buf; exit} next} b {buf = buf $0 "\n"}' "$PLAN" > "$W2/s35.sh"
assert_true "idd-plan Step 3.5 has a bash block that reads spectra instructions apply" "[ -s '$W2/s35.sh' ]"
sed -i.bak 's/^CHANGE="<change 名稱>"$/CHANGE=idd-7-x/' "$W2/s35.sh"
assert_grep "… whose CHANGE placeholder the test can fill" "CHANGE=idd-7-x" "$(cat "$W2/s35.sh")"
# spec-example: spec-on-every-issue / the step-3.5 block
mkdir -p "$W2/s35bin"
printf '#!/bin/sh\ncase "$1 $2" in\n  "list --parked") if [ "$FAKE_STATE" = parked ]; then printf "{\\"parked\\": [{\\"name\\": \\"idd-7-x\\"}]}"; else printf "{\\"parked\\": []}"; fi ;;\n  "unpark idd-7-x") [ "$FAKE_UNPARK" = fail ] && exit 1; : > "$FAKE_MARK"; echo "Unparked change: idd-7-x" ;;\n  "instructions apply") [ "$FAKE_INSTR" = fail ] && exit 1; printf "{\\"changeDir\\": \\"%%s\\"}" "$FAKE_DIR" ;;\n  *) exit 1 ;;\nesac\n' > "$W2/s35bin/spectra"
chmod +x "$W2/s35bin/spectra"
s35() { # state(parked|active) unpark(ok|fail) instr(ok|fail) delta(yes|no) → stdout, then a line "ERR:<stderr>", then "UNPARKED" when unpark ran
  rm -rf "$W2/s35dir" "$W2/s35mark"; mkdir -p "$W2/s35dir"
  printf '## Why\n' > "$W2/s35dir/proposal.md"; printf '## 1. A\n\n- [ ] 1.1 a\n' > "$W2/s35dir/tasks.md"
  [ "$4" = yes ] && { mkdir -p "$W2/s35dir/specs/demo"; printf '## ADDED Requirements\n' > "$W2/s35dir/specs/demo/spec.md"; }
  env -i HOME="$HOME" PATH="$W2/s35bin:/usr/bin:/bin" FAKE_STATE="$1" FAKE_UNPARK="$2" FAKE_INSTR="$3" FAKE_DIR="$W2/s35dir" FAKE_MARK="$W2/s35mark" \
    bash --norc --noprofile -c '. "$1"' _ "$W2/s35.sh" 2>"$W2/s35err" </dev/null
  printf 'ERR:%s\n' "$(cat "$W2/s35err")"
  [ -e "$W2/s35mark" ] && echo UNPARKED
  return 0
}
v=$(s35 parked ok ok yes)
assert_grep "step 3.5: parked → prints the change directory" "→ change files: $W2/s35dir" "$v"
assert_eq "… and its three files" 3 "$(printf '%s\n' "$v" | grep -c "^$W2/s35dir/.*\.md$")"
assert_grep "… after taking it out of the parked state" "UNPARKED" "$v"
v=$(s35 active ok ok yes)
assert_grep "step 3.5: active → prints the change directory" "→ change files: $W2/s35dir" "$v"
assert_eq "… and its three files" 3 "$(printf '%s\n' "$v" | grep -c "^$W2/s35dir/.*\.md$")"
refute_grep "… without an unpark" "UNPARKED" "$v"
v=$(s35 parked fail ok yes)
refute_grep "step 3.5: the unpark fails → no file list" "→ change files:" "$v"; assert_grep "… and a stop line" "ERR:✗ step 3.5" "$v"
v=$(s35 active ok fail yes)
refute_grep "step 3.5: spectra instructions fails → no file list" "→ change files:" "$v"; assert_grep "… and a stop line" "ERR:✗ step 3.5" "$v"
v=$(s35 active ok ok no)
refute_grep "step 3.5: no spec delta → no file list" "→ change files:" "$v"; assert_grep "… and a stop line" "ERR:✗ step 3.5" "$v"

echo "spec-wrapper-contract: idd-plan revisions and aborts act on the change's files (idd-480-fix6)"
S4="$(sed -n '/^### Step 4: /,/^### Step 5: /p' "$PLAN")"
assert_grep "Step 4 shows the files Step 3.5 listed" "Step 3.5 列出的" "$S4"
refute_grep "… and no longer reads the parked change's directory in place" '讀 `openspec/changes/<名稱>/` 底下的檔案' "$S4"
REV="$(grep -F '| Revised (with feedback) |' "$PLAN")"
assert_grep "Revised edits the change's files" "change 的檔案" "$REV"
assert_grep "… runs spectra validate" "spectra validate" "$REV"
assert_grep "… and runs Step 3.5 again before showing the plan" "重跑 Step 3.5" "$REV"
assert_grep "Aborted parks the change again" "spectra park" "$(grep -F '| Aborted |' "$PLAN")"
refute_grep "idd-implement's note no longer asks the Plan question as before" "照舊先問要不要改走" "$(read_file "$IMPL")"
v=$(exist_run x "$(pl 'proposed (change idd-7-y)')"); assert_grep "step 3: a proposed plan naming another change → the stop names it" "idd-7-y" "$v"; assert_grep "… and the open change" "idd-7-x" "$v"

echo "spec-wrapper-contract: spectra-verify warnings on idd-480-fix6"
TPL="$(sed -n '/^`ExitPlanMode` 的 plan 內容：/,/^### Step 5: /p' "$PLAN")"
assert_grep "the ExitPlanMode template has a place for the change files" "Step 3.5 列出的每個檔案" "$TPL"
assert_grep "Step 0 lists a task for Step 3.5" 'TaskCreate(name="read_change_files"' "$(read_file "$PLAN")"
HPR="$(grep -F 'TaskCreate(name="handle_plan_response"' "$PLAN")"
assert_grep "… and handle_plan_response says a revision edits the change files" "spectra validate" "$HPR"
assert_grep "… and an abort parks the change" "spectra park" "$HPR"
refute_grep "idd-plan no longer says it presents only the proposal and the tasks" "proposal 與 tasks" "$(read_file "$PLAN")"
refute_grep "nor does idd-diagnose's route table" "審查 proposal 與 tasks" "$(read_file "$PLUGIN/skills/idd-diagnose/SKILL.md")"

print_summary spec-wrapper-contract
