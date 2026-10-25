## ADDED Requirements

### Requirement: Cloud session detection

The plugin SHALL decide whether it runs inside a Claude Code cloud session, and whether a human is attending that session, from environment variables only, through the helper `scripts/lib/cloud-session.sh`. `idd_is_cloud_session` SHALL succeed if and only if `CLAUDE_CODE_REMOTE` equals the literal string `true`. `idd_cloud_interaction` SHALL print `attended` if and only if `CLAUDE_CODE_SESSION_ATTENDED` equals the literal string `1`, and SHALL print `unattended` in every other case, including when the variable is unset. Python components SHALL apply the same two literal comparisons. No component SHALL infer cloud execution from a GitHub API error.

#### Scenario: web cloud session with a human present

- **GIVEN** `CLAUDE_CODE_REMOTE=true` and `CLAUDE_CODE_SESSION_ATTENDED=1`
- **WHEN** a skill sources `scripts/lib/cloud-session.sh`
- **THEN** `idd_is_cloud_session` exits 0
- **AND** `idd_cloud_interaction` prints `attended`

#### Scenario: cloud session without an attended signal

- **GIVEN** `CLAUDE_CODE_REMOTE=true` and `CLAUDE_CODE_SESSION_ATTENDED` unset
- **WHEN** `idd_cloud_interaction` runs
- **THEN** it prints `unattended`

#### Scenario: non-literal values are not cloud

- **GIVEN** `CLAUDE_CODE_REMOTE` is unset, empty, `1`, or `TRUE`
- **WHEN** `idd_is_cloud_session` runs
- **THEN** it exits non-zero

### Requirement: Issue egress dispatches through the GitHub REST API

`scripts/gh-egress.sh` SHALL remain the only path for issue create, comment, and edit egress, and SHALL keep its attestation check, mechanical nets, empty-body guard, and exit-code band unchanged. After every gate passes, it SHALL dispatch `create`, `comment`, and `edit` through `gh api` REST calls in every environment (not only in cloud sessions), via `scripts/lib/gh_egress_rest.py`. On success, standard output SHALL be exactly one line holding the created or edited issue URL (for `create` and `edit`) or the comment URL (for `comment`). The translator SHALL support the flags listed in the design (D2) and SHALL refuse any other flag, a missing `create` title, a missing issue reference, an extra positional argument, a label that does not exist in the repository (REST would create it silently; `gh issue` refuses it), or a milestone title that matches no open milestone (compared ignoring case, as `gh` does), with exit code 14 and a message naming the cause; arguments that are not UTF-8 text SHALL be refused with exit code 12. Issue references SHALL be parsed strictly: an owner, repository or host that could alter the REST path (`#`, `?`, `.` or `..` segments, `user@` hosts) SHALL be refused with exit code 14 before any request. A failing `gh` call SHALL end the dispatch with that call's own exit code, SHALL leave standard output empty, and SHALL put `gh`'s message (and a `hint:` line for a repository the cloud session cannot reach) on standard error. The issue body SHALL reach `gh` through standard input, never through argv. The wrapper SHALL read a value-taking flag's next token as its value whatever its shape, as `gh` does, so the gates scan exactly the text that is sent.

#### Scenario: create dispatches a REST POST and prints the URL

- **GIVEN** `gh-egress.sh create --repo o/r --title T --body "clean body" --label bug --scrub-attested warn`
- **WHEN** every gate passes
- **THEN** `gh` receives `api repos/o/r/issues -X POST --input - --jq .html_url`
- **AND** its standard input is the JSON object `{"title":"T","body":"clean body","labels":["bug"]}`
- **AND** the wrapper's standard output is the single URL line `gh` printed

#### Scenario: comment on an issue given by URL

- **GIVEN** `gh-egress.sh comment https://github.com/o/r/issues/5 --body "done" --scrub-attested warn`
- **WHEN** every gate passes
- **THEN** `gh` receives `api repos/o/r/issues/5/comments -X POST --input - --jq .html_url` with standard input `{"body":"done"}`

#### Scenario: edit applies label changes before the body patch

