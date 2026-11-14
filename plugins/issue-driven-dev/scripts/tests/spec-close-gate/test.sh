#!/usr/bin/env bash
# spec-close-gate suite (#480) — idd-close refuses to close while the change an
# issue declared is not archived on the default branch (requirement "Close
# requires the issue's change to be archived", task 4.3).
#
# spec-example: spec-on-every-issue / the close gate reads the default branch
#
# Rows 1–4 run scripts/spec-change.py archived against the default branch of a
# real repository, the call Step 1.57 makes; the Step 1.57 block itself is then run
# as written with a stand-in gh, which covers row 5 (no Implementation Complete
# comment) and a failed comment fetch (idd-480-fix1).

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
SC="$PLUGIN/scripts/spec-change.py"
CLOSE="$PLUGIN/skills/idd-close/SKILL.md"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/idd-spec-close-gate.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
MARK='<!-- idd:comment type=implementation-complete -->'
field() { python3 -c 'import json,sys; d=json.loads(sys.stdin.read() or "{}"); print(d.get(sys.argv[1], "<missing>"))' "$1"; }
gate() { # comment-body → OUT, RC  (the call Step 1.57 makes, against origin's default branch)
  printf '%s\n' "$1" > "$WORK/ic.md"
  OUT=$(python3 "$SC" archived --file "$WORK/ic.md" --cwd "$C" --ref origin/main 2>/dev/null); RC=$?
}

# A remote whose main has the change archived for #42 only after merge; the issue branch has it archived.
git init -q --bare -b main "$WORK/o.git"; C="$WORK/clone"; git init -q -b main "$C"; git -C "$C" remote add origin "$WORK/o.git"
mkdir -p "$C/openspec/specs"; echo x > "$C/openspec/specs/.keep"; git -C "$C" add -A; git -C "$C" commit -q -m base; git -C "$C" push -q origin main
git -C "$C" checkout -q -b idd/42-x
mkdir -p "$C/openspec/changes/archive/2026-11-10-idd-42-fix-timeout"; echo p > "$C/openspec/changes/archive/2026-11-10-idd-42-fix-timeout/proposal.md"
git -C "$C" add -A; git -C "$C" commit -q -m "chore: archive idd-42-fix-timeout (#42)"; git -C "$C" push -q origin idd/42-x
git -C "$C" fetch -q origin

echo "spec-close-gate: Example rows"
gate "$MARK
**Spec**: change idd-42-fix-timeout"
assert_eq "archived on the issue's branch only, not yet merged → stops" refuse "$(printf '%s' "$OUT" | field status)"
assert_exit "… exit 1" 1 "$RC"
assert_grep "… and names the change" "idd-42-fix-timeout" "$(printf '%s' "$OUT" | field not_archived)"
git -C "$C" checkout -q main; git -C "$C" merge -q --ff-only idd/42-x; git -C "$C" push -q origin main; git -C "$C" fetch -q origin
gate "$MARK
**Spec**: change idd-42-fix-timeout"
assert_eq "archived on the default branch → passes" pass "$(printf '%s' "$OUT" | field status)"
assert_exit "… exit 0" 0 "$RC"
gate "$MARK
## Implementation Complete"
assert_eq "marker, no Spec line → stops" refuse "$(printf '%s' "$OUT" | field status)"
assert_grep "… naming the missing line" "no **Spec**: line" "$(printf '%s' "$OUT" | field reason)"
gate "## Implementation Complete
### Checklist
- [x] done"
assert_eq "no marker, no Spec line (legacy) → passes" pass "$(printf '%s' "$OUT" | field status)"

echo "spec-close-gate: Step 1.57 as written, with a stand-in gh (idd-480-fix1)"
# The bash block of Step 1.57 is run as the skill writes it. gh is replaced by a script that answers the two
# calls the block makes; the comments come from $FAKE_COMMENTS, or the fetch fails when FAKE_FAIL=1.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'GH'
#!/bin/sh
case "$1 $2" in
  "repo view") [ "${FAKE_VIEW_FAIL:-0}" = 1 ] && exit 1; echo main ;;
  "api repos/"*) [ "${FAKE_FAIL:-0}" = 1 ] && exit 1; cat "$FAKE_COMMENTS" ;;
  *) exit 1 ;;
