#!/usr/bin/env python3
"""close-stage.py — /idd-all's close stage, in one process (#392).

Why a helper and not bash blocks in the skill: every check that guards a merge
or a push has to run in the SAME process as the merge or push. Bash blocks in a
skill run one tool call at a time, and a failed check that ends its own block
with `exit 0` does not stop the next block (#383 r2 #12; #392 verify r1 #9).
Shell variables do not survive between tool calls either, so the values the
checks depend on (the run's flags, the PR, the verified commit) are read from a
state file and from GitHub here, never from the model's memory.

Subcommands
  init  --cwd C --repo O/R --issue N --path PR|direct-commit --requested-path PR|direct-commit
        --interaction attended|unattended --branch B --default D --review yes|no --in-chain yes|no
        Step 0.7: record the run's flags in C/.claude/.idd/state/idd-all-run-N.json.
        Every value is required: a value lost between tool calls is a usage
        error (64), never a silent "no" (#392 verify r2 #3).
  gate  --cwd C --repo O/R --issue N --sha SHA [--base SHA]
        Read the newest verify report this account posted on the issue since
        the run began, as GitHub renders it (body_html), and judge it with
        verify-gate.py --expect-sha [--expect-base]. The newest one must be a
        '## Verify: #N' report (a PR-mode report or pointer is not read here).
        Prints the gate JSON plus comment_id / verify_url.
        Exit 0 clean, 1 not clean, 2 unparseable (including: no such report,
        any error), 64 usage.
  run   --cwd C --repo O/R --issue N [--ci-timeout S] [--ci-grace S]
        Phase 5c: every guardrail, then the squash merge (PR) or the push
        (direct-commit). The CI guardrail runs the local CI gate
        (idd-ci-gate.sh) on the verified commit; only in remote mode (exit 10)
        does it wait for the PR's remote checks. Prints one JSON line and writes it to
        C/.claude/.idd/state/idd-all-result-N.json.
        Exit 0 merged/pushed, 3 stopped (reason in the JSON, including any
        error), 64 usage.
  reset --cwd C --issue N
        Abort duty: remove this issue's run-state and result files. (init does the
        same for the run it records.)
  confirm-close --cwd C --repo O/R --issue N
        After /idd-close: the issue is CLOSED and a comment by this account
        that opens with the canonical '## Closing Summary' heading was posted
        after the merge or push recorded in the result file. Exit 0 confirmed,
        3 not confirmed, 64 usage.

Fail closed throughout: anything that cannot be read or checked stops the
stage. Nothing here asks a person; a stop is reported, not negotiated.

Test seams (honoured only when IDD_CLOSE_STAGE_TEST=1): IDD_GH / IDD_GIT name
the gh and git executables; IDD_CI_GATE names the local CI gate; IDD_SLEEP=0
makes the wait loops not sleep.

Result fields a merge or push can carry besides the commit: `low_in_scope` (LOW
In-scope fix findings the merge did not wait for), `proposed_corrections`
(comments whose Proposed Corrections nobody answered), `local_ci` (pass or
remote), and with local CI `remote_ci_failed` / `remote_ci_pending` (remote
checks read once; they are reported and do not stop the merge).

Modules (scripts/lib/): ghread.py reads GitHub and git and fails closed;
intent.py decides whether the intent was confirmed and whether anyone else got
involved; workflows.py decides whether a push to the default branch publishes;
rendered.py reads GitHub's rendering of a comment, shared with verify-gate.py.
"""

import json
import math
import os
import re
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(HERE, "lib"))
import workflows  # noqa: E402  scripts/lib/workflows.py — does a push to the default branch publish?
from ghread import (CI_GATE_RESULTS, GH, GIT, SLEEP, TEST, Stop, gh_json, git, issue_comments, issue_view, iso,  # noqa: E402
                    local_ci, now, gh_paginated, parse_iso, run_cmd, session_login, ts, first_line)
from intent import (check_intent, check_issue_authors, check_meeting, check_others,  # noqa: E402
                    check_pr_people, issue_meta)

WRITE_PERMS = {"WRITE", "MAINTAIN", "ADMIN"}
STATE_TTL = 24 * 3600
REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
# A close keyword next to an issue reference in any form GitHub acts on:
# `#N`, `owner/repo#N`, or an issue/PR URL. Unlike idd-verify Step 0.8's
# warn-only Source 2, a hyphen or slash before the keyword does NOT exempt it:
# GitHub splits `idd-close #N` and closes the issue (#173).
TRAP_RE = re.compile(
    r"(?<![A-Za-z0-9])(close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s*:?\s*"
    r"(#\d+|[\w.-]+/[\w.-]+#\d+|https?://github\.com/[\w.-]+/[\w.-]+/(?:issues|pull)/\d+)",
    re.IGNORECASE,
)


def state_dir(cwd):
    cwd = os.path.realpath(cwd)   # a trailing slash or a symlinked ancestor of --cwd must not move the walk (r4 #43)
    d = os.path.join(cwd, ".claude", ".idd", "state")
    probe = d
    while probe and probe != cwd and probe != os.path.dirname(probe):
        if os.path.islink(probe):
            raise Stop(f"{probe} is a symlink — refusing to read or write run state through it")
        probe = os.path.dirname(probe)
    return d


def safe_path(path):
    if os.path.islink(path):
        raise Stop(f"{path} is a symlink — refusing to use it")
    return path


