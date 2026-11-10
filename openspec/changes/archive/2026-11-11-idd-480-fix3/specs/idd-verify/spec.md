## MODIFIED Requirements

### Requirement: Reviewers check behaviour against the specs

When `idd-verify` reviews an implementation of an issue under the `code` profile, which reviews a git range, it SHALL give every reviewer the `**Spec**:` line of the issue's newest Implementation Complete comment and the list of files under `openspec/specs/` that the reviewed range changes. It SHALL choose the comment with `spec-change.py ic` and SHALL run `scripts/spec-change.py links` with `--base` set to the base of the reviewed range, and `scripts/spec-change.py archived` with `--ref` set to the head of the reviewed range, and SHALL list as a Blocking finding each item `links` reports as missing, each change `archived` refuses, either command ending in `error` or printing no JSON, and a declaration that cannot be read because the comments could not be fetched, or whose form is `invalid`. The regression lens SHALL report as a HIGH finding a behaviour change in the range that no requirement in the specs at the head of the range states, and SHALL report as a HIGH finding any behaviour change in the range when the `**Spec**:` line is `no behaviour change`. A test that carries an Example's marker and does not exercise what the Example states SHALL be reported as a finding of MEDIUM or above, and so SHALL a `No executable check:` line under a requirement in the range whose reason does not hold because a check could be written. The data it hands the reviewers (the declaration, the changed files, the output of the two commands, which can carry requirement titles and up to 60 characters of comment text) SHALL be enclosed in a fence made with a token generated for the run, outside which the review rules stand; an occurrence of the token inside the data SHALL be neutralised. The devil's-advocate focus SHALL carry only the declaration form and the two statuses. The profile comes from `VERIFY_PROFILE`, which the executor sets to the `--profile` value in the shell that runs this step, `code` when it is unset. Under the `prose` and `academic` profiles, which review files, none of this runs and the devil's-advocate focus is not extended. Under `code`, a range that did not reach the shell is not a reason to skip: both checks are reported as `error`, which Step 3 writes as Blocking. The list of changed spec files names files under `openspec/specs/` only, not the deltas of changes. The lens set and the input detection of the default profile stay as they were; this requirement adds the spec context to them. An issue whose comment is legacy or declares `third-party clone` is not changed by this requirement; for those comments the results of `links` and `archived` are shown but give no finding (a third-party clone usually has no spec directory, where `links` prints `error`).

What the report holds:

| `**Spec**:` line | Behaviour change in the range | A requirement at the head states it | `links` | `archived` | Finding from this requirement |
| --- | --- | --- | --- | --- | --- |
| `change idd-7-x` | yes | yes | `ok` | `pass` | none |
| `change idd-7-x` | yes | no | `ok` | `pass` | HIGH: behaviour without a requirement |
| `change idd-7-x` | yes | yes | `missing`: one Example | `pass` | Blocking: the Example has no test |
| `change idd-7-x` | yes | yes | `ok` | `refuse` | Blocking: the change is not archived at the reviewed head |
| `change idd-7-x` | yes | yes | `error` | `pass` | Blocking: the link check did not run |
| `no behaviour change` | no | not applicable | `ok` | `pass` | none |
| `no behaviour change` | yes | not applicable | `ok` | `pass` | HIGH: the exemption does not hold |
| `third-party clone` | yes | not applicable | `ok`, or `error` with no spec directory | `pass` | none |
| the comments could not be fetched | yes | not read | `ok` | not run | Blocking: the declaration could not be read |
| `change idd-7-x` | yes | yes, with `No executable check:` although a test could check it | `ok` | `pass` | MEDIUM: the reason does not hold |
| a reviewed range of the last three commits on the default branch | yes | yes | run with `--base HEAD~3` | `pass` | none |

What the reviewers then find is the judgement of a model; the two commands the skill runs have their own Examples in the capability `spec-on-every-issue`.

#### Scenario: Behaviour without a requirement

- **GIVEN** a range that makes a script exit 3 where it exited 0, and no requirement in the specs at the head states its exit codes
- **WHEN** the regression lens reviews the range
- **THEN** the report holds a HIGH finding that names the behaviour change and says no requirement states it

#### Scenario: A declared exemption that is not true

- **GIVEN** an Implementation Complete comment with `**Spec**: no behaviour change`
- **AND** a range that changes which question a skill asks
- **WHEN** the regression lens reviews the range
- **THEN** the report holds a HIGH finding that the declared exemption does not hold

##### Example: the spec context the reviewers get

| `VERIFY_PROFILE` | Reviewed range in the shell | The spec block | The devil's-advocate focus |
| --- | --- | --- | --- |
| `prose` | none | not built; the file says it is not used | unchanged |
| `code` | none | built; the link and archive checks read `error` | gains the spec checks |
| `code` | present, and a comment carries the run's fence token | built; the token appears only in the header and the two fence lines, the data shows `[fence]`, the rules follow the closing fence | gains the spec checks |
