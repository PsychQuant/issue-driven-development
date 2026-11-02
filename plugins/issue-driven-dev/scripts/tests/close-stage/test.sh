#!/usr/bin/env bash
# close-stage suite (#392) — scripts/close-stage.py runs /idd-all's close stage
# in one process: every guardrail, then the squash merge or the push.
#
# gh is replaced by fake-gh.py (answers from a scenario directory, logs every
# call); git is real: each scenario gets a throwaway repository whose origin is
# a local bare remote at .../o/r.git (so the origin check sees repo o/r), and
# the direct-commit cases really push there. Each guardrail is checked twice:
# the run stops with the expected reason, and the merge / push did NOT happen.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
CS="$HERE/../../close-stage.py"
FAKE="$HERE/fake-gh.py"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/idd-close-stage-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
export IDD_CLOSE_STAGE_TEST=1 IDD_SLEEP=0
# Isolate git from the caller's configuration (#452 lesson).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
REPO=o/r; N=7

field() { python3 -c 'import json,sys; d=json.loads(sys.stdin.read() or "{}"); v=d.get(sys.argv[1], "<missing>"); print(v)' "$1"; }

new_scenario() { # name [workflow-file-content-on-main] → sets S (scenario dir), C (clone), SHA
  S="$WORK/$1"; mkdir -p "$S/gh" "$S/o"; C="$S/clone"
  git init -q -b main "$S/o/r.git" --bare
  git init -q -b main "$C"
  git -C "$C" remote add origin "$S/o/r.git"
  echo base > "$C/f.txt"; git -C "$C" add f.txt
  if [ -n "${2:-}" ]; then mkdir -p "$C/.github/workflows"; printf '%s\n' "$2" > "$C/.github/workflows/w.yml"; git -C "$C" add .github; fi
  git -C "$C" commit -q -m "base"
  git -C "$C" push -q origin main
  echo "me" > "$S/gh/login"
  export FAKE_REMOTE="$S/o/r.git"
}

work_commit() { # message (on the current branch)
  echo "$RANDOM" >> "$C/f.txt"; git -C "$C" commit -q -am "$1"; SHA=$(git -C "$C" rev-parse HEAD)
}

