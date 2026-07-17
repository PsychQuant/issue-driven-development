## ADDED Requirements

### Requirement: Composable verification profiles selectable at the skill layer

`idd-verify` SHALL accept a `--profile <name>` flag selecting a verification profile — a four-tuple of lens set, devil's-advocate focus, default input source, and freshness mechanism — with built-in profiles `code` (default), `prose`, and `academic` defined in `references/verify-profiles.md` as the single source of truth. When `--profile` is absent or `code`, behavior SHALL be byte-identical to the pre-profile skill (lens texts, input auto-detection, and the git diff-freshness gate unchanged). An unknown profile name (neither built-in nor config-defined) SHALL abort with the list of available profiles rather than silently falling back. Repo-local custom profiles MAY be registered under the `verify_profiles` config field; a custom profile whose name collides with a built-in SHALL be ignored with a warning (built-in wins).

#### Scenario: default invocation is unchanged

- **WHEN** `idd-verify #42` runs with no `--profile` flag
- **THEN** the ensemble uses the existing requirements/logic/security/regression lenses and git input auto-detection, byte-identical to pre-profile behavior

#### Scenario: prose profile verifies a document without a git worktree

- **WHEN** `idd-verify #42 --profile prose --file report.md` runs in a non-git directory
- **THEN** the ensemble runs the prose lens set (factual-accuracy-vs-source, format compliance, PII/PHI leak, citation support) against the file content, and the master comment posts to the config-resolved repo's issue

#### Scenario: unknown profile fails loud

- **WHEN** `idd-verify #42 --profile porse` runs and no such profile exists
- **THEN** the skill aborts listing available profiles; no ensemble is dispatched

#### Scenario: custom profile cannot shadow a built-in

- **GIVEN** config `verify_profiles` defines a profile named `code`
- **WHEN** `idd-verify #42` resolves profiles
- **THEN** the built-in `code` profile wins and a warning names the ignored config entry

### Requirement: Non-git input sources join input-source resolution

`idd-verify` SHALL accept `--file <path>` and `--dir <path>` as input sources parallel to `--pr` / `--commits` / `--branch` / `--since`, mutually exclusive with them (combining SHALL abort with usage). Profiles whose default input source is `file` SHALL require `--file` or `--dir` and SHALL NOT fall back to git detection. File-mode runs SHALL NOT perform git checkout or branch restore.

#### Scenario: mixed input sources are rejected

- **WHEN** `idd-verify #42 --file report.md --pr 123` is invoked
- **THEN** the skill aborts with a usage error naming the mutual exclusion

#### Scenario: prose profile without an input source aborts

- **WHEN** `idd-verify #42 --profile prose` is invoked with no `--file` / `--dir`
- **THEN** the skill aborts asking for an input source instead of falling back to git diff

### Requirement: File-input freshness gate equivalent to the diff-freshness gate

For `--file` / `--dir` input, `idd-verify` SHALL snapshot the SHA-256 of every input file before dispatching the ensemble and SHALL re-hash before posting the aggregate verdict; any mismatch — including added or removed files under `--dir` — SHALL refuse the verdict with a stale-snapshot message and a re-run instruction. The gate SHALL NOT be silently exempted for non-git inputs.

#### Scenario: input mutated mid-verify refuses the verdict

- **GIVEN** an ensemble dispatched over `--file report.md`
- **WHEN** `report.md` changes before the aggregate verdict posts
- **THEN** the skill refuses to post, reports the hash mismatch, and instructs a re-run
