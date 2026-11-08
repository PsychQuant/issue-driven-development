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

# ── Shared setup (#405) ──
# A stub gh first on PATH for every run, fixtures included, so nothing reaches GitHub:
# the script now asks the issues API whether a candidate is an issue or a pull request.
# The review copy that a dry run keeps goes to a temporary state directory, not $HOME.
SCN=$(mktemp -d "${TMPDIR:-/tmp}/post-ic-405-XXXXXX") || exit 1
export SPECTRA_POST_IC_STATE_DIR="$SCN/state"
trap 'rm -rf "$SCN"' EXIT

# Stub gh. GH_STUB_REPO: "PERM/PRIVATE" for the permission query, or "fail".
# `repo view --json nameWithOwner` answers with the owner/repo of the cwd's origin.
# GH_STUB_PRS and GH_STUB_MISSING: space-separated numbers the issues API reports as a
# pull request or as not found. GH_STUB_API_FAIL=1 makes every issues API call fail
# the way a transport error does, with the request URL in the message.
# GH_STUB_POST_FAIL=1 makes the comment fail with a message.
mkdir -p "$SCN/bin"
cat > "$SCN/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${GH_STUB_LOG:-/dev/null}"
case "$1 $2" in
  "repo view")
    case " $* " in
      *" nameWithOwner "*)
        git remote get-url origin 2>/dev/null | sed -E 's#\.git$##; s#.*[:/]([^/]+/[^/]+)$#\1#' ;;
      *)
        [ "${GH_STUB_REPO:-ADMIN/false}" = fail ] && exit 1
        printf '%s\n' "${GH_STUB_REPO:-ADMIN/false}" ;;
    esac ;;
  "api "repos/*/issues/*)
    n=${2##*/}
    [ "${GH_STUB_API_FAIL:-0}" = 1 ] && { echo "Get \"https://api.github.com/$2\": dial tcp: connection refused" >&2; exit 1; }
    case " ${GH_STUB_MISSING:-} " in *" $n "*) echo "gh: Not Found (HTTP 404)" >&2; exit 1 ;; esac
    case " ${GH_STUB_PRS:-} " in *" $n "*) echo pr ;; *) echo issue ;; esac ;;
  "issue comment")
    [ "${GH_STUB_POST_FAIL:-0}" = 1 ] && { echo "GraphQL: Could not resolve to an issue" >&2; exit 1; }
    n=$3
    while [ $# -gt 0 ]; do
      [ "$1" = --body-file ] && cp "$2" "${GH_STUB_BODY:-/dev/null}"
      shift
    done
    printf 'https://github.com/test/repo/issues/%s#issuecomment-1\n' "$n" ;;
esac
STUB
chmod +x "$SCN/bin/gh"

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

  # The fixtures sit inside this repository, whose origin is not the test/repo the
  # args name, so the script reads no commit history for them wherever it runs. The
  # cwd is /tmp for continuity; fixtures use absolute paths via __FIXTURE_PATH__.
  #
  # Parse args via array splitting (NOT eval) so malicious args.txt content cannot
  # achieve RCE on the test machine (R3-S1 finding from /idd-verify #56 R3 verify
  # report). `read -ra` populates the array using bash's standard word-splitting
  # rules + respects single-quoted segments, e.g. 'evil$(echo)' stays literal
  # (verified by fixture 07).
  read -ra args_array <<<"$args"
  actual_stdout=$(cd /tmp && PATH="$SCN/bin:$PATH" bash "$TARGET_SCRIPT" "${args_array[@]}" 2>/dev/null)
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
# commits, and the stub gh so lookups and the post path run without reaching GitHub.

scenario() {   # scenario <name> <0|1 from a test command already run>
  if [ "$2" = 0 ]; then
    echo "PASS   $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL   $1"
    echo "         outcome: ${OUT:-}"
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$1")
  fi
}

new_repo() {   # new_repo <dir> [origin]; origin defaults to the --gh-repo the tests pass
  git init -q "$1"
  git -C "$1" config user.name test
  git -C "$1" config user.email test@example.test
  git -C "$1" config commit.gpgsign false
  git -C "$1" remote add origin "${2:-https://github.com/test/repo.git}"
}

commit_all() {   # commit_all <dir> <subject> [body]
  git -C "$1" add -A
  if [ -n "${3:-}" ]; then
    git -C "$1" commit -q -m "$2" -m "$3"
  else
    git -C "$1" commit -q -m "$2"
  fi
}

run_post() {   # run_post <cwd> <args...>; sets OUT and RC, stub gh on PATH
  local dir=$1; shift
  : > "$SCN/gh.log"; rm -f "$SCN/body.md"
  OUT=$(cd "$dir" && PATH="$SCN/bin:$PATH" GH_STUB_LOG="$SCN/gh.log" GH_STUB_BODY="$SCN/body.md" \
    bash "${POST_SCRIPT:-$TARGET_SCRIPT}" "$@" 2>/dev/null)
  RC=$?
}

outcome_is() { [ "$OUT" = "https://github.com/test/repo/issues/$1#issuecomment-DRY-RUN" ]; }
dry_body() { printf '%s/body-%s.md' "$SPECTRA_POST_IC_STATE_DIR" "$1"; }
review_then_post() {   # review_then_post <cwd> <args...> --scrub-attested L: the dry run first, as Step 7 does
  local dir=$1; shift
  local dry=() a skip=0
  for a in "$@"; do
    if [ "$skip" = 1 ]; then skip=0; continue; fi
    [ "$a" = --scrub-attested ] && { skip=1; continue; }
    dry+=("$a")
  done
  run_post "$dir" "${dry[@]}" --dry-run
  run_post "$dir" "$@"
}
outcome_starts() { case "$OUT" in "$1"*) true ;; *) false ;; esac; }
posted() { grep -q '^issue comment' "$SCN/gh.log"; }

