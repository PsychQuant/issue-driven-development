# spectra-archive-post-ic Tests

Unit tests for `.claude/scripts/spectra-archive-post-ic.sh`.

## Run

```bash
.claude/scripts/tests/spectra-archive-post-ic/test.sh
```

Exits 0 on all-pass; 1 if any failure.

## Add a fixture

Each fixture is a self-contained directory under `fixtures/<NN-name>/`:

```
fixtures/NN-name/
├── archive/
│   ├── proposal.md         # Spectra change proposal (optional)
│   ├── design.md           # design notes (optional)
│   └── tasks.md            # task checklist (optional)
├── args.txt                # CLI args to pass to the script
├── expected_stdout.txt     # exact stdout to compare against
├── expected_exit.txt       # exit code to compare against
└── post_assert.txt         # optional: per-line assertions after run
```

`args.txt` MAY contain `__FIXTURE_PATH__` which the runner substitutes with the
absolute path to the fixture directory.

Always include `--dry-run` and `--gh-repo test/repo` in args so the test never
calls real `gh issue comment` / `gh issue view`. Dry-run mode emits a synthetic
`#issuecomment-DRY-RUN` URL so expected_stdout can be deterministic.

`post_assert.txt` supports:
- `must_not_exist <path>` — assert that path does NOT exist after run
- `must_exist <path>` — assert that path DOES exist after run

## Existing fixtures

| # | Name | Tests |
|---|------|-------|
| 01 | explicit-marker-single | Fallback 1 with single `**GitHub-side tracker**: #N` |
| 02 | refs-fallback | Fallback 2 matches `Refs #N` pattern |
| 03 | no-marker | No candidates → exit 0 + "(none — no linked issue detected)" |
| 04 | multi-candidate | 2 explicit markers → exit 75 + candidates file |
| 05 | malicious-tasks-triple-quote | tasks.md with Python RCE payload — verifies env-var passing prevents exploit (post_assert: `/tmp/pwn-fixture-05` must not exist) |
| 06 | missing-tasks | No tasks.md → placeholder checklist |
| 07 | unsafe-change-name | `--change-name 'evil$(echo)'` → allowlist guard blocks |
| 08 | linked-issue-resolved | Re-invoke with `--linked-issue 46` validates against candidate set |
| 09 | linked-issue-invalid | Re-invoke with `--linked-issue 99` not in `[44]` → failed message |
| 10 | deterministic-outcome-path | No `--outcome-file` passed → script derives `/tmp/spectra-archive-ic-outcome-<change-name>.txt` from `--change-name` (post_assert: derived path `must_exist`). Tests the actual derivation formula, not a hand-copied literal. |
| 11 | unsafe-outcome-file | `--outcome-file` containing `..` → exit 2 + `(failed — unsafe --outcome-file path)`, rejected before any archive read (post_assert: `/tmp/pwn-fixture-11.txt` must not exist). No `archive/` subdir — the script exits before reaching it. |

| 17 | cross-repo-refs | `other/sandbox#3`, `other/sandbox issue #4` and `-R` forms are not candidates; `Refs #400` is |
| 18 | same-repo-full-ref | `Test/Repo#400` counts as this repository, in any case; `other/sandbox#9` does not |

Fixtures 12 to 16 are not listed above; their directory names say what they cover.

## Scenario tests

`test.sh` ends with checks a fixture cannot express, because they need a real git
repository or a post that runs. They build temporary repositories and put a stub
`gh` first on `PATH`, so nothing reaches GitHub (#405):

- the path in the comment: absolute argument, subdirectory, no git repository
- the egress gate: a post through the wrapper, a refusal, a missing wrapper, no write access
- candidate detection: prose and commits disagreeing, a squash subject, a cluster
  commit, a cross-repo number in a subject, and the case that opened #405

## CI integration

`.github/workflows/tests.yml` runs this suite as its own step, because
`run-all-tests.sh` only covers `plugins/issue-driven-dev/scripts/tests/`.

Requires bash, git, python3, and the parser versions in
`plugins/issue-driven-dev/scripts/requirements-egress.txt` (the post path runs the
real wrapper). The `gh` CLI is not needed.
