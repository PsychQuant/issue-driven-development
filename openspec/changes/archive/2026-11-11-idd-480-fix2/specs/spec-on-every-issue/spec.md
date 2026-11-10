## MODIFIED Requirements

### Requirement: The spec directory is resolved the way Spectra resolves it

Every path this capability names under `openspec/` is relative to the spec directory Spectra uses for the repository, and `scripts/spec-change.py` SHALL resolve it the same way: the value of an uncommented `spec_dir:` line in `.spectra.yaml` at the top of the repository, or `openspec` when the file has no such line or does not exist. `archived` and `links` SHALL read `.spectra.yaml` at the revision they check; `preflight` SHALL read it in the working tree. A value that is absolute, empty, starts with `-`, names the repository root (`.`), or leaves the repository (a `..` component) SHALL be an `error`, not a fallback to `openspec`, and so SHALL a `.spectra.yaml` that exists but cannot be read as a file.

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

### Requirement: One way to choose the Implementation Complete comment

`scripts/spec-change.py ic --comments <file>` SHALL read the comments of an issue as GitHub's REST API returns them (one JSON array, or several arrays one after another as `gh api --paginate` prints them) and SHALL print the body of the newest comment whose `author_association` is `OWNER`, `MEMBER` or `COLLABORATOR` and whose body starts, after leading whitespace, with the marker `<!-- idd:comment type=implementation-complete -->` or with `## Implementation Complete`. It SHALL print nothing when no comment qualifies. The author association stands in for write access: the comments API does not report a commenter's permission, and a member or collaborator can lack write access to the repository. A comment whose body is not a string is not chosen. The command SHALL exit 0 in both cases and 2, printing nothing, when the file cannot be read, is empty, or is not such JSON. `idd-verify` and `idd-close` SHALL choose the comment with this command and with no other selection.

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
| a body that starts with a blank line and then the marker, by an `OWNER` | that body | 0 |
| a `## Diagnosis` by an `OWNER` only | nothing | 0 |
| no comments | nothing | 0 |
| two pages printed one after the other, the newest Implementation Complete on the second | the comment on the second page | 0 |
| the file does not exist | nothing | 2 |
| the file is not JSON | nothing | 2 |
| the file is empty | nothing | 2 |

### Requirement: Spec changes go through Spectra behind IDD wrappers

`idd-implement` SHALL be the wrapper for the Simple tier and `idd-plan` the wrapper for the Plan tier, and both SHALL follow one shared contract kept in `references/spec-wrapper.md`. Which phase of `idd-all` invokes which skill stays stated once, in the dispatch table of `skills/idd-all/SKILL.md`; this requirement constrains what the invoked skills do. A wrapper SHALL create one Spectra change per issue, named `idd-<N>-<slug>`, SHALL produce the proposal, the spec delta and the tasks through Spectra's propose workflow, and SHALL implement the tasks through Spectra's apply workflow, with the test of each Example written before the code it checks. When Spectra's propose workflow leaves the change parked, the wrapper SHALL take it out of the parked state itself before apply. In a run that `references/unattended-contract.md` marks as unattended, the wrapper SHALL tell Spectra's propose and apply skills not to ask questions and to record each choice they would have asked about as a line starting with `ASSUMPTION:` in the artifact. For the Simple tier the wrapper SHALL use the light form: no discuss step and no design artifact. For the Plan tier in an attended run, `idd-plan` SHALL present the proposal and the tasks for approval in plan mode before apply starts, and SHALL hand the approved change to `idd-implement`, which applies it and does not propose again. A Plan-tier issue in an unattended run goes to `idd-implement` as it does today and takes the light form. For the Spectra tier the existing chain of discuss, propose and apply stays as it is, preceded by the same preflight as the other tiers; that preflight SHALL run before any check that Spectra is installed, so that a third-party clone proceeds without Spectra, and Spectra's propose skill SHALL receive the same instructions on Examples, unique titles and test markers as in the other tiers. When a Spectra-tier issue is run by hand from the hand-off that `idd-diagnose` prints, the same preflight SHALL run before `/spectra-discuss`, and the issue SHALL be closed out as the contract's steps 5 and 6 say. When the issue has a change, the checklist of its Implementation Complete comment, headed `### Checklist (synced from tasks.md)`, SHALL copy the checkbox lines of the archived `tasks.md` of each change in order; the Spectra tier posts no `### Checklist` and its checklist lives in the issue body under `## Current Status` > `### Tasks`. The preflight call SHALL turn the account's permission into `--can-write` the same way in the shared contract and in `idd-all` Phase 3b, and SHALL stop on any outcome other than `ready` or `third-party`. Outside the wrappers and the shared contract, no IDD skill SHALL depend on the arguments or the output of Spectra's propose or apply skills for the Simple and Plan tiers.

The preflight call is checked by the Example below. No executable check: the propose and apply steps are carried out by a model that follows SKILL.md; what they leave behind is checked by the Examples of the other requirements of this capability (the Spec line, the archive, the links).

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

##### Example: the preflight call routes by permission and Spectra