- **GIVEN** `gh-egress.sh edit 7 --repo o/r --add-label triage --remove-label stale --body "new body text here" --scrub-attested warn`
- **WHEN** every gate passes
- **THEN** `gh` is called with `api repos/o/r/issues/7/labels -X POST --input - --silent` (input `{"labels":["triage"]}`), then `api repos/o/r/issues/7/labels/stale -X DELETE --silent`, then `api repos/o/r/issues/7 -X PATCH --input - --jq .html_url` (input `{"body":"new body text here"}`)
- **AND** if any earlier call fails, the later calls are not sent and the wrapper exits with the failing call's code

#### Scenario: unsupported flag is refused, not dropped

- **GIVEN** `gh-egress.sh create --repo o/r --title T --body x --project Roadmap --scrub-attested warn`
- **WHEN** the translator parses the arguments
- **THEN** the wrapper exits 14 and stderr names `--project`
- **AND** no `gh` call is made

#### Scenario: unknown label is refused, not created

- **GIVEN** label `missing` does not exist in `o/r`
- **WHEN** `gh-egress.sh create --repo o/r --title T --body x --label missing --scrub-attested warn` runs
- **THEN** the wrapper exits 14 naming the label, and no issue is created

#### Scenario: an issue URL cannot redirect the request

- **WHEN** `gh-egress.sh edit 'https://github.com/o/r#/issues/5' --remove-label bug --scrub-attested warn` runs
- **THEN** the wrapper exits 14 and no `gh` call is made (in particular, no request to `repos/o/r`)

#### Scenario: a flag-shaped body value is scanned as the body

- **WHEN** `gh-egress.sh comment 5 --repo o/r -b "--title=cc @victim" --scrub-attested warn` runs
- **THEN** the mention net refuses it with exit 11, exactly as for the same text without the prefix

#### Scenario: gate refusals still happen before any dispatch

- **GIVEN** a body containing an unattested raw `@login` token
- **WHEN** `gh-egress.sh comment 5 --repo o/r --body "<that body>" --scrub-attested warn` runs
- **THEN** the wrapper exits 11 and no `gh` call is made, exactly as before this change

### Requirement: Scripts read GitHub through the REST read helper

Scripts that read GitHub (`check-existing-work.sh`, `check-diagnosis-readiness.sh`, `process-attachments.sh`, `idd-worktree.sh`, `check-closed-without-summary.sh`) SHALL read through `scripts/lib/gh-rest.sh`, never through `gh issue`, `gh pr`, or `gh repo` porcelain. The helper SHALL offer the read-only subcommands `issue-view`, `issue-list`, `pr-list`, and `repo-view`; SHALL return JSON whose field names and shapes match `gh … --json` for the fields listed in the design (D3), with an empty body as `""`; SHALL page through results until a short page or the `--limit`; SHALL treat `pr-list --state merged` as closed pull requests with a merge time; SHALL exclude pull requests from `issue-list`; SHALL sort `issue-list --sort updated` on the server before the limit applies; SHALL return every comment for `comments` (no 100-comment cap); SHALL apply `issue-list --closed-since DATE` before the limit; and SHALL exit 2 for an unknown subcommand or field, 1 for a GitHub failure, and 0 on success. On failure caused by a cloud session that cannot reach the repository, stderr SHALL carry a `hint:` line telling the user to attach the repository to the session.

#### Scenario: porcelain field names from REST data

- **GIVEN** the REST pulls endpoint returns a pull request with `head.ref = idd/42-x`, `head.sha = abc`, `created_at = 2026-10-01T00:00:00Z`, and `merged_at = null`
- **WHEN** `gh-rest.sh pr-list --repo o/r --state open --json number,headRefName,headRefOid,createdAt,mergedAt` runs
- **THEN** the output element is `{"number":…, "headRefName":"idd/42-x", "headRefOid":"abc", "createdAt":"2026-10-01T00:00:00Z", "mergedAt":null}`

#### Scenario: merged state filter

- **GIVEN** the closed pull requests are #3 (merged) and #4 (closed without merge)
- **WHEN** `gh-rest.sh pr-list --repo o/r --state merged --json number` runs
- **THEN** the output is `[{"number":3}]`

#### Scenario: comments are paged

