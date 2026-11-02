#!/usr/bin/env python3
"""verify-gate.py — decide whether a verify round lets /idd-all merge and close (#392).

Reads one verify master comment AS GITHUB RENDERS IT (the comment's `body_html`)
and prints one JSON line:

    {"status": "clean" | "not_clean" | "unparseable",
     "verdict": "PASS" | "FAIL" | null,
     "blocking": int | null, "in_scope": int | null, "follow_up": int | null,
     "rejected": int | null, "reason": str}

Exit codes: clean 0 · not_clean 1 · unparseable 2 (also when the file cannot be
read) · usage error 64.

This is the only judgement that sends code to the default branch without a
person in the loop, so it fails closed: whatever it cannot read, or whatever
contradicts itself, is `unparseable` — never `clean`.

Why the rendered HTML and not the markdown: rounds 3 and 4 of #392's verify
found, one after another, report layouts that GitHub draws as a table while a
markdown parser written here did not (HTML blocks, fences inside list items, a
one-line comment holding a raw table, a continuation row). Each fix left the
next gap. GitHub's renderer is the thing a person reads, so the gate reads its
output: a table is a table exactly when GitHub drew one.

What it reads (idd-verify Step 4 / Step 5a):

- lines: the segments of a top-level paragraph, split at `<br>` (GitHub turns a
  single newline in a comment into `<br>`).
- the verdict line: a line that opens with a bold upper-case word, e.g.
  `**PASS** — 0 blocking, 0 in-scope fix, 2 follow-up`. Exactly one such line
  may exist anywhere in the report, it must be in a top-level paragraph (not in
  a quote, list, table or `<details>`), and its word must be PASS or FAIL
  (CONDITIONAL, or the unfilled template `**PASS / FAIL**`, is unparseable).
- the Reviewed line: one line opening with bold `Reviewed`, then
  `base..head` (or a single commit), also top level.
- the findings tables: every table GitHub drew whose header's last cell is
  `Action`, wherever it is (a table inside a collapsed `<details>` counts too).
  Every row's Action cell must be exactly `Blocking`, `In-scope fix`,
  `Follow-up` or `Rejected` (a finding the orchestrator judged not to stand;
  /idd-all never merges past one, close-stage.py decides that).
- the coverage line `X / Y requirements addressed`, when present: a PASS with
  X != Y contradicts itself.
"""

import json
import re
import sys
import unicodedata
from html.parser import HTMLParser

CLASSES = {"Blocking": "blocking", "In-scope fix": "in_scope", "Follow-up": "follow_up", "Rejected": "rejected"}
VERDICT_WORD_RE = re.compile(r"^[A-Z]+(?: / [A-Z]+)*$")
COUNT_RE = re.compile(r"(\d+)\s+(blocking|in-scope fix|follow-up|rejected)\b", re.IGNORECASE)
REVIEWED_RE = re.compile(r"^Reviewed\s*[:：]\s*(?:([0-9a-fA-F]+)\.\.)?([0-9a-fA-F]+)(?![0-9a-zA-Z])")
COVERAGE_RE = re.compile(r"^(\d+)\s*/\s*(\d+)\s+requirements?\s+addressed", re.IGNORECASE)
SHA_ARG_RE = re.compile(r"^[0-9a-f]{40}$")
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"}


def emit(status, reason, verdict=None, counts=None):
    counts = counts or {}
    out = {
        "status": status,
        "verdict": verdict,
        "blocking": counts.get("blocking"),
        "in_scope": counts.get("in_scope"),
        "follow_up": counts.get("follow_up"),
        "rejected": counts.get("rejected"),
        "reason": reason,
    }
    print(json.dumps(out, ensure_ascii=False))
    return {"clean": 0, "not_clean": 1, "unparseable": 2}[status]


def usage(msg):
    print(f"verify-gate: {msg}\nusage: verify-gate.py --html-file <path> [--expect-sha <40-hex commit> [--expect-base <40-hex commit>]]",
          file=sys.stderr)
    return 64


def parse_args(argv):
    """Return (path, expect_sha, expect_base) or None on a usage error."""
    got = {}
    i = 0
    while i < len(argv):
        flag = argv[i]
        if flag not in ("--html-file", "--expect-sha", "--expect-base") or flag in got \
                or i + 1 >= len(argv) or not argv[i + 1]:
            return None
        val = argv[i + 1]
        if flag != "--html-file":
            val = val.lower()
            if not SHA_ARG_RE.match(val):
                return None
        got[flag] = val
        i += 2
    if "--html-file" not in got or ("--expect-base" in got and "--expect-sha" not in got):
        return None
    return got["--html-file"], got.get("--expect-sha"), got.get("--expect-base")


class Unparseable(Exception):
    pass


# ── a small DOM over GitHub's sanitized HTML ───────────────────────────────

class Node:
    __slots__ = ("tag", "parent", "children")

    def __init__(self, tag, parent=None):
        self.tag, self.parent, self.children = tag, parent, []


