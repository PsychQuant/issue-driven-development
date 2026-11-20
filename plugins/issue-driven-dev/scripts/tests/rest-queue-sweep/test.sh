#!/usr/bin/env bash
# rest-queue-sweep suite (#478) — the checks of `rest-queue.py settle` that run it many hundred times:
#   - killed at every point and run again, it ends where an undisturbed settle ends (kill_sweep.py);
#   - the endings table and the exhaustive matrix of ../rest-queue hold under a git configuration that changes what
#     git shows by default (the other suite runs with an empty global configuration, and cannot see that class);
#   - the helper reads the working tree in one place.
# It is a suite of its own so that the rest-queue suite stays within a few minutes.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
RQ="$HERE/../../rest-queue.py"
RQT="$HERE/../rest-queue"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/idd-rest-queue-sweep.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
export IDD_CLOSE_STAGE_TEST=1 IDD_GH="$RQT/fake-gh.py" GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0

# spec-example: idd-all-rest / settle killed at any point and run again ends where an undisturbed settle ends
python3 "$HERE/kill_sweep.py" "$RQ" "$PLUGIN/scripts/process-attachments.sh" > "$WORK/sweep.out" 2>&1; rc=$?
assert_exit "kill sweep: at every point, the second run ends where the undisturbed one ends" 0 "$rc"
[ "$rc" = 0 ] || sed -n "1,40p" "$WORK/sweep.out"
assert_output_grep "kill sweep: it ran thirteen endings" "kill sweep: 13 endings" "$WORK/sweep.out"
POINTS=$(sed -n 's/^kill sweep: 13 endings, \([0-9]*\) kill points.*/\1/p' "$WORK/sweep.out")
assert_true "kill sweep: over more than 400 kill points" "[ ${POINTS:-0} -gt 400 ]"

# spec-example: idd-all-rest / what git shows by default does not change what settle does
cat > "$WORK/hostile.gitconfig" <<'EOF'
[status]
	showUntrackedFiles = no
	branch = true
	short = true
	renames = copies
	relativePaths = false
	submoduleSummary = true
[core]
	quotePath = false
	untrackedCache = true
[color]
	ui = always
[column]
	ui = always
[diff]
	renames = copies
EOF
IDD_TEST_GIT_CONFIG_GLOBAL="$WORK/hostile.gitconfig" python3 "$RQT/endings.py" "$RQ" "$PLUGIN/scripts/process-attachments.sh" > "$WORK/endings.out" 2>&1; rc=$?
assert_exit "another git configuration: every row of the endings table holds" 0 "$rc"
[ "$rc" = 0 ] || sed -n "1,40p" "$WORK/endings.out"
assert_output_grep "another git configuration: and it ran all of them" "29 rows, 0 failure(s)" "$WORK/endings.out"
IDD_TEST_GIT_CONFIG_GLOBAL="$WORK/hostile.gitconfig" python3 "$RQT/settle_matrix.py" "$RQ" > "$WORK/matrix.out" 2>&1; rc=$?
assert_exit "another git configuration: every combination of the matrix matches" 0 "$rc"
[ "$rc" = 0 ] || sed -n "1,40p" "$WORK/matrix.out"
assert_output_grep "another git configuration: and it ran all of them" "288 cases, 0 mismatch(es)" "$WORK/matrix.out"

# spec-example: idd-all-rest / the helper reads the working tree in one place
assert_eq "one reader: rest-queue.py has one call of git status" "1" "$(grep -c '\["status",' "$RQ")"
assert_grep "one reader: and it lists every untracked file whatever git is configured to show" '"--untracked-files=all"' "$(grep -F '["status",' "$RQ")"

print_summary "rest-queue-sweep"
