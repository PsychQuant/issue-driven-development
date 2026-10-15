## Purpose

Defines how `/idd-all --api` sends one issue to a deployer's GitHub Actions, where the Claude Agent SDK loads IDD and runs the idd-all pipeline to a verified pull request: the local entry point and its dispatch request, the split between the flow kept in the IDD repository and the secret kept in the deployer's repository, the GitHub permissions the cloud agent receives, the caller workflow's triggers, and what every cloud run must declare or omit.

## ADDED Requirements

### Requirement: idd-all --api dispatches the issue to the cloud and stops

`/idd-all` SHALL accept an `--api` flag. With `--api`, idd-all SHALL resolve the target repository as it does today, then send one dispatch request for issue `#N` to that repository and print the URL of the workflow run it started, and SHALL then stop without creating a branch, changing the local working tree, or running any later phase locally. `--api` SHALL accept only the from-issue form (`#N`); free-text input or a missing issue number MUST abort before any request is sent, with a message telling the user to create the issue first. `--api` combined with `--no-pr`, `--in-chain`, `--review`, or `--cwd` MUST abort before any request is sent, naming the conflicting flag. `--api` combined with `--pr` SHALL behave as `--api` alone.

#### Scenario: Dispatching an open issue

- **WHEN** the user runs `/idd-all --api #12` in a repository whose caller workflow is deployed and issue #12 is open
- **THEN** idd-all prints one workflow run URL for that repository and stops, and the local branch and working tree are unchanged

#### Scenario: Free text with --api

- **WHEN** the user runs `/idd-all --api 'fix the export bug'`
- **THEN** idd-all aborts without sending a request and tells the user to create the issue first

#### Scenario: Conflicting flag

- **WHEN** the user runs `/idd-all --api #12 --no-pr`
- **THEN** idd-all aborts without sending a request and the message names `--no-pr` as conflicting with `--api`

### Requirement: The dispatch request uses workflow_dispatch and returns the run

The dispatch script `plugins/issue-driven-dev/cloud/dispatch.sh` SHALL send `POST /repos/{owner}/{repo}/actions/workflows/idd-cloud.yml/dispatches` with `ref` set to the repository's default branch unless `--ref` is given, `inputs.prompt` set to exactly `/issue-driven-dev:idd-all #N --pr`, and `return_run_details` set to `true`, using the local `gh` login. On success it SHALL print only the run's `html_url` and exit 0. It SHALL refuse, with exit status 2 and no request, a repository not matching `owner/repo`, an issue number that is not a positive integer, or a ref that starts with `-` or contains characters other than letters, digits, `.`, `_`, `/`, and `-`. It SHALL check that the issue exists and is open before sending, and SHALL send nothing when it is closed or missing. With `--dry-run` it SHALL print the method, path, and JSON body it would send, and SHALL make no network request.

#### Scenario: Dry run shows the request

- **WHEN** a test runs `dispatch.sh --repo acme/app --issue 7 --dry-run` with no network and no GitHub token
- **THEN** the output contains `/repos/acme/app/actions/workflows/idd-cloud.yml/dispatches`, `/issue-driven-dev:idd-all #7 --pr`, and `"return_run_details": true`, and the exit status is 0

#### Scenario: Invalid issue number

- **WHEN** a test runs `dispatch.sh --repo acme/app --issue 0 --dry-run`
- **THEN** the exit status is 2 and the output names the issue argument

#### Scenario: Caller workflow not deployed

- **WHEN** GitHub answers the dispatch with HTTP 404
- **THEN** the script exits 1, says that `.github/workflows/idd-cloud.yml` was not found in that repository, and points to the deployment guide

### Requirement: The cloud agent holds only the job token

The reusable workflow `.github/workflows/idd-cloud-run.yml` SHALL declare exactly one secret, `ANTHROPIC_API_KEY`, and SHALL set `GH_TOKEN` for the agent from the job's own token only. It MUST NOT declare or read `IDD_GITHUB_TOKEN` or any other personal access token. Pull requests SHALL be opened with the job token, which requires the deployer's repository or organization to allow GitHub Actions to create pull requests.

#### Scenario: No personal token in the reusable workflow

- **WHEN** a test scans `.github/workflows/idd-cloud-run.yml`
- **THEN** the only declared secret is `ANTHROPIC_API_KEY`, the file does not contain `IDD_GITHUB_TOKEN`, and `GH_TOKEN` is set from `github.token`

