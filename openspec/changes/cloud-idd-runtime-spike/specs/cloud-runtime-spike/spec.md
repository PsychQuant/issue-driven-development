## Purpose

Defines how candidate cloud runtimes for running a full IDD lifecycle are evaluated before `/idd-all api` is built: the fixed evaluation criteria, the split between the flow kept in the IDD repository and the secrets kept in a deployer's own repository, the isolation and credential rules for spike runs, and the required contents of the decision record that selects a runtime.

## ADDED Requirements

### Requirement: Every candidate runtime is evaluated against criteria C1 to C8

The spike SHALL record, for each of the two candidate runtimes (Claude Managed Agents; the Claude Agent SDK running on GitHub Actions), one result for each of these criteria: C1 plugin loading, C2 GitHub writes, C3 trigger by a single API call, C4 billing against Max-subscriber API credits, C5 cost and duration of one end-to-end run, C6 tool availability, C7 degraded verify, and C8 deployability by following the deployment guide alone. Each result MUST be one of `pass`, `fail`, `partial`, or `not measured`, and every `pass`, `fail`, or `partial` MUST carry evidence: verbatim output, a URL, a session or workflow run identifier, or a file listing. A result without evidence SHALL be recorded as `not measured`, never as `pass`.

#### Scenario: A probe ran but its output was not captured

- **WHEN** the C2 probe for Managed Agents opened a pull request but the response was not saved
- **THEN** the C2 cell for Managed Agents is recorded as `not measured`, with a note that the evidence was lost

#### Scenario: The Agent SDK is refused by the credits-only organization

- **WHEN** the C4 probe for the Agent SDK route returns the error `Credit balance too low`
- **THEN** C4 for that route is recorded as `fail` with the verbatim error, the remaining Agent SDK probes are not run, and their cells are recorded as `not measured (stopped after C4 fail)`

### Requirement: The flow lives in the IDD repository and secrets stay in the deployer's repository

The cloud flow SHALL live in the IDD repository: a reusable workflow at `.github/workflows/idd-cloud-run.yml` triggered only by `workflow_call`, the Agent SDK runner and the Managed Agents launcher under `plugins/issue-driven-dev/cloud/`, a caller workflow template, and a deployment guide. The reusable workflow SHALL receive the Anthropic API key only as a `workflow_call` secret named `ANTHROPIC_API_KEY` and MUST NOT declare or read any other secret. The IDD repository MUST NOT store an API key. A deployer's repository SHALL need only its own `ANTHROPIC_API_KEY` secret and a copy of the caller workflow template; it MUST NOT need a fork of IDD or a copy of any other IDD file.

#### Scenario: Deploying to the sandbox repository

- **WHEN** the Agent SDK route is deployed to `PsychQuant/idd-cloud-sandbox` by following the deployment guide
- **THEN** the files added to the sandbox are exactly one caller workflow under `.github/workflows/`, the sandbox holds the `ANTHROPIC_API_KEY` secret, and the caller invokes `PsychQuant/issue-driven-development/.github/workflows/idd-cloud-run.yml`

#### Scenario: The reusable workflow does not run on IDD's own events

- **WHEN** a commit is pushed to `PsychQuant/issue-driven-development` or a pull request is opened there
- **THEN** `idd-cloud-run.yml` does not start, because its only trigger is `workflow_call`

### Requirement: Spike writes target only the dedicated scratch repository

All GitHub write operations performed by spike runs, including issue comments, branch pushes, pull request creation, and pull request merges, SHALL target the private repository `PsychQuant/idd-cloud-sandbox`. Spike runs MUST NOT create issues, comments, branches, pull requests, or merges in `PsychQuant/issue-driven-development`; that repository SHALL change only through the ordinary commits that add the cloud flow.

#### Scenario: End-to-end run on the seed issue

- **WHEN** the end-to-end probe runs `/issue-driven-dev:idd-all` against the sandbox seed issue
- **THEN** every comment, branch, and pull request it creates exists in `PsychQuant/idd-cloud-sandbox`, and `PsychQuant/issue-driven-development` shows no new issue, comment, branch, or pull request from the run

#### Scenario: A probe is pointed at the IDD repository

- **WHEN** a probe that writes to GitHub is configured with `PsychQuant/issue-driven-development` as its target
- **THEN** the probe does not run and the spike reports that the target must be the sandbox repository

### Requirement: Credentials never appear in repository files or output

API keys and GitHub tokens SHALL be read at run time from the macOS keychain or from the platform's secret store, and MUST NOT be written to tracked files, passed as command-line arguments, or printed. The Agent SDK runner and the Managed Agents launcher SHALL accept `--dry-run`, which prints the requests they would send with every secret replaced by `***` and sends nothing. User-supplied prompt text SHALL reach shell steps of the reusable workflow only through environment variables, never by direct `${{ }}` substitution into a `run:` command.

#### Scenario: Dry run masks a secret

- **WHEN** a test sets the API key to a known sentinel string and runs the Agent SDK runner or the Managed Agents launcher with `--dry-run`
- **THEN** the output contains `***`, does not contain the sentinel string, and no network request is made

#### Scenario: The API key is missing

- **WHEN** the runner or the launcher runs without `--dry-run` and no API key is available
- **THEN** it exits with a non-zero status, names the missing variable or keychain entry on stderr, and sends no request

#### Scenario: Prompt text is not interpolated into a shell command

- **WHEN** a test scans `.github/workflows/idd-cloud-run.yml`
- **THEN** no `run:` block contains `${{ inputs.prompt }}`, and the prompt reaches the runner through an environment variable

### Requirement: Cloud verify runs Claude-only and declares the missing Codex leg

When verify runs inside a spike run, it SHALL use Claude reviewers only, and the verify report MUST state that the Codex cross-model reviewer was not run. C7 SHALL be recorded as `fail` when the report omits that statement, even if the verify itself completed.

#### Scenario: Verify completes without declaring the missing reviewer

- **WHEN** a cloud verify finishes and its report does not mention that the Codex reviewer was absent
- **THEN** C7 for that runtime is recorded as `fail` with the report link as evidence

### Requirement: The decision record selects one runtime or none with reasons

The spike SHALL end with a findings record containing the C1 to C8 matrix for both runtimes, the measured cost and duration of one end-to-end run for each runtime that reached that stage, and a decision that either names the runtime selected for `/idd-all api` or states that neither is selected. The decision MUST cite the matrix cells it rests on, and a summary of the decision SHALL be posted to issue #400.

#### Scenario: Neither runtime is selected

- **WHEN** both runtimes record `fail` on a criterion the decision treats as required
- **THEN** the findings record names those cells and states what would have to change for each runtime to qualify

#### Scenario: A runtime is selected

- **WHEN** the decision selects the Agent SDK route
- **THEN** the findings record cites the C1, C2, C3, C4, and C8 cells for that route, and issue #400 receives a comment with the decision and a link to the findings record
