## Purpose

Defines how every issue that IDD implements leaves a change in the repository's specs, whatever tier its Diagnosis records: which cases are exempt, how the spec change is produced through Spectra behind IDD's own wrappers, when the change is archived, and how each added or modified requirement is tied to an executable check. It exists so that a later change has a written requirement and a runnable check to be judged against.

## ADDED Requirements

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

`scripts/spec-change.py declared --file <comment>` SHALL read the comment and print one JSON line with `form` (`change`, `no-behaviour-change`, `third-party-clone`, `legacy` or `invalid`) and `changes` (the names, in order). A comment without the marker and without a `**Spec**:` line is `legacy`: it was posted before this capability and is not held to it. A line inside a code fence is not read. The command SHALL exit 0 for the first four forms, 1 for `invalid` and 2 when the file cannot be read.

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
| the file does not exist | no JSON line | not applicable | 2 |

### Requirement: Spec changes go through Spectra behind IDD wrappers

`idd-implement` SHALL be the wrapper for the Simple tier and `idd-plan` the wrapper for the Plan tier, and both SHALL follow one shared contract kept in `references/spec-wrapper.md`. Which phase of `idd-all` invokes which skill stays stated once, in the dispatch table of `skills/idd-all/SKILL.md`; this requirement constrains what the invoked skills do. A wrapper SHALL create one Spectra change per issue, named `idd-<N>-<slug>`, SHALL produce the proposal, the spec delta and the tasks through Spectra's propose workflow, and SHALL implement the tasks through Spectra's apply workflow, with the test of each Example written before the code it checks. For the Simple tier the wrapper SHALL use the light form: no discuss step and no design artifact. For the Plan tier in an attended run, `idd-plan` SHALL present the proposal and the tasks for approval in plan mode before apply starts, and SHALL hand the approved change to `idd-implement`, which applies it and does not propose again. A Plan-tier issue in an unattended run goes to `idd-implement` as it does today and takes the light form. For the Spectra tier the existing chain of discuss, propose and apply stays as it is. Outside the wrappers and the shared contract, no IDD skill SHALL depend on the arguments or the output of Spectra's propose or apply skills for the Simple and Plan tiers.

No executable check: the wrappers are carried out by a model that follows SKILL.md; what they leave behind is checked by the Examples of the other requirements of this capability (the Spec line, the archive, the links).

#### Scenario: A Simple issue uses the light form

- **GIVEN** an issue whose Diagnosis records `Simple`
- **WHEN** `idd-implement` runs
- **THEN** it creates the change `idd-<N>-<slug>` with a proposal, a spec delta and tasks, creates no design artifact, runs no discuss step, and applies the tasks

#### Scenario: A Plan issue keeps its approval in an attended run

- **GIVEN** an attended run and an issue whose Diagnosis records `Plan`
- **WHEN** `idd-plan` runs
- **THEN** it produces the proposal and the tasks, asks for approval in plan mode, and only after approval hands the change to `idd-implement`, which applies it

### Requirement: The change is archived on the branch before verify

After apply and before `idd-verify`, the wrapper (for the Spectra tier, `idd-all`) SHALL run Spectra's verify skill for the change, SHALL archive the change with `spectra archive`, SHALL confirm that the archive landed in the working tree it is about to commit, and SHALL commit the result on the same branch, so that the commit `idd-verify` reviews contains the updated files under `openspec/specs/` and the archived change. When Spectra's verify reports a critical issue, the change SHALL NOT be archived until the issue is fixed. No archive commit SHALL be added to the default branch after the merge.

`scripts/spec-change.py archived --file <comment> --cwd <dir> --ref <rev>` SHALL answer whether every change the comment declares is archived at that revision: for each name, `openspec/changes/<name>/` is absent and exactly one directory under `openspec/changes/archive/` is named `<YYYY-MM-DD>-<name>`. It SHALL print one JSON line with `status` (`pass`, `refuse` or `error`) and the names that are not archived, and SHALL exit 0, 1 or 2 in that order. A comment whose form is `no-behaviour-change`, `third-party-clone` or `legacy` passes; an `invalid` comment is refused.

