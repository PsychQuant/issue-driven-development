#!/usr/bin/env bash
# Unit-test runner for spectra-archive-post-ic.sh
#
# Each fixture in fixtures/<NN-name>/ provides:
#   - archive/proposal.md (+ design.md / tasks.md as needed)
#   - args.txt        — args to pass (with __FIXTURE_PATH__ placeholder)
#   - expected_stdout.txt
#   - expected_exit.txt
#   - post_assert.txt (optional) — additional assertions after run
#
# Each test run:
#   1. Substitute __FIXTURE_PATH__ in args.txt → actual fixture path
#   2. Invoke script with those args
#   3. Compare actual stdout + exit code against expected
#   4. Apply post_assert (must_not_exist <path> currently supported)
#
# Exit 0 if all tests pass; exit 1 otherwise.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
TARGET_SCRIPT="$REPO_ROOT/.claude/scripts/spectra-archive-post-ic.sh"
FIXTURES_DIR="$SCRIPT_DIR/fixtures"

if [ ! -x "$TARGET_SCRIPT" ]; then
  echo "ERROR: target script not executable: $TARGET_SCRIPT" >&2
  exit 1
fi

PASS=0
FAIL=0
FAILED_TESTS=()

for fixture in "$FIXTURES_DIR"/*/; do
  name=$(basename "$fixture")
  fixture_abs=$(cd "$fixture" && pwd)

  # Skip if missing required files
  if [ ! -f "$fixture/args.txt" ] || [ ! -f "$fixture/expected_stdout.txt" ] || [ ! -f "$fixture/expected_exit.txt" ]; then
    echo "SKIP   $name (missing args.txt / expected_stdout.txt / expected_exit.txt)"
    continue
  fi

  # Build args (substitute __FIXTURE_PATH__)
  raw_args=$(cat "$fixture/args.txt")
  args="${raw_args//__FIXTURE_PATH__/$fixture_abs}"

  # Clean any leftover artifacts from prior runs.
  # The /tmp/spectra-archive-ic-outcome*.txt glob clears the change-name-derived
  # outcome files (the script derives the path from --change-name since #56 R6),
  # so fixture 10's must_exist post_assert cannot false-pass on a stale file.
  rm -f /tmp/spectra-archive-candidates.txt /tmp/spectra-archive-ic-dryrun-body.md \
        /tmp/pwn-fixture-05 /tmp/pwn-fixture-11.txt /tmp/spectra-archive-ic-outcome*.txt

  # Run script from /tmp (non-git cwd) so the script's commit lookup can't find
  # commits referencing the fixtures themselves. Fixtures use absolute paths via
  # __FIXTURE_PATH__ substitution, so cwd change is safe.
  #
  # Parse args via array splitting (NOT eval) so malicious args.txt content cannot
  # achieve RCE on the test machine (R3-S1 finding from /idd-verify #56 R3 verify
  # report). `read -ra` populates the array using bash's standard word-splitting
  # rules + respects single-quoted segments, e.g. 'evil$(echo)' stays literal
  # (verified by fixture 07).
  read -ra args_array <<<"$args"
  actual_stdout=$(cd /tmp && bash "$TARGET_SCRIPT" "${args_array[@]}" 2>/dev/null)
  actual_exit=$?

  # Expected values
  expected_stdout=$(cat "$fixture/expected_stdout.txt")
  expected_exit=$(cat "$fixture/expected_exit.txt")

  # Compare
  PASS_STDOUT=0
  PASS_EXIT=0
  PASS_POST=1

  if [ "$actual_stdout" = "$expected_stdout" ]; then
    PASS_STDOUT=1
  fi

  if [ "$actual_exit" = "$expected_exit" ]; then
    PASS_EXIT=1
  fi

  # Apply post-assertions (e.g., "must_not_exist /tmp/pwn-fixture-05")
  if [ -f "$fixture/post_assert.txt" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      cmd=$(echo "$line" | awk '{print $1}')
      target=$(echo "$line" | awk '{print $2}')
      case "$cmd" in
        must_not_exist)
          if [ -e "$target" ]; then
            PASS_POST=0
            echo "         post_assert FAIL: $target should not exist"
          fi
          ;;
        must_exist)
          if [ ! -e "$target" ]; then
            PASS_POST=0
            echo "         post_assert FAIL: $target should exist"
          fi
          ;;
        *)
          echo "         post_assert UNKNOWN command: $cmd"
          PASS_POST=0
          ;;
      esac
    done < "$fixture/post_assert.txt"
  fi

  if [ "$PASS_STDOUT" = "1" ] && [ "$PASS_EXIT" = "1" ] && [ "$PASS_POST" = "1" ]; then
    echo "PASS   $name"
    PASS=$((PASS + 1))
  else
    echo "FAIL   $name"
    if [ "$PASS_STDOUT" = "0" ]; then
      echo "         stdout expected: $expected_stdout"
      echo "         stdout actual:   $actual_stdout"
    fi
    if [ "$PASS_EXIT" = "0" ]; then
      echo "         exit expected: $expected_exit"
      echo "         exit actual:   $actual_exit"
    fi
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$name")
  fi
done


# ── Scenario tests (#405) ──
# These need what the fixtures above cannot give: a real git repository with
# commits, and a stubbed gh so the post path runs without reaching GitHub.
SCN=$(mktemp -d "${TMPDIR:-/tmp}/post-ic-405-XXXXXX") || exit 1
trap 'rm -rf "$SCN"' EXIT
DRY_BODY=/tmp/spectra-archive-ic-dryrun-body.md

mkdir -p "$SCN/bin"
cat > "$SCN/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_STUB_LOG"
case "$1 $2" in
  "repo view")
    [ "${GH_STUB_REPO:-ADMIN/false}" = fail ] && exit 1
    printf '%s\n' "${GH_STUB_REPO:-ADMIN/false}" ;;
  "issue comment")
    n=$3
    while [ $# -gt 0 ]; do
      [ "$1" = --body-file ] && cp "$2" "$GH_STUB_BODY"
      shift
    done
    printf 'https://github.com/test/repo/issues/%s#issuecomment-1\n' "$n" ;;
esac
STUB
chmod +x "$SCN/bin/gh"

scenario() {   # scenario <name> <0|1 from a test command already run>
  if [ "$2" = 0 ]; then
    echo "PASS   $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL   $1"
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$1")
  fi
}

new_repo() {   # new_repo <dir>
  git init -q "$1"
  git -C "$1" config user.name test
  git -C "$1" config user.email test@example.test
  git -C "$1" config commit.gpgsign false
}

commit_all() {   # commit_all <dir> <subject>
  git -C "$1" add -A
  git -C "$1" commit -q -m "$2"
}

run_post() {   # run_post <cwd> <args...>; sets OUT and RC, stub gh on PATH
  local dir=$1; shift
  : > "$SCN/gh.log"; rm -f "$SCN/body.md"
  OUT=$(cd "$dir" && PATH="$SCN/bin:$PATH" GH_STUB_LOG="$SCN/gh.log" GH_STUB_BODY="$SCN/body.md" \
    bash "${POST_SCRIPT:-$TARGET_SCRIPT}" "$@" 2>/dev/null)
  RC=$?
}

# A change that was archived and committed: tracker #7, tasks in place.
R1="$SCN/r1"
A1=openspec/changes/archive/2026-01-02-demo
new_repo "$R1"
mkdir -p "$R1/$A1"
printf '**GitHub-side tracker**: #7\n' > "$R1/$A1/proposal.md"
printf -- '- [x] 1.1 done\n' > "$R1/$A1/tasks.md"
commit_all "$R1" 'chore: seed'

# 1. An absolute --archive-dir does not reach the comment, on either line.
rm -f "$DRY_BODY"
run_post /tmp --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo --dry-run
scenario abs-path-relative-spectra-line "$(grep -qF "**Spectra change**: \`$A1/\`" "$DRY_BODY"; echo $?)"
scenario abs-path-relative-note-line "$(grep -qF "see archived \`$A1/tasks.md\`" "$DRY_BODY"; echo $?)"
scenario abs-path-absent "$(! grep -qF "$SCN" "$DRY_BODY"; echo $?)"

# 2. A path relative to a subdirectory comes out relative to the repository.
rm -f "$DRY_BODY"
run_post "$R1/openspec" --change-name demo --archive-dir changes/archive/2026-01-02-demo --gh-repo test/repo --dry-run
scenario subdir-relative-path "$(grep -qF "**Spectra change**: \`$A1/\`" "$DRY_BODY"; echo $?)"

# 3. Outside any git repository the path still does not leak.
mkdir -p "$SCN/plain/2026-01-03-loose"
printf '**GitHub-side tracker**: #8\n' > "$SCN/plain/2026-01-03-loose/proposal.md"
rm -f "$DRY_BODY"
run_post /tmp --change-name loose --archive-dir "$SCN/plain/2026-01-03-loose" --gh-repo test/repo --dry-run
scenario no-git-falls-back "$(grep -qF '**Spectra change**: `openspec/changes/archive/2026-01-03-loose/`' "$DRY_BODY"; echo $?)"
scenario no-git-path-absent "$(! grep -qF "$SCN" "$DRY_BODY"; echo $?)"

# 4. A real post goes through the wrapper and reports the URL.
run_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo
scenario egress-posts-url "$([ "$OUT" = 'https://github.com/test/repo/issues/7#issuecomment-1' ] && [ "$RC" = 0 ]; echo $?)"
scenario egress-sends-relative-body "$(grep -qF "$A1/" "$SCN/body.md" && ! grep -qF "$SCN" "$SCN/body.md"; echo $?)"
scenario egress-drops-attestation "$(grep -q '^issue comment 7 --repo test/repo' "$SCN/gh.log" && ! grep -q 'scrub-attested' "$SCN/gh.log"; echo $?)"

# 5. The gate refuses: nothing is posted and the outcome says why.
run_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo --spec-deltas '/Users/someone/private'
scenario refused-reports-it "$([ "$RC" = 0 ] && case "$OUT" in '(failed — gh-egress refused'*) true ;; *) false ;; esac; echo $?)"
scenario refused-posts-nothing "$(! grep -q '^issue comment' "$SCN/gh.log"; echo $?)"

# 6. Without a confirmed write level nothing is posted automatically.
GH_STUB_REPO=READ/false run_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo
scenario read-only-not-posted "$(! grep -q '^issue comment' "$SCN/gh.log" && case "$OUT" in '(failed —'*) true ;; *) false ;; esac; echo $?)"
GH_STUB_REPO=fail run_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo
scenario repo-probe-failure-not-posted "$(! grep -q '^issue comment' "$SCN/gh.log" && case "$OUT" in '(failed —'*) true ;; *) false ;; esac; echo $?)"

# 7. A missing wrapper is a refusal, not a fallback to raw gh.
mkdir -p "$SCN/elsewhere/.claude/scripts"
cp "$TARGET_SCRIPT" "$SCN/elsewhere/.claude/scripts/post-ic.sh"
POST_SCRIPT="$SCN/elsewhere/.claude/scripts/post-ic.sh" run_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo
scenario missing-wrapper-not-posted "$(! grep -q '^issue comment' "$SCN/gh.log" && case "$OUT" in *gh-egress*) true ;; *) false ;; esac; echo $?)"

# 8. The case that opened #405: prose about another repository, the real anchor
#    only in commit subjects, and the archive not committed yet (Step 7's moment).
R2="$SCN/r2"
new_repo "$R2"
mkdir -p "$R2/openspec/changes/spike"
printf '# Spike\n\nprivate repo sandbox, with seed issue #1.\n' > "$R2/openspec/changes/spike/proposal.md"
printf 'opened issue #3, then issue #6 in the sandbox.\n' > "$R2/openspec/changes/spike/findings.md"
printf -- '- [x] 1.1 done\n' > "$R2/openspec/changes/spike/tasks.md"
commit_all "$R2" 'docs: propose spike (#400)'
mkdir -p "$R2/openspec/changes/archive"
mv "$R2/openspec/changes/spike" "$R2/openspec/changes/archive/2026-01-04-spike"
run_post "$R2" --change-name spike --archive-dir openspec/changes/archive/2026-01-04-spike --gh-repo test/repo --dry-run
scenario spike-before-archive-commit "$([ "$OUT" = 'https://github.com/test/repo/issues/400#issuecomment-DRY-RUN' ]; echo $?)"

# 9. Same case after the archive commit.
commit_all "$R2" 'chore: archive spike (#400)'
run_post "$R2" --change-name spike --archive-dir openspec/changes/archive/2026-01-04-spike --gh-repo test/repo --dry-run
scenario spike-after-archive-commit "$([ "$OUT" = 'https://github.com/test/repo/issues/400#issuecomment-DRY-RUN' ]; echo $?)"

# 10. A squash subject carries the PR number too: prose picks the issue out of it.
R3="$SCN/r3"
new_repo "$R3"
mkdir -p "$R3/openspec/changes/archive/2026-01-05-squashed"
printf 'Refs #331\n\nSee also issue #120.\n' > "$R3/openspec/changes/archive/2026-01-05-squashed/proposal.md"
commit_all "$R3" 'feat: squashed work (#331) (#334)'
run_post "$R3" --change-name squashed --archive-dir openspec/changes/archive/2026-01-05-squashed --gh-repo test/repo --dry-run
scenario squash-intersection "$([ "$OUT" = 'https://github.com/test/repo/issues/331#issuecomment-DRY-RUN' ]; echo $?)"

# 11. A cluster commit touched the archive; the prose number lives on the pre-move path.
R4="$SCN/r4"
new_repo "$R4"
mkdir -p "$R4/openspec/changes/cluster"
printf 'Refs #148\n' > "$R4/openspec/changes/cluster/proposal.md"
commit_all "$R4" 'feat: default flip (#148)'
mkdir -p "$R4/openspec/changes/archive"
git -C "$R4" mv openspec/changes/cluster openspec/changes/archive/2026-01-06-cluster
commit_all "$R4" 'feat: cluster work (#137 #150)'
run_post "$R4" --change-name cluster --archive-dir openspec/changes/archive/2026-01-06-cluster --gh-repo test/repo --dry-run
scenario cluster-uses-pre-move-commits "$([ "$OUT" = 'https://github.com/test/repo/issues/148#issuecomment-DRY-RUN' ]; echo $?)"

# 12. Commits whose subjects name no prose number still win over that prose.
R5="$SCN/r5"
new_repo "$R5"
mkdir -p "$R5/openspec/changes/archive/2026-01-07-lone"
printf 'with seed issue #1.\n' > "$R5/openspec/changes/archive/2026-01-07-lone/proposal.md"
commit_all "$R5" 'chore: archive lone (#500)'
run_post "$R5" --change-name lone --archive-dir openspec/changes/archive/2026-01-07-lone --gh-repo test/repo --dry-run
scenario commits-beat-lone-prose "$([ "$OUT" = 'https://github.com/test/repo/issues/500#issuecomment-DRY-RUN' ]; echo $?)"

# 13. A cross-repo number in a commit subject does not become a candidate.
R6="$SCN/r6"
new_repo "$R6"
mkdir -p "$R6/openspec/changes/archive/2026-01-08-subject"
printf 'no reference here\n' > "$R6/openspec/changes/archive/2026-01-08-subject/proposal.md"
commit_all "$R6" 'chore: archive subject (#600), see other/sandbox#7'
run_post "$R6" --change-name subject --archive-dir openspec/changes/archive/2026-01-08-subject --gh-repo test/repo --dry-run
scenario cross-repo-commit-subject "$([ "$OUT" = 'https://github.com/test/repo/issues/600#issuecomment-DRY-RUN' ]; echo $?)"

echo ""
echo "─── Summary ───"
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed tests: ${FAILED_TESTS[*]}"
  exit 1
fi
exit 0
