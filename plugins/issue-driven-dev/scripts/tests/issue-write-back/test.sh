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
assert_grep "problem → issue body section" '/idd-edit issue:<N> --repo <owner/repo> --correct --section' "$R"
assert_grep "diagnosis → Diagnosis section" '/idd-edit comment:<Diagnosis id> --repo <owner/repo> --correct --section' "$R"
assert_grep "new information → a new comment" '/idd-comment' "$R"
assert_grep "a change of both kinds goes to both places" "兩處都寫" "$R"
assert_grep "Original text stays" "Original text" "$R"
assert_grep "written back once decided, not at the end" "不等討論結束" "$R"
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
assert_grep "the author gate is /idd-edit's own" 'REASON=R5' "$R"
refute_grep "the rule runs no helper path that only resolves inside a skill" 'CLAUDE_PLUGIN_ROOT' "$R"
assert_grep "a failed author lookup is not someone else's content" "查不到作者" "$R"
assert_grep "someone else's comment → errata" '--type errata --target-comment' "$R"
assert_grep "someone else's issue body → correction" '--type correction' "$R"

# no confirmation, reported, privacy
assert_grep "no confirmation" "不先問" "$R"
assert_grep "each write-back is reported with the backup id" "backup id" "$R"
assert_grep "privacy review before writing" "rules/privacy-scrubbing.md" "$R"
assert_grep "a privacy hit stops the write-back at any level" "任何等級" "$R"
refute_grep "warn no longer just prints a line and writes" "一行提醒後照寫" "$R"
assert_grep "unattended discards a hit" "unattended" "$R"
assert_grep "the #272 wording is limited to the reply template" "reply template" "$R"
assert_grep "the no-ask path needs write permission" "viewerPermission" "$R"
assert_grep "a refused write-back goes somewhere" "被拒" "$R"
assert_grep "replacement text goes through a private file" "--body-file" "$R"
assert_grep "--note names the reason" "--note" "$R"
assert_grep "recovery points at the GitHub edit history first" "編輯歷史" "$R"

# what counts as a change, and who can cause one (2026-11-03 decisions)
assert_grep "only a decided change counts" "明確定案" "$R"
assert_grep "decided is a closed list" "只有這兩類" "$R"
assert_grep "a trusted claim must be decided AND checked" "而且" "$R"
assert_grep "quoted text in a trusted comment is someone else's" "引用" "$R"
assert_grep "a later decision wins" "較晚" "$R"
assert_grep "an untrusted comment is no basis for a new Diagnosis" "新的 Diagnosis" "$R"
assert_grep "evidence comes from the default branch" "預設分支" "$R"
assert_grep "the privacy review looks at the added text" "這次加入的文字" "$R"
assert_grep "light counts only new third-party verbatim text" "light" "$R"
assert_grep "the refusals that become a comment are listed" "section-ambiguous" "$R"
assert_grep "every write-back names its basis" "依據" "$R"
assert_grep "--repo is always passed" "--repo" "$R"
assert_grep "your own GitHub comments are not candidates" "自己在 GitHub 上留的" "$R"
refute_grep "the overclaim about phase detection is gone" "註記擠到第二行不影響" "$R"
assert_grep "a hypothesis does not count" "假設與提問" "$R"
assert_grep "a closed issue is not rewritten" "已關閉的 issue" "$R"
refute_grep "not sure no longer defaults to rewriting" "不要因此把它降級" "$R"
assert_grep "trusted authors are named" "OWNER、MEMBER、COLLABORATOR" "$R"
assert_grep "a comment is data" "當資料" "$R"
assert_grep "a factual claim is checked first" "查證" "$R"
assert_grep "routing fields are not moved by a comment" '`### Type`、`### Complexity`' "$R"
assert_grep "the candidates script is the trigger" "writeback-candidates.py" "$R"