def state_path(cwd, n):
    return safe_path(os.path.join(state_dir(cwd), f"idd-all-run-{n}.json"))


def result_path(cwd, n):
    return safe_path(os.path.join(state_dir(cwd), f"idd-all-result-{n}.json"))


# ── arguments ──────────────────────────────────────────────────────────────

def parse(argv, spec):
    """spec: {flag: 'value'}. Returns dict or None on a malformed command line."""
    out, i = {}, 0
    while i < len(argv):
        flag = argv[i]
        if flag not in spec or flag in out or i + 1 >= len(argv) or argv[i + 1] == "":
            return None
        out[flag] = argv[i + 1]
        i += 2
    return out


def usage(msg):
    print(f"close-stage: {msg}", file=sys.stderr)
    return 64


def common_ok(a):
    return bool(a.get("--cwd") and os.path.isdir(a["--cwd"])
                and REPO_RE.match(a.get("--repo", ""))
                and re.match(r"^[0-9]+$", a.get("--issue", "")))


# ── init ───────────────────────────────────────────────────────────────────

def cmd_init(argv):
    keys = ["--cwd", "--repo", "--issue", "--path", "--requested-path", "--interaction", "--branch",
            "--default", "--review", "--in-chain"]
    a = parse(argv, {k: "value" for k in keys})
    if a is None or not common_ok(a) or any(k not in a for k in keys):
        return usage("init needs every one of: " + " ".join(keys) + " (each with a value)")
    if a["--path"] not in ("PR", "direct-commit") or a["--requested-path"] not in ("PR", "direct-commit"):
        return usage("--path and --requested-path must be PR or direct-commit")
    if a["--interaction"] not in ("attended", "unattended"):
        return usage("--interaction must be attended or unattended")
    if a["--review"] not in ("yes", "no") or a["--in-chain"] not in ("yes", "no"):
        return usage("--review and --in-chain must be yes or no")
    cwd = os.path.realpath(a["--cwd"])
    try:
        spath, rpath = state_path(cwd, a["--issue"]), result_path(cwd, a["--issue"])
    except Stop as exc:
        print(f"close-stage: {exc}", file=sys.stderr)
        return 3
    state = {
        "repo": a["--repo"], "issue": int(a["--issue"]), "path": a["--path"],
        "requested_path": a["--requested-path"], "interaction": a["--interaction"],
        "branch": a["--branch"], "default": a["--default"],
        "review": a["--review"] == "yes", "in_chain": a["--in-chain"] == "yes",
        "created_at": iso(now()),
    }
    os.makedirs(os.path.dirname(spath), exist_ok=True)
    with open(spath, "w", encoding="utf-8") as fh:
        json.dump(state, fh)
    if os.path.exists(rpath):
        os.unlink(rpath)
    print(spath)
    return 0


def cmd_reset(argv):
    a = parse(argv, {"--cwd": "value", "--issue": "value"})
    if a is None or not a.get("--cwd") or not os.path.isdir(a["--cwd"]) or not re.match(r"^[0-9]+$", a.get("--issue", "")):
        return usage("reset needs --cwd <dir> --issue <digits>")
    try:
        for path in (state_path(a["--cwd"], a["--issue"]), result_path(a["--cwd"], a["--issue"])):
            if os.path.exists(path):
                os.unlink(path)
    except (Stop, OSError) as exc:
        print(f"close-stage: reset failed: {exc}", file=sys.stderr)
        return 3
    return 0


# ── gate ───────────────────────────────────────────────────────────────────


def latest_report(n, me, since, comments):
    """The newest verify comment THIS account posted since the run began.

    Only this account: anyone else's comment after the run began stops the
    close stage on its own (check_others), so a teammate's report is never
    weighed here. Every verify heading counts when picking the newest, and the
    newest must be the branch-mode `## Verify: #N` report: a PR-mode report or
    its `## Verify (via PR #P)` pointer, posted later by someone running
    /idd-verify --pr with this account, is not read past (r4 #22). Reports older
    than the run's state are an earlier run's (r3 #6; no slack, r4 #8).
    """
    any_verify = re.compile(r"^#{1,6}[ \t]*Verify\b")
    found = [c for c in comments if c.get("login") == me and any_verify.match(first_line(c.get("body")))
             and (since is None or ts(c.get("created_at")) >= since)]
    if not found:
        return None, "none"
    newest = found[-1]
    if not re.match(rf"^## Verify: #{n}(?![0-9])", first_line(newest.get("body"))):
        return None, first_line(newest.get("body"))[:60]
    return newest, ""


