#!/usr/bin/env bash
# Test: `idd-issue --blocked-by` calls the GraphQL mutation that actually exists,
# and shows GitHub's error when it fails (#353).
#
# WHY THIS TEST EXISTS
#
# Since v2.52.0 (#21) Layer 1 of the --blocked-by fallback chain called
# `addBlockedByDependency(input:{issueId, blockedByIssueId})`. Neither name is
# in GitHub's current schema — the mutation is `addBlockedBy(input:{issueId,
# blockingIssueId})`. Nobody noticed because three things hid it:
#
#   1. `2>/dev/null` swallowed GitHub's error;
#   2. the warning hard-coded three causes ("repo not enabled / API error /
#      permission"), none of which was the real one;
#   3. the normative spec named the same wrong mutation, so a spec-driven
#      review agreed with the bug.
#
# So the checks below RUN the Layer 1 snippet out of SKILL.md against a stub
# `gh` instead of grepping for the right words: the defect was never a missing
# string, it was behaviour nobody could see. Every check has a positive control
# that breaks the snippet (or the input) and requires the check to fail.
#
# LIVE CHECK: IDD_LIVE_GH=1 also introspects GitHub's real schema. It is off in
# the default suite on purpose — every other suite here is offline and
# deterministic, and a GitHub API hiccup should not turn an unrelated PR red.
# A schema rename happens on GitHub's side, independently of any PR, so it is
# detected by `.github/workflows/live-schema.yml`, which runs this suite with
# IDD_LIVE_GH=1 on a weekly schedule against main. When the live check does not
# run, the suite prints SKIP — a skipped live check is not evidence that the
# schema was verified.
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
OLD_CAUSES='not enabled|API error|permission|rate limit'   # the causes the old warning guessed

# ── Harness: extract the Layer 1 snippet and run it against a stub `gh` ──

extract_layer1() {   # $1 = SKILL.md path → the Layer 1 lines, stopping at Layer 3 or a fence
  awk '/^# Layer 1[:：]/{f=1} f && /^```/{f=0} /^# Layer 3[:：]/{f=0} f' "$1"
}

marker_count() {     # $1 = ERE, $2 = file → number of lines matching
  grep -cE -- "$1" "$2"
}

mkdir -p "$TMP/bin" "$TMP/run"
cat > "$TMP/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case "$1 $2" in
  "issue view") echo "NODE_$3"; exit 0 ;;
  "api graphql")
    case "$GH_MODE" in
      ok)    echo '{"data":{"addBlockedBy":{"issue":{"number":9}}}}'; exit 0 ;;
      taken) echo '{"data":{"addBlockedBy":null},"errors":[{"type":"VALIDATION","message":"An error occurred while adding the blocking issue to the issue. Validation failed: Target issue has already been taken"}]}'
             echo "gh: An error occurred while adding the blocking issue to the issue. Validation failed: Target issue has already been taken" >&2
             exit 1 ;;
      other-unique)  # a different uniqueness failure must NOT be read as "already linked"
             echo '{"errors":[{"type":"VALIDATION","message":"Validation failed: Name has already been taken"}]}'
             echo "gh: Validation failed: Name has already been taken" >&2
             exit 1 ;;
      other) echo '{"errors":[{"type":"NOT_FOUND"}]}'
             echo "gh: stub-specific failure text 4711" >&2
             exit 1 ;;
    esac ;;
esac
exit 0
STUB
chmod +x "$TMP/bin/gh"

run_layer1() {   # $1 = snippet file, $2 = mode → $TMP/out.$2 (stdout), $TMP/err.$2, $TMP/rc.$2
  : > "$TMP/gh.log"
  (
    cd "$TMP/run" || exit 99    # anything the snippet writes by accident lands here, not in the repo
    export PATH="$TMP/bin:$PATH" GH_MODE="$2" GH_LOG="$TMP/gh.log"
    CHILD_NUM=9 BLOCKED_BY_LIST=7 GITHUB_REPO=owner/repo
    . "$1"
  ) > "$TMP/out.$2" 2> "$TMP/err.$2"
  echo $? > "$TMP/rc.$2"
}

