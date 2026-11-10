## Problem

Verify round 1 of #480 (2026-11-11, on `3eaa895`) found that several gates of `spec-on-every-issue` report success without the property holding, and that some paths the spec promises cannot be reached:

- `idd-close` Step 1.57 names a variable (`IC_BODY`) that no step sets; a failed comment fetch gives an empty file, which reads as a legacy comment and passes the close gate.
- In `idd-all` Phase 3b the old "spectra on PATH" check runs before the preflight, so a third-party clone without Spectra aborts instead of proceeding.
- When verify rejects a `no behaviour change` declaration, the fix rules only cover issues that already declared a change; nothing says the fix must create the issue's first change.
- `spec-change.py links` prints `ok` when a requirement heading cannot be parsed (`### Requirement Missing colon`) and when the spec directory is absent at the head revision; a marker for the Example `alpha` is satisfied by a line naming `alpha table`.
- `preflight` prints `error` (exit 2) for a directory that is not a git repository, which no requirement states.
- When the wrapper cannot read the account's permission, it passes `--can-write no` and treats the maintainer's own repository as a third-party clone.
- The Spectra tier's propose arguments do not ask for Examples and markers, and no reviewer is asked whether a `No executable check:` reason holds.

## Root Cause

The gates were specified by what they print for each input, but the inputs they are handed were assembled in prose (the comment selection in `idd-close`) or defaulted silently (permission, empty file), and the parser of requirement blocks treated anything it did not recognise as absent.

## Proposed Solution

- One way to choose the Implementation Complete comment: a `spec-change.py ic` subcommand reads the comments JSON that `gh api --paginate` returns and prints the newest one by an OWNER, MEMBER or COLLABORATOR. `idd-verify` and `idd-close` both use it, and a failed fetch stops the close gate and is reported as `unreadable` by verify.
- `links` reports `error` for a heading that names a requirement but does not parse, and when the spec directory has no tracked file at the head revision; a marker counts only when nothing but whitespace or a comment closer follows it on its line.
- `preflight`'s `error` status is written into the requirement and its Example.
- The wrapper stops when the permission cannot be read; Phase 3b runs the preflight before the CLI check and passes the Example and marker instructions to propose; a rejected exemption is fixed by creating the issue's first change.
- `idd-verify` reviewers judge `No executable check:` reasons.

## Non-Goals

- A legacy comment (no marker, no `**Spec**:` line) stays exempt: telling an old comment from one the wrapper forgot needs a cut-over rule of its own. Follow-up issue.
- Tying a declared change to the issue (an old archived change name passes `archived`): change names are not always `idd-<N>-…`. Follow-up issue.
- The LOW findings of round 1. Follow-up issue.

## Success Criteria

- Each new Example row has a test carrying its marker, and each failed on the commit before the fix.
- `spec-change.py links` over this change's range prints `ok`; `archived --ref HEAD` prints `pass` for a comment that declares both changes.
- Verify round 2 reports no HIGH and no MEDIUM in scope.

## Impact

- Affected specs: spec-on-every-issue, idd-verify
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/spec-change.py
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-change/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-close-gate/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-wrapper-contract/test.sh
  - Modified: plugins/issue-driven-dev/references/spec-wrapper.md
  - Modified: plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-verify/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
