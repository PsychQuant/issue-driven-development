"""ghread.py — read GitHub and git for the close stage, failing closed (#392).

Split out of close-stage.py (r5: the helper passed 800 lines). Everything here
raises Stop on anything it cannot read; nothing here decides a merge.

Test seams (honoured only when IDD_CLOSE_STAGE_TEST=1): IDD_GH / IDD_GIT name
the gh and git executables; IDD_CI_GATE names the local CI gate; IDD_SLEEP=0
makes the wait loops not sleep.
"""

import calendar
import json
import os
import re
import subprocess
import time

import rendered

TEST = os.environ.get("IDD_CLOSE_STAGE_TEST") == "1"
GH = os.environ.get("IDD_GH", "gh") if TEST else "gh"
GIT = os.environ.get("IDD_GIT", "git") if TEST else "git"
SLEEP = 0 if (TEST and os.environ.get("IDD_SLEEP") == "0") else 1
SCRIPTS_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# The local CI gate (#465, capability local-ci-gate): the command, without its arguments.
CI_GATE = [os.environ["IDD_CI_GATE"]] if (TEST and os.environ.get("IDD_CI_GATE")) else ["bash", os.path.join(SCRIPTS_DIR, "idd-ci-gate.sh")]
CI_GATE_RESULTS = {0: "pass", 1: "fail", 2: "timeout", 3: "not-configured", 4: "error", 10: "remote"}
WRITE_ROLES = {"admin", "maintain", "write"}
TRUSTED = {"OWNER", "MEMBER", "COLLABORATOR"}
DIAGNOSIS_RE = re.compile(r"(?m)^[ ]{0,3}## Diagnosis")   # the selector idd-all Phase 2 routes on (r5 #11)
FULL_JSON = "application/vnd.github.full+json"


class Stop(Exception):
    """A guardrail did not pass; the message is the reason, reported verbatim."""


def now():
    return time.time()


def iso(ts):
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(ts))


def parse_iso(text):
    return calendar.timegm(time.strptime(text, "%Y-%m-%dT%H:%M:%SZ"))


def ts(value):
    try:
        return parse_iso(value or "")
    except ValueError:
        return 0


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


def gh_paginated(path, jq, what, accept=None):
    cmd = [GH, "api", path] + (["-H", f"Accept: {accept}"] if accept else []) + ["--paginate", "--jq", jq]
    rc, out, err = run_cmd(cmd)
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


def session_login():
    rc, out, err = run_cmd([GH, "api", "user", "--jq", ".login"])
    login = out.strip()
    if rc != 0 or not login:
        raise Stop("could not read the account running this session (gh api user)")
    return login


_WRITE_CACHE = {}


def can_write(repo, login):
    if login not in _WRITE_CACHE:
        data = gh_json(["api", f"repos/{repo}/collaborators/{login}/permission"], f"the permission of {login}")
        _WRITE_CACHE[login] = (data.get("permission") in ("admin", "write")) or (data.get("role_name") in WRITE_ROLES)
    return _WRITE_CACHE[login]


def issue_comments(repo, n):
    """The issue's comments, each with GitHub's own rendering (`body_html`)."""
    return gh_paginated(f"repos/{repo}/issues/{n}/comments",
                        "[.[] | {id, node_id, html_url, login: .user.login, type: .user.type, assoc: .author_association, "
                        "created_at, updated_at, body, body_html}]",
                        f"the comments of #{n}", accept="application/vnd.github.full+json")


def issue_view(repo, n):
    """The issue as REST returns it with GitHub's rendering: state, title, labels, body, body_html."""
    return gh_json(["api", f"repos/{repo}/issues/{n}", "-H", f"Accept: {FULL_JSON}"], f"issue #{n}")


def first_line(body):
    return (body or "").lstrip("\ufeff \t\r\n").split("\n", 1)[0]


def latest_diagnosis(comments):
    """The comment idd-all Phase 2 routed on: the newest trusted comment with a `## Diagnosis` line."""
    diag = [c.get("body") or "" for c in comments if c.get("assoc") in TRUSTED and DIAGNOSIS_RE.search(c.get("body") or "")]
    return diag[-1] if diag else ""


def html_root(html, raw=""):
    """GitHub's rendering; text without a rendering stops rather than reads as empty (r6 #9)."""
    if not html and (raw or "").strip():
        raise Stop("GitHub returned no rendering for the issue or a comment — not merging")
    try:
        return rendered.parse(html or "")
    except ValueError:
        raise Stop("could not read GitHub's rendering of the issue or a comment — not merging")


def entry_count(conn, name, what):
    """How many entries the connection holds that the read could have returned.

    A timeline read names the event types it wants (`itemTypes`). GitHub's `totalCount` then still counts every
    entry of the timeline — commits and comments too — while the nodes are filtered; the entries that match the
    filter are counted by `filteredCount`. Comparing `totalCount` with the nodes read stopped every PR that had a
    commit (found by the end-to-end run of 2026-11-02; sandbox PR: totalCount 1, filteredCount 0, no nodes).
    An answer without the count stops: the read cannot tell whether it saw everything.
    """
    key = "filteredCount" if name == "timelineItems" else "totalCount"
    count = conn.get(key)
    if name == "timelineItems" and (isinstance(count, bool) or not isinstance(count, int)):
        raise Stop(f"{what}: GitHub's answer has no filteredCount — cannot tell whether every event was read; not merging")
    return count or 0


def connection(obj, name, since, field, what):
    """Nodes of a GraphQL connection read once (at most 100; order differs per connection, r6 #20). When it holds more and the oldest node read is
    still after `since`, older events in the window were not read: stop rather than guess (r5 #2)."""
    conn = obj.get(name) or {}
    nodes = conn.get("nodes") or []
    if entry_count(conn, name, what) > len(nodes) and (not nodes or min(ts(x.get(field)) for x in nodes) >= since):
        raise Stop(f"{what} has more entries than one read returns — not merging; a person reviews this one")
    return nodes


def local_ci(cwd, sha):
    """Run the local CI gate on `sha` and return its exit code (capability local-ci-gate: 0 pass, 1 fail,
    2 timeout, 3 not-configured, 4 error, 10 remote). The gate decides; nothing here reads its output as a verdict."""
    rc, out, err = run_cmd(CI_GATE + ["run", "--commit", sha, "--cwd", cwd])
    return rc
