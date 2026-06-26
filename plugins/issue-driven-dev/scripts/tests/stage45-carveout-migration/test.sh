#!/usr/bin/env bash
# test.sh — Stage 4.5 #55 carve-out refactor onto git-ignore-block.sh (#192 task 2).
#
# #55's add-exception case was refactored to call the shared helper. This test
# mirrors the refactored flow (migration awk + bare-.claude sed + helper call)
# against throwaway repos and asserts:
#   - behavior-equivalence: issue-runs becomes trackable, sibling .claude/ stays ignored
#   - one-time migration: a pre-#192 OLD-format #55 block is stripped (no duplicate)
#   - user content preserved
#   - idempotent on re-run
#
# Usage: bash test.sh   (exit 0 = all pass)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$HERE/../../git-ignore-block.sh"
. "$HERE/../../lib/assert-helpers.sh"

new_repo() {
  local d; d="$(mktemp -d)"
  git -C "$d" init -b main -q
  git -C "$d" config user.email t@t.t
  git -C "$d" config user.name t
  git -C "$d" rev-parse --show-toplevel
}
TMPDIRS=()
mk() { local r; r="$(new_repo)"; TMPDIRS+=("$r"); printf '%s' "$r"; }
cleanup() { for d in "${TMPDIRS[@]:-}"; do [ -n "${d:-}" ] && rm -rf "$d"; done; }
trap cleanup EXIT

NEW_SENTINEL="# >>> IDD jsonl run-log carve-out (#55) >>>"
OLD_MARKER="# IDD multi-finding run log carve-out (idd-issue Stage 4.5, #55)"

# Mirror the refactored Stage 4.5 add-exception flow (idd-issue SKILL.md).
apply_stage45_carveout() {
  local GITIGNORE_FILE="$1"
  # (1) migration: strip any OLD single-marker #55 block
  if grep -qxF "$OLD_MARKER" "$GITIGNORE_FILE" 2>/dev/null; then
    awk -v marker="$OLD_MARKER" '
      function is_block_pattern(line) {
        return (line == "!.claude" || line == ".claude/*" \
             || line == "!.claude/.idd" || line == ".claude/.idd/*" \
             || line == "!.claude/.idd/issue-runs")
      }
      $0 == marker { skip = 1; state = 1; next }
      skip && state == 1 { if ($0 ~ /^#/) next; if (is_block_pattern($0)) { state = 2; next } skip = 0 }
      skip && state == 2 { if ($0 == "!.claude/.idd/issue-runs") { skip = 0; next } if (is_block_pattern($0)) next; skip = 0 }
      { print }
    ' "$GITIGNORE_FILE" > "$GITIGNORE_FILE.tmp"
    mv "$GITIGNORE_FILE.tmp" "$GITIGNORE_FILE"
  fi
  # (2) remove bare .claude/
  touch "$GITIGNORE_FILE"
  sed -E '/^\.claude\/?$/d' "$GITIGNORE_FILE" > "$GITIGNORE_FILE.tmp"
  mv "$GITIGNORE_FILE.tmp" "$GITIGNORE_FILE"
  # (3) helper writes the carve-out
  bash "$HELPER" --target "$GITIGNORE_FILE" \
    --marker "IDD jsonl run-log carve-out (#55)" --direction re-include ".claude/.idd/issue-runs"
}

# --- Test 1: fresh .gitignore with .claude/ → carve-out makes run-log trackable
R="$(mk)"; G="$R/.gitignore"
printf '.claude/\n' > "$G"
require "fresh precheck: run-log ignored before" git -C "$R" check-ignore -q .claude/.idd/issue-runs/x.jsonl
apply_stage45_carveout "$G"
refute  "fresh: run-log now trackable"           git -C "$R" check-ignore -q .claude/.idd/issue-runs/x.jsonl
require "fresh: sibling .claude/other still ignored" git -C "$R" check-ignore -q .claude/other/y
refute  "fresh: bare .claude/ line removed"      grep -qxF ".claude/" "$G"

# --- Test 2: MIGRATION — pre-#192 OLD-format block stripped, no duplicate ------
R="$(mk)"; G="$R/.gitignore"
{
  printf '# user top\n*.log\n.claude/\n'
  printf '%s\n' "$OLD_MARKER"
  printf '# rationale comment a\n# rationale comment b\n'
  printf '!.claude\n.claude/*\n!.claude/.idd\n.claude/.idd/*\n!.claude/.idd/issue-runs\n'
  printf '\n# user section AFTER block\nbuild/\n'
} > "$G"
apply_stage45_carveout "$G"
refute "migration: OLD marker gone"               grep -qxF "$OLD_MARKER" "$G"
assert_eq "migration: NEW sentinel appears once" "1" "$(grep -cF "$NEW_SENTINEL" "$G")"
refute "migration: run-log trackable"             git -C "$R" check-ignore -q .claude/.idd/issue-runs/x.jsonl
assert_grep "migration: user top preserved"       "# user top" "$(cat "$G")"
assert_grep "migration: user AFTER section preserved" "# user section AFTER block" "$(cat "$G")"
require "migration: user *.log still effective"   git -C "$R" check-ignore -q debug.log
require "migration: user build/ still effective"  git -C "$R" check-ignore -q build/x

# --- Test 3: idempotent — run the refactored flow twice → one block -----------
R="$(mk)"; G="$R/.gitignore"
printf '.claude/\n' > "$G"
apply_stage45_carveout "$G"
apply_stage45_carveout "$G"
assert_eq "idempotent: NEW sentinel once after 2 runs" "1" "$(grep -cF "$NEW_SENTINEL" "$G")"
refute "idempotent: still trackable"              git -C "$R" check-ignore -q .claude/.idd/issue-runs/x.jsonl

# --- Test 4: MIGRATION of pre-#192 4-LINE old block (missing leading !.claude) -
# The historical #55 code had explicit upgrade logic for a 4-line block (marker
# present but `!.claude` absent). Confirm migration handles it: strip cleanly,
# no orphan pattern line, no duplicate.
R="$(mk)"; G="$R/.gitignore"
{
  printf '# user top\n.claude/\n'
  printf '%s\n' "$OLD_MARKER"
  printf '# rationale\n'
  printf '.claude/*\n!.claude/.idd\n.claude/.idd/*\n!.claude/.idd/issue-runs\n'
  printf '\n# user tail\nnode_modules/\n'
} > "$G"
apply_stage45_carveout "$G"
refute "4-line: OLD marker gone"                  grep -qxF "$OLD_MARKER" "$G"
assert_eq "4-line: NEW sentinel once"            "1" "$(grep -cF "$NEW_SENTINEL" "$G")"
# no ORPHAN old pattern line left outside the new sentinel block:
ORPHANS=$(awk -v b="$NEW_SENTINEL" '$0==b{f=1} f{next} /^(!?\.claude(\/(\*|\.idd(\/(\*|issue-runs))?))?)$/{print}' "$G" | wc -l | tr -d ' ')
assert_eq "4-line: no orphan carve-out pattern outside new block" "0" "$ORPHANS"
refute "4-line: run-log trackable"                git -C "$R" check-ignore -q .claude/.idd/issue-runs/x.jsonl
assert_grep "4-line: user top preserved"          "# user top" "$(cat "$G")"
assert_grep "4-line: user tail preserved"         "# user tail" "$(cat "$G")"
require "4-line: node_modules/ still effective"   git -C "$R" check-ignore -q node_modules/x

print_summary "stage45-carveout-migration"