- **GIVEN** issue #9 has 150 comments
- **WHEN** `gh-rest.sh issue-view 9 --repo o/r --json comments` runs
- **THEN** the helper requests page 1 and page 2 of `repos/o/r/issues/9/comments?per_page=100`
- **AND** the output `comments` array has 150 elements

#### Scenario: repository not attached to the cloud session

- **GIVEN** `gh api` fails with a message containing `not enabled for this session`
- **WHEN** any helper subcommand runs against that repository
- **THEN** the helper exits 1
- **AND** stderr includes a `hint:` line saying the repository must be attached to the cloud session

#### Scenario: unknown field is a usage error

- **WHEN** `gh-rest.sh repo-view --repo o/r --json stargazerCount` runs
- **THEN** the helper exits 2 and lists the accepted fields

### Requirement: Runtime reference maps porcelain to REST

The plugin SHALL ship `references/claude-code-remote-tools.md` describing the cloud runtime: the detection signals, a table mapping each `gh` porcelain form used by in-scope skills (`gh issue view`, `gh issue list`, `gh issue create`, `gh issue comment`, `gh issue edit`, `gh pr list`, `gh pr view`, `gh pr create`, `gh repo view`, `gh label list`, `gh auth status`) to its REST replacement, the rule that issue writes still go through `scripts/gh-egress.sh`, the unsupported surfaces with the message each one prints, and a setup-script template. Each in-scope skill (`idd-all`, `idd-issue`, `idd-diagnose`, `idd-plan`, `idd-implement`, `idd-verify`, `idd-update`, `idd-clarify`, `idd-list`) SHALL carry a runtime note pointing to the reference; each unsupported skill (`idd-find`, `idd-report`, `idd-discuss`, `idd-ask`) SHALL carry a runtime note telling the agent to stop in a cloud session and print the reason. Skill bodies SHALL NOT be rewritten from porcelain to REST, with one exception: `idd-all`'s own state-changing steps (feature-branch setup and PR creation) SHALL call the REST API directly (`gh api`), because an agent translating them wrongly would create the wrong branch or no PR.

#### Scenario: in-scope skill carries the supported note

- **WHEN** the drift-guard suite reads `skills/idd-diagnose/SKILL.md`
- **THEN** it finds the supported runtime-note marker and a link to `references/claude-code-remote-tools.md`

#### Scenario: unsupported skill carries the stop note

- **WHEN** the drift-guard suite reads `skills/idd-find/SKILL.md`
- **THEN** it finds the unsupported runtime-note marker

### Requirement: Unsupported cloud surfaces fail with a stated reason

In a cloud session, surfaces that need GitHub GraphQL or the search API SHALL stop with a message naming the cause and the alternative (run from a local session), and SHALL NOT fall back silently. `scripts/lib/discussions_api.py` SHALL raise its error type before sending any GraphQL request when `CLAUDE_CODE_REMOTE` equals `true`, with a message stating that Discussions need GraphQL, which cloud sessions block.

#### Scenario: Discussions read in a cloud session

- **GIVEN** `CLAUDE_CODE_REMOTE=true`
- **WHEN** any `discussions_api.GitHub` method that issues GraphQL is called
- **THEN** it raises the module's error type with a message naming GraphQL and the cloud session
- **AND** no `gh` process is started

### Requirement: Cloud verify runs Claude-only and declares the missing Codex leg

When `idd_is_cloud_session` succeeds, `idd-verify` SHALL NOT run the cross-model Codex leg and SHALL NOT resolve codex-pro governance. It SHALL pass `codexEnabled: false` to the workflow backend, SHALL not start the Codex call in the manual fan-out backend, and SHALL state `Codex leg not run — cloud session (degraded: Claude-only)` in the master report's engine line and process gaps. The missing Codex leg SHALL NOT by itself be a blocking finding. Outside a cloud session, `idd-verify` SHALL behave as before.

#### Scenario: cloud verify report

- **GIVEN** `CLAUDE_CODE_REMOTE=true`
- **WHEN** `idd-verify #N` produces its master report
- **THEN** the engine line contains `Codex leg not run — cloud session (degraded: Claude-only)`
- **AND** no Codex call was started