def judge_report(repo, n, sha, base, since):
    me = session_login()
    report, other = latest_report(n, me, since, issue_comments(repo, n))
    if report is None:
        when = f" since {iso(since)}" if since is not None else ""
        if other == "none":
            return 2, {"status": "unparseable", "reason": f"no verify report by this account{when}"}
        return 2, {"status": "unparseable",
                   "reason": f"the newest verify comment by this account{when} is '{other}', not a '## Verify: #{n}' report"}
    # A verdict changes only with a new verify round: a report edited after it was posted is not read (r5 #14),
    # nor one a maintainer hid as outdated or off-topic.
    if ts(report.get("updated_at")) != ts(report.get("created_at")):
        return 2, {"status": "unparseable", "reason": "the verify report was edited after it was posted — run verify again"}
    if not report.get("node_id"):
        return 2, {"status": "unparseable", "reason": "could not tell whether the verify report is hidden (no node id)"}
    q = "query($id:ID!){node(id:$id){... on IssueComment{isMinimized}}}"
    node = (gh_json(["api", "graphql", "-f", f"query={q}", "-f", f"id={report['node_id']}"],
                    "whether the verify report is hidden").get("data") or {}).get("node") or {}
    if node.get("isMinimized"):
        return 2, {"status": "unparseable", "reason": "the verify report is hidden on GitHub — a person set it aside"}
    html = report.get("body_html")
    if not html:
        return 2, {"status": "unparseable", "reason": "GitHub returned no rendered HTML for the verify report"}
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as fh:
        fh.write(html)
        tmp = fh.name
    try:
        cmd = [sys.executable, "-I", os.path.join(HERE, "verify-gate.py"), "--html-file", tmp, "--expect-sha", sha]
        if base:
            cmd += ["--expect-base", base]
        rc, out, err = run_cmd(cmd)
    finally:
        os.unlink(tmp)
    try:
        result = json.loads(out)
    except ValueError:
        return 2, {"status": "unparseable", "reason": f"verify-gate.py gave no JSON (exit {rc})"}
    result["comment_id"] = report.get("id")
    result["verify_url"] = report.get("html_url")
    result["report_author"] = report.get("login")
    return (rc if rc in (0, 1, 2) else 2), result


def gate_stop(rc, gate):
    """The one predicate every merge and push passes (r6 #1): clean, and nothing a person has to settle.
    A clean result without these fields stops too."""
    if rc != 0:
        raise Stop(f"guardrail 1 (verify gate) — {gate.get('status')}: {gate.get('reason')}")
    for field in ("rejected", "high_follow_up", "process_gaps"):
        if field not in gate or gate[field] is None:
            raise Stop(f"guardrail 1 (verify gate) — the gate did not report {field}")
    if gate["rejected"]:
        raise Stop(f"guardrail 1 (verify gate) — the report marks {gate['rejected']} finding(s) Rejected: the run judged "
                   "a reviewer wrong about its own code; a person decides whether they stand")
    if gate["high_follow_up"]:
        raise Stop(f"guardrail 1 (verify gate) — {gate['high_follow_up']} serious finding(s) filed as Follow-up; "
                   "a person agrees before they are left for later")
    if gate["process_gaps"]:
        raise Stop("guardrail 1 (verify gate) — the verify ran degraded (a reviewer or the cross-model pass is missing); "
                   "a person reviews this one")


def run_since(cwd, n):
    try:
        with open(state_path(cwd, n), encoding="utf-8") as fh:
            return parse_iso(json.load(fh)["created_at"])
    except (OSError, ValueError, KeyError, TypeError):
        return None


def cmd_gate(argv):
    a = parse(argv, {"--cwd": "value", "--repo": "value", "--issue": "value", "--sha": "value", "--base": "value"})
    if a is None or not common_ok(a) or not SHA_RE.match(a.get("--sha", "")) \
            or ("--base" in a and not SHA_RE.match(a["--base"])):
        return usage("gate needs --cwd --repo --issue and --sha (40 lowercase hex digits), optionally --base")
    try:
        rc, result = judge_report(a["--repo"], a["--issue"], a["--sha"], a.get("--base"), run_since(a["--cwd"], a["--issue"]))
    except Stop as exc:
        rc, result = 2, {"status": "unparseable", "reason": str(exc)}
    except Exception as exc:  # fail closed: any surprise is unparseable, never "not clean"
        rc, result = 2, {"status": "unparseable", "reason": f"internal error: {exc.__class__.__name__}: {exc}"}
    print(json.dumps(result, ensure_ascii=False))
    return rc


# ── run: shared checks ─────────────────────────────────────────────────────

def load_state(cwd, repo, n):
    try:
        with open(state_path(cwd, n), encoding="utf-8") as fh:
            st = json.load(fh)
    except (OSError, ValueError):
        raise Stop("no run state for this issue (Step 0.7 did not record the run's flags) — not merging")
    if st.get("repo") != repo or str(st.get("issue")) != str(n):
        raise Stop("the run state names another repo or issue — not merging")
    try:
        age = now() - parse_iso(st["created_at"])
    except (KeyError, ValueError, TypeError):
        raise Stop("the run state has no readable creation time — not merging")
    if age > STATE_TTL or age < -300:
        raise Stop("the run state is older than 24 hours (an earlier run's) — not merging; rerun /idd-all")
    return st


def check_origin(cwd, repo):
    """Every fetch and push URL of origin must be github.com/<repo> (git pushes to each push URL, r4 #33)."""
    urls = git(cwd, "remote", "get-url", "--all", "origin").splitlines() \
        + git(cwd, "remote", "get-url", "--push", "--all", "origin").splitlines()
    for url in [u.strip() for u in urls if u.strip()]:
        if TEST and url.startswith("/"):
            host, path = "github.com", url
        else:
            # userinfo may be empty (`https://@github.com/...`, r4 #19)
            m = re.match(r"^(?:https?://(?:[^@/]*@)?|ssh://(?:[^@/]*@)?|git@)([^/:]+)[:/](.+)$", url)
            if not m:
                raise Stop(f"origin URL {url} is not a GitHub URL — not pushing or merging")
            host, path = m.group(1).lower(), m.group(2)
        m2 = re.search(r"([^/:]+/[^/]+?)(?:\.git)?/?$", path)
        if host != "github.com" or not m2 or m2.group(1).lower() != repo.lower():
            raise Stop(f"origin ({url}) is not github.com/{repo} — not pushing or merging")


