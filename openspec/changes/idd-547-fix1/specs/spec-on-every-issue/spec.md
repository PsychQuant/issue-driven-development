## MODIFIED Requirements

### Requirement: Close requires the issue's change to be archived

`idd-close` SHALL fetch the issue's comments with `gh api --paginate`, SHALL choose the Implementation Complete comment with `spec-change.py ic` (requirement "One way to choose the Implementation Complete comment"), and SHALL run `spec-change.py archived` on it with `--ref` set to the default branch as the remote has it. It SHALL close the issue only when the command prints `pass`. On `refuse` it SHALL stop and name the changes that are not archived or the fault in the `**Spec**:` line; on `error` it SHALL stop and say the default branch could not be read. For a comment that declares a change, it SHALL first ask `spec-change.py archive-ref` which branch to read (requirement "A repository without a remote can opt into its local default branch"). When the answer is `remote`, it SHALL read the default branch by fetching it from the remote and checking the commit that fetch returned, and SHALL stop when `gh repo view` cannot name the default branch or the fetch fails; the reason it prints SHALL then include the reason `archive-ref` gave for answering `remote`, so that a repository meant for the local branch whose entry was not found says why. When the answer is `local`, it SHALL check the commit `archive-ref` returned for the configured branch, not `HEAD`, SHALL NOT fetch, and SHALL print that a local ref was used, with the branch, the commit and the entry's key, and without the configuration file's path. When the answer is `error`, or `archive-ref` prints nothing a JSON reader can take, it SHALL stop and print the reason. For any other comment the default branch is not read, since `archived` answers from the comment alone. When the comments cannot be fetched or `ic` exits 2, it SHALL stop and say the comments could not be read; it SHALL NOT treat that as an issue with no Implementation Complete comment. An issue with no Implementation Complete comment is not held to this rule. A retroactive close (`idd-close --retroactive`, for an issue that is already closed) skips this gate, as it skips the gates before it.

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
| marker, `**Spec**: change idd-42-fix-timeout` | no remote; opted into `master`; `HEAD` is on the issue's branch, where the change is archived, and `master` does not have it | stops, naming the change |
| marker, `**Spec**: change idd-42-fix-timeout` | no remote and no `spec_archive` entry for the repository | stops, saying the default branch could not be read |
| marker, `**Spec**: change idd-42-fix-timeout` | the repository has a remote and the configuration opts it into `local` | stops and prints the reason |

### Requirement: A repository without a remote can opt into its local default branch

`spec-change.py archive-ref --cwd <dir>` SHALL decide which branch the spec checks read for the repository that holds `<dir>`. The repository's path is its main working tree: for a linked worktree, the directory that holds the repository's common `.git` directory; otherwise its top level. It SHALL find the IDD configuration by walking up from that path, the way the skills walk up: at each directory below `/`, `.claude/.idd/local.json` first and then `.claude/issue-driven-dev.local.json`, stopping after the home directory, and SHALL use the first file found. The key it looks up is that path relative to the directory that holds the configuration's `.claude/` directory, with both paths resolved through symbolic links. A key in the file SHALL match when it names the same path after `.` and `..` segments and trailing `/` are normalised; `.` names the directory of the configuration itself; a key that is empty, only `/`, or has leading or trailing whitespace matches nothing. It SHALL print one JSON line and exit as follows:

- `remote` (exit 0), with a `reason`, when no configuration file is found; when the file found cannot be read as a JSON object (it is empty, `null`, not JSON, not valid UTF-8, or nested too deeply; a UTF-8 byte order mark is read as usual); when the file has no `spec_archive` field; or when `spec_archive` has no entry for the key. Callers then read the default branch as the remote has it, as before; a repository without any remote then stops there, with this reason.
- `local` (exit 0), with `branch`, `ref` (the commit `refs/heads/<branch>` points at, whatever `HEAD` is), `config` and `key`, when exactly one entry matches the key, it is `{"ref": "local", "branch": "<name>"}`, the repository has no remote, and the branch exists.
- `error` (exit 2), with a `reason`, when `spec_archive` is not an object; when more than one key matches; when the matching entry is not an object, its `ref` is not `local`, or its `branch` is missing, not a string, or not a valid branch name (`git check-ref-format --branch` must accept it unchanged, so revision syntax such as `master~1` or `master@{0}` is refused); when the repository has a remote; when the branch does not exist; or when `<dir>` is not inside a git repository.

