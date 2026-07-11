## Why

GitHub Discussions are a real intake channel that IDD is completely blind to. On 2026-07-04, `/idd-list` on `PsychQuant/che-ical-mcp` reported a clean backlog (0 open issues) while a real permission-bug report — with the maintainer's diagnosis and the reporter's "it's fixed" confirmation — had lived its entire lifecycle inside Discussion 105. Discussions have no REST API, so `gh issue list` never sees them; every IDD intake surface (`/idd-list` triage, `/idd-issue` filing) is bound to the Issues tab only. (#221)

## What Changes

- `/idd-list` gains an **opt-in** `--discussions` flag: fetch open Discussions via `gh api graphql`, no-op gracefully when the repo has Discussions disabled, filter to actionable ones (Q&A / Ideas category, unanswered via `answerChosenAt: null`, not already referenced by an existing issue), and render them in a dedicated block with a suggested next action. Opt-in keeps the default invocation latency- and noise-free.
- `/idd-issue` gains `--from-discussion <url|number>`: seed the issue body from the Discussion (provenance section with URL + verbatim blockquote of the opening post), and after the issue exists, post a back-reference reply in the Discussion — **draft-and-confirm only**; under unattended mode the reply is drafted but never posted (surfaced in the report instead).
- New reference `plugins/issue-driven-dev/references/discussions-intake.md` holds the normative contract (no-auto-file / dedup / resolution-detection) plus the GraphQL query templates both skills share.
- **Hard constraint carried from the motivating case: the tool never auto-files.** Discussion 105 was already resolved when it was discovered — mechanical filing would have created a noise issue. The bridge surfaces; the human judges.

## Non-Goals

- **Latest-comment sentiment analysis** for resolution detection — `answerChosenAt` is the honest mechanical boundary; reading "everything is fixed, thank you" is human judgment (diagnosis Residue, #221).
- **Auto-filing issues from Discussions** — rejected by design (see the che-ical-mcp 105 case).
- **Always-on Discussions fetch in idd-list** — opt-in flag only; no config key in v1 (a config key can be added later if the flag proves sticky).
- **Discussions write-path beyond the single back-reference reply** (no answering, no labeling, no closing Discussions).

## Capabilities

### New Capabilities

- `discussions-intake`: the Discussions→IDD intake bridge contract — idd-list surfacing (opt-in, filtered, deduped), idd-issue seeding with provenance, the no-auto-file / dedup / resolution-detection constraints, and the shared GraphQL templates.

### Modified Capabilities

(none — idd-list and idd-issue behavior extensions are additive flags; no existing spec's normative clauses change)

## Impact

- Affected specs: new `discussions-intake`
- Affected code:
  - New: plugins/issue-driven-dev/references/discussions-intake.md, plugins/issue-driven-dev/scripts/tests/discussions-intake/test.sh
  - Modified: plugins/issue-driven-dev/skills/idd-list/SKILL.md, plugins/issue-driven-dev/skills/idd-issue/SKILL.md, plugins/issue-driven-dev/references/usecase-routing.md, plugins/issue-driven-dev/README.md
  - Removed: (none)
