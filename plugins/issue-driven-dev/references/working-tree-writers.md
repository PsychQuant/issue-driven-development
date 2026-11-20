# What the plugin writes into a repository, and what rest mode does with it

`/idd-all` in rest mode (`skills/idd-all/SKILL.md`, `## Rest mode`) runs each issue in a directory of its own: a clone that `scripts/rest-queue.py next` makes at `<top>/.claude/worktrees/rest-<N>/`. After the issue, `rest-queue.py record` removes that directory only when nothing exists only there, and keeps it otherwise. The lists in the requirement "The directory of an issue is removed only when nothing exists only there" (capability `idd-all-rest`) come from this inventory. The working tree the run was started in is not used: rest mode writes there at four places only (requirement "A rest run leaves the working tree it was started in as it was").

A check in `scripts/tests/rest-queue/test.sh` fails when a skill or a script of the plugin names a location under `.claude/` that this file does not name. Adding a writer therefore means adding a row here, and deciding its class.

## Classes

| Class | What `record` does with such a path in the directory of an issue |
| --- | --- |
| written again | Does not keep the directory, whether it is untracked or a change of a tracked file: the plugin writes it again on the next run of the issue. Closed list of three: `.claude/.idd/attachments/`, `.claude/.idd/state/`, paths that begin with `.claude/.idd/tree-lock` |
| only there | Keeps the directory, whatever git says about it: the record exists nowhere else |
| carried over | Appended to the file of the same path at the top of the working tree the run was started in, in one write and not twice; then it does not keep the directory. When that cannot be done, the directory is kept |
| keeps the directory | Any other change git lists, any untracked file git does not ignore, a stash, a commit no branch on `origin` holds, a tag that `origin` does not have with the same value, a second working tree |
| removed with the directory | A file git ignores in the directory that is not `only there`: the directory was made by the run, so it holds no file of a person from before the run |
| not in the working tree | Outside the repository, or inside the git directory: `git status` does not show it |
| read only | The plugin reads this location and does not write it |

## Locations under `.claude/` that skills and scripts name

Paths are relative to the directory the skill runs in (`--cwd`, which in rest mode is the directory of the issue) unless the row says otherwise.

