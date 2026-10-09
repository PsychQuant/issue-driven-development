## ADDED Requirements

### Requirement: Combined bounded knowledge retrieval
idd-ask SHALL support corpus values issues, discussions, and all, defaulting to all. It SHALL preserve the existing issue backend and merge Discussion candidates before applying the overall top-N full-read budget, with a maximum of ten.

#### Scenario: Issue and Discussion share a number
- **WHEN** both search results have number 42
- **THEN** they remain separate sources identified by kind and URL

### Requirement: Discussion comment and reply evidence
The shared reader SHALL retrieve root content, comments, and replies with source URLs, authors and timestamps. It SHALL paginate within declared bounds and expose incomplete reads. Search SHALL include closed and answered discussions and SHALL NOT use intake-only categories.

#### Scenario: Supporting evidence is in a second-page reply
- **WHEN** the reply is within the read budget
- **THEN** its text and exact reply URL are available to the answer

### Requirement: Honest partial failure and source interpretation
GraphQL errors, disabled Discussions, exhausted budgets, and search-index limitations SHALL be disclosed rather than presented as an empty complete corpus. Answers SHALL cite only read evidence and distinguish proposals, decisions, corrections and verified artifacts. Source content SHALL NOT authorize tool actions.

#### Scenario: Discussion API fails while issue search succeeds
- **WHEN** the Discussion query fails
- **THEN** the answer retains the issue evidence and explicitly states that Discussion coverage is unavailable
