#!/usr/bin/env python3
"""A stand-in for `gh`, backed by JSON records in $FAKE_GH_STORE (#351).

Records: comment-<id>.json and issue-<n>.json, each
  {"body": ..., "user": {"login": ...}, "author_association": ..., "html_url": ...}
The file `user` holds the authenticated login. Only the repository
$FAKE_GH_REPO (default o/r) exists: any other owner/repo is a 404, so a write
aimed at the wrong repository fails here as it would on GitHub (verify #351
round 6). Switches (files in the store):
  fail-patch        — every write exits 1 and writes nothing
  fail-after-patch  — the write lands, then gh exits 1 (a 502 after the fact)
  mangle-read       — reads after a write return the body with a suffix
  pad-read          — reads after a write return the body plus one newline
  fail-body-read    — the raw read of a body fails (--jq reads still work)
  fail-author-read  — the author read ({login…} / .user.login) fails
Other files: repo.json answers `gh repo view <repo> --json …` (absent → error);
issue-<n>-comment-ids lists the comment ids of issue n, oldest first, for
`--paginate --jq '.[-1].id'`.
Every call is appended to calls.log.
"""
import json
import os
import sys

STORE = os.environ["FAKE_GH_STORE"]
REPO = os.environ.get("FAKE_GH_REPO", "o/r")


def log(argv):
    with open(os.path.join(STORE, "calls.log"), "a", encoding="utf-8") as fh:
        fh.write(" ".join(argv) + "\n")


def record_path(endpoint):
    parts = endpoint.strip("/").split("/")          # repos/<owner>/<repo>/issues/...
    if len(parts) < 3 or "/".join(parts[1:3]) != REPO:
        return None
    if len(parts) == 6 and parts[3] == "issues" and parts[4] == "comments":
        return os.path.join(STORE, f"comment-{parts[5]}.json")
    if len(parts) == 5 and parts[3] == "issues":
        return os.path.join(STORE, f"issue-{parts[4]}.json")
    return None


def load(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def save(path, rec):
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(rec, fh)


def write_body(path, body):
    if os.path.exists(os.path.join(STORE, "fail-patch")):
        print("HTTP 502: bad gateway", file=sys.stderr)
        sys.exit(1)
    rec = load(path)
    rec["body"] = body
    rec["written"] = True
    save(path, rec)
    if os.path.exists(os.path.join(STORE, "fail-after-patch")):
        print("HTTP 502: bad gateway", file=sys.stderr)
        sys.exit(1)
    print(json.dumps({"html_url": rec.get("html_url", "")}))


def main(argv):
    log(argv)
    if argv[:1] == ["api"]:
        args = argv[1:]
        method, jq, field, endpoint, paginate = "GET", None, None, None, False
        i = 0
        while i < len(args):
            a = args[i]
            if a == "-X":
                method = args[i + 1]; i += 2; continue
            if a == "--jq":
                jq = args[i + 1]; i += 2; continue
            if a == "-F":
                field = args[i + 1]; i += 2; continue
            if a == "--paginate":
                paginate = True; i += 1; continue
            if endpoint is None:
                endpoint = a
            i += 1
        if endpoint == "user":
            with open(os.path.join(STORE, "user"), encoding="utf-8") as fh:
                login = fh.read().strip()
            print(login if jq == ".login" else json.dumps({"login": login}))
            return 0
        parts = endpoint.strip("/").split("/")
        if (len(parts) == 6 and parts[3] == "issues" and parts[5] == "comments"
                and "/".join(parts[1:3]) == REPO):
            ids_path = os.path.join(STORE, f"issue-{parts[4]}-comment-ids")
            if not os.path.exists(ids_path):
                print("HTTP 404: Not Found", file=sys.stderr)
                return 1
            ids = open(ids_path, encoding="utf-8").read().split()
            if jq == ".[-1].id":
                print(ids[-1] if ids else "")
            else:
                print(json.dumps([{"id": int(i)} for i in ids]))
            return 0
        path = record_path(endpoint)
        if path is None or not os.path.exists(path):
            print("HTTP 404: Not Found", file=sys.stderr)
            return 1
        if method == "PATCH":
            src = field.split("=@", 1)[1]
            body = sys.stdin.read() if src == "-" else open(src, encoding="utf-8", newline="").read()
            write_body(path, body)
            return 0
        if jq and ("login" in jq or "author_association" in jq) and os.path.exists(os.path.join(STORE, "fail-author-read")):
            print("HTTP 502: Bad Gateway", file=sys.stderr)
            return 1
        if not jq and os.path.exists(os.path.join(STORE, "fail-body-read")):
            print("HTTP 502: Bad Gateway", file=sys.stderr)
            return 1
        rec = load(path)
        if rec.get("written") and os.path.exists(os.path.join(STORE, "mangle-read")):
            rec["body"] = rec.get("body", "") + "\nTAMPERED"   # every read form, like GitHub would
        if rec.get("written") and os.path.exists(os.path.join(STORE, "pad-read")):
            rec["body"] = rec.get("body", "") + "\n"
        body = rec.get("body") or ""
        if jq == ".body":
            print(body)
        elif jq == ".html_url":
            print(rec.get("html_url", ""))
        elif jq == ".issue_url":
            print(rec.get("issue_url", ""))
        elif jq and jq.startswith("{login"):
            print(json.dumps({"login": rec["user"]["login"], "assoc": rec["author_association"]}))
        else:
            print(json.dumps(rec))
        return 0
    if argv[:2] == ["repo", "view"]:
        path = os.path.join(STORE, "repo.json")
        if len(argv) < 3 or argv[2] != REPO or not os.path.exists(path):
            print("GraphQL: Could not resolve to a Repository", file=sys.stderr)
            return 1
        print(open(path, encoding="utf-8").read())
        return 0
    if argv[:2] == ["issue", "edit"]:
        n = argv[2]
        repo = argv[argv.index("--repo") + 1] if "--repo" in argv else None
        path = os.path.join(STORE, f"issue-{n}.json")
        if repo != REPO or not os.path.exists(path):
            print(f"GraphQL: Could not resolve to an issue ({repo}#{n})", file=sys.stderr)
            return 1
        body_file = argv[argv.index("--body-file") + 1]
        write_body(path, open(body_file, encoding="utf-8", newline="").read())
        return 0
    print(f"fake gh: unsupported call: {' '.join(argv)}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
