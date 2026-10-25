## MODIFIED Requirements

### Requirement: Mode resolution from pr_policy and flags

`idd-all` SHALL resolve a `(path, interaction)` tuple at Phase 0.5 from the existing `pr_policy` config field, `--pr` / `--no-pr` per-invocation flags, the `--in-chain` per-invocation flag introduced in v2.55.0+, and the cloud-session signals defined by capability `cloud-session-runtime`. The two axes MUST derive from a single source of truth — either `pr_policy`, `--in-chain`, or the cloud-session rule — to prevent duplicate config surfaces.

Resolution precedence (first match wins):

1. `--in-chain` flag → `(direct-commit, unattended)` — chain context tuple introduced for `/idd-all-chain` recursive invocations
2. `--pr` flag → `(PR, unattended)`
3. `--no-pr` flag → outside a cloud session `(direct-commit, attended)`; inside a cloud session `(PR, <cloud interaction>)` with an override notice, because a direct commit would be lost when the cloud container is reclaimed
4. Cloud session detected (`idd_is_cloud_session`) → `(PR, <cloud interaction>)`, where `<cloud interaction>` is the output of `idd_cloud_interaction` (`attended` only when the attended signal is present)
5. Fork detected (`gh repo view --json isFork` returns true) → `(PR, unattended)` regardless of config
6. `pr_policy: always` → `(PR, unattended)`
7. `pr_policy: never` → `(direct-commit, attended)`
8. `pr_policy: ask` (explicitly set) → `AskUserQuestion`; first answer locks the tuple for the invocation
9. `pr_policy` absent (no config file, or field missing) → `(PR, unattended)` — v2.40.0 backward-compat default; protects existing `/loop` automation callers from interactive hang

The resolved tuple MUST be printed as a one-line notice before any state-mutating action, e.g. `→ Path: direct-commit (attended) — pr_policy=never` or `→ Path: direct-commit (unattended) — flag=--in-chain`.

The `--in-chain` flag MUST NOT be combined with `--pr` or `--no-pr` in the same invocation. Combining them MUST cause `idd-all` to abort with a conflict error before Phase 0.3 universal pre-flight gates run.

When tuple is `(direct-commit, unattended)` resolved from `--in-chain`, `idd-all` Phase 0.5 MUST skip PR-mode branch creation (no `git checkout -b idd/<N>-<slug>`) and remain on the current branch (assumed to be a cluster branch managed by the calling `/idd-all-chain` shell). Phase 5.5 PR creation MUST be skipped entirely (the cluster PR is opened by `/idd-all-chain` Phase 3 after the chain queue completes).

Inside a cloud session, the Phase 0.6 ralph-loop gate MUST NOT degrade `(PR, unattended)` to `direct-commit`; when ralph-loop is missing it MUST remove the feature branch it just created and abort with a one-step install instruction. The `(PR, attended)` tuple does not pass through that gate. Outside a cloud session, the gate's behavior is unchanged.

#### Scenario: explicit --no-pr flag

- **GIVEN** the session is not a cloud session
- **WHEN** user invokes `idd-all #42 --no-pr`
- **THEN** `idd-all` resolves `(path, interaction) = (direct-commit, attended)`
- **AND** prints `→ Path: direct-commit (attended) — flag=--no-pr` before Phase 1

#### Scenario: pr_policy=never config

- **GIVEN** the session is not a cloud session
- **AND** `.claude/issue-driven-dev.local.json` contains `"pr_policy": "never"`
- **WHEN** user invokes `idd-all #42` with no `--pr` / `--no-pr` flag
- **THEN** `idd-all` resolves `(path, interaction) = (direct-commit, attended)`

#### Scenario: fork forces PR path

- **GIVEN** the session is not a cloud session
- **AND** the target repo is a fork (`gh repo view --json isFork` returns true)
- **AND** config sets `pr_policy: never`
- **WHEN** user invokes `idd-all #42`
- **THEN** `idd-all` resolves `(path, interaction) = (PR, unattended)` and prints a one-line override notice citing fork detection

#### Scenario: backward-compatible default (explicit --pr)

- **GIVEN** no `pr_policy` config exists and the repo is not a fork
- **WHEN** user invokes `idd-all #42 --pr`
- **THEN** `idd-all` resolves `(path, interaction) = (PR, unattended)` — identical to v2.40.0 behavior

#### Scenario: backward-compatible default (no flag, no config)

- **GIVEN** the session is not a cloud session
- **AND** no `pr_policy` config exists and the repo is not a fork
- **AND** user invokes `idd-all #42` with no `--pr` / `--no-pr` flag (the typical `/loop` automation shape)
- **WHEN** Phase 0.5 mode resolution runs
- **THEN** `idd-all` resolves `(path, interaction) = (PR, unattended)` and prints `→ Path: PR (unattended) — pr_policy absent (v2.40.0 default)` before Phase 1
- **AND** does NOT invoke `AskUserQuestion`; absent-config callers never hang waiting for interactive input

#### Scenario: explicit ask requires user choice

