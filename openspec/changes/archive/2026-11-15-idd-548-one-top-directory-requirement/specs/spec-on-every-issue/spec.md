## MODIFIED Requirements

### Requirement: spec-change.py reads the repository that holds --cwd

Every subcommand of `scripts/spec-change.py` that takes `--cwd` (`archived`, `links`, `preflight`, `archive-ref`, `link-base`) SHALL read the repository whose top level `git rev-parse --show-toplevel` reports for `--cwd`, and SHALL take that path exactly as git prints it, removing only the one line ending git appends (the name of the directory can itself end in a space or a newline). A top level whose name ends in whitespace is that directory, never a sibling directory whose name lacks the whitespace.

#### Scenario: A top level whose name ends in whitespace

- **GIVEN** two repositories side by side, `odd ` (with a trailing space) and `odd`
- **WHEN** a subcommand runs with `--cwd` inside `odd `
- **THEN** it reads `odd `

##### Example: a top level whose name ends in whitespace

| Repositories | Command | Result |
| --- | --- | --- |
| `odd ` has the change archived, the sibling `odd` does not | `archived --cwd 'odd ' --ref HEAD` | `pass` |
| `odd ` alone, with the change archived | `archived --cwd 'odd ' --ref HEAD` | `pass` |
| `odd ` has a spec added on a branch without an Example, the sibling `odd` has none | `links --base <its base> --cwd 'odd '` | `missing` |
| `pf ` has an `openspec/` directory, the sibling `pf` does not | `preflight --cwd 'pf ' --can-write yes` | `ready` |
| `pf ` alone, with an `openspec/` directory | `preflight --cwd 'pf ' --can-write yes` | `ready` |
| `nl` followed by a newline has the change archived, the sibling `nl` does not | `archived` with `--cwd` that directory, `--ref HEAD` | `pass` |
| `sp ` (its name ends in a space) holds an added requirement with its marker in a tracked test file, and has the declared change archived; `copy` is the same repository under a name that does not end in a space | `links` with `--cwd` at each | `ok` for both, with the same JSON line and exit code |
| the same two repositories | `archived` with `--cwd` at each, `--ref HEAD` | `pass` for both, with the same JSON line and exit code |
| the same two repositories | `preflight` with `--cwd` at each, `--can-write yes` | `ready` for both, with the same exit code |
| the same repository under a name that ends in a line feed, and `copy` | `links` with `--cwd` at each | `ok` for both, with the same JSON line and exit code |
| the same two repositories | `archived` with `--cwd` at each, `--ref HEAD` | `pass` for both, with the same JSON line and exit code |
| the same two repositories | `preflight` with `--cwd` at each, `--can-write yes` | the same `status` and exit code for both |

## REMOVED Requirements

### Requirement: The repository's top directory is read as git prints it

**Reason**: The requirement "spec-change.py reads the repository that holds --cwd", released in 4.1.0 while this branch was open, states the same rule for all five subcommands that take `--cwd`. Two requirements for one behaviour would have to be kept in step, and this one names only three of the five subcommands.

**Migration**: None for callers; no behaviour changes. The six rows of its Example `top directory names` become rows of the Example `a top level whose name ends in whitespace`, and the checks that carried the marker of the former carry the marker of the latter.
