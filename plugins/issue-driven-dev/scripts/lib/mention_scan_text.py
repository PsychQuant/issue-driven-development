#!/usr/bin/env python3
"""Preserve source prose, excluding parser-confirmed code and qualified URLs.

Grammar and source ranges come from maintained parsers. Keep original slices:
rendered tokens and link helpers can decode entity-encoded mentions, which
must remain subject to stricter refusal even when the login is attested.
"""
import html
import re
import sys
from urllib.parse import urlsplit


def qualified_host(raw_url):
    """Only complete ASCII dotted hosts with no userinfo receive exemptions."""
    try:
        parsed = urlsplit(raw_url)
        if (parsed.scheme.lower() not in ('http', 'https')
                or parsed.username is not None or parsed.password is not None):
            return False
        # Accessing port validates its format and range, even if unused below.
        parsed.port
        host = parsed.hostname
        if not host or not host.isascii() or len(host) > 253:
            return False
        labels = host.split('.')
        return len(labels) >= 2 and all(
            1 <= len(label) <= 63
            and label[0].isalnum() and label[-1].isalnum()
            and all(char.isalnum() or char == '-' for char in label)
            for label in labels
        )
    except ValueError:
        return False


def overlaps(span, others):
    return any(span[0] < end and start < span[1] for start, end in others)


def scan_text(source):
    from markdown_it import MarkdownIt, __version__ as markdown_version
    from linkify_it import LinkifyIt, __version__ as linkify_version
    from markdown_it.rules_inline.autolink import autolink
    from markdown_it.rules_inline.backticks import backtick
    from markdown_it.rules_inline.html_inline import html_inline

    # Source maps and rule-state offsets are part of this security boundary;
    # upgrades require fixtures and review before accepting new grammar.
    if markdown_version != '4.0.0' or linkify_version != '2.0.3':
        raise RuntimeError('unsupported Markdown or URL parser version')

    # GFM splits table cells before inline parsing; CommonMark alone can
    # incorrectly pair backticks across cells and hide a live mention.
    parser = MarkdownIt('commonmark').enable('table').disable('inline')
    linkifier = LinkifyIt()
    source = source.replace('\r\n', '\n').replace('\r', '\n')
    # splitlines() also treats Unicode separators as lines, unlike CommonMark;
    # that would shift maps and let a later code block hide earlier HTML.
    lines = source.split('\n')
    environment = {}
    blocks = parser.parse(source, environment)
    handled = set()
    fragments = []
    table_depth = 0

    for block in blocks:
        if block.type == 'table_open':
            table_depth += 1
        elif block.type == 'table_close':
            table_depth -= 1
        if block.type in ('fence', 'code_block'):
            if block.map is None:
                raise ValueError('code block has no source map')
            handled.update(range(*block.map))
        elif block.type == 'inline':
            code_spans, html_spans, angle_spans = [], [], []
            inline_tokens = []

            def observe(rule, token_type, spans):
                def record(state, silent):
                    start = state.pos
                    count = len(state.tokens)
                    matched = rule(state, silent)
                    # Silent lookahead emits no node. Images have another
                    # state with relative offsets; retain their source rather
                    # than applying child offsets to the parent's text.
                    if (matched and not silent and state.tokens is inline_tokens
                            and len(state.tokens) > count
                            and state.tokens[-1].type == token_type):
                        spans.append((start, state.pos))
                    return matched
                return record

            parser.inline.ruler.at('backticks', observe(backtick, 'code_inline', code_spans))
            parser.inline.ruler.at('html_inline', observe(html_inline, 'html_inline', html_spans))
            parser.inline.ruler.at('autolink', observe(autolink, 'link_close', angle_spans))
            parser.inline.parse(block.content, parser, environment, inline_tokens)
            spans = list(code_spans)
            # Qualify URL ranges on the original source, BEFORE code removal.
            # A URL crossing code receives no URL exemption: deleting the code
            # first could extend a URL over an otherwise live mention.
            if block.map is not None and not table_depth and not html_spans:
                for match in linkifier.match(block.content) or []:
                    span = (match.index, match.last_index)
                    if match.schema.lower() not in ('http:', 'https:'):
                        continue
                    start, end = span
                    if not (0 <= start < end <= len(block.content)):
                        raise ValueError('invalid URL source range')
                    if overlaps(span, code_spans) or overlaps(span, html_spans):
                        continue
                    # Explicit CommonMark <URL> is distinct from a bare GFM
                    # URL. Only the native autolink rule grants that exception.
                    angle = any(start == a + 1 and end == b - 1 for a, b in angle_spans)
                    prefix = start == 0 or block.content[start - 1] in ' \t\n\r\f\v*_~('
                    if not (angle or prefix):
                        continue
                    if qualified_host(block.content[start:end]):
                        spans.append(span)

            merged = []
            for start, end in sorted(spans):
                if not (0 <= start < end <= len(block.content)):
                    raise ValueError('invalid inert source range')
                if merged and start <= merged[-1][1]:
                    merged[-1] = (merged[-1][0], max(merged[-1][1], end))
                else:
                    merged.append((start, end))
            cursor = 0
            for start, end in merged:
                fragments.append(block.content[cursor:start])
                cursor = end
            fragments.append(block.content[cursor:])
            if block.map is not None and not table_depth:
                handled.update(range(*block.map))
            # Table cells may share a row map; they do not represent the whole
            # original row. Scan each cell AND retain the original row.
            # Mapless nodes also retain source; never guess missing offsets.

    # HTML, reference definitions, unknown nodes, and anything the parser did
    # not represent stay in the scan, without URL or guessed code exemptions.
    fragments.extend(line for index, line in enumerate(lines) if index not in handled)
    # Removed spans must break context, never form an email/URL from neighbours.
    return '\n'.join(fragments)


