#!/usr/bin/env python3
"""verify-gate.py — decide whether a verify round lets /idd-all merge and close (#392).

Reads one verify master comment AS GITHUB RENDERS IT (the comment's `body_html`)
and prints one JSON line:

    {"status": "clean" | "not_clean" | "unparseable",
     "verdict": "PASS" | "FAIL" | null,
     "blocking": int | null, "in_scope": int | null, "follow_up": int | null,
     "rejected": int | null, "high_follow_up": int | null,
     "process_gaps": bool | null, "reason": str}

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

- lines: every run of visible text in a block (paragraph, list item, heading,
  summary, details, quote, cell), split at `<br>` (GitHub turns a single
  newline in a comment into `<br>`) — scripts/lib/rendered.py. Code blocks
  are not read.
- the verdict line: a line that opens with a bold upper-case word, e.g.
  `**PASS** — 0 blocking, 0 in-scope fix, 2 follow-up`. Exactly one such line
  may exist anywhere outside table cells, it must be in a top-level paragraph
  (not in a quote, list, table or `<details>`), and its word must be PASS or
  FAIL (CONDITIONAL, or the unfilled template `**PASS / FAIL**`, is
  unparseable).
- the Reviewed line: one line opening with bold `Reviewed`, then
  `base..head` (or a single commit), also top level.
- the findings tables: every table GitHub drew whose header's last cell is
  `Action`, wherever it is (a table inside a collapsed `<details>` counts too).
  Every row's Action cell must be exactly `Blocking`, `In-scope fix`,
  `Follow-up` or `Rejected` (a finding the orchestrator judged not to stand;
  /idd-all never merges past one, close-stage.py decides that).
- the coverage line `X / Y requirements addressed`: a clean report must have
  exactly one, with X == Y.
- reported, not judged (close-stage.py stops on them): `high_follow_up`, the
  Follow-up rows whose Severity is CRITICAL, HIGH, P0 or P1 (a reviewer's
  serious finding filed as out of scope), and `process_gaps`, a `Process Gaps`
  heading (a degraded verify).
"""

import json
import os
import re
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib"))
import rendered  # noqa: E402  (scripts/lib/rendered.py, shared with close-stage.py)

CLASSES = {"Blocking": "blocking", "In-scope fix": "in_scope", "Follow-up": "follow_up", "Rejected": "rejected"}
VERDICT_WORD_RE = re.compile(r"^[A-Z]+(?: / [A-Z]+)*$")
COUNT_RE = re.compile(r"(\d+)\s+(blocking|in-scope fix|follow-up|rejected)\b", re.IGNORECASE)
REVIEWED_RE = re.compile(r"^Reviewed\s*[:：]\s*(?:([0-9a-fA-F]+)\.\.)?([0-9a-fA-F]+)(?![0-9a-zA-Z])")
COVERAGE_RE = re.compile(r"^(\d+)\s*/\s*(\d+)\s+requirements?\s+addressed", re.IGNORECASE)
SHA_ARG_RE = re.compile(r"^[0-9a-f]{40}$")
# Severities a reviewer uses for a finding that must not be filed away as out of scope (#392 verify r5 #4).
HIGH_SEVERITIES = {"CRITICAL", "HIGH", "P0", "P1"}


