#!/usr/bin/env bash
# test.sh — living-issue write-back (#424): the plugin rule, the confirmation
# policy of /idd-edit, and idd-diagnose correcting its own Diagnosis.
#
# Change: openspec/changes/archive/2026-11-06-issue-write-back
#   specs/issue-write-back/spec.md, specs/in-place-correction/spec.md
# The SessionStart line is asserted in scripts/tests/session-start-commit-rule;
# the detecting skills' Proposed Corrections blocks in scripts/tests/in-place-correction.
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
assert_grep "example row: scope → ## Expected" "--section '## Expected'" "$R"
assert_grep "example row: root cause → Root Cause section" "--section '### Root Cause / Analysis'" "$R"
assert_grep "example row: deadline → note" '--type note' "$R"
assert_grep "example row: chosen option → decision" '--type decision' "$R"

# two triggers, closed list; no real-time trigger

# only own content
assert_grep "the author gate is /idd-edit's own" 'REASON=R5' "$R"
refute_grep "the rule runs no helper path that only resolves inside a skill" 'CLAUDE_PLUGIN_ROOT' "$R"
assert_grep "someone else's comment → errata" '--type errata --target-comment' "$R"
assert_grep "someone else's issue body → correction" '--type correction' "$R"

# no confirmation, reported, privacy
assert_grep "no confirmation" "不先問" "$R"
assert_grep "each write-back is reported with the backup id" "backup id" "$R"
assert_grep "privacy review before writing" "rules/privacy-scrubbing.md" "$R"
assert_grep "a privacy hit at enforce or warn stops the write-back" '`enforce`、`warn` 命中就停' "$R"
refute_grep "warn no longer just prints a line and writes" "一行提醒後照寫" "$R"
assert_grep "the #272 wording is limited to the reply template" "reply template" "$R"
assert_grep "the no-ask path needs write permission" "viewerPermission" "$R"
assert_grep "a refused write-back goes somewhere" "被拒" "$R"
assert_grep "replacement text goes through a private file" "--body-file" "$R"
assert_grep "--note names the reason" "--note" "$R"
assert_grep "recovery points at the GitHub edit history first" "編輯歷史" "$R"

# what counts as a change, and who can cause one (2026-11-03 decisions)
assert_grep "only a decided change counts" "明確定案" "$R"
assert_grep "the privacy review looks at the added text" "這次加入的文字" "$R"
assert_grep "light counts only new third-party verbatim text" "light" "$R"
assert_grep "the refusals that become a comment are listed" "section-ambiguous" "$R"
assert_grep "every write-back names its basis" "依據" "$R"
assert_grep "--repo is always passed" "--repo" "$R"
refute_grep "the overclaim about phase detection is gone" "註記擠到第二行不影響" "$R"
assert_grep "a hypothesis does not count" "假設與提問" "$R"
assert_grep "a closed issue is not rewritten" "已關閉的 issue" "$R"
refute_grep "not sure no longer defaults to rewriting" "不要因此把它降級" "$R"

