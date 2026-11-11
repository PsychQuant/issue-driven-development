## ADDED Requirements

### Requirement: Plan-tier approval covers the change as it will be applied

When `idd-plan` presents a change for approval, it SHALL first run the step-3.5 block of `skills/idd-plan/SKILL.md`: if the change is parked, the block takes it out of the parked state; it reads the change directory from `spectra instructions apply --change <name> --json` (`changeDir`); it prints `→ change files: <directory>` followed by the path of each Markdown file in the change; and it stops, printing nothing after an error line, when the unpark fails, `spectra instructions` fails or names no directory, or the directory lacks `proposal.md`, `tasks.md` or a `specs/<capability>/spec.md`. Plan mode SHALL show each listed file verbatim after the Implementation Plan, so that what the maintainer approves is the set of files `idd-implement` applies. When the maintainer asks for a revision, `idd-plan` SHALL make it in those files, SHALL run `spectra validate <name>` and fix what it reports, and SHALL run the block again and rebuild the plan's `### Files & Changes` from the new tasks before it shows the plan again; changing only the Implementation Plan comment is not a revision. When the maintainer aborts, `idd-plan` SHALL park the change again before it writes `rejected (change <name> left parked)`.

#### Scenario: a parked change is shown from its files

- **WHEN** `idd-plan` is about to enter plan mode for a parked change `idd-7-x` whose directory holds a proposal, tasks and one spec delta
- **THEN** the block unparks `idd-7-x` and prints the directory and the three files, and plan mode shows those files

##### Example: the step-3.5 block

| Change state | `spectra instructions apply` | Files in the change directory | The block |
| --- | --- | --- | --- |
| parked | prints the directory | proposal, tasks, one spec delta | unparks it, prints `→ change files:` and three paths |
| active | prints the directory | proposal, tasks, one spec delta | does not unpark, prints `→ change files:` and three paths |
| parked, and the unpark fails | not reached | not read | stops |
| active | fails | not read | stops |
| active | prints the directory | proposal and tasks, no spec delta | stops |
