#!/usr/bin/env python3
"""gh_rest.py — read GitHub through the REST API, in the field shapes of `gh … --json` (#416).

Claude Code cloud sessions block GitHub GraphQL, and every `gh issue …` / `gh pr …` / `gh repo view`
porcelain call is GraphQL underneath; `gh api` REST works everywhere. Scripts read through this
module (via the shell entry `gh-rest.sh`) instead of porcelain, so one place owns the REST →
porcelain field mapping, the paging, and the error hints (change cloud-session-idd-all, design D3).

Read-only by construction: there is no write subcommand. Issue writes go through gh-egress.sh,
whose transport (gh_egress_rest.py) imports the shared helpers below.

Usage (stdout: JSON; exit 0 ok · 1 GitHub/gh failure · 2 usage error):
  gh-rest.sh issue-view <N|issue URL> [--repo R] --json f1,f2,…
  gh-rest.sh issue-list [--repo R] [--state open|closed|all] [--label L]… [--sort created|updated]
                        [--closed-since DATE] [--limit N] --json …
                        (comments: fully paged per issue — one call per issue; --closed-since keeps issues
                         closed on/after DATE — YYYY-MM-DD or an ISO timestamp, normalised to UTC — and --limit
                         counts the kept ones)
  gh-rest.sh pr-list    [--repo R] [--state open|closed|merged|all] [--limit N] --json …
                        (mergeable: one single-PR call per PR — the list endpoint does not carry it)
  gh-rest.sh repo-view  [--repo R] --json …
R is OWNER/REPO or HOST/OWNER/REPO; without it gh resolves {owner}/{repo} from the current
directory's git remote, as `gh issue … ` does without --repo.

Test override: IDD_GH_BIN (gh binary to call; default gh).
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys
import urllib.parse

PAGE = 100
DEFAULT_LIMIT = 30  # gh's own default for list commands

ISSUE_FIELDS = ("number", "title", "state", "body", "url", "createdAt", "updatedAt", "closedAt",
                "author", "labels", "assignees", "milestone", "comments")
PR_FIELDS = ("number", "title", "body", "state", "url", "createdAt", "updatedAt", "closedAt", "mergedAt",
             "headRefName", "headRefOid", "baseRefName", "isDraft", "author", "mergeable")
REPO_FIELDS = ("nameWithOwner", "defaultBranchRef", "isFork", "visibility", "url", "viewerPermission")

PLACEHOLDER = "{owner}/{repo}"

# Owner / repository names and hosts that may enter a REST path. Strict on purpose: a `#`, `?`, `.`/`..`
# segment or `user@` in an issue URL once turned `edit <url> --remove-label x` into DELETE /repos/o/r
# (#416 verify, security lens). `.` and `..` match the name class, so they are refused separately.
_NAME = re.compile(r"[A-Za-z0-9_.-]+")
_HOST = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?(?::[0-9]+)?")


def _name_ok(part):
    return bool(_NAME.fullmatch(part)) and part not in (".", "..")


class GhError(Exception):
    """A gh call failed. `exit_code` is gh's own code; `hint` is an optional extra line."""

    def __init__(self, message, hint=None, exit_code=1):
        super().__init__(message)
        self.hint = hint
        self.exit_code = exit_code


class UsageError(Exception):
    pass


def gh_bin():
    return os.environ.get("IDD_GH_BIN") or "gh"


def split_repo(spec):
    """OWNER/REPO | HOST/OWNER/REPO | None → (host or None, 'OWNER/REPO' or the gh placeholder)."""
    if not spec:
        return None, PLACEHOLDER
    parts = spec.split("/")
    if len(parts) == 2 and all(_name_ok(p) for p in parts):
        return None, spec
    if len(parts) == 3 and _HOST.fullmatch(parts[0]) and all(_name_ok(p) for p in parts[1:]):
        host = parts[0]
        return (None if host == "github.com" else host), f"{parts[1]}/{parts[2]}"
    raise UsageError(f"bad repository '{spec}' (expected OWNER/REPO or HOST/OWNER/REPO)")


