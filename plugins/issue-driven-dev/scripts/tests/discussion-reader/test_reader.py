"""Offline contract tests; only gh's process boundary is mocked."""
import importlib.util
import contextlib
import io
import sys
import json
import pathlib
import subprocess
import unittest
from unittest.mock import patch

ROOT = pathlib.Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location('discussions_api', ROOT / 'lib/discussions_api.py')
api = importlib.util.module_from_spec(SPEC) if SPEC and SPEC.loader and (ROOT / 'lib/discussions_api.py').exists() else None
if api:
    SPEC.loader.exec_module(api)


def connection(nodes, more=False, cursor=None):
    return {'nodes': nodes, 'pageInfo': {'hasNextPage': more, 'endCursor': cursor}}


def comment(key, parent=None, replies=0):
    return {'id': key, 'url': 'https://github.com/o/r/discussions/1#' + key,
            'body': 'evidence ' + key, 'author': {'login': 'alice'},
            'createdAt': '2026-01-01T00:00:00Z', 'updatedAt': '2026-01-02T00:00:00Z',
            'replyTo': {'id': parent} if parent else None, 'replies': {'totalCount': replies}}


REPO = {'id': 'R1', 'hasDiscussionsEnabled': True, 'visibility': 'PUBLIC', 'viewerPermission': 'WRITE'}
DISCUSSION = {'id': 'D1', 'number': 1, 'title': 'Topic', 'url': 'https://github.com/o/r/discussions/1',
              'body': 'snapshot', 'author': {'login': 'alice'}, 'createdAt': '2026-01-01T00:00:00Z',
              'updatedAt': '2026-01-02T00:00:00Z', 'closed': True, 'locked': False,
              'viewerCanUpdate': True, 'isAnswered': True, 'category': {'id': 'C1', 'name': 'General'},
              'repository': {'nameWithOwner': 'o/r'}}


class ReaderTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(api, 'shared Discussions reader has not been implemented')
        self.requests = []
        self.queue = []
        self.mock = patch.object(api.subprocess, 'run', side_effect=self.run_gh)
        self.mock.start()
        self.addCleanup(self.mock.stop)
        self.gh = api.GitHub()

    def run_gh(self, args, **kwargs):
        self.assertEqual(args, ['gh', 'api', 'graphql', '--input', '-'])
        self.assertFalse(kwargs.get('shell', False))
        self.assertGreater(kwargs['timeout'], 0)
        self.requests.append(json.loads(kwargs['input']))
        data = self.queue.pop(0)
        if isinstance(data, Exception):
            raise data
        if isinstance(data, subprocess.CompletedProcess):
            return data
        return subprocess.CompletedProcess(args, 0, json.dumps(data), '')

    def feed(self, *data):
        self.queue.extend({'data': value} for value in data)

    def test_reply_second_page_and_root_second_page_preserve_exact_evidence(self):
        self.feed({'repository': REPO}, {'repository': {'discussion': DISCUSSION}},
                  {'node': {'comments': connection([comment('C1', replies=2)], True, 'roots2')}},
                  {'node': {'replies': connection([comment('A1', 'C1')], True, 'replies2')}},
                  {'node': {'replies': connection([comment('A2', 'C1')])}},
                  {'node': {'comments': connection([comment('C2')])}})
        result = self.gh.get('o/r', 1)
        self.assertTrue(result['complete'])
        self.assertEqual([c['id'] for c in result['comments']], ['C1', 'A1', 'A2', 'C2'])
        self.assertEqual(result['comments'][2]['url'], 'https://github.com/o/r/discussions/1#A2')
        self.assertEqual(result['comments'][2]['replyTo'], 'C1')
        self.assertEqual(result['author'], 'alice')
        self.assertEqual(self.requests[4]['variables']['after'], 'replies2')
        self.assertEqual(self.requests[5]['variables']['after'], 'roots2')

    def test_replies_count_toward_global_cap(self):
        self.feed({'repository': REPO}, {'repository': {'discussion': DISCUSSION}},
                  {'node': {'comments': connection([comment('C1', replies=2), comment('C2')])}},
                  {'node': {'replies': connection([comment('A1', 'C1')], True, 'next')}})
        result = self.gh.get('o/r', 1, max_comments=2)
        self.assertFalse(result['complete'])
        self.assertEqual([c['id'] for c in result['comments']], ['C1', 'A1'])
        self.assertTrue(result['warnings'])

    def test_deleted_author_becomes_null(self):
        c = dict(comment('C1'), author=None)
        self.feed({'repository': REPO}, {'repository': {'discussion': dict(DISCUSSION, author=None)}},
                  {'node': {'comments': connection([c])}})
        result = self.gh.get('o/r', 1)
        self.assertIsNone(result['author'])
        self.assertIsNone(result['comments'][0]['author'])

    def test_list_paginates_and_cap_is_not_complete(self):
        self.feed({'repository': REPO}, {'repository': {'discussions': connection([DISCUSSION], True, 'next')}},
                  {'repository': {'discussions': connection([dict(DISCUSSION, id='D2', number=2)], True, 'more')}})
        result = self.gh.list_discussions('o/r', max_items=2)
        self.assertEqual(len(result['items']), 2)
        self.assertFalse(result['complete'])
        self.assertTrue(result['warnings'])
        self.assertEqual(self.requests[2]['variables']['after'], 'next')

    def test_disabled_discussions_are_explicit_error(self):
        self.feed({'repository': dict(REPO, hasDiscussionsEnabled=False)})
        with self.assertRaisesRegex(api.DiscussionError, 'disabled'):
            self.gh.search('o/r', 'topic')

    def test_graphql_partial_errors_are_not_success(self):
        self.queue.append({'data': {'viewer': {'login': 'alice'}}, 'errors': [{'message': 'denied'}]})
        with self.assertRaisesRegex(api.DiscussionError, 'denied'):
            self.gh.viewer()

    def test_timeout_becomes_discussion_error(self):
        self.queue.append(subprocess.TimeoutExpired('gh', 30))
        with self.assertRaises(api.DiscussionError):
            self.gh.viewer()

    def test_repo_validation_and_query_scope_injection_are_rejected(self):
        for repo in ['o/r extra', 'https://github.com/o/r', 'o/r;touch /tmp/no', 'o/r/x']:
            with self.assertRaises(api.DiscussionError):
                self.gh.repo(repo)
        for query in ['repo:evil/repo', 'topic OR repo:evil/repo', 'topic org:evil', '-repo:o/r']:
            with self.assertRaises(api.DiscussionError):
                self.gh.search('o/r', query)
        self.assertEqual(self.requests, [])

    def test_search_shell_text_is_stdin_data_and_all_states(self):
        self.feed({'repository': REPO}, {'search': dict(connection([DISCUSSION]), discussionCount=1)})
        result = self.gh.search('o/r', 'hello $(touch /tmp/never) `whoami`')
        self.assertEqual(result['items'][0]['number'], 1)
        self.assertTrue(result['complete'])
        self.assertTrue(result['warnings'])  # Search index never proves an exhaustive corpus.
        request = self.requests[-1]
        self.assertIn('$(touch /tmp/never)', request['variables']['query'])
        self.assertNotIn('hello', request['query'])
        self.assertNotIn('is:open', request['variables']['query'])
        self.assertNotIn('category:', request['variables']['query'])

    def test_search_foreign_repo_result_cannot_escape_scope(self):
        self.feed({'repository': REPO}, {'search': dict(connection([dict(DISCUSSION, repository={'nameWithOwner': 'evil/r'})]), discussionCount=1)})
        result = self.gh.search('o/r', 'topic')
        self.assertEqual(result['items'], [])
        self.assertFalse(result['complete'])

    def test_broken_pagination_errors_instead_of_looping(self):
        self.feed({'repository': REPO}, {'repository': {'discussions': connection([], True, None)}})
        with self.assertRaises(api.DiscussionError):
            self.gh.list_discussions('o/r')

    def test_nonzero_invalid_json_and_null_repository_are_errors(self):
        for response in [subprocess.CompletedProcess([], 1, '{}', 'unauthorized'),
                         subprocess.CompletedProcess([], 0, 'not JSON', ''),
                         {'data': {'repository': None}}]:
            self.queue.append(response)
            with self.assertRaises(api.DiscussionError):
                self.gh.repo('o/r')

    def test_exact_comment_budget_can_still_be_complete(self):
        self.feed({'repository': REPO}, {'repository': {'discussion': DISCUSSION}},
                  {'node': {'comments': connection([comment('C1', replies=1)])}},
                  {'node': {'replies': connection([comment('A1', 'C1')])}})
        result = self.gh.get('o/r', 1, max_comments=2)
        self.assertTrue(result['complete'])
        self.assertEqual(len(result['comments']), 2)

    def test_search_next_page_and_upper_bound_are_honest(self):
        self.feed({'repository': REPO},
                  {'search': dict(connection([DISCUSSION], True, 'next'), discussionCount=1001)},
                  {'search': dict(connection([dict(DISCUSSION, number=2)]), discussionCount=1001)})
        result = self.gh.search('o/r', 'topic', limit=2)
        self.assertEqual([d['number'] for d in result['items']], [1, 2])
        self.assertFalse(result['complete'])
        self.assertEqual(self.requests[-1]['variables']['after'], 'next')

    def test_zero_and_negative_budgets_fail_before_io(self):
        for value in [0, -1, True, 1.5]:
            with self.assertRaises(api.DiscussionError):
                self.gh.get('o/r', 1, max_comments=value)
            with self.assertRaises(api.DiscussionError):
                self.gh.list_discussions('o/r', max_items=value)
        self.assertEqual(self.requests, [])

    def test_missing_comment_parent_id_is_not_silent_null(self):
        self.feed({'repository': REPO}, {'repository': {'discussion': DISCUSSION}},
                  {'node': {'comments': connection([dict(comment('C1'), replyTo={})])}})
        with self.assertRaises(api.DiscussionError):
            self.gh.get('o/r', 1)

    def test_overfull_list_response_is_not_silently_truncated(self):
        self.feed({'repository': REPO}, {'repository': {'discussions': connection([DISCUSSION, DISCUSSION])}})
        with self.assertRaises(api.DiscussionError):
            self.gh.list_discussions('o/r', max_items=1)

    def test_cli_json_error_and_success_contract(self):
        with patch.dict(sys.modules, {'lib.discussions_api': api}):
            spec = importlib.util.spec_from_file_location('reader_cli', ROOT / 'idd-discussions-read.py')
            cli = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(cli)
        self.feed({'repository': REPO})
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            status = cli.main(['repo', '--repo', 'o/r'])
        self.assertEqual(status, 0)
        self.assertEqual(json.loads(stdout.getvalue())['id'], 'R1')
        self.queue.append({'errors': [{'message': 'denied'}]})
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            status = cli.main(['list', '--repo', 'o/r'])
        self.assertEqual(status, 1)
        self.assertFalse(json.loads(stdout.getvalue())['complete'])
        self.assertIn('denied', json.loads(stdout.getvalue())['error'])

    def test_cli_named_query_and_number_flags(self):
        with patch.dict(sys.modules, {'lib.discussions_api': api}):
            spec = importlib.util.spec_from_file_location('reader_cli_flags', ROOT / 'idd-discussions-read.py')
            cli = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(cli)
        self.feed({'repository': REPO}, {'search': dict(connection([DISCUSSION]), discussionCount=1)})
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            try:
                status = cli.main(['search', '--query', 'topic', '--repo', 'o/r'])
            except SystemExit as exc:
                self.fail(f'--query flag rejected: {exc}')
        self.assertEqual(status, 0)
        self.assertEqual(json.loads(stdout.getvalue())['items'][0]['number'], 1)
        self.feed({'repository': REPO}, {'repository': {'discussion': DISCUSSION}},
                  {'node': {'comments': connection([])}})
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            try:
                status = cli.main(['get', '--number', '1', '--repo', 'o/r', '--max-comments', '2000'])
            except SystemExit as exc:
                self.fail(f'--number flag rejected: {exc}')
        self.assertEqual(status, 0)
        self.assertEqual(json.loads(stdout.getvalue())['author'], 'alice')


if __name__ == '__main__':
    unittest.main()