# A change that was archived and committed: tracker #7, tasks in place.
R1="$SCN/r1"
A1=openspec/changes/archive/2026-01-02-demo
new_repo "$R1"
mkdir -p "$R1/$A1"
printf '**GitHub-side tracker**: #7\n' > "$R1/$A1/proposal.md"
printf -- '- [x] 1.1 done\n' > "$R1/$A1/tasks.md"
commit_all "$R1" 'chore: seed'

# 1. An absolute --archive-dir does not reach the comment, on either line.
rm -f "$(dry_body demo)"
run_post /tmp --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo --dry-run
scenario abs-path-relative-spectra-line "$(grep -qF "**Spectra change**: \`$A1/\`" "$(dry_body demo)"; echo $?)"
scenario abs-path-relative-note-line "$(grep -qF "see archived \`$A1/tasks.md\`" "$(dry_body demo)"; echo $?)"
scenario abs-path-absent "$(! grep -qF "$SCN/r1" "$(dry_body demo)"; echo $?)"

# 2. A path relative to a subdirectory comes out relative to the repository.
rm -f "$(dry_body demo)"
run_post "$R1/openspec" --change-name demo --archive-dir changes/archive/2026-01-02-demo --gh-repo test/repo --dry-run
scenario subdir-relative-path "$(grep -qF "**Spectra change**: \`$A1/\`" "$(dry_body demo)"; echo $?)"

# 3. Outside any git repository the path still does not leak.
mkdir -p "$SCN/plain/2026-01-03-loose"
printf '**GitHub-side tracker**: #8\n' > "$SCN/plain/2026-01-03-loose/proposal.md"
rm -f "$(dry_body loose)"
run_post /tmp --change-name loose --archive-dir "$SCN/plain/2026-01-03-loose" --gh-repo test/repo --dry-run
scenario no-git-falls-back "$(grep -qF '**Spectra change**: `openspec/changes/archive/2026-01-03-loose/`' "$(dry_body loose)"; echo $?)"
scenario no-git-path-absent "$(! grep -qF "$SCN/plain" "$(dry_body loose)"; echo $?)"

# 4. A repository whose origin is not --gh-repo gives no path prefix either.
R0="$SCN/r0"
new_repo "$R0" https://github.com/someone/elsewhere.git
mkdir -p "$R0/deep/openspec/changes/archive/2026-01-09-other"
printf '**GitHub-side tracker**: #9\n' > "$R0/deep/openspec/changes/archive/2026-01-09-other/proposal.md"
commit_all "$R0" 'chore: seed (#9)'
rm -f "$(dry_body other)"
run_post /tmp --change-name other --archive-dir "$R0/deep/openspec/changes/archive/2026-01-09-other" --gh-repo test/repo --dry-run
scenario other-origin-no-prefix "$(grep -qF '**Spectra change**: `openspec/changes/archive/2026-01-09-other/`' "$(dry_body other)"; echo $?)"

# 5. A real post needs the caller's review level, and goes through the wrapper.
run_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo
scenario no-attestation-not-posted "$(! posted && outcome_starts '(failed — not posted: run this step with --dry-run'; echo $?)"
run_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo --scrub-attested loud
scenario bad-attestation-usage-error "$([ "$RC" = 2 ] && ! posted; echo $?)"
review_then_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo --scrub-attested light
scenario egress-posts-url "$([ "$OUT" = 'https://github.com/test/repo/issues/7#issuecomment-1' ] && [ "$RC" = 0 ]; echo $?)"
scenario egress-sends-relative-body "$(grep -qF "$A1/" "$SCN/body.md" && ! grep -qF "$SCN" "$SCN/body.md"; echo $?)"
scenario egress-drops-attestation "$(grep -q '^issue comment 7 --repo test/repo' "$SCN/gh.log" && ! grep -q 'scrub-attested' "$SCN/gh.log"; echo $?)"

# 6. The gate refuses: nothing is posted and the outcome says why.
review_then_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo --scrub-attested warn --spec-deltas '/Users/someone/private'
scenario refused-reports-it "$([ "$RC" = 0 ] && outcome_starts '(failed — gh-egress refused'; echo $?)"
scenario refused-posts-nothing "$(! posted; echo $?)"

# 7. The repository level is a floor; enforce, an unreadable permission, or a caller's
#    own enforce never post.
GH_STUB_REPO=READ/false review_then_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo --scrub-attested light
scenario read-only-not-posted "$(! posted && outcome_starts '(failed — not posted at level enforce'; echo $?)"
GH_STUB_REPO=fail review_then_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo --scrub-attested warn
scenario repo-probe-failure-says-so "$(! posted && outcome_starts '(failed — could not read your permissions'; echo $?)"
review_then_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo --scrub-attested enforce
scenario caller-enforce-not-posted "$(! posted && outcome_starts '(failed — not posted at level enforce'; echo $?)"

# 8. A failed post keeps gh's reason.
GH_STUB_POST_FAIL=1 review_then_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo --scrub-attested warn
scenario post-failure-keeps-reason "$(case "$OUT" in *'Could not resolve to an issue'*) true ;; *) false ;; esac; echo $?)"

# 9. A missing wrapper is a refusal, not a fallback to raw gh.
mkdir -p "$SCN/elsewhere/.claude/scripts"
cp "$TARGET_SCRIPT" "$SCN/elsewhere/.claude/scripts/post-ic.sh"
POST_SCRIPT="$SCN/elsewhere/.claude/scripts/post-ic.sh" review_then_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo --scrub-attested warn
scenario missing-wrapper-not-posted "$(! posted && case "$OUT" in *gh-egress*) true ;; *) false ;; esac; echo $?)"

# 10. The case that opened #405, as round 1 of its verify replayed it: prose about
#     the sandbox (seed issue #1, issue #3, issue #6, and one line about its #4), and
#     a subject that names the sandbox's PR #4 before this repo's group (#400).
R2="$SCN/r2"
S2=openspec/changes/archive/2026-01-04-spike
new_repo "$R2"
mkdir -p "$R2/openspec/changes/spike"
printf '# Spike\n\nprivate repo sandbox, with seed issue #1.\n' > "$R2/openspec/changes/spike/proposal.md"
printf 'opened issue #3, then issue #6 in the sandbox.\nThe sandbox opened issue #4 and merged it.\nIts PR #2 said `Refs #1`, and PR #4 said `Refs #3`.\n' > "$R2/openspec/changes/spike/findings.md"
printf -- '- [x] 1.1 done\n' > "$R2/openspec/changes/spike/tasks.md"
commit_all "$R2" 'docs: propose spike (#400)'
printf 'run log\n' > "$R2/openspec/changes/spike/run.md"
commit_all "$R2" 'docs: record spike run — sandbox PR #4, verify PASS (#400)'
mkdir -p "$R2/openspec/changes/archive"
mv "$R2/openspec/changes/spike" "$R2/$S2"
run_post "$R2" --change-name spike --archive-dir "$S2" --gh-repo test/repo --dry-run
scenario spike-before-archive-commit "$(outcome_is 400; echo $?)"

