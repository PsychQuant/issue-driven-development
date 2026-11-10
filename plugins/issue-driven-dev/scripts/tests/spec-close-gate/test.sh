#!/usr/bin/env bash
# spec-close-gate suite (#480) — idd-close refuses to close while the change an
# issue declared is not archived on the default branch (requirement "Close
# requires the issue's change to be archived", task 4.3).
#
# spec-example: spec-on-every-issue / the close gate reads the default branch
#
# Rows 1–4 run scripts/spec-change.py archived against the default branch of a
# real repository, the call Step 1.57 makes; row 5 (no Implementation Complete
# comment) is a rule of the skill text and is checked there.

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

echo "spec-close-gate: the skill text"
G="$(sed -n '/^### Step 1.57: /,/^### Step 1.6: /p' "$CLOSE")"
line_of() { local n; n=$(grep -nF -- "$1" "$CLOSE" | head -1 | cut -d: -f1); printf '%s' "${n:-999999}"; }
assert_true "Step 1.57 sits between Step 1.55 and Step 1.6" \
  "[ $(line_of '### Step 1.55: ') -lt $(line_of '### Step 1.57: ') ] && [ $(line_of '### Step 1.57: ') -lt $(line_of '### Step 1.6: ') ]"
assert_grep "the gate calls spec-change.py archived" 'spec-change.py" archived' "$G"
assert_grep "the gate reads the default branch as the remote has it" '--ref "origin/$DEFAULT_BRANCH"' "$G"
assert_grep "the gate takes the newest Implementation Complete by a writer" "有寫入權" "$G"
assert_grep "no Implementation Complete comment → not held to the gate (row 5)" "沒有 Implementation Complete" "$G"
assert_grep "refuse or error stops the close" "停下、不 close" "$G"
assert_grep "the stage task list has the gate" 'name="spec_archive_gate"' "$(cat "$CLOSE")"
assert_grep "orchestrated runs stop on it too" "Step 1.57" "$(sed -n '/^## Orchestrated close/,/^## Configuration/p' "$CLOSE")"

print_summary spec-close-gate
