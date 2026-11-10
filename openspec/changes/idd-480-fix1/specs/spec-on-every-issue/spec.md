## ADDED Requirements

### Requirement: One way to choose the Implementation Complete comment

`scripts/spec-change.py ic --comments <file>` SHALL read the comments of an issue as GitHub's REST API returns them (one JSON array, or several arrays one after another as `gh api --paginate` prints them) and SHALL print the body of the newest comment whose `author_association` is `OWNER`, `MEMBER` or `COLLABORATOR` and whose body starts with the marker `<!-- idd:comment type=implementation-complete -->` or, after leading whitespace, with `## Implementation Complete`. It SHALL print nothing when no comment qualifies. The author association stands in for write access: the comments API does not report a commenter's permission, and a member or collaborator can lack write access to the repository. The command SHALL exit 0 in both cases and 2, printing nothing, when the file cannot be read or is not such JSON. `idd-verify` and `idd-close` SHALL choose the comment with this command and with no other selection.

#### Scenario: The newest trusted comment wins

- **GIVEN** an Implementation Complete comment by the owner, and a later one by a member
- **WHEN** `spec-change.py ic` reads the comments
- **THEN** it prints the member's comment

##### Example: choosing the Implementation Complete comment

| Comments, oldest first | Printed | Exit |
| --- | --- | --- |
| an Implementation Complete by an `OWNER`, then one by a `MEMBER` | the `MEMBER`'s body | 0 |
| an Implementation Complete by a `COLLABORATOR`, then one by a `CONTRIBUTOR` | the `COLLABORATOR`'s body | 0 |
| a body that starts with the marker, by an `OWNER` | that body | 0 |
| a `## Diagnosis` by an `OWNER` only | nothing | 0 |
| no comments | nothing | 0 |
| two pages printed one after the other, the newest Implementation Complete on the second | the comment on the second page | 0 |
| the file does not exist | nothing | 2 |
| the file is not JSON | nothing | 2 |

## MODIFIED Requirements

### Requirement: Spec changes go through Spectra behind IDD wrappers

`idd-implement` SHALL be the wrapper for the Simple tier and `idd-plan` the wrapper for the Plan tier, and both SHALL follow one shared contract kept in `references/spec-wrapper.md`. Which phase of `idd-all` invokes which skill stays stated once, in the dispatch table of `skills/idd-all/SKILL.md`; this requirement constrains what the invoked skills do. A wrapper SHALL create one Spectra change per issue, named `idd-<N>-<slug>`, SHALL produce the proposal, the spec delta and the tasks through Spectra's propose workflow, and SHALL implement the tasks through Spectra's apply workflow, with the test of each Example written before the code it checks. When Spectra's propose workflow leaves the change parked, the wrapper SHALL take it out of the parked state itself before apply. In a run that `references/unattended-contract.md` marks as unattended, the wrapper SHALL tell Spectra's propose and apply skills not to ask questions and to record each choice they would have asked about as a line starting with `ASSUMPTION:` in the artifact. For the Simple tier the wrapper SHALL use the light form: no discuss step and no design artifact. For the Plan tier in an attended run, `idd-plan` SHALL present the proposal and the tasks for approval in plan mode before apply starts, and SHALL hand the approved change to `idd-implement`, which applies it and does not propose again. A Plan-tier issue in an unattended run goes to `idd-implement` as it does today and takes the light form. For the Spectra tier the existing chain of discuss, propose and apply stays as it is, preceded by the same preflight as the other tiers; that preflight SHALL run before any check that Spectra is installed, so that a third-party clone proceeds without Spectra, and Spectra's propose skill SHALL receive the same instructions on Examples, unique titles and test markers as in the other tiers. Outside the wrappers and the shared contract, no IDD skill SHALL depend on the arguments or the output of Spectra's propose or apply skills for the Simple and Plan tiers.

No executable check: the wrappers are carried out by a model that follows SKILL.md; what they leave behind is checked by the Examples of the other requirements of this capability (the Spec line, the archive, the links).

#### Scenario: A Simple issue uses the light form

- **GIVEN** an issue whose Diagnosis records `Simple`
- **WHEN** `idd-implement` runs
- **THEN** it creates the change `idd-<N>-<slug>` with a proposal, a spec delta and tasks, creates no design artifact, runs no discuss step, and applies the tasks

#### Scenario: A Plan issue keeps its approval in an attended run

- **GIVEN** an attended run and an issue whose Diagnosis records `Plan`
- **WHEN** `idd-plan` runs
- **THEN** it produces the proposal and the tasks, asks for approval in plan mode, and only after approval hands the change to `idd-implement`, which applies it

#### Scenario: An unattended run does not stop on Spectra's questions

- **GIVEN** an unattended `/idd-all` run on a Simple issue, and a change that Spectra's propose workflow left parked
- **WHEN** the wrapper reaches apply
- **THEN** it unparks the change, and Spectra's apply skill receives the instruction not to ask whether to continue

#### Scenario: A Spectra-tier issue in a third-party clone without Spectra

- **GIVEN** a clone the session account cannot write to, no `spectra` command on PATH, and a Diagnosis that records `Spectra`
- **WHEN** `idd-all` reaches Phase 3b
- **THEN** the preflight prints `third-party` before any check for Spectra, Phase 3b does not run, and the issue is implemented on the Simple path with `**Spec**: third-party clone`

### Requirement: Added and modified requirements carry an executable check

