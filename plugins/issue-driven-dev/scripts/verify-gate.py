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
# A line that starts a CommonMark HTML block. Inside such a block a ``` line is
# not a fence and a table is rendered by GitHub's HTML, which this parser cannot
# follow, so the gate refuses the report (#392 verify r3 #11). A complete
# one-line comment (IDD's `<!-- idd:... -->` markers) is allowed.
HTML_START_RE = re.compile(r"^ {0,3}<(?:!--|/?[A-Za-z][A-Za-z0-9-]*(?:[\s/>]|$))")
ONE_LINE_COMMENT_RE = re.compile(r"^ {0,3}<!--.*-->\s*$")
REVIEWED_RE = re.compile(r"^\*\*Reviewed\*\*\s*[:：]\s*`?(?:([0-9a-fA-F]+)\.\.)?([0-9a-fA-F]+)`?")
COUNT_RE = re.compile(r"(\d+)\s+(blocking|in-scope fix|follow-up)\b", re.IGNORECASE)
SHA_ARG_RE = re.compile(r"^[0-9a-f]{40}$")


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
    print(f"verify-gate: {msg}\nusage: verify-gate.py --comment-file <path> [--expect-sha <commit> [--expect-base <commit>]]", file=sys.stderr)
    return 64


def parse_args(argv):
    """Return (path, expect_sha, expect_base) or None on a usage error."""
    got = {}
    i = 0
    while i < len(argv):
        flag = argv[i]
        if flag not in ("--comment-file", "--expect-sha", "--expect-base") or flag in got \
                or i + 1 >= len(argv) or not argv[i + 1]:
            return None
        val = argv[i + 1]
        if flag != "--comment-file":
            val = val.lower()
            if not SHA_ARG_RE.match(val):
                return None
        got[flag] = val
        i += 2
    if "--comment-file" not in got or ("--expect-base" in got and "--expect-sha" not in got):
        return None
    return got["--comment-file"], got.get("--expect-sha"), got.get("--expect-base")


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
            if HTML_START_RE.match(line) and not ONE_LINE_COMMENT_RE.match(line):
                raise Unparseable(f"the report contains an HTML block ({line.strip()[:40]}), which the gate cannot read the way GitHub renders it")
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
    in_findings = [False] * len(lines)
    i = 0
    while i < len(lines):
        line = lines[i]
        if "|" in line and i + 1 < len(lines):
            header = cells(line)
            if len(header) >= 2 and is_divider(lines[i + 1], len(header)):
                last = clean_value(header[-1])
                if last != "Action" and last.lower().startswith("action"):
                    raise Unparseable(f"a table header ends in '{header[-1]}', which is not exactly Action")
                if last != "Action" and any(clean_value(h).lower().startswith("action") for h in header[:-1]):
                    raise Unparseable("a table has an Action column that is not its last column")
                j = i + 2
                in_table[i] = in_table[i + 1] = True
                while j < len(lines) and lines[j].strip() and "|" in lines[j]:
                    in_table[j] = True
                    if last == "Action":
                        in_findings[j] = True
                        row = cells(lines[j])
                        rows.append(row[-1] if len(row) == len(header) else None)
                    j += 1
                if last == "Action":
                    tables += 1
                i = j
                continue
        i += 1
    for k, line in enumerate(lines):
        if in_findings[k] or "|" not in line:
            continue
        if any(clean_value(c) in CLASSES for c in cells(line)):
            raise Unparseable(f"a row naming Blocking, In-scope fix or Follow-up stands outside a findings table: {line.strip()[:80]}")
    return tables, rows


def check_reviewed(lines, expect_sha, expect_base):
    found = [(m.group(1), m.group(2)) for m in (REVIEWED_RE.match(l.strip()) for l in lines) if m]
    if not found:
        raise Unparseable("the report has no **Reviewed** line naming the commit it reviewed")
    if len(found) > 1:
        raise Unparseable(f"the report has {len(found)} **Reviewed** lines; expected exactly one")
    base, head = (x.lower() if x else None for x in found[0])
    if head != expect_sha:
        raise Unparseable(f"the report's **Reviewed** commit {head} is not the full commit being merged ({expect_sha})")
    if expect_base and base != expect_base:
        shown = base or "(a single commit, no range)"
        raise Unparseable(f"the report's **Reviewed** range starts at {shown}, not at {expect_base}: the reviewed range is not the range being merged")


def judge(text, expect_sha=None, expect_base=None):
    try:
        lines = unfenced_lines(text)
    except Unparseable as exc:
        return emit("unparseable", str(exc))

    verdict_lines = [l for l in lines if VERDICT_RE.match(l.strip())]
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
            check_reviewed(lines, expect_sha, expect_base)
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

    pairs = [(k.lower(), int(v)) for v, k in COUNT_RE.findall(verdict_lines[0])]
    stated = dict(pairs)
    if len(stated) != len(pairs):
        return emit("unparseable", "the verdict line states the same count twice", verdict, counts)
    if "blocking" not in stated:
        return emit("unparseable", "the verdict line does not state its blocking count (e.g. '**PASS** — 0 blocking, 2 follow-up')", verdict, counts)
    for key, field in (("blocking", "blocking"), ("in-scope fix", "in_scope"), ("follow-up", "follow_up")):
        if key in stated and stated[key] != counts[field]:
            return emit("unparseable", f"the verdict line says {stated[key]} {key} but the table has {counts[field]}", verdict, counts)
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
    path, expect_sha, expect_base = parsed
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except (OSError, UnicodeDecodeError) as exc:
        return emit("unparseable", f"cannot read {path}: {exc.__class__.__name__}")
    return judge(text, expect_sha, expect_base)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