# dependent records
assert_grep "Implementation Plan is corrected" "Implementation Plan" "$R"
refute_grep "verify reports get no note (D12)" '--prepend-note' "$R"
assert_grep "verify reports are left as they are (D12)" "不改，也不加註記" "$R"
assert_grep "a change the same PR carries is written back in place (D12)" "同一個 PR 跟著改" "$R"
assert_grep "the Diagnosis target is the newest one" "目標是**最新一則以 \`## Diagnosis\` 開頭的 comment**" "$R"
assert_grep "a newest Diagnosis by someone else gets errata" "最新那則是別人寫的" "$R"
assert_grep "a Spectra change gets the change by spectra-ingest" "/spectra-ingest" "$R"
refute_grep "the rule no longer tells the AI to delete earlier lines itself" "先自己拿掉" "$R"
assert_grep "text before the trailing group is left alone" "那一組之前的文字 helper 不動" "$R"
assert_grep "a scope widened after merge goes to a new issue (D14)" "用 \`/idd-issue\` 開一張新 issue 承接" "$R"
assert_output_grep "idd-diagnose Stage 1 decision carries --repo" "/idd-comment #N --repo <owner/repo> --type decision" "$SKILLS/idd-diagnose/SKILL.md"
assert_grep "direct-commit counts the same branch as the same PR (D14)" "結案前在同一條 branch 跟著改也算" "$R"
refute_grep "no undecided write-back-then-reorganize route (D14)" "照上面寫回之後，呼叫" "$R"
refute_output_grep "idd-reorganize does not take changes no PR carries (D14)" "或沒有 PR 會帶這個改變" "$SKILLS/idd-reorganize/SKILL.md"
assert_output_grep "idd-diagnose Stage 1 also posts a decision comment (D13)" "記下這個決定（兩處都寫" "$SKILLS/idd-diagnose/SKILL.md"
assert_grep "a new mention in a kind-3 comment is asked first" "提及會寄通知給對方" "$R"
refute_output_grep "the helper keeps no （AI 判斷） format" "（AI 判斷）" "$PLUGIN/scripts/idd-edit-helper.py"
refute_output_grep "the append-vs-modify delta no longer says an AI decided" "that an AI decided it" "$PLUGIN/../../openspec/specs/append-vs-modify-discipline/spec.md"
refute_output_grep "--correct has no --last exception (D15)" "target 來自" "$SKILLS/idd-edit/SKILL.md"
assert_grep "unattended verify and implementer changes are out of scope (D15)" "都不會觸發寫回" "$R"
assert_grep "every command carries --repo" "這份規則裡的每一個指令都帶" "$R"
assert_grep "a change that needs no work is written back as usual" "先看它要不要再動到實作" "$R"
refute_grep "no idd-clarify branch" "idd-clarify --status" "$R"
assert_output_grep "the hook keeps lines 1-4 literal" "cat <<'RULES'" "$PLUGIN/hooks/session-start-commit-rule.sh"
assert_grep "a decision that changes the diagnosis is written to both places (D13)" "改了診斷的決定，兩處都寫" "$R"
assert_grep "write-back files live under the cache, not TMPDIR (D13)" ".cache/idd/writeback" "$R"
refute_grep "the visible line no longer says AI 判斷 (D13)" "YYYY-MM-DD（AI 判斷）" "$R"
assert_output_grep "§8 holds a credential back" "a credential at any level" "$PLUGIN/rules/append-vs-modify.md"
assert_output_grep "the write-back table has the both-places row" "A decision that changes the diagnosis" "$PLUGIN/rules/append-vs-modify.md"
assert_output_grep "idd-reorganize sends a same-PR change to write-back" "跟著改的設計改變不用本 skill" "$SKILLS/idd-reorganize/SKILL.md"
assert_output_grep "--last with a whole-comment correction asks" "#N --last" "$SKILLS/idd-edit/SKILL.md"
assert_output_grep "a hit in --note is fixed with the note" "連 \`--note\` 一起改" "$SKILLS/idd-edit/SKILL.md"

# ── A2. append-vs-modify maps each write-back to its category ─────────────
echo "A2. append-vs-modify"
AVM="$PLUGIN/rules/append-vs-modify.md"
INPLACE="$(awk '/^### 8\. `in-place-correction`/{f=1;next} f&&/^##/{exit} f' "$AVM")"
assert_output_grep "append-vs-modify links the write-back rule" "issue-write-back.md" "$AVM"
refute_grep "in-place-correction no longer requires explicit confirmation" "get explicit confirmation" "$INPLACE"
assert_grep "other skills propose the command (D11)" "reach it by proposing the command" "$INPLACE"
refute_grep "no automatic correction is left in the category" "Applied Corrections" "$INPLACE"
refute_grep "the AI alone does not find content wrong" "by the AI in a discussion" "$INPLACE"
refute_grep "the write-back mapping has no verify-note row (D12)" "verify report after" "$(awk '/^### Discussion write-back/{f=1;next} f&&/^##/{exit} f' "$AVM")"

# ── B. /idd-edit confirmation policy ───────────────────────────────────────
echo "B. idd-edit Step 3"
EDIT="$SKILLS/idd-edit/SKILL.md"
S3="$(section "$EDIT" "### Step 3:")"
assert_grep "Step 3 found" "### Step 3:" "$S3"
assert_grep "--correct applies without asking (#424 D1)" '`--correct` 不問' "$S3"
assert_grep "SCRUB=enforce leaves the no-ask path" 'SCRUB=enforce' "$S3"
assert_grep "a privacy hit at enforce or warn stops --correct" '`enforce`、`warn` 命中就停' "$S3"
assert_grep "the privacy review looks at the added text" "加入的" "$S3"
assert_grep "--prepend-note, --append and --replace still ask (D12)" '`--prepend-note`、`--append`、`--replace` 照舊要問' "$S3"
assert_grep "a question defaults to NO" "預設 NO" "$S3"
refute_grep "--prepend-note no longer skips the question (D12)" "validate-target" "$S3"
refute_grep "no unattended branch in idd-edit (D12)" "is_unattended" "$S3"
refute_output_grep "no hold reasons in idd-edit (D12)" "held-" "$EDIT"
refute_grep "the blanket confirmation line is gone" "5. AskUserQuestion 確認，預設 NO（破壞性動作）。" "$S3"
assert_output_grep "the confirm task no longer covers every mode" 'TaskCreate(name="preview_and_report"' "$EDIT"
refute_output_grep "description no longer promises a confirm for every mode" "必 show 原 body + preview 新 body 讓 user confirm" "$EDIT"