`scripts/spec-change.py links --base <rev>` SHALL compare the files under `openspec/specs/` at `<rev>` and at `--head` (default `HEAD`). For every requirement that is new or whose text differs between the two, it SHALL require one of two things: at least one `##### Example:` under the requirement, where each such Example has a title that is unique within its capability and a tracked file at the head revision, outside `openspec/` and not ending in `.md`, that contains the marker `spec-example: <capability> / <Example title>`; or a line under the requirement that starts with `No executable check:` followed by a reason. A requirement that does not differ SHALL NOT be checked. A marker counts only when nothing but whitespace, or the comment closer `-->` or `*/`, follows the Example title on its line. Outside code fences, a heading that starts with `### Requirement` but does not have the form `### Requirement: <name>` with a non-empty name SHALL make the command print `error`, and so SHALL a head revision at which the spec directory's `specs/` holds no tracked file. The command SHALL print one JSON line with `status` (`ok`, `missing` or `error`) and a list naming each requirement or Example that lacks its check, and SHALL exit 0, 1 or 2 in that order. `--base` is required: the caller names the range, so that a run on the default branch is checked against the commit it started from. The marker ties an Example to a test by name only; whether the test exercises what the Example states is judged by the reviewers of `idd-verify`.

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
| `--base` names a revision that does not exist | not applicable | not applicable | not applicable | `error` |
| `--base` is not given | not applicable | not applicable | not applicable | usage error, exit 64 |

### Requirement: A fix after a verify round goes through the same wrapper

A fix made after a verify round SHALL leave the specs agreeing with the behaviour on the same branch. When the fix adds or modifies a requirement, it SHALL be made as a further Spectra change of the same issue, named `idd-<N>-fix<k>` where `k` is the number of the verify round, through the same wrapper in the light form, archived before the next verify round; the next Implementation Complete comment SHALL list every change of the issue on its `**Spec**:` line. When a requirement that states the behaviour already exists with an Example, the fix SHALL add or correct the test that carries the Example's marker and needs no further change. When verify finds that a `no behaviour change` declaration does not hold, the fix SHALL create the issue's first change, named `idd-<N>-<slug>`, through the same wrapper, SHALL archive it before the next verify round, and the next Implementation Complete comment SHALL declare `change <name>`. A fix for a Blocking finding SHALL leave a requirement that states the property the finding showed was violated, with an Example whose test fails on the commit before the fix.

What a fix round leaves:

| Finding | Before the fix | The fix round leaves | Further change |
| --- | --- | --- | --- |
| Blocking: the behaviour is wrong and no requirement states it | no requirement | an added requirement, an Example, a test that failed before the fix | `idd-<N>-fix<k>` |
| Blocking: the behaviour is wrong; a requirement states it and has no Example | a requirement with no Example | the requirement gains an Example, and its test | `idd-<N>-fix<k>` |
| Blocking: the behaviour is wrong; a requirement and an Example state it | the test is missing or does not check it | the corrected test with the marker | none |
| a lower finding whose fix changes behaviour that no requirement states | no requirement | an added or modified requirement, an Example, a test | `idd-<N>-fix<k>` |
| HIGH: a `no behaviour change` declaration does not hold | no change | the issue's first change, archived; the next comment declares it | `idd-<N>-<slug>` |
| a finding fixed by wording in documentation only | not applicable | no spec change | none |

No executable check: whether a requirement states the violated property, and whether its test failed before the fix, are judged by the reviewers of the next verify round; the link check of the fix round's range covers the added requirement.

#### Scenario: A Blocking finding becomes a requirement with a check

- **GIVEN** verify round 2 reports as Blocking that a script exits 0 on a failed lookup, and no requirement states its exit codes
- **WHEN** the fix round runs
- **THEN** the branch gains the archived change `idd-<N>-fix2` whose requirement states the exit code, with an Example and a test that fails on the commit before the fix, and the new Implementation Complete comment lists both changes

### Requirement: A repository without Spectra stops and a third-party clone proceeds

Before a wrapper creates any artifact or commit for an implementation, it SHALL run `scripts/spec-change.py preflight --cwd <dir> --can-write <yes|no>`, which prints one JSON line with `status`. `third-party` (the session account cannot write to the repository): the wrapper SHALL NOT create `openspec/`, SHALL implement the issue as it was implemented before this capability, and SHALL declare `**Spec**: third-party clone`. `linked-worktree` (the working tree is a git linked worktree, where Spectra writes into the main working tree), `install-spectra` (no `spectra` command on PATH) and `init-openspec` (no `openspec/` directory): the wrapper SHALL stop before it creates anything, and SHALL print the reason and, for the last two, the command that installs Spectra or `spectra init`. `error` (the directory is not a git repository, or `.spectra.yaml` names a spec directory that is absolute, empty or leaves the repository): the wrapper SHALL stop and report it. `ready`: the wrapper proceeds. The command SHALL exit 0 for `ready` and `third-party`, 1 for the three stops and 2 for `error`. The wrapper SHALL pass `--can-write yes` only when the account's permission on the repository reads as write, maintain or admin, and `--can-write no` only when it reads as read, triage or none; when the permission cannot be read, the wrapper SHALL stop before it runs the preflight.

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
| `yes` | `--cwd` is not a git repository | any | any | `error` | 2 |
| a value other than `yes` or `no` | any | any | any | usage error | 64 |

### Requirement: Close requires the issue's change to be archived

`idd-close` SHALL fetch the issue's comments with `gh api --paginate`, SHALL choose the Implementation Complete comment with `spec-change.py ic` (requirement "One way to choose the Implementation Complete comment"), and SHALL run `spec-change.py archived` on it with `--ref` set to the default branch as the remote has it. It SHALL close the issue only when the command prints `pass`. On `refuse` it SHALL stop and name the changes that are not archived or the fault in the `**Spec**:` line; on `error` it SHALL stop and say the default branch could not be read. When the comments cannot be fetched or `ic` exits 2, it SHALL stop and say the comments could not be read; it SHALL NOT treat that as an issue with no Implementation Complete comment. An issue with no Implementation Complete comment is not held to this rule.

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