def workflow_files(cwd, ref):
    rc, out, err = run_cmd([GIT, "-C", cwd, "ls-tree", "-r", "-z", "--name-only", ref, "--", ".github/workflows"])
    if rc != 0:
        raise Stop(f"could not list the workflows at {ref[:12]}: {err.strip()[:200]}")
    files = []
    for path in [p for p in out.split("\0") if p]:
        rc, text, err = run_cmd([GIT, "-C", cwd, "show", f"{ref}:{path}"])
        if rc != 0:
            raise Stop(f"could not read {path} at {ref[:12]}")
        files.append((path, text))
    return files


def read_at(cwd, ref, path):
    rc, out, err = run_cmd([GIT, "-C", cwd, "show", f"{ref}:{path}"])
    return out if rc == 0 else None


def releases_on_push(cwd, ref, default):
    """Workflows at `ref` that publish when `default` moves (scripts/lib/workflows.py; unknown counts as yes)."""
    return workflows.publishing(workflow_files(cwd, ref), lambda path: read_at(cwd, ref, path), default)


def expects_pr_checks(cwd, ref, default):
    """A workflow that runs on every pull_request into the default branch will report a check."""
    return any(workflows.runs_on_every_pr(text, default) for _, text in workflow_files(cwd, ref))


def touches_ci(cwd, base, head):
    out = git(cwd, "diff", "--name-only", f"{base}..{head}", "--", ".github/workflows", ".github/actions")
    return [p for p in out.splitlines() if p]


def scan_commits(cwd, base, head, n=None):
    """(foreign, trapped) short SHAs for base..head, from local git (no list cap)."""
    log = git(cwd, "log", "--format=%H%x00%s%x00%b%x1e", f"{base}..{head}")
    commits = [c.strip("\n") for c in log.split("\x1e") if c.strip()]
    ref = re.compile(rf"#{n}(?![0-9])") if n is not None else None
    foreign, trapped = [], []
    for entry in commits:
        oid, subj, body = (entry.split("\x00") + ["", ""])[:3]
        text = subj + "\n" + body
        if ref is not None and not ref.search(text):
            foreign.append(oid[:7])
        if trap_hits(text):
            trapped.append(oid[:7])
    return commits, foreign, trapped


def trap_hits(text):
    return [m.group(0) for m in TRAP_RE.finditer(text or "")]


# ── run: PR ────────────────────────────────────────────────────────────────

def wait_for_checks(repo, pr, expect_pr_event, timeout, grace):
    """Accept only a check set that is all passed AND has not changed for `grace` seconds.

    Jobs that depend on other jobs (`needs:`) create their check runs only when
    the earlier job ends; a set that looks complete for one poll can still grow
    (#392 verify r3 #40). The grace window restarts whenever the set changes.
    """
    start = now()
    last_set, stable_since = None, start
    while True:
        rc, out, err = run_cmd([GH, "pr", "checks", str(pr), "--repo", repo, "--json", "name,bucket,event"])
        if rc not in (0, 8):
            if "no checks reported" in (err + out):
                checks = []
            else:
                raise Stop(f"guardrail 2 (CI checks) — gh pr checks exited {rc}: {err.strip()[:200]}")
        else:
            try:
                checks = json.loads(out)
                assert isinstance(checks, list)
            except (ValueError, AssertionError):
                raise Stop("guardrail 2 (CI checks) — unreadable gh output")
        bad = [str(c.get("name")) for c in checks if c.get("bucket") in ("fail", "cancel")]
        if bad:
            raise Stop(f"guardrail 2 (CI checks) — failed: {', '.join(bad)}")
        pending = [str(c.get("name")) for c in checks if c.get("bucket") == "pending"]
        pr_event = any(c.get("event") in ("pull_request", "pull_request_target") for c in checks)
        current = sorted((str(c.get("name")), str(c.get("bucket"))) for c in checks)
        t = now()
        if current != last_set:
            last_set, stable_since = current, t
        if not pending and (t - stable_since) >= grace and (pr_event or not expect_pr_event):
            return f"{len(checks)} check(s) passed" if checks else "no checks reported and no workflow runs on every pull_request"
        if t - start >= timeout:
            if pending:
                what = "pending: " + ", ".join(pending)
            elif expect_pr_event and not pr_event:
                what = "no pull_request check has appeared although a workflow runs on every pull_request"
            else:
                what = "the check set was still changing"
            raise Stop(f"guardrail 2 (CI checks) — still waiting after {int(timeout // 60)} minute(s): {what}")
        time.sleep(20 * SLEEP)


def remote_checks_once(repo, pr):
    """The PR's remote checks read once, without waiting: (failed names, pending names), or (None, None) when unreadable."""
    rc, out, err = run_cmd([GH, "pr", "checks", str(pr), "--repo", repo, "--json", "name,bucket,event"])
    if rc not in (0, 8):
        return ([], []) if "no checks reported" in (err + out) else (None, None)
    try:
        checks = json.loads(out)
        assert isinstance(checks, list)
    except (ValueError, AssertionError):
        return None, None
    return ([str(c.get("name")) for c in checks if c.get("bucket") in ("fail", "cancel")],
            [str(c.get("name")) for c in checks if c.get("bucket") == "pending"])


