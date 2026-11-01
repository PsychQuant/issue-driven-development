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
# CommonMark fences: an opening run of 3+ backticks or tildes; the closing run
# must use the same character, be at least as long, and carry no info string.
FENCE_OPEN_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})(.*)$")
# GFM divider cells: one or more dashes, optional colons.
DIVIDER_CELL_RE = re.compile(r"^:?-+:?$")
REVIEWED_RE = re.compile(r"^\*\*Reviewed\*\*\s*[:：]\s*`?([0-9a-fA-F]+)`?")
SHA_ARG_RE = re.compile(r"^[0-9a-f]{7,40}$")


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
    print(f"verify-gate: {msg}\nusage: verify-gate.py --comment-file <path> [--expect-sha <commit>]", file=sys.stderr)
    return 64


def parse_args(argv):
    """Return (path, expect_sha) or None on a usage error."""
    path, sha = None, None
    i = 0
    while i < len(argv):
        flag = argv[i]
        if flag not in ("--comment-file", "--expect-sha") or i + 1 >= len(argv) or not argv[i + 1]:
            return None
        val = argv[i + 1]
        if flag == "--comment-file":
            if path is not None:
                return None
            path = val
        else:
            if sha is not None or not SHA_ARG_RE.match(val.lower()):
                return None
            sha = val.lower()
        i += 2
    if path is None:
        return None
    return path, sha


class Unparseable(Exception):
    pass


def unfenced_lines(text):
    """Lines outside fenced code blocks; raises Unparseable on an unclosed fence."""
    out = []
    fence = None  # (char, length) of the open fence
    for line in text.splitlines():
        m = FENCE_OPEN_RE.match(line)
        if fence is None:
            if m and not (m.group(1)[0] == "`" and "`" in m.group(2)):
                fence = (m.group(1)[0], len(m.group(1)))
                continue
            out.append(line)
        else:
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= fence[1] and not m.group(2).strip():
                fence = None
    if fence is not None:
        raise Unparseable("a fenced code block is never closed, so the rest of the report cannot be read")
    return out


def cells(line):
    s = line.strip()
    if s.startswith("|"):
        s = s[1:]
    if s.endswith("|") and not s.endswith("\\|"):
        s = s[:-1]
    return [c.strip() for c in re.split(r"(?<!\\)\|", s)]


def is_divider(line, width):
    if "-" not in line or "|" not in line and width > 1:
        return False
    cs = cells(line)
    return len(cs) == width and all(DIVIDER_CELL_RE.match(c) for c in cs)


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
    """Return (tables_found, rows).

    GFM tables: a header row with pipes, then a divider row with the same number
    of cells; data rows run until a blank line or a line without a pipe (a row
    may omit the leading pipe). A table whose last header cell is exactly
    `Action` is a findings table. Fail closed on anything ambiguous:
    - a header whose last cell is a decorated `Action` (e.g. `**Action（分類）**`);
    - outside every table, a pipe line that names one of the three classes in a
      cell (a findings row cut off from its table, e.g. by a blank line).
    """
    tables = 0
    rows = []
    in_table = [False] * len(lines)
    i = 0
    while i < len(lines):
        line = lines[i]
        if "|" in line and i + 1 < len(lines):
            header = cells(line)
            if len(header) >= 2 and is_divider(lines[i + 1], len(header)):
                last = clean_value(header[-1])
                if last != "Action" and last.lower().startswith("action"):
                    raise Unparseable(f"a table header ends in '{header[-1]}', which is not exactly Action")
                j = i + 2
                in_table[i] = in_table[i + 1] = True
                while j < len(lines) and lines[j].strip() and "|" in lines[j]:
                    in_table[j] = True
                    if last == "Action":
                        row = cells(lines[j])
                        rows.append(row[-1] if len(row) == len(header) else None)
                    j += 1
                if last == "Action":
                    tables += 1
                i = j
                continue
        i += 1
    for k, line in enumerate(lines):
        if in_table[k] or "|" not in line:
            continue
        if any(clean_value(c) in CLASSES for c in cells(line)):
            raise Unparseable(f"a findings row stands outside any findings table: {line.strip()[:80]}")
    return tables, rows


def check_reviewed(lines, expect_sha):
    found = [m.group(1).lower() for m in (REVIEWED_RE.match(l.strip()) for l in lines) if m]
    if not found:
        raise Unparseable("the report has no **Reviewed** line naming the commit it reviewed")
    if len(found) > 1:
        raise Unparseable(f"the report has {len(found)} **Reviewed** lines; expected exactly one")
    sha = found[0]
    if len(sha) < 7 or not expect_sha.startswith(sha):
        raise Unparseable(f"the report's **Reviewed** commit {sha} is not the commit being merged ({expect_sha})")


def judge(text, expect_sha=None):
    try:
        lines = unfenced_lines(text)
    except Unparseable as exc:
        return emit("unparseable", str(exc))

    verdicts = find_verdicts(lines)
    if not verdicts:
        return emit("unparseable", "no verdict line (a line starting with **PASS** or **FAIL**) was found")
    if len(verdicts) > 1:
        return emit("unparseable", f"{len(verdicts)} verdict lines were found ({', '.join(verdicts)}); expected exactly one")
    verdict = verdicts[0]
    if verdict not in ("PASS", "FAIL"):
        return emit("unparseable", f"the verdict is '{verdict}', not PASS or FAIL")

    try:
        if expect_sha:
            check_reviewed(lines, expect_sha)
        tables, rows = read_tables(lines)
    except Unparseable as exc:
        return emit("unparseable", str(exc), verdict)
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
    if verdict == "FAIL" and counts["blocking"] == 0 and counts["in_scope"] == 0:
        return emit("unparseable", "the verdict FAIL contradicts the table, which has no Blocking and no In-scope fix finding", verdict, counts)
    if verdict == "FAIL":
        return emit("not_clean", "the verdict is FAIL", verdict, counts)
    if counts["in_scope"] > 0:
        return emit("not_clean", f"{counts['in_scope']} In-scope fix finding(s) remain", verdict, counts)
    return emit("clean", "PASS with no Blocking and no In-scope fix finding", verdict, counts)


def main(argv):
    parsed = parse_args(argv)
    if parsed is None:
        return usage("expected --comment-file <path> and optionally --expect-sha <7-40 hex digits>, each once")
    path, expect_sha = parsed
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError) as exc:
        return emit("unparseable", f"cannot read {path}: {exc.__class__.__name__}")
    return judge(text, expect_sha)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
