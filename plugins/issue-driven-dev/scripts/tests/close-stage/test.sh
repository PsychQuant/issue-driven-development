#!/usr/bin/env bash
# close-stage suite (#392) — scripts/close-stage.py runs /idd-all's close stage
# in one process: every guardrail, then the squash merge or the push.
#
# gh is replaced by fake-gh.py (answers from a scenario directory, logs every
# call); git is real: each scenario gets a throwaway repository, and the
# direct-commit cases push to a local bare remote. Each guardrail is checked
# twice: the run stops with the expected reason, and the merge / push did NOT
# happen.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
CS="$HERE/../../close-stage.py"
FAKE="$HERE/fake-gh.py"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/idd-close-stage-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
export IDD_SLEEP=0
# Isolate git from the caller's configuration (#452 lesson).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
REPO=o/r; N=7

field() { python3 -c 'import json,sys; d=json.loads(sys.stdin.read() or "{}"); v=d.get(sys.argv[1], "<missing>"); print(v)' "$1"; }

new_scenario() { # name → sets S (scenario dir), C (clone), SHA
  S="$WORK/$1"; mkdir -p "$S/gh"; C="$S/clone"
  git init -q -b main "$S/remote.git" --bare
  git init -q -b main "$C"
  git -C "$C" remote add origin "$S/remote.git"
  echo base > "$C/f.txt"; git -C "$C" add f.txt; git -C "$C" commit -q -m "base"
  git -C "$C" push -q origin main
  echo "me" > "$S/gh/login"
}

work_commit() { # message (on the current branch)
  echo "$RANDOM" >> "$C/f.txt"; git -C "$C" commit -q -am "$1"; SHA=$(git -C "$C" rev-parse HEAD)
}

verify_comment() { # login sha verdict-line action-rows-json-ish → comments.json
  python3 - "$S/gh/comments.json" "$1" "$2" "$3" <<'EOF'
import json, sys
path, login, sha, verdict = sys.argv[1:5]
body = (f"## Verify: #7 — round 1\n\n### Aggregate\n{verdict}\n\n**Reviewed**: `{sha}`\n\n"
        "### Findings（合併後）\n| # | Severity | Finding | Source | Action |\n|---|---|---|---|---|\n")
diag = "## Diagnosis\n\n### Type\nbug\n"
try:
    cs = json.load(open(path))
except Exception:
    cs = [{"id": 1, "html_url": "u1", "user": {"login": "me"}, "author_association": "OWNER", "body": diag}]
cs.append({"id": len(cs) + 1, "html_url": f"https://example.test/c{len(cs)+1}", "user": {"login": login},
           "author_association": "MEMBER", "body": body})
json.dump(cs, open(path, "w"))
EOF
}

pr_fixture() { # head-sha [title]
  printf '[{"number": 9, "headRefName": "idd/7-x", "baseRefName": "main", "headRefOid": "%s", "title": "%s", "url": "https://example.test/pr/9"}]' \
    "$1" "${2:-feat: thing (#7)}" > "$S/gh/prs.json"
  echo '{"state": "MERGED", "mergeCommit": {"oid": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}' > "$S/gh/after-merge.json"
  echo '[]' > "$S/gh/refs.json"
  printf '[{"oid": "%s", "messageHeadline": "feat: thing (#7)", "messageBody": "Refs #7"}]' "$1" > "$S/gh/commits.json"
  echo '[{"name": "test", "bucket": "pass"}]' > "$S/gh/checks-1.json"
}

init_state() { # path [extra switches]
  local path="$1"; shift
  local branch=main; [ "$path" = PR ] && branch="idd/7-x"
  python3 "$CS" init --cwd "$C" --repo $REPO --issue $N --path "$path" --interaction unattended \
    --branch "$branch" --default main "$@" >/dev/null
}

run_stage() { # → OUT, RC
  OUT=$(IDD_GH="$FAKE" FAKE_GH_DIR="$S/gh" python3 "$CS" run --cwd "$C" --repo $REPO --issue $N --ci-timeout 0.5 --ci-grace 0 2>"$S/err"); RC=$?
}

merged_calls() { [ -f "$S/gh/calls.log" ] || { echo 0; return; }; grep -c '"merge"' "$S/gh/calls.log"; }

pr_scenario() { # name → a PR-mode scenario ready to merge
  new_scenario "$1"
  git -C "$C" checkout -q -b idd/7-x; work_commit "feat: thing (#7)"
  pr_fixture "$SHA"; verify_comment me "$SHA" "**PASS** — 0 blocking, 0 follow-up"; init_state PR
}

