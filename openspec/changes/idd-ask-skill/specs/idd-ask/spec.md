## ADDED Requirements

### Requirement: Grounded question-answering over the issue corpus

`/idd-ask <question>` SHALL answer natural-language questions grounded exclusively in the target repo's issue corpus (issues, comments, linked PRs, open and closed): it SHALL retrieve candidates via the `idd-find` search backend contract (lexical relevance, full corpus), read the top-N hits' full body and comments (N default 5, `--limit` capped at 10), and compose an answer in which the first line blockquotes the user's question and every claim carries an issue/comment citation. Content absent from the corpus SHALL NOT be asserted — an empty or insufficient retrieval SHALL be reported honestly with a suggestion to rephrase or fall through to `/idd-find`. The answer SHALL end with a `### Referenced Issues` section listing only the actually-cited issues. Source priority SHALL be closed-with-PR > open > orphaned comment, with conflicts surfaced rather than silently resolved.

#### Scenario: decision-rationale question gets a cited answer

- **WHEN** `/idd-ask "為什麼 idd-verify 的 DA 改成 sequenced spawn？"` runs against a repo whose closed issue #130 records that decision
- **THEN** the answer opens by blockquoting the question, cites #130's diagnosis/closing content for each claim, and lists #130 under `### Referenced Issues`

#### Scenario: corpus silence is reported, not filled

- **WHEN** the question matches nothing in the corpus
- **THEN** the skill says so, suggests rephrasing or `/idd-find`, and fabricates no answer

#### Scenario: open-vs-closed conflict is surfaced

- **GIVEN** a closed-with-PR issue records decision X and an open issue is trending toward Y
- **WHEN** both are retrieved for the same question
- **THEN** the answer leads with X (higher priority) and explicitly notes the open issue's in-progress divergence

### Requirement: Surfacing-only fourth member obligations

`/idd-ask` SHALL be read-only (no issue create / edit / comment / close; a bug-report-shaped question SHALL NOT trigger any lifecycle step — the answer MAY append a one-line pointer to `/idd-issue`), SHALL follow the surfacing-primitives family boilerplate (Step 0 bootstrap, config-protocol resolution with `--repo`, unattended fallback that searches without the confirm gate and records an audit line, bounded output), and SHALL be registered in the family's canonical member table in `references/surfacing-primitives.md`.

#### Scenario: bug-shaped question stays read-only

- **WHEN** `/idd-ask "idd-edit 是不是會把 body 洗掉？"` runs
- **THEN** the skill answers from history (e.g., the #150 record) without creating or modifying anything, and at most appends a `/idd-issue` pointer

#### Scenario: family table registers the fourth member

- **WHEN** `references/surfacing-primitives.md` is inspected
- **THEN** its member table lists idd-ask alongside idd-list / idd-clarify / idd-find with its distinct I/O shape
