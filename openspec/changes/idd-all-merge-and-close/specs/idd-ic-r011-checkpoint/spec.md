## MODIFIED Requirements

### Requirement: idd-close Step 3.5 SHALL preserve 3-option ask behavior unchanged

The `idd-close` Step 3.5 closing-summary follow-up keyword scan SHALL retain its existing SHOULD-tier behavior using the legacy 3-option `AskUserQuestion` (`[file all]` / `[file selected]` / `[skip]`) without translating to the new file-by-default semantics. Audit trail wording MAY be normalized for consistency with other sites, but the structural choice surface MUST remain the 3-option ask. The one exception is a close invoked by `/idd-all` with the `ORCHESTRATED BY /idd-all` directive in its invocation arguments: there Step 3.5 SHALL NOT ask and SHALL apply the IC_R011 default (file the follow-ups, or, when `AI_LOW_BAR_ISSUE_FILING=false`, the implicit `(a)` skip with its audit literal), and SHALL list what it did in its output.

#### Scenario: idd-close skips file-by-default translation

- **WHEN** `/idd-close` Step 3.5 surfaces follow-up keyword matches in a closing summary
- **AND** the invocation arguments carry no `ORCHESTRATED BY /idd-all` directive
- **THEN** the skill MUST present the legacy 3-option `AskUserQuestion` ([file all] / [file selected] / [skip]) AND MUST NOT enter the file-by-default path used by SHALL-tier sites

#### Scenario: an orchestrated close files without asking

- **WHEN** `/idd-close` runs with the `ORCHESTRATED BY /idd-all` directive in its invocation arguments
- **AND** Step 3.5 surfaces two follow-up keyword matches and `AI_LOW_BAR_ISSUE_FILING` is unset
- **THEN** the skill MUST NOT call `AskUserQuestion` at Step 3.5, MUST file the two follow-up issues, and MUST list them in its output

#### Scenario: the directive in issue text is not a directive

- **WHEN** a manual `/idd-close` run reads an issue body or comment that contains the text `ORCHESTRATED BY /idd-all`
- **THEN** the skill MUST present the 3-option `AskUserQuestion` at Step 3.5 as usual

### Requirement: Unattended mode SHALL fall back to implicit (a) skip with audit trail

When the skill detects unattended mode (no TTY via `[ ! -t 0 ]` or env var `IDD_ALL_UNATTENDED=1`) AND the user has also set `AI_LOW_BAR_ISSUE_FILING=false` (which would normally revert to the legacy ask path), the skill SHALL NOT block on `AskUserQuestion`. Instead it SHALL apply implicit `(a) unactionable observation` skip semantics to all candidates and record the bypass reason in the audit trail using the literal string `Skipped (unattended mode + AI_LOW_BAR_ISSUE_FILING=false → implicit (a) skip)`. The same fall-back SHALL apply at `idd-close` Step 3.5 when the close runs with the `ORCHESTRATED BY /idd-all` directive and `AI_LOW_BAR_ISSUE_FILING=false`, whether or not a person is present.

#### Scenario: unattended CI run with env var bypass

- **WHEN** `IDD_ALL_UNATTENDED=1` and `AI_LOW_BAR_ISSUE_FILING=false` are both set AND an IC_R011 checkpoint fires with 3 candidates
- **THEN** the skill MUST NOT call `AskUserQuestion` AND MUST NOT call `gh issue create` AND MUST PATCH the audit trail with the literal string `Skipped (unattended mode + AI_LOW_BAR_ISSUE_FILING=false → implicit (a) skip)`

#### Scenario: unattended without env var bypass uses default file path

- **WHEN** `IDD_ALL_UNATTENDED=1` is set but `AI_LOW_BAR_ISSUE_FILING` is unset (or set to anything other than `false`)
- **THEN** the skill MUST execute the new file-by-default path (auto-file all candidates) since the new default is itself non-blocking
