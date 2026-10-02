#!/usr/bin/env bash
# Test: `idd-issue --blocked-by` calls the GraphQL mutation that actually exists,
# and shows GitHub's error when it fails (#353).
#
# WHY THIS TEST EXISTS
#
# Since v2.52.0 (#21) Layer 1 of the --blocked-by fallback chain called
# `addBlockedByDependency(input:{issueId, blockedByIssueId})`. Neither name is
# in GitHub's schema — the mutation is `addBlockedBy(input:{issueId,
# blockingIssueId})`. Nobody noticed for months because three things hid it:
#
#   1. `2>/dev/null` swallowed GitHub's error;
#   2. the warning hard-coded three causes ("repo not enabled / API error /
#      permission"), none of which was the real one;
#   3. the normative spec named the same wrong mutation, so a spec-driven
#      review agreed with the bug.
#
# So the checks below RUN the Layer 1 snippet out of SKILL.md against a stub
# `gh` instead of grepping for the right words: the defect was never a missing
# string, it was behaviour nobody could see. Every check also has a positive
# control that breaks the snippet and requires the check to fail.
#
# OPT-IN LIVE CHECK: set IDD_LIVE_GH=1 to also introspect GitHub's real schema.
# Off by default because no suite in this repo touches the network (CI has
# neither a guaranteed network nor a token). When it does not run it prints
# SKIP — a skipped live check is not evidence that the schema was verified.
#
# Usage: bash test.sh   (exit 0 = pass, 1 = fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
REPO="$(cd "$PLUGIN/../.." && pwd)"
SKILL="$PLUGIN/skills/idd-issue/SKILL.md"
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/blocked-by-mutation-XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

BANNED='addBlockedByDependency|blockedByIssueId'

# ── Harness: extract the Layer 1 snippet and run it against a stub `gh` ──

extract_layer1() {   # $1 = SKILL.md path → prints the Layer 1 lines
  awk '/^# Layer 1[:：]/{f=1} /^# Layer 3[:：]/{f=0} f' "$1"
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case "$1 $2" in
  "issue view") echo "NODE_$3"; exit 0 ;;
  "api graphql")
    case "$GH_MODE" in
      ok)    echo '{"data":{"addBlockedBy":{"issue":{"number":9}}}}'; exit 0 ;;
      taken) echo '{"data":{"addBlockedBy":null},"errors":[{"type":"VALIDATION","message":"Validation failed: Target issue has already been taken"}]}'
             echo "gh: An error occurred while adding the blocking issue to the issue. Validation failed: Target issue has already been taken" >&2
             exit 1 ;;
      other) echo '{"errors":[{"type":"NOT_FOUND"}]}'
             echo "gh: stub-specific failure text 4711" >&2
             exit 1 ;;
    esac ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/gh"

run_layer1() {   # $1 = snippet file, $2 = mode → output in $TMP/out.$2, rc in $TMP/rc.$2
  : > "$TMP/gh.log"
  (
    export PATH="$TMP/bin:$PATH" GH_MODE="$2" GH_LOG="$TMP/gh.log"
    CHILD_NUM=9 BLOCKED_BY_LIST=7 GITHUB_REPO=owner/repo
    . "$1"
  ) > "$TMP/out.$2" 2>&1
  echo $? > "$TMP/rc.$2"
}

# Each check returns 0 when the snippet behaves correctly, 1 otherwise, so the
# positive controls can call the same function on a broken snippet.

check_mutation_name() {   # the query sent to GitHub uses the real names
  run_layer1 "$1" ok
  grep -q 'addBlockedBy(' "$TMP/gh.log" &&
  grep -q 'blockingIssueId' "$TMP/gh.log" &&
  ! grep -qE "$BANNED" "$TMP/gh.log"
}

check_error_surfaced() {  # a real failure shows GitHub's own text, not a guess
  run_layer1 "$1" other
  [ "$(cat "$TMP/rc.other")" = 0 ] &&
  grep -q 'stub-specific failure text 4711' "$TMP/out.other" &&
  grep -q '⚠' "$TMP/out.other" &&
  ! grep -q 'repo not enabled' "$TMP/out.other"
}

check_existing_is_success() {  # an existing dependency is not reported as a failure
  run_layer1 "$1" taken
  [ "$(cat "$TMP/rc.taken")" = 0 ] &&
  ! grep -q '⚠' "$TMP/out.taken" &&
  grep -q '#7' "$TMP/out.taken"
}

check_success_is_quiet() {  # success prints no warning and no raw JSON
  run_layer1 "$1" ok
  [ "$(cat "$TMP/rc.ok")" = 0 ] &&
  ! grep -q '⚠' "$TMP/out.ok" &&
  ! grep -q '"data"' "$TMP/out.ok"
}

