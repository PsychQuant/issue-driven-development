## MODIFIED Requirements

### Requirement: idd-close SHALL use the same evidence for its open-PR gate

`idd-close` Step 1.5 SHALL obtain the open PRs that reference the issue from the helper and not from a pattern of its own. The gate SHALL stay as it is: it SHALL refuse to close while any open PR references the issue, whether the evidence is E1 or E2 and whether the PR is the run's own or another's. It SHALL refuse to close, and say why, when the open PR list could not be fetched or reached its limit, or when the helper could not read the issue itself (PRs are matched against the issue's creation time, so an unread issue has no evidence at all), because a closing summary, once posted, notifies everyone watching the issue and cannot be withdrawn (the close itself can be reopened) and an unknown SHALL NOT be read as none. Step 1.55 SHALL keep its own matching.

#### Scenario: Close with an open PR that only mentions the issue

- **GIVEN** an open PR that mentions `#N` without declaring it
- **WHEN** `/idd-close #N` runs
- **THEN** it SHALL refuse to close, as it does today

#### Scenario: Close with the run's own unmerged PR

- **GIVEN** an open PR from `idd/N-x` that declares `#N`
- **WHEN** `/idd-close #N` runs
- **THEN** it SHALL refuse to close

#### Scenario: The open PR list cannot be fetched

- **GIVEN** the helper reports that `gh pr list --state open` failed
- **WHEN** `/idd-close #N` runs
- **THEN** it SHALL refuse to close and print the reason

#### Scenario: The issue itself cannot be read

- **GIVEN** the helper reports that `gh issue view N` failed
- **AND** an open PR declares `#N`
- **WHEN** `/idd-close #N` runs
- **THEN** it SHALL refuse to close and print the reason
