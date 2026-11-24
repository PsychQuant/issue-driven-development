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
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
CS="$HERE/../../close-stage.py"
FAKE="$HERE/fake-gh.py"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/idd-close-stage-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
export IDD_CLOSE_STAGE_TEST=1 IDD_SLEEP=0
# The local CI gate is replaced by fake-ci-gate.py (exit code from <scenario>/gh/ci-gate.rc, default 10 = remote mode).
export IDD_CI_GATE="$HERE/fake-ci-gate.py"
# Isolate git from the caller's configuration (#452 lesson).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test
REPO=o/r; N=7
export FX="$HERE/fixtures"   # GitHub's rendering of fixtures/*.md (../verify-gate/render-fixtures.sh <paths>)

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

verify_comment() { # login head base verdict-line [rows] [heading] → append to comments.json
  # body_html is what GitHub renders for that body (the gate reads only the HTML).
  # rows: "Class:Finding;Class:Finding" — findings table rows.
  python3 - "$S/gh/comments.json" "$1" "$2" "$3" "$4" "${5:-}" "${6:-## Verify: #7 — round 1}" <<'EOF'
import json, re, sys, html
path, login, head, base, verdict, rows, heading = sys.argv[1:8]
reviewed = f"{base}..{head}" if base != "-" else head
pairs = [r.split(":", 1) for r in rows.split(";") if r]
import os
sev = os.environ.get("SEV", "LOW")                      # #595: findings above LOW
cover = os.environ.get("COVER", "1 / 1")
revs = os.environ.get("REVIEWERS", "6 / 6")             # empty: no reviewers line at all
rev_md = f"{revs} reviewers completed\n\n" if revs else ""
rev_html = f"<p>{revs} reviewers completed</p>\n" if revs else ""
md_rows = "".join(f"| {i} | {sev} | {f} | codex | {c} |\n" for i, (c, f) in enumerate(pairs, 1))
body = (f"{heading}\n\n{rev_md}### Aggregate\n{verdict}\n\n**Reviewed**: `{reviewed}`\n\n### 要求覆蓋率\n{cover} requirements addressed\n\n"
        "### Findings（合併後）\n| # | Severity | Finding | Source | Action |\n|---|---|---|---|---|\n" + md_rows)
strong = lambda t: re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", html.escape(t, quote=False))
html_rows = "".join(f"<tr><td>{i}</td><td>{sev}</td><td>{html.escape(f)}</td><td>codex</td><td>{c}</td></tr>\n"
                    for i, (c, f) in enumerate(pairs, 1))
body_html = (f"<h2>{html.escape(heading.lstrip('# '))}</h2>\n{rev_html}<h3>Aggregate</h3>\n<p>{strong(verdict)}</p>\n"
             f"<p><strong>Reviewed</strong>: <code>{reviewed}</code></p>\n<h3>要求覆蓋率</h3>\n<p>{cover} requirements addressed</p>\n"
             "<h3>Findings（合併後）</h3>\n"
             "<markdown-accessiblity-table><table><thead><tr><th>#</th><th>Severity</th><th>Finding</th><th>Source</th>"
             f"<th>Action</th></tr></thead><tbody>\n{html_rows}</tbody></table></markdown-accessiblity-table>\n")
import os
FXD = os.environ["FX"]
diag = open(f"{FXD}/diag-simple.md").read()
diag_html = open(f"{FXD}/diag-simple.html").read()
try:
    cs = json.load(open(path))
except Exception:
    cs = [{"id": 1, "html_url": "u1", "user": {"login": "me"}, "author_association": "OWNER",
           "created_at": "2026-01-01T00:00:00Z", "updated_at": "2026-01-01T00:00:00Z", "body": diag, "body_html": diag_html}]
import time
t = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + 5))
cs.append({"id": len(cs) + 1, "node_id": f"IC_{len(cs) + 1}", "html_url": f"https://example.test/c{len(cs)+1}",
           "user": {"login": login, "type": "User"}, "author_association": "MEMBER", "created_at": t, "updated_at": t,
           "body": body, "body_html": body_html})
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

init_state() { # path [requested-path] [review] [in-chain] [interaction] [stop-mode]
  local path="$1" req="${2:-$1}" review="${3:-no}" chain="${4:-no}" inter="${5:-unattended}" stop="${6:-none}"
  local branch=main; [ "$path" = PR ] && branch="idd/7-x"
  python3 "$CS" init --cwd "$C" --repo $REPO --issue $N --path "$path" --requested-path "$req" \
    --interaction "$inter" --branch "$branch" --default main --review "$review" --in-chain "$chain" --stop "$stop" >/dev/null
}

run_stage() { # → OUT, RC. Phase 4 always judges the round before the close stage (#595): run the gate first,
  # unless the test is about a report Phase 4 never judged (NO_PREGATE=1).
  if [ -z "${NO_PREGATE:-}" ] && [ -n "${SHA:-}" ]; then
    IDD_GH="$FAKE" FAKE_GH_DIR="$S/gh" python3 "$CS" gate --cwd "$C" --repo $REPO --issue $N --sha "$SHA" --base "$(base_of "$SHA")" >/dev/null 2>&1
  fi
  OUT=$(IDD_GH="$FAKE" FAKE_GH_DIR="$S/gh" python3 "$CS" run --cwd "$C" --repo $REPO --issue $N --ci-timeout "${CI_TIMEOUT:-0.5}" --ci-grace 0 2>"$S/err"); RC=$?
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
assert_eq "clean run: no Proposed Corrections counted" "0" "$(printf '%s' "$OUT" | field proposed_corrections)"
assert_eq "clean run: no LOW in-scope finding left" "0" "$(printf '%s' "$OUT" | field low_in_scope)"
assert_eq "clean run: the CI gate ran on the verified commit, in the clone" "1" "$(calls_with "\"ci-gate\", \"run\", \"--commit\", \"$SHA\", \"--cwd\"")"
after_checks() { # pattern — calls matching pattern made after the last `gh pr checks` call
  awk -v pat="$1" '/"pr", "checks"/{n=0; seen=1; next} seen && index($0, pat){n++} END{print n+0}' "$S/gh/calls.log"
}
assert_eq "the report is read again after the CI wait" "yes" "$([ "$(after_checks '"--jq", "[.[] | {id, node_id, html_url')" -ge 1 ] && echo yes)"
assert_eq "the default branch is fetched again after the CI wait" "1" "$(after_checks 'mergeQueue')"
assert_eq "the PR's reviews and comments are read after the CI wait" "1" "$(after_checks 'pullRequest(number')"

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
stop_case "a report by another account" "after the run started"
pr_scenario teammate-fail; verify_comment teammate "$SHA" "$(base_of "$SHA")" "**FAIL** — 1 blocking"; run_stage
stop_case "a newer FAIL by a teammate with write access" "teammate commented"
pr_scenario pointer; verify_comment me "$SHA" "$(base_of "$SHA")" "$PASS_LINE" "" "## Verify (via PR #9)"; run_stage
stop_case "the newest verify comment is a PR-mode pointer (r4 #22)" "not a '## Verify: #7' report"
pr_scenario rejected; rm "$S/gh/comments.json"
verify_comment me "$SHA" "$(base_of "$SHA")" "**PASS** — 0 blocking, 0 in-scope fix, 0 follow-up, 1 rejected" "Rejected:claims X"; run_stage
stop_case "a report with a Rejected finding (r4 #7)" "Rejected"
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
echo '[{"name": "test", "bucket": "pass", "event": "pull_request"}]' > "$S/gh/checks-2.json"
CI_TIMEOUT=60 run_stage   # #602: 0.5 s was shorter than one fake gh call under load; the wait never sleeps (IDD_SLEEP=0)
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
echo '[{"name": "cla", "bucket": "pass", "event": ""}, {"name": "ci", "bucket": "fail", "event": "pull_request"}]' > "$S/gh/checks-2.json"
CI_TIMEOUT=60 run_stage   # #602 r2 #16: waits for a second poll, like cipending; the wait never sleeps
stop_case "the pull_request check appears later and fails" "failed: ci"
pr_scenario pathfilter $'on:\n  pull_request:\n    paths: [docs/**]\n'; rm "$S/gh/checks-1.json"; run_stage
assert_eq "a path-filtered pull_request workflow does not make the stage wait for a check" "merged" "$(printf '%s' "$OUT" | field status)"
pr_scenario release $'on:\n  push:\n    branches: [main]\njobs:\n  r:\n    steps:\n      - run: gh release create v1\n'; run_stage
stop_case "a workflow on main that publishes on push" "publishes on push"
pr_scenario tagrelease $'on:\n  push:\n    tags: [\'v*\']\njobs:\n  r:\n    steps:\n      - run: gh release create v1\n'; run_stage
assert_eq "a release workflow triggered by tags only does not stop the stage" "merged" "$(printf '%s' "$OUT" | field status)"
# r7 #16: a workflow that publishes when a release is published, or only when another workflow calls it, does not run on a merge.
pr_scenario on-release $'on:\n  release:\n    types: [published]\njobs:\n  r:\n    steps:\n      - run: npm publish\n'; run_stage
assert_eq "a publish-on-release workflow does not stop the stage" "merged" "$(printf '%s' "$OUT" | field status)"
pr_scenario on-workflow-call $'on:\n  workflow_call:\njobs:\n  r:\n    steps:\n      - run: npm publish\n'; run_stage
assert_eq "a reusable publishing workflow nothing calls on push does not stop the stage" "merged" "$(printf '%s' "$OUT" | field status)"
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
assert_eq "still OPEN after merging: the result says the merge was refused" "refused" "$(printf '%s' "$OUT" | field merge_attempted)"
pr_scenario lateconfirm; echo 'not json' > "$S/gh/after-merge-1.json"
echo '{"state": "MERGED", "mergeCommit": {"oid": "cccccccccccccccccccccccccccccccccccccccc"}}' > "$S/gh/after-merge-2.json"; run_stage
assert_eq "a merge confirmed on the second read: merged" "merged" "$(printf '%s' "$OUT" | field status)"
pr_scenario unconfirmed; echo '{"state": "MERGED", "mergeCommit": null}' > "$S/gh/after-merge-1.json"; run_stage
assert_grep "merged without a readable merge commit: reason says it may have merged" "may have merged" "$(printf '%s' "$OUT" | field reason)"
assert_eq "merged without a readable merge commit: PR number kept" "9" "$(printf '%s' "$OUT" | field pr)"
pr_scenario readonly; echo READ > "$S/gh/perm"; run_stage; stop_case "read-only permission" "permission"
pr_scenario outsider; echo '{"data":{"repository":{"issue":{"state":"OPEN","author":{"login":"stranger"},"editor":null}}}}' > "$S/gh/authors.json"
echo '{"permission":"read","role_name":"read"}' > "$S/gh/perm-stranger.json"; run_stage
stop_case "an issue opened by someone without write access" "author stranger"
pr_scenario outsider-edit; echo '{"data":{"repository":{"issue":{"state":"OPEN","author":{"login":"me"},"editor":{"login":"stranger"}}}}}' > "$S/gh/authors.json"
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
merged_case() { # name
  assert_eq "$1: merged" "merged" "$(printf '%s' "$OUT" | field status)"
}
diag_fixture() { # fixture — comment 0 (the Diagnosis) becomes fixtures/<name>.md with GitHub's rendering
  python3 - "$S/gh/comments.json" "$FX/$1" <<'EOF'
import json, sys
cs = json.load(open(sys.argv[1])); cs[0]["body"] = open(sys.argv[2] + ".md").read(); cs[0]["body_html"] = open(sys.argv[2] + ".html").read()
json.dump(cs, open(sys.argv[1], "w"))
EOF
}
add_comment() { # login fixture offset-seconds — append a comment (body + GitHub's rendering) at now+offset
  python3 - "$S/gh/comments.json" "$1" "$FX/$2" "$3" <<'EOF'
import json, sys, time
cs = json.load(open(sys.argv[1])); t = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + int(sys.argv[4])))
cs.append({"id": 80 + len(cs), "node_id": f"IC_x{len(cs)}", "html_url": "u", "user": {"login": sys.argv[2], "type": "User"},
           "author_association": "OWNER", "created_at": t, "updated_at": t,
           "body": open(sys.argv[3] + ".md").read(), "body_html": open(sys.argv[3] + ".html").read()})
