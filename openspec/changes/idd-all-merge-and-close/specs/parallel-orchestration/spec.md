## MODIFIED Requirements

### Requirement: idd-all multi-issue batch mode (conflict-class-ordered, sequential)

`idd-all` SHALL accept two or more distinct issue references and process them as a conflict-class-ordered **sequential** backlog drain. It SHALL read each issue's `### Conflict Class` (defaulting absent/unparseable to `D_diagnose_first`, surfaced), order the sequence by the discipline (`E_verified_close` and re-bucketed `D_diagnose_first` items first, `B_resource_serialize`/`C_shared_module_coord` issues touching the same named resource adjacent, same-file issues grouped, `A_parallel_safe` order unconstrained), and run each issue through the normal `idd-all` pipeline one at a time. Acquiring an `idd-worktree.sh` worktree for `A_parallel_safe` issues is optional, so the resulting branches can be parallelized manually later. Each issue SHALL end where a single-issue run of the same type ends: a non-meeting issue whose verify gate reports `clean` is merged and closed per the `idd-pr-hitl-modes` requirement "Clean verify leads to merge and close"; a non-meeting issue that stops at a guardrail stays at verified; a `type=meeting` issue stops at diagnosed or planning, runs no verify, and opens no PR. After an issue is merged, `idd-all` SHALL update the local default branch with `git pull --ff-only` before starting the next issue, and SHALL stop the batch and report if that update fails.

#### Scenario: a mixed backlog is drained in conflict-class order

- **WHEN** `/idd-all` is invoked on five issues classified `A_parallel_safe`(parser.rs), `A_parallel_safe`(formatter.rs), `A_parallel_safe`(parser.rs, same file as the first), `B_resource_serialize`(DB migration), and `E_verified_close`
- **THEN** the two `parser.rs` issues are grouped, the `E` issue is ordered early, and all five are processed sequentially through the normal `idd-all` pipeline, each one merged and closed when its verify gate reports `clean`

#### Scenario: a meeting issue in the batch

- **WHEN** `/idd-all` is invoked on a backlog that contains one `type=meeting` issue
- **THEN** that issue stops at diagnosed or planning with no verify and no PR, and the other issues continue through their own pipelines

#### Scenario: the default branch cannot be fast-forwarded between issues

- **WHEN** the first issue of a batch is merged and `git pull --ff-only` on the default branch then fails
- **THEN** `idd-all` stops the batch before starting the second issue and the report names the failed update
