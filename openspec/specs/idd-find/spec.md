# idd-find Specification

## Purpose

TBD - created by archiving change 'idd-find-skill'. Update Purpose after archive.

## Requirements

### Requirement: Surfacing-only semantic lookup across the full issue corpus

`/idd-find <query>` SHALL search the target repo's **open and closed** issues with GitHub search relevance ranking and render ranked hits, each with state, IDD phase (open issues, parsed from the body `**Phase**:` line), an open-PR reference overlay when one exists, and Closing-Summary presence for closed issues. The skill SHALL be surfacing-only: it SHALL NOT create, edit, close, or comment on any issue, and SHALL be runnable standalone with no in-flight phase context. The v1 backend is GitHub search relevance; the skill SHALL disclose the cross-phrasing limitation (no embedding semantics) in its output rather than implying semantic recall it does not have.

#### Scenario: query surfaces related closed work

- **WHEN** `/idd-find "comment surgery escape"` runs against a repo whose closed issue #150 body matches
- **THEN** the output lists #150 with its closed state and notes whether a Closing Summary exists, ranked by GitHub relevance

#### Scenario: open hit carries phase and PR overlay

- **WHEN** a hit is an open issue whose body says `**Phase**: implemented` and an open PR references it
- **THEN** the hit row shows `implemented` and `→ PR #M`

#### Scenario: read-only guarantee

- **WHEN** `/idd-find` completes any invocation
- **THEN** no issue, comment, label, or body has been created or modified

#### Scenario: empty result degrades honestly

- **WHEN** the query matches nothing
- **THEN** the skill prints an empty-result note suggesting broader phrasing, and does not fall back to fabricated matches


<!-- @trace
source: idd-find-skill
updated: 2026-07-17
code:
  - plugins/issue-driven-dev/scripts/.impeccable/hook.cache.json
  - plugins/issue-driven-dev/skills/idd-verify/.impeccable/hook.cache.json
  - .wiki-last-sync
-->

---
### Requirement: Division of labor against idd-list is preserved

`/idd-find` SHALL accept a free-text query (with `--repo` and `--limit` modifiers) and SHALL NOT accept phase/label/state filter flags; structural triage remains `idd-list`'s surface. The skill's output SHALL point users needing full cluster/triage views to `idd-list`.

#### Scenario: filter flags are rejected

- **WHEN** `/idd-find "cache bug" --state open` is invoked
- **THEN** the skill aborts with usage guidance naming `idd-list` as the filtering surface

<!-- @trace
source: idd-find-skill
updated: 2026-07-17
code:
  - plugins/issue-driven-dev/scripts/.impeccable/hook.cache.json
  - plugins/issue-driven-dev/skills/idd-verify/.impeccable/hook.cache.json
  - .wiki-last-sync
-->