json.dump(cs, open(sys.argv[1], "w"))
EOF
}
pr_scenario layerv; diag_fixture diag-layerv; run_stage; stop_case "a Layer V deferred record" "skipped confirmation"
pr_scenario layerv-prose; diag_fixture diag-layerv-prose; run_stage; merged_case "a Diagnosis that only names the literal (prose and a fence)"
pr_scenario layerv-backticks; diag_fixture diag-inline-backticks; run_stage
stop_case "a record after an inline code span of three backticks (r5 #12)" "skipped confirmation"
pr_scenario layerv-decided; diag_fixture diag-layerv; add_comment me decision -3600; python3 - "$S/gh/comments.json" <<'EOF'
import json, sys
cs = json.load(open(sys.argv[1])); dec = cs.pop(); cs.insert(1, dec); json.dump(cs, open(sys.argv[1], "w"))
EOF
run_stage; merged_case "a record answered by a later Decision comment"
pr_scenario layerv-rerun; diag_fixture diag-layerv; add_comment me diag-simple -1800; run_stage
stop_case "an unattended re-diagnosis does not clear an earlier record (r5 #18)" "skipped confirmation"
pr_scenario choice; diag_fixture diag-choice; run_stage; stop_case "a choice-first default taken unattended (r4 #20)" "unattended-auto-Step-4-choice-default"
pr_scenario choice-own-comment; add_comment me comment-choice -1800; run_stage
stop_case "a choice default record posted as its own comment (r5 #7)" "unattended-auto-Step-4-choice-default"
# Decision of 2026-11-10 (#392 comment 6761657951): Proposed Corrections nobody answered do not stop the merge; the result
# counts the comments that list them (spec Example "the count in the result").
corr() { assert_eq "$1: proposed_corrections" "$2" "$(printf '%s' "$OUT" | field proposed_corrections)"; }
report_corrections() { # the verify report gains a Proposed Corrections section, as idd-verify Step 3.5 writes it
  python3 - "$S/gh/comments.json" <<'EOF'
import json, sys
cs = json.load(open(sys.argv[1]))
cs[-1]["body"] += "\n### Proposed Corrections\n| # | Target | Section | 錯在哪 | Command |\n|---|---|---|---|---|\n| 1 | issue:7 | ## Expected | 預期行為寫反 | x |\n"
cs[-1]["body_html"] += ("<h3>Proposed Corrections</h3>\n<markdown-accessiblity-table><table><thead><tr><th>#</th><th>Target</th><th>Section</th>"
                        "<th>錯在哪</th><th>Command</th></tr></thead><tbody>\n<tr><td>1</td><td>issue:7</td><td>## Expected</td>"
                        "<td>預期行為寫反</td><td>x</td></tr>\n</tbody></table></markdown-accessiblity-table>\n")
json.dump(cs, open(sys.argv[1], "w"))
EOF
}
pr_scenario corrections; diag_fixture diag-corrections; run_stage
merged_case "Proposed Corrections listed by an unattended run do not stop the merge"; corr "in the Diagnosis" 1
pr_scenario corrections-attended; diag_fixture diag-corrections; init_state PR PR no no attended; run_stage
merged_case "Proposed Corrections in an attended run"; corr "attended" 1
pr_scenario corrections-verify; report_corrections; run_stage
merged_case "Proposed Corrections in the verify report of an unattended run"; corr "in the verify report" 1
pr_scenario corrections-two; diag_fixture diag-corrections; report_corrections; run_stage
merged_case "Proposed Corrections in the Diagnosis and in the verify report"; corr "in both" 2
pr_scenario corrections-decided; diag_fixture diag-corrections; add_comment me decision -3600; python3 - "$S/gh/comments.json" <<'EOF'
import json, sys
cs = json.load(open(sys.argv[1])); dec = cs.pop(); cs.insert(1, dec); json.dump(cs, open(sys.argv[1], "w"))
EOF
run_stage; merged_case "Proposed Corrections answered by a later Decision comment"; corr "answered by a Decision" 0
# r7 #15: a subheading inside the section does not end it.
pr_scenario corrections-sub; diag_fixture diag-corrections-sub; run_stage
merged_case "Proposed Corrections whose table stands under a subheading"; corr "under a subheading" 1
set_tier() { python3 - "$S/gh/comments.json" "$1" <<'EOF'
import json, sys
cs = json.load(open(sys.argv[1])); cs[0]["body"] = cs[0]["body"].replace("### Complexity\nSimple", "### Complexity\n" + sys.argv[2])
json.dump(cs, open(sys.argv[1], "w"))
EOF
}
# Decision of 2026-11-10 (#392 comment 6761899504): the tier does not decide the merge (spec Example "result by tier and
# interaction"). An unreadable tier still stops.
pr_scenario simple-unattended; run_stage; merged_case "Simple tier in an unattended run"
pr_scenario plan-unattended; set_tier Plan; run_stage; merged_case "Plan tier in an unattended run"
pr_scenario spectra-unattended; set_tier "Spectra（decision-heavy）"; run_stage; merged_case "Spectra tier in an unattended run"
pr_scenario sdd-unattended; set_tier "SDD-warranted"; run_stage; merged_case "SDD-warranted tier in an unattended run"
pr_scenario plan-attended; set_tier Plan; init_state PR PR no no attended; run_stage; merged_case "Plan tier in an attended run"
pr_scenario no-tier; set_tier "TBD"; run_stage; stop_case "a Diagnosis without a readable tier" "Complexity tier"
pr_scenario no-tier-attended; set_tier "TBD"; init_state PR PR no no attended; run_stage; stop_case "a Diagnosis without a readable tier, attended" "Complexity tier"
# The Diagnosis read is the newest one, also under a suffixed heading (r5 #11): the first has no readable tier, the newest has one.
pr_scenario rerun-heading; set_tier "TBD"; add_comment me diag-rerun-plan -1800; run_stage
merged_case "the newest Diagnosis Phase 2 routes on is the one read, with a suffixed heading"
clarity_fixture() { cp "$FX/$1.md" "$S/gh/issue-body"; cp "$FX/$1.html" "$S/gh/issue-body.html"; }
pr_scenario clarity; clarity_fixture clarity-surfaced; run_stage; stop_case "an open Clarity Surface question" "open question"
pr_scenario clarity-resolved; clarity_fixture clarity-resolved; run_stage; merged_case "a resolved Clarity row that keeps its Reason (r4 #18)"
pr_scenario clarity-deferred-other; clarity_fixture clarity-deferred-other; run_stage
stop_case "a deferred Clarity row with another reason (r4 #27)" "open question"
pr_scenario clarity-second; clarity_fixture clarity-second; run_stage; stop_case "an open row in the second Clarity block (r4 #30)" "open question"
pr_scenario clarity-fenced; clarity_fixture clarity-fenced; run_stage; merged_case "a Clarity example inside a code fence"
# r7 #2: the row is read wherever GitHub shows it; the heading above it does not matter.
pr_scenario clarity-details; clarity_fixture clarity-details; run_stage; stop_case "an open row inside a details block" "open question"
pr_scenario clarity-h4; clarity_fixture clarity-h4; run_stage; stop_case "an open row under a level-4 heading" "open question"
pr_scenario clarity-raw; clarity_fixture clarity-raw; run_stage; stop_case "an open row GitHub did not draw as a table" "open question"
pr_scenario clarity-annotated; clarity_fixture clarity-annotated; run_stage; stop_case "a deferred status with a note after it" "open question"
pr_scenario clarity-quoted; clarity_fixture clarity-quoted; run_stage; stop_case "an open row inside a quote" "open question"
pr_scenario clarity-other-heading; clarity_fixture clarity-other-heading; run_stage; stop_case "an open row under another heading" "open question"
pr_scenario clarity-resolved-mentions; clarity_fixture clarity-resolved-mentions; run_stage
merged_case "resolved rows whose other cells say deferred or surfaced"
others_comment() { # login type created-offset-seconds
  python3 - "$S/gh/comments.json" "$1" "$2" "$3" <<'EOF'
import json, sys, time
cs = json.load(open(sys.argv[1]))
t = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() + int(sys.argv[4])))
cs.append({"id": 70, "html_url": "u70", "user": {"login": sys.argv[2], "type": sys.argv[3]}, "author_association": "MEMBER",
           "created_at": t, "updated_at": t, "body": "Please hold off; do it differently."})
json.dump(cs, open(sys.argv[1], "w"))
EOF
}
pr_scenario teammate-after; others_comment teammate User 5; run_stage
stop_case "a teammate's comment after the run started (r4 #48)" "after the run started"
pr_scenario bot-after; others_comment ci-bot Bot 5; run_stage; merged_case "a bot's comment after the run started"
pr_scenario edited-after; echo '{"data":{"repository":{"issue":{"state":"OPEN","author":{"login":"me"},"editor":{"login":"me"},"userContentEdits":{"totalCount":2,"nodes":[{"editedAt":"2099-01-01T00:00:00Z","editor":{"login":"teammate"}},{"editedAt":"2099-01-01T00:00:01Z","editor":{"login":"me"}}]},"timelineItems":{"totalCount":2,"filteredCount":0,"nodes":[]}}}}}' > "$S/gh/authors.json"
run_stage; stop_case "the issue text edited by someone else after the run started" "edited the issue text"
pr_scenario deleted-after; echo '{"data":{"repository":{"issue":{"state":"OPEN","author":{"login":"me"},"editor":null,"userContentEdits":{"nodes":[]},"timelineItems":{"totalCount":5,"filteredCount":1,"nodes":[{"__typename":"CommentDeletedEvent","createdAt":"2099-01-01T00:00:00Z","deletedCommentAuthor":{"login":"stranger"}}]}}}}}' > "$S/gh/authors.json"
run_stage; stop_case "a comment deleted after the run started (r4 #4)" "was deleted after the run started"
pr_scenario deleted-before; echo '{"data":{"repository":{"issue":{"state":"OPEN","author":{"login":"me"},"editor":null,"userContentEdits":{"nodes":[]},"timelineItems":{"totalCount":5,"filteredCount":1,"nodes":[{"__typename":"CommentDeletedEvent","createdAt":"2020-01-01T00:00:00Z","deletedCommentAuthor":{"login":"stranger"}}]}}}}}' > "$S/gh/authors.json"
run_stage; merged_case "a comment deleted before the run started"
pr_people() { # partial PR JSON, merged over the defaults (author me, nothing else)
  python3 - "$S/gh/pr-people.json" "$1" <<'EOF'
import json, sys
base = {"author": {"login": "me"}, "isDraft": False, "reviewDecision": None, "reviews": {"totalCount": 0, "nodes": []},
        "comments": {"totalCount": 0, "nodes": []}, "userContentEdits": {"totalCount": 0, "nodes": []},
        "timelineItems": {"totalCount": 1, "filteredCount": 0, "nodes": []}}
base.update(json.loads(sys.argv[2]))
json.dump({"data": {"repository": {"pullRequest": base}}}, open(sys.argv[1], "w"))
EOF
}
issue_meta_json() { # partial issue JSON, merged over the defaults (OPEN, author me, nothing else)
  python3 - "$S/gh/authors.json" "$1" <<'EOF'
import json, sys
base = {"state": "OPEN", "author": {"login": "me"}, "editor": None, "userContentEdits": {"totalCount": 0, "nodes": []},
        "timelineItems": {"totalCount": 3, "filteredCount": 0, "nodes": []}}
base.update(json.loads(sys.argv[2]))
json.dump({"data": {"repository": {"issue": base}}}, open(sys.argv[1], "w"))
EOF
}
pr_scenario draft; pr_people '{"isDraft":true,"reviewDecision":null,"reviews":{"nodes":[]},"comments":{"nodes":[]}}'; run_stage
stop_case "a draft PR" "draft"
pr_scenario changes; pr_people '{"isDraft":false,"reviewDecision":"CHANGES_REQUESTED","reviews":{"nodes":[]},"comments":{"nodes":[]}}'; run_stage
stop_case "changes requested on the PR (r4 #15)" "changes requested"
pr_scenario prcomment; pr_people '{"isDraft":false,"reviewDecision":null,"reviews":{"nodes":[]},"comments":{"nodes":[{"author":{"login":"teammate","__typename":"User"}}]}}'; run_stage
stop_case "a comment on the PR" "comment by teammate"
pr_scenario prbot; pr_people '{"isDraft":false,"reviewDecision":null,"reviews":{"nodes":[]},"comments":{"nodes":[{"author":{"login":"codecov","__typename":"Bot"}}]}}'; run_stage
merged_case "a bot comment on the PR"
pr_scenario prother; pr_people '{"author":{"login":"teammate"}}'; run_stage
stop_case "a PR opened by another account (r5 #33)" "not by this account"
pr_scenario prlabel; pr_people '{"timelineItems":{"totalCount":5,"filteredCount":1,"nodes":[{"__typename":"LabeledEvent","createdAt":"2099-01-01T00:00:00Z","actor":{"login":"teammate","__typename":"User"}}]}}'; run_stage
stop_case "a label added to the PR by a teammate (r5 #16)" "labelled PR #9"
pr_scenario prownlabel; pr_people '{"timelineItems":{"totalCount":5,"filteredCount":1,"nodes":[{"__typename":"LabeledEvent","createdAt":"2099-01-01T00:00:00Z","actor":{"login":"me","__typename":"User"}}]}}'; run_stage
merged_case "a label this account added to its own PR"
pr_scenario predit; pr_people '{"userContentEdits":{"totalCount":1,"nodes":[{"editor":{"login":"teammate"}}]}}'; run_stage
stop_case "the PR description edited by a teammate (r5 #16)" "edited PR #9"
pr_scenario prmany; python3 - "$S/gh" <<'EOF'
import json, sys
nodes = [{"author": {"login": f"bot{i}", "__typename": "Bot"}} for i in range(100)]
open(sys.argv[1] + "/pr-people.json", "w").write(json.dumps({"data": {"repository": {"pullRequest": {
    "author": {"login": "me"}, "isDraft": False, "reviewDecision": None, "reviews": {"totalCount": 0, "nodes": []},
    "comments": {"totalCount": 101, "nodes": nodes}, "userContentEdits": {"totalCount": 0, "nodes": []},
    "timelineItems": {"totalCount": 1, "filteredCount": 0, "nodes": []}}}}}))
