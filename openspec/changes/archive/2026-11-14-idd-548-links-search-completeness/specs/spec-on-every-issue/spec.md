## ADDED Requirements

### Requirement: The repository's top directory is read as git prints it

The subcommands of `scripts/spec-change.py` that take `--cwd` (`links`, `archived` and `preflight`) SHALL take the repository's top directory from `git rev-parse --show-toplevel` as git prints it, removing only the line end that git adds: a directory name that ends in a space is kept. The three SHALL read it in the same way, so that they agree about the same `--cwd`.

#### Scenario: A repository whose directory name ends in a space

- **GIVEN** a repository whose top directory name ends in a space, with a requirement added in a range and its marker in a tracked test file
- **WHEN** `spec-change.py links` runs with `--cwd` at that directory
- **THEN** it prints `status` `ok` and exits 0, as it does for a copy of the repository at a path that does not end in a space

##### Example: top directory names

| Subcommand | Top directory of the repository | Answer |
| --- | --- | --- |
| `links` | the name ends in a space | the same JSON line and exit code as for a copy whose name does not end in a space (`ok`) |
| `archived` | the name ends in a space | the same JSON line and exit code as for that copy (`pass`) |
| `preflight` | the name ends in a space | the same `status` and exit code as for that copy |

## MODIFIED Requirements

### Requirement: Added and modified requirements carry an executable check

`scripts/spec-change.py links --base <rev>` SHALL compare the files under `openspec/specs/` at `<rev>` and at `--head` (default `HEAD`). For every requirement that is new or whose text differs between the two, it SHALL require one of two things: at least one `##### Example:` under the requirement, where each such Example has a title that is unique within its capability and a tracked file at the head revision, outside `openspec/` and not ending in `.md`, that contains the marker `spec-example: <capability> / <Example title>` (a tracked file of a submodule counts, as the paragraph "Submodules" below describes); or a line under the requirement that starts with `No executable check:` followed by a reason. A requirement that does not differ SHALL NOT be checked. A marker counts only when nothing but whitespace, or the comment closer `-->` or `*/`, follows the Example title on its line. Lines inside a code fence are not read as `##### Example:` or `No executable check:` lines; a fence opened by three or more backticks or tildes, at any indentation (as inside a list item), closes only on a line of the same character, at least as long, with nothing but whitespace after it; lines end only at `\n`, `\r\n` or `\r`. A requirement heading indented by up to three spaces SHALL be read as a requirement, as Spectra reads it. Paths SHALL be read as git stores them, never in git's quoted form, so a capability whose directory name is not ASCII is checked like any other. Two requirements with the same name in one capability SHALL make the command print `error`. So SHALL a code fence at the head revision that never closes, since the requirements after it would go unchecked. Outside code fences, a heading that starts with `### Requirement` but does not have the form `### Requirement: <name>` with a non-empty name SHALL make the command print `error`, and so SHALL a head revision at which the spec directory's `specs/` holds no tracked file, and a path under the spec directory that is not valid UTF-8 (the reason says so and carries no text of an exception). The command SHALL print one JSON line with `status` (`ok`, `missing` or `error`) and a list naming each requirement or Example that lacks its check, and SHALL exit 0, 1 or 2 in that order. `--base` is required: the caller names the range, so that a run on the default branch is checked against the commit it started from. The marker ties an Example to a test by name only; whether the test exercises what the Example states is judged by the reviewers of `idd-verify`.

Submodules. The tracked files at the head revision include the tracked files of every submodule of the repository at the commit that the head revision records for it, and in the same way the files of a submodule of a submodule. The command SHALL read that recorded commit, not the commit the submodule's working tree is on. It SHALL find the submodules itself, from the entries of the head revision's tree that record a commit; it SHALL NOT rely on git's own recursion into submodules, which passes over a submodule that is not checked out without saying so; the answer SHALL be the same whether or not the git configuration turns that recursion on (`submodule.recurse`). A file of a submodule is named by the submodule's path followed by the file's path, and the two exclusions (under the spec directory, ending in `.md`) apply to that name. A submodule whose own path is under the spec directory SHALL NOT be searched and SHALL NOT count as one that could not be searched: none of its files could count.