| Location | Writer | Class | Notes |
| --- | --- | --- | --- |
| `.claude/.idd/attachments` | `scripts/process-attachments.sh download`, called by `idd-diagnose` (every run of an issue, also when it has no attachment) | written again | One folder per issue, `issue-<N>/`, with `_manifest.json`. The script writes relative to the shell's current directory, not to `--cwd` (#586); in rest mode the shell is in the directory of the issue. `rules/process-attachments.md` says the folder is committed by default, so a repository may track the manifest: a change of it does not keep the directory |
| `.claude/.idd/state` | `scripts/close-stage.py` (the run of one issue and its result), `scripts/rest-queue.py` (the rest run, and in the directory of an issue the pointer file to it), `scripts/lib/unattended-state.sh` (the unattended marker), `scripts/manifest-append.sh` (the chain's spawned issues), `scripts/idd-discuss.py` (`discussions/`), `idd-comment` (`bridge.json`) | written again | `rest-queue.py start` refuses to begin when git would not ignore this folder; `next` adds it to the exclude file of every directory it makes |
| `.claude/.idd/archive` | `scripts/idd-edit-helper.py` (`edits/`: earlier versions of corrected GitHub text) | only there | Written in the main working tree of the repository (not in a linked worktree), at its top, whatever `--cwd` is; in rest mode that is the directory of the issue, which is a repository of its own. The writer adds its own ignore rule and refuses to write without it. The files hold other people's words and are not to be read: a directory that holds one is kept, and `record` names the folder, not the files |
| `.claude/.idd/tree-lock` | `scripts/idd-tree-lock.sh`, called by `idd-implement`; also `tree-lock.reclaim/` | written again | The writer adds an ignore rule through `scripts/lib/runtime-ignore.sh`, anchored at the top of the repository; `next` adds `.claude/.idd/tree-lock*` to the exclude file of every directory it makes |
| `.claude/worktrees` | `scripts/idd-worktree.sh`, called by `idd-implement` when the tree lock is held by another session; `scripts/rest-queue.py next`, at the top of the working tree the run was started in (`rest-<N>/`) | keeps the directory | Ignored through `scripts/lib/runtime-ignore.sh`; `rest-queue.py start` makes sure git ignores it at the top of the working tree the run was started in, and `next` adds it to the exclude file of every directory it makes. A linked worktree made in the directory of an issue is a second working tree and keeps the directory |
| `.claude/.idd/routing-stats.jsonl` | The `idd-route` program, called by `idd-verify` (every round) and `idd-close` | carried over | Written at the top of the working tree the shell is in (`git rev-parse --show-toplevel`), not below `--cwd`; in rest mode that is the directory of the issue. Carried over only when it is untracked there; a repository that tracks it keeps the directory on its change. Not written when `idd-route` is not installed |
| `.claude/.idd/issue-runs` | `idd-issue` in multi-finding mode (one `.jsonl` per run) | keeps the directory | Written relative to the shell's current directory |
| `.claude/.idd/local.json` | `idd-issue`, `idd-verify` and `idd-config` when no configuration exists; `idd-all` after the user confirms a CI command; `scripts/migrate-idd-config.sh` | keeps the directory | A user's configuration. A clone has it only when the repository tracks it; one written there keeps the directory. In a third-party clone its writer excludes it from git |
| `.claude/issue-driven-dev.local.json` | Earlier versions of the plugin; `scripts/migrate-idd-config.sh` moves it | keeps the directory | The legacy path of the configuration. Read as a fallback |
| `.claude/issue-driven-dev.local.md` | Earlier versions of the plugin | keeps the directory | A legacy configuration path. Read as a fallback |
| `.claude/local` | — | read only | Named only in a comment of `scripts/migrate-idd-config.sh` about a path it must not follow |
| `.claude/state` | — | read only | `.claude/state/idd-bridge.json`, the legacy place of the bridge bookmark; `idd-comment` reads it as a fallback |
| `.claude/rules` | — | read only | Rules of the target repository, read by `idd-diagnose` and `idd-issue` |
| `.claude/.idd/issue-pending` | — | not in the working tree | Named in `idd-issue` as a place that was considered and rejected; pasted images go to the system's temporary folder |
| `.claude/.idd/global.json` | `scripts/idd-repo-map.sh` | not in the working tree | In the user's home folder (`~/.claude/.idd/global.json`) |
| `.claude/issue-driven-dev.global.json` | — | not in the working tree | In the user's home folder; named in `idd-config` as a configuration that is not used |
| `.claude/image-cache` | Claude Code | not in the working tree | In the user's home folder; `idd-issue` copies pasted images out of it |
| `.claude/plugins` | Claude Code | not in the working tree | In the user's home folder; scripts look there for other plugins |

## Other things an issue leaves

| What | Writer | Class | Notes |
| --- | --- | --- | --- |
| Uncommitted edits of tracked files, new files of the implementation | `idd-implement`, the spec steps | keeps the directory | An issue that reached its pull request has committed and pushed them |
| `openspec/changes/<change>/` (the folder name comes from the repository's Spectra configuration) | The Spectra CLI, driven by `references/spec-wrapper.md` | keeps the directory | No step commits a proposal by name; the archive commit carries what is left |
| `.spectra/` | The Spectra CLI | keeps the directory | When the repository does not ignore it |
| `<git dir>/spectra-app/changes/` (parked changes) | The Spectra CLI | only there | Not in the working tree, and never pushed |
| `<git dir>/info/exclude` | `scripts/lib/runtime-ignore.sh`, `scripts/idd-edit-helper.py`, `scripts/git-ignore-block.sh`; `scripts/rest-queue.py` (`next`, in each directory it makes; `start`, the rule for `.claude/worktrees/` at the top of the working tree the run was started in) | not in the working tree | |
| `.gitignore` at the top | `idd-issue` (the carve-out for run logs, after the user chose it) | keeps the directory | |
| Files that the issue's own commands write and git ignores (a build, a test run) | The issue's own commands | removed with the directory | |
| The branch `idd/<N>-<slug>` | `idd-all` Step 0.5, before diagnose, from `origin/<default>` | keeps the directory | Only when it holds a commit that no branch on `origin` holds |
| A stash, a second working tree | The issue's own commands | keeps the directory | |
| The tags `idd-<N>-baseline` and `idd-<N>-verified` | `idd-issue`, `idd-verify` | keeps the directory | Only when `origin` does not have the tag with the same value; `idd-issue` pushes the baseline tag |

## What this inventory and its check cannot see

- Programs outside the plugin: the Spectra CLI, `idd-route`, and the hooks of the target repository. What they leave that git does not ignore keeps the directory.
- A writer that builds its path from pieces, so that no skill or script holds the path as text.
- Locations outside `.claude/`. The table "Other things an issue leaves" is kept by hand.
- A writer that goes by the shell's directory, when the shell is not in the directory of the issue: it writes into the working tree the run was started in. The report says when that working tree changed while an issue ran.