#### Scenario: The reviewed commit carries the applied spec

- **GIVEN** a Simple-tier run whose tasks are all complete and whose Spectra verify reports no critical issue
- **WHEN** the wrapper archives the change and commits
- **THEN** `spec-change.py archived` with `--ref HEAD` prints `pass`, and `idd-verify` reviews that commit

#### Scenario: A critical issue holds the archive

- **GIVEN** Spectra's verify reports that a requirement of the change has no implementation
- **WHEN** the wrapper reads the report
- **THEN** it does not archive, and `openspec/changes/idd-<N>-<slug>/` is still present

##### Example: whether the declared changes are archived at a commit

| `**Spec**:` line | At the revision: `openspec/changes/<name>/` | At the revision: directories under `openspec/changes/archive/` | `status` | Exit |
| --- | --- | --- | --- | --- |
| `change idd-42-fix-timeout` | absent | `2026-11-10-idd-42-fix-timeout` | `pass` | 0 |
| `change idd-42-fix-timeout` | present | none for this name | `refuse` | 1 |
| `change idd-42-fix-timeout` | present | `2026-11-10-idd-42-fix-timeout` | `refuse` | 1 |
| `change idd-42-fix-timeout` | absent | none for this name | `refuse` | 1 |
| `change idd-42-fix` | absent | only `2026-11-10-idd-42-fix-timeout` | `refuse` | 1 |
| `change idd-42-a, idd-42-b` | both absent | only `2026-11-10-idd-42-a` | `refuse`, naming `idd-42-b` | 1 |
| `no behaviour change` | not read | not read | `pass` | 0 |
| `third-party clone` | not read | not read | `pass` | 0 |
| a legacy comment | not read | not read | `pass` | 0 |
| an invalid comment | not read | not read | `refuse` | 1 |
| `change idd-42-fix-timeout` | the revision does not exist | not read | `error` | 2 |

### Requirement: Added and modified requirements carry an executable check

`scripts/spec-change.py links --base <rev>` SHALL compare the files under `openspec/specs/` at `<rev>` and at `--head` (default `HEAD`). For every requirement that is new or whose text differs between the two, it SHALL require one of two things: at least one `##### Example:` under the requirement, where each such Example has a title that is unique within its capability and a tracked file at the head revision, outside `openspec/` and not ending in `.md`, that contains the marker `spec-example: <capability> / <Example title>`; or a line under the requirement that starts with `No executable check:` followed by a reason. A requirement that does not differ SHALL NOT be checked. The command SHALL print one JSON line with `status` (`ok`, `missing` or `error`) and a list naming each requirement or Example that lacks its check, and SHALL exit 0, 1 or 2 in that order. `--base` is required: the caller names the range, so that a run on the default branch is checked against the commit it started from. The marker ties an Example to a test by name only; whether the test exercises what the Example states is judged by the reviewers of `idd-verify`.

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
| `--base` names a revision that does not exist | not applicable | not applicable | not applicable | `error` |
| `--base` is not given | not applicable | not applicable | not applicable | usage error, exit 64 |

### Requirement: A fix after a verify round goes through the same wrapper

A fix made after a verify round SHALL leave the specs agreeing with the behaviour on the same branch. When the fix adds or modifies a requirement, it SHALL be made as a further Spectra change of the same issue, named `idd-<N>-fix<k>` where `k` is the number of the verify round, through the same wrapper in the light form, archived before the next verify round; the next Implementation Complete comment SHALL list every change of the issue on its `**Spec**:` line. When a requirement that states the behaviour already exists with an Example, the fix SHALL add or correct the test that carries the Example's marker and needs no further change. A fix for a Blocking finding SHALL leave a requirement that states the property the finding showed was violated, with an Example whose test fails on the commit before the fix.

