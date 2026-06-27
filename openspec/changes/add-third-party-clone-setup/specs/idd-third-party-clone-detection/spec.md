## ADDED Requirements

### Requirement: idd-issue Step 0.5.E third-party clone detection branch

The `idd-issue` skill SHALL add a third branch to Step 0.5.E (fork-aware detection) that fires when the origin repo is neither owned by nor pushable by the authenticated user. The branch SHALL be evaluated AFTER the fork branch (E2) and BEFORE the non-fork-use-origin branch (E1).

#### Scenario: third-party clone detected via hybrid signal

- **WHEN** `idd-issue` runs Step 0.5.E with no existing config, `IS_FORK=false`, the origin owner differs from `gh api user --jq .login`, AND `gh api repos/{owner}/{repo} --jq .permissions.push` returns `false`
- **THEN** the system SHALL classify the working tree as a third-party clone
- **AND** SHALL present a 3-option AskUserQuestion (Upstream / your tracking repo / local-only) instead of silently using origin

#### Scenario: own repo skips third-party branch with zero extra API

- **WHEN** the origin owner equals the authenticated user's login
- **THEN** the system SHALL NOT issue the `repos/{owner}/{repo}` push-permission probe
- **AND** SHALL fall through to the existing E1 (use origin, write config, no prompt) behavior unchanged

#### Scenario: pushable org repo is not third-party

- **WHEN** the origin owner differs from the authenticated user BUT the push-permission probe returns `true`
- **THEN** the system SHALL treat the repo as the user's own (collaborator / org write access)
- **AND** SHALL fall through to E1 behavior, NOT the third-party branch

#### Scenario: fork takes precedence over third-party

- **WHEN** `IS_FORK=true` and an upstream exists
- **THEN** the system SHALL run the existing E2 fork 3-option flow
- **AND** SHALL NOT evaluate the third-party branch (no double-prompt), regardless of owner-mismatch or push permission

#### Scenario: push-permission probe failure is fail-safe

- **WHEN** the push-permission probe cannot be resolved (auth scope insufficient, rate limit, or API error) after the owner-mismatch pre-filter has matched
- **THEN** the system SHALL default to treating the repo as third-party (present the 3-option prompt)
- **AND** SHALL surface a one-line notice that the probe failed and the conservative default was applied

### Requirement: idd-issue third-party routing options

When a third-party clone is detected, the 3-option routing SHALL write config and ignore rules per the chosen option without creating any GitHub repository.

#### Scenario: user picks own tracking repo

- **WHEN** the user selects "your tracking repo" and supplies an existing `owner/repo` (via `--target` or prompt)
- **THEN** the system SHALL write `github_repo` = that repo to `.claude/.idd/local.json`
- **AND** SHALL NOT invoke `gh repo create`

#### Scenario: user picks upstream with visibility warning

- **WHEN** the user selects "Upstream (original author's repo)"
- **THEN** the system SHALL set `github_repo` = origin
- **AND** SHALL surface a warning that issues opened there are publicly visible on the original author's tracker

#### Scenario: user picks local-only

- **WHEN** the user selects "local-only"
- **THEN** the system SHALL NOT create a GitHub issue
- **AND** SHALL inform the user that GitHub-backed idd-* skills are unavailable until a target is configured

### Requirement: idd-config init third-party parity

The `idd-config init` flow SHALL offer the same third-party detection and 3-option setup as `idd-issue` Step 0.5.E.

#### Scenario: idd-config init in a third-party clone

- **WHEN** `/idd-config init` runs in a third-party clone (owner-mismatch + push=false, not a fork)
- **THEN** it SHALL present the same 3-option routing
- **AND** SHALL write config + `.git/info/exclude` rule + `pr_policy: never` per the chosen option

### Requirement: idd-issue Step 0 Bootstrap reflects third-party detection

The Step 0 Bootstrap TaskCreate batch description for target resolution SHALL mention the third-party branch so stage tracking reflects it.

#### Scenario: bootstrap task description names third-party branch

- **WHEN** `idd-issue` runs its Step 0 Bootstrap `detect_target_repo` TaskCreate
- **THEN** the description SHALL include the third-party branch in its resolution-order summary (fork E2 → third-party → E1)
