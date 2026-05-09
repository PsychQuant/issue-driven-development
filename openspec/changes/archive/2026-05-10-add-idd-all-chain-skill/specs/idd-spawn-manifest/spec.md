## ADDED Requirements

### Requirement: Spawn manifest file SHALL exist at a fixed path with a versioned schema

When `/idd-all-chain` is active in a session, the chain shell MUST initialize a JSON file at `.claude/.idd/state/chain-spawned-issues.json` (relative to the target repo root) with this top-level shape:

```json
{
  "schema_version": 1,
  "session_id": "<uuid>",
  "root_issue": <integer>,
  "spawned": []
}
```

The `schema_version` field MUST be `1` for the v1 contract. Future schema breaking changes MUST increment this integer; sub-skills reading the file MUST refuse to write entries when `schema_version` does not match the value they were built against.

The `session_id` field MUST be a UUID generated when the chain shell creates the file; sub-skills MUST NOT modify `session_id` after initialization.

The `root_issue` field MUST be the integer issue number passed to `/idd-all-chain`.

The `spawned` field MUST be an array of spawn entries (initially empty).

#### Scenario: chain shell initializes manifest at startup

- **WHEN** user invokes `/idd-all-chain #28`
- **THEN** before any sub-skill runs, the chain shell creates `.claude/.idd/state/chain-spawned-issues.json` with `schema_version=1`, a fresh UUID for `session_id`, `root_issue=28`, and `spawned=[]`

### Requirement: Each spawned issue SHALL produce one append-only entry in the manifest

When any of the four sub-skills (`idd-implement` / `idd-verify` / `idd-plan` / `idd-diagnose`) files a follow-up issue during chain context, the sub-skill MUST append exactly one entry to the manifest's `spawned` array. The entry MUST include all required fields:

```json
{
  "issue_number": <integer>,
  "spawned_by": "<sub-skill name>",
  "spawn_step": "<step identifier per sub-skill>",
  "spawn_kind": "<one of: sister-bug | follow-up-finding | tangential | sister-concern | upstream-tracking>",
  "same_file_as_root": <boolean>,
  "same_skill_as_root": <boolean>,
  "filed_at": "<ISO-8601 timestamp>",
  "title": "<spawned issue title>"
}
```

Required field semantics:
- `issue_number`: GitHub issue number of the spawned issue (must be `> 0`).
- `spawned_by`: One of `"idd-implement"`, `"idd-verify"`, `"idd-plan"`, `"idd-diagnose"`.
- `spawn_step`: A human-readable identifier matching the sub-skill's spawn step (e.g. `"Step 5.7 sister bug sweep"`, `"Phase 4 follow-up findings triage"`).
- `spawn_kind`: One of the five enumerated values; sub-skills MUST classify their spawn type.
- `same_file_as_root`: True only if the spawn references the same source files as the root issue's primary scope.
- `same_skill_as_root`: True only if the spawn references the same skill / module as the root issue.
- `filed_at`: ISO-8601 UTC timestamp of when the GitHub issue was created.
- `title`: The spawned issue's title (raw, no formatting).

Entries MUST be append-only — sub-skills MUST NOT modify or remove existing entries.

#### Scenario: idd-implement Step 5.7 appends sister-bug entry

- **GIVEN** chain context is active and #28 is the root
- **AND** `idd-implement` Step 5.7 sister bug sweep files issue #34
- **WHEN** Step 5.7 completes the `gh issue create` call
- **THEN** the manifest's `spawned` array gains a new entry with `issue_number=34`, `spawned_by="idd-implement"`, `spawn_step="Step 5.7 sister bug sweep"`, `spawn_kind="sister-bug"`, `same_skill_as_root=true`, valid `filed_at`, and the issue title

#### Scenario: idd-diagnose Step 3.6 appends sister-concern entry

- **GIVEN** chain context is active
- **AND** `idd-diagnose` Step 3.6 sister concern surfacing files issue #29
- **WHEN** Step 3.6 completes the `gh issue create` call
- **THEN** the manifest gains an entry with `issue_number=29`, `spawned_by="idd-diagnose"`, `spawn_kind="sister-concern"` (or `"upstream-tracking"` if tracking-only)

### Requirement: All four sub-skills SHALL conformantly write the manifest under chain context

The four spawning sub-skills (`idd-implement`, `idd-verify`, `idd-plan`, `idd-diagnose`) MUST detect chain context (presence of the manifest file at the fixed path AND `schema_version=1`) and MUST append a manifest entry whenever they file a follow-up issue. Sub-skills MUST NOT silently skip the manifest write.

When chain context is NOT detected (manifest file absent), sub-skills MUST behave identically to their pre-chain baseline — no manifest write attempted, existing audit-trail comments unchanged.

#### Scenario: sub-skill outside chain context skips manifest write

- **GIVEN** the manifest file does not exist at `.claude/.idd/state/chain-spawned-issues.json`
- **WHEN** `idd-implement` Step 5.7 files a sister bug
- **THEN** Step 5.7 emits its existing audit trail comment (Sister Bugs Filed section)
- **AND** does NOT attempt to write a manifest entry (no error, baseline behavior preserved)

#### Scenario: sub-skill in chain context writes both manifest and audit trail

- **GIVEN** the manifest file exists with `schema_version=1`
- **WHEN** `idd-verify` Phase 4 follow-up triage files issue #41
- **THEN** the manifest gains a new entry for #41
- **AND** the existing audit trail comment is also posted (both writes succeed)

### Requirement: Manifest writes SHALL be atomic via temp-file rename

To prevent partial writes from concurrent or interrupted sub-skill invocations, manifest updates MUST follow the read-modify-write pattern using atomic file replacement:

1. Read current manifest content
2. Parse JSON, append entry to `spawned` array
3. Write updated content to a temporary file in the same directory (e.g. `chain-spawned-issues.json.tmp.<pid>`)
4. Atomically rename the temp file over the original (`mv` or `os.rename`)

Sub-skills MUST NOT use direct in-place writes (`>` redirection or simple file overwrites) that risk truncation on interrupt.

#### Scenario: write completes atomically

- **GIVEN** manifest contains 2 entries
- **WHEN** sub-skill appends entry 3 via temp-file rename
- **THEN** between any two filesystem snapshots, the manifest file content is either the 2-entry version or the 3-entry version (never a truncated or partial-write state)
