## MODIFIED Requirements

### Requirement: Mode resolution from pr_policy and flags

`idd-all` SHALL resolve a `(path, interaction)` tuple at Phase 0.5 from the existing `pr_policy` config field, `--pr` / `--no-pr` per-invocation flags, and the new `--in-chain` per-invocation flag introduced in v2.55.0+. The two axes MUST derive from a single source of truth — either `pr_policy` or `--in-chain` — to prevent duplicate config surfaces.

Resolution precedence (first match wins):

1. `--in-chain` flag → `(direct-commit, unattended)` — chain context tuple introduced for `/idd-all-chain` recursive invocations
2. `--pr` flag → `(PR, unattended)`
3. `--no-pr` flag → `(direct-commit, attended)`
4. Fork detected (`gh repo view --json isFork` returns true) → `(PR, unattended)` regardless of config
5. `pr_policy: always` → `(PR, unattended)`
6. `pr_policy: never` → `(direct-commit, attended)`
7. `pr_policy: ask` (explicitly set) → `AskUserQuestion`; first answer locks the tuple for the invocation
8. `pr_policy` absent (no config file, or field missing) → `(PR, unattended)` — v2.40.0 backward-compat default; protects existing `/loop` automation callers from interactive hang

The resolved tuple MUST be printed as a one-line notice before any state-mutating action, e.g. `→ Path: direct-commit (attended) — pr_policy=never` or `→ Path: direct-commit (unattended) — flag=--in-chain`.

The `--in-chain` flag MUST NOT be combined with `--pr` or `--no-pr` in the same invocation. Combining them MUST cause `idd-all` to abort with a conflict error before Phase 0.3 universal pre-flight gates run.

When tuple is `(direct-commit, unattended)` resolved from `--in-chain`, `idd-all` Phase 0.5 MUST skip PR-mode branch creation (no `git checkout -b idd/<N>-<slug>`) and remain on the current branch (assumed to be a cluster branch managed by the calling `/idd-all-chain` shell). Phase 5.5 PR creation MUST be skipped entirely (the cluster PR is opened by `/idd-all-chain` Phase 3 after the chain queue completes).

#### Scenario: explicit --no-pr flag

- **WHEN** user invokes `idd-all #42 --no-pr`
- **THEN** `idd-all` resolves `(path, interaction) = (direct-commit, attended)`
- **AND** prints `→ Path: direct-commit (attended) — flag=--no-pr` before Phase 1

#### Scenario: pr_policy=never config

- **GIVEN** `.claude/issue-driven-dev.local.json` contains `"pr_policy": "never"`
- **WHEN** user invokes `idd-all #42` with no `--pr` / `--no-pr` flag
- **THEN** `idd-all` resolves `(path, interaction) = (direct-commit, attended)`

#### Scenario: fork forces PR path

- **GIVEN** the target repo is a fork (`gh repo view --json isFork` returns true)
- **AND** config sets `pr_policy: never`
- **WHEN** user invokes `idd-all #42`
- **THEN** `idd-all` resolves `(path, interaction) = (PR, unattended)` and prints a one-line override notice citing fork detection

#### Scenario: backward-compatible default (explicit --pr)

- **GIVEN** no `pr_policy` config exists and the repo is not a fork
- **WHEN** user invokes `idd-all #42 --pr`
- **THEN** `idd-all` resolves `(path, interaction) = (PR, unattended)` — identical to v2.40.0 behavior

#### Scenario: backward-compatible default (no flag, no config)

- **GIVEN** no `pr_policy` config exists and the repo is not a fork
- **AND** user invokes `idd-all #42` with no `--pr` / `--no-pr` flag (the typical `/loop` automation shape)
- **WHEN** Phase 0.5 mode resolution runs
- **THEN** `idd-all` resolves `(path, interaction) = (PR, unattended)` and prints `→ Path: PR (unattended) — pr_policy absent (v2.40.0 default)` before Phase 1
- **AND** does NOT invoke `AskUserQuestion`; absent-config callers never hang waiting for interactive input

#### Scenario: explicit ask requires user choice

- **GIVEN** `.claude/issue-driven-dev.local.json` contains `"pr_policy": "ask"` (explicitly set, not omitted)
- **AND** user invokes `idd-all #42` with no `--pr` / `--no-pr` flag
- **AND** the repo is not a fork
- **WHEN** Phase 0.5 mode resolution runs
- **THEN** `idd-all` invokes the `AskUserQuestion` Claude tool with two options (PR vs direct-commit)
- **AND** the first answer locks the tuple for the invocation

#### Scenario: in-chain flag resolves to chain-context tuple

- **GIVEN** user has a cluster branch `idd/chain-28-foo` checked out (e.g. from `/idd-all-chain` Phase 0)
- **WHEN** the chain shell invokes `idd-all #34 --in-chain`
- **THEN** `idd-all` resolves `(path, interaction) = (direct-commit, unattended)`
- **AND** prints `→ Path: direct-commit (unattended) — flag=--in-chain` before Phase 1
- **AND** Phase 0.5 PR-mode branch creation is skipped; the invocation remains on `idd/chain-28-foo`
- **AND** sub-skills receive an `UNATTENDED MODE` directive suppressing `AskUserQuestion`
- **AND** Phase 5.5 PR creation is skipped (the cluster PR is opened later by `/idd-all-chain`)

#### Scenario: in-chain flag conflicts with --pr or --no-pr

- **GIVEN** any combination such as `idd-all #34 --in-chain --pr` or `idd-all #34 --in-chain --no-pr`
- **WHEN** Phase 0.2 argument parsing runs
- **THEN** `idd-all` aborts with a conflict error message naming both flags and instructing the user to pick exactly one
- **AND** does NOT proceed to Phase 0.3 universal pre-flight gates