A repository has a remote when any `remote.<name>.url` is set in the git configuration it reads; a `remote` section without a URL (for example a global `remote.origin.prune`) does not count. The repository having a remote turns an entry into an error, not a silent `remote`, so that an entry written for a repository without a remote cannot outlive the reason it was written for.

`spec-change.py link-base --cwd <dir> --issue <N>` SHALL give the base of the link check (`spec-change.py links --base`) in local mode. It SHALL resolve the configuration as `archive-ref` does first, and print `remote` (exit 0) or the same `error` (exit 2) when `archive-ref` would, without reading `<N>`. In local mode it SHALL print `ok` (exit 0) with `base` and `from`: the commit of the baseline tag when that tag exists and is an ancestor of `HEAD` (`from: baseline-tag`); otherwise the parent of the oldest commit in the history of `HEAD` whose message contains `#<N>` with no letter, digit, `_`, `/` or `-` right before the `#` and no digit after the number, the rule of `references/pr-issue-matching.md` (`from: first-commit`). The baseline tag is the configuration's `auto_tag.baseline_format` with `{N}` replaced by `<N>`, or `idd-<N>-baseline` when that field is absent or not a string containing `{N}`. Commit messages SHALL be read so that no byte a message can hold hides a commit. It SHALL print `error` (exit 2) when neither base exists, when that oldest commit has no parent, or when `<N>` is not a positive integer written in digits; an empty `<N>` is a usage error (exit 64), like any empty argument of `spec-change.py`. It SHALL NOT fall back to `merge-base` with the branch: on a direct-commit run that is `HEAD` itself, and the range would be empty.

`references/spec-wrapper.md` step 5 SHALL ask `link-base` first, with the issue number taken from `NUMBER`, or from `N` when `NUMBER` is empty, and SHALL use its `base` when it prints `ok`, SHALL keep the fetch of the default branch when it prints `remote`, and SHALL stop with the reason when it prints `error` or nothing a JSON reader can take, without also printing the message about a failed fetch. `references/config-protocol.md` SHALL document the `spec_archive` field, the key, and why an entry is accepted only for a repository without a remote.

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
| the file is not JSON | — | no remote | `remote`, saying the file could not be read |
| the file is empty, or holds `null` | — | no remote | `remote` |
| the file starts with a UTF-8 byte order mark | `{"ref": "local", "branch": "master"}` | no remote, `master` exists | `local` |
| `spec_archive` names this path as `sub` and as `./sub/` | both `{"ref": "local", "branch": "master"}` | no remote | `error`, more than one entry |
| `spec_archive` names this path | `{"ref": "local", "branch": "master~1"}` | no remote | `error`, not a branch name |
| `spec_archive` names this path as ` sub` | `{"ref": "local", "branch": "master"}` | no remote | `remote` |
| `spec_archive` names this path | `{"ref": "local", "branch": "master"}` | no remote; the global git configuration has `[remote "origin"]` with only `prune = true` | `local` |
| `spec_archive` names the main working tree | `{"ref": "local", "branch": "master"}` | asked from a linked worktree of it | `local` |
| the new file without `spec_archive`, the legacy file beside it with an entry | — | no remote | `remote` (the new file wins) |
| a file above the home directory with an entry | — | no remote | `remote` (not read) |

##### Example: where the local link check starts

| Repository (opted into local `master`) | `link-base --issue 14` |
| --- | --- |
| tag `idd-14-baseline` on an ancestor of `HEAD` | `ok`, the tag's commit, `from: baseline-tag` |
| no tag; commits `base`, `a (#14)`, `b (Refs #14)` | `ok`, the commit `base`, `from: first-commit` |
| no tag; the only commit naming a 14 says `#142` | `error` |
| no tag; the first commit with `#14` is the root commit | `error` |
| the repository is not opted in | `remote` |
| the repository is not opted in, `--issue abc` | `remote` |
| no tag; commits `base`, `see o/r#14`, `x#14`, `fix (#14)` | `ok`, the parent of `fix (#14)` |
| tag `idd-14-baseline` on a commit that is not an ancestor of `HEAD`; commits `base`, `a (#14)` | `ok`, the commit `base`, `from: first-commit` |
| `auto_tag.baseline_format` is `start-{N}`, tag `start-14` on an ancestor | `ok`, that tag's commit, `from: baseline-tag` |
| no tag; a commit before `a (#14)` has the byte 0x1e in its message | `ok`, the parent of `a (#14)` |
