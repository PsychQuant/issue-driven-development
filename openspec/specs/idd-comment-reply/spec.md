# idd-comment-reply Specification

## Purpose

TBD - created by archiving change 'add-idd-comment-reply-type'. Update Purpose after archive.

## Requirements

### Requirement: Reply comment type with per-point structure

`idd-comment` SHALL support a seventh type `--type=reply` producing a recipient-facing point-by-point reply comment. The flag `--points-from` SHALL be required for this type; invocation without it SHALL be refused by the same Step 2 validation mechanism that enforces per-type required fields for the existing six types. The rendered comment SHALL contain, for each point: (1) the original point quoted verbatim as a blockquote, (2) a description of what was changed and where (file / section / theorem or symbol reference), (3) an anchor to the evidencing commit, PR, or merge SHA, and (4) a per-point status. The comment SHALL end with an overall state line (merged SHA, sync status, next step) and a metadata marker `<!-- idd:comment type=reply ... -->` recording the points source and whether calibration ran.

#### Scenario: Missing required flag is refused

- **WHEN** `/idd-comment #N --type=reply` is invoked without `--points-from`
- **THEN** validation refuses the invocation before any egress, naming `--points-from` as the missing required field

#### Scenario: Per-point rendering

- **WHEN** a reply is drafted for an issue whose review contains 3 points and 2 of them were addressed by merged commits
- **THEN** the drafted comment contains 3 verbatim blockquotes in the original order, each followed by its handling description and anchor, with the 2 evidenced points marked resolved and the third stated as open


<!-- @trace
source: add-idd-comment-reply-type
updated: 2026-07-19
code:
  - .wiki-last-sync
  - plugins/issue-driven-dev/scripts/.impeccable/hook.cache.json
-->

---
### Requirement: Points-source resolution

`--points-from` is required (per the Reply comment type requirement); its *value* SHALL resolve through a three-layer chain: (1) an explicit comment URL → points are taken from that comment's blockquote / enumerated list; (2) the literal `issue-body` — or an explicit URL that yields no enumerable point list — → the points SHALL be taken from the verbatim "Original text" blockquote(s) of the issue body; (3) when neither yields points, the skill SHALL ask the user to paste the original text. The three layers describe how the required value resolves — they are NOT a default for an absent flag (an absent flag is refused at Step 2). Resolved points SHALL be reproduced verbatim in the reply; paraphrasing the counterpart's original wording SHALL NOT occur. Verbatim reproduction is nonetheless subject to the privacy-scrub gate: when a quoted point carries private / PII content, the scrub gate takes precedence over verbatim (redaction wins on conflict).

#### Scenario: Value issue-body resolves to the issue-body blockquote

- **WHEN** `--points-from=issue-body` is given and the issue body contains an Original text blockquote
- **THEN** the points are extracted from that blockquote and quoted verbatim in the reply draft

#### Scenario: No resolvable source falls back to user input

- **WHEN** neither an explicit source nor an issue-body blockquote yields points
- **THEN** the skill asks the user to provide the original text and does not fabricate or summarize points on its own


<!-- @trace
source: add-idd-comment-reply-type
updated: 2026-07-19
code:
  - .wiki-last-sync
  - plugins/issue-driven-dev/scripts/.impeccable/hook.cache.json
-->

---
### Requirement: Verify-before-claim gate

Before the draft claims any point as resolved, the skill SHALL verify supporting evidence exists — a commit found via `git log --grep "#N"`, a merged PR, or an equivalent artifact reference. Points without verified evidence SHALL be stated as open or pending in the reply; the draft SHALL NOT assert completion for a point whose evidence was not found.

#### Scenario: Unevidenced point stays honest

- **WHEN** a point has no matching commit or merged PR at draft time
- **THEN** the reply renders that point with an open / pending status instead of claiming it resolved


<!-- @trace
source: add-idd-comment-reply-type
updated: 2026-07-19
code:
  - .wiki-last-sync
  - plugins/issue-driven-dev/scripts/.impeccable/hook.cache.json
-->

---
### Requirement: Perspective-writer soft integration with graceful degrade

The reply drafting flow SHALL probe for the `perspective-writer` plugin via `check-plugin-presence.sh perspective-writer perspective-writer`. When present, the anchored draft SHALL be passed through the `perspective-writer:perspective-writer` skill for voice and recipient calibration, forwarding the resolved `--mention` login and the path of the target repo's `.claude/rules/correspondence-<person>.md` when that file exists. When absent, the skill SHALL print a single notice containing the two install commands (`claude plugin marketplace add PsychQuant/perspective-writer` and `claude plugin install perspective-writer@perspective-writer`) and SHALL proceed to post the uncalibrated draft. The plugin manifest SHALL NOT declare an install-time dependency on perspective-writer.

#### Scenario: Plugin absent degrades gracefully

- **WHEN** the reply flow runs on a machine without the perspective-writer plugin
- **THEN** the notice with both install commands is printed and the structurally complete draft is still posted

#### Scenario: Plugin present triggers calibration

- **WHEN** the perspective-writer plugin is present in the plugin cache
- **THEN** the draft is calibrated before egress and the metadata marker records that calibration ran


<!-- @trace
source: add-idd-comment-reply-type
updated: 2026-07-19
code:
  - .wiki-last-sync
  - plugins/issue-driven-dev/scripts/.impeccable/hook.cache.json
-->

---
### Requirement: Anchoring precedes calibration

The drafting flow SHALL complete referent anchoring — verbatim quotes assembled, verify-before-claim executed, SHAs and file / symbol references fixed — before any calibration step runs. Calibration SHALL NOT alter anchored facts: commit SHAs, file / theorem references, and the verbatim quoted text of the counterpart's points.

#### Scenario: Calibration preserves anchors

- **WHEN** calibration rewrites the tone of a per-point handling description
- **THEN** the point's verbatim blockquote, its anchor SHA, and its file / symbol references remain byte-identical to the pre-calibration draft


<!-- @trace
source: add-idd-comment-reply-type
updated: 2026-07-19
code:
  - .wiki-last-sync
  - plugins/issue-driven-dev/scripts/.impeccable/hook.cache.json
-->

---
### Requirement: Additive audit posture and egress discipline

A reply comment SHALL be additive to existing audit-facing outputs — it SHALL NOT replace closing summaries, verify reports, or any of the six existing comment types. Reply egress SHALL dispatch through the `gh-egress.sh` choke-point with scrub attestation, and with mention attestation whenever the reply carries `@` mentions.

#### Scenario: Reply does not displace the closing summary

- **WHEN** an issue is closed after a reply comment was posted
- **THEN** the closing flow still requires its own closing summary; the reply is not accepted as a substitute

#### Scenario: Egress goes through the choke-point

- **WHEN** a reply draft is dispatched to GitHub
- **THEN** the dispatch command is `gh-egress.sh comment` with `--scrub-attested`, never a raw `gh issue comment`

<!-- @trace
source: add-idd-comment-reply-type
updated: 2026-07-19
code:
  - .wiki-last-sync
  - plugins/issue-driven-dev/scripts/.impeccable/hook.cache.json
-->