# Each check returns 0 when the snippet behaves correctly, 1 otherwise, so the
# positive controls can call the same function on a broken snippet.

check_request() {   # the request GitHub receives: real names, -f bindings, child → issueId
  run_layer1 "$1" ok
  local log; log=$(cat "$TMP/gh.log")
  printf '%s\n' "$log" | grep -qF -- 'addBlockedBy(input:{issueId:$i,blockingIssueId:$b}){issue{number}}' &&
  printf '%s\n' "$log" | grep -qF -- '-f i=NODE_9' &&
  printf '%s\n' "$log" | grep -qF -- '-f b=NODE_7' &&
  ! printf '%s\n' "$log" | grep -qE -- "$BANNED" &&
  ! printf '%s\n' "$log" | grep -qE -- '-F (i|b)='
}

check_error_surfaced() {  # a real failure: GitHub's own text, the target named, no guessed cause
  run_layer1 "$1" other
  [ "$(cat "$TMP/rc.other")" = 0 ] &&
  grep -q 'stub-specific failure text 4711' "$TMP/err.other" &&
  grep '⚠' "$TMP/err.other" | grep -q '#7' &&
  ! grep -qiE -- "$OLD_CAUSES" "$TMP/err.other"
}

check_existing_is_success() {  # the exact "already linked" message is not a failure
  run_layer1 "$1" taken
  [ "$(cat "$TMP/rc.taken")" = 0 ] &&
  ! grep -q '⚠' "$TMP/err.taken" &&
  grep -q '#7' "$TMP/err.taken"
}

check_other_uniqueness_warns() {  # any OTHER "has already been taken" is a real failure
  run_layer1 "$1" other-unique
  [ "$(cat "$TMP/rc.other-unique")" = 0 ] &&
  grep -q '⚠' "$TMP/err.other-unique" &&
  grep -q 'Name has already been taken' "$TMP/err.other-unique"
}

check_success_is_quiet() {  # success prints nothing at all
  run_layer1 "$1" ok
  [ "$(cat "$TMP/rc.ok")" = 0 ] &&
  [ ! -s "$TMP/out.ok" ] && [ ! -s "$TMP/err.ok" ]
}

check_stdout_silent() {  # messages go to stderr in every mode: bundle-mode captures stdout
  local m                 # with CHILD_NUM=$(…), so anything printed there is swallowed and
  for m in ok taken other-unique other; do   # then fed to the next child as --blocked-by
    run_layer1 "$1" "$m"
    [ ! -s "$TMP/out.$m" ] || return 1
  done
}