# 11. The same from /tmp with an absolute path, and from inside another repository.
run_post /tmp --change-name spike --archive-dir "$R2/$S2" --gh-repo test/repo --dry-run
scenario spike-from-outside-repo "$(outcome_is 400; echo $?)"
R7="$SCN/r7"
new_repo "$R7"
mkdir -p "$R7/openspec/changes/spike"
printf 'x\n' > "$R7/openspec/changes/spike/proposal.md"
commit_all "$R7" 'docs: unrelated spike (#1)'
run_post "$R7" --change-name spike --archive-dir "$R2/$S2" --gh-repo test/repo --dry-run
scenario spike-from-another-repo "$(outcome_is 400; echo $?)"

# 12. Same case after the archive commit.
commit_all "$R2" 'chore: archive spike (#400)'
run_post "$R2" --change-name spike --archive-dir "$S2" --gh-repo test/repo --dry-run
scenario spike-after-archive-commit "$(outcome_is 400; echo $?)"

# 13. A squash subject carries the PR number too: the explicit Refs picks the issue.
R3="$SCN/r3"
new_repo "$R3"
mkdir -p "$R3/openspec/changes/archive/2026-01-05-squashed"
printf 'Refs #331\n\nSee also issue #120.\n' > "$R3/openspec/changes/archive/2026-01-05-squashed/proposal.md"
commit_all "$R3" 'feat: squashed work (#331) (#334)'
GH_STUB_PRS=334 run_post "$R3" --change-name squashed --archive-dir openspec/changes/archive/2026-01-05-squashed --gh-repo test/repo --dry-run
scenario squash-intersection "$(outcome_is 331; echo $?)"

