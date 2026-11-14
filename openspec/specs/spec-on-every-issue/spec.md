# spec-on-every-issue Specification

## Purpose

Defines how every issue that IDD implements leaves a change in the repository's specs, whatever tier its Diagnosis records: which cases are exempt, how the spec change is produced through Spectra behind IDD's own wrappers, when the change is archived, and how each added or modified requirement is tied to an executable check. It exists so that a later change has a written requirement and a runnable check to be judged against.

## Requirements

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

---
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

---
### Requirement: Spec changes go through Spectra behind IDD wrappers

`idd-implement` SHALL be the wrapper for the Simple tier and `idd-plan` the wrapper for the Plan tier, and both SHALL follow one shared contract kept in `references/spec-wrapper.md`. Which phase of `idd-all` invokes which skill stays stated once, in the dispatch table of `skills/idd-all/SKILL.md`; this requirement constrains what the invoked skills do. A wrapper SHALL create one Spectra change per issue, named `idd-<N>-<slug>`, SHALL produce the proposal, the spec delta and the tasks through Spectra's propose workflow, and SHALL implement the tasks through Spectra's apply workflow, with the test of each Example written before the code it checks. The Implementation Plan comment (the Plan tier, or `idd-implement` Step 2) SHALL carry exactly one line that starts with `**Spec plan**:`, in one of four forms: `proposed (change <name>)`, which `idd-plan` writes before plan mode and replaces with `change <name>` once the maintainer approves; `change <name>`; `no behaviour change (<a|b|c|d>)`; or `third-party clone`. Later steps read the decision from that line. `idd-implement` posts its own plan line before it proposes, and a fix round posts a plan line naming `change idd-<N>-fix<k>` before it proposes the fix change, so a run that is cut off finds a plan that names its change; in an attended Plan-tier run through `idd-plan`, the change is proposed only after `idd-plan` has written `change <name>` on approval. `scripts/spec-change.py plan --comments <file>` SHALL read it: from the comments as the REST API returns them, it takes the newest comment by an `OWNER`, `MEMBER` or `COLLABORATOR` whose body starts, after leading whitespace, with the heading `## Implementation Plan` (followed by the end of the line, a space or `(`), reads its `**Spec plan**:` line outside code fences, and prints one JSON line with `form` (`proposed`, `change`, `no-behaviour-change`, `third-party-clone`, `none` when there is no such comment or line, or `invalid`) and `change`, exiting 0, 1 for `invalid`, or 2 when the file cannot be read. Before it proposes or posts anything, `idd-implement`, finding an open change of the issue, SHALL run that command and SHALL go on with the change only when the form is `change` with the same name; under any other form it SHALL stop and say how to go on: run `/idd-plan`, which presents the Implementation Plan for approval again and, on approval, writes `change <name>` for the open change. `idd-plan` does not run this check: a fixed bash block in its Step 2 SHALL look up the issue's open `idd-<N>-` change with `spectra list --json` and `spectra list --parked --json`, in the same lines as the lookup of the contract's step 3, and SHALL print one line that starts with `→ idd-plan change lookup: ` and ends with the name of the first such change (active before parked), with `new` when there is none, or with `stop: ` and a reason when either list cannot be read or is not JSON. When the issue number in the shell of that block (`NUMBER`) is unset, empty, starts with `0` or is not a decimal number, the block SHALL print the `stop: ` line without running either list command: the name filter would otherwise match nothing, or another issue's change, and the issue would be reported as having no open change. `idd-plan` names an open change in its plan instead of choosing a new name, and stops when the line says `stop:`. When the list of changes cannot be read, or is not JSON, the wrapper SHALL stop rather than treat the issue as having none. Invoked directly on a Plan-tier issue, `idd-implement` SHALL still offer `/idd-plan` before it proposes; having a change skips only the TaskList it would otherwise build. When Spectra's propose workflow leaves the change parked, the wrapper SHALL take it out of the parked state itself before apply, and only that change. In a run that `references/unattended-contract.md` marks as unattended, the wrapper SHALL tell Spectra's propose and apply skills not to ask questions and to record each choice they would have asked about as a line starting with `ASSUMPTION:` in the artifact. For the Simple tier the wrapper SHALL use the light form: no discuss step and no design artifact. For the Plan tier in an attended run, `idd-plan` SHALL present the Implementation Plan for approval in plan mode and SHALL NOT propose; on approval it SHALL hand the issue and the change name to `idd-implement`, which proposes in the light form and applies, as in the Simple tier. After it proposes, `idd-implement` SHALL NOT edit a plan comment whose heading is `## Implementation Plan (Plan tier)`, which is the plan the maintainer approved: it SHALL post the tasks of the change in a separate comment that starts with `## Spec tasks (change <name>)`, one task per line and without checkboxes, unless an `OWNER`, `MEMBER` or `COLLABORATOR` has already posted such a comment for that change. The newest plan, whose heading decides this, is the comment that `scripts/spec-change.py plan` reads: a plan or a `## Spec tasks` comment posted by an account without write access counts as neither. Where the newest plan is the one `idd-implement` posted itself, it replaces the list of that comment with the tasks and leaves its single `**Spec plan**:` line as it is. Approving the proposal itself in plan mode is not part of this requirement (#497). A Plan-tier issue in an unattended run goes to `idd-implement` as it does today and takes the light form. For the Spectra tier the existing chain of discuss, propose and apply stays as it is, preceded by the same preflight as the other tiers; that preflight SHALL run before any check that Spectra is installed, so that a third-party clone proceeds without Spectra, and Spectra's propose skill SHALL receive the same instructions on Examples, unique titles and test markers as in the other tiers. When a Spectra-tier issue is run by hand from the hand-off that `idd-diagnose` prints, the same preflight SHALL run before `/spectra-discuss`, and the issue SHALL be closed out as the contract's steps 5 and 6 say. When the issue has a change, the checklist of its Implementation Complete comment, headed `### Checklist (synced from tasks.md)`, SHALL copy the checkbox lines of the archived `tasks.md` of each change in order; the Spectra tier posts no `### Checklist` and its checklist lives in the issue body under `## Current Status` > `### Tasks`. The preflight call SHALL turn the account's permission into `--can-write` the same way in the shared contract and in `idd-all` Phase 3b, and SHALL stop on any outcome other than `ready` or `third-party`. Outside the wrappers and the shared contract, no IDD skill SHALL depend on the arguments or the output of Spectra's propose or apply skills for the Simple and Plan tiers.

