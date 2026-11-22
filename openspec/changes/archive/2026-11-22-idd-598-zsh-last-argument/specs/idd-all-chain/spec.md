## ADDED Requirements

### Requirement: idd-all-chain reads every argument in bash and zsh

`/idd-all-chain` Step 0.1 SHALL read every argument it is given under both bash and zsh, and SHALL take its lowest root without a 0-based array index, so the roots, `--bfs`, `--review` and `--cwd` parse the same in both shells.

#### Scenario: The last root and the lowest root under zsh

- **GIVEN** the Step 0.1 block run under zsh
- **WHEN** the arguments are `#12 #7 --bfs`
- **THEN** both roots and `--bfs` are read, and the lowest root is 7

##### Example: idd-all-chain reads the last argument in both shells

| Arguments | Under bash and under zsh |
| --- | --- |
| `#12 #7 --bfs` | roots 7 12, `TRAVERSAL=bfs`, `LOWEST_ROOT=7` |
| `#3 --review` | roots 3, `REVIEW_FLAG=--review`, `LOWEST_ROOT=3` |
| `#3 --cwd /tmp/x #9` | roots 3 9, `CWD_FLAG=/tmp/x` |
