"""rendered.py — read a GitHub comment or issue body the way GitHub renders it (#392).

GitHub's `body_html` is what a person sees. Parsing the markdown ourselves kept
missing layouts GitHub draws differently (HTML blocks, fences in list items,
continuation rows — #392 verify rounds 3 to 5), so the close stage reads the
rendered HTML: a table is a table exactly when GitHub drew one, and text
GitHub hides (HTML comments) is not read.

Used by verify-gate.py and close-stage.py. Standard library only.
"""

import re
import unicodedata
from html.parser import HTMLParser

VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param", "source", "track", "wbr"}
# Elements that start a new line of visible text. Everything else is inline.
BLOCKS = {"address", "article", "aside", "blockquote", "dd", "details", "div", "dl", "dt", "figcaption", "figure",
          "footer", "h1", "h2", "h3", "h4", "h5", "h6", "header", "hr", "li", "main", "markdown-accessiblity-table",
          "nav", "ol", "p", "pre", "section", "summary", "table", "tbody", "td", "tfoot", "th", "thead", "tr", "ul"}
HEADINGS = {"h1", "h2", "h3", "h4", "h5", "h6"}


class Node:
    __slots__ = ("tag", "parent", "children")

    def __init__(self, tag, parent=None):
        self.tag, self.parent, self.children = tag, parent, []


class _Builder(HTMLParser):
    """GitHub's comment HTML is sanitized and well formed; HTML comments are dropped."""

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


def parse(html):
    """The root Node of `html`. Raises ValueError when html.parser gives up."""
    builder = _Builder()
    try:
        builder.feed(html or "")
        builder.close()
    except Exception as exc:  # html.parser is lenient; anything it raises is unreadable input
        raise ValueError(f"{exc.__class__.__name__}: {exc}")
    return builder.root


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


def ancestor(node, tags):
    node = node.parent
    while node is not None and node.tag not in tags:
        node = node.parent
    return node


def lines(root):
    """Every line of visible text: (block, children, top_level).

    A line is a run of inline content inside a block element, ended by <br>
    or by a nested block. `top_level` is true only for a paragraph directly
    under the root (not in a quote, list, table or details block). Code
    blocks (<pre>) are skipped.
    """
    out = []
    for el in [root] + list(walk(root)):
        if el is not root and el.tag not in BLOCKS:
            continue
        if el.tag == "pre" or ancestor(el, {"pre"}) is not None:
            continue
        run = []
        for c in el.children:
            if isinstance(c, Node) and (c.tag in BLOCKS or c.tag == "br"):
                if run:
                    out.append((el, run))
                run = []
            else:
                run.append(c)
        if run:
            out.append((el, run))
    return [(el, run, el.tag == "p" and el.parent is root) for el, run in out
            if norm("".join(text_of(c) for c in run))]


def line_text(run):
    return norm("".join(text_of(c) for c in run))


def raw_line_texts(run):
    """The run's text split at newlines (raw text inside an HTML block keeps them)."""
    return [norm(part) for part in "".join(text_of(c) for c in run).split("\n") if norm(part)]


def leading_strong(run):
    """The text of the <strong>/<b> a line opens with (ignoring leading whitespace), else None."""
    for c in run:
        if isinstance(c, str):
            if c.strip():
                return None
            continue
        return norm(text_of(c)) if c.tag in ("strong", "b") else None
    return None


def heading_level(node):
    """1-6 when the node is a heading (or GitHub's div wrapper around one), else None."""
    if node.tag in HEADINGS:
        return int(node.tag[1])
    if node.tag == "div":
        kids = [c for c in node.children if isinstance(c, Node)]
        if kids and kids[0].tag in HEADINGS:
            return int(kids[0].tag[1])
    return None


def sections(root, prefix, max_level=3):
    """Top-level nodes under every heading (level <= max_level) whose text starts with `prefix`, up to the next such heading."""
    out, cur = [], None
    for node in root.children:
        if not isinstance(node, Node):
            continue
        level = heading_level(node)
        if level is not None and level <= max_level:
            cur = [] if norm(text_of(node)).startswith(prefix) else None
            if cur is not None:
                out.append(cur)
            continue
        if cur is not None:
            cur.append(node)
    return out


def table_rows(table):
    """Rows of this table (not of a table nested in one of its cells): [(is_header, [cell texts])]."""
    rows = []
    for tr in walk(table):
        if tr.tag != "tr" or ancestor(tr, {"table"}) is not table:
            continue
        cells = [c for c in tr.children if isinstance(c, Node) and c.tag in ("td", "th")]
        head = any(c.tag == "th" for c in cells) or ancestor(tr, {"thead"}) is not None
        rows.append((head, [norm(text_of(c)) for c in cells]))
    return rows


def tables(nodes):
    """Every table in or under `nodes`."""
    out = []
    for node in nodes:
        if node.tag == "table":
            out.append(node)
        out.extend(t for t in walk(node) if t.tag == "table")
    return out