EOF
run_stage; stop_case "a person's comment hidden behind 100 bot comments (r5 #2)" "more comments than one read returns"
pr_scenario issue-closed; issue_meta_json '{"state":"CLOSED"}'; run_stage
stop_case "the issue closed during the run (r5 #6)" "someone closed it"
pr_scenario issue-labelled; issue_meta_json '{"timelineItems":{"totalCount":5,"filteredCount":1,"nodes":[{"__typename":"LabeledEvent","createdAt":"2099-01-01T00:00:00Z","actor":{"login":"teammate","__typename":"User"}}]}}'; run_stage
stop_case "a label added to the issue by a teammate (r5 #6)" "labelled the issue"
pr_scenario issue-many; issue_meta_json '{"timelineItems":{"totalCount":154,"filteredCount":150,"nodes":[{"__typename":"LabeledEvent","createdAt":"2099-01-01T00:00:00Z","actor":{"login":"me","__typename":"User"}}]}}'; run_stage
stop_case "more issue events than one read returns, all after the run began (r5 #2)" "more entries than one read returns"
# 2026-11-10: GitHub's totalCount counts every timeline entry (commits, comments); the entries that match the filter are
# counted by filteredCount. The first two answers were recorded from a sandbox PR and its issue.
pr_scenario real-pr-timeline; cp "$FX/real-pr-one-commit.json" "$S/gh/pr-people.json"; run_stage
merged_case "a PR whose only timeline entry is its commit (the answer GitHub gave)"
pr_scenario real-issue-timeline; cp "$FX/real-issue-no-events.json" "$S/gh/authors.json"; run_stage
merged_case "an issue with no timeline event and two body edits by this account (the answer GitHub gave)"
pr_scenario pr-timeline-commits; pr_people '{"timelineItems":{"totalCount":16,"filteredCount":1,"nodes":[{"__typename":"ClosedEvent","createdAt":"2099-01-01T00:00:00Z","actor":{"login":"me","__typename":"User"}}]}}'; run_stage
merged_case "a PR timeline of 16 entries, one of them matching the filter"
pr_scenario pr-timeline-many; python3 - "$S/gh" <<'EOF'
import json, sys
nodes = [{"__typename": "LabeledEvent", "createdAt": "2099-01-01T00:00:00Z", "actor": {"login": "me", "__typename": "User"}} for _ in range(100)]
open(sys.argv[1] + "/pr-people.json", "w").write(json.dumps({"data": {"repository": {"pullRequest": {
    "author": {"login": "me"}, "isDraft": False, "reviewDecision": None, "reviews": {"totalCount": 0, "nodes": []},
    "comments": {"totalCount": 0, "nodes": []}, "userContentEdits": {"totalCount": 0, "nodes": []},
    "timelineItems": {"totalCount": 180, "filteredCount": 150, "nodes": nodes}}}}}))
EOF
run_stage; stop_case "more matching PR timeline events than one read returns" "more timelineItems than one read returns"
pr_scenario pr-timeline-nocount; pr_people '{"timelineItems":{"totalCount":1,"nodes":[]}}'; run_stage
stop_case "a PR timeline answer without filteredCount" "filteredCount"
pr_scenario issue-timeline-nocount; issue_meta_json '{"timelineItems":{"totalCount":1,"nodes":[]}}'; run_stage
stop_case "an issue timeline answer without filteredCount" "filteredCount"
pr_scenario issue-many-old; issue_meta_json '{"timelineItems":{"totalCount":154,"filteredCount":150,"nodes":[{"__typename":"LabeledEvent","createdAt":"2020-01-01T00:00:00Z","actor":{"login":"teammate","__typename":"User"}}]}}'; run_stage
merged_case "more matching issue events than read, the oldest one read from before the run began"
# The CI guardrail follows the local CI gate (spec Example "gate exit code, remote checks and the result").
ci_gate() { echo "$1" > "$S/gh/ci-gate.rc"; }
pr_scenario ci-local-pass; ci_gate 0; run_stage; merged_case "local CI passes, remote checks passed"
assert_eq "local CI passes: no failed remote check" "[]" "$(printf '%s' "$OUT" | field remote_ci_failed)"
pr_scenario ci-local-remote-fail; ci_gate 0; echo '[{"name": "test", "bucket": "fail", "event": "pull_request"}]' > "$S/gh/checks-1.json"; run_stage
merged_case "local CI passes while a remote check failed"
assert_eq "local pass, remote fail: the failed check is in the result" "['test']" "$(printf '%s' "$OUT" | field remote_ci_failed)"
pr_scenario ci-local-remote-pending; ci_gate 0; echo '[{"name": "test", "bucket": "pending", "event": "pull_request"}]' > "$S/gh/checks-1.json"; echo 8 > "$S/gh/checks.rc"; run_stage
merged_case "local CI passes while a remote check is pending"
assert_eq "local pass, remote pending: nothing failed" "[]" "$(printf '%s' "$OUT" | field remote_ci_failed)"
assert_eq "local pass, remote pending: the pending check is in the result" "['test']" "$(printf '%s' "$OUT" | field remote_ci_pending)"
assert_eq "local pass, remote pending: the checks are read once, without waiting" "1" "$(calls_with '"pr", "checks"')"
pr_scenario ci-local-remote-unreadable; ci_gate 0; echo 'not json' > "$S/gh/checks-1.json"; run_stage
merged_case "local CI passes while the remote checks cannot be read"
assert_eq "local pass, remote unreadable: the result says so" "not readable" "$(printf '%s' "$OUT" | field remote_ci_failed)"
wf_scenario ci-local-nochecks-wf; ci_gate 0; rm "$S/gh/checks-1.json"; run_stage
merged_case "local CI passes and no remote check has appeared, although a workflow runs on every pull_request"
for rc in 1 2 3 4 7; do
  pr_scenario "ci-gate-$rc"; ci_gate "$rc"; run_stage
  stop_case "local CI gate exits $rc" "guardrail 2 (CI)"
  assert_eq "local CI gate exits $rc: the remote checks are not read" "0" "$(calls_with '"pr", "checks"')"
done
pr_scenario ci-remote-fail; ci_gate 10; echo '[{"name": "test", "bucket": "fail", "event": "pull_request"}]' > "$S/gh/checks-1.json"; run_stage
stop_case "remote mode: a failed check" "failed: test"
pr_scenario edited-report; python3 - "$S/gh/comments.json" <<'EOF'
import json, sys
cs = json.load(open(sys.argv[1])); cs[-1]["updated_at"] = "2099-01-01T00:00:00Z"; json.dump(cs, open(sys.argv[1], "w"))
EOF
run_stage; stop_case "a verify report edited after it was posted (r5 #14)" "edited after it was posted"
pr_scenario hidden-report; echo '{"data":{"node":{"isMinimized":true}}}' > "$S/gh/minimized.json"; run_stage
stop_case "a verify report hidden on GitHub" "hidden on GitHub"
pr_scenario bot-before; others_comment ci-bot Bot -999999; echo '{"permission":"none","role_name":"none"}' > "$S/gh/perm-ci-bot.json"; run_stage
merged_case "a bot comment from before the run (bots exempt in the intent check too, r5 #19)"
pr_scenario foreign; git -C "$C" checkout -q main; echo z > "$C/z.txt"; git -C "$C" add z.txt; git -C "$C" commit -q -m "unrelated local work"
git -C "$C" checkout -q idd/7-x; git -C "$C" rebase -q main; SHA=$(git -C "$C" rev-parse HEAD); pr_fixture "$SHA"
rm "$S/gh/comments.json"; verify_comment me "$SHA" "$(base_of "$SHA")" "$PASS_LINE"; run_stage
stop_case "a commit on the PR branch that is not this run's (r5 #23)" "not this run's"
pr_scenario quoted-release $'on:
  "push":
    branches: [main]
jobs:
  r:
    runs-on: x
    steps:
      - run: npm publish
'; run_stage
stop_case "a release workflow with a quoted event key (r5 #1)" "publishes on push"
serious_report() { rm -f "$S/gh/comments.json"; verify_comment me "$SHA" "$(base_of "$SHA")" "$1" "$2"; python3 - "$S/gh/comments.json" "$3" <<'EOF'
import json, sys
cs = json.load(open(sys.argv[1]))
if sys.argv[2] == "high": cs[-1]["body_html"] = cs[-1]["body_html"].replace("<td>LOW</td>", "<td>HIGH</td>")
if sys.argv[2] == "gaps": cs[-1]["body_html"] += "<h3>Process Gaps</h3><ul><li>logic reviewer timed out</li></ul>"
if sys.argv[2] == "codex": cs[-1]["body_html"] = cs[-1]["body_html"].replace("<td>x</td>", "<td>cross-model pass incomplete</td>")
json.dump(cs, open(sys.argv[1], "w"))
EOF
}
pr_scenario high-followup; serious_report "**PASS** — 0 blocking, 0 in-scope fix, 1 follow-up" "Follow-up:x" high; run_stage
stop_case "a HIGH finding filed as Follow-up (r6 #1)" "serious finding"
pr_scenario gaps; serious_report "$PASS_LINE" "" gaps; run_stage; stop_case "a Process Gaps section (r6 #1)" "degraded"
pr_scenario nocodex; serious_report "**PASS** — 0 blocking, 0 in-scope fix, 1 follow-up" "Follow-up:x" codex; run_stage
stop_case "a missing cross-model pass (r6 #8)" "degraded"
pr_scenario on-merge $'on:\n  pull_request:\n    types: [closed]\njobs:\n  r:\n    steps:\n      - run: npm publish\n'; run_stage
stop_case "a release on PR close (r6 #6)" "publishes on push"
pr_scenario nested $'on: push\njobs:\n  r:\n    steps:\n      - uses: ./.github/actions/up\n'; mkdir -p "$C/.github/actions/up" "$C/scripts"
printf 'runs:\n  steps:\n    - run: bash scripts/up.sh\n' > "$C/.github/actions/up/action.yml"; echo 'twine upload dist/*' > "$C/scripts/up.sh"
git -C "$C" add .github scripts; git -C "$C" stash -q; git -C "$C" checkout -q main; git -C "$C" stash pop -q; git -C "$C" commit -q -m actions; git -C "$C" push -q origin main; git -C "$C" checkout -q idd/7-x; git -C "$C" rebase -q main; SHA=$(git -C "$C" rev-parse HEAD); pr_fixture "$SHA"
rm -f "$S/gh/comments.json"; verify_comment me "$SHA" "$(base_of "$SHA")" "$PASS_LINE"; run_stage
stop_case "workflow to action to script (r6 #2)" "twine upload"
pr_scenario script-change $'on: push\njobs:\n  r:\n    steps:\n      - run: bash scripts/b.sh\n'; mkdir -p "$C/scripts"; echo 'npm publish' > "$C/scripts/b.sh"; git -C "$C" add scripts; work_commit "b (#7)"; pr_fixture "$SHA"
rm -f "$S/gh/comments.json"; verify_comment me "$SHA" "$(base_of "$SHA")" "$PASS_LINE"; run_stage
stop_case "a change adds publishing to a script a push workflow runs (r6 #13)" "publishes on push"
pr_scenario quoted-decision; diag_fixture diag-layerv; python3 - "$S/gh/comments.json" <<'EOF'
import json, sys
cs = json.load(open(sys.argv[1]))
cs.insert(1, {"id": 90, "html_url": "u", "user": {"login": "me", "type": "User"}, "author_association": "OWNER", "created_at": "2026-02-01T00:00:00Z", "updated_at": "2026-02-01T00:00:00Z", "body": "notes: the marker is <!-- idd:comment type=decision --> here", "body_html": "<p>notes</p>"})
json.dump(cs, open(sys.argv[1], "w"))
EOF
run_stage; stop_case "a quoted decision marker does not answer a record (r6 #15)" "skipped confirmation"
pr_scenario remote-release $'on: push
jobs:
  r:
    uses: someorg/shared/.github/workflows/release.yml@main