# ── Rule: banned names appear nowhere except a CLOSED list of historical records ──
#
# Exactly these, and no others by analogy:
#   1. plugins/issue-driven-dev/CHANGELOG.md   — release history is not rewritten
#   2. README.md rows of the version table      — lines starting `| v<digit>`
#   3. openspec/changes/archive/                 — archived changes are frozen
#   4. this test's own directory                 — it has to name what it bans
#
# The scan covers every tracked file on purpose: a wrong mutation name copied
# into a new skill, rule or doc should fail here too. A future file that needs
# to mention the old name (e.g. to explain history) is added to this list
# explicitly, not exempted by a broader pattern.
banned_hits() {   # $1 = root; NUL-delimited root-relative paths on stdin → path:line:text
  local root="$1" f
  while IFS= read -r -d '' f; do
    case "$f" in
      plugins/issue-driven-dev/CHANGELOG.md) continue ;;
      openspec/changes/archive/*) continue ;;
      plugins/issue-driven-dev/scripts/tests/blocked-by-mutation/*) continue ;;
    esac
    [ -f "$root/$f" ] || continue          # tracked but deleted in the working tree
    # grep prints the path itself (-H): the path is never spliced into a program.
    if [ "$f" = "plugins/issue-driven-dev/README.md" ]; then
      (cd "$root" && grep -HInE -- "$BANNED" "$f") | grep -vE '^[^:]+:[0-9]+:\| v[0-9]'
    else
      (cd "$root" && grep -HInE -- "$BANNED" "$f")
    fi
  done
  return 0
}

list_files() {   # NUL-delimited; non-ASCII paths unquoted; tracked files when this is a checkout
  if git -C "$REPO" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$REPO" -c core.quotePath=false ls-files -z
  else
    (cd "$REPO" && find . -type f -not -path './.git/*' -not -path './.claude/worktrees/*' -print0 \
      | while IFS= read -r -d '' p; do printf '%s\0' "${p#./}"; done)
  fi
}

# ── Real runs ──

require "exactly one '# Layer 1:' marker in idd-issue/SKILL.md" \
  test "$(marker_count '^# Layer 1[:：]' "$SKILL")" = 1
require "exactly one '# Layer 3:' marker in idd-issue/SKILL.md" \
  test "$(marker_count '^# Layer 3[:：]' "$SKILL")" = 1

LAYER1="$TMP/layer1.sh"
extract_layer1 "$SKILL" > "$LAYER1"
require "the Layer 1 snippet can be found in idd-issue/SKILL.md" test -s "$LAYER1"

require "Layer 1 sends addBlockedBy(issueId=child, blockingIssueId=target) with -f bindings" check_request "$LAYER1"
require "Layer 1 shows GitHub's error text, names the target, guesses no cause" check_error_surfaced "$LAYER1"
require "Layer 1 treats the exact 'Target issue has already been taken' as already linked" check_existing_is_success "$LAYER1"
require "Layer 1 still warns on a different 'has already been taken' failure" check_other_uniqueness_warns "$LAYER1"
require "Layer 1 prints nothing on success" check_success_is_quiet "$LAYER1"
require "Layer 1 never writes to stdout" check_stdout_silent "$LAYER1"

require "the file list sees idd-issue/SKILL.md (an empty list would pass the scan vacuously)" \
  sh -c 'tr "\0" "\n" | grep -qx "plugins/issue-driven-dev/skills/idd-issue/SKILL.md"' < <(list_files)
HITS=$(list_files | banned_hits "$REPO")
assert_eq "no live file names addBlockedByDependency / blockedByIssueId" "" "$HITS"

# ── Positive controls: each check must FAIL on a snippet that is broken again ──

mutate() {   # $1 = sed expression, $2 = output file; fails if nothing changed
  sed -E "$1" "$LAYER1" > "$2"
  ! cmp -s "$LAYER1" "$2"
}

require "control: the old mutation name can be put back" \
  mutate 's/addBlockedBy\(/addBlockedByDependency(/; s/blockingIssueId/blockedByIssueId/' "$TMP/m1.sh"
refute "control: the request check catches the old mutation" check_request "$TMP/m1.sh"

require "control: the bindings can be swapped" \
  mutate 's/-f i="\$CHILD_NODE_ID" -f b="\$M_NODE_ID"/-f i="$M_NODE_ID" -f b="$CHILD_NODE_ID"/' "$TMP/m1b.sh"
refute "control: the request check catches a reversed dependency" check_request "$TMP/m1b.sh"

require "control: the bindings can go back to -F" \
  mutate 's/-f i=/-F i=/; s/-f b=/-F b=/' "$TMP/m1c.sh"
refute "control: the request check catches -F bindings" check_request "$TMP/m1c.sh"

require "control: GitHub's error can be swallowed again" \
  mutate 's/2>&1\)/2>\/dev\/null)/' "$TMP/m2.sh"
refute "control: the error check catches a swallowed error" check_error_surfaced "$TMP/m2.sh"

require "control: a guessed cause can be put back into the warning" \
  mutate 's/失敗；body blockquote/失敗 (permission)；body blockquote/' "$TMP/m2b.sh"
refute "control: the error check catches a guessed cause" check_error_surfaced "$TMP/m2b.sh"

require "control: the already-exists branch can be disabled" \
  mutate 's/Target issue has already been taken/zzz-never-matches/' "$TMP/m3.sh"
refute "control: the already-exists check catches its removal" check_existing_is_success "$TMP/m3.sh"

require "control: the already-exists match can be broadened" \
  mutate "s/'Target issue has already been taken'/'already been taken'/" "$TMP/m3b.sh"
refute "control: the other-uniqueness check catches a broadened match" check_other_uniqueness_warns "$TMP/m3b.sh"

require "control: success can be made noisy" \
  mutate 's/^([[:space:]]*):[[:space:]]+# 原生依賴已建立.*/\1printf "%s\\n" "$GQL_OUT" >\&2/' "$TMP/m4.sh"
