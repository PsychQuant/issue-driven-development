# What the plugin writes into a repository, and what rest mode does with it

`/idd-all` in rest mode (`skills/idd-all/SKILL.md`, `## Rest mode`) runs each issue in a directory of its own: a clone that `scripts/rest-queue.py next` makes at `<top>/.claude/worktrees/rest-<N>/`. Rest mode removes no directory: whatever an issue leaves stays in its directory, the report names the directory, and a person deletes it (requirement "The directory of an issue is left for a person", capability `idd-all-rest`). The working tree the run was started in is not used: rest mode writes there at three places only (requirement "A rest run leaves the working tree it was started in as it was").

A check in `scripts/tests/rest-queue/test.sh` fails when a skill or a script of the plugin names a location under `.claude/` that this file does not name. Adding a writer therefore means adding a row here, and deciding its class.

## Classes

| Class | What rest mode does with it |
| --- | --- |
| in the directory | Left in the directory of the issue, with everything else there; the directory is named in the report and a person deletes it |
| not in the working tree | Outside the repository, or inside the git directory: `git status` does not show it |
| read only | The plugin reads this location and does not write it |

## Locations under `.claude/` that skills and scripts name

Paths are relative to the directory the skill runs in (`--cwd`, which in rest mode is the directory of the issue) unless the row says otherwise.

