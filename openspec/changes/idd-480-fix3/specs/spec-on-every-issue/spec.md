## MODIFIED Requirements

### Requirement: Every implemented issue leaves a spec change or a declared exemption

When an issue is implemented, the step that finishes the implementation SHALL post a `## Implementation Complete` comment that carries the marker `<!-- idd:comment type=implementation-complete -->` and exactly one line that starts with `**Spec**:`. The line SHALL take one of three forms: `**Spec**: change <name>` followed by further names separated by commas when the issue has more than one change (each name is a Spectra change the branch archives); `**Spec**: no behaviour change`; or `**Spec**: third-party clone`. The tier of the Diagnosis (Simple, Plan, Spectra or SDD-warranted) SHALL NOT decide which form is used; it decides only which steps come before the implementation. An issue whose trusted Diagnosis records the type meeting is not implemented and has no such comment.

`no behaviour change` SHALL be declared only in one of four cases, and no other case SHALL be treated as one of them because it resembles it: (a) the change touches only documentation or narrative text that nothing executes; (b) the deliverable is a one-off analysis, a script with no caller together with its report; (c) the change touches only tests or CI configuration; (d) a refactor after which, for every skill, script, hook and rule in the repository, none of these differ: the text it prints or posts, its exit code, the files it writes or deletes, the remote calls it makes, the questions it asks, and the steps it runs. A skill file, a rule file and a reference that a skill executes are not documentation: rewording one is case (d) only when every step, question, command and output of the skill stays the same. `third-party clone` SHALL be declared when the session account cannot write to the repository.

Which form applies to a deliverable:

| Diagnosis | Deliverable | `**Spec**:` line |
| --- | --- | --- |
| Simple | a script prints a different message | `change idd-<N>-<slug>` |
| Plan | a helper shared by four callers returns a different value | `change idd-<N>-<slug>` |
| Spectra | a new skill | `change <name>` |
| Simple | a step of a SKILL.md is reworded so that the skill asks one question fewer | `change idd-<N>-<slug>` |
| Simple | a typo in `README.md` | `no behaviour change` (a) |
| Simple | a one-off analysis script and its report | `no behaviour change` (b) |
| Simple | a new case in an existing test suite | `no behaviour change` (c) |
| Plan | a function is split in two and every output stays the same | `no behaviour change` (d) |
| any tier, in a clone the account cannot write to | any | `third-party clone` |

`scripts/spec-change.py declared --file <comment>` SHALL read the comment and print one JSON line with `form` (`change`, `no-behaviour-change`, `third-party-clone`, `legacy` or `invalid`) and `changes` (the names, in order). A comment without the marker and without a `**Spec**:` line is `legacy`: it was posted before this capability and is not held to it. A line inside a code fence is not read; fences are judged as for the link check (three or more backticks or tildes at any indentation, closed only by a line of the same character at least as long with nothing after it), and lines end only at `\n`, `\r\n` or `\r`. The command SHALL exit 0 for the first four forms, 1 for `invalid` and 2 when the file cannot be read.

#### Scenario: A Simple-tier fix leaves a spec change

- **GIVEN** an issue whose Diagnosis records `Simple` and whose fix changes what a script prints
- **WHEN** `idd-implement` finishes
- **THEN** the branch changes a file under `openspec/specs/` and the Implementation Complete comment carries the marker and `**Spec**: change idd-<N>-<slug>`

#### Scenario: A typo fix declares the exemption

- **GIVEN** an issue whose only change corrects a typo in `README.md`
- **WHEN** `idd-implement` finishes
- **THEN** no file under `openspec/specs/` changes and the comment carries `**Spec**: no behaviour change`

##### Example: reading the Spec line

| Comment | `form` | `changes` | Exit |
| --- | --- | --- | --- |
| marker, `**Spec**: change idd-42-fix-timeout` | `change` | `idd-42-fix-timeout` | 0 |
| marker, `**Spec**: change idd-42-fix-timeout, idd-42-fix2` | `change` | both names, in that order | 0 |
| marker, `**Spec**: no behaviour change` | `no-behaviour-change` | empty | 0 |
| marker, `**Spec**: third-party clone` | `third-party-clone` | empty | 0 |
| no marker, no `**Spec**:` line | `legacy` | empty | 0 |
| no marker, `**Spec**: no behaviour change` | `no-behaviour-change` | empty | 0 |
| marker, no `**Spec**:` line | `invalid` | empty | 1 |
| marker, two `**Spec**:` lines | `invalid` | empty | 1 |
| marker, `**Spec**: change` with no name | `invalid` | empty | 1 |
| marker, `**Spec**: change ../x` | `invalid` | empty | 1 |
| marker, `**Spec**: nothing to see` | `invalid` | empty | 1 |
| marker, the only `**Spec**:` line is inside a code fence | `invalid` | empty | 1 |
| marker, the only `**Spec**:` line is inside a four-backtick fence that also holds a three-backtick line | `invalid` | empty | 1 |
| marker, `**Spec**: no behaviour change` follows other text on the same line after U+2028 | `invalid` | empty | 1 |
| the file does not exist | no JSON line | not applicable | 2 |

### Requirement: The spec directory is resolved the way Spectra resolves it

