## ADDED Requirements

### Requirement: Conflict-class taxonomy

The system SHALL define a five-class taxonomy that classifies an issue by the physical resources its implementation touches, so that a backlog drain can decide which issues are safe to parallelize and which must serialize. The classes SHALL be:

| Class | Meaning | If parallelized |
|-------|---------|-----------------|
| `A_parallel_safe` | independent file edits, no shared mutable resource | safe to run concurrently (one worktree each) |
| `B_resource_serialize` | touches a single-writer resource (DB lock, serial cloud upload, one external queue) | MUST serialize per named resource |
| `C_shared_module_coord` | edits a shared submodule or vendored dependency consumed by others | serialize and cross-verify consumers |
| `D_diagnose_first` | scope unclear; MUST be read before it can be bucketed | read-only diagnose first, then re-bucket |
| `E_verified_close` | already done; needs verification and close only | cheap; anytime |

The taxonomy SHALL be recorded in a single reference document (`plugins/issue-driven-dev/references/parallel-orchestration.md`) cited by both the diagnose-side emitter and the `idd-all` batch-mode consumer. Two issues that edit the same source file SHALL be treated as a single serialized group rather than as independent `A_parallel_safe` issues. Serialization for `B_resource_serialize` and `C_shared_module_coord` SHALL be per named resource: two issues touching different resources of the same class do not contend.

#### Scenario: same-file issues are not parallel-safe

- **WHEN** two issues in a backlog both modify the same source file
- **THEN** they are treated as one serialized group, not as independent `A_parallel_safe` issues

##### Example: classifying a mixed backlog

- **GIVEN** issue X edits `parser.rs`, issue Y edits `formatter.rs`, issue Z edits `parser.rs`, issue W runs a database migration, and issue V has unclear scope
- **WHEN** each issue is classified
- **THEN** X and Z are one serialized group (same file), Y is `A_parallel_safe`, W is `B_resource_serialize`, and V is `D_diagnose_first`

---
### Requirement: Conflict-class Diagnosis field contract

`idd-diagnose` SHALL emit a `### Conflict Class` section in its Diagnosis Report whose value is exactly one of the five taxonomy keys, accompanied by a one-line justification that names the shared resource when the class is `B_resource_serialize` or `C_shared_module_coord`. A consumer that parses a Diagnosis whose `### Conflict Class` field is absent or unparseable SHALL default the issue to `D_diagnose_first` and SHALL surface that fallback rather than failing silently or defaulting to any parallel class. The `### Conflict Class` field and the `### Complexity` field are orthogonal; a consumer SHALL NOT infer one from the other.

#### Scenario: diagnosis emits a parseable conflict class

- **WHEN** `idd-diagnose` completes RCA on an issue whose implementation edits only independent files
- **THEN** the Diagnosis Report contains `### Conflict Class` with value `A_parallel_safe` and a one-line justification

#### Scenario: missing conflict class defaults conservatively

- **WHEN** a consumer parses a Diagnosis that has no `### Conflict Class` section
- **THEN** the issue is treated as `D_diagnose_first` and the fallback is surfaced in the consumer output

---
### Requirement: Opt-in parallel-diagnose fan-out

`idd-diagnose` SHALL support an opt-in path that, for an issue whose root cause spans N independent subsystems or hypotheses, fans out one read-only investigator per subsystem in parallel (via the Workflow tool) and then runs a synthesis agent that merges their findings into a single Diagnosis Report. This path SHALL remain opt-in; the single-agent diagnose path SHALL stay the default for simple issues. The synthesis output SHALL cite concrete file references drawn from at least two independent investigator legs.

#### Scenario: multi-subsystem RCA fans out and synthesizes

- **WHEN** the parallel-diagnose fan-out is opted into for an issue whose root cause spans three independent subsystems
- **THEN** three read-only investigators run in parallel and a synthesis agent produces one Diagnosis Report citing file references from at least two of the legs

##### Example: a three-subsystem root cause

- **GIVEN** an issue whose root cause spans a code-generator contract, a build-cache selective-skip footgun, and a sister-occurrence sweep
- **WHEN** the parallel-diagnose fan-out is opted into
- **THEN** investigator-1 traces the generator, investigator-2 traces the cache footgun, investigator-3 scans for sister generators, and the synthesis agent merges them into one Diagnosis citing exact file references from at least investigator-1 and investigator-2

---
### Requirement: idd-all multi-issue batch mode (conflict-class-ordered, sequential)

`idd-all` SHALL accept two or more distinct issue references and process them as a conflict-class-ordered **sequential** backlog drain. It SHALL read each issue's `### Conflict Class` (defaulting absent/unparseable to `D_diagnose_first`, surfaced), order the sequence by the discipline (`E_verified_close` and re-bucketed `D_diagnose_first` items first, `B_resource_serialize`/`C_shared_module_coord` issues touching the same named resource adjacent, same-file issues grouped, `A_parallel_safe` order unconstrained), and run each issue through the normal `idd-all` pipeline one at a time. It MAY acquire an `idd-worktree.sh` worktree for `A_parallel_safe` issues so the resulting branches can be parallelized manually later. It SHALL stop at verified and SHALL NOT auto-close or auto-merge.

#### Scenario: a mixed backlog is drained in conflict-class order

- **WHEN** `/idd-all` is invoked on five issues classified `A_parallel_safe`(parser.rs), `A_parallel_safe`(formatter.rs), `A_parallel_safe`(parser.rs, same file as the first), `B_resource_serialize`(DB migration), and `E_verified_close`
- **THEN** the two `parser.rs` issues are grouped, the `E` issue is ordered early, and all five are processed sequentially through the normal `idd-all` pipeline, stopping at verified without auto-close

---
### Requirement: Concurrent stateful execution is deferred

The discipline SHALL NOT claim that any skill auto-parallelizes stateful implement or verify lanes, because no concurrent-lane primitive exists: within-window agent teams is a deferred case in `worktree-isolation.md` and `TeamCreate` was abandoned by `idd-verify`. The `idd-all` batch mode SHALL be sequential. Only the read-only parallel-diagnose fan-out (Workflow tool) SHALL be described as concurrent today. The conflict-class taxonomy SHALL be documented as a forward-looking safety contract for manual parallelization or a future primitive, not as a live auto-concurrency engine.

#### Scenario: the discipline does not freeze a non-existent concurrency engine

- **WHEN** the reference doc or any consuming skill describes draining a backlog of stateful issues
- **THEN** it describes sequential execution (or manual parallelization guided by the taxonomy), and does NOT specify a requirement mandating a within-window concurrent-stateful-lane mechanism
