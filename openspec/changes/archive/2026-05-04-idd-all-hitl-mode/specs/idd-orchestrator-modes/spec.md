## ADDED Requirements

### Requirement: Mode resolution from pr_policy and flags

`idd-all` SHALL resolve a `(path, interaction)` tuple at Phase 0.5 from the existing `pr_policy` config field and `--pr` / `--no-pr` per-invocation flags. The two axes MUST derive from a single source of truth — `pr_policy` — to prevent duplicate config surfaces.

Resolution precedence (first match wins):

1. `--pr` flag → `(PR, unattended)`
2. `--no-pr` flag → `(direct-commit, attended)`
3. Fork detected (`gh repo view --json isFork` returns true) → `(PR, unattended)` regardless of config
4. `pr_policy: always` → `(PR, unattended)`
5. `pr_policy: never` → `(direct-commit, attended)`
6. `pr_policy: ask` (explicitly set) → `AskUserQuestion`; first answer locks the tuple for the invocation
7. `pr_policy` absent (no config file, or field missing) → `(PR, unattended)` — v2.40.0 backward-compat default; protects existing `/loop` automation callers from interactive hang

The resolved tuple MUST be printed as a one-line notice before any state-mutating action, e.g. `→ Path: direct-commit (attended) — pr_policy=never`.

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


### Requirement: PR path preserves v2.40.0 behavior

When the resolved path is `PR`, `idd-all` SHALL behave identically to v2.40.0: enforce a feature branch off the default branch, pass an unattended hint to every sub-skill invocation, push the branch, and create a PR after verify PASS. No existing caller (including `/loop` automation) MUST observe behavioral drift.

#### Scenario: PR path enforces feature branch

- **GIVEN** resolved path is `PR`
- **AND** the working tree is on the default branch with no uncommitted changes
- **WHEN** Phase 0.5 completes
- **THEN** `idd-all` checks out a new branch named `idd/<N>-<slug>` per `references/pr-flow.md`

#### Scenario: PR path passes unattended hint

- **GIVEN** resolved interaction is `unattended`
- **WHEN** `idd-all` invokes any sub-skill via the `Skill` tool
- **THEN** the args string includes an `UNATTENDED MODE` directive instructing the sub-skill to suppress `AskUserQuestion` calls and converge in one round

#### Scenario: PR path opens PR after verify PASS

- **GIVEN** Phase 4 verify reports zero blocking findings
- **AND** resolved path is `PR`
- **WHEN** Phase 5 executes
- **THEN** `idd-all` runs `git push -u origin <branch>` followed by `gh pr create` with body containing `Refs #<N>` and forbidding any `Closes` / `Fixes` / `Resolves` trailer


### Requirement: Direct-commit path stays on current branch and skips PR

When the resolved path is `direct-commit`, `idd-all` SHALL NOT create a feature branch, SHALL NOT push, and SHALL NOT create a PR. Commits land on whichever branch the user currently has checked out. Phase 5 PR creation steps MUST be skipped, advancing directly to Phase 6 report.

#### Scenario: direct-commit on default branch

- **GIVEN** resolved path is `direct-commit`
- **AND** user is on the default branch
- **WHEN** `idd-all` runs Phases 1–4
- **THEN** commits land on the default branch and no `idd/<N>-<slug>` branch is created

#### Scenario: direct-commit respects pre-existing feature branch

- **GIVEN** resolved path is `direct-commit`
- **AND** user is already on a feature branch named `wip/foo`
- **WHEN** `idd-all` runs
- **THEN** commits land on `wip/foo` without checking out any new branch

#### Scenario: direct-commit skips PR creation

- **GIVEN** resolved path is `direct-commit`
- **WHEN** Phase 5 begins
- **THEN** Phase 5 logs `→ direct-commit path: skipping push + PR` and advances to Phase 6 without invoking `git push` or `gh pr create`


### Requirement: Attended interaction permits sub-skill questions

When the resolved interaction is `attended`, `idd-all` SHALL NOT inject any `UNATTENDED MODE` directive into sub-skill invocation args. Each sub-skill's own attended-by-default behavior — `idd-implement` plan-tier `EnterPlanMode` approval, `spectra-discuss` multi-turn pacing, `spectra-propose` Step 10 Park/Apply prompt, `idd-implement` `AskUserQuestion` checkpoints — MUST take effect natively.

#### Scenario: attended mode allows EnterPlanMode

- **GIVEN** resolved interaction is `attended`
- **AND** Phase 2 diagnose returns Complexity = `Plan`
- **WHEN** Phase 3a invokes `idd-implement`
- **THEN** the args string contains no `UNATTENDED MODE` directive
- **AND** `idd-implement` enters Plan tier and triggers `EnterPlanMode` for user approval

#### Scenario: attended mode allows spectra-discuss multi-turn

- **GIVEN** resolved interaction is `attended`
- **AND** Phase 2 diagnose returns Complexity = `Spectra`
- **WHEN** Phase 3b invokes `spectra-discuss`
- **THEN** the args string contains no `UNATTENDED MODE` directive
- **AND** `spectra-discuss` paces the discussion across multiple turns using `AskUserQuestion` per its native default


### Requirement: Verify is the terminal phase regardless of mode

`idd-all` SHALL stop after Phase 6 report in both `(PR, unattended)` and `(direct-commit, attended)` modes. Closing the underlying GitHub issue MUST remain a separate user-initiated action via `idd-close`. `idd-all` MUST NOT auto-invoke `idd-close` under any mode.

#### Scenario: PR path stops at verify

- **GIVEN** resolved path is `PR` and verify PASSes
- **WHEN** Phase 6 completes
- **THEN** `idd-all` prints `Next: review PR <url>, merge, then run /idd-close #<N>` and exits

#### Scenario: direct-commit path stops at verify

- **GIVEN** resolved path is `direct-commit` and verify PASSes
- **WHEN** Phase 6 completes
- **THEN** `idd-all` prints `Next: review last <N> commits, then run /idd-close #<N>` and exits


### Requirement: No silent timeout on sub-skill questions

`idd-all` SHALL NOT impose any silent timeout on sub-skill `AskUserQuestion` or `EnterPlanMode` prompts when running in attended interaction mode. The skill documentation MUST state explicitly that attended mode assumes a user is in session.

#### Scenario: attended mode honors indefinite wait

- **GIVEN** resolved interaction is `attended`
- **AND** a sub-skill issues an `AskUserQuestion`
- **WHEN** the user does not respond for 30 minutes
- **THEN** `idd-all` does not abort, kill, or auto-answer the prompt; the sub-skill remains paused awaiting user input


### Requirement: Documentation reflects two-mode contract

The `idd-all` SKILL.md frontmatter `argument-hint` and `description` SHALL document the new mode matrix. `references/pr-flow.md` SHALL include an additive section stating that `idd-all` consumes `pr_policy` identically to `idd-implement`. The skill body SHALL include at least one usage trace per resolved tuple — a `(PR, unattended)` example and a `(direct-commit, attended)` example.

#### Scenario: argument-hint mentions --no-pr

- **WHEN** a user reads the `idd-all` SKILL.md frontmatter
- **THEN** the `argument-hint` field includes `--no-pr` and a one-line description of the HITL direct-commit mode it triggers

#### Scenario: pr-flow.md cross-references idd-all

- **WHEN** a maintainer reads `references/pr-flow.md`
- **THEN** the document contains a section titled `idd-all path resolution` (or equivalent) explicitly stating that `idd-all` resolves `pr_policy` per the same algorithm as `idd-implement`