verify_comment() { # login head base verdict-line → append to comments.json
  python3 - "$S/gh/comments.json" "$1" "$2" "$3" "$4" <<'EOF'
import json, sys
path, login, head, base, verdict = sys.argv[1:6]
reviewed = f"{base}..{head}" if base != "-" else head
body = (f"## Verify: #7 — round 1\n\n### Aggregate\n{verdict}\n\n**Reviewed**: `{reviewed}`\n\n"
        "### Findings（合併後）\n| # | Severity | Finding | Source | Action |\n|---|---|---|---|---|\n")
diag = "## Diagnosis\n\n### Type\nbug\n"
try:
    cs = json.load(open(path))
except Exception:
    cs = [{"id": 1, "html_url": "u1", "user": {"login": "me"}, "author_association": "OWNER",
           "created_at": "2026-01-01T00:00:00Z", "body": diag}]
import time
cs.append({"id": len(cs) + 1, "html_url": f"https://example.test/c{len(cs)+1}", "user": {"login": login},
           "author_association": "MEMBER", "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 5)), "body": body})
json.dump(cs, open(path, "w"))
EOF
}
PASS_LINE="**PASS** — 0 blocking, 0 follow-up"
base_of() { git -C "$C" merge-base origin/main "$1"; }

pr_fixture() { # head-sha [title]
  printf '[{"number": 9, "headRefName": "idd/7-x", "baseRefName": "main", "headRefOid": "%s", "title": "%s", "url": "https://example.test/pr/9", "isCrossRepository": false}]' \
    "$1" "${2:-feat: thing (#7)}" > "$S/gh/prs.json"
  echo '{"state": "MERGED", "mergeCommit": {"oid": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}}' > "$S/gh/after-merge-1.json"
  echo '[]' > "$S/gh/refs.json"
  printf '[{"oid": "%s", "messageHeadline": "feat: thing (#7)", "messageBody": "Refs #7"}]' "$1" > "$S/gh/commits.json"
  echo '[{"name": "test", "bucket": "pass", "event": "pull_request"}]' > "$S/gh/checks-1.json"
}

init_state() { # path [requested-path] [review] [in-chain]
  local path="$1" req="${2:-$1}" review="${3:-no}" chain="${4:-no}"
  local branch=main; [ "$path" = PR ] && branch="idd/7-x"
  python3 "$CS" init --cwd "$C" --repo $REPO --issue $N --path "$path" --requested-path "$req" \
    --interaction unattended --branch "$branch" --default main --review "$review" --in-chain "$chain" >/dev/null
}

run_stage() { # → OUT, RC
  OUT=$(IDD_GH="$FAKE" FAKE_GH_DIR="$S/gh" python3 "$CS" run --cwd "$C" --repo $REPO --issue $N --ci-timeout 0.5 --ci-grace 0 2>"$S/err"); RC=$?
}

calls_with() { [ -f "$S/gh/calls.log" ] || { echo 0; return; }; grep -c -- "$1" "$S/gh/calls.log"; }
merged_calls() { calls_with '"merge", "9", "--repo", "o/r", "--squash"'; }

pr_scenario() { # name [workflow-on-main] → a PR-mode scenario ready to merge
  new_scenario "$1" "${2:-}"
  git -C "$C" checkout -q -b idd/7-x; work_commit "feat: thing (#7)"
  pr_fixture "$SHA"; verify_comment me "$SHA" "$(base_of "$SHA")" "$PASS_LINE"; init_state PR
}

stop_case() { # name expected-reason-substring
  assert_eq "$1: stopped" "stopped" "$(printf '%s' "$OUT" | field status)"
  assert_exit "$1: exit" 3 "$RC"
  assert_grep "$1: reason" "$2" "$(printf '%s' "$OUT" | field reason)"
  assert_eq "$1: no merge call" "0" "$(merged_calls)"
}

echo "close-stage: PR mode"
pr_scenario happy; run_stage
assert_eq "clean run: merged" "merged" "$(printf '%s' "$OUT" | field status)"
assert_exit "clean run: exit" 0 "$RC"
assert_output_grep "merge is a squash pinned to the verified head" "\"--match-head-commit\", \"$SHA\"" "$S/gh/calls.log"
assert_output_grep "squash subject is the PR title plus the PR number" '"--subject", "feat: thing (#7) (#9)"' "$S/gh/calls.log"
assert_output_grep "squash body references the issue with Refs" 'Refs #7' "$S/gh/calls.log"
assert_eq "result names the merge commit" "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "$(printf '%s' "$OUT" | field merge_sha)"
assert_grep "result records when it finished" "T" "$(printf '%s' "$OUT" | field done_at)"
assert_file_exists "result is written to the state dir" "$C/.claude/.idd/state/idd-all-result-7.json"
assert_eq "the gate is judged again after the CI wait" "2" "$(calls_with '"api", "user"')"

pr_scenario review; init_state PR PR yes no; run_stage; stop_case "--review" "--review"
pr_scenario chain; init_state PR PR no yes; run_stage; stop_case "--in-chain" "--in-chain"
pr_scenario degraded; init_state direct-commit PR; run_stage; stop_case "a run downgraded from PR mode" "downgraded"
pr_scenario nostate; rm -f "$C/.claude/.idd/state/idd-all-run-7.json"; run_stage; stop_case "no run state" "no run state"
pr_scenario stale; python3 - "$C/.claude/.idd/state/idd-all-run-7.json" <<'EOF'
import json, sys
p = sys.argv[1]; d = json.load(open(p)); d["created_at"] = "2020-01-01T00:00:00Z"; json.dump(d, open(p, "w"))
EOF
run_stage; stop_case "a run state from an earlier run" "24 hours"
pr_scenario stale-result; echo '{"status":"merged","pr":9,"merge_sha":"bbbb"}' > "$C/.claude/.idd/state/idd-all-result-7.json"
init_state PR PR yes no; run_stage
assert_eq "an earlier result file is not reused" "stopped" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$C/.claude/.idd/state/idd-all-result-7.json")"
pr_scenario forged; rm "$S/gh/comments.json"; verify_comment someone-else "$SHA" "$(base_of "$SHA")" "$PASS_LINE"
echo '{"permission":"read","role_name":"read"}' > "$S/gh/perm-someone-else.json"; run_stage
stop_case "a report by an account without write access" "write access"
pr_scenario teammate-fail; verify_comment teammate "$SHA" "$(base_of "$SHA")" "**FAIL** — 1 blocking"; run_stage
stop_case "a newer FAIL by a teammate with write access" "guardrail 1"
pr_scenario old-report; python3 - "$S/gh/comments.json" <<'EOF'
import json, sys
cs = json.load(open(sys.argv[1])); cs[-1]["created_at"] = "2026-01-01T00:00:00Z"; json.dump(cs, open(sys.argv[1], "w"))
EOF
run_stage; stop_case "a clean report from before this run" "since"
pr_scenario othersha; rm "$S/gh/comments.json"; verify_comment me "1111111111111111111111111111111111111111" "$(base_of "$SHA")" "$PASS_LINE"; run_stage
stop_case "a report on another commit" "Reviewed"
pr_scenario otherbase; rm "$S/gh/comments.json"; verify_comment me "$SHA" "2222222222222222222222222222222222222222" "$PASS_LINE"; run_stage
stop_case "a report on a shorter range than the PR" "range"
pr_scenario nobase; rm "$S/gh/comments.json"; verify_comment me "$SHA" "-" "$PASS_LINE"; run_stage
stop_case "a report naming only the tip commit" "range"
pr_scenario failverdict; rm "$S/gh/comments.json"; verify_comment me "$SHA" "$(base_of "$SHA")" "**FAIL** — 1 blocking"; run_stage
stop_case "a FAIL report" "guardrail 1"
pr_scenario cifail; echo '[{"name": "test", "bucket": "fail", "event": "pull_request"}]' > "$S/gh/checks-1.json"; run_stage
stop_case "a failed check" "failed: test"
pr_scenario cipending; echo '[{"name": "test", "bucket": "pending", "event": "pull_request"}]' > "$S/gh/checks-1.json"; echo 8 > "$S/gh/checks.rc"
echo '[{"name": "test", "bucket": "pass", "event": "pull_request"}]' > "$S/gh/checks-2.json"; run_stage
assert_eq "a pending check that then passes: merged" "merged" "$(printf '%s' "$OUT" | field status)"
pr_scenario nochecks; rm "$S/gh/checks-1.json"; run_stage
assert_eq "no checks and no pull_request workflow: merged" "merged" "$(printf '%s' "$OUT" | field status)"
wf_scenario() { # name → PR scenario whose default branch has a workflow on every pull_request
  pr_scenario "$1" $'on:\n  pull_request:\n'
}
wf_scenario nochecks-wf; rm "$S/gh/checks-1.json"; run_stage
stop_case "no checks yet although a workflow runs on every pull_request" "guardrail 2"
wf_scenario early-external; echo '[{"name": "cla", "bucket": "pass", "event": ""}]' > "$S/gh/checks-1.json"; run_stage
stop_case "only an external status, the pull_request workflow never reports" "no pull_request check"
wf_scenario late-pr-check; echo '[{"name": "cla", "bucket": "pass", "event": ""}]' > "$S/gh/checks-1.json"
echo '[{"name": "cla", "bucket": "pass", "event": ""}, {"name": "ci", "bucket": "fail", "event": "pull_request"}]' > "$S/gh/checks-2.json"; run_stage
stop_case "the pull_request check appears later and fails" "failed: ci"
pr_scenario pathfilter $'on:\n  pull_request:\n    paths: [docs/**]\n'; rm "$S/gh/checks-1.json"; run_stage
assert_eq "a path-filtered pull_request workflow does not make the stage wait for a check" "merged" "$(printf '%s' "$OUT" | field status)"
pr_scenario release $'on:\n  push:\n    branches: [main]\njobs:\n  r:\n    steps:\n      - run: gh release create v1\n'; run_stage
stop_case "a workflow on main that publishes on push" "publishes on push"
pr_scenario tagrelease $'on:\n  push:\n    tags: [\'v*\']\njobs:\n  r:\n    steps:\n      - run: gh release create v1\n'; run_stage
assert_eq "a release workflow triggered by tags only does not stop the stage" "merged" "$(printf '%s' "$OUT" | field status)"
pr_scenario editsci; mkdir -p "$C/.github/workflows"; printf 'on: push\n' > "$C/.github/workflows/new.yml"
git -C "$C" add .github; work_commit "ci (#7)"; pr_fixture "$SHA"; rm "$S/gh/comments.json"; verify_comment me "$SHA" "$(base_of "$SHA")" "$PASS_LINE"; run_stage
stop_case "a change that edits CI" "edits CI"
pr_scenario behind; git -C "$WORK/behind/clone" stash -q 2>/dev/null; ( cd "$WORK" && rm -rf behind-other && git clone -q "$S/o/r.git" behind-other && cd behind-other && echo x > g.txt && git add g.txt && git -c user.name=t -c user.email=t@e commit -q -m other && git push -q origin main ); run_stage
stop_case "a branch that fell behind the default branch" "behind"
pr_scenario queue; echo '{"data":{"repository":{"mergeQueue":{"id":"MQ"}}}}' > "$S/gh/mq.json"; run_stage
stop_case "a merge queue on the default branch" "merge queue"
pr_scenario closing; echo '[{"url": "https://example.test/issues/7"}]' > "$S/gh/refs.json"; run_stage
stop_case "the PR body would close the issue" "guardrail 3"
for body in "after merge run /idd-close #7" "fixes o/r#5" "Resolves: https://github.com/o/r/issues/5"; do
  pr_scenario "trap-$RANDOM"; echo "$RANDOM" >> "$C/f.txt"; git -C "$C" commit -q -am "x (#7)" -m "$body"; SHA=$(git -C "$C" rev-parse HEAD)
  pr_fixture "$SHA"; rm "$S/gh/comments.json"; verify_comment me "$SHA" "$(base_of "$SHA")" "$PASS_LINE"; run_stage
  stop_case "commit body: $body" "guardrail 3"
done
pr_scenario title; pr_fixture "$SHA" "login bug, fixes #3"; run_stage
stop_case "a PR title that would close another issue" "guardrail 4"
pr_scenario mergefail; echo 1 > "$S/gh/merge.rc"; echo '{"state": "OPEN", "mergeCommit": null}' > "$S/gh/after-merge-1.json"; run_stage
assert_eq "gh pr merge fails: stopped" "stopped" "$(printf '%s' "$OUT" | field status)"
assert_grep "gh pr merge fails: reason" "reads OPEN" "$(printf '%s' "$OUT" | field reason)"
pr_scenario mergeerr-but-merged; echo 1 > "$S/gh/merge.rc"; run_stage
assert_eq "gh pr merge errors but the PR is MERGED: merged" "merged" "$(printf '%s' "$OUT" | field status)"
pr_scenario stillopen; echo '{"state": "OPEN", "mergeCommit": null}' > "$S/gh/after-merge-1.json"; run_stage
assert_eq "still OPEN after merging: stopped" "stopped" "$(printf '%s' "$OUT" | field status)"
assert_grep "still OPEN after merging: auto-merge disabled" "auto-merge disabled" "$(printf '%s' "$OUT" | field reason)"
assert_eq "still OPEN after merging: the disable call was made" "1" "$(calls_with '"--disable-auto"')"
assert_eq "still OPEN after merging: the result says a merge was attempted" "True" "$(printf '%s' "$OUT" | field merge_attempted)"
pr_scenario lateconfirm; echo 'not json' > "$S/gh/after-merge-1.json"
echo '{"state": "MERGED", "mergeCommit": {"oid": "cccccccccccccccccccccccccccccccccccccccc"}}' > "$S/gh/after-merge-2.json"; run_stage
assert_eq "a merge confirmed on the second read: merged" "merged" "$(printf '%s' "$OUT" | field status)"
pr_scenario unconfirmed; echo '{"state": "MERGED", "mergeCommit": null}' > "$S/gh/after-merge-1.json"; run_stage
assert_grep "merged without a readable merge commit: reason says it may have merged" "may have merged" "$(printf '%s' "$OUT" | field reason)"
assert_eq "merged without a readable merge commit: PR number kept" "9" "$(printf '%s' "$OUT" | field pr)"
pr_scenario readonly; echo READ > "$S/gh/perm"; run_stage; stop_case "read-only permission" "permission"
pr_scenario outsider; echo '{"data":{"repository":{"issue":{"author":{"login":"stranger"},"editor":null}}}}' > "$S/gh/authors.json"
echo '{"permission":"read","role_name":"read"}' > "$S/gh/perm-stranger.json"; run_stage
stop_case "an issue opened by someone without write access" "author stranger"
pr_scenario outsider-edit; echo '{"data":{"repository":{"issue":{"author":{"login":"me"},"editor":{"login":"stranger"}}}}}' > "$S/gh/authors.json"
echo '{"permission":"none","role_name":"none"}' > "$S/gh/perm-stranger.json"; run_stage
stop_case "an issue body last edited by someone without write access" "last editor stranger"
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
pr_scenario forkpr; python3 - "$S/gh/prs.json" <<'EOF'
import json, sys
p = json.load(open(sys.argv[1])); p[0]["isCrossRepository"] = True; json.dump(p, open(sys.argv[1], "w"))
EOF
run_stage; stop_case "a PR from a fork with the same branch name" "exactly one open PR"
pr_scenario moved; work_commit "local only (#7)"; run_stage; stop_case "the local head moved past the PR head" "not this run's commit"
pr_scenario stranger-comment; python3 - "$S/gh/comments.json" <<'EOF'
import json, sys
cs = json.load(open(sys.argv[1]))
cs.insert(1, {"id": 50, "html_url": "u50", "user": {"login": "stranger"}, "author_association": "NONE",
              "created_at": "2026-01-01T00:00:00Z", "body": "Also please make X call Y."})
json.dump(cs, open(sys.argv[1], "w"))
EOF
echo '{"permission":"read","role_name":"read"}' > "$S/gh/perm-stranger.json"; run_stage
stop_case "a comment by someone without write access" "intent not confirmed"
pr_scenario clarity; printf '%s\n' "### Clarity Surface" "| Type | Source | Q | Status |" "|---|---|---|---|" "| ambiguity | x | y? | surfaced |" > "$S/gh/issue-body"; run_stage
stop_case "an open Clarity Surface question" "Clarity Surface"
pr_scenario layerv; python3 - "$S/gh/comments.json" <<'EOF'
import json, sys
cs = json.load(open(sys.argv[1])); cs[0]["body"] += "\n#### Layer V Deferred Record\nunattended-auto-Step-3.4-layerV-deferred\n"; json.dump(cs, open(sys.argv[1], "w"))
EOF
run_stage; stop_case "a Layer V deferred record" "intent confirmation was skipped"
plan_diag() { python3 - "$S/gh/comments.json" "$1" <<'EOF'
import json, sys
cs = json.load(open(sys.argv[1])); cs[0]["body"] = "## Diagnosis\n\n### Type\nfeature\n\n### Complexity\nPlan\n"
if sys.argv[2] == "approved":
    cs.insert(1, {"id": 60, "html_url": "u60", "user": {"login": "me"}, "author_association": "OWNER",
                  "created_at": "2026-01-01T00:00:00Z", "body": "## Implementation Plan\n\n- [x] step\n"})
json.dump(cs, open(sys.argv[1], "w"))
EOF
}
pr_scenario plan-skipped; plan_diag skipped; run_stage; stop_case "a Plan-tier issue without an Implementation Plan" "Plan tier"
pr_scenario plan-ok; plan_diag approved; run_stage
assert_eq "a Plan-tier issue with an approved Implementation Plan: merged" "merged" "$(printf '%s' "$OUT" | field status)"
pr_scenario crash; OUT=$(IDD_GH=/nonexistent/gh FAKE_GH_DIR="$S/gh" python3 "$CS" run --cwd "$C" --repo $REPO --issue $N 2>/dev/null); RC=$?
assert_eq "gh missing: stopped, not a traceback" "stopped" "$(printf '%s' "$OUT" | field status)"
assert_exit "gh missing: exit" 3 "$RC"

echo "close-stage: direct-commit mode"
direct_scenario() { new_scenario "$1"; work_commit "fix: thing (#7)"; verify_comment me "$SHA" "$(base_of "$SHA")" "$PASS_LINE"; init_state direct-commit; }
direct_scenario dhappy; run_stage
assert_eq "direct: pushed" "pushed" "$(printf '%s' "$OUT" | field status)"
assert_eq "direct: the remote has the verified commit" "$SHA" "$(git -C "$S/o/r.git" rev-parse main)"
direct_scenario dbranch; git -C "$C" checkout -q -b wip/foo; run_stage
assert_eq "direct: not on the default branch: stopped" "stopped" "$(printf '%s' "$OUT" | field status)"
assert_grep "direct: not on the default branch: reason" "wip/foo" "$(printf '%s' "$OUT" | field reason)"
direct_scenario dforeign; BASE=$(git -C "$S/o/r.git" rev-parse main); work_commit "unrelated work"
rm "$S/gh/comments.json"; verify_comment me "$SHA" "$(base_of "$SHA")" "$PASS_LINE"; run_stage
assert_grep "direct: a commit that is not this issue's: reason" "not this run's" "$(printf '%s' "$OUT" | field reason)"
assert_eq "direct: nothing was pushed" "$BASE" "$(git -C "$S/o/r.git" rev-parse main)"
direct_scenario dtrap; BASE=$(git -C "$S/o/r.git" rev-parse main); work_commit "fix: #7 the thing"
rm "$S/gh/comments.json"; verify_comment me "$SHA" "$(base_of "$SHA")" "$PASS_LINE"; run_stage
assert_grep "direct: a trap commit: reason" "close keyword" "$(printf '%s' "$OUT" | field reason)"
assert_eq "direct: a trap commit: nothing was pushed" "$BASE" "$(git -C "$S/o/r.git" rev-parse main)"
direct_scenario dstale; work_commit "more (#7)"; run_stage
assert_grep "direct: the report reviewed an older commit: reason" "Reviewed" "$(printf '%s' "$OUT" | field reason)"
direct_scenario dorigin; git -C "$C" remote set-url origin "$S/elsewhere/x.git"; run_stage
assert_grep "direct: origin is another repo: reason" "origin" "$(printf '%s' "$OUT" | field reason)"
direct_scenario dhost; git -C "$C" remote set-url origin "https://gitlab.example/o/r.git"; run_stage
assert_grep "direct: same owner/repo on another host: reason" "not github.com/o/r" "$(printf '%s' "$OUT" | field reason)"
direct_scenario dpushurl; BASE=$(git -C "$S/o/r.git" rev-parse main); git -C "$C" remote set-url --push origin "$S/elsewhere/o2/r2.git"; run_stage
assert_grep "direct: a push URL that points elsewhere: reason" "not github.com/o/r" "$(printf '%s' "$OUT" | field reason)"
assert_eq "direct: a push URL that points elsewhere: nothing pushed" "$BASE" "$(git -C "$S/o/r.git" rev-parse main)"

echo "close-stage: confirm-close"
confirm() { OUT=$(IDD_GH="$FAKE" FAKE_GH_DIR="$S/gh" python3 "$CS" confirm-close --cwd "$C" --repo $REPO --issue $N); RC=$?; }
summary_comment() { # login heading-line
  python3 - "$S/gh/comments.json" "$1" "$2" <<'EOF'
import json, sys, time
path, login, head = sys.argv[1:4]
cs = json.load(open(path))
cs.append({"id": 99, "html_url": "https://example.test/summary", "user": {"login": login}, "author_association": "OWNER",
           "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 60)), "body": head + "\n\n### Problem\nx\n"})
json.dump(cs, open(path, "w"))
EOF
}
pr_scenario cc-ok; run_stage; summary_comment me "## Closing Summary"; confirm
assert_eq "confirm: a summary by this account after the merge" "closed" "$(printf '%s' "$OUT" | field status)"
assert_exit "confirm: exit" 0 "$RC"
pr_scenario cc-mention; run_stage; summary_comment me "I still owe the closing summary"; confirm
assert_exit "confirm: a prose mention is not a summary" 3 "$RC"
pr_scenario cc-other; run_stage; summary_comment someone "## Closing Summary"; confirm
assert_exit "confirm: a summary by another account is not this run's" 3 "$RC"
pr_scenario cc-open; run_stage; summary_comment me "## Closing Summary"; echo OPEN > "$S/gh/issue-state"; confirm
assert_exit "confirm: the issue is still open" 3 "$RC"
pr_scenario cc-stopped; init_state PR PR yes no; run_stage; summary_comment me "## Closing Summary"; confirm
assert_exit "confirm: nothing was merged" 3 "$RC"

echo "close-stage: gate, init and usage"
pr_scenario gate
G=$(IDD_GH="$FAKE" FAKE_GH_DIR="$S/gh" python3 "$CS" gate --cwd "$C" --repo $REPO --issue $N --sha "$SHA" --base "$(base_of "$SHA")"); RC=$?
assert_eq "gate: clean" "clean" "$(printf '%s' "$G" | field status)"
assert_exit "gate: exit" 0 "$RC"
assert_grep "gate: names the report" "https://example.test/c" "$(printf '%s' "$G" | field verify_url)"
G=$(IDD_GH="$FAKE" FAKE_GH_DIR="$S/gh" python3 "$CS" gate --cwd "$C" --repo $REPO --issue 70 --sha "$SHA"); RC=$?
assert_exit "gate: a report for #7 is not a report for #70" 2 "$RC"
G=$(IDD_GH=/nonexistent/gh python3 "$CS" gate --cwd "$C" --repo $REPO --issue $N --sha "$SHA"); RC=$?
assert_exit "gate: gh missing is unparseable, not 'not clean'" 2 "$RC"
python3 "$CS" gate --cwd "$C" --repo $REPO --issue $N --sha abc >/dev/null 2>&1; assert_exit "gate: a short sha is a usage error" 64 $?
python3 "$CS" run --cwd "$C" --repo "not a repo" --issue $N >/dev/null 2>&1; assert_exit "run: a malformed repo is a usage error" 64 $?
python3 "$CS" run --cwd "$C" --repo $REPO --issue $N --ci-timeout nan >/dev/null 2>&1; assert_exit "run: a non-finite timeout is a usage error" 64 $?
python3 "$CS" init --cwd "$C" --repo $REPO --issue $N --path PR --requested-path PR --interaction unattended --branch b --default main --in-chain no >/dev/null 2>&1
assert_exit "init: a missing --review is a usage error, not 'no'" 64 $?
python3 "$CS" init --cwd "$C" --repo $REPO --issue $N --path PR --requested-path PR --interaction unattended --branch b --default main --review "" --in-chain no >/dev/null 2>&1
assert_exit "init: an empty --review (a lost variable) is a usage error" 64 $?
python3 "$CS" init --cwd "$C" --repo $REPO --issue $N --path sideways --requested-path PR --interaction unattended --branch b --default main --review no --in-chain no >/dev/null 2>&1
assert_exit "init: an unknown path is a usage error" 64 $?
BEFORE=$(wc -l < "$S/gh/calls.log")
IDD_GH="$FAKE" FAKE_GH_DIR="$S/gh" IDD_CLOSE_STAGE_TEST=0 PATH=/nonexistent python3 "$CS" gate --cwd "$C" --repo $REPO --issue $N --sha "$SHA" >/dev/null 2>&1
assert_eq "test seams are ignored unless IDD_CLOSE_STAGE_TEST=1 (the fake gh is not called)" "$BEFORE" "$(wc -l < "$S/gh/calls.log")"
python3 "$CS" reset --cwd "$C" --issue $N; assert_exit "reset: exit" 0 $?
assert_file_absent "reset: removes the run state" "$C/.claude/.idd/state/idd-all-run-7.json"
python3 "$CS" bogus >/dev/null 2>&1; assert_exit "an unknown subcommand is a usage error" 64 $?

print_summary close-stage