def has_entity_mention(text):
    """Inspect already-filtered prose, retaining charref provenance per character.

    Use the standard library's own recognizer, also used by html.unescape,
    rather than maintaining another charref grammar or named-entity list.
    A missing/changed recognizer or decoder error is handled as scan failure.
    """
    for line in text.split('\n'):
        chunks, from_entity = [], []
        empty_entity_offsets = set()
        cursor = 0
        for match in html._charref.finditer(line):
            literal = line[cursor:match.start()]
            chunks.append(literal)
            from_entity.extend([False] * len(literal))
            raw = match.group()
            decoded = html.unescape(raw)
            # Some valid numeric references decode to nothing. Preserve the
            # deleted boundary too: no output character can carry its flag.
            if not decoded:
                empty_entity_offsets.add(len(from_entity))
            chunks.append(decoded)
            from_entity.extend([decoded != raw] * len(decoded))
            cursor = match.end()
        literal = line[cursor:]
        chunks.append(literal)
        from_entity.extend([False] * len(literal))
        decoded = ''.join(chunks)
        if decoded != html.unescape(line):
            raise ValueError('charref provenance does not match standard decoding')
        # Match the gate's existing ASCII login shape. Refuse entity-derived
        # characters and deleted boundaries strictly inside the mention; an
        # entity outside the token does not make that token entity-derived.
        for mention in re.finditer(r'(?<![A-Za-z0-9_])@[A-Za-z0-9][A-Za-z0-9-]*', decoded):
            if (any(from_entity[mention.start():mention.end()])
                    or any(mention.start() < offset < mention.end()
                           for offset in empty_entity_offsets)):
                return True
    return False


def main():
    try:
        source = sys.stdin.read()
        if sys.argv[1:] == ['--check-entity-mentions']:
            # Input is MSCAN, with inert ranges already removed and fragment
            # boundaries preserved. Never reinterpret it as Markdown.
            if has_entity_mention(source):
                print('gh-egress: REFUSED — mention contains entity-derived characters.',
                      file=sys.stderr)
                return 11
            return 0
        if sys.argv[1:]:
            return 14
        result = scan_text(source)
    except Exception as error:
        print('gh-egress: Markdown mention scan unavailable (' + type(error).__name__ + ').',
              file=sys.stderr)
        return 12
    sys.stdout.write(result)
    return 0


if __name__ == '__main__':
    sys.exit(main())
