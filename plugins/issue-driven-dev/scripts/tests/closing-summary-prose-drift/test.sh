#!/usr/bin/env bash
# Test: no file in the plugin states a SUPERSEDED version of the closing-summary
# classification rule (#295).
#
# WHY THIS TEST EXISTS
#
# The `## Closing Summary` marker has one normative source —
# `scripts/check-closed-without-summary.sh` — and several prose readers that
# describe it: idd-list, idd-close, idd-find, idd-update, CLAUDE.md, the
# CHANGELOG. Across five verify rounds on PR #297 the SAME defect recurred four
# times: the classifier was fixed, the prose was updated only where a reviewer
# had cited it, and the neighbouring line kept stating the old rule. Round 5 was
# the clearest case — `CLAUDE.md:487` was rewritten while `CLAUDE.md:485`, one
# line above, still said "跑 idd-close --retroactive #N" unconditionally, and
# `idd-find/SKILL.md` had its class-count sentence fixed while the deleted
# "1-3 空格縮排" cap survived two lines away.
#
# Four rounds of trying harder did not fix it, so it is now mechanical. Each
# entry below is a phrase that can only be true under a rule this PR replaced.
# A hit fails the suite unless the line carries an explicit historical marker
# (R1..R6, 早期版本, superseded, …), which is how the CHANGELOG and the code
# comments legitimately quote the old behaviour while narrating why it changed.
#
# Usage: bash test.sh   (exit 0 = pass, 1 = fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"

# phrase <TAB> why it is superseded
STALE=$(cat <<'EOF'
own-comment	class renamed; the compliant class is now called `compliant`
mid-comment	class renamed; the unverified class is now called `present`
MID-COMMENT	class renamed; the unverified class is now called `present`
1-3 空格縮排	the indent cap was deleted with the parser (R5)
只看活的 markdown	R5 stopped distinguishing live markdown from quoted markdown
heading 底下要有內容	R2/R3 phrasing; content is now required only for `casing`/`compliant`
縮排上限 3 空格	the indent cap was deleted with the parser (R5)
CLOSED 但無	binary phrasing of the rule, replaced by the four destinations
the summary IS there	R1 wording; only `casing` may claim content, and it says so differently
EOF
)

# NOTE on the grep invocation below: `--include` must come BEFORE `--`. The first
# cut wrote `grep -rn -- "$phrase" "$PLUGIN" --include='*.md'`, and since `--`
# ends option parsing, `--include=...` was taken as a FILE OPERAND and silently
# ignored — so the scan covered every file type, including this one, and reported
# its own phrase list as nine violations. It did not error; it just stopped
# filtering. (`grep` here may be ugrep, GNU grep or BSD grep; all three behave
# this way.)

# A line may quote an old rule when it is explicitly marked as history.
HISTORICAL='R[1-6][ ]|round[ -][1-6]|rounds [1-6]|早期版本|舊判定|superseded|已被取代|#295 R|verify round'

hits=0
report=""
while IFS=$'\t' read -r phrase why; do
  [ -z "$phrase" ] && continue
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    text=${line#*:*:}
    if printf '%s' "$text" | grep -qE -- "$HISTORICAL"; then
      continue          # narrating the old rule on purpose
    fi
    hits=$((hits + 1))
    report="${report}
    ${line%%:*} — ${phrase}  (${why})"
  done <<EOF2
$(grep -rn --include='*.md' -- "$phrase" "$PLUGIN" 2>/dev/null | grep -v '/CHANGELOG.md:')
EOF2
done <<EOF3
$STALE
EOF3

require "no prose file states a superseded classification rule" \
  bash -c '[ "$0" -eq 0 ] || { printf "%s\n" "$1"; exit 1; }' "$hits" "$report"

# The normative source must still be exactly one file, and the readers must say
# so — a reader that silently holds its own definition is how the drift starts.
for reader in skills/idd-list/SKILL.md skills/idd-close/SKILL.md; do
  assert_grep "$reader points at the normative source" \
    "check-closed-without-summary.sh" "$(cat "$PLUGIN/$reader")"
done

print_summary "closing-summary-prose-drift"
exit $?
