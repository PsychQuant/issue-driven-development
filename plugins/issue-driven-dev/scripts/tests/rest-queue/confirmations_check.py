#!/usr/bin/env python3
"""Print what intent.unanswered_confirmations returns for the comment fixtures (rest-queue suite, #478).

  confirmations_check.py <scripts/lib> <fixtures dir>

One JSON line. The comments are built from fixtures/comment-*.md and GitHub's rendering of them (.html).
"""
# spec-example: idd-all-rest / a record before and after a Decision
import json
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
import intent  # noqa: E402

FX = sys.argv[2]


def comment(day, name, kind="User"):
    def read(ext):
        with open(f"{FX}/{name}.{ext}", encoding="utf-8") as fh:
            return fh.read()
    return {"login": "me", "type": kind, "assoc": "MEMBER", "created_at": f"2026-11-0{day}T00:00:00Z",
            "body": read("md"), "body_html": read("html")}


three = [comment(1, "comment-default-record"), comment(2, "comment-decision"), comment(3, "comment-layerv-record")]
print(json.dumps({
    "three": intent.unanswered_confirmations(three),
    "two": intent.unanswered_confirmations(three[:2]),
    "none answered": intent.unanswered_confirmations(three[:1]),
    "bot": intent.unanswered_confirmations([comment(1, "comment-default-record", "Bot")]),
    "in code": intent.unanswered_confirmations([comment(1, "comment-default-in-code")]),
}, separators=(",", ":")))
