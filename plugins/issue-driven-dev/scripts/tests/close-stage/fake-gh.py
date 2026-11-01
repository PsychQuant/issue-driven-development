#!/usr/bin/env python3
"""A stand-in for gh used by the close-stage suite. Answers from $FAKE_GH_DIR.

Files read (all optional unless the call needs them):
  login            account name for `gh api user`
  comments.json    the issue's comments as the REST API returns them
  perm             viewerPermission
  prs.json         `gh pr list` result
  checks-<k>.json  `gh pr checks` answers in order (k = 1, 2, ...); the last repeats.
                   A missing checks-1.json means "no checks reported".
  checks.rc        exit code for gh pr checks (0 or 8)
  refs.json        closingIssuesReferences
  commits.json     commits
  merge.rc         exit code of gh pr merge (default 0)
  after-merge.json `gh pr view --json state,mergeCommit` answer
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
if argv[:2] == ["api", "user"]:
    print(read("login", "me").strip()); sys.exit(0)
if argv[0] == "api" and argv[1].endswith("/comments"):
    jq = argv[argv.index("--jq") + 1]
    out = subprocess.run(["jq", "-c", jq], input=read("comments.json", "[]"), capture_output=True, text=True)
    sys.stdout.write(out.stdout); sys.exit(out.returncode)
if argv[:2] == ["repo", "view"]:
    print(json.dumps({"viewerPermission": read("perm", "ADMIN").strip()})); sys.exit(0)
if argv[:2] == ["pr", "list"]:
    print(read("prs.json", "[]")); sys.exit(0)
if argv[:2] == ["pr", "checks"]:
    cnt_path = os.path.join(d, "checks.count")
    k = int(read("checks.count", "0")) + 1
    open(cnt_path, "w").write(str(k))
    ans = None
    while k >= 1 and ans is None:
        ans = read(f"checks-{k}.json"); k -= 1
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
        print(read("after-merge.json", '{"state":"OPEN","mergeCommit":null}')); sys.exit(0)
if argv[:2] == ["pr", "merge"]:
    rc = int(read("merge.rc", "0").strip())
    if rc: sys.stderr.write("merge refused\n")
    sys.exit(rc)
sys.stderr.write("fake gh: unhandled " + " ".join(argv) + "\n"); sys.exit(2)