def parse_issue_ref(ref, repo_flag):
    """'9' / '#9' / 'https://HOST/OWNER/REPO/issues/9' → (host, repo, number)."""
    m = re.fullmatch(r"https?://([^/]+)/([^/]+)/([^/]+)/(?:issues|pull)/([1-9][0-9]{0,9})/?", ref or "")
    if m:
        host, owner, name = m.group(1), m.group(2), m.group(3)
        if not (_HOST.fullmatch(host) and _name_ok(owner) and _name_ok(name)):
            raise UsageError(f"bad issue URL '{ref}' (host, owner or repository has characters a REST path cannot carry)")
        return (None if host == "github.com" else host), f"{owner}/{name}", int(m.group(4))
    if (ref or "").startswith(("http://", "https://")):
        raise UsageError(f"bad issue URL '{ref}' (expected https://HOST/OWNER/REPO/issues/N)")
    m = re.fullmatch(r"#?([1-9][0-9]{0,9})", ref or "")   # bounded: int() refuses 4300+ digits
    if not m:
        raise UsageError(f"bad issue reference '{ref}' (expected a number or an issue URL)")
    host, repo = split_repo(repo_flag)
    return host, repo, int(m.group(1))


def subject(repo):
    return "the current repository" if repo == PLACEHOLDER else repo


def hint_for(stderr, subj):
    if "not enabled for this session" in stderr:
        return (f"hint: this cloud session cannot reach {subj}; attach the repository to the session "
                f"(add_repo) and retry")
    if "GraphQL is not available" in stderr:
        return ("hint: this operation needs GitHub GraphQL, which Claude Code cloud sessions block; "
                "run it from a local session")
    if "HTTP 404" in stderr:
        return f"hint: {subj} does not exist, or this token cannot see it"
    return None


def run_gh(args, stdin_fd=None):
    """Run gh with args; returns CompletedProcess (text). stdin_fd: an open file to feed as stdin."""
    try:
        return subprocess.run([gh_bin()] + args, stdin=stdin_fd if stdin_fd is not None else subprocess.DEVNULL,
                              capture_output=True, text=True)
    except OSError as exc:
        raise GhError(f"could not run gh: {exc}") from exc


def api(path, host=None, what="gh api", subj=None):
    """GET a REST path and return parsed JSON, or raise GhError with gh's stderr and a hint."""
    r = run_gh(["api", path] + (["--hostname", host] if host else []))
    if r.returncode != 0:
        first = (r.stderr or "").strip().splitlines()[:1]
        raise GhError(f"{what} failed: {first[0] if first else f'gh exited {r.returncode}'}",
                      hint_for(r.stderr or "", subj or "the repository"), r.returncode)
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError as exc:
        raise GhError(f"{what} returned unparseable output") from exc


def pages(path, query, host, what, subj, limit=None, keep=lambda item: True):
    """Page a list endpoint (per_page=100) until a short page or `limit` kept items."""
    items, page = [], 1
    while True:
        q = f"{query}&" if query else ""
        data = api(f"{path}?{q}per_page={PAGE}&page={page}", host, what, subj)
        if not isinstance(data, list):
            raise GhError(f"{what} returned a non-list page")
        for item in data:
            if keep(item):
                items.append(item)
                if limit is not None and len(items) >= limit:
                    return items
        if len(data) < PAGE:
            return items
        page += 1


# ── REST → porcelain shapes ──────────────────────────────────────────────────

def _login(user):
    return {"login": user.get("login")} if isinstance(user, dict) else None


def _issue_value(obj, field):
    return {
        "number": lambda: obj.get("number"),
        "title": lambda: obj.get("title"),
        "state": lambda: (obj.get("state") or "").upper() or None,
        "body": lambda: obj.get("body") or "",   # gh returns "" for an empty body; REST returns null
        "url": lambda: obj.get("html_url"),
        "createdAt": lambda: obj.get("created_at"),
        "updatedAt": lambda: obj.get("updated_at"),
        "closedAt": lambda: obj.get("closed_at"),
        "author": lambda: _login(obj.get("user")),
        "labels": lambda: [{"name": lb.get("name")} for lb in obj.get("labels") or [] if isinstance(lb, dict)],
        "assignees": lambda: [{"login": a.get("login")} for a in obj.get("assignees") or []],
        "milestone": lambda: ({"title": obj["milestone"].get("title"), "number": obj["milestone"].get("number")}
                              if isinstance(obj.get("milestone"), dict) else None),
    }[field]()


def comment_shape(c):
    return {"id": c.get("node_id"), "databaseId": c.get("id"), "author": _login(c.get("user")),
            "authorAssociation": c.get("author_association"), "body": c.get("body"),
            "createdAt": c.get("created_at"), "url": c.get("html_url")}


