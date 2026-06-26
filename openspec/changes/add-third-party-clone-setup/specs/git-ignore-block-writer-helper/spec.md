## ADDED Requirements

### Requirement: shared idempotent git ignore-block writer primitive

The plugin SHALL provide a single shared primitive that writes an idempotent, marker-delimited block of git ignore patterns to a caller-specified target file, parameterized by direction (re-include vs exclude). Both the Stage 4.5 (#55) `.gitignore` carve-out and the third-party `.git/info/exclude` writer SHALL use this primitive.

#### Scenario: idempotent re-run via marker

- **WHEN** the primitive is invoked twice with the same marker, target file, and lines
- **THEN** the second invocation SHALL NOT duplicate the block
- **AND** the resulting file SHALL contain exactly one copy of the marker-delimited block

#### Scenario: stale block upgrade-in-place

- **WHEN** the target file contains a block with the same marker but different lines (a stale earlier version)
- **THEN** the primitive SHALL replace the stale block in place (delete-then-append) without disturbing surrounding user content
- **AND** SHALL preserve any non-block lines (blank lines / user comments) adjacent to the block

#### Scenario: exclude direction targets .git/info/exclude

- **WHEN** the primitive is called with direction=exclude and target=`.git/info/exclude` and pattern `.claude/.idd/`
- **THEN** it SHALL append/update the block in `.git/info/exclude`
- **AND** the written rules SHALL cause `git check-ignore` to report `.claude/.idd/local.json` as ignored

#### Scenario: re-include direction handles parent-dir-excluded quirk

- **WHEN** the primitive is called with direction=re-include and target=`.gitignore` for a path whose parent directory is excluded
- **THEN** it SHALL emit the multi-line carve-out chain (parent re-include → re-exclude contents → re-include the target path) rather than a single `!path` line
- **AND** the re-included path SHALL become trackable (`git check-ignore` reports it as NOT ignored)

### Requirement: Stage 4.5 carve-out refactor preserves behavior

The Stage 4.5 (#55) `.gitignore` carve-out logic SHALL be refactored to call the shared primitive, with byte-equivalent output to the pre-refactor implementation.

#### Scenario: refactored carve-out is byte-equivalent

- **WHEN** the refactored Stage 4.5 carve-out runs against the existing #55 test fixtures (root `.gitignore`, `.git/info/exclude`, global `core.excludesfile`, and stacked combinations)
- **THEN** the resulting `.gitignore` content SHALL be byte-equivalent to the pre-refactor output for every fixture
- **AND** all existing #55 scenarios (add-exception / skip-commit / abort / nested-gitignore) SHALL continue to pass

#### Scenario: refactor does not change #55 observable surface

- **WHEN** Stage 4.5 dispatches the gate decision after the refactor
- **THEN** the gate's user-facing options, summary lines, and `JSONL_GITIGNORE_DECISION` values SHALL be unchanged
