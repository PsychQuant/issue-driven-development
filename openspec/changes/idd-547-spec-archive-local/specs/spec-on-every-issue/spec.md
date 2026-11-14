## MODIFIED Requirements

### Requirement: Close requires the issue's change to be archived

`idd-close` SHALL fetch the issue's comments with `gh api --paginate`, SHALL choose the Implementation Complete comment with `spec-change.py ic` (requirement "One way to choose the Implementation Complete comment"), and SHALL run `spec-change.py archived` on it with `--ref` set to the default branch as the remote has it. It SHALL close the issue only when the command prints `pass`. On `refuse` it SHALL stop and name the changes that are not archived or the fault in the `**Spec**:` line; on `error` it SHALL stop and say the default branch could not be read. For a comment that declares a change, it SHALL first ask `spec-change.py archive-ref` which branch to read (requirement "A repository without a remote can opt into its local default branch"). When the answer is `remote`, it SHALL read the default branch by fetching it from the remote and checking the commit that fetch returned, and SHALL stop when `gh repo view` cannot name the default branch or the fetch fails. When the answer is `local`, it SHALL check the commit `archive-ref` returned, SHALL NOT fetch, and SHALL print that a local ref was used, with the branch and the commit. When the answer is `error`, or `archive-ref` prints nothing a JSON reader can take, it SHALL stop and print the reason. For any other comment the default branch is not read, since `archived` answers from the comment alone. When the comments cannot be fetched or `ic` exits 2, it SHALL stop and say the comments could not be read; it SHALL NOT treat that as an issue with no Implementation Complete comment. An issue with no Implementation Complete comment is not held to this rule. A retroactive close (`idd-close --retroactive`, for an issue that is already closed) skips this gate, as it skips the gates before it.

#### Scenario: An unarchived change holds the close

- **GIVEN** an Implementation Complete comment with the marker and `**Spec**: change idd-42-fix-timeout`
- **AND** `openspec/changes/idd-42-fix-timeout/` still exists on the default branch
- **WHEN** `idd-close` runs its gates
- **THEN** it does not close the issue and says the change is not archived

#### Scenario: A repository without a remote, opted in

- **GIVEN** the code repository has no remote and the IDD configuration above it maps the repository's path to `{"ref": "local", "branch": "master"}`
- **AND** the change is archived on `master`
- **WHEN** `idd-close` runs its gates
- **THEN** the gate passes without fetching and prints the local branch and commit it checked

##### Example: the close gate reads the default branch

| Newest Implementation Complete comment | On the default branch | Close gate |
| --- | --- | --- |
| marker, `**Spec**: change idd-42-fix-timeout` | the change is archived | passes |
| marker, `**Spec**: change idd-42-fix-timeout` | archived on the issue's branch only, not yet merged | stops, naming the change |
| marker, no `**Spec**:` line | not read | stops, naming the missing line |
| no marker, no `**Spec**:` line | not read | passes |
| the issue has no Implementation Complete comment | not read | passes |
| the comments could not be fetched | not read | stops, saying the comments could not be read |
| marker, `**Spec**: change idd-42-fix-timeout` | the default branch cannot be fetched | stops, saying the default branch could not be read |
| marker, `**Spec**: no behaviour change` | the default branch cannot be fetched | passes; the branch is not read |
| marker, `**Spec**: change idd-42-fix-timeout` | the remote's default branch dropped the archive, the local tracking ref did not move | stops, naming the change |
| marker, `**Spec**: change idd-42-fix-timeout` | no remote; the configuration opts the repository into its local `master`, where the change is archived | passes; prints `local ref master@<commit>` |
| marker, `**Spec**: change idd-42-fix-timeout` | no remote; the configuration opts in, the change is not archived on `master` | stops, naming the change |
| marker, `**Spec**: change idd-42-fix-timeout` | the repository has a remote and the configuration opts it into `local` | stops and prints the reason |

## ADDED Requirements

### Requirement: A repository without a remote can opt into its local default branch

`spec-change.py archive-ref --cwd <dir>` SHALL decide which branch the spec checks read for the repository that holds `<dir>`. It SHALL find the IDD configuration by walking up from the repository's top level: at each directory, `.claude/.idd/local.json` first and then `.claude/issue-driven-dev.local.json`, stopping after the home directory or at `/`, and SHALL use the first file found. The key it looks up is the path of the repository's top level relative to the directory that holds that `.claude/` directory, with both paths resolved through symbolic links; a key in the file SHALL match when it names the same path after `.` and `..` segments and a trailing `/` are normalised, and `.` names the directory of the configuration itself. It SHALL print one JSON line and exit as follows:

