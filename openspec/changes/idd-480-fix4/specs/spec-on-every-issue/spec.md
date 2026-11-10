## MODIFIED Requirements

### Requirement: One way to choose the Implementation Complete comment

`scripts/spec-change.py ic --comments <file>` SHALL read the comments of an issue as GitHub's REST API returns them (one JSON array, or several arrays one after another as `gh api --paginate` prints them) and SHALL print the body of the newest comment whose `author_association` is `OWNER`, `MEMBER` or `COLLABORATOR` and whose body starts, after leading whitespace, with the marker `<!-- idd:comment type=implementation-complete -->` or with `## Implementation Complete`. It SHALL print nothing when no comment qualifies. The author association stands in for write access: the comments API does not report a commenter's permission, and a member or collaborator can lack write access to the repository. A comment whose body is not a string is not chosen. The command SHALL exit 0 in both cases and 2, printing nothing, when the file cannot be read, is empty, is not such JSON, or nests too deeply to read. `idd-verify` and `idd-close` SHALL choose the comment with this command and with no other selection.

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
| JSON nested a hundred thousand arrays deep | nothing | 2 |

### Requirement: Spec changes go through Spectra behind IDD wrappers

`idd-implement` SHALL be the wrapper for the Simple tier and `idd-plan` the wrapper for the Plan tier, and both SHALL follow one shared contract kept in `references/spec-wrapper.md`. Which phase of `idd-all` invokes which skill stays stated once, in the dispatch table of `skills/idd-all/SKILL.md`; this requirement constrains what the invoked skills do. A wrapper SHALL create one Spectra change per issue, named `idd-<N>-<slug>`, SHALL produce the proposal, the spec delta and the tasks through Spectra's propose workflow, and SHALL implement the tasks through Spectra's apply workflow, with the test of each Example written before the code it checks. The Implementation Plan comment (the Plan tier, or `idd-implement` Step 2) SHALL carry exactly one line that starts with `**Spec plan**:`, in one of four forms: `change <name>`, `no behaviour change (<a|b|c|d>)`, `third-party clone`, or `rejected (change <name> left parked)`, which `idd-plan` writes when the maintainer aborts in plan mode; later steps read the decision from that line. `scripts/spec-change.py plan --comments <file>` SHALL read it: from the comments as the REST API returns them, it takes the newest comment by an `OWNER`, `MEMBER` or `COLLABORATOR` whose body starts, after leading whitespace, with `## Implementation Plan`, reads its `**Spec plan**:` line outside code fences, and prints one JSON line with `form` (`change`, `no-behaviour-change`, `third-party-clone`, `rejected`, `none` when there is no such comment or line, or `invalid`) and `change`, exiting 0, 1 for `invalid`, or 2 when the file cannot be read. Before it proposes or posts anything, a wrapper that finds an open change of the issue SHALL run that command and SHALL go on with the change only when the form is `change` with the same name; under `rejected`, or any other form, it SHALL stop. After a rejection, only `idd-plan` re-presents the parked change for approval and, on approval, posts a new Implementation Plan that names it with `change <name>`. Invoked directly on a Plan-tier issue, `idd-implement` SHALL still offer `/idd-plan` before it proposes; having a change skips only the TaskList it would otherwise build. When Spectra's propose workflow leaves the change parked, the wrapper SHALL take it out of the parked state itself before apply, and only that change. In a run that `references/unattended-contract.md` marks as unattended, the wrapper SHALL tell Spectra's propose and apply skills not to ask questions and to record each choice they would have asked about as a line starting with `ASSUMPTION:` in the artifact. For the Simple tier the wrapper SHALL use the light form: no discuss step and no design artifact. For the Plan tier in an attended run, `idd-plan` SHALL present the proposal and the tasks for approval in plan mode before apply starts, and SHALL hand the approved change to `idd-implement`, which applies it and does not propose again. A Plan-tier issue in an unattended run goes to `idd-implement` as it does today and takes the light form. For the Spectra tier the existing chain of discuss, propose and apply stays as it is, preceded by the same preflight as the other tiers; that preflight SHALL run before any check that Spectra is installed, so that a third-party clone proceeds without Spectra, and Spectra's propose skill SHALL receive the same instructions on Examples, unique titles and test markers as in the other tiers. When a Spectra-tier issue is run by hand from the hand-off that `idd-diagnose` prints, the same preflight SHALL run before `/spectra-discuss`, and the issue SHALL be closed out as the contract's steps 5 and 6 say. When the issue has a change, the checklist of its Implementation Complete comment, headed `### Checklist (synced from tasks.md)`, SHALL copy the checkbox lines of the archived `tasks.md` of each change in order; the Spectra tier posts no `### Checklist` and its checklist lives in the issue body under `## Current Status` > `### Tasks`. The preflight call SHALL turn the account's permission into `--can-write` the same way in the shared contract and in `idd-all` Phase 3b, and SHALL stop on any outcome other than `ready` or `third-party`. Outside the wrappers and the shared contract, no IDD skill SHALL depend on the arguments or the output of Spectra's propose or apply skills for the Simple and Plan tiers.

The preflight call, the unattended check and the unpark are fixed bash and are checked by the Examples below. No executable check: choosing what to propose, the routing questions and the apply itself are carried out by a model that follows SKILL.md; what they leave behind is checked by the Examples of the other requirements of this capability (the Spec line, the archive, the links).

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