Order of the search. For each Example the command SHALL search the main repository first. When the marker is found there, the Example has its check and the command SHALL NOT run git in any submodule for it, so for a repository whose markers are all in its own files no entry that records a commit is listed and no submodule is examined, whatever its head revision records. Only when the marker is not found in the main repository are the submodules searched, and a marker found in one submodule settles the Example whatever the state of the others. When the marker of an Example is found, the Example has its check, whether or not every submodule could be searched. A submodule of a submodule is searched whenever its own six conditions hold, also when the search of the submodule that holds it failed; only when the tree of the outer one's recorded commit cannot be listed are the submodules inside it unknown.

Which submodules can be searched. A submodule SHALL be searched only when all six of these hold: (1) its path, as the tree records it, is relative and has no empty, `.` or `..` component; (2) its directory, after symbolic links are resolved, lies inside the working tree of the main repository; (3) the directory itself is not a symbolic link; (4) the directory holds an entry named `.git` of its own; (5) git, run in the directory, reports it as the top of its own working tree; (6) its object store holds the recorded commit. The command SHALL NOT run git in a directory that fails any of the first four: a directory of ordinary tracked files can be shaped like a git directory, and git would read, and act on, the configuration it holds. Nor SHALL it run git in the directory of any submodule when git is older than 2.45, the first version that honours `GIT_NO_LAZY_FETCH`, or when the version cannot be read: a submodule for which the first four hold then counts as one that could not be searched. In the directory of a submodule the command SHALL run git with `safe.bareRepository` set to `explicit`, with lazy fetching turned off (`GIT_NO_LAZY_FETCH=1`), and with the variables `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES` and `GIT_COMMON_DIR` removed from the environment it inherited. Before it searches a submodule the command SHALL ask git which objects of the recorded commit (its trees and the contents of its files) the object store lacks, without fetching any. A submodule is searched even when some are lacking, and a file that counts, found in it, settles the Example. When no file that counts is found in it, the submodule counts as one that could not be searched if its object store lacks an object of the recorded commit, if the search exits with a code other than 0 or 1, or if the tree of the recorded commit cannot be listed. What git writes to its error stream SHALL NOT change whether a submodule counts as searched, nor the reason reported for it. In the main repository a search that exits with a code other than 0 or 1 is `error`, as before; its reason is `git grep failed: ` followed by the first 200 characters of what git wrote to its error stream, also as before.

What is reported. When the marker is not found and every submodule was searched, the Example is reported as lacking its check, as before. When it is not found and at least one submodule could not be searched, the command SHALL print `error` and name the first such Example it meets, the submodules that could not be searched and the reason for each: an Example whose candidate files were not all read is not reported as lacking its check. The submodules are named by path, in the order of their paths and joined by `; `; a submodule of a submodule is named by its path under the outer one; when more than five could not be searched, the first five are named and the number of the others is stated; a path longer than 200 characters is cut to its first 200 followed by `...`. The reason is one of six: the path leaves the repository (conditions 1 and 2); the submodule is not checked out (conditions 3 and 4, or git names another directory as the top); git is older than 2.45 (stated also when its version cannot be read); git refused to open it (the git command of condition 5 fails); the recorded commit is not in its object store (condition 6); the recorded commit could not be read (its object store lacks an object of it, or the search or the listing of its tree failed). The reason given for a submodule SHALL NOT carry text from git's error stream. A path that is not valid UTF-8 is handled like any other path, and the command still prints one JSON line. A repository whose head revision records no submodule is searched in its own tracked files only: none of the rules for submodules changes its answer.

#### Scenario: An Example without a test is reported

- **GIVEN** a range that adds a requirement with one Example titled `status by exit code` to the capability `local-ci-gate`
- **AND** no tracked file outside `openspec/` contains `spec-example: local-ci-gate / status by exit code`
- **WHEN** `spec-change.py links` runs on that range
- **THEN** it prints `status` `missing`, names that Example, and exits 1

##### Example: what the link check reports