The preflight call, the unattended check, the unpark and `idd-plan`'s lookup of an open change are fixed bash and are checked by the Examples below. No executable check: choosing what to propose, the routing questions, posting the Spec tasks comment and the apply itself are carried out by a model that follows SKILL.md; what they leave behind is checked by the Examples of the other requirements of this capability (the Spec line, the archive, the links), and that neither a Spec tasks comment nor a plan posted by an account without write access is read as the newest plan is checked by the Example on reading the Spec plan line.

#### Scenario: A Simple issue uses the light form

- **GIVEN** an issue whose Diagnosis records `Simple`
- **WHEN** `idd-implement` runs
- **THEN** it creates the change `idd-<N>-<slug>` with a proposal, a spec delta and tasks, creates no design artifact, runs no discuss step, and applies the tasks

#### Scenario: A Plan issue keeps its approval in an attended run

- **GIVEN** an attended run and an issue whose Diagnosis records `Plan`
- **WHEN** `idd-plan` runs
- **THEN** it asks for approval of the Implementation Plan in plan mode without proposing, and only after approval hands the issue and the change name to `idd-implement`, which proposes in the light form, posts the tasks of the change in a separate `## Spec tasks` comment, leaves the approved plan comment as it is, and applies

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

##### Example: reading the Spec plan line

| Comments, oldest first | `form` | `change` | Exit |
| --- | --- | --- | --- |
| an `## Implementation Plan` by an `OWNER` with `**Spec plan**: change idd-7-x` | `change` | `idd-7-x` | 0 |
| a plan with `**Spec plan**: no behaviour change (a)` | `no-behaviour-change` | empty | 0 |
| a plan with `**Spec plan**: third-party clone` | `third-party-clone` | empty | 0 |
| a plan with `**Spec plan**: proposed (change idd-7-x)` | `proposed` | `idd-7-x` | 0 |
| the owner's plan naming `idd-7-x`, then a newer `## Implementation Planning notes` comment | `change` | `idd-7-x` | 0 |
| the owner's plan naming `idd-7-x`, then a newer `## Spec tasks (change idd-7-x)` comment | `change` | `idd-7-x` | 0 |
| a plan with `**Spec plan**: rejected (change idd-7-x left parked)` | `invalid` | empty | 1 |
| the owner's plan naming `idd-7-x`, then a newer plan by a `CONTRIBUTOR` naming `idd-7-y` | `change` | `idd-7-x` | 0 |
| no Implementation Plan comment | `none` | empty | 0 |
| a plan whose only `**Spec plan**:` line is inside a code fence | `none` | empty | 0 |
| a plan with two `**Spec plan**:` lines | `invalid` | empty | 1 |
| the file is not JSON | no JSON line | not applicable | 2 |