echo "close-stage: PR mode"
pr_scenario happy; run_stage
assert_eq "clean run: merged" "merged" "$(printf '%s' "$OUT" | field status)"
assert_exit "clean run: exit" 0 "$RC"
assert_output_grep "merge is a squash pinned to the verified head" "\"--match-head-commit\", \"$SHA\"" "$S/gh/calls.log"
assert_output_grep "squash subject is the PR title plus the PR number" '"--subject", "feat: thing (#7) (#9)"' "$S/gh/calls.log"
assert_output_grep "squash body references the issue with Refs" 'Refs #7' "$S/gh/calls.log"
assert_eq "result names the merge commit" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "$(printf '%s' "$OUT" | field merge_sha)"
assert_file_exists "result is written to the state dir" "$C/.claude/.idd/state/idd-all-result-7.json"

stop_case() { # name expected-reason-substring
  assert_eq "$1: stopped" "stopped" "$(printf '%s' "$OUT" | field status)"
  assert_exit "$1: exit" 3 "$RC"
  assert_grep "$1: reason" "$2" "$(printf '%s' "$OUT" | field reason)"
  assert_eq "$1: no merge call" "0" "$(merged_calls)"
}

pr_scenario review; init_state PR --review; run_stage; stop_case "--review" "--review"
pr_scenario chain; init_state PR --in-chain; run_stage; stop_case "--in-chain" "--in-chain"
pr_scenario nostate; rm -f "$C/.claude/.idd/state/idd-all-run-7.json"; run_stage; stop_case "no run state" "no run state"
pr_scenario forged; rm "$S/gh/comments.json"; verify_comment someone-else "$SHA" "**PASS** — 0 blocking, 0 follow-up"; run_stage
stop_case "a report by another account" "guardrail 1"
pr_scenario othersha; rm "$S/gh/comments.json"; verify_comment me "1111111111111111111111111111111111111111" "**PASS** — 0 blocking, 0 follow-up"; run_stage
stop_case "a report on another commit" "Reviewed"
pr_scenario failverdict; rm "$S/gh/comments.json"; verify_comment me "$SHA" "**FAIL** — 1 blocking"; run_stage
stop_case "a FAIL report" "guardrail 1"
pr_scenario cifail; echo '[{"name": "test", "bucket": "fail"}]' > "$S/gh/checks-1.json"; run_stage
stop_case "a failed check" "failed: test"
pr_scenario cipending; echo '[{"name": "test", "bucket": "pending"}]' > "$S/gh/checks-1.json"; echo 8 > "$S/gh/checks.rc"
echo '[{"name": "test", "bucket": "pass"}]' > "$S/gh/checks-2.json"; run_stage
assert_eq "a pending check that then passes: merged" "merged" "$(printf '%s' "$OUT" | field status)"
pr_scenario nochecks; rm "$S/gh/checks-1.json"; run_stage
assert_eq "no checks and no pull_request workflow: merged" "merged" "$(printf '%s' "$OUT" | field status)"
pr_scenario nochecks-wf; rm "$S/gh/checks-1.json"; mkdir -p "$C/.github/workflows"
printf 'on:\n  pull_request:\n' > "$C/.github/workflows/t.yml"; git -C "$C" add .github; work_commit "ci (#7)"
pr_fixture "$SHA"; rm "$S/gh/checks-1.json" "$S/gh/comments.json"; verify_comment me "$SHA" "**PASS** — 0 blocking, 0 follow-up"; run_stage
stop_case "no checks yet although a workflow runs on pull_request" "guardrail 2"
pr_scenario closing; echo '[{"url": "https://example.test/issues/7"}]' > "$S/gh/refs.json"; run_stage
stop_case "the PR body would close the issue" "guardrail 3"
for body in "after merge run /idd-close #7" "fixes o/r#5" "Resolves: https://github.com/o/r/issues/5"; do
  pr_scenario "trap-$RANDOM"; printf '[{"oid": "%s", "messageHeadline": "x (#7)", "messageBody": "%s"}]' "$SHA" "$body" > "$S/gh/commits.json"; run_stage
  stop_case "commit body: $body" "guardrail 3"