esac
GH
chmod +x "$WORK/bin/gh"
BLOCK="$WORK/step157.sh"
awk '/^### Step 1.57: /{f=1} f && /^```bash$/{b=1; next} b && /^```$/{exit} b' "$CLOSE" > "$BLOCK"
step157() { # comments-json fail(0|1) → STATUS, GRC
  printf '%s' "$1" > "$WORK/comments.json"
  local out
  out=$(cd "$C" && env PATH="$WORK/bin:$PATH" HOME="$WORK" FAKE_COMMENTS="$WORK/comments.json" FAKE_FAIL="$2" FAKE_VIEW_FAIL="${FAKE_VIEW_FAIL:-0}" \
        GITHUB_REPO=o/r NUMBER=42 CWD="$C" CLAUDE_PLUGIN_ROOT="$PLUGIN" \
        bash --norc --noprofile -c '. "$1"; printf "\nSTATUS=%s\nGRC=%s\n" "$(printf "%s" "$GATE" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get(\"status\"))")" "$GATE_RC"' _ "$BLOCK" 2>/dev/null </dev/null)
  STATUS=$(printf '%s\n' "$out" | sed -n 's/^STATUS=//p'); GRC=$(printf '%s\n' "$out" | sed -n 's/^GRC=//p')
}
assert_true "Step 1.57 has a bash block" "[ -s '$BLOCK' ]"
step157 '[{"author_association":"OWNER","body":"## Diagnosis\n\nx"}]' 0
assert_eq "no Implementation Complete comment → passes (row 5, run)" pass "$STATUS"
assert_eq "… exit 0" 0 "$GRC"
step157 '[]' 1
assert_eq "the comments could not be fetched → stops with error" error "$STATUS"
assert_eq "… exit 2" 2 "$GRC"
step157 "[{\"author_association\":\"OWNER\",\"body\":\"$MARK\\n**Spec**: change idd-42-other\"}]" 0
assert_eq "the newest trusted declaration names a change not archived on the default branch → stops" refuse "$STATUS"
step157 "[{\"author_association\":\"OWNER\",\"body\":\"$MARK\\n**Spec**: change idd-42-fix-timeout\"},{\"author_association\":\"CONTRIBUTOR\",\"body\":\"$MARK\\n**Spec**: change idd-42-other\"}]" 0
assert_eq "a newer declaration by a contributor is not the one read" pass "$STATUS"
IC_OK="[{\"author_association\":\"OWNER\",\"body\":\"$MARK\\n**Spec**: change idd-42-fix-timeout\"}]"
FAKE_VIEW_FAIL=1 step157 "$IC_OK" 0
assert_eq "gh repo view fails → stops with error (idd-480-fix2)" error "$STATUS"
git -C "$C" remote set-url origin "$WORK/no-such-remote.git"
step157 "$IC_OK" 0
assert_eq "git fetch of the default branch fails → stops with error, not a stale pass" error "$STATUS"
git -C "$C" remote set-url origin "$WORK/o.git"
# The default branch is read only for a declared change (spectra-verify on idd-480-fix2, warning 2).
FAKE_VIEW_FAIL=1 step157 '[{"author_association":"OWNER","body":"## Diagnosis\n\nx"}]' 0
assert_eq "gh repo view fails, no Implementation Complete → still passes (row 5)" pass "$STATUS"
git -C "$C" remote set-url origin "$WORK/no-such-remote.git"
step157 "[{\"author_association\":\"OWNER\",\"body\":\"$MARK\\n**Spec**: no behaviour change\"}]" 0
assert_eq "git fetch fails, an exemption is declared → passes, the branch is not read" pass "$STATUS"
git -C "$C" remote set-url origin "$WORK/o.git"

