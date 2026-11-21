## Why

Fix round 10 of issue #478 gave each issue a token, and `here` and `record` refused a token that was not the issue's with exit code 1. The skill then sent that session back to `next`. A run hands out one issue at a time, so `next` printed the same issue again: the session either went round (`here` refused it again) or read its refused token as a lost one and took the issue back with `next --take-over`. Two sessions on one issue is what the token was added to prevent (verify round 10, finding 2).

## What Changes

- `here` and `record` exit with code 4 for a token that is not the issue's. Code 4 already means "another session has this run" (a lock that is held).
- `idd-all` ends the invocation on code 4 from any command: no `record`, `stop`, `report` or `next`, and no `next --take-over`.
- The skill says that a refused token is not a lost token.
- The reason of an issue whose directory place is taken is `existing work: directory <path>` in the spec too (the helper already said so; the spec still said `kept directory`).

## Non-Goals

- Telling a session that lost its token from another session.

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `idd-all-rest`: five requirements changed (the loop of the skill, the directory of an issue, the lock, the directory left for a person, the existing-work reasons).

## Impact

- `plugins/issue-driven-dev/scripts/rest-queue.py` (`here`, `record`)
- `plugins/issue-driven-dev/skills/idd-all/SKILL.md` (rest section)
- `plugins/issue-driven-dev/scripts/tests/rest-queue/`