| Location | Writer | Class | Notes |
| --- | --- | --- | --- |
| `.claude/.idd/attachments` | `scripts/process-attachments.sh download`, called by `idd-diagnose` (every run of an issue, also when it has no attachment) | in the directory | One folder per issue, `issue-<N>/`, with `_manifest.json`. The script writes relative to the shell's current directory, not to `--cwd` (#586); in rest mode the shell is in the directory of the issue. `rules/process-attachments.md` says the folder is committed by default, so a repository may track the manifest: a change of it does not keep the directory |
| `.claude/.idd/state` | `scripts/close-stage.py` (the run of one issue and its result), `scripts/rest-queue.py` (the rest run, where it was started; nothing in the directory of an issue), `scripts/lib/unattended-state.sh` (the unattended marker), `scripts/manifest-append.sh` (the chain's spawned issues), `scripts/idd-discuss.py` (`discussions/`), `idd-comment` (`bridge.json`) | in the directory | `rest-queue.py start` refuses to begin when git would not ignore this folder; `next` adds it to the exclude file of every directory it makes |
| `.claude/.idd/archive` | `scripts/idd-edit-helper.py` (`edits/`: earlier versions of corrected GitHub text) | in the directory | Written in the main working tree of the repository (not in a linked worktree), at its top, whatever `--cwd` is; in rest mode that is the directory of the issue, which is a repository of its own. The writer adds its own ignore rule and refuses to write without it. The files hold other people's words and are not to be read; they stay in the directory with the rest |
| `.claude/.idd/tree-lock` | `scripts/idd-tree-lock.sh`, called by `idd-implement`; also `tree-lock.reclaim/` | in the directory | The writer adds an ignore rule through `scripts/lib/runtime-ignore.sh`, anchored at the top of the repository; `next` adds `.claude/.idd/tree-lock*` to the exclude file of every directory it makes |
| `.claude/worktrees` | `scripts/idd-worktree.sh`, called by `idd-implement` when the tree lock is held by another session; `scripts/rest-queue.py next`, at the top of the working tree the run was started in (`rest-<N>/`) | in the directory | Ignored through `scripts/lib/runtime-ignore.sh`; `rest-queue.py start` makes sure git ignores it at the top of the working tree the run was started in, and `next` adds it to the exclude file of every directory it makes. A linked worktree made in the directory of an issue stays with it |
| `.claude/.idd/routing-stats.jsonl` | The `idd-route` program, called by `idd-verify` (every round) and `idd-close` | in the directory | Written at the top of the working tree the shell is in (`git rev-parse --show-toplevel`), not below `--cwd`; in rest mode that is the directory of the issue. It stays in the directory; its lines do not reach the working tree the run was started in (#584). Not written when `idd-route` is not installed |
| `.claude/.idd/issue-runs` | `idd-issue` in multi-finding mode (one `.jsonl` per run) | in the directory | Written relative to the shell's current directory |
| `.claude/.idd/local.json` | `idd-issue`, `idd-verify` and `idd-config` when no configuration exists; `idd-all` after the user confirms a CI command; `scripts/migrate-idd-config.sh` | in the directory | A user's configuration. A clone has it only when the repository tracks it; one written there stays in the directory. In a third-party clone its writer excludes it from git |
| `.claude/issue-driven-dev.local.json` | Earlier versions of the plugin; `scripts/migrate-idd-config.sh` moves it | in the directory | The legacy path of the configuration. Read as a fallback |
| `.claude/issue-driven-dev.local.md` | Earlier versions of the plugin | in the directory | A legacy configuration path. Read as a fallback |
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
| Uncommitted edits of tracked files, new files of the implementation | `idd-implement`, the spec steps | in the directory | An issue that reached its pull request has committed and pushed them |
| `openspec/changes/<change>/` (the folder name comes from the repository's Spectra configuration) | The Spectra CLI, driven by `references/spec-wrapper.md` | in the directory | No step commits a proposal by name; the archive commit carries what is left |
| `.spectra/` | The Spectra CLI | in the directory | When the repository does not ignore it |
| `<git dir>/spectra-app/changes/` (parked changes) | The Spectra CLI | in the directory | Not in the working tree, and never pushed |
| `<git dir>/info/exclude` | `scripts/lib/runtime-ignore.sh`, `scripts/idd-edit-helper.py`, `scripts/git-ignore-block.sh`; `scripts/rest-queue.py` (`next`, in each directory it makes; `start`, the rule for `.claude/worktrees/` at the top of the working tree the run was started in) | not in the working tree | |
| `<git dir>/idd-rest-mark` | `scripts/rest-queue.py next`, in each directory it makes: the mark that binds the directory to its issue, read by `here` and by the close stage | not in the working tree | With the exclude lines, the only file the helper writes into a clone (a closed list, requirement "Each issue of a rest run runs in a directory of its own") |
| `.claude/worktrees/.rest-<N>-…` at the top of the working tree the run was started in | `scripts/rest-queue.py next`: the temporary folder the clone is made in before it is moved to its place | not in the working tree | Recorded with the issue before the clone starts; when a `next` is ended before the move, or the place was taken meanwhile, the folder is left and the report names it |
| `.gitignore` at the top | `idd-issue` (the carve-out for run logs, after the user chose it) | in the directory | |
| Files that the issue's own commands write and git ignores (a build, a test run) | The issue's own commands | in the directory | |
| The branch `idd/<N>-<slug>` | `idd-all` Step 0.5, before diagnose, from `origin/<default>` | in the directory | Pushed when the issue reaches its pull request |
| A stash, a second working tree | The issue's own commands | in the directory | |
| The tags `idd-<N>-baseline` and `idd-<N>-verified` | `idd-issue`, `idd-verify` | in the directory | Only when `origin` does not have the tag with the same value; `idd-issue` pushes the baseline tag |

## What this inventory and its check cannot see

- Programs outside the plugin: the Spectra CLI, `idd-route`, and the hooks of the target repository. What they leave stays in the directory.
- A writer that builds its path from pieces, so that no skill or script holds the path as text.
- Locations outside `.claude/`. The table "Other things an issue leaves" is kept by hand.
- A writer that goes by the shell's directory, when the shell is not in the directory of the issue: it writes into the working tree the run was started in (a shell reset between two tool calls of one phase; a known limitation the maintainer accepted). The report says when that working tree changed while an issue ran, as far as what git lists changed.