refute "control: the quiet-success check catches output on success" check_success_is_quiet "$TMP/m4.sh"

require "control: messages can be sent back to stdout" \
  mutate 's/ >&2$//; s/^([[:space:]]*\}) >&2$/\1/' "$TMP/m5.sh"
refute "control: the stdout check catches a message on stdout" check_stdout_silent "$TMP/m5.sh"

mkdir -p "$TMP/tree/plugins/issue-driven-dev" "$TMP/tree/docs" "$TMP/tree/openspec/changes/archive/x"
echo 'old: addBlockedByDependency'             > "$TMP/tree/plugins/issue-driven-dev/CHANGELOG.md"
echo 'old: addBlockedByDependency'             > "$TMP/tree/openspec/changes/archive/x/design.md"
printf '| v2.52.0 | addBlockedByDependency |\nnow: addBlockedByDependency\n' > "$TMP/tree/plugins/issue-driven-dev/README.md"
echo 'blockedByIssueId: $b'                    > "$TMP/tree/docs/commands.md"
echo 'blockedByIssueId: $b'                    > "$TMP/tree/docs/文件.md"
CTRL=$(printf '%s\0' plugins/issue-driven-dev/CHANGELOG.md openspec/changes/archive/x/design.md \
  plugins/issue-driven-dev/README.md docs/commands.md "docs/文件.md" | banned_hits "$TMP/tree")
assert_grep "control: a live doc with a banned name is reported" "docs/commands.md:1:" "$CTRL"
assert_grep "control: a non-ASCII path with a banned name is reported" "docs/文件.md:1:" "$CTRL"
assert_grep "control: a README line outside the version table is reported" "README.md:2:" "$CTRL"
refute_grep "control: a README version-table row is exempt" "README.md:1:" "$CTRL"
refute_grep "control: CHANGELOG is exempt" "CHANGELOG.md" "$CTRL"
refute_grep "control: archived changes are exempt" "archive/" "$CTRL"

# ── Live: GitHub's real schema (IDD_LIVE_GH=1; weekly in .github/workflows/live-schema.yml) ──

if [ "${IDD_LIVE_GH:-}" = 1 ]; then
  MUTS=$(gh api graphql -f query='{__type(name:"Mutation"){fields{name}}}' --jq '.data.__type.fields[].name' 2>&1)
  INPUT=$(gh api graphql -f query='{__type(name:"AddBlockedByInput"){inputFields{name}}}' --jq '.data.__type.inputFields[].name' 2>&1)
  PAYLOAD=$(gh api graphql -f query='{__type(name:"AddBlockedByPayload"){fields{name}}}' --jq '.data.__type.fields[].name' 2>&1)
  # Whole-line matches: a substring test would let `blockingIssueId` satisfy
  # "has issueId", and any longer mutation name satisfy "has addBlockedBy".
  assert_grep_re "live: the schema has an addBlockedBy mutation" '^addBlockedBy$' "$MUTS"
  assert_grep_re "live: AddBlockedByInput has issueId" '^issueId$' "$INPUT"
  assert_grep_re "live: AddBlockedByInput has blockingIssueId" '^blockingIssueId$' "$INPUT"
  assert_grep_re "live: AddBlockedByPayload has issue (the snippet selects issue{number})" '^issue$' "$PAYLOAD"
else
  echo "SKIP live schema check (set IDD_LIVE_GH=1 to introspect GitHub's real schema)"
fi

print_summary "blocked-by-mutation"
exit $?