# ── Rule: banned names appear nowhere except a CLOSED list of historical records ──
#
# Exactly these, and no others by analogy:
#   1. plugins/issue-driven-dev/CHANGELOG.md   — release history is not rewritten
#   2. README.md rows of the version table      — lines starting `| v<digit>`
#   3. openspec/changes/archive/                 — archived changes are frozen
#   4. this test's own directory                 — it has to name what it bans
banned_hits() {   # $1 = root; file list (root-relative) on stdin → offending lines
  local root="$1" f
  while IFS= read -r f; do
    case "$f" in
      plugins/issue-driven-dev/CHANGELOG.md) continue ;;
      openspec/changes/archive/*) continue ;;
      plugins/issue-driven-dev/scripts/tests/blocked-by-mutation/*) continue ;;
    esac
    [ -f "$root/$f" ] || continue
    if [ "$f" = "plugins/issue-driven-dev/README.md" ]; then
      grep -InE "$BANNED" "$root/$f" | grep -vE '^[0-9]+:\| v[0-9]' | sed "s|^|$f:|"
    else
      grep -InE "$BANNED" "$root/$f" | sed "s|^|$f:|"
    fi
  done
}

list_files() {   # tracked files when this is a checkout; otherwise everything but .git
  git -C "$REPO" ls-files 2>/dev/null && return
  (cd "$REPO" && find . -type f -not -path './.git/*' -not -path './.claude/worktrees/*' | sed 's|^\./||')
}

# ── Real runs ──

LAYER1="$TMP/layer1.sh"
extract_layer1 "$SKILL" > "$LAYER1"
require "the Layer 1 snippet can be found in idd-issue/SKILL.md" test -s "$LAYER1"

require "Layer 1 sends addBlockedBy with blockingIssueId" check_mutation_name "$LAYER1"
require "Layer 1 shows GitHub's error text on failure, without guessed causes" check_error_surfaced "$LAYER1"
require "Layer 1 treats an already-existing dependency as success" check_existing_is_success "$LAYER1"
require "Layer 1 prints neither a warning nor raw JSON on success" check_success_is_quiet "$LAYER1"

HITS=$(list_files | banned_hits "$REPO")
assert_eq "no live file names addBlockedByDependency / blockedByIssueId" "" "$HITS"

# ── Positive controls: each check must FAIL on a snippet that is broken again ──

mutate() {   # $1 = sed expression, $2 = output file; fails if nothing changed
  sed -E "$1" "$LAYER1" > "$2"
  ! cmp -s "$LAYER1" "$2"
}

require "control: the old mutation name can be put back" \
  mutate 's/addBlockedBy\(/addBlockedByDependency(/; s/blockingIssueId/blockedByIssueId/' "$TMP/m1.sh"
refute "control: the name check catches the old mutation" check_mutation_name "$TMP/m1.sh"

require "control: GitHub's error can be swallowed again" \
  mutate 's/2>&1/2>\/dev\/null/' "$TMP/m2.sh"
refute "control: the error check catches a swallowed error" check_error_surfaced "$TMP/m2.sh"

require "control: the already-exists branch can be disabled" \
  mutate 's/already been taken/zzz-never-matches/' "$TMP/m3.sh"
refute "control: the already-exists check catches its removal" check_existing_is_success "$TMP/m3.sh"

mkdir -p "$TMP/tree/plugins/issue-driven-dev" "$TMP/tree/docs" "$TMP/tree/openspec/changes/archive/x"
echo 'old: addBlockedByDependency'             > "$TMP/tree/plugins/issue-driven-dev/CHANGELOG.md"
echo 'old: addBlockedByDependency'             > "$TMP/tree/openspec/changes/archive/x/design.md"
printf '| v2.52.0 | addBlockedByDependency |\nnow: addBlockedByDependency\n' > "$TMP/tree/plugins/issue-driven-dev/README.md"
echo 'blockedByIssueId: $b'                    > "$TMP/tree/docs/commands.md"
CTRL=$(printf '%s\n' plugins/issue-driven-dev/CHANGELOG.md openspec/changes/archive/x/design.md \
  plugins/issue-driven-dev/README.md docs/commands.md | banned_hits "$TMP/tree")
assert_grep "control: a live doc with a banned name is reported" "docs/commands.md:1:" "$CTRL"
assert_grep "control: a README line outside the version table is reported" "README.md:2:" "$CTRL"
refute_grep "control: a README version-table row is exempt" "README.md:1:" "$CTRL"
refute_grep "control: CHANGELOG is exempt" "CHANGELOG.md" "$CTRL"
refute_grep "control: archived changes are exempt" "archive/" "$CTRL"

# ── Opt-in: GitHub's real schema ──

if [ "${IDD_LIVE_GH:-}" = 1 ]; then
  MUTS=$(gh api graphql -f query='{__type(name:"Mutation"){fields{name}}}' --jq '.data.__type.fields[].name' 2>&1)
  INPUT=$(gh api graphql -f query='{__type(name:"AddBlockedByInput"){inputFields{name}}}' --jq '.data.__type.inputFields[].name' 2>&1)
  # Whole-line matches: a substring test would let `blockingIssueId` satisfy
  # "has issueId", and any longer mutation name satisfy "has addBlockedBy".
  assert_grep_re "live: the schema has an addBlockedBy mutation" '^addBlockedBy$' "$MUTS"
  assert_grep_re "live: AddBlockedByInput has issueId" '^issueId$' "$INPUT"
  assert_grep_re "live: AddBlockedByInput has blockingIssueId" '^blockingIssueId$' "$INPUT"
else
  echo "SKIP live schema check (set IDD_LIVE_GH=1 to introspect GitHub's real schema)"
fi

print_summary "blocked-by-mutation"
exit $?
