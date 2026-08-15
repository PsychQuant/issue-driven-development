#!/usr/bin/env bash
# Test: no skill may name a FIXED scratch path under /tmp (#288).
#
# WHY THIS EXISTS
#
# #288 was closed with a summary stating that every scratch path now hung off
# `mktemp -d`. What actually shipped was a NOTE saying so, followed by twenty-
# three paragraphs that went on MUSTing `/tmp/verify_${NUMBER}_*` — including
# the OUTPUT instructions handed to the reviewer agents, i.e. the paths that
# decide where findings actually land. The rule and its violations lived four
# lines apart for two releases.
#
# A fixed name under /tmp carries no repo identity. Two sessions verifying the
# SAME issue number in DIFFERENT repos share filenames, and a leftover file from
# the earlier run is read as this run's findings — silently, and in the worst
# direction: another repo's verdict merged into this PR's report.
#
# So the rule is mechanised rather than restated. Prose cannot drift from a
# grep.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"

# A fixed scratch path = /tmp (or ${TMPDIR:-/tmp}) followed by a literal name.
# `mktemp` lines are exempt: that is the sanctioned way to obtain one, and the
# template it takes necessarily contains /tmp.
#
# SCOPE, stated rather than implied: this scans `idd-verify` only. The same
# grep over all of skills/ also hits `idd-edit`, which writes
# `/tmp/idd-edit-backup/` and `/tmp/idd-edit-repl-${COMMENT_ID}.md`. Those are a
# different problem and are NOT covered here: the backup directory is a
# documented recovery location users are told to `ls`, so moving it is a
# behaviour change, and the collision consequence there is a visible clash
# rather than a silently merged verdict. Filed separately — do not read this
# file's green as a statement about idd-edit.
scan_fixed_tmp() {
  grep -rnE --include='*.md' -- '(^|[^A-Za-z0-9_])/tmp/[A-Za-z0-9_.-]' \
    "$PLUGIN/skills/idd-verify" 2>/dev/null \
    | grep -v 'mktemp' \
    | grep -v 'TMPDIR:-/tmp'
}

HITS=$(scan_fixed_tmp || true)
require "no skill names a fixed scratch path under /tmp" \
  bash -c '[ -z "$0" ] || { printf "%s\n" "$0"; exit 1; }' "$HITS"

# Positive control. Without it, a scan broken by a bad flag or a wrong path
# (all of which have happened in this repo) reads as a clean tree. Unique name
# + trap, because the canary is written INTO the repo and an interrupted run
# would otherwise leave it there as a permanent red.
CANARY="$PLUGIN/skills/idd-verify/.tmp-path-canary.$$-${RANDOM}.md"
trap 'rm -f "$CANARY"' EXIT HUP INT TERM
printf 'canary: write findings to /tmp/verify_${NUMBER}_findings_logic.md\n' > "$CANARY"
SEEN=$(scan_fixed_tmp | grep -c 'tmp-path-canary' || true)
rm -f "$CANARY"
require "positive control: the scan actually detects a planted fixed path" \
  bash -c '[ "$0" -ge 1 ]' "$SEEN"

# The sanctioned replacement must be present and resolved BEFORE anything is
# written — a run directory created after the first write is not a run
# directory, it is a rename.
VERIFY_MD=$(cat "$PLUGIN/skills/idd-verify/SKILL.md")
assert_grep "idd-verify resolves a per-run scratch dir with mktemp -d" \
  'VERIFY_DIR=$(mktemp -d' "$VERIFY_MD"
assert_grep "...as a Step 0 task, before any spawn or write" \
  'TaskCreate(name="resolve_scratch_dir"' "$VERIFY_MD"
assert_grep "reviewer OUTPUT instructions use it" \
  '$VERIFY_DIR/findings_' "$VERIFY_MD"

print_summary "verify-scratch-paths"
exit $?
