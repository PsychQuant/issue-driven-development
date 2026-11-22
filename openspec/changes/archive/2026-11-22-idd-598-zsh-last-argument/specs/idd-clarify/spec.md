## ADDED Requirements

### Requirement: idd-clarify reads every argument in bash and zsh

`/idd-clarify` Step 1 SHALL read every argument it is given under both bash and zsh, including the value that follows `--status` or `--cwd`, so a trailing flag is never dropped.

#### Scenario: A trailing status update under zsh

- **GIVEN** the Step 1 block run under zsh
- **WHEN** the arguments are `#8 --status resolved=2,checked`
- **THEN** the issue, the action, the row and the reason are all read, as under bash

##### Example: idd-clarify reads the last argument in both shells

| Arguments | Under bash and under zsh |
| --- | --- |
| `#8 --status resolved=2,checked` | `NUMBER=8`, `STATUS_ACTION=resolved`, `STATUS_ROW_IDX=2`, `STATUS_REASON=checked` |
| `--cwd=/tmp/x #8` | `NUMBER=8`, `CWD_FLAG=/tmp/x` |
| `#8 --status dismissed=3` | `STATUS_ACTION=dismissed`, `STATUS_ROW_IDX=3`, `STATUS_REASON=` (empty) |