def ci_guardrail(cwd, sha):
    """Guardrail 2: the local CI gate decides (capability local-ci-gate, #465). Returns "pass" or "remote"; anything
    else stops. The gate runs here, in the process that merges or pushes: a result handed over from an earlier
    step could be another commit's."""
    rc = local_ci(cwd, sha)
    if rc == 0:
        return "pass"
    if rc == 10:
        return "remote"
    raise Stop(f"guardrail 2 (CI) — the local CI gate ended with {CI_GATE_RESULTS.get(rc, 'an unknown code')} (exit {rc}) "
               f"for {sha[:7]}; run scripts/idd-ci-gate.sh run --commit {sha[:7]} to see it")


def check_merge_queue(repo, branch):
    owner, name = repo.split("/", 1)
    q = "query($o:String!,$r:String!,$b:String!){repository(owner:$o,name:$r){mergeQueue(branch:$b){id}}}"
    data = gh_json(["api", "graphql", "-f", f"query={q}", "-f", f"o={owner}", "-f", f"r={name}", "-f", f"b={branch}"],
                   "whether the default branch uses a merge queue")
    if (((data.get("data") or {}).get("repository") or {}).get("mergeQueue")):
        raise Stop(f"{branch} uses a merge queue; the close stage merges only directly — merge it through the queue by hand")


def pr_base(cwd, repo, default, sha):
    """Fetch the default branch and check what a merge onto its tip would do; return the tip.

    Run before the CI wait and again after it, right before the merge: the
    wait can last 15 minutes and other PRs land meanwhile (r4 #1, #32, #38, #45).
    """
    git(cwd, "fetch", "-q", "origin", default)
    tip = git(cwd, "rev-parse", f"origin/{default}")
    if git(cwd, "merge-base", tip, sha) != tip:
        raise Stop(f"the branch is behind {default} (new commits landed during the run) — the merged tree was never "
                   "reviewed; update the branch and verify again")
    # Both trees: a change can add publishing to a script a push workflow already runs (r6 #13).
    published = releases_on_push(cwd, tip, default) + releases_on_push(cwd, sha, default)
    if published:
        raise Stop(f"a workflow publishes on push to {default} ({', '.join(published)}): merging is a release — run with --review")
    changed_ci = touches_ci(cwd, tip, sha)
    if changed_ci:
        raise Stop(f"the change edits CI ({', '.join(changed_ci[:3])}) — workflow changes are merged by a person")
    check_merge_queue(repo, default)
    return tip


def write_result(cwd, n, result):
    os.makedirs(state_dir(cwd), exist_ok=True)
    with open(result_path(cwd, n), "w", encoding="utf-8") as fh:
        json.dump(result, fh, ensure_ascii=False)


