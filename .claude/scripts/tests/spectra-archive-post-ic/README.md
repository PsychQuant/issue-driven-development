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

## CI integration

This test suite is intended to be runnable as a pre-merge gate. Add to CI:

```yaml
- name: spectra-archive-post-ic unit tests
  run: .claude/scripts/tests/spectra-archive-post-ic/test.sh
```

Requires bash, `gh` CLI installed (only for `gh repo view` in non-dry-run paths
which tests don't exercise), and python3.
