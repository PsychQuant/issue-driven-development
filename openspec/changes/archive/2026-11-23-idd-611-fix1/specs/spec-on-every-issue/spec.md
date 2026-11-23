## MODIFIED Requirements

### Requirement: Change metadata carries no author address

`spec-change.py scrub-authors --cwd <dir>` SHALL read every `.openspec.yaml` under `<spec dir>/changes/` (the spec directory resolved as for the other subcommands, from the working tree) that is untracked or differs from HEAD, and in each SHALL rewrite a `created_by:` or `archived_by:` line whose value ends in an angle-bracketed part containing `@` (written by Spectra as `<name> <<address>>`) to the field and whatever precedes that part. Every other line, and every file without such a line, SHALL stay byte-identical, and a `.openspec.yaml` that matches HEAD SHALL not be changed. A file whose staged copy differs from HEAD SHALL be staged again after it is rewritten, so the index keeps no address. It SHALL read and check every file before it rewrites any, so that an error found while reading leaves every file unchanged, and an error while writing or staging SHALL name the files already rewritten. Only the working copy is read; a staged copy whose working copy is deleted or already has no address is not checked, and a working copy whose bytes match HEAD SHALL be left unchanged even when its staged copy differs. The files read are those `git status` reports as untracked or changed. Ignored files and symbolic links are not read, and neither is a file `git status` does not report (marked assume-unchanged, or equal to HEAD after line-ending conversion), since `git add` does not take it either. A missing `<spec dir>/changes/`, or a symbolic link there, has nothing to scan, and SHALL give `ok` with an empty `cleaned` list before `git status` is read; a file under a symbolically linked directory below it is not read. A `.openspec.yaml` with a merge conflict, a directory under `<spec dir>/changes/` that cannot be read, or a HEAD copy that cannot be read SHALL be an error, found before any file is rewritten. After staging a rewritten file again it SHALL read the staged copy back; a copy it cannot read, a copy that is not UTF-8, and an address there SHALL each be an error with its own reason. Lines are split at CR, LF and CRLF only, and a byte-order mark before the first line is kept. A rewrite SHALL replace the file with a new one, so a hard link to the old file keeps its bytes. It SHALL print one JSON line: `{"status": "ok", "cleaned": [<paths relative to the repository top, sorted>]}` with exit 0, or `{"status": "error", "reason": <why>}` with exit 2 when the repository, the spec directory or one of the files cannot be read, or a file is not UTF-8. The spec wrapper SHALL run it at step 3, after the change is created, or when step 3 goes on with an open change, and before anything is committed; at step 4, after any unpark and before `spectra-apply`, because `spectra park` moves a change out of the working tree, where step 3's run does not see it; and at step 5, after `spectra archive` and before the archive commit; it SHALL print the paths it cleaned and SHALL stop on any result other than `ok`. `idd-implement` and `idd-all`, where they restate the close-out order, SHALL list it between the archive check and the archive commit; `idd-all` SHALL run it after its own call to `spectra-propose` and before its call to `spectra-apply`; and `idd-implement`, where it restates step 4, SHALL name it after the unpark and before `spectra-apply`. The subcommand does not look at the repository's visibility.

#### Scenario: An address in new change metadata is removed

- **WHEN** scrub-authors runs on a repository whose untracked change metadata holds an address
- **THEN** the field keeps the name, the address is gone, other lines are unchanged and the report lists the file

##### Example: lines of change metadata before and after

Each row is the only line of interest in an untracked `openspec/changes/c/.openspec.yaml` that also holds `schema: spec-driven` and `created_with: claude`.

| Line before | Line after | File listed in `cleaned` |
| --- | --- | --- |
| `created_by: t <t@example.test>` | `created_by: t` | yes |
| `archived_by: t <t@example.test>` | `archived_by: t` | yes |
| `created_by: t` | `created_by: t` (file byte-identical) | no |
| `created_by: a <b> c <x@example.test>` | `created_by: a <b> c` | yes |
| `created_by: t <no-address>` | `created_by: t <no-address>` (file byte-identical) | no |
| `owner: t <t@example.test>` | `owner: t <t@example.test>` (file byte-identical) | no |
| `created_by: A` U+2028 `B <t@example.test>` | `created_by: A` U+2028 `B` | yes |
| a byte-order mark, then `created_by: t <t@example.test>` as the first line | the byte-order mark, then `created_by: t` | yes |

#### Scenario: Only metadata that differs from HEAD is read

- **WHEN** scrub-authors runs on a repository with committed, modified and untracked change metadata
- **THEN** it rewrites the untracked and modified files and leaves the unchanged committed ones, and a repository it cannot read is an error

##### Example: which files scrub-authors reads