##### Example: an open change is checked against the newest plan

| Open change of the issue | Newest plan's `**Spec plan**:` line | Step 3 prints |
| --- | --- | --- |
| none | not read | `propose` |
| `idd-7-x` | `change idd-7-x` | `go on with idd-7-x` |
| `idd-7-x` | `proposed (change idd-7-x)` | a stop that names `/idd-plan` |
| `idd-7-x` | `change idd-7-y` | a stop that names `/idd-plan` |
| `idd-7-x` | no plan comment | a stop |
| the change list cannot be read | not read | a stop, not `propose` |
| the change list is not JSON | not read | a stop, not `propose` |

##### Example: idd-plan looks up the open change of the issue

| Issue | Active changes | Parked changes | The block prints |
| --- | --- | --- | --- |
| 7 | `idd-7-x` | none | `→ idd-plan change lookup: idd-7-x` |
| 7 | none | `idd-7-x` | `→ idd-plan change lookup: idd-7-x` |
| 7 | none | none | `→ idd-plan change lookup: new` |
| 7 | `idd-7-a` | `idd-7-b` | `→ idd-plan change lookup: idd-7-a` |
| 7 | `idd-70-x` | none | `→ idd-plan change lookup: new` |
| 70 | `idd-7-x` | none | `→ idd-plan change lookup: new` |
| 7 | the list command fails | none | a line that starts with `→ idd-plan change lookup: stop:` |
| 7 | none | the list command fails | a line that starts with `→ idd-plan change lookup: stop:` |
| 7 | text that is not JSON | none | a line that starts with `→ idd-plan change lookup: stop:` |
| 7 | none | text that is not JSON | a line that starts with `→ idd-plan change lookup: stop:` |
| not set | `idd-7-x` | none | a line that starts with `→ idd-plan change lookup: stop:` |
| empty | `idd-7-x` | none | a line that starts with `→ idd-plan change lookup: stop:` |
| `abc` | `idd-7-x` | none | a line that starts with `→ idd-plan change lookup: stop:` |
| `#7` | `idd-7-x` | none | a line that starts with `→ idd-plan change lookup: stop:` |
| `.*` | `idd-7-x` | none | a line that starts with `→ idd-plan change lookup: stop:` |
| `07` | `idd-7-x` | none | a line that starts with `→ idd-plan change lookup: stop:` |

In every row the block prints exactly one line and does not read the issue's comments. In the first ten rows it runs only the two list commands; in the last six, where the shell holds no usable issue number, it runs neither.

---
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

---
### Requirement: Added and modified requirements carry an executable check

`scripts/spec-change.py links --base <rev>` SHALL compare the files under `openspec/specs/` at `<rev>` and at `--head` (default `HEAD`). For every requirement that is new or whose text differs between the two, it SHALL require one of two things: at least one `##### Example:` under the requirement, where each such Example has a title that is unique within its capability and a tracked file at the head revision, outside `openspec/` and not ending in `.md`, that contains the marker `spec-example: <capability> / <Example title>` (a tracked file of a submodule counts, as the paragraph "Submodules" below describes); or a line under the requirement that starts with `No executable check:` followed by a reason. A requirement that does not differ SHALL NOT be checked. A marker counts only when nothing but whitespace, or the comment closer `-->` or `*/`, follows the Example title on its line. Lines inside a code fence are not read as `##### Example:` or `No executable check:` lines; a fence opened by three or more backticks or tildes, at any indentation (as inside a list item), closes only on a line of the same character, at least as long, with nothing but whitespace after it; lines end only at `\n`, `\r\n` or `\r`. A requirement heading indented by up to three spaces SHALL be read as a requirement, as Spectra reads it. Paths SHALL be read as git stores them, never in git's quoted form, so a capability whose directory name is not ASCII is checked like any other. Two requirements with the same name in one capability SHALL make the command print `error`. So SHALL a code fence at the head revision that never closes, since the requirements after it would go unchecked. Outside code fences, a heading that starts with `### Requirement` but does not have the form `### Requirement: <name>` with a non-empty name SHALL make the command print `error`, and so SHALL a head revision at which the spec directory's `specs/` holds no tracked file. The command SHALL print one JSON line with `status` (`ok`, `missing` or `error`) and a list naming each requirement or Example that lacks its check, and SHALL exit 0, 1 or 2 in that order. `--base` is required: the caller names the range, so that a run on the default branch is checked against the commit it started from. The marker ties an Example to a test by name only; whether the test exercises what the Example states is judged by the reviewers of `idd-verify`.

