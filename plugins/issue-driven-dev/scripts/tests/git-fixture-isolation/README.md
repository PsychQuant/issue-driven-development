# Git fixture isolation (#452)

Suites that create Git repositories must bootstrap the test-only helper before
their first Git command. Standalone invocation is protected as well as invocation
through `run-all-tests.sh`. The assertion library and aggregate runner do not
silently change Git configuration for suites that inspect the source checkout.

```bash
. "$HERE/../../lib/git-fixture-helpers.sh"
git_fixture_setup
REPO=$(git_fixture_mktemp) || exit 1
git_fixture_init "$REPO" -b main
git -C "$REPO" add . || exit 1
git -C "$REPO" commit --allow-empty -qm fixture || exit 1
```

`git_fixture_setup` owns a private root and its EXIT cleanup. Compose additional
cleanup as `trap 'cleanup; git_fixture_cleanup' EXIT`. All Git fixture directories
must be inside that root. `git_fixture_init` accepts existing subdirectories and
`--bare`; it refuses empty/outside paths, symlink escapes, existing repositories,
and failed init/config operations. Empty templates still get an `info/` directory
for tests of `info/exclude`.

Every allocation in command substitution **and every wrapper around it** must
use `|| exit 1`: an `exit` in a substitution cannot stop its parent shell, and
these suites deliberately do not use `set -e`. Split `export TMPDIR=$(...)` into
a checked assignment and `export TMPDIR`; `export` hides the allocation status.
Optional mktemp templates support non-repository scratch paths such as the
existing `/var/tmp` cases.

## Isolation boundary

| Input | Treatment |
| --- | --- |
| Repository-local environment, config parameters/count/key/value, object/index paths, identity, namespace, trace output and future `GIT_*` variables | Clear names without reading values before any Git invocation. Malformed inherited config can make even `git rev-parse --local-env-vars` fail. |
| Global/system config | One private global file and disabled system config. Never read, overwrite or display the original files. |
| Hooks, fsmonitor, commit/tag signing | Private defaults and repository-local defaults for child shells that reset their environment. Explicit settings authored by a test remain possible. |
| Default XDG ignore and attributes | Both `core.excludesFile` and `core.attributesFile` point to `/dev/null`; system attributes are disabled. Clearing global config alone is insufficient. |
| Init/clone/submodule templates | Empty `--template=` for helper init and an empty private `GIT_TEMPLATE_DIR` for descendant commands. |
| TMPDIR inside the caller's worktree | Canonical discovery ceiling prevents plain fixtures from discovering the caller. Roots containing `:` fail closed because Git cannot represent them as one ceiling entry. |
| Allocation/init failure | Abort before later operations; no fallback to the current directory or empty pathname. |
| Parent shell | Process-local changes only. Execute suites with `bash`; do not source them into an interactive shell. |

This harness assumes a trusted Git executable, PATH, and shell startup files.
It does not contain tests that deliberately override their isolation settings.
No network service is needed by its regression tests.

## Inventory and existing work

Main reviewed: `da47674a8bd25cdbb0d8fec5872a0ac0792cea56` (2026-10-30).

| Suite | Repository shape |
| --- | --- |
| actionability-gate | Branch/unwind fixtures |
| authoritative-source-producer | Repository and linked worktree |
| check-existing-work | Bare origin, clone, branches and local pushes |
| correct-flow | Correction repositories and `/var/tmp` scratch |
| correction-archive | Repositories, nested repositories, non-Git and symlink fixtures |
| doc-sync-sweep | Tracked document enumeration |
| edit-run | Edit repository and fresh child shells |
| git-ignore-block | Per-case ignore repositories |
| idd-worktree | Per-case repositories and linked worktrees |
| in-place-correction | Correction archive repository |
| merge-completeness | Commit/squash/history fixtures |
| stage45-carveout-migration | Per-case ignore repositories |
| submodule-routing | Parent, source repository and submodule clone |

[Issue #335](https://github.com/PsychQuant/issue-driven-development/issues/335)
and [PR #453](https://github.com/PsychQuant/issue-driven-development/pull/453)
were checked. PR #453 was open at review time; its
`plan-routing-consistency/test.sh` change is not overwritten here. That change
intentionally honors personal ignores when scanning the actual source checkout.
Do not apply suite-wide private config to that scan. When integrating #453,
use `git_fixture_clear_environment` at entry and put the throwaway repository
(including its scan assertions) in a subshell using `git_fixture_setup`. Keep
the source-checkout scan outside that subshell. The inventory guard flags this
newly introduced Git fixture until that integration is done.

## Validation

Install the same Python dependencies as CI, then run:

```bash
python3 -m pip install PyYAML==6.0.2 -r plugins/issue-driven-dev/scripts/requirements-egress.txt
bash plugins/issue-driven-dev/scripts/tests/git-fixture-isolation/test.sh
bash plugins/issue-driven-dev/scripts/run-all-tests.sh
```

The harness independently creates disposable callers and synthetic HOME/XDG
settings before injecting hostile state. It captures subprocess output and
compares file bytes, modes and symlink targets, without printing config values.
Cases cover direct invocation, actual linked-worktree aliases/hooks/rebase-exec,
config channels, ignore/attributes/templates, malformed environment, unsafe init
targets, allocation/init failures, cleanup, and all discovered fixture suites
under hostile state. Hooks have a recursion guard; timeout kills process groups.

The drift guard discovers helper consumers and `git init`/`clone` callers, then
runs every discovered suite with failed allocations, failed init and a hostile
disposable caller. New fixture suites must join the helper contract. The existing
aggregate runner automatically discovers this regression suite.

Initial red tests on main confirmed that inherited repository variables and a
linked-worktree alias changed the disposable caller. Additional red tests
confirmed nested-TMPDIR discovery and XDG-attributes failures before their fixes.
The helper uses Bash 3.2-compatible syntax; actual Bash 3.2/macOS execution needs
a host with those environments.