What a fix round leaves:

| Finding | Before the fix | The fix round leaves | Further change |
| --- | --- | --- | --- |
| Blocking: the behaviour is wrong and no requirement states it | no requirement | an added requirement, an Example, a test that failed before the fix | `idd-<N>-fix<k>` |
| Blocking: the behaviour is wrong; a requirement states it and has no Example | a requirement with no Example | the requirement gains an Example, and its test | `idd-<N>-fix<k>` |
| Blocking: the behaviour is wrong; a requirement and an Example state it | the test is missing or does not check it | the corrected test with the marker | none |
| a lower finding whose fix changes behaviour that no requirement states | no requirement | an added or modified requirement, an Example, a test | `idd-<N>-fix<k>` |
| a finding fixed by wording in documentation only | not applicable | no spec change | none |

No executable check: whether a requirement states the violated property, and whether its test failed before the fix, are judged by the reviewers of the next verify round; the link check of the fix round's range covers the added requirement.

#### Scenario: A Blocking finding becomes a requirement with a check

- **GIVEN** verify round 2 reports as Blocking that a script exits 0 on a failed lookup, and no requirement states its exit codes
- **WHEN** the fix round runs
- **THEN** the branch gains the archived change `idd-<N>-fix2` whose requirement states the exit code, with an Example and a test that fails on the commit before the fix, and the new Implementation Complete comment lists both changes

### Requirement: A repository without Spectra stops and a third-party clone proceeds

Before a wrapper creates any artifact or commit for an implementation, it SHALL run `scripts/spec-change.py preflight --cwd <dir> --can-write <yes|no>`, which prints one JSON line with `status`. `third-party` (the session account cannot write to the repository): the wrapper SHALL NOT create `openspec/`, SHALL implement the issue as it was implemented before this capability, and SHALL declare `**Spec**: third-party clone`. `linked-worktree` (the working tree is a git linked worktree, where Spectra writes into the main working tree), `install-spectra` (no `spectra` command on PATH) and `init-openspec` (no `openspec/` directory): the wrapper SHALL stop before it creates anything, and SHALL print the reason and, for the last two, the command that installs Spectra or `spectra init`. `ready`: the wrapper proceeds. The command SHALL exit 0 for `ready` and `third-party` and 1 for the three stops.

#### Scenario: The maintainer's own repository has no Spectra

- **GIVEN** a repository the session account can write to and no `spectra` command on PATH
- **WHEN** `idd-implement` starts on a Simple-tier issue
- **THEN** preflight prints `install-spectra`, the wrapper stops with the install command, and no commit is made

##### Example: preflight by write access and Spectra state

| `--can-write` | Linked worktree | `spectra` on PATH | `openspec/` exists | `status` | Exit |
| --- | --- | --- | --- | --- | --- |
| `no` | no | yes | yes | `third-party` | 0 |
| `no` | yes | no | no | `third-party` | 0 |
| `yes` | yes | yes | yes | `linked-worktree` | 1 |
| `yes` | no | no | yes | `install-spectra` | 1 |
| `yes` | no | no | no | `install-spectra` | 1 |
| `yes` | no | yes | no | `init-openspec` | 1 |
| `yes` | no | yes | yes | `ready` | 0 |
| a value other than `yes` or `no` | any | any | any | usage error | 64 |

### Requirement: Close requires the issue's change to be archived

`idd-close` SHALL take the issue's newest `## Implementation Complete` comment posted by an account that can write to the repository, and SHALL run `spec-change.py archived` on it with `--ref` set to the default branch as the remote has it. It SHALL close the issue only when the command prints `pass`. On `refuse` it SHALL stop and name the changes that are not archived or the fault in the `**Spec**:` line; on `error` it SHALL stop and say the default branch could not be read. An issue with no Implementation Complete comment is not held to this rule.

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