# 14. A squash subject with only the PR number: the PR is dropped, the Refs remains.
R8="$SCN/r8"
new_repo "$R8"
mkdir -p "$R8/openspec/changes/archive/2026-01-10-only-pr"
printf 'Refs #465\n' > "$R8/openspec/changes/archive/2026-01-10-only-pr/proposal.md"
commit_all "$R8" 'feat: add thing (#468)'
GH_STUB_PRS=468 run_post "$R8" --change-name only-pr --archive-dir openspec/changes/archive/2026-01-10-only-pr --gh-repo test/repo --dry-run
scenario pr-only-subject-keeps-refs "$(outcome_is 465; echo $?)"

# 15. An explicit Closes that disagrees with an issue number from the commits is asked.
R9="$SCN/r9"
new_repo "$R9"
mkdir -p "$R9/openspec/changes/archive/2026-01-11-disagree"
printf 'Closes #10\n' > "$R9/openspec/changes/archive/2026-01-11-disagree/proposal.md"
commit_all "$R9" 'docs: tidy spectra tasks (#20)'
run_post "$R9" --change-name disagree --archive-dir openspec/changes/archive/2026-01-11-disagree --gh-repo test/repo --dry-run
scenario explicit-refs-disagreement-asks "$([ "$RC" = 75 ] && grep -qx 10 /tmp/spectra-archive-candidates.txt && grep -qx 20 /tmp/spectra-archive-candidates.txt; echo $?)"