# The remote's default branch drops the archive while the local tracking ref stays put (a fetch refspec that
# does not cover main): Step 1.57 must check the commit the fetch returned (idd-480-fix3).
C2="$WORK/clone2"; git clone -q "$WORK/o.git" "$C2" 2>/dev/null
git -C "$C2" rm -q -r openspec/changes/archive/2026-11-10-idd-42-fix-timeout; git -C "$C2" commit -q -m "revert the archive"; git -C "$C2" push -q origin HEAD:main
git -C "$C" config remote.origin.fetch '+refs/heads/nothing:refs/remotes/origin/nothing'
step157 "$IC_OK" 0
assert_eq "the remote dropped the archive, the local tracking ref did not move → stops" refuse "$STATUS"
git -C "$C" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'

echo "spec-close-gate: a repository without a remote, opted into its local branch (#547)"
# The configuration sits above the repository, keyed by its path; the repository has no remote. gh repo view
# fails in these rows, so a pass shows the gate did not go to the remote at all.
L="$WORK/issue-repo"; LR="$L/code"; mkdir -p "$L/.claude/.idd" "$LR"
printf '%s\n' '{"spec_archive": {"code": {"ref": "local", "branch": "master"}}}' > "$L/.claude/.idd/local.json"
git init -q -b master "$LR"; mkdir -p "$LR/openspec/specs"; echo x > "$LR/openspec/specs/.keep"
git -C "$LR" add -A; git -C "$LR" commit -q -m base
step157_in() { # dir comments-json → STATUS, GRC, OUTALL
  printf '%s' "$2" > "$WORK/comments.json"
  OUTALL=$(cd "$1" && env PATH="$WORK/bin:$PATH" HOME="$WORK" FAKE_COMMENTS="$WORK/comments.json" FAKE_FAIL=0 FAKE_VIEW_FAIL=1 \
        GITHUB_REPO=o/r NUMBER=42 CWD="$1" CLAUDE_PLUGIN_ROOT="$PLUGIN" \
        bash --norc --noprofile -c '. "$1"; printf "\nSTATUS=%s\nGRC=%s\n" "$(printf "%s" "$GATE" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get(\"status\"))")" "$GATE_RC"' _ "$BLOCK" 2>/dev/null </dev/null)
  STATUS=$(printf '%s\n' "$OUTALL" | sed -n 's/^STATUS=//p'); GRC=$(printf '%s\n' "$OUTALL" | sed -n 's/^GRC=//p')
}
step157_in "$LR" "$IC_OK"
assert_eq "no remote, opted in, the change is not archived on master → stops" refuse "$STATUS"
mkdir -p "$LR/openspec/changes/archive/2026-11-14-idd-42-fix-timeout"; echo p > "$LR/openspec/changes/archive/2026-11-14-idd-42-fix-timeout/proposal.md"
git -C "$LR" add -A; git -C "$LR" commit -q -m "chore: archive idd-42-fix-timeout (#42)"
step157_in "$LR" "$IC_OK"
assert_eq "no remote, opted in, the change is archived on master → passes without the remote" pass "$STATUS"
assert_eq "… exit 0" 0 "$GRC"
assert_grep "… and prints the local branch and commit" "local ref master@$(git -C "$LR" rev-parse --short master)" "$OUTALL"
git -C "$LR" remote add origin "$WORK/o.git"
step157_in "$LR" "$IC_OK"
assert_eq "the repository has a remote and is opted into local → stops" error "$STATUS"
assert_eq "… exit 2" 2 "$GRC"
assert_grep "… and prints the reason" "remote" "$OUTALL"
git -C "$LR" remote remove origin
refute_grep "the local-mode line does not print the configuration file's path (idd-547-fix1)" ".claude/.idd/local.json" "$(cd "$LR" && git checkout -q master 2>/dev/null; step157_in "$LR" "$IC_OK"; printf '%s' "$OUTALL")"
# idd-547-fix1: HEAD on the issue's branch, where the change is archived; the configured master does not have it.
LH="$WORK/issue-repo-h"; LHR="$LH/code"; mkdir -p "$LH/.claude/.idd" "$LHR"
printf '%s\n' '{"spec_archive": {"code": {"ref": "local", "branch": "master"}}}' > "$LH/.claude/.idd/local.json"
git init -q -b master "$LHR"; mkdir -p "$LHR/openspec/specs"; echo x > "$LHR/openspec/specs/.keep"
git -C "$LHR" add -A; git -C "$LHR" commit -q -m base; git -C "$LHR" checkout -q -b idd/42-x
mkdir -p "$LHR/openspec/changes/archive/2026-11-14-idd-42-fix-timeout"; echo p > "$LHR/openspec/changes/archive/2026-11-14-idd-42-fix-timeout/proposal.md"
git -C "$LHR" add -A; git -C "$LHR" commit -q -m "chore: archive idd-42-fix-timeout (#42)"
step157_in "$LHR" "$IC_OK"
assert_eq "no remote, opted into master, HEAD on the issue's branch with the archive, master without → stops" refuse "$STATUS"
# idd-547-fix1: no remote and no spec_archive entry → stops, and the reason says why archive-ref answered remote
LN="$WORK/noentry"; mkdir -p "$LN/.claude/.idd"; git init -q -b master "$LN/code"
printf '%s\n' '{"github_repo": "o/r"}' > "$LN/.claude/.idd/local.json"
mkdir -p "$LN/code/openspec/specs"; echo x > "$LN/code/openspec/specs/.keep"; git -C "$LN/code" add -A; git -C "$LN/code" commit -q -m base
step157_in "$LN/code" "$IC_OK"
assert_eq "no remote and no spec_archive entry → stops with error" error "$STATUS"
assert_eq "… exit 2" 2 "$GRC"
GATE_REASON=$(cd "$LN/code" && env PATH="$WORK/bin:$PATH" HOME="$WORK" FAKE_COMMENTS="$WORK/comments.json" FAKE_FAIL=0 FAKE_VIEW_FAIL=0 \
  GITHUB_REPO=o/r NUMBER=42 CWD="$LN/code" CLAUDE_PLUGIN_ROOT="$PLUGIN" \
  bash --norc --noprofile -c '. "$1"; printf "%s" "$GATE"' _ "$BLOCK" 2>/dev/null </dev/null)