| File | State | Result |
| --- | --- | --- |
| `openspec/changes/new-x/.openspec.yaml` with an address | untracked | rewritten, listed |
| `openspec/changes/archive/2026-01-01-old/.openspec.yaml` with an address | committed and unchanged | unchanged, not listed |
| `openspec/changes/archive/2026-01-02-y/.openspec.yaml` without an address, then an address added in the working tree | committed, modified | rewritten, listed |
| `docs/spectra/changes/z/.openspec.yaml` with an address, in a repository whose `.spectra.yaml` says `spec_dir: docs/spectra` | untracked | rewritten, listed |
| `openspec/changes/s/.openspec.yaml` with an address | staged | rewritten, listed, and its staged copy holds no address |
| `openspec/changes/a/.openspec.yaml` with an address, beside `openspec/changes/b/.openspec.yaml` that is not UTF-8 | both untracked | `{"status": "error", …}` with no `cleaned` list, exit 2, and `a` unchanged |
| `openspec/changes/a/.openspec.yaml` with an address, beside `openspec/changes/b/.openspec.yaml` that cannot be read (mode 000; skipped when the suite runs as root) | both untracked | `{"status": "error", …}` with no `cleaned` list, exit 2, and `a` unchanged |
| `openspec/changes/a/.openspec.yaml` with an address, beside a directory `openspec/changes/d/` that cannot be read (mode 000; skipped as root) | untracked | `{"status": "error", …}`, exit 2, and `a` unchanged |
| `openspec/changes/m/.openspec.yaml` committed with an address, a staged copy without it, and the working copy restored to HEAD's bytes | staged, working copy matches HEAD | unchanged, not listed, and the staged copy unchanged |
| `openspec/changes/c/.openspec.yaml` with a merge conflict between two addresses | unmerged | `{"status": "error", …}`, exit 2, and the file unchanged |
| `openspec/changes/h/.openspec.yaml` with an address, a hard link to the committed `openspec/changes/archive/2026-01-01-old/.openspec.yaml` | untracked | `h` rewritten and listed; the committed file keeps its bytes |
| `openspec/changes/..draft/.openspec.yaml` with an address (a directory whose name starts with two dots) | untracked | rewritten, listed |
| `openspec/changes/n/.openspec.yaml` committed with bytes that are not UTF-8, a staged UTF-8 copy, and the working copy restored to HEAD's bytes | staged, working copy matches HEAD | `ok`, not listed |
| `openspec/changes/f/.openspec.yaml` with an address, staged, in a repository whose clean filter for that file puts `<t@example.test>` back after `created_by: t` | staged | `{"status": "error", …}`, exit 2 |
| a repository whose spec directory has no `changes/` | — | `ok`, `cleaned` empty |
| `openspec/changes/c/.openspec.yaml` staged and marked assume-unchanged, after which `openspec/changes` becomes a symbolic link to a directory outside the repository holding `c/.openspec.yaml` with an address | staged | `ok`, `cleaned` empty, and the file outside unchanged |
| `openspec/changes/d/.openspec.yaml` staged and marked assume-unchanged, after which `openspec/changes/d` becomes a symbolic link to a directory outside holding `.openspec.yaml` with an address | staged | `ok`, and the file outside unchanged |
| `notes/.openspec.yaml` with an address | untracked, outside the spec directory | unchanged, not listed |
| `--cwd` a directory that is not a git repository | — | `{"status": "error", …}`, exit 2 |

#### Scenario: The wrapper runs it before its commits

- **WHEN** the spec wrapper is read
- **THEN** step 3 runs scrub-authors after the change is created, also on the branch that goes on with an open change, and before any commit; step 4 runs it after the unpark and before `spectra-apply`; and step 5 runs it after `spectra archive` and before the archive commit

##### Example: the wrapper's two calls

- **GIVEN** plugins/issue-driven-dev/references/spec-wrapper.md
- **WHEN** the sections "## 3. Propose", "## 4. Apply" and "## 5. Close-out" are read
- **THEN** each contains `spec-change.py" scrub-authors --cwd "$CWD"`, the row for `go on with <名稱>` in section 3 names `scrub-authors`, in section 4 that call comes after the line that runs `spectra unpark` and before the line that calls `spectra-apply`, and in section 5 it comes after the line that runs `spectra archive` and before the line that commits `chore: archive`

#### Scenario: The skills that restate the close-out order include it

- **WHEN** idd-implement and idd-all are read
- **THEN** each line that restates the close-out order lists scrub-authors between the archive and the commit, and idd-all runs it after its own propose

##### Example: the close-out order restated by idd-implement and idd-all

- **GIVEN** plugins/issue-driven-dev/skills/idd-implement/SKILL.md and plugins/issue-driven-dev/skills/idd-all/SKILL.md
- **WHEN** every line that holds both `spectra archive` and `→ commit` is read, and the section "#### Step 3b.3: Propose" of idd-all is read
- **THEN** there are three such lines, each names `scrub-authors` after `spectra archive` and before `→ commit`; the Step 3b.3 section contains `spec-change.py" scrub-authors --cwd "$CWD"`; in the Step 3b.4 section that call comes before `Skill(skill="spectra-apply"`; and the idd-implement line that holds both `spectra unpark` and `spectra-apply` names `scrub-authors` between them
