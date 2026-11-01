#!/usr/bin/env python3
"""verify-gate.py — decide whether a verify round lets /idd-all merge and close (#392).

Reads one verify master comment and prints one JSON line:

    {"status": "clean" | "not_clean" | "unparseable",
     "verdict": "PASS" | "FAIL" | null,
     "blocking": int | null, "in_scope": int | null, "follow_up": int | null,
     "reason": str}

Exit codes: clean 0 · not_clean 1 · unparseable 2 (also when the file cannot be
read) · usage error 64.

This is the only judgement that sends code to the default branch without a
person in the loop, so it fails closed: whatever it cannot read, or whatever
contradicts itself, is `unparseable` — never `clean`.

What it reads (idd-verify Step 4 / Step 5a):

- the verdict line: a line that opens with a bold upper-case word, e.g.
  `**PASS** — 0 blocking, 2 follow-up`. Exactly one such line must exist, and
  its word must be PASS or FAIL (CONDITIONAL, or the unfilled template
  `**PASS / FAIL**`, is unparseable).
- the findings tables: markdown tables whose header row's last cell is
  `Action`. Every data row's Action cell must be exactly `Blocking`,
  `In-scope fix` or `Follow-up` (surrounding `*`, `_` or backticks are
  stripped). A table with no data rows counts as zero findings.

Fenced code blocks are skipped, so a quoted template is never read as the report.
"""

import json
import re
import sys

CLASSES = {"Blocking": "blocking", "In-scope fix": "in_scope", "Follow-up": "follow_up"}
# A verdict line opens with a bold run of upper-case ASCII words, optionally
# joined by " / " (so the unfilled template `**PASS / FAIL**` is still seen,
# and rejected). Bold labels such as `**更正**` or `**HIGH 的重現**` are not verdicts.
VERDICT_RE = re.compile(r"^\*\*([A-Z]+(?: / [A-Z]+)*)\*\*")
FENCE_RE = re.compile(r"^\s*(```|~~~)")
DIVIDER_RE = re.compile(r"^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)*\|?\s*$")


def emit(status, reason, verdict=None, counts=None):
    counts = counts or {}
    out = {
        "status": status,
        "verdict": verdict,
        "blocking": counts.get("blocking"),
        "in_scope": counts.get("in_scope"),
        "follow_up": counts.get("follow_up"),
        "reason": reason,
    }
    print(json.dumps(out, ensure_ascii=False))
    return {"clean": 0, "not_clean": 1, "unparseable": 2}[status]


def usage(msg):
    print(f"verify-gate: {msg}\nusage: verify-gate.py --comment-file <path>", file=sys.stderr)
    return 64


def parse_args(argv):
    if len(argv) != 2 or argv[0] != "--comment-file" or not argv[1]:
        return None
    return argv[1]


def unfenced_lines(text):
    in_fence = False
    for line in text.splitlines():
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if not in_fence:
            yield line


def cells(line):
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|"):
        s = s[:-1]
    return [c.strip() for c in s.split("|")]


def clean_value(value):
    v = value.strip()
    while len(v) >= 2 and v[0] == v[-1] and v[0] in "*_`":
        v = v[1:-1].strip()
    return v


def find_verdicts(lines):
    found = []
    for line in lines:
        m = VERDICT_RE.match(line.strip())
        if m:
            found.append(m.group(1).strip())
    return found


def read_tables(lines):
    """Return (tables_found, rows) where rows is a list of Action values.

    A findings table is a header row whose last cell is `Action`, followed by a
    divider row. Data rows continue until the first line that is not a table row.
    """
    tables = 0
    rows = []
    i = 0
    while i < len(lines):
        line = lines[i].strip()
        if line.startswith("|") and i + 1 < len(lines) and DIVIDER_RE.match(lines[i + 1].strip()):
            header = cells(line)
            j = i + 2
            if header and header[-1] == "Action":
                tables += 1
                while j < len(lines) and lines[j].strip().startswith("|"):
                    row = cells(lines[j])
                    rows.append(row[-1] if len(row) == len(header) else None)
                    j += 1
            else:
                while j < len(lines) and lines[j].strip().startswith("|"):
                    j += 1
            i = j
            continue
        i += 1
    return tables, rows


def judge(text):
    lines = list(unfenced_lines(text))

    verdicts = find_verdicts(lines)
    if not verdicts:
        return emit("unparseable", "no verdict line (a line starting with **PASS** or **FAIL**) was found")
    if len(verdicts) > 1:
        return emit("unparseable", f"{len(verdicts)} verdict lines were found ({', '.join(verdicts)}); expected exactly one")
    verdict = verdicts[0]
    if verdict not in ("PASS", "FAIL"):
        return emit("unparseable", f"the verdict is '{verdict}', not PASS or FAIL")

    tables, rows = read_tables(lines)
    if tables == 0:
        return emit("unparseable", "no findings table (a table whose last column is Action) was found", verdict)

    counts = {"blocking": 0, "in_scope": 0, "follow_up": 0}
    for n, raw in enumerate(rows, 1):
        if raw is None:
            return emit("unparseable", f"findings row {n} has a different number of cells than its header", verdict)
        value = clean_value(raw)
        if value not in CLASSES:
            shown = value if value else "(empty)"
            return emit("unparseable", f"findings row {n} has Action '{shown}', which is not Blocking, In-scope fix or Follow-up", verdict)
        counts[CLASSES[value]] += 1

    if verdict == "PASS" and counts["blocking"] > 0:
        return emit("unparseable", f"the verdict PASS contradicts the table, which has {counts['blocking']} Blocking finding(s)", verdict, counts)
    if verdict == "FAIL":
        return emit("not_clean", "the verdict is FAIL", verdict, counts)
    if counts["in_scope"] > 0:
        return emit("not_clean", f"{counts['in_scope']} In-scope fix finding(s) remain", verdict, counts)
    return emit("clean", "PASS with no Blocking and no In-scope fix finding", verdict, counts)


def main(argv):
    path = parse_args(argv)
    if path is None:
        return usage("expected exactly --comment-file <path>")
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError) as exc:
        return emit("unparseable", f"cannot read {path}: {exc.__class__.__name__}")
    return judge(text)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
