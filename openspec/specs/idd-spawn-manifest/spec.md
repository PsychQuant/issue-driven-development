# idd-spawn-manifest Specification

## Purpose

Defines the **spawn manifest** — the machine-readable, append-only, atomically-written (temp-file-rename) file at a fixed path with a versioned schema that records each *auto-emergent* spawned issue under chain context. Governs: the fixed-path + schema-version contract, the one-append-only-entry-per-spawn rule, atomic-write durability, and the requirement that all four IC_R011 sub-skill sites (`idd-diagnose` / `idd-plan` / `idd-implement` / `idd-verify`) write it conformantly — supplying the `root_id` / traversal / eligibility-flag fields that `idd-all-chain` reads to drive and bound its traversal.

## Requirements

### Requirement: Spawn manifest file SHALL exist at a fixed path with a versioned schema

When `/idd-all-chain` is active in a session, the chain shell MUST initialize a JSON file at `.claude/.idd/state/chain-spawned-issues.json` (relative to the target repo root) with this top-level shape:

```json
{
  "schema_version": 2,
  "session_id": "<uuid>",
  "root_issues": [<integer>, ...],
  "traversal": "dfs" | "bfs",
  "spawned": []
}
```

The `schema_version` field MUST be `2` for the v2 contract. Future schema breaking changes MUST increment this integer; sub-skills reading the file MUST refuse to write entries when `schema_version` does not match the value they were built against (`EXPECTED_SCHEMA_VERSION=2` for the v2 cohort).

The `session_id` field MUST be a UUID generated when the chain shell creates the file; sub-skills MUST NOT modify `session_id` after initialization.

The `root_issues` field MUST be a non-empty array of integer issue numbers (each `> 0`) corresponding to the root issues passed to `/idd-all-chain`. For single-root invocations the array contains exactly one element. The ordering of `root_issues` SHALL match the order of `#NNN` tokens parsed from the invocation (positional left-to-right). The v1 singular `root_issue: <integer>` field is removed in v2.

The `traversal` field MUST be either `"dfs"` (default when `--bfs` flag is absent) or `"bfs"` (when `--bfs` flag is present at invocation time).

The `spawned` field MUST be an array of spawn entries (initially empty).

The v1 schema (with singular `root_issue: <integer>` field, no `traversal` field, and spawn entries lacking `root_id`) is no longer supported. Manifests written with `schema_version=1` SHALL cause the helper script and chain shell to refuse to operate (fail-fast with a clear migration hint pointing to v2 documentation).

#### Scenario: chain shell initializes multi-root v2 manifest

- **WHEN** user invokes `/idd-all-chain #44 #45 #50`
- **THEN** before any sub-skill runs, the chain shell creates `.claude/.idd/state/chain-spawned-issues.json` with `schema_version=2`, a fresh UUID for `session_id`, `root_issues=[44,45,50]`, `traversal="dfs"`, and `spawned=[]`

#### Scenario: chain shell initializes single-root v2 manifest

- **WHEN** user invokes `/idd-all-chain #28`
- **THEN** the manifest is created with `schema_version=2`, `root_issues=[28]`, `traversal="dfs"`, and `spawned=[]`
- **AND** the singular `root_issue` field is absent (v1 field removed)

#### Scenario: chain shell records BFS traversal in v2 manifest

- **WHEN** user invokes `/idd-all-chain #44 #45 --bfs`
- **THEN** the manifest records `traversal="bfs"` (not `"dfs"`)

#### Scenario: v1 manifest on disk causes fail-fast

- **GIVEN** an existing v1 manifest at `.claude/.idd/state/chain-spawned-issues.json` with `schema_version=1` and singular `root_issue` field
- **WHEN** the chain shell or any sub-skill attempts to read or append to the manifest
- **THEN** the operation fails with exit status indicating schema mismatch
- **AND** the error output contains the expected schema_version (`2`) and the actual schema_version observed (`1`)
- **AND** the error output suggests deleting or migrating the v1 manifest before re-running the chain