class Builder(HTMLParser):
    """GitHub's comment HTML is sanitized and well formed; comments are dropped."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("#root")
        self.cur = self.root

    def handle_starttag(self, tag, attrs):
        node = Node(tag, self.cur)
        self.cur.children.append(node)
        if tag not in VOID:
            self.cur = node

    def handle_startendtag(self, tag, attrs):
        self.cur.children.append(Node(tag, self.cur))

    def handle_endtag(self, tag):
        node = self.cur
        while node is not self.root and node.tag != tag:
            node = node.parent
        if node is not self.root:
            self.cur = node.parent

    def handle_data(self, data):
        self.cur.children.append(data)


def norm(text):
    """Visible text for comparison: NFKC, no format characters (zero-width etc.), collapsed spaces."""
    text = unicodedata.normalize("NFKC", text)
    text = "".join(ch for ch in text if unicodedata.category(ch) != "Cf")
    return re.sub(r"\s+", " ", text).strip()


def text_of(node):
    if isinstance(node, str):
        return node
    return "".join(text_of(c) for c in node.children)


def walk(node):
    for c in node.children:
        if isinstance(c, Node):
            yield c
            yield from walk(c)


def lines_of(p):
    """Split a paragraph's children at <br> into lines (lists of children)."""
    out, cur = [], []
    for c in p.children:
        if isinstance(c, Node) and c.tag == "br":
            out.append(cur)
            cur = []
        else:
            cur.append(c)
    out.append(cur)
    return out


def leading_strong(line):
    """The text of the <strong> a line opens with (ignoring leading whitespace), else None."""
    for c in line:
        if isinstance(c, str):
            if c.strip():
                return None
            continue
        return norm(text_of(c)) if c.tag in ("strong", "b") else None
    return None


def labelled_lines(root):
    """[(label, text, top_level)] for every paragraph line that opens with bold text."""
    found = []
    for p in walk(root):
        if p.tag != "p":
            continue
        top = p.parent is root
        for line in lines_of(p):
            label = leading_strong(line)
            if label is not None:
                found.append((label, norm("".join(text_of(c) for c in line)), top))
    return found


def nearest(node, tag):
    node = node.parent
    while node is not None and node.tag != tag:
        node = node.parent
    return node


def table_rows(table):
    """Rows of this table (not of a table nested in one of its cells), as lists of cell texts."""
    rows = []
    for tr in walk(table):
        if tr.tag != "tr" or nearest(tr, "table") is not table:
            continue
        cells = [c for c in tr.children if isinstance(c, Node) and c.tag in ("td", "th")]
        head = any(c.tag == "th" for c in cells) or nearest(tr, "thead") is not None
        rows.append((head, [norm(text_of(c)) for c in cells]))
    return rows


def read_tables(root):
    """Return (findings_tables, action_values). Fail closed on anything ambiguous."""
    tables, values = 0, []
    for table in walk(root):
        if table.tag != "table":
            continue
        rows = table_rows(table)
        if not rows:
            continue
        head_row = rows[0][1] if rows[0][0] else None
        body = rows[1:] if head_row is not None else rows
        header = head_row or []
        last = header[-1] if header else ""
        if last != "Action" and last.lower().startswith("action"):
            raise Unparseable(f"a table header ends in '{last}', which is not exactly Action")
        if "Action" in header[:-1]:
            raise Unparseable("a table has an Action column that is not its last column")
        if last == "Action":
            tables += 1
            for k, (_, cells) in enumerate(body, 1):
                if len(cells) != len(header):
                    raise Unparseable(f"a findings row has {len(cells)} cells but its header has {len(header)}")
                values.append(cells[-1])
            continue
        for _, cells in rows:
            for cell in cells:
                if cell in CLASSES:
                    raise Unparseable(f"a table without an Action column has a cell '{cell}': a findings row outside a findings table")
    # A findings row that GitHub did not draw as a table row (e.g. cut off from
    # its table by a blank line) shows as a line of text with pipes. The author
    # meant a finding; the gate cannot count it, so it refuses the report.
    for p in walk(root):
        if p.tag != "p":
            continue
        for line in lines_of(p):
            text = norm("".join(text_of(c) for c in line))
            if "|" in text and any(cell.strip() in CLASSES for cell in text.split("|")):
                raise Unparseable(f"a findings row stands outside a findings table: {text[:80]}")
    return tables, values


def check_reviewed(labelled, expect_sha, expect_base):
    found = [(t, top) for label, t, top in labelled if label == "Reviewed"]
    if not found:
        raise Unparseable("the report has no **Reviewed** line naming the commit it reviewed")
    if len(found) > 1:
        raise Unparseable(f"the report has {len(found)} **Reviewed** lines; expected exactly one")
    text, top = found[0]
    if not top:
        raise Unparseable("the **Reviewed** line is inside a quote, list or details block; it must stand on its own")
    m = REVIEWED_RE.match(text)
    if not m:
        raise Unparseable(f"the **Reviewed** line does not name a commit: {text[:80]}")
    base, head = (x.lower() if x else None for x in m.groups())
    if head != expect_sha:
        raise Unparseable(f"the report's **Reviewed** commit {head} is not the full commit being merged ({expect_sha})")
    if expect_base and base != expect_base:
        shown = base or "(a single commit, no range)"
        raise Unparseable(f"the report's **Reviewed** range starts at {shown}, not at {expect_base}: the reviewed range is not the range being merged")