- `remote` (exit 0) when no configuration file is found, when the file has no `spec_archive` field, or when `spec_archive` has no entry for the key. Callers then read the default branch as the remote has it, as before.
- `local` (exit 0), with `branch`, `ref` (the commit `refs/heads/<branch>` points at), `config` and `key`, when the entry is `{"ref": "local", "branch": "<name>"}`, the repository has no remote at all (`git remote` lists nothing), and the branch exists.
- `error` (exit 2), with a `reason`, when the file found cannot be read as a JSON object; when `spec_archive` is not an object; when the entry is not an object, its `ref` is not `local`, or its `branch` is missing, empty, not a string or starts with `-`; when the repository has any remote; when the branch does not exist; or when `<dir>` is not inside a git repository.

The repository having a remote turns an entry into an error, not a silent `remote`, so that an entry written for a repository without a remote cannot outlive the reason it was written for.

`spec-change.py link-base --cwd <dir> --issue <N>` SHALL give the base of the link check (`spec-change.py links --base`) in local mode. It SHALL resolve the configuration as `archive-ref` does and print `remote` (exit 0) or the same `error` (exit 2) when `archive-ref` would. In local mode it SHALL print `ok` (exit 0) with `base` and `from`: the commit of the tag `idd-<N>-baseline` when that tag exists and is an ancestor of `HEAD` (`from: baseline-tag`); otherwise the parent of the oldest commit in the history of `HEAD` whose message contains `#<N>` not followed by another digit (`from: first-commit`). It SHALL print `error` (exit 2) when neither exists, when that oldest commit has no parent, or when `<N>` is not a positive integer written in digits. It SHALL NOT fall back to `merge-base` with the branch: on a direct-commit run that is `HEAD` itself, and the range would be empty.

`references/spec-wrapper.md` step 5 SHALL ask `link-base` first and use its `base` when it prints `ok`, SHALL keep the fetch of the default branch when it prints `remote`, and SHALL stop when it prints `error` or nothing a JSON reader can take. `references/config-protocol.md` SHALL document the `spec_archive` field, the key, and why an entry is accepted only for a repository without a remote.

#### Scenario: An entry for a repository that later gained a remote

- **GIVEN** a configuration entry `{"ref": "local", "branch": "master"}` for a repository
- **AND** a remote was added to that repository afterwards
- **WHEN** `archive-ref` runs for it
- **THEN** it prints `error` and names the remote, instead of reading the local branch

##### Example: how a spec_archive entry resolves

| Configuration found | Entry for the repository's path | Repository | `archive-ref` |
| --- | --- | --- | --- |
| none | — | no remote | `remote` |
| a file without `spec_archive` | — | no remote | `remote` |
| `spec_archive` names another path only | — | no remote | `remote` |
| `spec_archive` names this path | `{"ref": "local", "branch": "master"}` | no remote, `master` exists | `local`, `master` and its commit |
| `spec_archive` names this path as `./sub/` | `{"ref": "local", "branch": "master"}` | no remote, `master` exists | `local` |
| `spec_archive` names this path | `{"ref": "local", "branch": "master"}` | has a remote `origin` | `error`, naming the remote |
| `spec_archive` names this path | `{"ref": "local", "branch": "trunk"}` | no remote, no branch `trunk` | `error` |
| `spec_archive` names this path | `{"ref": "remote", "branch": "master"}` | no remote | `error` |
| `spec_archive` names this path | `{"ref": "local"}` | no remote | `error` |
| `spec_archive` is a list | — | no remote | `error` |
| the file is not JSON | — | no remote | `error` |

##### Example: where the local link check starts

| Repository (opted into local `master`) | `link-base --issue 14` |
| --- | --- |
| tag `idd-14-baseline` on an ancestor of `HEAD` | `ok`, the tag's commit, `from: baseline-tag` |
| no tag; commits `base`, `a (#14)`, `b (Refs #14)` | `ok`, the commit `base`, `from: first-commit` |
| no tag; the only commit naming a 14 says `#142` | `error` |
| no tag; the first commit with `#14` is the root commit | `error` |
| the repository is not opted in | `remote` |
