#!/usr/bin/env bash
# test.sh — living-issue write-back (#424): the plugin rule, the confirmation
# policy of /idd-edit, and idd-diagnose correcting its own Diagnosis.
#
# Change: openspec/changes/issue-write-back
#   specs/issue-write-back/spec.md, specs/in-place-correction/spec.md
# The SessionStart line is asserted in scripts/tests/session-start-commit-rule;
# the Applied Corrections blocks in scripts/tests/in-place-correction.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"

PLUGIN="$(cd "$HERE/../../.." && pwd)"
RULE="$PLUGIN/rules/issue-write-back.md"
SKILLS="$PLUGIN/skills"

# section <file> <heading-line-prefix> — the lines from that heading to the next
# heading of the same or a higher level; a `# comment` inside a code fence is
# not a heading
section() {
  awk -v h="$2" '
    /^[[:space:]]*```/ { fence = !fence }
    !fence && index($0, h) == 1 { f = 1; lvl = match($0, /[^#]/) - 1; print; next }
    f && !fence && /^#+ / { l = match($0, /[^#]/) - 1; if (l <= lvl) exit }
    f { print }' "$1"
}

# ── A. the rule ────────────────────────────────────────────────────────────
echo "A. rules/issue-write-back.md"
assert_file_exists "the write-back rule exists" "$RULE"
R="$(cat "$RULE" 2>/dev/null || true)"

# three kinds, closed list
assert_grep "the kinds are a closed list" "只有這三類" "$R"
assert_grep "no fourth kind by similarity" "不得依性質相似類推" "$R"
assert_grep "problem → issue body section" '/idd-edit issue:<N> --correct --section' "$R"
assert_grep "diagnosis → Diagnosis section" '/idd-edit comment:<Diagnosis id> --correct --section' "$R"
assert_grep "new information → a new comment" '/idd-comment' "$R"
assert_grep "a change of both kinds goes to both places" "兩處都寫" "$R"
assert_grep "Original text stays" "Original text" "$R"
assert_grep "written back during the discussion" "討論當下" "$R"
# the spec's routing example, one row each
assert_grep "example row: scope → ## Expected" '--section "## Expected"' "$R"
assert_grep "example row: root cause → Root Cause section" '--section "### Root Cause / Analysis"' "$R"
assert_grep "example row: deadline → note" '--type note' "$R"
assert_grep "example row: chosen option → decision" '--type decision' "$R"

# two triggers, closed list; no real-time trigger
assert_grep "the triggers are a closed list" "只有這兩種" "$R"
assert_grep "trigger 1: session discussion" "session 裡討論" "$R"
assert_grep "trigger 2: a comment, seen at the next read" "下一次讀到" "$R"
assert_grep "no real-time trigger" "不需要即時觸發" "$R"

# only own content
assert_grep "strict author check" 'validate-target <id> <repo> false --correct' "$R"
assert_grep "someone else's comment → errata" '--type errata --target-comment' "$R"
assert_grep "someone else's issue body → correction" '--type correction' "$R"

# no confirmation, reported, privacy
assert_grep "no confirmation" "不先問" "$R"
assert_grep "each write-back is reported with the backup id" "backup id" "$R"
assert_grep "privacy review before writing" "rules/privacy-scrubbing.md" "$R"
assert_grep "enforce hit holds the write-back" "enforce" "$R"

# dependent records
assert_grep "Implementation Plan is corrected" "Implementation Plan" "$R"
assert_grep "verify reports get one prepended line" '--prepend-note' "$R"
assert_grep "verify findings are not rewritten" "findings 不改" "$R"

# ── A2. append-vs-modify maps each write-back to its category ─────────────
echo "A2. append-vs-modify"
AVM="$PLUGIN/rules/append-vs-modify.md"
INPLACE="$(awk '/^### 8\. `in-place-correction`/{f=1;next} f&&/^##/{exit} f' "$AVM")"
assert_output_grep "append-vs-modify links the write-back rule" "issue-write-back.md" "$AVM"
refute_grep "in-place-correction no longer requires explicit confirmation" "get explicit confirmation" "$INPLACE"
refute_grep "other skills no longer only propose the command" "reach it by proposing the command" "$INPLACE"
assert_grep "the write-back mapping names audit-block-append for the verify note" "audit-block-append" "$(awk '/^### Discussion write-back/{f=1;next} f&&/^##/{exit} f' "$AVM")"

# ── B. /idd-edit confirmation policy ───────────────────────────────────────
echo "B. idd-edit Step 3"
EDIT="$SKILLS/idd-edit/SKILL.md"
S3="$(section "$EDIT" "### Step 3:")"
assert_grep "Step 3 found" "### Step 3:" "$S3"
assert_grep "--correct applies without asking (#424 D1)" '`--correct`：不問' "$S3"
assert_grep "--prepend-note runs the strict author check (#424 D1b)" "validate-target" "$S3"
assert_grep "--prepend-note check is the --correct one" "false --correct" "$S3"
assert_grep "--append / --replace still ask, default NO" "預設 NO" "$S3"
refute_grep "the blanket confirmation line is gone" "5. AskUserQuestion 確認，預設 NO（破壞性動作）。" "$S3"
assert_output_grep "the confirm task no longer covers every mode" 'TaskCreate(name="preview_and_report"' "$EDIT"
refute_output_grep "description no longer promises a confirm for every mode" "必 show 原 body + preview 新 body 讓 user confirm" "$EDIT"

# ── C. idd-diagnose Stage 1 ────────────────────────────────────────────────
echo "C. idd-diagnose Stage 1"
DIAG="$SKILLS/idd-diagnose/SKILL.md"
assert_output_grep "Stage 1 adjusts the Diagnosis with --correct" '/idd-edit comment:<Diagnosis id> --correct --section' "$DIAG"
refute_output_grep "Stage 1 no longer appends a correction comment" '修改後用 `gh issue comment` 追加修正' "$DIAG"
assert_output_grep "Stage 1 points to the write-back rule" "rules/issue-write-back.md" "$DIAG"

print_summary "issue-write-back"
