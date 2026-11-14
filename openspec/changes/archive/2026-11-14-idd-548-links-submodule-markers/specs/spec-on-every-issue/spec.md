## MODIFIED Requirements

### Requirement: Added and modified requirements carry an executable check

`scripts/spec-change.py links --base <rev>` SHALL compare the files under `openspec/specs/` at `<rev>` and at `--head` (default `HEAD`). For every requirement that is new or whose text differs between the two, it SHALL require one of two things: at least one `##### Example:` under the requirement, where each such Example has a title that is unique within its capability and a tracked file at the head revision, outside `openspec/` and not ending in `.md`, that contains the marker `spec-example: <capability> / <Example title>` (a tracked file of a submodule counts, as the paragraph "Submodules" below describes); or a line under the requirement that starts with `No executable check:` followed by a reason. A requirement that does not differ SHALL NOT be checked. A marker counts only when nothing but whitespace, or the comment closer `-->` or `*/`, follows the Example title on its line. Lines inside a code fence are not read as `##### Example:` or `No executable check:` lines; a fence opened by three or more backticks or tildes, at any indentation (as inside a list item), closes only on a line of the same character, at least as long, with nothing but whitespace after it; lines end only at `\n`, `\r\n` or `\r`. A requirement heading indented by up to three spaces SHALL be read as a requirement, as Spectra reads it. Paths SHALL be read as git stores them, never in git's quoted form, so a capability whose directory name is not ASCII is checked like any other. Two requirements with the same name in one capability SHALL make the command print `error`. So SHALL a code fence at the head revision that never closes, since the requirements after it would go unchecked. Outside code fences, a heading that starts with `### Requirement` but does not have the form `### Requirement: <name>` with a non-empty name SHALL make the command print `error`, and so SHALL a head revision at which the spec directory's `specs/` holds no tracked file. The command SHALL print one JSON line with `status` (`ok`, `missing` or `error`) and a list naming each requirement or Example that lacks its check, and SHALL exit 0, 1 or 2 in that order. `--base` is required: the caller names the range, so that a run on the default branch is checked against the commit it started from. The marker ties an Example to a test by name only; whether the test exercises what the Example states is judged by the reviewers of `idd-verify`.

Submodules. The tracked files at the head revision include the tracked files of every submodule of the repository at the commit that the head revision records for it, and in the same way the files of a submodule of a submodule. The command SHALL read that recorded commit, not the commit the submodule's working tree is on. It SHALL find the submodules itself, from the entries of the head revision's tree that record a commit, and SHALL search each one whose directory is the top of its own working tree and whose object store holds the recorded commit; it SHALL NOT rely on git's own recursion into submodules, which passes over a submodule that is not checked out without saying so; the answer SHALL be the same whether or not the git configuration turns that recursion on (`submodule.recurse`). A file of a submodule is named by the submodule's path followed by the file's path, and the two exclusions (under the spec directory, ending in `.md`) apply to that name. When the marker of an Example is found, the Example has its check, whether or not every submodule could be searched. When it is not found and every submodule was searched, the Example is reported as lacking its check, as before. When it is not found and at least one submodule could not be searched (its directory is not a checked-out working tree of its own, or the recorded commit is not in its object store), the command SHALL print `error` and name the first such Example it meets, the path of each submodule that could not be searched (several are joined by `; `, and a submodule of a submodule is named by its path under the outer one) and the reason: an Example whose candidate files were not all read is not reported as lacking its check. A repository whose head revision records no submodule is checked exactly as before.

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