# ── C. idd-diagnose Stage 1 ────────────────────────────────────────────────
echo "C. idd-diagnose Stage 1"
DIAG="$SKILLS/idd-diagnose/SKILL.md"
assert_output_grep "Stage 1 adjusts the Diagnosis with --correct" '/idd-edit comment:<Diagnosis id> --repo <owner/repo> --correct --section' "$DIAG"
refute_output_grep "Stage 1 no longer appends a correction comment" '修改後用 `gh issue comment` 追加修正' "$DIAG"
assert_output_grep "Stage 1 leaves the superseded Plan and verify reports alone" "依據的是被取代的診斷，都不動" "$DIAG"
refute_output_grep "Stage 1 adds no note to verify reports (D12)" "每份 verify 報告用" "$DIAG"
assert_output_grep "Stage 1 points to the write-back rule" "rules/issue-write-back.md" "$DIAG"

# ── D. other people's comments do not trigger on their own (D11) ─────────
echo "D. no comment trigger"
assert_grep "someone else's comment does not trigger by itself" "別人的 comment 不會自動觸發寫回" "$R"
assert_grep "it counts when the user raises and adopts it" "使用者在 session 裡提到它" "$R"
assert_grep "the items the user names count as decided (D15)" "使用者點名採納的項目" "$R"
refute_grep "no list-and-wait for adopted comments (D15)" "等使用者確認" "$R"
assert_grep "credentials are a hit at every level" "credential 在任何等級都算命中" "$R"
assert_output_grep "idd-edit counts credentials at every level" "credential 在任何等級都算命中" "$SKILLS/idd-edit/SKILL.md"
refute_output_grep "the canonical spec Purpose no longer lets skills apply corrections" "may apply themselves" "$PLUGIN/../../openspec/specs/in-place-correction/spec.md"
for sk in idd-diagnose idd-plan idd-implement idd-update idd-verify; do
  refute_output_grep "$sk runs no candidates script" "writeback-candidates" "$SKILLS/$sk/SKILL.md"
done
assert_true "the candidates script is gone" "[ ! -e '$PLUGIN/scripts/writeback-candidates.py' ]"
HELPER="$PLUGIN/scripts/idd-edit-helper.py"
refute_output_grep "the helper has no private-path gate (D12)" "_private_path" "$HELPER"
refute_output_grep "the helper has no hold reasons (D12)" "HOLD_REASONS" "$HELPER"
refute_output_grep "the errata pointer asks as on main (D12)" "D1b" "$SKILLS/idd-comment/SKILL.md"

# ── E. idd-close reads a corrected empty residue ───────────────────────────
echo "E. idd-close Step 3.6"
CLOSE="$SKILLS/idd-close/SKILL.md"
PIPE="$(awk '/^RESIDUE_CONTENT=\$\(/{f=1} f{print} f&&/head -c 4000\)/{exit}' "$CLOSE")"
assert_grep "the pipeline was found" "RESIDUE_CONTENT=" "$PIPE"
DIAG_BODY='## Diagnosis

### Residue
(none)

_更正於 2026-11-03：沒有殘留_
<!-- idd:edit mode="correct" backup-id="comment-1-20261103T000000Z" date="2026-11-03" -->

### Next
x'
eval "$PIPE"
assert_eq "the visible line and the marker are not residue" "(none)" "$RESIDUE_CONTENT"
DIAG_BODY='### Residue
real residue

_更正於 2026-11-03_
<!-- idd:edit mode="correct" backup-id="comment-1-20261103T000000Z" date="2026-11-03" -->
'
eval "$PIPE"
assert_eq "real residue stays" "real residue" "$RESIDUE_CONTENT"
DIAG_BODY='### Residue
(none)
_更正於 後來的討論：仍需補上 migration 測試_
'
eval "$PIPE"
assert_grep "a residue line that only starts like the visible line stays" "仍需補上 migration 測試" "$RESIDUE_CONTENT"

print_summary "issue-write-back"
