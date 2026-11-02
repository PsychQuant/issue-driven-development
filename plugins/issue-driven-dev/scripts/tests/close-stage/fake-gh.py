#!/usr/bin/env python3
"""A stand-in for gh used by the close-stage suite. Answers from $FAKE_GH_DIR.

Files read (all optional unless the call needs them):
  login                 account name for `gh api user`
  comments.json         the issue's comments as the REST API returns them
  perm                  viewerPermission of the session account
  perm-<login>.json     collaborator permission of <login> (default: admin)
  authors.json          GraphQL issue author/editor (default: author me, no editor)
  mq.json               GraphQL mergeQueue answer (default: none)
  prs.json              `gh pr list` result
  checks-<k>.json       `gh pr checks` answers in order (k = 1, 2, ...); the last repeats.
                        A missing checks-1.json means "no checks reported".
  checks.rc             exit code for gh pr checks (0 or 8)
  refs.json             closingIssuesReferences
  commits.json          commits
  merge.rc              exit code of gh pr merge (default 0)
  after-merge-<k>.json  `gh pr view --json state,mergeCommit` answers in order; the last repeats
  issue-state           `gh issue view --json state` (default CLOSED)
Every call is appended to calls.log as one JSON array.
"""
import json, os, subprocess, sys
d = os.environ["FAKE_GH_DIR"]
argv = sys.argv[1:]
with open(os.path.join(d, "calls.log"), "a") as fh:
    fh.write(json.dumps(argv) + "\n")
def read(name, default=None):
    p = os.path.join(d, name)
    return open(p).read() if os.path.exists(p) else default
def seq(prefix):
    k = int(read(prefix + ".count", "0")) + 1
    open(os.path.join(d, prefix + ".count"), "w").write(str(k))
    while k >= 1:
        ans = read(f"{prefix}-{k}.json")
        if ans is not None:
            return ans
        k -= 1
    return None
if argv[:2] == ["api", "user"]:
    print(read("login", "me").strip()); sys.exit(0)
if argv[:2] == ["api", "graphql"]:
    q = " ".join(argv)
    if "mergeQueue" in q:
        print(read("mq.json", '{"data":{"repository":{"mergeQueue":null}}}')); sys.exit(0)
    print(read("authors.json", '{"data":{"repository":{"issue":{"author":{"login":"me"},"editor":null}}}}')); sys.exit(0)
if argv[0] == "api" and "/collaborators/" in argv[1]:
    login = argv[1].split("/collaborators/")[1].split("/")[0]
    print(read(f"perm-{login}.json", '{"permission":"admin","role_name":"admin"}')); sys.exit(0)
if argv[0] == "api" and argv[1].endswith("/comments"):
    jq = argv[argv.index("--jq") + 1]
    out = subprocess.run(["jq", "-c", jq], input=read("comments.json", "[]"), capture_output=True, text=True)
    sys.stdout.write(out.stdout); sys.exit(out.returncode)
if argv[:2] == ["repo", "view"]:
    print(json.dumps({"viewerPermission": read("perm", "ADMIN").strip()})); sys.exit(0)
if argv[:2] == ["issue", "view"]:
    print(json.dumps({"state": read("issue-state", "CLOSED").strip()})); sys.exit(0)
if argv[:2] == ["pr", "list"]:
    print(read("prs.json", "[]")); sys.exit(0)
if argv[:2] == ["pr", "checks"]:
    ans = seq("checks")
    if ans is None:
        sys.stderr.write("no checks reported on the 'x' branch\n"); sys.exit(1)
    print(ans); sys.exit(int(read("checks.rc", "0").strip()))
if argv[:2] == ["pr", "view"]:
    field = argv[argv.index("--json") + 1]
    if field == "closingIssuesReferences":
        print(json.dumps({"closingIssuesReferences": json.loads(read("refs.json", "[]"))})); sys.exit(0)
    if field == "commits":
        print(json.dumps({"commits": json.loads(read("commits.json", "[]"))})); sys.exit(0)
    if field == "state,mergeCommit":
        ans = seq("after-merge")
        print(ans if ans is not None else '{"state":"OPEN","mergeCommit":null}'); sys.exit(0)
if argv[:2] == ["pr", "merge"]:
    if "--disable-auto" in argv:
        sys.exit(0)
    rc = int(read("merge.rc", "0").strip())
    if rc: sys.stderr.write("merge refused\n")
    sys.exit(rc)
sys.stderr.write("fake gh: unhandled " + " ".join(argv) + "\n"); sys.exit(2)
