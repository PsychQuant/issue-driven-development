## MODIFIED Requirements

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