def run_pr(st, cwd, repo, n, timeout, grace, partial):
    default = st["default"]
    prs = gh_json(["pr", "list", "--repo", repo, "--head", st["branch"], "--state", "open",
                   "--json", "number,headRefName,baseRefName,headRefOid,title,url,isCrossRepository"], "the open PRs")
    prs = [p for p in prs if p.get("headRefName") == st["branch"] and p.get("baseRefName") == default
           and p.get("isCrossRepository") is False]
    if len(prs) != 1:
        raise Stop(f"expected exactly one open PR from {st['branch']} (this repo) into {default}, found {len(prs)}")
    pr = prs[0]
    sha = pr.get("headRefOid") or ""
    local = git(cwd, "rev-parse", "HEAD")
    if local != sha:
        raise Stop(f"the PR head {sha[:7]} is not this run's commit {local[:7]} — not merging")
    base = pr_base(cwd, repo, default, sha)
    since = parse_iso(st["created_at"])

    rc, gate = judge_report(repo, n, sha, base, since)
    gate_stop(rc, gate)

    # Local CI decides; remote checks are waited for only in remote mode. With a local pass they are read once,
    # right before the merge, and reported (capability local-ci-gate: they do not block the merge decision).
    local = ci_guardrail(cwd, sha)
    if local == "remote":
        ci = wait_for_checks(repo, pr["number"], expects_pr_checks(cwd, sha, default), timeout, grace)
    else:
        ci = "local CI passed"

    refs = gh_json(["pr", "view", str(pr["number"]), "--repo", repo, "--json", "closingIssuesReferences"],
                   "the PR's closing references").get("closingIssuesReferences") or []
    if refs:
        raise Stop("guardrail 3 (auto-close trap) — the PR body would close: "
                   + ", ".join(str(r.get("url", "?")) for r in refs))
    # The PR's commits, read from local git over the exact range (local HEAD == PR head was checked
    # above): `gh pr view --json commits` is capped and would leave later commits unscanned (r3 #2).
    _, foreign, hits = scan_commits(cwd, base, sha, n)
    if foreign:
        # Only this run's commits go into the squash, as on the direct-commit path (r5 #23)
        raise Stop(f"commit(s) {', '.join(foreign)} on the branch do not reference #{n} — they are not this run's; not merging")
    if hits:
        raise Stop("guardrail 3 (auto-close trap) — close keyword next to an issue reference in commit(s): " + ", ".join(hits))

    subject = f"{pr.get('title') or ''} (#{pr['number']})"
    body = f"Refs #{n}\n\nMerged by /idd-all after a clean verify: {gate.get('verify_url')}\n"
    if trap_hits(subject + "\n" + body):
        raise Stop(f"guardrail 4 (squash message) — close keyword next to an issue reference: {subject[:120]}")

    # The CI wait can take minutes: everything that can change meanwhile is read again right before the merge.
    base = pr_base(cwd, repo, default, sha)
    rc, gate = judge_report(repo, n, sha, base, since)
    gate_stop(rc, gate)
    me = session_login()
    comments = issue_comments(repo, n)
    check_others(me, since, comments, issue_meta(repo, n))
    check_pr_people(repo, pr["number"], me)
    remote = {}
    if local == "pass":
        failed, pending = remote_checks_once(repo, pr["number"])
        remote = {"remote_ci_failed": "not readable" if failed is None else failed,
                  "remote_ci_pending": [] if pending is None else pending}

    partial.update({"pr": pr["number"], "pr_url": pr.get("url"), "verified_sha": sha, "merge_attempted": True})
    # Written before the merge call: if this process dies after GitHub merged, the
    # result still says a merge may have happened (r4 #34).
    write_result(cwd, n, dict(partial, status="stopped",
                              reason=f"interrupted after the merge call started — PR #{pr['number']} may be merged; check it",
                              interaction=st.get("interaction", "unknown")))
    rc, out, err = run_cmd([GH, "pr", "merge", str(pr["number"]), "--repo", repo, "--squash",
                            "--subject", subject, "--body", body, "--match-head-commit", sha])
    if rc != 0:
        try:
            after = gh_json(["pr", "view", str(pr["number"]), "--repo", repo, "--json", "state"], "the PR").get("state")
        except Stop:
            after = "unreadable"
        if after != "MERGED":
            partial["merge_attempted"] = "refused" if after == "OPEN" else True
            raise Stop(f"merge — gh pr merge failed (PR #{pr['number']} reads {after}): {err.strip()[:300]}"
                       + ("" if after == "OPEN" else " — it may have merged; check the PR"))
    view, merge_sha = {}, ""
    for attempt in range(4):
        try:
            view = gh_json(["pr", "view", str(pr["number"]), "--repo", repo, "--json", "state,mergeCommit,mergedAt"],
                           "the PR after merging")
        except Stop:
            view = {}
        merge_sha = ((view.get("mergeCommit") or {}).get("oid")) or ""
        if view.get("state") == "MERGED" and merge_sha:
            break
        time.sleep(5 * SLEEP)
    else:
        state = view.get("state") or "unreadable"
        if state == "OPEN":
            partial["merge_attempted"] = "refused"
            rc2, _, err2 = run_cmd([GH, "pr", "merge", str(pr["number"]), "--repo", repo, "--disable-auto"])
            note = "auto-merge disabled" if rc2 == 0 else f"could not disable auto-merge: {err2.strip()[:120]}"
            raise Stop(f"merge — PR #{pr['number']} is still OPEN after gh pr merge ({note}); not closing — check the PR")
        raise Stop(f"merge — gh pr merge succeeded but PR #{pr['number']} reads {state} without a merge commit; "
                   "it may have merged — check the PR before running /idd-close")
    run_cmd([GIT, "-C", cwd, "fetch", "-q", "origin"])
    return {"status": "merged", "pr": pr["number"], "pr_url": pr.get("url"), "merge_sha": merge_sha,
            "merged_at": view.get("mergedAt"),
            "verified_sha": sha, "reviewed_base": base, "verify_url": gate.get("verify_url"), "ci": ci,
            "local_ci": local, "low_in_scope": gate.get("low_in_scope") or 0, "default": default, **remote}


# ── run: direct-commit ─────────────────────────────────────────────────────