def _pr_value(obj, field):
    head, base = obj.get("head") or {}, obj.get("base") or {}
    return {
        "number": lambda: obj.get("number"),
        "title": lambda: obj.get("title"),
        "body": lambda: obj.get("body") or "",
        "state": lambda: "MERGED" if obj.get("merged_at") else (obj.get("state") or "").upper() or None,
        "url": lambda: obj.get("html_url"),
        "createdAt": lambda: obj.get("created_at"),
        "updatedAt": lambda: obj.get("updated_at"),
        "closedAt": lambda: obj.get("closed_at"),
        "mergedAt": lambda: obj.get("merged_at"),
        "headRefName": lambda: head.get("ref"),
        "headRefOid": lambda: head.get("sha"),
        "baseRefName": lambda: base.get("ref"),
        "isDraft": lambda: bool(obj.get("draft")),
        "author": lambda: _login(obj.get("user")),
    }[field]()


def _permission(perms):
    for key, name in (("admin", "ADMIN"), ("maintain", "MAINTAIN"), ("push", "WRITE"),
                      ("triage", "TRIAGE"), ("pull", "READ")):
        if (perms or {}).get(key):
            return name
    return None


def _repo_value(obj, field):
    return {
        "nameWithOwner": lambda: obj.get("full_name"),
        "defaultBranchRef": lambda: {"name": obj.get("default_branch")} if obj.get("default_branch") else None,
        "isFork": lambda: bool(obj.get("fork")),
        "visibility": lambda: (obj.get("visibility") or ("private" if obj.get("private") else "public")).upper(),
        "url": lambda: obj.get("html_url"),
        "viewerPermission": lambda: _permission(obj.get("permissions")),
    }[field]()


# ── subcommands ──────────────────────────────────────────────────────────────

def fields_of(spec, allowed, sub):
    if not spec:
        raise UsageError(f"{sub} needs --json <fields>; accepted: {','.join(allowed)}")
    fields = [f.strip() for f in spec.split(",") if f.strip()]
    bad = [f for f in fields if f not in allowed]
    if bad or not fields:
        raise UsageError(f"{sub}: unknown field(s) {','.join(bad) or '(none)'}; accepted: {','.join(allowed)}")
    return fields


def issue_view(a):
    fields = fields_of(a.json, ISSUE_FIELDS, "issue-view")
    host, repo, n = parse_issue_ref(a.issue, a.repo)
    subj = f"{subject(repo)}#{n}"
    out = {}
    base = [f for f in fields if f != "comments"]
    obj = api(f"repos/{repo}/issues/{n}", host, "issue-view", subj) if base else {}
    for f in fields:
        if f == "comments":
            out[f] = [comment_shape(c) for c in pages(f"repos/{repo}/issues/{n}/comments", "", host,
                                                      "issue-view comments", subj)]
        else:
            out[f] = _issue_value(obj, f)
    return out


def closed_since_utc(value):
    """`--closed-since` → `YYYY-MM-DDTHH:MM:SSZ` (UTC), the form `closed_at` uses, so the keep filter can
    compare strings. Accepts what `closed:>=` accepted in search: a date (`2026-10-01`, `2026-1-5`) or a
    timestamp with `Z`, an offset (`2026-10-01T08:00:00+08:00`) or neither (read as UTC)."""
    m = re.fullmatch(r"(\d{4})-(\d{1,2})-(\d{1,2})(?:T(\d{2}):(\d{2})(?::(\d{2}))?(Z|[+-]\d{2}:?\d{2})?)?", value)
    try:
        if not m:
            raise ValueError
        y, mo, d, hh, mm, ss, tz = m.groups()
        when = datetime.datetime(int(y), int(mo), int(d), int(hh or 0), int(mm or 0), int(ss or 0),
                                 tzinfo=datetime.timezone.utc)
        if tz and tz != "Z":
            sign = 1 if tz[0] == "+" else -1
            digits = tz[1:].replace(":", "")
            if int(digits[:2]) > 14 or int(digits[2:]) > 59:
                raise ValueError
            when -= sign * datetime.timedelta(hours=int(digits[:2]), minutes=int(digits[2:]))
    except (ValueError, OverflowError):
        raise UsageError(f"--closed-since needs a date: YYYY-MM-DD, or a timestamp such as 2026-10-01T08:00:00Z "
                         f"or 2026-10-01T08:00:00+08:00 (got {value[:40]!r})")
    return when.strftime("%Y-%m-%dT%H:%M:%SZ")