assert_grep "… and the reason includes why archive-ref answered remote" "spec_archive" "$GATE_REASON"

echo "spec-close-gate: the skill text"
G="$(sed -n '/^### Step 1.57: /,/^### Step 1.6: /p' "$CLOSE")"
line_of() { local n; n=$(grep -nF -- "$1" "$CLOSE" | head -1 | cut -d: -f1); printf '%s' "${n:-999999}"; }
assert_true "Step 1.57 sits between Step 1.55 and Step 1.6" \
  "[ $(line_of '### Step 1.55: ') -lt $(line_of '### Step 1.57: ') ] && [ $(line_of '### Step 1.57: ') -lt $(line_of '### Step 1.6: ') ]"
assert_grep "the gate calls spec-change.py archived" 'spec-change.py" archived' "$G"
assert_grep "the gate fetches the default branch from the remote" 'fetch -q origin -- "$DEFAULT_BRANCH"' "$G"
assert_grep "… and checks the commit that fetch returned" 'rev-parse -q --verify FETCH_HEAD' "$G"
assert_grep "the gate first asks archive-ref which branch to read (#547)" 'spec-change.py" archive-ref' "$G"
assert_grep "the gate chooses the comment with spec-change.py ic (one selection, shared with verify)" 'spec-change.py" ic --comments' "$G"
assert_grep "no Implementation Complete comment → not held to the gate (row 5)" "沒有 Implementation Complete" "$G"
assert_grep "refuse or error stops the close" "停下、不 close" "$G"
assert_grep "the stage task list has the gate" 'name="spec_archive_gate"' "$(cat "$CLOSE")"
assert_grep "orchestrated runs stop on it too" "Step 1.57" "$(sed -n '/^## Orchestrated close/,/^## Configuration/p' "$CLOSE")"

print_summary spec-close-gate