def run_direct(st, cwd, repo, n, partial):
    default = st["default"]
    cur = git(cwd, "branch", "--show-current")
    if cur != default:
        raise Stop(f"the fix is on '{cur}', not on the default branch '{default}' — not pushing, not closing")
    git(cwd, "fetch", "-q", "origin", default)
    head = git(cwd, "rev-parse", "HEAD")
    base = git(cwd, "rev-parse", f"origin/{default}")
    if git(cwd, "merge-base", base, head) != base:
        raise Stop(f"origin/{default} has commits this clone does not — not pushing (no automatic rebase)")
    published = releases_on_push(cwd, base, default) + releases_on_push(cwd, head, default)
    if published:
        raise Stop(f"a workflow publishes on push to {default} ({', '.join(published)}): pushing is a release — run with --review")
    changed_ci = touches_ci(cwd, base, head)
    if changed_ci:
        raise Stop(f"the change edits CI ({', '.join(changed_ci[:3])}) — workflow changes are pushed by a person")
    rc, gate = judge_report(repo, n, head, base, parse_iso(st["created_at"]))
    gate_stop(rc, gate)
    # Local CI before the push. In remote mode there is no remote result for commits that were never pushed,
    # so the push proceeds and remote CI runs after it (as before #465).
    local = ci_guardrail(cwd, head)
    # Everything below names `head`, never HEAD: another session can move HEAD
    # or switch the branch while the checks run (#392 verify r2 #1).
    commits, foreign, trapped = scan_commits(cwd, base, head, n)
    if not commits:
        raise Stop(f"nothing to push: {head[:7]} is already on origin/{default}")
    if foreign:
        raise Stop(f"commit(s) {', '.join(foreign)} do not reference #{n} — they are not this run's, not pushing")
    if trapped:
        raise Stop(f"commit(s) {', '.join(trapped)} carry a close keyword next to an issue reference — "
                   "GitHub would close the issue without /idd-close; not pushing")
    if git(cwd, "rev-parse", "HEAD") != head or git(cwd, "branch", "--show-current") != default:
        raise Stop("HEAD or the branch changed while the checks ran — not pushing")
    partial.update({"verified_sha": head, "push_attempted": True, "push_from": base, "push_to": head})
    write_result(cwd, n, dict(partial, status="stopped",
                              reason=f"interrupted after the push started — {default} may already be at {head[:7]}; check it",
                              interaction=st.get("interaction", "unknown")))
    rc, out, err = run_cmd([GIT, "-C", cwd, "push", "origin", f"{head}:refs/heads/{default}"])
    if rc != 0:
        partial["push_attempted"] = "refused"
        raise Stop(f"push rejected (no automatic rebase) — not closing: {err.strip()[:300]}")
    # Confirm on GitHub that the default branch now points at the verified commit (r3 #9).
    landed = (gh_json(["api", f"repos/{repo}/branches/{default}"], f"{default} on GitHub").get("commit") or {}).get("sha")
    if landed != head:
        raise Stop(f"pushed, but GitHub's {default} is at {str(landed)[:7]}, not {head[:7]} — check the remote before closing")
    return {"status": "pushed", "push_from": base, "push_to": head, "count": len(commits),
            "verified_sha": head, "reviewed_base": base, "verify_url": gate.get("verify_url"), "default": default,
            "local_ci": local, "low_in_scope": gate.get("low_in_scope") or 0}


def cmd_run(argv):
    a = parse(argv, {"--cwd": "value", "--repo": "value", "--issue": "value",
                     "--ci-timeout": "value", "--ci-grace": "value"})
    if a is None or not common_ok(a):
        return usage("run needs --cwd <dir> --repo owner/repo --issue <digits>")
    try:
        timeout = float(a.get("--ci-timeout", 900))
        grace = float(a.get("--ci-grace", 90))
        assert math.isfinite(timeout) and math.isfinite(grace) and timeout >= 0 and grace >= 0
    except (ValueError, AssertionError):
        return usage("--ci-timeout and --ci-grace are non-negative seconds")
    cwd, repo, n = os.path.realpath(a["--cwd"]), a["--repo"], a["--issue"]
    try:
        if os.path.exists(result_path(cwd, n)):
            os.unlink(result_path(cwd, n))   # never let an earlier run's result stand for this one
    except (OSError, Stop):
        pass
    st, partial = {}, {}
    try:
        st = load_state(cwd, repo, n)
        if st.get("review"):
            raise Stop("--review: the run stays at verified (no merge, no close)")
        if st.get("in_chain"):
            raise Stop("--in-chain: /idd-all-chain owns the cluster PR (no merge, no close)")
        if st.get("path") != st.get("requested_path"):
            raise Stop(f"the run was downgraded from {st.get('requested_path')} to {st.get('path')} "
                       "(ralph-loop missing) — stays at verified; a person decides where the change goes")
        perm = gh_json(["repo", "view", repo, "--json", "viewerPermission"], "the repo permission").get("viewerPermission")
        if perm not in WRITE_PERMS:
            raise Stop(f"this account has {perm or 'no'} permission on {repo}; the close stage runs only where it can write")
        check_origin(cwd, repo)
        me = session_login()
        since = parse_iso(st["created_at"])
        comments = issue_comments(repo, n)
        meta = issue_meta(repo, n)
        issue = issue_view(repo, n)
        check_meeting(comments)
        check_issue_authors(repo, meta)
        check_others(me, since, comments, meta)
        corrections = check_intent(repo, n, st, comments, issue)
        if st.get("path") == "PR":
            result = run_pr(st, cwd, repo, n, timeout, grace, partial)
        elif st.get("path") == "direct-commit":
            result = run_direct(st, cwd, repo, n, partial)
        else:
            raise Stop("the run state has no path")
        result["done_at"] = iso(now())
        result["proposed_corrections"] = corrections
        code = 0
    except Stop as exc:
        result, code = dict(partial, status="stopped", reason=str(exc)), 3
    except Exception as exc:  # fail closed: a crash is a stop, with whatever was already done
        result, code = dict(partial, status="stopped", reason=f"internal error: {exc.__class__.__name__}: {exc}"), 3
    result["interaction"] = st.get("interaction", "unknown")
    try:
        write_result(cwd, n, result)
    except (OSError, Stop) as exc:
        result["result_file"] = f"not written: {exc}"
    print(json.dumps(result, ensure_ascii=False))
    return code


# ── confirm-close ──────────────────────────────────────────────────────────

