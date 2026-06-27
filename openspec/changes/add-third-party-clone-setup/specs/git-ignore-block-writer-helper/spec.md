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

The Stage 4.5 (#55) `.gitignore` carve-out logic SHALL be refactored to call the shared primitive, with **behavior-equivalent** output to the pre-refactor implementation. (Byte-equivalence was found infeasible — the helper uses BEGIN/END sentinels whereas the prior #55 block was a single-marker + rationale-comments format; replicating the old format would couple the generic helper to #55's specifics and defeat the extraction. The criterion is therefore identical `git check-ignore` results + a one-time migration of the old format, NOT byte-identical text — see design.md D4.)

#### Scenario: refactored carve-out is behavior-equivalent

- **WHEN** the refactored Stage 4.5 carve-out runs against a `.gitignore` that excludes `.claude/`
- **THEN** the run-log path `.claude/.idd/issue-runs/<f>.jsonl` SHALL become trackable (`git check-ignore` reports NOT ignored)
- **AND** sibling `.claude/<other>` paths SHALL remain ignored
- **AND** the bare `.claude/` line SHALL be removed
- **AND** the gate's user-facing options, summary lines, and `JSONL_GITIGNORE_DECISION` values SHALL be unchanged

#### Scenario: one-time migration of pre-#192 old-format block

- **WHEN** the refactored carve-out runs against a `.gitignore` already containing a pre-#192 OLD-format #55 block (single marker `# IDD multi-finding run log carve-out (idd-issue Stage 4.5, #55)` + rationale comments + the 5 pattern lines, no END sentinel)
- **THEN** the old block SHALL be stripped and replaced by the new BEGIN/END-sentinel block, with **no duplicate** (the new sentinel appears exactly once)
- **AND** unrelated user content adjacent to the old block SHALL be preserved

#### Scenario: third-party clone suppresses the Add-carve-out option (#193)

- **WHEN** the Stage 4.5 gate fires in a third-party clone (origin owner ≠ you AND no push permission, per Step 0.5.E detection)
- **THEN** the gate SHALL NOT offer the "Add carve-out chain to `.gitignore`" option (it would pollute a repo you don't own)
- **AND** SHALL offer only skip-commit (local-only) / abort, keeping the run log local