<!-- @trace
source: multi-root-traversal-idd-all-chain
updated: 2026-05-18
code:
  - plugins/issue-driven-dev/skills/idd-verify/SKILL.md
  - plugins/issue-driven-dev/README.md
  - plugins/issue-driven-dev/references/chain-flow.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/CLAUDE.md
  - plugins/issue-driven-dev/references/spawn-manifest.md
  - plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-all-chain/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - plugins/issue-driven-dev/scripts/manifest-append.sh
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
-->

---
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
  "root_id": <integer>,
  "filed_at": "<ISO-8601 timestamp>",
  "title": "<spawned issue title>"
}
```

Required field semantics:

- `issue_number`: GitHub issue number of the spawned issue (must be `> 0`).
- `spawned_by`: One of `"idd-implement"`, `"idd-verify"`, `"idd-plan"`, `"idd-diagnose"`.
- `spawn_step`: A human-readable identifier matching the sub-skill's spawn step (e.g. `"Step 5.7 sister bug sweep"`, `"Phase 4 follow-up findings triage"`).
- `spawn_kind`: One of the five enumerated values; sub-skills MUST classify their spawn type.
- `same_file_as_root`: True only if the spawn references the same source files as the **specific root** issue this spawn descends from (not any root in the chain).
- `same_skill_as_root`: True only if the spawn references the same skill / module as the **specific root** this spawn descends from.
- `root_id`: The integer issue number of the root that owns this spawn's subtree. MUST be one of the values present in the manifest's top-level `root_issues` array. For top-level root issues themselves (depth 0), `root_id` equals the issue's own number. This field is new in v2.
- `filed_at`: ISO-8601 UTC timestamp of when the GitHub issue was created.
- `title`: The spawned issue's title (raw, no formatting).

Entries MUST be append-only — sub-skills MUST NOT modify or remove existing entries.

When a sub-skill runs under chain context, the `root_id` value MUST be derived by tracing the spawn's parent chain back to its originating root. The sub-skill MAY read the manifest to locate the parent's existing entry and inherit `root_id`, or MAY compute it from the chain shell's working environment when the chain shell explicitly passes the current `root_id` as an environment variable or argument.

#### Scenario: spawn entry records correct root_id under multi-root chain

- **GIVEN** the manifest has `root_issues=[44, 45, 50]`
- **AND** root #44 has spawned #X (depth 1, root_id=44)
- **AND** `idd-implement` Step 5.7 while processing #X spawns sister-bug #Y
- **WHEN** Step 5.7 appends the manifest entry for #Y
- **THEN** the entry has `root_id=44` (inherited from #X's parent chain)

#### Scenario: spawn entry under single-root chain has root_id equal to the lone root

- **GIVEN** the manifest has `root_issues=[28]`
- **AND** `idd-verify` Phase 4 spawns follow-up issue #41 while processing root #28
- **WHEN** Phase 4 appends the manifest entry for #41
- **THEN** the entry has `root_id=28`


<!-- @trace
source: multi-root-traversal-idd-all-chain
updated: 2026-05-18
code:
  - plugins/issue-driven-dev/skills/idd-verify/SKILL.md
  - plugins/issue-driven-dev/README.md
  - plugins/issue-driven-dev/references/chain-flow.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/CLAUDE.md
  - plugins/issue-driven-dev/references/spawn-manifest.md
  - plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-all-chain/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - plugins/issue-driven-dev/scripts/manifest-append.sh
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
-->

---
### Requirement: All four sub-skills SHALL conformantly write the manifest under chain context

The four spawning sub-skills (`idd-implement`, `idd-verify`, `idd-plan`, `idd-diagnose`) MUST detect chain context (presence of the manifest file at the fixed path AND `schema_version=2`) and MUST append a manifest entry whenever they file a follow-up issue. Sub-skills MUST NOT silently skip the manifest write.

When chain context is NOT detected (manifest file absent), sub-skills MUST behave identically to their pre-chain baseline — no manifest write attempted, existing audit-trail comments unchanged.

When the manifest file exists but `schema_version` is not `2` (for example a stale v1 manifest on disk), sub-skills MUST fail-fast with exit status indicating schema mismatch (sub-skills MUST NOT silently fall back to v1 write semantics, MUST NOT silently skip the write, and MUST NOT overwrite the file with a v2 shape).

The helper script `manifest-append.sh` SHALL accept exactly nine positional arguments. The ninth argument is `root_id` (integer `> 0`), added in v2. Sub-skills invoking `manifest-append.sh` with fewer than nine arguments SHALL cause the helper to exit with status 2 (usage error).

#### Scenario: sub-skill outside chain context skips manifest write

- **GIVEN** the manifest file does not exist at `.claude/.idd/state/chain-spawned-issues.json`
- **WHEN** `idd-implement` Step 5.7 files a sister bug
- **THEN** Step 5.7 emits its existing audit trail comment (Sister Bugs Filed section)
- **AND** does NOT attempt to write a manifest entry (no error, baseline behavior preserved)

#### Scenario: sub-skill in v2 chain context writes both manifest and audit trail with nine arguments

- **GIVEN** the manifest file exists with `schema_version=2`
- **WHEN** `idd-verify` Phase 4 follow-up triage files issue #41 while processing a spawn whose root_id is 44
- **THEN** the sub-skill invokes `manifest-append.sh` with nine positional arguments including `root_id=44` as the ninth
- **AND** the manifest gains a new entry for #41 with `root_id=44`
- **AND** the existing audit trail comment is also posted (both writes succeed)

#### Scenario: helper rejects eight-argument invocation under v2

- **GIVEN** the manifest exists with `schema_version=2`
- **WHEN** a caller invokes `manifest-append.sh` with only eight positional arguments (omitting `root_id`)
- **THEN** the helper exits with status 2
- **AND** the helper's stderr indicates the usage error and lists the expected nine arguments

#### Scenario: helper rejects v1 manifest on disk under v2 helper

- **GIVEN** a stale v1 manifest exists with `schema_version=1`
- **WHEN** any sub-skill invokes `manifest-append.sh` with nine arguments
- **THEN** the helper exits with status 1 (schema mismatch)
- **AND** the helper's stderr lists expected version `2` and actual version `1`


<!-- @trace
source: multi-root-traversal-idd-all-chain
updated: 2026-05-18
code:
  - plugins/issue-driven-dev/skills/idd-verify/SKILL.md
  - plugins/issue-driven-dev/README.md
  - plugins/issue-driven-dev/references/chain-flow.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/CLAUDE.md
  - plugins/issue-driven-dev/references/spawn-manifest.md
  - plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-all-chain/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - plugins/issue-driven-dev/scripts/manifest-append.sh
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
-->

---
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

<!-- @trace
source: add-idd-all-chain-skill
updated: 2026-05-10
code:
  - .spectra.yaml
  - .agents/skills/spectra-ingest/SKILL.md
  - plugins/issue-driven-dev/scripts/manifest-append.sh
  - plugins/issue-driven-dev/CHANGELOG.md
  - plugins/issue-driven-dev/CLAUDE.md
  - .agents/skills/spectra-archive/SKILL.md
  - .agents/skills/spectra-audit/SKILL.md
  - .agents/skills/spectra-apply/SKILL.md
  - plugins/issue-driven-dev/.claude-plugin/plugin.json
  - plugins/issue-driven-dev/references/spawn-manifest.md
  - .agents/skills/spectra-commit/SKILL.md
  - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
  - plugins/issue-driven-dev/references/usecase-routing.md
  - plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - .agents/skills/spectra-discuss/SKILL.md
  - .claude-plugin/marketplace.json
  - .agents/skills/spectra-drift/SKILL.md
  - plugins/issue-driven-dev/skills/idd-all-chain/SKILL.md
  - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - plugins/issue-driven-dev/skills/idd-verify/SKILL.md
  - plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - docs/design-patterns/default-dilemma.md
  - plugins/issue-driven-dev/references/chain-flow.md
  - .agents/skills/spectra-debug/SKILL.md
  - .agents/skills/spectra-propose/SKILL.md
  - .agents/skills/spectra-ask/SKILL.md
  - AGENTS.md
-->