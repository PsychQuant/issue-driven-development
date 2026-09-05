#!/usr/bin/env python3
"""Read GitHub Discussions as bounded JSON; no mutations are exposed."""
import argparse
import json
import sys
from lib.discussions_api import DiscussionError, GitHub


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    for name in ('search', 'get', 'list', 'repo'):
        command = sub.add_parser(name)
        command.add_argument('--repo', required=True, help='GitHub owner/name')
        if name == 'search':
            command.add_argument('query', nargs='?', help='Free text; GitHub qualifiers and OR/NOT are not accepted')
            command.add_argument('--query', dest='query_flag', help='Free-text knowledge query')
            command.add_argument('--limit', type=int, default=5)
        elif name == 'get':
            command.add_argument('number', nargs='?', type=int)
            command.add_argument('--number', dest='number_flag', type=int)
            command.add_argument('--max-comments', type=int, default=500)
        elif name == 'list':
            command.add_argument('--max-items', type=int, default=1000)
    args = parser.parse_args(argv)
    github = GitHub()
    try:
        if args.command == 'search':
            if args.query is not None and args.query_flag is not None:
                raise DiscussionError('Pass query either positionally or with --query, not both')
            args.query = args.query_flag if args.query_flag is not None else args.query
            result = github.search(args.repo, args.query, args.limit)
        elif args.command == 'get':
            if args.number is not None and args.number_flag is not None:
                raise DiscussionError('Pass number either positionally or with --number, not both')
            args.number = args.number_flag if args.number_flag is not None else args.number
            result = github.get(args.repo, args.number, args.max_comments)
        elif args.command == 'list':
            result = github.list_discussions(args.repo, args.max_items)
        else:
            result = github.repo(args.repo)
    except DiscussionError as exc:
        print(json.dumps({'error': str(exc), 'complete': False}, ensure_ascii=False))
        return 1
    print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == '__main__':
    sys.exit(main())