# 15b. The same conflict is still asked when a weak `issue #N` mention matches the commit
#      (verify round 2, Codex).
R15="$SCN/r15"
new_repo "$R15"
mkdir -p "$R15/openspec/changes/archive/2026-01-17-masked"
printf 'Closes #10\nSee also issue #20.\n' > "$R15/openspec/changes/archive/2026-01-17-masked/proposal.md"
commit_all "$R15" 'docs: update change (#20)'
run_post "$R15" --change-name masked --archive-dir openspec/changes/archive/2026-01-17-masked --gh-repo test/repo --dry-run
scenario weak-overlap-does-not-hide-conflict "$([ "$RC" = 75 ] && grep -qx 10 /tmp/spectra-archive-candidates.txt && grep -qx 20 /tmp/spectra-archive-candidates.txt; echo $?)"

# 16. A change whose only commit number is a pull request has no candidate at all.
R10="$SCN/r10"
new_repo "$R10"
mkdir -p "$R10/openspec/changes/archive/2026-01-12-pr-only"
printf 'no reference here\n' > "$R10/openspec/changes/archive/2026-01-12-pr-only/proposal.md"
commit_all "$R10" 'feat: runtime notes (#201)'
GH_STUB_PRS=201 run_post "$R10" --change-name pr-only --archive-dir openspec/changes/archive/2026-01-12-pr-only --gh-repo test/repo --dry-run
scenario pr-number-not-posted "$(outcome_starts '(none'; echo $?)"
GH_STUB_MISSING=201 run_post "$R10" --change-name pr-only --archive-dir openspec/changes/archive/2026-01-12-pr-only --gh-repo test/repo --dry-run
scenario missing-number-not-posted "$(outcome_starts '(none'; echo $?)"

# 17. When the issue/PR check cannot run, a lone commit number is asked, not posted.
GH_STUB_API_FAIL=1 run_post "$R10" --change-name pr-only --archive-dir openspec/changes/archive/2026-01-12-pr-only --gh-repo test/repo --dry-run
scenario unverified-number-asks "$([ "$RC" = 75 ] && grep -qx 201 /tmp/spectra-archive-candidates.txt; echo $?)"

# 18. A cluster commit touched the archive; the prose number lives on the pre-move path.
R4="$SCN/r4"
new_repo "$R4"
mkdir -p "$R4/openspec/changes/cluster"
printf 'Refs #148\n' > "$R4/openspec/changes/cluster/proposal.md"
commit_all "$R4" 'feat: default flip (#148)'
mkdir -p "$R4/openspec/changes/archive"
git -C "$R4" mv openspec/changes/cluster openspec/changes/archive/2026-01-06-cluster
commit_all "$R4" 'feat: cluster work (#137 #150)'
run_post "$R4" --change-name cluster --archive-dir openspec/changes/archive/2026-01-06-cluster --gh-repo test/repo --dry-run
scenario cluster-uses-pre-move-commits "$(outcome_is 148; echo $?)"

# 19. Commits whose groups name no prose number still win over `issue #N` prose.
R5="$SCN/r5"
new_repo "$R5"
mkdir -p "$R5/openspec/changes/archive/2026-01-07-lone"
printf 'with seed issue #1.\n' > "$R5/openspec/changes/archive/2026-01-07-lone/proposal.md"
commit_all "$R5" 'chore: archive lone (#500)'
run_post "$R5" --change-name lone --archive-dir openspec/changes/archive/2026-01-07-lone --gh-repo test/repo --dry-run
scenario commits-beat-weak-prose "$(outcome_is 500; echo $?)"

# 20. A cross-repo number in a commit subject does not become a candidate.
R6="$SCN/r6"
new_repo "$R6"
mkdir -p "$R6/openspec/changes/archive/2026-01-08-subject"
printf 'no reference here\n' > "$R6/openspec/changes/archive/2026-01-08-subject/proposal.md"
commit_all "$R6" 'chore: archive subject (#600), see other/sandbox#7'
run_post "$R6" --change-name subject --archive-dir openspec/changes/archive/2026-01-08-subject --gh-repo test/repo --dry-run
scenario cross-repo-commit-subject "$(outcome_is 600; echo $?)"