Submodules. The tracked files at the head revision include the tracked files of every submodule of the repository at the commit that the head revision records for it, and in the same way the files of a submodule of a submodule. The command SHALL read that recorded commit, not the commit the submodule's working tree is on. It SHALL find the submodules itself, from the entries of the head revision's tree that record a commit; it SHALL NOT rely on git's own recursion into submodules, which passes over a submodule that is not checked out without saying so; the answer SHALL be the same whether or not the git configuration turns that recursion on (`submodule.recurse`). A file of a submodule is named by the submodule's path followed by the file's path, and the two exclusions (under the spec directory, ending in `.md`) apply to that name. A submodule whose own path is under the spec directory SHALL NOT be searched and SHALL NOT count as one that could not be searched: none of its files could count.

Order of the search. For each Example the command SHALL search the main repository first. When the marker is found there, the Example has its check and the command SHALL NOT run git in any submodule for it, so a repository whose markers are all in its own files is checked exactly as before, whatever its head revision records. Only when the marker is not found in the main repository are the submodules searched, and a marker found in one submodule settles the Example whatever the state of the others. When the marker of an Example is found, the Example has its check, whether or not every submodule could be searched.

Which submodules can be searched. A submodule SHALL be searched only when all six of these hold: (1) its path, as the tree records it, is relative and has no empty, `.` or `..` component; (2) its directory, after symbolic links are resolved, lies inside the working tree of the main repository; (3) the directory itself is not a symbolic link; (4) the directory holds an entry named `.git` of its own; (5) git, run in the directory, reports it as the top of its own working tree; (6) its object store holds the recorded commit. The command SHALL NOT run git in a directory that fails any of the first four: a directory of ordinary tracked files can be shaped like a git directory, and git would read, and act on, the configuration it holds. In the directory of a submodule the command SHALL run git with `safe.bareRepository` set to `explicit`, with lazy fetching turned off (`GIT_NO_LAZY_FETCH=1`), and with the variables `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE`, `GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES` and `GIT_COMMON_DIR` removed from the environment it inherited. A submodule whose search fails after it began counts as one that could not be searched; the search fails when the search command exits with a code other than 0 or 1, when it finds no file that counts and git writes to its error stream (something could not be read), or when the tree of the recorded commit cannot be listed. In the main repository nothing changes: a search that exits with a code other than 0 or 1 is `error`, as before.

What is reported. When the marker is not found and every submodule was searched, the Example is reported as lacking its check, as before. When it is not found and at least one submodule could not be searched, the command SHALL print `error` and name the first such Example it meets, the submodules that could not be searched and the reason for each: an Example whose candidate files were not all read is not reported as lacking its check. The submodules are named by path, in the order of their paths and joined by `; `; a submodule of a submodule is named by its path under the outer one; when more than five could not be searched, the first five are named and the number of the others is stated; a path longer than 200 characters is cut to its first 200 followed by `...`. The reason is one of five: the path leaves the repository (conditions 1 and 2); the submodule is not checked out (conditions 3 and 4, or git names another directory as the top); git refused to open it (the git command of condition 5 fails); the recorded commit is not in its object store (condition 6); the recorded commit could not be read (the search failed after it began). The reason SHALL NOT carry text from git's error stream. A path that is not valid UTF-8 is handled like any other path, and the command still prints one JSON line. A repository whose head revision records no submodule is checked exactly as before.

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

---
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

---
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

---
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

---
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

---