'; run_stage
stop_case "a push workflow that calls a workflow in another repository" "another repository"
pr_scenario moved-during-ci; cat > "$S/gh/on-checks.sh" <<EOF
cd "$WORK" && rm -rf mdc && git clone -q "$S/o/r.git" mdc && cd mdc && echo y > h.txt && git add h.txt && git -c user.name=t -c user.email=t@e commit -q -m other && git push -q origin main
EOF
run_stage; stop_case "the default branch moved during the CI wait (r4 #1)" "behind"
pr_scenario slash; init_state PR
IDD_GH="$FAKE" FAKE_GH_DIR="$S/gh" python3 "$CS" gate --cwd "$C/" --repo $REPO --issue $N --sha "$SHA" --base "$(base_of "$SHA")" >/dev/null 2>&1   # Phase 4 judged it
OUT=$(IDD_GH="$FAKE" FAKE_GH_DIR="$S/gh" python3 "$CS" run --cwd "$C/" --repo $REPO --issue $N --ci-timeout 0.5 --ci-grace 0 2>"$S/err"); RC=$?
merged_case "--cwd with a trailing slash (r4 #43)"
pr_scenario crash; OUT=$(IDD_GH=/nonexistent/gh FAKE_GH_DIR="$S/gh" python3 "$CS" run --cwd "$C" --repo $REPO --issue $N 2>/dev/null); RC=$?
assert_eq "gh missing: stopped, not a traceback" "stopped" "$(printf '%s' "$OUT" | field status)"
assert_exit "gh missing: exit" 3 "$RC"

echo "close-stage: direct-commit mode"
direct_scenario() { new_scenario "$1"; work_commit "fix: thing (#7)"; verify_comment me "$SHA" "$(base_of "$SHA")" "$PASS_LINE"; init_state direct-commit; }
direct_scenario dhappy; run_stage
assert_eq "direct: pushed" "pushed" "$(printf '%s' "$OUT" | field status)"
assert_eq "direct: the remote has the verified commit" "$SHA" "$(git -C "$S/o/r.git" rev-parse main)"
assert_eq "direct: the CI gate ran on the verified commit" "1" "$(calls_with "\"ci-gate\", \"run\", \"--commit\", \"$SHA\"")"
direct_scenario dci-pass; echo 0 > "$S/gh/ci-gate.rc"; run_stage
assert_eq "direct: local CI passes: pushed" "pushed" "$(printf '%s' "$OUT" | field status)"
for rc in 1 2 3 4 7; do
  direct_scenario "dci-$rc"; BASE=$(git -C "$S/o/r.git" rev-parse main); echo "$rc" > "$S/gh/ci-gate.rc"; run_stage
  assert_eq "direct: local CI gate exits $rc: stopped" "stopped" "$(printf '%s' "$OUT" | field status)"
  assert_grep "direct: local CI gate exits $rc: reason" "guardrail 2 (CI)" "$(printf '%s' "$OUT" | field reason)"
  assert_eq "direct: local CI gate exits $rc: nothing was pushed" "$BASE" "$(git -C "$S/o/r.git" rev-parse main)"
done
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
direct_scenario dsecondpush; BASE=$(git -C "$S/o/r.git" rev-parse main)
git -C "$C" remote set-url --push origin "$S/o/r.git"; git -C "$C" remote set-url --add --push origin "$S/elsewhere/o2/r2.git"; run_stage
assert_grep "direct: a second push URL that points elsewhere (r4 #33): reason" "not github.com/o/r" "$(printf '%s' "$OUT" | field reason)"
assert_eq "direct: a second push URL: nothing pushed" "$BASE" "$(git -C "$S/o/r.git" rev-parse main)"
direct_scenario demptyuser; git -C "$C" remote set-url origin "https://@github.com/o/r.git"; run_stage
assert_grep "direct: an origin URL with empty userinfo passes the origin check (r4 #19)" "git fetch failed" "$(printf '%s' "$OUT" | field reason)"
direct_scenario drejected; rm "$S/gh/comments.json"
verify_comment me "$SHA" "$(base_of "$SHA")" "**PASS** — 0 blocking, 0 in-scope fix, 0 follow-up, 1 rejected" "Rejected:claims X"; run_stage
assert_grep "direct: a Rejected finding stops the push" "Rejected" "$(printf '%s' "$OUT" | field reason)"

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
python3 "$CS" init --cwd "$C" --repo $REPO --issue $N --path PR --requested-path PR --interaction unattended --branch b --default main --in-chain no --stop none >/dev/null 2>&1
assert_exit "init: a missing --review is a usage error, not 'no'" 64 $?
python3 "$CS" init --cwd "$C" --repo $REPO --issue $N --path PR --requested-path PR --interaction unattended --branch b --default main --review "" --in-chain no --stop none >/dev/null 2>&1
assert_exit "init: an empty --review (a lost variable) is a usage error" 64 $?
python3 "$CS" init --cwd "$C" --repo $REPO --issue $N --path sideways --requested-path PR --interaction unattended --branch b --default main --review no --in-chain no --stop none >/dev/null 2>&1
assert_exit "init: an unknown path is a usage error" 64 $?
BEFORE=$(wc -l < "$S/gh/calls.log")
IDD_GH="$FAKE" FAKE_GH_DIR="$S/gh" IDD_CLOSE_STAGE_TEST=0 PATH=/nonexistent python3 "$CS" gate --cwd "$C" --repo $REPO --issue $N --sha "$SHA" >/dev/null 2>&1
assert_eq "test seams are ignored unless IDD_CLOSE_STAGE_TEST=1 (the fake gh is not called)" "$BEFORE" "$(wc -l < "$S/gh/calls.log")"
python3 "$CS" reset --cwd "$C" --issue $N; assert_exit "reset: exit" 0 $?
assert_file_absent "reset: removes the run state" "$C/.claude/.idd/state/idd-all-run-7.json"
python3 "$CS" bogus >/dev/null 2>&1; assert_exit "an unknown subcommand is a usage error" 64 $?

echo "close-stage: pr-check (may the run open its pull request without asking)"
# spec-example: idd-pr-hitl-modes / pr-check by title, body and default branch
prc() { # uses $S $C $TITLE $BODY → PRC (the JSON line), RC
  printf '%s' "$TITLE" > "$S/title.txt"; printf '%s' "$BODY" > "$S/body.txt"
  PRC=$(python3 "$CS" pr-check --cwd "$C" --default main --title-file "$S/title.txt" --body-file "$S/body.txt" 2>/dev/null); RC=$?
}
codeowners() { # path [push] — commit the file on the current branch; push main unless told not to
  mkdir -p "$C/$(dirname "$1")"; echo '* @someone' > "$C/$1"; git -C "$C" add "$1"; git -C "$C" commit -q -m "codeowners"
  [ "${2:-push}" = push ] && git -C "$C" push -q origin main
}
# plain_pr stays on one line ending in }: run_parallel.py then puts it in every block's prelude
plain_pr() { TITLE="docs: say hello (#7)"; BODY=$'Refs #7\n\n## Summary\nhello'; }
new_scenario prc-plain; plain_pr; prc
assert_eq "pr-check: no mention, no CODEOWNERS → open" open "$(printf '%s' "$PRC" | field status)"
assert_exit "pr-check: open exits 0" 0 "$RC"
for where in .github/CODEOWNERS CODEOWNERS docs/CODEOWNERS; do
  new_scenario "prc-co-$(printf '%s' "$where" | tr -c 'A-Za-z' '-')"; codeowners "$where"; plain_pr; prc
  assert_eq "pr-check: $where on the default branch → ask" ask "$(printf '%s' "$PRC" | field status)"
  assert_exit "pr-check: $where → exit 3" 3 "$RC"
  assert_grep "pr-check: the reason names $where" "$where" "$(printf '%s' "$PRC" | field reason)"
done
new_scenario prc-co-branch-only; git -C "$C" checkout -q -b idd/7-x; codeowners .github/CODEOWNERS nopush; plain_pr; prc
assert_eq "pr-check: a CODEOWNERS only on the run's branch does not count (the default branch decides)" open "$(printf '%s' "$PRC" | field status)"
new_scenario prc-mention; plain_pr; BODY=$'Refs #7\n\nthanks @someone'; prc
assert_eq "pr-check: a mention in the body → ask" ask "$(printf '%s' "$PRC" | field status)"
assert_grep "pr-check: the reason says it is a mention" "mentions an account" "$(printf '%s' "$PRC" | field reason)"
new_scenario prc-mention-title; plain_pr; TITLE="docs: for @someone (#7)"; prc
assert_eq "pr-check: a mention in the title → ask" ask "$(printf '%s' "$PRC" | field status)"
new_scenario prc-email; plain_pr; BODY=$'Refs #7\n\nmail t@example.test and `pkg@1.2`'; prc
assert_eq "pr-check: an e-mail address and a version pin are not mentions" open "$(printf '%s' "$PRC" | field status)"
new_scenario prc-trap; plain_pr; TITLE="fix #7"; prc
assert_eq "pr-check: a close keyword next to the issue number → ask" ask "$(printf '%s' "$PRC" | field status)"
assert_grep "pr-check: the reason says it is a close keyword" "close keyword" "$(printf '%s' "$PRC" | field reason)"
new_scenario prc-noref; git -C "$C" update-ref -d refs/remotes/origin/main; git -C "$C" remote set-url origin "$S/gone.git"; plain_pr; prc
assert_eq "pr-check: the default branch cannot be read → ask" ask "$(printf '%s' "$PRC" | field status)"
assert_exit "pr-check: unreadable default branch → exit 3" 3 "$RC"
new_scenario prc-usage; printf 'b' > "$S/body.txt"
python3 "$CS" pr-check --cwd "$C" --default main --title-file "$S/absent.txt" --body-file "$S/body.txt" >/dev/null 2>&1
assert_exit "pr-check: a missing title file is a usage error" 64 $?
python3 "$CS" pr-check --cwd "$C" --default "-x" --title-file "$S/body.txt" --body-file "$S/body.txt" >/dev/null 2>&1
assert_exit "pr-check: a default branch that starts with a dash is a usage error" 64 $?