| Requirement in the range | Examples | Marker at the head revision | `No executable check:` line | `status` |
| --- | --- | --- | --- | --- |
| added | one | in `scripts/tests/x/test.sh` | absent | `ok` |
| added | one | absent | absent | `missing` |
| added | one | only in a file under `openspec/` | absent | `missing` |
| added | one | only in a file ending in `.md` | absent | `missing` |
| added | none | not applicable | absent | `missing` |
| added | none | not applicable | present, with a reason | `ok` |
| added | none | not applicable | present, with nothing after the colon | `missing` |
| added | one, with no title | not applicable | absent | `missing` |
| added | two with the same title as an Example elsewhere in the capability | present | absent | `missing` |
| changed | two | present for one, absent for the other | absent | `missing` |
| unchanged, with no Example | none | not applicable | absent | `ok` |
| removed in the range | not applicable | not applicable | not applicable | `ok` |
| no file under `openspec/specs/` differs | not applicable | not applicable | not applicable | `ok` |
| added | one | only a marker naming a longer title that starts with this one | absent | `missing` |
| added, under the heading `### Requirement Missing colon` | not applicable | not applicable | not applicable | `error` |
| any; `openspec/specs/` holds no tracked file at the head revision | not applicable | not applicable | not applicable | `error` |
| added, its only `##### Example:` line inside a code fence | none outside fences | not applicable | absent | `missing` |
| added, its only `No executable check:` line inside a code fence | none | not applicable | only inside a fence | `missing` |
| added, after a fence of four backticks that a line of three backticks does not close | its Example inside that fence | not applicable | absent | `missing` |
| added, under the heading `  ### Requirement: Alpha` (two leading spaces) | none | not applicable | absent | `missing` |
| added, its only `No executable check:` line inside a fence indented four spaces in a list item | none | not applicable | only inside that fence | `missing` |
| added, in a capability whose directory name is not ASCII (`中文能力`) | none | not applicable | absent | `missing` |
| added, in a capability whose directory name holds a double quote (`quo"te`) | none | not applicable | absent | `missing` |
| added, in a capability whose directory name is not valid UTF-8 | not applicable | not applicable | not applicable | `error`, with a reason that says so |
| added; a tree of the head revision outside the spec directory cannot be read | one | absent | absent | `error`; the reason is `git grep failed: ` followed by the first 200 characters of what git wrote to its error stream |
| added twice with the same name in one capability | not applicable | not applicable | not applicable | `error` |
| any, after a code fence that never closes | not applicable | not applicable | not applicable | `error` |
| `--base` names a revision that does not exist | not applicable | not applicable | not applicable | `error` |
| `--base` is not given | not applicable | not applicable | not applicable | usage error, exit 64 |

##### Example: markers in submodules

