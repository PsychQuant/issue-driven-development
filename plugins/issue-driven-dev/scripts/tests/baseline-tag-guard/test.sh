#!/usr/bin/env bash
# Test: idd-issue never tags `idd--baseline` when the issue was not created (#412).
#
# Step 3.A showed a bare `gh-egress.sh create …` call: no captured URL, no issue
# number, no stop on failure. gh-egress leaves stdout empty on every failure (gh's
# own error, a missing label, a gate refusal at exit 10-15), so an agent that
# derived NUMBER from the output got "" and carried on. Step 3.6 then built the tag
# from that empty number, tagged and pushed `idd--baseline`, and every later
# failure printed "already exists — skip (idempotent)", which looks normal.
#
# The checks RUN both snippets out of SKILL.md (a stub gh-egress / gh, a temp repo
# with a bare remote), because the defect was behaviour, not a missing word. The
# Step 3.6 guard has a positive control: with the guard neutralised, the same
# empty number must produce `idd--baseline` again.
#
# Usage: bash test.sh   (exit 0 = pass, 1 = fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
SKILL="$PLUGIN/skills/idd-issue/SKILL.md"
. "$PLUGIN/scripts/lib/assert-helpers.sh"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/baseline-tag-guard-XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

fenced_block_with() { # $1 = needle → the first fenced bash block (in $SKILL) that contains it
  awk -v needle="$1" '/^```bash/{buf=""; f=1; next} f&&/^```/{if (index(buf, needle)) {printf "%s", buf; exit} f=0; next} f{buf=buf $0 "\n"}' "$SKILL"
}
S36="$(fenced_block_with 'TAG="${BASELINE_FMT')"
S3A="$(fenced_block_with 'gh-egress.sh" create')"
assert_true "Step 3.6 tag block is extractable" '[ -n "$S36" ]'
assert_true "Step 3.A create block is extractable" '[ -n "$S3A" ]'

# ── Step 3.6: tag only a real issue number ──
GIT=(-c user.name=t -c user.email=t@t -c init.defaultBranch=main)
mkdir -p "$TMP/bin"
printf '#!/usr/bin/env bash\ncase "$*" in *defaultBranchRef*) echo main ;; *) echo "unexpected gh $*" >&2; exit 1 ;; esac\n' > "$TMP/bin/gh"
chmod +x "$TMP/bin/gh"
newrepo() { # $1 → $TMP/r-$1 (main, one commit) with a bare origin
  local r="$TMP/r-$1"
  git "${GIT[@]}" init -q --bare "$r.git" && git "${GIT[@]}" clone -q "$r.git" "$r" 2>/dev/null
  ( cd "$r" && git "${GIT[@]}" checkout -q -b main && git "${GIT[@]}" commit -q --allow-empty -m init && git "${GIT[@]}" push -q origin main 2>/dev/null )
}
run36() { # $1 repo, $2 NUMBER, $3 block → combined output; returns the block's exit code
  ( cd "$1" && PATH="$TMP/bin:$PATH" NUMBER="$2" GITHUB_REPO=o/r CONFIG_PATH="$TMP/no-config.json" bash -c "$3" 2>&1 )
}
remote_tags() { git -C "$1.git" tag --list; }

i=0
for bad in '' 'abc' 'https://github.com/o/r/issues/42' '042' '4 2'; do
  i=$((i + 1)); newrepo "bad$i"
  OUT="$(run36 "$TMP/r-bad$i" "$bad" "$S36")"; RC=$?
  assert_exit "Step 3.6, NUMBER='$bad': never aborts (graceful-skip)" 0 "$RC"
  assert_eq "Step 3.6, NUMBER='$bad': no tag is pushed" "" "$(remote_tags "$TMP/r-bad$i")"
  assert_grep "Step 3.6, NUMBER='$bad': says why it skipped" "graceful-skip" "$OUT"
done
newrepo good
OUT="$(run36 "$TMP/r-good" 42 "$S36")"; RC=$?
assert_exit "Step 3.6, NUMBER=42: succeeds" 0 "$RC"
assert_eq "Step 3.6, NUMBER=42: tags idd-42-baseline on the remote" "idd-42-baseline" "$(remote_tags "$TMP/r-good")"

# under `set -u` an unset NUMBER still skips gracefully (TAG is built before the guard)
newrepo unset
OUT="$( cd "$TMP/r-unset" && PATH="$TMP/bin:$PATH" GITHUB_REPO=o/r CONFIG_PATH="$TMP/no-config.json" bash -u -c "$S36" 2>&1 )"; RC=$?
assert_exit "Step 3.6 under set -u, NUMBER unset: never aborts" 0 "$RC"
assert_grep "…and skips with a reason" "graceful-skip" "$OUT"

# positive control: neutralise the guard → the empty number tags idd--baseline again
MUTANT="$(printf '%s' "$S36" | sed 's/BASELINE_SKIP="no valid issue number[^;]*;/BASELINE_SKIP="";/')"
assert_true "control: the guard line is present to neutralise" '[ "$MUTANT" != "$S36" ]'
newrepo control
run36 "$TMP/r-control" '' "$MUTANT" >/dev/null
assert_eq "control: without the guard an empty number tags idd--baseline" "idd--baseline" "$(remote_tags "$TMP/r-control")"

# ── Step 3.A: capture the URL, check the number, stop when the issue was not created ──
FR="$TMP/root"; mkdir -p "$FR/scripts"
cat > "$FR/scripts/gh-egress.sh" <<'STUB'
#!/usr/bin/env bash
case "${STUB_MODE:-ok}" in
  ok)      echo "https://github.com/o/r/issues/77" ;;
  fail)    echo "could not add label: 'P0' not found" >&2; exit 1 ;;
  refused) echo "✗ gh-egress: REFUSED — privacy net" >&2; exit 10 ;;
  garbage) echo "oops" ;;
  crlf)    printf 'https://github.com/o/r/issues/79\r\n' ;;
  url_then_fail) echo "https://github.com/o/r/issues/78"; echo "gh: later step failed" >&2; exit 1 ;;