echo "close-stage: round 8 — the direct path reads again after the local CI gate"
# spec-example: idd-pr-hitl-modes / what the direct path reads again after the local CI gate
direct_scenario dci-teammate; ci_gate 0; cp "$S/gh/comments.json" "$S/gh/before.json"; others_comment teammate User 5
mv "$S/gh/comments.json" "$S/gh/after.json"; mv "$S/gh/before.json" "$S/gh/comments.json"
printf '%s\n' "cp '$S/gh/after.json' '$S/gh/comments.json'" > "$S/gh/on-ci-gate.sh"; run_stage
assert_eq "direct: a teammate's comment during the local CI gate stops the push" "stopped" "$(printf '%s' "$OUT" | field status)"
assert_grep "direct: the stop names the comment" "after the run started" "$(printf '%s' "$OUT" | field reason)"
assert_true "direct: nothing was pushed" '[ "$(git -C "$S/o/r.git" rev-parse main)" != "$SHA" ]'
direct_scenario dci-fail-report; ci_gate 0; cp "$S/gh/comments.json" "$S/gh/before.json"
verify_comment me "$SHA" "$(base_of "$SHA")" "**FAIL** — 1 blocking" "" "## Verify: #7 — round 2"
mv "$S/gh/comments.json" "$S/gh/after.json"; mv "$S/gh/before.json" "$S/gh/comments.json"
printf '%s\n' "cp '$S/gh/after.json' '$S/gh/comments.json'" > "$S/gh/on-ci-gate.sh"; run_stage
assert_eq "direct: a FAIL report posted during the local CI gate stops the push" "stopped" "$(printf '%s' "$OUT" | field status)"
assert_grep "direct: the stop is the verify gate" "verify gate" "$(printf '%s' "$OUT" | field reason)"
assert_true "direct: nothing was pushed after the FAIL report" '[ "$(git -C "$S/o/r.git" rev-parse main)" != "$SHA" ]'
direct_scenario dci-quiet; ci_gate 0; run_stage
assert_eq "direct: a quiet local CI gate still ends in a push" "pushed" "$(printf '%s' "$OUT" | field status)"

echo "close-stage: round 8 — gh pr checks exits 1 when a check failed"
pr_scenario rc1; ci_gate 0; echo '[{"name": "lint", "bucket": "fail", "event": "pull_request"}]' > "$S/gh/checks-1.json"; echo 1 > "$S/gh/checks.rc"; run_stage
assert_eq "local pass, gh exits 1 for a failed remote check: merged" "merged" "$(printf '%s' "$OUT" | field status)"
assert_eq "local pass, gh exits 1: the failed check is named" "['lint']" "$(printf '%s' "$OUT" | field remote_ci_failed)"

pr_scenario rc1-remote; echo '[{"name": "lint", "bucket": "fail", "event": "pull_request"}]' > "$S/gh/checks-1.json"; echo 1 > "$S/gh/checks.rc"; run_stage
stop_case "remote mode, gh exits 1 for a failed check: the stop names the check" "failed: lint"

echo "close-stage: round 8 — pr-check"
for m in '_@someone_' 'see -@someone' 'x.@someone' '&#64;someone' '&#x40;someone' '&commat;someone' '(@someone)'; do
  new_scenario "prc-m-$(printf '%s' "$m" | cksum | cut -d' ' -f1)"; plain_pr; BODY="Refs #7 $m"; prc
  assert_eq "pr-check: '$m' counts as a mention → ask" ask "$(printf '%s' "$PRC" | field status)"
done
new_scenario prc-empty-title; plain_pr; TITLE=""; prc
assert_eq "pr-check: an empty title → ask" ask "$(printf '%s' "$PRC" | field status)"
assert_grep "pr-check: the reason says the title is empty" "title is empty" "$(printf '%s' "$PRC" | field reason)"
new_scenario prc-stale; git clone -q "$S/o/r.git" "$S/other"; mkdir -p "$S/other/.github"; echo '* @someone' > "$S/other/.github/CODEOWNERS"
git -C "$S/other" add .github; git -C "$S/other" commit -q -m codeowners; git -C "$S/other" push -q origin main; plain_pr; prc
assert_eq "pr-check: a CODEOWNERS pushed after the clone was made is seen (the check fetches) → ask" ask "$(printf '%s' "$PRC" | field status)"
new_scenario prc-nofetch; git -C "$C" remote set-url origin "$S/gone.git"; plain_pr; prc
assert_eq "pr-check: the default branch cannot be fetched → ask" ask "$(printf '%s' "$PRC" | field status)"
assert_grep "pr-check: the reason says the fetch failed" "could not fetch" "$(printf '%s' "$PRC" | field reason)"

echo "close-stage: stop modes (#595)"
# write_rounds mode interaction review "b,i,l;b,i,l" [last-gate-status] [attempts] [rejected-in-last-round]
# — a run-state with a stop mode and rounds. Each round gets report id 100+k and a 40-hex sha; last_gate repeats the
# newest round unless a status is given; attempts (one per commit the gate judged) default to one per round.
write_rounds() {
  mkdir -p "$C/.claude/.idd/state"
  python3 - "$C/.claude/.idd/state/idd-all-run-7.json" "$@" <<'EOF'
import json, sys, time
path, mode, inter, review, spec = sys.argv[1:6]
status = sys.argv[6] if len(sys.argv) > 6 else "not_clean"
n_attempts = int(sys.argv[7]) if len(sys.argv) > 7 and sys.argv[7] else None
rejected = int(sys.argv[8]) if len(sys.argv) > 8 else 0
at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
rounds = []
for k, triple in enumerate([t for t in spec.split(";") if t], 1):
    b, i, l = (int(x) for x in triple.split(","))
    rounds.append({"round": k, "sha": f"{k:040x}", "blocking": b, "in_scope": i, "low_in_scope": l,
                   "rejected": rejected if k == len(spec.split(";")) else 0,
                   "status": status if k == len(spec.split(";")) else "not_clean",
                   "report_id": 100 + k, "at": at})
st = {"repo": "o/r", "issue": 7, "path": "PR", "requested_path": "PR", "interaction": inter, "branch": "idd/7-x",
      "default": "main", "review": review == "yes", "in_chain": False, "created_at": at,
      "verify_stop": None if mode == "none" else mode, "rounds": rounds,
      "attempts": [{"sha": f"{k:040x}", "at": at} for k in range(1, (n_attempts if n_attempts is not None else len(rounds)) + 1)],
      "last_gate": {"status": status, "report_id": rounds[-1]["report_id"] if rounds else None,
                    "sha": rounds[-1]["sha"] if rounds else None, "at": at}}
json.dump(st, open(path, "w"))
EOF
}
next_run() { NX=$(python3 "$CS" next --cwd "$C" --repo $REPO --issue $N 2>"$S/err"); RC=$?; }
nx() { printf '%s' "$NX" | field "$1"; }
rounds_len() { python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1])).get("rounds") or []))' "$C/.claude/.idd/state/idd-all-run-7.json"; }
gate_run() { G=$(IDD_GH="$FAKE" FAKE_GH_DIR="$S/gh" python3 "$CS" gate --cwd "$C" --repo $REPO --issue $N --sha "$SHA" --base "$(base_of "$SHA")"); RC=$?; }

# spec: early stops when the count stops falling and merges with no Blocking
new_scenario stop-early-converges; write_rounds early unattended no "0,6,0;0,4,0;0,4,0"; next_run
assert_eq "early 6,4,4: stop" stop "$(nx decision)"
assert_eq "early 6,4,4: merge" True "$(nx merge)"
assert_grep "early 6,4,4: the reason names 4 → 4" "4 → 4" "$(nx reason)"
assert_exit "early 6,4,4: next decided" 0 "$RC"
write_rounds early unattended no "0,6,0;0,4,0"; next_run
assert_eq "early 6,4: the count fell, fix again" fix "$(nx decision)"
write_rounds early unattended no "0,3,0"; next_run
assert_eq "early round 1 with findings: fix" fix "$(nx decision)"
write_rounds early unattended no "0,2,2"; next_run
assert_eq "early: only LOW in-scope findings is nothing to fix → stop" stop "$(nx decision)"
assert_eq "early: only LOW in-scope findings → merge" True "$(nx merge)"

# spec: early stops with Blocking and does not merge
new_scenario stop-early-blocking; write_rounds early unattended no "1,2,0;1,2,0"; next_run
assert_eq "early 3,3 with 1 Blocking: stop" stop "$(nx decision)"
assert_eq "early 3,3 with 1 Blocking: no merge" False "$(nx merge)"

# spec: exhaustive-blocking reaches zero Blocking
new_scenario stop-exb-zero; write_rounds exhaustive-blocking unattended no "2,0,0;1,0,0;0,3,0"; next_run
assert_eq "exhaustive-blocking 2,1,0: stop" stop "$(nx decision)"
assert_eq "exhaustive-blocking 2,1,0: merge with In-scope fix left" True "$(nx merge)"

# spec: exhaustive-blocking stops when Blocking does not fall twice
new_scenario stop-exb-stuck; write_rounds exhaustive-blocking unattended no "2,0,0;2,0,0"; next_run
assert_eq "exhaustive-blocking 2,2: one round without progress, fix again" fix "$(nx decision)"
write_rounds exhaustive-blocking unattended no "2,0,0;2,0,0;2,0,0"; next_run
assert_eq "exhaustive-blocking 2,2,2: stop" stop "$(nx decision)"
assert_eq "exhaustive-blocking 2,2,2: no merge" False "$(nx merge)"
write_rounds exhaustive-blocking unattended no "3,0,0;2,0,0;2,0,0"; next_run
assert_eq "exhaustive-blocking 3,2,2: only one round without progress, fix again" fix "$(nx decision)"

# spec: exhaustive-all keeps going until nothing is left
new_scenario stop-exall; write_rounds exhaustive-all unattended no "3,3,0;2,3,0;1,2,0;1,1,0;0,1,0;0,1,1"; next_run
assert_eq "exhaustive-all round 6 with one LOW in-scope finding: fix" fix "$(nx decision)"
write_rounds exhaustive-all unattended no "3,3,0;2,3,0;1,2,0;1,1,0;0,1,0;0,1,1;0,0,0"; next_run
assert_eq "exhaustive-all round 7 at zero: stop" stop "$(nx decision)"
assert_eq "exhaustive-all round 7 at zero: merge" True "$(nx merge)"
write_rounds exhaustive-all unattended no "5,0,0;5,0,0;5,0,0;5,0,0"; next_run
assert_eq "exhaustive-all has no round limit and no progress rule" fix "$(nx decision)"

# spec: an attended run with a stop mode fixes on its own
new_scenario stop-attended; write_rounds early attended no "1,0,0"; next_run
assert_eq "attended early with 1 Blocking in round 1: fix" fix "$(nx decision)"

# stop modes: what stops every mode, and runs that never merge
new_scenario stop-edges; write_rounds exhaustive-all unattended no "1,0,0" unparseable; next_run
assert_eq "an unparseable latest gate stops" stop "$(nx decision)"
assert_eq "an unparseable latest gate does not merge" False "$(nx merge)"
write_rounds early unattended yes "0,3,0"; next_run
assert_eq "--review counts Blocking only: nothing to fix → stop" stop "$(nx decision)"
assert_eq "--review never merges" False "$(nx merge)"
rm -f "$C/.claude/.idd/state/idd-all-run-7.json"; next_run
assert_exit "next without a run state cannot decide" 3 "$RC"
assert_eq "next without a run state answers stop" stop "$(nx decision)"
assert_eq "next without a run state does not merge" False "$(nx merge)"
write_rounds none unattended no "0,3,0"; next_run
assert_eq "no stop mode, unattended round 1: fix" fix "$(nx decision)"
write_rounds none unattended no "0,3,0;0,2,0"; next_run
assert_eq "no stop mode, unattended round 2: stop (two-round limit)" stop "$(nx decision)"
write_rounds none attended no "0,3,0"; next_run
assert_eq "no stop mode, attended round 1: stop" stop "$(nx decision)"
write_rounds none unattended no "1,0,0" unparseable; next_run
assert_eq "no stop mode, unparseable in round 1 of 2: rounds are left (Phase 4 reads the report itself)" fix "$(nx decision)"
assert_eq "no stop mode, unparseable: the answer still carries the round limit" 2 "$(nx limit)"
assert_eq "no stop mode, unparseable: and the round" 1 "$(nx round)"
write_rounds none unattended no "0,3,0" unparseable 2; next_run
assert_eq "no stop mode: a second attempt whose report was missing still counts → stop" stop "$(nx decision)"
assert_eq "no stop mode: the missing report's attempt is round 2" 2 "$(nx round)"
write_rounds none unattended no "1,0,0" not_clean "" 1; next_run
assert_eq "no stop mode, round 1 with a Rejected finding: fix as before #595" fix "$(nx decision)"
assert_eq "no stop mode, round 1 with a Rejected finding: the answer carries the limit" 2 "$(nx limit)"
write_rounds none unattended no "0,0,0" clean 3; next_run
assert_eq "no stop mode, a clean third round: no merge" False "$(nx merge)"
write_rounds early unattended no "0,3,0" not_clean "" 1; next_run
assert_eq "early, a round with a Rejected finding: stop" stop "$(nx decision)"
assert_eq "early, a round with a Rejected finding: no merge" False "$(nx merge)"
write_rounds early unattended no "0,6,0;0,4,0"; next_run
assert_eq "next lists the to-fix count of each round" "6 4" "$(printf '%s' "$NX" | python3 -c 'import json,sys; print(" ".join(str(r["to_fix"]) for r in json.load(sys.stdin)["rounds"]))')"

