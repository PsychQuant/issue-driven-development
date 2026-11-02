"""ghread.py — read GitHub and git for the close stage, failing closed (#392).

Split out of close-stage.py (r5: the helper passed 800 lines). Everything here
raises Stop on anything it cannot read; nothing here decides a merge.

Test seams (honoured only when IDD_CLOSE_STAGE_TEST=1): IDD_GH / IDD_GIT name
the gh and git executables; IDD_SLEEP=0 makes the wait loops not sleep.
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


def html_root(html):
    try:
        return rendered.parse(html or "")
    except ValueError:
        raise Stop("could not read GitHub's rendering of the issue or a comment — not merging")


def connection(obj, name, since, field, what):
    """Nodes of a GraphQL connection read with last:100. When it holds more and the oldest node read is
    still after `since`, older events in the window were not read: stop rather than guess (r5 #2)."""
    conn = obj.get(name) or {}
    nodes = conn.get("nodes") or []
    if (conn.get("totalCount") or 0) > len(nodes) and (not nodes or ts(nodes[0].get(field)) >= since):
        raise Stop(f"{what} has more entries than one read returns — not merging; a person reviews this one")
    return nodes
