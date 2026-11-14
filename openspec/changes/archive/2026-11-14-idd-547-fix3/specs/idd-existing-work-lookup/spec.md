## MODIFIED Requirements

### Requirement: The helper can skip the branch lookup

`check-existing-work.sh` SHALL accept `--skip-branches` before the repository argument. With it, the helper SHALL NOT run `git fetch` or list remote-tracking branches in `--cwd`, SHALL treat the clone as having no branches, SHALL NOT look up the default branch (it asks neither GitHub nor `refs/remotes/origin/HEAD`, a remote-tracking ref; with no branches to compare it is not needed, so no default-branch error is added), SHALL NOT add a `git fetch failed` error, and SHALL add a top-level `notes` list that says the branch lookup was skipped. The PR lookups on the repository argument SHALL run as without the flag, and their failures and limits SHALL be reported as before. Without the flag the helper's output SHALL be as before, without a `notes` field.

`idd-close` Step 1.5 SHALL pass `--skip-branches` only when `spec-change.py archive-ref` prints `local` for its working directory (requirement "A repository without a remote can opt into its local default branch" of `spec-on-every-issue`), and SHALL then print that the branch lookup was skipped and that the open PRs were checked on the issue's repository. The open-PR gate itself is unchanged.

#### Scenario: idd-close in a repository opted into its local branch

- **GIVEN** the working directory of `/idd-close` is a repository without a remote, opted into its local branch
- **WHEN** Step 1.5 runs
- **THEN** it calls the helper with `--skip-branches`, prints that the branch lookup was skipped, and still refuses to close while an open PR on the issue's repository references the issue

##### Example: the branch lookup can be skipped

| Clone | Flag | `git fetch` run | `errors` | `notes` | An open PR declaring the issue |
| --- | --- | --- | --- | --- | --- |
| has an `origin` that cannot be fetched | none | yes | has `git fetch failed` | absent | reported as E1 |
| has no remote | `--skip-branches` | no | no `git fetch failed` | says the branch lookup was skipped | reported as E1 |
| has no remote, the open PR list fails | `--skip-branches` | no | has the PR list failure | says the branch lookup was skipped | verdict `unknown` |
| has an `origin` and its `origin/HEAD`; `gh repo view` fails | `--skip-branches` | no | no default-branch error | says the branch lookup was skipped | none open; `origin/HEAD` is not read |