def judge(html, expect_sha=None, expect_base=None):
    builder = Builder()
    try:
        builder.feed(html)
        builder.close()
    except Exception as exc:  # html.parser is lenient; anything it raises is unreadable input
        return emit("unparseable", f"the report HTML could not be read: {exc.__class__.__name__}")
    root = builder.root

    labelled = labelled_lines(root)
    verdicts = [(label, t, top) for label, t, top in labelled if VERDICT_WORD_RE.match(label)]
    if not verdicts:
        return emit("unparseable", "no verdict line (a line starting with **PASS** or **FAIL**) was found")
    if len(verdicts) > 1:
        return emit("unparseable", f"{len(verdicts)} verdict lines were found ({', '.join(v[0] for v in verdicts)}); expected exactly one")
    verdict, verdict_text, top = verdicts[0]
    if verdict not in ("PASS", "FAIL"):
        return emit("unparseable", f"the verdict is '{verdict}', not PASS or FAIL")
    if not top:
        return emit("unparseable", "the verdict line is inside a quote, list or details block; it must stand on its own", verdict)

    try:
        if expect_sha:
            check_reviewed(labelled, expect_sha, expect_base)
        tables, values = read_tables(root)
    except Unparseable as exc:
        return emit("unparseable", str(exc), verdict)
    if tables == 0:
        return emit("unparseable", "no findings table (a table whose last column is Action) was found", verdict)

    counts = {"blocking": 0, "in_scope": 0, "follow_up": 0, "rejected": 0}
    for n, value in enumerate(values, 1):
        if value not in CLASSES:
            shown = value if value else "(empty)"
            return emit("unparseable", f"findings row {n} has Action '{shown}', which is not Blocking, In-scope fix, Follow-up or Rejected", verdict)
        counts[CLASSES[value]] += 1

    pairs = [(k.lower(), int(v)) for v, k in COUNT_RE.findall(verdict_text)]
    stated = dict(pairs)
    if len(stated) != len(pairs):
        return emit("unparseable", "the verdict line states the same count twice", verdict, counts)
    if "blocking" not in stated:
        return emit("unparseable", "the verdict line does not state its blocking count (e.g. '**PASS** — 0 blocking, 0 in-scope fix, 2 follow-up')", verdict, counts)
    if counts["rejected"] and "rejected" not in stated:
        return emit("unparseable", f"the table has {counts['rejected']} Rejected finding(s) but the verdict line does not state the rejected count", verdict, counts)
    for key, field in (("blocking", "blocking"), ("in-scope fix", "in_scope"), ("follow-up", "follow_up"), ("rejected", "rejected")):
        if key in stated and stated[key] != counts[field]:
            return emit("unparseable", f"the verdict line says {stated[key]} {key} but the table has {counts[field]}", verdict, counts)
    if verdict == "PASS" and counts["blocking"] > 0:
        return emit("unparseable", f"the verdict PASS contradicts the table, which has {counts['blocking']} Blocking finding(s)", verdict, counts)
    if verdict == "FAIL" and counts["blocking"] == 0 and counts["in_scope"] == 0:
        return emit("unparseable", "the verdict FAIL contradicts the table, which has no Blocking and no In-scope fix finding", verdict, counts)
    if verdict == "PASS":
        for p in walk(root):
            if p.tag != "p":
                continue
            for line in lines_of(p):
                m = COVERAGE_RE.match(norm("".join(text_of(c) for c in line)))
                if m and m.group(1) != m.group(2):
                    return emit("unparseable", f"the verdict PASS contradicts the coverage line ({m.group(1)} / {m.group(2)} requirements addressed)", verdict, counts)
    if verdict == "FAIL":
        return emit("not_clean", "the verdict is FAIL", verdict, counts)
    if counts["in_scope"] > 0:
        return emit("not_clean", f"{counts['in_scope']} In-scope fix finding(s) remain", verdict, counts)
    return emit("clean", "PASS with no Blocking and no In-scope fix finding", verdict, counts)


def main(argv):
    parsed = parse_args(argv)
    if parsed is None:
        return usage("expected --html-file <path>, optionally --expect-sha and --expect-base (each 40 hex digits), each once")
    path, expect_sha, expect_base = parsed
    try:
        with open(path, encoding="utf-8") as fh:
            html = fh.read()
    except (OSError, UnicodeDecodeError) as exc:
        return emit("unparseable", f"cannot read {path}: {exc.__class__.__name__}")
    return judge(html, expect_sha, expect_base)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