esac
STUB
chmod +x "$FR/scripts/gh-egress.sh"
run3a() { # $1 STUB_MODE → output + the numbers left behind (also on exit); returns the block's exit code
  STUB_MODE="$1" CLAUDE_PLUGIN_ROOT="$FR" GITHUB_REPO=o/r TITLE=T TYPE=bug SCRUB_LEVEL=warn NUMBER=999 NEW_ISSUE_NUMBER=999 \
    bash -c 'trap '"'"'echo "EXIT-NUMBER=[${NUMBER:-}] EXIT-NEW=[${NEW_ISSUE_NUMBER:-}]"'"'"' EXIT'$'\n'"$S3A"$'\n''echo "NUMBER=[$NUMBER] NEW=[${NEW_ISSUE_NUMBER:-}]"' 2>&1
}
OUT="$(run3a ok)"; RC=$?
assert_exit "Step 3.A, created: continues" 0 "$RC"
assert_grep "Step 3.A, created: NUMBER is the new issue's number" "NUMBER=[77]" "$OUT"
assert_grep "Step 3.A, created: Step 4.6's NEW_ISSUE_NUMBER is set" "NEW=[77]" "$OUT"
for mode in fail refused garbage; do
  OUT="$(run3a "$mode")"; RC=$?
  assert_exit "Step 3.A, $mode: stops" 1 "$RC"
  assert_grep "Step 3.A, $mode: says the issue was not created" "issue was not created" "$OUT"
  assert_grep "Step 3.A, $mode: a stale number from before is not kept" "EXIT-NUMBER=[] EXIT-NEW=[]" "$OUT"
done

OUT="$(run3a crlf)"; RC=$?
assert_exit "Step 3.A, URL printed with a CR: continues" 0 "$RC"
assert_grep "…with the number" "NUMBER=[79]" "$OUT"
OUT="$(run3a url_then_fail)"; RC=$?
assert_exit "Step 3.A, URL printed but non-zero exit: stops" 1 "$RC"
assert_grep "…saying the issue may exist (no blind retry)" "the issue may exist" "$OUT"
refute_grep "…and not claiming it was not created" "issue was not created" "$OUT"

print_summary "baseline-tag-guard (#412)"
