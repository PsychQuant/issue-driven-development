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
  out=$(cd "$C" && env PATH="$WORK/bin:$PATH" FAKE_COMMENTS="$WORK/comments.json" FAKE_FAIL="$2" FAKE_VIEW_FAIL="${FAKE_VIEW_FAIL:-0}" \
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

echo "spec-close-gate: the skill text"
G="$(sed -n '/^### Step 1.57: /,/^### Step 1.6: /p' "$CLOSE")"
line_of() { local n; n=$(grep -nF -- "$1" "$CLOSE" | head -1 | cut -d: -f1); printf '%s' "${n:-999999}"; }
assert_true "Step 1.57 sits between Step 1.55 and Step 1.6" \
  "[ $(line_of '### Step 1.55: ') -lt $(line_of '### Step 1.57: ') ] && [ $(line_of '### Step 1.57: ') -lt $(line_of '### Step 1.6: ') ]"
assert_grep "the gate calls spec-change.py archived" 'spec-change.py" archived' "$G"
assert_grep "the gate reads the default branch as the remote has it" '--ref "origin/$DEFAULT_BRANCH"' "$G"
assert_grep "the gate chooses the comment with spec-change.py ic (one selection, shared with verify)" 'spec-change.py" ic --comments' "$G"
assert_grep "no Implementation Complete comment → not held to the gate (row 5)" "沒有 Implementation Complete" "$G"
assert_grep "refuse or error stops the close" "停下、不 close" "$G"
assert_grep "the stage task list has the gate" 'name="spec_archive_gate"' "$(cat "$CLOSE")"
assert_grep "orchestrated runs stop on it too" "Step 1.57" "$(sed -n '/^## Orchestrated close/,/^## Configuration/p' "$CLOSE")"

print_summary spec-close-gate
