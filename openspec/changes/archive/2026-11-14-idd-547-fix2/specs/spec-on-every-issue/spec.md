## MODIFIED Requirements

### Requirement: A repository without a remote can opt into its local default branch

`spec-change.py archive-ref --cwd <dir>` SHALL decide which branch the spec checks read for the repository that holds `<dir>`. The repository's path is its main working tree: for a linked worktree (its git directory differs from the common git directory), the directory that holds the common `.git` directory; otherwise its top level, including a repository made with `--separate-git-dir`. It SHALL find the IDD configuration by walking up from that path, the way the skills walk up: at each directory below `/`, `.claude/.idd/local.json` first and then `.claude/issue-driven-dev.local.json`, stopping after the home directory, and SHALL use the first file found. The key it looks up is that path relative to the directory that holds the configuration's `.claude/` directory, with both paths resolved through symbolic links. A key in the file SHALL match when it names the same path after `.` and `..` segments and trailing `/` are normalised; `.` names the directory of the configuration itself; a key that is empty, only `/`, or has leading or trailing whitespace matches nothing. When the repository's own path cannot be written as a key (it has leading or trailing whitespace), the answer is `remote`; it SHALL NOT fall back to `.`. Reasons name the configuration file by its path relative to the repository, not by an absolute path. It SHALL print one JSON line and exit as follows:

- `remote` (exit 0), with a `reason`, when no configuration file is found; when the file found cannot be read as a JSON object (it is empty, `null`, not JSON, not valid UTF-8, or nested too deeply; a UTF-8 byte order mark is read as usual); when the file has no `spec_archive` field; when `spec_archive` has no entry for the key; or when the repository's path cannot be written as a key. Callers then read the default branch as the remote has it, as before; a repository without any remote then stops there, with this reason.
- `local` (exit 0), with `branch`, `ref` (the commit `refs/heads/<branch>` points at, whatever `HEAD` is), `config` and `key`, when exactly one entry matches the key, it is `{"ref": "local", "branch": "<name>"}`, the repository has no remote, and the branch exists.
- `error` (exit 2), with a `reason`, when `spec_archive` is not an object; when more than one key matches, including the same key written twice in the file; when the matching entry is not an object, its `ref` is not `local`, or its `branch` is missing, not a string, or not a valid branch name (`git check-ref-format --branch` must accept it unchanged, so revision syntax such as `master~1` or `master@{0}` is refused); when the repository has a remote; when the branch does not exist; or when `<dir>` is not inside a git repository.

A repository has a remote when `git remote` lists a name that has a `url` or a `pushurl` in the git configuration it reads, or a legacy `remotes/<name>` or `branches/<name>` file in its git directory; a `remote` section without either (for example a global `remote.origin.prune`) does not count. The repository having a remote turns an entry into an error, not a silent `remote`, so that an entry written for a repository without a remote cannot outlive the reason it was written for.

`spec-change.py link-base --cwd <dir> --issue <N>` SHALL give the base of the link check (`spec-change.py links --base`) in local mode. It SHALL resolve the configuration as `archive-ref` does first, and print `remote` (exit 0) or the same `error` (exit 2) when `archive-ref` would, without reading `<N>`. In local mode it SHALL print `ok` (exit 0) with `base` and `from`: the commit of the baseline tag when that tag exists and is an ancestor of `HEAD` other than `HEAD` itself (`from: baseline-tag`); otherwise the parent of the oldest commit in the history of `HEAD` whose message names issue `<N>`: `#<N>` with no letter, digit, `_`, `/` or `-` right before the `#`, the rule of `references/pr-issue-matching.md`, or `<owner>/<repo>#<N>` where `<owner>/<repo>` is the configuration's `github_repo` (letter case ignored), the form a commit in a separate code repository uses for the issue repository's issues; in both forms no digit follows the number (`from: first-commit`). `<owner>/<repo>#<N>` for any other repository does not count. The baseline tag is the configuration's `auto_tag.baseline_format` with `{N}` replaced by `<N>`, or `idd-<N>-baseline` when that field is absent, not a string containing `{N}`, or does not give a valid tag name. Commit messages SHALL be read so that no byte a message can hold hides a commit, with signature display turned off and `HEAD` separated from paths, and every commit and parent read SHALL be a hexadecimal object id. It SHALL print `error` (exit 2) when neither base exists, when that oldest commit has no parent, or when `<N>` is not a positive integer written in digits; an empty `<N>` is a usage error (exit 64), like any empty argument of `spec-change.py`. It SHALL NOT fall back to `merge-base` with the branch: on a direct-commit run that is `HEAD` itself, and the range would be empty.

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
| `spec_archive` has `.` | `{"ref": "local", "branch": "master"}` | another repository below, whose directory name ends in a space | `remote` (no fallback to `.`) |
| `spec_archive` names this path twice, written as the same key | `{"ref": "local", "branch": "master"}` | no remote | `error`, more than one entry |
| `spec_archive` names this path | `{"ref": "local", "branch": "master"}` | its only remote has a `pushurl` and no `url` | `error`, naming the remote |
| `spec_archive` names this path | `{"ref": "local", "branch": "master"}` | a legacy `remotes/origin` file in its git directory | `error`, naming the remote |
| `spec_archive` names this path | `{"ref": "local", "branch": "master"}` | made with `--separate-git-dir` | `local`, keyed by its top level |

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
| `github_repo` is `o/issues`; no tag; commits `base`, `see other/r#14`, `fix (O/ISSUES#14)` | `ok`, the parent of `fix (O/ISSUES#14)` |
| tag `idd-14-baseline` on `HEAD` itself; commits `base`, `a (#14)` | `ok`, the commit `base`, `from: first-commit` |
| `log.showSignature` is on and a commit before `a (#14)` is signed | `ok`, the parent of `a (#14)` |
| a file named `HEAD` at the repository's top level; no tag; commits `base`, `a (#14)` | `ok`, the commit `base` |