done
pr_scenario title; pr_fixture "$SHA" "login bug, fixes #3"; run_stage
stop_case "a PR title that would close another issue" "guardrail 4"
pr_scenario mergefail; echo 1 > "$S/gh/merge.rc"; run_stage
assert_eq "gh pr merge fails: stopped" "stopped" "$(printf '%s' "$OUT" | field status)"
assert_grep "gh pr merge fails: reason" "still open" "$(printf '%s' "$OUT" | field reason)"
pr_scenario queued; echo '{"state": "OPEN", "mergeCommit": null}' > "$S/gh/after-merge.json"; run_stage
assert_eq "merge queued, PR still open: stopped" "stopped" "$(printf '%s' "$OUT" | field status)"
assert_grep "merge queued: reason" "merge queue" "$(printf '%s' "$OUT" | field reason)"
pr_scenario readonly; echo READ > "$S/gh/perm"; run_stage; stop_case "read-only permission" "permission"
pr_scenario meeting; python3 - "$S/gh/comments.json" <<'EOF'
import json, sys
cs = json.load(open(sys.argv[1])); cs[0]["body"] = "## Diagnosis\n\n### Type\nmeeting\n"; json.dump(cs, open(sys.argv[1], "w"))
EOF
run_stage; stop_case "a meeting issue" "meeting"
pr_scenario twoprs; python3 - "$S/gh/prs.json" <<'EOF'
import json, sys
p = json.load(open(sys.argv[1])); p.append(dict(p[0], number=10)); json.dump(p, open(sys.argv[1], "w"))
EOF
run_stage; stop_case "two open PRs from the branch" "exactly one open PR"
pr_scenario moved; work_commit "local only (#7)"; run_stage; stop_case "the local head moved past the PR head" "not this run's commit"

echo "close-stage: direct-commit mode"
direct_scenario() { new_scenario "$1"; work_commit "fix: thing (#7)"; verify_comment me "$SHA" "**PASS** — 0 blocking, 0 follow-up"; init_state direct-commit; }
direct_scenario dhappy; run_stage
assert_eq "direct: pushed" "pushed" "$(printf '%s' "$OUT" | field status)"
assert_eq "direct: the remote has the commit" "$SHA" "$(git -C "$S/remote.git" rev-parse main)"
direct_scenario dbranch; git -C "$C" checkout -q -b wip/foo; run_stage
assert_eq "direct: not on the default branch: stopped" "stopped" "$(printf '%s' "$OUT" | field status)"
assert_grep "direct: not on the default branch: reason" "wip/foo" "$(printf '%s' "$OUT" | field reason)"
direct_scenario dforeign; BASE=$(git -C "$S/remote.git" rev-parse main); work_commit "unrelated work"
rm "$S/gh/comments.json"; verify_comment me "$SHA" "**PASS** — 0 blocking, 0 follow-up"; run_stage
assert_eq "direct: a commit that is not this issue's: stopped" "stopped" "$(printf '%s' "$OUT" | field status)"
assert_eq "direct: nothing was pushed" "$BASE" "$(git -C "$S/remote.git" rev-parse main)"
direct_scenario dtrap; BASE=$(git -C "$S/remote.git" rev-parse main); work_commit "fix: #7 the thing"
rm "$S/gh/comments.json"; verify_comment me "$SHA" "**PASS** — 0 blocking, 0 follow-up"; run_stage
assert_grep "direct: a trap commit: reason" "close keyword" "$(printf '%s' "$OUT" | field reason)"
assert_eq "direct: a trap commit: nothing was pushed" "$BASE" "$(git -C "$S/remote.git" rev-parse main)"
direct_scenario dstale; work_commit "more (#7)"; run_stage
assert_grep "direct: the report reviewed an older commit: reason" "Reviewed" "$(printf '%s' "$OUT" | field reason)"

echo "close-stage: gate, init and usage"
pr_scenario gate
G=$(IDD_GH="$FAKE" FAKE_GH_DIR="$S/gh" python3 "$CS" gate --cwd "$C" --repo $REPO --issue $N --sha "$SHA"); RC=$?
assert_eq "gate: clean" "clean" "$(printf '%s' "$G" | field status)"
assert_exit "gate: exit" 0 "$RC"
assert_grep "gate: names the report" "https://example.test/c" "$(printf '%s' "$G" | field verify_url)"
G=$(IDD_GH="$FAKE" FAKE_GH_DIR="$S/gh" python3 "$CS" gate --cwd "$C" --repo $REPO --issue 70 --sha "$SHA"); RC=$?
assert_exit "gate: a report for #7 is not a report for #70" 2 "$RC"
python3 "$CS" gate --cwd "$C" --repo $REPO --issue $N --sha abc >/dev/null 2>&1; assert_exit "gate: a short sha is a usage error" 64 $?
python3 "$CS" run --cwd "$C" --repo "not a repo" --issue $N >/dev/null 2>&1; assert_exit "run: a malformed repo is a usage error" 64 $?
python3 "$CS" init --cwd "$C" --repo $REPO --issue $N --path sideways --interaction unattended --branch b --default main >/dev/null 2>&1
assert_exit "init: an unknown path is a usage error" 64 $?
python3 "$CS" bogus >/dev/null 2>&1; assert_exit "an unknown subcommand is a usage error" 64 $?

print_summary close-stage