#### Scenario: Pull request author in a cloud run

- **WHEN** a cloud run in `PsychQuant/idd-cloud-sandbox` opens a pull request
- **THEN** the pull request's author is `github-actions[bot]`

### Requirement: The caller workflow cannot be re-triggered by the agent

The caller template `plugins/issue-driven-dev/cloud/caller-example.yml` SHALL be triggered only by `workflow_dispatch`, with the inputs `prompt` (required), `model`, `max_turns`, and `dry_run`. It MUST NOT declare a `repository_dispatch` trigger. Its `permissions` SHALL grant write on contents, issues, and pull-requests and MUST NOT grant `actions`. It SHALL pass `ANTHROPIC_API_KEY` explicitly and MUST NOT use `secrets: inherit`.

#### Scenario: Scanning the caller template

- **WHEN** a test scans `plugins/issue-driven-dev/cloud/caller-example.yml`
- **THEN** it finds a `workflow_dispatch` trigger, no `repository_dispatch` trigger, no `actions` permission, and no `secrets: inherit`

### Requirement: Cloud runs use PR mode, omit attribution, and can run gh-egress

Every cloud run started by `/idd-all --api` SHALL run idd-all with `--pr`, so a deployer's `pr_policy` cannot make the run commit to the default branch. The Agent SDK runner SHALL pass settings that set `attribution.commit` and `attribution.pr` to empty strings, so commits and pull requests from the run carry no Claude attribution. The reusable workflow SHALL install `markdown-it-py` 4.0.0 and `linkify-it-py` 2.0.3 in a step that does not receive the API key. The runner SHALL accept `--model`; an empty value SHALL leave the SDK's default model in place.

#### Scenario: Runner dry run shows the settings

- **WHEN** a test runs `sdk_run.py --dry-run --model claude-sonnet-5-5` with a sentinel API key
- **THEN** the output shows the model `claude-sonnet-5-5` and settings in which `attribution.commit` and `attribution.pr` are empty strings, and does not contain the sentinel

#### Scenario: Commit from a cloud run

- **WHEN** a cloud run commits to its feature branch
- **THEN** the commit message contains no `Co-Authored-By` trailer naming Claude

### Requirement: The flow lives in the IDD repository and the key stays in the deployer's repository

The cloud flow SHALL live in the IDD repository: the reusable workflow triggered only by `workflow_call`, the Agent SDK runner, the dispatch script, the caller template, and the deployment guide under `plugins/issue-driven-dev/cloud/`. The IDD repository MUST NOT store an API key. A deployer's repository SHALL need only its `ANTHROPIC_API_KEY` secret and a copy of the caller template at `.github/workflows/idd-cloud.yml`; it MUST NOT need a fork of IDD or a copy of any other IDD file. The Managed Agents launcher SHALL NOT be shipped.

#### Scenario: The reusable workflow does not run on IDD's own events

- **WHEN** a commit is pushed to `PsychQuant/issue-driven-development` or a pull request is opened there
- **THEN** `idd-cloud-run.yml` does not start, because its only trigger is `workflow_call`

#### Scenario: The Managed Agents launcher is gone

- **WHEN** a test lists `plugins/issue-driven-dev/cloud/`
- **THEN** `ma_run.sh` is not present

### Requirement: Credentials and prompt text never become shell code or output

API keys and tokens MUST NOT be written to tracked files, passed as command-line arguments, or printed by the runner, the dispatch script, or the workflow. Every workflow input SHALL reach shell steps through environment variables; no `run:` block of the reusable workflow SHALL contain a `${{ }}` expression.

#### Scenario: Prompt text is not interpolated into a shell command

- **WHEN** a test scans `.github/workflows/idd-cloud-run.yml`
- **THEN** no `run:` block contains `${{`, and the prompt and model reach the runner through environment variables

### Requirement: Cloud verify runs Claude-only and declares the missing Codex leg

When idd-verify runs inside a cloud run, it SHALL use Claude reviewers only, and its report MUST state that the Codex cross-model reviewer did not run.

#### Scenario: Verify report in a cloud run

- **WHEN** a cloud run reaches idd-verify and posts the verify report
- **THEN** the report states that the Codex reviewer was not run
