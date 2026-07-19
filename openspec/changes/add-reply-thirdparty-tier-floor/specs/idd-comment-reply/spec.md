## MODIFIED Requirements

### Requirement: Points-source resolution

`--points-from` is required (per the Reply comment type requirement); its *value* SHALL resolve through a three-layer chain: (1) an explicit comment URL → points are taken from that comment's blockquote / enumerated list; (2) the literal `issue-body` — or an explicit URL that yields no enumerable point list — → the points SHALL be taken from the verbatim "Original text" blockquote(s) of the issue body; (3) when neither yields points, the skill SHALL ask the user to paste the original text. The three layers describe how the required value resolves — they are NOT a default for an absent flag (an absent flag is refused at Step 2). Resolved points SHALL be reproduced verbatim in the reply; paraphrasing the counterpart's original wording SHALL NOT occur. Verbatim reproduction is nonetheless subject to the privacy-scrub gate: when a quoted point carries private / PII content, the scrub gate takes precedence over verbatim (redaction wins on conflict). Layer-3 (user-pasted) content is additionally subject to the third-party payload tier floor (see the "Layer-3 third-party payload tier floor" requirement): it SHALL NOT dispatch under the LIGHT tier, and the metadata marker SHALL record `points-from=user-pasted` so the floor is mechanically detectable.

#### Scenario: Value issue-body resolves to the issue-body blockquote

- **WHEN** `--points-from=issue-body` is given and the issue body contains an Original text blockquote
- **THEN** the points are extracted from that blockquote and quoted verbatim in the reply draft

#### Scenario: No resolvable source falls back to user input

- **WHEN** neither an explicit source nor an issue-body blockquote yields points
- **THEN** the skill asks the user to provide the original text and does not fabricate or summarize points on its own

#### Scenario: Layer-3 resolution marks the marker

- **WHEN** points are resolved from user-pasted text (layer 3)
- **THEN** the rendered metadata marker records `points-from=user-pasted`

## ADDED Requirements

### Requirement: Layer-3 third-party payload tier floor

Reply drafts whose points source is user-pasted external content (layer 3) SHALL NOT dispatch under the LIGHT scrub tier regardless of repository visibility: the minimum is WARN accompanied by an explicit user confirmation that the quoted third-party verbatim content may be pushed to the remote. In an unattended context the skill SHALL refuse to post such a reply (with an explanatory notice deferring to an attended session) rather than dispatch it unconfirmed. Layer-1 and layer-2 sources (content already present on the same repository's remote) SHALL remain governed by the repository-visibility tier default. As a deterministic backstop, `gh-egress.sh` SHALL refuse dispatch (attestation exit-code band) when the drafted body contains both the `type=reply` and `points-from=user-pasted` marker tokens while the attested level is `light`; this check matches IDD's own structured metadata marker tokens only and SHALL NOT grow into semantic content matching.

#### Scenario: Light-tier dispatch of user-pasted reply is refused mechanically

- **WHEN** a body containing both `type=reply` and `points-from=user-pasted` marker tokens is dispatched with `--scrub-attested light`
- **THEN** `gh-egress.sh` refuses in the attestation exit band and instructs re-dispatch at `warn` after explicit user confirmation

#### Scenario: Warn-tier dispatch after confirmation proceeds

- **WHEN** the same body is dispatched with `--scrub-attested warn` after the user confirmed the quoted content
- **THEN** the wrapper dispatches normally

#### Scenario: Layer-1/2 replies are unaffected

- **WHEN** a reply whose marker records `points-from=issue-body` is dispatched with `--scrub-attested light` on a private repo
- **THEN** the wrapper dispatches normally (the floor binds layer 3 only)

#### Scenario: Unattended layer-3 reply is not posted

- **WHEN** the reply pipeline runs in an unattended context and the points source resolved to user-pasted text
- **THEN** the skill refuses to post, explains the tier-floor reason, and defers to an attended session
