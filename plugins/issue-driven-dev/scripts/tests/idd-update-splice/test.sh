#!/usr/bin/env bash
# Test: idd-update never turns the body's last line into a setext heading (#413).
#
# Step 5 Branch B appended `\n---\n\n## Current Status…`. When the body ended without
# a newline — common for bodies edited on GitHub, and every body read through `$(...)`
# — the body's last line sat directly on the `---`, and CommonMark reads
# "a paragraph line\n---" as a setext h2. That heading then makes `/idd-edit --correct`
# refuse the section above Current Status. 23 bodies in this repo had that shape.
#
# The splice is RUN out of SKILL.md and its output parsed with the same pinned
# CommonMark parser the correction helper uses (markdown-it-py, table rule on). Branch
# A (an existing Current Status) is checked too: per the 2026-10-26 maintainer decision
# it re-joins with a blank line, which repairs bodies an older Branch B wrote as setext.
#
# Usage: bash test.sh   (exit 0 = pass, 1 = fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
SKILL="$PLUGIN/skills/idd-update/SKILL.md"
. "$PLUGIN/scripts/lib/assert-helpers.sh"

python3 -c 'import markdown_it' 2>/dev/null || { echo "✗ markdown-it-py missing (scripts/requirements-egress.txt)" >&2; exit 1; }

SPLICE="$(awk '/^```bash/{buf=""; f=1; next} f&&/^```/{if (index(buf, "HEAD_PART=")) {printf "%s", buf; exit} f=0; next} f{buf=buf $0 "\n"}' "$SKILL")"
assert_true "Step 5 splice block is extractable" '[ -n "$SPLICE" ]'

NEW_STATUS=$'---\n\n## Current Status\n\n**Phase**: diagnosed\n\n### Blocking\n- (none)'
splice() { # $1 = body → UPDATED_BODY on stdout (exact bytes, via a trailing sentinel)
  BODY="$1" NEW_STATUS="$NEW_STATUS" bash -c "$SPLICE"$'\n''printf "%s<END>" "$UPDATED_BODY"'
}
check() { # $1 = label, $2 = body, $3 = expected prefix that must survive verbatim
  local out; out="$(splice "$2")"; out="${out%<END>}"
  local verdict
  verdict="$(BODY_OUT="$out" PREFIX="$3" python3 - <<'PY'
import os
from markdown_it import MarkdownIt
out, prefix = os.environ["BODY_OUT"], os.environ["PREFIX"]
toks = MarkdownIt("commonmark").enable("table").parse(out)
setext = sum(1 for t in toks if t.type == "heading_open" and t.markup in ("-", "="))
cs = sum(1 for i, t in enumerate(toks) if t.type == "inline" and t.content == "Current Status" and toks[i-1].type == "heading_open")
hr_before_cs = any(t.type == "hr" for t in toks[:next((i for i, t in enumerate(toks) if t.type == "inline" and t.content == "Current Status"), 0)])
print(f"setext={setext} cs={cs} hr={'yes' if hr_before_cs else 'no'} prefix={'yes' if out.startswith(prefix) else 'no'} old={'yes' if 'old status' in out else 'no'}")
PY
)"
  assert_grep "$1: no setext heading" "setext=0" "$verdict"
  assert_grep "$1: exactly one Current Status heading" "cs=1" "$verdict"
  assert_grep "$1: the --- above it is a thematic break" "hr=yes" "$verdict"
  assert_grep "$1: earlier content survives verbatim" "prefix=yes" "$verdict"
  assert_grep "$1: the old Current Status is gone" "old=no" "$verdict"
}

# Branch B — no Current Status yet
check "B, paragraph, no final newline"   'Some text'                                   'Some text'
check "B, paragraph, one newline"        $'Some text\n'                                'Some text'
check "B, paragraph, blank line at end"  $'Some text\n\n'                              'Some text'
check "B, CRLF"                          $'Some text\r\n'                              'Some text'
check "B, IC_R011 footer, no newline"    $'Body.\n\n---\n**Source**: surfaced during x' $'Body.\n\n---\n**Source**: surfaced during x'
check "B, list"                          $'- a\n- b'                                   $'- a\n- b'
check "B, table"                         $'| a | b |\n|---|---|\n| 1 | 2 |'            $'| a | b |\n|---|---|\n| 1 | 2 |'
check "B, fenced block naming the heading" $'```\n## Current Status\n```'              $'```\n## Current Status\n```'
# Branch A — an existing Current Status is replaced from the --- above it
check "A, normal shape"                  $'Problem.\n\n---\n\n## Current Status\n\nold status' $'Problem.'
check "A, setext shape an old Branch B wrote" $'Problem line\n---\n\n## Current Status\n\nold status' $'Problem line'
check "A, no --- above the heading"      $'Problem.\n\n## Current Status\n\nold status' $'Problem.'
check "A, audit block above is kept"     $'Problem.\n\n---\n\n### Clarity Surface\n\n| t |\n|---|\n| x |\n\n---\n\n## Current Status\nold status' $'Problem.\n\n---\n\n### Clarity Surface\n\n| t |\n|---|\n| x |'

# the block refuses to write when the assembled status is missing (shell state lost, #414)
OUT="$(BODY="x" NEW_STATUS="" bash -c "$SPLICE" 2>&1)"; RC=$?
assert_exit "an empty NEW_STATUS stops the splice" 1 "$RC"

refute_output_grep "the bare \\n--- append is gone from Branch B" 'append 新區塊（`\n---\n\n## Current Status...`）' "$SKILL"
print_summary "idd-update-splice (#413)"
