"""Exercise the shared gate locally: no real GitHub dispatches or credentials."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

GATE = Path(__file__).resolve().parents[2] / 'gh-egress.sh'


class MentionMarkdownTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.env = dict(os.environ, IDD_CLAUDE_JSON=str(self.work / 'absent.json'))

    def check(self, body, expected, attested=None, env=None, verb='check'):
        bodyfile = self.work / 'body.md'
        bodyfile.write_bytes(body.encode('utf-8'))
        args = ['bash', str(GATE), verb, '--body-file', str(bodyfile),
                '--scrub-attested', 'warn']
        if attested:
            args += ['--mention-attested', attested]
        result = subprocess.run(args, env=env or self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, expected, repr(body) + '\n' + result.stderr)

    def test_invalid_delimiters_cannot_hide_mentions(self):
        for body in [
            '```text\n```not-a-close\n```\n@octocat',
            '`text @octocat ``',
            '``text @octocat `',
            '````text\n```\n````\n@octocat',
            '~~~text\n~~~not-a-close\n~~~\n@octocat',
            '```text`invalid\n@octocat',
            '> ```text\n> ```not-a-close\n> ```\n> @octocat',
            '- ```text\n  ```not-a-close\n  ```\n\n@octocat',
            '```text\r```not-a-close\r```\r@octocat',
            '```text\r\n```not-a-close\r\n```\r\n@octocat',
        ]:
            with self.subTest(body=body):
                self.check(body, 11)

    def test_valid_code_nodes_are_inert(self):
        for body in [
            '`@octocat`', '``@octocat ` x``', '```@octocat `` x```',
            '```text\n@octocat\n```', '````\n@octocat\n```\n````',
            '~~~text\n@octocat\n~~~', '```\n@octocat',
            '    @octocat', '\t@octocat',
            '> ```\n> @octocat\n> ```', '> `@octocat`',
            '- ```\n  @octocat\n  ```', '- `@octocat`',
            '- item\n\n      @octocat',
            '```text\r@octocat\r```', '```text\r\n@octocat\r\n```',
            '`&#64;octocat`', '~~~\n&#x40;octocat\n~~~',
        ]:
            with self.subTest(body=body):
                self.check(body, 0)

    def test_removing_code_never_creates_email_or_url_exemption(self):
        for body in [
            'hello`code`@octocat', 'https://example.org/`code`@octocat',
            'https://example.org/`code`/@octocat',
            'https://exa`mple`.org/@octocat',
            'https://example.org/`code`&#64;octocat',
            'https://example.org/`code`\n@octocat',
        ]:
            with self.subTest(body=body):
                self.check(body, 11)

    def test_entity_mentions_stay_refused_even_when_attested(self):
        for entity in ['&#64;', '&#064;', '&#x40;', '&#x0040;', '&commat;']:
            with self.subTest(entity=entity):
                self.check(entity + 'octocat', 11, attested='octocat')
        self.check('&#64;&#111;ctocat', 11, attested='octocat')
        self.check('[label](/path \"&#64;octocat\")', 11, attested='octocat')
        self.check('[label](/&#64;octocat)', 11, attested='octocat')
        self.check('[ref]: /path \"&#64;octocat\"\n\ntext', 11, attested='octocat')

    def test_html_and_link_metadata_are_conservatively_scanned(self):
        for body in [
            '<div>\n`@octocat`\n</div>', '<!-- @octocat -->',
            '<span data-login="@octocat">text</span>',
            '[label](/@octocat)', '[label](https://example.org "@octocat")',
            '[ref]: /@octocat\n\ntext',
            '![alt @octocat](https://example.org/image.png)',
        ]:
            with self.subTest(body=body):
                self.check(body, 11)

    def test_existing_exemptions_and_attestation_remain(self):
        for body in ['user@example.org', 'https://example.org/@octocat',
                     '[link](https://example.org/@octocat)',
                     '<https://example.org/@octocat>']:
            with self.subTest(body=body):
                self.check(body, 0)
        self.check('@octocat', 0, attested='octocat')
        self.check('http://localhost/@octocat', 11)
        self.check('https://@octocat', 11)

    def test_less_than_terminates_url_exemption(self):
        for body in ['https://example.org/<@octocat',
                     'https://example.org/<&#64;octocat']:
            with self.subTest(body=body):
                self.check(body, 11, attested=None if '<@' in body else 'octocat')
        self.check('https://example.org/@octocat', 0)
        self.check('<https://example.org/@octocat>', 0)

    def test_nul_body_files_are_refused_before_shell_capture(self):
        bodyfile = self.work / 'nul.md'
        bodyfile.write_bytes(b'`\x00` @octocat ``')
        for flags in [['--body-file', str(bodyfile)], ['-F', str(bodyfile)],
                      ['--body-file=' + str(bodyfile)], ['-F' + str(bodyfile)]]:
            with self.subTest(flags=flags):
                result = subprocess.run(
                    ['bash', str(GATE), 'check', *flags, '--scrub-attested', 'warn'],
                    env=self.env, text=True, capture_output=True)
                self.assertEqual(result.returncode, 12, result.stderr)
                self.assertNotIn('ignored null byte', result.stderr)

    def test_each_body_input_has_an_independent_markdown_boundary(self):
        bodyfile = self.work / 'second.md'
        bodyfile.write_text('@octocat')
        for flags in [
            ['--body', '```', '--body', '@octocat'],
            ['--body=```', '--body=@octocat'],
            ['-b```', '-b@octocat'],
            ['--body', '```', '--body-file', str(bodyfile)],
            ['--body', '`', '--body', '@octocat `'],
        ]:
            with self.subTest(flags=flags):
                result = subprocess.run(
                    ['bash', str(GATE), 'check', *flags, '--scrub-attested', 'warn'],
                    env=self.env, text=True, capture_output=True)
                self.assertEqual(result.returncode, 11, result.stderr)

    def test_url_prefix_and_domain_require_parser_confirmed_ranges(self):
        for body in [
            'xhttps://example.org/@octocat', '[https://example.org/@octocat',
            'https://example.org_/@octocat', 'https://-example.org/@octocat',
            'https://example-.org/@octocat', 'https://example..org/@octocat',
            'https://example.org:bad/@octocat', 'https://example.org:999999/@octocat',
            'https://example_org.com/@octocat', 'https://localhost/@octocat',
            '{https://example.org/@octocat', '/https://example.org/@octocat',
            '_https://example.org/@octocat', '~https://example.org/@octocat',
            'prefix\u00a0https://example.org/@octocat',
            'https://user@example.org/@octocat',
            'https://user:secret@example.org/@octocat',
        ]:
            with self.subTest(body=body):
                self.check(body, 11)
        for prefix in ['', ' ', '\t', '\n', '*', '(']:
            with self.subTest(prefix=prefix):
                self.check(prefix + 'https://example.org/@octocat', 0)
        self.check('https://sub.example.org:443/@octocat', 0)
        self.check('https://example.org/path?q=value&tag=@octocat', 0)

    def test_urls_in_uncertain_contexts_are_conservatively_scanned(self):
        for body in [
            '<div>https://example.org/@octocat</div>',
            '<span data-url=" https://example.org/@octocat">text</span>',
            '<span> https://example.org/@octocat </span>',
            '[ref]: https://example.org/@octocat\n\ntext',
            'a | b\n--- | ---\nhttps://example.org/@octocat | text',
        ]:
            with self.subTest(body=body):
                self.check(body, 11)

    def test_url_ranges_never_weaken_code_boundaries(self):
        for body in [
            'https://example.org/`code`@octocat',
            'https://example.org/`code`&#64;octocat',
            'https://example.org/``code``/@octocat',
        ]:
            with self.subTest(body=body):
                self.check(body, 11)
        self.check('`text https://example.org/@octocat`', 0)
        self.check('```\nhttps://example.org/@octocat\n```', 0)

    def test_linkifier_dependency_failure_refuses_even_clean_body(self):
        (self.work / 'linkify_it.py').write_text('raise ImportError("fixture unavailable")\n')
        env = dict(self.env, PYTHONPATH=str(self.work))
        self.check('ordinary prose', 12, env=env)

    def test_linkifier_runtime_failure_refuses_even_clean_body(self):
        (self.work / 'sitecustomize.py').write_text(
            'from linkify_it import LinkifyIt\n'
            'def fail(*a, **kw): raise RuntimeError("fixture linkifier failure")\n'
            'LinkifyIt.match = fail\n')
        env = dict(self.env, PYTHONPATH=str(self.work))
        self.check('ordinary prose', 12, env=env)

    def test_unsupported_linkifier_version_refuses_even_clean_body(self):
        (self.work / 'sitecustomize.py').write_text(
            'import linkify_it\n'
            'linkify_it.__version__ = "999.0.0"\n')
        env = dict(self.env, PYTHONPATH=str(self.work))
        self.check('ordinary prose', 12, env=env)

    def test_check_and_issue_dispatch_share_the_same_refusal(self):
        marker = self.work / 'dispatched'
        fake = self.work / 'gh'
        fake.write_text('#!/bin/sh\nprintf done > "$DISPATCH_MARKER"\n')
        fake.chmod(0o755)
        env = dict(self.env, IDD_GH_BIN=str(fake), DISPATCH_MARKER=str(marker))
        for verb in ['check', 'comment']:
            for body in ['```text\n```not-a-close\n```\n@octocat',
                         '`text @octocat ``']:
                with self.subTest(verb=verb, body=body):
                    self.check(body, 11, env=env, verb=verb)
                    self.assertFalse(marker.exists())
        self.check('`@octocat`', 0, env=env, verb='comment')
        self.assertEqual(marker.read_text(), 'done')

    def test_gfm_table_cells_cannot_share_a_code_delimiter(self):
        self.check('a | b\n--- | ---\n`foo | @octocat`', 11)
        self.check('a | b\n--- | ---\n`foo | &#64;octocat`', 11,
                   attested='octocat')
        self.check('a | b\n--- | ---\nhttps://example.org/`code`@octocat | end', 11)
        self.check('a | b\n--- | ---\nplain | text', 0)

    def test_unknown_parser_nodes_keep_source_in_scan(self):
        (self.work / 'sitecustomize.py').write_text(
            'from markdown_it import MarkdownIt\n'
            'parse = MarkdownIt.parse\n'
            'def future_parse(self, *a, **kw):\n'
            '    tokens = parse(self, *a, **kw)\n'
            '    for token in tokens:\n'
            '        if token.type == "inline": token.type = "future_block"\n'
            '    return tokens\n'
            'MarkdownIt.parse = future_parse\n')
        env = dict(self.env, PYTHONPATH=str(self.work))
        self.check('@octocat', 11, env=env)
        self.check('`@octocat`', 11, env=env)

    def test_unsupported_parser_version_refuses_even_clean_body(self):
        (self.work / 'sitecustomize.py').write_text(
            'import markdown_it\n'
            'markdown_it.__version__ = "999.0.0"\n')
        env = dict(self.env, PYTHONPATH=str(self.work))
        self.check('ordinary prose', 12, env=env)

    def test_parser_import_failure_refuses_even_clean_body(self):
        (self.work / 'markdown_it.py').write_text('raise ImportError("fixture unavailable")\n')
        env = dict(self.env, PYTHONPATH=str(self.work))
        self.check('ordinary prose', 12, env=env)

    def test_parser_runtime_failure_refuses_even_clean_body(self):
        (self.work / 'sitecustomize.py').write_text(
            'from markdown_it import MarkdownIt\n'
            'def fail(*a, **kw): raise RuntimeError("fixture parse failure")\n'
            'MarkdownIt.parse = fail\n')
        env = dict(self.env, PYTHONPATH=str(self.work))
        self.check('ordinary prose', 12, env=env)

    def test_unicode_separators_do_not_shift_commonmark_source_lines(self):
        self.check('prefix\u2028continuation\n```\n@octocat\n```', 0)
        self.check('<!-- harmless\u2028@octocat -->\n```\ncode\n```', 11)
        self.check('```\ncode\u2028line\n```\n@octocat', 11)

    def test_missing_python_refuses_before_dispatch(self):
        fake_bin = self.work / 'bin'
        fake_bin.mkdir()
        python = fake_bin / 'python3'
        python.write_text('#!/bin/sh\nexit 127\n')
        python.chmod(0o755)
        env = dict(self.env, PATH=str(fake_bin) + os.pathsep + os.environ['PATH'])
        self.check('ordinary prose', 12, env=env)


if __name__ == '__main__':
    unittest.main()
