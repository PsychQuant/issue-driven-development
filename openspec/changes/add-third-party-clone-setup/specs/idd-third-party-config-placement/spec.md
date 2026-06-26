## ADDED Requirements

### Requirement: third-party clone config-placement defaults

When a third-party clone is detected, IDD SHALL place its config locally and ignore it via `.git/info/exclude` (never via the upstream's tracked `.gitignore`), and SHALL default `pr_policy` to `never`.

#### Scenario: config ignored via .git/info/exclude

- **WHEN** IDD writes `.claude/.idd/local.json` in a third-party clone
- **THEN** the system SHALL add a marker-delimited block to `.git/info/exclude` that ignores `.claude/.idd/` (and legacy `.claude/issue-driven-dev.local.*`)
- **AND** SHALL NOT modify the repo's tracked `.gitignore`
- **AND** after the write, `git status` SHALL show no IDD-related untracked files

#### Scenario: pr_policy defaults to never

- **WHEN** IDD writes config for a third-party clone
- **THEN** the written `.claude/.idd/local.json` SHALL include `"pr_policy": "never"`
- **AND** the rationale (no push permission → local direct-commit) SHALL be surfaced once to the user

#### Scenario: tracked .gitignore is never touched

- **WHEN** IDD sets up ignore rules in a third-party clone
- **THEN** the system MUST NOT stage, modify, or commit the upstream repo's tracked `.gitignore`

### Requirement: config-protocol documents the placement matrix

`references/config-protocol.md` mechanism 5 SHALL document the third-party detection clause and the config-placement × ignore-mechanism decision matrix.

#### Scenario: config-protocol mechanism 5 names third-party detection

- **WHEN** a reader consults `config-protocol.md` mechanism 5 (git remote fallback / fork-aware detect)
- **THEN** it SHALL describe the third-party detection (hybrid owner-mismatch + push-permission), its ordering relative to fork detection, and the placement matrix
- **AND** SHALL state that third-party config defaults to `.git/info/exclude` + `pr_policy: never`

### Requirement: idd-all Phase 0.5 third-party pr_policy default

The `idd-all` Phase 0.5 mode resolution SHALL apply a `pr_policy: never` default when the working tree is a third-party clone and pr_policy is not explicitly set by config or flag.

#### Scenario: idd-all in third-party clone defaults to direct-commit

- **WHEN** `idd-all` Phase 0.5 resolves mode in a third-party clone with no explicit `pr_policy` and no `--pr`/`--no-pr` flag
- **THEN** it SHALL resolve to `(direct-commit, attended)` with reason citing third-party detection
- **AND** SHALL print the resolved-tuple notice line including the third-party reason

#### Scenario: explicit flag still overrides third-party default

- **WHEN** `idd-all` runs in a third-party clone with an explicit `--pr` flag
- **THEN** the explicit flag SHALL take precedence over the third-party `pr_policy: never` default (per existing override precedence)
