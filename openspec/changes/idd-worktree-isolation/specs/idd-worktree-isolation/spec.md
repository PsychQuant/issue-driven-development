## ADDED Requirements

### Requirement: Worktree creation

The `idd-worktree.sh create <N>` helper SHALL create a git worktree at `.claude/worktrees/idd-<N>/` under the target repo root, checked out on a feature branch named `idd/<N>-<slug>`. The `slug` SHALL be taken from a `--slug` flag when given, otherwise derived from the issue title (lowercased, non-alphanumeric runs collapsed to `-`, trimmed, capped at 40 characters), otherwise the bare form `idd/<N>` when no title source is available. The helper SHALL print the absolute worktree path as the sole content of stdout so callers and the `--cwd` flag can consume it. The helper SHALL add `.claude/worktrees/` to the target repo's `.gitignore` idempotently (guarded by a marker comment) so the worktree directory is never reported as untracked in the main working tree.

Re-invoking `create <N>` for a worktree that already exists SHALL print the existing path and exit 0 without creating a second worktree (idempotent).

#### Scenario: Create a fresh worktree

- **WHEN** `idd-worktree.sh create 167` runs in a clean repo with no `.claude/worktrees/idd-167/`
- **THEN** a git worktree exists at `.claude/worktrees/idd-167/` on branch `idd/167-<slug>`
- **AND** `.claude/worktrees/` appears in the repo's `.gitignore`
- **AND** stdout is exactly the absolute path of the new worktree

#### Scenario: Idempotent re-create

- **GIVEN** `.claude/worktrees/idd-167/` already exists from a prior `create 167`
- **WHEN** `idd-worktree.sh create 167` runs again
- **THEN** the helper prints the existing worktree path and exits 0
- **AND** no second worktree or branch is created

#### Scenario: Branch already on a different worktree

- **GIVEN** a branch `idd/167-foo` is already checked out on a worktree at a different path
- **WHEN** `idd-worktree.sh create 167` runs
- **THEN** the helper exits 4 and names the conflicting worktree path

### Requirement: Worktree cleanup

The `idd-worktree.sh cleanup <N>` helper SHALL remove the worktree at `.claude/worktrees/idd-<N>/`. When the worktree does not exist, cleanup SHALL exit 0 as a no-op (idempotent). When the worktree has uncommitted changes and `--force` is not given, cleanup SHALL refuse, exit 5, leave the worktree intact, and surface which worktree is dirty. With `--force`, cleanup SHALL remove the worktree regardless of uncommitted changes. Cleanup SHALL leave the feature branch intact (an associated PR may still be open or merged independently).

#### Scenario: Clean worktree removed

- **GIVEN** `.claude/worktrees/idd-167/` exists with no uncommitted changes
- **WHEN** `idd-worktree.sh cleanup 167` runs
- **THEN** the worktree directory no longer exists
- **AND** the branch `idd/167-<slug>` still exists

#### Scenario: Dirty worktree refused without force

- **GIVEN** `.claude/worktrees/idd-167/` has uncommitted changes
- **WHEN** `idd-worktree.sh cleanup 167` runs without `--force`
- **THEN** the helper exits 5 and the worktree directory still exists

#### Scenario: Missing worktree is a no-op

- **WHEN** `idd-worktree.sh cleanup 999` runs and no `.claude/worktrees/idd-999/` exists
- **THEN** the helper exits 0 and makes no changes

### Requirement: Worktree listing

The `idd-worktree.sh list` helper SHALL print one line per existing IDD worktree (those under `.claude/worktrees/idd-*`), each line containing the issue number, the branch name, and the worktree path. When no IDD worktrees exist, it SHALL print nothing and exit 0.

#### Scenario: List active worktrees

- **GIVEN** worktrees exist for issues 12 and 34
- **WHEN** `idd-worktree.sh list` runs
- **THEN** stdout contains a line for issue 12 and a line for issue 34, each naming the branch and path

### Requirement: Per-issue PR convergence

Parallel IDD pipelines SHALL converge as N independent feature branches producing N pull requests — one branch and one PR per issue. The worktree-isolation convention SHALL NOT merge multiple worktree branches into a single shared cluster branch. Work that must land as a single clustered PR SHALL use the existing sequential `/idd-all-chain`, which is the designated single-cluster-PR path.

#### Scenario: Two parallel issues yield two PRs

- **GIVEN** issue 12 runs in `.claude/worktrees/idd-12/` and issue 34 runs in `.claude/worktrees/idd-34/`
- **WHEN** each pipeline reaches its PR step
- **THEN** two independent PRs are opened, one per issue, with no merge-back into a shared branch

### Requirement: idd-implement worktree-branch acceptance

`idd-implement` Phase 0.5 SHALL accept a pre-existing feature branch as the working branch when invoked with `--cwd` pointing at a worktree whose current branch matches `idd/<N>-*` for the issue number `<N>` being implemented. In that case it SHALL skip branch creation and the default-branch precondition, proceeding as if it were already on the expected feature branch. This acceptance SHALL be slug-agnostic — any slug after `idd/<N>-` qualifies.

#### Scenario: Implement on a helper-created worktree branch

- **GIVEN** a worktree on branch `idd/167-parallel-isolation` created by `idd-worktree.sh create 167`
- **WHEN** `idd-implement #167 --cwd .claude/worktrees/idd-167` runs
- **THEN** `idd-implement` accepts `idd/167-parallel-isolation` as the feature branch
- **AND** does not abort on the "must start from default branch" precondition

#### Scenario: Non-matching branch is not auto-accepted

- **GIVEN** a worktree on branch `idd/999-unrelated`
- **WHEN** `idd-implement #167 --cwd <that worktree>` runs
- **THEN** the branch is not accepted for issue 167 and Phase 0.5 follows its normal resolution

### Requirement: idd-close worktree garbage collection

After `idd-close` closes issue `#N`, it SHALL attempt to remove the worktree at `.claude/worktrees/idd-<N>/` by invoking `idd-worktree.sh cleanup <N>`. The garbage collection SHALL be best-effort: if the helper is absent or cleanup refuses (dirty worktree), `idd-close` SHALL surface a one-line warning and still complete the close. Worktree GC SHALL NOT block or fail the close.

#### Scenario: Worktree removed on close

- **GIVEN** issue 167 has a clean worktree at `.claude/worktrees/idd-167/`
- **WHEN** `idd-close #167` completes the close
- **THEN** `.claude/worktrees/idd-167/` no longer exists

#### Scenario: Dirty worktree does not block close

- **GIVEN** issue 167 has a worktree with uncommitted changes
- **WHEN** `idd-close #167` runs
- **THEN** the issue is closed
- **AND** a one-line warning notes the worktree was left in place for manual cleanup

### Requirement: Staging isolation guarantee

Each IDD worktree SHALL provide an independent `.claude/.idd/` staging directory by virtue of having its own working directory, such that concurrent IDD pipelines in separate worktrees do not share attachment staging, run-log paths, or any other repo-relative `.claude/.idd/` artifact. The convention SHALL NOT introduce a new file-locking layer; isolation relies on per-worktree working directories plus issue-scoped artifact naming.

#### Scenario: Concurrent staging does not collide

- **GIVEN** issue 12 and issue 34 run concurrently in separate worktrees
- **WHEN** each pipeline writes to `.claude/.idd/`
- **THEN** each writes under its own worktree directory and neither overwrites the other's staging artifacts
