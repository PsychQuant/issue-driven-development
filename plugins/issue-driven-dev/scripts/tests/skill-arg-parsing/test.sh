#!/bin/bash
# skill-arg-parsing — the flag-parsing blocks of idd-all, idd-all-chain and idd-clarify read every argument
# under both bash and zsh (#598). Claude Code's Bash tool runs zsh, whose arrays start at 1: an index loop from 0
# never reads the last argument there.
#
# Each skill marks its parsing block with `# >>> arg-parse` and `# <<< arg-parse`; the suite runs that block
# under each shell with the arguments of the spec Examples and compares what it parsed.
#
# spec-example: idd-pr-hitl-modes / idd-all reads the last argument in both shells
# spec-example: idd-all-chain / idd-all-chain reads the last argument in both shells
# spec-example: idd-clarify / idd-clarify reads the last argument in both shells

HERE=$(cd "$(dirname "$0")" && pwd)
SKILLS=$(cd "$HERE/../../../skills" && pwd)
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ✓ $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  ✗ $1"; [ -n "${2:-}" ] && printf '      %s\n' "$2"; }

# extract <skill> → $WORK/<skill>.sh, the lines strictly between the two markers; a missing or doubled marker fails
extract() {
  local f="$SKILLS/$1/SKILL.md" out="$WORK/$1.sh"
  local starts ends
  starts=$(grep -c '^# >>> arg-parse$' "$f" 2>/dev/null); ends=$(grep -c '^# <<< arg-parse$' "$f" 2>/dev/null)
  if [ "$starts" != 1 ] || [ "$ends" != 1 ]; then
    bad "$1: exactly one '# >>> arg-parse' and one '# <<< arg-parse' line in SKILL.md (found $starts and $ends)"
    return 1
  fi
  awk '/^# <<< arg-parse$/{f=0} f{print} /^# >>> arg-parse$/{f=1}' "$f" > "$out"
  [ -s "$out" ] || { bad "$1: the arg-parse block is empty"; return 1; }
}

# run <shell> <skill> <print-expression> <args...> — run the block, then print the parsed values on one line
run() {
  local sh="$1" skill="$2" show="$3"; shift 3
  # the block sees only the skill's arguments as "$@"; the file and the print expression are taken off first
  "$sh" -c 'abort() { echo "ABORT: $*"; exit 9; }
__F=$1; __S=$2; shift 2
. "$__F"
eval "$__S"' _ "$WORK/$skill.sh" "$show" "$@" 2>&1
}

# check <skill> <print-expression> <expected> <args...> — same result under bash and zsh
check() {
  local skill="$1" show="$2" want="$3"; shift 3
  local sh got
  for sh in bash zsh; do
    got=$(run "$sh" "$skill" "$show" "$@" | tail -1)
    if [ "$got" = "$want" ]; then ok "$skill under $sh: $* → $want"
    else bad "$skill under $sh: $*" "expected: $want"$'\n'"      got:      $got"; fi
  done
}

command -v zsh >/dev/null 2>&1 || { echo "skill-arg-parsing: zsh is not installed — cannot check the zsh half"; exit 1; }

echo "── idd-all Step 0.2"
if extract idd-all; then
  SHOW='echo "review=$REVIEW_FLAG stop=$STOP_FLAG pr=$PR_FLAG cwd=$CWD_FLAG"'
  check idd-all "$SHOW" "review=--review stop= pr= cwd=" '#5' --review
  check idd-all "$SHOW" "review= stop=early pr= cwd=" '#5' --stop=early
  check idd-all "$SHOW" "review= stop=exhaustive-all pr=--pr cwd=" '#5' --stop exhaustive-all --pr
  check idd-all "$SHOW" "review= stop= pr= cwd=/tmp/x" '#5' --cwd=/tmp/x
  check idd-all "$SHOW" "review=--review stop= pr=--no-pr cwd=/tmp/y" --cwd /tmp/y '#5' --no-pr --review
  check idd-all "$SHOW" "ABORT: --stop needs a value: early, exhaustive-blocking or exhaustive-all" '#5' --stop --review
  check idd-all "$SHOW" "ABORT: Conflicting flags: '--pr' and '--no-pr' both passed. Pick one." '#5' --pr --no-pr
fi

echo "── idd-all-chain Step 0.1"
if extract idd-all-chain; then
  SHOW='echo "roots=${ROOT_ISSUES_SORTED[*]} traversal=$TRAVERSAL review=$REVIEW_FLAG cwd=$CWD_FLAG lowest=$LOWEST_ROOT"'
  check idd-all-chain "$SHOW" "roots=7 12 traversal=bfs review= cwd= lowest=7" '#12' '#7' --bfs
  check idd-all-chain "$SHOW" "roots=3 traversal=dfs review=--review cwd= lowest=3" '#3' --review
  check idd-all-chain "$SHOW" "roots=3 9 traversal=dfs review= cwd=/tmp/x lowest=3" '#3' --cwd /tmp/x '#9'
fi

echo "── idd-clarify Step 1"
if extract idd-clarify; then
  SHOW='echo "n=$NUMBER action=$STATUS_ACTION row=$STATUS_ROW_IDX reason=$STATUS_REASON cwd=$CWD_FLAG"'
  check idd-clarify "$SHOW" "n=8 action=resolved row=2 reason=checked cwd=" '#8' --status resolved=2,checked
  check idd-clarify "$SHOW" "n=8 action= row= reason= cwd=/tmp/x" --cwd=/tmp/x '#8'
  check idd-clarify "$SHOW" "n=8 action=dismissed row=3 reason= cwd=" '#8' --status dismissed=3
fi

echo
echo "PASS: $PASS"
echo "FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
