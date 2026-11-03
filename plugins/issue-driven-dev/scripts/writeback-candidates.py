#!/usr/bin/env python3
"""List the comments a write-back should look at (#424, rules/issue-write-back.md).

usage: writeback-candidates.py --repo <owner/repo> --issue <N>

Prints one line per comment by someone other than the invoking user, updated no
earlier than one day before your own latest `## Diagnosis`, `## Implementation
Plan` or `## Implementation Complete` comment was updated:

    TRUSTED <comment id> <login> <author_association>
    UNTRUSTED <comment id> <login> <author_association>

Those three comments are posted by the skills that run this script, so a comment
older than the latest of them was listed then; the day of margin covers the time
between the listing and the post. Only your own comments set the cutoff: a line in
the issue body, or someone else's comment, cannot hide comments. A comment edited
later is compared by `updated_at`, so it comes back. A bot is UNTRUSTED whatever
its association. Bodies are not printed: the reader fetches one by id and reads it
as data.

Exit: 0 (nothing printed = nothing to look at; a closed issue is not rewritten),
1 could not read, 2 bad arguments.
"""
import datetime
import json
import re
import subprocess
import sys

TRUSTED = {"OWNER", "MEMBER", "COLLABORATOR"}
REPO_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9._-]+")
ISSUE_RE = re.compile(r"[0-9]{1,18}")
LOGIN_RE = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]*(\[bot\])?")
STAGE_RE = re.compile(r"^## (Diagnosis|Implementation Plan|Implementation Complete)\b")


def gh_json(*args):
    """Every JSON value gh printed (--paginate may print one array per page)."""
    try:
        proc = subprocess.run(["gh", *args], capture_output=True)
    except FileNotFoundError:
        return None
    if proc.returncode != 0:
        return None
    text = proc.stdout.decode("utf-8", errors="replace")
    decoder, pos, values = json.JSONDecoder(), 0, []
    try:
        while True:
            while pos < len(text) and text[pos].isspace():
                pos += 1
            if pos >= len(text):
                return values
            value, pos = decoder.raw_decode(text, pos)
            values.append(value)
    except ValueError:
        return None


def stamp(comment):
    """When the comment last changed, as an aware datetime, or None."""
    raw = str(comment.get("updated_at") or comment.get("created_at") or "")
    try:
        return datetime.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None


def first_line(body):
    for line in (body or "").splitlines():
        if line.strip():
            return line.strip()
    return ""


def main(argv):
    if len(argv) != 4 or argv[0] != "--repo" or argv[2] != "--issue":
        print("usage: writeback-candidates.py --repo <owner/repo> --issue <N>", file=sys.stderr)
        return 2
    repo, issue = argv[1], argv[3]
    if not REPO_RE.fullmatch(repo) or ".." in repo or not ISSUE_RE.fullmatch(issue):
        print("ERROR: invalid repo or issue number", file=sys.stderr)
        return 2

    who = gh_json("api", "user")
    me = who[0].get("login") if who and isinstance(who[0], dict) else None
    if not me:
        print("✗ cannot read the gh user; everyone would look like someone else", file=sys.stderr)
        return 1
    record = gh_json("api", f"repos/{repo}/issues/{issue}")
    if not record or not isinstance(record[0], dict):
        print(f"✗ cannot read issue #{issue}", file=sys.stderr)
        return 1
    if record[0].get("state") == "closed":
        print(f"#{issue} is closed; a closed issue is not rewritten", file=sys.stderr)
        return 0
    pages = gh_json("api", f"repos/{repo}/issues/{issue}/comments", "--paginate")
    if pages is None or not all(isinstance(page, list) for page in pages):
        print(f"✗ cannot read the comments of #{issue}", file=sys.stderr)
        return 1
    comments = [c for page in pages for c in page if isinstance(c, dict) and isinstance(c.get("id"), int)]

    latest = None
    for comment in comments:
        if (comment.get("user") or {}).get("login") == me and STAGE_RE.match(first_line(comment.get("body"))):
            when = stamp(comment)
            if when and (latest is None or when > latest):
                latest = when
    cutoff = latest - datetime.timedelta(days=1) if latest else None

    for comment in comments:
        user = comment.get("user") or {}
        login = user.get("login") or ""
        if login == me:
            continue
        when = stamp(comment)
        if cutoff and when and when < cutoff:
            continue
        assoc = str(comment.get("author_association", "NONE"))
        assoc = assoc if assoc.isalpha() else "NONE"
        bot = login.endswith("[bot]") or user.get("type") == "Bot"
        label = "TRUSTED" if assoc in TRUSTED and not bot else "UNTRUSTED"
        shown = login if LOGIN_RE.fullmatch(login) else "(unknown)"
        print(f"{label} {comment['id']} {shown} {assoc}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
