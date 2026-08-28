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
# SCOPE, stated rather than implied: idd-verify plus the two files its own
# contract drags in — `references/external-agent-delegation.md` (the egress-body
# copy of the same posting loop) and `rules/tagging-collaborators.md` (a
# protocol idd-verify MANDATES, whose fixed files are the mention gate's
# decision source). The first version scanned only `skills/idd-verify` and said
# so; both of those were outside it, so the rule and its largest violations
# shipped in the same release.
#
# Still NOT covered, and deliberately: `idd-edit`, which writes
# `/tmp/idd-edit-backup/`. That is a documented recovery location users are told
# to `ls`, so moving it is a behaviour change, and its collision consequence is
# a visible clash rather than a silently published wrong comment. Do not read
# this file's green as a statement about idd-edit.
scan_fixed_tmp() {
  # `${TMPDIR:-/tmp}` is exempted ONLY on an mktemp line. The first cut dropped
  # every line containing the idiom, so a FIXED name written that way — an
  # egress body included — sailed through the check that exists to forbid it.
  # The idiom is not the sanctioned thing; `mktemp` is.
  # TWO shapes, because they do not look alike to a regex: a bare `/tmp/name`,
  # and the idiom `${TMPDIR:-/tmp}/name` where `/tmp` is followed by `}`. The
  # first cut wrote only the first alternative and then `grep -v`-ed the idiom
  # wholesale, so the idiom form was doubly invisible — excluded by the filter
  # AND unmatched by the pattern. Its positive control below is what surfaced it.
  grep -rnE --include='*.md' -- '(^|[^A-Za-z0-9_])/tmp/[A-Za-z0-9_.-]|\$\{TMPDIR:-/tmp\}/[A-Za-z0-9_.-]' \
    "$PLUGIN/skills/idd-verify" \
    "$PLUGIN/references/external-agent-delegation.md" \
    "$PLUGIN/rules/tagging-collaborators.md" 2>/dev/null \
    | grep -v 'mktemp'
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

# Second control, for the exemption itself: a FIXED name written with the
# ${TMPDIR:-/tmp} idiom must still be caught. Under the old blanket `grep -v`
# this exact line was invisible.
CANARY2="$PLUGIN/skills/idd-verify/.tmp-idiom-canary.$$-${RANDOM}.md"
trap 'rm -f "$CANARY" "$CANARY2"' EXIT HUP INT TERM
printf 'body-file ${TMPDIR:-/tmp}/pointer.md\n' > "$CANARY2"
SEEN2=$(scan_fixed_tmp | grep -c 'tmp-idiom-canary' || true)
rm -f "$CANARY2"
require "positive control: the TMPDIR idiom does not grant blanket exemption" \
  bash -c '[ "$0" -ge 1 ]' "$SEEN2"

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
