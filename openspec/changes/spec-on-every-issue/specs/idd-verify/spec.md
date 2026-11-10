## ADDED Requirements

### Requirement: Reviewers check behaviour against the specs

When `idd-verify` reviews an implementation of an issue under the `code` profile, it SHALL give every reviewer the `**Spec**:` line of the issue's newest Implementation Complete comment and the list of files under `openspec/specs/` that the reviewed range changes. It SHALL run `scripts/spec-change.py links` with `--base` set to the base of the reviewed range, and `scripts/spec-change.py archived` with `--ref` set to the head of the reviewed range, and SHALL list as a Blocking finding each item `links` reports as missing, each change `archived` refuses, and either command ending in `error`. The regression lens SHALL report as a HIGH finding a behaviour change in the range that no requirement in the specs at the head of the range states, and SHALL report as a HIGH finding any behaviour change in the range when the `**Spec**:` line is `no behaviour change`. A test that carries an Example's marker and does not exercise what the Example states SHALL be reported as a finding of MEDIUM or above. An issue whose comment is legacy, and the `prose` and `academic` profiles, are not changed by this requirement.

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
| `third-party clone` | yes | not applicable | `ok` | `pass` | none |
| a reviewed range of the last three commits on the default branch | yes | yes | run with `--base HEAD~3` | `pass` | none |

No executable check: the reviewers and the report are produced by a model; the two commands the skill runs have their own Examples in the capability `spec-on-every-issue`.

#### Scenario: Behaviour without a requirement

- **GIVEN** a range that makes a script exit 3 where it exited 0, and no requirement in the specs at the head states its exit codes
- **WHEN** the regression lens reviews the range
- **THEN** the report holds a HIGH finding that names the behaviour change and says no requirement states it

#### Scenario: A declared exemption that is not true

- **GIVEN** an Implementation Complete comment with `**Spec**: no behaviour change`
- **AND** a range that changes which question a skill asks
- **WHEN** the regression lens reviews the range
- **THEN** the report holds a HIGH finding that the declared exemption does not hold
