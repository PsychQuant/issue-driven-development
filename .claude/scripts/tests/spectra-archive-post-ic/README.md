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

Always include `--dry-run` and `--gh-repo test/repo` in args. Dry-run mode emits a
synthetic `#issuecomment-DRY-RUN` URL so expected_stdout can be deterministic. The
runner puts a stub `gh` first on `PATH` for every run, fixtures included, because the
script asks the issues API whether a candidate is an issue or a pull request; it also
points `SPECTRA_POST_IC_STATE_DIR` at a temporary directory, so the review copies a dry
run keeps never land in `$HOME`.

`post_assert.txt` supports:
- `must_not_exist <path>` — assert that path does NOT exist after run
- `must_exist <path>` — assert that path DOES exist after run

## Existing fixtures

| # | Name | Tests |
|---|------|-------|
| 01 | explicit-marker-single | Single `**GitHub-side tracker**: #N` marker |
| 02 | refs-fallback | Without a marker, prose `Refs #N` is used |
| 03 | no-marker | No candidates → exit 0 + "(none — no linked issue detected)" |
| 04 | multi-candidate | 2 explicit markers → exit 75 + candidates file |
| 05 | malicious-tasks-triple-quote | tasks.md with Python RCE payload — verifies env-var passing prevents exploit (post_assert: `/tmp/pwn-fixture-05` must not exist) |
| 06 | missing-tasks | No tasks.md → placeholder checklist |
| 07 | unsafe-change-name | `--change-name 'evil$(echo)'` → allowlist guard blocks |
| 08 | linked-issue-resolved | Re-invoke with `--linked-issue 46` validates against candidate set |
| 09 | linked-issue-invalid | Re-invoke with `--linked-issue 99` not in `[44]` → failed message |
| 10 | deterministic-outcome-path | No `--outcome-file` passed → script derives `/tmp/spectra-archive-ic-outcome-<change-name>.txt` from `--change-name` (post_assert: derived path `must_exist`). Tests the actual derivation formula, not a hand-copied literal. |
| 11 | unsafe-outcome-file | `--outcome-file` containing `..` → exit 2 + `(failed — unsafe --outcome-file path)`, rejected before any archive read (post_assert: `/tmp/pwn-fixture-11.txt` must not exist). No `archive/` subdir — the script exits before reaching it. |
| 12 | prose-issue-detect | Prose `issue #N` is a candidate |
| 13 | linked-issue-empty-candidates | `--linked-issue` with no candidates points to `--force-linked-issue` |
| 14 | word-boundary-no-substring | `reissue #5` / `tissue #9` are not candidates |
| 15 | force-linked-issue | `--force-linked-issue` bypasses detection |
| 16 | force-and-linked-mutex | Both flags → failed message |
| 17 | cross-repo-refs | `other/sandbox#3`, `other/sandbox issue #4` and `-R` forms are not candidates; `Refs #400` is |
| 18 | same-repo-full-ref | `Test/Repo#400` counts as this repository, in any case; `other/sandbox#9` does not |


## Scenario tests

`test.sh` ends with checks a fixture cannot express, because they need a real git
repository or a post that runs. They build temporary repositories and put a stub
`gh` first on `PATH`, so nothing reaches GitHub (#405):

- the path in the comment: absolute argument, subdirectory, no git repository, a
  repository whose origin is not `--gh-repo`
- the review level: missing or invalid `--scrub-attested`, the repository level as a
  floor, `enforce`, unreadable permissions
- the review copy: no dry run, a body or an issue that changed after the review, a
  planted symlink, its permissions, its removal after a post
- the egress gate: a post through the wrapper, a refusal, a missing wrapper, a failed
  post that keeps gh's message
- candidate detection: the case that opened #405 (before and after the archive commit,
  from `/tmp` and from another repository), squash subjects, pull-request and missing
  numbers, an unverifiable number, an explicit `Closes` that disagrees with the commits,
  a cluster commit, body `Refs` lines, cross-repo numbers in subjects, this repository's
  full form (explicit, as a group, as a mention), `referencing issue #N`, explicit
  references only partly covered by commits, a prose-only pull request, a transport
  error whose URL contains 404, no `--gh-repo`, non-UTF-8 bytes, and Python modules
  planted in the cwd (dry run and real post)

## CI integration

`.github/workflows/tests.yml` runs this suite as its own step, because
`run-all-tests.sh` only covers `plugins/issue-driven-dev/scripts/tests/`.

The fixtures sit inside this repository, whose origin is not `test/repo`, so they get
no commit evidence and stay independent of this repository's history.

Requires bash, git, python3, and the parser versions in
`plugins/issue-driven-dev/scripts/requirements-egress.txt` (the post path runs the
real wrapper). The `gh` CLI is not needed.