- **GIVEN** the session is not a cloud session
- **AND** `.claude/issue-driven-dev.local.json` contains `"pr_policy": "ask"` (explicitly set, not omitted)
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

#### Scenario: attended cloud session resolves to PR attended

- **GIVEN** `CLAUDE_CODE_REMOTE=true` and `CLAUDE_CODE_SESSION_ATTENDED=1`
- **AND** config sets `pr_policy: never`
- **WHEN** user invokes `idd-all #42` with no flag
- **THEN** `idd-all` resolves `(path, interaction) = (PR, attended)`
- **AND** prints a notice line naming the cloud session as the reason before Phase 1
- **AND** sub-skills receive no `UNATTENDED MODE` directive

#### Scenario: cloud session without attended signal resolves to PR unattended

- **GIVEN** `CLAUDE_CODE_REMOTE=true` and `CLAUDE_CODE_SESSION_ATTENDED` unset
- **WHEN** user invokes `idd-all #42` with no flag
- **THEN** `idd-all` resolves `(path, interaction) = (PR, unattended)`

#### Scenario: --no-pr is overridden in a cloud session

- **GIVEN** `CLAUDE_CODE_REMOTE=true` and `CLAUDE_CODE_SESSION_ATTENDED=1`
- **WHEN** user invokes `idd-all #42 --no-pr`
- **THEN** `idd-all` resolves `(path, interaction) = (PR, attended)`
- **AND** the notice line states that `--no-pr` was overridden because a direct commit would be lost with the cloud container

#### Scenario: missing ralph-loop in a cloud session aborts instead of degrading

- **GIVEN** `CLAUDE_CODE_REMOTE=true` and `CLAUDE_CODE_SESSION_ATTENDED` unset
- **AND** the ralph-loop plugin is not installed
- **WHEN** Phase 0.6 runs for the resolved `(PR, unattended)` tuple
- **THEN** `idd-all` removes the `idd/<N>-<slug>` branch it created, prints the one-step install instruction, and aborts
- **AND** the path is never switched to `direct-commit`

### Requirement: PR path preserves v2.40.0 behavior

When the resolved path is `PR`, `idd-all` SHALL enforce a feature branch off the default branch, push the branch, and create a PR after verify PASS. It SHALL NOT create a PR while verify reports blocking findings; in a cloud session it SHALL still push the branch in that case, including when the unattended verify-fix loop gives up, because unpushed commits are lost with the container. A missing verify verdict SHALL NOT be read as PASS: when Phase 5 cannot tell whether verify passed, `idd-all` SHALL stop before pushing and say so. A failed push SHALL stop the run before any PR is created. When the resolved tuple is `(PR, unattended)`, `idd-all` SHALL additionally pass an unattended hint to every sub-skill invocation, so that `(PR, unattended)` behaves identically to v2.40.0 and no existing caller (including `/loop` automation) observes behavioral drift. When the resolved tuple is `(PR, attended)`, `idd-all` SHALL NOT pass the unattended hint.

#### Scenario: PR path enforces feature branch

- **GIVEN** resolved path is `PR`
- **AND** the working tree is on the default branch with no uncommitted changes
- **WHEN** Phase 0.5 completes
- **THEN** `idd-all` checks out a new branch named `idd/<N>-<slug>` per `references/pr-flow.md`

#### Scenario: PR path passes unattended hint

- **GIVEN** resolved interaction is `unattended`
- **WHEN** `idd-all` invokes any sub-skill via the `Skill` tool
- **THEN** the args string includes an `UNATTENDED MODE` directive instructing the sub-skill to suppress `AskUserQuestion` calls and converge in one round

#### Scenario: PR attended path passes no unattended hint

- **GIVEN** resolved tuple is `(PR, attended)`
- **WHEN** `idd-all` invokes any sub-skill via the `Skill` tool
- **THEN** the args string contains no `UNATTENDED MODE` directive

#### Scenario: PR path opens PR after verify PASS

- **GIVEN** Phase 4 verify reports zero blocking findings
- **AND** resolved path is `PR`
- **WHEN** Phase 5 executes
- **THEN** `idd-all` runs `git push -u origin <branch>` followed by a PR creation (REST `POST repos/<R>/pulls`) with body containing `Refs #<N>` and forbidding any `Closes` / `Fixes` / `Resolves` trailer

#### Scenario: a lost verify verdict stops before the push

- **GIVEN** resolved path is `PR`
- **AND** the Phase 5 shell does not carry the verify verdict (for example, the shell state was lost between tool calls)
- **WHEN** Phase 5 executes
- **THEN** `idd-all` exits non-zero before `git push`, creates no PR, and names the missing verdict

#### Scenario: attended cloud run with blocking findings pushes but opens no PR

- **GIVEN** a cloud session resolved to `(PR, attended)`
- **AND** Phase 4 verify hands back blocking findings
- **WHEN** Phase 5 executes
- **THEN** `idd-all` pushes the branch, creates no PR, and its report says the PR was not opened
