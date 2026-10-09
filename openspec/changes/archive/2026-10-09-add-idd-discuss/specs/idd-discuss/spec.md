## ADDED Requirements

### Requirement: Explicit topic capture with provenance
The skill SHALL preserve selected available messages, distinguish original text from AI summary, and identify source scope. Unknown attribution SHALL remain unknown. A decision SHALL cite an existing user message and SHALL NOT be inferred solely from an assistant proposal.

#### Scenario: Partial conversation and unknown model
- **WHEN** only the current visible exchange is available and the model identity is unknown
- **THEN** the record states that scope and uses unknown attribution without inventing earlier turns

### Requirement: Append-only source snapshots
The publisher SHALL create an initial discussion or append a new complete snapshot to its comments. It SHALL NOT overwrite a discussion body or existing comment. Title equality SHALL NOT identify a topic.

#### Scenario: Correction to an earlier conclusion
- **WHEN** a new source batch revises a previous conclusion
- **THEN** a new comment records the correction while preserving the original content

### Requirement: Retry and uncertain mutation handling
Stable topic and source identifiers SHALL drive deduplication. Equal source IDs with equal payloads SHALL not repeat a write; unequal payloads SHALL fail. A locally uncertain attempt SHALL be reconciled against remote state and SHALL NOT be blindly repeated. The contract SHALL disclose the lack of cross-device atomic create guarantees.

#### Scenario: Timeout after server accepted a comment
- **WHEN** the original response is lost and the same source is retried
- **THEN** an existing matching remote marker is recovered, or the publisher refuses to repeat the uncertain mutation

### Requirement: Authorised egress through existing gate
Only an explicit publish operation SHALL permit mutations. Each mutation SHALL pass the existing privacy and mention checks using its complete body and title. Disabled, locked, closed, or unwritable destinations and incomplete deduplication reads SHALL stop writes.

#### Scenario: Local path inside a supplied transcript
- **WHEN** the payload includes a literal local home path
- **THEN** the existing egress gate refuses publication before a GraphQL mutation

### Requirement: Immutable human content and bounded integration
Managed markers SHALL be checked against the current actor and specified target. The skill SHALL NOT create follow-up issues automatically; it SHALL delegate explicitly requested issue creation to the existing intake bridge.

#### Scenario: Human-authored discussion without a managed topic marker
- **WHEN** a caller tries to continue it as a managed topic
- **THEN** the operation refuses without modifying human content
