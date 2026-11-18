#!/usr/bin/env python3
"""A stand-in for gh used by the rest-queue suite. Answers from $FAKE_GH_DIR.

Files read (all optional unless the call needs them):
  issues.json          the open issues, as a list of GraphQL issue nodes (see scenario.py)
  page-size            issues per GraphQL page (default 50)
  fail-page            1-based page number whose request exits 1
  perm-<login>.json    collaborator permission of <login> (default: admin)
  perm-<login>.404     when present, the permission request fails with HTTP 404
  perm-<login>.500     when present, the permission request fails with HTTP 500
  comments-<n>.json    every comment of issue n, as `gh api … --paginate --jq` prints them (one JSON list)
  state-<n>            state of issue n for `gh issue view --json state` (default OPEN)
  default-branch       the default branch `gh repo view --json defaultBranchRef` answers (default main)
  perm-<login>.403     when present, the permission request fails with HTTP 403
Every call is appended to calls.log as one JSON array.
"""
import json, os, sys

d = os.environ["FAKE_GH_DIR"]
argv = sys.argv[1:]
with open(os.path.join(d, "calls.log"), "a") as fh:
    fh.write(json.dumps(argv) + "\n")


def read(name, default=None):
    p = os.path.join(d, name)
    return open(p, encoding="utf-8").read() if os.path.exists(p) else default


def field(name):
    """The value of `-f name=value` / `-F name=value` in argv, or None."""
    for i, a in enumerate(argv):
        if a in ("-f", "-F") and i + 1 < len(argv) and argv[i + 1].startswith(name + "="):
            return argv[i + 1][len(name) + 1:]
    return None


if argv[:2] == ["api", "graphql"]:
    query = field("query") or ""
    if query.count("{") != query.count("}"):   # a real gh would get a syntax error
        sys.stderr.write("fake gh: unbalanced GraphQL\n"); sys.exit(1)
    if "issues(" not in query:
        sys.stderr.write("fake gh: unexpected GraphQL query\n"); sys.exit(1)
    nodes = json.loads(read("issues.json", "[]"))
    size = int(read("page-size", "50"))
    start = int(field("c") or "0")
    page = start // size + 1
    if read("fail-page") is not None and int(read("fail-page")) == page:
        sys.stderr.write("fake gh: HTTP 502\n"); sys.exit(1)
    chunk = nodes[start:start + size]
    more = start + size < len(nodes)
    print(json.dumps({"data": {"repository": {"issues": {
        "pageInfo": {"hasNextPage": more, "endCursor": str(start + size) if more else None},
        "nodes": chunk}}}}))
    sys.exit(0)

if argv[:1] == ["api"] and len(argv) > 1 and "/collaborators/" in argv[1] and argv[1].endswith("/permission"):
    login = argv[1].split("/collaborators/")[1].split("/")[0]
    if read(f"perm-{login}.404") is not None:
        sys.stderr.write("gh: Not Found (HTTP 404)\n"); sys.exit(1)
    if read(f"perm-{login}.403") is not None:
        sys.stderr.write("gh: Must have push access to view collaborator permission. (HTTP 403)\n"); sys.exit(1)
    if read(f"perm-{login}.500") is not None:
        sys.stderr.write("gh: Server Error (HTTP 500)\n"); sys.exit(1)
    print(read(f"perm-{login}.json", '{"permission": "admin", "role_name": "admin"}')); sys.exit(0)

if argv[:1] == ["api"] and len(argv) > 1 and "/issues/" in argv[1] and argv[1].endswith("/comments"):
    n = argv[1].split("/issues/")[1].split("/")[0]
    print(read(f"comments-{n}.json", "[]")); sys.exit(0)

if argv[:2] == ["repo", "view"]:
    print(json.dumps({"defaultBranchRef": {"name": (read("default-branch", "main") or "main").strip()}})); sys.exit(0)

if argv[:2] == ["issue", "view"]:
    n = argv[2]
    print(json.dumps({"state": (read(f"state-{n}", "OPEN") or "OPEN").strip()})); sys.exit(0)

sys.stderr.write("fake gh: unhandled call: " + json.dumps(argv) + "\n")
sys.exit(1)