# 21. A body line `Refs #N` counts as a commit reference.
R11="$SCN/r11"
new_repo "$R11"
mkdir -p "$R11/openspec/changes/archive/2026-01-13-body"
printf 'no reference here\n' > "$R11/openspec/changes/archive/2026-01-13-body/proposal.md"
commit_all "$R11" 'docs: body reference only' 'Refs #700'
run_post "$R11" --change-name body --archive-dir openspec/changes/archive/2026-01-13-body --gh-repo test/repo --dry-run
scenario body-refs-line "$(outcome_is 700; echo $?)"

# 21b. Several Refs on one body line all count; the prose picks the archive's own.
R13="$SCN/r13"
new_repo "$R13"
mkdir -p "$R13/openspec/changes/archive/2026-01-15-cluster-body"
printf 'Codified as issue #150.\n' > "$R13/openspec/changes/archive/2026-01-15-cluster-body/design.md"
commit_all "$R13" 'feat: #137 one thing + #150 another (cluster)' 'Refs #137 Refs #150 Refs #154'
run_post "$R13" --change-name cluster-body --archive-dir openspec/changes/archive/2026-01-15-cluster-body --gh-repo test/repo --dry-run
scenario body-refs-several-on-a-line "$(outcome_is 150; echo $?)"

# 21c. A Refs written outside code still disagrees with the commits and is asked;
#      the same Refs quoted in code does not.
R14="$SCN/r14"
new_repo "$R14"
mkdir -p "$R14/openspec/changes/archive/2026-01-16-quoted"
printf 'The upstream PR body said `Refs #12`.\n' > "$R14/openspec/changes/archive/2026-01-16-quoted/proposal.md"
commit_all "$R14" 'docs: quoted refs (#800)'
run_post "$R14" --change-name quoted --archive-dir openspec/changes/archive/2026-01-16-quoted --gh-repo test/repo --dry-run
scenario quoted-refs-is-weak "$(outcome_is 800; echo $?)"
printf 'Refs #12\n' > "$R14/openspec/changes/archive/2026-01-16-quoted/design.md"
run_post "$R14" --change-name quoted --archive-dir openspec/changes/archive/2026-01-16-quoted --gh-repo test/repo --dry-run
scenario unquoted-refs-still-asks "$([ "$RC" = 75 ] && grep -qx 12 /tmp/spectra-archive-candidates.txt && grep -qx 800 /tmp/spectra-archive-candidates.txt; echo $?)"

# 22. Bytes that are not UTF-8 do not cost the marker in the same file.
R12="$SCN/r12"
new_repo "$R12"
mkdir -p "$R12/openspec/changes/archive/2026-01-14-bytes"
printf '**GitHub-side tracker**: #400\ncaf\351 notes\n' > "$R12/openspec/changes/archive/2026-01-14-bytes/proposal.md"
commit_all "$R12" 'chore: wip (#7)'
LC_ALL=en_US.UTF-8 run_post "$R12" --change-name bytes --archive-dir openspec/changes/archive/2026-01-14-bytes --gh-repo test/repo --dry-run
scenario non-utf8-keeps-marker "$(outcome_is 400; echo $?)"

# 23. Python modules planted in the cwd are not imported.
mkdir -p "$SCN/planted"
printf 'open("%s/planted/ran", "w").close()\n' "$SCN" > "$SCN/planted/re.py"
cp "$SCN/planted/re.py" "$SCN/planted/subprocess.py"
run_post "$SCN/planted" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo --dry-run
scenario cwd-modules-not-imported "$([ ! -e "$SCN/planted/ran" ] && outcome_is 7; echo $?)"

# 24. Without a dry run there is nothing reviewed, so nothing is posted.
rm -f "$(dry_body demo)"
run_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo --scrub-attested warn
scenario no-dry-run-not-posted "$(! posted && outcome_starts '(failed — not posted: the body or the issue'; echo $?)"

# 25. A body that changed after the review is not posted.
run_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo --dry-run
printf -- '- [x] 1.2 added after the review\n' >> "$R1/$A1/tasks.md"
run_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo --scrub-attested warn
scenario changed-body-not-posted "$(! posted && outcome_starts '(failed — not posted: the body or the issue'; echo $?)"
git -C "$R1" checkout -q -- "$A1/tasks.md"