| Permission `gh` reports | `spectra` on PATH | Spec directory | Printed status | The run |
| --- | --- | --- | --- | --- |
| `WRITE` | yes | present | `ready` | proceeds |
| `ADMIN` | no | present | `install-spectra` | stops |
| `READ` | no | absent | `third-party` | proceeds without a spec change |
| `TRIAGE` | yes | present | `third-party` | proceeds without a spec change |
| nothing (the call failed) | yes | present | `error` | stops |
| `SOMETHING_ELSE` | yes | present | `error` | stops |

### Requirement: Added and modified requirements carry an executable check

`scripts/spec-change.py links --base <rev>` SHALL compare the files under `openspec/specs/` at `<rev>` and at `--head` (default `HEAD`). For every requirement that is new or whose text differs between the two, it SHALL require one of two things: at least one `##### Example:` under the requirement, where each such Example has a title that is unique within its capability and a tracked file at the head revision, outside `openspec/` and not ending in `.md`, that contains the marker `spec-example: <capability> / <Example title>`; or a line under the requirement that starts with `No executable check:` followed by a reason. A requirement that does not differ SHALL NOT be checked. A marker counts only when nothing but whitespace, or the comment closer `-->` or `*/`, follows the Example title on its line. Lines inside a code fence are not read as `##### Example:` or `No executable check:` lines; a fence opened by three or more backticks or tildes closes only on a line of the same character, at least as long, with nothing but whitespace after it. Two requirements with the same name in one capability SHALL make the command print `error`. So SHALL a code fence at the head revision that never closes, since the requirements after it would go unchecked. Outside code fences, a heading that starts with `### Requirement` but does not have the form `### Requirement: <name>` with a non-empty name SHALL make the command print `error`, and so SHALL a head revision at which the spec directory's `specs/` holds no tracked file. The command SHALL print one JSON line with `status` (`ok`, `missing` or `error`) and a list naming each requirement or Example that lacks its check, and SHALL exit 0, 1 or 2 in that order. `--base` is required: the caller names the range, so that a run on the default branch is checked against the commit it started from. The marker ties an Example to a test by name only; whether the test exercises what the Example states is judged by the reviewers of `idd-verify`.

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
| added twice with the same name in one capability | not applicable | not applicable | not applicable | `error` |
| any, after a code fence that never closes | not applicable | not applicable | not applicable | `error` |
| `--base` names a revision that does not exist | not applicable | not applicable | not applicable | `error` |
| `--base` is not given | not applicable | not applicable | not applicable | usage error, exit 64 |

### Requirement: A repository without Spectra stops and a third-party clone proceeds

Before a wrapper creates any artifact or commit for an implementation, it SHALL run `scripts/spec-change.py preflight --cwd <dir> --can-write <yes|no>`, which prints one JSON line with `status`. `third-party` (the session account cannot write to the repository): the wrapper SHALL NOT create `openspec/`, SHALL implement the issue as it was implemented before this capability, and SHALL declare `**Spec**: third-party clone`. `linked-worktree` (the working tree is a git linked worktree, where Spectra writes into the main working tree), `install-spectra` (no `spectra` command on PATH) and `init-openspec` (no `openspec/` directory): the wrapper SHALL stop before it creates anything, and SHALL print the reason and, for the last two, the command that installs Spectra or `spectra init`. `error` (the directory is not a git repository, `.spectra.yaml` cannot be read, or it names a spec directory that is absolute, empty, starts with `-` or leaves the repository): the wrapper SHALL stop and report it. The wrapper SHALL also stop when the command prints nothing, prints something that is not one JSON line, or prints a status not named here. `ready`: the wrapper proceeds. The command SHALL exit 0 for `ready` and `third-party`, 1 for the three stops and 2 for `error`. The wrapper SHALL pass `--can-write yes` only when the account's permission on the repository reads as write, maintain or admin, and `--can-write no` only when it reads as read, triage or none; when the permission cannot be read, the wrapper SHALL stop before it runs the preflight.

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
| `yes` | no | yes | yes, but `.spectra.yaml` cannot be read | `error` | 2 |
| a value other than `yes` or `no` | any | any | any | usage error | 64 |

### Requirement: Close requires the issue's change to be archived

`idd-close` SHALL fetch the issue's comments with `gh api --paginate`, SHALL choose the Implementation Complete comment with `spec-change.py ic` (requirement "One way to choose the Implementation Complete comment"), and SHALL run `spec-change.py archived` on it with `--ref` set to the default branch as the remote has it. It SHALL close the issue only when the command prints `pass`. On `refuse` it SHALL stop and name the changes that are not archived or the fault in the `**Spec**:` line; on `error` it SHALL stop and say the default branch could not be read, and so SHALL it when `gh repo view` cannot name the default branch or `git fetch` of it fails. When the comments cannot be fetched or `ic` exits 2, it SHALL stop and say the comments could not be read; it SHALL NOT treat that as an issue with no Implementation Complete comment. An issue with no Implementation Complete comment is not held to this rule. A retroactive close (`idd-close --retroactive`, for an issue that is already closed) skips this gate, as it skips the gates before it.

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