| Where the marker of the Example is at the head revision | Submodules recorded at the head revision | `status` |
| --- | --- | --- |
| in a tracked file of a submodule, at the commit the head revision records | one, checked out | `ok` |
| in a tracked file of a submodule of a submodule | both checked out | `ok` |
| in a tracked file of a submodule whose path holds a space | one, checked out | `ok` |
| only in the recorded commit of a submodule whose working tree is on a later commit without it | one, checked out | `ok` |
| only in a later commit of a submodule, which its working tree is on, not in the recorded commit | one, checked out | `missing` |
| only in a file of a submodule that ends in `.md` | one, checked out | `missing` |
| nowhere | one, checked out | `missing` |
| nowhere in the main repository | one, not checked out | `error`, naming the Example and the submodule's path |
| in a tracked file of the main repository | one, not checked out | `ok` |
| nowhere in the main repository | one, checked out, whose object store lacks the recorded commit | `error`, naming the Example and the submodule's path |
| in a tracked file of the main repository | one, checked out, whose object store lacks the recorded commit; `submodule.recurse` is true in the repository's git configuration | `ok` |
| nowhere in the main repository | one, checked out, whose object store lacks the recorded commit; `submodule.recurse` is true in the repository's git configuration | `error`, naming the Example and the submodule's path |
| only in the recorded commits of two submodules | two, neither checked out | `error`, naming the Example and both paths, joined by `; ` |
| only in a submodule of a submodule | the outer one checked out, the inner one not | `error`, naming the Example and the inner submodule by its path under the outer one |
| only in a tracked file of a submodule that is mounted under `openspec/` | one, checked out | `missing` |
| in a tracked file of the main repository | one whose path is not valid UTF-8, not checked out | `ok` |
| nowhere | one whose path is not valid UTF-8, not checked out | `error` on one JSON line, exit 2 |
| in a tracked file of the main repository | one, checked out, holding the recorded commit but not the tree of that commit | `ok` |
| nowhere in the main repository | one, checked out, holding the recorded commit but not the tree of that commit | `error`, naming the Example and the submodule's path, with no text from git's error stream |
| nowhere | one, checked out, whose object store lacks the content of one file of the recorded commit | `error`, naming the Example and the submodule's path, with no text from git's error stream |
| nowhere | one, checked out, whose recorded commit records a second submodule; at that second path the working tree holds ordinary files shaped like a git directory (`HEAD`, `config`, `objects/`, `refs/`) and no `.git` entry, and that `config` names a command to run | `error`, naming the second path as not checked out; the command named in that `config` does not run |
| in a tracked file of the main repository | the same two, with the same files at the second path | `ok`; no git command runs in the directory of a submodule, and the command named in that `config` does not run |
| only in a repository outside the main repository, at a path with a `..` component that the head revision's tree records as a submodule | that one | `error`, naming the path as one that leaves the repository; the same answer when nothing is at that outside path |
| only in a repository outside the main repository, reached through a symbolic link in the working tree that is part of a recorded submodule path | that one | `error`, naming the path as one that leaves the repository |
| in a tracked file of a submodule whose path ends in a space | one, checked out | `ok` |
| nowhere | one, not checked out, mounted under `openspec/` | `missing` |
| only in a tracked file of a submodule | one, checked out elsewhere inside the working tree of the main repository, whose own directory is a symbolic link to that checkout | `error`, naming the Example and the submodule's path as not checked out |
| in a tracked file of a submodule | one, checked out; the variable `GIT_DIR` is set to the git directory of the main repository | `ok` |
| only in the recorded commits of seven submodules | seven, none checked out | `error`, naming the Example, the first five paths in order and the number of the other two |
| nowhere | one whose directory holds a `.git` entry that git cannot open | `error`, naming the Example and the submodule's path as one git refused to open |
| nowhere | one whose directory holds an empty `.git` directory and, beside it, ordinary files shaped like a git directory (`HEAD`, `config`, `objects/`, `refs/`) whose `config` names a command to run | `error`, naming the submodule's path as one git refused to open; the command named in that `config` does not run |
| in a tracked file of the main repository | one, checked out as a partial clone that never fetched the file contents of the recorded commit | `ok`; nothing is fetched into the submodule |
| nowhere | one, checked out as a partial clone that never fetched the file contents of the recorded commit | `error`, naming the Example and the submodule's path; nothing is fetched into the submodule |
| nowhere | one, not checked out, whose path is longer than 200 characters | `error`, naming the first 200 characters of the path followed by `...` |
| in a tracked file of one submodule | two; the one with the marker checked out, the other not | `ok` |
| only in a file ending in `.md` of a submodule | one, checked out, whose object store lacks the content of another file of the recorded commit | `error`, naming the Example and the submodule's path |
| only in a tracked file of a submodule | one whose `.git` entry git opens, with the working tree of that git directory set to the parent directory, so that git names the parent as the top | `error`, naming the Example and the submodule's path as not checked out |
| only in a submodule of a submodule | three recorded paths: `a`, checked out; its own submodule `a/inner`, not checked out; and `a-b`, not checked out | `error`, naming `a-b` before `a/inner` |
| nowhere | one, at a path with a `.` component that the head revision's tree records | `error`, naming the path as one that leaves the repository |
| in a tracked file of a submodule | one, checked out; the six variables named above are all set to the git directory, working tree, index and object store of the main repository | `ok` |
| only in the recorded commit of a submodule, which the checked-out submodule's own object store lacks | one, checked out; the variable `GIT_ALTERNATE_OBJECT_DIRECTORIES` names an object store that holds that commit | `error`, naming the Example and the submodule's path, with the recorded commit as not in its object store |
| only in a submodule of a submodule, checked out and complete | the outer one checked out, its object store lacking the content of one unrelated file of its recorded commit | `ok` |
| nowhere | the same two | `error`, naming the Example and the outer submodule's path only, with its recorded commit as one that could not be read |
| in a tracked file of one submodule | two; the other one is not checked out and comes first in the order of the paths | `ok` |
| in a tracked file that counts, of a submodule whose object store lacks the content of another file of the recorded commit | one, checked out | `ok` |
| nowhere | one, checked out, holding every object of the recorded commit; git writes to its error stream during the search (`GIT_TRACE=1`) | `missing` |
| only in a tracked file of a submodule | one, checked out; git reports a version older than 2.45, or one that cannot be read | `error`, naming the Example and the submodule's path with git as older than 2.45; no git command runs in the directory of the submodule |
| in a tracked file of the main repository | one, checked out; git reports a version older than 2.45 | `ok` |
| nowhere | one, checked out, whose object store holds a damaged copy of the content of one file of the recorded commit (present, not readable) | `error`, naming the Example and the submodule's path, with its recorded commit as one that could not be read |
