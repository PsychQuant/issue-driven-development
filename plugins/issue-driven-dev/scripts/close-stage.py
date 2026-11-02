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
        Read the newest '## Verify: #N' report posted by the account running
        this session and judge it with verify-gate.py --expect-sha [--expect-base].
        Prints the gate JSON plus comment_id / verify_url.
        Exit 0 clean, 1 not clean, 2 unparseable (including: no such report,
        any error), 64 usage.
  run   --cwd C --repo O/R --issue N [--ci-timeout S] [--ci-grace S]
        Phase 5c: every guardrail, then the squash merge (PR) or the push
        (direct-commit). Prints one JSON line and writes it to
        C/.claude/.idd/state/idd-all-result-N.json.
        Exit 0 merged/pushed, 3 stopped (reason in the JSON, including any
        error), 64 usage.
  confirm-close --cwd C --repo O/R --issue N
        After /idd-close: the issue is CLOSED and a comment by this account
        that opens with the canonical '## Closing Summary' heading was posted
        after the merge or push recorded in the result file. Exit 0 confirmed,
        3 not confirmed, 64 usage.

Fail closed throughout: anything that cannot be read or checked stops the
stage. Nothing here asks a person; a stop is reported, not negotiated.

Test seams (honoured only when IDD_CLOSE_STAGE_TEST=1): IDD_GH / IDD_GIT name
the gh and git executables; IDD_SLEEP=0 makes the wait loops not sleep.
"""

import calendar
import json
import math
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TEST = os.environ.get("IDD_CLOSE_STAGE_TEST") == "1"
GH = os.environ.get("IDD_GH", "gh") if TEST else "gh"
GIT = os.environ.get("IDD_GIT", "git") if TEST else "git"
SLEEP = 0 if (TEST and os.environ.get("IDD_SLEEP") == "0") else 1
WRITE_PERMS = {"WRITE", "MAINTAIN", "ADMIN"}
WRITE_ROLES = {"admin", "maintain", "write"}
TRUSTED = {"OWNER", "MEMBER", "COLLABORATOR"}
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
# Steps that publish when a workflow runs on a push to the default branch. A
# merge into such a branch is a release, not the reversible action this stage
# assumes (#392 verify r2 #8). Heuristic, and deliberately one-sided: a hit stops.
RELEASE_MARKERS = ("gh release", "action-gh-release", "create-release", "npm publish", "semantic-release",
                   "goreleaser", "gh-action-pypi-publish", "twine upload", "cargo publish", "docker push",
                   "vsce publish", "release-please", "changesets/action")


class Stop(Exception):
    """A guardrail did not pass; the message is the reason, reported verbatim."""


def now():
    return time.time()


def iso(ts):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ts))


def parse_iso(text):
    return calendar.timegm(time.strptime(text, "%Y-%m-%dT%H:%M:%SZ"))


def run_cmd(cmd, cwd=None):
    try:
        proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    except OSError as exc:
        raise Stop(f"could not run {cmd[0]}: {exc.strerror or exc}")
    return proc.returncode, proc.stdout, proc.stderr


def gh_json(args, what):
    rc, out, err = run_cmd([GH] + args)
    if rc != 0:
        raise Stop(f"could not read {what}: {err.strip()[:300] or 'gh exited ' + str(rc)}")
    try:
        return json.loads(out)
    except ValueError:
        raise Stop(f"could not read {what}: gh did not return JSON")


def gh_paginated(path, jq, what):
    rc, out, err = run_cmd([GH, "api", path, "--paginate", "--jq", jq])
    if rc != 0:
        raise Stop(f"could not read {what}: {err.strip()[:300] or 'gh exited ' + str(rc)}")
    items, dec, i = [], json.JSONDecoder(), 0
    out = out.strip()
    try:
        while i < len(out):
            page, j = dec.raw_decode(out, i)
            if not isinstance(page, list):
                raise ValueError
            items.extend(page)
            i = j
            while i < len(out) and out[i].isspace():
                i += 1
    except ValueError:
        raise Stop(f"could not read {what}: gh did not return a JSON list")
    return items


def git(cwd, *args):
    rc, out, err = run_cmd([GIT, "-C", cwd] + list(args))
    if rc != 0:
        raise Stop(f"git {args[0]} failed: {err.strip()[:300]}")
    return out.strip()


def state_dir(cwd):
    return os.path.join(cwd, ".claude", ".idd", "state")


def state_path(cwd, n):
    return os.path.join(state_dir(cwd), f"idd-all-run-{n}.json")


def result_path(cwd, n):
    return os.path.join(state_dir(cwd), f"idd-all-result-{n}.json")


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
    cwd = a["--cwd"]
    state = {
        "repo": a["--repo"], "issue": int(a["--issue"]), "path": a["--path"],
        "requested_path": a["--requested-path"], "interaction": a["--interaction"],
        "branch": a["--branch"], "default": a["--default"],
        "review": a["--review"] == "yes", "in_chain": a["--in-chain"] == "yes",
        "created_at": iso(now()),
    }
    os.makedirs(state_dir(cwd), exist_ok=True)
    with open(state_path(cwd, a["--issue"]), "w", encoding="utf-8") as fh:
        json.dump(state, fh)
    if os.path.exists(result_path(cwd, a["--issue"])):
        os.unlink(result_path(cwd, a["--issue"]))
    print(state_path(cwd, a["--issue"]))
    return 0


# ── gate ───────────────────────────────────────────────────────────────────

def session_login():
    rc, out, err = run_cmd([GH, "api", "user", "--jq", ".login"])
    login = out.strip()
    if rc != 0 or not login:
        raise Stop("could not read the account running this session (gh api user)")
    return login


def latest_report(repo, n, me):
    """Newest '## Verify: #N' comment written by the account running this session.

    Only that account: `author_association` MEMBER / COLLABORATOR also covers
    people with read access, and this report decides a merge (#392 verify r1 #26).
    """
    comments = gh_paginated(f"repos/{repo}/issues/{n}/comments",
                            "[.[] | {id, html_url, login: .user.login, body}]",
                            f"the comments of #{n}")
    head = re.compile(rf"^## Verify: #{n}(?![0-9])")
    mine = [c for c in comments if c.get("login") == me and head.match(c.get("body") or "")]
    return mine[-1] if mine else None


def judge_report(repo, n, sha, base):
    me = session_login()
    report = latest_report(repo, n, me)
    if report is None:
        return 2, {"status": "unparseable", "reason": f"no '## Verify: #{n}' report by the account running this session"}
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as fh:
        fh.write(report.get("body") or "")
        tmp = fh.name
    try:
        cmd = [sys.executable, "-I", os.path.join(HERE, "verify-gate.py"), "--comment-file", tmp, "--expect-sha", sha]
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
    return (rc if rc in (0, 1, 2) else 2), result


def cmd_gate(argv):
    a = parse(argv, {"--cwd": "value", "--repo": "value", "--issue": "value", "--sha": "value", "--base": "value"})
    if a is None or not common_ok(a) or not SHA_RE.match(a.get("--sha", "")) \
            or ("--base" in a and not SHA_RE.match(a["--base"])):
        return usage("gate needs --cwd --repo --issue and --sha (40 lowercase hex digits), optionally --base")
    try:
        rc, result = judge_report(a["--repo"], a["--issue"], a["--sha"], a.get("--base"))
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


def check_meeting(repo, n):
    comments = gh_paginated(f"repos/{repo}/issues/{n}/comments",
                            "[.[] | {assoc: .author_association, body}]", f"the comments of #{n}")
    diag = [c.get("body") or "" for c in comments
            if c.get("assoc") in TRUSTED and re.match(r"^## Diagnosis[ \t]*(\r?\n|$)", c.get("body") or "")]
    body = diag[-1] if diag else ""
    rc, out, err = run_cmd(["bash", "-c", '. "$1/lib/actionability.sh" && idd_diagnosis_type "$2"', "_", HERE, body])
    if rc != 0:
        raise Stop("could not re-read the Diagnosis type")
    if out.strip() == "meeting":
        raise Stop("the latest trusted Diagnosis records type meeting — meeting issues are never merged or pushed")


def can_write(repo, login):
    data = gh_json(["api", f"repos/{repo}/collaborators/{login}/permission"], f"the permission of {login}")
    return (data.get("permission") in ("admin", "write")) or (data.get("role_name") in WRITE_ROLES)


def check_issue_authors(repo, n):
    """The issue's author and the last editor of its body must be able to write.

    The issue text is what implement builds and verify checks against; on a
    public repo anyone can open one, and an author can edit it after a
    maintainer read it. Without a person merging, that text must come from
    someone who could have pushed the change anyway (#392 verify r2 #4).
    """
    owner, name = repo.split("/", 1)
    q = ("query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n)"
         "{author{login} editor{login}}}}")
    data = gh_json(["api", "graphql", "-f", f"query={q}", "-F", f"o={owner}", "-F", f"r={name}", "-F", f"n={n}"],
                   "the issue's author and editor")
    issue = ((data.get("data") or {}).get("repository") or {}).get("issue") or {}
    author = (issue.get("author") or {}).get("login")
    editor = (issue.get("editor") or {}).get("login")
    if not author:
        raise Stop("could not read the issue's author — not merging")
    for role, login in (("author", author), ("last editor", editor)):
        if login and not can_write(repo, login):
            raise Stop(f"the issue's {role} {login} has no write access — a person reviews and merges this one")


def check_origin(cwd, repo):
    url = git(cwd, "remote", "get-url", "origin")
    m = re.search(r"[:/]([^/:]+/[^/]+?)(?:\.git)?/?$", url)
    if not m or m.group(1).lower() != repo.lower():
        raise Stop(f"the clone's origin ({url}) is not {repo} — not pushing or merging")


def workflow_files(cwd, ref):
    rc, out, err = run_cmd([GIT, "-C", cwd, "ls-tree", "-r", "--name-only", ref, "--", ".github/workflows"])
    files = []
    for path in out.split():
        rc, text, err = run_cmd([GIT, "-C", cwd, "show", f"{ref}:{path}"])
        if rc == 0:
            files.append((path, text))
    return files


def releases_on_push(cwd, ref):
    hits = []
    for path, text in workflow_files(cwd, ref):
        if re.search(r"(^|\W)push\s*:|on:\s*\[?[^\]\n]*\bpush\b", text) and any(m in text for m in RELEASE_MARKERS):
            hits.append(path)
    return hits


def expects_pr_checks(cwd, ref):
    """A workflow that runs on every pull_request (no path filter) will report a check."""
    for path, text in workflow_files(cwd, ref):
        if "pull_request" in text and "paths:" not in text and "paths-ignore:" not in text:
            return True
    return False


def trap_hits(text):
    return [m.group(0) for m in TRAP_RE.finditer(text or "")]


# ── run: PR ────────────────────────────────────────────────────────────────

def wait_for_checks(repo, pr, expect_pr_event, timeout, grace):
    start = now()
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
        elapsed = now() - start
        if not pending and elapsed >= grace and (pr_event or not expect_pr_event):
            return f"{len(checks)} check(s) passed" if checks else "no checks reported and no workflow runs on every pull_request"
        if elapsed >= timeout:
            if pending:
                what = "pending: " + ", ".join(pending)
            elif expect_pr_event:
                what = "no pull_request check has appeared although a workflow runs on every pull_request"
            else:
                what = "checks still settling"
            raise Stop(f"guardrail 2 (CI checks) — still waiting after {int(timeout // 60)} minute(s): {what}")
        time.sleep(20 * SLEEP)


def check_merge_queue(repo, branch):
    owner, name = repo.split("/", 1)
    q = "query($o:String!,$r:String!,$b:String!){repository(owner:$o,name:$r){mergeQueue(branch:$b){id}}}"
    data = gh_json(["api", "graphql", "-f", f"query={q}", "-F", f"o={owner}", "-F", f"r={name}", "-F", f"b={branch}"],
                   "whether the default branch uses a merge queue")
    if (((data.get("data") or {}).get("repository") or {}).get("mergeQueue")):
        raise Stop(f"{branch} uses a merge queue; the close stage merges only directly — merge it through the queue by hand")


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
    git(cwd, "fetch", "-q", "origin", default)
    base = git(cwd, "merge-base", f"origin/{default}", sha)
    published = releases_on_push(cwd, sha)
    if published:
        raise Stop(f"a workflow publishes on push ({', '.join(published)}): merging is a release — run with --review")
    check_merge_queue(repo, default)

    rc, gate = judge_report(repo, n, sha, base)
    if rc != 0:
        raise Stop(f"guardrail 1 (verify gate) — {gate.get('status')}: {gate.get('reason')}")

    ci = wait_for_checks(repo, pr["number"], expects_pr_checks(cwd, sha), timeout, grace)

    refs = gh_json(["pr", "view", str(pr["number"]), "--repo", repo, "--json", "closingIssuesReferences"],
                   "the PR's closing references").get("closingIssuesReferences") or []
    if refs:
        raise Stop("guardrail 3 (auto-close trap) — the PR body would close: "
                   + ", ".join(str(r.get("url", "?")) for r in refs))
    commits = gh_json(["pr", "view", str(pr["number"]), "--repo", repo, "--json", "commits"],
                      "the PR's commits").get("commits") or []
    hits = [str(c.get("oid", "?"))[:7] for c in commits
            if trap_hits((c.get("messageHeadline") or "") + "\n" + (c.get("messageBody") or ""))]
    if hits:
        raise Stop("guardrail 3 (auto-close trap) — close keyword next to an issue reference in commit(s): " + ", ".join(hits))

    subject = f"{pr.get('title') or ''} (#{pr['number']})"
    body = f"Refs #{n}\n\nMerged by /idd-all after a clean verify: {gate.get('verify_url')}\n"
    if trap_hits(subject + "\n" + body):
        raise Stop(f"guardrail 4 (squash message) — close keyword next to an issue reference: {subject[:120]}")

    # The CI wait can take minutes: judge the report again right before the merge.
    rc, gate = judge_report(repo, n, sha, base)
    if rc != 0:
        raise Stop(f"guardrail 1 (verify gate, re-checked after CI) — {gate.get('status')}: {gate.get('reason')}")

    partial.update({"pr": pr["number"], "pr_url": pr.get("url"), "verified_sha": sha, "merge_attempted": True})
    rc, out, err = run_cmd([GH, "pr", "merge", str(pr["number"]), "--repo", repo, "--squash",
                            "--subject", subject, "--body", body, "--match-head-commit", sha])
    if rc != 0:
        partial["merge_attempted"] = "refused"
        raise Stop(f"merge — gh pr merge failed, PR #{pr['number']} is still open: {err.strip()[:300]}")
    view, merge_sha = {}, ""
    for attempt in range(4):
        try:
            view = gh_json(["pr", "view", str(pr["number"]), "--repo", repo, "--json", "state,mergeCommit"],
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
            rc2, _, err2 = run_cmd([GH, "pr", "merge", str(pr["number"]), "--repo", repo, "--disable-auto"])
            note = "auto-merge disabled" if rc2 == 0 else f"could not disable auto-merge: {err2.strip()[:120]}"
            raise Stop(f"merge — PR #{pr['number']} is still OPEN after gh pr merge ({note}); not closing — check the PR")
        raise Stop(f"merge — gh pr merge succeeded but PR #{pr['number']} reads {state} without a merge commit; "
                   "it may have merged — check the PR before running /idd-close")
    run_cmd([GIT, "-C", cwd, "fetch", "-q", "origin"])
    return {"status": "merged", "pr": pr["number"], "pr_url": pr.get("url"), "merge_sha": merge_sha,
            "verified_sha": sha, "reviewed_base": base, "verify_url": gate.get("verify_url"), "ci": ci,
            "default": default}


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
    published = releases_on_push(cwd, head)
    if published:
        raise Stop(f"a workflow publishes on push ({', '.join(published)}): pushing is a release — run with --review")
    rc, gate = judge_report(repo, n, head, base)
    if rc != 0:
        raise Stop(f"guardrail 1 (verify gate) — {gate.get('status')}: {gate.get('reason')}")
    # Everything below names `head`, never HEAD: another session can move HEAD
    # or switch the branch while the checks run (#392 verify r2 #1).
    log = git(cwd, "log", "--format=%H%x00%s%x00%b%x1e", f"{base}..{head}")
    commits = [c.strip("\n") for c in log.split("\x1e") if c.strip()]
    if not commits:
        raise Stop(f"nothing to push: {head[:7]} is already on origin/{default}")
    ref = re.compile(rf"#{n}(?![0-9])")
    foreign, trapped = [], []
    for entry in commits:
        oid, subj, body = (entry.split("\x00") + ["", ""])[:3]
        text = subj + "\n" + body
        if not ref.search(text):
            foreign.append(oid[:7])
        if trap_hits(text):
            trapped.append(oid[:7])
    if foreign:
        raise Stop(f"commit(s) {', '.join(foreign)} do not reference #{n} — they are not this run's, not pushing")
    if trapped:
        raise Stop(f"commit(s) {', '.join(trapped)} carry a close keyword next to an issue reference — "
                   "GitHub would close the issue without /idd-close; not pushing")
    if git(cwd, "rev-parse", "HEAD") != head or git(cwd, "branch", "--show-current") != default:
        raise Stop("HEAD or the branch changed while the checks ran — not pushing")
    partial.update({"verified_sha": head, "push_attempted": True})
    rc, out, err = run_cmd([GIT, "-C", cwd, "push", "origin", f"{head}:refs/heads/{default}"])
    if rc != 0:
        partial["push_attempted"] = "refused"
        raise Stop(f"push rejected (no automatic rebase) — not closing: {err.strip()[:300]}")
    return {"status": "pushed", "push_from": base, "push_to": head, "count": len(commits),
            "verified_sha": head, "reviewed_base": base, "verify_url": gate.get("verify_url"), "default": default}


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
    cwd, repo, n = a["--cwd"], a["--repo"], a["--issue"]
    try:
        if os.path.exists(result_path(cwd, n)):
            os.unlink(result_path(cwd, n))   # never let an earlier run's result stand for this one
    except OSError:
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
        check_meeting(repo, n)
        check_issue_authors(repo, n)
        if st.get("path") == "PR":
            result = run_pr(st, cwd, repo, n, timeout, grace, partial)
        elif st.get("path") == "direct-commit":
            result = run_direct(st, cwd, repo, n, partial)
        else:
            raise Stop("the run state has no path")
        result["done_at"] = iso(now())
        code = 0
    except Stop as exc:
        result, code = dict(partial, status="stopped", reason=str(exc)), 3
    except Exception as exc:  # fail closed: a crash is a stop, with whatever was already done
        result, code = dict(partial, status="stopped", reason=f"internal error: {exc.__class__.__name__}: {exc}"), 3
    result["interaction"] = st.get("interaction", "unknown")
    try:
        os.makedirs(state_dir(cwd), exist_ok=True)
        with open(result_path(cwd, n), "w", encoding="utf-8") as fh:
            json.dump(result, fh, ensure_ascii=False)
    except OSError as exc:
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
        since = parse_iso(res["done_at"]) - 5
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
              and (c.get("body") or "").split("\n", 1)[0].strip() == "## Closing Summary"
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


def main(argv):
    if not argv:
        return usage("subcommand required: init | gate | run | confirm-close")
    sub, rest = argv[0], argv[1:]
    handlers = {"init": cmd_init, "gate": cmd_gate, "run": cmd_run, "confirm-close": cmd_confirm}
    if sub not in handlers:
        return usage(f"unknown subcommand '{sub}'")
    return handlers[sub](rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