# spec: the same report read twice is one round
pr_scenario stop-gate-rounds; init_state PR PR no no unattended early
gate_run; gate_run
assert_eq "gate: the same report read twice is one round" 1 "$(rounds_len)"
assert_eq "gate: prints the round number" 1 "$(printf '%s' "$G" | field round)"
verify_comment me "$SHA" "$(base_of "$SHA")" "$PASS_LINE"; gate_run
assert_eq "gate: a new report is a new round" 2 "$(rounds_len)"
gate_run
assert_eq "gate: reading round 2's report again keeps 2 rounds" 2 "$(rounds_len)"
attempts_len() { python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1])).get("attempts") or []))' "$C/.claude/.idd/state/idd-all-run-7.json"; }
assert_eq "gate: a new report on the same commit is a new attempt (a fix pass that made no commit counts)" 2 "$(attempts_len)"

# spec: flag over config, and values outside the three (the init half; the skill resolves flag and config)
new_scenario stop-init
python3 "$CS" init --cwd "$C" --repo $REPO --issue $N --path PR --requested-path PR --interaction unattended --branch b --default main --review no --in-chain no >/dev/null 2>&1
assert_exit "init: a missing --stop is a usage error" 64 $?
python3 "$CS" init --cwd "$C" --repo $REPO --issue $N --path PR --requested-path PR --interaction unattended --branch b --default main --review no --in-chain no --stop fast >/dev/null 2>&1
assert_exit "init: --stop fast is a usage error" 64 $?
  for m in none early exhaustive-blocking exhaustive-all; do   # indented: run_parallel.py starts a new scenario at a top-level for
  python3 "$CS" init --cwd "$C" --repo $REPO --issue $N --path PR --requested-path PR --interaction unattended --branch b --default main --review no --in-chain no --stop "$m" >/dev/null
  assert_eq "init: --stop $m is recorded" "$([ "$m" = none ] && echo None || echo "$m")" "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("verify_stop", "<missing>"))' "$C/.claude/.idd/state/idd-all-run-7.json")"
  done

# spec: a stop-mode run merges a reviewed commit that is not clean
new_scenario stop-merge-notclean; git -C "$C" checkout -q -b idd/7-x; work_commit "feat: thing (#7)"; pr_fixture "$SHA"
verify_comment me "$SHA" "$(base_of "$SHA")" "**FAIL** — 0 blocking, 1 in-scope fix" "In-scope fix:a LOW leftover"
init_state PR PR no no unattended early; gate_run; run_stage
assert_eq "early, a FAIL round with nothing to fix: merged" merged "$(printf '%s' "$OUT" | field status)"
assert_exit "early, a FAIL round with nothing to fix: exit" 0 "$RC"

new_scenario stop-merge-nomode; git -C "$C" checkout -q -b idd/7-x; work_commit "feat: thing (#7)"; pr_fixture "$SHA"
verify_comment me "$SHA" "$(base_of "$SHA")" "**FAIL** — 0 blocking, 1 in-scope fix" "In-scope fix:a LOW leftover"
init_state PR; gate_run; run_stage
stop_case "no stop mode, the same FAIL round" "verify gate"

new_scenario stop-merge-blocking; git -C "$C" checkout -q -b idd/7-x; work_commit "feat: thing (#7)"; pr_fixture "$SHA"
verify_comment me "$SHA" "$(base_of "$SHA")" "**FAIL** — 1 blocking" "Blocking:a real problem"
init_state PR PR no no unattended early; gate_run; run_stage
stop_case "early, a round with Blocking" "stop mode early"

new_scenario stop-merge-stale; git -C "$C" checkout -q -b idd/7-x; work_commit "feat: thing (#7)"; pr_fixture "$SHA"
verify_comment me "$SHA" "$(base_of "$SHA")" "**FAIL** — 0 blocking, 1 in-scope fix" "In-scope fix:a LOW leftover"
init_state PR PR no no unattended early; gate_run
verify_comment me "$SHA" "$(base_of "$SHA")" "**FAIL** — 0 blocking, 1 in-scope fix" "In-scope fix:a LOW leftover"; NO_PREGATE=1 run_stage
stop_case "early, a report the round record has not seen" "not the round"

# two rounds of one PR: round 1 on the first commit, round 2 on a fix commit
two_rounds() { # name mode "verdict1" "rows1" "verdict2" "rows2"
  new_scenario "$1"; git -C "$C" checkout -q -b idd/7-x; work_commit "feat: thing (#7)"; pr_fixture "$SHA"
  init_state PR PR no no unattended "$2"
  verify_comment me "$SHA" "$(base_of "$SHA")" "$3" "$4"; gate_run
  work_commit "fix: address verify finding (#7)"; pr_fixture "$SHA"
  verify_comment me "$SHA" "$(base_of "$SHA")" "$5" "$6"; gate_run
}
# spec: early stops when the count stops falling and merges with no Blocking (the run itself, findings above LOW)
SEV=MEDIUM two_rounds stop-run-early-flat early "**FAIL** — 0 blocking, 2 in-scope fix" "In-scope fix:a;In-scope fix:b" \
  "**FAIL** — 0 blocking, 2 in-scope fix" "In-scope fix:c;In-scope fix:d"; run_stage
assert_eq "early 2 → 2 with MEDIUM findings: the run merges the reviewed commit" merged "$(printf '%s' "$OUT" | field status)"
assert_output_grep "early: the squash body names the stop mode" "after stop mode early" "$S/gh/calls.log"
# spec: exhaustive-blocking reaches zero Blocking (the run itself)
SEV=MEDIUM two_rounds stop-run-exb exhaustive-blocking "**FAIL** — 1 blocking, 3 in-scope fix" "Blocking:x;In-scope fix:a;In-scope fix:b;In-scope fix:c" \
  "**FAIL** — 0 blocking, 3 in-scope fix" "In-scope fix:a;In-scope fix:b;In-scope fix:c"; run_stage
assert_eq "exhaustive-blocking at 0 Blocking with 3 MEDIUM left: merged" merged "$(printf '%s' "$OUT" | field status)"
# spec: a stop-mode merge passes the clean merge's coverage and reviewers checks
COVER="3 / 5" SEV=MEDIUM two_rounds stop-run-cover early "**FAIL** — 0 blocking, 2 in-scope fix" "In-scope fix:a;In-scope fix:b" \
  "**FAIL** — 0 blocking, 2 in-scope fix" "In-scope fix:c;In-scope fix:d"; run_stage
stop_case "early, coverage 3 / 5" "coverage line"
REVIEWERS="" SEV=MEDIUM two_rounds stop-run-noreviewers early "**FAIL** — 0 blocking, 2 in-scope fix" "In-scope fix:a;In-scope fix:b" \
  "**FAIL** — 0 blocking, 2 in-scope fix" "In-scope fix:c;In-scope fix:d"; run_stage
stop_case "early, no reviewers line" "reviewers line"
# no stop mode: a report the round record never saw does not merge
pr_scenario stop-nomode-unseen; gate_run; verify_comment me "$SHA" "$(base_of "$SHA")" "$PASS_LINE"; NO_PREGATE=1 run_stage
stop_case "no stop mode, a newer report Phase 4 never judged" "never judged"
# gate: a broken round record fails the gate closed
pr_scenario stop-gate-broken; echo '{"repo": "o/r", "issue": 7, "rounds": "x"}' > "$C/.claude/.idd/state/idd-all-run-7.json"; gate_run
assert_exit "gate: a round record that is not a list is unparseable" 2 "$RC"
assert_eq "gate: … and says so" unparseable "$(printf '%s' "$G" | field status)"

# spec (fix round 1): a result already answered with fix stops the loop
new_scenario stop-fix-answered; write_rounds early unattended no "0,3,0"; next_run
assert_eq "early round 1 with 3 to fix: fix" fix "$(nx decision)"
next_run
assert_eq "the same result asked again (no new report, no new commit): stop" stop "$(nx decision)"
assert_eq "the same result asked again: no merge" False "$(nx merge)"
assert_grep "the same result asked again: the reason says so" "no new report or commit" "$(nx reason)"
write_rounds none unattended no "0,3,0"; next_run; next_run
assert_eq "no stop mode: the same result asked again also stops" stop "$(nx decision)"
# spec (fix round 1): a serious In-scope finding left unfixed is not merged
SEV=HIGH two_rounds stop-run-high early "**FAIL** — 0 blocking, 2 in-scope fix" "In-scope fix:a;In-scope fix:b" \
  "**FAIL** — 0 blocking, 2 in-scope fix" "In-scope fix:c;In-scope fix:d"; run_stage
stop_case "early, two HIGH In-scope fix findings left" "HIGH"
# … and the close stage checks it itself: a round record without high_in_scope (next cannot see it) still stops
SEV=HIGH two_rounds stop-run-high-cs early "**FAIL** — 0 blocking, 2 in-scope fix" "In-scope fix:a;In-scope fix:b" \
  "**FAIL** — 0 blocking, 2 in-scope fix" "In-scope fix:c;In-scope fix:d"
python3 - "$C/.claude/.idd/state/idd-all-run-7.json" <<'PY'
import json, sys
p = sys.argv[1]; st = json.load(open(p))
for r in st["rounds"]:
    r.pop("high_in_scope", None)
json.dump(st, open(p, "w"))
PY
NO_PREGATE=1 run_stage
stop_case "early, HIGH In-scope fix left and not in the round record" "CRITICAL, HIGH, P0 or P1"
# verify r2 #1: a stop-mode merge checks that the report it re-reads has the counts the round record holds
SEV=MEDIUM two_rounds stop-run-counts exhaustive-all "**FAIL** — 0 blocking, 2 in-scope fix" "In-scope fix:a;In-scope fix:b" \
  "**FAIL** — 0 blocking, 2 in-scope fix" "In-scope fix:c;In-scope fix:d"
python3 - "$C/.claude/.idd/state/idd-all-run-7.json" <<'PY'
import json, sys
p = sys.argv[1]; st = json.load(open(p)); st["rounds"][-1]["in_scope"] = 0; json.dump(st, open(p, "w"))
PY
NO_PREGATE=1 run_stage
stop_case "exhaustive-all, a round record whose counts differ from the report" "does not match"
# verify r2 #2: without a stop mode, a round with no report on the same commit is still a round
new_scenario stop-nomode-noreport; git -C "$C" checkout -q -b idd/7-x; work_commit "feat: thing (#7)"; pr_fixture "$SHA"
init_state PR PR no no unattended none
verify_comment me "$SHA" "$(base_of "$SHA")" "**FAIL** — 1 blocking" "Blocking:x"; gate_run; next_run
assert_eq "no stop mode, round 1 with a Blocking finding: fix" fix "$(nx decision)"
# round 2's newest verify comment is a PR-mode pointer: the gate reads no report id (the same as a failed fetch)
verify_comment me "$SHA" "$(base_of "$SHA")" "$PASS_LINE" "" "## Verify (via PR #9) — round 2"; gate_run
assert_eq "no stop mode: round 2 without a branch-mode report has no report id" "<missing>" "$(printf '%s' "$G" | field comment_id)"
assert_eq "no stop mode: a second round with no report on the same commit is a second attempt" 2 "$(attempts_len)"
next_run
assert_eq "no stop mode: … and the two-round limit stops the loop" stop "$(nx decision)"
# verify r2 #3: a result next answered with fix is not merged when it later reads clean
new_scenario stop-nomode-laterclean; git -C "$C" checkout -q -b idd/7-x; work_commit "feat: thing (#7)"; pr_fixture "$SHA"
init_state PR PR no no unattended none
verify_comment me "$SHA" "$(base_of "$SHA")" "$PASS_LINE"
python3 - "$S/gh/comments.json" "$S/html.stash" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); open(sys.argv[2], "w").write(d[-1].pop("body_html")); json.dump(d, open(sys.argv[1], "w"))
PY
gate_run; next_run
assert_eq "no stop mode, round 1 unreadable (no rendered HTML): fix" fix "$(nx decision)"
python3 - "$S/gh/comments.json" "$S/html.stash" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d[-1]["body_html"] = open(sys.argv[2]).read(); json.dump(d, open(sys.argv[1], "w"))
PY
gate_run; next_run
assert_eq "the same report read as clean after a fix answer: stop" stop "$(nx decision)"
assert_eq "the same report read as clean after a fix answer: no merge" False "$(nx merge)"
NO_PREGATE=1 run_stage
stop_case "no stop mode, a clean report next already answered with fix" "fix answer"
# verify r3 #1: Phase 5 reads the gate without writing the round record; a report Phase 4 never judged does not merge
SEV=MEDIUM two_rounds stop-run-readonly early "**FAIL** — 1 blocking, 2 in-scope fix" "Blocking:x;In-scope fix:a;In-scope fix:b" \
  "**FAIL** — 1 blocking, 2 in-scope fix" "Blocking:x;In-scope fix:c;In-scope fix:d"; next_run
