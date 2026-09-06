"""Bounded GitHub Discussions reads shared by knowledge retrieval and publishing.

All gh payloads travel over JSON stdin. Search completeness describes the fetched
index results, not an exhaustive or immediately consistent repository corpus.
Schema reference: https://docs.github.com/en/graphql/reference/discussions
"""
import json
from datetime import datetime
import re
import subprocess


class DiscussionError(RuntimeError):
    """A failed or invalid Discussion operation; never an empty complete corpus."""


DISCUSSION_FIELDS = """
    id number title url body author { login } createdAt updatedAt
    closed locked viewerCanUpdate isAnswered category { id name }
    repository { nameWithOwner }
"""
COMMENT_FIELDS = """
    id url body author { login } createdAt updatedAt replyTo { id }
"""
PAGE_INFO = 'pageInfo { hasNextPage endCursor }'


def _repo_parts(repo):
    if not isinstance(repo, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+', repo):
        raise DiscussionError('repo must be owner/name')
    owner, name = repo.split('/')
    if name in ('.', '..'):
        raise DiscussionError('repo must be owner/name')
    return {'owner': owner, 'name': name}


def _bound(value, name, maximum=10000):
    if isinstance(value, bool) or not isinstance(value, int) or not 1 <= value <= maximum:
        raise DiscussionError(f'{name} must be an integer from 1 to {maximum}')
    return value


def _object(value, context):
    if not isinstance(value, dict):
        raise DiscussionError(f'Missing or malformed {context} in GitHub response')
    return value


def _string(value, context, allow_empty=False):
    if not isinstance(value, str) or (not allow_empty and not value.strip()):
        raise DiscussionError(f'Malformed {context}: expected a string')
    return value


def _timestamp(value, context):
    _string(value, context)
    if not re.fullmatch(r'\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})', value):
        raise DiscussionError(f'Malformed {context}: expected an ISO 8601 timestamp with timezone')
    try:
        datetime.fromisoformat(value[:-1] + '+00:00' if value.endswith('Z') else value)
    except ValueError as exc:
        raise DiscussionError(f'Malformed {context}: invalid timestamp') from exc
    return value


def _count(value, context):
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        raise DiscussionError(f'Malformed {context}: expected a nonnegative integer')
    return value


def _boolean(value, context, nullable=False):
    if not isinstance(value, bool) and not (nullable and value is None):
        raise DiscussionError(f'Malformed {context}: expected a boolean')
    return value


def _author(value):
    # Deleted GitHub actors are represented by null, not an empty login.
    if value is None:
        return None
    actor = _object(value, 'author')
    return _string(actor.get('login'), 'author login')


def _discussion(value):
    result = dict(_object(value, 'Discussion'))
    fields = ('id', 'number', 'title', 'url', 'body', 'author', 'createdAt', 'updatedAt',
              'closed', 'locked', 'viewerCanUpdate', 'isAnswered', 'repository', 'category')
    for key in fields:
        if key not in result:
            raise DiscussionError(f'Missing Discussion field: {key}')
    for key in ('id', 'title', 'url', 'body'):
        _string(result[key], f'Discussion {key}', allow_empty=key == 'body')
    _bound(result['number'], 'Discussion number', 2147483647)
    for key in ('createdAt', 'updatedAt'):
        _timestamp(result[key], f'Discussion {key}')
    for key in ('closed', 'locked', 'viewerCanUpdate', 'isAnswered'):
        # isAnswered is Boolean (nullable) in GitHub's Discussion schema.
        _boolean(result[key], f'Discussion {key}', nullable=key == 'isAnswered')
    repository = _object(result['repository'], 'Discussion repository')
    _repo_parts(repository.get('nameWithOwner'))
    category = _object(result['category'], 'Discussion category')
    for key in ('id', 'name'):
        _string(category.get(key), f'Discussion category {key}')
    result['author'] = _author(result['author'])
    return result


def _check_source_repo(discussion, repo):
    if discussion['repository']['nameWithOwner'].lower() != repo.lower():
        raise DiscussionError('Discussion repository does not match the requested repository')
    return discussion


def _comment(value):
    node = _object(value, 'DiscussionComment')
    for key in ('id', 'url', 'body', 'author', 'createdAt', 'updatedAt', 'replyTo'):
        if key not in node:
            raise DiscussionError(f'Missing DiscussionComment field: {key}')
    for key in ('id', 'url', 'body'):
        _string(node[key], f'DiscussionComment {key}', allow_empty=key == 'body')
    for key in ('createdAt', 'updatedAt'):
        _timestamp(node[key], f'DiscussionComment {key}')
    result = {key: node[key] for key in ('id', 'url', 'body', 'createdAt', 'updatedAt')}
    result['author'] = _author(node['author'])
    parent = node['replyTo']
    result['replyTo'] = (_string(_object(parent, 'replyTo').get('id'), 'replyTo ID')
                         if parent is not None else None)
    return result


def _page(value, seen, max_nodes):
    value = _object(value, 'connection')
    nodes = value.get('nodes')
    info = _object(value.get('pageInfo'), 'pageInfo')
    if not isinstance(nodes, list) or not isinstance(info.get('hasNextPage'), bool):
        raise DiscussionError('Malformed connection nodes or pageInfo')
    if len(nodes) > max_nodes:
        raise DiscussionError('GitHub returned more nodes than the requested page budget')
    cursor = None
    if info['hasNextPage']:
        cursor = info.get('endCursor')
        if not isinstance(cursor, str) or not cursor or cursor in seen or not nodes:
            raise DiscussionError('GitHub pagination did not advance')
        seen.add(cursor)
    return nodes, cursor


class GitHub:
    def __init__(self, timeout=30):
        self.timeout = timeout

    def graphql(self, query, variables):
        """Run gh without a shell; partial GraphQL errors are failures too."""
        try:
            result = subprocess.run(
                ['gh', 'api', 'graphql', '--input', '-'],
                input=json.dumps({'query': query, 'variables': variables}),
                text=True, capture_output=True, timeout=self.timeout, check=False,
            )
        except (OSError, subprocess.TimeoutExpired) as exc:
            raise DiscussionError(f'GitHub GraphQL invocation failed: {exc}') from exc
        try:
            payload = json.loads(result.stdout)
        except (TypeError, json.JSONDecodeError) as exc:
            raise DiscussionError(f'GitHub returned invalid JSON: {result.stderr.strip()}') from exc
        payload = _object(payload, 'GraphQL response')
        if payload.get('errors'):
            raise DiscussionError('GitHub GraphQL errors: ' + json.dumps(payload['errors'], ensure_ascii=False))
        if result.returncode:
            raise DiscussionError(f'GitHub exited {result.returncode}: {result.stderr.strip()}')
        return _object(payload.get('data'), 'GraphQL data')

    def repo(self, repo):
        data = self.graphql('''query($owner:String!, $name:String!) {
            repository(owner:$owner, name:$name) {
                id hasDiscussionsEnabled visibility viewerPermission
            }
        }''', _repo_parts(repo))
        result = _object(data.get('repository'), 'repository (not found or inaccessible)')
        for key in ('id', 'hasDiscussionsEnabled', 'visibility', 'viewerPermission'):
            if key not in result:
                raise DiscussionError(f'Missing repository metadata: {key}')
        _string(result['id'], 'repository ID')
        _boolean(result['hasDiscussionsEnabled'], 'hasDiscussionsEnabled')
        _string(result['visibility'], 'repository visibility')
        # viewerPermission is nullable for viewers without repository access.
        if result['viewerPermission'] is not None:
            _string(result['viewerPermission'], 'repository viewerPermission')
        return result

    def viewer(self):
        data = self.graphql('query { viewer { login } }', {})
        return _author(_object(data.get('viewer'), 'viewer'))

    def _enabled(self, repo):
        if not self.repo(repo)['hasDiscussionsEnabled']:
            raise DiscussionError(f'Discussions are disabled for {repo}')

    def search(self, repo, query, limit=5):
        _repo_parts(repo)
        _bound(limit, 'limit', 1000)
        if not isinstance(query, str) or not query.strip():
            raise DiscussionError('query must be non-empty text')
        # The CLI takes free-text knowledge queries, not GitHub scope or state
        # expressions. Reject qualifiers/operators before any network operation.
        if re.search(r'\b[\w-]+\s*:', query) or re.search(r'\b(?:OR|NOT)\b', query):
            raise DiscussionError('query must be free text without search qualifiers or OR/NOT operators')
        self._enabled(repo)
        search_query = f'repo:{repo} {query}'
        items, warnings, after, seen = [], [
            'GitHub search uses an index and may omit recent or unindexed Discussions; complete only describes these index results.'
        ], None, set()
        complete = True
        while True:
            data = self.graphql('''query($query:String!, $first:Int!, $after:String) {
                search(query:$query, type:DISCUSSION, first:$first, after:$after) {
                    discussionCount ''' + PAGE_INFO + ''' nodes { ... on Discussion {
                    ''' + DISCUSSION_FIELDS + ''' } }
                }
            }''', {'query': search_query, 'first': min(100, limit - len(items)), 'after': after})
            search = _object(data.get('search'), 'search')
            discussion_count = _count(search.get('discussionCount'), 'discussionCount')
            nodes, after = _page(search, seen, min(100, limit - len(items)))
            for node in nodes:
                item = _discussion(node)
                origin = _object(item.get('repository'), 'Discussion repository').get('nameWithOwner')
                if not isinstance(origin, str) or origin.lower() != repo.lower():
                    complete = False
                    warnings.append('Search returned a Discussion outside the requested repository; it was excluded.')
                    continue
                items.append(item)
                if len(items) == limit:
                    break
            if after is None:
                break
            if len(items) >= limit or len(seen) >= 10:
                complete = False
                warnings.append(f'Search result budget reached ({limit}); further matches were not read.')
                break
        if discussion_count > 1000:
            complete = False
            warnings.append('GitHub search exposes at most 1000 results.')
        return {'items': items, 'complete': complete, 'warnings': warnings}

    def list_discussions(self, repo, max_items=1000):
        variables = _repo_parts(repo)
        _bound(max_items, 'max_items')
        self._enabled(repo)
        items, after, seen = [], None, set()
        while True:
            data = self.graphql('''query($owner:String!, $name:String!, $first:Int!, $after:String) {
                repository(owner:$owner, name:$name) {
                    discussions(first:$first, after:$after, orderBy:{field:CREATED_AT,direction:ASC}) {
                    ''' + PAGE_INFO + ' nodes { ' + DISCUSSION_FIELDS + ''' }
                    }
                }
            }''', dict(variables, first=min(100, max_items - len(items)), after=after))
            repository = _object(data.get('repository'), 'repository')
            nodes, after = _page(repository.get('discussions'), seen, min(100, max_items - len(items)))
            items.extend(_check_source_repo(_discussion(node), repo) for node in nodes)
            if after is None:
                return {'items': items, 'complete': True, 'warnings': []}
            if len(items) >= max_items:
                return {'items': items, 'complete': False,
                        'warnings': [f'Discussion budget reached ({max_items}); repository listing is incomplete.']}

    def get(self, repo, number, max_comments=500):
        variables = _repo_parts(repo)
        _bound(number, 'number', 2147483647)
        _bound(max_comments, 'max_comments')
        self._enabled(repo)
        data = self.graphql('''query($owner:String!, $name:String!, $number:Int!) {
            repository(owner:$owner, name:$name) { discussion(number:$number) {
            ''' + DISCUSSION_FIELDS + ''' } }
        }''', dict(variables, number=number))
        repository = _object(data.get('repository'), 'repository')
        result = _check_source_repo(_discussion(repository.get('discussion')), repo)
        comments = []
        after, seen = None, set()
        incomplete = False
        while True:
            data = self.graphql('''query($id:ID!, $first:Int!, $after:String) {
                node(id:$id) { ... on Discussion {
                    comments(first:$first, after:$after) {
                    ''' + PAGE_INFO + ' nodes { ' + COMMENT_FIELDS + ''' replies { totalCount } }
                    }
                } }
            }''', {'id': result['id'], 'first': min(100, max_comments - len(comments)), 'after': after})
            node = _object(data.get('node'), 'Discussion node')
            roots, after = _page(node.get('comments'), seen, min(100, max_comments - len(comments)))
            for index, root in enumerate(roots):
                if len(comments) == max_comments:
                    incomplete = True
                    break
                comments.append(_comment(root))
                count = _count(_object(root.get('replies'), 'reply count').get('totalCount'), 'replies.totalCount')
                if count:
                    reply_after, reply_seen = None, set()
                    while True:
                        if len(comments) == max_comments:
                            incomplete = True
                            break
                        data = self.graphql('''query($id:ID!, $first:Int!, $after:String) {
                            node(id:$id) { ... on DiscussionComment {
                                replies(first:$first, after:$after) {
                                ''' + PAGE_INFO + ' nodes { ' + COMMENT_FIELDS + ''' }
                                }
                            } }
                        }''', {'id': root['id'], 'first': min(100, max_comments - len(comments)), 'after': reply_after})
                        reply_node = _object(data.get('node'), 'DiscussionComment node')
                        replies, reply_after = _page(reply_node.get('replies'), reply_seen, min(100, max_comments - len(comments)))
                        remaining = max_comments - len(comments)
                        comments.extend(_comment(reply) for reply in replies[:remaining])
                        if len(replies) > remaining:
                            incomplete = True
                        if reply_after is None or incomplete:
                            break
                if incomplete:
                    break
                if len(comments) == max_comments and (index + 1 < len(roots) or after is not None):
                    incomplete = True
                    break
            if incomplete or after is None:
                break
        result.update(comments=comments, complete=not incomplete,
                      warnings=[f'Comment/reply budget reached ({max_comments}); Discussion is incomplete.'] if incomplete else [])
        return result
