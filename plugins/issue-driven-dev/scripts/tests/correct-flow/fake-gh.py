#!/usr/bin/env python3
"""A stand-in for `gh`, backed by JSON records in $FAKE_GH_STORE (#351).

Records: comment-<id>.json and issue-<n>.json, each
  {"body": ..., "user": {"login": ...}, "author_association": ..., "html_url": ...}
The file `user` holds the authenticated login. Switches (files in the store):
  fail-patch   — every write exits 1
  mangle-read  — reads after a write return the body with a suffix
Every call is appended to calls.log.
"""
import json
import os
import sys

STORE = os.environ["FAKE_GH_STORE"]


def log(argv):
    with open(os.path.join(STORE, "calls.log"), "a", encoding="utf-8") as fh:
        fh.write(" ".join(argv) + "\n")


def record_path(endpoint):
    parts = endpoint.strip("/").split("/")          # repos/<owner>/<repo>/issues/...
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
        path = record_path(endpoint)
        if path is None or not os.path.exists(path):
            print("HTTP 404: Not Found", file=sys.stderr)
            return 1
        if method == "PATCH":
            src = field.split("=@", 1)[1]
            body = sys.stdin.read() if src == "-" else open(src, encoding="utf-8").read()
            write_body(path, body)
            return 0
        rec = load(path)
        if rec.get("written") and os.path.exists(os.path.join(STORE, "mangle-read")):
            rec["body"] = rec.get("body", "") + "\nTAMPERED"   # every read form, like GitHub would
        body = rec.get("body", "")
        if jq == ".body":
            print(body)
        elif jq == ".html_url":
            print(rec.get("html_url", ""))
        elif jq and jq.startswith("{login"):
            print(json.dumps({"login": rec["user"]["login"], "assoc": rec["author_association"]}))
        else:
            print(json.dumps(rec))
        return 0
    if argv[:2] == ["issue", "edit"]:
        n = argv[2]
        body_file = argv[argv.index("--body-file") + 1]
        write_body(os.path.join(STORE, f"issue-{n}.json"), open(body_file, encoding="utf-8").read())
        return 0
    print(f"fake gh: unsupported call: {' '.join(argv)}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
