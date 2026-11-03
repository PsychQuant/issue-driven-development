#!/usr/bin/env python3
"""List the comments a write-back should look at (#424, rules/issue-write-back.md).

usage: writeback-candidates.py --repo <owner/repo> --issue <N>

Prints one line per comment by someone other than the invoking user, created no
earlier than one day before the issue body's **Last updated** date:

    TRUSTED <comment id> <login> <author_association>
    UNTRUSTED <comment id> <login> <author_association>

The day of margin exists because that date is local and created_at is UTC: a
comment could otherwise fall in the gap and never be seen. A comment seen twice is
skipped by the reader once it is reflected. Bodies are not printed: the reader
fetches one by id and reads it as data.

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
STAMP_RE = re.compile(r"^\*\*Last updated\*\*:\s*([0-9]{4}-[0-9]{2}-[0-9]{2})", re.M)


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


def cutoff_of(body):
    """The first day to look at, or None when every comment counts."""
    found = STAMP_RE.search(body or "")
    if not found:
        return None
    try:
        day = datetime.date.fromisoformat(found.group(1))
    except ValueError:
        return None
    return (day - datetime.timedelta(days=1)).isoformat()


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

    cutoff = cutoff_of(record[0].get("body"))
    for page in pages:
        for comment in page:
            if not isinstance(comment, dict) or not isinstance(comment.get("id"), int):
                continue
            login = (comment.get("user") or {}).get("login") or ""
            if login == me or (cutoff and str(comment.get("created_at", ""))[:10] < cutoff):
                continue
            assoc = str(comment.get("author_association", "NONE"))
            assoc = assoc if assoc.isalpha() else "NONE"
            label = "TRUSTED" if assoc in TRUSTED else "UNTRUSTED"
            shown = login if LOGIN_RE.fullmatch(login) else "(unknown)"
            print(f"{label} {comment['id']} {shown} {assoc}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