# 26. An issue that detection resolves differently after the review is not posted.
run_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo --dry-run
printf '**GitHub-side tracker**: #8\n' > "$R1/$A1/proposal.md"
run_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo --scrub-attested warn
scenario changed-target-not-posted "$(! posted && outcome_starts '(failed — not posted: the body or the issue (#8)'; echo $?)"
git -C "$R1" checkout -q -- "$A1/proposal.md"

# 27. The review copy is private, and a symlink planted at its name is not followed.
printf 'keep me\n' > "$SCN/victim"
rm -f "$(dry_body demo)"
ln -s "$SCN/victim" "$(dry_body demo)"
run_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo --dry-run
scenario review-copy-symlink-not-followed "$([ "$(cat "$SCN/victim")" = 'keep me' ] && [ -f "$(dry_body demo)" ] && [ ! -L "$(dry_body demo)" ]; echo $?)"
scenario review-copy-private "$(ls -ld "$SPECTRA_POST_IC_STATE_DIR" | grep -q '^drwx------' && ls -l "$(dry_body demo)" | grep -q '^-rw-------'; echo $?)"

# 28. After a successful post the review copy is gone.
review_then_post "$R1" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo --scrub-attested warn
scenario review-copy-removed-after-post "$(posted && [ ! -e "$(dry_body demo)" ]; echo $?)"

# 29. The real post does not import Python modules planted in the cwd either.
rm -f "$SCN/planted/ran"
printf 'open("%s/planted/ran", "w").close()\n' "$SCN" > "$SCN/planted/pathlib.py"
cp "$SCN/planted/pathlib.py" "$SCN/planted/json.py"
review_then_post "$SCN/planted" --change-name demo --archive-dir "$R1/$A1" --gh-repo test/repo --scrub-attested warn
scenario real-post-cwd-modules-not-imported "$([ ! -e "$SCN/planted/ran" ] && posted; echo $?)"

# 30. Without --gh-repo the target comes from the archive's repository, not the cwd's.
R16="$SCN/r16"
new_repo "$R16" https://github.com/test/other.git
mkdir -p "$R16/x"; printf 'x\n' > "$R16/x/f"; commit_all "$R16" 'chore: other repo (#1)'
run_post "$R16" --change-name spike --archive-dir "$R2/$S2" --dry-run
scenario no-gh-repo-uses-archive-repo "$(outcome_is 400; echo $?)"

# 31. A transport error whose URL contains 404 is not read as "not found".
R17="$SCN/r17"
new_repo "$R17"
mkdir -p "$R17/openspec/changes/archive/2026-01-18-url404"
printf 'Sandbox notes: seed issue #1.\n' > "$R17/openspec/changes/archive/2026-01-18-url404/proposal.md"
commit_all "$R17" 'feat: thing (#404)'
GH_STUB_API_FAIL=1 run_post "$R17" --change-name url404 --archive-dir openspec/changes/archive/2026-01-18-url404 --gh-repo test/repo --dry-run
scenario transport-error-is-not-404 "$([ "$RC" = 75 ] && grep -qx 404 /tmp/spectra-archive-candidates.txt; echo $?)"

# 32. Explicit references that commits only partly cover are asked.
R18="$SCN/r18"
new_repo "$R18"
mkdir -p "$R18/openspec/changes/archive/2026-01-19-partial"
printf 'Closes #10\nRefs #20\n' > "$R18/openspec/changes/archive/2026-01-19-partial/proposal.md"
commit_all "$R18" 'docs: update change (#20)'
run_post "$R18" --change-name partial --archive-dir openspec/changes/archive/2026-01-19-partial --gh-repo test/repo --dry-run
scenario partial-explicit-overlap-asks "$([ "$RC" = 75 ] && grep -qx 10 /tmp/spectra-archive-candidates.txt && grep -qx 20 /tmp/spectra-archive-candidates.txt; echo $?)"

