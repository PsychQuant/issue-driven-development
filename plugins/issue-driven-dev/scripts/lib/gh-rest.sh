#!/usr/bin/env bash
# gh-rest.sh — read GitHub through the REST API, in the field shapes of `gh … --json` (#416).
#
# The stable shell entry for scripts and SKILL.md; the logic lives in gh_rest.py next to it.
# Use it instead of `gh issue view|list`, `gh pr list`, `gh repo view`: those are GraphQL underneath,
# which Claude Code cloud sessions block. Read-only — issue writes go through scripts/gh-egress.sh.
#
#   gh-rest.sh issue-view <N|issue URL> [--repo R] --json f1,f2,…
#   gh-rest.sh issue-list [--repo R] [--state open|closed|all] [--label L]… [--limit N] --json …
#   gh-rest.sh pr-list    [--repo R] [--state open|closed|merged|all] [--limit N] --json …
#   gh-rest.sh repo-view  [--repo R] --json …
#
# Stdout JSON · exit 0 ok · 1 GitHub/gh failure (stderr: the failure plus an optional `hint:` line) ·
# 2 usage error. Fields, paging and hints: references/claude-code-remote-tools.md.
exec python3 "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gh_rest.py" "$@"