def emit(status, reason, verdict=None, counts=None, extra=None):
    counts = counts or {}
    out = {
        "status": status,
        "verdict": verdict,
        "blocking": counts.get("blocking"),
        "in_scope": counts.get("in_scope"),
        "follow_up": counts.get("follow_up"),
        "rejected": counts.get("rejected"),
        "high_follow_up": (extra or {}).get("high_follow_up"),
        "process_gaps": (extra or {}).get("process_gaps"),
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


def labelled(root):
    """[(label, text, top_level, block_tag)] for every line that opens with bold text."""
    out = []
    for el, run, top in rendered.lines(root):
        label = rendered.leading_strong(run)
        if label is not None:
            out.append((label, rendered.line_text(run), top, el.tag))
    return out


def read_tables(root):
    """Return (findings_tables, [(action, severity)]). Fail closed on anything ambiguous."""
    count, values = 0, []
    for table in rendered.tables([root]):
        rows = rendered.table_rows(table)
        if not rows:
            continue
        header = rows[0][1] if rows[0][0] else []
        body = rows[1:] if rows[0][0] else rows
        last = header[-1] if header else ""
        if last != "Action" and last.lower().startswith("action"):
            raise Unparseable(f"a table header ends in '{last}', which is not exactly Action")
        if "Action" in header[:-1]:
            raise Unparseable("a table has an Action column that is not its last column")
        if last == "Action":
            count += 1
            sev = header.index("Severity") if "Severity" in header else None
            for _, cells in body:
                if len(cells) != len(header):
                    raise Unparseable(f"a findings row has {len(cells)} cells but its header has {len(header)}")
                if sev is None:
                    raise Unparseable("a findings table has no Severity column (r6 #11)")
                word = re.search(r"\b(CRITICAL|HIGH|MEDIUM|LOW|INFO|P[0-3])\b", cells[sev].upper())
                if not word and cells[-1] in ("Follow-up", "In-scope fix"):
                    raise Unparseable(f"a {cells[-1]} row has Severity '{cells[sev]}', which is not readable")
                values.append((cells[-1], word.group(1) if word else ""))
            continue
        for _, cells in rows:
            for cell in cells:
                if any(cell.lower().startswith(c.lower()) for c in CLASSES):
                    raise Unparseable(f"a table without an Action column has a cell '{cell}': a findings row outside a findings table")
    # A findings row GitHub did not draw as a table row shows as text with pipes —
    # in a paragraph, a list item, a summary, raw text in a details block. The
    # author meant a finding; the gate cannot count it, so it refuses the report
    # (#392 verify r5 #3). Cells are excluded: they are inside a table already.
    for el, run, _ in rendered.lines(root):
        if el.tag in ("td", "th"):
            continue
        # A heading or a bold label naming a class is a finding a person reads (r6 #17).
        label = rendered.leading_strong(run) if el.tag not in rendered.HEADINGS else rendered.line_text(run)
        if label and label.rstrip(":： ").lower() in {c.lower() for c in CLASSES}:
            raise Unparseable(f"'{label}' names a finding class outside a findings table")
        for text in rendered.raw_line_texts(run):
            if "|" in text and any(cell.strip() in CLASSES for cell in text.split("|")):
                raise Unparseable(f"a findings row stands outside a findings table: {text[:80]}")
    return count, values


def check_reviewed(found_lines, expect_sha, expect_base):
    found = [(t, top) for label, t, top in found_lines if label == "Reviewed"]
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
    try:
        root = rendered.parse(html)
    except ValueError as exc:
        return emit("unparseable", f"the report HTML could not be read: {exc}")

    found = labelled(root)
    # A verdict-looking line anywhere a person reads text counts, except inside table cells
    # (a bold severity such as **HIGH** in a findings row is not a verdict) — r5 #10.
    verdicts = [(label, t, top) for label, t, top, tag in found
                if VERDICT_WORD_RE.match(label) and tag not in ("td", "th")]
    if not verdicts:
        return emit("unparseable", "no verdict line (a line starting with **PASS** or **FAIL**) was found")
    if len(verdicts) > 1:
        return emit("unparseable", f"{len(verdicts)} verdict lines were found ({', '.join(v[0] for v in verdicts)}); expected exactly one")
    verdict, verdict_text, top = verdicts[0]
    if verdict not in ("PASS", "FAIL"):
        return emit("unparseable", f"the verdict is '{verdict}', not PASS or FAIL")
    if not top:
        return emit("unparseable", "the verdict line is inside a quote, list, table or details block; it must stand on its own", verdict)

    try:
        if expect_sha:
            check_reviewed([(l, t, top) for l, t, top, _ in found], expect_sha, expect_base)
        tables, values = read_tables(root)
    except Unparseable as exc:
        return emit("unparseable", str(exc), verdict)
    if tables == 0:
        return emit("unparseable", "no findings table (a table whose last column is Action) was found", verdict)

    counts = {"blocking": 0, "in_scope": 0, "follow_up": 0, "rejected": 0}
    high_follow_up = 0
    blocking_scope = 0
    for n, (value, severity) in enumerate(values, 1):
        if value not in CLASSES:
            shown = value if value else "(empty)"
            return emit("unparseable", f"findings row {n} has Action '{shown}', which is not Blocking, In-scope fix, Follow-up or Rejected", verdict)
        counts[CLASSES[value]] += 1
        if value == "Follow-up" and severity in HIGH_SEVERITIES:
            high_follow_up += 1
        # LOW and INFO In-scope fixes do not hold a merge back: decision after round 7 (#392).
        if value == "In-scope fix" and severity not in ("LOW", "INFO", "P3"):
            blocking_scope += 1
    # A verify that ran degraded (a reviewer failed and the coordinator stood in) says so under
    # `### Process Gaps`; the close stage does not merge on it (r5 #22).
    gaps = any(rendered.norm(rendered.text_of(node)).startswith("Process Gaps")
               for node in rendered.walk(root) if rendered.heading_level(node) is not None)
    # The default backend writes a missing cross-model pass as a row, not a section (r6 #8, #21).
    gaps = gaps or "cross-model pass incomplete" in rendered.norm(rendered.text_of(root)).lower()
    extra = {"high_follow_up": high_follow_up, "process_gaps": gaps}

    pairs = [(k.lower(), int(v)) for v, k in COUNT_RE.findall(verdict_text)]
    stated = dict(pairs)
    if len(stated) != len(pairs):
        return emit("unparseable", "the verdict line states the same count twice", verdict, counts, extra)
    if "blocking" not in stated:
        return emit("unparseable", "the verdict line does not state its blocking count (e.g. '**PASS** — 0 blocking, 0 in-scope fix, 2 follow-up')", verdict, counts, extra)
    if counts["rejected"] and "rejected" not in stated:
        return emit("unparseable", f"the table has {counts['rejected']} Rejected finding(s) but the verdict line does not state the rejected count", verdict, counts, extra)
    for key, field in (("blocking", "blocking"), ("in-scope fix", "in_scope"), ("follow-up", "follow_up"), ("rejected", "rejected")):
        if key in stated and stated[key] != counts[field]:
            return emit("unparseable", f"the verdict line says {stated[key]} {key} but the table has {counts[field]}", verdict, counts, extra)
    if verdict == "PASS" and counts["blocking"] > 0:
        return emit("unparseable", f"the verdict PASS contradicts the table, which has {counts['blocking']} Blocking finding(s)", verdict, counts, extra)
    if verdict == "FAIL" and counts["blocking"] == 0 and counts["in_scope"] == 0:
        return emit("unparseable", "the verdict FAIL contradicts the table, which has no Blocking and no In-scope fix finding", verdict, counts, extra)
    if verdict == "FAIL":
        return emit("not_clean", "the verdict is FAIL", verdict, counts, extra)
    if blocking_scope > 0:
        return emit("not_clean", f"{blocking_scope} In-scope fix finding(s) above LOW remain", verdict, counts, extra)
    # A clean report must state its requirements coverage, and it must be complete (r5 #41).
    if verdict == "PASS":
        cover = [COVERAGE_RE.match(rendered.line_text(run)) for _, run, _ in rendered.lines(root)]
        cover = [m for m in cover if m]
        if not cover:
            return emit("unparseable", "a PASS report has no coverage line ('X / Y requirements addressed')", verdict, counts, extra)
        if len(cover) > 1 or cover[0].group(1) != cover[0].group(2):
            shown = ", ".join(f"{m.group(1)} / {m.group(2)}" for m in cover)
            return emit("unparseable", f"the verdict PASS contradicts the coverage line ({shown} requirements addressed)", verdict, counts, extra)
    return emit("clean", "PASS with no Blocking and no In-scope fix finding", verdict, counts, extra)


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
    try:
        return judge(html, expect_sha, expect_base)
    except Exception as exc:  # never exit 1 (not_clean) without JSON on a crash (r5 #46)
        return emit("unparseable", f"internal error: {exc.__class__.__name__}: {exc}")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
