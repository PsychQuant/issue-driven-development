## ADDED Requirements

### Requirement: idd-list surfaces actionable Discussions on opt-in

`/idd-list` SHALL fetch open GitHub Discussions via `gh api graphql` when — and only when — the `--discussions` flag is passed. When the repository has Discussions disabled (`hasDiscussionsEnabled: false`), the step SHALL no-op with a single visible note and continue. A Discussion SHALL be surfaced as actionable only when its category is Q&A or Ideas, `answerChosenAt` is null, and no existing issue (open or closed) references its URL. Actionable Discussions SHALL render in a dedicated block with a suggested next action pointing at `/idd-issue --from-discussion <url>`; zero actionable SHALL print a one-line note rather than silence.

#### Scenario: repo with Discussions disabled

- **GIVEN** a target repo where `hasDiscussionsEnabled` is false
- **WHEN** the user runs `/idd-list --discussions`
- **THEN** the run prints one skip note for the Discussions step and the issues table renders unaffected

#### Scenario: answered discussion is not flagged

- **GIVEN** a Q&A Discussion whose `answerChosenAt` is non-null
- **WHEN** `/idd-list --discussions` runs
- **THEN** that Discussion does not appear in the actionable block

#### Scenario: discussion already referenced by an issue is deduped

- **GIVEN** an unanswered Q&A Discussion whose URL appears in the body of an existing closed issue
- **WHEN** `/idd-list --discussions` runs
- **THEN** that Discussion does not appear in the actionable block

### Requirement: idd-issue seeds an issue from a Discussion with verbatim provenance

`/idd-issue` SHALL accept `--from-discussion <url|number>`, fetch the Discussion via GraphQL, and seed the drafted issue body with a Provenance section containing the Discussion URL, its author, and a verbatim blockquote of the opening post. The seeded draft SHALL then flow through the unchanged idd-issue pipeline (type/priority gathering, privacy gate, egress wrapper).

#### Scenario: seeding from a Discussion URL

- **GIVEN** an unanswered Q&A Discussion reporting a bug
- **WHEN** the user runs `/idd-issue --from-discussion <its url>`
- **THEN** the drafted body contains a Provenance section with the URL and a blockquote of the opening post, and issue creation proceeds through the normal gates

### Requirement: the intake bridge never auto-files and never auto-posts

The bridge SHALL NOT create an issue from a Discussion without an explicit human invocation of `--from-discussion`, and SHALL NOT post the back-reference reply to the Discussion without explicit confirmation. Under unattended mode the reply SHALL be drafted and surfaced in the report but never posted.

#### Scenario: unattended run drafts but does not post the reply

- **GIVEN** `/idd-issue --from-discussion <url>` running under an orchestrator's UNATTENDED MODE directive
- **WHEN** the issue is created successfully
- **THEN** the back-reference reply text appears in the final report marked as not posted, and no `addDiscussionComment` mutation is executed

### Requirement: the contract and GraphQL templates live in one shared reference

The normative constraints (no-auto-file, dedup, resolution-detection) and every GraphQL query the bridge uses (hasDiscussionsEnabled probe, discussions list, single-discussion fetch) SHALL be defined once in the discussions-intake reference document; both skills SHALL cite it rather than embedding divergent copies.

#### Scenario: adding a field to the list query

- **GIVEN** a maintainer extending the discussions list query with a new field
- **WHEN** they edit the reference document's query template
- **THEN** both idd-list and idd-issue consume the change without any skill-local query text needing a parallel edit