def issue_list(a):
    fields = fields_of(a.json, ISSUE_FIELDS, "issue-list")
    host, repo = split_repo(a.repo)
    query = f"state={a.state}"
    if a.label:
        query += "&labels=" + ",".join(urllib.parse.quote(lb, safe="") for lb in a.label)
    if a.sort:   # server-side order BEFORE the limit cuts, or "N arbitrary issues, sorted" (#299)
        query += f"&sort={a.sort}&direction=desc"
    since = None
    if a.closed_since:   # REST `since` is update time — closing updates an issue, so it only narrows
        since = closed_since_utc(a.closed_since)
        query += f"&since={since}"
    def keep(it):
        if "pull_request" in it:
            return False
        return since is None or (it.get("closed_at") or "") >= since
    items = pages(f"repos/{repo}/issues", query, host, "issue-list", subject(repo), a.limit, keep=keep)
    out = []
    for it in items:
        row = {}
        for f in fields:
            if f == "comments":   # every comment, not gh's oldest-100 cap
                n = it.get("number")
                if type(n) is not int or n < 1:   # fetched data about to enter an API path
                    raise GhError(f"issue-list returned a non-numeric issue number: {str(n)[:40]!r}")
                row[f] = [comment_shape(c) for c in pages(f"repos/{repo}/issues/{n}/comments", "", host,
                                                          "issue-list comments", f"{subject(repo)}#{n}")]
            else:
                row[f] = _issue_value(it, f)
        out.append(row)
    return out


def pr_list(a):
    fields = fields_of(a.json, PR_FIELDS, "pr-list")
    host, repo = split_repo(a.repo)
    rest_state = {"open": "open", "closed": "closed", "merged": "closed", "all": "all"}[a.state]
    keep = (lambda it: bool(it.get("merged_at"))) if a.state == "merged" else (lambda it: True)
    items = pages(f"repos/{repo}/pulls", f"state={rest_state}", host, "pr-list", subject(repo), a.limit, keep)
    out = []
    for it in items:
        row = {}
        for f in fields:
            if f == "mergeable":   # only the single-PR endpoint computes it; null while GitHub is computing
                pn = it.get("number")
                if type(pn) is not int or pn < 1:   # fetched data about to enter an API path
                    raise GhError(f"pr-list returned a non-numeric pull request number: {str(pn)[:40]!r}")
                one = api(f"repos/{repo}/pulls/{pn}", host, "pr-list mergeable", f"{subject(repo)}#{pn}")
                m = one.get("mergeable") if isinstance(one, dict) else None
                row[f] = {True: "MERGEABLE", False: "CONFLICTING"}.get(m, "UNKNOWN")
            else:
                row[f] = _pr_value(it, f)
        out.append(row)
    return out


def repo_view(a):
    fields = fields_of(a.json, REPO_FIELDS, "repo-view")
    host, repo = split_repo(a.repo)
    obj = api(f"repos/{repo}", host, "repo-view", subject(repo))
    if not isinstance(obj, dict):
        raise GhError("repo-view returned a non-object")
    return {f: _repo_value(obj, f) for f in fields}


class _Parser(argparse.ArgumentParser):
    def error(self, message):
        raise UsageError(message)


def build_parser():
    p = _Parser(prog="gh-rest.sh", allow_abbrev=False)
    sub = p.add_subparsers(dest="cmd", parser_class=_Parser)
    for name, fn in (("issue-view", issue_view), ("issue-list", issue_list), ("pr-list", pr_list),
                     ("repo-view", repo_view)):
        s = sub.add_parser(name, allow_abbrev=False)
        s.set_defaults(fn=fn)
        s.add_argument("--repo", "-R")
        s.add_argument("--json")
        if name == "issue-view":
            s.add_argument("issue", nargs="?")
        if name in ("issue-list", "pr-list"):
            states = ("open", "closed", "all") if name == "issue-list" else ("open", "closed", "merged", "all")
            s.add_argument("--state", choices=states, default="open")
            s.add_argument("--limit", type=int, default=DEFAULT_LIMIT)
        if name == "issue-list":
            s.add_argument("--label", "-l", action="append")
            s.add_argument("--sort", choices=("created", "updated"))
            s.add_argument("--closed-since")
    return p


def main(argv):
    try:
        a = build_parser().parse_args(argv)
        if not getattr(a, "fn", None):
            raise UsageError("missing subcommand (issue-view | issue-list | pr-list | repo-view)")
        if a.cmd == "issue-view" and not a.issue:
            raise UsageError("issue-view needs an issue number or URL")
        if getattr(a, "limit", 1) is not None and getattr(a, "limit", 1) < 1:
            raise UsageError("--limit must be a positive integer")
        result = a.fn(a)
    except UsageError as exc:
        print(f"gh-rest: {exc}", file=sys.stderr)
        return 2
    except GhError as exc:
        print(f"gh-rest: {exc}", file=sys.stderr)
        if exc.hint:
            print(exc.hint, file=sys.stderr)
        return 1
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