Every path this capability names under `openspec/` is relative to the spec directory Spectra uses for the repository, and `scripts/spec-change.py` SHALL resolve it the same way: the value of an uncommented `spec_dir:` line in `.spectra.yaml` at the top of the repository, or `openspec` when the file has no such line or does not exist. `archived` and `links` SHALL read `.spectra.yaml` at the revision they check; `preflight` SHALL read it in the working tree. A value that is absolute, empty, starts with `-` or `:`, names the repository root (`.`), or leaves the repository (a `..` component) SHALL be an `error`, not a fallback to `openspec`, and so SHALL a `.spectra.yaml` that exists but is not a regular file: in the working tree, or at the revision (a directory or a symbolic link there). Paths are given to git literally, never as pathspec magic.

#### Scenario: A repository initialised by Spectra 3

- **GIVEN** `.spectra.yaml` has `spec_dir: docs/spectra` and the change was archived under `docs/spectra/changes/archive/`
- **WHEN** `spec-change.py archived` runs on that revision
- **THEN** it looks under `docs/spectra/` and prints `pass`

##### Example: spec directory by .spectra.yaml

| `.spectra.yaml` at the revision | Spec directory | Result |
| --- | --- | --- |
| `spec_dir: docs/spectra` | `docs/spectra` | read there |
| `spec_dir: "docs/specs"` | `docs/specs` | read there |
| a file whose only `spec_dir` line is commented out | `openspec` | read there |
| no `.spectra.yaml` | `openspec` | read there |
| `spec_dir: /srv/specs` | not applicable | `error` |
| `spec_dir: ../specs` | not applicable | `error` |
| `spec_dir:` with no value | not applicable | `error` |
| `spec_dir: -x` | not applicable | `error` |
| `spec_dir: .` | not applicable | `error` |
| `spec_dir: ":(top)openspec"` | not applicable | `error` |
| a directory named `.spectra.yaml` at the revision | not applicable | `error` |

### Requirement: Added and modified requirements carry an executable check

`scripts/spec-change.py links --base <rev>` SHALL compare the files under `openspec/specs/` at `<rev>` and at `--head` (default `HEAD`). For every requirement that is new or whose text differs between the two, it SHALL require one of two things: at least one `##### Example:` under the requirement, where each such Example has a title that is unique within its capability and a tracked file at the head revision, outside `openspec/` and not ending in `.md`, that contains the marker `spec-example: <capability> / <Example title>`; or a line under the requirement that starts with `No executable check:` followed by a reason. A requirement that does not differ SHALL NOT be checked. A marker counts only when nothing but whitespace, or the comment closer `-->` or `*/`, follows the Example title on its line. Lines inside a code fence are not read as `##### Example:` or `No executable check:` lines; a fence opened by three or more backticks or tildes, at any indentation (as inside a list item), closes only on a line of the same character, at least as long, with nothing but whitespace after it; lines end only at `\n`, `\r\n` or `\r`. A requirement heading indented by up to three spaces SHALL be read as a requirement, as Spectra reads it. Two requirements with the same name in one capability SHALL make the command print `error`. So SHALL a code fence at the head revision that never closes, since the requirements after it would go unchecked. Outside code fences, a heading that starts with `### Requirement` but does not have the form `### Requirement: <name>` with a non-empty name SHALL make the command print `error`, and so SHALL a head revision at which the spec directory's `specs/` holds no tracked file. The command SHALL print one JSON line with `status` (`ok`, `missing` or `error`) and a list naming each requirement or Example that lacks its check, and SHALL exit 0, 1 or 2 in that order. `--base` is required: the caller names the range, so that a run on the default branch is checked against the commit it started from. The marker ties an Example to a test by name only; whether the test exercises what the Example states is judged by the reviewers of `idd-verify`.

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
| added twice with the same name in one capability | not applicable | not applicable | not applicable | `error` |
| any, after a code fence that never closes | not applicable | not applicable | not applicable | `error` |
| `--base` names a revision that does not exist | not applicable | not applicable | not applicable | `error` |
| `--base` is not given | not applicable | not applicable | not applicable | usage error, exit 64 |

### Requirement: Close requires the issue's change to be archived

`idd-close` SHALL fetch the issue's comments with `gh api --paginate`, SHALL choose the Implementation Complete comment with `spec-change.py ic` (requirement "One way to choose the Implementation Complete comment"), and SHALL run `spec-change.py archived` on it with `--ref` set to the default branch as the remote has it. It SHALL close the issue only when the command prints `pass`. On `refuse` it SHALL stop and name the changes that are not archived or the fault in the `**Spec**:` line; on `error` it SHALL stop and say the default branch could not be read. For a comment that declares a change, it SHALL read the default branch by fetching it from the remote and checking the commit that fetch returned, and SHALL stop when `gh repo view` cannot name the default branch or the fetch fails; for any other comment the default branch is not read, since `archived` answers from the comment alone. When the comments cannot be fetched or `ic` exits 2, it SHALL stop and say the comments could not be read; it SHALL NOT treat that as an issue with no Implementation Complete comment. An issue with no Implementation Complete comment is not held to this rule. A retroactive close (`idd-close --retroactive`, for an issue that is already closed) skips this gate, as it skips the gates before it.

#### Scenario: An unarchived change holds the close

- **GIVEN** an Implementation Complete comment with the marker and `**Spec**: change idd-42-fix-timeout`
- **AND** `openspec/changes/idd-42-fix-timeout/` still exists on the default branch
- **WHEN** `idd-close` runs its gates
- **THEN** it does not close the issue and says the change is not archived

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
