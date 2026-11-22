## ADDED Requirements

### Requirement: idd-all reads every argument in bash and zsh

`/idd-all` Step 0.2 SHALL read every argument it is given, in any order, under both bash and zsh: the block loops over the arguments without an array index, so the last argument is read in zsh as in bash. Each flag keeps its meaning, its conflict checks and its value rules.

#### Scenario: A trailing flag is read under zsh

- **GIVEN** the Step 0.2 block run under zsh
- **WHEN** the arguments end with `--review`
- **THEN** the run records `--review`, as it does under bash

##### Example: idd-all reads the last argument in both shells

| Arguments | Under bash and under zsh |
| --- | --- |
| `#5 --review` | `REVIEW_FLAG=--review` |
| `#5 --stop=early` | `STOP_FLAG=early` |
| `#5 --stop exhaustive-all --pr` | `STOP_FLAG=exhaustive-all`, `PR_FLAG=--pr` |
| `#5 --cwd=/tmp/x` | `CWD_FLAG=/tmp/x` |
| `#5 --stop --review` | aborts: `--stop needs a value` |