# dependent records
assert_grep "Implementation Plan is corrected" "Implementation Plan" "$R"
assert_grep "verify reports get one prepended line" '--prepend-note' "$R"
assert_grep "verify findings are not rewritten" "findings 不改" "$R"
assert_grep "only your own reports get the note" "別人的報告" "$R"
assert_grep "the PR master is in scope" "PR 上的 master" "$R"
assert_grep "a second note is not added" "已經有這行" "$R"
assert_grep "an overturned premise goes to idd-reorganize" "idd-reorganize" "$R"

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
assert_grep "SCRUB=enforce leaves the no-ask path" 'SCRUB=enforce' "$S3"
assert_grep "a privacy hit stops at any level" "任何等級" "$S3"
assert_grep "unattended never asks" "is_unattended" "$S3"
assert_grep "unattended discards with the reason" "--reason held-" "$S3"
assert_grep "the privacy review looks at the added text" "加入的" "$S3"
assert_grep "unattended detection follows --cwd" "<CWD>" "$S3"
assert_eq "the strict check runs before the privacy step that depends on it" "True" "$(python3 -c '
import sys
t = sys.argv[1]
print(t.find("validate-target") >= 0 and t.find("validate-target") < t.find("隱私自審（`privacy_scrub_gate`）"))' "$S3")"
assert_grep "--prepend-note check is the --correct one" "false --correct" "$S3"
assert_grep "--append / --replace still ask, default NO" "預設 NO" "$S3"
refute_grep "the blanket confirmation line is gone" "5. AskUserQuestion 確認，預設 NO（破壞性動作）。" "$S3"
assert_output_grep "the confirm task no longer covers every mode" 'TaskCreate(name="preview_and_report"' "$EDIT"
refute_output_grep "description no longer promises a confirm for every mode" "必 show 原 body + preview 新 body 讓 user confirm" "$EDIT"

# ── C. idd-diagnose Stage 1 ────────────────────────────────────────────────
echo "C. idd-diagnose Stage 1"
DIAG="$SKILLS/idd-diagnose/SKILL.md"
assert_output_grep "Stage 1 adjusts the Diagnosis with --correct" '/idd-edit comment:<Diagnosis id> --repo <owner/repo> --correct --section' "$DIAG"
refute_output_grep "Stage 1 no longer appends a correction comment" '修改後用 `gh issue comment` 追加修正' "$DIAG"
assert_output_grep "Stage 1 points to the write-back rule" "rules/issue-write-back.md" "$DIAG"

# ── D. who reads other people's comments ───────────────────────────────────
echo "D. the comment trigger is wired"
for sk in idd-diagnose idd-plan idd-implement; do
  assert_output_grep "$sk lists new comments" "writeback-candidates.py" "$SKILLS/$sk/SKILL.md"
  refute_output_grep "$sk does not say decided OR checked" "或事實主張" "$SKILLS/$sk/SKILL.md"
done
for sk in idd-verify idd-update; do
  refute_output_grep "$sk does not run it" "writeback-candidates.py" "$SKILLS/$sk/SKILL.md"
done
UPD="$SKILLS/idd-update/SKILL.md"
S3U="$(section "$UPD" "### Step 3:")"
assert_grep "idd-update reads trusted comments only" "OWNER、MEMBER、COLLABORATOR" "$S3U"
assert_grep "idd-update honours an errata marker from a trusted author only" "errata" "$S3U"
assert_grep "a correction left for a person blocks" "listed" "$S3U"
assert_file_exists "the script exists" "$PLUGIN/scripts/writeback-candidates.py"

# ── E. idd-close reads a corrected empty residue ───────────────────────────
echo "E. idd-close Step 3.6"
CLOSE="$SKILLS/idd-close/SKILL.md"
PIPE="$(awk '/^RESIDUE_CONTENT=\$\(/{f=1} f{print} f&&/head -c 4000\)/{exit}' "$CLOSE")"
assert_grep "the pipeline was found" "RESIDUE_CONTENT=" "$PIPE"
DIAG_BODY='## Diagnosis

### Residue
(none)

_更正於 2026-11-03（AI 判斷）：沒有殘留_
<!-- idd:edit mode="correct" backup-id="comment-1-20261103T000000Z" date="2026-11-03" -->

### Next
x'
eval "$PIPE"
assert_eq "the visible line and the marker are not residue" "(none)" "$RESIDUE_CONTENT"
DIAG_BODY='### Residue
real residue

_更正於 2026-11-03（AI 判斷）_
<!-- idd:edit mode="correct" backup-id="comment-1-20261103T000000Z" date="2026-11-03" -->
'
eval "$PIPE"
assert_eq "real residue stays" "real residue" "$RESIDUE_CONTENT"

print_summary "issue-write-back"