def cmd_confirm(argv):
    a = parse(argv, {"--cwd": "value", "--repo": "value", "--issue": "value"})
    if a is None or not common_ok(a):
        return usage("confirm-close needs --cwd --repo --issue")
    cwd, repo, n = a["--cwd"], a["--repo"], a["--issue"]
    try:
        try:
            with open(result_path(cwd, n), encoding="utf-8") as fh:
                res = json.load(fh)
        except (OSError, ValueError):
            raise Stop("no close-stage result for this issue")
        if res.get("status") not in ("merged", "pushed") or not res.get("done_at"):
            raise Stop("the close stage did not merge or push, so there is nothing to confirm")
        # GitHub's own clock where GitHub recorded the event (the merge); the local clock, with slack, for a push.
        since = parse_iso(res["merged_at"]) - 5 if res.get("merged_at") else parse_iso(res["done_at"]) - 300
        state = gh_json(["issue", "view", n, "--repo", repo, "--json", "state"], "the issue state").get("state")
        if state != "CLOSED":
            raise Stop(f"the issue is {state}")
        me = session_login()
        comments = gh_paginated(f"repos/{repo}/issues/{n}/comments",
                                "[.[] | {html_url, login: .user.login, created_at, body}]", f"the comments of #{n}")
        # Positive confirmation, not the audit classifier: that one may only veto
        # (check-closed-without-summary.sh --issue, "MAY VETO. IT MAY NOT PERMIT"),
        # and counts prose mentions. /idd-close writes the canonical heading.
        ok = [c for c in comments if c.get("login") == me
              and (c.get("body") or "").lstrip("\ufeff").lstrip().split("\n", 1)[0].strip() == "## Closing Summary"
              and parse_iso(c.get("created_at", "1970-01-01T00:00:00Z")) >= since]
        if not ok:
            raise Stop("no '## Closing Summary' comment by this account after the merge or push")
        print(json.dumps({"status": "closed", "summary_url": ok[-1].get("html_url")}, ensure_ascii=False))
        return 0
    except Stop as exc:
        print(json.dumps({"status": "not_confirmed", "reason": str(exc)}, ensure_ascii=False))
        return 3
    except Exception as exc:
        print(json.dumps({"status": "not_confirmed", "reason": f"internal error: {exc.__class__.__name__}: {exc}"}))
        return 3


# ── pr-check: may the run open its pull request without asking? ────────────
# The SKILL's 權限 section: opening the pull request is reversible (it can be closed and edited)
# unless it notifies a person or would close the issue on merge. The privacy self-review of the
# text is the model's; this check covers what a program can decide.

CODEOWNERS_PATHS = (".github/CODEOWNERS", "CODEOWNERS", "docs/CODEOWNERS")
# An @ that starts a token: not part of an e-mail address, a version pin (pkg@1.2) or a path.
MENTION_RE = re.compile(r"(?<![A-Za-z0-9_.+/-])@[A-Za-z0-9][A-Za-z0-9-]*")
BRANCH_RE = re.compile(r"^[A-Za-z0-9._/][A-Za-z0-9._/-]*$")


def pr_check(cwd, default, title, body):
    """The reason the run must ask before opening the pull request, or None."""
    text = title + "\n" + body
    mention = MENTION_RE.search(text)
    if mention:
        return f"the title or the body mentions an account ({mention.group(0)[:40]}): a notification cannot be recalled"
    hits = trap_hits(text)
    if hits:
        return "a close keyword next to an issue reference in the title or the body: " + ", ".join(h[:40] for h in hits[:3])
    ref = f"refs/remotes/origin/{default}"
    rc, out, err = run_cmd([GIT, "-C", cwd, "rev-parse", "--verify", "--quiet", ref + "^{commit}"])
    if rc != 0:
        return f"could not read origin/{default} in the local clone — cannot tell whether a CODEOWNERS file exists"
    rc, out, err = run_cmd([GIT, "-C", cwd, "ls-tree", "-z", "--name-only", ref, "--"] + list(CODEOWNERS_PATHS))
    if rc != 0:
        return f"could not list origin/{default} — cannot tell whether a CODEOWNERS file exists"
    found = [path for path in out.split("\0") if path]
    if found:
        return f"the default branch has {found[0]}: opening the pull request would request a review from a person"
    return None


def cmd_pr_check(argv):
    a = parse(argv, {"--cwd": "value", "--default": "value", "--title-file": "value", "--body-file": "value"})
    if a is None or not (a.get("--cwd") and os.path.isdir(a["--cwd"])) or not BRANCH_RE.match(a.get("--default", "")) \
            or not all(a.get(k) and os.path.isfile(a[k]) for k in ("--title-file", "--body-file")):
        return usage("pr-check needs --cwd --default (a branch name) --title-file --body-file (existing files)")
    try:
        with open(a["--title-file"], encoding="utf-8") as fh:
            title = fh.read()
        with open(a["--body-file"], encoding="utf-8") as fh:
            body = fh.read()
        reason = pr_check(a["--cwd"], a["--default"], title, body)
    except Exception as exc:  # fail closed: a surprise means ask, never open
        reason = f"internal error: {exc.__class__.__name__}: {exc}"
    if reason:
        print(json.dumps({"status": "ask", "reason": reason}, ensure_ascii=False))
        return 3
    print(json.dumps({"status": "open"}))
    return 0


def main(argv):
    if not argv:
        return usage("subcommand required: init | reset | gate | pr-check | run | confirm-close")
    sub, rest = argv[0], argv[1:]
    handlers = {"init": cmd_init, "reset": cmd_reset, "gate": cmd_gate, "pr-check": cmd_pr_check, "run": cmd_run,
                "confirm-close": cmd_confirm}
    if sub not in handlers:
        return usage(f"unknown subcommand '{sub}'")
    return handlers[sub](rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