assert_eq "early 3 → 3 with a Blocking finding: stop" stop "$(nx decision)"
SEV=MEDIUM verify_comment me "$SHA" "$(base_of "$SHA")" "**FAIL** — 0 blocking, 2 in-scope fix" "In-scope fix:e;In-scope fix:f" "## Verify: #7 — round 3"
G=$(IDD_GH="$FAKE" FAKE_GH_DIR="$S/gh" python3 "$CS" gate --cwd "$C" --repo $REPO --issue $N --sha "$SHA" --base "$(base_of "$SHA")" --read-only yes); RC=$?
assert_eq "gate --read-only: judges the newest report" not_clean "$(printf '%s' "$G" | field status)"
assert_eq "gate --read-only: writes no round" 2 "$(rounds_len)"
NX=$(python3 "$CS" next --cwd "$C" --repo $REPO --issue $N --read-only yes 2>"$S/err"); RC=$?
assert_eq "next --read-only: Phase 4's answer stands" stop "$(nx decision)"
NO_PREGATE=1 run_stage
stop_case "early, a report posted after Phase 4 stopped" "not the round"
# verify r3 #2: without a stop mode, a record with fewer attempts than rounds does not merge
pr_scenario stop-nomode-noattempts; gate_run
python3 - "$C/.claude/.idd/state/idd-all-run-7.json" <<'PY'
import json, sys
p = sys.argv[1]; st = json.load(open(p)); last = st["rounds"][-1]
st["rounds"] = [dict(last, round=1, report_id=-1), dict(last, round=2, report_id=-2), dict(last, round=3)]
st.pop("attempts"); json.dump(st, open(p, "w"))
PY
NO_PREGATE=1 run_stage
stop_case "no stop mode, three rounds and no attempts recorded" "inconsistent"
# verify r3 #3: before any gate result is recorded, next cannot decide
new_scenario stop-nomode-nogate; init_state PR PR no no unattended none; next_run
assert_eq "no stop mode, nothing recorded yet: stop" stop "$(nx decision)"
assert_exit "no stop mode, nothing recorded yet: undecided" 3 "$RC"
# spec (fix round 1): exhaustive-all with --review counts Blocking only
new_scenario stop-exall-review; write_rounds exhaustive-all unattended yes "0,2,0"; next_run
assert_eq "exhaustive-all --review, 0 Blocking: stop" stop "$(nx decision)"
assert_eq "exhaustive-all --review: no merge" False "$(nx merge)"
assert_grep "exhaustive-all --review: the reason says no Blocking" "no Blocking" "$(nx reason)"
# spec (fix round 1): an empty round record does not merge
pr_scenario stop-nomode-empty; NO_PREGATE=1 run_stage
stop_case "no stop mode, an empty round record" "never judged"

# spec (Clean verify leads to merge and close): a stop-mode run is not stopped by its own length
age_state() { # created-hours-ago last-round-hours-ago
  python3 - "$C/.claude/.idd/state/idd-all-run-7.json" "$1" "$2" <<'EOF'
import json, sys, time
path, created, last = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
st = json.load(open(path))
fmt = lambda h: time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(time.time() - h * 3600))
st["created_at"] = fmt(created)
if st.get("rounds"):
    st["rounds"][-1]["at"] = fmt(last)
json.dump(st, open(path, "w"))
EOF
}
pr_scenario stop-ttl-mode; init_state PR PR no no unattended exhaustive-all; gate_run; age_state 30 2; run_stage
assert_eq "exhaustive-all, created 30 h ago, last round 2 h ago: merged" merged "$(printf '%s' "$OUT" | field status)"
pr_scenario stop-ttl-old; init_state PR PR no no unattended exhaustive-all; gate_run; age_state 30 26; run_stage
stop_case "exhaustive-all, last round 26 h ago" "older than 24 hours"
pr_scenario stop-ttl-nomode; gate_run; age_state 30 2; run_stage
stop_case "no stop mode, created 30 h ago" "older than 24 hours"

# spec (Unattended fix loop … two-round limit): a third round is caught by the close stage
pr_scenario stop-third-round; gate_run
python3 - "$C/.claude/.idd/state/idd-all-run-7.json" <<'EOF'
import json, sys
p = sys.argv[1]; st = json.load(open(p)); last = st["rounds"][-1]
st["rounds"] = [dict(last, round=1, report_id=-1), dict(last, round=2, report_id=-2), dict(last, round=3)]
st["attempts"] = [{"sha": "1" * 40, "report_id": -1, "at": last["at"]}, {"sha": "2" * 40, "report_id": -2, "at": last["at"]},
                  {"sha": last["sha"], "report_id": last["report_id"], "at": last["at"]}]