##### Example: contract steps 3 and 4 run as written

| `IDD_ALL_UNATTENDED` | Parked changes | Step 3 prints | Step 4 unparks |
| --- | --- | --- | --- |
| `1` | `idd-7-x` | `unattended` | `idd-7-x` |
| unset | `idd-7-x` | `attended` | `idd-7-x` |
| unset | `idd-8-y` only | `attended` | nothing |
| unset | none | `attended` | nothing |

### Requirement: Added and modified requirements carry an executable check

`scripts/spec-change.py links --base <rev>` SHALL compare the files under `openspec/specs/` at `<rev>` and at `--head` (default `HEAD`). For every requirement that is new or whose text differs between the two, it SHALL require one of two things: at least one `##### Example:` under the requirement, where each such Example has a title that is unique within its capability and a tracked file at the head revision, outside `openspec/` and not ending in `.md`, that contains the marker `spec-example: <capability> / <Example title>`; or a line under the requirement that starts with `No executable check:` followed by a reason. A requirement that does not differ SHALL NOT be checked. A marker counts only when nothing but whitespace, or the comment closer `-->` or `*/`, follows the Example title on its line. Lines inside a code fence are not read as `##### Example:` or `No executable check:` lines; a fence opened by three or more backticks or tildes, at any indentation (as inside a list item), closes only on a line of the same character, at least as long, with nothing but whitespace after it; lines end only at `\n`, `\r\n` or `\r`. A requirement heading indented by up to three spaces SHALL be read as a requirement, as Spectra reads it. Paths SHALL be read as git stores them, never in git's quoted form, so a capability whose directory name is not ASCII is checked like any other. Two requirements with the same name in one capability SHALL make the command print `error`. So SHALL a code fence at the head revision that never closes, since the requirements after it would go unchecked. Outside code fences, a heading that starts with `### Requirement` but does not have the form `### Requirement: <name>` with a non-empty name SHALL make the command print `error`, and so SHALL a head revision at which the spec directory's `specs/` holds no tracked file. The command SHALL print one JSON line with `status` (`ok`, `missing` or `error`) and a list naming each requirement or Example that lacks its check, and SHALL exit 0, 1 or 2 in that order. `--base` is required: the caller names the range, so that a run on the default branch is checked against the commit it started from. The marker ties an Example to a test by name only; whether the test exercises what the Example states is judged by the reviewers of `idd-verify`.

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
| added twice with the same name in one capability | not applicable | not applicable | not applicable | `error` |
| any, after a code fence that never closes | not applicable | not applicable | not applicable | `error` |
| `--base` names a revision that does not exist | not applicable | not applicable | not applicable | `error` |
| `--base` is not given | not applicable | not applicable | not applicable | usage error, exit 64 |

### Requirement: The spec directory is resolved the way Spectra resolves it

Every path this capability names under `openspec/` is relative to the spec directory Spectra uses for the repository (a value in quotes is read whole; ` #` starts a comment only outside quotes), and `scripts/spec-change.py` SHALL resolve it the same way: the value of an uncommented `spec_dir:` line in `.spectra.yaml` at the top of the repository, or `openspec` when the file has no such line or does not exist. `archived` and `links` SHALL read `.spectra.yaml` at the revision they check; `preflight` SHALL read it in the working tree. A value that is absolute, empty, starts with `-` or `:`, names the repository root (`.`), or leaves the repository (a `..` component) SHALL be an `error`, not a fallback to `openspec`, and so SHALL a `.spectra.yaml` that exists but is not a regular file (a directory or a symbolic link), in the working tree or at the revision. Paths are given to git literally, never as pathspec magic.

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
| `spec_dir: "docs/my # specs"` (a ` #` inside the quotes) | `docs/my # specs` | read there |
| `spec_dir: # a comment` | not applicable | `error` |
| `spec_dir: ":(top)openspec"` | not applicable | `error` |
| a directory named `.spectra.yaml` at the revision | not applicable | `error` |
| a symbolic link named `.spectra.yaml` at the revision | not applicable | `error` |

##### Example: reading the Spec plan line

| Comments, oldest first | `form` | `change` | Exit |
| --- | --- | --- | --- |
| an `## Implementation Plan` by an `OWNER` with `**Spec plan**: change idd-7-x` | `change` | `idd-7-x` | 0 |
| that plan, then a newer one with `**Spec plan**: rejected (change idd-7-x left parked)` | `rejected` | `idd-7-x` | 0 |
| a plan with `**Spec plan**: no behaviour change (a)` | `no-behaviour-change` | empty | 0 |
| a plan with `**Spec plan**: third-party clone` | `third-party-clone` | empty | 0 |
| the owner's plan naming `idd-7-x`, then a newer plan by a `CONTRIBUTOR` naming `idd-7-y` | `change` | `idd-7-x` | 0 |
| no Implementation Plan comment | `none` | empty | 0 |
| a plan whose only `**Spec plan**:` line is inside a code fence | `none` | empty | 0 |
| a plan with two `**Spec plan**:` lines | `invalid` | empty | 1 |
| the file is not JSON | no JSON line | not applicable | 2 |

