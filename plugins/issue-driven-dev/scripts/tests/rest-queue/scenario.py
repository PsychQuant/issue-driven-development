#!/usr/bin/env python3
"""Write issues.json for a rest-queue scenario.

  scenario.py DIR ISSUE [ISSUE…]

ISSUE is `number[:key=value[,key=value…]]`. Keys:
  author=LOGIN (default me; `none` = the account is gone)   editor=LOGIN
  labels=a+b                                                html=FIXTURE (fixtures/FIXTURE.html and .md)
  diag=Simple|Plan|Spectra|meeting|parked                    (a trusted Diagnosis comment)
  blocking=TEXT                                             (a non-empty ### Blocking in the body)
  comments=N                                                (total comment count the query reports)
  commenter=LOGIN                                           (one more comment, by that account)
  bot=NAME                                                  (one more comment, by a bot account)
A diagnosis is the newest comment unless comments=N is given: then the query returns only the last 100
comments, none of them a Diagnosis, and comments-<n>.json holds all N with the Diagnosis as the 5th.
"""
import json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
DIAG = {
    "Simple": "## Diagnosis\n\n### Type\nbug\n\n### Complexity\nSimple\n",
    "Plan": "## Diagnosis\n\n### Type\nfeature\n\n### Complexity\nPlan\n",
    "Spectra": "## Diagnosis\n\n### Type\nfeature\n\n### Complexity\nSpectra\n",
    "meeting": "## Diagnosis\n\n### Type\nmeeting\n\n### Strategy (meeting deliberation)\nPhase A\n",
    "parked": "## Diagnosis\n\n### Type\nbug\n\n### Complexity\nSimple when triggered\n",
}


def fixture(name, ext):
    with open(os.path.join(HERE, "fixtures", f"{name}.{ext}"), encoding="utf-8") as fh:
        return fh.read()


def user(login):
    return {"login": login, "__typename": "User"}


def node(spec, out_dir):
    number, _, rest = spec.partition(":")
    opts = dict(kv.split("=", 1) for kv in rest.split(",") if kv)
    n = int(number)
    body, html = "A plain issue. SECRET-TITLE-TEXT\n", "<p dir=\"auto\">A plain issue. SECRET-TITLE-TEXT</p>"
    if "html" in opts:
        body, html = fixture(opts["html"], "md"), fixture(opts["html"], "html")
    if "blocking" in opts:
        body += f"\n---\n\n## Current Status\n\n**Phase**: diagnosed\n\n### Blocking\n- {opts['blocking']}\n"
    comments, total = [], 0
    if "diag" in opts:
        comments = [{"authorAssociation": "MEMBER", "body": DIAG[opts["diag"]], "author": user("me")}]
        total = 1
    if "commenter" in opts:
        comments.append({"authorAssociation": "NONE", "body": "an outside remark", "author": user(opts["commenter"])})
        total += 1
    if "bot" in opts:
        comments.append({"authorAssociation": "NONE", "body": "automated note",
                         "author": {"login": opts["bot"], "__typename": "Bot"}})
        total += 1
    if "comments" in opts:
        total = int(opts["comments"])
        every = [{"assoc": "MEMBER", "body": f"comment {i}", "login": "me", "type": "User"} for i in range(1, total + 1)]
        if "diag" in opts:
            every[4] = {"assoc": "MEMBER", "body": DIAG[opts["diag"]], "login": "me", "type": "User"}
        if "commenter" in opts:   # older than the 100 comments the query returns
            every[2] = {"assoc": "NONE", "body": "an outside remark", "login": opts["commenter"], "type": "User"}
        with open(os.path.join(out_dir, f"comments-{n}.json"), "w", encoding="utf-8") as fh:
            json.dump(every, fh)
        comments = [{"authorAssociation": c["assoc"], "body": c["body"], "author": user(c["login"])} for c in every[-100:]]
    author = opts.get("author", "me")
    labels = [l for l in opts.get("labels", "").split("+") if l]
    return {
        "number": n,
        "author": None if author == "none" else {"login": author},
        "editor": {"login": opts["editor"]} if "editor" in opts else None,
        "labels": {"totalCount": len(labels), "nodes": [{"name": l} for l in labels]},
        "body": body, "bodyHTML": html,
        "comments": {"totalCount": total, "nodes": comments},
    }


def main():
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    nodes = [node(spec, out_dir) for spec in sys.argv[2:]]
    with open(os.path.join(out_dir, "issues.json"), "w", encoding="utf-8") as fh:
        json.dump(nodes, fh)


if __name__ == "__main__":
    main()