json.dump(st, open(p, "w"))
EOF
assert_eq "no stop mode, 3 rounds: the record holds exactly 3 attempts (verify r4 #5)" 3 "$(attempts_len)"
NO_PREGATE=1 run_stage
assert_eq "no stop mode, 3 rounds: the close stage added no attempt" 3 "$(attempts_len)"
stop_case "no stop mode, 3 rounds recorded" "2 verify rounds"
# verify r4 #1: a gate result read for one run is not written into the run that replaced it
pr_scenario stop-gate-replaced
RR=$(python3 - "$CS" "$C" "$REPO" "$N" "$SHA" <<'PY'
import importlib.util, json, sys
cs, cwd, repo, n, sha = sys.argv[1:]
spec = importlib.util.spec_from_file_location("cs", cs); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
since = m.run_since(cwd, n)
p = m.state_path(cwd, n); st = json.load(open(p)); st["created_at"] = "2099-01-01T00:00:00Z"; json.dump(st, open(p, "w"))
try:
    m.record_round(cwd, repo, n, {"status": "clean", "comment_id": 5, "blocking": 0, "in_scope": 0}, sha, since)
    print("written", len(json.load(open(p)).get("rounds") or []))
except m.Stop as exc:   # only the close stage's own refusal counts
    print("refused", len(json.load(open(p)).get("rounds") or []), exc)
PY
)
assert_grep "gate: a result read for a replaced run is refused" "refused 0" "$RR"
# spec-example: idd-pr-hitl-modes / the run state is identified and locked
# #602 1: a run replaced within the same second (same created_at, another run_id) is not recorded
pr_scenario stop-gate-sameSecond
RR=$(python3 - "$CS" "$C" "$REPO" "$N" "$SHA" <<'PY'
import importlib.util, json, sys
cs, cwd, repo, n, sha = sys.argv[1:]
spec = importlib.util.spec_from_file_location("cs", cs); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
ident = m.run_identity(cwd, n)
p = m.state_path(cwd, n); st = json.load(open(p)); st["run_id"] = "another-run"; json.dump(st, open(p, "w"))
try:
    m.record_round(cwd, repo, n, {"status": "clean", "comment_id": 5, "blocking": 0, "in_scope": 0}, sha, ident["created_at"], ident["run_id"])
    print("written", len(json.load(open(p)).get("rounds") or []))
except m.Stop as exc:
    print("refused", len(json.load(open(p)).get("rounds") or []), exc)
PY
)
assert_grep "gate: a run replaced with the same created_at but another run_id is refused" "refused 0" "$RR"
pr_scenario stop-runid
assert_grep "init: the run state carries a run_id" '"run_id": "' "$(cat "$C/.claude/.idd/state/idd-all-run-7.json")"
# #602 1: the run-state lock is exclusive, and record_round takes it
pr_scenario stop-gate-lock
LK=$(python3 - "$CS" "$C" "$REPO" "$N" "$SHA" <<'PY'
import fcntl, importlib.util, os, subprocess, sys
cs, cwd, repo, n, sha = sys.argv[1:]
spec = importlib.util.spec_from_file_location("cs", cs); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
probe = "import fcntl,os,sys\nfd=os.open(sys.argv[1], os.O_RDWR)\ntry:\n fcntl.flock(fd, fcntl.LOCK_EX|fcntl.LOCK_NB); print('free')\nexcept BlockingIOError:\n print('held')"
with m.state_lock(cwd, n):
    held = subprocess.run([sys.executable, "-c", probe, m.lock_path(cwd, n)], capture_output=True, text=True).stdout.strip()
after = subprocess.run([sys.executable, "-c", probe, m.lock_path(cwd, n)], capture_output=True, text=True).stdout.strip()
taken = []
real = m.state_lock
def spy(*a, **k):
    taken.append(1); return real(*a, **k)
m.state_lock = spy
ident = m.run_identity(cwd, n)
m.record_round(cwd, repo, n, {"status": "clean", "comment_id": 5, "blocking": 0, "in_scope": 0}, sha, ident["created_at"], ident["run_id"])
print(f"inside={held} after={after} record_round_locks={len(taken)}")
PY
)
assert_eq "lock: held inside state_lock, free after, and record_round takes it" "inside=held after=free record_round_locks=1" "$LK"
# #602 2: a record without verify_stop is refused, never read as no stop mode
pr_scenario stop-no-verify-stop
python3 - "$C/.claude/.idd/state/idd-all-run-7.json" <<'PY'
import json, sys
p = sys.argv[1]; st = json.load(open(p)); st.pop("verify_stop"); json.dump(st, open(p, "w"))
PY
next_run
assert_eq "next: a record without verify_stop → stop" stop "$(nx decision)"
assert_exit "next: a record without verify_stop → undecided" 3 "$RC"
assert_grep "next: … and says verify_stop is missing" "has no verify_stop field" "$(nx reason)"
NO_PREGATE=1 run_stage
stop_case "run: a record without verify_stop" "has no verify_stop field"
# spec-example: idd-pr-hitl-modes / next says whether it decided
# #602 3: next prints decided, so Phase 4 can take the fallback without the exit code
new_scenario stop-decided; init_state PR PR no no unattended none; next_run
assert_eq "next: nothing recorded yet → decided is false in the answer" False "$(nx decided)"
write_rounds none unattended no "0,3,0"; next_run
assert_eq "next: one not_clean round → fix" fix "$(nx decision)"
assert_eq "next: … and decided is true" True "$(nx decided)"
# verify r5 #4: a run-state path the close stage refuses (a symlink) is an unparseable gate result, not a traceback
pr_scenario stop-gate-symlink
mv "$C/.claude/.idd/state/idd-all-run-7.json" "$S/real-state.json"
ln -s "$S/real-state.json" "$C/.claude/.idd/state/idd-all-run-7.json"
gate_run
assert_exit "gate: a symlinked run state is unparseable (exit 2)" 2 "$RC"
assert_eq "gate: … with a JSON answer" unparseable "$(printf '%s' "$G" | field status)"
# #602 r1 #11 (r2 #15): after a gate that could not write the record, next reads the readable record and is undecided
restore_state() { rm -f "$C/.claude/.idd/state/idd-all-run-7.json"; mv "$S/real-state.json" "$C/.claude/.idd/state/idd-all-run-7.json"; }
restore_state
next_run
assert_eq "next: after a gate that could not write → decided is false" False "$(nx decided)"
assert_eq "next: … at round 0 (the record is readable and has no round)" 0 "$(nx round)"
# spec-example: idd-pr-hitl-modes / replaced is marked and stops the run
# #602 r1 #3/#4: a run replaced while the gate reads is marked replaced, so Phase 4 stops instead of fixing
pr_scenario stop-gate-replaced-flag
RP=$(IDD_GH="$FAKE" FAKE_GH_DIR="$S/gh" python3 - "$CS" "$C" "$REPO" "$N" "$SHA" "$(base_of "$SHA")" <<'PY'
import importlib.util, io, json, sys, contextlib
cs, cwd, repo, n, sha, base = sys.argv[1:]
spec = importlib.util.spec_from_file_location("cs", cs); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
real = m.run_identity
def stale(c, i):
    ident = real(c, i); ident["run_id"] = "the-run-this-gate-started-for"; return ident
m.run_identity = stale
out = io.StringIO()
with contextlib.redirect_stdout(out):
    rc = m.cmd_gate(["--cwd", cwd, "--repo", repo, "--issue", n, "--sha", sha, "--base", base])
print(rc, json.loads(out.getvalue()).get("replaced"), json.loads(out.getvalue())["status"])
PY
)
assert_eq "gate: a run replaced while it read → unparseable and replaced" "2 True unparseable" "$RP"
pr_scenario stop-next-replaced-flag
write_rounds exhaustive-blocking unattended no "2,0,0"
NR=$(python3 - "$CS" "$C" "$REPO" "$N" <<'PY'
import importlib.util, io, json, sys, contextlib
cs, cwd, repo, n = sys.argv[1:]
spec = importlib.util.spec_from_file_location("cs", cs); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
real = m.read_state; calls = []
def second_differs(c, r, i):
    st = real(c, r, i); calls.append(1)
    if len(calls) > 1: st = dict(st, run_id="another-run")
    return st
m.read_state = second_differs
out = io.StringIO()
with contextlib.redirect_stdout(out):
    rc = m.cmd_next(["--cwd", cwd, "--repo", repo, "--issue", n])
a = json.loads(out.getvalue()); print(rc, a["decision"], a.get("replaced"), a["decided"])
PY
)
assert_eq "next: a run replaced while it decided → stop, replaced, undecided" "3 stop True False" "$NR"
# #602 r1 #6: init and next's fix answer take the lock
pr_scenario stop-lock-writers
LW=$(python3 - "$CS" "$C" "$REPO" "$N" <<'PY'
import importlib.util, io, sys, contextlib
cs, cwd, repo, n = sys.argv[1:]
spec = importlib.util.spec_from_file_location("cs", cs); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
taken = []; real = m.state_lock
def spy(*a, **k):
    taken.append(1); return real(*a, **k)
m.state_lock = spy
with contextlib.redirect_stdout(io.StringIO()):
    m.cmd_init(["--cwd", cwd, "--repo", repo, "--issue", n, "--path", "PR", "--requested-path", "PR", "--interaction", "unattended",
                "--branch", "b", "--default", "main", "--review", "no", "--in-chain", "no", "--stop", "exhaustive-blocking"])
init_locks = len(taken)
import json
p = m.state_path(cwd, n); st = json.load(open(p))
st["rounds"] = [{"round": 1, "sha": "a" * 40, "status": "not_clean", "blocking": 2, "in_scope": 0, "low_in_scope": 0,
                 "report_id": 9, "at": st["created_at"]}]
st["attempts"] = [{"sha": "a" * 40, "report_id": 9, "at": st["created_at"]}]
st["last_gate"] = {"status": "not_clean", "report_id": 9, "sha": "a" * 40, "at": st["created_at"]}; json.dump(st, open(p, "w"))
with contextlib.redirect_stdout(io.StringIO()):
    m.cmd_next(["--cwd", cwd, "--repo", repo, "--issue", n])
with contextlib.redirect_stdout(io.StringIO()):
    m.cmd_reset(["--cwd", cwd, "--issue", n])
print(f"init={init_locks} next={len(taken) - init_locks - 1} reset=1" if len(taken) == init_locks + 2 else f"locks={taken} init={init_locks}")
PY
)
assert_eq "lock: init, next's fix answer and reset each take the lock" "init=1 next=1 reset=1" "$LW"
# #602 r1 #10: a writer waits for a lock held by another process (spec Example, third row)
pr_scenario stop-lock-waits
LWAIT=$(python3 - "$CS" "$C" "$REPO" "$N" "$SHA" <<'PY'
import importlib.util, subprocess, sys, time, json
cs, cwd, repo, n, sha = sys.argv[1:]
spec = importlib.util.spec_from_file_location("cs", cs); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
hold = ("import fcntl,os,sys,time\nfd=os.open(sys.argv[1], os.O_RDWR|os.O_CREAT, 0o600)\nfcntl.flock(fd, fcntl.LOCK_EX)\n"
        "print('held', flush=True)\ntime.sleep(1.0)\n")
p = subprocess.Popen([sys.executable, "-c", hold, m.lock_path(cwd, n)], stdout=subprocess.PIPE, text=True)
assert p.stdout.readline().strip() == "held"
ident = m.run_identity(cwd, n); t = time.monotonic()
m.record_round(cwd, repo, n, {"status": "clean", "comment_id": 5, "blocking": 0, "in_scope": 0}, sha, ident["created_at"], ident["run_id"])
waited = time.monotonic() - t; p.wait()
print("waited" if waited >= 0.7 else f"no-wait {waited:.2f}", len(json.load(open(m.state_path(cwd, n)))["rounds"]))
PY
)
assert_eq "lock: a writer waits for a lock another process holds, then writes" "waited 1" "$LWAIT"
# #602 r1 #7: a verify_stop value that is not null or a mode is refused
pr_scenario stop-bad-verify-stop
python3 - "$C/.claude/.idd/state/idd-all-run-7.json" <<'PY'
import json, sys
p = sys.argv[1]; st = json.load(open(p)); st["verify_stop"] = "sometimes"; json.dump(st, open(p, "w"))
PY
next_run
assert_eq "next: verify_stop 'sometimes' → stop" stop "$(nx decision)"
assert_exit "next: … undecided" 3 "$RC"
assert_grep "next: … and names the value" "'sometimes'" "$(nx reason)"
NO_PREGATE=1 run_stage
stop_case "run: a verify_stop value that is not a mode" "not null or one of"
# #602 r2 #1: a verify report of this run that is not in the round record (an unrecorded round) blocks the merge
# spec-example: idd-pr-hitl-modes / an unrecorded round blocks the merge
pr_scenario stop-unrecorded-report
LG=$(IDD_GH="$FAKE" FAKE_GH_DIR="$S/gh" python3 - "$CS" "$C" "$REPO" "$N" "$SHA" "$(base_of "$SHA")" <<'PY'
import importlib.util, json, sys
cs, cwd, repo, n, sha, base = sys.argv[1:]
spec = importlib.util.spec_from_file_location("cs", cs); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
st = m.read_state(cwd, repo, n)
rc, gate = m.judge_report(repo, n, sha, base, m.parse_iso(st["created_at"]))
print("ids", json.dumps(gate.get("reports_since")))
rid = gate["comment_id"]
st["rounds"] = [{"round": 1, "sha": sha, "status": "clean", "blocking": 0, "in_scope": 0, "low_in_scope": 0, "report_id": rid, "at": st["created_at"]}]
st["attempts"] = [{"sha": sha, "report_id": rid, "at": st["created_at"]}]
ok = "merge-ok"
try:
    m.merge_gate(st, rc, dict(gate, reports_since=[rid]), sha)
except m.Stop as exc:
    ok = f"refused {exc}"
try:
    m.merge_gate(st, rc, dict(gate, reports_since=[rid - 1, rid]), sha)
    print(ok, "| unrecorded: merge-ok")
except m.Stop as exc:
    print(ok, "| unrecorded: refused", exc)
PY
)
assert_grep "gate: the gate lists this run's report ids" "ids [" "$LG"
assert_grep "merge: every report of this run in the record → the ledger does not refuse" "merge-ok |" "$LG"
assert_grep "merge: a report of this run not in the record → refused" "unrecorded: refused" "$LG"
assert_grep "merge: … and says a round was not recorded" "not recorded" "$LG"
# #602 r2 #5/#10: a record deleted (reset) after the gate or next read it is a replaced run
pr_scenario stop-deleted-replaced
DR=$(python3 - "$CS" "$C" "$REPO" "$N" "$SHA" <<'PY'
import importlib.util, os, sys
cs, cwd, repo, n, sha = sys.argv[1:]
spec = importlib.util.spec_from_file_location("cs", cs); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
ident = m.run_identity(cwd, n)
os.unlink(m.state_path(cwd, n))
try:
    m.record_round(cwd, repo, n, {"status": "clean", "comment_id": 5, "blocking": 0, "in_scope": 0}, sha, ident["created_at"], ident["run_id"])
    print("gate: written-or-skipped")
except m.Replaced:
    print("gate: replaced")
except m.Stop as exc:
    print("gate: stop", exc)
PY
)
assert_eq "gate: the record it read for was deleted → replaced" "gate: replaced" "$DR"
# #602 r2 #4/#11: reset waits for a held lock, then deletes
pr_scenario stop-reset-waits
RW=$(python3 - "$CS" "$C" "$REPO" "$N" <<'PY'
import importlib.util, io, os, subprocess, sys, time, contextlib
cs, cwd, repo, n = sys.argv[1:]
spec = importlib.util.spec_from_file_location("cs", cs); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
hold = ("import fcntl,os,sys,time\nfd=os.open(sys.argv[1], os.O_RDWR|os.O_CREAT, 0o600)\nfcntl.flock(fd, fcntl.LOCK_EX)\n"
        "print('held', flush=True)\ntime.sleep(1.0)\n")
p = subprocess.Popen([sys.executable, "-c", hold, m.lock_path(cwd, n)], stdout=subprocess.PIPE, text=True)
assert p.stdout.readline().strip() == "held"
t = time.monotonic()
with contextlib.redirect_stdout(io.StringIO()):
    rc = m.cmd_reset(["--cwd", cwd, "--issue", n])
waited = time.monotonic() - t; p.wait()
print("waited" if waited >= 0.7 else f"no-wait {waited:.2f}", rc, os.path.exists(m.state_path(cwd, n)))
PY
)
assert_eq "reset: waits for a lock another process holds, then deletes" "waited 0 False" "$RW"
# #602 r2 #12/#14: reset with nothing to delete touches nothing, and a lock that cannot be opened does not keep the state
new_scenario stop-reset-nothing
python3 "$CS" reset --cwd "$C" --issue $N; RC=$?
assert_exit "reset: nothing to delete → 0" 0 "$RC"
assert_eq "reset: … and creates no state directory" no "$([ -e "$C/.claude/.idd/state" ] && echo yes || echo no)"
pr_scenario stop-reset-badlock
rm -f "$C/.claude/.idd/state/idd-all-run-7.lock"; ln -s "$S/elsewhere" "$C/.claude/.idd/state/idd-all-run-7.lock"
python3 "$CS" reset --cwd "$C" --issue $N 2>"$S/err"; RC=$?
assert_exit "reset: a lock path that cannot be used → still deletes, exit 0" 0 "$RC"
assert_eq "reset: … the run state is gone" no "$([ -e "$C/.claude/.idd/state/idd-all-run-7.json" ] && echo yes || echo no)"
assert_grep "reset: … and warns about the lock" "lock" "$(cat "$S/err")"
# #602 r2 #19: init with a lock path that cannot be used is an error message, not a traceback
new_scenario stop-init-badlock
mkdir -p "$C/.claude/.idd/state"; ln -s "$S/elsewhere" "$C/.claude/.idd/state/idd-all-run-7.lock"
python3 "$CS" init --cwd "$C" --repo $REPO --issue $N --path PR --requested-path PR --interaction unattended --branch b --default main --review no --in-chain no --stop none 2>"$S/err"; RC=$?
assert_exit "init: a lock path that cannot be used → exit 3" 3 "$RC"
refute_grep "init: … without a traceback" "Traceback" "$(cat "$S/err")"

print_summary close-stage