# 33. This repository's full form stays explicit in prose and stays a group in subjects.
R19="$SCN/r19"
new_repo "$R19"
mkdir -p "$R19/openspec/changes/archive/2026-01-20-fullform"
printf 'Closes test/repo#10\n' > "$R19/openspec/changes/archive/2026-01-20-fullform/proposal.md"
commit_all "$R19" 'docs: update change (#20)'
run_post "$R19" --change-name fullform --archive-dir openspec/changes/archive/2026-01-20-fullform --gh-repo test/repo --dry-run
scenario full-form-closes-stays-explicit "$([ "$RC" = 75 ] && grep -qx 10 /tmp/spectra-archive-candidates.txt; echo $?)"
R20="$SCN/r20"
new_repo "$R20"
mkdir -p "$R20/openspec/changes/archive/2026-01-21-fullgroup"
printf 'with seed issue #1.\n' > "$R20/openspec/changes/archive/2026-01-21-fullgroup/proposal.md"
commit_all "$R20" 'feat: playbook (Refs test/repo#102)'
printf 'more\n' >> "$R20/openspec/changes/archive/2026-01-21-fullgroup/proposal.md"
commit_all "$R20" 'chore: archive (#103)'
run_post "$R20" --change-name fullgroup --archive-dir openspec/changes/archive/2026-01-21-fullgroup --gh-repo test/repo --dry-run
scenario full-form-group-is-a-group "$([ "$RC" = 75 ] && grep -qx 102 /tmp/spectra-archive-candidates.txt && grep -qx 103 /tmp/spectra-archive-candidates.txt; echo $?)"

# 33b. A bare full-form mention of this repository is still a mention.
R23="$SCN/r23"
new_repo "$R23"
mkdir -p "$R23/openspec/changes/archive/2026-01-24-bare"
printf 'Designed for test/repo#135 and its sisters.\n' > "$R23/openspec/changes/archive/2026-01-24-bare/design.md"
commit_all "$R23" 'feat: skill (#135)' 'Refs #135
Refs #136 #137 (sister concerns)'
run_post "$R23" --change-name bare --archive-dir openspec/changes/archive/2026-01-24-bare --gh-repo test/repo --dry-run
scenario bare-full-form-is-a-mention "$(outcome_is 135; echo $?)"

# 34. The link /spectra-propose writes counts as explicit.
R21="$SCN/r21"
new_repo "$R21"
mkdir -p "$R21/openspec/changes/archive/2026-01-22-proposed"
printf 'This change was proposed referencing issue #400.\n' > "$R21/openspec/changes/archive/2026-01-22-proposed/proposal.md"
commit_all "$R21" 'docs: propose follow-up change (#398)'
run_post "$R21" --change-name proposed --archive-dir openspec/changes/archive/2026-01-22-proposed --gh-repo test/repo --dry-run
scenario referencing-issue-is-explicit "$([ "$RC" = 75 ] && grep -qx 400 /tmp/spectra-archive-candidates.txt && grep -qx 398 /tmp/spectra-archive-candidates.txt; echo $?)"

# 35. A prose-only candidate that is a pull request is not posted to.
R22="$SCN/r22"
new_repo "$R22"
mkdir -p "$R22/openspec/changes/archive/2026-01-23-prose-pr"
printf 'Refs #208\n' > "$R22/openspec/changes/archive/2026-01-23-prose-pr/proposal.md"
commit_all "$R22" 'docs: seed'
GH_STUB_PRS=208 run_post "$R22" --change-name prose-pr --archive-dir openspec/changes/archive/2026-01-23-prose-pr --gh-repo test/repo --dry-run
scenario prose-pr-not-posted "$(outcome_starts '(none'; echo $?)"

# 36. --help prints the whole header, through the review options.
scenario help-shows-review-options "$(bash "$TARGET_SCRIPT" --help | grep -q 'scrub-attested' && bash "$TARGET_SCRIPT" --help | grep -q 'what was reviewed is what'; echo $?)"

echo ""
echo "─── Summary ───"
echo "PASS: $PASS"
echo "FAIL: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo "Failed tests: ${FAILED_TESTS[*]}"
  exit 1
fi
exit 0
